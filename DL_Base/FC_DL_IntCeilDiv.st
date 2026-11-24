(*==============================================================================
 * 组件名称 (Component)  : FC_DL_IntCeilDiv
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅用标准 / 与 MOD 运算、LINT 中间量，无任何厂商内建函数
 * 功能描述 (Function)   : 整数向上取整除法（向 +∞ 取整，DINT 域）。返回 ceil(nDividend / nDivisor)，
 *                         即满足 nResult × nDivisor >= nDividend 的最小整数（nDivisor > 0 时）。
 *                         用于"件数 = ceil(总长 / 单件长)"、"拍数 = ceil(行程 / 步距)"一类分配
 *                         计算——这类场景必须向上取整，写 (a/b)+1 在整除时会多算一件。
 * 负 数 语 义 (Negative): 本件严格按数学 ceil 定义实现，对负数同样向 +∞ 取整，与截断除法
 *                         （向 0 取整）在异号与同负两种情形下都不同：
 *                           ceil( 7 / 2) =  4  ｜ ceil(-7 / 2) = -3
 *                           ceil( 7 / -2) = -3 ｜ ceil(-7 / -2) =  4
 *                         判据写成"余数与除数同号则商加一"，因此对除数负号同样成立；
 *                         若调用方需要"向 0 取整"或"向 −∞ 取整"，请显式换用本件的兄弟实现，
 *                         不要靠改符号位硬凑（负号外提会改变取整方向）。
 * 已知缺陷对照 (AntiPattern): 禁写 TRUNC(x) + 1 —— ① x 已整除时多算一件；② REAL 域大数精度
 *                         丢失后 TRUNC 结果跳变；③ 负数时 TRUNC 向 0 取整，+1 后方向仍错。
 *                         本件全整数域运算，无 TRUNC、无实数转换，三个缺陷同时规避。
 * 接口     (Interface)  : 入 nDividend 被除数、nDivisor 除数；出 bValid 结果有效、
 *                         bDivZero 除零命中、bOverflow 结果越 DINT 域（已饱和）。
 * 边界     (Boundary)   : ① 除零：不计算，返回 0，bValid=FALSE、bDivZero=TRUE（不抛异常，
 *                         不返回魔数 1 或 −1）；② 溢出：用 LINT 中间量算商，越 DINT 域时
 *                         按符号饱和到 DINT 上下限并置 bOverflow、bValid=FALSE（饱和值可直接
 *                         参与后续比较，但不得当作正确值入库）；③ 无状态：纯组合逻辑，
 *                         同一输入永远同一输出，可任意并发调用（无跨拍驻留）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖（仅运算符与类型转换函数）
 * 来源标签 (Source Tag) : T0 防御包装 —— 本件是 **IEC 61131-3 标准语义的道莅防御性实现**：
 *                         向上取整属标准算术语义，防御点在于除零闸、LINT 中间量防溢出、
 *                         余数同号判据（替代 TRUNC+1 缺陷写法）。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。异常出口为 BOOL 三枚
 *                         （bValid / bDivZero / bOverflow）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸 + 溢出双侧直比 + 无浮点比较 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无状态机，无 CASE） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 1 · 序号 3）
 *==============================================================================*)
FUNCTION FC_DL_IntCeilDiv : DINT
VAR_INPUT
    nDividend : DINT := 0;      // 被除数（可为负） [无量纲] / Dividend, may be negative [dimensionless]
    nDivisor  : DINT := 1;      // 除数（可为负，0 触发除零闸） [无量纲] / Divisor, may be negative, 0 trips the divide gate
END_VAR
VAR_OUTPUT
    bValid    : BOOL;           // 结果有效（未除零且未溢出） [-] / Result valid, no divide-by-zero and no overflow
    bDivZero  : BOOL;           // 除零命中，返回值为 0 的哨兵 [-] / Division by zero hit, 0 returned as sentinel
    bOverflow : BOOL;           // 结果越 DINT 域，返回值已饱和 [-] / Result out of DINT range, saturated
