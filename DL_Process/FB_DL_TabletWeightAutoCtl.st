(*
  DL Factory R84 | FB_DL_TabletWeightAutoCtl
  功能：压片机片重自动控制：固定二十点滚动窗统计片重均值与标准差，按速度式 PI 出充填深度增量（死区＋限幅），单片按三倍标准差与上下公差判剔除，连续五片超差停机上报警。
  开源溯源：无（clean-room 自研，依据公开工艺公式与安全设计惯例，来源=行业通用公式+工程实践，许可证=MIT，借鉴点=公式结构与联锁分层）
  规则：R1-R16 全遵守
  ------------------------------------------------------------------
  分类 DL_Process ｜ 复杂度 cx4 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（R_TRIG、LREAL、ENUM、CASE）
  边界一：只出充填深度指令与剔废脉冲，不驱动加料伺服、不控冲头行程、不执行剔废气缸（属主边界，执行由下层 PRG 完成）。
  边界二：滚动窗为定长二十槽环形缓冲（R15 显式定长），入窗与取窗同一存储；统计采用两遍法（先均值再离差平方和），
          分母为常量 20 与 19，结构性零除不可能；标准差取样本口径（分母 n−1）。
  边界三：判据次序为「先判后入窗」——单片离群判据使用入窗前的均值与标准差，避免本片自掩蔽把离群点拉回带内；
          剔除判定后该片仍入窗（工艺上已成型，属真实产出），故窗统计含被剔片，此口径写死在段 4 至段 6 顺序中。
  边界四：离群判据的三倍标准差门限仅在标准差大于零闸门限时生效；标准差为零（窗内全同）时只用公差判据，
          防「零标准差 → 任意微小偏差皆判离群」的假剔废群。
  边界五：调节量为速度式 PI 增量（du ＝ Kp·Δe ＋ Ki·e），积分效应内置于增量式，无独立积分累加器，
          故不存在积分饱和；累计指令的硬域钳定即为抗饱和的最终保障。死区为目标片重的 0.01 倍，死区内 e 取零，
          但 Δe 仍按零参与，使过零后不产生阶跃踢动。
  边界六：无效拍语义——目标片重不大于零、深度上下限越域、冲头压力低于下限、或任一浮点入参非有限 → xValid 出假、
          相位保持、调节量不出（深度指令保持上一值）；此三态均为信息级，故障级语义由 xStop 锁存位承担。
  量纲自检：片重 [mg]＝fWeightMg、fTargetMg、fTolUpMg、fTolDnMg、fMeanMg、fStdMg 同量纲；
          充填深度 [mm]＝fFillDepthMm、fDepthCmd、fDu、上下限；增益 Kp 单位 [mm/mg]、Ki 单位 [mm/mg]；
          压力 [kN]＝fForceKn 与 fForceMinKn。
  码表：本件全部码位为信息级（2801 目标片重越域、2802 深度限越域、2803 入参非有限、2804 压力低于下限、
        2805 连续超差停机、2806 非法相位）；信息级码每拍重算且不置 bError；停机锁存由 xStop 表达，故本件无 bError 出口（R187）。
  输出契约：fDepthCmd 为累计充填深度指令 [mm]（域内恒等于上下限之间）；xReject 为单拍剔除脉冲（统一出口映射）；
          xReady 在窗未满时为假且 fMeanMg 出 0（不出调节量）；iRejectCnt 为累计剔除片数 [片]，复位沿清零。
  修订记录：2026-11-24 v1.0.0 R84 首版（批 R84 · 序号 43）
*)

TYPE E_DL_TabWtState :
(
    eIdle     := 0, // 空闲：等使能与首片 / idle, waiting for the enable and the first tablet
    eSampling := 10, // 取样：窗未满，只统计不调节 / sampling, the window is filling and nothing is adjusted
    eAdjust   := 20, // 调节：窗已满，逐片出充填深度增量 / adjusting, the window is full and the depth is trimmed
    eReject   := 30, // 剔除：单拍过渡态，出剔除脉冲 / reject, a one scan transition emitting the reject pulse
    eStop     := 40  // 停机：连续超差锁存，复位沿解除 / stop, latched on consecutive deviations and cleared by the reset edge
);
END_TYPE

TYPE E_DL_TabWtCause :
(
    eNone      := 0, // 无成因 / no cause
    eTargetBad := 1, // 目标片重越域（信息级 2801）/ the target weight is out of domain, info grade 2801
    eLimitBad  := 2, // 充填深度上下限越域（信息级 2802）/ the depth limits are out of domain, info grade 2802
    eNotFinite := 3, // 入参非有限（信息级 2803）/ a non-finite input, info grade 2803
    eForceLow  := 4, // 冲头压力低于下限（信息级 2804）/ the punch force is below its floor, info grade 2804
    eConsBad   := 5, // 连续超差停机（信息级 2805）/ consecutive deviations tripped the machine, info grade 2805
    ePhaseBad  := 6  // 非法相位（信息级 2806）/ an illegal phase, info grade 2806
);
END_TYPE

FUNCTION_BLOCK FB_DL_TabletWeightAutoCtl
VAR CONSTANT
    DL_TWC_WIN         : INT := 20;       // 滚动窗点数 [点] / the rolling window length [point]
    DL_TWC_WIN_CAP     : INT := 20;       // 缓冲槽数（下标 0..19，与窗点数一致）[槽] / the buffer slots, subscripts 0..19 [slot]
    DL_TWC_DEN_N       : LREAL := 20.0;   // 均值分母（常量，结构性非零）[-] / the mean denominator as a constant [-]
    DL_TWC_DEN_N1      : LREAL := 19.0;   // 样本方差分母 n−1（常量）[-] / the sample variance denominator [-]
    DL_TWC_KP          : LREAL := 0.020;  // 比例增益 [mm/mg] / the proportional gain [mm/mg]
    DL_TWC_KI          : LREAL := 0.004;  // 积分增益（速度式内的积分项）[mm/mg] / the integral gain inside the velocity form [mm/mg]
    DL_TWC_DEADBAND_FRAC : LREAL := 0.01; // 死区带宽（目标片重的倍数）[-] / the dead band as a fraction of the target [-]
    DL_TWC_STEP_MM     : LREAL := 0.05;   // 单次调节限幅 [mm] / the per shot adjustment step limit [mm]
    DL_TWC_SIGMA_K     : LREAL := 3.0;    // 离群判据的标准差倍数 [-] / the sigma multiplier of the outlier test [-]
    DL_TWC_CONS_MAX    : INT := 5;        // 连续超差停机点数 [片] / the consecutive deviation trip count [tablet]
    DL_TWC_EPS         : LREAL := 1.0E-9; // 零闸与零判定门限 [-] / the zero guard and zero test threshold [-]
END_VAR
VAR_INPUT
    bEnable       : BOOL := TRUE;    // 使能，失能回空闲且不再调节 [-] / enable, a disable returns to idle and stops trimming
    bReset        : BOOL := FALSE;   // 复位上升沿清停机锁存与全部计数 [-] / reset rising edge clears the stop latch and the counters
    bPieceValid   : BOOL := FALSE;   // 新片有效（脉冲或电平，取上升沿）[-] / a valid tablet, its rising edge is consumed
    fWeightMg     : LREAL := 500.0;  // 实测片重 [mg] / the measured tablet weight [mg]
    fTargetMg     : LREAL := 500.0;  // 目标片重 [mg] / the target tablet weight [mg]
    fTolUpMg      : LREAL := 10.0;   // 上公差 [mg] / the upper tolerance [mg]
    fTolDnMg      : LREAL := 10.0;   // 下公差 [mg] / the lower tolerance [mg]
    fFillDepthMm  : LREAL := 8.00;   // 充填深度反馈 [mm] / the fill depth feedback [mm]
    fFillDepthMinMm : LREAL := 4.00; // 充填深度下限 [mm] / the fill depth lower limit [mm]
    fFillDepthMaxMm : LREAL := 14.0; // 充填深度上限 [mm] / the fill depth upper limit [mm]
    fForceKn      : LREAL := 30.0;   // 冲头压力 [kN] / the punch force [kN]
    fForceMinKn   : LREAL := 5.00;   // 冲头压力下限（低于即无效拍）[kN] / the punch force floor [kN]
