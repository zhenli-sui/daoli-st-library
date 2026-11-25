//==============================================================================
// 功能块：FB_DL_ElectrolyzerStackPurgeSeq ｜ 中文名称：电解槽氮气吹扫与升压序（复杂度 C4）
// 所属子库：DL_Process ｜ 版本 VERSION: v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：电解槽停机检修后的投运前置序——低压氮气保压检漏 → N2 置换吹扫（按置换
//           倍数 n = ln(C0/C1) 算所需体积）→ O2 校验 → 升压至运行压力 → 就绪放行
//           （H2 侧仅在就绪相且 O2 合格时才允许打开）→ 泄压走 eVent 单向。泄漏率超
//           限、吹扫/升压超时、O2 不合格一律不放行并锁存故障。
// 开源溯源 (Origin)：道莅原创实现（参考 ISO 22734 水电解制氢系统与 GB/T 19774 水
//           电解制氢系统技术要求 分类与参数域，许可证=MIT，借鉴点=「惰性气体置换至
//           爆炸下限以下再投氢」的置换倍数判据与硬互锁序）
// 单位表：O2[%] / 压力[bar] / 流量[Nm³/h] / 体积[Nm³] / 泄漏率[bar/min] / 时间[ms]
// 置换倍数公式（本件核心判据，单位与推导写清）：
//   n = ln(C0 / C1)；C0 = 空气 O2 体积分数 20.9 [%]，C1 = 目标 O2 阈值 1.0 [%]
//   → n = ln(20.9 / 1.0) ≈ 3.04 [倍]，即需通入约 3.04 倍栈容积的 N2。
//   累计 N2 体积 [Nm³] = Σ (fN2FlowNm3h ÷ 3600 × Δt[s])，Δt 取 DL_ELZ_DT_S 假定任务
//   周期 10 ms；置换倍数出口 = 累计体积 ÷ 栈容积 [倍]。除零由段 3/段 4 双侧闸拦。
// 错误码表（Process 段 0005，故障窗口 3F01~3F09，信息窗口 3F81/3F82）：
//   16#0005_3F01 故障级：组态非法（栈容积/目标压/泄漏限/时间量 <= 0 或 O2 阈值域外）
//   16#0005_3F02 故障级：实时量入口非有限（O2 / 压力 / 流量 NaN 或 Inf），拒算
//   16#0005_3F03 故障级：检修保压检漏超限（泄漏率 > fLeakLimitBarPerMin，不放行）
//   16#0005_3F04 故障级：吹扫超时（tPurgeMaxTime 内置换倍数未达 n）
//   16#0005_3F05 故障级：O2 校验失败（校验窗内 O2 未降至阈值以下）
//   16#0005_3F06 故障级：升压超时（预充压或正式升压未达目标压）
//   16#0005_3F07 故障级：投运前保压检漏超限（就绪相保压窗内泄漏率超限，不放行）
//   16#0005_3F08 故障级兜底：状态机落 ELSE 非法态，全输出断
//   16#0005_3F09 故障级：H2 硬互锁违反（就绪相 O2 回升超阈值，立即关 H2 并锁存）
//   16#0005_3F81 信息级：置换倍数达标（置换完成拍，不置 bError）
//   16#0005_3F82 信息级：系统就绪放行（进入 eReady 拍，不置 bError）
//           故障级码全部锁存回放（R187），唯一清除路径 = bReset 上升沿。
// 状态机：E_DL_ElyzPurgeState（八态：eIdle=0 / eLeakTest=10 / ePurge=20 / eVerifyO2=30 /
//           ePressurize=40 / eReady=50 / eVent=60 / eFault=99）。eVent 为单向泄压相，
//           迁出唯一目标 = eIdle，不得返回 eReady（防止带氢泄压后直接投运）。
// 边界行为：① H2 侧硬互锁三重闸：相位必须是 eReady、O2 <= 阈值、无任何故障锁存；段 8
//           的 CASE ELSE 与出口断言各断一次（双保险）；② O2 未达标绝不进 eReady，故
//           不可能放 H2；③ 泄漏率判据只用「>」单侧直比（泄漏率本身是统计量，不设容差
//           死区，避免漏判）；④ 八态 CASE 每态显式 + ELSE 兜底 → 3F08 全断；⑤ 中止在
//           任何运行相都只迁入 eVent（单向泄压），不走「原地停机」路径。
// 语义假设：① fO2Pct 为栈内气相 O2 体积分数，单位 %；② fLeakDropBarPerMin 由上层
//           压降速率仪表或本库泄漏率估算件提供（本件不重复实现估算）；③ N2 流量为
//           标况体积流量，压力对体积的修正由上层完成；④ 栈容积含管路死体积。
// 依赖纪律：仅 Standard.library（TON / R_TRIG / LN）；零 GVL、零 VAR_EXTERNAL、零物
//           理地址直连，业务侧只经引脚注入。
// 修订历史：v1.0.0 2026-11-25 R88 首版（无人值守批次 · 复杂件 C4 · 序号 3）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_ElyzPurgeState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 吹扫升压相位，与段 7 状态机、段 8 输出置位一一对应。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_ElyzPurgeState :
(
    eIdle       := 0,  // 空闲：等启动沿 / Idle, awaiting the start edge
    eLeakTest   := 10, // 检修检漏：低压氮气保压测泄漏率 / Leak test at low nitrogen pressure
    ePurge      := 20, // 吹扫：N2 置换至置换倍数达标 / Purge until the exchange ratio is reached
    eVerifyO2   := 30, // O2 校验：静置取样，O2 须稳定在阈值下 / O2 verification with a stable sample
    ePressurize := 40, // 升压：N2 升至运行压力 / Pressurise to the operating pressure
    eReady      := 50, // 就绪：放行相，H2 侧唯一允许投运的相位 / Ready, the only phase allowing H2
    eVent       := 60, // 泄压：单向排空至常压 / Vent, one-way depressurisation
    eFault      := 99  // 故障：泄漏/超时/O2/互锁/非法态 / Fault, leak, timeout, O2, interlock or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrolyzerStackPurgeSeq
VAR_INPUT
    xEnable             : BOOL;   // 使能，FALSE 期间按中止处理（转泄压） [—] / Enable, a drop aborts into venting
    xStart              : BOOL;   // 启动请求，上升沿生效 [—] / Start request, rising edge effective
    xAbort              : BOOL;   // 中止请求，任意拍生效，转 eVent 单向泄压 [—] / Abort request, moves to one-way venting
    xReset              : BOOL;   // 故障复位，上升沿清全部锁存 [—] / Fault reset, rising edge clears all latches
    fO2Pct              : LREAL;  // 栈内气相 O2 体积分数 [%] / Gas-phase O2 volume fraction [%]
    fStackPressBar      : LREAL;  // 栈内实际压力 [bar] / Actual stack pressure [bar]
    fTargetPressBar     : LREAL;  // 运行目标压力 [bar]，须 > 0 / Operating target pressure [bar]
    fN2FlowNm3h         : LREAL;  // 氮气标况流量 [Nm³/h] / Nitrogen normal-volume flow [Nm3/h]
    fStackVolM3         : LREAL;  // 栈与管路总容积 [Nm³]，须 > 0 / Total stack and piping volume [Nm3]
    fLeakDropBarPerMin  : LREAL;  // 实测压力下降速率 [bar/min] / Measured pressure decay rate [bar/min]
    fLeakLimitBarPerMin : LREAL;  // 允许泄漏率上限 [bar/min]，须 > 0 / Allowed leak rate ceiling [bar/min]
    tPurgeMaxTime       : TIME;   // 吹扫最长允许时间 [ms] / Maximum purge time [ms]
    tHoldTime           : TIME;   // 保压/取样稳定窗 [ms] / Hold and sampling window [ms]
    tPressTimeout       : TIME;   // 升压与预充压超时 [ms] / Pressurisation timeout [ms]
END_VAR
VAR_OUTPUT
    xN2ValveCmd         : BOOL;   // 氮气进气阀命令 [—] / Nitrogen inlet valve command
    xVentValveCmd       : BOOL;   // 排放阀命令（吹扫出口与泄压共用） [—] / Vent valve command
    xH2ValveCmd         : BOOL;   // 氢气侧阀命令（仅就绪相且 O2 合格才允许） [—] / H2 valve, ready phase and O2 proven only
    bRunning            : BOOL;   // 顺控运行中（非空闲非就绪非故障非泄压） [—] / Sequencing active
    bDone               : BOOL;   // 就绪放行电平（eReady 相） [—] / Ready-released level in the eReady phase
    bError              : BOOL;   // 故障级标志，仅故障级码置位 [—] / Fault-class flag, fault-level codes only
    nErrCode            : UDINT;  // 错误码，0 = 无错 [—] / Error code, 0 = none
    fPurgeVolRatio      : LREAL;  // 置换倍数出口 [倍] = 累计 N2 体积 ÷ 栈容积 / Exchange ratio [ratio]
    nPurgeCount         : UDINT;  // 累计吹扫次数 [次] / Accumulated purge count
END_VAR
VAR
    _eState             : E_DL_ElyzPurgeState := E_DL_ElyzPurgeState.eIdle; // 当前相位 [—] / Current phase
    _bInit              : BOOL := FALSE; // 首扫标志，取非判定 [—] / First-scan flag, tested negated
    _fPurgeVolNm3       : LREAL;         // 累计通入氮气体积 [Nm³] / Accumulated nitrogen volume [Nm3]
    _fReqRatioN         : LREAL;         // 所需置换倍数 n = ln(C0/C1) [倍] / Required exchange ratio n [ratio]
    _fPurgeVolRatio     : LREAL;         // 本拍置换倍数 [倍] / Exchange ratio of this scan [ratio]
    _nPurgeCount        : UDINT;         // 内部累计吹扫次数 [次] / Internal purge counter
    _bCfgBad            : BOOL;          // 组态非法锁存 / Illegal configuration latch
    _bCfgOk             : BOOL;          // 本拍组态合法（派生量不锁存） [—] / Configuration legal this scan, derived
    _bSigBad            : BOOL;          // 实时量非有限锁存 / Non-finite process value latch
    _bLeakErr           : BOOL;          // 检修检漏超限锁存 / Commissioning leak-test latch
    _bPurgeTmo          : BOOL;          // 吹扫超时锁存 / Purge timeout latch
    _bO2Err             : BOOL;          // O2 校验失败锁存 / O2 verification failure latch
    _bPressTmo          : BOOL;          // 升压超时锁存 / Pressurisation timeout latch
    _bLeakReadyErr      : BOOL;          // 投运前检漏超限锁存 / Pre-start leak-test latch
    _bH2LockErr         : BOOL;          // H2 互锁违反锁存 / H2 interlock violation latch
    _bIllegal           : BOOL;          // 非法状态标志 / Illegal state flag
    _bInfoRatio         : BOOL;          // 置换达标信息当拍标志 / Ratio-reached info flag of this scan
    _bInfoReady         : BOOL;          // 就绪放行信息当拍标志 / Ready info flag of this scan
    _bAbortReq          : BOOL;          // 中止请求合成（xAbort 或失能） [—] / Combined abort request
    _bO2Ok              : BOOL;          // O2 合格判据（派生量） [—] / O2 proven criterion, derived
    _bH2Permit          : BOOL;          // H2 投运许可（三重闸合成） [—] / H2 permit, three gates combined
    rtStart             : R_TRIG;        // 启动沿，段 6 无条件刷新 [—] / Start edge, refreshed in segment 6
    rtReset             : R_TRIG;        // 复位沿，段 6 无条件刷新 [—] / Reset edge, refreshed in segment 6
    tonLeakFill         : TON;           // 检修预充压超时 [ms] / Commissioning pre-fill timeout [ms]
    tonHold             : TON;           // 检修保压窗 [ms] / Commissioning hold window [ms]
    tonPurgeMax         : TON;           // 吹扫最长允许时间 [ms] / Maximum purge time [ms]
    tonO2Win            : TON;           // O2 合格稳定窗 [ms] / O2 stability window [ms]
    tonO2Max            : TON;           // O2 校验最长等待 [ms] / Maximum O2 verification wait [ms]
    tonPress            : TON;           // 升压超时 [ms] / Pressurisation timeout [ms]
    tonReadyHold        : TON;           // 就绪相保压窗 [ms] / Ready-phase hold window [ms]
END_VAR
VAR CONSTANT
    DL_EPS                : LREAL := 1.0E-9;  // 浮点容差零点，兼作除法分母下限 / Float epsilon, also the divisor floor
    DL_ELZ_O2_AIR_PCT     : LREAL := 20.9;    // 空气 O2 体积分数 C0 [%] / O2 fraction of air C0 [%]
    DL_ELZ_O2_LIMIT_PCT   : LREAL := 1.0;     // 投运前 O2 阈值 C1 [%] / O2 limit before start-up C1 [%]
    DL_ELZ_SEC_PER_H      : LREAL := 3600.0;  // 小时折算秒 [s/h]，流量积分用 / Seconds per hour for the flow integral
    DL_ELZ_DT_S           : LREAL := 0.01;    // 体积积分假定任务周期 [s]（10 ms） / Assumed task period for the volume integral [s]
    DL_ELZ_LEAK_PRESS_BAR : LREAL := 2.0;     // 检修检漏预充压 [bar] / Commissioning leak-test pressure [bar]
    DL_ELZ_PRESS_TOL_BAR  : LREAL := 0.5;     // 升压到位容差 [bar] / Pressurisation tolerance [bar]
    DL_ELZ_VENT_DONE_BAR  : LREAL := 0.20;    // 泄压完成阈值 [bar] / Vent completion threshold [bar]
    DL_ELZ_PRESS_MAX_BAR  : LREAL := 400.0;   // 压力反馈合法幅值上限 [bar] / Legal pressure ceiling [bar]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：全部输出先落安全侧（H2 阀优先断），单拍标志预清零
 *      All outputs preset to the safe side, the H2 valve first, one-shot flags cleared
 *-----------------------------------------------------------------------------*)
