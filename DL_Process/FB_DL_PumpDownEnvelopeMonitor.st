(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PumpDownEnvelopeMonitor
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 命名说明 (Naming)     : 本库已存在 FB_DL_ChamberPumpDownProfile（早期入库，引脚为包络上界
 *                         与停滞极差口径，码位 0005_01F2/01F3/0330~0332）。R28 计划书序 13
 *                         的引脚口径（seg1End/seg2End 段界 + 斜率包络 + 抽速早停建议）与之
 *                         不兼容，且同名会与已注册组件撞名，故按「段界斜率包络」语义另立
 *                         本名，旧件保持不动。命名归属待总监裁定。
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 抽气曲线三段包络监视与抽速早停建议。按段界压强把抽气过程分为
 *                         粗抽 / 过渡 / 精抽三段，逐段用采样斜率与最小抽速比较：低于包络只
 *                         给早停**建议**（bSlowWarn），绝不切泵；压强非有限立即停段并报故障；
 *                         段超时只建议不切断。不做泵启停、不做阀门时序、不做泄漏率诊断。
 *                         交付门槛：斜率用时间转换链换算秒，须在 CODESYS / TwinCAT /
 *                         InoProShop 三平台各编译验证一次。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_PumpSeg / FUNCTION_BLOCK FB_DL_PumpDownEnvelopeMonitor
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / TIME_TO_LREAL）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         最小抽速与采样周期判零防除零 ｜ 段界反置判组态错 ｜ 压强非有限即
 *                         停段（不可读不许推进段）｜ 采样与段超时定时器无条件周期刷新 ｜
 *                         枚举显式赋值 ｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0005_0435 就绪（各段正常或非抽气期）
 *                         16#0005_0436 预留：本版不发码（下一轮区间起点，禁止回填）
 *                         16#0005_0437 故障级 组态非法（段界反置或最小抽速 ≤0、采样周期出域）
 *                         16#0005_0438 信息级 段超时，只给早停建议（不切泵、不置故障级标志）
 *                         16#0005_0439 故障级 压强非有限，停段（uSeg=9，不可读不许推进段）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 3（因撞名另立名）
 *                         2026-11-17  v1.0.1  终审修复：①早停建议改为段内锁存派生输出，新循环
 *                                    起点同拍清零（原「置位后永不清」会向上位留幽灵建议）；
 *                                    ②故障码改由锁存码回放，原「守不住原码」会把组态故障错
 *                                    报成压强故障· R28 · 阶段四
 * 验收向量 (Acceptance) : 正向 101→10 kPa/30 s（3.03 kPa/s）+ 10→1 kPa/45 s（0.2 kPa/s）、
 *                         最小抽速 0.1 → 全程合格、bProfileOk
 *                         反向 段拖到 200 s（0.045 kPa/s 低于 0.1）→ bSlowWarn 且不置故障；
 *                         段界反置 → 16#0005_0437；压强给 NaN → uSeg=9 + 16#0005_0439
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PumpSeg（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PumpSeg :
(
    eIdle  := 0,    // 待机：泵未运行 / Idle, the pump is not running
    eRough := 1,    // 粗抽段：压强高于段界 1 / Rough segment above boundary one
    eTrans := 2,    // 过渡段：介于段界 1 与段界 2 / Transition between the two boundaries
    eFine  := 3,    // 精抽段：低于段界 2 / Fine segment below boundary two
    eDone  := 4,    // 完成：全程达标 / Done, the whole profile was acceptable
    eFault := 9     // 故障：读数不可信，停段 / Fault, the reading is untrustworthy and the segment stops
);
END_TYPE

FUNCTION_BLOCK FB_DL_PumpDownEnvelopeMonitor
VAR_INPUT
    bEnable       : BOOL := FALSE;        // 使能 / Enable
    bPumpOn       : BOOL := FALSE;        // 泵运行中 / Pump running
    fPress_kPa    : REAL := 101.3;        // 腔体压强 [kPa(abs)] / Chamber pressure in kilopascal absolute
    fSeg1End_kPa  : REAL := 10.0;         // 段界 1 压强 [kPa(abs)]，须 > 段界 2 / Boundary one, must exceed boundary two
    fSeg2End_kPa  : REAL := 1.0;          // 段界 2 压强 [kPa(abs)] / Boundary two
    fSlopeMin_kPas : REAL := 0.1;         // 各段最小抽速 [kPa/s]，域 0.001~10 / Minimum slope, domain 0.001 to 10
    tSampleTime   : TIME := T#100MS;      // 采样周期 [ms]，域 10~1000 / Sampling period, domain 10 to 1000 ms
    tSegMax       : TIME := T#1800S;      // 单段超时 [ms]，域 1~1800 s / Per-segment timeout
END_VAR
VAR_OUTPUT
    fSeg1Slope_kPas : REAL;               // 段 1 实测斜率 [kPa/s] / Measured slope of segment one
    fSeg2Slope_kPas : REAL;               // 段 2 实测斜率 [kPa/s] / Measured slope of segment two
    uSeg          : UINT;                 // 段号 0 待机 1 粗抽 2 过渡 3 精抽 4 完成 9 故障 [—] / Segment number
    bSlowWarn     : BOOL;                 // 低于包络（早停建议） / Below the envelope, early-stop advice
    bProfileOk    : BOOL;                 // 全程合格 / The whole profile is acceptable
    eErr          : UDINT;                // 错误码，段位 16#0005_xxxx / Error code in segment 16#0005_xxxx
END_VAR
VAR
    _eSeg         : E_DL_PumpSeg := E_DL_PumpSeg.eIdle; // 当前段 / Current segment
    _bInit        : BOOL := FALSE;        // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk       : BOOL;                 // 组态合法标志 / Configuration valid flag
    _bHasSample   : BOOL := FALSE;        // 已有上一拍样本 / A previous sample exists
    _bSlowLatch   : BOOL := FALSE;        // 早停建议锁存（段内保持） / Early-stop advice latched inside a segment
    _uLatchCode   : UDINT;                // 故障锁存码载体（回放用） / Latch code carrier for the replay
    _bS1Judged    : BOOL := FALSE;        // 段 1 已判定标志 / Segment one already judged
    _bS2Judged    : BOOL := FALSE;        // 段 2 已判定标志 / Segment two already judged
    _fPrev_kPa    : REAL := 0.0;          // 上一拍压强 [kPa(abs)] / Previous pressure sample
    _fSampleSec   : REAL := 0.1;          // 采样周期换算秒 [s] / Sampling period in seconds
    _fSlope       : REAL;                 // 本拍斜率 [kPa/s] / Slope of this scan
    _rtrigSample  : R_TRIG;               // 采样节拍沿 / Sample tick edge
    _tonSample    : TON;                  // 采样周期计时（自复位） / Sampling period timer, self resetting
    _tonSeg       : TON;                  // 段超时计时 / Segment timeout timer
END_VAR
VAR CONSTANT
    DL_PD_READY    : UDINT := 16#0005_0435;  // 就绪码 / Ready code
    DL_PD_CFG_BAD  : UDINT := 16#0005_0437;  // 故障级组态非法码 / Fault code for bad configuration
    DL_PD_SEG_TO   : UDINT := 16#0005_0438;  // 信息级段超时码 / Info code for a segment timeout
    DL_PD_PRESS_BAD : UDINT := 16#0005_0439; // 故障级压强非有限码 / Fault code for a non-finite pressure
    DL_PD_SLOPE_LO : REAL := 0.001;          // 最小抽速下限 [kPa/s] / Minimum slope lower bound
    DL_PD_SLOPE_HI : REAL := 10.0;           // 最小抽速上限 [kPa/s] / Minimum slope upper bound
    DL_PD_SMP_LO   : TIME := T#10MS;         // 采样周期下限 / Sampling period lower bound
    DL_PD_SMP_HI   : TIME := T#1000MS;       // 采样周期上限 / Sampling period upper bound
    DL_PD_SEG_LO   : TIME := T#1S;           // 段超时下限 / Segment timeout lower bound
    DL_PD_SEG_HI   : TIME := T#1800S;        // 段超时上限 / Segment timeout upper bound
END_VAR

// 段 1｜输出与单拍标志预置
bProfileOk := FALSE;                                // 合格标志预清 / Acceptable flag pre-cleared
bSlowWarn := _bSlowLatch;                           // 早停建议由段内锁存派生（新循环起点即清） / Advice derived from the segment latch
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜采样与段超时定时器、沿实例无条件周期刷新
_tonSample(IN := bEnable AND bPumpOn AND (NOT _tonSample.Q), PT := tSampleTime);
_rtrigSample(CLK := _tonSample.Q);
_tonSeg(IN := bEnable AND bPumpOn AND (_eSeg <> E_DL_PumpSeg.eIdle) AND (_eSeg <> E_DL_PumpSeg.eDone)
            AND (_eSeg <> E_DL_PumpSeg.eFault), PT := tSegMax);

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eSeg := E_DL_PumpSeg.eIdle;                    // 段待机起步 / Segment starts idle
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜组态闸（段界反置使段永远进不去；最小抽速与采样周期判零防除零）
_bCfgOk := (fSeg1End_kPa > fSeg2End_kPa)
        AND NOT ((fSlopeMin_kPas <> fSlopeMin_kPas) OR ((fSlopeMin_kPas - fSlopeMin_kPas) <> (fSlopeMin_kPas - fSlopeMin_kPas)))
        AND (fSlopeMin_kPas >= DL_PD_SLOPE_LO) AND (fSlopeMin_kPas <= DL_PD_SLOPE_HI)
        AND (tSampleTime >= DL_PD_SMP_LO) AND (tSampleTime <= DL_PD_SMP_HI)
        AND (tSegMax >= DL_PD_SEG_LO) AND (tSegMax <= DL_PD_SEG_HI);
_fSampleSec := TIME_TO_LREAL(tSampleTime) / 1000.0; // 采样周期换算秒 [s] / Sampling period in seconds
IF _fSampleSec < 0.001 THEN
    _fSampleSec := 0.001;                           // 换算兜底下限 [s] / Conversion lower bound guard
END_IF
IF NOT _bCfgOk THEN
    eErr := DL_PD_CFG_BAD;                          // 故障级：组态非法 / Fault, bad configuration
    _uLatchCode := DL_PD_CFG_BAD;                   // 故障锁存码 / Fault latch code
    _eSeg := E_DL_PumpSeg.eFault;
END_IF

// 段 5｜压强可读闸（不可读不许推进段）
IF (fPress_kPa <> fPress_kPa) OR ((fPress_kPa - fPress_kPa) <> (fPress_kPa - fPress_kPa)) THEN
    eErr := DL_PD_PRESS_BAD;                        // 故障级：压强非有限 / Fault, the pressure is not finite
    _uLatchCode := DL_PD_PRESS_BAD;                 // 故障锁存码 / Fault latch code
    _eSeg := E_DL_PumpSeg.eFault;
    _bHasSample := FALSE;                           // 样本作废 / The sample is dropped
END_IF

// 段 6｜采样斜率（仅泵运行且样本有效）
IF _rtrigSample.Q AND _bHasSample AND (_eSeg <> E_DL_PumpSeg.eFault) THEN
    _fSlope := (fPress_kPa - _fPrev_kPa) / _fSampleSec;   // 本拍斜率（负 = 下降）[kPa/s] / Slope of this scan
    IF _eSeg = E_DL_PumpSeg.eRough THEN
        fSeg1Slope_kPas := ABS(_fSlope);            // 段 1 斜率取绝对值 [kPa/s] / Segment one slope magnitude
    ELSIF _eSeg = E_DL_PumpSeg.eTrans THEN
        fSeg2Slope_kPas := ABS(_fSlope);            // 段 2 斜率取绝对值 [kPa/s] / Segment two slope magnitude
    END_IF
    IF ABS(_fSlope) < fSlopeMin_kPas THEN
        _bSlowLatch := TRUE;                        // 低于包络：早停建议锁存 / Below the envelope, the advice is latched
        bSlowWarn := TRUE;
    END_IF
END_IF
IF _rtrigSample.Q THEN
    _fPrev_kPa := fPress_kPa;                       // 样本快照（唯一写点） / Sample snapshot, the single write point
    _bHasSample := TRUE;
END_IF

// 段 7｜段推进（ENUM + CASE + ELSE 兜底）
IF bEnable THEN
    CASE _eSeg OF
        E_DL_PumpSeg.eIdle:                         // 待机：泵启动即入粗抽
            IF bPumpOn THEN
                _bSlowLatch := FALSE;               // 新循环：建议清 / New cycle, the advice is cleared
                bSlowWarn := FALSE;                 // 同拍清出口，不留给上位幽灵建议 / The output is cleared in the same scan
                _bS1Judged := FALSE;
                _bS2Judged := FALSE;
                bProfileOk := FALSE;
                fSeg1Slope_kPas := 0.0;
                fSeg2Slope_kPas := 0.0;
                _eSeg := E_DL_PumpSeg.eRough;
            END_IF
            eErr := DL_PD_READY;

        E_DL_PumpSeg.eRough:                        // 粗抽段：跌破段界 1 即判段 1 合格与否
            IF NOT bPumpOn THEN
                _eSeg := E_DL_PumpSeg.eDone;        // 泵停：结束本次监视 / The pump stopped, the monitoring ends
            ELSIF fPress_kPa <= fSeg1End_kPa THEN
                IF ABS(fSeg1Slope_kPas) < fSlopeMin_kPas THEN
                    _bSlowLatch := TRUE;            // 段 1 低于包络 / Segment one below the envelope
                    bSlowWarn := TRUE;
                ELSE
                    _bS1Judged := TRUE;             // 段 1 合格 / Segment one accepted
                END_IF
                _eSeg := E_DL_PumpSeg.eTrans;
            ELSIF _tonSeg.Q THEN
                eErr := DL_PD_SEG_TO;               // 信息级：段超时，只建议早停 / Info, the segment timed out, advice only
                bSlowWarn := TRUE;
            END_IF

        E_DL_PumpSeg.eTrans:                        // 过渡段：跌破段界 2 即判段 2
            IF NOT bPumpOn THEN
                _eSeg := E_DL_PumpSeg.eDone;
            ELSIF fPress_kPa <= fSeg2End_kPa THEN
                IF ABS(fSeg2Slope_kPas) < fSlopeMin_kPas THEN
                    _bSlowLatch := TRUE;            // 段 2 低于包络 / Segment two below the envelope
                    bSlowWarn := TRUE;
                ELSE
                    _bS2Judged := TRUE;             // 段 2 合格 / Segment two accepted
                END_IF
                _eSeg := E_DL_PumpSeg.eFine;
            ELSIF _tonSeg.Q THEN
                eErr := DL_PD_SEG_TO;               // 信息级：段超时 / Info, the segment timed out
                bSlowWarn := TRUE;
            END_IF

        E_DL_PumpSeg.eFine:                         // 精抽段：泵停即完成并给全程结论
            IF NOT bPumpOn THEN
                bProfileOk := _bS1Judged AND _bS2Judged AND (NOT _bSlowLatch);   // 全程合格判据 / Whole-profile verdict
                _eSeg := E_DL_PumpSeg.eDone;
            ELSIF _tonSeg.Q THEN
                eErr := DL_PD_SEG_TO;               // 信息级：精抽段超时 / Info, the fine segment timed out
                bSlowWarn := TRUE;
            END_IF

        E_DL_PumpSeg.eDone:                         // 完成：等泵再次启动或失能
            bProfileOk := _bS1Judged AND _bS2Judged AND (NOT _bSlowLatch);
            IF NOT bPumpOn THEN
                _eSeg := E_DL_PumpSeg.eIdle;        // 泵已停：回待机 / Pump stopped, back to idle
            END_IF

        E_DL_PumpSeg.eFault:                        // 故障：停段，等失能后恢复
            IF _uLatchCode <> 0 THEN
                eErr := _uLatchCode;                // 锁存码回放（守住首因，不按当下输入改码） / Replay the latch code
            ELSIF eErr = 0 THEN
                eErr := DL_PD_PRESS_BAD;            // 兜底：无锁存码时按读数不可信上报 / Fallback when no latch code exists
            END_IF
            IF NOT bEnable THEN
                _eSeg := E_DL_PumpSeg.eIdle;        // 失能恢复 / Recovered on disable
                _uLatchCode := 0;                   // 锁存码清 / Latch code cleared
                _bHasSample := FALSE;
            END_IF

        ELSE
            // 非法段兜底（故障级，组态非法码承载）
            eErr := DL_PD_CFG_BAD;                  // 故障级：非法段值 / Fault, illegal segment value
            _uLatchCode := DL_PD_CFG_BAD;           // 故障锁存码 / Fault latch code
            _eSeg := E_DL_PumpSeg.eFault;
    END_CASE
END_IF

uSeg := 0;                                          // 段出口预置 / Segment output pre-set
CASE _eSeg OF
    E_DL_PumpSeg.eIdle:  uSeg := 0;                 // 待机 / Idle
    E_DL_PumpSeg.eRough: uSeg := 1;                 // 粗抽 / Rough
    E_DL_PumpSeg.eTrans: uSeg := 2;                 // 过渡 / Transition
    E_DL_PumpSeg.eFine:  uSeg := 3;                 // 精抽 / Fine
    E_DL_PumpSeg.eDone:  uSeg := 4;                 // 完成 / Done
    E_DL_PumpSeg.eFault: uSeg := 9;                 // 故障 / Fault
    ELSE
        uSeg := 9;                                  // 非法段按故障段出口 / Illegal segments are reported as fault
END_CASE
END_FUNCTION_BLOCK