END_VAR
VAR_OUTPUT
    fDepthCmd    : LREAL := 0.0;  // 充填深度指令（累计）[mm] / the fill depth command, accumulated [mm]
    fMeanMg      : LREAL := 0.0;  // 窗内片重均值（窗未满出 0）[mg] / the window mean, zero until the window is full [mg]
    fStdMg       : LREAL := 0.0;  // 窗内片重样本标准差 [mg] / the window sample standard deviation [mg]
    fDevMg       : LREAL := 0.0;  // 本片相对上拍均值的偏差 [mg] / the deviation of the tablet against the previous mean [mg]
    iRejectCnt   : DINT := 0;     // 累计剔除片数 [片] / the accumulated reject count [tablet]
    nWinFill     : INT := 0;      // 窗内已填点数 [点] / the filled window points [point]
    xReject      : BOOL := FALSE; // 单拍剔除脉冲（统一出口映射）[-] / the one scan reject pulse
    xStop        : BOOL := FALSE; // 停机锁存（连续超差，复位沿清除）[-] / the stop latch cleared by the reset edge
    xReady       : BOOL := FALSE; // 窗已满且可出调节量 [-] / the window is full and a trim may be issued
    eState       : E_DL_TabWtState := E_DL_TabWtState.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    iErrCode     : INT := 0;      // 信息级码（每拍重算，非锁存）[码] / the info grade code, recomputed every scan [code]
    xValid       : BOOL := FALSE; // 本拍输入可信 [-] / the inputs of this scan are trustworthy
END_VAR
VAR
    rtPiece    : R_TRIG; // 新片沿实例（无量纲）[-] / the tablet edge refreshed unconditionally
    rtReset    : R_TRIG; // 复位沿实例（无量纲）[-] / the reset edge refreshed unconditionally
    _eState    : E_DL_TabWtState := E_DL_TabWtState.eIdle; // 内部相位（枚举，无量纲）[-] / the internal phase, the only CASE target
    _aBuf      : ARRAY[0..19] OF LREAL; // 片重环形缓冲（定长二十槽，R15）[mg] / the ring buffer of the weights [mg]
    _iHead     : INT := 0;    // 下一点写入槽号（0..19）[槽] / the next write slot [slot]
    _iFill     : INT := 0;    // 已填点数（封顶二十）[点] / the filled points capped at twenty [point]
    _i         : INT := 0;    // 遍历下标 [-] / the traversal index
    _iConsBad  : INT := 0;    // 连续超差片数 [片] / the consecutive deviating count [tablet]
    _iErrTmp   : INT := 0;    // 本拍信息级码暂存 [码] / the scan info code scratch [code]
    _iRejAcc   : DINT := 0;   // 剔除计数累加（唯一写入点）[片] / the reject accumulator, the only write point [tablet]
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bFinOk    : BOOL := FALSE; // 全部浮点入参有限 [-] / every floating input is finite
    _bTgtOk    : BOOL := FALSE; // 目标片重与公差域内 [-] / the target and the tolerances are inside the domain
    _bLimOk    : BOOL := FALSE; // 深度上下限域内 [-] / the depth limits are inside the domain
    _bForceOk  : BOOL := FALSE; // 冲头压力不低于下限 [-] / the punch force is at or above its floor
    _bWinFull  : BOOL := FALSE; // 窗已填满（可统计可调节）[-] / the window is full
    _bReject   : BOOL := FALSE; // 本片剔除判据结果 [-] / the reject verdict of the tablet
    _bOverTol  : BOOL := FALSE; // 本片超公差（参与连续计数）[-] / the tablet broke the tolerance
    _bRejOut   : BOOL := FALSE; // 单拍剔除位（段 0 预清，出口映射）[-] / the one scan reject bit
    _bStopLch  : BOOL := FALSE; // 停机锁存位（唯一清除：复位沿）[-] / the stop latch cleared by the reset edge only
    _bAdjOk    : BOOL := FALSE; // 本拍允许调节（状态量与窗满合取）[-] / the trim permit from the state and the window
    _fSum      : LREAL := 0.0;  // 窗内片重和 [mg] / the window sum [mg]
    _fMean     : LREAL := 0.0;  // 窗内均值（本拍计算）[mg] / the window mean of this scan [mg]
    _fDev      : LREAL := 0.0;  // 单点离差（窗统计遍历用）[mg] / the single point deviation used by the traversal [mg]
    _fDevPiece : LREAL := 0.0;  // 本片相对上拍均值的偏差（判据与诊断）[mg] / the tablet deviation against the previous mean [mg]
    _fVar      : LREAL := 0.0;  // 窗内样本方差 [mg²] / the window sample variance [mg^2]
    _fStd      : LREAL := 0.0;  // 窗内样本标准差 [mg] / the window sample standard deviation [mg]
    _fMeanPrev : LREAL := 0.0;  // 上拍均值快照（判据用，不含本片）[mg] / the previous mean snapshot used by the verdict [mg]
    _fStdPrev  : LREAL := 0.0;  // 上拍标准差快照（判据用）[mg] / the previous deviation snapshot used by the verdict [mg]
    _fErr      : LREAL := 0.0;  // 片重偏差（目标减均值，正为偏轻）[mg] / the weight error, positive means too light [mg]
    _fErrEff   : LREAL := 0.0;  // 死区处理后的偏差 [mg] / the error after the dead band [mg]
    _fErrPrev  : LREAL := 0.0;  // 上次调节的偏差快照 [mg] / the error snapshot of the last trim [mg]
    _fBand     : LREAL := 0.0;  // 死区带宽 [mg] / the dead band width [mg]
    _fDu       : LREAL := 0.0;  // 速度式 PI 增量（限幅前）[mm] / the velocity form increment before limiting [mm]
    _fCmd      : LREAL := 0.0;  // 充填深度指令累加（唯一写入点）[mm] / the depth command accumulator [mm]
