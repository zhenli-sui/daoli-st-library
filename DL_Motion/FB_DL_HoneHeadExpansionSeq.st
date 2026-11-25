//==============================================================================
// 功能块：FB_DL_HoneHeadExpansionSeq ｜ 中文名称：珩磨头涨缩与往复联动序（复杂度 C4）
// 所属子库：DL_Motion ｜ 版本 VERSION: v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：珩磨头按压力曲线涨开油石——接近 → 压力爬坡涨开 → 保压珩磨 → 缩回退刀
//           → 完成。涨开量 = 基准涨开量 + 油石磨损补偿（按件数线性累加）；压力闭环
//           用纯比例 + 死区（无积分器，杜绝饱和），指令按爬坡速率限幅；中止立即泄压、
//           压力降到安全值以下才允许退刀（禁止带压退刀）。
// 开源溯源 (Origin)：道莅原创实现（参考 ISO 12180 珩磨工艺与油石磨损补偿工程惯例
//           分类与参数域，许可证=MIT，借鉴点=「按件数线性补偿涨开量 + 定压保压」工艺序）
// 单位表：压力[bar] / 涨开量[μm] / 时间[ms] / 计数[件]
// 错误码表（Motion 段 0008，故障窗口 0B01~0B08，信息窗口 0B11）：
//   16#0008_0B01 故障级：组态非法（目标压/爬坡率/上限/时间量 <= 0，或磨损系数 < 0）
//   16#0008_0B02 故障级：压力反馈入口非有限（NaN / Inf）或幅值超合法上限，拒算
//   16#0008_0B03 故障级：涨开量 > fMaxExpandUm，拒动并置 xOverExpand
//   16#0008_0B04 故障级：涨开爬坡超时（压力未进入目标带宽）
//   16#0008_0B05 故障级：保压期压力跌出带宽（掉压）
//   16#0008_0B06 故障级：泄压超时（压力未降到安全值，禁止带压退刀）
//   16#0008_0B07 故障级：缩回超时（tRetractTime 满时压力仍高于安全值，退刀未完成）
//   16#0008_0B08 故障级兜底：状态机落 ELSE 非法态，全输出断
//   16#0008_0B11 信息级：涨缩循环完成（完成拍，不置 bError）
//           故障级码全部锁存回放（R187），唯一清除路径 = bReset 上升沿。
// 状态机：E_DL_HoneExpState（七态：eIdle=0 / eApproach=10 / eExpand=20 / eDwell=30 /
//           eRetract=40 / eDone=50 / eFault=99）。中止两段化不占相位，由内部段号
//           _uAbortStage 驱动（0 无 / 1 泄压中 / 2 退刀中）。
// 边界行为：① eApproach 为固定接近延时相，不设超时（无故障码，仅作换向让位）；② 涨开
//           与缩回两命令在段 10 互斥，任何相不得同时置位；③ 带压退刀被物理禁止：中止段
//           A 只泄压不退刀，压力降到 DL_HNE_SAFE_BAR 以下才进段 B；④ 保压期压力跌出带宽
//           持续 DL_HNE_DROP_T 即锁存 0B05，不用单拍瞬时值；⑤ 七态 CASE 每态显式 +
//           ELSE 兜底 → 0B08 全断。
// 语义假设：① 压力指令为 bar 量纲的比例阀指令，0 bar = 泄压；② 涨开量与压力非线性对
//           应，故涨开量只作磨损补偿核算（fExpandUm 供上层显示与上限校验），不参与压力
//           闭环；③ 闭环执行周期按 DL_HNE_DT_S 假定 10 ms，本件无任务周期引脚，故以常量
//           声明该假定，换平台须同步。
// 依赖纪律：仅 Standard.library（TON / R_TRIG）；零 GVL、零 VAR_EXTERNAL、零物理地址。
// 修订历史：v1.0.0 2026-11-25 R88 首版（无人值守批次 · 复杂件 C4 · 序号 2）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_HoneExpState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 珩磨头涨缩相位，与段 9 状态机、段 10 输出置位一一对应。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_HoneExpState :
(
    eIdle     := 0,  // 空闲：等启动沿 / Idle, awaiting the start edge
    eApproach := 10, // 接近：固定延时让位，为涨开做准备 / Approach, fixed delay before expansion
    eExpand   := 20, // 涨开：压力按爬坡率升到目标带宽 / Expand, pressure ramps into the target band
    eDwell    := 30, // 保压：定压珩磨计时，监视掉压 / Dwell, timed honing with drop monitoring
    eRetract  := 40, // 缩回：压力归零并缩回退刀 / Retract, pressure zeroed before withdrawal
    eDone     := 50, // 完成：本件循环结束 / Done, the cycle finished
    eFault    := 99  // 故障：组态/掉压/超时/非法态 / Fault, configuration, pressure drop, timeout or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_HoneHeadExpansionSeq
VAR_INPUT
    xEnable          : BOOL;   // 使能，FALSE 期间按中止处理 [—] / Enable, a drop is treated as an abort
    xStart           : BOOL;   // 启动请求，上升沿生效 [—] / Start request, rising edge effective
    xAbort           : BOOL;   // 中止请求，任意拍生效（立即泄压） [—] / Abort request, effective on any scan
    xReset           : BOOL;   // 故障复位，上升沿清全部锁存 [—] / Fault reset, rising edge clears all latches
    fTargetPressBar  : LREAL;  // 目标珩磨压力 [bar]，须 > 0 / Target honing pressure [bar], must be > 0
    fPressFbBar      : LREAL;  // 压力实际反馈 [bar] / Actual pressure feedback [bar]
    fRampRateBarPerS : LREAL;  // 压力指令爬坡速率 [bar/s]，须 > 0 / Command ramp rate [bar/s], must be > 0
    tDwellTime       : TIME;   // 保压珩磨时长 [ms] / Dwell honing time [ms]
    tRetractTime     : TIME;   // 缩回退刀时长 [ms] / Retract time [ms]
    fStoneWearUmPerPc: LREAL;  // 油石每件磨损量 [μm/件] / Stone wear per piece [um/pc]
    nPieceCount      : UDINT;  // 累计加工件数 [件]，用于磨损补偿 / Accumulated piece count for wear compensation
    fMaxExpandUm     : LREAL;  // 涨开量上限 [μm]，须 > 0 / Expansion ceiling [um], must be > 0
    tPressTimeout    : TIME;   // 涨开爬坡与泄压超时 [ms] / Ramp and vent timeout [ms]
END_VAR
VAR_OUTPUT
    fPressCmdBar     : LREAL;  // 压力指令出口 [bar]，0 = 泄压 / Pressure command outlet [bar], 0 = vented
    xExpandCmd       : BOOL;   // 涨开命令（油石外张） [—] / Expansion command
    xRetractCmd      : BOOL;   // 缩回命令（油石内收退刀） [—] / Retract command
    bRunning         : BOOL;   // 循环运行中（非空闲非完成非故障非中止） [—] / Cycle active
    bDone            : BOOL;   // 单件循环完成相电平 [—] / Cycle done, level in the done phase
    bError           : BOOL;   // 故障级标志，仅故障级码置位 [—] / Fault-class flag, fault-level codes only
    nErrCode         : UDINT;  // 错误码，0 = 无错 [—] / Error code, 0 = none
    fExpandUm        : LREAL;  // 涨开量出口 [μm] = 基准 + 磨损补偿 / Expansion outlet [um] = base plus wear
    fWearCompUm      : LREAL;  // 磨损补偿量出口 [μm] = 每件磨损 × 件数 / Wear compensation outlet [um]
    xOverExpand      : BOOL;   // 涨开量超上限（拒动锁存） [—] / Expansion beyond the ceiling, latched
END_VAR
VAR
    _eState          : E_DL_HoneExpState := E_DL_HoneExpState.eIdle; // 当前相位 [—] / Current phase
    _bInit           : BOOL := FALSE;   // 首扫标志，取非判定 [—] / First-scan flag, tested negated
    _fPressCmd       : LREAL;           // 压力指令保持量（速率限幅后） [bar] / Held command after rate limiting [bar]
    _fWearCompUm     : LREAL;           // 内部磨损补偿量 [μm] / Internal wear compensation [um]
    _fExpandUm       : LREAL;           // 内部涨开量 [μm] / Internal expansion [um]
    _bCfgBad         : BOOL;            // 组态非法锁存 / Illegal configuration latch
    _bCfgOk          : BOOL;            // 本拍组态合法（派生量不锁存） [—] / Configuration legal this scan, derived
    _bSigBad         : BOOL;            // 压力反馈非有限锁存 / Non-finite pressure feedback latch
    _bOverExpand     : BOOL;            // 涨开量超上限锁存 / Over-expansion latch
    _bRampTmo        : BOOL;            // 涨开爬坡超时锁存 / Ramp timeout latch
    _bDropErr        : BOOL;            // 保压掉压锁存 / Pressure drop latch
    _bVentTmo        : BOOL;            // 泄压超时锁存 / Vent timeout latch
    _bRetractTmo     : BOOL;            // 缩回超时锁存 / Retract timeout latch
    _bIllegal        : BOOL;            // 非法状态标志 / Illegal state flag
    _bInfoDone       : BOOL;            // 循环完成信息当拍标志 / Cycle-done info flag of this scan
    _bAbortReq       : BOOL;            // 中止请求合成（xAbort 或失能） [—] / Combined abort request
    _bBandOk         : BOOL;            // 压力在目标带宽内（派生量） [—] / Pressure inside the target band, derived
    _bSafePressure   : BOOL;            // 压力已降到安全值以下（派生量） [—] / Pressure below the safe value, derived
    _uAbortStage     : UINT;            // 中止段号 0=无 1=泄压中 2=退刀中 / Abort stage 0 none 1 venting 2 retracting
    rtStart          : R_TRIG;          // 启动沿，段 7 无条件刷新 [—] / Start edge, refreshed in segment 7
    rtReset          : R_TRIG;          // 复位沿，段 7 无条件刷新 [—] / Reset edge, refreshed in segment 7
    tonApproach      : TON;             // 接近让位延时 [ms] / Approach delay [ms]
    tonRamp          : TON;             // 涨开爬坡超时 [ms] / Ramp timeout [ms]
    tonDwell         : TON;             // 保压珩磨计时 [ms] / Dwell honing timer [ms]
    tonPressDrop     : TON;             // 保压掉压持续窗 [ms] / Pressure-drop persistence window [ms]
    tonRetract       : TON;             // 缩回退刀计时 [ms] / Retract timer [ms]
    tonVent          : TON;             // 中止泄压超时 [ms] / Abort venting timeout [ms]
    tonAbortRetract  : TON;             // 中止退刀计时 [ms] / Abort retract timer [ms]
END_VAR
VAR_TEMP
    fErr             : LREAL;           // 本拍压力偏差暂存 [bar] / Pressure error scratch of this scan [bar]
    fDes             : LREAL;           // 本拍期望指令暂存 [bar] / Desired command scratch of this scan [bar]
    fRampStep        : LREAL;           // 本拍允许变化量暂存 [bar] / Allowed change per scan [bar]
END_VAR
VAR CONSTANT
    DL_EPS            : LREAL := 1.0E-9;     // 浮点容差零点，兼作除法分母下限 / Float epsilon, also the divisor floor
    DL_HNE_DT_S       : LREAL := 0.01;       // 闭环假定执行周期 [s]（10 ms 任务） / Assumed control period [s]
    DL_HNE_KP         : LREAL := 2.0;        // 压力闭环比例增益 [bar/bar] / Proportional gain [bar/bar]
    DL_HNE_DEAD_BAR   : LREAL := 0.05;       // 比例控制死区 [bar]，死区内保持指令 / Proportional dead band [bar]
    DL_HNE_BAND_RATIO : LREAL := 0.10;       // 目标带宽比例项 [倍] / Target band ratio term
    DL_HNE_BAND_MIN   : LREAL := 0.50;       // 目标带宽最小绝对值 [bar] / Minimum absolute band [bar]
    DL_HNE_BASE_UM    : LREAL := 25.0;       // 油石基准涨开量 [μm] / Base stone expansion [um]
    DL_HNE_CMD_MAX    : LREAL := 60.0;       // 压力指令幅值上限 [bar] / Command magnitude ceiling [bar]
    DL_HNE_SAFE_BAR   : LREAL := 0.50;       // 退刀前压力安全值 [bar] / Safe pressure before retraction [bar]
    DL_HNE_PRESS_MAX  : LREAL := 400.0;      // 压力反馈合法幅值上限 [bar] / Legal feedback ceiling [bar]
    DL_HNE_APPROACH_T : TIME  := T#800MS;    // 接近让位固定延时 [ms] / Fixed approach delay [ms]
    DL_HNE_DROP_T     : TIME  := T#300MS;    // 掉压持续判定窗 [ms] / Drop persistence window [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：全部输出先落安全侧，单拍标志预清零
 *      All outputs preset to the safe side, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fPressCmdBar := 0.0;                        // 压力指令先归零（泄压安全侧） / Command zeroed, vented side
xExpandCmd := FALSE; xRetractCmd := FALSE;  // 涨开/缩回命令先断 / Expansion and retract commands cleared
bRunning := FALSE;  bDone := FALSE;         // 运行与完成标志每拍重算 / Running and done flags recomputed
bError := FALSE;    nErrCode := 16#0000_0000; // 故障标志与错误码每拍重算 / Fault flag and code recomputed
xOverExpand := FALSE;                       // 超涨开标志每拍重算 / Over-expansion flag recomputed
_bIllegal := FALSE; _bInfoDone := FALSE;    // 非法态与完成信息预清零 / Illegal and done-info flags pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：相位、指令保持量与中止段号复位
 *      First-scan initialisation of phase, held command and abort stage
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState      := E_DL_HoneExpState.eIdle; // 相位从空闲起步 / Phase starts idle
    _fPressCmd := 0.0;  _fWearCompUm := 0.0; _fExpandUm := 0.0; // 指令/磨损/涨开量从零起步 / Command, wear and expansion at zero
    _uAbortStage := 0;                       // 中止段号从零起步 / Abort stage starts at zero
    _bInit       := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜入口非有限闸 + 组态闸（浮点量逐只双侧幅值判，时间量下限判）
 *      Non-finite inlet gate and configuration gates
 *-----------------------------------------------------------------------------*)
IF NOT (fPressFbBar > -1.0E30 AND fPressFbBar < 1.0E30) THEN _bSigBad := TRUE; END_IF    // 压力反馈非有限 → 0B02 / Non-finite feedback, 0B02
IF ABS(fPressFbBar) > DL_HNE_PRESS_MAX THEN _bSigBad := TRUE; END_IF                   // 反馈幅值超上限 → 0B02 / Beyond the ceiling, 0B02
IF NOT (fTargetPressBar > -1.0E30 AND fTargetPressBar < 1.0E30) THEN _bCfgBad := TRUE; END_IF // 目标压非有限 → 0B01 / Non-finite target, 0B01
IF NOT (fRampRateBarPerS > -1.0E30 AND fRampRateBarPerS < 1.0E30) THEN _bCfgBad := TRUE; END_IF // 爬坡率非有限 → 0B01 / Non-finite ramp, 0B01
IF NOT (fMaxExpandUm > -1.0E30 AND fMaxExpandUm < 1.0E30) THEN _bCfgBad := TRUE; END_IF  // 涨开上限非有限 → 0B01 / Non-finite ceiling, 0B01
IF NOT (fStoneWearUmPerPc > -1.0E30 AND fStoneWearUmPerPc < 1.0E30) THEN _bCfgBad := TRUE; END_IF // 磨损系数非有限 → 0B01 / Non-finite wear, 0B01
IF (fTargetPressBar <= DL_EPS) OR (fRampRateBarPerS <= DL_EPS) OR (fMaxExpandUm <= DL_EPS)
   OR (fStoneWearUmPerPc < 0.0) THEN _bCfgBad := TRUE; END_IF // 三者须为正且磨损非负 → 0B01 / Positive values required, 0B01
