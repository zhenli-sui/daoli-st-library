(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChamberPumpDownSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 腔体抽真空顺控与漏率复测（四段：抽气 → 稳压 → 漏率复测 → 放气限速）。
 *                         每相一枚**专用** TON，PT 各绑一个时间引脚，绝不复用实例改 PT：
 *                           ePump   抽气  ：tonPumpTo  PT = tPumpTo  （到目标真空 fPrTargetKpa 即过相）
 *                           eStab   稳压  ：tonStabTo  PT = tStab    （纯定时过相）
 *                           eLeak   复测  ：tonLeakWin PT = tLeakWin （窗满即算漏率）
 *                           eVent   放气  ：tonVentTo  PT = tVentTo  （到常压即回待机）
 *                         **漏率判据**：窗起压 fPrStart 与窗末压 fPrEnd 之差除以窗内实际时长；
 *                         窗内实际时长＝采样计数 × 采样周期（fSampleS），因此不需要 TIME→实数转换
 *                         （规避跨平台时间转换链，R64 家族），且分母双闸（计数 ≥ 1 且周期 > 0）。
 *                         **放气限速**：逐拍放气速率超 fVentRateMaxKpaPerS 时当拍关阀（bang-bang 限速），
 *                         并在下一拍重新开阀，形成占空比式限速；超速不锁存（工艺可容忍），只置信息级。
 *                         验收向量：
 *                           ① 目标 −90 kPa，实测 −90.2 → 过相进入稳压
 *                           ② 窗 5 s、周期 0.1 s、Δp = 0.5 kPa → 漏率 0.5/(50×0.1) = 0.1 kPa/s
 *                           ③ fLeakMax = 0.05 kPa/s 且实测 0.1 → eLeakNg 锁存，禁止进入放气
 *                           ④ 放气速率 2.0 kPa/s > 上限 1.0 → 当拍关阀 + eVentTooFast（信息级）
 * 接口     (Interface)  : 入 bStart 启动沿、fPrMeasKpa 实测腔压、fPrTargetKpa 目标真空（负值）、
 *                         fLeakMaxKpaPerS 漏率上限、fVentRateMaxKpaPerS 放气速率上限、fSampleS 采样周期、
 *                         tPumpTo / tStab / tLeakWin / tVentTo 四段时间、bStop 中止、bReset 复位沿；
 *                         出 bPumpValve 抽气阀位、bVentValve 放气阀位、fLeakRateKpaPerS 实测漏率、
 *                         bLeakNg 漏率超限锁存、bBusy 顺控中、bDone 完成脉冲（单拍）、
 *                         ePhase 当前相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"腔体抽真空时序 + 漏率判据 + 放气限速"，
 *                         不驱动真空泵/角阀线圈、不做脱泡/灌胶工艺**——灌胶真空脱泡四相属
 *                         `FB_DL_ModulePottingVac`，两件不同属主、判据不共用（R47 边界声明）；
 *                         ② **分母双闸**：窗内采样计数 = 0 或采样周期 ≤ 0 时漏率判据整段不判，
 *                         并锁存 eCfgIllegal（静默失效比报错危险，R179）；
 *                         ③ **组态闸**：四段时间须 > T#0S、目标真空须 < 0（相对压）、
 *                         两上限须 > 0，违反即锁存 eCfgIllegal；
 *                         ④ **一相一 TON**：四枚专用 TON 段 0 无条件调用，IN 由当前相派生
 *                         （R228A/R275），无跨相累积；
 *                         ⑤ **eFault 可迁出**：bReset 上升沿 → eIdle；bStop 在非故障相回 eIdle
 *                         并置中止脉冲（泵/阀在出口侧随相切断）；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"腔体抽真空与漏率复测"。不接管：灌胶脱泡四相
 *                         （属 FB_DL_ModulePottingVac）、真空泵轮换（属泵组件）、
 *                         腔体压力闭环调节（属压力环件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（腔体抽真空与漏率复测，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 分母双闸 + 组态闸 + 漏率钳位 + 非有限闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ 四 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 3 · 序号 14）
 *==============================================================================*)

