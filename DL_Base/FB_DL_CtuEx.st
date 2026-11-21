(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CtuEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），计数本体为库内显式
 *                         判界加减法（重实现最小化：仅一圈判界 + 加 1）
 * 功能描述 (Function)   : 加计数器防御包装。内部以 R_TRIG 标准实例产计数脉冲，
 *                         计数本体采用显式判界加法实现 CV 饱和不回绕（达 DINT
 *                         上限锁定并置诊断码）；复位优先级 bRESET > bCU。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_0153（本件独占，仅此一码，
 *                         双事件共用一类码）
 *                         16#0001_0153 = nPV 为负值已钳 0 ／ CV 达 DINT 上限
 *                         饱和锁定（信息级，饱和是正常防御行为，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PV 钳位+DINT 上限判界防回绕
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ R_TRIG 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为「复位/计数」双态时序逻辑，
 *                         非顺序步进状态机，无 CASE 可写；两态互斥由优先级链
 *                         （复位 > 计数）显式保证，以本节说明替代 ELSE 兜底，
 *                         符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① nPV < 0 时钳位为 0 并置信息码 16#0001_0153
 *                           （负预置在本包装下使 bQ 恒 TRUE，属组态错误提示）；
 *                         ② 上溢饱和不回绕：CV 达 DINT 上限 2147483647 后停止
 *                           递增、保持不变并置信息码（与标准 CTU 的 DINT 回绕
 *                           行为差异点，饱和是正常防御行为）；
 *                         ③ 优先级链写死：bRESET（电平）> bCU 计数脉冲；
 *                         ④ 内部状态量写入点排序审计（历史教训⑦）：PV 钳位段
 *                           与计数段对 uDiag 只写同一码值 16#0001_0153，不存在
 *                           复位类与置位类竞态，排序安全；
 *                         ⑤ DINT 上限提为只读常量 nDintMax，禁魔法数。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 2 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CtuEx
VAR_INPUT
    bCU    : BOOL;  // 加计数脉冲输入（内部 R_TRIG 取沿） / Count-up pulse input (edge taken by internal R_TRIG)
    bRESET : BOOL;  // 复位输入（电平，优先级最高），CV 清零 / Reset input (level, highest priority), clears CV
    nPV    : INT;   // 预置值 [个]，负值将被钳位为 0 / Preset value [count], negative values are clamped to 0
END_VAR
VAR_OUTPUT
    nCV   : DINT;   // 当前计数值 [个]，达上限饱和不回绕 / Current count [count], saturates at upper limit without wrap
    bQ    : BOOL;   // 计数到达输出，nCV >= 钳位后 nPV 时 TRUE / Done output, TRUE when nCV >= clamped nPV
    uDiag : UDINT;  // 诊断字，16#0001_0153=nPV 负钳 0 或 CV 上限饱和，0=无事件 / Diag word, 16#0001_0153=negative nPV clamped or CV upper saturation, 0=no event
END_VAR
VAR
    fbCuTrig  : R_TRIG;  // 内建上升沿实例，产计数脉冲 / Built-in R_TRIG instance, generates the count pulse
    nPVClamp  : DINT;    // 钳位后的预置值 [个]，用于比较输出 / Clamped preset [count], used for the compare output
    nDintMax  : DINT := 2147483647;  // DINT 上限常量（只读语义，主体禁写）/ DINT upper-limit constant (read-only semantics, never written in body)
    xInit     : BOOL;    // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训④口径）：置于逻辑最前，首扫 CV=0、bQ=FALSE
 *      First-scan init (lesson 4): placed at the very front, CV=0 and bQ=FALSE on first scan
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
    uDiag    := 16#0001_0153;  // 信息码：nPV 负值已钳 0 / Informational: negative nPV clamped to 0
ELSE
    nPVClamp := nPV;          // 域内直通 [个] / In-domain pass-through [count]
    uDiag    := 16#0000_0000;  // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：R_TRIG 实例严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE
 *-----------------------------------------------------------------------------*)
fbCuTrig(CLK := bCU);  // 每扫描周期无条件取 bCU 上升沿 / Take bCU rising edge unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 4｜计数主体（优先级链 bRESET > bCU）：复位电平优先，计数沿次之；
 *      上溢判界先行——CV 达 DINT 上限停止递增并置饱和码，绝不回绕
 *      Count body (priority chain bRESET > bCU): reset level first, count edge
 *      second; overflow boundary checked before increment, no wrap ever
 *-----------------------------------------------------------------------------*)
IF bRESET THEN
    nCV := 0;   // 复位清零计数值 [个] / Reset clears count [count]
ELSIF fbCuTrig.Q THEN
    IF nCV < nDintMax THEN
        nCV := nCV + 1;           // 域内递增 1 [个] / In-domain increment by 1 [count]
    ELSE
        uDiag := 16#0001_0153;    // 信息码：CV 上限饱和锁定，不回绕 / Informational: CV upper-limit saturation, no wrap
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜比较输出：按 IEC CTU 语义 Q = CV >= PV（PV 钳 0 时恒 TRUE，属组态
 *      提示范畴，见头注释防御声明①）
 *      Compare output: per IEC CTU semantics Q = CV >= PV (always TRUE when
 *      PV clamped to 0, a configuration hint, see defense note 1)
 *-----------------------------------------------------------------------------*)
bQ := (nCV >= nPVClamp);  // 计数到达比较 [个] / Done comparison [count]
END_FUNCTION_BLOCK
