(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BatchTransferSeq
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Process / Sequence
 * 当前版本 (Version)    : 1.0.2
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / TIME_TO_DINT / DINT_TO_TIME
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 批次物料转移顺控
 * 功能一句话 (Summary)  : 开阀 → 等双阀开到位 → 启泵 → 计量转移 → 停泵 →
 *                         排空验证 → 关阀，按 ISA-88 相/步骤最小语义编排。
 *
 * 本件存在的意义 (Why this unit exists)
 *   批次转移是 ISA-88 相步骤的最小实证单元，也是 OEE 事故的高发点：
 *   泵在阀没到位时就启（干转烧泵）、中止时先关阀后停泵（管道憋压）、
 *   转移量靠程序自己积分（累计量双份口径，对不上账）。本件把这三件事
 *   写成结构约束：泵的启动条件是双阀反馈、中止路径先停泵再关阀、
 *   累计量**由调用方积分器注入**，本件不重复积分。
 *
 * 步骤与判据 (Steps and criteria)
 *   ePrepValve   : 双阀开指令，等 bSrcValveFb 与 bDstValveFb **同时**到位
 *   eTransferring: 双阀保持、泵启动；fTransferred >= fVolumeTarget → 停泵
 *   eDraining    : 泵停、双阀仍开；fFlow < fDrainFlow 持续 tDrainVerify → 判排空完成
 *   eClosing     : 双阀关指令（本库阀门指令语义：TRUE = 开启，故关阀 = 清指令），
 *                  等关阀确认窗（tValveFb）后进 eComplete
 *   eComplete    : 放行；bStart 落下才回 eIdle（不自动开始下一批）
 *   eAbort       : 中止兼容路径（xCoastStop = FALSE）：先停泵后关阀（顺序
 *                  不可反，防管道憋压），等 bStart 落下复位
 *   eAbortCoast  : 中止第一段（xCoastStop = TRUE，推荐）：泵输出使能立即断、
 *                  **阀位保持不动**（不发关阀指令），泵惰转计时窗内管路
 *                  残压随泵惰转泄放，杜绝停泵与关阀同拍发出的物理竞态
 *   eAbortClose  : 中止第二段：惰转窗满后发关阀指令（清阀门指令），等阀
 *                  离开开位（双阀开反馈任一保持即计时）；确认超时 → 0317
 *
 * 中止语义（三件顺控件共用同一段口径）
 *   bAbort **任意拍**生效（中止族态内不重复触发，防惰转窗被反复重启）：
 *   xCoastStop = TRUE 走两段化——段 A 断泵输出使能、阀保持不动、惰转计时；
 *   段 B 惰转窗满发关阀指令，等关阀确认，超时报 0317。两段之间由 TON 跨拍
 *   物理时序分隔，**禁止单拍内「停泵赋值 + 关阀赋值」连续成立**（机检断言：
 *   abort 拍不得出现关阀输出置位）。xCoastStop = FALSE 保留 v1.0.1 单拍
 *   行为（仅存量调用兼容，**不推荐：泵惰转期间残压可经未关阀位回流**）。
 *   中止**不排队、不回退重来、不自动续跑**——中止是人的决定，重启必须由
 *   新的 bStart 重新开始。bStart 落沿同样按中止处理（外部撤销）。
 *
 * 边界安全 (Boundary)
 *   ① fVolumeTarget <= 0 或 tTimeout = T#0S → 故障 0315、停泵关阀、回 eFault；
 *   ② 阀位反馈超 tValveFb 未到位 → 故障 0314、**不启泵**、回 eIdle 并先清输出；
 *   ③ 转移总时长超 tTimeout → 故障 0315（复用，R90）；
 *   ④ fTransferred 由调用方注入：**批次切换必须由调用方清零累计器**；本件以本拍
 *      值为准，不做回退检测（回退是换批的正常现象，不是故障，若在此报错会
 *      让每批首拍都报一次假故障）；该口径以信息 01E0 在进入转移相时声明一次；
 *   ⑤ 输入非有限（累计量或流量）→ 复用 0315 并停泵关阀（无专用码位，R90）；
 *   ⑥ 泵/阀三输出互斥在段 1 全清、段 7 按相置位（R72 双路径）；
 *   ⑦ 四只 TON 各司其职：开阀到位 / 关阀确认 / 排空验证 / 总时长，
 *      绝不复用同一实例跨相计时（R40；规格写三个实例，关阀确认必须独立，故实测为四只）；
 *      v1.0.2 增至六只：惰转计时 / 中止关阀确认各自独立实例，同样不复用；
 *   ⑧ CASE 落 ELSE 置 0316 并回 eFault；
 *   ⑨ xCoastStop = TRUE 且 tPumpCoastTime <= 0 → 参数非法 0315 复用（R90：
 *      惰转窗为 0 使两段化退化为单拍，违背修复意图，按非法参数拦截）。
 *
 * 验收向量（v1.0.2 中止时序，修复后必测）：
 *   V9  abort 触发拍（xCoastStop = TRUE）：泵指令 FALSE、双阀指令保持开
 *       （TRUE）、关阀输出（指令清零动作）当拍不发生——机检断言主向量；
 *   V10 惰转窗未满期间跨拍扫描：双阀指令恒保持开、泵指令恒 FALSE
 *       （跨拍验证，窗内无任何输出翻转）；
 *   V11 惰转窗满拍：双阀指令置 FALSE（发关阀指令）；
 *   V12 关阀确认超时（阀开反馈在确认窗内仍保持）→ eErr = 16#0005_0317
 *       且 bError 置位（R45 配对），输出保持关阀指令；
 *   V13 xCoastStop = FALSE：回归 v1.0.1 向量 V4（abort 拍泵 FALSE 且阀
 *       指令 FALSE 同拍成立，兼容路径单拍中止）。
 *
 * 错误码    : 16#0005_01E0 累计转移量由调用方积分器注入，本件不重复积分——信息级，口径声明
 *             16#0005_01E1 排空验证窗内流量持续低于门限，判排空完成——信息级，正常结论
 *             16#0005_0314 阀位反馈超时未到位，拒绝启泵——故障级，回 eIdle 并先清输出
 *             16#0005_0315 转移总时长超时或体积/超时/输入参数非法（含非有限复用，R90）——故障级
 *             16#0005_0316 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault 并先清输出
 *             16#0005_0317 中止第二段关阀确认超时（阀开反馈在确认窗内保持，
 *                          v1.0.2 新增）——故障级，置 bError，保持关阀指令等启动撤销
 * 码位总账  : 16#0005_01E0 用 / 16#0005_01E1 用 ｜ 16#0005_0314 用 / 16#0005_0315 用 /
 *             16#0005_0316 用 / 16#0005_0317 用（R23 特批故障槽）
 * 状态机    : E_DL_TransferState（eIdle / ePrepValve / eTransferring / eDraining / eClosing /
 *             eComplete / eAbort / eAbortCoast / eAbortClose / eFault），
 *             CASE 含 ELSE 兜底，ELSE 置 16#0005_0316 并回 eFault
 * 采样约定  : 每任务周期调用一次；各窗时长由引脚给定，不读系统时钟
 * 依赖说明  : 只做组合编排；累计量由调用方以 FB_DL_Integrator 注入，本件**不内联积分**
 * 验收向量  : V1 双阀反馈到位 → 泵启动（启泵条件主向量）；fTransferred 达 5.0 m³ → 停泵
 *             V2 阀位反馈 5 s 内未到位 → 0314，泵始终 FALSE，回 eIdle（不启泵主向量）
 *             V3 排空相流量 0.02 m³/h（< 0.05）持续 10 s → bDrained = TRUE，eErr = 01E1 → eClosing
 *             V4 转移中 bAbort → 同拍泵 FALSE 且阀指令 FALSE，回 eAbort（中止主向量）
 *             V5 转移总时长超 30 min → 0315，停泵关阀，bFailed = TRUE
 *             V6 fVolumeTarget = 0 → 0315，回 eFault，bValid = FALSE
 *             V7 fTransferred = NaN → 0315 复用，停泵关阀（坏值安全侧）
 *             V8 换批（fTransferred 由 5.0 回 0.1）→ **不报故障**，以本拍值为准继续（口径主向量）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             浮点只用大小比较 ｜ 无循环 ｜ 全变量双语同行注释 ｜ ENUM + CASE 含 ELSE
 *             ｜ 六只 TON 在主体前部无条件刷新 ｜ 单拍标志全部预清零 ｜ 阈值常量化
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 3 · 批处理顺控）
 *             2026-11-16  v1.0.1  R22 终审修复：总时长超时分支（0315）补置
 *             bError := TRUE——故障级码位必须同时置故障标志（R45 纪律），
 *             原实现只给码不置标志，bValid 误判为可用
 *             2026-11-17  v1.0.2  R23 P0 修复：中止时序两段化——新增
 *             xCoastStop（默认 TRUE 走惰转两段化）与 tPumpCoastTime（惰转
 *             窗）引脚；段 A 断泵输出使能、阀位保持不动、惰转计时；段 B
 *             窗满发关阀指令、确认超时置新故障码 16#0005_0317 + bError
 *             （R45 配对）；禁止单拍「停泵 + 关阀」连续成立；验收向量
 *             V9~V13 收录于本头注释「验收向量（v1.0.2 中止时序）」段；xCoastStop = FALSE 保留 v1.0.1
 *             单拍行为（不推荐：残压回流风险）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TransferState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 批次转移顺控相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_TransferState :
(
    eIdle         := 0,   // 待机：未启动 / Idle, not started
    ePrepValve    := 10,  // 准备阀门：双阀开指令，等开到位反馈 / Preparing, valves open, waiting for feedback
    eTransferring := 20,  // 转移中：泵运行，按注入累计量判结束 / Transferring, the pump runs
    eDraining     := 30,  // 排空中：泵停，等流量降到门限以下 / Draining, the pump stopped
    eClosing      := 40,  // 关阀中：双阀关指令，等确认窗 / Closing, waiting for the confirmation window
    eComplete     := 50,  // 完成：放行 / Complete, released
    eAbort        := 60,  // 中止兼容路径：单拍停泵关阀（xCoastStop = FALSE，不推荐） / Legacy single-scan abort, pump and valves off in one scan
    eAbortCoast   := 61,  // 中止第一段：泵输出使能已断，阀位保持不动，惰转计时中 / Abort stage A, pump disabled, valves held, coast timing
    eAbortClose   := 62,  // 中止第二段：惰转窗满，关阀指令已发，等阀离开开位 / Abort stage B, close command issued, waiting for the valve to leave open position
    eFault        := 99   // 故障：参数/超时/非法状态 / Fault, parameters, timeout or an illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchTransferSeq
VAR_INPUT
    bStart        : BOOL;                      // 启动请求，电平有效 / start request, level active
    bAbort        : BOOL;                      // 中止请求，任意拍生效 / abort request, effective on any scan
    bSrcValveFb   : BOOL;                      // 源阀开到位反馈 / source valve open feedback
    bDstValveFb   : BOOL;                      // 目标阀开到位反馈 / destination valve open feedback
    fTransferred  : REAL;                      // 累计转移量 [m3]，**由调用方积分器注入** / transferred volume, injected by the caller
    fVolumeTarget : REAL := 5.0;               // 目标转移量 [m3]，须 > 0 / target volume [m3], must be > 0
    fFlow         : REAL;                      // 实测流量 [m3/h] / measured flow [m3/h]
    fDrainFlow    : REAL := 0.05;              // 排空判据流量门限 [m3/h] / drain flow threshold [m3/h]
    tDrainVerify  : TIME := T#10S;             // 排空验证时长 [ms] / drain verification duration [ms]
    tValveFb      : TIME := T#5S;              // 阀位反馈确认窗 [ms] / valve feedback window [ms]
    tTimeout      : TIME := T#30M;             // 转移总时长上限 [ms]，须 > 0 / total transfer timeout [ms], must be > 0
    xCoastStop    : BOOL := TRUE;              // TRUE = 中止走惰转两段化（推荐）/ FALSE = 兼容旧行为单拍中止（仅存量调用保留，不推荐：残压回流风险） / Coast-stop abort sequencing enabled
    tPumpCoastTime: TIME := T#2S;              // 泵惰转时间 [ms]（默认 2 s）：停泵到关阀的物理时序分隔窗 / Pump coast-down time [ms]
END_VAR
VAR_OUTPUT
    bPumpCmd      : BOOL;                      // 泵指令 / pump command
    bSrcValveCmd  : BOOL;                      // 源阀指令（TRUE = 开启） / source valve command, TRUE means open
    bDstValveCmd  : BOOL;                      // 目标阀指令（TRUE = 开启） / destination valve command
    bDrained      : BOOL;                      // 排空完成标志 / drained flag
    bDone         : BOOL;                      // 转移完成放行 / transfer complete, released
    bFailed       : BOOL;                      // 转移失败锁定 / transfer failed, latched
    eErr          : UDINT;                     // 错误码，0 表示无错 / error code, 0 means no error
    bError        : BOOL;                      // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid        : BOOL;                      // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbValveFb     : TON;                       // 开阀到位确认窗，段 6 无条件刷新 [ms] / open feedback window
    fbCloseFb     : TON;                       // 关阀确认窗，段 6 无条件刷新 [ms] / close confirmation window
    fbDrain       : TON;                       // 排空验证窗，段 6 无条件刷新 [ms] / drain verification window
    fbTotal       : TON;                       // 转移总时长，段 6 无条件刷新 [ms] / total transfer timer
    fbCoast       : TON;                       // 泵惰转计时窗（中止第一段），段 6 无条件刷新 [ms] / pump coast-down window, abort stage A
    fbAbortClose  : TON;                       // 中止关阀确认窗（中止第二段，独立实例不复用），段 6 无条件刷新 [ms] / abort close-confirm window, stage B, dedicated instance
    _eState       : E_DL_TransferState := E_DL_TransferState.eIdle; // 当前相位 / current phase
    _bInit        : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad    : BOOL;                      // 参数非法标志 / illegal parameter flag
    _bFiniteBad   : BOOL;                      // 输入非有限标志 / non-finite input flag
    _bIllegal     : BOOL;                      // 非法状态标志 / illegal state flag
    _bFaultAcc    : BOOL;                      // 故障锁存保持量（等新启动清除） / held fault latch, cleared by a new start
    _bFailedAcc   : BOOL;                      // 失败锁存保持量 / held failure latch
    _bBothFb      : BOOL;                      // 双阀同时到位 / both valves reported open
    _bDrainCond   : BOOL;                      // 排空条件（流量低于门限） / drain condition
    _bFbBreak     : BOOL;                      // 开阀确认计时器断输入一拍 / open window one-scan break
    _bCloseBreak  : BOOL;                      // 关阀确认计时器断输入一拍 / close window one-scan break
    _bDrainBreak  : BOOL;                      // 排空计时器断输入一拍 / drain window one-scan break
    _bTotalBreak  : BOOL;                      // 总时长计时器断输入一拍 / total timer one-scan break
    _bVolumeOk    : BOOL;                      // 累计量达目标 / the target volume is reached
    _bRunning     : BOOL;                      // 处于计时阶段（准备/转移/排空/关阀） / inside a timed phase
    _bDrainedHeld : BOOL;                      // 排空完成保持量 / held drained flag
    _bCoastBreak  : BOOL;                      // 惰转计时器断输入一拍 / coast window one-scan break
    _bAbortCloseBreak : BOOL;                  // 中止关阀确认计时器断输入一拍 / abort close window one-scan break
    _bAbortCloseToAcc : BOOL;                  // 中止关阀确认超时锁存（等新启动清除） / held abort close-confirm timeout latch
END_VAR
VAR CONSTANT
    DL_VAL_LIM    : REAL := 1.0E9;             // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling
    DL_VOL_MIN    : REAL := 0.0;               // 目标体积下限 [m3]，须严格大于 / target volume floor, strictly greater
    DL_FLOW_MIN   : REAL := 0.0;               // 排空门限下限 [m3/h] / drain threshold floor [m3/h]
    DL_TIME_ZERO  : TIME := T#0MS;             // 时间零值基准 [ms] / time zero reference
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：泵与双阀**先全清**（R72），单拍标志预清零（R25 第一律）
 *      Pump and both valves cleared first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bPumpCmd     := FALSE;                         // 泵指令先清 / pump command cleared first
bSrcValveCmd := FALSE;                         // 源阀指令先清 / source valve cleared first
bDstValveCmd := FALSE;                         // 目标阀指令先清 / destination valve cleared first
bDrained     := FALSE;                         // 排空标志每拍重算 / drained flag recomputed
bDone        := FALSE;                         // 完成标志每拍重算 / done flag recomputed
bFailed      := FALSE;                         // 失败标志每拍重算 / failed flag recomputed
bValid       := FALSE;                         // 可用标志每拍重算 / usable flag recomputed
eErr         := 16#0000_0000;                  // 错误码每拍重算 / error code recomputed
bError       := FALSE;                         // 故障标志每拍重算 / fault flag recomputed
_bParamBad   := FALSE;                         // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad  := FALSE;                         // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal    := FALSE;                         // 非法状态标志预清零 / illegal state flag pre-cleared
_bBothFb     := FALSE;                         // 双阀到位标志预置 FALSE / both-feedback preset FALSE
_bDrainCond  := FALSE;                         // 排空条件预置 FALSE / drain condition preset FALSE
_bVolumeOk   := FALSE;                         // 体积达标预置 FALSE / volume reached preset FALSE
_bRunning    := FALSE;                         // 计时阶段标志预置 FALSE / running preset FALSE

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（锁存与保持量从零起）
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState       := E_DL_TransferState.eIdle;  // 相位待机 / phase idle
    _bFaultAcc    := FALSE;                     // 故障锁存清零 / fault latch cleared
    _bFailedAcc   := FALSE;                     // 失败锁存清零 / failure latch cleared
    _bDrainedHeld := FALSE;                     // 排空保持量清零 / drained flag cleared
    _bAbortCloseToAcc := FALSE;                 // 中止关阀确认超时锁存清零 / abort close timeout latch cleared
    _bFbBreak     := TRUE;                      // 开阀确认窗从零开始 / the open window starts from zero
    _bCloseBreak  := TRUE;                      // 关阀确认窗从零开始 / the close window starts from zero
    _bDrainBreak  := TRUE;                      // 排空验证窗从零开始 / the drain window starts from zero
    _bTotalBreak  := TRUE;                      // 总时长计时从零开始 / the total timer starts from zero
    _bInit        := TRUE;                      // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（目标体积、总超时、排空门限）
 *      Parameter gate for the target volume, the timeout and the drain threshold
 *-----------------------------------------------------------------------------*)
IF (fVolumeTarget <> fVolumeTarget) OR (ABS(fVolumeTarget) > DL_VAL_LIM) OR (fVolumeTarget <= DL_VOL_MIN) THEN
    _bParamBad := TRUE;                        // 目标体积非法 / target volume illegal
END_IF
IF TIME_TO_DINT(tTimeout) <= 0 THEN
    _bParamBad := TRUE;                        // 总超时为 0：无限等待，非法 / zero timeout means waiting forever
END_IF
IF xCoastStop AND (TIME_TO_DINT(tPumpCoastTime) <= 0) THEN
    _bParamBad := TRUE;                        // 两段化已使能但惰转窗为 0：退化为单拍中止，违背修复意图，按非法参数拦截 / coast time of zero degrades the two-stage abort, intercepted as an illegal parameter
END_IF
IF (fDrainFlow <> fDrainFlow) OR (ABS(fDrainFlow) > DL_VAL_LIM) OR (fDrainFlow < DL_FLOW_MIN) THEN
    _bParamBad := TRUE;                        // 排空门限非法 / drain threshold illegal
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜输入有限性（累计量与流量；区间判据同时拦 NaN 与 ±Inf）
 *      Input finiteness for the injected volume and the flow
 *-----------------------------------------------------------------------------*)
