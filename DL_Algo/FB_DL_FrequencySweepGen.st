(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FrequencySweepGen
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / ABS），零厂商私有库
 * 功能描述 (Function)   : 频率往返扫描发生器：从 fStartHz 按升斜率 fRampUpHzS
 *                         扫至 fEndHz，边界驻留 tDwell 后按降斜率 fRampDnHzS
 *                         扫回，循环往复。四态顺控：
 *                           eRampUp → eDwellHi → eRampDn → eDwellLo → eRampUp
 *                         输出 fFreqOutHz 当前频率与 bUpward 方向标志。与定频
 *                         （FB_DL_PulseGenerator 频率域）、波形发生、测频
 *                         （FB_DL_FrequencyMeasure）职责三分离（分工声明）。
 * 接口     (Interface)  : 输入 fStartHz 扫描下限（域 > 0）、fEndHz 扫描上限
 *                         （域 > fStartHz）、fRampUpHzS 升斜率（域 > 0）
 *                         [Hz/s]、fRampDnHzS 降斜率（域 > 0） [Hz/s]、tDwell
 *                         边界驻留（域 > T#0S）、bEnable 使能、bReset 复位；
 *                         输出 fFreqOutHz 当前频率 [Hz]、bUpward 升向标志、
 *                         ePhase 四态相位出口、eErrCode 错误码、bError 故障
 *                         标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出频率给定值，不产生波形、
 *                         不测频、不做定频脉宽**（三分离，分工声明）。
 *                         ② 四态 CASE + ELSE 兜底（R6）；两驻留 TON 与两沿
 *                         实例段 0 无条件调用（R7）；驻留 TON IN 挂相驻留本身
 *                         （R145：不准叠加业务条件补集）。
 *                         ③ 斜率步长 = 斜率 × fCy，单步上限自钳：步长 > 全程
 *                         带宽时按带宽单步直达边界（防步长过冲来回抖动）。
 *                         ④ 组态闸：fStartHz <= 0、fEndHz <= fStartHz、任一
 *                         斜率 <= 0、tDwell <= T#0S → 锁存故障，输出安全侧
 *                         fStartHz 且方向 FALSE，解除沿 = bReset 上升沿
 *                         （R45 配对）。
 *                         ⑤ 非有限判据（R79 双判）：组态量非有限并入组态闸
 *                         （扫频给定源头件，非有限组态不得下放）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_FrequencyGenerator` 分工：定频发生归那件、
 *                         往返扫描归本件；与 `FB_DL_FrequencyMeasure` 分工：
 *                         测频归那件；波形合成（正弦/三角）归信号链其他件，
 *                         本件只给频率标量。
 * 来源标签 (Source Tag) : 自研线（往返斜坡扫描为公开测试激励模式 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 频率 +
 *                         BOOL 方向 + ENUM 相位/错误码；数字码位待主控收口
 *                         阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 步长过冲自钳 + 组态锁存 + 非有限入闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 CASE 含 ELSE ｜ R7 ✓ 两 TON 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 3 · 序号 13）
 * 验收向量 (Acceptance) : ① fStart=10, fEnd=20, 斜率 100 Hz/s，fCycle=0.01
 *                         → 单步 +1.0 Hz：10 → 11 → … → 20 共 10 拍达上限
 *                         入 eDwellHi，bUpward=TRUE；② tDwell=T#500MS →
 *                         50 拍驻留后转 eRampDn，bUpward=FALSE；③ 斜率
 *                         2000 Hz/s（步长 20 > 带宽 10）→ 单拍直达 20.0
 *                         （过冲自钳，头注释③）；④ fEndHz <= fStartHz →
 *                         锁存 eCfgBad。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FsgPhase（扫描相位，全库唯一属主本文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FsgPhase :
(
    eIdle    := 0,   // 待机（未使能） / Idle
    eRampUp  := 10,  // 升斜坡相 / Up-ramp phase
    eDwellHi := 20,  // 上限驻留相 / Dwell at ceiling phase
    eRampDn  := 30,  // 降斜坡相 / Down-ramp phase
    eDwellLo := 40,  // 下限驻留相 / Dwell at floor phase
    eFault   := 90   // 故障（等复位） / Fault, awaiting reset
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FsgErr（错误码；故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FsgErr :
(
    eOk       := 0,   // 正常 / Normal
    eCfgBad   := 1,   // 故障级：组态非法（域/斜率/驻留/非有限） / Fault: illegal configuration
    ePhaseBad := 2    // 故障级：非法相位兜底 / Fault: illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_FrequencySweepGen
VAR_INPUT
    fStartHz   : LREAL := 10.0;       // 扫描下限，域 > 0 [Hz] / Sweep floor frequency
    fEndHz     : LREAL := 20.0;       // 扫描上限，域 > fStartHz [Hz] / Sweep ceiling frequency
    fRampUpHzS : LREAL := 100.0;      // 升斜率，域 > 0 [Hz/s] / Upward slope
    fRampDnHzS : LREAL := 100.0;      // 降斜率，域 > 0 [Hz/s] / Downward slope
    tDwell     : TIME := T#500MS;     // 边界驻留时长，域 > T#0S [ms] / Boundary dwell duration
    fCycle     : LREAL := 0.0;        // 扫描周期（<=0 用缺省） [s] / Scan cycle, default used when <= 0
    bEnable    : BOOL := FALSE;       // 使能（FALSE 回待机并归 fStartHz） [-] / Enable
    bReset     : BOOL := FALSE;       // 复位，上升沿清组态锁存并回待机 [-] / Reset, rising edge clears latch
END_VAR
VAR_OUTPUT
    fFreqOutHz : LREAL;               // 当前频率给定输出 [Hz] / Present frequency output
    bUpward    : BOOL;                // 升向标志（TRUE=升斜坡/上限驻留） [-] / Upward direction flag
    ePhase     : E_DL_FsgPhase;       // 四态相位出口 [-] / Phase outlet
    eErrCode   : E_DL_FsgErr;         // 错误码出口 / Error code outlet
    bError     : BOOL;                // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _eState   : E_DL_FsgPhase := E_DL_FsgPhase.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _fFreq    : LREAL := 0.0;         // 频率内部锁存（斜坡源） [Hz] / Frequency internal latch
    _fCy      : LREAL;                // 当拍有效周期 [s] / Effective cycle this scan
    _fStepUp  : LREAL;                // 升向单步上限（过冲自钳后） [Hz] / Upward step ceiling
    _fStepDn  : LREAL;                // 降向单步上限 [Hz] / Downward step ceiling
    _fBand    : LREAL;                // 全程带宽 = fEndHz − fStartHz [Hz] / Full band width
    _bNonFin  : BOOL;                 // 组态非有限当拍量 [-] / Non-finite configuration
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    _eCause   : E_DL_FsgErr := E_DL_FsgErr.eOk;   // 故障成因锁存（归因唯一，R190） / Latched fault cause
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
    tonDwellHi: TON;                  // 上限驻留 TON，段 0 无条件调用（IN 挂相驻留，R145） / Ceiling dwell TON
    tonDwellLo: TON;                  // 下限驻留 TON，段 0 无条件调用 / Floor dwell TON
END_VAR
VAR CONSTANT
    DL_FSG_CYDEF : LREAL := 0.01;     // 缺省扫描周期 [s] / Default scan cycle
    DL_FSG_ZERO  : LREAL := 0.0;      // 判零基准 [Hz] / Zero base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 两 TON 一沿无条件刷新 —— *)
_bNonFin := (fStartHz <> fStartHz) OR ((fStartHz - fStartHz) <> DL_FSG_ZERO)
         OR (fEndHz <> fEndHz) OR ((fEndHz - fEndHz) <> DL_FSG_ZERO)
         OR (fRampUpHzS <> fRampUpHzS) OR ((fRampUpHzS - fRampUpHzS) <> DL_FSG_ZERO)
         OR (fRampDnHzS <> fRampDnHzS) OR ((fRampDnHzS - fRampDnHzS) <> DL_FSG_ZERO);   // 组态非有限（R79 双判） / Non-finite configuration
_bCfgBad := _bNonFin OR (fStartHz <= DL_FSG_ZERO) OR (fEndHz <= fStartHz)
         OR (fRampUpHzS <= DL_FSG_ZERO) OR (fRampDnHzS <= DL_FSG_ZERO)
         OR (tDwell <= T#0S);        // 组态域闸 / Configuration gate
IF fCycle > DL_FSG_ZERO THEN
    _fCy := fCycle;                  // 组态周期有效 / Configured cycle valid
ELSE
    _fCy := DL_FSG_CYDEF;            // 周期缺省兜底 / Default cycle fallback
END_IF
_fBand := fEndHz - fStartHz;         // 带宽（组态闸后恒正） / Band width
_fStepUp := MIN(fRampUpHzS * _fCy, _fBand);   // 升步长过冲自钳（头注释③） / Up step clamped to band
_fStepDn := MIN(fRampDnHzS * _fCy, _fBand);   // 降步长过冲自钳 / Down step clamped
rtReset(CLK := bReset);              // 复位沿，每拍必调 / Reset edge, every scan
tonDwellHi(IN := (_eState = E_DL_FsgPhase.eDwellHi), PT := tDwell);   // 上限驻留计时（相驻留使能，出相自复位） / Ceiling dwell timer
tonDwellLo(IN := (_eState = E_DL_FsgPhase.eDwellLo), PT := tDwell);   // 下限驻留计时 / Floor dwell timer

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;             // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;              // 锁存 / Latch
    _eCause := E_DL_FsgErr.eCfgBad;  // 归因：组态非法 / Cause: config illegal
END_IF

(* —— 段 2：使能退出 → 待机（先于 CASE，退出语义优先） —— *)
IF (NOT bEnable) OR _bErrLatch THEN
    _eState := E_DL_FsgPhase.eIdle;  // 未使能/故障回待机（R191 声明：频率归 fStartHz 安全值） / Back to idle
    _fFreq := fStartHz;              // 频率安全侧归下限 / Frequency safe-side floor
    bUpward := FALSE;                // 方向安全侧 FALSE / Direction safe side
END_IF

(* —— 段 3：四态顺控（仅使能且无故障期推进） —— *)
IF bEnable AND (NOT _bErrLatch) THEN
    CASE _eState OF

    E_DL_FsgPhase.eIdle:
        _fFreq := fStartHz;          // 起扫频率归下限 / Start at floor
        _eState := E_DL_FsgPhase.eRampUp;   // 使能即入升斜坡 / Enter up-ramp on enable

    E_DL_FsgPhase.eRampUp:
        IF _fFreq + _fStepUp >= fEndHz THEN
            _fFreq := fEndHz;        // 步内到顶：贴上限（禁过冲） / Reach ceiling
            _eState := E_DL_FsgPhase.eDwellHi;   // 入上限驻留 / Enter ceiling dwell
        ELSE
            _fFreq := _fFreq + _fStepUp;   // 升斜坡步进 / Up-ramp step
        END_IF

    E_DL_FsgPhase.eDwellHi:
        IF tonDwellHi.Q THEN
            _eState := E_DL_FsgPhase.eRampDn;   // 驻留到：反向 / Dwell done: reverse
        END_IF

    E_DL_FsgPhase.eRampDn:
        IF _fFreq - _fStepDn <= fStartHz THEN
            _fFreq := fStartHz;      // 步内到底：贴下限 / Reach floor
            _eState := E_DL_FsgPhase.eDwellLo;   // 入下限驻留 / Enter floor dwell
        ELSE
            _fFreq := _fFreq - _fStepDn;   // 降斜坡步进 / Down-ramp step
        END_IF

    E_DL_FsgPhase.eDwellLo:
        IF tonDwellLo.Q THEN
            _eState := E_DL_FsgPhase.eRampUp;   // 驻留到：再升 / Dwell done: ramp up again
        END_IF

    E_DL_FsgPhase.eFault:
        ;                            // 故障相驻留（由段 2 迁出链处理） / Held by exit chain

    ELSE
        _bErrLatch := TRUE;          // 非法相位兜底：锁存（R45 配对见段 5） / Illegal phase fallback latch
        _eCause := E_DL_FsgErr.ePhaseBad;   // 归因：非法相位（独立码，R190） / Cause: illegal phase
        _eState := E_DL_FsgPhase.eFault;   // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fFreqOutHz := _fFreq;                // 频率出口 / Frequency outlet
bUpward := (_eState = E_DL_FsgPhase.eRampUp) OR (_eState = E_DL_FsgPhase.eDwellHi);   // 方向标志（相别派生单源） / Direction from phase
ePhase := _eState;                   // 相位出口 / Phase outlet
IF _bErrLatch THEN
    bError := TRUE;                  // 故障标志（R45 配对） / Error flag
    eErrCode := _eCause;             // 成因锁存回放（R189） / Cause replay
ELSE
    bError := FALSE;                 // 无故障级条件 / No fault
    eErrCode := E_DL_FsgErr.eOk;     // 正常码 / OK code
END_IF

END_FUNCTION_BLOCK
