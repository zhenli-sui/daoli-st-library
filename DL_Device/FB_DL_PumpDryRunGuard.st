//==============================================================================
// 功能块：FB_DL_PumpDryRunGuard ｜ 中文名称：泵干转保护（双判据 + 防频繁启停）
// 所属子库：DL_Device ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：泵干转保护三段式——判据（功率 < 干转阈 AND 流量 < 干转阈，
//           双判据同时命中才认定干转，单判据只预警）、去抖（双判据持续
//           tTripDebounce 才跳闸）、防频繁启停（跳闸后 tRestartInh 重启
//           抑制窗 + 运行起步 tLearnWin 启动学习窗内不判干转，避开启动
//           瞬态）。同拍多窗配比约束（R100）：tLearnWin < tTripDebounce
//           < tRestartInh——学习窗必须短于去抖窗，否则启动期永不判干转；
//           重启抑制窗为最长的外层窗。
// 开源溯源 (Origin)：道莅原创实现（参考离心泵干转保护工程惯例（功率/流量双判据） 分类与参数域）
// 单位表：功率[千瓦] / 流量[立方米每小时] / 阈值[同量纲] / 时间[ms]
// 错误码表：16#0003_0188 信息级（干转预警：单判据命中或双判据去抖计窗
//           中，不置 bError）/ 16#0003_0189 信息级（重启抑制窗中：跳闸
//           后防频繁启停计时未满，不置 bError）/ 16#0003_035D 故障级
//           （干转跳闸：双判据 + 去抖窗满，锁存，置 bError）/
//           16#0003_035E 故障级（组态非法：阈值 <= 0、时间窗 <= 0 或
//           任一输入非有限，置 bError）/ 16#0003_035F 故障级兜底（状态机
//           落 ELSE 或非法状态，置 bError）
// 状态机：E_DL_PumpGuardState（六态：eIdle=0 / eRunning=10 / eWarn=20 /
//           eTripped=30 / eInhibit=40 / eFault=99），CASE 含 ELSE 兜底，
//           ELSE 置 035F 并断跳闸输出
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 启动学习窗内
//           （运行反馈上升沿起 tLearnWin）不判干转（启动瞬态豁免）；
//           ③ 跳闸锁存：bTripCmd 保持至 bReset 人工复位（抑制窗满回空闲
//           后仍保持，人工确认复位为唯一清除路径，与④一致）；
//           ④ 使能撤销不自动清跳闸锁存（安全侧：干转须人工确认复位）；
//           ⑤ 单判据命中 → eWarn 预警可观测，判据消失自动回运行态；
//           ⑥ 安全侧 = 故障/空闲路径 bTripCmd := FALSE 且 bValid :=
//           FALSE，跳闸输出只在锁存态保持。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §452）
//           v1.0.1 2026-11-17 R24 终审修复（R106 第一档，契约不变）：
//           tTripDebounce 默认 3S 与 tLearnWin 默认 5S 自违反头注释
//           R100 配比约束（学习窗 < 去抖窗 < 抑制窗），默认参数出厂即
//           组态非法 035E——默认去抖窗 3S→8S；边界行为③注释与实现
//           漂移同步修正（锁存仅 bReset 清除）。引脚集合与码位不变。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PumpGuardState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 干转保护相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PumpGuardState :
(
    eIdle     := 0,   // 空闲：泵未运行 / Idle, pump not running
    eRunning  := 10,  // 运行：双判据未命中或学习窗内 / Running, criteria clear or in the learning window
    eWarn     := 20,  // 预警：单判据命中或去抖计窗中 / Warn, one criterion hit or debounce counting
    eTripped  := 30,  // 跳闸：干转锁存，跳闸输出保持 / Tripped, dry-run latched, trip output held
    eInhibit  := 40,  // 抑制：重启抑制窗中（泵已停） / Inhibit, restart window counting, pump stopped
    eFault    := 99   // 故障：组态非法/非法状态 / Fault, illegal config or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_PumpDryRunGuard
VAR_INPUT
    bEnable        : BOOL;                  // 保护使能 [—] / Protection enable
    bReset         : BOOL;                  // 故障复位 [—]，上升沿清跳闸锁存 / Fault reset, rising edge clears the trip latch
    bPumpRunFb     : BOOL;                  // 泵运行反馈 [—] / Pump running feedback
    fMotorPowerKw  : LREAL;                 // 电机功率实测 [千瓦] / Measured motor power [kW]
    fFlowM3h       : LREAL;                 // 流量实测 [立方米每小时] / Measured flow [m3/h]
    fPowerThreshKw : LREAL := 1.0;          // 干转功率阈 [千瓦]，低于此判功率命中，须 > 0 / Dry-run power threshold [kW], must be > 0
    fFlowThreshM3h : LREAL := 0.5;          // 干转流量阈 [立方米每小时]，低于此判流量命中，须 > 0 / Dry-run flow threshold [m3/h], must be > 0
    tTripDebounce  : TIME  := T#8S;         // 双判据去抖窗 [ms]，须 > 0 且 > 学习窗（v1.0.1 默认 3S→8S：原默认 5S 学习窗 > 3S 去抖窗，自违反 R100 配比约束出厂即 035E 故障） / Dual-criteria debounce window [ms], default raised to satisfy learn < debounce < inhibit
    tLearnWin      : TIME  := T#5S;         // 启动学习窗 [ms]，起步瞬态豁免，须 > 0 且 < 去抖窗 / Startup learning window [ms]
    tRestartInh    : TIME  := T#60S;        // 重启抑制窗 [ms]，防频繁启停，须 > 0 且为最长窗 / Restart inhibit window [ms], the longest
END_VAR
VAR_OUTPUT
    bTripCmd       : BOOL;                  // 跳闸指令 [—]（停泵请求，锁存态保持） / Trip command, held while latched
    bRestartBlock  : BOOL;                  // 重启抑制中 [—] / Restart inhibit active
    eState         : E_DL_PumpGuardState;   // 保护相位 [—] / Protection phase
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0003_0188 起信息级、16#0003_035D 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDebounce : TON;                       // 双判据去抖计时（每拍无条件刷新）[ms] / Dual-criteria debounce timer, refreshed unconditionally
    fbLearn    : TON;                       // 启动学习窗计时（每拍无条件刷新）[ms] / Startup learning timer, refreshed unconditionally
    fbInhibit  : TON;                       // 重启抑制窗计时（每拍无条件刷新）[ms] / Restart inhibit timer, refreshed unconditionally
    _eState    : E_DL_PumpGuardState := E_DL_PumpGuardState.eIdle; // 当前相位 / Current phase
    _bCfgBad   : BOOL;                      // 组态非法锁存 / Illegal config latch
    _bTripLatch: BOOL;                      // 干转跳闸锁存 / Dry-run trip latch
    _bRunPrev  : BOOL;                      // 运行反馈上拍电平快照（学习窗起步沿） / Previous-scan level of the run feedback
    _bInfoWarn : BOOL;                      // 预警信息当拍标志 / Warn info flag of this scan
    _bInfoInh  : BOOL;                      // 抑制窗信息当拍标志 / Inhibit info flag of this scan
    _bIllegal  : BOOL;                      // 非法状态标志 / Illegal state flag
    _bInit     : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_PDG_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_PDG_EPS     : LREAL := 1.0E-6;       // 浮点判零容差 [混合] / Float zero tolerance
    DL_PDG_ZERO    : LREAL := 0.0;          // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出安全侧清零，单拍标志预清零
 *      Outputs cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bTripCmd      := FALSE;                  // 跳闸指令先清（锁存态在段 6 重置） / Trip command cleared first
bRestartBlock := FALSE;                  // 抑制标志先清 / Inhibit flag cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoWarn := FALSE;                     // 预警信息预清零 / Warn info pre-cleared
_bInfoInh  := FALSE;                     // 抑制信息预清零 / Inhibit info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_PumpGuardState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad    := FALSE;                  // 组态锁存清零 / Config latch cleared
    _bTripLatch := FALSE;                  // 跳闸锁存清零 / Trip latch cleared
    _bRunPrev   := FALSE;                  // 运行快照清零 / Run snapshot cleared
    _bInit      := TRUE;                   // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 阈值/时间窗物理域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fMotorPowerKw <> fMotorPowerKw) OR (ABS(fMotorPowerKw) > DL_PDG_INF)
   OR (fFlowM3h <> fFlowM3h) OR (ABS(fFlowM3h) > DL_PDG_INF)
   OR (fPowerThreshKw <> fPowerThreshKw) OR (ABS(fPowerThreshKw) > DL_PDG_INF)
   OR (fFlowThreshM3h <> fFlowThreshM3h) OR (ABS(fFlowThreshM3h) > DL_PDG_INF) THEN
    _bCfgBad := TRUE;                      // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fPowerThreshKw <= DL_PDG_EPS) OR (fFlowThreshM3h <= DL_PDG_EPS)
   OR (tTripDebounce <= T#0MS) OR (tLearnWin <= T#0MS) OR (tRestartInh <= T#0MS)
   OR (tLearnWin >= tTripDebounce) OR (tTripDebounce >= tRestartInh)) THEN
    _bCfgBad := TRUE;                      // 阈值/时间窗非法锁存（含 R100 配比约束：学习窗 < 去抖窗 < 抑制窗） / Threshold and window domains latched with the R100 ratio rule
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜三只计时无条件刷新（R40：CASE 之外每拍必调）
 *      Three timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbDebounce(IN := ((_eState = E_DL_PumpGuardState.eRunning)
                OR (_eState = E_DL_PumpGuardState.eWarn))
           AND (fMotorPowerKw < fPowerThreshKw)
           AND (fFlowM3h < fFlowThreshM3h),
           PT := tTripDebounce);           // 双判据去抖窗（条件含双判据命中） / Debounce window, conditioned on the dual criteria
fbLearn(IN := (_eState = E_DL_PumpGuardState.eRunning)
             OR (_eState = E_DL_PumpGuardState.eWarn),
        PT := tLearnWin);                  // 启动学习窗 / Startup learning window
fbInhibit(IN := (_eState = E_DL_PumpGuardState.eInhibit), PT := tRestartInh); // 重启抑制窗 / Restart inhibit window

(*------------------------------------------------------------------------------
 * 段 5｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_PumpGuardState.eIdle:             // 空闲：运行反馈进运行态
        IF bPumpRunFb AND (NOT _bCfgBad) AND bEnable THEN
            _eState := E_DL_PumpGuardState.eRunning; // 进运行 / To running
        END_IF

    E_DL_PumpGuardState.eRunning:          // 运行：学习窗内豁免；判据命中进预警
        IF (NOT bPumpRunFb) OR (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_PumpGuardState.eIdle; // 前置消失回空闲（eWait 类双条件之一） / Precondition gone, back to idle
        ELSIF NOT fbLearn.Q THEN
            _eState := _eState;            // 学习窗内：豁免期不动（显式自持） / Learning window, state held (explicit self-hold)
        ELSIF (fMotorPowerKw < fPowerThreshKw) AND (fFlowM3h < fFlowThreshM3h) THEN
            _bInfoWarn := TRUE;            // 双判据已命中，进预警（拍 N 进入） / Dual criteria hit, to warn
            _eState := E_DL_PumpGuardState.eWarn; // 进预警 / To warn
        ELSIF (fMotorPowerKw < fPowerThreshKw) OR (fFlowM3h < fFlowThreshM3h) THEN
            _bInfoWarn := TRUE;            // 单判据预警（信息级） / Single-criterion warn, info level
        END_IF

    E_DL_PumpGuardState.eWarn:             // 预警：去抖窗满跳闸；判据消失回运行
        IF (NOT bPumpRunFb) OR (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_PumpGuardState.eIdle; // 前置消失回空闲 / Precondition gone, back to idle
        ELSIF (fMotorPowerKw >= fPowerThreshKw) AND (fFlowM3h >= fFlowThreshM3h) THEN
            _eState := E_DL_PumpGuardState.eRunning; // 判据消失回运行 / Criteria cleared, back to running
        ELSIF fbDebounce.Q THEN
            _bTripLatch := TRUE;           // 干转跳闸锁存 / Dry-run trip latched
            _eState := E_DL_PumpGuardState.eTripped; // 进跳闸态 / To tripped
        END_IF

    E_DL_PumpGuardState.eTripped:          // 跳闸：输出保持；运行反馈撤销进抑制窗
        IF NOT bPumpRunFb THEN
            _eState := E_DL_PumpGuardState.eInhibit; // 进抑制窗（泵已停） / To inhibit, pump stopped
        END_IF

    E_DL_PumpGuardState.eInhibit:          // 抑制：抑制窗满回空闲（bReset 才清锁存）
        _bInfoInh := TRUE;                 // 抑制窗中（信息级） / Inhibit window active, info
        IF fbInhibit.Q THEN
            _eState := E_DL_PumpGuardState.eIdle; // 抑制窗满回空闲 / Inhibit elapsed, back to idle
        END_IF

    E_DL_PumpGuardState.eFault:            // 故障：复位沿且组态恢复回空闲
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_PumpGuardState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_PumpGuardState.eFault; // 回故障态 / Back to fault
END_CASE
IF bReset THEN
    _bTripLatch := FALSE;                  // 复位清跳闸锁存（人工确认） / Reset clears the trip latch, manual confirmation
END_IF
_bRunPrev := bPumpRunFb;                   // 运行快照推进 / Run snapshot advanced

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_035F;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0003_035E;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bTripLatch THEN
    eErr   := 16#0003_035D;                // 故障级：干转跳闸锁存 / Fault: dry-run trip latched
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoInh THEN
    eErr := 16#0003_0189;                  // 信息级：重启抑制窗中 / Info: restart inhibit active
ELSIF _bInfoWarn THEN
    eErr := 16#0003_0188;                  // 信息级：干转预警 / Info: dry-run warn
END_IF

bTripCmd := _bTripLatch;                   // 跳闸输出 = 锁存量（不挂单拍标志，R99） / Trip output equals the latch, not a one-shot flag
bRestartBlock := (_eState = E_DL_PumpGuardState.eInhibit); // 抑制中出口 / Inhibit outlet
bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_PumpGuardState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
eState := _eState;                         // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
