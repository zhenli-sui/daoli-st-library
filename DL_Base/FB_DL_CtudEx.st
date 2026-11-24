(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CtudEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），计数本体为库内显式
 *                         判界加减法（重实现最小化：一圈判界 + 加减 1）
 * 功能描述 (Function)   : 双向计数器（CTUD）防御包装。内部以两个 R_TRIG 标准实例
 *                         分别取 bCU / bCD 上升沿，CU/CD 同拍出现时按「净额抵消法」
 *                         取净值一次性施加（net = CU沿 − CD沿，同拍加减相消不误
 *                         动作）；优先级链 bRESET > bLOAD > 计数；PV 负值钳 0；
 *                         双向饱和不回绕（达 DINT 上/下限锁定并置故障码）。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级 16#0001_0155（本件独占）：
 *                         nPV 为负值已钳 0 ／ CU/CD 同拍抵消（净变化 0）
 *                         故障级 16#0001_0226（本件独占）：
 *                         CV 达 DINT 上/下限饱和锁定（异常记录，绝不回绕）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 边界声明 (Boundary)   : 本件是对标准 CTUD 的逐引脚等义防御包装（无双预设、无倒置
 *                         冻结扩展）；CTUD 全语义超集见 FB_DL_BidirectionalCounter，
 *                         两者在 MANUAL 中互引声明边界，不互相替代。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ PV 钳位+DINT 双向判界防回绕
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ R_TRIG 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为「复位/装载/计数」优先级时序
 *                         逻辑，非顺序步进状态机，无 CASE 可写；三态互斥由优先级
 *                         链（复位 > 装载 > 计数）显式保证，以本节说明替代
 *                         ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① CU/CD 同拍出现按「净额抵消法」处理：两沿同拍时
 *                           net = +1 − 1 = 0，本拍不动作并置信息码 16#0001_0155
 *                           （先加后减的顺序歧义被一次性净值施加天然规避）；
 *                         ② 优先级链写死：bRESET（电平）> bLOAD（电平）> 计数净值；
 *                           装载拍跳过计数（装载覆盖计数，与库内计数族口径一致）；
 *                         ③ nPV < 0 时钳位为 0 并置信息码 16#0001_0155
 *                           （负预置使 bQU 恒 TRUE，属组态错误提示）；
 *                         ④ 双向饱和不回绕：CV 达 DINT 上限 2147483647 停止递增、
 *                           达下限 −2147483648 停止递减，保持不变并置故障码
 *                           16#0001_0226（与标准 CTUD 的回绕行为差异点）；
 *                         ⑤ DINT 上/下限提为只读常量，禁魔法数。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 3 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CtudEx
VAR_INPUT
    bCU    : BOOL;  // 加计数脉冲输入（内部 R_TRIG 取沿） / Count-up pulse input (edge taken by internal R_TRIG)
    bCD    : BOOL;  // 减计数脉冲输入（内部 R_TRIG 取沿） / Count-down pulse input (edge taken by internal R_TRIG)
    bRESET : BOOL;  // 复位输入（电平，优先级最高），CV 清零 / Reset input (level, highest priority), clears CV
    bLOAD  : BOOL;  // 装载输入（电平，次高优先级），CV 装入钳位后 PV / Load input (level, second priority), loads clamped PV into CV
    nPV    : INT;   // 预置值 [个]，负值将被钳位为 0 / Preset value [count], negative values are clamped to 0
END_VAR
VAR_OUTPUT
    nCV   : DINT;   // 当前计数值 [个]，双向饱和不回绕 / Current count [count], saturates both ways without wrap
    bQU   : BOOL;   // 上计数到达输出，nCV >= 钳位后 nPV 时 TRUE / Upper done output, TRUE when nCV >= clamped nPV
    bQD   : BOOL;   // 下计数到达输出，nCV <= 0 时 TRUE / Lower done output, TRUE when nCV <= 0
    uDiag : UDINT;  // 诊断字，16#0001_0155=PV负钳0或同拍抵消，16#0001_0226=CV饱和，0=无事件 / Diag word, 16#0001_0155=PV clamped or same-scan cancel, 16#0001_0226=CV saturated, 0=no event
END_VAR
VAR
    fbCuTrig  : R_TRIG;  // 内建上升沿实例，取 bCU 计数脉冲 / Built-in R_TRIG instance for the count-up pulse
    fbCdTrig  : R_TRIG;  // 内建上升沿实例，取 bCD 计数脉冲 / Built-in R_TRIG instance for the count-down pulse
    nPVClamp  : DINT;    // 钳位后的预置值 [个]，用于装载与比较输出 / Clamped preset [count], used for load and compare outputs
    nNet      : INT;     // 本拍净计数额 [个]，加 1 / 减 1 / 0 抵消 / Net count delta this scan [count], plus one, minus one or zero
    xInit     : BOOL;    // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
    nDintMax  : DINT := 2147483647;   // DINT 上限常量（只读语义，主体禁写）/ DINT upper-limit constant (read-only semantics, never written in body)
    nDintMin  : DINT := -2147483648;  // DINT 下限常量（只读语义，主体禁写）/ DINT lower-limit constant (read-only semantics, never written in body)
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训④口径）：置于逻辑最前，首扫 CV=0、比较输出 FALSE
 *      First-scan init (lesson 4): placed at the very front, CV=0 and compare outputs FALSE on first scan
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit    := TRUE;             // 置初始化完成标志 / Mark init as done
    nCV      := 0;                // 首扫计数值清零 [个] / Zero count on first scan [count]
    nPVClamp := 0;                // 首扫钳位预置清零 [个] / Zero clamped preset on first scan [count]
    nNet     := 0;                // 首扫净额清零 [个] / Zero net delta on first scan [count]
    uDiag    := 16#0000_0000;     // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜PV 域校验与钳位：nPV 负值钳 0 并置信息码 16#0001_0155
 *      PV domain check and clamp: negative nPV clamped to 0 with code 16#0001_0155
 *-----------------------------------------------------------------------------*)
