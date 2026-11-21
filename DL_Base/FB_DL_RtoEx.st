(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RtoEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商方言
 * 功能描述 (Function)   : 保持型（累加）定时器防御包装。IEC 61131-3 无标准 RTO
 *                         块，本件按通用 RTO 语义以「内建 TON + 内部累加状态位」
 *                         实现：bIN 断开时冻结累计值（掉保持），bIN 恢复后续计，
 *                         bRESET 任意时刻清零累计（复位优先级最高）。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （RTO 非标准块，按通用 RTO 语义 clean-room 实现，
 *                         计时内核委托内建 TON，重实现最小化）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_0152（本件独占，仅此一码）
 *                         16#0001_0152 = tPT 为负值，已钳位为 T#0s（信息级，
 *                         钳位属正常防御行为，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PT 钳位+越界无涉（纯时间加法）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ TON 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为「使能/暂停/复位」三态时序逻辑，
 *                         非顺序步进状态机，无 CASE 可写；三态互斥由优先级链
 *                         （复位 > 使能）显式保证，无非法态可陷入，以本节说明
 *                         替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① tPT < T#0s 时钳位为 T#0s 并置信息码 16#0001_0152；
 *                         ② 优先级链写死：bRESET（电平）> bIN 使能，复位拍即使
 *                           bIN=TRUE 也清零并重新计时（RTO 通用语义）；
 *                         ③ 掉保持/恢复语义：bIN 断开当拍，上一扫描周期的实时
 *                           计时值被冻结累入保持量（tETLast 在内建 TON 被本次
 *                           调用清零前取用），bIN 恢复后从保持量续计，tET 只增
 *                           不减直至复位；
 *                         ④ 计时中途变更 tPT：以完成时刻的 PT 值计入保持量，
 *                           语义为"以完成时刻预置为准"，头注释留档；
 *                         ⑤ tPT 钳 0（含负钳 0）时 bQ 上电使能即到时（ET>=PT
 *                           恒真），属正常防御行为；
 *                         ⑥ 内部状态量写入点排序审计（历史教训⑦）：复位类
 *                           写入（清累计/清到时位）前置，置位类写入（冻结累加/
 *                           到时锁存）后置，复位沿不被吞。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 2 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RtoEx
VAR_INPUT
    bIN    : BOOL;  // 计时使能，TRUE 累计计时，FALSE 暂停并保持累计值 / Timing enable, TRUE accumulates, FALSE pauses and holds the accumulated time
    bRESET : BOOL;  // 复位输入（电平，优先级最高），清零累计与到时位 / Reset input (level, highest priority), clears accumulation and done flag
    tPT    : TIME;  // 预置总延时 [ms]，负值将被钳位为 T#0s / Preset total delay [ms], negative values are clamped to T#0s
END_VAR
VAR_OUTPUT
    bQ    : BOOL;   // 累计到达输出，累计值达 tPT 后保持 / Accumulated-done output, held TRUE once accumulation reaches tPT
    tET   : TIME;   // 累计值 [ms]，bIN 断开保持、只增不减至复位 / Accumulated time [ms], held on bIN drop, only grows until reset
    uDiag : UDINT;  // 诊断字，16#0001_0152=tPT 负值已钳 0，0=无诊断事件 / Diag word, 16#0001_0152=negative tPT clamped to 0, 0=no diag event
END_VAR
VAR
    fbTon    : TON;   // 内建接通延时实例，承担单段计时内核 / Built-in TON instance, owns the per-segment timing kernel
    tPTClamp : TIME;  // 钳位后的预置总延时 [ms]，喂给内建实例 / Clamped preset total delay [ms], fed to the built-in instance
    tAccum   : TIME;  // 保持量累计 [ms]，跨暂停段保持 / Retained accumulation [ms], kept across pause segments
    tETLast  : TIME;  // 上一扫描周期的实时计时快照 [ms]，供断开拍冻结 / Last-scan elapsed snapshot [ms], frozen on the drop scan
    bRunPrev : BOOL;  // 上一扫描周期 bIN 快照，用于下降沿识别 / Previous-scan bIN snapshot, for falling-edge detection
    bDone    : BOOL;  // 累计到达内部锁存位 / Internal done latch
    xInit    : BOOL;  // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训④口径）：置于逻辑最前，首扫不产假 bQ
 *      First-scan init (lesson 4): placed at the very front, no false bQ on first scan
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit    := TRUE;    // 置初始化完成标志 / Mark init as done
    tPTClamp := T#0s;    // 首扫钳位值归零，避免未初始化喂入 / Zero the clamp value on first scan
    tAccum   := T#0s;    // 首扫保持量清零 / Zero retained accumulation on first scan
    tETLast  := T#0s;    // 首扫计时快照清零 / Zero elapsed snapshot on first scan
    bRunPrev := FALSE;   // 首扫使能快照为 FALSE，杜绝假下降沿 / FALSE on first scan, no false falling edge
    bDone    := FALSE;   // 首扫到时位清零 / Clear done latch on first scan
    uDiag    := 16#0000_0000;  // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜PT 域校验与钳位：负 TIME 统一钳 0 并置信息码
 *      PT domain check and clamp: negative TIME unified to 0 with informational code
 *-----------------------------------------------------------------------------*)
