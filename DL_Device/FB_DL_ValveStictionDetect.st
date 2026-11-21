(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ValveStictionDetect
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / TON）
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备本体退化诊断 · 阀门黏滞
 * 功能描述 (Function)   : 用**常规运行数据**（指令 OP 与阀位 PV，无需激励试验）
 *                         在线判阀门黏滞，输出黏滞等级、黏滞带估计、方向性滞后
 *                         归一指标与停滞事件计数，并把「需要维护」语义交给
 *                         NE107 的 eMaintenanceReq。
 * 三条判据 (Criteria)   : 三条判据**并发**，缺一不升级（这是本件的核心裁定）：
 *                         (a) 方向性滞后：上升行程与下降行程在同一 OP 处 PV 之差，
 *                             即黏滞带 fDeadbandEst；
 *                         (b) 停滞拍：|ΔOP| > fStallThr 而 |ΔPV| < fMoveThr，持续
 *                             tStallTime 判一次停滞事件；
 *                         (c) 反转确认延迟：方向反转后到 PV 开始移动的时间超过
 *                             tReverseTime 判一次反转超时。
 *                         只有 (a) 超限而 (b)(c) 均无证据时，等级封顶在 eSlight
 *                         ——单个指标越限不足以判重度黏滞，这是文献反复强调的
 *                         「无单一方法 100% 可信」在本件的落地方式。
 * 等级映射 (Levels)     : eNone(0) → eOk；eSlight(10) / eModerate(20) →
 *                         eMaintenanceReq；eSevere(30) → eOutOfSpec。
 *                         黏滞是**退化**不是失效：阀门仍在调节，只是品质下降，
 *                         故最高只到 eOutOfSpec，绝不进 eFailure（故障只来自
 *                         参数非法与非有限输入）。
 * 边界声明 (Limits)     : ① **不做互相关**：需要长窗 FFT，违 O(1) 内存纪律；
 *                         ② **不做椭圆拟合**：需要二维迭代，不可逐拍复算；
 *                         ③ 输出是**趋势判据，不是黏滞量的计量级量化**——按
 *                         行业文献口径，黏滞带估计只用于纵向趋势比较与维护
 *                         排序，不可作为验收数据；④ 不替代定位器自诊断，
 *                         不做任何补偿（补偿属定位器或 APC 层职责）；
 *                         ⑤ **判据 (a) 只取准静态反转点**：同一 OP 处比较要求
 *                         前后反转点的指令差 ≤ fDeadbandMax。全行程单向斜坡
 *                         （0→100→0）的反转点 OP 差达全量程，本件不出滞后样本，
 *                         黏滞带保持 0、等级保持 eNone —— 这是**刻意的保守方向**：
 *                         在持续运动的阀上做同 OP 差分会把「纯跟随滞后」误算成
 *                         黏滞（滞后 0.3 % 会产出 0.6 % 的假黏滞带），文献明确
 *                         该法只在准静态与小幅往复下可信。需要全行程评估时应在
 *                         工艺上安排往复小步激励，或改看定位器自诊断。
 * 段序 (Cycle order)   : 段 1 默认值与单拍预清零 → 段 2 首扫初始化 →
 *                         段 3 参数闸门 → 段 4 定时器与边沿无条件刷新 →
 *                         段 5 输入域检查与快照 → 段 6 复位通道与故障锁存
 *                         （**CASE 前置，且不做状态赋值**）→ 段 7 相位机 →
 *                         段 8 采样采集 → 段 9 分析计算 → 段 10 发布与窗口重建
 *                         （含本拍复验）→ 段 11 出口钳位与保持重写 → 段 12 码位链。
 * 镜像量清单 (R38)      : `_bPosValidSnap` —— 窗口关闭那一刻的反馈有效性快照，
 *                         **唯一消费点**是段 9 的「窗口合法性闸门」；实时量
 *                         `bPosValid` 的三处消费点各自独立且不含边界量含义：
 *                         段 4 的定时器输入、段 7 的挂起迁移、段 10 的本拍复验。
 *                         窗口内的 OP/PV 一律取 `_afOpWin` / `_afPvWin` 缓存，
 *                         **绝不**在分析相读实时 `fPos` —— 这是 R38/R42 的正解。
 * 定时器清单 (R40)      : 实例名 / IN 表达式 / 断输入拍标志 / 自清位置
 *                         fbWindowWatch  / 相位为采集 AND NOT _bWindowBreak
 *                                        / _bWindowBreak / 段 4 调用后自清
 *                         fbSampleWatch  / 相位为采集 AND NOT _bSampleBreak
 *                                        / _bSampleBreak / 段 4 调用后自清，采样后置位
 *                         fbStallWatch   / 停滞条件 AND NOT _bStallBreak
 *                                        / _bStallBreak / 段 4 调用后自清
 *                         fbReverseWatch / 反转待确认 AND NOT _bReverseBreak
 *                                        / _bReverseBreak / 段 4 调用后自清
 *                         fbSinceWatch   / NOT _bSinceBreak / _bSinceBreak
 *                                        / 段 4 调用后自清，停滞事件时置位
 * 单拍标志清单 (R25)    : `_bResetPulse` 预清段 1 / 置位段 6 / 消费段 6；
 *                         `_bWindowBreak` `_bSampleBreak` `_bStallBreak`
 *                         `_bReverseBreak` `_bSinceBreak` 预清处不设（就地置位
 *                         后段 4 自清），置位点见定时器清单；
 *                         `_bStallEvent` `_bRevEvent` 预清段 1 / 置位段 8 /
 *                         消费段 8 与段 9。
 * 保持位清单 (R27)      : `_eLevel`（等级）、`_fDbHeld`（黏滞带）、`_uStallCount`
 *                         （停滞计数）、`_bSuspectHeld`（嫌疑位）四个保持量，全部
 *                         由段 11 每拍重写出口；复位沿清除（R27 的反面：复位是
 *                         保持量的唯一清除通道）。
 * 三元一致表 (R35)      : 量 / 守卫封顶 / 判据运算符
 *                         fDeadbandMax      / 钳到 ≥0.5   / 等级判据用 >=
 *                         fDeadbandModerate / 钳到 < Max  / 等级判据用 >=
 *                         轻微下限（Max 的 1/4）/ 钳到 ≥0.1 / 等级判据用 >=
 * 验收向量 (Acceptance) :
 *   V1 正常阀：OP 斜坡 0→100、PV 滞后 0.3% → eStiction=eNone、黏滞带约 0.3、
 *      停滞计数 0
 *   V2 黏滞阀：OP 每 2 s 步进 2%、PV 每 4 s 跳 3% → 三判据全成立 →
 *      eStiction=eSevere、停滞计数 ≥2、eHealth=eOutOfSpec
 *   V3（V-C 跨相复验）：分析相已缓存样本 → 判定相当拍 bPosValid 置 FALSE →
 *      **必须不发布新等级**（保持上次值 + 015D），不得用缓存样本直接出结论
 *   V4（V-D 恢复首拍）：挂起恢复后样本数从 0 重建（R41），重建窗**不发布**
 *      任何等级（比「不判 Severe」更严），只置 015C
 *   V5（V-A 域外）：fCmd 为 NaN → 031D 锁存，黏滞带保持上次值并夹进 0~100（R43）
 * 规格偏离 (Deviation)  :
 *   ① 规格未给采样周期。本件按「窗口长度 ÷ 最少样本数」推导采样周期并钳进
 *      20 ms~5 s，使一个标准窗恰好采到 nMinSamples 个样本；若窗口内样本数
 *      先达缓冲上限（128）则提前进入分析相，避免溢出。
 *   ② 规格的 eNone/eSlight 分界未给阈值。本件取「中限的 1/4」作为轻微下限
 *      （默认 2.0 × 0.25 = 0.5%），并在三元一致表中登记，避免出现无闸门的
 *      隐式阈值。
 *   ③ 规格 V4 要求「恢复首拍不得判 eSevere」。本件实现为**重建窗不发布任何
 *      等级**（只置 015C 保持上次值），比规格更严，且不引入「部分发布」的
 *      半可信语义。
 * 开源溯源 (Origin)     : 来源标签 namur-ne107 / stiction-diag / asset-health。
 *                         原创 clean-room 实现。NE107（公开推荐规范）仅提供
 *                         健康分级语义；阀黏滞的**判据思想**（方向性滞后、
 *                         停滞拍、反转确认延迟）来自控制工程公开文献的通行
 *                         定性描述，属公有领域方法学思想，不构成代码版权标的；
 *                         本件未复制任何文献代码或开源工程源码，缓冲区结构、
 *                         阈值口径、等级仲裁、状态机与全部码位 100% 本库独立
 *                         设计。T3 定位：文献仅作立项理由，不作为实现依据。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R13 · 泳道 A · 阀门黏滞在线诊断）
 *   2026-11-16  v1.0.1  终审修复一处、留档一处：① 距上次停滞定时器的 PT
 *                       由裸 `T#24H` 改为常量 DL_SINCE_MAX（无魔法数红线）；
 *                       ② 头注释补边界 ⑤，明确判据 (a) 在全行程单向斜坡下不出
 *                       样本的保守语义与理由（原实现无此声明，易被误读为漏判缺陷）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StictionLevel（归属本功能块，同文件发布）
 * 含义: 黏滞严重度。0 起步长 10，便于后续插入细分等级。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_StictionLevel :
(
    eNone     := 0,    // 无黏滞：滞后在噪声带内 / No stiction, hysteresis within the noise band
    eSlight   := 10,   // 轻微：可察觉但影响可忽略 / Slight, noticeable but negligible
    eModerate := 20,   // 中度：调节品质下降，排入维护计划 / Moderate, control quality degraded
    eSevere   := 30    // 重度：明显黏滑运动，须尽快处理 / Severe, stick-slip motion
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StictionPhase（归属本功能块，同文件发布）
 * 含义: 诊断相位。每个成员在段 7 有且仅有一个 CASE 标签，ELSE 只接脏值。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_StictionPhase :
(
    eIdle    := 0,     // 待机：未使能或参数未通过 / Idle, disabled or parameters not accepted
    eCollect := 10,    // 采集：按采样周期入缓冲 / Collect, samples enter the ring buffer
    eAnalyze := 20,    // 分析：仅在窗口关闭当拍执行一次 / Analyze, executed once when the window closes
    eVerdict := 30,    // 判定：本拍复验后发布，再回采集 / Verdict, re-verify then publish
    eSuspend := 40,    // 挂起：反馈失效，非故障；恢复后窗口重建 / Suspended, not a fault
    eFault   := 99     // 故障：参数非法或输入非有限，锁存待复位 / Fault, latched until reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_ValveStictionDetect
VAR_INPUT
    bEnable          : BOOL;                          // 使能，FALSE 时窗口冻结 [-] / Enable, freezes the window
    bReset           : BOOL;                          // 复位锁存与统计，上升沿有效 [-] / Rising edge resets latch and statistics
    fCmd             : REAL;                          // 阀门指令 OP [%]，范围 0~100 / Valve command in percent
    fPos             : REAL;                          // 阀位反馈 PV [%]，范围 0~100 / Valve position feedback in percent
    bPosValid        : BOOL := TRUE;                  // 反馈有效性，FALSE 时诊断挂起（非故障）[-] / Feedback validity, FALSE suspends
    fMoveThr         : REAL := 0.5;                   // 判阀位在动的位移阈 [%]，范围 0.1~5.0 / Movement threshold
    fStallThr        : REAL := 1.0;                   // 判指令在变的变化阈 [%]，范围 0.2~10.0 / Command change threshold
    tStallTime       : TIME := T#2S;                  // 停滞持续判据 [毫秒]，范围 100 ms~60 s / Stall duration
    tReverseTime     : TIME := T#1S;                  // 反转确认允许延迟 [毫秒]，范围 100 ms~30 s / Reverse confirmation delay
    tWindow          : TIME := T#60S;                 // 分析窗长 [毫秒]，范围 10 s~30 min / Analysis window
    nMinSamples      : INT := 30;                     // 窗口最少有效样本 [个]，范围 5~1000 / Minimum samples per window
    fDeadbandMax     : REAL := 5.0;                   // 黏滞带上限，超此判 Severe [%]，范围 0.5~20.0 / Severe limit
    fDeadbandModerate: REAL := 2.0;                   // 黏滞带中限，超此判 Moderate [%]，范围 0.1~上限 / Moderate limit
END_VAR
VAR_OUTPUT
    eHealth          : E_DL_Ne107Status;              // NE107 健康态（引用自 I_DL_DeviceHealth）[-] / NE107 health
    uDiagCode        : UDINT;                         // 当前诊断码，0=无码 [代码] / Active diagnostic code
    uErrorId         : UDINT;                         // 末次故障码，仅故障级 [代码] / Last fault code, faults only
    bError           : BOOL;                          // 故障锁存 [-] / Fault latched
    eStiction        : E_DL_StictionLevel;            // 黏滞等级（保持语义）[-] / Stiction level, held
    fDeadbandEst     : REAL;                          // 黏滞带估计 [%]，保持并钳进 0~100 / Estimated stiction band
    fHysteresisRatio : REAL;                          // 方向性滞后归一指标（黏滞带/全行程）[-]，范围 0~1 / Normalised hysteresis
    nStallCount      : UDINT;                         // 停滞事件累计 [次]，锁存，仅复位清 / Stall event counter, reset only
    tSinceLastStall  : TIME;                          // 距上次停滞事件时长 [毫秒] / Time since the last stall event
    nSampleCount     : UINT;                          // 本窗有效样本数 [个] / Valid samples in the window
    bStictionSuspect : BOOL;                          // 嫌疑位，任一判据成立即 TRUE [-] / Suspect flag for early HMI hints
END_VAR
VAR
    fbTrigReset      : R_TRIG;                        // 复位沿检测，段 4 无条件刷新 [-] / Reset edge detector
    fbWindowWatch    : TON;                           // 窗口长度计时，段 4 无条件刷新 [毫秒] / Window timer
    fbSampleWatch    : TON;                           // 采样周期计时，段 4 无条件刷新 [毫秒] / Sample period timer
    fbStallWatch     : TON;                           // 停滞持续计时，段 4 无条件刷新 [毫秒] / Stall duration timer
    fbReverseWatch   : TON;                           // 反转确认计时，段 4 无条件刷新 [毫秒] / Reverse confirmation timer
    fbSinceWatch     : TON;                           // 距上次停滞计时，段 4 无条件刷新 [毫秒] / Time since the last stall
    _ePhase          : E_DL_StictionPhase := E_DL_StictionPhase.eIdle; // 当前相位 [-] / Current phase
    _bInit           : BOOL := FALSE;                 // 首扫标志，初值 FALSE [-] / First-scan flag
    _bFaultLatch     : BOOL;                          // 故障锁存，仅复位清 [-] / Fault latch
    _uErrFault       : UDINT;                         // 首出故障码 [代码] / First-out fault code
    _bResetPulse     : BOOL;                          // 复位单拍 [-] / One-shot reset pulse
    _bWindowBreak    : BOOL;                          // 窗口定时器断输入一拍 [-] / Window timer break
    _bSampleBreak    : BOOL;                          // 采样定时器断输入一拍 [-] / Sample timer break
    _bStallBreak     : BOOL;                          // 停滞定时器断输入一拍 [-] / Stall timer break
    _bReverseBreak   : BOOL;                          // 反转定时器断输入一拍 [-] / Reverse timer break
    _bSinceBreak     : BOOL;                          // 距上次停滞定时器断输入一拍 [-] / Since timer break
    _bStallEvent     : BOOL;                          // 本拍停滞事件 [-] / Stall event this scan
    _bRevEvent       : BOOL;                          // 本拍反转超时事件 [-] / Reverse timeout this scan
    _fCmdUse         : REAL;                          // 生效指令（钳位后）[%] / Effective command after clamping
    _fPosUse         : REAL;                          // 生效阀位（钳位后）[%] / Effective position after clamping
    _fMoveUse        : REAL := 0.5;                   // 生效位移阈 [%] / Effective movement threshold
    _fStallUse       : REAL := 1.0;                   // 生效指令变化阈 [%] / Effective command threshold
    _fDbMaxUse       : REAL := 5.0;                   // 生效黏滞带上限 [%] / Effective severe limit
    _fDbModUse       : REAL := 2.0;                   // 生效黏滞带中限 [%] / Effective moderate limit
    _fDbSlightUse    : REAL := 0.5;                   // 生效轻微下限 [%] / Effective slight limit
    _tStallUse       : TIME := T#2S;                  // 生效停滞时长 [毫秒] / Effective stall duration
    _tReverseUse     : TIME := T#1S;                  // 生效反转延迟 [毫秒] / Effective reverse delay
    _tWindowUse      : TIME := T#60S;                 // 生效窗长 [毫秒] / Effective window length
    _tSampleUse      : TIME := T#2S;                  // 生效采样周期 [毫秒] / Effective sample period
    _nMinUse         : INT := 30;                     // 生效最少样本数 [个] / Effective minimum samples
    _diWinMs         : DINT;                          // 窗长毫秒数 [毫秒] / Window length in milliseconds
    _diSampleMs      : DINT;                          // 采样周期毫秒数 [毫秒] / Sample period in milliseconds
    _afOpWin         : ARRAY[1..128] OF REAL;         // 窗口指令缓存 [%] / Buffered commands
    _afPvWin         : ARRAY[1..128] OF REAL;         // 窗口阀位缓存 [%] / Buffered positions
    _nSampleCount    : UINT;                          // 本窗样本数 [个] / Samples in the window
    _fOpPrev         : REAL;                          // 上一样本指令 [%] / Previous command sample
    _fPvPrev         : REAL;                          // 上一样本阀位 [%] / Previous position sample
    _nDir            : INT;                           // 行程方向：+1 上升 / -1 下降 / 0 静止 / Travel direction
    _nDirPrev        : INT;                           // 上次记录的方向 [-] / Last recorded direction
    _fOpRev          : REAL;                          // 上次方向反转处的指令 [%] / Command at the last reversal
    _fPvRev          : REAL;                          // 上次方向反转处的阀位 [%] / Position at the last reversal
    _bHaveRev        : BOOL;                          // 已记录过反转点 [-] / A reversal has been recorded
    _fDbSum          : REAL;                          // 本窗滞后样本累加 [%] / Hysteresis sample sum
    _nDbCount        : UINT;                          // 本窗滞后样本数 [个] / Hysteresis sample count
    _fDbWin          : REAL;                          // 本窗黏滞带估计 [%] / Window deadband estimate
    _bCmdMovedLatch  : BOOL;                          // 指令在变（跨采样保持）[-] / Command moving, latched across samples
    _bPosMovedLatch  : BOOL;                          // 阀位在动（跨采样保持）[-] / Position moving, latched across samples
    _bRevPending     : BOOL;                          // 反转待确认 [-] / Reversal awaiting confirmation
    _fOpMin          : REAL;                          // 窗内指令最小值 [%] / Minimum command in the window
    _fOpMax          : REAL;                          // 窗内指令最大值 [%] / Maximum command in the window
    _fOpSpan         : REAL;                          // 窗内指令行程 [%] / Command span in the window
    _bStaticWindow   : BOOL;                          // 窗内阀位长期静止 [-] / Static window flag
    _bPosValidSnap   : BOOL;                          // 窗口关闭时的反馈有效性快照（R38 镜像量）[-] / Validity snapshot at window close
    _nIdx            : DINT;                          // 缓冲区循环索引 [1~128] / Buffer loop index
    _nSlot           : DINT;                          // 本次采样落位下标 [1~128] / Slot index of this sample
    _fCell           : REAL;                          // 缓冲区单元临时值 [%] / Cell temporary value
    _eCandLevel      : E_DL_StictionLevel := E_DL_StictionLevel.eNone; // 分析相候选等级 [-] / Candidate level
    _fCandDb         : REAL;                          // 分析相候选黏滞带 [%] / Candidate deadband
    _bCandValid      : BOOL := FALSE;                 // 候选有效（样本足够且反馈有效）[-] / Candidate valid flag
    _bRebuildWin     : BOOL;                          // 重建窗标志，首窗不发布 [-] / Rebuild window flag
    _eLevel          : E_DL_StictionLevel := E_DL_StictionLevel.eNone; // 保持的等级 [-] / Held level
    _fDbHeld         : REAL;                          // 保持的黏滞带 [%] / Held deadband
    _uStallCount     : UDINT;                         // 保持的停滞计数 [次] / Held stall counter
    _bSuspectHeld    : BOOL;                          // 保持的嫌疑位 [-] / Held suspect flag
    _tSinceHeld      : TIME;                          // 距上次停滞时长（保持量）[毫秒] / Held elapsed time
    _bCurValid       : BOOL;                          // 本拍反馈有效复验结果 [-] / Re-verified validity this scan
    _bStallSeenWin   : BOOL := FALSE;                 // 本窗有停滞证据 [-] / Stall evidence in this window
    _bRevSeenWin     : BOOL := FALSE;                 // 本窗有反转超时证据 [-] / Reverse evidence in this window
    _uWinCode        : UDINT;                         // 本窗信息码，新窗起点清零（R44）[代码] / Window info code
    _uDiagCode       : UDINT;                         // 当前诊断码（单一链产出）[代码] / Active diagnostic code
    _eHealthInt      : E_DL_Ne107Status := E_DL_Ne107Status.eUnknown; // 健康态内部量 [-] / Internal health state
    _bCmdFinite      : BOOL;                          // 指令有限标志 [-] / Command finite flag
    _bPosFinite      : BOOL;                          // 阀位有限标志 [-] / Position finite flag
    _bParamBad       : BOOL;                          // 阈值参数非法标志 [-] / Illegal threshold flag
END_VAR
VAR CONSTANT
    DL_BUF_MAX       : UINT := 128;                   // 窗口缓冲上限 [个]，O(1) 内存纪律 / Buffer capacity
    DL_VAL_LIM       : REAL := 1.0E6;                 // 有限性判定的绝对值上限 [%] / Finiteness limit
    DL_REAL_MAX      : REAL := 100.0;                 // 阀门全行程上限 [%] / Full stroke
    DL_REAL_MIN      : REAL := 0.0;                   // 阀门全行程下限 [%] / Zero stroke
    DL_SAMPLE_MIN_MS : DINT := 20;                    // 采样周期下限 [毫秒] / Minimum sample period
    DL_SAMPLE_MAX_MS : DINT := 5000;                  // 采样周期上限 [毫秒] / Maximum sample period
    DL_WIN_MIN_MS    : DINT := 10000;                 // 窗长下限 [毫秒] / Minimum window
    DL_WIN_MAX_MS    : DINT := 1800000;               // 窗长上限 [毫秒] / Maximum window
    DL_STALL_MIN_MS  : DINT := 100;                   // 停滞判据下限 [毫秒] / Minimum stall duration
    DL_STALL_MAX_MS  : DINT := 60000;                 // 停滞判据上限 [毫秒] / Maximum stall duration
    DL_REV_MIN_MS    : DINT := 100;                   // 反转延迟下限 [毫秒] / Minimum reverse delay
    DL_REV_MAX_MS    : DINT := 30000;                 // 反转延迟上限 [毫秒] / Maximum reverse delay
    DL_TIME_ZERO     : TIME := T#0S;                  // 时间零值基准 [毫秒] / Time zero reference
    DL_SINCE_MAX     : TIME := T#24H;                 // 距上次停滞计时的封顶（TON 上限，无魔法数）[毫秒] / Elapsed-time ceiling
    DL_EPS           : REAL := 1.0E-6;                // 浮点比较容差 [%] / Float comparison tolerance
    DL_SLIGHT_RATIO  : REAL := 0.25;                  // 轻微下限相对中限的比例 [-] / Slight ratio of the moderate limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜确定性默认值与单拍标志预清零（R25 第一律）
 *      Deterministic defaults and one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
_bResetPulse   := FALSE;                              // 复位单拍预清零（Reset pulse pre-cleared）
_bStallEvent   := FALSE;                              // 停滞事件预清零（Stall event pre-cleared）
_bRevEvent     := FALSE;                              // 反转事件预清零（Reverse event pre-cleared）
_bCmdFinite    := FALSE;                              // 指令有限标志预清零（Command finite pre-cleared）
_bPosFinite    := FALSE;                              // 阀位有限标志预清零（Position finite pre-cleared）
_bParamBad     := FALSE;                              // 参数非法标志预清零（Illegal parameter pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19：bInit 初值 FALSE，判据取非；首拍只装基准）
 *      First-scan initialisation, baseline only
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _ePhase        := E_DL_StictionPhase.eIdle;       // 相位待机（Phase idle）
    _bFaultLatch   := FALSE;                          // 故障锁存清零（Fault latch cleared）
    _uErrFault     := 16#0000_0000;                   // 首出码清零（First-out code cleared）
    _eLevel        := E_DL_StictionLevel.eNone;       // 等级初值无黏滞（Level starts at none）
    _fDbHeld       := 0.0;                            // 黏滞带初值 0（Deadband starts at zero）
    _uStallCount   := 0;                              // 停滞计数清零（Stall counter cleared）
    _bSuspectHeld  := FALSE;                          // 嫌疑位清零（Suspect cleared）
    _tSinceHeld    := DL_TIME_ZERO;                   // 计时清零（Elapsed cleared）
    _nSampleCount  := 0;                              // 样本数清零（Sample count cleared）
    _fDbSum        := 0.0;                            // 滞后累加清零（Hysteresis sum cleared）
    _nDbCount      := 0;                              // 滞后样本数清零（Hysteresis count cleared）
    _bHaveRev      := FALSE;                          // 反转记录清零（Reversal record cleared）
    _nDir          := 0;                              // 方向静止（Direction still）
    _nDirPrev      := 0;                              // 上次方向静止（Previous direction still）
    _bCmdMovedLatch := FALSE;                         // 指令在变清零（Command moving cleared）
    _bPosMovedLatch := FALSE;                         // 阀位在动清零（Position moving cleared）
    _bRevPending   := FALSE;                          // 反转待确认清零（Reversal pending cleared）
    _bRebuildWin   := FALSE;                          // 重建窗标志清零（Rebuild flag cleared）
    _uWinCode      := 16#0000_0000;                   // 窗口码清零（Window code cleared）
    _bInit         := TRUE;                           // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（阈值倒置属故障级；越界钳位并保持一致）
 *      Parameter gate: inverted thresholds latch a fault, ranges are clamped
 *-----------------------------------------------------------------------------*)
IF (fDeadbandMax <= 0.0) OR (fDeadbandMax > DL_VAL_LIM) OR (fDeadbandModerate >= fDeadbandMax) OR (fDeadbandModerate <= 0.0) THEN
    _bParamBad  := TRUE;                              // 上下限倒置或非正（Inverted or non-positive limits）
    _fDbMaxUse  := 5.0;                               // 兜底上限，防后续除零（Fallback severe limit）
    _fDbModUse  := 2.0;                               // 兜底中限（Fallback moderate limit）
ELSE
    _fDbMaxUse := LIMIT(0.5, fDeadbandMax, 20.0);     // 上限钳进 0.5~20 %（Clamped）
    _fDbModUse := LIMIT(0.1, fDeadbandModerate, _fDbMaxUse); // 中限钳进 0.1~上限，与守卫同向（R35）
END_IF
_fDbSlightUse := _fDbModUse * DL_SLIGHT_RATIO;        // 轻微下限随中限缩放（Slight limit scales with moderate）
_fDbSlightUse := LIMIT(0.1, _fDbSlightUse, _fDbModUse); // 轻微下限钳进 0.1~中限（Clamped）

_fMoveUse := LIMIT(0.1, fMoveThr, 5.0);               // 位移阈钳进 0.1~5 %（Clamped）
_fStallUse := LIMIT(0.2, fStallThr, 10.0);            // 指令阈钳进 0.2~10 %（Clamped）
_nMinUse  := LIMIT(5, nMinSamples, 1000);             // 最少样本钳进 5~1000（Clamped）

_diWinMs := LIMIT(DL_WIN_MIN_MS, TIME_TO_DINT(tWindow), DL_WIN_MAX_MS); // 窗长钳位 [毫秒]（Clamped）
_tWindowUse := DINT_TO_TIME(_diWinMs);                // 生效窗长（Effective window）
_diSampleMs := _diWinMs / INT_TO_DINT(_nMinUse);      // 采样周期 = 窗长 ÷ 最少样本，除数恒 ≥5（Guarded divisor）
_diSampleMs := LIMIT(DL_SAMPLE_MIN_MS, _diSampleMs, DL_SAMPLE_MAX_MS); // 采样周期钳位（Clamped）
_tSampleUse := DINT_TO_TIME(_diSampleMs);             // 生效采样周期（Effective sample period）

_diWinMs := LIMIT(DL_STALL_MIN_MS, TIME_TO_DINT(tStallTime), DL_STALL_MAX_MS); // 停滞时长钳位（Clamped）
_tStallUse := DINT_TO_TIME(_diWinMs);                 // 生效停滞时长（Effective stall duration）
_diWinMs := LIMIT(DL_REV_MIN_MS, TIME_TO_DINT(tReverseTime), DL_REV_MAX_MS); // 反转延迟钳位（Clamped）
_tReverseUse := DINT_TO_TIME(_diWinMs);               // 生效反转延迟（Effective reverse delay）

(*------------------------------------------------------------------------------
 * 段 4｜定时器与边沿实例无条件刷新（红线：实例一律在 CASE 之外每拍必调）
 *      Timers and edge detectors refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);                           // 复位沿无条件刷新（Reset edge refreshed）

fbWindowWatch(IN := (_ePhase = E_DL_StictionPhase.eCollect) AND (NOT _bWindowBreak), PT := _tWindowUse); // 窗口计时
_bWindowBreak := FALSE;                               // 断输入拍在调用后自清（Break self-cleared）

fbSampleWatch(IN := (_ePhase = E_DL_StictionPhase.eCollect) AND (NOT _bSampleBreak), PT := _tSampleUse); // 采样周期计时
_bSampleBreak := FALSE;                               // 断输入拍在调用后自清（Break self-cleared）

fbStallWatch(IN := _bCmdMovedLatch AND (NOT _bPosMovedLatch) AND (NOT _bStallBreak), PT := _tStallUse); // 停滞计时
_bStallBreak := FALSE;                                // 断输入拍在调用后自清（Break self-cleared）
IF fbStallWatch.Q AND (_ePhase = E_DL_StictionPhase.eCollect) THEN
    _bStallEvent := TRUE;                             // 停滞事件单拍（Stall event, one scan）
    _bStallBreak := TRUE;                             // 事件后重启计时，防同一停滞重复计次（Restart to avoid double counting）
END_IF

fbReverseWatch(IN := _bRevPending AND (NOT _bPosMovedLatch) AND (NOT _bReverseBreak), PT := _tReverseUse); // 反转确认计时
_bReverseBreak := FALSE;                              // 断输入拍在调用后自清（Break self-cleared）
IF fbReverseWatch.Q AND (_ePhase = E_DL_StictionPhase.eCollect) THEN
    _bRevEvent     := TRUE;                           // 反转超时事件单拍（Reverse timeout, one scan）
    _bRevPending   := FALSE;                          // 事件已定性，撤待确认（Verdict reached, pending cleared）
    _bReverseBreak := TRUE;                           // 计时重启（Timer restarted）
END_IF

fbSinceWatch(IN := bEnable AND (NOT _bSinceBreak), PT := DL_SINCE_MAX); // 距上次停滞计时（封顶常量，不用裸时间字面量）
_bSinceBreak := FALSE;                                // 断输入拍在调用后自清（Break self-cleared）
_tSinceHeld  := fbSinceWatch.ET;                      // 时长在调用后取用（Elapsed read after the call）

(*------------------------------------------------------------------------------
 * 段 5｜输入域检查与钳位（非有限属故障级；有限越界只钳位）
 *      Input domain check: non-finite latches a fault, finite out-of-range is clamped
 *-----------------------------------------------------------------------------*)
(* 区间内写法做有限性判定：NaN 会让两侧比较同时为假，无需浮点判等 *)
_bCmdFinite := (fCmd >= -DL_VAL_LIM) AND (fCmd <= DL_VAL_LIM);
_bPosFinite := (fPos >= -DL_VAL_LIM) AND (fPos <= DL_VAL_LIM);
_fCmdUse := LIMIT(DL_REAL_MIN, fCmd, DL_REAL_MAX);    // 指令钳进 0~100 %（Clamped）
_fPosUse := LIMIT(DL_REAL_MIN, fPos, DL_REAL_MAX);    // 阀位钳进 0~100 %（Clamped）
IF NOT _bCmdFinite THEN
    _fCmdUse := 0.0;                                  // 非有限：置 0 防污染缓冲（Non-finite, zeroed to protect the buffer）
END_IF
IF NOT _bPosFinite THEN
    _fPosUse := 0.0;                                  // 非有限：置 0（Non-finite, zeroed）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜复位通道 + 故障锁存（CASE 前置；**不做状态变量赋值**，R39）
 *      Reset channel and fault latching before the CASE, with no state write
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    _bResetPulse := TRUE;                             // 复位单拍（One-shot reset）
END_IF

IF _bResetPulse THEN
    _bFaultLatch   := FALSE;                          // 清故障锁存（Latch cleared）
    _uErrFault     := 16#0000_0000;                   // 清首出码（First-out code cleared）
    _eLevel        := E_DL_StictionLevel.eNone;       // 等级回无黏滞（Level back to none）
    _fDbHeld       := 0.0;                            // 黏滞带回 0（Deadband back to zero）
    _uStallCount   := 0;                              // 停滞计数清零（Stall counter cleared）
    _bSuspectHeld  := FALSE;                          // 嫌疑位清零（Suspect cleared）
    _tSinceHeld    := DL_TIME_ZERO;                   // 计时清零（Elapsed cleared）
    _nSampleCount  := 0;                              // 样本数清零（Sample count cleared）
    _fDbSum        := 0.0;                            // 滞后累加清零（Hysteresis sum cleared）
    _nDbCount      := 0;                              // 滞后样本数清零（Hysteresis count cleared）
    _bHaveRev      := FALSE;                          // 反转记录清零（Reversal record cleared）
    _uWinCode      := 16#0000_0000;                   // 窗口码清零（Window code cleared）
    _bRebuildWin   := TRUE;                           // 复位后首窗视为重建窗（First window after reset is a rebuild）
    _bWindowBreak  := TRUE;                           // 窗口计时重启（Window timer restarted）
    _bSampleBreak  := TRUE;                           // 采样计时重启（Sample timer restarted）
    _bStallBreak   := TRUE;                           // 停滞计时重启（Stall timer restarted）
    _bReverseBreak := TRUE;                           // 反转计时重启（Reverse timer restarted）
    _bSinceBreak   := TRUE;                           // 距上次停滞计时重启（Since timer restarted）
END_IF

IF _bParamBad AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_031E;                     // 031E 阈值参数非法（Illegal thresholds）
    _bFaultLatch := TRUE;                             // 锁存（Latched）
ELSIF ((NOT _bCmdFinite) OR (NOT _bPosFinite)) AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_031D;                     // 031D 指令或阀位非有限（Non-finite input）
    _bFaultLatch := TRUE;                             // 锁存（Latched）
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜诊断相位机（6 个成员各一标签 + ELSE 兜底）
 *      Phase machine, one label per member plus a trailing fallback
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF

    E_DL_StictionPhase.eIdle: // 待机：参数与输入合法且使能后开始采集
        IF _bFaultLatch THEN
            _ePhase := E_DL_StictionPhase.eFault;     // 已锁故障（Already latched）
        ELSIF bEnable AND (NOT _bParamBad) THEN
            _nSampleCount := 0;                       // 新窗从 0 起（New window starts at zero）
            _fDbSum       := 0.0;                     // 滞后累加清零（Hysteresis sum cleared）
            _nDbCount     := 0;                       // 滞后样本数清零（Hysteresis count cleared）
            _bHaveRev     := FALSE;                   // 反转记录清零（Reversal record cleared）
            _nDir         := 0;                       // 方向静止（Direction still）
            _nDirPrev     := 0;                       // 上次方向静止（Previous direction still）
            _fOpPrev      := _fCmdUse;                // 首个样本基准（First sample baseline）
            _fPvPrev      := _fPosUse;                // 首个样本基准（First sample baseline）
            _uWinCode     := 16#0000_0000;            // 新窗清码（New window clears the code, R44）
            _bStallSeenWin := FALSE;                  // 新窗停滞证据清零（Window stall evidence cleared）
            _bRevSeenWin   := FALSE;                  // 新窗反转证据清零（Window reverse evidence cleared）
            _bWindowBreak := TRUE;                    // 窗口从 0 计时（Window starts from zero）
            _bSampleBreak := TRUE;                    // 采样从 0 计时（Sample timer starts from zero）
            _bStallBreak  := TRUE;                    // 停滞计时重启（Stall timer restarted）
            _bReverseBreak := TRUE;                   // 反转计时重启（Reverse timer restarted）
            _ePhase := E_DL_StictionPhase.eCollect;   // 进采集（Enter collection）
        END_IF

    E_DL_StictionPhase.eCollect: // 采集：入缓冲；反馈失效则挂起；窗口满或缓冲满则分析
        IF NOT bPosValid THEN
            _bPosValidSnap := FALSE;                  // 快照反馈失效（Snapshot invalid）
            _ePhase := E_DL_StictionPhase.eSuspend;   // 挂起（Suspend）
        ELSIF _bFaultLatch THEN
            _ePhase := E_DL_StictionPhase.eFault;     // 转故障（Enter the fault state）
        ELSIF fbWindowWatch.Q OR (_nSampleCount >= DL_BUF_MAX) THEN
            _bPosValidSnap := bPosValid;              // 窗口关闭时快照有效性（Snapshot validity at window close）
            _ePhase := E_DL_StictionPhase.eAnalyze;   // 进分析（Enter analysis）
        ELSIF NOT bEnable THEN
            _ePhase := E_DL_StictionPhase.eIdle;      // 掉使能冻结回待机（Disabled, freeze back to idle）
        END_IF

    E_DL_StictionPhase.eAnalyze: // 分析：仅在窗口关闭当拍执行一次，产物写入候选量
        IF NOT bEnable THEN
            _ePhase := E_DL_StictionPhase.eIdle;      // 掉使能中止（Disabled, abort）
        ELSE
            _ePhase := E_DL_StictionPhase.eVerdict;   // 无条件推进，判定相做复验（Always advance, verdict re-verifies）
        END_IF

    E_DL_StictionPhase.eVerdict: // 判定：本拍复验后发布，然后开新窗
        IF bEnable THEN
            _ePhase := E_DL_StictionPhase.eCollect;   // 出结论后回采集（Back to collection）
        ELSE
            _ePhase := E_DL_StictionPhase.eIdle;      // 掉使能中止（Disabled, abort）
        END_IF

    E_DL_StictionPhase.eSuspend: // 挂起：非故障，恢复后窗口重建（R41：不沿用旧窗）
        IF _bFaultLatch THEN
            _ePhase := E_DL_StictionPhase.eFault;     // 转故障（Enter the fault state）
        ELSIF bPosValid THEN
            _nSampleCount := 0;                       // 恢复首拍样本数从 0 重建（Samples rebuilt from zero）
            _fDbSum       := 0.0;                     // 滞后累加清零（Hysteresis sum cleared）
            _nDbCount     := 0;                       // 滞后样本数清零（Hysteresis count cleared）
            _bHaveRev     := FALSE;                   // 反转记录清零（Reversal record cleared）
            _nDir         := 0;                       // 方向静止（Direction still）
            _nDirPrev     := 0;                       // 上次方向静止（Previous direction still）
            _fOpPrev      := _fCmdUse;                // 重建基准（Rebuild baseline）
            _fPvPrev      := _fPosUse;                // 重建基准（Rebuild baseline）
            _bRebuildWin  := TRUE;                    // 首窗只重建不发布（First window rebuilds only）
            _uWinCode     := 16#0000_0000;            // 新窗清码（New window clears the code）
            _bStallSeenWin := FALSE;                  // 重建窗证据清零（Rebuild window evidence cleared）
            _bRevSeenWin   := FALSE;                  // 重建窗证据清零（Rebuild window evidence cleared）
            _bWindowBreak := TRUE;                    // 窗口重启（Window restarted）
            _bSampleBreak := TRUE;                    // 采样重启（Sample restarted）
            _bStallBreak  := TRUE;                    // 停滞计时重启（Stall timer restarted）
            _bReverseBreak := TRUE;                   // 反转计时重启（Reverse timer restarted）
            _ePhase := E_DL_StictionPhase.eCollect;   // 回采集（Back to collection）
        END_IF

    E_DL_StictionPhase.eFault: // 故障：等复位且原因消失
        IF _bResetPulse THEN
            _ePhase := E_DL_StictionPhase.eIdle;      // 复位受理：回待机（Reset accepted, back to idle）
        END_IF

    ELSE
        _uErrFault   := 16#0003_031F;                 // 031F 非法状态兜底（Illegal state fallback）
        _bFaultLatch := TRUE;                         // 兜底锁存（Fallback latched）
        _ePhase      := E_DL_StictionPhase.eFault;    // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜采样采集与判据累计（仅采集相；每采集一次推进一次方向与滞后统计）
 *      Sample capture and criterion accumulation, collection phase only
 *-----------------------------------------------------------------------------*)
IF (_ePhase = E_DL_StictionPhase.eCollect) AND fbSampleWatch.Q THEN

    (* 入缓冲：先算落位下标，再上下界校验，绝不越界写（Compute the slot, then check both bounds） *)
    IF UINT_TO_DINT(_nSampleCount) < UINT_TO_DINT(DL_BUF_MAX) THEN
        _nSlot := UINT_TO_DINT(_nSampleCount) + 1;    // 落位下标 = 已有样本数 + 1（Slot = count + 1）
        IF (_nSlot >= LOWER_BOUND(_afOpWin, 1)) AND (_nSlot <= UPPER_BOUND(_afOpWin, 1)) THEN
            _afOpWin[_nSlot] := _fCmdUse;             // 缓存指令（Buffer the command）
            _afPvWin[_nSlot] := _fPosUse;             // 缓存阀位（Buffer the position）
            _nSampleCount := _nSampleCount + 1;       // 写入成功后才计数（Count only after a successful write）
        END_IF
    END_IF

    (* 方向判定与方向性滞后：同 OP 处两向行程的 PV 差即黏滞带样本 *)
    IF (_fCmdUse - _fOpPrev) > DL_EPS THEN
        _nDir := 1;                                   // 上升行程（Rising travel）
    ELSIF (_fOpPrev - _fCmdUse) > DL_EPS THEN
        _nDir := -1;                                  // 下降行程（Falling travel）
    ELSE
        _nDir := 0;                                   // 静止（Still）
    END_IF

    IF (_nDir <> 0) AND (_nDirPrev <> 0) AND (_nDir <> _nDirPrev) THEN
        (* 方向反转：与前一次反转比较同一 OP 处的 PV 差（Reversal: compare positions at the same command） *)
        IF _bHaveRev AND (ABS(_fOpRev - _fCmdUse) <= _fDbMaxUse) THEN
            _fCell := ABS(_fPvRev - _fPosUse);        // 滞后样本（Hysteresis sample）
            IF _fCell <= DL_REAL_MAX THEN
                _fDbSum := _fDbSum + _fCell;          // 滞后累加（Accumulate）
                IF _nDbCount < 65535 THEN
                    _nDbCount := _nDbCount + 1;       // 样本计数防上溢（Guard the counter）
                END_IF
            END_IF
        END_IF
        _fOpRev  := _fCmdUse;                         // 记录本次反转点（Record the reversal）
        _fPvRev  := _fPosUse;                         // 记录本次反转点（Record the reversal）
        _bHaveRev := TRUE;                            // 已有反转基准（A reversal baseline exists）
        _bRevPending := TRUE;                         // 反转待确认计时开始（Start the confirmation timer）
        _bReverseBreak := TRUE;                       // 新反转重启计时（Restart the timer）
    END_IF

    IF _nDir <> 0 THEN
        _nDirPrev := _nDir;                           // 记录方向（Record the direction）
    END_IF

    (* 跨采样保持的移动标志：供停滞与反转定时器使用（Latched movement flags） *)
    _bCmdMovedLatch := ABS(_fCmdUse - _fOpPrev) > _fStallUse; // 指令在变（Command moving）
    _bPosMovedLatch := ABS(_fPosUse - _fPvPrev) > _fMoveUse;  // 阀位在动（Position moving）
    IF _bPosMovedLatch THEN
        _bRevPending := FALSE;                        // 阀位已动，反转确认完成（Position moved, confirmation done）
    END_IF

    _fOpPrev := _fCmdUse;                             // 更新上一样本（Update the previous sample）
    _fPvPrev := _fPosUse;                             // 更新上一样本（Update the previous sample）

    _bSampleBreak := TRUE;                            // 本次采样完成，采样计时重启（Restart the sample timer）
END_IF

(* 事件消费独立成段：事件在段 4 由定时器置位，若本拍恰好换相也不能丢（Never lose an event）
 * 停滞与反转超时都属「证据」，本窗内只增不减（Evidence accumulates within the window） *)
IF _bStallEvent THEN
    IF _uStallCount < 16#FFFF_FFFF THEN
        _uStallCount := _uStallCount + 1;             // 停滞计数防上溢（Guard the counter）
    END_IF
    _bStallSeenWin := TRUE;                           // 本窗停滞证据（Stall evidence in this window）
    _bSuspectHeld  := TRUE;                           // 嫌疑位（Suspect flag）
    _bSinceBreak   := TRUE;                           // 距上次停滞计时重启（Since timer restarted）
END_IF
IF _bRevEvent THEN
    _bRevSeenWin := TRUE;                             // 本窗反转证据（Reverse evidence in this window）
    _bSuspectHeld := TRUE;                            // 嫌疑位（Suspect flag）
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜分析计算（仅分析相，单拍；全部边界量取自缓冲与快照，R38）
 *      Window analysis, single scan, boundaries taken from the buffer and snapshot
 *-----------------------------------------------------------------------------*)
IF _ePhase = E_DL_StictionPhase.eAnalyze THEN
    _uWinCode := 16#0000_0000;                        // 新轮起点清码（Clear the window code at the start of a round, R44）

    (* 窗内指令行程：用于识别「工艺停机导致的长期静止」 *)
    _fOpMin := DL_REAL_MAX;                           // 最小值先置上界（Minimum preset to the upper bound）
    _fOpMax := DL_REAL_MIN;                           // 最大值先置下界（Maximum preset to the lower bound）
    FOR _nIdx := 1 TO 128 DO
        IF (_nIdx >= LOWER_BOUND(_afOpWin, 1)) AND (_nIdx <= UPPER_BOUND(_afOpWin, 1)) THEN
            IF _nIdx <= UINT_TO_DINT(_nSampleCount) THEN
                _fCell := _afOpWin[_nIdx];            // 取缓存指令（Read the buffered command）
                IF _fCell < _fOpMin THEN
                    _fOpMin := _fCell;                // 更新最小（Update the minimum）
                END_IF
                IF _fCell > _fOpMax THEN
                    _fOpMax := _fCell;                // 更新最大（Update the maximum）
                END_IF
            END_IF
        END_IF
    END_FOR
    IF _nSampleCount > 0 THEN
        _fOpSpan := _fOpMax - _fOpMin;                // 窗内行程（Command span）
    ELSE
        _fOpSpan := 0.0;                              // 无样本：行程 0（No samples, zero span）
    END_IF
    _bStaticWindow := _fOpSpan < _fStallUse;          // 指令几乎未动：工艺停机（Command static, plant stopped）

    (* 窗口合法性闸门：快照有效性 + 样本数（两条都用快照/缓冲，不读实时量） *)
    IF NOT _bPosValidSnap THEN
        _bCandValid := FALSE;                         // 快照失效：不出候选（Snapshot invalid, no candidate）
        _uWinCode   := 16#0003_015D;                  // 015D 反馈失效导致挂起（Suspended due to invalid feedback）
    ELSIF _nSampleCount < INT_TO_UINT(_nMinUse) THEN
        _bCandValid := FALSE;                         // 样本不足：保持上次等级（Insufficient samples, hold the level）
        _uWinCode   := 16#0003_015C;                  // 015C 样本不足未评级（Insufficient samples）
    ELSE
        _bCandValid := TRUE;                          // 样本充足，可评级（Enough samples, a verdict is possible）
    END_IF

    IF _bCandValid THEN
        IF _nDbCount > 0 THEN
            _fDbWin := _fDbSum / UINT_TO_REAL(_nDbCount); // 平均滞后，分母已守卫（Guarded average）
        ELSE
            _fDbWin := 0.0;                           // 无滞后样本：黏滞带 0（No hysteresis samples）
        END_IF
        _fCandDb := LIMIT(DL_REAL_MIN, _fDbWin, DL_REAL_MAX); // 候选黏滞带钳进 0~100（Clamped）

        (* 等级判据：先判最严，向下逐级；三条判据并发，缺一不升级 *)
        IF _fCandDb >= _fDbMaxUse THEN
            _eCandLevel := E_DL_StictionLevel.eSevere; // 超上限判重度（Above the severe limit）
        ELSIF _fCandDb >= _fDbModUse THEN
            _eCandLevel := E_DL_StictionLevel.eModerate; // 超中限判中度（Above the moderate limit）
        ELSIF _fCandDb >= _fDbSlightUse THEN
            _eCandLevel := E_DL_StictionLevel.eSlight; // 超轻微下限（Above the slight limit）
        ELSE
            _eCandLevel := E_DL_StictionLevel.eNone;  // 滞后在噪声带内（Within the noise band）
        END_IF

        (* 并发裁定：中度及以上必须有停滞或反转证据，否则封顶轻微 *)
        IF (_eCandLevel = E_DL_StictionLevel.eModerate) OR (_eCandLevel = E_DL_StictionLevel.eSevere) THEN
            IF (NOT _bStallSeenWin) AND (NOT _bRevSeenWin) THEN
                _eCandLevel := E_DL_StictionLevel.eSlight; // 单一指标越限，封顶轻微（Cap at slight without corroboration）
            END_IF
        END_IF

        (* 工艺停机抑制：窗内指令几乎未动时，停滞判据无意义（Static plant suppresses the stall criterion） *)
        IF _bStaticWindow THEN
            _uWinCode := 16#0003_015E;                // 015E 阀位长期静止，停滞判据被抑制（Stall suppressed）
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜发布与窗口重建（判定相；本拍复验 bPosValid，R42）
 *      Publish with a same-scan validity re-check, then rebuild the window
 *-----------------------------------------------------------------------------*)