xH2ValveCmd := FALSE;                       // 氢气阀先断（最高优先级安全侧） / H2 valve cleared first
xN2ValveCmd := FALSE; xVentValveCmd := FALSE; // 氮气与排放阀先断 / Nitrogen and vent valves cleared
bRunning := FALSE;  bDone := FALSE;         // 运行与就绪标志每拍重算 / Running and ready flags recomputed
bError := FALSE;    nErrCode := 16#0000_0000; // 故障标志与错误码每拍重算 / Fault flag and code recomputed
_bIllegal := FALSE; _bInfoRatio := FALSE; _bInfoReady := FALSE; // 非法态与两条信息标志预清零 / Illegal and info flags pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：所需置换倍数 n = ln(C0/C1) 只算一次，计数与体积清零
 *      First-scan initialisation, the required ratio n computed once
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_ElyzPurgeState.eIdle; // 相位从空闲起步 / Phase starts idle
    _fPurgeVolNm3 := 0.0;  _nPurgeCount := 0; // 累计体积与吹扫次数清零 / Volume and purge counter at zero
    _fReqRatioN := 0.0;                       // 置换倍数先清零 / Required ratio starts at zero
    IF DL_ELZ_O2_LIMIT_PCT > DL_EPS THEN
        _fReqRatioN := LN(DL_ELZ_O2_AIR_PCT / DL_ELZ_O2_LIMIT_PCT); // n = ln(C0/C1) ≈ 3.04 [倍]，除数已判零 / Ratio n, divisor already proven
    END_IF
    _bInit := TRUE;                           // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜实时量入口非有限闸 + 组态闸（O2 阈值域闸与除零闸并列）
 *      Non-finite inlet gate and configuration gates
 *-----------------------------------------------------------------------------*)
