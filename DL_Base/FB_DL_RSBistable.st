(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RSBistable
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准运算符，零厂商方言
 * 功能描述 (Function)   : RS 复位优先双稳态防御包装。内部委托 IEC 61131-3 标准
 *                         RS 语义（bQ := (bS OR bQ) AND NOT bR1），外围提供
 *                         S/R1 同拍仲裁显式化与仲裁诊断码输出。
 *                         与 FB_DL_SRBistable 为镜像件（SR=置位优先，RS=复位优先），
 *                         选型时以"同拍竞态时谁说了算"为准，两者头注释互引。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_014E（本件独占，仅此一码）
 *                         16#0001_014E = S/R1 同拍为 TRUE，复位胜出（标准语义，
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
 * 防御行为声明 (Defense): ① S 与 R1 同拍为 TRUE 时按 IEC 语义复位优先（R1 胜出），
 *                           同时置信息级诊断码 16#0001_014E，下拍仲裁消失自动清零；
 *                         ② 首扫输出初始化为 FALSE，杜绝上电假输出。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 1 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RSBistable
VAR_INPUT
    bS  : BOOL;  // 置位输入，仅在 R1 为 FALSE 的拍次生效 / Set input, effective only on scans where R1 is FALSE
    bR1 : BOOL;  // 复位主导输入（IEC R1 语义），TRUE 时输出无条件复位 / Reset-dominant input (IEC R1), TRUE forces output reset
END_VAR
VAR_OUTPUT
    bQ    : BOOL;   // 复位优先输出（IEC Q1 语义），TRUE 保持至复位 / Reset-dominant output (IEC Q1), latched TRUE until reset
    uDiag : UDINT;  // 仲裁诊断字，16#0001_014E=S/R1 同拍复位胜出，0=无仲裁事件 / Arbitration diag word, 16#0001_014E=same-scan S/R1 with reset winning, 0=no arbitration
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
    bQ    := FALSE;     // 首扫输出强制 FALSE，杜绝上电假输出 / Force output FALSE on first scan
    uDiag := 16#0000_0000;  // 首扫诊断字清零 / Clear diag word on first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜同拍仲裁诊断：S 与 R1 同拍为 TRUE 是标准定义的合法竞态，置信息码不置故障
 *      Same-scan arbitration diag: S AND R1 is a legal race per the standard,
 *      informational code only, never a fault
 *-----------------------------------------------------------------------------*)
IF bS AND bR1 THEN
    uDiag := 16#0001_014E;  // 同拍竞态：复位优先胜出（信息级）/ Same-scan race: reset-dominant wins (informational)
ELSE
    uDiag := 16#0000_0000;  // 无竞态，诊断字清零 / No race, clear diag word
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜RS 复位优先核心语义（委托 IEC 61131-3 标准 RS 定义，不重实现）：
 *      bQ := (bS OR bQ) AND NOT bR1，右侧 bQ 取上一拍锁存值
 *      RS reset-dominant core semantics (delegates to the IEC 61131-3 RS definition);
 *      the bQ on the right-hand side reads the latched value of the previous scan
 *-----------------------------------------------------------------------------*)
bQ := (bS OR bQ) AND NOT bR1;  // 复位优先：R1=1 恒复位，R1=0 且 S=1 才置位 / Reset-dominant: R1=1 always resets, set only when R1=0 and S=1
END_FUNCTION_BLOCK
