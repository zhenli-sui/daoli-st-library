(*==============================================================================
 * 组件名称 (Component)  : FC_DL_SaturateSub
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library，零厂商私有库
 * 功能描述 (Function)   : 有符号整数（DINT）饱和减法原语：nResult = nMinuend - nSubtrahend，
 *                         结果若超出 DINT 可表域则钳位返回 DINT 域下限/上限，并经引用参数
 *                         bOverflow 置溢出标志；正常域 bOverflow := FALSE。
 *                         与 `FC_DL_SaturateAdd` 成对（那件管累加方向防回绕，本件管扣减方向
 *                         防回绕），实现独立、只对齐注释风格与引脚组织，不复制其实现。
 * 接口     (Interface)  : 输入 nMinuend 被减数、nSubtrahend 减数；
 *                         引用输出 bOverflow 溢出标志（REFERENCE TO BOOL，当拍写回）；
 *                         返回值 = 饱和后的差（DINT）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做单次减法饱和运算，不记忆任何跨拍状态、
 *                         不接管计数器/累积器语义**；调用方自持累积变量并按需调用本件。
 *                         ② 溢出判定采用「先判后算」跨域预判，禁止先算后判（先算后判时中间值
 *                         已回绕、溢出不可观测）：减数 > 0 时下溢预判式为
 *                         nMinuend < (DINT 下限 + 减数)；减数 < 0 时上溢预判式为
 *                         nMinuend > (DINT 上限 + 减数)。两个预判式中的加法结果均在 DINT
 *                         域内可表（下限+正数 ≤ 上限方向、上限+负数 ≥ -1），不产生新的回绕。
 *                         ③ 减数 = 0 时恒为直通拷贝，无溢出可能，bOverflow 恒 FALSE。
 *                         ④ 边界向量覆盖：MIN_INT - (-1)、MAX_INT - 负数、MIN_INT - 正数、
 *                         零减零，详见头注释修订记录所附验收向量。
 *                         ⑤ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_SaturateAdd` 分工：累加方向防回绕归那件、扣减方向防回绕
 *                         归本件（余料核销、步进回退计数等减法域）；二者不互相调用。
 * 来源标签 (Source Tag) : 自研线（成对补口，公开饱和运算定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 DINT 差值 + BOOL 溢出标志；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 先判后算跨域预判 + 类型可表性反算 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-20  v1.0.1  R50 返修 R5：头注释验收向量溢出
 *                         断言更正（实现不动）——原「MIN-(-1)=MIN 溢出」为误
 *                         断言：MIN−(−1) = −2147483647 在 DINT 域内可表，无
 *                         溢出（预判式 nMinuend > MAX−1 对 MIN 不成立，实现
 *                         行为正确）；更正为「MIN-(-1)=MIN+1 正常」。另
 *                         「MIN-1=MIN 溢出」复核成立（MIN−1 下溢钳 MIN）。
 *                         2026-11-20  v1.0.0  R48 首版（批次 1 · 序号 1）
 *                         验收向量：MAX-(-1)=MAX 溢出；MIN-1=MIN 溢出；
 *                         MIN-(-1)=-2147483647 正常（v1.0.1 更正）；0-0=0 正常；
 *                         MIN-MIN=0 正常；MAX-MIN=MAX 溢出。
 *==============================================================================*)

FUNCTION FC_DL_SaturateSub : DINT
VAR_INPUT
    nMinuend    : DINT;                // 被减数 [-] / Minuend of the subtraction
    nSubtrahend : DINT;                // 减数 [-] / Subtrahend of the subtraction
    bOverflow   : REFERENCE TO BOOL;   // 溢出标志（引用传参，当拍写回；TRUE=已钳位） [-] / Overflow flag, by-reference, TRUE when clamped
END_VAR
VAR CONSTANT
    DL_SBS_MIN : DINT := DINT#16#80000000;   // DINT 域下限（类型可表性下界；位型常量，非事件码） [-] / DINT lower bound, bit-pattern constant, not an event code
    DL_SBS_MAX : DINT := 2147483647;         // DINT 域上限（类型可表性上界） [-] / DINT upper bound
END_VAR

(* —— 先判后算：跨域预判溢出，杜绝中间值回绕不可观测 —— *)
bOverflow := FALSE;                                                      // 正常域缺省无溢出 / Default: no overflow
IF nSubtrahend > 0 THEN                                                  // 减数为正：只可能下溢 / Positive subtrahend: underflow only
    IF nMinuend < (DL_SBS_MIN + nSubtrahend) THEN                        // 预判式在 DINT 域内可表 / Pre-check stays representable in DINT
        bOverflow := TRUE;                                               // 下溢成立：置溢出标志 / Underflow: raise overflow flag
        FC_DL_SaturateSub := DL_SBS_MIN;                                 // 钳位返回 DINT 下限 / Clamp to DINT lower bound
        RETURN;                                                          // 早退，不做真实减法 / Early exit, skip the raw subtraction
    END_IF
ELSIF nSubtrahend < 0 THEN                                               // 减数为负：只可能上溢 / Negative subtrahend: overflow only
    IF nMinuend > (DL_SBS_MAX + nSubtrahend) THEN                        // 预判式在 DINT 域内可表 / Pre-check stays representable in DINT
        bOverflow := TRUE;                                               // 上溢成立：置溢出标志 / Overflow: raise overflow flag
        FC_DL_SaturateSub := DL_SBS_MAX;                                 // 钳位返回 DINT 上限 / Clamp to DINT upper bound
        RETURN;                                                          // 早退，不做真实减法 / Early exit, skip the raw subtraction
    END_IF
END_IF

FC_DL_SaturateSub := nMinuend - nSubtrahend;                             // 已证可表的正常域减法 / Subtraction proven representable

END_FUNCTION