IF NOT (fO2Pct > -1.0E30 AND fO2Pct < 1.0E30) THEN _bSigBad := TRUE; END_IF            // O2 非有限 → 3F02 / Non-finite O2, 3F02
IF NOT (fStackPressBar > -1.0E30 AND fStackPressBar < 1.0E30) THEN _bSigBad := TRUE; END_IF // 压力非有限 → 3F02 / Non-finite pressure, 3F02
IF ABS(fStackPressBar) > DL_ELZ_PRESS_MAX_BAR THEN _bSigBad := TRUE; END_IF             // 压力幅值超上限 → 3F02 / Beyond the ceiling, 3F02
IF NOT (fN2FlowNm3h > -1.0E30 AND fN2FlowNm3h < 1.0E30) OR (fN2FlowNm3h < 0.0) THEN _bSigBad := TRUE; END_IF // 流量非有限或负值 → 3F02 / Non-finite or negative flow, 3F02
IF NOT (fStackVolM3 > -1.0E30 AND fStackVolM3 < 1.0E30) THEN _bCfgBad := TRUE; END_IF   // 栈容积非有限 → 3F01 / Non-finite volume, 3F01
IF NOT (fTargetPressBar > -1.0E30 AND fTargetPressBar < 1.0E30) THEN _bCfgBad := TRUE; END_IF // 目标压非有限 → 3F01 / Non-finite target, 3F01
IF (fStackVolM3 <= DL_EPS) OR (fTargetPressBar <= DL_EPS) OR (fLeakLimitBarPerMin <= DL_EPS) THEN _bCfgBad := TRUE; END_IF // 三者须为正 → 3F01 / All three must be positive
IF NOT (fLeakDropBarPerMin > -1.0E30 AND fLeakDropBarPerMin < 1.0E30) THEN _bSigBad := TRUE; END_IF // 泄漏率非有限 → 3F02（R88 修复：原漏项致 NaN 判合格） / non-finite leak rate, 3F02
IF (fO2Pct < 0.0) OR (fO2Pct > 100.0) THEN _bSigBad := TRUE; END_IF                    // O2 超出 0~100% 域 → 3F02 / O2 outside 0..100, 3F02
IF (tPurgeMaxTime <= T#0MS) OR (tHoldTime <= T#0MS) OR (tPressTimeout <= T#0MS) THEN _bCfgBad := TRUE; END_IF // 时间量须为正 → 3F01 / Time values must be positive
_bCfgOk := NOT _bCfgBad;                    // 本拍组态合法派生量 / Configuration-legal derived flag of this scan
_bO2Ok  := (fO2Pct <= DL_ELZ_O2_LIMIT_PCT) AND (NOT _bSigBad); // O2 合格判据（非有限时不判合格） / O2 proven unless non-finite

(*------------------------------------------------------------------------------
 * 段 4｜吹扫体积积分与置换倍数（除零双侧闸：栈容积与秒折算均先判分母）
 *      Purge volume integral and the exchange ratio, both divisors proven first
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_ElyzPurgeState.ePurge) AND (NOT _bCfgBad) THEN
    IF DL_ELZ_SEC_PER_H > DL_EPS THEN
        _fPurgeVolNm3 := _fPurgeVolNm3 + (fN2FlowNm3h / DL_ELZ_SEC_PER_H) * DL_ELZ_DT_S; // 体积积分 [Nm³] / Volume integral [Nm3]
    END_IF
END_IF
_fPurgeVolRatio := 0.0;                     // 置换倍数先清零 / Exchange ratio pre-cleared
IF fStackVolM3 > DL_EPS THEN
    _fPurgeVolRatio := _fPurgeVolNm3 / fStackVolM3; // 置换倍数 [倍] = 累计体积 ÷ 栈容积 / Ratio = volume over stack volume
END_IF
fPurgeVolRatio := _fPurgeVolRatio;          // 置换倍数出口 [倍] / Exchange ratio outlet [ratio]

(*------------------------------------------------------------------------------
 * 段 5｜中止入口（任意运行相 → eVent 单向泄压）与复位
 *      Abort entry into one-way venting plus the reset edge
 *-----------------------------------------------------------------------------*)
_bAbortReq := xAbort OR (NOT xEnable);      // 中止请求合成：显式中止或失能 / Combined abort: explicit abort or enable loss
IF _bAbortReq AND (_eState <> E_DL_ElyzPurgeState.eIdle)
   AND (_eState <> E_DL_ElyzPurgeState.eVent) AND (_eState <> E_DL_ElyzPurgeState.eFault) THEN
    _eState := E_DL_ElyzPurgeState.eVent;   // 转单向泄压相（禁原地停机） / Move to one-way venting, never a plain stop
END_IF
IF rtReset.Q THEN
    _bCfgBad := FALSE;  _bSigBad := FALSE;  _bLeakErr := FALSE; // 复位清组态/入口/检漏锁存 / Clears configuration, inlet and leak latches
    _bPurgeTmo := FALSE; _bO2Err := FALSE; _bPressTmo := FALSE;  // 复位清吹扫/校验/升压锁存 / Clears purge, O2 and pressure latches
    _bLeakReadyErr := FALSE; _bH2LockErr := FALSE;               // 复位清投运检漏与互锁锁存 / Clears pre-start leak and interlock latches
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜定时器与边沿无条件周期刷新（R7：CASE 之外每拍必调，各司其职不复用）
 *      Timers and edges refreshed unconditionally every scan, outside the CASE
 *-----------------------------------------------------------------------------*)
rtStart(CLK := xStart); rtReset(CLK := xReset); // 启动沿与复位沿无条件刷新 / Start and reset edges refreshed
tonLeakFill(IN := (_eState = E_DL_ElyzPurgeState.eLeakTest) AND (fStackPressBar < DL_ELZ_LEAK_PRESS_BAR), PT := tPressTimeout); // 检修预充压超时
tonHold(IN := (_eState = E_DL_ElyzPurgeState.eLeakTest) AND (fStackPressBar >= DL_ELZ_LEAK_PRESS_BAR), PT := tHoldTime);       // 检修保压窗
tonPurgeMax(IN := (_eState = E_DL_ElyzPurgeState.ePurge), PT := tPurgeMaxTime);   // 吹扫最长允许时间 / Maximum purge time
tonO2Win(IN := (_eState = E_DL_ElyzPurgeState.eVerifyO2) AND _bO2Ok, PT := tHoldTime); // O2 合格稳定窗 / O2 stability window
tonO2Max(IN := (_eState = E_DL_ElyzPurgeState.eVerifyO2), PT := tPurgeMaxTime);       // O2 校验最长等待 / Maximum O2 wait
tonPress(IN := (_eState = E_DL_ElyzPurgeState.ePressurize), PT := tPressTimeout);     // 升压超时 / Pressurisation timeout
tonReadyHold(IN := (_eState = E_DL_ElyzPurgeState.eReady), PT := tHoldTime);          // 就绪相保压窗 / Ready hold window

(*------------------------------------------------------------------------------
 * 段 7｜状态机（每态显式迁移判据，ELSE 兜底落故障）
 *      Phase machine with explicit transition criteria and an ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_ElyzPurgeState.eIdle:              // 空闲：启动沿 + 组态合法 + 入口可用才进检漏 / Idle, legal start edge only
        IF rtStart.Q AND _bCfgOk AND (NOT _bSigBad) AND (NOT _bAbortReq) THEN
            _fPurgeVolNm3 := 0.0;           // 新循环体积清零 / Volume reset for the new cycle
            _eState := E_DL_ElyzPurgeState.eLeakTest; // 进检修检漏相 / To the leak-test phase
        END_IF
    E_DL_ElyzPurgeState.eLeakTest:          // 检修检漏：保压窗满判泄漏率，超限不放行 / Leak rate judged at the end of the hold
        IF (fStackPressBar < DL_ELZ_LEAK_PRESS_BAR) AND tonLeakFill.Q THEN
            _bPressTmo := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 预充压超时 → 3F06 / Pre-fill timeout, 3F06
        ELSIF tonHold.Q THEN
            IF NOT (fLeakDropBarPerMin <= fLeakLimitBarPerMin) THEN // fail-closed：非有限时 NOT(FALSE)=TRUE 即判超限（R88 修复）
                _bLeakErr := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 泄漏率超限 → 3F03 / Leak over limit, 3F03
            ELSE
                _eState := E_DL_ElyzPurgeState.ePurge; // 检漏合格，进吹扫相 / Leak proven, to purge
            END_IF
        END_IF
    E_DL_ElyzPurgeState.ePurge:             // 吹扫：置换倍数达 n 即完成，超时落故障 / Purge until the ratio reaches n
        IF _fPurgeVolRatio >= _fReqRatioN THEN
            _nPurgeCount := _nPurgeCount + 1;  // 吹扫次数递增 / Purge counter incremented
            _bInfoRatio  := TRUE;              // 置换达标信息 / Ratio-reached info
            _eState      := E_DL_ElyzPurgeState.eVerifyO2; // 进 O2 校验相 / To O2 verification
        ELSIF tonPurgeMax.Q THEN
            _bPurgeTmo := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 吹扫超时 → 3F04 / Purge timeout, 3F04
        END_IF
    E_DL_ElyzPurgeState.eVerifyO2:          // O2 校验：稳定窗满即合格，最长等待到则失败 / Stable window or maximum wait
        IF tonO2Win.Q THEN
            _eState := E_DL_ElyzPurgeState.ePressurize; // O2 合格稳定，进升压相 / O2 proven, to pressurise
        ELSIF tonO2Max.Q THEN
            _bO2Err := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 校验失败 → 3F05 / Verification failed, 3F05
        END_IF
    E_DL_ElyzPurgeState.ePressurize:        // 升压：达目标压容差即就绪，超时落故障 / Pressurise to the target band
        IF fStackPressBar >= (fTargetPressBar - DL_ELZ_PRESS_TOL_BAR) THEN
            _bInfoReady := TRUE;            // 就绪放行信息 / Ready info
            _eState     := E_DL_ElyzPurgeState.eReady; // 进就绪相 / To the ready phase
        ELSIF tonPress.Q THEN
            _bPressTmo := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 升压超时 → 3F06 / Pressurisation timeout, 3F06
        END_IF
    E_DL_ElyzPurgeState.eReady:             // 就绪：O2 回升即互锁故障；保压窗满判泄漏；启动撤销回空闲
        IF NOT _bO2Ok THEN
            _bH2LockErr := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // O2 回升，H2 互锁违反 → 3F09 / O2回升, 3F09
        ELSIF tonReadyHold.Q AND (NOT (fLeakDropBarPerMin <= fLeakLimitBarPerMin)) THEN // fail-closed 同判据（R88 修复）
            _bLeakReadyErr := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 投运前检漏超限 → 3F07 / Pre-start leak, 3F07
        ELSIF tonReadyHold.Q AND (NOT xStart) THEN
            _eState := E_DL_ElyzPurgeState.eIdle; // 就绪撤销且检漏合格，回空闲 / Ready withdrawn and leak proven, idle
        END_IF
    E_DL_ElyzPurgeState.eVent:              // 泄压：单向排空至阈值以下才回空闲 / Vent one-way, idle below the threshold
        IF fStackPressBar <= DL_ELZ_VENT_DONE_BAR THEN _eState := E_DL_ElyzPurgeState.eIdle; END_IF
    E_DL_ElyzPurgeState.eFault:             // 故障：复位沿且组态合法且入口可用才回空闲 / Fault, reset edge only
        IF rtReset.Q AND _bCfgOk AND (NOT _bSigBad) THEN _eState := E_DL_ElyzPurgeState.eIdle; END_IF
    ELSE                                    // 非法状态兜底（R6：CASE 必带 ELSE）/ Illegal-state fallback
        _bIllegal := TRUE; _eState := E_DL_ElyzPurgeState.eFault; // 非法态 → 3F08，落故障 / Illegal state, 3F08
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜输出置位（H2 侧三重闸 + 出口断言双保险；泄压相只开排放阀）
 *      Output assignment, H2 gated threefold with a second outlet assertion
 *-----------------------------------------------------------------------------*)
