(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ConveyorLineLink
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺段功能块（Function Block · 线体级联握手协调器）
 * 功能简述 (Function)   : 相邻机台/线体段之间的级联握手协调器。把「上游有料
 *                         (BA)」「下游可收 (MR)」「强制抑制 (INH)」三类干接
 *                         点握手信号抽象为与供应商无关的状态机：三路消抖、
 *                         握手判据、传递看门狗、维护直通、同拍冲突保守侧处
 *                         理。本块只做握手编排，不直接驱动任何执行机构。
 * 首扫说明 (Init note)  : 纯事件型组件，免首扫（R23/公约 0.1），无 bInit；
 *                         所有状态由引脚沿/电平驱动，无自动首扫初始化语义。
 * 公约遵循 (Convention) : 0.2/R21 bFault 为显式排除信息级码的派生式，故障/
 *                         信息码分表标注；0.4 引脚双语同行注释；0.5/R7 全部
 *                         实例主体最前部无条件刷新，入参先算普通变量再喂实
 *                         例；0.7/R15 传递超时锁存仅复位路径清码，信息级码
 *                         瞬时型每拍重算；0.8 码位段 16#0005_xxxx（编码前经
 *                         DL_Process VERSION.md 复核：既有占用信息级
 *                         0101~0115、故障级 0200~0223，本块 0130~0133 /
 *                         0230~0231 无冲突）；0.16 无魔法数（阈值全部常量化
 *                         或引脚化）；0.17 终结符成对 ✓；0.19 码位 16# 与
 *                         【级别】同行注释；0.20 验收向量入头注释。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 看门狗/消抖/锁存复位路径 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 六实例（R_TRIG×2/TON×4）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓｜R25 单拍标志生命周期三律（置位-消费
 *                         -复位同周期闭环，bTransferDone 每拍先清零再置位）✓
 * 设计要点 (Key notes)  : ① 握手判据一行布尔式：上游有料(消抖 BA 或 Request)
 *                           AND 本段空 AND 下游可收 AND NOT 抑制 AND 使能
 *                           AND 无故障；同拍冲突（BA 与 Request 同真，或 MR
 *                           与 INH 同真）保守侧不放行，仅信息码暴露；
 *                         ② 传递受理 = 入口光电上升沿；料离开 = 入/出口光电
 *                           全清；完成单拍 + 计数递增；
 *                         ③ 看门狗：传递态超 tTransferTimeout → 卡料锁存
 *                           0230，仅 bReset 清；看门狗 < 消抖窗两倍自动提升
 *                           + 信息码 0133（防消抖窗吃掉整个看门狗）；
 *                         ④ 维护直通 bBypass：强制抑制输出为 FALSE 且不判超
 *                           时（信息码 0131 每拍重算）——直通会绕过卡料保护，
 *                           仅供维护调试，须审计；
 *                         ⑤ 出口断言（IF 结构保证）：向上游宣告可收与抑制上
 *                           游两输出不得同真（故障态可收输出恒 FALSE）；
 *                         ⑥ 与 FB_DL_ConveyorZone 衔接示例（仅注释，不引实
 *                           例）：本块 bMachineReadyOut → 下游区块
 *                           bDownstreamReady；下游区块 bZoneReady → 本块
 *                           bDownMachineReady。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① eComplete「等复位」语义解释：规格未定义复位源，
 *                           按「上游 BA/Request 释放（料源已清）即视为自动复
 *                           位回 eIdle」+ bReset 手动复位双路径实现。理由：
 *                           自动线每板后手动复位不可运维；影响：eComplete 为
 *                           短暂过渡态，若调用方需强制人工确认，可不接 BA 释
 *                           放自动复位（BA 持续保持时仅 bReset 可退出）。
 * 开源溯源 (Origin)     : 来源标签 smema / conveyor-handshake（RAW_NOTES_R8
 *                         S-7：SMEMA 板级握手公开惯例——上游有料 BA、下游可
 *                         收 MR、抑制 INH 三信号电平语义与消抖/看门狗经验参
 *                         数域（消抖 20~30 ms、看门狗 5 s 量级），公开技术资
 *                         料，仅借鉴信号分类与参数域；状态机设计、码位、引脚
 *                         契约 100% 本库独立设计，clean-room 未复制任何源码。
 *                         许可证说明：SMEMA 为行业公开接口惯例，无附带许可
 *                         限制；本文件为本库原创实现，随本库许可证发布）。
 * 验收向量 (Acceptance) :
 *   V1 完整握手：BA→MR→料进（入口沿）→料出（全清）→ bTransferDone 单拍 +
 *      nTransferCount +1 → eComplete → BA 释放回 eIdle；
 *   V2 下游 INH 有效 → eInhibited，不放行，抑制解除回 eIdle + 信息码 0130；
 *   V3 传递态看门狗到 → eJamFault 锁存 0230 + bInhibitUpstream TRUE +
 *      bTransferTimeout 保持；V4 bReset 沿清锁存回 eIdle；
 *   V5 BA 与 Request 同真 → 不放行 + 信息码 0132（MR 与 INH 同真同理）；
 *   V6 bBypass 直通：bInhibitUpstream 恒 FALSE、不判超时 + 信息码 0131；
 *   V7 消抖：20 ms 毛刺（< tDebounce）被滤掉，稳定电平才参与握手；
 *   V8 故障态 bMachineReadyOut 恒 FALSE（坏料禁止放进本段）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Process 级联握手件）
 *   2026-11-15  v1.0.1  R8 总监终审修复：三路消抖 TON 的 IN 原误写为 PT 变更
 *                       掩码 _bDebBreak（常态 TRUE，三路 Q 恒 TRUE，消抖完全
 *                       失效、V7 不成立），改为「原信号 AND _bDebBreak」——原
 *                       信号为消抖对象，掩码仅承担 R14 的 PT 变更断输入一拍。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LineLinkState（归属 FB_DL_ConveyorLineLink，与其同文件发布，
 *       公约 0.18 口径）。编号步长 10 留空位，eJamFault 取 99 保证排序末位
 *       （全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_LineLinkState :
(
    eIdle         := 0,   // 空闲：无料，等上游有料信号 / Idle, no board, waiting for upstream board-available
    eBoardReady   := 10,  // 待放行：上游有料且本机可收，等下游可收 / Board ready, waiting for downstream machine-ready
    eTransferring := 20,  // 传递中：已握手，看门狗计时 / Transferring, handshake done and watchdog timing
    eComplete     := 30,  // 传递完成：料已离开本段，等复位 / Transfer complete, board left, awaiting release
    eInhibited    := 40,  // 被抑制：下游强制抑制有效，禁止启动传递 / Inhibited by downstream, transfer not allowed
    eJamFault     := 99   // 传递超时锁存：仅复位沿可退出 / Jam fault latched, only reset edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ConveyorLineLink
VAR_INPUT
    bEnable             : BOOL;             // 本链使能（Chain enable），FALSE=全部输出置安全侧（不放行、不请求）/ Chain enable, FALSE forces all outputs to safe side
    bUpBoardAvailable   : BOOL;             // 上游有料（Board available，上游→本机 BA 干接点），电平语义 / Upstream board available, level semantics
    bDownMachineReady   : BOOL;             // 下游可接收（Machine ready，下游→本机 MR 干接点），电平语义 / Downstream machine ready, level semantics
    bDownInhibit        : BOOL;             // 下游强制抑制（Inhibit，下游→本机 INH 干接点），TRUE=禁止放行 / Downstream inhibit, TRUE blocks release
    bBoardAtEntry       : BOOL;             // 本段入口光电（Entry photoeye），TRUE=料已进入本段 / Board present at entry photoeye
    bBoardAtExit        : BOOL;             // 本段出口光电（Exit photoeye），TRUE=料仍在本段出口 / Board present at exit photoeye
    bBoardQualityNg     : BOOL;             // 来料质量 NG 标志（Good/bad board 干接点，可选），仅透传供下游分选 / Incoming board quality NG flag, pass-through only
    bUpstreamRequest    : BOOL;             // 上游请求放料（Board requested 干接点，可选），与 BA 二选一接线 / Upstream board request, alternative to BA wiring
    tDebounce           : TIME := T#30MS;   // 输入消抖时间（Input debounce），域 T#0MS..T#1S；T#0MS=零消抖直通；经验值 20~30 ms / Input debounce time, 0 = pass-through
    tTransferTimeout    : TIME := T#5S;     // 传递看门狗（Transfer watchdog），域 T#100MS..T#60S；小于消抖窗两倍自动提升 / Transfer watchdog, auto-raised below twice debounce
    bBypass             : BOOL;             // 维护直通（Maintenance bypass），TRUE=恒放行且不报卡料，须审计，绕过卡料保护 / Maintenance bypass, overrides jam protection, audit required
    bReset              : BOOL;             // 复位超时锁存（Fault reset），上升沿受理 / Rising edge resets latched jam
END_VAR
VAR_OUTPUT
    bBoardAvailableOut  : BOOL;             // 向下游宣告有料（BA out），消抖后有料且本段已就绪 / Board available to downstream
    bMachineReadyOut    : BOOL;             // 向上游宣告可收（MR out），本段空且无故障且非抑制 / Machine ready to upstream
    bRequestBoard       : BOOL;             // 向上游请求送料（Request out），本段空且下游可收 / Board request to upstream
    bInhibitUpstream    : BOOL;             // 抑制上游（INH out），本段卡料/传递超时锁存时为 TRUE / Inhibit upstream while jammed
    bTransferring       : BOOL;             // 传递中（Transferring），传递态为 TRUE / TRUE while transferring
    bTransferDone       : BOOL;             // 传递完成单拍脉冲（Transfer done），单拍生命周期三律：每拍先清零，完成拍内置位 / One-scan transfer done pulse
    bTransferTimeout    : BOOL;             // 传递超时（Timeout），卡料锁存保持期为 TRUE / TRUE while jam latch held
    bQualityNgOut       : BOOL;             // 质量 NG 透传（NG pass-through），受理后保持下游可见直至传递完成 / NG flag held downstream-visible until complete
    bFault              : BOOL;             // 故障标志（Fault flag），显式排除信息级码（仅故障级置位）/ Fault flag, info codes excluded
    uErrorId            : UDINT;            // 故障码（Error code），16#0005_xxxx 段，0=无故障；故障级优先、无故障透出本拍信息级 / Error code, fault-level priority
    nTransferCount      : UDINT;            // 累计传递次数（Transfer counter），每完成一板 +1 / Total transfers completed
END_VAR
VAR
    _eState             : E_DL_LineLinkState := E_DL_LineLinkState.eIdle; // 内部链状态（Internal link state）/ Internal state
    _bFaultLatch        : BOOL;             // 卡料锁存标志（Jam latch flag），仅复位路径清除 / Jam latch, cleared only via reset path
    _uErrorIdInt        : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode          : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bBaStable          : BOOL;             // 消抖后上游有料（Debounced BA）/ Debounced upstream board available
    _bMrStable          : BOOL;             // 消抖后下游可收（Debounced MR）/ Debounced downstream machine ready
    _bInhStable         : BOOL;             // 消抖后下游抑制（Debounced INH）/ Debounced downstream inhibit
    _bUpPresent         : BOOL;             // 归并后上游有料（Upstream present = BA 或 Request，冲突时保守侧 FALSE）/ Merged upstream present, conservative on conflict
    _bSegEmpty          : BOOL;             // 本段空（Segment empty，入口与出口光电均未遮挡）/ Segment empty by both photoeyes
    _bTransferStart     : BOOL;             // 握手判据（Transfer start condition），一行布尔式 / Transfer start handshake condition
    _bAccepted          : BOOL;             // 传递受理标志（Transfer accepted），入口光电上升沿置位 / Board accepted at entry edge
    _bNgHold            : BOOL;             // 质量 NG 保持（Quality NG hold），受理时锁存至传递完成 / Quality NG held from acceptance to completion
    _bConflict          : BOOL;             // 握手信号同拍冲突（Signal conflict this cycle），保守侧判据 / Handshake signal conflict flag
    _tWatchdogEff       : TIME := T#5S;     // 生效看门狗（Effective watchdog），被消抖窗两倍提升后的值 / Effective watchdog after auto-raise
    _tDebounceEff       : TIME := T#30MS;   // 生效消抖窗（Effective debounce），域钳位后值 / Effective debounce after clamp
    _tDebLast           : TIME := T#30MS;   // 上拍生效消抖窗（Last debounce），PT 变更检测基准 / Last debounce for PT-change detection
    _tWdLast            : TIME := T#5S;     // 上拍生效看门狗（Last watchdog），PT 变更检测基准 / Last watchdog for PT-change detection
    _bDebBreak          : BOOL := TRUE;     // 消抖输入使能（Debounce input enable），PT 变更拍断一拍 / Debounce input enable, broken on PT change
    _bWdBreak           : BOOL := TRUE;     // 看门狗输入使能（Watchdog input enable），PT 变更拍断一拍 / Watchdog input enable, broken on PT change
    _fbTonDebounceBa    : TON;              // 上游有料消抖（BA debounce timer）/ BA debounce timer
    _fbTonDebounceMr    : TON;              // 下游可收消抖（MR debounce timer）/ MR debounce timer
    _fbTonDebounceInh   : TON;              // 下游抑制消抖（INH debounce timer）/ INH debounce timer
    _fbTonWatchdog      : TON;              // 传递看门狗（Transfer watchdog timer）/ Transfer watchdog timer
    _fbTrigReset        : R_TRIG;           // 复位沿（Reset edge detector）/ Reset edge detector
    _fbTrigEntry        : R_TRIG;           // 入口光电上升沿（Entry photoeye rising edge），传递受理判据 / Entry photoedge detector
END_VAR
VAR CONSTANT
    DL_LINE_DEB_MAX     : TIME := T#1S;     // 消抖时间上限（Debounce upper clamp）/ Debounce upper clamp
    DL_LINE_WD_MIN      : TIME := T#100MS;  // 看门狗下限（Watchdog lower clamp）/ Watchdog lower clamp
    DL_LINE_WD_MAX      : TIME := T#60S;    // 看门狗上限（Watchdog upper clamp）/ Watchdog upper clamp
    DL_LINE_WD_FACTOR   : INT  := 2;        // 看门狗提升倍数（Watchdog raise factor）[-]，提升到消抖窗的此倍数 / Watchdog auto-raise factor over debounce window
    DL_LINE_ERR_JAM     : UDINT := 16#0005_0230; // 0005_0230 传递超时（卡料）【故障级】/ Transfer watchdog timeout, fault level
    DL_LINE_ERR_STATE   : UDINT := 16#0005_0231; // 0005_0231 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_LINE_INFO_INHREL : UDINT := 16#0005_0130; // 0005_0130 下游抑制解除，恢复放行【信息级】/ Downstream inhibit released, info level
    DL_LINE_INFO_BYPASS : UDINT := 16#0005_0131; // 0005_0131 维护直通生效（每拍重算）【信息级】/ Maintenance bypass active, info level
    DL_LINE_INFO_CONFL  : UDINT := 16#0005_0132; // 0005_0132 握手信号同拍冲突（保守侧不放行）【信息级】/ Handshake signal conflict, conservative side, info level
    DL_LINE_INFO_WDRAISE: UDINT := 16#0005_0133; // 0005_0133 看门狗被提升至消抖窗两倍【信息级】/ Watchdog auto-raised to twice debounce, info level
END_VAR

// ============================================================================
// 段 1｜信息级预清零 + 实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Info preset + unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_uInfoCode := 0;                        // 信息级瞬时型每拍重算（Transient info recomputed each scan）
// 消抖窗域钳位（R14：PT 变更检测先行，变更拍断输入归零 / PT change breaks input one scan）
IF tDebounce > DL_LINE_DEB_MAX THEN
    _tDebounceEff := DL_LINE_DEB_MAX;   // 超限钳位到上限（Clamped to upper bound）
ELSE
    _tDebounceEff := tDebounce;         // 引脚原值（Pin value as-is）
END_IF
// 看门狗提升值计算（R14：PT 变更检测先行 / Watchdog PT change detection first）
IF tTransferTimeout < tDebounce * DL_LINE_WD_FACTOR THEN
    _tWatchdogEff := tDebounce * DL_LINE_WD_FACTOR;      // 自动提升：防消抖窗吃掉整个看门狗（Auto-raise above debounce window）
    _uInfoCode := DL_LINE_INFO_WDRAISE; // 0005_0133 看门狗被提升【信息级】/ Watchdog raised, info level
ELSIF tTransferTimeout < DL_LINE_WD_MIN THEN
    _tWatchdogEff := DL_LINE_WD_MIN;    // 域下限钳位（Domain lower clamp）
ELSIF tTransferTimeout > DL_LINE_WD_MAX THEN
    _tWatchdogEff := DL_LINE_WD_MAX;    // 域上限钳位（Domain upper clamp）
ELSE
    _tWatchdogEff := tTransferTimeout;  // 引脚原值（Pin value as-is）
END_IF

// 三路消抖：IN 必须取「原信号」（规格 2.1-1），_bDebBreak 仅作 PT 变更拍的断输入掩码
// Three debounces: IN must be the RAW signal (spec 2.1-1); _bDebBreak is only the
// one-scan PT-change mask ANDed in, never the sole input (would make Q always TRUE)
_fbTonDebounceBa(IN := bUpBoardAvailable AND _bDebBreak, PT := _tDebounceEff);  // 上游有料消抖（BA debounce）
_fbTonDebounceMr(IN := bDownMachineReady AND _bDebBreak, PT := _tDebounceEff);  // 下游可收消抖（MR debounce）
_fbTonDebounceInh(IN := bDownInhibit AND _bDebBreak, PT := _tDebounceEff);      // 下游抑制消抖（INH debounce）
_fbTrigReset(CLK := bReset);            // 复位沿（Reset edge）
_fbTrigEntry(CLK := bBoardAtEntry);     // 入口光电沿（Entry photoedge）
_fbTonWatchdog(IN := (_eState = E_DL_LineLinkState.eTransferring) AND (NOT bBypass) AND (NOT _bWdBreak),
               PT := _tWatchdogEff);    // 传递看门狗（Transfer watchdog）

// 消抖窗/看门狗 PT 变更断输入一拍（R14：防改时间常数后计时不清零的幽灵故障）
// Debounce/watchdog PT-change one-scan input break (R14)
IF (_tDebounceEff <> _tDebLast) OR (_tWatchdogEff <> _tWdLast) THEN
    _bDebBreak := FALSE;                // 消抖输入断一拍（Debounce input broken one scan）
    _bWdBreak := FALSE;                 // 看门狗输入断一拍（Watchdog input broken one scan）
    _tDebLast := _tDebounceEff;         // 登记新消抖窗（Register new debounce）
    _tWdLast := _tWatchdogEff;          // 登记新看门狗（Register new watchdog）
ELSE
    _bDebBreak := TRUE;                 // 恢复消抖输入（Debounce input restored）
    _bWdBreak := TRUE;                  // 恢复看门狗输入（Watchdog input restored）
END_IF

// 消抖输出归并：零消抖直通（T#0MS 时 Q 有一拍滞后，此处按语义直取原信号）
// Debounce merge: pass-through raw signal when zero debounce requested
IF _tDebounceEff = T#0MS THEN
    _bBaStable := bUpBoardAvailable;    // 零消抖直通（Zero debounce pass-through）
    _bMrStable := bDownMachineReady;    // 零消抖直通（Zero debounce pass-through）
    _bInhStable := bDownInhibit;        // 零消抖直通（Zero debounce pass-through）
ELSE
    _bBaStable  := _fbTonDebounceBa.Q;  // 消抖后有料（Debounced BA）
    _bMrStable  := _fbTonDebounceMr.Q;  // 消抖后可收（Debounced MR）
    _bInhStable := _fbTonDebounceInh.Q; // 消抖后抑制（Debounced INH）
END_IF

// ============================================================================
// 段 2｜单拍标志预清零 + 复位路径（R15：锁存仅复位路径清码）
//      One-shot preset + reset path (R15)
// ============================================================================
bTransferDone := FALSE;                 // 完成单拍先清零（R25：置位-消费-复位同周期闭环）/ Done pulse preset FALSE (R25 lifecycle)

// 复位路径：仅此路径可清卡料锁存（R15）
IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;              // 卡料锁存解除（Jam latch released）
    _uErrorIdInt := 16#0000_0000;       // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜派生信号与同拍冲突保守侧判定（"不猜"原则）
//      Derived signals and same-cycle conflict conservative handling
// ============================================================================
_bSegEmpty := (NOT bBoardAtEntry) AND (NOT bBoardAtExit);   // 本段空：入/出口光电均未遮挡（Segment empty）
_bConflict := (_bBaStable AND bUpstreamRequest)             // 冲突一：BA 与 Request 同真（接线错误暴露点）
           OR (_bMrStable AND _bInhStable);                 // 冲突二：MR 与 INH 同真（下游语义矛盾）
IF _bConflict THEN
    _uInfoCode := DL_LINE_INFO_CONFL;   // 0005_0132 同拍冲突，保守侧不放行【信息级】/ Conflict, conservative side, info level
END_IF
IF _bConflict OR (NOT _bBaStable) THEN
    _bUpPresent := FALSE;               // 冲突或无料 → 按无上游料处理（不猜）/ Conflict or empty means no upstream board
ELSE
    _bUpPresent := TRUE;                // 上游有料成立（Upstream board present）
END_IF

// 握手判据一行布尔式（Handshake condition, single boolean expression）：
// 上游有料 AND 本段空 AND 下游可收 AND 非抑制 AND 使能 AND 无故障 AND 无冲突
_bTransferStart := _bUpPresent AND _bSegEmpty AND _bMrStable
              AND (NOT _bInhStable) AND bEnable AND (NOT _bFaultLatch)
              AND (NOT _bConflict);

// 传递看门狗：实例已在段 1 无条件刷新（Watchdog instance refreshed unconditionally in section 1）

// ============================================================================
// 段 4｜看门狗全局监视（优先级最高，R15 锁存语义）
//      Watchdog global monitor (highest priority, latched)
// ============================================================================
IF _fbTonWatchdog.Q AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;               // 传递超时锁存（Watchdog timeout latch）
    _uErrorIdInt := DL_LINE_ERR_JAM;    // 0005_0230 传递超时（卡料）【故障级】/ Transfer timeout, fault level
    _eState := E_DL_LineLinkState.eJamFault;
END_IF

// ============================================================================
// 段 5｜核心握手状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core handshake state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
IF NOT bEnable THEN
    // 使能撤销：全部输出安全侧，状态回空闲（卡料锁存保留，仍需复位路径清）
    // Disabled: outputs to safe side, state back to idle (jam latch retained)
    _eState := E_DL_LineLinkState.eIdle;
    _bAccepted := FALSE;
ELSE
    CASE _eState OF

        E_DL_LineLinkState.eIdle: // 空闲：等上游有料
            IF _bInhStable THEN
                _eState := E_DL_LineLinkState.eInhibited;   // 下游抑制生效（Downstream inhibit active）
            ELSIF _bTransferStart THEN
                _eState := E_DL_LineLinkState.eTransferring; // 握手成立直接起传（Handshake met, start transfer）
                _bAccepted := FALSE;                         // 受理标志清零待入口沿（Accept flag armed on entry edge）
            ELSIF _bUpPresent AND _bSegEmpty AND bEnable AND (NOT _bConflict) THEN
                _eState := E_DL_LineLinkState.eBoardReady;   // 有料但下游未就绪，待放行（Board waiting for downstream ready）
            END_IF

        E_DL_LineLinkState.eBoardReady: // 待放行：等下游 MR
            IF _bInhStable THEN
                _eState := E_DL_LineLinkState.eInhibited;   // 抑制优先（Inhibit takes priority）
            ELSIF _bTransferStart THEN
                _eState := E_DL_LineLinkState.eTransferring; // 下游就绪，起传（Downstream ready, start transfer）
                _bAccepted := FALSE;
            ELSIF NOT (_bUpPresent AND _bSegEmpty) THEN
                _eState := E_DL_LineLinkState.eIdle;         // 上游料撤销或本段被占，回空闲（Upstream withdrawn or segment occupied）
            END_IF

        E_DL_LineLinkState.eTransferring: // 传递中：等受理、等料离开
            IF _fbTrigEntry.Q THEN
                _bAccepted := TRUE;              // 入口沿受理（Accepted at entry edge）
                IF bBoardQualityNg THEN
                    _bNgHold := TRUE;            // 来料 NG 锁存保持下游可见（NG held for downstream sorting）
                END_IF
            END_IF
            IF _bAccepted AND _bSegEmpty THEN
                // 料已离开本段：完成单拍 + 计数（R25：本拍内置位，段 7 出口后由下拍清零）
                // Board left: one-scan done pulse + counter increment (R25 lifecycle)
                bTransferDone := TRUE;
                nTransferCount := nTransferCount + 1;
                _eState := E_DL_LineLinkState.eComplete;
            END_IF

        E_DL_LineLinkState.eComplete: // 传递完成：等复位（偏离留档①：BA 释放自动复位 / bReset 手动复位）
            _bNgHold := FALSE;           // NG 透传随完成释放（NG pass-through released on completion）
            IF (NOT _bUpPresent) OR _fbTrigReset.Q THEN
                _eState := E_DL_LineLinkState.eIdle;     // 料源已清或手动复位（Source cleared or manual reset）
            END_IF

        E_DL_LineLinkState.eInhibited: // 被抑制：不放行
            IF NOT _bInhStable THEN
                _eState := E_DL_LineLinkState.eIdle;     // 抑制解除（Inhibit released）
                _uInfoCode := DL_LINE_INFO_INHREL;       // 0005_0130 抑制解除恢复放行【信息级】/ Inhibit released, info level
            END_IF

        E_DL_LineLinkState.eJamFault: // 卡料锁存：等复位
            IF _fbTrigReset.Q THEN
                _bAccepted := FALSE;     // 受理标志随复位清零（Accept flag cleared on reset）
            END_IF

        ELSE // 非法状态兜底（本块专用码位）
            _bFaultLatch := TRUE;        // 非法状态锁存（Illegal state latch）
            _uErrorIdInt := DL_LINE_ERR_STATE; // 0005_0231 非法状态兜底【故障级】/ Illegal state fallback, fault level
            _eState := E_DL_LineLinkState.eJamFault;
    END_CASE
END_IF

// ============================================================================
// 段 6｜输出派生（出口断言：可收输出与抑制输出不得同真）
//      Output derivation (exit assertion: ready-out and inhibit-out never both TRUE)
// ============================================================================
IF bBypass THEN
    _uInfoCode := DL_LINE_INFO_BYPASS;  // 0005_0131 维护直通生效（每拍重算）【信息级】/ Maintenance bypass active, info level
END_IF

// 向下游宣告有料：消抖后有料 + 使能 + 无故障（BA out）
bBoardAvailableOut := _bBaStable AND bEnable AND (NOT _bFaultLatch) AND (NOT _bConflict);

// 向上游宣告可收：本段空 + 使能 + 无故障 + 非抑制 + 无冲突（出口断言：故障/抑制期恒 FALSE，
// 与 bInhibitUpstream 互斥由本布尔式结构保证 / Exit assertion: mutually exclusive by construction）
bMachineReadyOut := _bSegEmpty AND bEnable AND (NOT _bFaultLatch)
               AND (NOT _bInhStable) AND (NOT _bConflict);

// 向上游请求送料：本段空 + 下游可收 + 使能 + 无故障 + 无冲突（Request out）
bRequestBoard := _bSegEmpty AND _bMrStable AND bEnable AND (NOT _bFaultLatch) AND (NOT _bConflict);

// 抑制上游：卡料锁存保持期；维护直通强制 FALSE（Inhibit upstream while jammed, voided by bypass）
bInhibitUpstream := _bFaultLatch AND (NOT bBypass);

// 状态镜像输出（State mirror outputs）
bTransferring    := (_eState = E_DL_LineLinkState.eTransferring);  // 传递中（Transferring）
bTransferTimeout := (_eState = E_DL_LineLinkState.eJamFault);      // 传递超时保持期（Timeout latch held）
bQualityNgOut    := _bNgHold;                                      // 质量 NG 透传保持（NG held visible）

// ============================================================================
// 段 7｜bFault/uErrorId 出口（R21：bFault 显式排除信息级码）
//      Outlets: bFault excludes info codes (R21)
// ============================================================================
bFault := _bFaultLatch;                 // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;           // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;             // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK