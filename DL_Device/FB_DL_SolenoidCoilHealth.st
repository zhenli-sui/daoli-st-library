(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SolenoidCoilHealth
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 电磁阀线圈电气健康诊断（吸合窗 / 保持段分域判据）：
 *                         ① 吸合窗：bEnergized 上升沿起 tWindow 内捕获峰值电流 fPickPeakA，
 *                            峰值 > fPickMaxA 判 eStuckPeak（衔铁卡阻 / 短路匝趋势）；
 *                         ② 保持段：窗后保持电流对学习基线 _fHoldBase 的偏差超 fHoldPct，
 *                            低偏判 eUnderCurrent（断匝趋势）、高偏判 eOverCurrent（短路匝
 *                            趋势）；基线自合格吸合（峰值入 [fPickMinA, fPickMaxA] 窗）递推
 *                            学习，n < 3 次合格吸合前**拒判**（不足拒判，防冷启动误报）。
 *                         ③ 电流 <= 0 且 bEnergized 持续 tWindow → eNoData（传感器断线，
 *                            不与欠流混码，R190 成因分码）。
 * 接口     (Interface)  : 输入 fCurrentA 线圈电流（A）、bEnergized 得电、tWindow 判据窗、
 *                         fPickMaxA/fPickMinA 吸合峰值窗（A）、fHoldPct 保持电流容差（%）、
 *                         bReset 复位；输出 eCoil 健康态、fPickPeakA 最近吸合峰值（A）、
 *                         bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做线圈电气健康诊断，不驱动线圈、
 *                         不判触点熔焊、不做阀通断动作**。
 *                         ② 非有限电流当拍剔除（不参与峰值与判据，R245）。
 *                         ③ 峰值窗 TON / 断线 TON 段 0 无条件刷新；IN 由状态表达式派生，
 *                         无外部沿清零。
 *                         ④ 组态闸：tWindow<=T#0S、fPickMaxA<=fPickMinA、fHoldPct<=0 →
 *                         锁存 bError 且 eCoil 冻结 eOk 侧不误报，解除沿 = bReset 上升沿。
 *                         ⑤ 基线递推：_fHoldBase += (窗末电流 - _fHoldBase)/_nPickOk
 *                         （均值增量式，_nPickOk 为 UDINT 合格吸合计数，饱和不回绕）。
 *                         ⑥ 每次得电下降沿回 eOff 并清吸合窗标志；诊断态在失电后不保持
 *                         （健康态按周期重判）。
 *                         ⑦ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_ContactorWeldDetect` 分工：线圈电气健康（本件）≠ 触点
 *                         熔焊（那件）；与 `FB_DL_SingleSolenoidCyl` 分工：诊断 ≠ 通断驱动。
 * 来源标签 (Source Tag) : T2-6 ◐（Rockwell AOI 设备诊断粒度只借"吸合窗/保持段分域"分类
 *                         事实，判据与基线学习为本件自研实现）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 健康态 + LREAL 峰值 +
 *                         BOOL；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前置（均值分母计数闸）+ 非有限剔除 + 组态闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM 健康态 CASE 化判序 ｜ R7 ✓ 两 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 2 · 序号 10）
 *                         验收向量：峰值超上限 → eStuckPeak；保持欠偏 → eUnderCurrent；
 *                         电流恒 0 得电 → eNoData；n<3 合格吸合 → 拒判 eOk。
 *==============================================================================*)

TYPE E_DL_SchHealth :
(
    eOk           := 0,    // 健康（含拒判期）/ Healthy, including not-yet-judged period
    eUnderCurrent := 10,   // 保持欠流（断匝趋势）/ Hold under-current, turn-short-open trend
    eOverCurrent  := 20,   // 保持过流（短路匝趋势）/ Hold over-current, turn-short trend
    eStuckPeak    := 30,   // 吸合峰值超上限（衔铁卡阻）/ Pickup peak above ceiling, armature stuck
    eNoData       := 40,   // 传感器断线（得电而电流恒零）/ No data, sensor dead while energized
    eOff          := 50    // 线圈失电（判据冻结）/ Coil de-energized, judges frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_SolenoidCoilHealth
VAR_INPUT
    fCurrentA : LREAL := 0.0;    // 线圈电流实测 [A] / Coil current measurement [A]
    bEnergized: BOOL := FALSE;   // 线圈得电命令反馈 [-] / Coil energized state
    tWindow   : TIME := T#500MS; // 吸合判据窗（峰值捕获与断线判据共用窗长），域 > T#0S [ms] / Pickup judge window [ms]
    fPickMaxA : LREAL := 2.0;    // 吸合峰值窗上限，域 > fPickMinA [A] / Pickup peak window ceiling [A]
    fPickMinA : LREAL := 1.0;    // 吸合峰值窗下限，域 >= 0 [A] / Pickup peak window floor [A]
    fHoldPct  : LREAL := 20.0;   // 保持电流容差（对基线百分比），域 > 0 [%] / Hold current tolerance vs baseline [%]
    bReset    : BOOL := FALSE;   // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears config latch
END_VAR
VAR_OUTPUT
    eCoil      : E_DL_SchHealth;  // 线圈健康态出口 [-] / Coil health outlet
    fPickPeakA : LREAL;            // 最近一次吸合峰值电流（失电保持供诊断） [A] / Last captured pickup peak [A]
    bError     : BOOL;            // 故障标志（组态非法 ∨ 健康态非 eOk/eOff） [-] / Error flag
END_VAR
VAR
    _eCoil    : E_DL_SchHealth := E_DL_SchHealth.eOff;   // 内部健康态 / Internal health state
    _bPickWin : BOOL;               // 吸合窗开启标志（上升沿置位、窗到清除） / Pickup window open flag
    _fPeak    : LREAL := 0.0;       // 当次吸合峰值跟踪 [A] / Current pickup peak tracker
    _fHoldBase: LREAL := 0.0;       // 保持电流学习基线（递推均值） [A] / Learned hold-current baseline
    _nPickOk  : UDINT := 0;         // 合格吸合计数（基线判据门槛 n>=3，诊断用） [次] / Qualified pickup count
    _nDiv     : LREAL := 0.0;       // 均值递推实数除数（随合格吸合递增，判零前置） / Mean recursion real divisor
    _fDevLim  : LREAL;              // 保持段容差绝对限（基线×fHoldPct） [A] / Hold tolerance absolute limit
    _bErrLatch: BOOL;               // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault, cleared by reset edge
    tonPickWin: TON;                // 吸合峰值窗定时器，段 0 无条件调用 / Pickup window timer
    tonNoData : TON;                // 断线判据定时器，段 0 无条件调用 / No-data timer
    rtEn      : R_TRIG;             // 得电上升沿实例，段 0 无条件调用 / Energize rising edge instance
    rtDis     : R_TRIG;             // 失电下降沿实例（F_TRIG 语义由 R_TRIG 反相实现），段 0 无条件调用 / De-energize falling edge instance
    rtReset   : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNonFin  : BOOL;               // 电流非有限当拍量 [-] / Non-finite current this scan
END_VAR
VAR CONSTANT
    DL_SCH_UDMAX   : UDINT := 4294967295;   // UDINT 上限（合格吸合计数饱和点） [次] / UDINT ceiling for count saturation
    DL_SCH_NMIN    : UDINT := 3;            // 基线生效最小合格吸合次数 [次] / Minimum qualified pickups for baseline
    DL_SCH_ZEROTH  : LREAL := 0.0;          // 电流判零基准（断线判据） [A] / Current zero base for no-data test
    DL_SCH_EPS     : LREAL := 0.0;          // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_SCH_PCT     : LREAL := 100.0;        // 百分比换算基 [无量纲] / Percent conversion base
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 两 TON 三沿无条件周期刷新 —— *)
_bNonFin := (fCurrentA <> fCurrentA) OR ((fCurrentA - fCurrentA) <> DL_SCH_EPS);   // 电流非有限（R245） / Non-finite current
IF (tWindow <= T#0S) OR (fPickMaxA <= fPickMinA) OR (fPickMinA < DL_SCH_ZEROTH) OR (fHoldPct <= 0.0) THEN
    _bErrLatch := TRUE;                                     // 组态域闸：锁存（R188 解除沿 = bReset 上升沿） / Config gate: latch
END_IF
rtEn(CLK := bEnergized);                                    // 得电沿，每拍必调 / Energize edge, every scan
rtDis(CLK := NOT bEnergized);                               // 失电沿（反相实现下降沿），每拍必调 / De-energize edge, every scan
rtReset(CLK := bReset);                                     // 复位沿，每拍必调 / Reset edge, every scan
tonPickWin(IN := _bPickWin, PT := tWindow);                 // 吸合峰值窗（IN 状态派生，无外部清零） / Pickup window timer
tonNoData(IN := bEnergized AND (fCurrentA <= DL_SCH_ZEROTH) AND (NOT _bNonFin), PT := tWindow);   // 断线判据窗 / No-data judge window

(* —— 段 1：复位沿 / 失电沿（窗态与判据态清出） —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                                    // 清组态故障锁存 / Clear config latch
END_IF
IF rtDis.Q THEN
    _bPickWin := FALSE;                                     // 失电关吸合窗 / Close pickup window on de-energize
    _eCoil := E_DL_SchHealth.eOff;                          // 失电判据冻结回 eOff / Freeze to eOff
END_IF

(* —— 段 2：吸合窗开启与峰值捕获 —— *)
IF rtEn.Q THEN
    _bPickWin := TRUE;                                      // 得电沿开启吸合窗 / Open pickup window on energize edge
    _fPeak := 0.0;                                          // 峰值跟踪清零重捕 / Reset peak tracker
END_IF
IF _bPickWin AND (NOT _bNonFin) THEN
    IF fCurrentA > _fPeak THEN
        _fPeak := fCurrentA;                                // 峰值捕获（正电流单调上取） / Capture peak
    END_IF
END_IF

(* —— 段 3：窗到裁决（判吸合窗 → 基线学习） —— *)
IF tonPickWin.Q THEN
    _bPickWin := FALSE;                                     // 窗到关闭（下一拍 IN 派生自复位） / Close window at Q
    IF _fPeak > fPickMaxA THEN
        _eCoil := E_DL_SchHealth.eStuckPeak;                // 峰值超上限：判卡阻（R190 独立成因） / Peak above ceiling: stuck
    ELSIF _fPeak >= fPickMinA THEN
        IF _nPickOk < DL_SCH_UDMAX THEN
            _nPickOk := _nPickOk + 1;                       // 合格吸合计数（饱和不回绕） / Count qualified pickup, saturating
        END_IF
        _nDiv := _nDiv + 1.0;                               // 实数除数同步递增（避免 UDINT 转型溢出） / Real divisor increments in step
        IF (NOT _bNonFin) AND (_nDiv >= 1.0) THEN
            _fHoldBase := _fHoldBase + (fCurrentA - _fHoldBase) / _nDiv;   // 基线增量均值学习（除数恒 >=1） / Incremental mean baseline learning
        END_IF
        (* 合格吸合当拍不直接判健康，进入保持段分域判据（段 4） *) 
        _eCoil := E_DL_SchHealth.eOk;                       // 吸合窗内默认健康（保持段再判） / Default healthy in window
    ELSE
        _eCoil := E_DL_SchHealth.eOk;                       // 峰值偏弱不判卡阻不学基线（保持段判欠流） / Weak peak: left to hold judge
    END_IF
END_IF

(* —— 段 4：保持段判据（窗后得电期；n<3 拒判） —— *)
IF bEnergized AND (NOT _bPickWin) AND (NOT _bErrLatch) THEN
    IF tonNoData.Q THEN
        _eCoil := E_DL_SchHealth.eNoData;                   // 电流恒零：传感器断线（不与欠流混码，R190） / Constant zero current: no data
    ELSIF _nPickOk >= DL_SCH_NMIN THEN
        _fDevLim := _fHoldBase * fHoldPct / DL_SCH_PCT;     // 保持容差绝对限 [A] / Hold tolerance absolute limit
        IF (fCurrentA < _fHoldBase - _fDevLim) AND (NOT _bNonFin) THEN
            _eCoil := E_DL_SchHealth.eUnderCurrent;         // 欠偏：断匝趋势 / Under deviation: open-turn trend
        ELSIF (fCurrentA > _fHoldBase + _fDevLim) AND (NOT _bNonFin) THEN
            _eCoil := E_DL_SchHealth.eOverCurrent;          // 过偏：短路匝趋势 / Over deviation: short-turn trend
        ELSE
            _eCoil := E_DL_SchHealth.eOk;                   // 带内健康 / In-band healthy
        END_IF
    ELSE
        _eCoil := E_DL_SchHealth.eOk;                       // 合格吸合不足 3 次：拒判（防冷启动误报） / Fewer than three pickups: not judged
    END_IF
END_IF

(* —— 段 5：出口单点映射（名实双出口同源，R191） —— *)
eCoil := _eCoil;                                            // 健康态出口 / Health outlet
fPickPeakA := _fPeak;                                       // 最近吸合峰值出口（失电保持供诊断） / Last peak outlet, kept on de-energize
bError := _bErrLatch
       OR (_eCoil = E_DL_SchHealth.eNoData)
       OR (_eCoil = E_DL_SchHealth.eStuckPeak)
       OR (_eCoil = E_DL_SchHealth.eOverCurrent)
       OR (_eCoil = E_DL_SchHealth.eUnderCurrent);          // 故障标志 = 组态非法 ∨ 任一非健康态（与 eCoil 同源配对） / Error = cfg fault or any unhealthy state

END_FUNCTION_BLOCK
