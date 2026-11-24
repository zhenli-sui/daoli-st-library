(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EscHeLeakCheck
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 静电吸盘氦背冷泄漏率判定
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / TON / ABS / MIN / MAX / LIMIT），零厂商方言
 * 接口依赖 (Depends)    : E_DL_Ne107Status —— 唯一属主为 DL_Device 子库的契约件
 *                         I_DL_DeviceHealth（R13 泳道 A1）。本文件只引用成员，不重定义枚举体。
 * 功能描述 (Function)   : 静电吸盘（ESC）氦背冷回路的三段式泄漏率判定 ——
 *                         升压段（斜率监视 + 达压确认）→ 稳压段（窗内极差稳定判据）→
 *                         测量段（压降率 → 漏率换算 + 温漂修正）→ 判定（OK / Warn / NG）。
 * 与 FB_DL_LeakTestStation 的分工（必须遵守，禁止合并）:
 *                         后者是**通用压降法工站**（充气-稳压-保压-压降换算-排气，面向工件
 *                         腔体，压力区间宽、带排气相与夹具确认）；本件是**ESC 专用**：氦侧
 *                         压力区间窄（1~100 kPa）、必须做温漂修正、判定带 Warn 三级、且要
 *                         单独识别「氦源串漏方向」（测量段压力上升 = 阀未关或源侧串漏）。
 *                         两者**不得合并**：合并会把两套压力量纲与判定门限塞进一个方式参数，
 *                         这正是历史库反复交学费的老毛病（一套 MODE 管两种物理过程）。
 * 边界     (Boundary)   : ① 不做抽真空/排气相（ESC 背冷不排气，氦侧常压回收）；② 不做
 *                         夹具确认（背冷腔由卡盘机械结构保证）；③ 不做腔体几何漏率模型，
 *                         压降率→漏率的换算系数为标定常量（见 DL_ESC_LEAK_K 注释）。
 * 分层声明 (Layer)      : 工艺层（DL_Process）。零全局变量表引用、零外部变量声明、零物理 IO。
 * 段序     (Segments)   : 段1 实例无条件刷新 → 段2 断输入拍自清与复位通道（CASE 前，R39）→
 *                         段3 输入防御与参数钳位 → 段4 启动沿受理（R24/R25）→ 段5 相位状态机 →
 *                         段6 判定结算 → 段7 码位单一优先级链 → 段8 出口钳位与保持重写。
 * 枚举映射表 (R31)      : 相位 E_DL_EscLeakPhase：eIdle(0)→标签 0｜ePressurize(10)→标签 10｜
 *                         eStabilize(20)→标签 20｜eMeasure(30)→标签 30｜eVerdict(40)→标签 40｜
 *                         eFault(99)→标签 99。结果 E_DL_LeakResult：eOk(0)｜eWarn(10)｜
 *                         eNg(20)｜eAborted(30)，不作为 CASE 选择子，仅作出口判定值。
 * 单拍标志清单 (R25)    : bStart —— 预清零点：段1 每拍被实例输出覆盖；置位点：段1
 *                         `_bStartReq := _fbTrigStart.Q AND (NOT _bStartConsumed)`；自清点：
 *                         段4 消费时置 `_bStartConsumed := TRUE`，bStart 回 FALSE 即解除。
 *                         bReset —— 预清零点：段1 覆盖 _bResetEdge；置位点：段1 实例调用；
 *                         自清点：紧随实例调用的 _bResetEdge 赋值行。
 * 保持位清单 (R27)      : bDone / bPass / eResult / fLeakRate / fPressDecay —— 逐拍由
 *                         _bDoneLatched / _bPassLatched / _eResultHeld / _fLeakHeld /
 *                         _fDecayHeld 重写并夹域；新启动沿与复位沿清除。
 * 定时器清单 (R40)      : 三段各一个 TON，**每段切换必须断输入一拍**（R40 核心）：
 *                         _fbTonPress ｜IN = (相位 = ePressurize) AND NOT _bPressBreak｜
 *                         断输入标志 _bPressBreak（进升压段置一拍，段2 自清）；
 *                         _fbTonStab   ｜IN = (相位 = eStabilize) AND NOT _bStabBreak｜
 *                         断输入标志 _bStabBreak（进稳压段置一拍，段2 自清）；
 *                         _fbTonStabExt｜IN = (相位 = eStabilize) AND _bStabExtended AND NOT _bStabExtBreak｜
 *                         断输入标志 _bStabExtBreak（延长一次时置一拍，段2 自清）；
 *                         _fbTonMeas   ｜IN = (相位 = eMeasure) AND NOT _bMeasBreak｜
 *                         断输入标志 _bMeasBreak（进测量段置一拍，段2 自清）。
 *                         四者绝不共用实例、绝不用 `IN := (相位 <> eIdle)` 这类跨段恒真写法。
 * 三元一致表 (R35)      : 达压容差守卫 0.01~50 kPa / 封顶 50 / 判据 `≤`｜
 *                         漏率 Warn 阈守卫 0~1E4 sccm / 封顶 1E4 / 判据 `>`（超 Warn 进 Warn 带）｜
 *                         漏率 NG 阈守卫 0~1E4 sccm 且强制 ≥ Warn / 判据 `>`（超 NG 判 NG）。
 * 镜像量清单 (R38)      : fHePressure 的唯一消费点是段3 的 _fPnow（每拍单次锁存），相位机
 *                         与结算全部读 _fPnow，绝不回读实时入参；fChuckTemp 同理锁存为 _fTnow。
 * 开源溯源 (Origin)     : 自研（T2-8 仅借「分级 → 维护建议」的语言形态，即 Warn/NG 两级
 *                         判定后给出维护动作，不涉及任何实现细节）。ESC 氦背冷检漏无可对应
 *                         的开源件（LBP 与 OSCAT 均无此工艺块，见 R13 溯源结论），压降率→
 *                         漏率换算与三段定时结构为本库独立设计。许可证说明：无代码借鉴对象，
 *                         本文件为本库原创，随本库许可证发布。
 * 验收向量 (Acceptance) :
 *   V1 15 kPa 达压、30 s 内压降 0.04 kPa → fPressDecay ≈ 0.00133 kPa/s、
 *      fLeakRate ≈ 2.0 sccm（× 换算系数 1500）→ eOk、bPass = TRUE（保持）。
 *   V2 压降 0.12 kPa/30 s → 漏率 6.0 sccm > NG 阈 5.0 → eNg、bPass = FALSE（保持）。
 *   V3（V-C 三段定时器，R40）升压 10 s + 稳压 10 s + 测量 30 s，三段各用一个 TON 且
 *      **每段切换断输入一拍**。若误写成三段共用一个 TON 且 IN 跨段恒真，则 50 s 时
 *      tMeasure = 30 s 会被提前判超时 —— 本向量用于区分这两种实现。
 *   V4（V-D 中止恢复，R41）eMeasure 中 bEnable 掉 → 回 eIdle、eResult = eAborted、
 *      bDone 保持；重新 bStart 后三段计时**从 0 开始**（断输入拍保证 ET 清零）。
 *   V5（V-A 非有限）fHePressure = NaN → 16#0005_02F8、fLeakRate 保持上次值（绝不写 NaN）。
 * 偏离留档 (Deviation)  :
 *   ① 输入非有限值与「非法状态兜底」共用 16#0005_02F8：规格故障表只给 3 个故障码，
 *      而其验收向量 V5 明确要求 NaN 走 02F8，故按向量口径执行，不新增码位。
 *   ② fPressRiseMax 的语义裁定：规格命名为「升压速率上限」。氦侧有机械减压阀，超压风险
 *      不成立，因此本件不把它当拦截阈值，而是当作**升压段的供气健康基准**：升压速率
 *      持续（≥1 s）低于其 2 % 且远未达压时判供气异常 02F6。「上限语义不拦截」这一裁定
 *      在头注释声明，避免后人误以为漏实现了超速拦截。
 *   ③ 漏率换算系数 DL_ESC_LEAK_K = 1500 sccm/(kPa/s) 为标定常量：由背冷腔容积与标定
 *      工装决定，规格未给容积引脚；调用方按腔体台账整定（值误差只影响绝对量程，
 *      不影响 OK/Warn/NG 的判定结构）。
 *   ④ 稳压延长仅一次（01C8 语义）；延长后仍不稳则**进入测量**但在判定时把 eOk 降为
 *      eWarn（不确定性上升），绝不因稳定判据未过而丢弃整次检测。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 C · DL_Process 第 24 件）
 *   2026-11-16  v1.0.1  终审修复：稳压延长窗原实现「_fbTonStab.Q OR _fbTonStabExt.Q」
 *                       联合裁决，延长置位后主稳压定时器 IN 未断、Q 保持 TRUE，下一拍
 *                       即被提前判「延长后仍不稳」进测量，_fbTonStabExt 从未计时；改为以
 *                       _bStabExtended 区分两窗，延长窗仅由 _fbTonStabExt.Q 裁决（D-C4-1）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EscLeakPhase（归属 FB_DL_EscHeLeakCheck，同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_EscLeakPhase :
(
    eIdle       := 0,   // 空闲：等启动沿 / Idle, awaiting the start edge
    ePressurize := 10,  // 升压：等达压或超时 / Pressurise, awaiting the target or a timeout
    eStabilize  := 20,  // 稳压：等窗内极差收敛 / Stabilise, awaiting a settled pressure range
    eMeasure    := 30,  // 测量：隔离测压降 / Measure, isolated pressure-decay window
    eVerdict    := 40,  // 判定：结算一次后回空闲 / Verdict, settles once then returns to idle
    eFault      := 99   // 故障：锁存等复位 / Fault latched until reset
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LeakResult（归属 FB_DL_EscHeLeakCheck，同文件发布）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LeakResult :
(
    eOk      := 0,      // 合格：漏率低于 Warn 阈 / OK, leak rate below the warn limit
    eWarn    := 10,     // 警告：落在 Warn 带或稳定判据欠佳 / Warn, inside the warn band or weakly settled
    eNg      := 20,     // 不合格：漏率超 NG 阈 / Reject, leak rate above the reject limit
    eAborted := 30      // 中止：无结论（掉使能或复位）/ Aborted, no conclusion
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_EscHeLeakCheck
VAR_INPUT
    bEnable        : BOOL;                  // 使能（Enable），FALSE = 中止当前检测并回空闲；复位通道不受其屏蔽 / Enable, FALSE aborts the check
    bReset         : BOOL;                  // 复位（Reset），上升沿清故障、结果与保持量 / Rising edge clears fault, result and held values
    bStart         : BOOL;                  // 启动一次检测（One-shot start），上升沿受理（R24）/ One-shot start, rising edge only
    fHePressure    : REAL;                  // 氦侧压力（Helium pressure）[kPa]，域 0~500 / Helium pressure [kPa], 0 to 500
    fHeFlow        : REAL;                  // 氦侧流量（Helium flow）[sccm]，域 0~5000，用于与漏率交叉校验 / Helium flow [sccm], used for the cross check
    fChuckTemp     : REAL;                  // 卡盘温度（Chuck temperature）[℃]，域 0~200，温漂修正用 / Chuck temperature [degC], used for the drift correction
    tPressurizeMax : TIME := T#20S;         // 升压段超时（Pressurise timeout），默认 20 s / Pressurise timeout, default 20 s
    tStabilize     : TIME := T#10S;         // 稳压段时长（Stabilisation time），默认 10 s / Stabilisation time, default 10 s
    tMeasure       : TIME := T#30S;         // 测量段时长（Measurement time），默认 30 s / Measurement time, default 30 s
    fPressTarget   : REAL := 15.0;          // 目标背压（Target back pressure）[kPa]，域 1~100 / Target back pressure [kPa]
    fPressTol      : REAL := 0.5;           // 达压容差（Pressure tolerance）[kPa]，域 0.01~50 / Pressure tolerance [kPa]
    fLeakWarn      : REAL := 3.0;           // 漏率 Warn 阈（Leak-rate warn limit）[sccm]，域 0~1E4 / Leak-rate warn limit [sccm]
    fLeakNg        : REAL := 5.0;           // 漏率 NG 阈（Leak-rate reject limit）[sccm]，域 0~1E4 且 ≥ Warn / Leak-rate reject limit [sccm]
    fPressRiseMax  : REAL := 2.0;           // 升压速率基准（Pressurise rate reference）[kPa/s]，域 0.01~100，偏离留档② / Pressurise rate reference [kPa/s]
    fTempCoeff     : REAL := 0.003;         // 压力温漂修正系数（Pressure temperature coefficient）[1/K]，域 −0.05~0.05 / Pressure temperature coefficient [1/K]
    fStabTol       : REAL := 0.2;           // 稳压判据：窗内极差上限（Stabilisation tolerance）[kPa]，域 0.001~50 / Stabilisation tolerance [kPa]
END_VAR

VAR_OUTPUT
    fLeakRate      : REAL;                  // 换算漏率（Corrected leak rate）[sccm]，温漂修正后，夹进 ≥0 / Corrected leak rate [sccm], clamped non-negative
    fPressDecay    : REAL;                  // 测量段压降率（Pressure decay rate）[kPa/s]，有符号，夹域 / Pressure decay rate [kPa/s], signed and clamped
    eResult        : E_DL_LeakResult;       // 判定结果（Result），保持语义（R27）/ Result, held until the next start
    bDone          : BOOL;                  // 检测完成（Done），保持语义（R27）/ Done, held
    bPass          : BOOL;                  // 合格（Pass），保持语义（R27）/ Pass, held
    nTestCount     : UDINT;                 // 检测次数（Test counter）[次] / Test counter [count]
    nNgCount       : UDINT;                 // 不合格次数（Reject counter）[次] / Reject counter [count]
    eHealth        : E_DL_Ne107Status;      // 健康态（NE107 health），引用属主 A1 的枚举 / NE107 health, owned by A1
    uDiagCode      : UDINT;                 // 诊断码（Diagnostic code），本拍单一优先级链输出 / Diagnostic code, single priority chain
    uErrorId       : UDINT;                 // 故障码（Error code），仅故障级码，0 = 无故障 / Fault-level code, 0 = no fault
    bError         : BOOL;                  // 故障标志（Error），仅故障级码置位（NG 属工件不良，不置位）/ TRUE only for fault-level codes
END_VAR

VAR
    _ePhase        : E_DL_EscLeakPhase := E_DL_EscLeakPhase.eIdle;  // 内部相位（Internal phase）/ Internal phase value
    _bStartReq     : BOOL;                  // 启动单拍请求（Start one-shot request）/ Start one-shot request
    _bStartConsumed : BOOL;                 // 启动已消费（Start consumed flag）/ Start consumed flag
    _bResetEdge    : BOOL;                  // 复位沿单拍标志（Reset one-shot flag）/ Reset one-shot flag
    _bPressBreak   : BOOL;                  // 升压段断输入拍（Pressurise break）/ Pressurise segment break
    _bStabBreak    : BOOL;                  // 稳压段断输入拍（Stabilise break）/ Stabilise segment break
    _bStabExtBreak : BOOL;                  // 稳压延长段断输入拍（Stabilise extension break）/ Stabilise extension break
    _bMeasBreak    : BOOL;                  // 测量段断输入拍（Measure break）/ Measure segment break
    _uFaultCode    : UDINT;                 // 本拍故障级码（Fault-level code this scan）/ Fault-level code of this scan
    _uFaultLatched : UDINT;                 // 故障码锁存（Latched fault code），仅复位清除 / Latched fault code, reset only
    _uInfoCode     : UDINT;                 // 本拍信息级码（Info-level code this scan）/ Info-level code of this scan
    _bFaultCond    : BOOL;                  // 故障条件（Fault condition）/ Fault condition flag
    _fPnow         : REAL;                  // 压力快照（Pressure snapshot）[kPa]，唯一消费点的入口（R38）/ Pressure snapshot [kPa]
    _fTnow         : REAL;                  // 温度快照（Temperature snapshot）[℃]，唯一消费点的入口（R38）/ Temperature snapshot [degC]
    _fFlowNow      : REAL;                  // 流量快照（Flow snapshot）[sccm]，交叉校验用 / Flow snapshot [sccm]
    _fTargetEff    : REAL;                  // 生效目标压力（Effective target pressure）[kPa] / Effective target pressure [kPa]
    _fTolEff       : REAL;                  // 生效达压容差（Effective tolerance）[kPa] / Effective pressure tolerance [kPa]
    _fWarnEff      : REAL;                  // 生效 Warn 阈（Effective warn limit）[sccm] / Effective warn limit [sccm]
    _fNgEff        : REAL;                  // 生效 NG 阈（Effective reject limit）[sccm] / Effective reject limit [sccm]
    _fRiseRefEff   : REAL;                  // 生效升压速率基准（Effective rate reference）[kPa/s] / Effective rate reference [kPa/s]
    _fCoeffEff     : REAL;                  // 生效温漂系数（Effective temperature coefficient）[1/K] / Effective coefficient [1/K]
    _fStabTolEff   : REAL;                  // 生效稳压容差（Effective stabilisation tolerance）[kPa] / Effective tolerance [kPa]
    _fP0           : REAL;                  // 升压起点压力（Pressure at pressurise start）[kPa] / Pressure at pressurise start [kPa]
    _fPm           : REAL;                  // 测量起点压力（Pressure at measure start）[kPa] / Pressure at measure start [kPa]
    _fTm           : REAL;                  // 测量起点温度（Temperature at measure start）[℃] / Temperature at measure start [degC]
    _fStabMin      : REAL;                  // 稳压段压力极小（Stabilise minimum pressure）[kPa] / Stabilise minimum [kPa]
    _fStabMax      : REAL;                  // 稳压段压力极大（Stabilise maximum pressure）[kPa] / Stabilise maximum [kPa]
    _fStabRange    : REAL;                  // 稳压段极差（Stabilise range）[kPa] / Stabilise range [kPa]
    _bStabExtended : BOOL;                  // 稳压已延长（Stabilisation extended once）/ Stabilisation extended once
    _bStabWeak     : BOOL;                  // 稳定判据欠佳（Weakly settled）/ Weakly settled flag
    _fRiseRate     : REAL;                  // 升压速率（Pressurise rate）[kPa/s] / Pressurise rate [kPa/s]
    _fEtSec        : REAL;                  // 定时器已历秒值（Elapsed seconds）[s] / Elapsed seconds
    _fDecay        : REAL;                  // 压降量（Pressure drop）[kPa]，有符号 / Pressure drop [kPa], signed
    _fDecayCorr    : REAL;                  // 温漂修正后压降（Drift-corrected drop）[kPa] / Drift-corrected pressure drop [kPa]
    _fDecayRate    : REAL;                  // 压降率（Decay rate）[kPa/s] / Decay rate [kPa/s]
    _fMeasSec      : REAL;                  // 测量段实际秒值（Measured seconds）[s] / Measured seconds [s]
    _fLeakCalc     : REAL;                  // 本拍漏率（Computed leak rate）[sccm] / Computed leak rate [sccm]
    _fDtKelvin     : REAL;                  // 测量段温差（Temperature change）[K] / Temperature change during measure [K]
    _eResultCalc   : E_DL_LeakResult;       // 本拍结果（Computed result）/ Computed result
    _bDoneLatched  : BOOL;                  // 完成锁存（Done latch）/ Done latch
    _bPassLatched  : BOOL;                  // 合格锁存（Pass latch）/ Pass latch
    _eResultHeld   : E_DL_LeakResult := E_DL_LeakResult.eAborted;   // 保持的结果（Held result）/ Held result
    _fLeakHeld     : REAL;                  // 保持的漏率（Held leak rate）[sccm] / Held leak rate [sccm]
    _fDecayHeld    : REAL;                  // 保持的压降率（Held decay rate）[kPa/s] / Held decay rate [kPa/s]
    _nTestInt      : UDINT;                 // 内部检测计数（Internal test counter）[次] / Internal test counter [count]
    _nNgInt        : UDINT;                 // 内部不合格计数（Internal reject counter）[次] / Internal reject counter [count]
    _fbTrigStart   : R_TRIG;                // 启动上升沿（Start rising edge）/ Start rising edge
    _fbTrigReset   : R_TRIG;                // 复位上升沿（Reset rising edge）/ Reset rising edge
    _fbTonPress    : TON;                   // 升压段定时（Pressurise timer）/ Pressurise timer
    _fbTonStab     : TON;                   // 稳压段定时（Stabilise timer）/ Stabilise timer
    _fbTonStabExt  : TON;                   // 稳压延长定时（Stabilise extension timer）/ Stabilise extension timer
    _fbTonMeas     : TON;                   // 测量段定时（Measure timer）/ Measure timer
END_VAR

VAR CONSTANT
    DL_ESC_REAL_MAX   : REAL := 3.4E38;      // 单精度有限值判据幅值（Finite magnitude bound）/ Finite bound for REAL inputs
    DL_ESC_EPS        : REAL := 1.0E-6;      // 浮点防零容差（Divide-guard epsilon）/ Float divide-guard epsilon
    DL_ESC_PRESS_MAX  : REAL := 500.0;       // 压力输入域上限（Pressure input bound）[kPa] / Pressure input bound [kPa]
    DL_ESC_FLOW_MAX   : REAL := 5000.0;      // 流量输入域上限（Flow input bound）[sccm] / Flow input bound [sccm]
    DL_ESC_TEMP_MAX   : REAL := 200.0;       // 温度输入域上限（Temperature input bound）[℃] / Temperature input bound [degC]
    DL_ESC_TGT_MIN    : REAL := 1.0;         // 目标压力域下限（Target lower clamp）[kPa] / Target lower clamp [kPa]
    DL_ESC_TGT_MAX    : REAL := 100.0;       // 目标压力域上限（Target upper clamp）[kPa] / Target upper clamp [kPa]
    DL_ESC_TOL_MIN    : REAL := 0.01;        // 达压容差域下限（Tolerance lower clamp）[kPa] / Tolerance lower clamp [kPa]
    DL_ESC_TOL_MAX    : REAL := 50.0;        // 达压容差域上限（Tolerance upper clamp）[kPa] / Tolerance upper clamp [kPa]
    DL_ESC_LEAK_MAX   : REAL := 1.0E4;       // 漏率域上限（Leak limit ceiling）[sccm] / Leak limit ceiling [sccm]
    DL_ESC_RISE_MIN   : REAL := 0.01;        // 升压速率基准下限（Rate reference lower clamp）[kPa/s] / Rate reference lower clamp [kPa/s]
    DL_ESC_RISE_MAX   : REAL := 100.0;       // 升压速率基准上限（Rate reference upper clamp）[kPa/s] / Rate reference upper clamp [kPa/s]
    DL_ESC_COEF_MIN   : REAL := -0.05;       // 温漂系数域下限（Coefficient lower clamp）[1/K] / Coefficient lower clamp [1/K]
    DL_ESC_COEF_MAX   : REAL := 0.05;        // 温漂系数域上限（Coefficient upper clamp）[1/K] / Coefficient upper clamp [1/K]
    DL_ESC_STAB_MIN   : REAL := 0.001;       // 稳压容差域下限（Stabilisation tolerance lower clamp）[kPa] / Tolerance lower clamp [kPa]
    DL_ESC_STAB_MAX   : REAL := 50.0;        // 稳压容差域上限（Stabilisation tolerance upper clamp）[kPa] / Tolerance upper clamp [kPa]
    DL_ESC_RISE_LOWR  : REAL := 0.02;        // 供气异常判据：基准速率的 2 %（Suppy-fault ratio）[-] / Supply-fault ratio
    DL_ESC_RISE_WAIT  : REAL := 1.0;         // 升压速率判据等待秒值（Rate-test wait）[s] / Rate-test wait [s]
    DL_ESC_DTK_MIN    : REAL := 1.0;         // 温漂修正启用温差（Correction-enable temperature change）[K] / Correction-enable delta-T [K]
    DL_ESC_MS_SCALE   : REAL := 1000.0;      // 毫秒→秒换算（Milliseconds-to-seconds scale）[-] / Milliseconds-to-seconds scale
    DL_ESC_LEAK_K     : REAL := 1500.0;      // 压降率→漏率标定系数（Decay-to-leak calibration）[sccm/(kPa/s)]，偏离留档③ / Calibration constant
    DL_ESC_SCCM_MAX   : REAL := 1.0E5;       // 漏率出口上限（Leak output ceiling）[sccm] / Leak output ceiling [sccm]
    DL_ESC_DECAY_MAX  : REAL := 1.0E3;       // 压降率出口夹域（Decay output clamp）[kPa/s] / Decay output clamp [kPa/s]
    DL_ESC_ERR_PRESS  : UDINT := 16#0005_02F6; // 0005_02F6 升压超时或供气异常【故障级】/ Pressurisation failed, fault level
    DL_ESC_ERR_RISE   : UDINT := 16#0005_02F7; // 0005_02F7 测量段压力上升（源侧串漏或阀未关）【故障级】/ Pressure rising in the measure phase
    DL_ESC_ERR_STATE  : UDINT := 16#0005_02F8; // 0005_02F8 非有限输入或非法状态兜底【故障级】/ Non-finite input or illegal state fallback
    DL_ESC_INFO_EXT   : UDINT := 16#0005_01C8; // 0005_01C8 稳压未达判据已延长一次【信息级】/ Stabilisation extended once, info level
    DL_ESC_INFO_TCORR : UDINT := 16#0005_01C9; // 0005_01C9 温漂修正已启用【信息级】/ Temperature correction active, info level
    DL_ESC_INFO_WARN  : UDINT := 16#0005_01CA; // 0005_01CA 漏率落在 Warn 带【信息级】/ Leak rate inside the warn band, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of every instance (R7/0.5)
// ============================================================================
_fbTrigStart(CLK := bStart);                    // 启动上升沿（Start rising edge）
_bStartReq := _fbTrigStart.Q AND (NOT _bStartConsumed);   // 单拍启动请求（R25 置位点）
_fbTrigReset(CLK := bReset);                    // 复位上升沿（Reset rising edge）
_bResetEdge := _fbTrigReset.Q;                  // 复位单拍标志紧随实例赋值（R25 自清点）

// 三段各一个 TON，IN 串「段断输入标志」（R40 合规指纹：绝不跨段恒真）
// One timer per segment with the segment break folded into IN (R40)
_fbTonPress(
    IN := (_ePhase = E_DL_EscLeakPhase.ePressurize) AND (NOT _bPressBreak),
    PT := tPressurizeMax
);                                              // 升压段超时（Pressurise timeout）
_fbTonStab(
    IN := (_ePhase = E_DL_EscLeakPhase.eStabilize) AND (NOT _bStabBreak),
    PT := tStabilize
);                                              // 稳压段时长（Stabilise duration）
_fbTonStabExt(
    IN := (_ePhase = E_DL_EscLeakPhase.eStabilize) AND _bStabExtended AND (NOT _bStabExtBreak),
    PT := tStabilize
);                                              // 稳压延长段时长（Stabilise extension duration）
_fbTonMeas(
    IN := (_ePhase = E_DL_EscLeakPhase.eMeasure) AND (NOT _bMeasBreak),
    PT := tMeasure
);                                              // 测量段时长（Measure duration）

// 本拍码与条件预置（每拍重算；故障码以上拍锁存续用）
// Per-scan preset of codes and conditions, the fault code is carried from the latch
_uFaultCode := _uFaultLatched;                  // 故障码续用（Carry the latched fault code）
_uInfoCode  := 16#0000_0000;                    // 信息级码预清零（Info code preset to zero）
_bFaultCond := FALSE;                           // 故障条件预清零（Fault condition preset FALSE）

// 启动消费标志解除：输入回落即允许下一周期（R25 生命周期闭环）
// Release the start consumption flag once the input falls
IF NOT bStart THEN
    _bStartConsumed := FALSE;                   // 允许下一次上升沿（Next rising edge accepted）
END_IF

// ============================================================================
// 段 2｜断输入拍自清 + 复位通道（R40 自清 / R39 前置）
//      Segment break self-clear and the reset path, both before CASE
// ============================================================================
IF _bPressBreak THEN
    _bPressBreak := FALSE;                      // 升压段断输入拍自清（Pressurise break self-cleared）
END_IF
IF _bStabBreak THEN
    _bStabBreak := FALSE;                       // 稳压段断输入拍自清（Stabilise break self-cleared）
END_IF
IF _bStabExtBreak THEN
    _bStabExtBreak := FALSE;                    // 稳压延长断输入拍自清（Extension break self-cleared）
END_IF
IF _bMeasBreak THEN
    _bMeasBreak := FALSE;                       // 测量段断输入拍自清（Measure break self-cleared）
END_IF

IF _bResetEdge THEN
    _bDoneLatched  := FALSE;                    // 完成锁存清除（Done latch cleared）
    _bPassLatched  := FALSE;                    // 合格锁存清除（Pass latch cleared）
    _eResultHeld   := E_DL_LeakResult.eAborted; // 结果回「无结论」（Result back to the no-conclusion value）
    _fLeakHeld     := 0.0;                      // 漏率保持值清零（Held leak rate cleared）
    _fDecayHeld    := 0.0;                      // 压降率保持值清零（Held decay rate cleared）
    _bStabExtended := FALSE;                    // 延长标志清除（Extension flag cleared）
    _bStabWeak     := FALSE;                    // 弱稳定标志清除（Weak settle flag cleared）
    _nTestInt      := UDINT#0;                  // 检测计数清零（Test counter cleared）
    _nNgInt        := UDINT#0;                  // 不合格计数清零（Reject counter cleared）
    _uFaultLatched := 16#0000_0000;             // 故障码锁存清除（Latched fault code cleared）
    _uFaultCode    := 16#0000_0000;             // 本拍故障码清空，防止段7 重新锁存旧码（Clear this scan code）
    IF _ePhase = E_DL_EscLeakPhase.eFault THEN
        _ePhase := E_DL_EscLeakPhase.eIdle;     // 故障态回空闲（Fault phase back to idle）
        _bFaultCond := FALSE;                   // 故障条件清除（Fault condition cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜输入防御与参数钳位（先判可用再算值；镜像量每拍只锁一次，R38）
//      Input defense and parameter clamping, each mirror value latched once (R38)
// ============================================================================
IF (NOT (fHePressure >= (-DL_ESC_REAL_MAX) AND fHePressure <= DL_ESC_PRESS_MAX))
OR (NOT (fHeFlow >= (-DL_ESC_REAL_MAX) AND fHeFlow <= DL_ESC_FLOW_MAX))
OR (NOT (fChuckTemp >= (-DL_ESC_REAL_MAX) AND fChuckTemp <= DL_ESC_TEMP_MAX)) THEN
    _bFaultCond := TRUE;                        // 非有限或越域即故障（Non-finite or out-of-domain is a fault）
    _uFaultCode := DL_ESC_ERR_STATE;            // 0005_02F8 非有限输入【故障级】/ Non-finite input, fault level
    _fPnow   := 0.0;                            // 压力快照置零，绝不用脏值（Pressure snapshot zeroed）
    _fTnow   := 0.0;                            // 温度快照置零（Temperature snapshot zeroed）
    _fFlowNow := 0.0;                           // 流量快照置零（Flow snapshot zeroed）
ELSE
    _fPnow   := fHePressure;                    // 压力快照锁定（Pressure snapshot latched）
    _fTnow   := fChuckTemp;                     // 温度快照锁定（Temperature snapshot latched）
    _fFlowNow := fHeFlow;                       // 流量快照锁定（Flow snapshot latched）
END_IF

// 参数域钳位（R35：守卫、封顶与判据同向）
// Parameter clamping so that guard, ceiling and comparison stay in step (R35)
_fTargetEff  := LIMIT(DL_ESC_TGT_MIN, fPressTarget, DL_ESC_TGT_MAX);     // 目标压力 1~100 kPa（Target clamped）
_fTolEff     := LIMIT(DL_ESC_TOL_MIN, fPressTol, DL_ESC_TOL_MAX);        // 达压容差 0.01~50 kPa（Tolerance clamped）
_fWarnEff    := LIMIT(0.0, fLeakWarn, DL_ESC_LEAK_MAX);                  // Warn 阈 0~1E4（Warn limit clamped）
_fNgEff      := LIMIT(0.0, fLeakNg, DL_ESC_LEAK_MAX);                    // NG 阈 0~1E4（Reject limit clamped）
IF _fNgEff < _fWarnEff THEN
    _fNgEff := _fWarnEff;                       // NG 阈不得低于 Warn 阈（Reject limit never below the warn limit）
END_IF
_fRiseRefEff := LIMIT(DL_ESC_RISE_MIN, fPressRiseMax, DL_ESC_RISE_MAX);  // 升压速率基准 0.01~100（Rate reference clamped）
_fCoeffEff   := LIMIT(DL_ESC_COEF_MIN, fTempCoeff, DL_ESC_COEF_MAX);     // 温漂系数 ±0.05（Coefficient clamped）
_fStabTolEff := LIMIT(DL_ESC_STAB_MIN, fStabTol, DL_ESC_STAB_MAX);       // 稳压容差 0.001~50（Stabilise tolerance clamped）

// ============================================================================
// 段 4｜启动沿受理（R24/R25：单拍消费，消费拍与转出拍分离）
//      Start edge acceptance, single-scan consumption (R24/R25)
// ============================================================================
IF _bStartReq AND (NOT _bStartConsumed) AND bEnable AND (NOT _bFaultCond)
AND ((_ePhase = E_DL_EscLeakPhase.eIdle) OR (_ePhase = E_DL_EscLeakPhase.eVerdict)) THEN
    _bStartConsumed := TRUE;                    // 消费启动沿（Start edge consumed）
    _bDoneLatched   := FALSE;                   // 上一次完成标志清除（Previous done cleared）
    _bPassLatched   := FALSE;                   // 上一次合格标志清除（Previous pass cleared）
    _bStabExtended  := FALSE;                   // 延长标志清零（Extension flag cleared）
    _bStabWeak      := FALSE;                   // 弱稳定标志清零（Weak settle cleared）
    _fP0            := _fPnow;                  // 升压起点压力（Pressurise start pressure）
    _fStabMin       := _fPnow;                  // 稳压极值初值（Stabilise extremes seeded）
    _fStabMax       := _fPnow;                  // 稳压极大初值（Stabilise maximum seeded）
    _uInfoCode      := 16#0000_0000;            // 新一次检测起点清信息码（R44：清码点绑定新周期）
    _ePhase         := E_DL_EscLeakPhase.ePressurize;   // 进升压段（Enter pressurise）
    _bPressBreak    := TRUE;                    // 断输入一拍，三段计时都从 0 起（R40/R41）
END_IF

// ============================================================================
// 段 5｜相位状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Phase state machine with an explicit ELSE fallback
// ============================================================================
IF _bFaultCond THEN
    _ePhase := E_DL_EscLeakPhase.eFault;        // 故障条件优先于状态机（Fault outranks the machine）
END_IF

// 掉使能冻结分支：显式排除故障态（R39 合法写法①），复位通道仍可从故障态退出
// Disable branch explicitly excludes the fault state so the reset path still works
IF (NOT bEnable) AND (_ePhase <> E_DL_EscLeakPhase.eFault) THEN
    IF (_ePhase = E_DL_EscLeakPhase.ePressurize) OR (_ePhase = E_DL_EscLeakPhase.eStabilize)
    OR (_ePhase = E_DL_EscLeakPhase.eMeasure) THEN
        _eResultHeld := E_DL_LeakResult.eAborted;   // 中止：无结论（Aborted, no conclusion）
        _bDoneLatched := TRUE;                  // 完成标志保持（Done held, per V4）
        _bPassLatched := FALSE;                 // 合格标志强制假（Pass forced FALSE）
    END_IF
    _ePhase := E_DL_EscLeakPhase.eIdle;         // 回空闲（Back to idle）
END_IF

CASE _ePhase OF

    E_DL_EscLeakPhase.eIdle: // 空闲：启动受理已在段4 完成
        // 启动动作在 CASE 之前完成（R39 前置纪律），此处保留空标签与原因注释（R31）
        // Start acceptance happens before CASE, so this label stays empty (R31)

    E_DL_EscLeakPhase.ePressurize: // 升压：等达压 / 供气异常 / 超时
        _fEtSec := TIME_TO_REAL(_fbTonPress.ET) / DL_ESC_MS_SCALE;   // 已历秒值（Elapsed seconds）
        IF ABS(_fPnow - _fTargetEff) <= _fTolEff THEN
            _ePhase      := E_DL_EscLeakPhase.eStabilize;   // 达压进稳压（Target reached, stabilise）
            _fStabMin    := _fPnow;             // 稳压极值重装（Extremes reloaded）
            _fStabMax    := _fPnow;             // 稳压极大重装（Maximum reloaded）
            _bStabBreak  := TRUE;               // 稳压定时断输入一拍（R40）
        ELSIF _fEtSec > DL_ESC_EPS THEN
            _fRiseRate := (_fPnow - _fP0) / _fEtSec;            // 升压速率（Pressurise rate）
            IF (_fRiseRate < (_fRiseRefEff * DL_ESC_RISE_LOWR))
            AND (_fEtSec > DL_ESC_RISE_WAIT) THEN
                _bFaultCond := TRUE;            // 供气异常：速率长期低于基准 2 %（Supply fault）
                _uFaultCode := DL_ESC_ERR_PRESS;    // 0005_02F6 供气异常【故障级】/ Supply fault, fault level
                _ePhase     := E_DL_EscLeakPhase.eFault;
            END_IF
        END_IF
        IF _fbTonPress.Q AND (_ePhase = E_DL_EscLeakPhase.ePressurize) THEN
            _bFaultCond := TRUE;                // 升压超时（Pressurise timeout）
            _uFaultCode := DL_ESC_ERR_PRESS;    // 0005_02F6 升压超时【故障级】/ Pressurise timeout, fault level
            _ePhase     := E_DL_EscLeakPhase.eFault;
        END_IF

    E_DL_EscLeakPhase.eStabilize: // 稳压：跟踪极差，到时判稳定
        IF _fPnow < _fStabMin THEN
            _fStabMin := _fPnow;                // 稳压极小（Stabilise minimum）
        END_IF
        IF _fPnow > _fStabMax THEN
            _fStabMax := _fPnow;                // 稳压极大（Stabilise maximum）
        END_IF
        _fStabRange := _fStabMax - _fStabMin;   // 稳压极差（Stabilise range）
        IF _bStabExtended THEN
            // 延长窗：只由延长定时器到点裁决；主稳压定时器的 Q 在延长窗内保持 TRUE，
            // 绝不能再参与裁决（否则延长置位次拍即被提前判不稳，v1.0.1 修复 D-C4-1）
            //     Extension window: arbitrated only by the extension timer (v1.0.1 fix)
            IF _fbTonStabExt.Q THEN
                IF _fStabRange <= _fStabTolEff THEN
                    _ePhase   := E_DL_EscLeakPhase.eMeasure;    // 延长后收敛：正常进测量（Settled after extension）
                    _bStabWeak := FALSE;            // 已收敛不留弱稳定标记（Settled, weak flag cleared）
                    _fPm      := _fPnow;            // 测量起点压力（Measure start pressure）
                    _fTm      := _fTnow;            // 测量起点温度（Measure start temperature）
                    _bMeasBreak := TRUE;            // 测量定时断输入一拍（R40）
                ELSE
                    _ePhase    := E_DL_EscLeakPhase.eMeasure;   // 延长后仍不稳：进测量但降级判（Deviation 4）
                    _bStabWeak := TRUE;             // 弱稳定标记（Weak settle flagged）
                    _fPm       := _fPnow;           // 测量起点压力（Measure start pressure）
                    _fTm       := _fTnow;           // 测量起点温度（Measure start temperature）
                    _bMeasBreak := TRUE;            // 测量定时断输入一拍（R40）
                END_IF
            END_IF
        ELSIF _fbTonStab.Q THEN
            IF _fStabRange <= _fStabTolEff THEN
                _ePhase   := E_DL_EscLeakPhase.eMeasure;    // 稳定判据通过进测量（Settled, measure）
                _fPm      := _fPnow;            // 测量起点压力（Measure start pressure）
                _fTm      := _fTnow;            // 测量起点温度（Measure start temperature）
                _bMeasBreak := TRUE;            // 测量定时断输入一拍（R40）
            ELSE
                _bStabExtended  := TRUE;        // 仅延长一次（Extend exactly once）
                _bStabExtBreak  := TRUE;        // 延长段定时断输入一拍（R40）
                _uInfoCode      := DL_ESC_INFO_EXT; // 0005_01C8 稳压未达判据已延长一次【信息级】/ Stabilisation extended
            END_IF
        END_IF

    E_DL_EscLeakPhase.eMeasure: // 测量：隔离窗到期结算压降与漏率
        IF _fbTonMeas.Q THEN
            _fMeasSec := TIME_TO_REAL(_fbTonMeas.ET) / DL_ESC_MS_SCALE;     // 实际测量秒值（Measured seconds）
            _fDecay   := _fPm - _fPnow;         // 压降量，有符号（Pressure drop, signed）
            IF _fDecay < 0.0 THEN
                _bFaultCond := TRUE;            // 压力上升：方向反（Pressure rising, direction reversed）
                _uFaultCode := DL_ESC_ERR_RISE; // 0005_02F7 氦源串漏或阀未关【故障级】/ Rising pressure, fault level
                _ePhase     := E_DL_EscLeakPhase.eFault;
            ELSIF _fMeasSec > DL_ESC_EPS THEN
                // 温漂修正：ΔP_corr = ΔP − P·α·ΔT（一阶线性近似，对外声明适用域）
                //     Drift correction: first-order linear approximation
                _fDtKelvin := _fTnow - _fTm;    // 测量段温差（Temperature change）
                IF (ABS(_fCoeffEff) > DL_ESC_EPS) AND (ABS(_fDtKelvin) > DL_ESC_DTK_MIN) THEN
                    _fDecayCorr := _fDecay - (_fPm * _fCoeffEff * _fDtKelvin);  // 修正后压降（Corrected drop）
                    _uInfoCode  := DL_ESC_INFO_TCORR;   // 0005_01C9 温漂修正已启用【信息级】/ Correction active
                ELSE
                    _fDecayCorr := _fDecay;     // 未启用修正（Correction not applied）
                END_IF
                IF _fDecayCorr < 0.0 THEN
                    _fDecayCorr := 0.0;         // 修正后回负按 0（Corrected drop floored to zero）
                END_IF
                _fDecayRate  := _fDecayCorr / _fMeasSec;                // 压降率（Decay rate）
                _fLeakCalc   := _fDecayRate * DL_ESC_LEAK_K;            // 漏率换算（Leak rate conversion）
                _fLeakHeld   := LIMIT(0.0, _fLeakCalc, DL_ESC_SCCM_MAX);    // 漏率夹进非负（Leak clamped）
                _fDecayHeld  := LIMIT(-DL_ESC_DECAY_MAX, _fDecayRate, DL_ESC_DECAY_MAX); // 压降率夹域（Decay clamped）

                // 三级判定：Warn 带 / NG / OK，并做流量交叉校验
                //     Three-level verdict plus the flow cross check
                IF _fLeakHeld > _fNgEff THEN
                    _eResultCalc := E_DL_LeakResult.eNg;            // 超 NG 阈（Above the reject limit）
                ELSIF _fLeakHeld > _fWarnEff THEN
                    _eResultCalc := E_DL_LeakResult.eWarn;          // 落在 Warn 带（Inside the warn band）
                    _uInfoCode   := DL_ESC_INFO_WARN;               // 0005_01CA 漏率落在 Warn 带【信息级】/ Inside the warn band
                ELSE
                    _eResultCalc := E_DL_LeakResult.eOk;            // 合格（OK）
                END_IF
                IF (_fFlowNow > _fNgEff) AND (_fLeakHeld <= _fWarnEff) THEN
                    _eResultCalc := E_DL_LeakResult.eWarn;          // 流量与换算值矛盾：至少 Warn（Corroboration mismatch）
                    _uInfoCode   := DL_ESC_INFO_WARN;               // 0005_01CA 交叉校验不一致【信息级】/ Cross check mismatch
                END_IF
                IF _bStabWeak AND (_eResultCalc = E_DL_LeakResult.eOk) THEN
                    _eResultCalc := E_DL_LeakResult.eWarn;          // 稳定判据欠佳：OK 降为 Warn（Weak settle degrades OK）
                    _uInfoCode   := DL_ESC_INFO_WARN;               // 0005_01CA 稳定判据欠佳【信息级】/ Weak settle, info level
                END_IF

                _eResultHeld  := _eResultCalc;                      // 结果锁存（Result latched）
                _bPassLatched := (_eResultCalc = E_DL_LeakResult.eOk);  // 合格锁存（Pass latched）
                _bDoneLatched := TRUE;                              // 完成锁存（Done latched）
                _nTestInt     := _nTestInt + UDINT#1;               // 检测计数 +1（Test counted）
                IF _eResultCalc = E_DL_LeakResult.eNg THEN
                    _nNgInt := _nNgInt + UDINT#1;                   // 不合格计数 +1（Reject counted）
                END_IF
                _ePhase := E_DL_EscLeakPhase.eVerdict;              // 进判定相（Enter the verdict phase）
            END_IF
        END_IF

    E_DL_EscLeakPhase.eVerdict: // 判定：结论已在测量段结算，本相只做回空闲
        _ePhase := E_DL_EscLeakPhase.eIdle;     // 结算完成回空闲（Settled, back to idle）
        _bDoneLatched := TRUE;                  // 完成标志逐拍保持（Done held, R27）

    E_DL_EscLeakPhase.eFault: // 故障：等复位沿（段2）
        // 复位通道位于 CASE 之前，此分支无需动作（R39）
        // The reset path sits before CASE, so no action is needed here (R39)

    ELSE // 兜底：非法状态
        _uFaultCode := DL_ESC_ERR_STATE;        // 0005_02F8 非法状态兜底【故障级】/ Illegal state fallback
        _bFaultCond := TRUE;                    // 置故障条件（Raise the fault condition）
        _ePhase     := E_DL_EscLeakPhase.eFault;    // 强制回故障态（Force the fault state）
END_CASE

// ============================================================================
// 段 7｜码位单一优先级链（全拍只写一次，信息级不置 bError）
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
// 段 8｜出口钳位与保持语义重写（R27/R43：结论逐拍重写，每条路径一次钳位）
//      Output clamping and held-semantics rewrite (R27/R43)
// ============================================================================
fLeakRate   := LIMIT(0.0, _fLeakHeld, DL_ESC_SCCM_MAX);                          // 漏率非负夹域（Leak clamped non-negative）
fPressDecay := LIMIT(-DL_ESC_DECAY_MAX, _fDecayHeld, DL_ESC_DECAY_MAX);          // 压降率夹域（Decay clamped）
eResult     := _eResultHeld;                                                    // 结果逐拍重写（Result rewritten every scan）
bDone       := _bDoneLatched;                                                   // 完成位逐拍重写（Done rewritten every scan）
bPass       := _bPassLatched;                                                   // 合格位逐拍重写（Pass rewritten every scan）
nTestCount  := _nTestInt;                                                       // 检测计数逐拍重写（Test counter rewritten）
nNgCount    := _nNgInt;                                                         // 不合格计数逐拍重写（Reject counter rewritten）

// 健康态仲裁（引用属主 A1 的四态语言；工件漏率 NG 不是设备健康问题）
// Health arbitration: a part leak NG is not an equipment health problem
IF _ePhase = E_DL_EscLeakPhase.eFault THEN
    eHealth := E_DL_Ne107Status.eFailure;       // 故障：供气/阀件/传感器不可信（Failure）
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：未使能（Unknown）
ELSIF (_eResultHeld = E_DL_LeakResult.eWarn) OR _bStabWeak THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq;    // 需维护：漏率入 Warn 带或稳压欠佳（Maintenance required）
ELSIF _eResultHeld = E_DL_LeakResult.eNg THEN
    eHealth := E_DL_Ne107Status.eOk;            // 正常：NG 属工件/密封面不良，设备本身健康（OK, part-level defect）
ELSE
    eHealth := E_DL_Ne107Status.eOk;            // 正常（OK）
END_IF

END_FUNCTION_BLOCK