IF _ePhase = E_DL_StictionPhase.eVerdict THEN
    _bCurValid := bPosValid;                          // 本拍复验：与取值同拍（Re-verify in the same scan as the publish）

    IF (NOT _bCurValid) THEN
        _uWinCode := 16#0003_015D;                    // 015D 反馈失效，不发布新等级（Invalid feedback, publish nothing）
    ELSIF _bRebuildWin THEN
        _bRebuildWin := FALSE;                        // 重建窗只消费一次（The rebuild window is consumed once）
        _uWinCode := 16#0003_015C;                    // 015C 重建窗不发布，保持上次等级（Rebuild window publishes nothing）
    ELSIF _bCandValid THEN
        _eLevel := _eCandLevel;                       // 发布新等级（Publish the new level）
        _fDbHeld := _fCandDb;                         // 发布黏滞带（Publish the deadband）
    END_IF

    (* 开新窗：样本与统计清零，定时器断输入（R40 段边界）；证据按窗清（R44） *)
    _bStallSeenWin := FALSE;                          // 新窗停滞证据清零（Window stall evidence cleared）
    _bRevSeenWin   := FALSE;                          // 新窗反转证据清零（Window reverse evidence cleared）
    _nSampleCount := 0;                               // 样本数清零（Sample count cleared）
    _fDbSum       := 0.0;                             // 滞后累加清零（Hysteresis sum cleared）
    _nDbCount     := 0;                               // 滞后样本数清零（Hysteresis count cleared）
    _bHaveRev     := FALSE;                           // 反转记录清零（Reversal record cleared）
    _bWindowBreak := TRUE;                            // 窗口重启（Window restarted）
    _bSampleBreak := TRUE;                            // 采样重启（Sample restarted）
    _bStallBreak  := TRUE;                            // 停滞计时重启（Stall timer restarted）
    _bReverseBreak := TRUE;                           // 反转计时重启（Reverse timer restarted）
    _bRevPending  := FALSE;                           // 反转待确认清零（Reversal pending cleared）
    _fOpPrev      := _fCmdUse;                        // 新窗基准（New window baseline）
    _fPvPrev      := _fPosUse;                        // 新窗基准（New window baseline）
    _nDir         := 0;                               // 方向静止（Direction still）
    _nDirPrev     := 0;                               // 上次方向静止（Previous direction still）
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜健康仲裁、出口钳位与保持重写（R27 + R43）
 *      Health arbitration, outlet clamping and hold semantics
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _eHealthInt := E_DL_Ne107Status.eFailure;         // 失效：参数非法或非有限输入（Failure）
ELSIF _eLevel = E_DL_StictionLevel.eSevere THEN
    _eHealthInt := E_DL_Ne107Status.eOutOfSpec;       // 重度黏滞：仍可运行但超规（Severe, still running）
