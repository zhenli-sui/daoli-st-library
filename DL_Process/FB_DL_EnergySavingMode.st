(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EnergySavingMode
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 工艺段 · 整线空闲节能编排
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
 *                         仅依赖标准库（TON / R_TRIG / LIMIT），气源压力与温度全部经
 *                         引脚注入，块内不读任何外部量、不做任何模拟量通道绑定
 * 功能描述 (Function)   : 以「空闲确认延时 → 节能态（降压 / 停热 / 伺服休眠）→ 唤醒
 *                         缓冲（压力先恢复再放行）」三段编排节能与生产，输出可解释
 *                         的节能标志与累计时长，杜绝「唤醒即放行」造成的低压启动
 * 与既有件边界 (Scope)  : 多台设备轮值由轮值调度件承担；单机运行时长由运行计时件承
 *                         担；本件管整线状态级的能量模式切换与放行门控，不替代任何
 *                         单机控制块，也不下发任何设备级启停指令（只给节能请求位）
 * 状态机规模 (States)   : 四工作态加故障（eRun 0 / eIdleCount 10 / eEco 20 / eWake 30
 *                         / eFault 99）；编号留 10 间隔便于插态
 * 关键算法 (Algorithm)  :
 *   ① 空闲确认：空闲判据须在确认延时内持续为真，中途掉沿立即回运行态并清计时
 *   ② 节能编排：进入顺序固定为「先降压 → 再停热 → 最后伺服休眠」，每步间隔一个台
 *      阶（默认 500 毫秒）；原因是伺服休眠时若气源仍为工作压力，抱闸释放瞬间会顶件
 *   ③ 退出反序：唤醒时严格反序撤销（先撤休眠 → 再撤停热 → 最后恢复压力），保证伺服
 *      再上电时气源已在工作压力附近，不会出现带压顶缸
 *   ④ 唤醒门控：放行须同时满足「压力达节能目标加压裕量」「压力低位请求已撤」「唤醒
 *      缓冲时间走完」三条，防压力表冲高瞬放行
 *   ⑤ 三出口全部为状态派生式，无锁存：既避免单拍标志跨拍残留，也保证任何异常路径
 *      （故障、使能撤销）都会在下一拍自然复位，不需要额外的撤除分支
 *   ⑥ 反馈失效：节能或唤醒期间压力读数触零或非有限值，说明无反馈可用，此时无法确认
 *      压力已恢复，一律禁止放行并锁故障
 * 码位表 (Error codes)  :
 *   16#0005_01C4【信息级】延时或压力参数越界已钳位，不置故障位
 *   16#0005_02F0【故障级】唤醒超时（超过两倍唤醒缓冲仍未达压）
 *   16#0005_02F1【故障级】气源压力反馈缺失（读数为零或非有限值）
 *   16#0005_02F2【故障级】非法状态兜底
 * R32 写入点次序审计 :
 *   bAirPressureLow / bHeatStandby / bServoSleep : 仅在段 9 按状态单点派生（每拍先清零
 *       再按所在阶段置位），状态机内不写，因此不存在同拍多分支写同一量的可能
 *   bReadyToRun : 仅段 9 单点派生（运行态恒真；唤醒态须门控通过）
 *   _uErrorIdInt: ① 首扫清（段 4）→ ② 参数越界（段 2 只进信息码，不写故障码）→ ③ 反馈
 *       缺失（段 6）→ ④ 唤醒超时（段 6）→ ⑤ 非法状态（ELSE）→ ⑥ 复位清（eFault）
 *   _eState     : 每拍只在 CASE 分支出口单点写入；CASE 之外仅段 6 两处监视与段 7 使能
 *       撤销，均在 CASE 之前，次序固定
 *   _tEcoDur    : ① 节能转出拍快照（eEco）→ ② 统计消费拍读取（eWake）→ ③ 复位清
 * 单拍纪律说明 (R24/R25) : 本件节能出口全部为状态派生式（每拍重算、不锁存），因此不
 *       存在单拍标志跨拍残留；唯一具单拍性质的事件是「模式切换」，由切换计数器在节能
 *       转出拍唯一加一承担，不存在预清零与转出拍冲突的问题
 * 验收向量 (Acceptance) :
 *   V1 进入节能：空闲持续达确认延时 → 节能生效为真，同一拍降压请求为真
 *   V2 唤醒门控：节能目标 4.0 巴、裕量 0.2 巴，实测 4.1 巴 → 放行为假（未达 4.2 巴）
 *   V3 唤醒完成：实测 4.25 巴且缓冲走完 → 放行为真，下一拍回运行态
 *   V4 反馈缺失：实测 0.0 巴且节能生效 → 码 02F1、故障态
 *   V5 统计：一次节能持续 300 秒 → 累计节能时长增加 300 秒、切换次数加一
 * 开源溯源 (Origin)     : 参考批控与轻工产线公开手册的能量状态分层与停机分级语义组织，
 *                         只借状态分类与参数域；状态机、反序编排、门控判据、码位与引
 *                         脚契约为本库独立设计，clean-room 不构成衍生作品
 * 红线自检 (Redline)    : R1 零全局表与外部变量引用、零物理地址记号 ✓｜R2 零占位符 ✓
 *                         R3 纯 IEC 61131-3 加标准库 ✓｜R4 非有限值防御、比较全带容差、
 *                         无除法 ✓｜R5 声明行中英双语同行注释 ✓｜R6 五成员逐一有 CASE
 *                         标签且含 ELSE 兜底 ✓｜R7 两沿检测与三定时器全部在 CASE 之外
 *                         无条件刷新 ✓
 * 现场投用须知 (Notes)  :
 *   ① 节能目标压力必须低于工作压力且高于夹具最低夹持压力，低于夹持压力会导致待机
 *      期间工件松脱；建议先按气动原理图核算最低夹持压力再定目标值
 *   ② 唤醒裕量不宜小于压力传感器的重复精度，否则门控会在阈值上下反复抖动；现场
 *      经验值是取传感器精度的三到五倍
 *   ③ 伺服休眠许可由工艺侧给出，本块不判断伺服是否已停稳；若需停机确认，请把停稳
 *      反馈串进许可位，不要在块内加延时猜测
 *   ④ 唤醒缓冲只保证「压力恢复后才放行」，不保证「工件已就位」；来料检测与就位确
 *      认仍由上游工站负责，本块不越权
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 11 · C 泳道 · 工站四件套之四）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_EcoModeState（归属 FB_DL_EnergySavingMode，同文件发布）
 *   四工作态加故障，每个成员在主状态机中均有同名 CASE 标签（R31 完备性）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_EcoModeState :
(
    eRun       := 0,    // 运行：产线生产，节能出口全撤 / Running, all eco outlets withdrawn
    eIdleCount := 10,   // 空闲确认：等空闲判据持续成立达延时 / Idle confirmation, waiting for the delay
    eEco       := 20,   // 节能：降压、停热、伺服休眠按序投入 / Eco, staged withdrawal of energy
    eWake      := 30,   // 唤醒：按反序恢复并等压力回到工作值 / Wake, reverse restore and pressure gate
    eFault     := 99    // 故障锁存：仅复位沿可退 / Fault latched, only a reset edge leaves
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_EcoStat（归属 FB_DL_EnergySavingMode）
 *   跨周期统计，由调用方持有，本块只累加，掉电保持由上层负责
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_EcoStat :
STRUCT
    tTotalEco    : TIME;                    // 累计节能时长 [毫秒] [Accumulated eco time]
    nSwitchCount : UDINT;                   // 累计模式切换次数 [次] [Mode switch counter]
    tLastEco     : TIME;                    // 上一轮节能时长 [毫秒] [Last eco duration]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_EnergySavingMode
VAR_INPUT
    bEnable            : BOOL;              // 使能，FALSE 立即回运行态并撤节能请求 [Enable, FALSE returns to run]
    bReset             : BOOL;              // 复位故障，上升沿受理 [Reset fault on rising edge]
    bLineIdle          : BOOL;              // 产线空闲判据（无料且无作业）[-] [Line idle criterion]
    bWakeRequest       : BOOL;              // 唤醒请求（来料 / 操作员 / 上位机）[-] [Wake-up request]
    fAirPressureAct    : REAL;              // 实际气源压力 [巴]，量程 0.0~10.0 [Actual air pressure, bar]
    fAirPressureEco    : REAL := 4.0;       // 节能目标压力 [巴]，域 0.0~10.0 [Eco target pressure, bar]
    fWakeMargin        : REAL := 0.2;       // 唤醒压力裕量 [巴]，须达目标加裕量 [Wake margin, bar]
    tIdleDelay         : TIME := T#120S;    // 空闲确认延时 [毫秒]，0 表示立即节能 [Idle confirm delay]
    tWakeRamp          : TIME := T#3S;      // 唤醒缓冲（压力恢复等待上限）[毫秒] [Wake ramp allowance]
    bServoSleepPermit  : BOOL;              // 允许伺服休眠，工艺侧给出 [-] [Servo sleep permitted by process]
    bHeatStandbyPermit : BOOL;              // 允许加热转保温或关闭 [-] [Heater standby permitted]
END_VAR
VAR_OUTPUT
    bEcoActive         : BOOL;              // 节能模式生效（节能与唤醒期间均为真）[-] [Eco mode engaged]
    bAirPressureLow    : BOOL;              // 请求降压（送气源比例阀）[-] [Request reduced air pressure]
    bHeatStandby       : BOOL;              // 请求加热转保温或关闭 [-] [Request heater standby]
    bServoSleep        : BOOL;              // 请求伺服休眠 [-] [Request servo sleep]
    bReadyToRun        : BOOL;              // 唤醒完成，可放行生产 [-] [Ready to run after wake]
    eState             : E_DL_EcoModeState; // 主状态机当前态 [-] [Current state]
    bError             : BOOL;              // 故障锁存，需复位清除 [Latched fault]
    uErrorId           : UDINT;             // 事件码或故障码，0 表示无 [Event or fault code]
    tIdleElapsed       : TIME;              // 空闲累计已计时长 [毫秒] [Idle elapsed time]
    tEcoElapsed        : TIME;              // 本次节能已持续时长 [毫秒] [Eco elapsed time]
END_VAR
VAR_IN_OUT
    stStat             : ST_DL_EcoStat;     // 跨周期统计，调用方持有 [Persistent statistics]
END_VAR
VAR
    _eState          : E_DL_EcoModeState := E_DL_EcoModeState.eRun;  // 内部状态寄存器，唯一真值源 [Internal state register]
    _bInit           : BOOL := FALSE;       // 首扫标志，初值 FALSE，判据 NOT _bInit [First-scan flag, R19 pattern]
    _bFaultLatch     : BOOL;                // 故障级锁存，仅复位路径清 [Fault latch, reset path only]
    _uErrorIdInt     : UDINT;               // 故障级码寄存 [Fault-level code register]
    _uInfoCode       : UDINT;               // 本拍信息级码，每拍重算 [Transient info code]
    fEcoEff          : REAL;                // 生效节能目标压力 [巴] [Effective eco pressure, bar]
    fMarginEff       : REAL;                // 生效唤醒裕量 [巴] [Effective wake margin, bar]
    fWakeGate        : REAL;                // 唤醒放行压力门限 [巴] [Wake gate pressure, bar]
    tIdleEff         : TIME;                // 生效空闲延时 [毫秒] [Effective idle delay]
    tWakeEff         : TIME;                // 生效唤醒缓冲 [毫秒] [Effective wake ramp]
    tWakeMaxEff      : TIME;                // 唤醒超时上限（缓冲的两倍）[毫秒] [Wake timeout limit]
    _tEcoDur         : TIME;                // 本次节能实际时长快照 [毫秒] [Eco duration snapshot]
    _bPressFinite    : BOOL;                // 压力读数有限 [-] [Pressure reading finite]
    _bPressMissing   : BOOL;                // 压力反馈缺失判据 [-] [Pressure feedback missing]
    _bWakeGateOk     : BOOL;                // 唤醒放行三条件同时成立 [-] [Wake gate satisfied]
    _bReadyLatch     : BOOL;                // 放行锁存：先放行一拍再转运行态 [Permit latched one scan before returning]
    bIdleIn          : BOOL;                // 空闲计时输入条件，先算后调 [Idle timer input]
    bEcoIn           : BOOL;                // 节能计时输入条件，先算后调 [Eco timer input]
    bWakeIn          : BOOL;                // 唤醒计时输入条件，先算后调 [Wake timer input]
    fbTrigReset      : R_TRIG;              // 复位沿检测 [Reset edge detector]
    fbTrigIdle       : R_TRIG;              // 空闲判据上升沿 [Idle rising edge]
    fbTrigWake       : R_TRIG;              // 唤醒请求上升沿 [Wake request rising edge]
    fbTmoIdle        : TON;                 // 空闲确认计时 [Idle confirmation timer]
    fbTmoEco         : TON;                 // 节能计时兼阶段时钟 [Eco timer and stage clock]
    fbTmoWake        : TON;                 // 唤醒缓冲计时兼阶段时钟 [Wake timer and stage clock]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : REAL := 1.0E-6;      // 浮点判等容差 [-] [Float comparison epsilon]
    DL_PRESSURE_MAX  : REAL := 10.0;        // 压力量程上限 [巴] [Pressure upper bound, bar]
    DL_MARGIN_MAX    : REAL := 5.0;         // 裕量域上限 [巴] [Margin upper bound, bar]
    DL_REAL_MAX      : REAL := 3.4E38;      // 单精度有限值判据幅值 [-] [Finite magnitude bound]
    DL_ECO_GAP1      : TIME := T#500MS;     // 节能与唤醒的第一步台阶 [毫秒] [First stage step]
    DL_ECO_GAP2      : TIME := T#1S;        // 节能与唤醒的第二步台阶 [毫秒] [Second stage step]
    DL_WAKE_FACTOR   : DINT := 2;           // 唤醒超时相对缓冲的倍数 [-] [Wake timeout factor]
    DL_TMO_MAX       : TIME := T#600S;      // 延时参数域上限 [毫秒] [Delay upper bound]
    DL_TIME_MAX      : TIME := T#500H;     // 累计时长饱和上限 [毫秒] [Duration saturation limit]
    DL_SWITCH_MAX    : UDINT := 16#FFFF_FFFE; // 切换次数饱和上限 [次] [Switch counter saturation]
    DL_INFO_LIM_CLAMP: UDINT := 16#0005_01C4; // 01C4 延时或压力参数越界已钳位【信息级】 [Info, parameter clamped]
    DL_ERR_WAKE_TMO  : UDINT := 16#0005_02F0; // 02F0 唤醒超时（压力未恢复）【故障级】 [Fault, wake timeout]
    DL_ERR_PRESS     : UDINT := 16#0005_02F1; // 02F1 气源压力反馈缺失【故障级】 [Fault, pressure feedback missing]
    DL_ERR_STATE     : UDINT := 16#0005_02F2; // 02F2 非法状态兜底【故障级】 [Fault, illegal state]
END_VAR

// ==== 段 1｜信息级码预清零（信息码每拍重算，不跨拍残留） / Info code pre-clear, recomputed every scan
_uInfoCode := 16#0000_0000;                 // 信息级码每拍重算 [Info code recomputed]

// ==== 段 2｜参数钳位（压力、裕量、两个延时，先钳位再进逻辑） / Parameter clamping before any logical use
fEcoEff := fAirPressureEco;                 // 节能目标先取引脚值 [Eco pressure from pin]
IF (fEcoEff < 0.0) OR (fEcoEff > DL_PRESSURE_MAX) THEN
    fEcoEff    := LIMIT(0.0, fEcoEff, DL_PRESSURE_MAX);   // 越界钳到量程内 [Clamped into range]
    _uInfoCode := DL_INFO_LIM_CLAMP;        // 01C4 延时或压力参数越界已钳位【信息级】 [Info, parameter clamped]
END_IF

fMarginEff := fWakeMargin;                  // 裕量先取引脚值 [Margin from pin]
IF (fMarginEff < 0.0) OR (fMarginEff > DL_MARGIN_MAX) THEN
    fMarginEff := LIMIT(0.0, fMarginEff, DL_MARGIN_MAX);  // 越界钳到裕量域内 [Clamped into margin range]
    _uInfoCode := DL_INFO_LIM_CLAMP;        // 01C4 延时或压力参数越界已钳位【信息级】 [Info, parameter clamped]
END_IF

fWakeGate := fEcoEff + fMarginEff;          // 放行门限等于目标加裕量 [Gate = target plus margin]

tIdleEff := tIdleDelay;                     // 空闲延时先取引脚值 [Idle delay from pin]
IF tIdleEff > DL_TMO_MAX THEN
    tIdleEff   := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
    _uInfoCode := DL_INFO_LIM_CLAMP;        // 01C4 延时或压力参数越界已钳位【信息级】 [Info, parameter clamped]
ELSIF tIdleEff < T#0S THEN
    tIdleEff := T#0S;                       // 负值归零即立即节能 [Negative means immediate]
END_IF

tWakeEff := tWakeRamp;                      // 唤醒缓冲先取引脚值 [Wake ramp from pin]
IF tWakeEff > DL_TMO_MAX THEN
    tWakeEff   := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
    _uInfoCode := DL_INFO_LIM_CLAMP;        // 01C4 延时或压力参数越界已钳位【信息级】 [Info, parameter clamped]
ELSIF tWakeEff < T#0S THEN
    tWakeEff := T#0S;                       // 负值归零 [Negative clamped to zero]
END_IF

tWakeMaxEff := tWakeEff * DL_WAKE_FACTOR;   // 唤醒超时取缓冲的两倍 [Wake timeout = twice the ramp]

// ==== 段 3｜沿与定时器无条件刷新（R7 红线：严禁置于 IF / CASE 分支内） / Unconditional refresh of edges and timers
fbTrigReset(CLK := bReset);                 // 复位沿 [Reset edge]
fbTrigIdle(CLK := bLineIdle);               // 空闲上升沿 [Idle rising edge]
fbTrigWake(CLK := bWakeRequest);            // 唤醒上升沿 [Wake rising edge]

IF (_eState = E_DL_EcoModeState.eIdleCount) AND bLineIdle THEN
    bIdleIn := TRUE;                        // 空闲确认段且判据仍成立才计时 [Count only while idle persists]
ELSE
    bIdleIn := FALSE;                       // 其余段清零 [Cleared otherwise]
END_IF
fbTmoIdle(IN := bIdleIn, PT := tIdleEff);

IF _eState = E_DL_EcoModeState.eEco THEN
    bEcoIn := TRUE;                         // 节能段计时兼阶段时钟 [Eco timer and stage clock]
ELSE
    bEcoIn := FALSE;                        // 其余段清零 [Cleared otherwise]
END_IF
fbTmoEco(IN := bEcoIn, PT := DL_TIME_MAX);

IF _eState = E_DL_EcoModeState.eWake THEN
    bWakeIn := TRUE;                        // 唤醒段计时兼阶段时钟 [Wake timer and stage clock]
ELSE
    bWakeIn := FALSE;                       // 其余段清零 [Cleared otherwise]
END_IF
fbTmoWake(IN := bWakeIn, PT := DL_TIME_MAX);

// ==== 段 4｜首扫初始化（R19 唯一合法范式：初值 FALSE，判据 NOT，同步后置 TRUE） / First-scan initialisation with the canonical R19 pattern
IF NOT _bInit THEN
    _eState        := E_DL_EcoModeState.eRun;   // 状态回运行 [State to run]
    _bFaultLatch   := FALSE;                // 故障锁存清零 [Fault latch cleared]
    _uErrorIdInt   := 16#0000_0000;         // 故障码清零 [Fault code cleared]
    _tEcoDur       := T#0S;                 // 节能时长快照清零 [Eco snapshot cleared]
    _bReadyLatch   := FALSE;                // 放行锁存复位 [Permit latch reset]
    bEcoActive     := FALSE;                // 节能标志复位 [Eco flag reset]
    bAirPressureLow := FALSE;               // 降压请求复位 [Pressure request reset]
    bHeatStandby   := FALSE;                // 停热请求复位 [Heater request reset]
    bServoSleep    := FALSE;                // 休眠请求复位 [Sleep request reset]
    bReadyToRun    := TRUE;                 // 初始视为可运行 [Initially ready to run]
    bError         := FALSE;                // 故障标志清零 [Error cleared]
    uErrorId       := 16#0000_0000;         // 事件码清零 [Error id cleared]
    tIdleElapsed   := T#0S;                 // 空闲计时清零 [Idle elapsed cleared]
    tEcoElapsed    := T#0S;                 // 节能计时清零 [Eco elapsed cleared]
    stStat.tTotalEco    := T#0S;            // 累计节能时长清零 [Total eco cleared]
    stStat.nSwitchCount := 0;               // 切换次数清零 [Switch counter cleared]
    stStat.tLastEco     := T#0S;            // 上轮节能时长清零 [Last eco cleared]
    _bInit := TRUE;                         // 首扫只做一次 [Runs exactly once]
END_IF

// ==== 段 5｜压力反馈有效性（零读数与非有限值同属「无反馈」，一律按缺失处理） / Pressure feedback validity, zero and non-finite treated alike
_bPressFinite := (fAirPressureAct >= (-DL_REAL_MAX)) AND (fAirPressureAct <= DL_REAL_MAX);
IF (NOT _bPressFinite) OR (fAirPressureAct <= DL_FLOAT_EPS) THEN
    _bPressMissing := TRUE;                 // 无可用反馈 [No usable feedback]
ELSE
    _bPressMissing := FALSE;                // 反馈可用 [Feedback usable]
END_IF

// ==== 段 6｜全局监视：反馈缺失优先，其次唤醒超时（两者都在模式切换之外单点判定） / Global monitors: missing feedback first, then wake timeout
IF bEnable AND (NOT _bFaultLatch) AND _bPressMissing
AND ((_eState = E_DL_EcoModeState.eEco) OR (_eState = E_DL_EcoModeState.eWake)) THEN
    _bFaultLatch := TRUE;                   // 无反馈无法确认恢复，禁止放行 [Cannot confirm recovery, fault]
    _uErrorIdInt := DL_ERR_PRESS;           // 02F1 气源压力反馈缺失【故障级】 [Fault, feedback missing]
    _eState      := E_DL_EcoModeState.eFault;
END_IF

_bWakeGateOk := (_eState = E_DL_EcoModeState.eWake)
            AND (NOT _bPressMissing)
            AND (fAirPressureAct >= (fWakeGate + DL_FLOAT_EPS))
            AND (fbTmoWake.ET >= tWakeEff);   // 门控三条件：压力达标、无缺失、缓冲走完 [Three gate conditions]

IF bEnable AND (NOT _bFaultLatch)
AND (_eState = E_DL_EcoModeState.eWake)
AND (tWakeMaxEff > T#0S)
AND (fbTmoWake.ET > tWakeMaxEff)
AND (NOT _bWakeGateOk) THEN
    _bFaultLatch := TRUE;                   // 缓冲两倍仍未达压，锁故障 [Pressure not restored, fault]
    _uErrorIdInt := DL_ERR_WAKE_TMO;        // 02F0 唤醒超时【故障级】 [Fault, wake timeout]
    _eState      := E_DL_EcoModeState.eFault;
END_IF

// ==== 段 7｜使能撤销（FALSE 立即回运行态，节能出口由段 9 自然撤销） / Disable path returns to run, eco outlets drop by derivation
IF NOT bEnable THEN
    _eState := E_DL_EcoModeState.eRun;      // 立即回运行态 [Immediately back to run]
    _tEcoDur := T#0S;                       // 时长快照作废 [Snapshot invalidated]
END_IF

// ==== 段 8｜主状态机（ENUM 加 CASE 加 ELSE 兜底，五成员逐一有标签） / Main state machine, every member has its own label
CASE _eState OF
    E_DL_EcoModeState.eRun: // 运行：等空闲判据上升沿
        IF fbTrigIdle.Q AND bEnable AND (NOT _bFaultLatch) THEN
            _uErrorIdInt := 16#0000_0000;   // 进入确认前无故障 [No fault before confirmation]
            _eState      := E_DL_EcoModeState.eIdleCount;
        END_IF

    E_DL_EcoModeState.eIdleCount: // 空闲确认：判据中途掉沿立即回运行
        IF NOT bLineIdle THEN
            _eState := E_DL_EcoModeState.eRun;     // 判据失守，回运行态 [Idle criterion lost, back to run]
        ELSIF fbTmoIdle.Q THEN
            _tEcoDur := T#0S;               // 新一轮节能，时长快照清零 [New eco round, snapshot cleared]
            _eState  := E_DL_EcoModeState.eEco;
        END_IF

    E_DL_EcoModeState.eEco: // 节能：三段按阶投入，唤醒请求或来料即转唤醒
        IF fbTrigWake.Q OR (NOT bLineIdle) THEN
            _tEcoDur     := fbTmoEco.ET;    // 转出拍快照节能时长（定时器出段即清零）[Snapshot before the timer resets]
            _bReadyLatch := FALSE;          // 新的唤醒过程，放行锁存复位 [Permit latch reset]
            _eState      := E_DL_EcoModeState.eWake;
        END_IF

    E_DL_EcoModeState.eWake: // 唤醒：三条件成立先放行一拍，下一拍才转运行
        IF _bWakeGateOk AND (NOT _bReadyLatch) THEN
            _bReadyLatch := TRUE;           // 本拍放行（bReadyToRun 由出口派生为真）[Permit for this scan only]
        ELSIF _bWakeGateOk AND _bReadyLatch THEN
            IF stStat.nSwitchCount < DL_SWITCH_MAX THEN
                stStat.nSwitchCount := stStat.nSwitchCount + 1;   // 模式切换计数，本拍唯一加一 [Switch counter, single increment]
            END_IF
            stStat.tLastEco := _tEcoDur;    // 上一轮节能时长 [Last eco duration]
            IF stStat.tTotalEco < DL_TIME_MAX THEN
                stStat.tTotalEco := stStat.tTotalEco + _tEcoDur;  // 累计节能时长饱和累加 [Total eco accumulated]
            END_IF
            _bReadyLatch := FALSE;          // 转出即复位 [Reset on exit]
            _eState      := E_DL_EcoModeState.eRun;
        ELSIF NOT _bWakeGateOk THEN
            _bReadyLatch := FALSE;          // 门控失守（压力回落）则撤销放行 [Gate lost, permit revoked]
        END_IF

    E_DL_EcoModeState.eFault: // 故障：等复位沿，复位后清码回运行
        IF fbTrigReset.Q THEN
            _bFaultLatch := FALSE;          // 锁存解除 [Latch released]
            _uErrorIdInt := 16#0000_0000;   // 故障码清零 [Fault code cleared]
            _tEcoDur     := T#0S;           // 时长快照作废 [Snapshot invalidated]
            _bReadyLatch := FALSE;          // 放行锁存复位 [Permit latch reset]
            _eState      := E_DL_EcoModeState.eRun;
        END_IF

    ELSE // 非法枚举值兜底：回安全态并锁故障（节能出口由段 9 派生为假）
        _bFaultLatch := TRUE;               // 兜底锁存 [Fallback latch]
        _uErrorIdInt := DL_ERR_STATE;       // 02F2 非法状态兜底【故障级】 [Fault, illegal state]
        _eState      := E_DL_EcoModeState.eFault;
END_CASE

// ==== 段 9｜出口派生（三个节能出口与放行位全部按状态与阶段单点派生） / Outlets derived from state and stage at a single point
bAirPressureLow := FALSE;                   // 先清零再按阶段置位 [Pre-cleared, then set by stage]
bHeatStandby    := FALSE;
bServoSleep     := FALSE;

IF _eState = E_DL_EcoModeState.eEco THEN
    bAirPressureLow := TRUE;                // 第一步：先降压（伺服仍带电，防带压休眠）[Step 1: reduce pressure first]
    IF (fbTmoEco.ET >= DL_ECO_GAP1) AND bHeatStandbyPermit THEN
        bHeatStandby := TRUE;               // 第二步：降压稳定后再停热 [Step 2: heater standby after pressure settled]
    END_IF
    IF (fbTmoEco.ET >= DL_ECO_GAP2) AND bServoSleepPermit THEN
        bServoSleep := TRUE;                // 第三步：最后才允许伺服休眠 [Step 3: servo sleep last]
    END_IF
ELSIF _eState = E_DL_EcoModeState.eWake THEN
    IF fbTmoWake.ET < DL_ECO_GAP1 THEN
        bHeatStandby   := TRUE;             // 反序第一步：先撤休眠，其余保持不动作 [Reverse step 1: sleep released first]
        bAirPressureLow := TRUE;            // 压力仍处低位 [Pressure still low]
    ELSIF fbTmoWake.ET < DL_ECO_GAP2 THEN
        bAirPressureLow := TRUE;            // 反序第二步：停热已撤，压力仍低位 [Reverse step 2: heater restored, pressure low]
    END_IF
    // 反序第三步：压力请求撤除（三出口全假），由气源比例阀自行回到工作压力
END_IF

bEcoActive  := (_eState = E_DL_EcoModeState.eEco)
            OR (_eState = E_DL_EcoModeState.eWake);   // 节能与唤醒期间均视为节能投入 [Engaged during eco and wake]

bReadyToRun := (_eState = E_DL_EcoModeState.eRun)
            OR _bReadyLatch;                // 运行态恒可运行；唤醒态须放行锁存已置 [Ready in run, or when latched in wake]

IF _eState = E_DL_EcoModeState.eWake THEN
    tEcoElapsed := _tEcoDur;                // 唤醒期间显示本轮节能已持续时长 [Show the finished eco duration]
ELSE
    tEcoElapsed := fbTmoEco.ET;             // 其余时段按节能定时器已历时 [Eco timer elapsed otherwise]
END_IF
tIdleElapsed := fbTmoIdle.ET;               // 空闲确认已计时长 [Idle confirmation elapsed]

eState := _eState;                          // 状态镜像 [State mirror]
bError := _bFaultLatch;                     // 故障级派生式（R21）[Fault-level derived form]
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;               // 故障级码优先透出 [Fault code wins]
ELSE
    uErrorId := _uInfoCode;                 // 无故障时透出信息级码 [Info code otherwise]
END_IF

// ==== 段 10｜现场提示（调试与验收要点，不参与逻辑） / Field notes, no logic impact
//   1 三个节能出口均为派生式：任何时刻读到的值都与当前状态严格一致，不存在「已撤
//     状态但出口还挂着」的中间态，这是排查「节能撤不掉」类问题的前提；
//   2 进入节能后第一步只降压，停热与休眠各隔一个台阶（默认 500 毫秒），台阶时长
//     由常量给定，若现场气源响应慢，改常量而不是在逻辑里加延时；
//   3 唤醒超时取缓冲的两倍：一倍用于压力恢复，另一倍留给比例阀回差与管路充气，
//     超过两倍仍未达压说明气源或阀件有问题，此时锁故障比继续等待更有价值；
//   4 切换次数在节能转出拍加一，与累计时长同一拍结算，两者可在上位机互校。
END_FUNCTION_BLOCK