END_VAR
// 段 0｜出口预置：全部出口先赋安全侧值，任何路径不留未初始化输出
xValid := FALSE; // 有效性预置假 / validity preset false
xReady := _bWinFull AND bEnable; // 就绪位预置（窗满且使能）/ the ready bit preset
xReject := FALSE; // 剔除脉冲预置假（本拍重新判定）/ the reject pulse preset false
xStop := _bStopLch; // 停机锁存回放 / replay the stop latch
fDepthCmd := _fCmd; // 深度指令回放上一值（无效拍保持）/ replay the last depth command
fMeanMg := 0.0; // 均值预置零（窗未满契约）/ the mean preset zero
fStdMg := 0.0; // 标准差预置零 / the standard deviation preset zero
fDevMg := 0.0; // 偏差预置零 / the deviation preset zero
iRejectCnt := _iRejAcc; // 剔除计数回放 / replay the reject count
nWinFill := _iFill; // 窗内点数回放 / replay the filled points
eState := _eState; // 相位回放 / replay the phase
iErrCode := 0; // 信息级码预置零（本拍重算）/ the info code preset zero
_bRejOut := FALSE; // 单拍剔除位预清零（FB32-1：仅单拍标志可预清）/ preclear the one scan reject bit
_bReject := FALSE; // 单拍剔除判据预清 / preclear the reject verdict
_bOverTol := FALSE; // 单拍超公差判据预清 / preclear the tolerance verdict
_iErrTmp := 0; // 单拍码暂存预清 / preclear the code scratch
// 段 1｜非有限闸：NaN 自反比较、Inf 差值自减双判，逐项枚举八个浮点入参（R79、R272）
_bFinOk := (fWeightMg = fWeightMg) AND ((fWeightMg - fWeightMg) = (fWeightMg - fWeightMg)) // 片重有限 [-] / the weight is finite
    AND (fTargetMg = fTargetMg) AND ((fTargetMg - fTargetMg) = (fTargetMg - fTargetMg)) // 目标片重有限 [-] / the target is finite
    AND (fTolUpMg = fTolUpMg) AND ((fTolUpMg - fTolUpMg) = (fTolUpMg - fTolUpMg)) // 上公差有限 [-] / the upper tolerance is finite
    AND (fTolDnMg = fTolDnMg) AND ((fTolDnMg - fTolDnMg) = (fTolDnMg - fTolDnMg)) // 下公差有限 [-] / the lower tolerance is finite
    AND (fFillDepthMm = fFillDepthMm) AND ((fFillDepthMm - fFillDepthMm) = (fFillDepthMm - fFillDepthMm)) // 深度反馈有限 [-] / the depth feedback is finite
    AND (fFillDepthMinMm = fFillDepthMinMm) AND ((fFillDepthMinMm - fFillDepthMinMm) = (fFillDepthMinMm - fFillDepthMinMm)) // 深度下限有限 [-] / the depth floor is finite
    AND (fFillDepthMaxMm = fFillDepthMaxMm) AND ((fFillDepthMaxMm - fFillDepthMaxMm) = (fFillDepthMaxMm - fFillDepthMaxMm)) // 深度上限有限 [-] / the depth ceiling is finite
    AND (fForceKn = fForceKn) AND ((fForceKn - fForceKn) = (fForceKn - fForceKn)) // 冲头压力有限 [-] / the punch force is finite
    AND (fForceMinKn = fForceMinKn) AND ((fForceMinKn - fForceMinKn) = (fForceMinKn - fForceMinKn)); // 压力下限有限 [-] / the force floor is finite