IF nPV < 0 THEN
    nPVClamp := 0;                // 负预置钳位为 0 [个] / Clamp negative preset to 0 [count]
    uDiag    := 16#0001_0155;     // 信息码：nPV 负值已钳 0 / Informational: negative nPV clamped to 0
ELSE
    nPVClamp := nPV;              // 域内直通 [个] / In-domain pass-through [count]
    uDiag    := 16#0000_0000;     // 无诊断事件，清码 / No diag event, clear code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：两个 R_TRIG 实例严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE
 *-----------------------------------------------------------------------------*)
fbCuTrig(CLK := bCU);  // 每扫描周期无条件取 bCU 上升沿 / Take bCU rising edge unconditionally every scan
fbCdTrig(CLK := bCD);  // 每扫描周期无条件取 bCD 上升沿 / Take bCD rising edge unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 4｜净额抵消仲裁（防御声明①）：CU/CD 同拍时 net = 0，同拍加减相消不误动作；
 *      净额一次性施加，杜绝「先加后减还是先减后加」的平台顺序歧义
 *      Net-amount arbitration (defense note 1): same-scan CU and CD edges cancel
 *      to net zero; the net value is applied once, eliminating order ambiguity
 *-----------------------------------------------------------------------------*)
IF fbCuTrig.Q AND fbCdTrig.Q THEN
    nNet  := 0;                   // 同拍双向抵消，净变化 0 [个] / Same-scan bidirectional cancel, net zero [count]
    uDiag := 16#0001_0155;        // 信息码：同拍抵消已记录 / Informational: same-scan cancel recorded
ELSIF fbCuTrig.Q THEN
    nNet := 1;                    // 仅加沿，净额 +1 [个] / Up edge only, net plus one [count]
ELSIF fbCdTrig.Q THEN
    nNet := -1;                   // 仅减沿，净额 -1 [个] / Down edge only, net minus one [count]
ELSE
    nNet := 0;                    // 无计数沿，净额 0 [个] / No count edge, net zero [count]
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜计数主体（优先级链 bRESET > bLOAD > 计数，防御声明②）：
 *      双向饱和判界先行——达 DINT 上/下限锁定并置故障码，绝不回绕
 *      Count body (priority chain bRESET > bLOAD > count, defense note 2):
 *      both-direction saturation checked before the update, no wrap ever
 *-----------------------------------------------------------------------------*)
IF bRESET THEN
    nCV := 0;                     // 复位清零计数值 [个] / Reset clears count [count]
ELSIF bLOAD THEN
    nCV := nPVClamp;              // 装载钳位后预置 [个]，本拍跳过计数 / Load clamped preset [count], counting skipped this scan
ELSIF nNet = 1 THEN
    IF nCV < nDintMax THEN
        nCV := nCV + 1;           // 域内递增 1 [个] / In-domain increment by 1 [count]
    ELSE
        uDiag := 16#0001_0226;    // 故障码：CV 上限饱和锁定，不回绕 / Fault: CV upper-limit saturation, no wrap
    END_IF
ELSIF nNet = -1 THEN
    IF nCV > nDintMin THEN
        nCV := nCV - 1;           // 域内递减 1 [个] / In-domain decrement by 1 [count]
    ELSE
        uDiag := 16#0001_0226;    // 故障码：CV 下限饱和锁定，不回绕 / Fault: CV lower-limit saturation, no wrap
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜比较输出：按 IEC CTUD 语义 QU = CV >= PV、QD = CV <= 0
 *      （PV 钳 0 时 bQU 恒 TRUE，属组态提示范畴，见头注释防御声明③）
 *      Compare outputs: per IEC CTUD semantics QU = CV >= PV and QD = CV <= 0
 *      (bQU always TRUE when PV clamped to 0, a configuration hint, defense note 3)
 *-----------------------------------------------------------------------------*)
bQU := (nCV >= nPVClamp);  // 上计数到达比较 [个] / Upper done comparison [count]
bQD := (nCV <= 0);         // 下计数到达比较 [个] / Lower done comparison [count]
END_FUNCTION_BLOCK