ELSIF (_eLevel = E_DL_StictionLevel.eModerate) OR (_eLevel = E_DL_StictionLevel.eSlight) THEN
    _eHealthInt := E_DL_Ne107Status.eMaintenanceReq;  // 轻中度：排入维护计划（Maintenance required）
ELSIF NOT bEnable THEN
    _eHealthInt := E_DL_Ne107Status.eUnknown;         // 未使能（Disabled）
ELSE
    _eHealthInt := E_DL_Ne107Status.eOk;              // 无黏滞（No stiction）
END_IF

eHealth          := _eHealthInt;                      // 健康态出口（Health outlet）
eStiction        := _eLevel;                          // 等级保持重写（Held level rewritten every scan）
fDeadbandEst     := LIMIT(DL_REAL_MIN, _fDbHeld, DL_REAL_MAX); // 黏滞带钳进 0~100（Clamped, R43）
fHysteresisRatio := LIMIT(0.0, fDeadbandEst / DL_REAL_MAX, 1.0); // 归一指标钳进 0~1，除数恒 100（Clamped）
nStallCount      := _uStallCount;                     // 停滞计数出口（Stall counter outlet）
tSinceLastStall  := _tSinceHeld;                      // 距上次停滞时长出口（Elapsed outlet）
nSampleCount     := _nSampleCount;                    // 本窗样本数出口（Sample count outlet）
bStictionSuspect := _bSuspectHeld;                    // 嫌疑位保持重写（Held suspect flag）
bError           := _bFaultLatch;                     // 故障位只反映锁存（Latch only）

(*------------------------------------------------------------------------------
 * 段 12｜码位单一优先级链（全拍只写一次 uDiagCode）
 *      Single priority chain, the diagnostic code is written exactly once
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _uDiagCode := _uErrFault;                         // 故障级优先，保留首出码（Fault level, first-out code）
ELSIF _ePhase = E_DL_StictionPhase.eSuspend THEN
    _uDiagCode := 16#0003_015D;                       // 015D 挂起提示（Suspension advisory）
ELSIF _uWinCode <> 16#0000_0000 THEN
    _uDiagCode := _uWinCode;                          // 本窗信息码（Window info code）
ELSE
    _uDiagCode := 16#0000_0000;                       // 无码（No code）
END_IF

uDiagCode := _uDiagCode;                              // 诊断码出口（Diagnostic code outlet）
uErrorId  := _uErrFault;                              // 末次故障码出口（Last fault code outlet）

END_FUNCTION_BLOCK