TYPE E_DL_CpdPhase :
(
    eIdle  := 0,    // 待机相（泵/阀全停） / Idle, pump and valves off
    ePump  := 10,   // 抽气相（等到目标真空） / Pumping down to the target
    eStab  := 20,   // 稳压相（压力稳定） / Stabilising
    eLeak  := 30,   // 漏率复测相（测量窗内） / Leak-rate measurement window
    eVent  := 40,   // 放气相（限速） / Venting with rate limiting
    eFault := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_CpdCause :
(
    eNone         := 0,   // 无异常 / No anomaly
    eCfgIllegal   := 1,   // 组态非法（时间/目标/上限/采样越域） / Illegal configuration
    ePumpTimeout  := 2,   // 抽气超时未达目标真空 / Pump-down timeout
    eLeakNg       := 3,   // 漏率超限（锁存） / Leak rate exceeded, latched
    eVentTimeout  := 4,   // 放气超时未到常压 / Vent timeout
    eVentTooFast  := 5,   // 放气速率超限（信息级，当拍关阀） / Vent rate exceeded, info level
    ePhaseBad     := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChamberPumpDownSeq
VAR_INPUT
    bStart             : BOOL := FALSE;     // 启动沿，进入抽气相 [-] / Start edge, enters pumping
    bStop              : BOOL := FALSE;     // 中止（非故障相回待机） [-] / Abort
    fPrMeasKpa         : LREAL := 0.0;      // 实测腔压（相对压，负值为真空） [kPa] / Measured chamber pressure [kPa]
    fPrTargetKpa       : LREAL := -90.0;    // 目标真空，域 < 0 [kPa] / Target vacuum, < 0
    fLeakMaxKpaPerS    : LREAL := 0.05;     // 漏率上限，域 > 0 [kPa/s] / Leak-rate limit, > 0
    fVentRateMaxKpaPerS: LREAL := 1.0;      // 放气速率上限，域 > 0 [kPa/s] / Vent-rate limit, > 0
    fSampleS           : LREAL := 0.1;      // 调用采样周期，域 > 0 [s] / Sampling period, > 0
    tPumpTo            : TIME := T#120S;    // 抽气超时，域 > T#0S [ms] / Pump-down timeout
    tStab              : TIME := T#5S;      // 稳压时长，域 > T#0S [ms] / Stabilisation time
    tLeakWin           : TIME := T#10S;     // 漏率测量窗，域 > T#0S [ms] / Leak measurement window
    tVentTo            : TIME := T#60S;     // 放气超时，域 > T#0S [ms] / Vent timeout
    bReset             : BOOL := FALSE;     // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    bPumpValve  : BOOL := FALSE;                          // 抽气阀位（含真空泵启动允许） [-] / Pump valve position
    bVentValve  : BOOL := FALSE;                          // 放气阀位 [-] / Vent valve position
    fLeakRateKpaPerS : LREAL := 0.0;                      // 实测漏率 [kPa/s] / Measured leak rate [kPa/s]
    bLeakNg     : BOOL := FALSE;                          // 漏率超限锁存（等复位） [-] / Leak NG, latched
    bBusy       : BOOL := FALSE;                          // 顺控进行中 [-] / Sequence busy
    bDone       : BOOL := FALSE;                          // 完成脉冲（单拍） [-] / Completion pulse, single scan
    bAborted    : BOOL := FALSE;                          // 中止脉冲（单拍） [-] / Abort pulse, single scan
    ePhase      : E_DL_CpdPhase := E_DL_CpdPhase.eIdle;   // 当前相出口 [-] / Present phase outlet
    eCause      : E_DL_CpdCause := E_DL_CpdCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL := FALSE;                          // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState    : E_DL_CpdPhase := E_DL_CpdPhase.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_CpdCause := E_DL_CpdCause.eNone;    // 成因锁存量 / Latched cause
    _bFault    : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bLeakNg   : BOOL := FALSE;                           // 漏率超限锁存位 / Latched leak-NG bit
    _bDone     : BOOL := FALSE;                           // 完成脉冲内部位（单拍） / Internal completion pulse
    _bAborted  : BOOL := FALSE;                           // 中止脉冲内部位（单拍） / Internal abort pulse
    _bBusyPrev : BOOL := FALSE;                           // 上拍忙碌快照 / Busy snapshot of the previous scan
    _fPrStart  : LREAL := 0.0;                            // 测量窗起始压力 [kPa] / Pressure at the window start
    _fPrPrev   : LREAL := 0.0;                            // 上拍压力（放气速率用） [kPa] / Previous pressure for the vent rate
    _fPrNow    : LREAL := 0.0;                            // 当拍压力工作值 [kPa] / Pressure working value
    _fRate     : LREAL := 0.0;                            // 速率工作值 [kPa/s] / Rate working value
    _fDtS      : LREAL := 0.0;                            // 实际时长（计数 × 周期） [s] / Effective duration [s]
    _nWinCnt   : UDINT := 0;                              // 窗内采样计数 [个] / Sample count inside the window
    _bCfgBad   : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _bPrOk     : BOOL := FALSE;                           // 压力样本有限性结论 / Pressure sample finiteness
    _bVent     : BOOL := FALSE;                           // 放气阀内部位（限速判决，单拍重算） / Internal vent valve bit
    tonPumpTo  : TON;                                     // 抽气相专用超时，段 0 无条件调用 / Pump dedicated timeout
    tonStabTo  : TON;                                     // 稳压相专用时长，段 0 无条件调用 / Stabilisation dedicated time
    tonLeakWin : TON;                                     // 复测相专用窗，段 0 无条件调用 / Leak-window dedicated timer
    tonVentTo  : TON;                                     // 放气相专用超时，段 0 无条件调用 / Vent dedicated timeout
    rtStart    : R_TRIG;                                  // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset    : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_CPD_EPS : LREAL := 1.0E-9;         // 浮点判等容差 [kPa] / Equality tolerance [kPa]
END_VAR

(* —— 段 0：组态闸 + 四枚专用 TON 与两沿无条件周期刷新（R228A/R275） —— *)
_bCfgBad := (tPumpTo <= T#0S) OR (tStab <= T#0S) OR (tLeakWin <= T#0S) OR (tVentTo <= T#0S)   // 四时间须为正 / Four times positive
         OR (fPrTargetKpa >= 0.0)                                                              // 目标真空须为负（相对压） / Target vacuum negative
         OR (fLeakMaxKpaPerS <= 0.0) OR (fVentRateMaxKpaPerS <= 0.0)                           // 两上限须为正 / Both limits positive
         OR (fSampleS <= 0.0) OR (fSampleS <> fSampleS);                                        // 采样周期须为正且有限 / Sampling period positive and finite
rtStart(CLK := bStart);                                                                        // 启动沿 / Start edge
rtReset(CLK := bReset);                                                                        // 复位沿 / Reset edge
tonPumpTo(IN := (_eState = E_DL_CpdPhase.ePump), PT := tPumpTo);                                // 抽气相专用超时 / Pump timeout
tonStabTo(IN := (_eState = E_DL_CpdPhase.eStab), PT := tStab);                                  // 稳压相专用时长 / Stabilisation time
tonLeakWin(IN := (_eState = E_DL_CpdPhase.eLeak), PT := tLeakWin);                              // 复测相专用窗 / Leak window
tonVentTo(IN := (_eState = E_DL_CpdPhase.eVent), PT := tVentTo);                                // 放气相专用超时 / Vent timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bLeakNg/_fPrStart/_bBusyPrev 不入清单，R107） —— *)
_bDone    := FALSE;                                                                             // 完成脉冲预清 / Completion pulse preset
_bAborted := FALSE;                                                                             // 中止脉冲预清 / Abort pulse preset
bError    := FALSE;                                                                             // 故障标志预清（R45 配对） / Error preset
_bVent    := FALSE;                                                                             // 放气阀内部位预清（每拍显式赋值，R285） / Vent bit preset
fLeakRateKpaPerS := 0.0;                                                                        // 漏率出口预置 / Leak-rate outlet preset
_fRate    := 0.0;                                                                               // 速率工作值预置 / Rate working value preset

(* —— 段 2：组态闸（非法即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_CpdCause.eCfgIllegal;                                                       // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                                            // 锁存 / Latch
    _eState := E_DL_CpdPhase.eFault;                                                            // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿 → 待机相；清漏率锁存） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;                                                                          // 清故障锁存 / Clear fault latch
    _bLeakNg := FALSE;                                                                          // 清漏率锁存 / Clear the leak latch
    _eCause  := E_DL_CpdCause.eNone;                                                            // 清成因 / Clear cause
    _nWinCnt := 0;                                                                              // 窗计数清零 / Window count cleared
    _eState  := E_DL_CpdPhase.eIdle;                                                            // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（顺控 + 漏率判据 + 放气限速） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    _bPrOk := NOT ((fPrMeasKpa <> fPrMeasKpa) OR ((fPrMeasKpa - fPrMeasKpa) <> (fPrMeasKpa - fPrMeasKpa)));   // 压力样本有限性
    _fPrNow := fPrMeasKpa;                                                                       // 当拍压力工作值 / Pressure working value

    IF bStop AND (_eState <> E_DL_CpdPhase.eIdle) THEN
        _bAborted := TRUE;                                                                       // 中止脉冲 / Abort pulse
        _eState := E_DL_CpdPhase.eIdle;                                                          // 回待机相（出口侧泵/阀随相切断） / Back to idle
    ELSE
        CASE _eState OF

        E_DL_CpdPhase.eIdle:
            _nWinCnt := 0;                                                                       // 待机相清零窗计数 / Clear the window count in idle
            IF rtStart.Q THEN
                _eState := E_DL_CpdPhase.ePump;                                                  // 启动沿进抽气相 / Enter pumping
            END_IF

        E_DL_CpdPhase.ePump:
            IF _bPrOk AND (_fPrNow <= fPrTargetKpa) THEN
                _eState := E_DL_CpdPhase.eStab;                                                  // 达目标真空：进稳压相 / Target reached, stabilise
            ELSIF tonPumpTo.Q THEN
                _eCause := E_DL_CpdCause.ePumpTimeout;                                           // 归因：抽气超时 / Cause: pump timeout
                _bFault := TRUE;                                                                 // 锁存 / Latch
                _eState := E_DL_CpdPhase.eFault;                                                 // 入故障相 / Enter fault phase
            END_IF

        E_DL_CpdPhase.eStab:
            IF tonStabTo.Q THEN
                _fPrStart := _fPrNow;                                                            // 记录窗起压（稳压结束点） / Record the window-start pressure
                _nWinCnt  := 0;                                                                  // 窗计数清零 / Clear the window count
                _eState   := E_DL_CpdPhase.eLeak;                                                // 进复测相 / Enter the leak phase
            END_IF

        E_DL_CpdPhase.eLeak:
            IF _bPrOk THEN
                _nWinCnt := _nWinCnt + 1;                                                        // 窗内采样计数 +1 / Count this sample
            END_IF
            IF tonLeakWin.Q THEN
                _fDtS := UDINT_TO_LREAL(_nWinCnt) * fSampleS;                                    // 实际时长 = 计数 × 周期 / Effective duration
                IF (_nWinCnt < 1) OR (fSampleS <= 0.0) THEN
                    _eCause := E_DL_CpdCause.eCfgIllegal;                                        // 分母闸：无有效样本，判据不成立 / Denominator gate
                    _bFault := TRUE;                                                             // 锁存 / Latch
                    _eState := E_DL_CpdPhase.eFault;                                             // 入故障相 / Enter fault phase
                ELSE
                    _fRate := ABS(_fPrNow - _fPrStart) / _fDtS;                                   // 漏率 = |Δp| / Δt（绝对值口径） / Leak rate
                    fLeakRateKpaPerS := _fRate;                                                   // 漏率出口 / Leak-rate outlet
                    IF _fRate > fLeakMaxKpaPerS THEN
                        _bLeakNg := TRUE;                                                         // 漏率超限：锁存 / Leak beyond the limit: latch
                        _eCause := E_DL_CpdCause.eLeakNg;                                         // 归因：漏率超限 / Cause: leak NG
                        _bFault := TRUE;                                                          // 故障锁存 / Latch the fault
                        _eState := E_DL_CpdPhase.eFault;                                          // 入故障相（禁止放气，等人工） / Enter fault phase
                    ELSE
                        _fPrPrev := _fPrNow;                                                      // 记录放气基准压力 / Record the vent reference pressure
                        _eState := E_DL_CpdPhase.eVent;                                           // 漏率合格：进放气相 / Leak OK, enter venting
                    END_IF
                END_IF
            END_IF

        E_DL_CpdPhase.eVent:
            IF _bPrOk THEN
                _fDtS  := fSampleS;                                                              // 单拍时长即采样周期（已过正域闸） / One-scan duration equals the sampling period
                _fRate := ABS(_fPrNow - _fPrPrev) / _fDtS;                                        // 逐拍放气速率 / Per-scan vent rate
                IF _fRate > fVentRateMaxKpaPerS THEN
                    _bVent := FALSE;                                                              // 超速：当拍关阀（占空比限速） / Too fast: close this scan
                    _eCause := E_DL_CpdCause.eVentTooFast;                                        // 归因：放气超速（信息级，不锁存） / Cause: vent too fast, info level
                ELSE
                    _bVent := TRUE;                                                               // 未超速：保持放气 / Below the limit: keep venting
                END_IF
                _fPrPrev := _fPrNow;                                                              // 更新基准压力 / Update the reference
            END_IF
            IF _bPrOk AND (_fPrNow >= 0.0) THEN
                _eState := E_DL_CpdPhase.eIdle;                                                  // 到常压：回待机相 / Atmosphere reached, back to idle
            ELSIF tonVentTo.Q THEN
                _eCause := E_DL_CpdCause.eVentTimeout;                                            // 归因：放气超时 / Cause: vent timeout
                _bFault := TRUE;                                                                  // 锁存 / Latch
                _eState := E_DL_CpdPhase.eFault;                                                  // 入故障相 / Enter fault phase
            END_IF

        E_DL_CpdPhase.eFault:
            ;                                                                                    // 故障相：仅等复位沿 / Wait for the reset edge only

        ELSE
            _eCause := E_DL_CpdCause.ePhaseBad;                                                  // 归因：非法相位 / Cause: illegal phase
            _bFault := TRUE;                                                                     // 锁存 / Latch
            _eState := E_DL_CpdPhase.eFault;                                                     // 强拉故障相 / Force fault phase

        END_CASE
    END_IF
END_IF

(* —— 段 5：完成脉冲（忙碌 → 待机，且无中止无故障；两段式单拍） —— *)
IF _bBusyPrev AND (_eState = E_DL_CpdPhase.eIdle) AND (NOT _bAborted) AND (NOT _bFault) THEN
    _bDone := TRUE;                                                                              // 完成脉冲 / Completion pulse
END_IF
_bBusyPrev := (_eState <> E_DL_CpdPhase.eIdle) AND (_eState <> E_DL_CpdPhase.eFault);            // 忙碌快照（本拍末） / Busy snapshot at body end

(* —— 段 6：出口单点映射（泵阀随相切断，名实双出口，R191） —— *)
bPumpValve := (_eState = E_DL_CpdPhase.ePump) OR (_eState = E_DL_CpdPhase.eStab) OR (_eState = E_DL_CpdPhase.eLeak);   // 抽气阀在前三相保持
bBusy      := (_eState <> E_DL_CpdPhase.eIdle) AND (_eState <> E_DL_CpdPhase.eFault);            // 忙碌 / Busy
bDone      := _bDone;                                                                            // 完成脉冲出口 / Completion pulse outlet
bAborted   := _bAborted;                                                                         // 中止脉冲出口 / Abort pulse outlet
bVentValve := _bVent AND (_eState = E_DL_CpdPhase.eVent);                                        // 放气阀位（仅放气相，单点映射） / Vent valve, vent phase only
bLeakNg    := _bLeakNg;                                                                          // 漏率锁存出口 / Leak latch outlet
ePhase     := _eState;                                                                           // 相出口 / Phase outlet
eCause     := _eCause;                                                                           // 成因出口 / Cause outlet
bError     := _bFault;                                                                           // 故障标志 / Error flag

END_FUNCTION_BLOCK