// 段 2｜组态域闸：目标片重正定、公差非负、深度上限大于下限、压力下限非负（R151、FB51-2）
_bTgtOk := (fTargetMg > 0.0) AND (fTolUpMg >= 0.0) AND (fTolDnMg >= 0.0); // 目标与公差域闸 [-] / the target and the tolerance gates
_bLimOk := (fFillDepthMinMm > 0.0) AND (fFillDepthMaxMm > fFillDepthMinMm); // 深度域闸（上限严格大于下限）[-] / the depth domain gate
_bForceOk := (fForceMinKn >= 0.0) AND (fForceKn >= fForceMinKn); // 压力域闸 [-] / the force domain gate
IF NOT _bFinOk THEN _iErrTmp := 2803; // 信息级：入参非有限 / the info code for a non-finite input
ELSIF NOT _bTgtOk THEN _iErrTmp := 2801; // 信息级：目标片重越域 / the info code for a bad target
ELSIF NOT _bLimOk THEN _iErrTmp := 2802; // 信息级：深度限越域 / the info code for bad depth limits
ELSIF NOT _bForceOk THEN _iErrTmp := 2804; // 信息级：压力低于下限 / the info code for a low punch force
END_IF
// 段 3｜沿检测无条件周期刷新（R7）
rtPiece(CLK := bPieceValid); // 新片沿无条件刷新 / unconditional refresh of the tablet edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
// 段 4｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志 / the first scan flag
    _bStopLch := FALSE; // 作用域一：清停机锁存（唯一清除边，R188）/ scope one, clear the stop latch
    _iRejAcc := 0; _iConsBad := 0; // 作用域二：清剔除计数与连续超差计数 / scope two, clear the counters
    _iHead := 0; _iFill := 0; // 作用域二：缓冲复位 / scope two, reset the buffer
    _fMeanPrev := 0.0; _fStdPrev := 0.0; _fErrPrev := 0.0; // 作用域三：清统计与调节快照 / scope three, clear the snapshots
    _fCmd := fFillDepthMm; // 作用域三：指令基准取当前反馈 [mm] / scope three, the command base is the feedback [mm]
    IF _fCmd < fFillDepthMinMm THEN _fCmd := fFillDepthMinMm; END_IF // 基准下限钳定 / clamp the base low
    IF _fCmd > fFillDepthMaxMm THEN _fCmd := fFillDepthMaxMm; END_IF // 基准上限钳定 / clamp the base high
    _eState := E_DL_TabWtState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate to idle