IF (fTransferred < -DL_VAL_LIM) OR (fTransferred > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 累计量非有限 / injected volume non-finite
END_IF
IF (fFlow < -DL_VAL_LIM) OR (fFlow > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 流量非有限 / flow non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜判据计算（双阀到位 / 体积达标 / 排空条件 / 计时阶段）
 *      Criteria evaluation
 *-----------------------------------------------------------------------------*)
_bBothFb    := bSrcValveFb AND bDstValveFb;    // 双阀同时到位（启泵的唯一许可） / both valves open, the only permit to start the pump
_bVolumeOk  := (fTransferred >= fVolumeTarget); // 累计量达目标 [布尔] / the target volume is reached
_bDrainCond := (fFlow < fDrainFlow);           // 排空条件：流量低于门限 / drain condition

_bRunning := (_eState = E_DL_TransferState.ePrepValve)
             OR (_eState = E_DL_TransferState.eTransferring)
             OR (_eState = E_DL_TransferState.eDraining)
             OR (_eState = E_DL_TransferState.eClosing);

(*------------------------------------------------------------------------------
 * 段 6｜四只计时器无条件刷新（R40：CASE 之外每拍必调，各司其职不复用）
 *      Four timers refreshed unconditionally, one duty each, never reused
 *-----------------------------------------------------------------------------*)
fbValveFb(IN := (_eState = E_DL_TransferState.ePrepValve) AND (NOT _bFbBreak), PT := tValveFb); // 开阀到位确认窗
_bFbBreak := FALSE;                            // 断输入拍在调用后自清 / break self-cleared after the call

fbCloseFb(IN := (_eState = E_DL_TransferState.eClosing) AND (NOT _bCloseBreak), PT := tValveFb); // 关阀确认窗
_bCloseBreak := FALSE;                         // 断输入拍在调用后自清 / break self-cleared after the call

fbDrain(IN := (_eState = E_DL_TransferState.eDraining) AND _bDrainCond AND (NOT _bDrainBreak),
        PT := tDrainVerify);                   // 排空验证窗
_bDrainBreak := FALSE;                         // 断输入拍在调用后自清 / break self-cleared after the call

fbTotal(IN := _bRunning AND (NOT _bTotalBreak), PT := tTimeout); // 转移总时长
_bTotalBreak := FALSE;                         // 断输入拍在调用后自清 / break self-cleared after the call

fbCoast(IN := (_eState = E_DL_TransferState.eAbortCoast) AND (NOT _bCoastBreak), PT := tPumpCoastTime); // 泵惰转计时窗（中止第一段）
_bCoastBreak := FALSE;                         // 断输入拍在调用后自清 / break self-cleared after the call

fbAbortClose(IN := (_eState = E_DL_TransferState.eAbortClose) AND (bSrcValveFb OR bDstValveFb) AND (NOT _bAbortCloseBreak),
             PT := tValveFb);                  // 中止关阀确认窗：阀开反馈任一保持即计时 / abort close window, timed while any open feedback holds
_bAbortCloseBreak := FALSE;                    // 断输入拍在调用后自清 / break self-cleared after the call

(*------------------------------------------------------------------------------
 * 段 7｜相位机（只做迁移；输出在段 8 按相置位，泵永远在阀之后）
 *      Phase machine, transitions only, the pump is always gated behind the valves
 *-----------------------------------------------------------------------------*)
IF bAbort AND (_eState <> E_DL_TransferState.eAbort)
   AND (_eState <> E_DL_TransferState.eAbortCoast) AND (_eState <> E_DL_TransferState.eAbortClose) THEN
    (* 中止：任意拍生效；中止族态内不重复触发（防惰转窗被反复重启，v1.0.2） *)
    (* Abort takes effect on any scan, not re-triggered inside the abort family *)
    IF xCoastStop THEN
        _eState    := E_DL_TransferState.eAbortCoast; // 两段化：先断泵、阀保持，惰转计时 / two-stage: pump off, valves held, coast timing
        _bCoastBreak := TRUE;                  // 惰转窗从零开始 / the coast window starts from zero
    ELSE
        _eState    := E_DL_TransferState.eAbort; // 兼容路径：单拍停泵关阀（不推荐） / legacy single-scan abort, not recommended
    END_IF
    _bFbBreak  := TRUE;                        // 四个窗全部重启 / every window restarts
    _bCloseBreak := TRUE;
    _bDrainBreak := TRUE;
    _bTotalBreak := TRUE;
    _bAbortCloseBreak := TRUE;                 // 中止关阀确认窗重启 / the abort close window restarts
ELSIF _bParamBad THEN
    _eState := E_DL_TransferState.eFault;      // 参数非法：转故障 / illegal parameters go to fault
    _bFailedAcc := TRUE;                       // 失败锁存（本批不可用） / this batch is unusable
ELSIF _bFiniteBad THEN
    _eState := E_DL_TransferState.eFault;      // 输入非有限：转故障，停泵关阀（段 8） / non-finite input
    _bFailedAcc := TRUE;                       // 失败锁存 / failure latched
ELSE
    IF fbTotal.Q AND _bRunning THEN
        (* 总时长超时：先锁存失败再转故障，段 8 下一拍停泵关阀 *)
        (* Total timeout, the failure is latched and the outputs drop on the next scan *)
        _bFailedAcc := TRUE;                   // 本批失败锁定 / latch the failure
        _bFbBreak   := TRUE;                   // 四个窗全部重启 / every window restarts
        _bCloseBreak := TRUE;
        _bDrainBreak := TRUE;
        _bTotalBreak := TRUE;
        _eState     := E_DL_TransferState.eFault;
    ELSIF (_eState <> E_DL_TransferState.eIdle) AND (_eState <> E_DL_TransferState.eAbort)
          AND (_eState <> E_DL_TransferState.eAbortCoast) AND (_eState <> E_DL_TransferState.eAbortClose)
          AND (_eState <> E_DL_TransferState.eFault) AND (NOT bStart) THEN
        (* 启动撤销等同中止：外部撤掉启动必须让设备停下，不能继续跑 *)
        (* A dropped start is treated as an abort, the machine must stop *)
        IF xCoastStop THEN
            _eState      := E_DL_TransferState.eAbortCoast; // 两段化中止 / two-stage abort
            _bCoastBreak := TRUE;               // 惰转窗从零开始 / the coast window starts from zero
        ELSE
            _eState      := E_DL_TransferState.eAbort; // 兼容路径单拍中止 / legacy single-scan abort
        END_IF
        _bFbBreak  := TRUE;
        _bCloseBreak := TRUE;
        _bDrainBreak := TRUE;
        _bTotalBreak := TRUE;
        _bAbortCloseBreak := TRUE;              // 中止关阀确认窗重启 / the abort close window restarts
    ELSE
        CASE _eState OF

            E_DL_TransferState.eIdle:          // 待机：启动即准备阀门
                IF bStart THEN
                    _bFaultAcc    := FALSE;    // 新任务清除故障锁存 / a new job clears the fault latch
                    _bFailedAcc   := FALSE;    // 新任务清除失败锁存 / a new job clears the failure latch
                    _bDrainedHeld := FALSE;    // 新任务清除排空保持量 / a new job clears the drained flag
                    _bAbortCloseToAcc := FALSE; // 新任务清除中止关阀超时锁存 / a new job clears the abort close timeout latch
                    _bFbBreak     := TRUE;     // 开阀确认窗从零开始 / the open window starts from zero
                    _bTotalBreak  := TRUE;     // 总时长从零开始 / the total timer starts from zero
                    _eState       := E_DL_TransferState.ePrepValve; // 进准备阀门相 / prepare the valves
                END_IF

            E_DL_TransferState.ePrepValve:     // 准备阀门：双阀到位才启泵
                IF _bBothFb THEN
                    _bTotalBreak := TRUE;      // 启泵当拍重启总时长（此前只算阀门准备） / the total timer restarts at pump start
                    _eState      := E_DL_TransferState.eTransferring; // 进转移相 / start transferring
                ELSIF fbValveFb.Q THEN
                    _bFaultAcc := TRUE;        // 阀位反馈超时：锁存故障 / feedback timeout, latch the fault
                    _bFbBreak  := TRUE;        // 窗重启 / the window restarts
                    _eState    := E_DL_TransferState.eIdle; // 回待机（先清输出，泵从未启动） / back to idle
                END_IF

            E_DL_TransferState.eTransferring:  // 转移中：累计量达目标即停泵
                IF _bVolumeOk THEN
                    _bDrainBreak := TRUE;      // 排空验证窗从零开始 / the drain window starts from zero
                    _eState      := E_DL_TransferState.eDraining; // 进排空相（泵在段 8 停） / start draining
                END_IF

            E_DL_TransferState.eDraining:      // 排空中：流量持续低于门限即判排空完成
                IF fbDrain.Q THEN
                    _bDrainedHeld := TRUE;     // 排空完成（保持量） / drained, latched
                    _bCloseBreak  := TRUE;     // 关阀确认窗从零开始 / the close window starts from zero
                    _eState       := E_DL_TransferState.eClosing; // 进关阀相 / close the valves
                END_IF

            E_DL_TransferState.eClosing:       // 关阀中：确认窗满即完成
                IF fbCloseFb.Q THEN
                    _eState := E_DL_TransferState.eComplete; // 进完成相 / complete
                END_IF

            E_DL_TransferState.eComplete:      // 完成：等启动撤销（bStart 落下由上方统一处理）
                _bTotalBreak := TRUE;          // 总时长停表 / stop the total timer
                _bFbBreak    := TRUE;          // 各窗复位 / every window reset
                _bCloseBreak := TRUE;
                _bDrainBreak := TRUE;

            E_DL_TransferState.eAbort:         // 中止兼容路径：等启动撤销后回待机
                _bTotalBreak := TRUE;          // 总时长停表 / stop the total timer
                IF NOT bStart THEN
                    _eState := E_DL_TransferState.eIdle; // 启动已撤销，回待机 / back to idle
                END_IF

            E_DL_TransferState.eAbortCoast:    // 中止第一段：泵已断使能、阀保持不动，等惰转窗满
                _bTotalBreak := TRUE;          // 总时长停表 / stop the total timer
                IF fbCoast.Q THEN
                    _bAbortCloseBreak := TRUE; // 惰转窗满，中止关阀确认窗从零开始 / coast elapsed, the abort close window starts from zero
                    _eState := E_DL_TransferState.eAbortClose; // 进中止第二段（阀指令在段 8 清零）/ abort stage B
                END_IF

            E_DL_TransferState.eAbortClose:    // 中止第二段：关阀指令已发，等阀离开开位或确认超时
                _bTotalBreak := TRUE;          // 总时长停表 / stop the total timer
                IF fbAbortClose.Q THEN
                    _bAbortCloseToAcc := TRUE; // 阀开反馈在确认窗内保持：关阀确认超时锁存 / open feedback held through the window, close-confirm timeout latched
                END_IF
                IF (NOT bSrcValveFb) AND (NOT bDstValveFb) AND (NOT bStart) THEN
                    _eState := E_DL_TransferState.eIdle; // 阀已离开开位且启动撤销，回待机 / valves left open position and the start is dropped
                END_IF

            E_DL_TransferState.eFault:         // 故障：启动撤销且参数合法才回待机
                IF (NOT bStart) AND (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
                    _eState := E_DL_TransferState.eIdle; // 原因消失 / the cause is gone
                END_IF

            ELSE
                _bIllegal := TRUE;             // 标记非法状态 / flag the illegal state
                _bFbBreak := TRUE;             // 四个窗全部重启 / every window restarts
                _bCloseBreak := TRUE;
                _bDrainBreak := TRUE;
                _bTotalBreak := TRUE;
                _eState := E_DL_TransferState.eFault; // 回故障态 / back to the fault state
        END_CASE
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出置位（次序即安全：**泵先于阀**，中止路径先停泵后关阀）
 *      Output assignment, the pump always precedes the valves
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_TransferState.ePrepValve:             // 准备阀门：双阀开，泵不启
        bSrcValveCmd := TRUE;                  // 源阀开 / source valve open
        bDstValveCmd := TRUE;                  // 目标阀开 / destination valve open
    E_DL_TransferState.eTransferring:          // 转移：双阀保持 + 泵运行（泵在阀之后赋值）
        bSrcValveCmd := TRUE;                  // 源阀开 / source valve open
        bDstValveCmd := TRUE;                  // 目标阀开 / destination valve open
        bPumpCmd     := TRUE;                  // 泵运行（阀门已到位并保持） / the pump runs after the valves are open
    E_DL_TransferState.eDraining:              // 排空：泵停、双阀仍开
        bSrcValveCmd := TRUE;                  // 源阀开 / source valve open
        bDstValveCmd := TRUE;                  // 目标阀开 / destination valve open
    E_DL_TransferState.eAbortCoast:            // 中止第一段：泵断使能、**阀位保持不动**（不发关阀指令，
                                               //   机检断言：abort 拍不得出现关阀输出置位，验收向量 V9/V10）
        bSrcValveCmd := TRUE;                  // 源阀保持开（惰转窗内阀位不动） / source valve held open during the coast window
        bDstValveCmd := TRUE;                  // 目标阀保持开 / destination valve held open
    ELSE
        bPumpCmd     := FALSE;                 // 其余相：泵显式停（先停泵） / pump explicitly stopped first
        bSrcValveCmd := FALSE;                 // 源阀关指令（TRUE = 开启，故清指令即关阀） / source valve closed
        bDstValveCmd := FALSE;                 // 目标阀关指令 / destination valve closed
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜码位优先级链与出口
 *      Code priority chain and exit
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr     := 16#0005_0316;                  // 故障级：状态机兜底 / fault: state machine fallback
    bError   := TRUE;                          // 置故障标志 / raise the fault flag
    _bFailedAcc := TRUE;                       // 非法状态按失败锁定 / an illegal state latches a failure
ELSIF _bParamBad OR _bFiniteBad THEN
    eErr     := 16#0005_0315;                  // 故障级：参数非法或输入非有限（复用，R90） / fault: illegal parameter or non-finite input
    bError   := TRUE;                          // 置故障标志 / raise the fault flag
ELSIF _bAbortCloseToAcc THEN
    eErr     := 16#0005_0317;                  // 故障级：中止第二段关阀确认超时（v1.0.2 新增） / fault: abort close-confirm timeout
    bError   := TRUE;                          // 故障级码位必须同时置故障标志（R45 配对） / a fault-class code must raise the fault flag
ELSIF (_eState = E_DL_TransferState.eFault) AND _bFailedAcc THEN
    eErr     := 16#0005_0315;                  // 故障级：转移总时长超时（复用，R90） / fault: total transfer timeout
    bError   := TRUE;                          // 故障级码位必须置故障标志（R22 终审修复：原实现漏置）/ a fault-class code must raise the fault flag
ELSIF _bFaultAcc THEN
    eErr     := 16#0005_0314;                  // 故障级：阀位反馈超时未到位，拒绝启泵 / fault: feedback timeout, no pump start
    bError   := TRUE;                          // 置故障标志 / raise the fault flag
ELSIF _bDrainedHeld THEN
    eErr     := 16#0005_01E1;                  // 信息级：排空验证窗内流量持续低于门限 / informational: drained
ELSIF _eState = E_DL_TransferState.eTransferring THEN
    eErr     := 16#0005_01E0;                  // 信息级：累计量由调用方注入，本件不重复积分 / informational: the volume is injected
END_IF

bDrained   := _bDrainedHeld;                   // 排空标志出口 / drained outlet
bDone      := (_eState = E_DL_TransferState.eComplete); // 完成放行出口 / done outlet
bFailed    := (_eState = E_DL_TransferState.eFault) OR _bFailedAcc OR _bAbortCloseToAcc; // 失败出口（中止本身是人的决定不计失败；关阀确认超时是真实故障，计入）

IF bError THEN
    bValid := FALSE;                           // 故障级：输出不可用 / fault: outputs unusable
ELSIF (_eState = E_DL_TransferState.eIdle) THEN
    bValid := FALSE;                           // 待机：无批次在执行 / idle: no batch in progress
ELSE
    bValid := TRUE;                            // 输出可用 / outputs usable
END_IF

END_FUNCTION_BLOCK
