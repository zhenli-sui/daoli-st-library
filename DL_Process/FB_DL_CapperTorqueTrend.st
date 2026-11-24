(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CapperTorqueTrend
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 旋盖扭矩曲线特征与 NG 判别
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS / MIN / MAX / LIMIT），零厂商方言
 * 接口依赖 (Depends)    : E_DL_Ne107Status —— 唯一属主为 DL_Device 子库的契约件
 *                         I_DL_DeviceHealth（R13 泳道 A1）。本文件只引用成员，不重定义枚举体。
 * 功能描述 (Function)   : 单次拧紧周期的扭矩曲线特征提取 + 五类 NG 判别。特征：峰值 fPeak、
 *                         上升斜率 fSlope、稳态段均值 fSteadyMean、上升段/总段面积比；
 *                         判别：低扭 / 高扭 / 滑牙 / 歪盖 / 曲线异常，输出 NG 原因位图（可多位置位）
 *                         与单一主判定 eOk / eNgLow / eNgHigh / eNgSlip / eNgCross / eNgCurve。
 * 边界     (Boundary)   : ① **不内联分位排序** —— 批次分位由 FC_DL_PercentileLReal 在批次层
 *                            算好，以 fBatchP10 / fBatchP90 引脚注入；② **不内联滤波** —— 曲线
 *                            平滑由上游 FB_DL_MedianFilter / FB_DL_MovingAverage 完成，本件输入
 *                            视为已平滑曲线；③ 不做拧紧轴运动控制（启停/转速归运动层）；
 *                         ④ 不做 SPC 与合格率统计（本件只做单周期判定与计数）。
 * 依赖方向纪律 (Rule)   : DL_Process 可依赖低层，但不得复制低层能力。本件的特征提取是
 *                         「整段批式曲线」的一次性扫描，与 FB_DL_SignalStatistics 的「流式
 *                         窗口逐拍采样」语义不同（后者无 fSpeed 换算、不保留峰值索引），故不
 *                         组合调用该件；层内已具备的分位能力（FC_DL_PercentileLReal）一律
 *                         以引脚注入，**不在本件内部排序**。
 * 分层声明 (Layer)      : 工艺层（DL_Process）。零全局变量表引用、零外部变量声明、零物理 IO。
 * 段序     (Segments)   : 段1 实例无条件刷新 → 段2 复位通道（CASE 前，R39）→ 段3 输入防御与
 *                         参数钳位 → 段4 单拍沿受理（R24/R25）→ 段5 状态机 → 段6 特征提取 →
 *                         段7 判定与码位仲裁 → 段8 码位单一优先级链 → 段9 出口钳位与保持重写。
 * 枚举映射表 (R31)      : 状态 E_DL_CapTrendState：eIdle(0)→标签 0｜eSampling(10)→标签 10｜
 *                         eEvaluate(20)→标签 20｜eVerdict(30)→标签 30｜eFault(99)→标签 99。
 *                         判定 E_DL_CapperVerdict：eOk(0)｜eNgLow(10)｜eNgHigh(20)｜eNgSlip(30)｜
 *                         eNgCross(40)｜eNgCurve(50)；主判定优先级 =
 *                         滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常（安全/功能严重度降序）。
 * 单拍标志清单 (R25)    : bCycleStart —— 预清零点：段1 每拍被实例输出覆盖；置位点：段1
 *                         `_bStartReq := _fbTrigStart.Q AND (NOT _bStartConsumed)`；自清点：
 *                         段6/段5 消费时置 `_bStartConsumed := TRUE`，bCycleStart 回 FALSE 时解除。
 *                         bReset —— 预清零点：段1 每拍覆盖 _bResetEdge；置位点：段1 实例调用；
 *                         自清点：紧随实例调用的 _bResetEdge 赋值行。
 * 保持位清单 (R27)      : eVerdict / bVerdictValid —— 逐拍由 _eVerdictHeld / _bVerdictLatched
 *                         重写（判定后持续有效，直到下一次 bCycleStart）；fPeak / fSlope /
 *                         fSteadyMean / uNgMask 同样逐拍由保持量重写并钳位。
 * 定时器清单 (R40)      : 无 TON/TOF 实例。曲线就绪判据用「nPoints 连续两拍不变」实现，
 *                         不占用定时器，也不存在跨段恒真输入。
 * 三元一致表 (R35)      : 峰值窗守卫 fPeakMin/fPeakMax 由 LIMIT 保证 0~1E4 N·m / 封顶 1E4 /
 *                         判据 `峰值 < 下限` 与 `峰值 > 上限`（与守卫同向）｜
 *                         斜率窗守卫 ±1E6 N·m/s / 封顶 1E6 / 判据 `<` 与 `>`｜
 *                         稳态容差守卫 0.1~100 % / 封顶 100 / 判据 `>`。
 * 镜像量清单 (R38)      : nPoints 在段3 一次性锁存为 _nPtsEff，此后全部循环上界与越界判定
 *                         只读 _nPtsEff，绝不回读实时入参 nPoints（R38 核心）。
 * 开源溯源 (Origin)     : 原创实现（参考 Rockwell PlantPAx 设备级 AOI 的「单块覆盖 指令-反馈-
 *                         判定-诊断 四段」粒度，T2-6 主源；以及 Siemens LBP 的「命令 → 监视 →
 *                         判定」三段分层，T2-2 次源）。仅借鉴分段粒度与参数域划分，AOI 名称、
 *                         UDT 布局、参数命名、判定阈值一律未沿用；五类 NG（低扭/高扭/滑牙/
 *                         歪盖/曲线异常）的判据为本库自有（公开资料无对应判据集）。
 *                         许可证说明：两源均为闭源文档版权，本件只借分类与参数域，未接触任何
 *                         源码，clean-room 编写；本文件为本库原创，随本库许可证发布。
 * 验收向量 (Acceptance) :
 *   V1 标准曲线（0 → 15 N·m 线性 0.5 s、稳态 2 s、回 0，fSpeed=120 rpm 即 Δt=0.5 s/点）→
 *      eOk、uNgMask = 0。
 *   V2 滑牙：峰值 12 后 0.2 s 内跌到 6（跌落 50% > fSlipDropRatio 20%）→ eNgSlip，
 *      uNgMask 的滑牙位置 1（必要时歪盖位同时置 1，位图允许并置）。
 *   V3（V-C 单拍沿纪律，R24/R25）bCycleStart 在 eSampling 内保持 TRUE 两拍 → **不得**
 *      触发第二次判定：沿只在 FALSE→TRUE 那一拍生效，且消费后置 _bStartConsumed。
 *   V4（V-D 保持）判定后上位机 3 拍后才读 → bVerdictValid 与 eVerdict 仍有效（R27 保持，非脉冲）。
 *   V5（V-A 无结论）nPoints = 0 → 16#0005_01C5、bVerdictValid = FALSE，eVerdict 保持上次值
 *      （「无结论」不等于「不合格」，不得强置 eNgCurve）。
 * 偏离留档 (Deviation)  :
 *   ① 数组维度用字面量 200 声明，逻辑门限用常量 DL_CAP_MAXP（= 200）：避免「常量前向引用」
 *      在汇川/施耐德编译器上的行为差异，两处必须同步（本行即为同步声明）。超上限按故障
 *      16#0005_02F3 处理，绝不越界读数组。
 *   ② 采样点间距按「每转一点」约定 Δt = 60 / fSpeed [s]：曲线采样节拍属上游采集系统职责，
 *      规格未给节拍引脚；以转速换算是最小假设的可行口径（fSpeed ≤ 0 时按 1 rpm 兜底并降精度）。
 *   ③ 曲线就绪判据用「nPoints 连续两拍不变」：规格无「曲线就绪」引脚，本件以稳定性判据
 *      代替显式握手，避免读到半写入的曲线。
 *   ④ nBatchMin 不参与本件统计（样本数归批次层），仅用于「分位基线是否可信」的闸门；
 *      fBatchP10 ≤ 0 或 fBatchP90 ≤ fBatchP10 或 nBatchMin < 1 时置 16#0005_01C6 并只走绝对阈值。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 C · DL_Process 第 23 件）
 *   2026-11-16  v1.0.1  终审修复：评估相出口原实现无条件转 eVerdict，评估中检出非有限
 *                       样本（02F4）后状态机不停在 eFault，下一启动沿可绕过复位直接开新
 *                       周期；改为 _bFaultCond 时转 eFault，符合规格迁移表（D-C3-1）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CapTrendState（归属 FB_DL_CapperTorqueTrend，同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CapTrendState :
(
    eIdle     := 0,     // 空闲：等 bCycleStart 上升沿 / Idle, awaiting the bCycleStart edge
    eSampling := 10,    // 采样：等曲线点数稳定（连续两拍不变）/ Sampling, waiting for a stable point count
    eEvaluate := 20,    // 评估：特征提取与判定（单拍完成）/ Evaluate, features and verdict in one scan
    eVerdict  := 30,    // 判定：结论保持（R27）/ Verdict held until the next cycle start
    eFault    := 99     // 故障：点数越界或曲线含非有限值 / Fault, point count or non-finite sample
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CapperVerdict（归属 FB_DL_CapperTorqueTrend，同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CapperVerdict :
(
    eOk       := 0,     // 合格：五类判据全未触发 / OK, none of the five criteria triggered
    eNgLow    := 10,    // 低扭：峰值低于下限 / Low torque, peak below the lower limit
    eNgHigh   := 20,    // 高扭：峰值高于上限 / High torque, peak above the upper limit
    eNgSlip   := 30,    // 滑牙：峰值后跌落比例超阈（主判定优先级最高）/ Thread slip, drop after the peak
    eNgCross  := 40,    // 歪盖：上升段面积占比过低（螺纹未咬合）/ Cross thread, low rise-area share
    eNgCurve  := 50     // 曲线异常：斜率越窗或无稳态平台 / Abnormal curve, slope or plateau
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_CapperTorqueTrend
VAR_INPUT
    bEnable      : BOOL;                        // 使能（Enable），FALSE = 冻结判定与计数；复位通道不受其屏蔽 / Enable, FALSE freezes the verdict
    bReset       : BOOL;                        // 复位（Reset），上升沿清判定、保持量与计数 / Rising edge clears verdict, held values and counters
    bCycleStart  : BOOL;                        // 单次拧紧开始（One-shot cycle start），上升沿受理（R24）/ One-shot cycle start, rising edge only
    afCurve      : ARRAY[1..200] OF REAL;       // 扭矩采样曲线（Torque curve samples）[N·m]，0~50，有效点由 nPoints 指定，维度与 DL_CAP_MAXP 同步 / Torque curve [N m]
    nPoints      : INT;                         // 有效点数（Valid sample count）[个]，域 2~DL_CAP_MAXP / Valid sample count, 2 to DL_CAP_MAXP
    fSpeed       : REAL;                        // 拧紧转速（Tightening speed）[rpm]，域 1~2000，用于采样间距换算 / Tightening speed [rpm]
    fPeakMin     : REAL;                        // 峰值合格下限（Peak lower limit）[N·m]，域 0~1E4 / Peak lower limit [N m]
    fPeakMax     : REAL;                        // 峰值合格上限（Peak upper limit）[N·m]，域 0~1E4 / Peak upper limit [N m]
    fSlopeMin    : REAL;                        // 上升斜率合格下限（Slope lower limit）[N·m/s]，域 −1E6~1E6 / Slope lower limit [N m/s]
    fSlopeMax    : REAL;                        // 上升斜率合格上限（Slope upper limit）[N·m/s]，域 −1E6~1E6 / Slope upper limit [N m/s]
    fSteadyTol   : REAL := 5.0;                 // 稳态段相对峰值容差（Steady band tolerance）[%]，域 0.1~100，默认 5.0 / Steady band tolerance [%]
    fSlipDropRatio : REAL := 0.20;              // 滑牙判据：峰值后跌落比例（Slip drop ratio）[-]，域 0.02~0.95，默认 0.20 / Slip drop ratio [-]
    fCrossRatio  : REAL := 0.40;                // 歪盖判据：上升段面积占比下限（Cross-thread area ratio）[-]，域 0.05~0.95，默认 0.40 / Cross-thread area ratio [-]
    fBatchP10    : REAL := 0.0;                 // 批次 P10 基线（Batch P10 baseline）[N·m]，0 = 未下发 / Batch P10 baseline [N m], 0 means not delivered
    fBatchP90    : REAL := 0.0;                 // 批次 P90 基线（Batch P90 baseline）[N·m]，0 = 未下发 / Batch P90 baseline [N m], 0 means not delivered
    nBatchMin    : INT := 30;                   // 分位可用所需最小样本（Minimum batch size）[件]，<1 视为分位不可用 / Minimum batch size, below one disables the baseline
END_VAR

VAR_OUTPUT
    fPeak        : REAL;                        // 峰值扭矩（Peak torque）[N·m]，保持语义 / Peak torque [N m], held
    fSlope       : REAL;                        // 上升斜率（Rise slope）[N·m/s]，保持语义 / Rise slope [N m/s], held
    fSteadyMean  : REAL;                        // 稳态段均值（Steady-band mean）[N·m]，保持语义 / Steady-band mean [N m], held
    eVerdict     : E_DL_CapperVerdict;          // 主判定（Main verdict），保持语义（R27）/ Main verdict, held until the next cycle
    uNgMask      : WORD;                        // NG 原因位图（NG reason bitmap），bit0 低扭 / bit1 高扭 / bit2 滑牙 / bit3 歪盖 / bit4 曲线异常 / NG reason bitmap
    bVerdictValid : BOOL;                       // 判定有效（Verdict valid），保持到下次 bCycleStart（R27）/ Verdict valid, held until the next start
    nTotal       : UDINT;                       // 已判周期总数（Cycle counter）[件] / Evaluated cycle counter [pcs]
    nNg          : UDINT;                       // 不合格周期数（Reject counter）[件] / Rejected cycle counter [pcs]
    eHealth      : E_DL_Ne107Status;            // 健康态（NE107 health），引用属主 A1 的枚举 / NE107 health, owned by A1
    uDiagCode    : UDINT;                       // 诊断码（Diagnostic code），本拍单一优先级链输出 / Diagnostic code, single priority chain
    uErrorId     : UDINT;                       // 故障码（Error code），仅故障级码，0 = 无故障 / Fault-level code, 0 = no fault
    bError       : BOOL;                        // 故障标志（Error），仅故障级码置位（NG 属工件不良，不置位）/ TRUE only for fault-level codes, NG is a part defect
END_VAR

VAR
    _eState      : E_DL_CapTrendState := E_DL_CapTrendState.eIdle;  // 内部状态（Internal state）/ Internal state value
    _bStartReq   : BOOL;                        // 周期启动单拍请求（Cycle start request）/ Cycle start one-shot request
    _bStartConsumed : BOOL;                     // 启动已消费（Start consumed flag）/ Start consumed flag
    _bResetEdge  : BOOL;                        // 复位沿单拍标志（Reset one-shot flag）/ Reset one-shot flag
    _uFaultCode  : UDINT;                       // 本拍故障级码（Fault-level code this scan）/ Fault-level code of this scan
    _uFaultLatched : UDINT;                     // 故障码锁存（Latched fault code），仅复位清除 / Latched fault code, reset only
    _uInfoCode   : UDINT;                       // 本拍信息级码（Info-level code this scan）/ Info-level code of this scan
    _bFaultCond  : BOOL;                        // 故障条件（Fault condition）/ Fault condition flag
    _nPtsEff     : INT;                         // 生效点数（Effective point count）[个]，本拍唯一锁存量（R38）/ Effective point count, the only latched copy (R38)
    _nPtsPrev    : INT;                         // 上拍点数（Previous point count）[个]，曲线就绪判据用 / Previous point count for the readiness test
    _bCurveReady : BOOL;                        // 曲线就绪（Curve ready），点数连续两拍不变 / Curve ready, the count is unchanged for two scans
    _nIdx        : INT;                         // 遍历索引（Loop index）[个]，域 1~_nPtsEff / Loop index, 1 to _nPtsEff
    _nGuard      : INT;                         // 遍历防死锁计数（Loop guard counter）[次] / Loop guard counter
    _nPeakIdx    : INT;                         // 峰值索引（Peak index）[个] / Peak index
    _fPeakCalc   : REAL;                        // 本拍峰值（Computed peak）[N·m] / Computed peak [N m]
    _fSample     : REAL;                        // 当前样本值（Current sample）[N·m] / Current sample [N m]
    _fDtSample   : REAL;                        // 采样间距（Sample interval）[s]，Δt = 60 / fSpeed / Sample interval, 60 divided by the speed
    _fRiseT      : REAL;                        // 上升时间（Rise time）[s]，(峰值索引−1)·Δt / Rise time [s]
    _fSlopeCalc  : REAL;                        // 本拍斜率（Computed slope）[N·m/s] / Computed slope [N m/s]
    _fSteadySum  : REAL;                        // 稳态段累加（Steady-band sum）[N·m] / Steady-band sum [N m]
    _nSteadyN    : INT;                         // 稳态段样本数（Steady-band sample count）[个] / Steady-band sample count
    _fSteadyCalc : REAL;                        // 本拍稳态均值（Computed steady mean）[N·m] / Computed steady mean [N m]
    _fAreaAll    : REAL;                        // 总曲线面积（Total curve area）[N·m·s] / Total curve area [N m s]
    _fAreaRise   : REAL;                        // 上升段面积（Rise-segment area）[N·m·s] / Rise-segment area [N m s]
    _fAreaRatio  : REAL;                        // 上升段面积占比（Rise-area share）[-] / Rise-area share [-]
    _fBandAbs    : REAL;                        // 稳态带绝对宽度（Absolute steady band）[N·m] / Absolute steady band [N m]
    _fMinAfter   : REAL;                        // 峰值后最小值（Minimum after the peak）[N·m] / Minimum after the peak [N m]
    _fDropRatio  : REAL;                        // 峰值后跌落比例（Drop ratio after the peak）[-] / Drop ratio after the peak [-]
    _nNoise      : INT;                         // 峰前一阶差分变号次数（Sign changes before the peak）[次] / Sign changes before the peak
    _fDiffPrev   : REAL;                        // 上一差分值（Previous difference）[N·m] / Previous difference [N m]
    _fDiffNow    : REAL;                        // 当前差分值（Current difference）[N·m] / Current difference [N m]
    _fPeakLowEff : REAL;                        // 生效峰值下限（Effective peak low limit）[N·m] / Effective peak low limit [N m]
    _fPeakHighEff : REAL;                       // 生效峰值上限（Effective peak high limit）[N·m] / Effective peak high limit [N m]
    _fSlopeLowEff : REAL;                       // 生效斜率下限（Effective slope low limit）[N·m/s] / Effective slope low limit [N m/s]
    _fSlopeHighEff : REAL;                      // 生效斜率上限（Effective slope high limit）[N·m/s] / Effective slope high limit [N m/s]
    _fSteadyTolEff : REAL;                      // 生效稳态容差（Effective steady tolerance）[%] / Effective steady tolerance [%]
    _fSlipRatioEff : REAL;                      // 生效滑牙比例（Effective slip ratio）[-] / Effective slip ratio [-]
    _fCrossRatioEff : REAL;                     // 生效歪盖比例（Effective cross-thread ratio）[-] / Effective cross-thread ratio [-]
    _bBatchOk    : BOOL;                        // 批次分位可用（Batch baseline usable）/ Batch baseline usable flag
    _uMask       : WORD;                        // 本拍 NG 位图（NG bitmap this scan）/ NG bitmap of this scan
    _eVerdictCalc : E_DL_CapperVerdict;         // 本拍主判定（Computed verdict）/ Computed verdict
    _nTotalInt   : UDINT;                       // 内部周期计数（Internal cycle counter）[件] / Internal cycle counter [pcs]
    _nNgInt      : UDINT;                       // 内部不良计数（Internal reject counter）[件] / Internal reject counter [pcs]
    _eVerdictHeld : E_DL_CapperVerdict := E_DL_CapperVerdict.eOk;   // 保持的主判定（Held verdict）/ Held verdict
    _bVerdictLatched : BOOL;                    // 判定锁存（Verdict latch），新周期起点清除 / Verdict latch, cleared at a new cycle start
    _uMaskHeld   : WORD;                        // 保持的位图（Held bitmap）/ Held bitmap
    _fPeakHeld   : REAL;                        // 保持的峰值（Held peak）[N·m] / Held peak [N m]
    _fSlopeHeld  : REAL;                        // 保持的斜率（Held slope）[N·m/s] / Held slope [N m/s]
    _fSteadyHeld : REAL;                        // 保持的稳态均值（Held steady mean）[N·m] / Held steady mean [N m]
    _fbTrigStart : R_TRIG;                      // 周期启动上升沿（Cycle start rising edge）/ Cycle start rising edge
    _fbTrigReset : R_TRIG;                      // 复位上升沿（Reset rising edge）/ Reset rising edge
END_VAR

VAR CONSTANT
    DL_CAP_MAXP      : INT  := 200;         // 曲线点数上限（Curve point ceiling）[个]，必须与 afCurve 维度 200 同步 / Curve point ceiling, kept in sync with the array bound
    DL_CAP_MINP      : INT  := 2;           // 最小可分析点数（Minimum analysable points）[个] / Minimum analysable points
    DL_CAP_GUARD     : INT  := 1024;        // 遍历防死锁上限（Loop guard ceiling）[次] / Loop guard ceiling
    DL_CAP_REAL_MAX  : REAL := 3.4E38;      // 单精度有限值判据幅值（Finite magnitude bound）/ Finite bound for REAL inputs
    DL_CAP_EPS       : REAL := 1.0E-6;      // 浮点防零容差（Divide-guard epsilon）/ Float divide-guard epsilon
    DL_CAP_NM_MAX    : REAL := 1.0E4;       // 扭矩域上限（Torque domain ceiling）[N·m] / Torque domain ceiling [N m]
    DL_CAP_SLOPE_LIM : REAL := 1.0E6;       // 斜率域上限（Slope domain ceiling）[N·m/s] / Slope domain ceiling [N m/s]
    DL_CAP_SPEED_LO  : REAL := 1.0;         // 转速域下限（Speed lower clamp）[rpm] / Speed lower clamp [rpm]
    DL_CAP_SPEED_HI  : REAL := 2000.0;      // 转速域上限（Speed upper clamp）[rpm] / Speed upper clamp [rpm]
    DL_CAP_TOL_LO    : REAL := 0.1;         // 稳态容差下限（Steady tolerance lower clamp）[%] / Steady tolerance lower clamp [%]
    DL_CAP_TOL_HI    : REAL := 100.0;       // 稳态容差上限（Steady tolerance upper clamp）[%] / Steady tolerance upper clamp [%]
    DL_CAP_SLIP_LO   : REAL := 0.02;        // 滑牙比例下限（Slip ratio lower clamp）[-] / Slip ratio lower clamp
    DL_CAP_SLIP_HI   : REAL := 0.95;        // 滑牙比例上限（Slip ratio upper clamp）[-] / Slip ratio upper clamp
    DL_CAP_CROSS_LO  : REAL := 0.05;        // 歪盖比例下限（Cross ratio lower clamp）[-] / Cross ratio lower clamp
    DL_CAP_CROSS_HI  : REAL := 0.95;        // 歪盖比例上限（Cross ratio upper clamp）[-] / Cross ratio upper clamp
    DL_CAP_SEC_MIN   : REAL := 60.0;        // 分钟→秒换算（Minutes-to-seconds scale）[-] / Minutes-to-seconds scale
    DL_CAP_NOISE_MAX : INT  := 3;           // 峰前抖动次数上限（Noise sign-change ceiling）[次] / Noise sign-change ceiling
    DL_CAP_BATCH_MIN : INT  := 1;           // 分位闸门最小样本（Batch gate minimum size）[件] / Batch gate minimum size
    DL_CAP_NG_NONE   : WORD := 16#0000;     // 位图空值（Empty bitmap）/ Empty bitmap
    DL_CAP_NG_LOW    : WORD := 16#0001;     // bit0 低扭（Low torque）/ Bit 0, low torque
    DL_CAP_NG_HIGH   : WORD := 16#0002;     // bit1 高扭（High torque）/ Bit 1, high torque
    DL_CAP_NG_SLIP   : WORD := 16#0004;     // bit2 滑牙（Thread slip）/ Bit 2, thread slip
    DL_CAP_NG_CROSS  : WORD := 16#0008;     // bit3 歪盖（Cross thread）/ Bit 3, cross thread
    DL_CAP_NG_CURVE  : WORD := 16#0010;     // bit4 曲线异常（Abnormal curve）/ Bit 4, abnormal curve
    DL_CAP_ERR_RANGE : UDINT := 16#0005_02F3; // 0005_02F3 点数超上限【故障级】/ Point count above the buffer, fault level
    DL_CAP_ERR_NAN   : UDINT := 16#0005_02F4; // 0005_02F4 曲线含非有限值【故障级】/ Non-finite sample, fault level
    DL_CAP_ERR_STATE : UDINT := 16#0005_02F5; // 0005_02F5 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_CAP_INFO_PTS  : UDINT := 16#0005_01C5; // 0005_01C5 点数不足未评级【信息级】/ Insufficient points, info level
    DL_CAP_INFO_BATCH : UDINT := 16#0005_01C6; // 0005_01C6 批次分位未下发，仅用绝对阈值【信息级】/ Batch baseline unavailable, info level
    DL_CAP_INFO_NOISE : UDINT := 16#0005_01C7; // 0005_01C7 曲线噪声大，斜率可信度低【信息级】/ Noisy curve, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of every instance (R7/0.5)
// ============================================================================
_fbTrigStart(CLK := bCycleStart);               // 周期启动上升沿（Cycle start rising edge）
_bStartReq := _fbTrigStart.Q AND (NOT _bStartConsumed);    // 单拍启动请求（R25 置位点）/ One-shot start request
_fbTrigReset(CLK := bReset);                    // 复位上升沿（Reset rising edge）
_bResetEdge := _fbTrigReset.Q;                  // 复位单拍标志紧随实例赋值（R25 自清点）

// 本拍码与条件预置（每拍重算；故障码以上拍锁存续用）
// Per-scan preset of codes and conditions, the fault code is carried from the latch
_uFaultCode := _uFaultLatched;                  // 故障码续用（Carry the latched fault code）
_uInfoCode  := 16#0000_0000;                    // 信息级码预清零（Info code preset to zero）
_bFaultCond := FALSE;                           // 故障条件预清零（Fault condition preset FALSE）
_uMask      := DL_CAP_NG_NONE;                  // 位图预清零（Bitmap preset empty）
_eVerdictCalc := _eVerdictHeld;                 // 主判定预置上次保持值（Verdict preset from the held value）
_fPeakCalc  := _fPeakHeld;                      // 峰值预置保持值（Peak preset from the held value）
_fSlopeCalc := _fSlopeHeld;                     // 斜率预置保持值（Slope preset from the held value）
_fSteadyCalc := _fSteadyHeld;                   // 稳态均值预置保持值（Steady mean preset from the held value）

// 启动消费标志解除：输入回落即允许下一周期（R25 生命周期闭环）
// Release the start consumption flag once the input falls, so the next cycle can arm
IF NOT bCycleStart THEN
    _bStartConsumed := FALSE;                   // 允许下一次上升沿（Next rising edge accepted）
END_IF

// ============================================================================
// 段 2｜复位通道（R39：置于 CASE 之前，且不被掉使能分支屏蔽）
//      Reset path, before CASE and never masked by the disable branch
// ============================================================================
IF _bResetEdge THEN
    _eVerdictHeld    := E_DL_CapperVerdict.eOk; // 判定复位为合格初值（Verdict reset to the initial value）
    _bVerdictLatched := FALSE;                  // 判定锁存清除（Verdict latch cleared）
    _uMaskHeld       := DL_CAP_NG_NONE;         // 位图保持量清零（Held bitmap cleared）
    _fPeakHeld       := 0.0;                    // 峰值保持量清零（Held peak cleared）
    _fSlopeHeld      := 0.0;                    // 斜率保持量清零（Held slope cleared）
    _fSteadyHeld     := 0.0;                    // 稳态均值保持量清零（Held steady mean cleared）
    _nPtsPrev        := 0;                      // 点数记忆清零（Point memory cleared）
    _nTotalInt       := UDINT#0;                // 周期计数清零（Cycle counter cleared）
    _nNgInt          := UDINT#0;                // 不良计数清零（Reject counter cleared）
    _uFaultLatched   := 16#0000_0000;           // 故障码锁存清除（Latched fault code cleared）
    _uFaultCode      := 16#0000_0000;           // 本拍故障码清空，防止段8 重新锁存旧码（Clear this scan code）
    IF _eState = E_DL_CapTrendState.eFault THEN
        _eState := E_DL_CapTrendState.eIdle;    // 故障态回空闲（Fault state back to idle）
        _bFaultCond := FALSE;                   // 故障条件清除（Fault condition cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜输入防御与参数钳位（点数一次性锁存，此后只读锁存量，R38）
//      Input defense and parameter clamping, the point count is latched once (R38)
// ============================================================================
_nPtsEff := nPoints;                            // 点数唯一锁存点（The single latch point of the count）
IF _nPtsEff > DL_CAP_MAXP THEN
    _bFaultCond := TRUE;                        // 越界即故障，绝不截断后静默分析（Above the buffer is a fault）
    _uFaultCode := DL_CAP_ERR_RANGE;            // 0005_02F3 点数超上限【故障级】/ Point count above the buffer
    _nPtsEff    := 0;                           // 锁存量归零，杜绝越界读（Zeroed so no out-of-range read happens）
ELSIF _nPtsEff < 0 THEN
    _nPtsEff := 0;                              // 负点数按 0 处理（Negative count treated as zero）
END_IF

// 参数域钳位（R35：守卫、封顶与判据同向）
// Parameter clamping so that guard, ceiling and comparison stay in step (R35)
_fPeakLowEff   := LIMIT(0.0, fPeakMin, DL_CAP_NM_MAX);              // 峰值下限 0~1E4（Peak low limit clamped）
_fPeakHighEff  := LIMIT(0.0, fPeakMax, DL_CAP_NM_MAX);              // 峰值上限 0~1E4（Peak high limit clamped）
_fSlopeLowEff  := LIMIT(-DL_CAP_SLOPE_LIM, fSlopeMin, DL_CAP_SLOPE_LIM);   // 斜率下限（Slope low clamped）
_fSlopeHighEff := LIMIT(-DL_CAP_SLOPE_LIM, fSlopeMax, DL_CAP_SLOPE_LIM);   // 斜率上限（Slope high clamped）
_fSteadyTolEff := LIMIT(DL_CAP_TOL_LO, fSteadyTol, DL_CAP_TOL_HI);  // 稳态容差 0.1~100 %（Steady tolerance clamped）
_fSlipRatioEff := LIMIT(DL_CAP_SLIP_LO, fSlipDropRatio, DL_CAP_SLIP_HI);   // 滑牙比例（Slip ratio clamped）
_fCrossRatioEff := LIMIT(DL_CAP_CROSS_LO, fCrossRatio, DL_CAP_CROSS_HI);   // 歪盖比例（Cross ratio clamped）
IF _fPeakLowEff > _fPeakHighEff THEN
    _fSample        := _fPeakLowEff;            // 借道交换（Borrow the scratch to swap）
    _fPeakLowEff    := _fPeakHighEff;           // 下限取原上限（Low takes the former high）
    _fPeakHighEff   := _fSample;                // 上限取原下限（High takes the former low）
END_IF

// 采样间距换算：每转一点约定（偏离留档②），转速非法按 1 rpm 兜底
// Sample interval by the one-point-per-revolution convention (deviation 2)
IF (fSpeed >= DL_CAP_SPEED_LO) AND (fSpeed <= DL_CAP_SPEED_HI) THEN
    _fDtSample := DL_CAP_SEC_MIN / fSpeed;      // Δt = 60 / 转速（Sample interval in seconds）
ELSE
    _fDtSample := DL_CAP_SEC_MIN / DL_CAP_SPEED_LO;  // 非法转速按 1 rpm 兜底（Illegal speed falls back to 1 rpm）
END_IF

// 曲线就绪判据：点数连续两拍不变（偏离留档③），避免读到半写入的曲线
// Curve readiness: the point count stays unchanged for two scans (deviation 3)
_bCurveReady := (_nPtsEff >= DL_CAP_MINP) AND (_nPtsEff = _nPtsPrev);
_nPtsPrev    := _nPtsEff;                       // 记忆本拍点数（Remember this scan count）

// 批次分位闸门：三条件同时成立才认为基线可信（偏离留档④）
// Batch baseline gate: all three conditions must hold before the baseline is trusted
_bBatchOk := (_nPtsEff > 0)
          AND (fBatchP10 > 0.0)
          AND (fBatchP90 > fBatchP10)
          AND (nBatchMin >= DL_CAP_BATCH_MIN);
IF _nPtsEff >= DL_CAP_MINP THEN
    IF _bBatchOk THEN
        IF fBatchP10 > _fPeakLowEff THEN
            _fPeakLowEff := fBatchP10;          // 双阈收紧：分位更严时取分位（Tighter of both limits）
        END_IF
        IF fBatchP90 < _fPeakHighEff THEN
            _fPeakHighEff := fBatchP90;         // 双阈收紧：分位更严时取分位（Tighter of both limits）
        END_IF
        IF _fPeakLowEff >= _fPeakHighEff THEN
            _fPeakLowEff  := LIMIT(0.0, fPeakMin, DL_CAP_NM_MAX);   // 窗被夹死后回退绝对阈值（Fall back to the absolute window）
            _fPeakHighEff := LIMIT(0.0, fPeakMax, DL_CAP_NM_MAX);   // 回退绝对上限（Absolute upper limit restored）
            _bBatchOk     := FALSE;             // 分位基线判为不可用（Baseline marked unusable）
            _uInfoCode    := DL_CAP_INFO_BATCH; // 0005_01C6 分位未下发【信息级】/ Batch baseline unavailable
        END_IF
    ELSE
        _uInfoCode := DL_CAP_INFO_BATCH;        // 0005_01C6 分位未下发，仅绝对阈值【信息级】/ Batch baseline unavailable
    END_IF
END_IF

// ============================================================================
// 段 4｜状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      State machine with an explicit ELSE fallback
// ============================================================================
IF _bFaultCond THEN
    _eState := E_DL_CapTrendState.eFault;       // 故障条件优先于状态机（Fault outranks the machine）
END_IF

// 掉使能冻结分支：显式排除故障态（R39 合法写法①），复位通道仍可从故障态退出
// Disable branch explicitly excludes the fault state so the reset path still works
IF (NOT bEnable) AND (_eState <> E_DL_CapTrendState.eFault) THEN
    _eState := E_DL_CapTrendState.eIdle;        // 冻结回空闲（Freeze back to idle）
    _bCurveReady := FALSE;                      // 就绪标志作废（Readiness voided）
END_IF

CASE _eState OF

    E_DL_CapTrendState.eIdle: // 空闲：等启动沿
        IF _bStartReq AND (NOT _bStartConsumed) THEN
            _bStartConsumed  := TRUE;           // 消费启动沿（Start edge consumed）
            _bVerdictLatched := FALSE;          // 上一轮判定作废（Previous verdict voided）
            _nPtsPrev        := 0;              // 点数记忆清零，重新等稳定（Point memory cleared）
            _uInfoCode       := 16#0000_0000;   // 新轮起点清信息码（R44：清码点绑定新轮起点）
            _eState          := E_DL_CapTrendState.eSampling;   // 进采样相（Enter sampling）
        END_IF

    E_DL_CapTrendState.eSampling: // 采样：等曲线点数稳定
        IF _bStartReq AND (NOT _bStartConsumed) THEN
            _bStartConsumed := TRUE;            // 采样相内的重复沿只消费不再触发判定（R24 单拍纪律）
            _nPtsPrev       := 0;               // 重新建立点数记忆，等新的稳定判据（Rebuild the readiness test）
        END_IF
        IF _bCurveReady THEN
            _eState := E_DL_CapTrendState.eEvaluate;    // 曲线稳定进评估（Curve ready, evaluate）
        ELSIF _nPtsEff < DL_CAP_MINP THEN
            _uInfoCode := DL_CAP_INFO_PTS;      // 0005_01C5 点数不足未评级【信息级】/ Insufficient points
            _bVerdictLatched := FALSE;          // 无结论即无效，但**不**改写主判定（R27/V5）
        END_IF

    E_DL_CapTrendState.eEvaluate: // 评估：特征提取与判定在段6 完成，本分支只做相转移
        // 评估在段6 一次完成，本分支保留空标签与原因注释（R31）
        // Evaluation happens in segment 6, so this label stays empty (R31)

    E_DL_CapTrendState.eVerdict: // 判定保持：等下一次启动沿开新周期
        IF _bStartReq AND (NOT _bStartConsumed) THEN
            _bStartConsumed  := TRUE;           // 消费启动沿（Start edge consumed）
            _bVerdictLatched := FALSE;          // 判定作废，等新结果（Verdict voided until the new result）
            _nPtsPrev        := 0;              // 点数记忆清零（Point memory cleared）
            _uInfoCode       := 16#0000_0000;   // 新轮起点清信息码（R44）
            _eState          := E_DL_CapTrendState.eSampling;   // 采新一周期的曲线（Sample the new curve）
        END_IF

    E_DL_CapTrendState.eFault: // 故障：等复位沿（段2）
        // 复位通道位于 CASE 之前，此分支无需动作（R39）
        // The reset path sits before CASE, so no action is needed here (R39)

    ELSE // 兜底：非法状态
        _uFaultCode := DL_CAP_ERR_STATE;        // 0005_02F5 非法状态兜底【故障级】/ Illegal state fallback
        _bFaultCond := TRUE;                    // 置故障条件（Raise the fault condition）
        _eState     := E_DL_CapTrendState.eFault;   // 强制回故障态（Force the fault state）
END_CASE

// ============================================================================
// 段 6｜特征提取与判定（仅在评估相执行一次；越界已在上游锁存与拦截）
//      Feature extraction and verdict, executed once in the evaluate phase
// ============================================================================
IF (_eState = E_DL_CapTrendState.eEvaluate) AND _bCurveReady THEN

    // 6.1 峰值与峰值索引（单遍扫描，同时校验非有限值）
    //     Peak and peak index in a single pass, validating every sample
    _nGuard    := 0;                            // 遍历守卫清零（Loop guard cleared）
    _fPeakCalc := 0.0;                          // 峰值初值（Peak initial value）
    _nPeakIdx  := 1;                            // 峰值索引初值（Peak index initial value）
    _fAreaAll  := 0.0;                          // 总面积清零（Total area cleared）
    _fAreaRise := 0.0;                          // 上升段面积清零（Rise area cleared）
    _nNoise    := 0;                            // 抖动计数清零（Noise counter cleared）
    _fDiffPrev := 0.0;                          // 上差分清零（Previous difference cleared）
    _fMinAfter := 0.0;                          // 峰后最小值先置 0，峰值确定后再装初值（Seeded after the peak is known）
    _fSteadySum := 0.0;                         // 稳态累加清零（Steady sum cleared）
    _nSteadyN  := 0;                            // 稳态样本数清零（Steady count cleared）

    FOR _nIdx := 1 TO _nPtsEff DO
        _nGuard  := _nGuard + 1;                // 守卫自增（Guard increments）
        IF _nGuard > DL_CAP_GUARD THEN
            EXIT;                               // 防死循环（Loop guard exit）
        END_IF
        _fSample := afCurve[_nIdx];             // 取样本（Take the sample）
        IF (NOT (_fSample >= (-DL_CAP_REAL_MAX) AND _fSample <= DL_CAP_REAL_MAX)) THEN
            _bFaultCond := TRUE;                // 非有限值即故障（Non-finite sample is a fault）
            _uFaultCode := DL_CAP_ERR_NAN;      // 0005_02F4 曲线含非有限值【故障级】/ Non-finite sample
            EXIT;                               // 立即停止分析（Stop analysing immediately）
        END_IF
        IF (_fSample > _fPeakCalc) OR (_nIdx = 1) THEN
            _fPeakCalc := _fSample;             // 更新峰值（Update the peak）
            _nPeakIdx  := _nIdx;                // 更新峰值索引（Update the peak index）
        END_IF
        _fAreaAll := _fAreaAll + (_fSample * _fDtSample);   // 总面积累加（Total area accumulates）
    END_FOR

    // 6.2 上升段面积、峰后最小值、峰前抖动（第二遍，仅在前一遍无故障时执行）
    //     Rise area, post-peak minimum and pre-peak noise on a second pass
    IF (NOT _bFaultCond) AND (_nPeakIdx >= 1) THEN
        _fBandAbs  := _fPeakCalc * _fSteadyTolEff / 100.0;   // 稳态带绝对宽度，必须先于第二遍算出（Band before the second pass）
        _fMinAfter := _fPeakCalc;               // 峰后最小值初值取峰值本身，无跌落时跌落比为 0（Seed with the peak so no drop means zero）
        _nGuard := 0;                           // 守卫清零（Guard cleared）
        FOR _nIdx := 1 TO _nPtsEff DO
            _nGuard := _nGuard + 1;             // 守卫自增（Guard increments）
            IF _nGuard > DL_CAP_GUARD THEN
                EXIT;                           // 防死循环（Loop guard exit）
            END_IF
            _fSample := afCurve[_nIdx];         // 取样本（Take the sample）
            IF _nIdx <= _nPeakIdx THEN
                _fAreaRise := _fAreaRise + (_fSample * _fDtSample);     // 上升段面积（Rise area）
                IF _nIdx > 1 THEN
                    _fDiffNow := _fSample - afCurve[_nIdx - 1];         // 一阶差分（First difference）
                    IF ((_fDiffNow > DL_CAP_EPS) AND (_fDiffPrev < (-DL_CAP_EPS)))
                    OR ((_fDiffNow < (-DL_CAP_EPS)) AND (_fDiffPrev > DL_CAP_EPS)) THEN
                        _nNoise := _nNoise + 1;     // 变号计数（Sign change counted）
                    END_IF
                    _fDiffPrev := _fDiffNow;        // 记忆差分（Remember the difference）
                END_IF
            ELSE
                IF _fSample < _fMinAfter THEN
                    _fMinAfter := _fSample;     // 峰后最小值（Minimum after the peak）
                END_IF
            END_IF
            IF (_nIdx >= _nPeakIdx) AND (ABS(_fSample - _fPeakCalc) <= _fBandAbs) THEN
                _fSteadySum := _fSteadySum + _fSample;  // 稳态段累加（Steady-band sum）
                _nSteadyN   := _nSteadyN + 1;           // 稳态段计数（Steady-band count）
            END_IF
        END_FOR
    END_IF

    IF NOT _bFaultCond THEN
        // 6.3 派生特征
        //     Derived features
        _fRiseT    := INT_TO_REAL(_nPeakIdx - 1) * _fDtSample;   // 上升时间（Rise time）
        IF _fRiseT > DL_CAP_EPS THEN
            _fSlopeCalc := _fPeakCalc / _fRiseT;             // 上升斜率（Rise slope）
        ELSE
            _fSlopeCalc := 0.0;                              // 单点上升按 0 处理（Single-point rise has no slope）
        END_IF
        IF _nSteadyN > 0 THEN
            _fSteadyCalc := _fSteadySum / INT_TO_REAL(_nSteadyN);    // 稳态均值（Steady mean）
        ELSE
            _fSteadyCalc := 0.0;                             // 无稳态平台按 0（No plateau, zero mean）
        END_IF
        IF _fAreaAll > DL_CAP_EPS THEN
            _fAreaRatio := _fAreaRise / _fAreaAll;           // 上升段面积占比（Rise-area share）
        ELSE
            _fAreaRatio := 1.0;                              // 全零曲线按满占比，避免除零（All-zero curve, divide guard）
        END_IF
        IF _fPeakCalc > DL_CAP_EPS THEN
            _fDropRatio := (_fPeakCalc - _fMinAfter) / _fPeakCalc;   // 峰后跌落比例（Drop ratio）
        ELSE
            _fDropRatio := 0.0;                              // 峰值为零无跌落（Zero peak has no drop）
        END_IF
        IF (_nNoise > DL_CAP_NOISE_MAX) AND (_nSteadyN >= DL_CAP_MINP) THEN
            _uInfoCode := DL_CAP_INFO_NOISE;                 // 0005_01C7 曲线噪声大斜率可信度低【信息级】/ Noisy curve
        END_IF

        // 6.4 五类 NG 判据（位图可并置；主判定按严重度优先级仲裁）
        //     Five NG criteria, the bitmap may hold several bits at once
        IF _fPeakCalc < _fPeakLowEff THEN
            _uMask := _uMask OR DL_CAP_NG_LOW;               // bit0 低扭（Low torque）
        END_IF
        IF _fPeakCalc > _fPeakHighEff THEN
            _uMask := _uMask OR DL_CAP_NG_HIGH;              // bit1 高扭（High torque）
        END_IF
        IF _fDropRatio > _fSlipRatioEff THEN
            _uMask := _uMask OR DL_CAP_NG_SLIP;              // bit2 滑牙（Thread slip）
        END_IF
        IF _fAreaRatio < _fCrossRatioEff THEN
            _uMask := _uMask OR DL_CAP_NG_CROSS;             // bit3 歪盖（Cross thread）
        END_IF
        IF (_fSlopeCalc < _fSlopeLowEff) OR (_fSlopeCalc > _fSlopeHighEff)
        OR (_nSteadyN < DL_CAP_MINP)
        OR ((_fPeakCalc > DL_CAP_EPS) AND (ABS(_fSteadyCalc - _fPeakCalc) / _fPeakCalc > (_fSteadyTolEff / 100.0))) THEN
            _uMask := _uMask OR DL_CAP_NG_CURVE;             // bit4 曲线异常（Abnormal curve）
        END_IF

        // 6.5 主判定优先级：滑牙 > 歪盖 > 低扭 > 高扭 > 曲线异常 > 合格
        //     Verdict priority: slip, cross, low, high, curve, then OK
        IF (_uMask AND DL_CAP_NG_SLIP) <> DL_CAP_NG_NONE THEN
            _eVerdictCalc := E_DL_CapperVerdict.eNgSlip;     // 滑牙优先（Slip wins）
        ELSIF (_uMask AND DL_CAP_NG_CROSS) <> DL_CAP_NG_NONE THEN
            _eVerdictCalc := E_DL_CapperVerdict.eNgCross;    // 歪盖次之（Cross thread next）
        ELSIF (_uMask AND DL_CAP_NG_LOW) <> DL_CAP_NG_NONE THEN
            _eVerdictCalc := E_DL_CapperVerdict.eNgLow;      // 低扭（Low torque）
        ELSIF (_uMask AND DL_CAP_NG_HIGH) <> DL_CAP_NG_NONE THEN
            _eVerdictCalc := E_DL_CapperVerdict.eNgHigh;     // 高扭（High torque）
        ELSIF (_uMask AND DL_CAP_NG_CURVE) <> DL_CAP_NG_NONE THEN
            _eVerdictCalc := E_DL_CapperVerdict.eNgCurve;    // 曲线异常（Abnormal curve）
        ELSE
            _eVerdictCalc := E_DL_CapperVerdict.eOk;         // 合格（OK）
        END_IF

        // 6.6 结论锁存与计数（每周期只结算一次）
        //     Latch the verdict and count once per cycle
        _fPeakHeld       := _fPeakCalc;         // 峰值锁存（Peak latched）
        _fSlopeHeld      := _fSlopeCalc;        // 斜率锁存（Slope latched）
        _fSteadyHeld     := _fSteadyCalc;       // 稳态均值锁存（Steady mean latched）
        _uMaskHeld       := _uMask;             // 位图锁存（Bitmap latched）
        _eVerdictHeld    := _eVerdictCalc;      // 主判定锁存（Verdict latched）
        _bVerdictLatched := TRUE;               // 判定有效锁存（Verdict latched valid）
        _nTotalInt          := _nTotalInt + UDINT#1;  // 周期计数 +1（Cycle counted）
        IF _uMask <> DL_CAP_NG_NONE THEN
            _nNgInt := _nNgInt + UDINT#1;             // 不良计数 +1（Reject counted）
        END_IF
    ELSE
        _bVerdictLatched := FALSE;              // 曲线故障：本周期无判定（No verdict for this cycle）
    END_IF
END_IF

// 评估相出口：检出故障转故障态等复位（规格迁移表：任何态--非有限--> eFault），否则进判定保持相
// Leave the evaluate phase to fault on a detected fault, otherwise to the held-verdict phase
IF _eState = E_DL_CapTrendState.eEvaluate THEN
    IF _bFaultCond THEN
        _eState := E_DL_CapTrendState.eFault;   // 曲线故障：转故障态，须复位方可退出（v1.0.1 修复）
    ELSE
        _eState := E_DL_CapTrendState.eVerdict; // 进判定保持相（Enter the held-verdict phase）
    END_IF
END_IF

// ============================================================================
// 段 8｜码位单一优先级链（全拍只写一次，信息级不置 bError）
//      Single priority chain for the codes, written once per scan
// ============================================================================
IF _uFaultCode <> 16#0000_0000 THEN
    _uFaultLatched := _uFaultCode;              // 故障码锁存（Latched until reset）
    uErrorId  := _uFaultCode;                   // 故障级码优先（Fault-level code wins）
    uDiagCode := _uFaultCode;                   // 诊断码同源（Diagnostic code mirrors the fault）
    bError    := TRUE;                          // 故障标志置位（Error flag raised）
ELSIF _uInfoCode <> 16#0000_0000 THEN
    uErrorId  := 16#0000_0000;                  // 信息级不占故障码（Info level leaves the fault code empty）
    uDiagCode := _uInfoCode;                    // 诊断码取信息级码（Diagnostic code takes the info code）
    bError    := FALSE;                         // 信息级不置故障位（Info level never raises the error flag）
ELSE
    uErrorId  := 16#0000_0000;                  // 无码（No code）
    uDiagCode := 16#0000_0000;                  // 无码（No code）
    bError    := FALSE;                         // 无故障（No error）
END_IF

// ============================================================================
// 段 9｜出口钳位与保持语义重写（R27：判定态逐拍重写，不是进入那一拍的脉冲）
//      Output clamping and held-semantics rewrite (R27)
// ============================================================================
fPeak       := LIMIT(0.0, _fPeakHeld, DL_CAP_NM_MAX);                    // 峰值 0~1E4（Peak clamped）
fSlope      := LIMIT(-DL_CAP_SLOPE_LIM, _fSlopeHeld, DL_CAP_SLOPE_LIM);   // 斜率 ±1E6（Slope clamped）
fSteadyMean := LIMIT(0.0, _fSteadyHeld, DL_CAP_NM_MAX);                   // 稳态均值 0~1E4（Steady mean clamped）
eVerdict    := _eVerdictHeld;                                             // 主判定逐拍重写（Verdict rewritten every scan）
uNgMask     := _uMaskHeld;                                                // 位图逐拍重写（Bitmap rewritten every scan）
bVerdictValid := _bVerdictLatched;                                        // 有效位逐拍重写（Validity rewritten every scan）
nTotal      := _nTotalInt;                                                // 周期计数逐拍重写（Cycle counter rewritten）
nNg         := _nNgInt;                                                   // 不良计数逐拍重写（Reject counter rewritten）

// 健康态仲裁（引用属主 A1 的四态语言；工件 NG 不是设备健康问题）
// Health arbitration: a part NG is not an equipment health problem
IF _eState = E_DL_CapTrendState.eFault THEN
    eHealth := E_DL_Ne107Status.eFailure;       // 故障：数据不可信（Failure）
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：未使能（Unknown）
ELSIF _uInfoCode = DL_CAP_INFO_NOISE THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq;    // 需维护：采集质量下降（Maintenance required, acquisition quality degraded）
ELSIF NOT _bBatchOk AND (_nPtsEff >= DL_CAP_MINP) THEN
    eHealth := E_DL_Ne107Status.eOutOfSpec;     // 越规：缺批次基线，判定不确定度上升（Out of spec, no baseline）
ELSIF _bVerdictLatched THEN
    eHealth := E_DL_Ne107Status.eOk;            // 正常：有有效判定（OK, a valid verdict exists）
ELSE
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：尚无结论（Unknown, no verdict yet）
END_IF

END_FUNCTION_BLOCK