_bH2Permit := (_eState = E_DL_ElyzPurgeState.eReady) AND _bO2Ok AND (NOT _bAbortReq)
              AND (NOT _bH2LockErr) AND (NOT _bLeakReadyErr); // H2 许可三重闸：相位 + O2 + 无故障 / Three gates: phase, O2, no fault
CASE _eState OF
    E_DL_ElyzPurgeState.eLeakTest:          // 检修检漏：未达预充压才开 N2，排放阀关 / Fill nitrogen until the test pressure
        xN2ValveCmd := (fStackPressBar < DL_ELZ_LEAK_PRESS_BAR); // 达压即关氮气 / Nitrogen closed once at pressure
    E_DL_ElyzPurgeState.ePurge:             // 吹扫：氮气进、排放出，双向流路 / Purge with both inlet and vent open
        xN2ValveCmd := TRUE; xVentValveCmd := TRUE; // 进气与排放同开 / Inlet and vent both open
    E_DL_ElyzPurgeState.eVerifyO2:          // O2 校验：静置取样，两阀均关 / Verification with both valves closed
        xN2ValveCmd := FALSE; xVentValveCmd := FALSE; // 静态取样 / Static sampling
    E_DL_ElyzPurgeState.ePressurize:        // 升压：只开氮气，排放阀必须关 / Pressurise with the vent closed
        xN2ValveCmd := TRUE; xVentValveCmd := FALSE; // 关排放防漏压 / Vent closed to hold pressure
    E_DL_ElyzPurgeState.eReady:             // 就绪：只允许 H2（严格由三重闸决定） / Ready, H2 by the three gates only
        xH2ValveCmd := _bH2Permit;          // H2 阀由许可位驱动 / H2 valve driven by the permit
    E_DL_ElyzPurgeState.eVent:              // 泄压：只开排放阀，N2 与 H2 全关 / Vent only, nitrogen and H2 closed
        xVentValveCmd := TRUE;
    ELSE                                    // 其余相（空闲/故障）全断 / Other phases, all off
        xN2ValveCmd := FALSE; xVentValveCmd := FALSE; xH2ValveCmd := FALSE; // 全阀断 / All valves off