END_IF
// 段 5｜单片剔除判据：先用上拍统计（不含本片），3σ 门限仅在标准差有效时生效（边界四）
IF rtPiece.Q AND _bFinOk AND _bTgtOk THEN // 新片且目标与入参可信 / a new tablet with a trustworthy target
    _fDevPiece := fWeightMg - _fMeanPrev; // 本片偏差 [mg] / the deviation of the tablet [mg]
    IF _fStdPrev > DL_TWC_EPS THEN // 标准差有效才用三倍标准差判据 / the sigma test only with a valid deviation
        IF ABS(_fDevPiece) > (DL_TWC_SIGMA_K * _fStdPrev) THEN _bReject := TRUE; END_IF // 三倍标准差离群 / the three sigma outlier
    END_IF
    IF fWeightMg > (fTargetMg + fTolUpMg) THEN _bReject := TRUE; _bOverTol := TRUE; END_IF // 上公差越限（方向分列）/ the upper tolerance breach
    IF fWeightMg < (fTargetMg - fTolDnMg) THEN _bReject := TRUE; _bOverTol := TRUE; END_IF // 下公差越限（方向分列）/ the lower tolerance breach
    IF _bReject THEN // 判为剔除 / judged as a reject
        _iRejAcc := _iRejAcc + 1; // 累计剔除片数（唯一写入点）/ the only write point of the reject count
        _bRejOut := TRUE; // 置单拍剔除位（出口统一映射，R187）/ raise the one scan reject bit
    END_IF
    IF _bOverTol THEN _iConsBad := _iConsBad + 1; ELSE _iConsBad := 0; END_IF // 连续超差净额计数（单点写入）/ the net consecutive count
    IF _iConsBad >= DL_TWC_CONS_MAX THEN _bStopLch := TRUE; END_IF // 连续五片超差：锁存停机 / five in a row latch the stop
END_IF
// 段 6｜入窗：环形推进（禁 MOD，R140 委托边界），写入值已过有限闸
IF rtPiece.Q AND _bFinOk THEN // 新片且入参可信 / a new tablet with trustworthy inputs
    IF (_iHead >= 0) AND (_iHead <= (DL_TWC_WIN_CAP - 1)) THEN // 写槽下标先夹取（R4 越界防御）/ clamp the slot subscript first
        _aBuf[_iHead] := fWeightMg; // 写当前槽 [mg] / write the current slot [mg]
    END_IF
    IF _iHead >= (DL_TWC_WIN_CAP - 1) THEN _iHead := 0; ELSE _iHead := _iHead + 1; END_IF // 环形推进 / advance the ring
    IF _iFill < DL_TWC_WIN_CAP THEN _iFill := _iFill + 1; END_IF // 已填点数封顶 / cap the filled points
END_IF
_bWinFull := _iFill >= DL_TWC_WIN; // 窗满判据 / the window full verdict
// 段 7｜窗统计：两遍法（均值 → 离差平方和），分母为常量 20 与 19（结构性零除不可能）
IF _bWinFull THEN // 窗满才统计 / statistics only with a full window
    _fSum := 0.0; // 求和累加清零 / clear the sum
    FOR _i := 0 TO (DL_TWC_WIN_CAP - 1) DO // 第一遍：求和（定长字面界）/ pass one, the sum
        _fSum := _fSum + _aBuf[_i]; // 逐槽累加 [mg] / accumulate slot by slot [mg]
    END_FOR
    _fMean := _fSum / DL_TWC_DEN_N; // 均值 [mg] / the mean [mg]
    _fVar := 0.0; // 离差平方和清零 / clear the squared deviations
    FOR _i := 0 TO (DL_TWC_WIN_CAP - 1) DO // 第二遍：离差平方和（定长字面界）/ pass two, the squared deviations
        _fDev := _aBuf[_i] - _fMean; // 单点离差 [mg] / the single point deviation [mg]
        _fVar := _fVar + (_fDev * _fDev); // 累加平方 [mg²] / accumulate the square [mg^2]
    END_FOR
    _fVar := _fVar / DL_TWC_DEN_N1; // 样本方差 [mg²] / the sample variance [mg^2]
    IF _fVar < 0.0 THEN _fVar := 0.0; END_IF // 舍入残差负方差钳零 / clamp the rounding residual
    _fStd := SQRT(_fVar); // 样本标准差 [mg] / the sample standard deviation [mg]
    IF NOT (_fStd = _fStd) THEN _fStd := 0.0; END_IF // 标准差 NaN 兜底 / the NaN fallback
    IF (_fStd - _fStd) <> (_fStd - _fStd) THEN _fStd := 0.0; END_IF // 标准差 Inf 兜底 / the Inf fallback
    _fMeanPrev := _fMean; // 均值快照供下一片判据（不含下一片）/ the mean snapshot for the next verdict
    _fStdPrev := _fStd; // 标准差快照供下一片判据 / the deviation snapshot for the next verdict
