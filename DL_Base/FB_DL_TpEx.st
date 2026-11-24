(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TpEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TP），零厂商方言
 * 功能描述 (Function)   : 脉冲定时器防御包装。内部委托 IEC 61131-3 标准 TP 实例
 *                         完成计时内核，外围提供 PT 负值钳位，并把"不可重触发"
 *                         语义在头注释显式写死。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_0151（本件独占，仅此一码）
 *                         16#0001_0151 = tPT 为负值，已钳位为 T#0s（信息级，
 *                         钳位属正常防御行为，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TP
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PT 钳位+除零/越界无涉
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ TP 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为单步脉冲逻辑，不存在顺序状态机，
 *                         无 CASE 可写；唯一状态即"脉冲中/待触发"，以本节说明
 *                         替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① tPT < T#0s 时钳位为 T#0s 并置信息码 16#0001_0151
 *                           （部分平台负 TIME 行为未定义，本库统一钳 0，
 *                           PT=0 时脉冲退化为单扫描周期宽度）；
 *                         ② 不可重触发语义显式化（IEC TP 标准语义，多平台实现
 *                           有偏差，此处以标准实例写死）：计时进行中 bIN 再次
 *                           触发不延长、不重启当前脉冲，必须等当前脉冲结束；
 *                         ③ R24 教训落实：本件不存在任何"实例调用前的自清/
 *                           复位写入"——段 2 钳位仅写钳位值与诊断字（纯输入域
 *                           逻辑，不触内建实例状态），实例调用后到输出镜像之间
 *                           零状态写入，bQ 不可能被前置自清压成恒 FALSE。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 2 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TpEx
VAR_INPUT
    bIN : BOOL;   // 触发输入，上升沿启动脉冲，计时中再触发不重启 / Trigger input, rising edge starts the pulse, retrigger during timing is ignored
    tPT : TIME;   // 脉冲宽度 [ms]，负值将被钳位为 T#0s / Pulse width [ms], negative values are clamped to T#0s
END_VAR
VAR_OUTPUT
    bQ    : BOOL;   // 脉冲输出，触发后保持 tPT 宽度 / Pulse output, held TRUE for tPT after trigger
    tET   : TIME;   // 已计时 [ms]，脉冲结束后归零 / Elapsed time [ms], zeroed after the pulse finishes
    uDiag : UDINT;  // 诊断字，16#0001_0151=tPT 负值已钳 0，0=无诊断事件 / Diag word, 16#0001_0151=negative tPT clamped to 0, 0=no diag event
END_VAR
VAR
    fbTp     : TP;    // 内建脉冲定时器实例，承担计时内核 / Built-in TP instance, owns the timing kernel
    tPTClamp : TIME;  // 钳位后的脉冲宽度 [ms]，喂给内建实例 / Clamped pulse width [ms], fed to the built-in instance
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
 * 段 2｜PT 域校验与钳位（纯输入域逻辑，不触内建实例状态——R24 教训）；
 *      写入点排序审计（历史教训⑦）：本件诊断字仅有"置码/清码"单一分支对，
 *      无复位类与置位类竞态，排序安全
 *      PT domain check and clamp (input-domain only, never touches instance
 *      state - R24 lesson); single set/clear branch pair, ordering safe
 *-----------------------------------------------------------------------------*)
IF tPT < T#0s THEN
    tPTClamp := T#0s;        // 负值钳位为 0 [ms]，PT=0 脉冲退化为单拍宽度 / Clamp negative to 0 [ms], PT=0 degenerates to one-scan pulse
    uDiag    := 16#0001_0151;  // 信息码：PT 负值已钳 0 / Informational: negative PT clamped to 0
ELSE
    tPTClamp := tPT;         // 域内直通 / In-domain pass-through
    uDiag    := 16#0000_0000;  // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：TP 实例严禁进入任何 IF / CASE 分支；
 *      不可重触发语义由内建标准实例行为保证，包装层零自清/复位写入，
 *      实例调用之后无任何状态写点，bQ 恒可正常动作（R24 教训）
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE;
 *      non-retriggerable semantics is guaranteed by the built-in standard
 *      instance; zero self-clear/reset writes after the instance call
 *-----------------------------------------------------------------------------*)
fbTp(IN := bIN, PT := tPTClamp);  // 每扫描周期无条件喂入输入与钳位后 PT / Feed input and clamped PT unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 4｜输出直通：bQ/tET 逐拍镜像内建实例输出，包装层不重实现计时内核
 *      Output pass-through: bQ/tET mirror the built-in outputs scan by scan;
 *      the wrapper never re-implements the timing kernel
 *-----------------------------------------------------------------------------*)
bQ  := fbTp.Q;    // 脉冲输出直通 / Pulse output pass-through
tET := fbTp.ET;   // 已计时 [ms] 直通 / Elapsed time [ms] pass-through
END_FUNCTION_BLOCK
