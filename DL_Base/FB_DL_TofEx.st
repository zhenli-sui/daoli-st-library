(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TofEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TOF），零厂商方言
 * 功能描述 (Function)   : 断开延时定时器防御包装。内部委托 IEC 61131-3 标准 TOF
 *                         实例完成计时内核，外围提供 PT 负值钳位、首扫语义统一
 *                         （首扫 bIN=FALSE 时 bQ 必为 FALSE）与跨段语义直通。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_0150（本件独占，仅此一码）
 *                         16#0001_0150 = tPT 为负值，已钳位为 T#0s（信息级，
 *                         钳位属正常防御行为，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TOF
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PT 钳位+除零/越界无涉
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ TOF 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为单步延时逻辑，不存在顺序状态机，
 *                         无 CASE 可写；唯一状态即"延时中/直通"，以本节说明
 *                         替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① tPT < T#0s 时钳位为 T#0s 并置信息码 16#0001_0150
 *                           （部分平台负 TIME 行为未定义，本库统一钳 0）；
 *                         ② 首扫语义统一：首扫 bIN=FALSE 时 bQ 必为 FALSE、tET=T#0s
 *                           ——由内建 TOF 标准行为（Q 随 IN 直通 + 断开延时）保证，
 *                           部分平台首扫假触发差异在包装层被标准实例天然屏蔽；
 *                         ③ bIN 接通当拍 tET 归零、bQ 立即 TRUE（IEC TOF 标准语义，
 *                           包装层不重实现）。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 2 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TofEx
VAR_INPUT
    bIN : BOOL;   // 定时输入，TRUE 直通输出，FALSE 起断开延时 / Timing input, TRUE passes through, FALSE starts the off-delay
    tPT : TIME;   // 预置延时 [ms]，负值将被钳位为 T#0s / Preset delay [ms], negative values are clamped to T#0s
END_VAR
VAR_OUTPUT
    bQ    : BOOL;   // 输出，bIN 断开并持续 tPT 后变 FALSE / Output, goes FALSE after bIN held FALSE for tPT
    tET   : TIME;   // 已计时 [ms]，bIN 接通当拍归零 / Elapsed time [ms], zeroed on the scan bIN rises
    uDiag : UDINT;  // 诊断字，16#0001_0150=tPT 负值已钳 0，0=无诊断事件 / Diag word, 16#0001_0150=negative tPT clamped to 0, 0=no diag event
END_VAR
VAR
    fbTof    : TOF;   // 内建断开延时实例，承担计时内核 / Built-in TOF instance, owns the timing kernel
    tPTClamp : TIME;  // 钳位后的预置延时 [ms]，喂给内建实例 / Clamped preset delay [ms], fed to the built-in instance
    xInit    : BOOL;  // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训④口径）：置于逻辑最前，首扫不产假 bQ
 *      First-scan init (lesson 4): placed at the very front, no false bQ on first scan
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit    := TRUE;    // 置初始化完成标志 / Mark init as done
    tPTClamp := T#0s;    // 首扫钳位值归零，避免未初始化喂入 / Zero the clamp value on first scan, no uninitialized feed
    uDiag    := 16#0000_0000;  // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜PT 域校验与钳位：负 TIME 在部分平台行为未定义，统一钳 0 并置信息码；
 *      写入点排序审计（历史教训⑦）：本件诊断字仅有"置码/清码"单一分支对，
 *      无复位类与置位类竞态，排序安全
 *      PT domain check and clamp: negative TIME is undefined on some platforms,
 *      unified clamp to 0 with an informational code
 *-----------------------------------------------------------------------------*)
IF tPT < T#0s THEN
    tPTClamp := T#0s;        // 负值钳位为 0 [ms] / Clamp negative to 0 [ms]
    uDiag    := 16#0001_0150;  // 信息码：PT 负值已钳 0 / Informational: negative PT clamped to 0
ELSE
    tPTClamp := tPT;         // 域内直通 / In-domain pass-through
    uDiag    := 16#0000_0000;  // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：TOF 实例严禁进入任何 IF / CASE 分支；
 *      首扫 bIN=FALSE → bQ=FALSE 与"接通当拍 ET 归零"均由内建标准语义保证
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE;
 *      first-scan bQ=FALSE with bIN=FALSE and ET zeroing on bIN rise are both
 *      guaranteed by the built-in TOF standard behavior
 *-----------------------------------------------------------------------------*)
fbTof(IN := bIN, PT := tPTClamp);  // 每扫描周期无条件喂入输入与钳位后 PT / Feed input and clamped PT unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 4｜输出直通：bQ/tET 逐拍镜像内建实例输出，包装层不重实现计时内核
 *      Output pass-through: bQ/tET mirror the built-in outputs scan by scan;
 *      the wrapper never re-implements the timing kernel
 *-----------------------------------------------------------------------------*)
bQ  := fbTof.Q;   // 输出直通 / Output pass-through
tET := fbTof.ET;  // 已计时 [ms] 直通 / Elapsed time [ms] pass-through
END_FUNCTION_BLOCK