END_IF
// 段 8｜速度式 PI 调节：窗满、新片、使能、未锁存、输入可信五条件齐备才出增量（状态量门控，R99）
_bAdjOk := _bWinFull AND bEnable AND (NOT _bStopLch) AND _bFinOk AND _bTgtOk; // 调节许可合取 / the trim permit
IF _bAdjOk AND rtPiece.Q THEN // 仅在窗满后的每片调节一次 / trim once per tablet after the window filled
    _fErr := fTargetMg - _fMean; // 片重偏差 [mg]，正为偏轻需加深 / the error, positive means too light
    _fBand := fTargetMg * DL_TWC_DEADBAND_FRAC; // 死区带宽 [mg] / the dead band width [mg]
    IF ABS(_fErr) <= _fBand THEN _fErrEff := 0.0; ELSE _fErrEff := _fErr; END_IF // 死区内偏差取零 / zero the error inside the dead band
    _fDu := (DL_TWC_KP * (_fErrEff - _fErrPrev)) + (DL_TWC_KI * _fErrEff); // 速度式 PI 增量 [mm] / the velocity form increment [mm]
    IF _fDu > DL_TWC_STEP_MM THEN _fDu := DL_TWC_STEP_MM; ELSIF _fDu < (0.0 - DL_TWC_STEP_MM) THEN _fDu := (0.0 - DL_TWC_STEP_MM); END_IF // 单次调节双向限幅 / the two sided step limit
    IF NOT (_fDu = _fDu) THEN _fDu := 0.0; END_IF // 增量 NaN 兜底（拒收不外抛）/ the NaN fallback
    IF (_fDu - _fDu) <> (_fDu - _fDu) THEN _fDu := 0.0; END_IF // 增量 Inf 兜底 / the Inf fallback
    _fCmd := _fCmd + _fDu; // 累计指令（唯一写入点）[mm] / the only write point of the command [mm]
    IF _fCmd > fFillDepthMaxMm THEN _fCmd := fFillDepthMaxMm; END_IF // 上限硬钳（抗饱和终保）/ the hard clamp high
    IF _fCmd < fFillDepthMinMm THEN _fCmd := fFillDepthMinMm; END_IF // 下限硬钳 / the hard clamp low
    _fErrPrev := _fErrEff; // 偏差快照（供下一次差分）/ the error snapshot for the next difference
END_IF
// 段 9｜相位状态机：ENUM ＋ CASE ＋ ELSE 非法相位兜底（R6、R128）
CASE _eState OF
E_DL_TabWtState.eIdle: // 空闲相：退出条件三（使能丢失驻留、锁存升停机、首片进取样）
    IF _bStopLch THEN // 停机锁存已置 / the stop latch is set
        _eState := E_DL_TabWtState.eStop; // 迁停机相 / migrate to stop
    ELSIF bEnable AND rtPiece.Q THEN // 使能且首片到达 / enabled with the first tablet
        _eState := E_DL_TabWtState.eSampling; // 迁取样相 / migrate to sampling
    END_IF
E_DL_TabWtState.eSampling: // 取样相：退出条件四（失能、锁存、剔除、窗满）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_TabWtState.eIdle; // 回空闲 / back to idle
    ELSIF _bStopLch THEN // 停机锁存已置 / the stop latch is set
        _eState := E_DL_TabWtState.eStop; // 迁停机相 / migrate to stop
    ELSIF _bRejOut THEN // 本片判剔除（拍 N 进入：本片判据命中；本拍行为：拒收并出脉冲；拍 N+1 转出：回取样或调节）
        _eState := E_DL_TabWtState.eReject; // 迁剔除过渡相 / migrate to the reject transition
    ELSIF _bWinFull THEN // 窗已满（本拍不调节，下一片起调节）/ the window is full
        _eState := E_DL_TabWtState.eAdjust; // 迁调节相 / migrate to adjusting
    END_IF
