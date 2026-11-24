(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TonEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商方言
 * 功能描述 (Function)   : 接通延时定时器防御包装。内部委托 IEC 61131-3 标准 TON
 *                         实例完成计时内核，外围提供 PT 负值钳位与跨段输入断开
 *                         语义统一（bIN 断开当拍 ET 归零、bQ 立即 FALSE）。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_014F（本件独占，仅此一码）
 *                         16#0001_014F = tPT 为负值，已钳位为 T#0s（信息级，
 *                         钳位属正常防御行为，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PT 钳位+除零/越界无涉
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ TON 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为单步延时逻辑，不存在顺序状态机，
 *                         无 CASE 可写；非法状态不可能出现（唯一状态即"计时/直通"），
 *                         故以本节说明替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① tPT < T#0s 时钳位为 T#0s 并置信息码 16#0001_014F
 *                           （部分平台负 TIME 行为未定义，本库统一钳 0）；
 *                         ② 跨段输入断开语义统一：bIN 断开当拍 tET 归零、bQ 立即
 *                           FALSE（由内建 TON 标准语义保证，包装层不重实现）；
 *                         ③ 首扫 bIN=TRUE 允许正常计时（TON 标准语义）但不产假 bQ
 *                           （首拍 ET 从 0 起步，bQ 天然 FALSE，无需额外抑制）。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 1 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TonEx
VAR_INPUT
    bIN : BOOL;   // 定时输入，TRUE 起计时，FALSE 立即复位计时 / Timing input, TRUE starts timing, FALSE resets immediately
    tPT : TIME;   // 预置延时 [ms]，负值将被钳位为 T#0s / Preset delay [ms], negative values are clamped to T#0s
END_VAR
VAR_OUTPUT
    bQ    : BOOL;   // 延时到输出，bIN 保持 TRUE 达 tPT 后置位 / Delay-elapsed output, set after bIN held TRUE for tPT
    tET   : TIME;   // 已计时 [ms]，bIN 断开当拍归零 / Elapsed time [ms], zeroed on the scan bIN drops
    uDiag : UDINT;  // 诊断字，16#0001_014F=tPT 负值已钳 0，0=无诊断事件 / Diag word, 16#0001_014F=negative tPT clamped to 0, 0=no diag event
END_VAR
VAR
    fbTon    : TON;   // 内建接通延时实例，承担计时内核 / Built-in TON instance, owns the timing kernel
    tPTClamp : TIME;  // 钳位后的预置延时 [ms]，喂给内建实例 / Clamped preset delay [ms], fed to the built-in instance
    xInit    : BOOL;  // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训⑤口径）：置于逻辑最前，禁止"初值置位后同步清零"反模式
 *      First-scan init (lesson 5): placed at the very front of the logic body
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit    := TRUE;    // 置初始化完成标志 / Mark init as done
    tPTClamp := T#0s;    // 首扫钳位值归零，避免未初始化喂入 / Zero the clamp value on first scan, no uninitialized feed
    uDiag    := 16#0000_0000;  // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜PT 域校验与钳位：负 TIME 在部分平台行为未定义，统一钳 0 并置信息码；
 *      写入点排序（历史教训⑩）：本件诊断字仅有"置码 / 清码"单一分支对，无
 *      复位类与置位类竞态，排序安全
 *      PT domain check and clamp: negative TIME is undefined on some platforms,
 *      unified clamp to 0 with an informational code
 *-----------------------------------------------------------------------------*)
IF tPT < T#0s THEN
    tPTClamp := T#0s;        // 负值钳位为 0 [ms] / Clamp negative to 0 [ms]
    uDiag    := 16#0001_014F;  // 信息码：PT 负值已钳 0 / Informational: negative PT clamped to 0
ELSE
    tPTClamp := tPT;         // 域内直通 / In-domain pass-through
    uDiag    := 16#0000_0000;  // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：TON 实例严禁进入任何 IF / CASE 分支；
 *      bIN 断开当拍 ET 归零、bQ 立即 FALSE 的跨段统一语义由内建 TON 标准行为保证
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE;
 *      the unified drop-out semantics (ET zeroed and bQ FALSE on the scan bIN
 *      drops) is guaranteed by the built-in TON standard behavior
 *-----------------------------------------------------------------------------*)
fbTon(IN := bIN, PT := tPTClamp);  // 每扫描周期无条件喂入输入与钳位后 PT / Feed input and clamped PT unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 4｜输出直通：bQ/tET 逐拍镜像内建实例输出，包装层不重实现计时内核
 *      Output pass-through: bQ/tET mirror the built-in outputs scan by scan;
 *      the wrapper never re-implements the timing kernel
 *-----------------------------------------------------------------------------*)
bQ  := fbTon.Q;   // 延时到输出直通 / Delay-elapsed output pass-through
tET := fbTon.ET;  // 已计时 [ms] 直通 / Elapsed time [ms] pass-through
END_FUNCTION_BLOCK
