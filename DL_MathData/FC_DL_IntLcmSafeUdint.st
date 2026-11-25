(*==============================================================================
 * 组件名称 : FC_DL_IntLcmSafeUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : UDINT 最小公倍数，先除后乘防溢出：LCM = (nA / GCD) × nB。供脉冲当量配比、
 *            电子齿轮比约分、多轴同步周期归一使用。
 * 契约     : 任一入参为 0 返回 0（IV 约定 LCM(0, x) = 0，信息级，bError 保持 FALSE）；
 *            乘积仍溢出 UDINT 时饱和到 16#FFFF_FFFF 并置 bOverflow := TRUE、bError := TRUE、
 *            bValid := FALSE（饱和值非精确结果，调用方须按故障处理）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现：欧几里得 GCD 内联），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid / bOverflow 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（nG ≥ 1 由「非双零」保证）+ 乘法前反算上界
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 双零入参同属「任一为 0」分支返回 0；GCD 迭代守卫 64 步为安全断言，
 *            理论不可达（欧几里得余量单调递减）；溢出判定用 nQ > (16#FFFF_FFFF / nB)
 *            反算，不做乘法后再比（乘后比已无意义，值已回绕）。
 * 修订历史 : 2026-11-24 R79-B 首版（整数数论族 7/8）
 *============================================================================*)
FUNCTION FC_DL_IntLcmSafeUdint : UDINT
VAR_INPUT
    nA : UDINT := 0; // 左操作数 [脉冲 / 计数] / the left operand, unsigned
    nB : UDINT := 0; // 右操作数 [脉冲 / 计数] / the right operand, unsigned
END_VAR
VAR_OUTPUT
    eErr      : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;  // 乘积溢出时为真（与 bOverflow 同源）/ TRUE on a product overflow, the same source as bOverflow
    bValid    : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
    bOverflow : BOOL;  // 饱和标志：已钳到 16#FFFF_FFFF / TRUE when the result is saturated to the unsigned ceiling
END_VAR
VAR CONSTANT
    DL_ZERO  : UDINT := 0;          // 无符号零哨兵 / unsigned zero sentinel
    DL_ONE   : UDINT := 1;          // 无符号一哨兵 / unsigned one sentinel
    DL_UMAX  : UDINT := 16#FFFF_FFFF; // UDINT 上界，饱和目标 [无量纲] / the unsigned ceiling used for saturation
    DL_GUARD : DINT  := 64;         // GCD 迭代守卫上界 [次] / the euclid guard ceiling
    DL_GUARDI : DINT := 0;          // 迭代计数初值 [次] / the iteration counter start value
END_VAR
VAR
    nX    : UDINT; // GCD 迭代被除数副本 [无量纲] / the gcd dividend copy
    nY    : UDINT; // GCD 迭代除数副本 [无量纲] / the gcd divisor copy
    nG    : UDINT; // 最大公约数 [无量纲] / the greatest common divisor
    nQ    : UDINT; // 先除得商 nA / GCD [无量纲] / the quotient of the division done first
    nIter : DINT;  // GCD 迭代计数，供收敛审计 [次] / the euclid iteration count
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntLcmSafeUdint := DL_ZERO;  // 缺省零 / default zero
eErr      := 0;                    // 零码位范式 / zero-code rule
bError    := FALSE;                // 预置无故障 / preset no fault
bValid    := FALSE;                // 域闸前不认返回值 / the return value is unusable until the gates pass
bOverflow := FALSE;                // 预置未饱和 / preset no saturation

// 段 2｜零入参短路：IV 约定 LCM(0, x) = 0，属信息级不算故障 / segment 2, the zero operand short circuit
IF (nA = DL_ZERO) OR (nB = DL_ZERO) THEN
    bValid := TRUE;                // 0 是合法约定值 / zero is the agreed value here
    RETURN;                        // 返回 0 / return the preset zero
END_IF

// 段 3｜欧几里得 GCD（守卫计数为安全断言，理论不可达）/ segment 3, the euclidean gcd with a guard
nX    := nA;                       // 被除数副本 / dividend copy
nY    := nB;                       // 除数副本 / divisor copy
nIter := DL_GUARDI;                // 计数清零 / clear the counter
WHILE (nY <> DL_ZERO) AND (nIter < DL_GUARD) DO
    nG    := nX MOD nY;            // 余数（nY 非零已证，除法安全）/ the remainder, the divisor is proven non zero
    nX    := nY;                   // 左移 / shift left
    nY    := nG;                   // 左移 / shift left
    nIter := nIter + 1;            // 计数递增 / increment the counter
END_WHILE
IF nIter >= DL_GUARD THEN
    bError := TRUE;                // 守卫命中属平台异常 / a guard hit means a platform anomaly
    RETURN;                        // 返回 0 / return the preset zero
END_IF
nG := nX;                          // 收敛值即 GCD，非双零保证 nG ≥ 1 / the converged value is the gcd and it is at least one

// 段 4｜先除：nQ = nA / GCD，除零已被 nG ≥ 1 拦住 / segment 4, the division done before the multiplication
nQ := nA / nG;                     // 商 [无量纲] / the quotient

// 段 5｜乘法前反算上界：nQ × nB 是否可表示 / segment 5, the pre multiplication ceiling
IF nQ > (DL_UMAX / nB) THEN        // 除零不可达：nB 非零已由段 2 保证 / the divisor is proven non zero
    bOverflow := TRUE;             // 饱和标志 / saturation flag
    bError    := TRUE;             // 故障级：结果不精确 / fault level, the result is inexact
    FC_DL_IntLcmSafeUdint := DL_UMAX;  // 饱和到上界 / saturate to the ceiling
    RETURN;                        // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 6｜安全乘法与出口 / segment 6, the safe multiplication and the exit
FC_DL_IntLcmSafeUdint := nQ * nB;  // 已证可表示 / proven representable
bValid := TRUE;                    // 返回值可用 / the return value is usable
END_FUNCTION
