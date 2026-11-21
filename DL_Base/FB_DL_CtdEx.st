(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CtdEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），计数本体为库内显式
 *                         判界加减法（重实现最小化：仅一圈判界 + 减 1）
 * 功能描述 (Function)   : 减计数器防御包装。内部以 R_TRIG 标准实例产计数脉冲，
 *                         计数本体采用显式判界减法实现 CV 下限饱和不回绕（达
 *                         DINT 下限锁定并置诊断码）；装载优先级 bLOAD > bCD，
 *                         LOAD 按 IEC 标准语义为电平装载（CV := PV）。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_0154（本件独占，仅此一码，
 *                         双事件共用一类码）
 *                         16#0001_0154 = nPV 为负值已钳 0 ／ CV 达 DINT 下限
 *                         饱和锁定（信息级，饱和是正常防御行为，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PV 钳位+DINT 下限判界防回绕
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ R_TRIG 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为「装载/计数」双态时序逻辑，
 *                         非顺序步进状态机，无 CASE 可写；两态互斥由优先级链
 *                         （装载 > 计数）显式保证，以本节说明替代 ELSE 兜底，
 *                         符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① nPV < 0 时钳位为 0 并置信息码 16#0001_0154
 *                           （装载后 CV=0，bQ 立即 TRUE，属组态错误提示）；
 *                         ② 下溢饱和不回绕：CV 达 DINT 下限 -2147483648 后停止
 *                           递减、保持不变并置信息码（与标准 CTD 的 DINT 回绕
 *                           行为差异点，饱和是正常防御行为）；
 *                         ③ LOAD 语义按 IEC 标准：bLOAD 为电平有效，有效期间
 *                           CV 每拍装载为钳位后 PV（非沿触发），优先级高于
 *                           bCD 计数脉冲；
 *                         ④ CV 允许为负数并继续递减至 DINT 下限（IEC CTD 标准
 *                           语义 Q = CV <= 0），下限饱和仅拦截 DINT 回绕；
 *                         ⑤ 内部状态量写入点排序审计（历史教训⑦）：PV 钳位段
 *                           与计数段对 uDiag 只写同一码值 16#0001_0154，不存在
 *                           复位类与置位类竞态，排序安全；
 *                         ⑥ DINT 下限提为只读常量 nDintMin，禁魔法数。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 2 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CtdEx
VAR_INPUT
    bCD   : BOOL;  // 减计数脉冲输入（内部 R_TRIG 取沿） / Count-down pulse input (edge taken by internal R_TRIG)
    bLOAD : BOOL;  // 装载输入（电平，优先级最高），CV := 钳位后 PV / Load input (level, highest priority), CV := clamped PV
    nPV   : INT;   // 预置装载值 [个]，负值将被钳位为 0 / Preset load value [count], negative values are clamped to 0
END_VAR
VAR_OUTPUT
    nCV   : DINT;   // 当前计数值 [个]，可为负，达下限饱和不回绕 / Current count [count], may go negative, saturates at lower limit without wrap
    bQ    : BOOL;   // 计数到零输出，nCV <= 0 时 TRUE / Zero-reached output, TRUE when nCV <= 0
    uDiag : UDINT;  // 诊断字，16#0001_0154=nPV 负钳 0 或 CV 下限饱和，0=无事件 / Diag word, 16#0001_0154=negative nPV clamped or CV lower saturation, 0=no event
END_VAR
VAR
    fbCdTrig  : R_TRIG;  // 内建上升沿实例，产计数脉冲 / Built-in R_TRIG instance, generates the count pulse
    nPVClamp  : DINT;    // 钳位后的预置装载值 [个]，用于装载与组态提示 / Clamped preset load value [count], used for loading and config hint
    nDintMin  : DINT := -2147483648;  // DINT 下限常量（只读语义，主体禁写）/ DINT lower-limit constant (read-only semantics, never written in body)
    xInit     : BOOL;    // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训④口径）：置于逻辑最前，首扫 CV=0、bQ=TRUE
 *      （IEC CTD 标准语义 CV<=0，首扫 0 值天然满足，非假触发）
 *      First-scan init (lesson 4): CV=0 and bQ=TRUE on first scan per IEC CTD
 *      semantics CV<=0, a natural zero value, not a false trigger
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit    := TRUE;    // 置初始化完成标志 / Mark init as done
    nCV      := 0;       // 首扫计数值清零 [个] / Zero count on first scan [count]
    nPVClamp := 0;       // 首扫钳位预置清零 [个] / Zero clamped preset on first scan [count]
    uDiag    := 16#0000_0000;  // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜PV 域校验与钳位（历史教训⑨）：nPV 负值钳 0 并置信息码
 *      PV domain check and clamp (lesson 9): negative nPV clamped to 0 with code
 *-----------------------------------------------------------------------------*)
IF nPV < 0 THEN
    nPVClamp := 0;            // 负预置钳位为 0 [个] / Clamp negative preset to 0 [count]
    uDiag    := 16#0001_0154;  // 信息码：nPV 负值已钳 0 / Informational: negative nPV clamped to 0
ELSE
    nPVClamp := nPV;          // 域内直通 [个] / In-domain pass-through [count]
    uDiag    := 16#0000_0000;  // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：R_TRIG 实例严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE
 *-----------------------------------------------------------------------------*)
fbCdTrig(CLK := bCD);  // 每扫描周期无条件取 bCD 上升沿 / Take bCD rising edge unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 4｜计数主体（优先级链 bLOAD > bCD）：装载电平优先，计数沿次之；
 *      LOAD 为 IEC 标准电平装载语义（CV := PV）；下溢判界先行——CV 达 DINT
 *      下限停止递减并置饱和码，绝不回绕
 *      Count body (priority chain bLOAD > bCD): load level first, count edge
 *      second; LOAD is the IEC level-load semantics (CV := PV); underflow
 *      boundary checked before decrement, no wrap ever
 *-----------------------------------------------------------------------------*)
IF bLOAD THEN
    nCV := nPVClamp;  // 电平装载：CV := 钳位后预置值 [个] / Level load: CV := clamped preset [count]
ELSIF fbCdTrig.Q THEN
    IF nCV > nDintMin THEN
        nCV := nCV - 1;           // 域内递减 1 [个] / In-domain decrement by 1 [count]
    ELSE
        uDiag := 16#0001_0154;    // 信息码：CV 下限饱和锁定，不回绕 / Informational: CV lower-limit saturation, no wrap
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜比较输出：按 IEC CTD 标准语义 Q = CV <= 0
 *      Compare output: per IEC CTD standard semantics Q = CV <= 0
 *-----------------------------------------------------------------------------*)
bQ := (nCV <= 0);  // 计数到零比较 [个] / Zero-reached comparison [count]
END_FUNCTION_BLOCK