IF (tDwellTime <= T#0MS) OR (tRetractTime <= T#0MS) OR (tPressTimeout <= T#0MS) THEN _bCfgBad := TRUE; END_IF // 时间量须为正 → 0B01 / Time values must be positive
_bCfgOk := NOT _bCfgBad;                    // 本拍组态合法派生量 / Configuration-legal derived flag of this scan

(*------------------------------------------------------------------------------
 * 段 4｜磨损补偿与涨开量核算 + 超涨开拒动判定
 *      Wear compensation, expansion accounting and the over-expansion check
 *-----------------------------------------------------------------------------*)
_fWearCompUm := fStoneWearUmPerPc * UDINT_TO_LREAL(nPieceCount); // 磨损补偿 [μm] = 每件磨损 × 件数 / Wear = per-piece wear times pieces
_fExpandUm   := DL_HNE_BASE_UM + _fWearCompUm;                   // 涨开量 [μm] = 基准 + 磨损补偿 / Expansion = base plus wear
IF (_bCfgOk) AND (_fExpandUm > fMaxExpandUm) THEN
    _bOverExpand := TRUE;                   // 涨开量超上限，拒动锁存 → 0B03 / Beyond the ceiling, code 0B03
END_IF
fWearCompUm := _fWearCompUm; fExpandUm := _fExpandUm; // 磨损补偿与涨开量出口 [μm] / Wear and expansion outlets [um]
xOverExpand := _bOverExpand;                // 超涨开出口 [—] / Over-expansion outlet

(*------------------------------------------------------------------------------
 * 段 5｜压力闭环（纯比例 + 死区，无积分器）+ 爬坡速率限幅
 *      Pressure loop, proportional only with a dead band, plus ramp rate limiting
 *-----------------------------------------------------------------------------*)
IF ((_eState = E_DL_HoneExpState.eExpand) OR (_eState = E_DL_HoneExpState.eDwell))
   AND (_uAbortStage = 0) AND (NOT _bCfgBad) AND (NOT _bSigBad) THEN
    fErr := fTargetPressBar - fPressFbBar;  // 压力偏差 [bar] / Pressure error [bar]
    IF ABS(fErr) > DL_HNE_DEAD_BAR THEN
        fDes := _fPressCmd + DL_HNE_KP * fErr; // 比例增量，死区外才动 / Proportional increment outside the dead band
    ELSE
        fDes := _fPressCmd;                 // 死区内保持（无积分器，杜绝饱和） / Held inside the dead band, no integrator
    END_IF
    IF fDes < 0.0 THEN fDes := 0.0; END_IF  // 指令下钳 0（不吸真空） / Lower clamp at zero
    IF fDes > DL_HNE_CMD_MAX THEN fDes := DL_HNE_CMD_MAX; END_IF // 指令上钳幅值上限 / Upper clamp at the ceiling
    fRampStep := fRampRateBarPerS * DL_HNE_DT_S; // 本拍允许变化量 [bar] / Allowed change per scan [bar]
    IF (fDes - _fPressCmd) > fRampStep THEN fDes := _fPressCmd + fRampStep;      // 正向限幅 / Positive ramp limit
    ELSIF (fDes - _fPressCmd) < (0.0 - fRampStep) THEN fDes := _fPressCmd - fRampStep; // 反向限幅 / Negative ramp limit
    END_IF
    _fPressCmd := fDes;                     // 指令保持量推进 / Held command advanced
ELSE
    _fPressCmd := 0.0;                      // 非涨开相一律归零（泄压） / Zeroed outside the expansion phases
END_IF
fPressCmdBar := _fPressCmd;                 // 压力指令出口 [bar] / Pressure command outlet [bar]
_bBandOk := ABS(fPressFbBar - fTargetPressBar) <= (fTargetPressBar * DL_HNE_BAND_RATIO + DL_HNE_BAND_MIN); // 带宽判据 / Band criterion
_bSafePressure := fPressFbBar <= DL_HNE_SAFE_BAR;  // 安全压判据（退刀许可） / Safe-pressure criterion for retraction

(*------------------------------------------------------------------------------
 * 段 6｜中止入口（段 0→1，立即泄压）与复位
 *      Abort entry, immediate venting, and the reset edge
 *-----------------------------------------------------------------------------*)
_bAbortReq := xAbort OR (NOT xEnable);      // 中止请求合成：显式中止或失能 / Combined abort: explicit abort or enable loss
IF _bAbortReq AND (_uAbortStage = 0) AND (_eState <> E_DL_HoneExpState.eIdle)
   AND (_eState <> E_DL_HoneExpState.eDone) AND (_eState <> E_DL_HoneExpState.eFault) THEN
    _uAbortStage := 1;                      // 进中止段 A：立即泄压，禁带压退刀 / Enter abort stage A, vent first
END_IF
IF rtReset.Q THEN
    _bCfgBad := FALSE;  _bSigBad := FALSE;  _bOverExpand := FALSE; // 复位清组态/反馈/超涨开锁存 / Clears configuration, feedback, expansion
    _bRampTmo := FALSE; _bDropErr := FALSE; _bVentTmo := FALSE; _bRetractTmo := FALSE; // 复位清爬坡/掉压/泄压/缩回锁存 / Clears ramp, drop, vent, retract
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜定时器与边沿无条件周期刷新（R7：CASE 之外每拍必调，各司其职不复用）
 *      Timers and edges refreshed unconditionally every scan, outside the CASE
 *-----------------------------------------------------------------------------*)
rtStart(CLK := xStart); rtReset(CLK := xReset); // 启动沿与复位沿无条件刷新 / Start and reset edges refreshed
tonApproach(IN := (_eState = E_DL_HoneExpState.eApproach) AND (_uAbortStage = 0), PT := DL_HNE_APPROACH_T); // 接近让位延时 / Approach delay
tonRamp(IN := (_eState = E_DL_HoneExpState.eExpand) AND (_uAbortStage = 0), PT := tPressTimeout);            // 涨开爬坡超时 / Ramp timeout
tonDwell(IN := (_eState = E_DL_HoneExpState.eDwell) AND (_uAbortStage = 0), PT := tDwellTime);               // 保压计时 / Dwell timer
tonPressDrop(IN := (_eState = E_DL_HoneExpState.eDwell) AND (NOT _bBandOk), PT := DL_HNE_DROP_T);            // 掉压持续窗 / Drop window
tonRetract(IN := (_eState = E_DL_HoneExpState.eRetract) AND (_uAbortStage = 0), PT := tRetractTime);         // 缩回计时 / Retract timer
tonVent(IN := (_uAbortStage = 1), PT := tPressTimeout);                                                      // 中止泄压超时 / Abort vent timeout
tonAbortRetract(IN := (_uAbortStage = 2), PT := tRetractTime);                                               // 中止退刀计时 / Abort retract timer

