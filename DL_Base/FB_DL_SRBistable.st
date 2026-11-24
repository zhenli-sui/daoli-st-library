(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SRBistable
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准运算符，零厂商方言
 * 功能描述 (Function)   : SR 置位优先双稳态防御包装。内部委托 IEC 61131-3 标准
 *                         SR 语义（bQ1 := bS1 OR (bQ1 AND NOT bR)），外围提供
 *                         S1/R 同拍仲裁显式化与仲裁诊断码输出。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_014D（本件独占，仅此一码）
 *                         16#0001_014D = S1/R 同拍为 TRUE，置位胜出（标准语义，
 *                         仅供现场排查，不置故障）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库实例（纯布尔逻辑）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 同拍仲裁显式化+首扫初始化
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ 无定时器/沿检测实例（N/A）
 * 说明     (Note)       : R6 标注 N/A —— 本组件为组合逻辑双稳态，不存在顺序状态机，
 *                         无 CASE 可写；非法状态不可能出现（唯一状态即输出锁存），
 *                         故以本节说明替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① S1 与 R 同拍为 TRUE 时按 IEC 语义置位优先（S1 胜出），
 *                           同时置信息级诊断码 16#0001_014D，下拍仲裁消失自动清零；
 *                         ② 首扫输出初始化为 FALSE，杜绝上电假输出。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 1 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SRBistable
VAR_INPUT
    bS1 : BOOL;  // 置位主导输入（IEC S1 语义），TRUE 时输出无条件置位 / Set-dominant input (IEC S1), TRUE forces output set
    bR  : BOOL;  // 复位输入，仅在 S1 为 FALSE 的拍次生效 / Reset input, effective only on scans where S1 is FALSE
END_VAR
VAR_OUTPUT
    bQ1   : BOOL;   // 置位优先输出（IEC Q1 语义），TRUE 保持至复位 / Set-dominant output (IEC Q1), latched TRUE until reset
    uDiag : UDINT;  // 仲裁诊断字，16#0001_014D=S1/R 同拍置位胜出，0=无仲裁事件 / Arbitration diag word, 16#0001_014D=same-scan S1/R with set winning, 0=no arbitration
END_VAR
VAR
    xInit : BOOL;   // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜首扫初始化（历史教训⑤口径）：置于逻辑最前，禁止"初值置位后同步清零"反模式
 *      First-scan init (lesson 5): placed at the very front of the logic body
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit := TRUE;      // 置初始化完成标志 / Mark init as done
    bQ1   := FALSE;     // 首扫输出强制 FALSE，杜绝上电假输出 / Force output FALSE on first scan
    uDiag := 16#0000_0000;  // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜同拍仲裁诊断：S1 与 R 同拍为 TRUE 是标准定义的合法竞态，置信息码不置故障
 *      Same-scan arbitration diag: S1 AND R is a legal race per the standard,
 *      informational code only, never a fault
 *-----------------------------------------------------------------------------*)
IF bS1 AND bR THEN
    uDiag := 16#0001_014D;  // 同拍竞态：置位优先胜出（信息级）/ Same-scan race: set-dominant wins (informational)
ELSE
    uDiag := 16#0000_0000;  // 无竞态，诊断字清零 / No race, clear diag word
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜SR 置位优先核心语义（委托 IEC 61131-3 标准 SR 定义，不重实现）：
 *      bQ1 := bS1 OR (bQ1 AND NOT bR)，右侧 bQ1 取上一拍锁存值
 *      SR set-dominant core semantics (delegates to the IEC 61131-3 SR definition);
 *      the bQ1 on the right-hand side reads the latched value of the previous scan
 *-----------------------------------------------------------------------------*)
bQ1 := bS1 OR (bQ1 AND NOT bR);  // 置位优先：S1=1 恒置位，S1=0 且 R=1 才复位 / Set-dominant: S1=1 always sets, reset only when S1=0 and R=1
END_FUNCTION_BLOCK
