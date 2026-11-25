(*
    FB_DL_GantryDualDriveTorqueBalance —— 龙门双驱转矩失衡评估与从动侧偏置自适应
    ------------------------------------------------------------------
    组件名    : FB_DL_GantryDualDriveTorqueBalance
    分类      : DL_Motion / Dual-Drive Balance（双驱转矩均衡）
    一句话功能: 在线评估龙门双驱的转矩失衡，带死区按周期步进调整从动侧转矩偏置，
                失衡恶化时输出降速比例保护机械。
    复杂度    : C3
    版本      : v1.0.0
    开源溯源  : 无（clean-room 自研，未借鉴任何开源实现）
    平台      : 纯 IEC 61131-3（TON / R_TRIG / ABS 标准库），目标编译器 RuSTy 1.0.8，
                兼容 CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
                无 PROPERTY、无 VLA、无 FOR..DOWNTO、无 AS 类方言
    ------------------------------------------------------------------
    功能说明  : ① 失衡度 fImbalancePct = ABS(fTorqueMasterPct − fTorqueSlavePct)，单位 %；
                ② 死区：失衡 ≤ fBalanceTolPct 时完全不调整偏置（防积分漂移抖动），
                   且 bBalanced := TRUE；
                ③ 调整：失衡 > 死区且处 eBiasAdj 相时，每 tBiasPeriodMs（TON 自复位，R188）
                   按 fBiasStepPct 朝「减小失衡」的方向步进一次 fBiasOutPct，并钳位在
                   ±fMaxBiasPct；方向约定：主轴转矩大（从动侧出力不足）→ 偏置加，反之偏置减；
                ④ 降额：失衡 > fBalanceTolPct × fDerateRatio → eDerate，fSpeedScalePct 从 100
                   线性降到 50 并饱和；恢复带滞回 fThDerate − DL_GB_HYS_PCT，防临界抖动；
                ⑤ 安全默认：bReset 上升沿与 eFault 相内 fBiasOutPct 一律清 0（不带偏置上电）；
                ⑥ 转矩读数非有限（NaN / ±Inf / 超幅值域）→ eFault，fSpeedScalePct := 0。
    量纲链    : fTorqueMasterPct [%] − fTorqueSlavePct [%] → 失衡度 fImbalancePct [%]（同类量相减）；
                fBalanceTolPct [%] × fDerateRatio [-] → 降额阈值 fThDerate [%]（比例无因次）；
                (fImbalancePct − fThDerate) [%] ÷ fThDerate [%] → _fRto [-]（% ÷ % 无因次）；
                fSpeedScalePct = 100 [%] − (100 − 50)[%] × _fRto [-] → [%]；
                fBiasStepPct [%] 逐拍累加到 fBiasOutPct [%]，钳位界 ±fMaxBiasPct [%]。
                全程无「温度、时间、角度进入转矩加法链」，量纲链逐段闭合。
    状态机    : eIdle(0) --使能且组态合法且数据有限--> eBalance(10)
                eBalance --失衡 > 死区--> eBiasAdj(20)；--失衡 > 降额阈值--> eDerate(30)
                eBiasAdj --失衡回到死区内--> eBalance（偏置保持）；--失衡 > 降额阈值--> eDerate
                eDerate --失衡 ≤ 降额阈值 − DL_GB_HYS_PCT--> 回到 eBalance 或 eBiasAdj
                任意相 --失能--> eIdle；--数据非有限或组态非法--> eFault(90)
                eFault 的唯一解除路径 = bReset 上升沿（见段 8 与复位作用域声明）
    失能语义  : bEnable = FALSE → eIdle，fBiasOutPct 清 0、fSpeedScalePct 清 0（安全侧：不带偏置、
                不发放行），不冻结末次偏置 —— 双驱偏置在无人监控时保持是有害的（R191 显式声明）。
    复位作用域: bReset 上升沿①清 _bFaultLatch / _bBadIn / _bCfgBad；②fBiasOutPct 清 0 且
                _fBias 清 0（偏置不得跨复位继承）；③迁相回 eIdle；④不清 _fImb（下一拍重算）。
    防御口径  : NaN 用自反 f<>f；±Inf 用 (f−f)<>(f−f)；另设幅值域闸 ABS(f) > 1.0E30。
                除法前先判零：降额归一的分母 fThDerate 与 DL_GB_EPS 比较后才做除法，组态闸另
                强制 fBalanceTolPct > DL_GB_EPS 且 fDerateRatio > 1.0，使分母结构性为正。
                周期调整 TON 的 IN 由自身 Q 取反驱动（IN := NOT tonBias.Q ...），不依赖外部沿（R188）。
    规格补充  : 按 R190 归因唯一补充 bCfgErr / bDataErr 两个诊断位，使两条故障成因各自可观测。
    码位说明  : 本件按零码位范式交付，不分配 16# 事件码；失衡、降额与故障一律经
                eState / bBalanced / bFaultOut / bCfgErr / bDataErr 组合观测。
    修订记录  : 2026-11-24 v1.0.0 首次入库（R87 批 · #4）
*)
TYPE E_DL_BalanceState :
(
    eIdle    := 0,    // 空闲：未使能，偏置与放行均清 0 | idle, disabled, bias and release both zeroed
    eBalance := 10,   // 均衡：失衡在死区内，偏置保持不动 | balanced, imbalance inside the dead band, bias held
    eBiasAdj := 20,   // 偏置调整：按周期步进偏置以减小失衡 | bias adjustment, stepped once per period
    eDerate  := 30,   // 降额：失衡超降额阈值，输出降速比例 < 100 | derate, speed scale below 100
    eFault   := 90    // 故障：读数非有限或组态非法，锁存至复位沿 | fault latched until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_GantryDualDriveTorqueBalance
VAR_INPUT
    bEnable          : BOOL;                      // 使能电平，TRUE = 允许评估与调整 | enable level, TRUE = evaluation and adjustment active
    bReset           : BOOL;                      // 复位请求，上升沿生效 | reset request, rising-edge active
    fTorqueMasterPct : REAL;                      // 主轴转矩百分比 [%]，可为负（回馈）| master torque [%], negative on regen
    fTorqueSlavePct  : REAL;                      // 从动轴转矩百分比 [%] | slave torque [%]
    fBalanceTolPct   : REAL := 5.0;               // 失衡死区（容差）[%]，须为正 | imbalance dead band [%]
    fMaxBiasPct      : REAL := 10.0;              // 偏置钳位上限 [%]，须为正 | bias clamp magnitude [%]
    fDerateRatio     : REAL := 3.0;               // 降额阈值相对死区的倍数 [-]，须 > 1 | derate threshold as a multiple of the band
    fBiasStepPct     : REAL := 0.5;               // 每周期偏置步长 [%]，须为正 | bias step per period [%]
    tBiasPeriodMs    : TIME := T#500MS;           // 偏置步进周期 [ms] | bias step period [ms]
END_VAR
VAR_OUTPUT
    eState           : E_DL_BalanceState;         // 主状态，供 HMI 与联锁使用 | main state for HMI and interlocks
    fImbalancePct    : REAL;                      // 本拍失衡度 [%] | imbalance this scan [%]
    fBiasOutPct      : REAL;                      // 从动侧转矩偏置指令 [%]，正 = 增加从动侧出力 | slave torque bias [%]
    fSpeedScalePct   : REAL;                      // 派生速度比例指令 [%]，100 = 不限速 | derived speed scale [%]
    bBalanced        : BOOL;                      // 失衡在死区内 | imbalance inside the dead band
    bFaultOut        : BOOL;                      // 故障汇总位 | fault aggregate
    bCfgErr          : BOOL;                      // 组态非法诊断位（归因唯一，R190）| bad-configuration flag
    bDataErr         : BOOL;                      // 数据非有限诊断位（归因唯一，R190）| non-finite data flag
END_VAR
VAR
    rtReset          : R_TRIG;                    // 复位上升沿实例，每拍无条件刷新 | reset rising-edge instance
    tonBias          : TON;                       // 偏置步进周期计时，自复位，每拍无条件刷新 | bias step period timer
    _eState          : E_DL_BalanceState := E_DL_BalanceState.eIdle; // 状态机内部当前态 | internal current state
    _bInit           : BOOL := TRUE;              // 首扫初始化标志，含偏置积分状态 | first-scan init flag
    _bResetLatch     : BOOL := FALSE;             // 复位沿锁存量，本拍末清除 | reset-edge latch, cleared at scan end
    _bFaultLatch     : BOOL := FALSE;             // 故障锁存位 | fault latch
    _bBadIn          : BOOL := FALSE;             // 数据非有限成因位 | non-finite data cause
    _bCfgBad         : BOOL := FALSE;             // 组态非法成因位 | bad configuration cause
    _fBias           : REAL := 0.0;               // 偏置累积值 [%] | accumulated bias [%]
    _fImb           : REAL := 0.0;                // 本拍失衡度 [%] | imbalance this scan [%]
    _fThDerate       : REAL := 0.0;               // 本拍降额阈值 [%] | derate threshold this scan [%]
    _fThRecover      : REAL := 0.0;               // 本拍降额恢复阈值 [%] | derate recovery threshold this scan [%]
    _fDen            : REAL := 0.0;               // 降额归一除子 [%] | derate normalisation divisor [%]
    _fRto            : REAL := 0.0;               // 降额带内归一比例 [0..1] | normalised ratio inside the derate band
END_VAR
VAR CONSTANT
    DL_GB_EPS        : REAL := 1.0E-6;            // 浮点判零容差 [%] | float zero tolerance [%]
    DL_GB_MAG_MAX    : REAL := 1.0E30;            // 有限幅值域闸上限 [%] | magnitude domain bound [%]
    DL_GB_SCALE_FULL : REAL := 100.0;             // 满速比例 [%] | full speed scale [%]
    DL_GB_SCALE_MIN  : REAL := 50.0;              // 降额最低速度比例 [%] | minimum derated speed scale [%]
    DL_GB_HYS_PCT    : REAL := 2.0;               // 降额恢复滞回带 [%] | derate release hysteresis [%]
    DL_GB_RATIO_MIN  : REAL := 1.0;               // 降额倍数的下界 [-]（须严格大于该值）| lower bound of the derate multiple
END_VAR

METHOD ClampBias : REAL
(*
    偏置钳位：把偏置钳到 ±fMaxBiasPct（调用方保证 fMaxBiasPct > 0 且有限）。纯函数，无跨拍状态。
    Clamp the bias to plus or minus the configured magnitude; the caller guarantees a positive finite limit.
*)
VAR_INPUT
    fIn   : REAL;                                 // 待钳偏置 [%] | bias to clamp [%]
    fLimit: REAL;                                 // 钳位界（正数）[%] | clamp magnitude, positive [%]
END_VAR
ClampBias := fIn;                                 // 直通后按两侧硬界饱和 | straight-through, saturated below
IF ClampBias > fLimit THEN
    ClampBias := fLimit;                          // 正向钳到 +界 [%] | clamp to the positive limit
END_IF
IF ClampBias < (0.0 - fLimit) THEN
    ClampBias := 0.0 - fLimit;                    // 负向钳到 −界 [%] | clamp to the negative limit
END_IF
END_METHOD

// 段 1｜输出预置与首扫初始化（含偏置积分状态，故必须有 _bInit，R310）
// segment 1, output presets and first-scan initialisation; the bias integrator requires _bInit
fSpeedScalePct := 0.0;                             // 预置速度比例 0 [%]，放行默认撤销 | preset zero speed scale
bBalanced := FALSE;                                // 预置非均衡 | preset not balanced
fBiasOutPct := 0.0;                                // 预置偏置 0 [%] | preset zero bias
_bBadIn := FALSE;                                  // 预置数据有限 | preset finite data
_bCfgBad := FALSE;                                 // 预置组态合法 | preset legal configuration
IF _bInit THEN
    _bInit := FALSE;                               // 首扫只执行一次 | runs once on the first scan
    _eState := E_DL_BalanceState.eIdle;            // 首扫状态回空闲相 | initialise the state
    _fBias := 0.0;                                 // 首扫偏置归零 [%]，不带偏置上电 | initial bias [%]
END_IF

// 段 2｜非有限闸：NaN 自反 + Inf 自减 + 幅值域，逐个浮点入参枚举（R4 / R151 / R272）
// segment 2, non-finite gate over every REAL input: NaN self-reflexive, Inf by self-subtraction, magnitude bound
IF (fTorqueMasterPct <> fTorqueMasterPct) OR ((fTorqueMasterPct - fTorqueMasterPct) <> (fTorqueMasterPct - fTorqueMasterPct)) THEN
    _bBadIn := TRUE;                               // 主轴转矩 NaN 或 ±Inf | master torque NaN or infinity
END_IF
IF ABS(fTorqueMasterPct) > DL_GB_MAG_MAX THEN
    _bBadIn := TRUE;                               // 主轴转矩超幅值域 | master torque beyond the magnitude domain
END_IF
IF (fTorqueSlavePct <> fTorqueSlavePct) OR ((fTorqueSlavePct - fTorqueSlavePct) <> (fTorqueSlavePct - fTorqueSlavePct)) THEN
    _bBadIn := TRUE;                               // 从动轴转矩 NaN 或 ±Inf | slave torque NaN or infinity
END_IF
IF ABS(fTorqueSlavePct) > DL_GB_MAG_MAX THEN
    _bBadIn := TRUE;                               // 从动轴转矩超幅值域 | slave torque beyond the magnitude domain
END_IF
IF (fBalanceTolPct <> fBalanceTolPct) OR ((fBalanceTolPct - fBalanceTolPct) <> (fBalanceTolPct - fBalanceTolPct)) THEN
    _bBadIn := TRUE;                               // 死区 NaN 或 ±Inf | dead band NaN or infinity
END_IF
IF (fMaxBiasPct <> fMaxBiasPct) OR ((fMaxBiasPct - fMaxBiasPct) <> (fMaxBiasPct - fMaxBiasPct)) THEN
    _bBadIn := TRUE;                               // 偏置上限 NaN 或 ±Inf | bias limit NaN or infinity
END_IF
IF (fDerateRatio <> fDerateRatio) OR ((fDerateRatio - fDerateRatio) <> (fDerateRatio - fDerateRatio)) THEN
    _bBadIn := TRUE;                               // 降额倍数 NaN 或 ±Inf | derate multiple NaN or infinity
END_IF
IF (fBiasStepPct <> fBiasStepPct) OR ((fBiasStepPct - fBiasStepPct) <> (fBiasStepPct - fBiasStepPct)) THEN
    _bBadIn := TRUE;                               // 步长 NaN 或 ±Inf | bias step NaN or infinity
END_IF
IF ABS(fBalanceTolPct) > DL_GB_MAG_MAX THEN
    _bBadIn := TRUE;                               // 死区超幅值域 | dead band beyond the magnitude domain
END_IF
IF ABS(fMaxBiasPct) > DL_GB_MAG_MAX THEN
    _bBadIn := TRUE;                               // 偏置上限超幅值域 | bias limit beyond the magnitude domain
END_IF
IF ABS(fDerateRatio) > DL_GB_MAG_MAX THEN
    _bBadIn := TRUE;                               // 降额倍数超幅值域 | derate multiple beyond the magnitude domain
END_IF
IF ABS(fBiasStepPct) > DL_GB_MAG_MAX THEN
    _bBadIn := TRUE;                               // 步长超幅值域 | bias step beyond the magnitude domain
END_IF

// 段 3｜组态闸：死区与偏置上限与步长须为正，降额倍数须严格大于 1（保证降额阈值高于死区）
// segment 3, configuration gate: band, bias limit and step must be positive, the derate multiple must exceed one
IF fBalanceTolPct <= DL_GB_EPS THEN
    _bCfgBad := TRUE;                              // 死区非正：失衡判据无意义 | non-positive dead band
END_IF
IF fMaxBiasPct <= DL_GB_EPS THEN
    _bCfgBad := TRUE;                              // 偏置上限非正：钳位界非法 | non-positive bias limit
END_IF
IF fBiasStepPct <= DL_GB_EPS THEN
    _bCfgBad := TRUE;                              // 步长非正：调整永不生效 | non-positive bias step
END_IF
IF fDerateRatio <= (DL_GB_RATIO_MIN + DL_GB_EPS) THEN
    _bCfgBad := TRUE;                              // 降额倍数不大于 1：降额阈值落进死区 | derate multiple not above one
END_IF
IF tBiasPeriodMs <= T#0S THEN
    _bCfgBad := TRUE;                              // 步进周期非正：TON 无意义 | non-positive step period
END_IF

// 段 4｜失衡度与阈值（每拍全量重算，无跨拍状态驻留）
// segment 4, imbalance and thresholds, fully recomputed every scan with no cross-scan state
IF (NOT _bBadIn) AND (NOT _bCfgBad) THEN
    _fImb := ABS(fTorqueMasterPct - fTorqueSlavePct); // 失衡度 [%] = |[%] − [%]| | imbalance [%]
    _fThDerate := fBalanceTolPct * fDerateRatio;   // 降额阈值 [%] = [%] × [-] | derate threshold [%]
    _fThRecover := _fThDerate - DL_GB_HYS_PCT;     // 降额恢复阈值 [%] = [%] − [%] | derate release threshold [%]
    IF _fImb <= fBalanceTolPct THEN
        bBalanced := TRUE;                         // 失衡在死区内：判定均衡 | balanced inside the dead band
    END_IF
ELSE
    _fImb := 0.0;                                  // 闸门未过：失衡度置 0，绝不让 NaN 外泄到输出 | gated, never leak NaN downstream
    _fThDerate := 0.0;                             // 闸门未过：降额阈值置 0 [%] | derate threshold zeroed
    _fThRecover := 0.0;                            // 闸门未过：恢复阈值置 0 [%] | release threshold zeroed
END_IF

// 段 5｜定时器与沿实例无条件周期刷新（R7）；步进周期 TON 自复位（R188）
// segment 5, timers and edge instances refreshed unconditionally; the step timer is self-resetting
rtReset(CLK := bReset);
tonBias(IN := (NOT tonBias.Q) AND bEnable AND (NOT _bFaultLatch) AND (_fImb > fBalanceTolPct), PT := tBiasPeriodMs);
IF rtReset.Q THEN
    _bResetLatch := TRUE;                          // 复位沿存锁存量，段 8 统一消费 | store the reset edge, consumed in segment 8
END_IF

// 段 6｜复位沿与故障锁存（复位先执行，保证本拍新故障不被抹除，R275）
// segment 6, reset edge and fault latches; reset runs first so a same-scan fault survives
IF _bResetLatch THEN
    _bFaultLatch := FALSE;                         // 清故障锁存 | clear the fault latch
    _bBadIn := FALSE;                              // 清数据非有限成因位 | clear the non-finite cause
    _bCfgBad := FALSE;                             // 清组态非法成因位（下一拍按新参数重判）| clear the configuration cause
    _fBias := 0.0;                                 // 偏置清 0 [%]：偏置不得跨复位继承 | bias cleared, never inherited across a reset
    _eState := E_DL_BalanceState.eIdle;            // 迁相回空闲 | return to idle
END_IF
IF _bBadIn AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                          // 锁存数据非有限（独立成因）| latch the non-finite cause
    _eState := E_DL_BalanceState.eFault;           // 与锁存同拍迁相（R258）| migrate in the same scan
END_IF
IF _bCfgBad AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                          // 锁存组态非法（独立成因）| latch the configuration cause
    _eState := E_DL_BalanceState.eFault;           // 与锁存同拍迁相（R258）| migrate in the same scan
END_IF

// 段 7｜主状态机：ENUM + CASE + ELSE 兜底（R6）；偏置步进只在 eBiasAdj 相内执行
// segment 7, main state machine with ENUM + CASE + ELSE fallback; bias stepping runs only inside eBiasAdj
CASE _eState OF
E_DL_BalanceState.eIdle:
    fSpeedScalePct := 0.0;                         // 空闲相速度比例 0 [%] | idle phase keeps the scale at zero
    _fBias := 0.0;                                 // 空闲相偏置清 0 [%]：不带偏置待机 | idle phase holds no bias
    // 拍 N 进入：首扫、复位沿或失能；本拍行为：偏置与放行均清 0，拒绝步进；
    // 拍 N+1 转出：使能且组态合法且数据有限 → eBalance
    // entered on the first scan, the reset edge or on disable; both the bias and the release are zeroed;
    // exits to eBalance once enabled with legal configuration and finite data
    IF bEnable AND (NOT _bCfgBad) AND (NOT _bBadIn) AND (NOT _bFaultLatch) THEN
        _eState := E_DL_BalanceState.eBalance;
    END_IF

E_DL_BalanceState.eBalance:
    fSpeedScalePct := DL_GB_SCALE_FULL;            // 均衡相满速 100 [%] | balanced phase runs at full scale
    IF NOT bEnable THEN
        _eState := E_DL_BalanceState.eIdle;         // 失能回空闲（偏置随之清 0）| disable returns to idle and clears the bias
    ELSIF _fImb > _fThDerate THEN
        _eState := E_DL_BalanceState.eDerate;       // 恶化到降额带 | worsen into the derate band
    ELSIF _fImb > fBalanceTolPct THEN
        _eState := E_DL_BalanceState.eBiasAdj;      // 超出死区：进偏置调整相 | outside the dead band, adjust the bias
    END_IF

E_DL_BalanceState.eBiasAdj:
    fSpeedScalePct := DL_GB_SCALE_FULL;            // 调整相仍满速 100 [%] | the adjustment phase still runs at full scale
    IF NOT bEnable THEN
        _eState := E_DL_BalanceState.eIdle;         // 失能回空闲 | disable returns to idle
    ELSIF _fImb > _fThDerate THEN
        _eState := E_DL_BalanceState.eDerate;       // 恶化到降额带（本相不再步进）| worsen into the derate band, stepping stops
    ELSIF _fImb <= fBalanceTolPct THEN
        _eState := E_DL_BalanceState.eBalance;      // 回到死区内：停步进，偏置保持 | back inside the band, bias held
    ELSE
        IF tonBias.Q THEN
            // 死区内不动作：此分支只在 _fImb > fBalanceTolPct 时可达，死区由上层判据与 TON 的 IN 双重保证
            // no action inside the dead band: this branch is reachable only above the band, guarded twice
            IF fTorqueMasterPct > fTorqueSlavePct THEN
                _fBias := _fBias + fBiasStepPct;    // 主轴出力偏大 → 增加从动侧偏置 [%] | master carries more, raise the slave bias
            ELSE
                _fBias := _fBias - fBiasStepPct;    // 从动侧出力偏大 → 减小偏置 [%] | slave carries more, lower the bias
            END_IF
            _fBias := ClampBias(_fBias, fMaxBiasPct); // 钳位在 ±fMaxBiasPct [%] | clamp the bias [%]
        END_IF
    END_IF

E_DL_BalanceState.eDerate:
    // 降额比例：失衡从降额阈值升到 2 倍降额阈值的过程中，速度比例从 100 线性降到 50 并饱和
    // derate scale: linear descent from 100 to 50 while the imbalance runs from the threshold to twice the threshold
    _fDen := _fThDerate;                           // 归一除子 [%] | normalisation divisor [%]
    IF _fDen > DL_GB_EPS THEN
        _fRto := (_fImb - _fThDerate) / _fDen;      // 归一比例 [-] = [%] ÷ [%]，先判零再除 | guarded division
    ELSE
        _fRto := 1.0;                              // 除子退化（组态闸已禁）→ 保守取饱和比例 | degenerate divisor, take saturation
    END_IF
    _fRto := ClampBias(_fRto, DL_GB_RATIO_MIN);    // 归一比例先钳到 [−1,1]（限值取 1.0）| clamp the ratio into the unit band
    IF _fRto < 0.0 THEN
        _fRto := 0.0;                              // 下限再钳：滞回带内不得反向抬高速度比例 | lower clamp, never raise the scale
    END_IF
    fSpeedScalePct := DL_GB_SCALE_FULL - (DL_GB_SCALE_FULL - DL_GB_SCALE_MIN) * _fRto; // [%] − [%] × [-] | derated scale [%]
    IF NOT bEnable THEN
        _eState := E_DL_BalanceState.eIdle;         // 失能回空闲 | disable returns to idle
    ELSIF _fImb <= _fThRecover THEN
        IF _fImb <= fBalanceTolPct THEN
            _eState := E_DL_BalanceState.eBalance;  // 已回到死区内 | back inside the dead band
        ELSE
            _eState := E_DL_BalanceState.eBiasAdj;  // 回到滞回带内但仍在死区外：继续调偏置 | resume bias adjustment
        END_IF
    END_IF

E_DL_BalanceState.eFault:
    fSpeedScalePct := 0.0;                         // 故障相速度比例 0 [%]，撤放行 | fault phase withdraws the release
    _fBias := 0.0;                                 // 故障相偏置清 0 [%]：安全默认不带偏置 | fault phase holds no bias
    // 驻留语义：本相只能由段 6 的复位沿迁出（唯一解除路径）；成因经 _bBadIn / _bCfgBad 分别观测
    // dwell semantics: left only through the reset edge in segment 6; causes observed via _bBadIn and _bCfgBad

ELSE
    // 非法枚举值（越界或未定义成员）：不猜，清偏置与放行并回故障相
    // illegal enumerator: no guessing, clear the bias and the release, then return to the fault phase
    fSpeedScalePct := 0.0;
    _fBias := 0.0;
    _bFaultLatch := TRUE;
    _eState := E_DL_BalanceState.eFault;
END_CASE;

// 段 8｜出口单点映射（偏置与放行在本段统一对外，CASE 后不再无条件清零 CASE 内写入量，R187）
// segment 8, single-point output mapping; nothing written inside the CASE is cleared afterwards
eState := _eState;                                 // 状态映射 | state mapping
fImbalancePct := _fImb;                            // 失衡度映射 [%] | imbalance mapping [%]
fBiasOutPct := _fBias;                             // 偏置映射 [%] | bias mapping [%]
bFaultOut := _bFaultLatch;                         // 故障锁存回放 | replay the fault latch
bCfgErr := _bCfgBad;                               // 组态非法诊断位 | bad-configuration diagnostic
bDataErr := _bBadIn;                               // 数据非有限诊断位 | non-finite data diagnostic
IF _bFaultLatch THEN
    fBiasOutPct := 0.0;                            // 故障锁存期间偏置强制 0 [%]（安全默认双保险）| bias forced to zero while latched
END_IF

// 段 9｜本拍消费量收尾（仅清沿锁存；不触碰任何锁存位与 CASE 内写入量）
// segment 9, end-of-scan cleanup; only the edge latch is cleared
_bResetLatch := FALSE;
END_FUNCTION_BLOCK