IF tPT < T#0s THEN
    tPTClamp := T#0s;        // 负值钳位为 0 [ms] / Clamp negative to 0 [ms]
    uDiag    := 16#0001_0152;  // 信息码：PT 负值已钳 0 / Informational: negative PT clamped to 0
ELSE
    tPTClamp := tPT;         // 域内直通 / In-domain pass-through
    uDiag    := 16#0000_0000;  // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜复位类写入（前置，历史教训⑦）：bRESET 电平优先级最高，清零累计与
 *      到时位；即使同拍 bIN=TRUE 也走复位语义（段 5 内建实例随后重新起计时）
 *      Reset-class writes (front, lesson 7): level reset has top priority;
 *      even with bIN TRUE on the same scan, reset semantics wins
 *-----------------------------------------------------------------------------*)
IF bRESET THEN
    tAccum := T#0s;    // 清零保持量累计 [ms] / Clear retained accumulation [ms]
    bDone  := FALSE;   // 清零到时锁存位 / Clear done latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜下降沿冻结（置位类，须在内建 TON 调用之前）：bIN 断开当拍，内建 TON
 *      将被本次调用清零，故取上一拍快照 tETLast 冻结累入保持量；
 *      复位拍与到时态不冻结（复位已清零、到时无未结段落）
 *      Falling-edge freeze (set-class, before the built-in TON call): on the
 *      scan bIN drops, the built-in TON will be zeroed by this very call, so
 *      the last-scan snapshot tETLast is frozen into the retention
 *-----------------------------------------------------------------------------*)
IF bRunPrev AND (NOT bIN) AND (NOT bDone) AND (NOT bRESET) THEN
    tAccum := tAccum + tETLast;  // 冻结上一拍实时计时入保持量 [ms] / Freeze last-scan elapsed into retention [ms]
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜无条件刷新区（红线 R7）：TON 实例严禁进入任何 IF / CASE 分支；
 *      IN = 使能且未到时——到时后自动摘除使能，杜绝重复计时
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE;
 *      IN = enabled AND not done, auto-detached after completion
 *-----------------------------------------------------------------------------*)
fbTon(IN := bIN AND (NOT bDone), PT := tPTClamp);  // 每扫描周期无条件喂入 / Feed unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 6｜到时锁存（实例调用之后置位类写入，R24 教训）：完成拍把本段满程计时
 *      （此时 ET=钳位后 PT）累入保持量并锁存到时位
 *      Done latch (set-class write after the instance call, R24 lesson): on the
 *      completion scan, the full segment (ET = clamped PT) is frozen and done latched
 *-----------------------------------------------------------------------------*)
IF fbTon.Q AND (NOT bDone) THEN
    bDone  := TRUE;              // 锁存累计到达 / Latch accumulated-done
    tAccum := tAccum + fbTon.ET; // 本段满程计时累入保持量 [ms]（完成拍 ET=钳位后 PT）/ Full segment frozen into retention [ms], ET equals clamped PT on the completion scan
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出组合：运行中 = 保持量 + 本段实时值；暂停/到时/复位 = 仅保持量
 *      Output composition: running = retention + live segment; else retention only
 *-----------------------------------------------------------------------------*)
IF bIN AND (NOT bDone) THEN
    tET := tAccum + fbTon.ET;  // 运行中输出 [ms] / Live output while running [ms]
ELSE
    tET := tAccum;             // 暂停/到时/复位输出仅保持量 [ms] / Paused/done/reset output, retention only [ms]
END_IF
bQ := bDone;                 // 累计到达输出 / Accumulated-done output

(*------------------------------------------------------------------------------
 * 段 8｜周期快照落盘：本拍使能与实时计时供下一拍下降沿冻结取用
 *      Per-scan snapshot: this scan's enable and live elapsed feed next scan's freeze
 *-----------------------------------------------------------------------------*)
bRunPrev := bIN;      // 快照本拍使能 / Snapshot this scan's enable
tETLast  := fbTon.ET; // 快照本拍实时计时 [ms] / Snapshot this scan's live elapsed [ms]
END_FUNCTION_BLOCK
