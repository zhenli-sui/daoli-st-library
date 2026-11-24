(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FoulingResistanceEstimator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 换热器本体退化算法底座
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / LN / ABS / MIN / MAX / LIMIT），零厂商方言
 * 接口依赖 (Depends)    : E_DL_Ne107Status —— 唯一属主为 DL_Device 子库的契约件
 *                         I_DL_DeviceHealth（R13 泳道 A1）。本文件只按成员名引用该枚举，
 *                         不重复定义枚举体（重复定义即同名异型，R33 家族超集风险）。
 * 功能描述 (Function)   : 由热侧/冷侧进出口温度与体积流量算出换热量 Q、对数平均温差
 *                         LMTD 与实测传热系数 K，再由 K 与清洁态基准 K_clean 反算污垢
 *                         热阻 Rf = 1/K − 1/K_clean；在趋势窗 tWindow 内用最小二乘做
 *                         Rf 对时间的线性拟合，输出增长斜率与清洗建议。
 *                         本件是「换热器污垢趋势」工艺件的算法底座：只做「算一个值 +
 *                         算一个趋势」，不判工艺合格、不控阀门、不做结垢成分分析。
 * 边界     (Boundary)   : ① 不做 PID、不做阀门/泵控制；② 不做结垢成分与化学分析；
 *                         ③ 数据不可信（温差过小 / 流量过低 / 两侧热负荷不平衡 /
 *                            输入非有限）时**拒绝更新**并保持上次有效值 —— 宁可不给
 *                            数，也不给脏数（R42 精神：判可用与取值同拍）；
 *                         ④ 不内置换热器几何模型与介质物性库，fCp/fRho 与 K_clean 全部
 *                            由调用方按设备台账注入。
 * 分层声明 (Layer)      : 算法层（DL_Algo）。上游为工艺台账件与 HMI 趋势，下游仅
 *                         Standard.library。零全局变量表引用、零外部变量声明、零物理 IO。
 * 段序     (Segments)   : 段1 实例无条件刷新 → 段2 复位通道（CASE 之前，R39）→
 *                         段3 参数闸门与输入防御 → 段4 数据质量四判据 → 段5 状态机 →
 *                         段6 有效更新与趋势累计 → 段7 结论仲裁 → 段8 码位单一优先级链 →
 *                         段9 出口钳位与保持语义重写。
 * 枚举映射表 (R31)      : eIdle(0)→标签 0｜eValid(10)→标签 10｜eTrend(20)→标签 20｜
 *                         eAdvice(30)→标签 30｜eFault(99)→标签 99。每个成员有且仅有一个
 *                         显式标签，ELSE 只接脏值（2212）。
 * 单拍标志清单 (R25)    : 本件唯一的沿输入是 bReset（复位），其消费点为段2 复位通道。
 *                         预清零点：段1 末（_bResetEdge := _fbTrigReset.Q 每次覆盖）；
 *                         置位点：段1 的 _fbTrigReset 实例调用；自清点：紧随实例调用之后
 *                         的 _bResetEdge 赋值行（下拍 R_TRIG.Q 转假即自然清）。
 * 保持位清单 (R27)      : bCleanAdvice（清洗建议，逐拍由 _bCleanLatched 重写）｜
 *                         fQ / fLmtd / fK / fRf（上次有效值，逐拍由 _fXxxHeld 重写并钳位）｜
 *                         fRfSlope（上次窗口斜率，逐拍重写）。复位沿清除锁存与保持值。
 * 定时器清单 (R40)      : 无 TON/TOF 实例。趋势窗以引脚 tSamplePeriod 累加计时，
 *                         窗边界显式重装基准（_fWinElapsedH := 0），不存在跨窗恒真输入；
 *                         时长到**或**样本数触顶（64）即结算并重开新窗，触顶提前结算是为了
 *                         避免「为了凑时长而丢掉分辨率」，也避免样本触顶后窗永远关不上。
 * 三元一致表 (R35)      : 流量比例守卫 0.05~0.9 / 封顶 0.9 / 判据 `<`（低于即不更新）｜
 *                         热平衡容差守卫 0.02~0.5 / 封顶 0.5 / 判据 `>`（超出即不更新）｜
 *                         最小温差守卫 0.5~20 K / 封顶 20 K / 判据 `<`（低于即不更新）。
 * 镜像量清单 (R38)      : 实时量 fFlowHot / fFlowCold 的唯一消费点是段4 的流量比例
 *                         判定（自学习参考流量 _fFlowHotMax / _fFlowColdMax 在同段更新）；
 *                         本件不设「锁存副本 + 实时镜像」双源，边界量全部取自本拍单次读取。
 * 开源溯源 (Origin)     : 原创实现（参考 OSCAT Building 的「温度/流量进 → 传热系数与
 *                         污垢热阻出」行为定义组织方式，T1-2；OSCAT 现行版为 EPL-2.0，
 *                         归档旧件仍受其原始许可约束 —— 本件只取行为定义与引脚组织，
 *                         未下载库文件、未复制任何源码行，公式取自公开传热学常识：
 *                         Q = m·cp·ΔT、逆/顺流 LMTD、Rf = 1/K − 1/K_clean）。
 *                         许可证结论：无代码复制，本文件为本库原创，随本库许可证发布。
 * 验收向量 (Acceptance) :
 *   V1 热侧 90/70 ℃、冷侧 20/40 ℃、逆流、两侧 10 m³/h：ΔT1 = 90−40 = 50 K、
 *      ΔT2 = 70−20 = 50 K，两温差相等时 LMTD 退化为算术平均 50.0 K；fQ ≈ 232.2 kW
 *      （10 m³/h × 1000 kg/m³ × 4.18 kJ/(kg·K) × 20 K / 3600）。规格记 49.7 K 与
 *      232 kW 为取整口径，本件按上式复算（见偏离留档②）。
 *   V2 fK = 1000、fKClean = 2000 → fRf = 1/1000 − 1/2000 = 5.0E-4 ≥ 3.0E-4 →
 *      bCleanAdvice = TRUE（保持态逐拍重写）。
 *   V3（V-A 除零）fArea = 0 → 16#0002_2210，fK 保持上次值并夹进 ≥ 0（R43）。
 *   V4（V-C 跨拍复验）进入 eTrend 后当拍流量骤降 → 段4 本拍复验流量门限失败 →
 *      本拍不更新、不累计斜率样本（绝不用上一相结论直接算斜率，R42）。
 *   V5（V-D 首拍）上电首拍 bValid = FALSE、fRf = 0.0，且首拍样本**不**写入趋势基准
 *      （R19：首扫只装基准，不参与斜率）。
 * 偏离留档 (Deviation)  :
 *   ① 「流量低于额定比例」的额定量：规格未给出额定流量引脚。本件以块内自学习的
 *      「投运以来观测到的最大流量」为参考（_fFlowHotMax / _fFlowColdMax），比例 =
 *      本拍流量 / 参考流量。理由：不新增引脚即可表达「相对自身额定」的语义；影响：
 *      上电初期参考流量偏低，门限自然宽松，随运行收敛（首拍样本不受门限影响）。
 *   ② V1 的 LMTD 数值：等温差时 LMTD 退化为算术平均（数值稳定性要求），与规格
 *      49.7 K 的取整口径相差 0.3 K，属口径差异而非算法差异，此处显式留档。
 *   ③ 输入非有限与「面积/清洁 K 非正」共用 16#0002_2210（规格故障表只给 3 个故障码，
 *      不新增码位；码位表以 §3.0 为准，编码者不得自行偏移）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 C · DL_Algo 第 28 件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FoulingState（归属 FB_DL_FoulingResistanceEstimator，同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FoulingState :
(
    eIdle   := 0,    // 空闲：未使能或参数未就绪 / Idle, disabled or parameters not ready
    eValid  := 10,   // 有效：本拍已算出可信的 K 与 Rf / Valid, trustworthy K and Rf computed
    eTrend  := 20,   // 趋势：窗内样本数已达 3，斜率可算 / Trend, at least three window samples
    eAdvice := 30,   // 建议清洗：热阻或其斜率越阈（锁存）/ Cleaning advised, latched
    eFault  := 99    // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_FoulingResistanceEstimator
VAR_INPUT
    bEnable         : BOOL;                 // 使能（Enable），FALSE = 冻结更新并回空闲；复位通道不受其屏蔽 / Enable, FALSE freezes updates
    bReset          : BOOL;                 // 复位（Reset），上升沿清趋势窗、清洗锁存与保持值 / Rising edge clears trend window and latches
    fTinHot         : REAL;                 // 热侧进口温度（Hot inlet temperature）[℃]，域 −50~300 / Hot side inlet temperature [degC]
    fToutHot        : REAL;                 // 热侧出口温度（Hot outlet temperature）[℃]，域 −50~300 / Hot side outlet temperature [degC]
    fTinCold        : REAL;                 // 冷侧进口温度（Cold inlet temperature）[℃]，域 −50~300 / Cold side inlet temperature [degC]
    fToutCold       : REAL;                 // 冷侧出口温度（Cold outlet temperature）[℃]，域 −50~300 / Cold side outlet temperature [degC]
    fFlowHot        : REAL;                 // 热侧体积流量（Hot volumetric flow）[m³/h]，域 0~10000 / Hot volumetric flow [m3/h]
    fFlowCold       : REAL;                 // 冷侧体积流量（Cold volumetric flow）[m³/h]，域 0~10000 / Cold volumetric flow [m3/h]
    fCpHot          : REAL := 4.18;         // 热侧比热（Hot specific heat）[kJ/(kg·K)]，域 0.5~10，默认 4.18 / Hot specific heat [kJ/(kg K)]
    fCpCold         : REAL := 4.18;         // 冷侧比热（Cold specific heat）[kJ/(kg·K)]，域 0.5~10，默认 4.18 / Cold specific heat [kJ/(kg K)]
    fRhoHot         : REAL := 1000.0;       // 热侧密度（Hot density）[kg/m³]，域 1~2000，默认 1000.0 / Hot density [kg/m3]
    fRhoCold        : REAL := 1000.0;       // 冷侧密度（Cold density）[kg/m³]，域 1~2000，默认 1000.0 / Cold density [kg/m3]
    fArea           : REAL;                 // 换热面积（Heat transfer area）[m²]，域 >0，除零保护对象 / Heat transfer area [m2], must be positive
    fKClean         : REAL;                 // 清洁态传热系数基准（Clean-condition K）[W/(m²·K)]，域 >0 / Clean-condition K [W/(m2 K)], must be positive
    bCounterFlow    : BOOL := TRUE;         // 流型（Flow arrangement），TRUE = 逆流，FALSE = 顺流，默认 TRUE / TRUE counter-flow, FALSE parallel-flow
    fDtmMin         : REAL := 2.0;          // 最小可用温差（Minimum usable temperature difference）[K]，域 0.5~20，默认 2.0 / Minimum usable LMTD [K]
    fHeatBalTol     : REAL := 0.10;         // 两侧热负荷允许偏差比（Heat balance tolerance）[-]，域 0.02~0.5，默认 0.10 / Heat balance tolerance [-]
    fFlowMinRatio   : REAL := 0.20;         // 流量下限比例（Minimum flow ratio）[-]，域 0.05~0.9，默认 0.20 / Minimum flow ratio [-]
    tWindow         : TIME := T#1H;         // 趋势窗长（Trend window），域 5 min~24 h，默认 1 h / Trend window, default 1 h
    tSamplePeriod   : TIME := T#10S;        // 调用周期（Call period）[ms]，必须与实际任务周期一致，默认 10 s / Call period, must match the task
    fRfAlarm        : REAL := 3.0E-4;       // 污垢热阻报警阈（Fouling resistance alarm）[m²·K/W]，域 1E-5~5E-3 / Fouling resistance alarm [m2 K/W]
    fSlopeAlarm     : REAL := 2.0E-5;       // 污垢增长速率阈（Fouling slope alarm）[m²·K/(W·h)]，域 1E-7~1E-3 / Fouling slope alarm [m2 K/(W h)]
END_VAR

VAR_OUTPUT
    fQ              : REAL;                 // 热负荷两侧平均（Heat duty, mean of both sides）[kW]，保持语义 / Mean heat duty of both sides [kW], held
    fLmtd           : REAL;                 // 对数平均温差（Log mean temperature difference）[K]，保持语义 / LMTD [K], held
    fK              : REAL;                 // 实测传热系数（Measured overall K）[W/(m²·K)]，保持语义且夹进 ≥0 / Measured K [W/(m2 K)], held and clamped non-negative
    fRf             : REAL;                 // 污垢热阻（Fouling resistance）[m²·K/W]，= 1/K − 1/K_clean，保持语义 / Fouling resistance [m2 K/W], held
    fRfSlope        : REAL;                 // 窗内趋势斜率（Trend slope in window）[m²·K/(W·h)]，保持语义 / Trend slope [m2 K/(W h)], held
    bValid          : BOOL;                 // 本拍输出有效（Output valid this scan），数据质量不足时为 FALSE / TRUE when this scan produced a trustworthy value
    bCleanAdvice    : BOOL;                 // 建议清洗（Cleaning advised），保持语义（R27），复位沿清除 / Cleaning advised, held until reset
    eHealth         : E_DL_Ne107Status;     // 健康态（NE107 health），引用属主 A1 的枚举 / NE107 health state, owned by A1
    uDiagCode       : UDINT;                // 诊断码（Diagnostic code），本拍单一优先级链输出 / Diagnostic code, single priority chain
    uErrorId        : UDINT;                // 故障码（Error code），仅故障级码，0 = 无故障 / Fault-level code, 0 = no fault
    bError          : BOOL;                 // 故障标志（Error），仅故障级码置位，信息级不置位 / TRUE only for fault-level codes
    nUpdateCount    : UDINT;                // 有效更新次数（Valid update counter）[次]，每次有效更新 +1 / Valid update counter [count]
END_VAR

VAR
    _eState         : E_DL_FoulingState := E_DL_FoulingState.eIdle; // 内部状态（Internal state）/ Internal state machine value
    _bInit          : BOOL;                 // 首扫标志（First-scan flag），初值 FALSE，唯一首扫判据为 NOT _bInit（R19）/ First-scan flag, FALSE by default
    _bSkipSample    : BOOL;                 // 本拍不参与斜率（Skip trend sample this scan），首扫与不可信拍置位 / Skip this scan as a trend sample
    _bParamOk       : BOOL;                 // 参数闸门通过（Parameter gate passed）/ Parameter gate result
    _bDataOk        : BOOL;                 // 数据质量通过（Data quality passed）/ Data quality result
    _bValidNow      : BOOL;                 // 本拍有效（Valid this scan）/ Valid this scan
    _bFaultCond     : BOOL;                 // 故障条件（Fault condition latch-free flag）/ Fault condition flag
    _uFaultCode     : UDINT;                // 本拍故障级码（Fault-level code this scan）/ Fault-level code of this scan
    _uFaultLatched  : UDINT;                // 故障码锁存（Latched fault code），仅复位沿清除 / Latched fault code, reset only
    _uInfoCode      : UDINT;                // 本拍信息级码（Info-level code this scan），每拍重算 / Info-level code, recomputed every scan
    _bArrPrev       : BOOL;                 // 上拍流型（Previous flow arrangement）/ Flow arrangement of the previous scan
    _bArrKnown      : BOOL;                 // 流型已记录（Arrangement recorded）/ Arrangement recorded flag
    _fAreaEff       : REAL;                 // 生效换热面积（Effective area）[m²]，闸门后值 / Effective area [m2] after the gate
    _fKCleanEff     : REAL;                 // 生效清洁 K（Effective clean K）[W/(m²·K)] / Effective clean K [W/(m2 K)]
    _fDtmMinEff     : REAL;                 // 生效最小温差（Effective minimum LMTD）[K]，钳位 0.5~20 / Effective minimum LMTD [K], clamped
    _fBalTolEff     : REAL;                 // 生效热平衡容差（Effective heat balance tolerance）[-]，钳位 0.02~0.5 / Effective heat balance tolerance, clamped
    _fFlowRatioEff  : REAL;                 // 生效流量比例（Effective minimum flow ratio）[-]，钳位 0.05~0.9 / Effective minimum flow ratio, clamped
    _fFlowHotMax    : REAL;                 // 热侧参考流量（Hot reference flow）[m³/h]，自学习峰值 / Self-learned hot reference flow [m3/h]
    _fFlowColdMax   : REAL;                 // 冷侧参考流量（Cold reference flow）[m³/h]，自学习峰值 / Self-learned cold reference flow [m3/h]
    _fQHot          : REAL;                 // 热侧放热量（Heat duty, hot side）[kW]，有符号 / Hot-side duty [kW], signed
    _fQCold         : REAL;                 // 冷侧吸热量（Heat duty, cold side）[kW]，有符号 / Cold-side duty [kW], signed
    _fQMean         : REAL;                 // 两侧平均热负荷（Mean duty）[kW] / Mean duty of both sides [kW]
    _fDt1           : REAL;                 // 端差一（Terminal difference one）[K]，按流型取 / Terminal temperature difference one [K]
    _fDt2           : REAL;                 // 端差二（Terminal difference two）[K]，按流型取 / Terminal temperature difference two [K]
    _fLmtdCalc      : REAL;                 // 本拍 LMTD 计算值（Computed LMTD）[K] / Computed LMTD [K]
    _fLmtdAbs       : REAL;                 // 端差差值的绝对值（Absolute terminal difference gap）[K]，退化判据 / Absolute gap between terminal differences [K]
    _fLmtdDen       : REAL;                 // 对数比值（Logarithmic ratio）[-]，除零保护对象 / Logarithmic ratio, divide-guard object
    _fBalDev        : REAL;                 // 热平衡偏差比（Heat balance deviation）[-] / Heat balance deviation ratio [-]
    _fBalRef        : REAL;                 // 热平衡参考量（Heat balance reference）[kW]/ Reference magnitude for the balance test [kW]
    _fKCalc         : REAL;                 // 本拍 K 计算值（Computed K）[W/(m²·K)] / Computed K [W/(m2 K)]
    _fRfCalc        : REAL;                 // 本拍 Rf 计算值（Computed Rf）[m²·K/W] / Computed Rf [m2 K/W]
    _fQHeld         : REAL;                 // 保持的热负荷（Held heat duty）[kW] / Held heat duty [kW]
    _fLmtdHeld      : REAL;                 // 保持的 LMTD（Held LMTD）[K] / Held LMTD [K]
    _fKHeld         : REAL;                 // 保持的 K（Held K）[W/(m²·K)] / Held K [W/(m2 K)]
    _fRfHeld        : REAL;                 // 保持的 Rf（Held Rf）[m²·K/W] / Held Rf [m2 K/W]
    _fSlopeHeld     : REAL;                 // 保持的斜率（Held slope）[m²·K/(W·h)] / Held slope [m2 K/(W h)]
    _bCleanLatched  : BOOL;                 // 清洗建议锁存（Cleaning advice latch），仅复位沿清除 / Cleaning advice latch, reset only
    _nWinN          : INT;                  // 窗内样本数（Window sample count）[个]，上限 64 / Window sample count, capped at 64
    _fWinElapsedH   : REAL;                 // 窗内已历时（Elapsed hours in window）[h] / Elapsed hours in the current window [h]
    _fWinX          : REAL;                 // 最小二乘 Σt（Sum of time stamps）[h] / Least-squares sum of time stamps [h]
    _fWinY          : REAL;                 // 最小二乘 ΣRf（Sum of Rf samples）[m²·K/W] / Least-squares sum of Rf samples [m2 K/W]
    _fWinXY         : REAL;                 // 最小二乘 Σt·Rf（Sum of products）[h·m²·K/W] / Least-squares sum of products
    _fWinXX         : REAL;                 // 最小二乘 Σt²（Sum of squared times）[h²] / Least-squares sum of squared times [h2]
    _fWinDen        : REAL;                 // 最小二乘分母（Normal-equation denominator）[-]，除零保护对象 / Denominator of the normal equations
    _fWinNum        : REAL;                 // 最小二乘分子（Normal-equation numerator）[-] / Numerator of the normal equations
    _fDtHours       : REAL;                 // 本拍步长（Step in hours）[h]，由 tSamplePeriod 折算 / Step in hours, derived from the call period
    _fWinHoursEff   : REAL;                 // 生效窗长（Effective window length）[h]，由 tWindow 折算 / Effective window length [h]
    _fbTrigReset    : R_TRIG;               // 复位沿（Reset edge detector），主体最前部无条件刷新 / Reset edge detector, refreshed unconditionally
    _bResetEdge     : BOOL;                 // 复位沿单拍标志（Reset one-shot flag），紧随实例自清 / Reset one-shot flag, cleared right after the call
END_VAR

VAR CONSTANT
    DL_FRE_REAL_MAX   : REAL := 3.4E38;      // 单精度有限值判据幅值（Finite magnitude bound）/ Finite bound for REAL inputs
    DL_FRE_EPS        : REAL := 1.0E-6;      // 浮点防零容差（Divide-guard epsilon）/ Float divide-guard epsilon
    DL_FRE_K_MAX      : REAL := 1.0E9;       // K 出口上限（K output ceiling）[W/(m²·K)] / Upper clamp of K [W/(m2 K)]
    DL_FRE_RF_MAX     : REAL := 1.0;         // Rf 出口上限（Rf output ceiling）[m²·K/W] / Upper clamp of Rf [m2 K/W]
    DL_FRE_SLOPE_MAX  : REAL := 1.0;         // 斜率出口上限（Slope output ceiling）[m²·K/(W·h)] / Upper clamp of slope
    DL_FRE_SLOPE_MIN  : REAL := -1.0;        // 斜率出口下限（Slope output floor）[m²·K/(W·h)] / Lower clamp of slope
    DL_FRE_WIN_MAX    : INT  := 64;          // 窗内样本上限（Window sample ceiling）[个] / Window sample ceiling
    DL_FRE_MS_PER_H   : REAL := 3600000.0;   // 毫秒→小时换算（Milliseconds-to-hours scale）[-] / Milliseconds-to-hours scale
    DL_FRE_KW_SCALE   : REAL := 3600.0;      // m³/h·kg/m³·kJ/(kg·K)·K → kW 的换算（Duty unit scale）[-] / Duty unit scale
    DL_FRE_W_SCALE    : REAL := 1000.0;      // kW → W 换算（Kilowatt-to-watt scale）[-] / Kilowatt-to-watt scale
    DL_FRE_DTM_MIN    : REAL := 0.5;         // 最小温差域下限（Minimum LMTD lower clamp）[K] / Minimum LMTD lower clamp [K]
    DL_FRE_DTM_MAX    : REAL := 20.0;        // 最小温差域上限（Minimum LMTD upper clamp）[K] / Minimum LMTD upper clamp [K]
    DL_FRE_TOL_MIN    : REAL := 0.02;        // 热平衡容差域下限（Balance tolerance lower clamp）[-] / Balance tolerance lower clamp
    DL_FRE_TOL_MAX    : REAL := 0.5;         // 热平衡容差域上限（Balance tolerance upper clamp）[-] / Balance tolerance upper clamp
    DL_FRE_RATIO_MIN  : REAL := 0.05;        // 流量比例域下限（Flow ratio lower clamp）[-] / Flow ratio lower clamp
    DL_FRE_RATIO_MAX  : REAL := 0.9;         // 流量比例域上限（Flow ratio upper clamp）[-] / Flow ratio upper clamp
    DL_FRE_RF_FLOOR   : REAL := 0.0;         // Rf 出口下限（Rf output floor）[m²·K/W]，K>K_clean 时按 0 / Rf floor, zero when K exceeds clean K
    DL_FRE_WIN_MIN_N  : INT  := 3;           // 斜率所需最少样本（Minimum samples for a slope）[个] / Minimum samples for the slope
    DL_FRE_ERR_PARAM  : UDINT := 16#0002_2210; // 0002_2210 面积/清洁 K 非正或输入非有限【故障级】/ Illegal area, clean K or non-finite input
    DL_FRE_ERR_LMTD   : UDINT := 16#0002_2211; // 0002_2211 LMTD ≤ 0（温度交叉或流型用错）【故障级】/ Non-positive LMTD
    DL_FRE_ERR_STATE  : UDINT := 16#0002_2212; // 0002_2212 非法状态兜底【故障级】/ Illegal state fallback
    DL_FRE_INFO_LMTD  : UDINT := 16#0002_2201; // 0002_2201 LMTD 低于最小可用温差【信息级】/ LMTD below the usable limit
    DL_FRE_INFO_FLOW  : UDINT := 16#0002_2202; // 0002_2202 流量低于下限比例【信息级】/ Flow below the minimum ratio
    DL_FRE_INFO_BAL   : UDINT := 16#0002_2203; // 0002_2203 两侧热负荷偏差超容差【信息级】/ Heat balance exceeded
    DL_FRE_INFO_ARR   : UDINT := 16#0002_2204; // 0002_2204 逆/顺流口径切换，趋势基准已重置【信息级】/ Arrangement changed, trend reset
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of every instance (R7/0.5)
// ============================================================================
_fbTrigReset(CLK := bReset);            // 复位沿实例调用（Reset edge instance call）
_bResetEdge := _fbTrigReset.Q;          // 单拍标志紧随实例赋值，下拍自然清（R24/R25 自清点）

// 本拍故障/信息码与结论预置（每拍重算，杜绝跨拍残留）
// Per-scan preset of codes and conclusions, no cross-scan residue
_uFaultCode  := _uFaultLatched;         // 故障码以上拍锁存续用（Carry the latched fault code）
_uInfoCode   := 16#0000_0000;           // 信息级码预清零（Info code preset to zero）
_bFaultCond  := FALSE;                  // 故障条件预清零（Fault condition preset FALSE）
_bParamOk    := FALSE;                  // 参数闸门预置未通过（Parameter gate preset closed）
_bDataOk     := FALSE;                  // 数据质量预置未通过（Data quality preset failed）
_bValidNow   := FALSE;                  // 本拍有效预置假（Valid preset FALSE）
_bSkipSample := FALSE;                  // 采样跳过预置假（Sample skip preset FALSE）

// 调用周期折算为小时，非法周期按复位通道外的钳位处理（不做除零）
// Convert the call period into hours, illegal periods are clamped instead of divided by zero
IF tSamplePeriod >= T#1MS THEN
    _fDtHours := TIME_TO_REAL(tSamplePeriod) / DL_FRE_MS_PER_H;   // 毫秒 → 小时（Milliseconds to hours）
ELSE
    _fDtHours := 0.0;                   // 周期非法时不推进窗口（Illegal period does not advance the window）
    _bFaultCond := TRUE;                // 周期非法按参数故障处理（Illegal period treated as a parameter fault）
    _uFaultCode := DL_FRE_ERR_PARAM;    // 0002_2210 周期非法并入参数故障【故障级】/ Illegal period folded into the parameter fault
END_IF

// ============================================================================
// 段 2｜复位通道（R39：置于 CASE 之前，且不被掉使能分支屏蔽）
//      Reset path, placed before CASE and never masked by the disable branch
// ============================================================================
IF _bResetEdge THEN
    _bCleanLatched := FALSE;            // 清洗建议锁存清除（Cleaning advice latch cleared）
    _nWinN         := 0;                // 窗内样本数清零（Window sample count cleared）
    _fWinElapsedH  := 0.0;              // 窗内历时清零（Window elapsed cleared）
    _fWinX         := 0.0;              // Σt 清零（Sum of time cleared）
    _fWinY         := 0.0;              // ΣRf 清零（Sum of Rf cleared）
    _fWinXY        := 0.0;              // Σt·Rf 清零（Sum of products cleared）
    _fWinXX        := 0.0;              // Σt² 清零（Sum of squares cleared）
    _fSlopeHeld    := 0.0;              // 斜率保持值清零（Held slope cleared）
    _fRfHeld       := 0.0;              // Rf 保持值清零（Held Rf cleared）
    _fKHeld        := 0.0;              // K 保持值清零（Held K cleared）
    _fQHeld        := 0.0;              // 热负荷保持值清零（Held duty cleared）
    _fLmtdHeld     := 0.0;              // LMTD 保持值清零（Held LMTD cleared）
    _uFaultLatched := 16#0000_0000;     // 故障码锁存清除（Latched fault code cleared）
    _uFaultCode    := 16#0000_0000;     // 本拍故障码随复位清空，防止段8 重新锁存旧码（Clear this scan code）
    IF _eState = E_DL_FoulingState.eFault THEN
        _eState := E_DL_FoulingState.eIdle;  // 故障态回空闲（Fault state back to idle）
        _uFaultCode := 16#0000_0000;    // 故障码随复位清除（Fault code cleared with the reset）
        _bFaultCond := FALSE;           // 故障条件随复位清除（Fault condition cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜参数闸门与输入防御（先判可用，再算值；R42 同源纪律）
//      Parameter gate and input defense: availability first, arithmetic second
// ============================================================================
IF (NOT (fArea     >= (-DL_FRE_REAL_MAX) AND fArea     <= DL_FRE_REAL_MAX))
OR (NOT (fKClean   >= (-DL_FRE_REAL_MAX) AND fKClean   <= DL_FRE_REAL_MAX))
OR (NOT (fTinHot   >= (-DL_FRE_REAL_MAX) AND fTinHot   <= DL_FRE_REAL_MAX))
OR (NOT (fToutHot  >= (-DL_FRE_REAL_MAX) AND fToutHot  <= DL_FRE_REAL_MAX))
OR (NOT (fTinCold  >= (-DL_FRE_REAL_MAX) AND fTinCold  <= DL_FRE_REAL_MAX))
OR (NOT (fToutCold >= (-DL_FRE_REAL_MAX) AND fToutCold <= DL_FRE_REAL_MAX))
OR (NOT (fFlowHot  >= (-DL_FRE_REAL_MAX) AND fFlowHot  <= DL_FRE_REAL_MAX))
OR (NOT (fFlowCold >= (-DL_FRE_REAL_MAX) AND fFlowCold <= DL_FRE_REAL_MAX))
OR (NOT (fCpHot    >= (-DL_FRE_REAL_MAX) AND fCpHot    <= DL_FRE_REAL_MAX))
OR (NOT (fCpCold   >= (-DL_FRE_REAL_MAX) AND fCpCold   <= DL_FRE_REAL_MAX))
OR (NOT (fRhoHot   >= (-DL_FRE_REAL_MAX) AND fRhoHot   <= DL_FRE_REAL_MAX))
OR (NOT (fRhoCold  >= (-DL_FRE_REAL_MAX) AND fRhoCold  <= DL_FRE_REAL_MAX))
OR (NOT (fRfAlarm  >= (-DL_FRE_REAL_MAX) AND fRfAlarm  <= DL_FRE_REAL_MAX))
OR (NOT (fSlopeAlarm >= (-DL_FRE_REAL_MAX) AND fSlopeAlarm <= DL_FRE_REAL_MAX)) THEN
    _bFaultCond := TRUE;                // 任一输入非有限即故障（Any non-finite input is a fault）
    _uFaultCode := DL_FRE_ERR_PARAM;    // 0002_2210 输入非有限【故障级】/ Non-finite input, fault level
ELSIF fArea <= 0.0 THEN
    _bFaultCond := TRUE;                // 面积非正：K 的分母不可用（Non-positive area breaks the K denominator）
    _uFaultCode := DL_FRE_ERR_PARAM;    // 0002_2210 面积非正【故障级】/ Illegal area, fault level
ELSIF fKClean <= 0.0 THEN
    _bFaultCond := TRUE;                // 清洁 K 非正：Rf 的基准不可用（Non-positive clean K breaks the Rf basis）
    _uFaultCode := DL_FRE_ERR_PARAM;    // 0002_2210 清洁 K 非正【故障级】/ Illegal clean K, fault level
ELSE
    _bParamOk := TRUE;                  // 参数闸门通过（Parameter gate passed）
END_IF

// 生效参数的域钳位（R35：守卫、封顶值、判据运算符三者同向）
// Clamp effective parameters, keeping guard, ceiling and comparison operator in step (R35)
_fDtmMinEff    := LIMIT(DL_FRE_DTM_MIN, fDtmMin, DL_FRE_DTM_MAX);       // 最小温差钳位 0.5~20 K（Minimum LMTD clamped）
_fBalTolEff    := LIMIT(DL_FRE_TOL_MIN, fHeatBalTol, DL_FRE_TOL_MAX);   // 热平衡容差钳位 0.02~0.5（Balance tolerance clamped）
_fFlowRatioEff := LIMIT(DL_FRE_RATIO_MIN, fFlowMinRatio, DL_FRE_RATIO_MAX); // 流量比例钳位 0.05~0.9（Flow ratio clamped）
_fWinHoursEff  := TIME_TO_REAL(tWindow) / DL_FRE_MS_PER_H;   // 窗长折算为小时（Window length in hours）
_fAreaEff      := fArea;                // 面积已过正数防御（Area already defended positive inside the gate）
_fKCleanEff     := fKClean;             // 清洁 K 已过正数防御（Clean K already defended positive inside the gate）

// 参考流量自学习（偏离留档①）：上电初期参考值随运行收敛，仅用于相对流量判定
// Self-learned reference flow (deviation 1): converges during commissioning, used for the relative flow test
IF fFlowHot >= 0.0 THEN
    _fFlowHotMax  := MAX(_fFlowHotMax, fFlowHot);   // 热侧参考取历史峰值（Hot reference takes the historic peak）
ELSE
    _fFlowHotMax  := _fFlowHotMax;                  // 负流量不参与自学习（Negative flow is not learned）
END_IF
IF fFlowCold >= 0.0 THEN
    _fFlowColdMax := MAX(_fFlowColdMax, fFlowCold); // 冷侧参考取历史峰值（Cold reference takes the historic peak）
ELSE
    _fFlowColdMax := _fFlowColdMax;                 // 负流量不参与自学习（Negative flow is not learned）
END_IF

// ============================================================================
// 段 4｜数据质量四判据（本拍复验；判「可用」与取「值」同拍完成，R42）
//      Four data-quality criteria, all re-evaluated on this very scan (R42)
// ============================================================================
IF _bParamOk AND bEnable AND (NOT _bFaultCond) THEN

    // 4.1 计算两侧热负荷（有符号，kW）：Q = V̇ · ρ · cp · ΔT / 3600
    //     Duty on both sides, signed, in kW
    _fQHot  := fFlowHot  * fRhoHot  * fCpHot  * (fTinHot  - fToutHot)  / DL_FRE_KW_SCALE;
    _fQCold := fFlowCold * fRhoCold * fCpCold * (fToutCold - fTinCold) / DL_FRE_KW_SCALE;
    _fQMean := (ABS(_fQHot) + ABS(_fQCold)) / 2.0;   // 两侧平均热负荷（Mean duty of both sides）

    // 4.2 端差按流型取：逆流对热进-冷出；顺流对热进-冷进
    //     Terminal differences by flow arrangement
    IF bCounterFlow THEN
        _fDt1 := fTinHot - fToutCold;   // 逆流端差一（Counter-flow terminal difference one）
        _fDt2 := fToutHot - fTinCold;   // 逆流端差二（Counter-flow terminal difference two）
    ELSE
        _fDt1 := fTinHot - fTinCold;    // 顺流端差一（Parallel-flow terminal difference one）
        _fDt2 := fToutHot - fToutCold;  // 顺流端差二（Parallel-flow terminal difference two）
    END_IF

    // 4.3 LMTD：端差相等时退化为算术平均，避免 ln(1)=0 造成除零
    //     LMTD degenerates to the arithmetic mean when both terminal differences are equal
    _fLmtdAbs := ABS(_fDt1 - _fDt2);    // 端差差值绝对值（Absolute gap of the terminal differences）
    IF _fLmtdAbs < DL_FRE_EPS THEN
        _fLmtdCalc := (_fDt1 + _fDt2) / 2.0;    // 等温差退化（Equal-difference degeneration）
    ELSIF (_fDt1 <= 0.0) OR (_fDt2 <= 0.0) THEN
        _fLmtdCalc := 0.0;              // 温度交叉：本拍不可算（Temperature cross, not computable）
    ELSE
        _fLmtdDen  := _fDt1 / _fDt2;    // 对数比值（Logarithmic ratio），两端差均为正才有意义
        _fLmtdCalc := (_fDt1 - _fDt2) / LN(_fLmtdDen);   // 标准 LMTD 定义（Standard LMTD definition）
    END_IF

    // 4.4 流型切换：趋势基准必须重置，否则跨流型样本混算斜率
    //     Arrangement change forces a trend reset, mixing arrangements would corrupt the slope
    IF _bArrKnown AND (bCounterFlow <> _bArrPrev) THEN
        _nWinN        := 0;             // 窗内样本清零（Window samples cleared）
        _fWinElapsedH := 0.0;           // 窗内历时清零（Window elapsed cleared）
        _fWinX        := 0.0;           // Σt 清零（Sum of time cleared）
        _fWinY        := 0.0;           // ΣRf 清零（Sum of Rf cleared）
        _fWinXY       := 0.0;           // Σt·Rf 清零（Sum of products cleared）
        _fWinXX       := 0.0;           // Σt² 清零（Sum of squares cleared）
        _uInfoCode    := DL_FRE_INFO_ARR;   // 0002_2204 流型切换趋势重置【信息级】/ Arrangement changed, info level
    END_IF
    _bArrPrev  := bCounterFlow;         // 记录本拍流型（Record this scan arrangement）
    _bArrKnown := TRUE;                 // 流型已记录（Arrangement recorded）

    // 4.5 四判据依次裁决：LMTD 非法 > 温差不足 > 流量不足 > 热平衡超差
    //     Four criteria in a single priority chain
    IF _fLmtdCalc <= 0.0 THEN
        _bFaultCond := TRUE;            // LMTD 非正属故障级（Non-positive LMTD is a fault）
        _uFaultCode := DL_FRE_ERR_LMTD; // 0002_2211 LMTD ≤ 0【故障级】/ Non-positive LMTD, fault level
    ELSIF _fLmtdCalc < _fDtmMinEff THEN
        _uInfoCode := DL_FRE_INFO_LMTD; // 0002_2201 温差太小不可信【信息级】/ LMTD below usable limit
    ELSIF (_fFlowHotMax > DL_FRE_EPS) AND ((fFlowHot / _fFlowHotMax) < _fFlowRatioEff) THEN
        _uInfoCode := DL_FRE_INFO_FLOW; // 0002_2202 热侧流量过低【信息级】/ Hot flow below the ratio
    ELSIF (_fFlowColdMax > DL_FRE_EPS) AND ((fFlowCold / _fFlowColdMax) < _fFlowRatioEff) THEN
        _uInfoCode := DL_FRE_INFO_FLOW; // 0002_2202 冷侧流量过低【信息级】/ Cold flow below the ratio
    ELSE
        _fBalRef := MAX(ABS(_fQHot), ABS(_fQCold));  // 热平衡参考量（Balance reference magnitude）
        IF _fBalRef > DL_FRE_EPS THEN
            _fBalDev := ABS(_fQHot - _fQCold) / _fBalRef;   // 偏差比（Deviation ratio）
        ELSE
            _fBalDev := 1.0;            // 两侧均为零：按最坏偏差处理（Both sides zero: worst case）
        END_IF
        IF _fBalDev > _fBalTolEff THEN
            _uInfoCode := DL_FRE_INFO_BAL;  // 0002_2203 热平衡超差【信息级】/ Heat balance exceeded
        ELSE
            _bDataOk := TRUE;           // 数据质量通过（Data quality passed）
        END_IF
    END_IF
END_IF

// ============================================================================
// 段 5｜状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      State machine with an explicit ELSE fallback
// ============================================================================
IF _bFaultCond THEN
    _eState := E_DL_FoulingState.eFault;    // 故障条件优先于状态机（Fault condition outranks the machine）
END_IF

// 掉使能冻结分支：显式排除故障态，复位通道仍可从故障态退出（R39 合法写法①）
// Disable branch explicitly excludes the fault state, the reset path still works (R39 form 1)
IF (NOT bEnable) AND (_eState <> E_DL_FoulingState.eFault) THEN
    _eState := E_DL_FoulingState.eIdle;     // 冻结回空闲（Freeze back to idle）
    _bDataOk := FALSE;                      // 掉使能时数据质量结论作废（Quality result voided while disabled）
END_IF

CASE _eState OF

    E_DL_FoulingState.eIdle: // 空闲：等使能与参数闸门
        IF bEnable AND _bParamOk AND (NOT _bFaultCond) THEN
            _eState := E_DL_FoulingState.eValid;    // 进有效态（Enter valid state）
        END_IF

    E_DL_FoulingState.eValid: // 有效：等待窗内样本积累
        IF _bDataOk AND (_nWinN >= DL_FRE_WIN_MIN_N) THEN
            _eState := E_DL_FoulingState.eTrend;    // 样本足够进趋势态（Enough samples, enter trend）
        END_IF

    E_DL_FoulingState.eTrend: // 趋势：持续累计，越阈转建议
        IF _bCleanLatched THEN
            _eState := E_DL_FoulingState.eAdvice;   // 越阈转建议清洗（Threshold crossed, advise cleaning）
        END_IF

    E_DL_FoulingState.eAdvice: // 建议清洗：锁存至复位，本分支只做出口重写（R27）
        // 结论与出口在本分支外逐拍重写，此处仅保留空标签与原因注释（R31）
        // Outputs are rewritten outside this branch every scan, so the label stays empty (R31)

    E_DL_FoulingState.eFault: // 故障：等复位沿
        // 复位通道位于 CASE 之前，本分支无需动作，保留标签与原因注释（R31/R39）
        // The reset path sits before CASE, so this branch only keeps the label (R31/R39)

    ELSE // 兜底：非法状态
        _uFaultCode := DL_FRE_ERR_STATE;        // 0002_2212 非法状态兜底【故障级】/ Illegal state fallback
        _bFaultCond := TRUE;                    // 置故障条件（Raise the fault condition）
        _eState     := E_DL_FoulingState.eFault;    // 强制回故障态（Force the fault state）
END_CASE

// ============================================================================
// 段 6｜有效更新与趋势累计（首扫只装基准，不参与斜率，R19）
//      Valid update and trend accumulation, the first scan only loads the basis (R19)
// ============================================================================
IF _bDataOk AND (_eState <> E_DL_FoulingState.eFault) THEN
    _fKCalc := (_fQMean * DL_FRE_W_SCALE) / (_fAreaEff * _fLmtdCalc);   // K = Q / (A · LMTD)
    _fRfCalc := 0.0;                    // Rf 预置 0（Rf preset to zero）
    IF _fKCalc > DL_FRE_EPS THEN
        _fRfCalc := (1.0 / _fKCalc) - (1.0 / _fKCleanEff);  // Rf = 1/K − 1/K_clean
    ELSE
        _fRfCalc := 0.0;                // K 过小按不可算处理（K too small, treated as not computable）
    END_IF
    IF _fRfCalc < DL_FRE_RF_FLOOR THEN
        _fRfCalc := DL_FRE_RF_FLOOR;    // 负污垢（比清洁态更好）按 0（Negative fouling floored to zero）
    END_IF

    // 首扫只装基准：本拍只把有效值写进保持量，不压入趋势样本（R19）
    // First scan loads the basis only: hold the value but never push a trend sample (R19)
    IF NOT _bInit THEN
        _bInit       := TRUE;           // 首扫完成（First scan done）
        _bSkipSample := TRUE;           // 本拍不参与斜率（Do not take a trend sample this scan）
    END_IF

    _fQHeld    := _fQMean;              // 热负荷保持（Duty held）
    _fLmtdHeld := _fLmtdCalc;           // LMTD 保持（LMTD held）
    _fKHeld    := _fKCalc;              // K 保持（K held）
    _fRfHeld   := _fRfCalc;             // Rf 保持（Rf held）
    nUpdateCount := nUpdateCount + UDINT#1; // 有效更新计数（Valid update counted）
    _bValidNow := TRUE;                 // 本拍有效（Valid this scan）

    // 趋势累计：窗内最小二乘（Σt、ΣRf、Σt·Rf、Σt²）
    // Trend accumulation with the normal-equation sums
    //   计时必须**无条件**推进：若只在压样本时才推进，样本数触顶后窗内历时停止增长，
    //   窗永远关不上，斜率也就永远算不出来（这是本件最容易写死的一处）。
    //   Elapsed time advances unconditionally, otherwise a capped sample count freezes the window.
    _fWinElapsedH := _fWinElapsedH + _fDtHours;         // 窗内历时推进（Window elapsed advances）
    IF (NOT _bSkipSample) AND (_nWinN < DL_FRE_WIN_MAX) THEN
        _fWinX        := _fWinX + _fWinElapsedH;        // Σt 累加（Sum of time accumulates）
        _fWinY        := _fWinY + _fRfCalc;             // ΣRf 累加（Sum of Rf accumulates）
        _fWinXY       := _fWinXY + (_fWinElapsedH * _fRfCalc);  // Σt·Rf 累加（Sum of products accumulates）
        _fWinXX       := _fWinXX + (_fWinElapsedH * _fWinElapsedH); // Σt² 累加（Sum of squares accumulates）
        _nWinN        := _nWinN + 1;    // 样本计数 +1（Sample counted）
    END_IF

    // 窗结算：时长到 或 样本数触顶（触顶提前结算，避免为了凑时长而丢掉分辨率）
    // Window settled on the duration or on the sample ceiling, whichever comes first
    IF (_fWinHoursEff > DL_FRE_EPS)
    AND ((_fWinElapsedH >= _fWinHoursEff) OR (_nWinN >= DL_FRE_WIN_MAX)) THEN
        IF _nWinN >= DL_FRE_WIN_MIN_N THEN
            _fWinDen := (INT_TO_REAL(_nWinN) * _fWinXX) - (_fWinX * _fWinX);   // 正规方程分母（Normal-equation denominator）
            IF ABS(_fWinDen) > DL_FRE_EPS THEN
                _fWinNum   := (INT_TO_REAL(_nWinN) * _fWinXY) - (_fWinX * _fWinY);  // 正规方程分子（Numerator）
                _fSlopeHeld := _fWinNum / _fWinDen;     // 斜率 [m²·K/(W·h)]（Slope in engineering units）
            END_IF
        END_IF
        _nWinN        := 1;             // 新窗以当前样本起算（New window starts with this sample）
        _fWinElapsedH := 0.0;           // 新窗历时归零（New window elapsed reset）
        _fWinX        := 0.0;           // Σt 归零（Sum of time reset）
        _fWinY        := _fRfCalc;      // ΣRf 装当前样本（Sum of Rf seeded）
        _fWinXY       := 0.0;           // Σt·Rf 归零（Sum of products reset）
        _fWinXX       := 0.0;           // Σt² 归零（Sum of squares reset）
    END_IF
END_IF

// ============================================================================
// 段 7｜结论仲裁：清洗建议（保持语义，逐拍由锁存重写，R27）
//      Verdict arbitration: cleaning advice, rewritten from the latch every scan (R27)
// ============================================================================
IF _bValidNow THEN
    IF (_fRfHeld >= fRfAlarm) OR (_fSlopeHeld >= fSlopeAlarm) THEN
        _bCleanLatched := TRUE;         // 热阻或斜率越阈，锁存建议（Resistance or slope crossed, latched）
    END_IF
END_IF

// ============================================================================
// 段 8｜码位单一优先级链（全拍只写一次，信息级不置 bError）
//      Single priority chain for the codes, written once per scan
// ============================================================================
IF _uFaultCode <> 16#0000_0000 THEN
    _uFaultLatched := _uFaultCode;      // 故障码锁存，跨拍保持至复位（Latched until reset）
    uErrorId  := _uFaultCode;           // 故障级码优先（Fault-level code wins）
    uDiagCode := _uFaultCode;           // 诊断码同源（Diagnostic code mirrors the fault）
    bError    := TRUE;                  // 故障标志置位（Error flag raised）
ELSIF _uInfoCode <> 16#0000_0000 THEN
    uErrorId  := 16#0000_0000;          // 信息级不占故障码（Info level leaves the fault code empty）
    uDiagCode := _uInfoCode;            // 诊断码取信息级码（Diagnostic code takes the info code）
    bError    := FALSE;                 // 信息级不置故障位（Info level never raises the error flag）
ELSE
    uErrorId  := 16#0000_0000;          // 无码（No code）
    uDiagCode := 16#0000_0000;          // 无码（No code）
    bError    := FALSE;                 // 无故障（No error）
END_IF

// ============================================================================
// 段 9｜出口钳位与保持语义重写（R43：每条出口路径都能追到一次钳位）
//      Output clamping and held-semantics rewrite (R43: one clamp per output path)
// ============================================================================
fQ        := LIMIT(0.0, _fQHeld, (DL_FRE_REAL_MAX / 2.0));           // 热负荷夹进非负域（Duty clamped non-negative）
fLmtd     := LIMIT(0.0, _fLmtdHeld, DL_FRE_REAL_MAX);                // LMTD 夹进非负域（LMTD clamped non-negative）
fK        := LIMIT(0.0, _fKHeld, DL_FRE_K_MAX);                      // K 夹进 0~1E9（K clamped）
fRf       := LIMIT(DL_FRE_RF_FLOOR, _fRfHeld, DL_FRE_RF_MAX);        // Rf 夹进 0~1.0（Rf clamped）
fRfSlope  := LIMIT(DL_FRE_SLOPE_MIN, _fSlopeHeld, DL_FRE_SLOPE_MAX); // 斜率夹进 ±1.0（Slope clamped）
bValid    := _bValidNow;                                             // 有效位逐拍重写（Valid bit rewritten every scan）
bCleanAdvice := _bCleanLatched;                                      // 清洗建议逐拍重写（Advice rewritten every scan）

// 健康态仲裁（引用属主 A1 的四态语言，本件只做映射不做判据扩张）
// Health arbitration mapped onto the A1 health language
IF _eState = E_DL_FoulingState.eFault THEN
    eHealth := E_DL_Ne107Status.eFailure;           // 故障：信号不可信（Failure, signal invalid）
ELSIF (NOT _bDataOk) AND bEnable THEN
    eHealth := E_DL_Ne107Status.eOutOfSpec;         // 越规：数据不满足出值条件（Out of spec, no trustworthy value）
ELSIF _bCleanLatched THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq;    // 需维护：热阻劣化但量值仍有效（Maintenance required, value still valid）
ELSIF (NOT _bInit) OR (NOT bEnable) THEN
    eHealth := E_DL_Ne107Status.eUnknown;           // 未知：尚未取得有效数据（Unknown, no valid data yet）
ELSE
    eHealth := E_DL_Ne107Status.eOk;                // 正常（OK）
END_IF

END_FUNCTION_BLOCK
