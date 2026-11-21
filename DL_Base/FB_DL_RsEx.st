(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RsEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准运算符，零厂商方言
 * 功能描述 (Function)   : RS 复位优先双稳态防御包装。内部委托 IEC 61131-3 标准
 *                         RS 语义（bQ1 := (NOT bR1) AND (bS OR bQ1)），外围提供
 *                         S/R1 同拍仲裁显式化诊断与主从双输出镜像。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款，未复制任何闭源厂商源码）
 * 码位     (Diag Codes) : 信息级占用区间 16#0001_049B（本件独占，仅此一码）
 *                         16#0001_049B = S/R1 同拍为 TRUE，复位胜出（标准语义，
 *                         仅供现场排查，不置故障）
 *                         （R90 反证句：同拍仲裁事实无法由 bQ1 观测——复位胜出与
 *                           单纯复位的输出同为 FALSE，现有输出组合无法还原「曾发生
 *                           同拍竞争」，故占信息码）
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库实例（纯布尔逻辑）
 * 对偶声明 (Dual Note)  : 本件与 FB_DL_SrEx 严格对偶（仲裁优先级互逆：SR 置位优先、
 *                         RS 复位优先；注释结构逐条对照，仲裁语义方向相反）。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 同拍仲裁显式化，无浮点无除法
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 N/A 无定时器与沿检测实例（纯组合保持逻辑）
 * 说明     (Note)       : R6 标注 N/A —— 本组件为单步双稳态保持逻辑，不存在顺序
 *                         状态机，无 CASE 可写；非法状态不可能出现（唯一状态即
 *                         「保持 / 置位 / 复位」三态组合，由标准布尔语义全覆盖），
 *                         故以本节说明替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 输出语义声明 (R191)   : bS = FALSE 且 bR1 = FALSE 时输出保持末值（双稳态记忆语义），
 *                         非降级非冻结，由标准 RS 语义保证；主从输出 bQ1 与 bQ1M
 *                         单点同源赋值（名实双出口，R191 名实相符）。
 * 修订历史 (Revision)   :
 *   2026-11-19  v1.0.0  首版入库（R40 批 4 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RsEx
VAR_INPUT
    bS  : BOOL;  // 置位输入，TRUE 请求置位，与复位同拍时被复位优先压制 ｜ set input, TRUE requests set, suppressed when simultaneous with the reset
    bR1 : BOOL;  // 复位输入，TRUE 请求复位，与置位同拍时复位优先胜出 ｜ reset input, TRUE requests reset, wins the arbitration when simultaneous with the set
END_VAR
VAR_OUTPUT
    bQ1   : BOOL;  // 主输出，复位优先双稳态 ｜ main output of the reset-dominant bistable
    bQ1M  : BOOL;  // 从输出，与 bQ1 同源镜像（名实双出口）｜ mirror output, same source as bQ1
    uDiag : UDINT; // 诊断字，16#0001_049B=S/R1 同拍复位胜出，0=无诊断事件 ｜ diag word, 16#0001_049B=reset wins on simultaneous S/R1, 0=no diag event
END_VAR

// 段 1｜RS 复位优先标准语义主体（IEC 61131-3 双稳态，不重实现状态内核） ｜ RS reset-dominant standard semantics (IEC 61131-3 bistable, no kernel re-implementation)
bQ1 := (NOT bR1) AND (bS OR bQ1); // 复位优先：R1 为真复位，S 单独为真置位，同拍复位胜出 ｜ reset-dominant: R1 resets, S alone sets, the reset wins on simultaneity

// 段 2｜同拍仲裁显式化诊断（信息级每拍重算口径） ｜ simultaneous-arbitration diagnostics (info level, recomputed every scan)
IF bS AND bR1 THEN
    uDiag := 16#0001_049B; // 同拍仲裁：复位优先胜出（信息级，仅排查用）｜ simultaneous arbitration: the reset wins (info level, for troubleshooting only)
ELSE
    uDiag := 16#0000_0000; // 无同拍仲裁事件，清码（信息级允许每拍重算）｜ no arbitration event, clear the code (info level may be recomputed per scan)
END_IF

// 段 3｜主从输出镜像：单点同源赋值（R191 名实双出口） ｜ main-mirror output: single same-source assignment (R191 paired exits)
bQ1M := bQ1; // 从输出镜像主输出 ｜ the mirror output copies the main output
END_FUNCTION_BLOCK
