(*==============================================================================
 * 组件名称 (Component)  : FC_DL_IntFloorDiv
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 内建整数除法，零厂商私有库
 * 功能描述 (Function)   : 整数向下取整除法（floor 语义，向 −∞ 取整）。
 *                         与 R46 已入册的 FC_DL_IntCeilDiv 成对：本件向 −∞，那件向 +∞，
 *                         正数域两者等价、负数域才分道，故负数向量是唯一有效判别样本。
 *                         实现路径：先取 IEC 内建整数除法的截断商（向 0 取整）与余数，
 *                         再按"余数与除数异号"判据把商减 1 —— 绝不用 TRUNC(x)+1 类写法
 *                         （R28/R153 整数进位点反例），也不做浮点中转（避免 2^31 精度丢失）。
 *                         验收向量（整数域精确，无容差）：
 *                           (+7, +2) = +3 ；(−7, +2) = −4 ；(+7, −2) = −4 ；(−7, −2) = +3
 *                           同余向量：(+8, +2) = +4 ；(−8, +2) = −4 （整除不偏移）
 *                           边界向量：(MIN_INT, +1) = MIN_INT ；（MIN_INT, −1) 溢出钳位
 * 接口     (Interface)  : 入 nNum 被除数、nDen 除数；出 FC 返回值（floor 商）、bInvalid
 *                         拒算标志（nDen=0 当拍）、bOverflow 溢出钳位标志。
 * 边界     (Boundary)   : ① **零除闸**：nDen = 0 → 返回 0 + bInvalid 当拍，不做任何算术；
 *                         ② **溢出闸**：MIN_INT ÷ −1 在补码域不可表（真值 +2147483648），
 *                         钳位返回 MIN_INT + bOverflow（与 FC_DL_IntCeilDiv 同口径，不饱和到 MAX）；
 *                         ③ 中间量 nQ*nDen 不会溢出：|q·d| ≤ |n| 恒成立，仅 MIN_INT/−1 例外已被②拦截；
 *                         ④ 纯函数无记忆量，无锁存、无跨拍状态；⑤ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"整数域 floor 商"。不接管：浮点取整（用标准库 TRUNC/FLOOR 包装件）、
 *                         向上取整（属 FC_DL_IntCeilDiv）、取模（属 FC_DL_ModLrealSafe 族）。
 * 来源标签 (Source Tag) : T0 防御包装 —— IEC 61131-3 标准语义的道莅防御性实现
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 零除闸 + 溢出双侧钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 判别用 IF/RETURN 链无状态机（无 CASE 需求，非状态件）
 *                         R7 ✓ 无定时器/沿实例（纯组合函数）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 1 · 序号 1）
 *==============================================================================*)

FUNCTION FC_DL_IntFloorDiv : DINT
VAR_INPUT
    nNum : DINT := 0;                       // 被除数，全 DINT 域 [-] / Dividend, full DINT domain
    nDen : DINT := 1;                       // 除数，零值拒算 [-] / Divisor, zero value rejected
END_VAR
VAR_OUTPUT
    bInvalid  : BOOL := FALSE;              // 拒算标志（nDen=0，当拍有效） [-] / Rejection flag (nDen=0, this scan)
    bOverflow : BOOL := FALSE;              // 溢出钳位标志（MIN_INT/−1） [-] / Overflow clamp flag
END_VAR
VAR
    nQ : DINT := 0;                         // 截断商中间量（向 0 取整） [-] / Truncated quotient (towards zero)
    nR : DINT := 0;                         // 截断余数中间量（与被除数同号） [-] / Truncated remainder, sign of dividend
END_VAR
VAR CONSTANT
    DL_DINT_MIN : DINT := -2147483647 - 1;  // DINT 最小值（避字面量溢出写法） [-] / DINT minimum, literal-overflow safe
    DL_DINT_MAX : DINT := 2147483647;       // DINT 最大值（上溢反算参照） [-] / DINT maximum, upper-bound reference
END_VAR

(* —— 段 1：返回值与两标志预置（R45 四段式第①段） —— *)
FC_DL_IntFloorDiv := 0;                     // 返回值预置安全值 0 / Return value preset to 0
bInvalid  := FALSE;                         // 拒算标志预置 / Rejection flag preset
bOverflow := FALSE;                         // 溢出标志预置 / Overflow flag preset

(* —— 段 2：域闸门早退（零除，不进入任何算术） —— *)
IF nDen = 0 THEN
    bInvalid := TRUE;                       // 零除拒算 / Division by zero rejected
    FC_DL_IntFloorDiv := 0;                 // 拒算返回值 0 / Return 0 on rejection
    RETURN;                                 // 早退，不委托内建除法 / Early return, built-in division not invoked
END_IF

(* —— 段 3：溢出闸（补码域不可表的唯一象限） —— *)
IF (nNum = DL_DINT_MIN) AND (nDen = -1) THEN
    bOverflow := TRUE;                      // 溢出标志 / Overflow flag
    FC_DL_IntFloorDiv := DL_DINT_MIN;       // 钳位返回 MIN_INT（不饱和到 MAX，保持符号侧一致） / Clamp to MIN_INT
    RETURN;                                 // 早退 / Early return
END_IF

(* —— 段 4：委托内建截断除法取商与余数 —— *)
nQ := nNum / nDen;                          // IEC 整数除法截断（向 0） / IEC integer division truncates towards zero
nR := nNum - nQ * nDen;                     // 余数＝被除数−商×除数（与被除数同号） / Remainder, same sign as dividend

(* —— 段 5：向 −∞ 修正（余数与除数异号则商减 1；整除时 nR=0 不偏移） —— *)
IF (nR <> 0) AND ((nR < 0) <> (nDen < 0)) THEN
    nQ := nQ - 1;                           // 向下取整修正 / Floor correction
END_IF

(* —— 段 6：统一出口（结果复检：商域必在 [MIN_INT, MAX] 内，无需再钳） —— *)
FC_DL_IntFloorDiv := nQ;                    // 输出 floor 商 / Output the floor quotient

END_FUNCTION