(*------------------------------------------------------------------------------
 * 段 8｜中止段推进（1 泄压 → 压力安全值以下才进 2 退刀 → 收口）
 *      Abort progression, retraction only after the pressure is below the safe value
 *-----------------------------------------------------------------------------*)
IF (_uAbortStage = 1) AND _bSafePressure THEN
    _uAbortStage := 2;                      // 压力已泄到安全值，进退刀段 / Pressure safe, enter retraction
ELSIF (_uAbortStage = 1) AND tonVent.Q THEN
    _bVentTmo := TRUE; _uAbortStage := 0;   // 泄压超时，禁止带压退刀 → 0B06 / Vent timeout, 0B06
    _eState   := E_DL_HoneExpState.eFault;  // 落故障 / Fall to fault
END_IF
IF (_uAbortStage = 2) AND tonAbortRetract.Q THEN
    _uAbortStage := 0;                      // 退刀完成，中止收口 / Retraction done, abort closed
    _eState      := E_DL_HoneExpState.eIdle; // 回空闲 / Back to idle
END_IF
(*------------------------------------------------------------------------------
 * 段 9｜状态机（中止期间迁移冻结；本段只做迁移，输出在段 10）
 *      Phase machine, transitions frozen while aborting, outputs in segment 10
 *-----------------------------------------------------------------------------*)
IF _uAbortStage = 0 THEN
    CASE _eState OF
        E_DL_HoneExpState.eIdle:            // 空闲：启动沿 + 组态合法 + 未超涨开才进接近 / Idle, legal start edge only
            IF rtStart.Q AND _bCfgOk AND (NOT _bSigBad) AND (NOT _bOverExpand) AND (NOT _bAbortReq) THEN
                _fPressCmd := 0.0;          // 新循环指令复位 / Command reset for the new cycle
                _eState    := E_DL_HoneExpState.eApproach; // 进接近相 / To the approach phase
            END_IF
        E_DL_HoneExpState.eApproach:        // 接近：固定让位延时满即涨开 / Approach, expansion after the fixed delay
            IF tonApproach.Q THEN _eState := E_DL_HoneExpState.eExpand; END_IF // 延时满，进涨开相 / Delay elapsed, expand
        E_DL_HoneExpState.eExpand:          // 涨开：压力进入带宽即进保压，超时落故障 / Expand into the band or time out
            IF _bBandOk THEN _eState := E_DL_HoneExpState.eDwell; // 压力进带宽，进保压相 / In band, to dwell
            ELSIF tonRamp.Q THEN _bRampTmo := TRUE; _eState := E_DL_HoneExpState.eFault; // 爬坡超时 → 0B04 / Ramp timeout, 0B04
            END_IF
        E_DL_HoneExpState.eDwell:           // 保压：掉压超窗落故障，计时满进缩回 / Dwell, drop faults, timer to retract
            IF tonPressDrop.Q THEN _bDropErr := TRUE; _eState := E_DL_HoneExpState.eFault; // 掉压持续 → 0B05 / Pressure drop, 0B05
            ELSIF tonDwell.Q THEN _eState := E_DL_HoneExpState.eRetract; // 保压满，进缩回相 / Dwell elapsed, retract
            END_IF
        E_DL_HoneExpState.eRetract:         // 缩回：退刀计时满且压力已安全才完成 / Retract done once timed and safe
            IF tonRetract.Q AND (NOT _bSafePressure) THEN
                _bRetractTmo := TRUE; _eState := E_DL_HoneExpState.eFault; // 计时满仍带压 → 0B07 / Still pressurized, 0B07
            ELSIF tonRetract.Q THEN
                _bInfoDone := TRUE;         // 置循环完成信息 / Raise the cycle-done info
                _eState    := E_DL_HoneExpState.eDone; // 进完成相 / To the done phase
            END_IF
        E_DL_HoneExpState.eDone:            // 完成：启动撤销且无中止请求才回空闲 / Done, back to idle once start drops
            IF (NOT xStart) AND (NOT _bAbortReq) THEN _eState := E_DL_HoneExpState.eIdle; END_IF
        E_DL_HoneExpState.eFault:           // 故障：复位沿且组态合法且未超涨开才回空闲 / Fault, reset edge only
            IF rtReset.Q AND _bCfgOk AND (NOT _bSigBad) AND (NOT _bOverExpand) THEN _eState := E_DL_HoneExpState.eIdle; END_IF
        ELSE                                // 非法状态兜底（R6：CASE 必带 ELSE）/ Illegal-state fallback
            _bIllegal := TRUE; _eState := E_DL_HoneExpState.eFault; // 非法态 → 0B08，落故障 / Illegal state, 0B08
    END_CASE