END_VAR
VAR
    n64Dividend : LINT;         // 被除数的 64 位副本（防 DINT 域内中间溢出） [无量纲] / 64-bit copy of the dividend
    n64Divisor  : LINT;         // 除数的 64 位副本（防 DINT 域内中间溢出） [无量纲] / 64-bit copy of the divisor
    n64Quot     : LINT;         // 截断商（向 0 取整），再按余数修正 [无量纲] / Truncated quotient before remainder correction
    n64Rem      : LINT;         // 余数，符号随被除数（IEC MOD 语义） [无量纲] / Remainder, sign follows the dividend per IEC MOD
END_VAR
VAR CONSTANT
    DL_ICD_DINT_MAX : LINT := 2147483647;    // DINT 上限，饱和基准 [无量纲] / DINT upper bound for saturation
    DL_ICD_DINT_MIN : LINT := -2147483648;   // DINT 下限，饱和基准 [无量纲] / DINT lower bound for saturation
END_VAR

(* —— 段 1：返回值与出口初始化（任何路径下返回值确定） —— *)
FC_DL_IntCeilDiv := 0;              // 缺省返回 0（哨兵，不作正确值解读） / Default 0 sentinel, not a valid answer
bValid           := TRUE;           // 先假定有效，闸门命中时改判 / Assume valid, gates may overrule
bDivZero         := FALSE;          // 除零标志清零 / Divide-by-zero flag cleared
bOverflow        := FALSE;          // 溢出标志清零 / Overflow flag cleared

(* —— 段 2：除零闸（除零是小概率但后果为停机，故前置硬闸并非后置判断） —— *)
IF nDivisor = 0 THEN
    bValid   := FALSE;              // 结果无效 / Result invalid
    bDivZero := TRUE;               // 除零命中 / Divide-by-zero hit
    RETURN;                         // 提前返回，返回值为段 1 的 0 哨兵 / Early return with the 0 sentinel
END_IF

(* —— 段 3：64 位域截断除 + 余数同号进位（数学 ceil 判据，替代 TRUNC+1） —— *)
n64Dividend := DINT_TO_LINT(nDividend);      // 升域防中间溢出 / Widen to avoid intermediate overflow
n64Divisor  := DINT_TO_LINT(nDivisor);       // 升域防中间溢出 / Widen to avoid intermediate overflow
n64Quot     := n64Dividend / n64Divisor;     // 截断商（向 0 取整） / Truncated quotient toward zero
n64Rem      := n64Dividend MOD n64Divisor;   // 余数，符号随被除数 / Remainder, sign of dividend
IF (n64Rem <> 0)                                     // 非整除才可能进位 / Carry only when not exactly divisible
   AND (((n64Rem > 0) AND (n64Divisor > 0))           // 同正：向 +∞ 进位 / Both positive: carry up
     OR ((n64Rem < 0) AND (n64Divisor < 0))) THEN     // 同负：向 +∞ 进位 / Both negative: carry up
    n64Quot := n64Quot + 1;                          // 唯一进位点，全件仅此一处 / The only carry site in this unit
END_IF

(* —— 段 4：越界双侧直比（禁 ABS 单侧——ABS(DINT_MIN) 无符号可表性已失） —— *)
IF (n64Quot > DL_ICD_DINT_MAX) OR (n64Quot < DL_ICD_DINT_MIN) THEN
    bOverflow := TRUE;              // 溢出标志 / Overflow flag
    bValid    := FALSE;             // 结果无效 / Result invalid
    IF n64Quot > 0 THEN
        FC_DL_IntCeilDiv := 2147483647;     // 正溢出饱和到 DINT 上限 / Saturate to DINT max
    ELSE
        FC_DL_IntCeilDiv := -2147483648;    // 负溢出饱和到 DINT 下限 / Saturate to DINT min
    END_IF
    RETURN;                         // 饱和值可参与比较，但不得当正确值 / Saturated value must not be treated as correct
END_IF

(* —— 段 5：正常出口（无隐式转换，显式降域） —— *)
FC_DL_IntCeilDiv := LINT_TO_DINT(n64Quot);   // 已知在域内，显式降域 / Known in range, explicit narrowing
bValid           := TRUE;                    // 结果有效 / Result valid

END_FUNCTION
