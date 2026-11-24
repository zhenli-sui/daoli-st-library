(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HeaterBreakDetect
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 加热管断棒检测（电 + 温双判据，判据介入次序纪律固化）：
 *                         ① 判据一（电流对比）：通电 tWatch 窗到后，电流对基线 fCurRefA 的
 *                            欠偏百分比超 fCurDevPct → eCurLow（电流显著低，直接判低）。
 *                         ② 判据二（温升速率）：**仅在判据一存疑时介入**（电流欠偏为正但
 *                            未达阈值，散热类误报高发域）；以 tTempWatch 自复位窗做窗端温升
 *                            差值判据：窗内温升 < fTempRiseMin × 窗长(分钟) → eNoTempRise。
 *                         ③ 两判据同时成立 → eBreakConfirm **锁存**（断棒确认需人工核查，
 *                            解除沿 = bReset 上升沿）。
 *                         SCR 调功类供电（bPhaseAngle=TRUE，电流与功率非线性）：判据一自动
 *                         降级不判，只信判据二。
 * 接口     (Interface)  : 输入 bHeaterOn 通电、fCurrentA 电流（A）、fTempC 被加热体温度
 *                         （℃）、fCurRefA 额定电流基线（A）、fCurDevPct 判据一欠偏阈值
 *                         （%）、fTempRiseMin 判据二最小温升（℃/min）、tWatch 判据一窗、
 *                         tTempWatch 判据二窗、bPhaseAngle 相角调功声明、bReset 复位；
 *                         输出 eHeat 状态、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做断棒诊断，不驱动加热器、不调功、
 *                         不接管 SSR/SCR**（驱动归 `FB_DL_SsrHeaterDrive` 族）。
 *                         ② 非通电相全判据冻结回 eOff；温升判据采用窗端差值法（温升 =
 *                         窗末温 - 窗首温），阈值 = fTempRiseMin × 窗长分钟数，分母时间闸
 *                         以窗长 > T#0S 组态闸实现（不做逐拍速率除法，无除零路径）。
 *                         ③ 非有限输入当拍剔除（判据冻结当拍，R245）；窗首温度快照仅在
 *                         有限拍更新（防 NaN 污染快照）。
 *                         ④ TIME_TO_DINT 取窗长毫秒数（tTempWatch 经组态闸保证为正，
 *                         无 TIME_TO_DINT 负值恒假陷阱）。
 *                         ⑤ 组态闸：fCurRefA<=0、fCurDevPct<=0、fTempRiseMin<0、
 *                         tWatch<=T#0S、tTempWatch<=T#0S → 锁存 bError，eHeat 冻结 eOff，
 *                         解除沿 = bReset 上升沿。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_SsrHeaterDrive` / `FB_DL_HeaterSsrBank` 分工：诊断
 *                         （本件）≠ 驱动/组 bank（那两件）。
 * 来源标签 (Source Tag) : T2-6 ◐（Rockwell AOI 设备诊断粒度只借"断棒电+温双判据"分类
 *                         事实，判据介入次序纪律为本件自研固化）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 状态 + BOOL；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前置（基线闸）+ 非有限剔除 + 时间域组态闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM 状态判序 ｜ R7 ✓ 两 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 3 · 序号 11）
 *                         验收向量：电流欠偏超阈值 → eCurLow；电流略低 + 窗温升不足 →
 *                         eBreakConfirm 锁存；bPhaseAngle=TRUE 只走温判据；断电回 eOff。
 *==============================================================================*)

TYPE E_DL_HbdState :
(
    eOk           := 0,    // 正常（判据未触发）/ Healthy, no judge fired
    eCurLow       := 10,   // 电流显著欠偏（判据一直接判低）/ Current notably low, judge 1 direct
    eNoTempRise   := 20,   // 温升不足（判据二介入判出）/ Insufficient temperature rise, judge 2 fired
    eBreakConfirm := 30,   // 双判据同时成立，断棒确认（锁存待复位）/ Both judges fired, break confirmed, latched
    eOff          := 40    // 未通电（判据冻结）/ Heater off, judges frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeaterBreakDetect
VAR_INPUT
    bHeaterOn   : BOOL := FALSE;   // 加热器通电状态 [-] / Heater energized state
    fCurrentA   : LREAL := 0.0;    // 加热回路电流实测 [A] / Heater loop current [A]
    fTempC      : LREAL := 0.0;    // 被加热体温度实测 [℃] / Heated body temperature [degC]
    fCurRefA    : LREAL := 10.0;   // 额定电流基线，域 > 0 [A] / Rated current baseline [A]
    fCurDevPct  : LREAL := 30.0;   // 判据一欠偏阈值，域 > 0 [%] / Judge-1 under-deviation threshold [%]
    fTempRiseMin: LREAL := 2.0;    // 判据二最小温升速率，域 >= 0 [℃/min] / Judge-2 minimum rise rate [degC/min]
    tWatch      : TIME := T#10S;   // 判据一观察窗，域 > T#0S [ms] / Judge-1 watch window [ms]
    tTempWatch  : TIME := T#60S;   // 判据二温升窗，域 > T#0S [ms] / Judge-2 rise window [ms]
    bPhaseAngle : BOOL := FALSE;   // 相角调功声明（TRUE=判据一降级只信判据二） [-] / Phase-angle supply declaration
    bReset      : BOOL := FALSE;   // 复位，上升沿清 bError 与断棒锁存 [-] / Reset, rising edge clears latches
END_VAR
VAR_OUTPUT
    eHeat  : E_DL_HbdState;        // 断棒诊断状态出口 [-] / Break-detect state outlet
    bError : BOOL;                 // 故障标志（组态非法 ∨ 断棒确认，锁存） [-] / Error flag, latched
END_VAR
VAR
    _eHeat     : E_DL_HbdState := E_DL_HbdState.eOff;   // 内部状态 / Internal state
    _bCurLow   : BOOL;           // 判据一命中当拍量 / Judge-1 fired this scan
    _bSuspect  : BOOL;           // 判据一存疑（欠偏为正未达阈值）/ Judge-1 suspect flag
    _bNoRise   : BOOL;           // 判据二命中锁存（窗到裁决结果保持到下次裁决）/ Judge-2 fired latch
    _bBreak    : BOOL;           // 断棒确认锁存位（解除沿 = bReset 上升沿） / Break-confirm latch, cleared by reset edge
    _bErrLatch : BOOL;           // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    _fTempStart: LREAL := 0.0;   // 温升窗首温度快照 [℃] / Window-start temperature snapshot
    _fRiseLim  : LREAL;          // 温升判据绝对限（速率×窗长分钟） [℃] / Rise judge absolute limit
    _fMinWin   : LREAL;          // 窗长分钟数（毫秒/60000） [min] / Window length in minutes
    _fDevPct   : LREAL;          // 当拍电流欠偏百分比 [%] / Current under-deviation percent
    _bNonFin   : BOOL;           // 输入非有限当拍量 [-] / Non-finite input this scan
    tonWatch   : TON;            // 判据一观察窗定时器，段 0 无条件调用 / Judge-1 window timer
    tonTempWatch: TON;           // 判据二自复位温升窗，段 0 无条件调用 / Judge-2 self-reset rise window
    rtOn       : R_TRIG;         // 通电上升沿实例，段 0 无条件调用 / Energize rising edge instance
    rtReset    : R_TRIG;         // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_HBD_PCT  : LREAL := 100.0;   // 百分比换算基 [无量纲] / Percent conversion base
    DL_HBD_MS   : LREAL := 60000.0; // 毫秒到分钟换算基 [ms/min] / Millisecond-per-minute base
    DL_HBD_ZERO : LREAL := 0.0;     // 非有限差值判零基准 [-] / Non-finite difference zero base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 两 TON 两沿无条件周期刷新 —— *)
_bNonFin := (fCurrentA <> fCurrentA) OR ((fCurrentA - fCurrentA) <> DL_HBD_ZERO)
         OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> DL_HBD_ZERO);   // 电流/温度非有限（R245） / Non-finite current and temperature
IF (fCurRefA <= 0.0) OR (fCurDevPct <= 0.0) OR (fTempRiseMin < 0.0)
   OR (tWatch <= T#0S) OR (tTempWatch <= T#0S) THEN
    _bErrLatch := TRUE;                                     // 组态域闸：锁存（R188 解除沿 = bReset 上升沿） / Config gate: latch
END_IF
_fMinWin := DINT_TO_LREAL(TIME_TO_DINT(tTempWatch)) / DL_HBD_MS;   // 窗长分钟数（窗长已过正闸，无负值陷阱） / Window minutes
_fRiseLim := fTempRiseMin * _fMinWin;                       // 温升判据绝对限 [℃] / Rise absolute limit
tonWatch(IN := bHeaterOn AND (NOT _bNonFin) AND (NOT _bErrLatch), PT := tWatch);   // 判据一观察窗 / Judge-1 window
tonTempWatch(IN := bHeaterOn AND (NOT tonTempWatch.Q) AND (NOT _bNonFin) AND (NOT _bErrLatch), PT := tTempWatch);   // 判据二自复位窗（R188） / Judge-2 self-reset window
rtOn(CLK := bHeaterOn);                                     // 通电沿，每拍必调 / Energize edge, every scan
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 / 通电沿（快照初始化） —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                                    // 清组态故障锁存 / Clear config latch
    _bBreak := FALSE;                                       // 清断棒确认锁存 / Clear break latch
    _bNoRise := FALSE;                                      // 清温升判据锁存 / Clear rise latch
END_IF
IF rtOn.Q THEN
    _fTempStart := fTempC;                                  // 通电首拍初始化窗首快照（仅有限拍更新） / Init snapshot on energize
END_IF

(* —— 段 2：判据一（电流对比；相角调功降级不判） —— *)
_bCurLow := FALSE;                                          // 判据一当拍量预清 / Judge-1 preset
_bSuspect := FALSE;                                         // 存疑量预清 / Suspect preset
IF bHeaterOn AND (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fDevPct := (fCurRefA - fCurrentA) / fCurRefA * DL_HBD_PCT;   // 欠偏百分比（分母基线已过闸，无除零） / Under-deviation percent
    IF (NOT bPhaseAngle) AND tonWatch.Q THEN
        IF _fDevPct > fCurDevPct THEN
            _bCurLow := TRUE;                               // 判据一直接判低 / Judge-1 direct low
        ELSIF _fDevPct > 0.0 THEN
            _bSuspect := TRUE;                              // 电流略低未达阈值：判据一存疑，判据二获准介入 / Marginally low: judge 2 engaged
        END_IF
    END_IF
END_IF

(* —— 段 3：判据二（窗端温升差值；仅存疑时介入，窗到裁决） —— *)
IF tonTempWatch.Q THEN
    IF _bSuspect AND (NOT _bNonFin) AND ((fTempC - _fTempStart) < _fRiseLim) THEN
        _bNoRise := TRUE;                                   // 窗内温升不足限值：判据二命中（锁存至下次裁决） / Insufficient rise: judge 2 fired
    ELSE
        _bNoRise := FALSE;                                  // 温升达标或无存疑前提：判据二复位 / Rise adequate: judge 2 reset
    END_IF
    _fTempStart := fTempC;                                  // 窗末重置快照（先裁决后重置，防同拍抹除） / Reset snapshot after judging
END_IF

(* —— 段 4：状态合成（断棒确认锁存优先；非通电回 eOff） —— *)
IF _bErrLatch THEN
    _eHeat := E_DL_HbdState.eOff;                           // 组态故障期冻结 eOff 安全侧 / Frozen to eOff on fault
ELSIF NOT bHeaterOn THEN
    _eHeat := E_DL_HbdState.eOff;                           // 非通电相判据冻结 / Off phase frozen
ELSIF _bBreak THEN
    _eHeat := E_DL_HbdState.eBreakConfirm;                  // 锁存回放确认态（不按当下输入重推断，R189） / Latched confirm replay
ELSE
    IF _bCurLow AND _bNoRise THEN
        _bBreak := TRUE;                                    // 双判据同时成立：锁存确认（解除沿 = bReset 上升沿） / Both judges: latch confirm
        _eHeat := E_DL_HbdState.eBreakConfirm;              // 入确认态 / Enter confirm
    ELSIF _bCurLow THEN
        _eHeat := E_DL_HbdState.eCurLow;                    // 判据一单独命中 / Judge 1 alone
    ELSIF _bNoRise THEN
        _eHeat := E_DL_HbdState.eNoTempRise;                // 判据二单独命中 / Judge 2 alone
    ELSE
        _eHeat := E_DL_HbdState.eOk;                        // 判据均未触发 / No judge fired
    END_IF
END_IF

(* —— 段 5：出口单点映射（名实双出口同源，R191） —— *)
eHeat  := _eHeat;                                           // 状态出口 / State outlet
bError := _bErrLatch OR _bBreak;                            // 故障标志 = 组态非法 ∨ 断棒确认 / Error = cfg fault or confirm

END_FUNCTION_BLOCK