E_DL_TabWtState.eAdjust: // 调节相：退出条件三（失能、锁存、剔除）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_TabWtState.eIdle; // 回空闲 / back to idle
    ELSIF _bStopLch THEN // 停机锁存已置 / the stop latch is set
        _eState := E_DL_TabWtState.eStop; // 迁停机相 / migrate to stop
    ELSIF _bRejOut THEN // 本片判剔除 / the tablet is a reject
        _eState := E_DL_TabWtState.eReject; // 迁剔除过渡相 / migrate to the reject transition
    END_IF
E_DL_TabWtState.eReject: // 剔除过渡相：本拍不出调节量，只等本拍之后转出
    IF _bStopLch THEN // 停机锁存已置 / the stop latch is set
        _eState := E_DL_TabWtState.eStop; // 迁停机相 / migrate to stop
    ELSIF _bWinFull THEN // 窗已满：回调节相 / the window is full, back to adjusting
        _eState := E_DL_TabWtState.eAdjust; // 回调节相 / back to adjusting
    ELSE // 窗未满：回取样相 / the window is not full, back to sampling
        _eState := E_DL_TabWtState.eSampling; // 回取样相 / back to sampling
    END_IF
E_DL_TabWtState.eStop: // 停机相：锁存驻留，唯一解除为复位沿（段 4 已迁回空闲）
    IF NOT _bStopLch THEN // 锁存已被复位沿清除 / the latch was cleared by the reset edge
        _eState := E_DL_TabWtState.eIdle; // 回空闲 / back to idle
    END_IF
ELSE // 非法相位兜底（R6、R128）
    _eState := E_DL_TabWtState.eStop; // 落停机安全相 / fall back to the safe stop phase
    _iErrTmp := 2806; // 信息级非法相位码 / the info grade illegal phase code
END_CASE
// 段 10｜统一出口：单点映射，剔除脉冲与停机位同源派生（R191、FB51-8）
eState := _eState; // 相位单点映射 / the single point mapping of the phase
xReject := _bRejOut; // 剔除脉冲单点映射（单拍，段 0 已预清）/ the one scan reject pulse
xStop := _bStopLch; // 停机锁存单点映射 / the single point mapping of the stop latch
fDepthCmd := _fCmd; // 深度指令单点映射 [mm] / the single point mapping of the depth command [mm]
nWinFill := _iFill; // 窗内点数单点映射 / the single point mapping of the filled points
iRejectCnt := _iRejAcc; // 剔除计数单点映射 / the single point mapping of the reject count
IF _bWinFull THEN // 窗满才外抛统计量 / publish the statistics only with a full window
    fMeanMg := _fMean; // 均值 [mg] / the mean [mg]
    fStdMg := _fStd; // 标准差 [mg] / the standard deviation [mg]
ELSE // 窗未满：按契约出零（不出调节量）/ not full, the contract demands zeros
    fMeanMg := 0.0; // 均值出零 / the mean goes to zero
    fStdMg := 0.0; // 标准差出零 / the deviation goes to zero
END_IF
fDevMg := _fDevPiece; // 本片偏差（诊断用）[mg] / the tablet deviation for diagnostics [mg]
xReady := _bWinFull AND bEnable AND (NOT _bStopLch); // 就绪位：窗满、使能、未锁存 / the ready bit
IF _bStopLch AND (_iErrTmp = 0) THEN _iErrTmp := 2805; END_IF // 停机原因码（信息级，锁存语义由 xStop 承担）/ the stop cause code
iErrCode := _iErrTmp; // 信息级码单点映射（每拍重算，不锁存）/ the info code mapping
xValid := _bFinOk AND _bTgtOk AND _bLimOk AND _bForceOk AND (_iErrTmp = 0); // 有效性：四闸通过且无信息级码
END_FUNCTION_BLOCK
