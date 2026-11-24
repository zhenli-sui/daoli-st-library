(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AgvDockingHandshake
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 工站模板 · 移动载体对接交接
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
 *                         仅依赖标准库（TON / R_TRIG / F_TRIG），握手信号全部为布尔
 *                         引脚注入，块内不含任何车辆调度、导航或总线通讯细节
 * 功能描述 (Function)   : 把「到位检测 → 双侧就绪握手 → 交接放行 → 完成确认」做成带
 *                         超时与失序诊断的交接状态机，屏蔽移动载体与固定工站两侧的
 *                         信号时序差异，产出单一放行位与握手成功单拍脉冲
 * 与既有件边界 (Scope)  : 固定段之间的连续物流握手（成组上下游节拍链）由输送链路件
 *                         承担，属长连接；本件面向移动载体与固定工站的临时对接（会话
 *                         式、一次性），握手条件含「物料在位」与「双侧就绪」双约束，
 *                         语义与生命周期都不同，不可互替
 * 状态机规模 (States)   : 七态（eIdle 0 / eWaitArrive 10 / eDockConfirm 20 /
 *                         ePermitTransfer 30 / eTransferMonitor 40 / eComplete 50 /
 *                         eFault 99）；编号留 10 间隔便于插态
 * 关键算法 (Algorithm)  :
 *   ① 到位稳定：到位信号须连续两个扫描周期为真才推进，滤掉光电单拍毛刺
 *   ② 双侧就绪：两侧就绪位须同时为真且连续两拍成立，避免单拍毛刺直接放行
 *   ③ 物料一致性：进入交接监视时快照物料在位位；过程中该位由真转假且完成确认尚未
 *      到达，即判物料丢失或错位（02E2），因为这属于「该在的时候不在」
 *   ④ 完成判定：完成确认上升沿 → 置完成保持位、对接次数累加、撤放行、出握手单拍
 *   ⑤ 失序诊断：完成确认在到位或握手阶段提前到达，属非法请求序列（02E3），直接锁
 *      故障而不吞掉，否则上游误接线会被解释成「一次成功交接」
 *   ⑥ 状态停留时长：用「状态未变则计时、状态一变即清零」的单一秒表实现，供现场
 *      判读卡在哪个阶段，不额外增加引脚
 * 码位表 (Error codes)  :
 *   16#0005_01C3【信息级】超时参数越界已钳位，不置故障位
 *   16#0005_02E0【故障级】到位确认超时
 *   16#0005_02E1【故障级】握手或交接超时（两处共用，均属未在期望时间内建立期望状态）
 *   16#0005_02E2【故障级】物料在位信号丢失
 *   16#0005_02E3【故障级】非法请求序列（完成确认提前到达）
 *   16#0005_02E4【故障级】非法状态兜底
 * R32 写入点次序审计 :
 *   bTransferComplete : ① 待机启动拍清（eIdle）→ ② 交接监视完成拍置（eTransferMonitor
 *                       ，唯一置位点）。保持特性由「不再写」实现，不设第三处写点
 *   _uErrorIdInt      : ① 首扫清（段 4）→ ② 到位超时（eWaitArrive）→ ③ 握手/交接超时
 *                       （eDockConfirm 与 eTransferMonitor 各一处，同拍只命中一处）
 *                       → ④ 物料丢失（eTransferMonitor）→ ⑤ 失序（段 5）→ ⑥ 非法状态
 *                       （ELSE）→ ⑦ 复位清（eFault）
 *   _eState           : 每拍只在 CASE 分支出口单点写入；CASE 之外仅两处（段 5 失序监视、
 *                       段 6 中止与使能撤销），均在 CASE 之前，次序固定
 *   _bMatSnap         : ① 交接监视入口快照（ePermitTransfer 转出拍）→ ② 完成与复位清
 *   tElapsed          : 仅段 10 单点派生（秒表已历时），状态机内不写
 * 设计偏离登记 (Deviations) :
 *   D1 bHandshakeOk 取「握手成功」口径，在进入放行态那一拍出脉冲；规格验收向量 V1 把
 *      该脉冲写在完成确认之后叙述，二者不冲突——脉冲发生在交接放行时刻，完成确认只
 *      负责置完成保持位，头注释按状态迁移表口径落地
 *   D2 到位与双侧就绪用「连续两拍」替代「沿后与门」等价实现，效果相同（滤单拍毛刺），
 *      但不需要额外的边沿实例，拍序更易推演
 * 验收向量 (Acceptance) :
 *   V1 正常序：到位 → 双侧就绪依序为真 → 放行位为真、握手单拍、完成确认后完成保持位
 *      为真且对接次数加一
 *   V2 到位超时：超时窗 10 秒内到位信号未建立 → 码 02E0、故障态
 *   V3 物料丢失：交接监视内物料在位由真转假且完成确认为假 → 码 02E2、放行位撤
 *   V4 完成提前：到位阶段完成确认为真 → 码 02E3、直接故障态
 *   V5 统计：交接监视停留 12 秒、监视超时 30 秒 → 上一轮时长 12 秒、累计加 12 秒
 * 开源溯源 (Origin)     : 参考包装机械与批控公开手册的「会话式交接」阶段划分与双侧
 *                         就绪语义组织，只借阶段分类与参数域；状态机、快照一致性判据、
 *                         失序诊断、码位与引脚契约为本库独立设计，clean-room 不构成
 *                         衍生作品
 * 红线自检 (Redline)    : R1 零全局表与外部变量引用、零物理地址记号 ✓｜R2 零占位符 ✓
 *                         R3 纯 IEC 61131-3 加标准库 ✓｜R4 时长比较带零值旁路、计数
 *                         饱和、无数组访问 ✓｜R5 声明行中英双语同行注释 ✓｜R6 七成员
 *                         逐一有 CASE 标签且含 ELSE 兜底 ✓｜R7 三沿检测与四定时器全
 *                         部在 CASE 之外无条件刷新 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 11 · C 泳道 · 工站四件套之三）
 *   2026-11-16  v1.0.1  R13 机检 R39 修复：段 5 使能撤销分支原先把 _eState 无条件
 *                       改写为 eIdle，而故障复位沿的消化位于其后 CASE 的 eFault
 *                       分支——禁用期间按下的复位沿当拍被抹掉，_bFaultLatch 与
 *                       故障码留存至操作员补按第二次复位，期间使能回升也被
 *                       「有锁存」判据挡在待机。改为 eFault 态不被禁用覆盖
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_AgvDockState（归属 FB_DL_AgvDockingHandshake，同文件发布）
 *   七态，每个成员在主状态机中均有同名 CASE 标签（R31 完备性）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_AgvDockState :
(
    eIdle            := 0,  // 待机：等到位信号 / Idle, awaiting arrival signal
    eWaitArrive      := 10, // 到位确认：等到位信号稳定 / Arrival confirmation, waiting for a stable signal
    eDockConfirm     := 20, // 对接确认：等双侧就绪同时成立 / Dock confirmation, waiting for both sides ready
    ePermitTransfer  := 30, // 放行交接：单拍过渡态 / Transfer permit, a single-scan transition state
    eTransferMonitor := 40, // 交接监视：等完成确认并监视物料在位 / Transfer monitor, watching completion and material
    eComplete        := 50, // 交接完成：保持一拍后回待机 / Complete, holds one scan then returns
    eFault           := 99  // 故障锁存：仅复位沿可退 / Fault latched, only a reset edge leaves
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_AgvDockStat（归属 FB_DL_AgvDockingHandshake）
 *   跨周期统计，由调用方持有，本块只累加，掉电保持由上层负责
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_AgvDockStat :
STRUCT
    nDockCount     : UDINT;                 // 累计成功对接次数 [次] [Docking counter]
    tTotalTransfer : TIME;                  // 累计交接时长 [毫秒] [Accumulated transfer time]
    tLastCycle     : TIME;                  // 上一轮交接时长 [毫秒] [Last transfer duration]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_AgvDockingHandshake
VAR_INPUT
    bEnable           : BOOL;               // 使能，FALSE 撤回全部放行位 [Enable, withdraws all permits on FALSE]
    bReset            : BOOL;               // 复位故障，上升沿受理 [Reset fault on rising edge]
    bAbort            : BOOL;               // 中止本次交接，上升沿受理，不置故障 [Abort the handshake on rising edge, no fault]
    bAgvArrived       : BOOL;               // 载体到位光电（粗定位）[-] [Carrier presence sensor]
    bAgvDockReady     : BOOL;               // 载体侧对接机构就绪 [-] [Carrier-side dock ready]
    bStationReady     : BOOL;               // 工站侧可收料或可放料 [-] [Station-side ready]
    bMaterialOnAgv    : BOOL;               // 物料在位，交接前为载侧、交接后为站侧 [-] [Material present flag]
    bTransferDone     : BOOL;               // 下游完成接收确认 [-] [Downstream receipt confirmation]
    tArriveTimeout    : TIME := T#10S;      // 到位确认超时 [毫秒]，0 表示不监控 [Arrival timeout]
    tHandshakeTimeout : TIME := T#5S;       // 双侧就绪握手超时 [毫秒]，0 表示不监控 [Handshake timeout]
    tTransferTimeout  : TIME := T#30S;      // 交接过程超时 [毫秒]，0 表示不监控 [Transfer timeout]
END_VAR
VAR_OUTPUT
    bDockLamp         : BOOL;               // 对接允许指示灯，载体可进入 [-] [Dock-permitted lamp]
    bTransferPermit   : BOOL;               // 放行交接，可放料或可接料 [-] [Transfer permit]
    bHandshakeOk      : BOOL;               // 握手成功单拍脉冲 [-] [Single pulse when handshake succeeds]
    bTransferComplete : BOOL;               // 交接完成，保持到下次启动 [Transfer complete, held until next cycle]
    eState            : E_DL_AgvDockState;  // 主状态机当前态 [-] [Current state]
    bError            : BOOL;               // 故障锁存，需复位清除 [Latched fault]
    uErrorId          : UDINT;              // 事件码或故障码，0 表示无 [Event or fault code]
    tElapsed          : TIME;               // 当前态已耗时 [毫秒]，现场判读用 [Elapsed time in current state]
END_VAR
VAR_IN_OUT
    stStat            : ST_DL_AgvDockStat;  // 跨周期统计，调用方持有 [Persistent statistics]
END_VAR
VAR
    _eState          : E_DL_AgvDockState := E_DL_AgvDockState.eIdle;  // 内部状态寄存器，唯一真值源 [Internal state register]
    _eStateIn        : E_DL_AgvDockState := E_DL_AgvDockState.eIdle;  // 上拍状态，用于识别迁移拍 [Previous state of last scan]
    _bInit           : BOOL := FALSE;       // 首扫标志，初值 FALSE，判据 NOT _bInit [First-scan flag, R19 pattern]
    _bFaultLatch     : BOOL;                // 故障级锁存，仅复位路径清 [Fault latch, reset path only]
    _uErrorIdInt     : UDINT;               // 故障级码寄存 [Fault-level code register]
    _uInfoCode       : UDINT;               // 本拍信息级码，每拍重算 [Transient info code]
    _bStateChg       : BOOL;                // 本拍发生过状态迁移，秒表清零用 [State changed this scan]
    _bArrivePrev     : BOOL;                // 上位到位信号，稳定判据用 [Arrival signal of last scan]
    _bBothReadyPrev  : BOOL;                // 上拍双侧就绪，稳定判据用 [Both-ready of last scan]
    _bMatSnap        : BOOL;                // 交接入口物料在位快照 [Material snapshot at monitor entry]
    tArriveEff       : TIME;                // 生效到位超时 [毫秒] [Effective arrival timeout]
    tHandEff         : TIME;                // 生效握手超时 [毫秒] [Effective handshake timeout]
    tTranEff         : TIME;                // 生效交接超时 [毫秒] [Effective transfer timeout]
    tMoniEff         : TIME;                // 本次交接监视时长（钳位后）[毫秒] [Clamped monitor duration]
    bArriveIn        : BOOL;                // 到位计时输入条件，先算后调 [Arrival timer input]
    bHandIn          : BOOL;                // 握手计时输入条件，先算后调 [Handshake timer input]
    bTranIn          : BOOL;                // 交接计时输入条件，先算后调 [Transfer timer input]
    fbTrigReset      : R_TRIG;              // 复位沿检测 [Reset edge detector]
    fbTrigAbort      : R_TRIG;              // 中止沿检测 [Abort edge detector]
    fbTrigDone       : R_TRIG;              // 完成确认上升沿 [Completion rising edge]
    fbTrigMateria    : F_TRIG;              // 物料在位下降沿，丢失诊断用 [Material falling edge, loss diagnosis]
    fbTmoArrive      : TON;                 // 到位确认计时 [Arrival timer]
    fbTmoHandshake   : TON;                 // 双侧就绪握手计时 [Handshake timer]
    fbTmoTransfer    : TON;                 // 交接过程计时 [Transfer timer]
    fbTmoState       : TON;                 // 状态停留秒表 [State elapsed stopwatch]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : REAL := 1.0E-6;      // 浮点判等容差（预留）[-] [Float comparison epsilon]
    DL_STAT_MAX      : UDINT := 16#FFFF_FFFE; // 统计计数饱和上限 [次] [Statistics saturation limit]
    DL_TMO_MAX       : TIME := T#600S;      // 超时参数域上限 [毫秒] [Timeout upper bound]
    DL_TMAX_STATE    : TIME := T#24H;       // 状态秒表量程 [毫秒] [State stopwatch range]
    DL_TIME_MAX      : TIME := T#500H;     // 累计时长饱和上限 [毫秒] [Duration saturation limit]
    DL_INFO_TMO_CLAMP: UDINT := 16#0005_01C3; // 01C3 超时参数越界已钳位【信息级】 [Info, timeout clamped]
    DL_ERR_ARRIVE    : UDINT := 16#0005_02E0; // 02E0 到位确认超时【故障级】 [Fault, arrival timeout]
    DL_ERR_HANDSHAKE : UDINT := 16#0005_02E1; // 02E1 握手或交接超时【故障级】 [Fault, handshake or transfer timeout]
    DL_ERR_MATERIAL  : UDINT := 16#0005_02E2; // 02E2 物料在位信号丢失【故障级】 [Fault, material lost]
    DL_ERR_SEQUENCE  : UDINT := 16#0005_02E3; // 02E3 非法请求序列【故障级】 [Fault, illegal request sequence]
    DL_ERR_STATE     : UDINT := 16#0005_02E4; // 02E4 非法状态兜底【故障级】 [Fault, illegal state]
END_VAR

// ==== 段 1｜单拍输出预清零（握手脉冲每拍先清零，置位点唯一） / Single-scan pulse pre-clear, single set point
bHandshakeOk := FALSE;                      // 握手单拍先清零 [Handshake pulse pre-cleared]
_uInfoCode   := 16#0000_0000;               // 信息级码每拍重算 [Info code recomputed]

// ==== 段 2｜超时参数钳位（三个超时统一钳位，零值表示不监控） / Timeout clamping, zero disables supervision
tArriveEff := tArriveTimeout;               // 到位超时先取引脚值 [Arrival timeout from pin]
IF tArriveEff > DL_TMO_MAX THEN
    tArriveEff := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
    _uInfoCode := DL_INFO_TMO_CLAMP;        // 01C3 超时参数越界已钳位【信息级】 [Info, timeout clamped]
ELSIF tArriveEff < T#0S THEN
    tArriveEff := T#0S;                     // 负值归零即不监控 [Negative means disabled]
END_IF

tHandEff := tHandshakeTimeout;              // 握手超时先取引脚值 [Handshake timeout from pin]
IF tHandEff > DL_TMO_MAX THEN
    tHandEff   := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
    _uInfoCode := DL_INFO_TMO_CLAMP;        // 01C3 超时参数越界已钳位【信息级】 [Info, timeout clamped]
ELSIF tHandEff < T#0S THEN
    tHandEff := T#0S;                       // 负值归零即不监控 [Negative means disabled]
END_IF

tTranEff := tTransferTimeout;               // 交接超时先取引脚值 [Transfer timeout from pin]
IF tTranEff > DL_TMO_MAX THEN
    tTranEff   := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
    _uInfoCode := DL_INFO_TMO_CLAMP;        // 01C3 超时参数越界已钳位【信息级】 [Info, timeout clamped]
ELSIF tTranEff < T#0S THEN
    tTranEff := T#0S;                       // 负值归零即不监控 [Negative means disabled]
END_IF

// ==== 段 3｜沿与定时器无条件刷新（R7 红线：严禁置于 IF / CASE 分支内） / Unconditional refresh of edges and timers
fbTrigReset(CLK := bReset);                 // 复位沿 [Reset edge]
fbTrigAbort(CLK := bAbort);                 // 中止沿 [Abort edge]
fbTrigDone(CLK := bTransferDone);           // 完成确认上升沿 [Completion rising edge]
fbTrigMateria(CLK := bMaterialOnAgv);       // 物料在位下降沿 [Material falling edge]

IF (_eState = E_DL_AgvDockState.eWaitArrive) AND (tArriveEff > T#0S) THEN
    bArriveIn := TRUE;                      // 仅到位段且监控开启时计时 [Only while waiting with supervision on]
ELSE
    bArriveIn := FALSE;                     // 其余段清零 [Cleared otherwise]
END_IF
fbTmoArrive(IN := bArriveIn, PT := tArriveEff);

IF (_eState = E_DL_AgvDockState.eDockConfirm) AND (tHandEff > T#0S) THEN
    bHandIn := TRUE;                        // 仅握手段且监控开启时计时 [Only while confirming with supervision on]
ELSE
    bHandIn := FALSE;                       // 其余段清零 [Cleared otherwise]
END_IF
fbTmoHandshake(IN := bHandIn, PT := tHandEff);

IF (_eState = E_DL_AgvDockState.eTransferMonitor) AND (tTranEff > T#0S) THEN
    bTranIn := TRUE;                        // 仅交接段且监控开启时计时 [Only while monitoring with supervision on]
ELSE
    bTranIn := FALSE;                       // 其余段清零 [Cleared otherwise]
END_IF
fbTmoTransfer(IN := bTranIn, PT := tTranEff);

// 状态秒表：本拍未发生迁移才计时；迁移后的下一拍输入断一拍，已历时清零（时基由定时器内部保证）
fbTmoState(IN := (NOT _bStateChg) AND bEnable, PT := DL_TMAX_STATE);

// ==== 段 4｜首扫初始化（R19 唯一合法范式：初值 FALSE，判据 NOT，同步后置 TRUE） / First-scan initialisation with the canonical R19 pattern
IF NOT _bInit THEN
    _eState          := E_DL_AgvDockState.eIdle;  // 状态回待机 [State to idle]
    _eStateIn        := E_DL_AgvDockState.eIdle;  // 上拍状态同步 [Previous state synced]
    _bFaultLatch     := FALSE;              // 故障锁存清零 [Fault latch cleared]
    _uErrorIdInt     := 16#0000_0000;       // 故障码清零 [Fault code cleared]
    _bStateChg       := FALSE;              // 迁移标志清零 [State change flag cleared]
    _bArrivePrev     := FALSE;              // 到位上拍值清零 [Arrival previous cleared]
    _bBothReadyPrev  := FALSE;              // 双侧就绪上拍值清零 [Both-ready previous cleared]
    _bMatSnap        := FALSE;              // 物料快照清零 [Material snapshot cleared]
    bDockLamp        := FALSE;              // 指示灯灭 [Lamp off]
    bTransferPermit  := FALSE;              // 放行撤 [Permit withdrawn]
    bTransferComplete := FALSE;             // 完成保持位清 [Complete flag cleared]
    bError           := FALSE;              // 故障标志清零 [Error cleared]
    uErrorId         := 16#0000_0000;       // 事件码清零 [Error id cleared]
    tElapsed         := T#0S;               // 状态耗时清零 [Elapsed cleared]
    stStat.nDockCount     := 0;             // 对接次数清零 [Dock counter cleared]
    stStat.tTotalTransfer := T#0S;          // 累计交接时长清零 [Total transfer cleared]
    stStat.tLastCycle     := T#0S;          // 上轮时长清零 [Last cycle cleared]
    _bInit := TRUE;                         // 首扫只做一次 [Runs exactly once]
END_IF

// ==== 段 5｜全局监视：中止优先，其次失序诊断（完成确认在到位或握手阶段提前到达） / Abort first, then out-of-sequence diagnosis
IF fbTrigAbort.Q AND bEnable
AND (_eState <> E_DL_AgvDockState.eIdle)
AND (_eState <> E_DL_AgvDockState.eFault) THEN
    _bMatSnap         := FALSE;             // 快照作废（放行由出口按状态派生，不在此重复写）[Snapshot invalidated]
    _eState           := E_DL_AgvDockState.eIdle;   // 回待机，不置故障 [Back to idle, no fault]
END_IF

IF bEnable AND (NOT _bFaultLatch) AND bTransferDone
AND ((_eState = E_DL_AgvDockState.eWaitArrive) OR (_eState = E_DL_AgvDockState.eDockConfirm)) THEN
    _bFaultLatch := TRUE;                   // 失序锁存 [Sequence fault latched]
    _uErrorIdInt := DL_ERR_SEQUENCE;        // 02E3 非法请求序列【故障级】 [Fault, illegal sequence]
    _eState      := E_DL_AgvDockState.eFault;
END_IF

// ==== 段 5 之三｜使能撤销回待机（eFault 除外：复位沿的消化权归 CASE 的 eFault 分支） / Disable returns to idle, the fault state keeps its reset edge
// R39 纪律：复位沿只在发生的那一拍为真，eFault 分支是唯一清除 _bFaultLatch 与故障码
// 的出口。若本分支无条件改写 _eState，禁用期间按下的复位沿当拍被抹掉（CASE 落到 eIdle
// 分支，其判据要求 bEnable 为真，复位判据摸不到），锁存留存且二次复位才清。
// R39: the reset edge lives one scan and is only consumed inside the eFault branch, so
// the disable override must not pre-empt it, otherwise a reset pressed while disabled
// is lost and the fault latch survives until a second press.
IF (NOT bEnable) AND (_eState <> E_DL_AgvDockState.eFault) THEN
    _eState          := E_DL_AgvDockState.eIdle;   // 使能撤销回待机（放行与灯由出口派生）[Disable returns to idle]
    _bMatSnap        := FALSE;              // 快照作废 [Snapshot invalidated]
END_IF

// ==== 段 6｜主状态机（ENUM 加 CASE 加 ELSE 兜底，七成员逐一有标签） / Main state machine, every member has its own label
CASE _eState OF
    E_DL_AgvDockState.eIdle: // 待机：载体到位且使能即进入到位确认
        IF bEnable AND bAgvArrived AND (NOT _bFaultLatch) THEN
            bTransferComplete := FALSE;     // 新会话开始，清上一轮完成保持位 [Clear last completion]
            _uErrorIdInt      := 16#0000_0000;  // 启动前必无故障 [No fault before start]
            _bArrivePrev      := TRUE;      // 到位已成立，稳定判据起点 [Arrival already true]
            _bBothReadyPrev   := FALSE;     // 双侧就绪起点复位 [Both-ready starts false]
            _eState           := E_DL_AgvDockState.eWaitArrive;
        END_IF

    E_DL_AgvDockState.eWaitArrive: // 到位确认：信号连续两拍为真才推进
        IF (NOT bAgvArrived) THEN
            _eState := E_DL_AgvDockState.eIdle;   // 载体离开，回待机 [Carrier left, back to idle]
        ELSIF _bArrivePrev AND bAgvArrived THEN
            _eState := E_DL_AgvDockState.eDockConfirm;
        ELSIF fbTmoArrive.Q THEN
            _bFaultLatch := TRUE;           // 超时锁存 [Timeout latched]
            _uErrorIdInt := DL_ERR_ARRIVE;  // 02E0 到位确认超时【故障级】 [Fault, arrival timeout]
            _eState      := E_DL_AgvDockState.eFault;
        END_IF

    E_DL_AgvDockState.eDockConfirm: // 对接确认：双侧就绪同时成立且连续两拍
        IF (NOT bAgvArrived) THEN
            _eState := E_DL_AgvDockState.eIdle;   // 载体离开，回待机 [Carrier left, back to idle]
        ELSIF bAgvDockReady AND bStationReady AND _bBothReadyPrev THEN
            bHandshakeOk := TRUE;           // 握手成功单拍，本拍唯一置位点 [Sole set point of the pulse]
            _bMatSnap    := bMaterialOnAgv; // 交接前物料在位快照 [Snapshot before transfer]
            _eState      := E_DL_AgvDockState.ePermitTransfer;
        ELSIF fbTmoHandshake.Q THEN
            _bFaultLatch := TRUE;           // 超时锁存 [Timeout latched]
            _uErrorIdInt := DL_ERR_HANDSHAKE;  // 02E1 握手或交接超时【故障级】 [Fault, handshake timeout]
            _eState      := E_DL_AgvDockState.eFault;
        END_IF

    E_DL_AgvDockState.ePermitTransfer: // 放行交接：单拍过渡，把放行与监视分开便于现场观察
        _eState := E_DL_AgvDockState.eTransferMonitor;   // 放行由出口按状态派生 [Permit derived from state]

    E_DL_AgvDockState.eTransferMonitor: // 交接监视：等完成确认，同时监视物料在位
        IF fbTrigDone.Q THEN
            bTransferComplete := TRUE;      // 完成保持，本拍唯一置位点 [Sole set point of the flag]
            IF stStat.nDockCount < DL_STAT_MAX THEN
                stStat.nDockCount := stStat.nDockCount + 1;   // 对接次数饱和累加 [Dock counter, saturated]
            END_IF
            IF fbTmoTransfer.ET > tTranEff THEN
                tMoniEff := tTranEff;       // 异常值按超时上限钳位，防污染均值 [Clamp abnormal duration]
            ELSE
                tMoniEff := fbTmoTransfer.ET;
            END_IF
            stStat.tLastCycle := tMoniEff;  // 上一轮交接时长 [Last transfer duration]
            IF stStat.tTotalTransfer < DL_TIME_MAX THEN
                stStat.tTotalTransfer := stStat.tTotalTransfer + tMoniEff;  // 累计交接时长 [Total transfer accumulated]
            END_IF
            _bMatSnap := FALSE;             // 快照用毕作废 [Snapshot consumed]
            _eState   := E_DL_AgvDockState.eComplete;
        ELSIF _bMatSnap AND fbTrigMateria.Q THEN
            _bFaultLatch := TRUE;           // 物料该在时不在，锁故障 [Material lost, fault latched]
            _uErrorIdInt := DL_ERR_MATERIAL;   // 02E2 物料在位信号丢失【故障级】 [Fault, material lost]
            _eState      := E_DL_AgvDockState.eFault;
        ELSIF fbTmoTransfer.Q THEN
            _bFaultLatch := TRUE;           // 超时锁存 [Timeout latched]
            _uErrorIdInt := DL_ERR_HANDSHAKE;  // 02E1 握手或交接超时【故障级】 [Fault, transfer timeout]
            _eState      := E_DL_AgvDockState.eFault;
        END_IF

    E_DL_AgvDockState.eComplete: // 完成：保持一拍后回待机，完成保持位由 eIdle 下场会话清
        IF bAgvArrived THEN
            _bArrivePrev := TRUE;           // 载体仍在位，为下一轮预置 [Carrier still present for the next cycle]
        ELSE
            _bArrivePrev := FALSE;
        END_IF
        _eState := E_DL_AgvDockState.eIdle;

    E_DL_AgvDockState.eFault: // 故障：等复位沿，复位后清码回待机
        IF fbTrigReset.Q THEN
            _bFaultLatch := FALSE;          // 锁存解除 [Latch released]
            _uErrorIdInt := 16#0000_0000;   // 故障码清零 [Fault code cleared]
            _bMatSnap    := FALSE;          // 快照作废 [Snapshot invalidated]
            _eState      := E_DL_AgvDockState.eIdle;
        END_IF

    ELSE // 非法枚举值兜底：回安全态并锁故障（放行由出口按状态派生为假）
        _bFaultLatch    := TRUE;            // 兜底锁存 [Fallback latch]
        _uErrorIdInt    := DL_ERR_STATE;    // 02E4 非法状态兜底【故障级】 [Fault, illegal state]
        _eState         := E_DL_AgvDockState.eFault;
END_CASE

// ==== 段 7｜稳定判据与迁移寄存器更新（每次扫描末统一更新，供下一拍判稳定与秒表清零） / Stability registers updated at scan end
_bBothReadyPrev := bAgvDockReady AND bStationReady;   // 双侧就绪上拍值 [Both-ready of this scan]
IF (_eState = E_DL_AgvDockState.eWaitArrive) THEN
    _bArrivePrev := bAgvArrived;            // 到位上拍值（仅到位段跟踪）[Arrival tracked while waiting]
END_IF
_bStateChg := (_eState <> _eStateIn);       // 本拍是否迁移 [Transition happened this scan]
_eStateIn  := _eState;                      // 迁移寄存器同步 [Previous state synced]

// ==== 段 8｜出口派生（指示灯、放行、耗时均在此单点派生） / Outlets derived at a single point
bDockLamp := (_eState = E_DL_AgvDockState.eWaitArrive)
          OR (_eState = E_DL_AgvDockState.eDockConfirm);   // 对接期间指示灯亮 [Lamp on while docking]

IF (_eState = E_DL_AgvDockState.ePermitTransfer)
OR (_eState = E_DL_AgvDockState.eTransferMonitor) THEN
    bTransferPermit := TRUE;                // 交接期间放行（与状态同源，杜绝双写冲突）[Permit while transferring]
ELSE
    bTransferPermit := FALSE;
END_IF

tElapsed := fbTmoState.ET;                  // 状态停留时长 [Elapsed in current state]

eState := _eState;                          // 状态镜像 [State mirror]
bError := _bFaultLatch;                     // 故障级派生式（R21）[Fault-level derived form]
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;               // 故障级码优先透出 [Fault code wins]
ELSE
    uErrorId := _uInfoCode;                 // 无故障时透出信息级码 [Info code otherwise]
END_IF
END_FUNCTION_BLOCK