END_IF
(*------------------------------------------------------------------------------
 * 段 10｜输出置位（涨开与缩回互斥；中止段 A 只泄压不退刀）
 *      Output assignment, expand and retract exclusive, abort stage A vents only
 *-----------------------------------------------------------------------------*)
xExpandCmd := FALSE;                        // 默认两命令先断，再由状态判定置位（R88 修复：原 CASE ELSE 覆盖涨开命令） / default both off (R88 fix)
xRetractCmd := FALSE;                       // 缩回命令默认断 / retract default off
IF (_eState = E_DL_HoneExpState.eExpand) OR (_eState = E_DL_HoneExpState.eDwell) THEN
    xExpandCmd := TRUE;                     // 涨开相与保压相：油石外张 / Expand and dwell, stone outwards
END_IF
CASE _eState OF
    E_DL_HoneExpState.eRetract:             // 缩回相：油石内收退刀 / Retract phase, stone inwards
        xRetractCmd := TRUE;                // 缩回命令 / Retract command
    E_DL_HoneExpState.eDone:                // 完成相：完成电平 / Done phase, done level
        bDone := TRUE;                      // 循环完成 / Cycle done
    ELSE
        xRetractCmd := FALSE;               // 兜底：仅保持缩回断，涨开指令由上方状态判定决定，不得覆盖 / fallback keeps retract off only
END_CASE
IF _uAbortStage >= 1 THEN
    xExpandCmd := FALSE;                    // 中止段 A：涨开命令立即断 / Abort A, expansion cut immediately
    fPressCmdBar := 0.0;                    // 立即泄压（泄压优先于一切） / Vent immediately, before anything else
    xRetractCmd := (_uAbortStage = 2);      // 压力已安全才退刀，禁带压退刀 / Retract only once the pressure is safe
END_IF
bRunning := (_eState <> E_DL_HoneExpState.eIdle) AND (_eState <> E_DL_HoneExpState.eDone)
            AND (_eState <> E_DL_HoneExpState.eFault) AND (_uAbortStage = 0); // 运行标志 / Running flag

(*------------------------------------------------------------------------------
 * 段 11｜错误码映射（锁存回放，R187：故障相不按当下输入重推断）
 *      Error-code map, latched replay
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN nErrCode := 16#0008_0B08; bError := TRUE;        // 故障级兜底：非法态 / Fault, illegal state fallback
ELSIF _bCfgBad THEN nErrCode := 16#0008_0B01; bError := TRUE;      // 故障级：组态非法 / Fault, illegal configuration
ELSIF _bSigBad THEN nErrCode := 16#0008_0B02; bError := TRUE;      // 故障级：压力反馈非有限 / Fault, non-finite feedback
ELSIF _bOverExpand THEN nErrCode := 16#0008_0B03; bError := TRUE;  // 故障级：涨开量超上限 / Fault, over expansion
ELSIF _bRampTmo THEN nErrCode := 16#0008_0B04; bError := TRUE;     // 故障级：涨开爬坡超时 / Fault, ramp timeout
ELSIF _bDropErr THEN nErrCode := 16#0008_0B05; bError := TRUE;     // 故障级：保压掉压 / Fault, pressure drop
ELSIF _bVentTmo THEN nErrCode := 16#0008_0B06; bError := TRUE;     // 故障级：泄压超时/带压退刀 / Fault, vent timeout
ELSIF _bRetractTmo THEN nErrCode := 16#0008_0B07; bError := TRUE;  // 故障级：缩回超时 / Fault, retract timeout
ELSIF _bInfoDone THEN nErrCode := 16#0008_0B11;                    // 信息级：循环完成，不置 bError / Info, cycle done
END_IF
END_FUNCTION_BLOCK