END_CASE
IF NOT _bH2Permit THEN
    xH2ValveCmd := FALSE;                   // 出口断言：许可不成立时 H2 必须为 FALSE / Outlet assertion, H2 false without a permit
END_IF
bRunning := (_eState <> E_DL_ElyzPurgeState.eIdle) AND (_eState <> E_DL_ElyzPurgeState.eReady)
            AND (_eState <> E_DL_ElyzPurgeState.eVent) AND (_eState <> E_DL_ElyzPurgeState.eFault); // 运行标志
bDone := (_eState = E_DL_ElyzPurgeState.eReady); nPurgeCount := _nPurgeCount; // 就绪放行电平与吹扫次数出口 / Ready level and purge count

(*------------------------------------------------------------------------------
 * 段 9｜错误码映射（锁存回放，R187：故障相不按当下输入重推断）
 *      Error-code map, latched replay
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN nErrCode := 16#0005_3F08; bError := TRUE;        // 故障级兜底：非法态 / Fault, illegal state fallback
ELSIF _bCfgBad THEN nErrCode := 16#0005_3F01; bError := TRUE;      // 故障级：组态非法 / Fault, illegal configuration
ELSIF _bSigBad THEN nErrCode := 16#0005_3F02; bError := TRUE;      // 故障级：入口非有限 / Fault, non-finite inlet
ELSIF _bH2LockErr THEN nErrCode := 16#0005_3F09; bError := TRUE;   // 故障级：H2 硬互锁违反 / Fault, H2 interlock violated
ELSIF _bLeakErr THEN nErrCode := 16#0005_3F03; bError := TRUE;     // 故障级：检修检漏超限 / Fault, commissioning leak
ELSIF _bLeakReadyErr THEN nErrCode := 16#0005_3F07; bError := TRUE; // 故障级：投运前检漏超限 / Fault, pre-start leak
ELSIF _bPurgeTmo THEN nErrCode := 16#0005_3F04; bError := TRUE;    // 故障级：吹扫超时 / Fault, purge timeout
ELSIF _bO2Err THEN nErrCode := 16#0005_3F05; bError := TRUE;       // 故障级：O2 校验失败 / Fault, O2 verification failed
ELSIF _bPressTmo THEN nErrCode := 16#0005_3F06; bError := TRUE;    // 故障级：升压超时 / Fault, pressurisation timeout
ELSIF _bInfoRatio THEN nErrCode := 16#0005_3F81;                   // 信息级：置换倍数达标 / Info, exchange ratio reached
ELSIF _bInfoReady THEN nErrCode := 16#0005_3F82;                   // 信息级：系统就绪放行 / Info, ready released
END_IF
END_FUNCTION_BLOCK
