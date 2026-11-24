(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LeakTestStation
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.2
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺段功能块（Function Block · 压降法气密检漏工站）
 * 功能简述 (Function)   : 压降法气密检漏十相顺控：夹具确认 → 充气 → 稳压 →
 *                         隔离测量 → 排气 → PASS/NG/Abort。内置大漏快判、温
 *                         度补偿（一阶理想气体近似）、稳压超容差设备异常与工
 *                         件不良分离判定（工件 NG 不置故障位）。本工站为流程
 *                         编排与判定层——检漏仪精度与夹具密封属测量系统，不
 *                         在本块职责内；压力/温度反馈由调用方适配层注入。
 * 首扫说明 (Init note)  : 顺序型组件但全部状态由指令沿/电平驱动，无跟踪/初
 *                         始化语义，免首扫（R23/公约 0.1），无 bInit。
 * 公约遵循 (Convention) : 0.2/R21 bError 仅故障级码置位（工件 NG 不置位）；
 *                         0.4 双语同行注释；0.5/R7 实例主体最前部无条件刷新；
 *                         0.10 定时基准由引脚给——依公约增补 tCycle 输入引
 *                         脚（泳道 A FB_DL_ElectronicGear 同款处理，公共约
 *                         定强制项，非逐组件条款）；0.14 非有限值自比等价式
 *                         防御、除法前判零；0.15 压力统一 kPa、温度统一 ℃、
 *                         泄漏率统一 mL/min，同块不混用同类单位；0.16 无魔
 *                         法数；0.17 终结符成对 ✓；0.19 码位同行【级别】注
 *                         释；0.20 验收向量入头注释；R25 bDone 单拍三律；
 *                         R14 语义参数（各相计时 PT）变更经相位切换自然断输
 *                         入一拍归零。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 非有限值/除零/互斥出口 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 七实例（R_TRIG×2/TON×5）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓｜R25 单拍标志生命周期三律 ✓
 * 设计要点 (Key notes)  : ① 充气出口双条件：最小充气保持时长 tFill 到且压力
 *                           达 target×(1−DL_LEAK_FILL_TOL)——tFill 按「最小
 *                           充气保持时长」实现（偏离留档②）；
 *                         ② 稳压结束压力超容差 → 故障 0252 设备异常（不判工
 *                           件 NG，测量系统与被测件责任分离）；
 *                         ③ 大漏快判：测量窗内压降 ≥ fGrossLeakDrop 立即 NG
 *                           （信息码 0153），fGrossLeakDrop=0 禁用快判；
 *                         ④ 泄漏率量纲推导（完整链）：Q[kPa·mL/s] = ΔP[kPa]
 *                           × V[mL] / t[s]；乘 DL_LEAK_UNIT_FACTOR=60 转分钟
 *                           口径 → Q[mL/min]。该系数为工艺约定换算（秒→分），
 *                           非严格气体动力学模型；温度补偿
 *                           Q ×= (273.15+fRefTemp)/(273.15+fT0) 为一阶理想气
 *                           体近似，适用于温漂小、测量窗短的常规检漏工况；
 *                         ⑤ 压差回负（温度回升）按 0 处理 + 信息码 0151，不
 *                           判 NG；bPass/bFail 先清后置保证互斥出口；
 *                         ⑥ 秒值换算：测量时长经 tCycle 引脚折算（TIME 毫
 *                           秒口径 /1000，TIME_TO_REAL），tCycle 非有限值/
 *                           非正 → 故障 0254 归并（输入防御）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① tCycle 增补引脚：规格引脚表未含任务周期，泄漏率
 *                           秒值换算必须有时间基准；理由/影响见公约 0.10 与
 *                           泳道 A 先例——公共约定强制项，非语义偏离；
 *                         ② tFill 引脚语义展开：规格仅列「充气时长」未定义
 *                           出口关系，按「最小充气保持时长（到时才允许判压
 *                           力达标）」实现；理由：防止大容积腔体压力冲击期误
 *                           判达标；影响：充气相出口 = tFill 到 AND 压力达标
 *                           双条件，仅接压力反馈而不接 tFill 的调用方需给足
 *                           tFill=最小值。
 * 开源溯源 (Origin)     : 来源标签 leak-test / pressure-decay（RAW_NOTES_R8
 *                         S-8：压降法检漏公开工程惯例——充气/稳压/隔离测量/
 *                         排气相序、测量前必须隔离气源、稳压过短既藏漏又造
 *                         漏、大漏表现为充不上压、稳压超容差属设备异常（提取
 *                         点⑤⑥），公开技术资料，仅借鉴相序分类与参数域；状态
 *                         机、码位、引脚契约、温度补偿与量纲推导 100% 本库独
 *                         立设计，clean-room 未复制源码。许可证说明：借鉴对象
 *                         为公开技术惯例，无附带许可限制；本文件为本库原创实
 *                         现，随本库许可证发布）。
 * 验收向量 (Acceptance) :
 *   V1 合格件（ΔP 对应 Q < 限值）→ ePass + bDone 单拍 + nPartCount +1；
 *   V2 大漏件（充不上压）→ 充气超时 0251；
 *   V3 测量窗 ΔP 超快判阈 → 立即 FAIL + 信息码 0153；
 *   V4 稳压结束压力超容差 → 0252 且不判 NG（设备异常分离）；
 *   V5 温度 35 ℃ 时补偿后 Q 下降（比值 298.15/308.15）；
 *   V6 bAbort 测量中 → 立即排气不记 NG、判定输出清；
 *   V7 fChamberVolume=0 → 0255（除零防护）；
 *   V8 排气超时 → 0253。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Process 检漏工站件）
 *   2026-11-15  v1.0.1  R8 总监终审修复：终端态分支内的孤立空语句 `;`（非 IEC 61131-3 文法，statement_list 允许零条语句但不容纳孤立分号）改为纯注释占位分支，行为等价、跨平台可移植性合规。
 *   2026-11-15  v1.0.2  R11 修复：压差锁存赋值目标笔误，`_fDeltaP` -> `fDeltaP`（输出 fDeltaP 此前全文零写入致恒 0，属功能缺口 + 未声明标识符编译阻断双缺陷）；快判路径与测量结算路径各一处，共 2 处。
 *                       R11 fix: assignment target erratum, `_fDeltaP` -> `fDeltaP` (2 sites).
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LeakPhase（归属 FB_DL_LeakTestStation，与其同文件发布，公约 0.18）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LeakPhase :
(
    eIdle       := 0,   // 空闲：等启动 / Idle, awaiting start
    eClampCheck := 10,  // 夹具确认：等夹具闭合信号 / Clamp check, awaiting fixture closed
    eFill       := 20,  // 充气：充气阀开，至目标压力 / Fill, valve open to target pressure
    eStabilize  := 30,  // 稳压：隔离保温，等热平衡 / Stabilize, isolated for thermal balance
    eMeasure    := 40,  // 测量：隔离测压降 / Measure, isolated pressure-decay window
    eVent       := 50,  // 排气：排气阀开，泄压到安全位 / Vent, depressurize to safe level
    ePass       := 60,  // 合格：结果保持，等复位/新周期 / Pass verdict held
    eFail       := 70,  // 不合格：结果保持，等复位 / Fail verdict held
    eAbort      := 80,  // 中止：操作员/上游中止，安全排气 / Aborted, safe depressurize
    eFault      := 99   // 设备故障锁存 / Equipment fault latched
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_LeakTestStation
VAR_INPUT
    bEnable             : BOOL;             // 工站使能（Station enable），FALSE=安全排气并清判定输出 / Enable, FALSE = safe depressurize and clear verdicts
    bStart              : BOOL;             // 启动测试周期（Start），上升沿受理（空闲/合格/不合格态）/ Start edge accepted at idle/pass/fail
    bAbort              : BOOL;             // 中止（Abort），电平最高优先 → 安全排气 / Abort level, highest priority, safe vent
    bReset              : BOOL;             // 复位故障与结果（Reset），上升沿受理 / Rising edge resets fault and verdicts
    bFixtureClosed      : BOOL;             // 夹具闭合确认（Fixture closed），FALSE 禁止充气 / Fixture closed interlock, FALSE blocks fill
    bTempCompEnable     : BOOL := TRUE;     // 温度补偿使能（Temp compensation），FALSE=按原始压降计算 / Temperature compensation enable
    fTestPressure       : REAL := 300.0;    // 目标测试压力（Test pressure）[kPa]，域 1..10000 / Target test pressure [kPa]
    fPressureTol        : REAL := 5.0;      // 稳压结束压力容差（Pressure tolerance）[kPa]，域 0.1..100；超容差判设备异常 / Pressure tolerance at stabilize end [kPa]
    fActPressure        : REAL;             // 实际压力（Actual pressure）[kPa]，由变送器/适配层注入 / Actual pressure [kPa] injected by adapter
    fActTemp            : REAL := 25.0;     // 实际温度（Actual temperature）[℃]，温度补偿用 / Actual temperature [degC]
    fRefTemp            : REAL := 25.0;     // 基准温度（Reference temperature）[℃]，补偿基准 / Reference temperature [degC]
    fChamberVolume      : REAL := 100.0;    // 被测腔容积（Chamber volume）[mL]，泄漏率换算用 / Chamber volume [mL] for leak-rate conversion
    fLeakLimit          : REAL := 10.0;     // 泄漏率上限（Leak rate limit）[mL/min]，≤ 此值为 PASS / Leak rate limit [mL/min], PASS below
    fGrossLeakDrop      : REAL := 20.0;     // 大漏快判压降（Gross leak drop）[kPa]，测量窗内超此值立即 NG；0=禁用快判 / Gross-leak quick-judge drop [kPa], 0 disables
    tFill               : TIME := T#3S;     // 最小充气保持时长（Min fill hold，偏离留档②），到时才允许判压力达标 / Minimum fill hold time before pressure verdict
    tStabilize          : TIME := T#5S;     // 稳压时长（Stabilize time），过短既藏漏又造漏 / Stabilize time
    tMeasure            : TIME := T#10S;    // 测量时长（Measure time），T#0S 判故障 / Measure window duration
    tFillTimeout        : TIME := T#20S;    // 充气超时（Fill timeout），兼作夹具确认超时 / Fill timeout, also clamp-check timeout
    tVentTimeout        : TIME := T#10S;    // 排气超时（Vent timeout）/ Vent timeout
    tCycle              : TIME := T#10MS;   // 任务扫描周期（Task cycle time）[ms]，由调用方按实际任务给，泄漏率秒值换算基准（公约 0.10）/ Task cycle time, seconds conversion base
END_VAR
VAR_OUTPUT
    bCmdFillValve       : BOOL;             // 充气阀指令（Fill valve）/ Fill valve command
    bCmdIsolateValve    : BOOL;             // 隔离阀指令（Isolate valve），测量期间为 TRUE（测量前必须隔离气源）/ Isolate valve, TRUE during stabilize/measure
    bCmdVentValve       : BOOL;             // 排气阀指令（Vent valve）/ Vent valve command
    ePhase              : E_DL_LeakPhase := E_DL_LeakPhase.eIdle; // 当前相位（Current phase）/ Current phase
    bBusy               : BOOL;             // 周期执行中（Busy），夹具确认至排气态为 TRUE / TRUE from clamp check to vent
    bDone               : BOOL;             // 周期结束单拍脉冲（Done pulse），单拍生命周期三律 / One-scan verdict pulse
    bPass               : BOOL;             // 判定合格（PASS），合格保持态为 TRUE / PASS verdict held
    bFail               : BOOL;             // 判定不合格（FAIL），不合格保持态为 TRUE / FAIL verdict held
    fLeakRate           : REAL;             // 计算泄漏率（Leak rate）[mL/min]，已含温度补偿，测量后锁存 / Leak rate [mL/min] latched after measure
    fDeltaP             : REAL;             // 测量窗压降（Pressure drop）[kPa]，锁存 / Pressure drop [kPa] latched
    bError              : BOOL;             // 设备故障锁存（Error），仅故障级码；工件 NG 不置此位 / Equipment fault, fault codes only, part NG excluded
    uErrorId            : UDINT;            // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, fault-level priority
    nPartCount          : UDINT;            // 测试件数（Part counter），每次判定 +1 / Tested part counter
    nRejectCount        : UDINT;            // 不合格件数（Reject counter）/ Rejected part counter
END_VAR
VAR
    _ePhase             : E_DL_LeakPhase := E_DL_LeakPhase.eIdle; // 内部相位（Internal phase）/ Internal phase
    _bFaultLatch        : BOOL;             // 设备故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt        : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode          : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code
    _bAbortActive       : BOOL;             // 中止激活（Abort active），电平锁存至排气完成 / Abort latched until vent completes
    _bPassLatched       : BOOL;             // 判定锁存（Verdict latch），TRUE=合格 / Verdict latch, TRUE = pass
    _bVerdictValid      : BOOL;             // 判定有效（Verdict valid），有已结算结果 / A settled verdict exists
    _fDtS               : REAL;             // 扫描周期秒值（Cycle time seconds）[s]，tCycle 折算 / Cycle time in seconds
    _fTestPressEff      : REAL;             // 生效目标压力（Effective test pressure）[kPa]，防御后值 / Sanitized test pressure
    _fTolEff            : REAL;             // 生效容差（Effective tolerance）[kPa] / Sanitized tolerance
    _fVolEff            : REAL;             // 生效容积（Effective volume）[mL] / Sanitized volume
    _fLeakLimEff        : REAL;             // 生效泄漏率上限（Effective leak limit）[mL/min] / Sanitized leak limit
    _fGrossEff          : REAL;             // 生效大漏阈（Effective gross-leak threshold）[kPa] / Sanitized gross-leak threshold
    _fP0                : REAL;             // 测量起点压力（Pressure at measure start）[kPa] / Pressure at measure start
    _fT0                : REAL;             // 测量起点温度（Temperature at measure start）[℃] / Temperature at measure start
    _fDeltaPInt         : REAL;             // 内部压差（Internal delta-P）[kPa]，回负按 0 / Internal delta-P, negative floored to zero
    _fMeasSec           : REAL;             // 测量累计秒值（Accumulated measure seconds）[s] / Accumulated measure seconds
    _fLeakRateInt       : REAL;             // 内部泄漏率（Internal leak rate）[mL/min] / Internal leak rate
    _fDenK              : REAL;             // 温度补偿分母（Compensation denominator）[K] / Compensation denominator in kelvin
    _fbTrigStart        : R_TRIG;           // 启动沿（Start edge detector）/ Start edge detector
    _fbTrigReset        : R_TRIG;           // 复位沿（Reset edge detector）/ Reset edge detector
    _fbTonClampTo       : TON;              // 夹具确认超时（Clamp-check timeout）/ Clamp-check timeout
    _fbTonFillMin       : TON;              // 最小充气保持（Min fill hold）/ Minimum fill hold
    _fbTonFillTo        : TON;              // 充气超时（Fill timeout）/ Fill timeout
    _fbTonStab          : TON;              // 稳压时长（Stabilize duration）/ Stabilize duration
    _fbTonMeas          : TON;              // 测量时长（Measure duration）/ Measure duration
    _fbTonVentTo        : TON;              // 排气超时（Vent timeout）/ Vent timeout
END_VAR
VAR CONSTANT
    DL_LEAK_REAL_MAX    : REAL := 3.4E38;   // 单精度有限值判据幅值（Finite magnitude bound）/ Finite magnitude bound for REAL inputs
    DL_LEAK_EPS         : REAL := 1.0E-6;   // 浮点防零容差（Float divide-guard epsilon）/ Float divide-guard epsilon
    DL_LEAK_FILL_TOL    : REAL := 0.02;     // 充气达标相对容差（Fill reach tolerance）[-]，目标压力的 2% / Fill reach tolerance fraction of target
    DL_LEAK_UNIT_FACTOR : REAL := 60.0;     // 泄漏率秒→分换算系数（Seconds-to-minutes factor）[-]，工艺约定换算 / Unit conversion factor, convention
    DL_LEAK_VENT_DONE   : REAL := 2.0;      // 排气完成压力（Vent-done pressure）[kPa]，低于此值视为安全 / Vent-done pressure threshold [kPa]
    DL_LEAK_KELVIN      : REAL := 273.15;   // 摄氏→开氏偏移（Celsius-to-kelvin offset）[K] / Celsius-to-kelvin offset
    DL_LEAK_PRESS_MIN   : REAL := 1.0;      // 目标压力域下限（Test pressure lower clamp）[kPa] / Test pressure lower clamp
    DL_LEAK_PRESS_MAX   : REAL := 10000.0;  // 目标压力域上限（Test pressure upper clamp）[kPa] / Test pressure upper clamp
    DL_LEAK_TOL_MIN     : REAL := 0.1;      // 容差域下限（Tolerance lower clamp）[kPa] / Tolerance lower clamp
    DL_LEAK_TOL_MAX     : REAL := 100.0;    // 容差域上限（Tolerance upper clamp）[kPa] / Tolerance upper clamp
    DL_TIME_MS_SCALE    : REAL := 1000.0;   // 毫秒→秒换算（Milliseconds-to-seconds scale）[-] / Milliseconds-to-seconds scale
    DL_LEAK_ERR_CLAMP   : UDINT := 16#0005_0250; // 0005_0250 夹具闭合超时【故障级】/ Fixture closed timeout, fault level
    DL_LEAK_ERR_FILL    : UDINT := 16#0005_0251; // 0005_0251 充气超时未达压（大漏常见表现）【故障级】/ Fill timeout, gross leak typical, fault level
    DL_LEAK_ERR_STAB    : UDINT := 16#0005_0252; // 0005_0252 稳压结束压力超容差（设备异常）【故障级】/ Stabilize-end pressure out of tolerance, equipment fault
    DL_LEAK_ERR_VENT    : UDINT := 16#0005_0253; // 0005_0253 排气超时【故障级】/ Vent timeout, fault level
    DL_LEAK_ERR_NAN     : UDINT := 16#0005_0254; // 0005_0254 压力/温度/容积/阈值输入非有限值【故障级】/ Non-finite process input, fault level
    DL_LEAK_ERR_VOL     : UDINT := 16#0005_0255; // 0005_0255 腔容积非法（≤0，除零防护）【故障级】/ Invalid chamber volume, fault level
    DL_LEAK_ERR_MEAS    : UDINT := 16#0005_0256; // 0005_0256 测量时长为零【故障级】/ Zero measure duration, fault level
    DL_LEAK_ERR_STATE   : UDINT := 16#0005_0257; // 0005_0257 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_LEAK_INFO_LIMIT  : UDINT := 16#0005_0150; // 0005_0150 泄漏率上限为负，取绝对值【信息级】/ Negative leak limit, absolute taken, info level
    DL_LEAK_INFO_RISE   : UDINT := 16#0005_0151; // 0005_0151 测量窗压力回升（ΔP<0），按 0 处理【信息级】/ Pressure rise in window, floored, info level
    DL_LEAK_INFO_NOTC   : UDINT := 16#0005_0152; // 0005_0152 温度补偿已关闭，按原始压降判定【信息级】/ Temp compensation off, info level
    DL_LEAK_INFO_GROSS  : UDINT := 16#0005_0153; // 0005_0153 大漏快判触发（提前判 NG）【信息级】/ Gross-leak quick judge triggered, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigStart(CLK := bStart);            // 启动沿（Start edge）
_fbTrigReset(CLK := bReset);            // 复位沿（Reset edge）
_fbTonClampTo(IN := (_ePhase = E_DL_LeakPhase.eClampCheck), PT := tFillTimeout);  // 夹具确认超时（Clamp timeout）
_fbTonFillMin(IN := (_ePhase = E_DL_LeakPhase.eFill), PT := tFill);               // 最小充气保持（Min fill hold）
_fbTonFillTo(IN := (_ePhase = E_DL_LeakPhase.eFill), PT := tFillTimeout);         // 充气超时（Fill timeout）
_fbTonStab(IN := (_ePhase = E_DL_LeakPhase.eStabilize), PT := tStabilize);        // 稳压时长（Stabilize duration）
_fbTonMeas(IN := (_ePhase = E_DL_LeakPhase.eMeasure), PT := tMeasure);            // 测量时长（Measure duration）
_fbTonVentTo(IN := (_ePhase = E_DL_LeakPhase.eVent), PT := tVentTimeout);         // 排气超时（Vent timeout）

// 扫描周期秒值折算（R14：周期变更经相位切换自然断输入归零；此处每拍重算）
// Cycle seconds conversion (R14: phase switches naturally break timer input)
_fDtS := TIME_TO_REAL(tCycle) / DL_TIME_MS_SCALE;    // 毫秒 → 秒，本行换算单位为 s（Conversion unit: seconds）

// ============================================================================
// 段 2｜信息级预清零 + 输入防御 + 复位路径（R15）
//      Info preset + input defense + reset path (R15)
// ============================================================================
_uInfoCode := 0;                        // 信息级瞬时型每拍重算（Transient info recomputed each scan）
bDone := FALSE;                         // 判定单拍先清零（R25：置位-消费-复位同周期闭环）/ Done pulse preset FALSE (R25)

// 泄漏率上限负值取绝对值（Negative leak limit, absolute taken）
IF fLeakLimit < 0.0 THEN
    _fLeakLimEff := ABS(fLeakLimit);    // 取绝对值（Absolute value）
    _uInfoCode := DL_LEAK_INFO_LIMIT;   // 0005_0150 上限为负取绝对值【信息级】/ Negative limit, info level
ELSE
    _fLeakLimEff := fLeakLimit;         // 引脚原值（Pin value as-is）
END_IF

// REAL 输入非有限值/域防御（偏离留档①：tCycle 归并本码防御）
// REAL input non-finite/domain defense (deviation 1: tCycle folded into this code)
IF (NOT (fActPressure >= (-DL_LEAK_REAL_MAX) AND fActPressure <= DL_LEAK_REAL_MAX))
OR (NOT (fActTemp    >= (-DL_LEAK_REAL_MAX) AND fActTemp    <= DL_LEAK_REAL_MAX))
OR (NOT (fRefTemp    >= (-DL_LEAK_REAL_MAX) AND fRefTemp    <= DL_LEAK_REAL_MAX))
OR (NOT (fTestPressure >= (-DL_LEAK_REAL_MAX) AND fTestPressure <= DL_LEAK_REAL_MAX))
OR (NOT (fPressureTol  >= (-DL_LEAK_REAL_MAX) AND fPressureTol  <= DL_LEAK_REAL_MAX))
OR (NOT (fChamberVolume >= (-DL_LEAK_REAL_MAX) AND fChamberVolume <= DL_LEAK_REAL_MAX))
OR (NOT (fGrossLeakDrop >= (-DL_LEAK_REAL_MAX) AND fGrossLeakDrop <= DL_LEAK_REAL_MAX))
OR (NOT (fLeakLimit   >= (-DL_LEAK_REAL_MAX) AND fLeakLimit   <= DL_LEAK_REAL_MAX))
OR (NOT (tCycle >= T#1MS)) THEN
    _bFaultLatch := TRUE;               // 输入非有限值/周期非法锁存（Input defense latch）
    _uErrorIdInt := DL_LEAK_ERR_NAN;    // 0005_0254 输入非有限值【故障级】/ Non-finite input, fault level
    _ePhase := E_DL_LeakPhase.eFault;
ELSIF fChamberVolume <= 0.0 THEN
    _bFaultLatch := TRUE;               // 容积非法锁存（Volume defense latch）
    _uErrorIdInt := DL_LEAK_ERR_VOL;    // 0005_0255 腔容积非法【故障级】/ Invalid volume, fault level
    _ePhase := E_DL_LeakPhase.eFault;
ELSIF tMeasure = T#0MS THEN
    _bFaultLatch := TRUE;               // 测量时长为零锁存（Zero measure latch）
    _uErrorIdInt := DL_LEAK_ERR_MEAS;   // 0005_0256 测量时长为零【故障级】/ Zero measure duration, fault level
    _ePhase := E_DL_LeakPhase.eFault;
ELSE
    // 域钳位后的生效参数（Sanitized effective parameters）
    _fTestPressEff := LIMIT(DL_LEAK_PRESS_MIN, fTestPressure, DL_LEAK_PRESS_MAX); // 目标压力域钳位（Pressure clamped）
    _fTolEff       := LIMIT(DL_LEAK_TOL_MIN, fPressureTol, DL_LEAK_TOL_MAX);      // 容差域钳位（Tolerance clamped）
    _fVolEff       := fChamberVolume;   // 容积已过正数防御（Volume defended positive）
    _fGrossEff     := fGrossLeakDrop;   // 大漏阈（0=禁用快判）/ Gross threshold (0 = off)
END_IF

// 复位路径：仅此路径可清故障锁存与判定（R15）
IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;              // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000;       // 故障码清零（Fault code cleared）
    _bAbortActive := FALSE;             // 中止锁存解除（Abort latch released）
    _bVerdictValid := FALSE;            // 判定失效（Verdict invalidated）
    _bPassLatched := FALSE;             // 判定锁存清零（Verdict latch cleared）
    IF _ePhase = E_DL_LeakPhase.eFault THEN
        _ePhase := E_DL_LeakPhase.eIdle; // 故障态回空闲（Fault phase back to idle）
    END_IF
END_IF

// ============================================================================
// 段 3｜中止电平全局拦截（优先级最高：任意执行相 → 安全排气）
//      Abort level global intercept (highest priority: safe vent from any active phase)
// ============================================================================
IF bAbort AND (NOT _bAbortActive)
AND (_ePhase <> E_DL_LeakPhase.eIdle) AND (_ePhase <> E_DL_LeakPhase.eFault)
AND (_ePhase <> E_DL_LeakPhase.ePass) AND (_ePhase <> E_DL_LeakPhase.eFail) THEN
    _bAbortActive := TRUE;              // 中止锁存（Abort latched）
    _bVerdictValid := FALSE;            // 判定作废不记 NG（Verdict voided, no NG recorded）
    _ePhase := E_DL_LeakPhase.eAbort;   // 进入安全排气（Enter safe vent）
END_IF

// ============================================================================
// 段 4｜核心相位状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core phase state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
IF NOT bEnable THEN
    // 使能撤销：阀组安全侧（充气/隔离关、排气开）、判定清、相位回空闲
    // Disabled: valves to safe side, verdicts cleared, phase back to idle
    _ePhase := E_DL_LeakPhase.eIdle;
    _bVerdictValid := FALSE;
    _bPassLatched := FALSE;
    _bAbortActive := FALSE;
ELSE
    CASE _ePhase OF

        E_DL_LeakPhase.eIdle: // 空闲：等启动沿
            IF _fbTrigStart.Q AND (NOT _bFaultLatch) AND (NOT _bAbortActive) THEN
                _ePhase := E_DL_LeakPhase.eClampCheck;   // 受理启动（Start accepted）
            END_IF

        E_DL_LeakPhase.eClampCheck: // 夹具确认：等闭合信号
            IF bFixtureClosed THEN
                _ePhase := E_DL_LeakPhase.eFill;         // 夹具确认通过（Clamp confirmed）
            ELSIF _fbTonClampTo.Q THEN
                _bFaultLatch := TRUE;                    // 夹具未闭超时（Clamp timeout）
                _uErrorIdInt := DL_LEAK_ERR_CLAMP;       // 0005_0250 夹具闭合超时【故障级】/ Clamp timeout, fault level
                _ePhase := E_DL_LeakPhase.eFault;
            END_IF

        E_DL_LeakPhase.eFill: // 充气：最小保持到 + 压力达标双条件（偏离留档②）
            IF _fbTonFillMin.Q
            AND (fActPressure >= _fTestPressEff * (1.0 - DL_LEAK_FILL_TOL)) THEN
                _ePhase := E_DL_LeakPhase.eStabilize;    // 达标进稳压（Reached, stabilize）
            ELSIF _fbTonFillTo.Q THEN
                _bFaultLatch := TRUE;                    // 充气超时（Fill timeout）
                _uErrorIdInt := DL_LEAK_ERR_FILL;        // 0005_0251 充气超时未达压【故障级】/ Fill timeout, fault level
                _ePhase := E_DL_LeakPhase.eFault;
            END_IF

        E_DL_LeakPhase.eStabilize: // 稳压：隔离保温，结束时记录起点并判容差
            IF _fbTonStab.Q THEN
                _fP0 := fActPressure;                    // 测量起点压力（Pressure at start）
                _fT0 := fActTemp;                        // 测量起点温度（Temperature at start）
                _fMeasSec := 0.0;                        // 测量秒值累计清零（Measure seconds reset）
                IF ABS(_fP0 - _fTestPressEff) > _fTolEff THEN
                    _bFaultLatch := TRUE;                // 设备异常：稳压后压力超容差（Equipment fault: out of tolerance）
                    _uErrorIdInt := DL_LEAK_ERR_STAB;    // 0005_0252 稳压超容差（不判工件 NG）【故障级】/ Stabilize out of tolerance, equipment fault
                    _ePhase := E_DL_LeakPhase.eFault;
                ELSE
                    _ePhase := E_DL_LeakPhase.eMeasure;  // 进入隔离测量（Enter measure）
                END_IF
            END_IF

        E_DL_LeakPhase.eMeasure: // 测量：实时压差跟踪 + 大漏快判 + 计时结算
            _fMeasSec := _fMeasSec + _fDtS;              // 测量秒值累计（Measure seconds accumulate）
            _fDeltaPInt := _fP0 - fActPressure;          // 实时压差（Live delta-P）
            IF _fDeltaPInt < 0.0 THEN
                _fDeltaPInt := 0.0;                      // 压力回升按 0 处理（Rise floored to zero）
                _uInfoCode := DL_LEAK_INFO_RISE;         // 0005_0151 压力回升【信息级】/ Pressure rise, info level
            END_IF
            IF (_fGrossEff > 0.0) AND (_fDeltaPInt >= _fGrossEff) THEN
                _uInfoCode := DL_LEAK_INFO_GROSS;        // 0005_0153 大漏快判触发【信息级】/ Gross-leak quick judge, info level
                fDeltaP := _fDeltaPInt;                 // 压差锁存（Delta-P latched）
                fLeakRate := 0.0;                        // 快判路径无有效泄漏率（No rate on gross path）
                _bPassLatched := FALSE;                  // 不合格锁存（Fail latched）
                _bVerdictValid := TRUE;
                nPartCount := nPartCount + UINT#1;       // 计件（Part counted）
                nRejectCount := nRejectCount + UINT#1;   // 计不良（Reject counted）
                bDone := TRUE;                           // 判定单拍（R25 本拍闭环）/ Done pulse (R25)
                _ePhase := E_DL_LeakPhase.eVent;
            ELSIF _fbTonMeas.Q THEN
                // 测量窗到期结算（Measure window settled）
                fDeltaP := _fDeltaPInt;                 // 压差锁存（Delta-P latched）
                IF _fMeasSec > DL_LEAK_EPS THEN
                    _fLeakRateInt := _fDeltaPInt * _fVolEff / _fMeasSec * DL_LEAK_UNIT_FACTOR;
                    // 量纲链：kPa·mL/s × 60 → mL/min（偏离留档②前的设计要点④完整推导）
                    // Unit chain: kPa*mL/s times 60 = mL/min (full derivation in key notes 4)
                ELSE
                    _fLeakRateInt := 0.0;                // 秒值防御（除零保护，理论上不可达）/ Divide guard (unreachable by design)
                END_IF
                IF bTempCompEnable THEN
                    _fDenK := DL_LEAK_KELVIN + _fT0;     // 补偿分母（Compensation denominator）
                    IF _fDenK > DL_LEAK_EPS THEN
                        _fLeakRateInt := _fLeakRateInt * (DL_LEAK_KELVIN + fRefTemp) / _fDenK;
                        // 一阶理想气体近似（设计要点④声明适用域）/ First-order ideal-gas approximation
                    END_IF
                ELSE
                    _uInfoCode := DL_LEAK_INFO_NOTC;     // 0005_0152 温度补偿关闭【信息级】/ Temp compensation off, info level
                END_IF
                fLeakRate := _fLeakRateInt;              // 泄漏率锁存（Rate latched）
                _bPassLatched := _fLeakRateInt <= _fLeakLimEff;  // 判定：≤ 上限为合格（Verdict by limit）
                _bVerdictValid := TRUE;
                nPartCount := nPartCount + UINT#1;       // 计件（Part counted）
                IF NOT _bPassLatched THEN
                    nRejectCount := nRejectCount + UINT#1;   // 计不良（Reject counted）
                END_IF
                bDone := TRUE;                           // 判定单拍（R25 本拍闭环）/ Done pulse (R25)
                _ePhase := E_DL_LeakPhase.eVent;
            END_IF

        E_DL_LeakPhase.eVent: // 排气：泄压到安全位后分流（中止→空闲 / 判定→保持态）
            IF fActPressure < DL_LEAK_VENT_DONE THEN
                IF _bAbortActive THEN
                    _bAbortActive := FALSE;              // 中止路径排气完成回空闲（Abort vent done back to idle）
                    _ePhase := E_DL_LeakPhase.eIdle;
                ELSIF _bVerdictValid THEN
                    // 正常判定路径排气完成后进保持态（Verdict hold phase after vent done）
                    IF _bPassLatched THEN
                        _ePhase := E_DL_LeakPhase.ePass; // 合格保持（Pass hold）
                    ELSE
                        _ePhase := E_DL_LeakPhase.eFail; // 不合格保持（Fail hold）
                    END_IF
                ELSE
                    _ePhase := E_DL_LeakPhase.eIdle;     // 无判定兜底回空闲（No verdict, back to idle）
                END_IF
            ELSIF _fbTonVentTo.Q THEN
                _bFaultLatch := TRUE;                    // 排气超时（Vent timeout）
                _uErrorIdInt := DL_LEAK_ERR_VENT;        // 0005_0253 排气超时【故障级】/ Vent timeout, fault level
                _ePhase := E_DL_LeakPhase.eFault;
            END_IF

        E_DL_LeakPhase.ePass: // 合格保持：等复位或新周期
            IF _fbTrigStart.Q AND (NOT _bFaultLatch) AND (NOT bAbort) THEN
                _ePhase := E_DL_LeakPhase.eClampCheck;   // 新周期受理（New cycle accepted）
                _bVerdictValid := FALSE;
                bPass := FALSE;
            END_IF

        E_DL_LeakPhase.eFail: // 不合格保持：等复位或新周期
            IF _fbTrigStart.Q AND (NOT _bFaultLatch) AND (NOT bAbort) THEN
                _ePhase := E_DL_LeakPhase.eClampCheck;   // 新周期受理（New cycle accepted）
                _bVerdictValid := FALSE;
                bFail := FALSE;
            END_IF

        E_DL_LeakPhase.eAbort: // 中止排气：泄压到安全位后保持等待复位
            IF fActPressure < DL_LEAK_VENT_DONE THEN
                _bAbortActive := FALSE;                  // 安全位达成，中止释放（Safe level reached, abort released）
            END_IF

        E_DL_LeakPhase.eFault: // 设备故障锁存：等复位（复位路径在段 2）
            // 等复位（Awaiting reset）

        ELSE // 非法状态兜底（本块专用码位）
            _bFaultLatch := TRUE;
            _uErrorIdInt := DL_LEAK_ERR_STATE;           // 0005_0257 非法状态兜底【故障级】/ Illegal state fallback, fault level
            _ePhase := E_DL_LeakPhase.eFault;
    END_CASE
END_IF

// 复位路径补充：保持态复位回空闲（Hold phases reset back to idle）
IF _fbTrigReset.Q AND ((_ePhase = E_DL_LeakPhase.ePass) OR (_ePhase = E_DL_LeakPhase.eFail)) THEN
    _ePhase := E_DL_LeakPhase.eIdle;     // 保持态复位（Hold released）
END_IF

// ============================================================================
// 段 5｜输出派生（阀组安全侧 + 判定互斥先清后置）
//      Output derivation (valve safe side + verdict mutual exclusion)
// ============================================================================
// 阀组默认安全侧：全关（Valves preset closed）
bCmdFillValve := FALSE;                  // 充气阀预清（Fill preset）
bCmdIsolateValve := FALSE;               // 隔离阀预清（Isolate preset）
bCmdVentValve := FALSE;                  // 排气阀预清（Vent preset）

IF bEnable AND (NOT _bFaultLatch) THEN
    bCmdFillValve := (_ePhase = E_DL_LeakPhase.eFill);          // 充气阀：仅充气相（Fill in fill phase）
    bCmdIsolateValve := (_ePhase = E_DL_LeakPhase.eStabilize)
                     OR (_ePhase = E_DL_LeakPhase.eMeasure);    // 隔离阀：稳压与测量相（测量前必须隔离气源）/ Isolate in stabilize+measure
    bCmdVentValve := (_ePhase = E_DL_LeakPhase.eVent)
                  OR (_ePhase = E_DL_LeakPhase.eAbort)
                  OR _bAbortActive;                             // 排气阀：排气/中止相与中止锁存期（Vent in vent/abort）
ELSE
    bCmdVentValve := TRUE;               // 使能撤销/故障：安全排气（Safe vent on disable or fault）
END_IF

// 判定互斥先清后置（出口断言：bPass 与 bFail 恒互斥）
// Verdict mutual exclusion: preset clear then set (exit assertion)
bPass := FALSE;                          // 合格预清（Pass preset）
bFail := FALSE;                          // 不合格预清（Fail preset）
IF _bVerdictValid THEN
    bPass := _bPassLatched;              // 合格出口（Pass outlet）
    bFail := NOT _bPassLatched;          // 不合格出口（Fail outlet）
END_IF

bBusy := (_ePhase = E_DL_LeakPhase.eClampCheck)
      OR (_ePhase = E_DL_LeakPhase.eFill)
      OR (_ePhase = E_DL_LeakPhase.eStabilize)
      OR (_ePhase = E_DL_LeakPhase.eMeasure)
      OR (_ePhase = E_DL_LeakPhase.eVent);               // 周期执行中派生（Busy derived）

ePhase := _ePhase;                       // 相位镜像（Phase mirror）

// ============================================================================
// 段 6｜bError/uErrorId 出口（R21：bError 显式排除信息级码）
//      Outlets: bError excludes info codes (R21)
// ============================================================================
bError := _bFaultLatch;                  // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;            // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;              // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK