(*==============================================================================
 * 组件名称 : FC_DL_IntReverseDigitsUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 无符号整数的十进制数字反转（如 123 → 321，120 → 21，末尾零自然丢弃）。
 *            逐位取余乘十再累加，纯整数实现。乘前反算：累加器 > (上界 − 当前位) DIV 10
 *            即判溢出，饱和到 16#FFFF_FFFF 并置 bOverflow。
 * 契约     : 返回反转值；反转结果超 UDINT 域时返回 16#FFFF_FFFF、bOverflow := TRUE、
 *            bValid 保持 TRUE（饱和值是确定结论）。nVal = 0 返回 0。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，溢出以 bOverflow 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 乘前反算防溢出、循环上界 10 次、除数为常量
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 8/8）
 *============================================================================*)
FUNCTION FC_DL_IntReverseDigitsUdint : UDINT
VAR_INPUT
    nVal        : UDINT;    // 待反转整数，全域 0~16#FFFF_FFFF [无量纲] / value to reverse over the whole unsigned range
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid      : BOOL;     // 结果可用标志，饱和亦为可用结论 / TRUE even when saturated
    bOverflow   : BOOL;     // 反转结果已饱和到 UDINT 上界 / TRUE when the reversed value saturated
END_VAR
VAR CONSTANT
    DL_TEN       : UDINT := 10;             // 十进制基数 [无量纲] / decimal radix, dimensionless
    DL_MAX_UDINT : UDINT := 16#FFFF_FFFF;   // UDINT 上界，饱和目标值 [无量纲] / unsigned upper bound and saturation target
    DL_ZERO      : UDINT := 0;              // 整数零哨兵 / integer zero sentinel
    DL_LOOP_MAX  : UDINT := 10;             // UDINT 十进制最大位数，循环上界 [位] / loop cap equal to the largest decimal width [digit]
END_VAR
VAR
    nRest       : UDINT;    // 降位过程中的剩余值 / remaining value while descending
    nRev        : UDINT;    // 反转累加器 / reversed accumulator
    nDigit      : UDINT;    // 当前取出的个位数 / the digit taken from the current position
    nGuard      : UDINT;    // 循环守卫计数 / loop guard counter
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntReverseDigitsUdint := 0;   // 缺省 0 / default zero
eErr      := 0;                     // 零码位范式 / zero-code rule
bError    := FALSE;                 // 本件不产生故障级 / this component raises no fault
bValid    := TRUE;                  // 饱和也是确定结论 / saturation is still a definite verdict
bOverflow := FALSE;                 // 预置未饱和 / preset unsaturated
nRest     := nVal;                  // 从输入起步 / start from the input
nRev      := DL_ZERO;               // 累加器清零 / clear the accumulator
nGuard    := DL_ZERO;               // 守卫清零 / clear the guard

// 段 2｜逐位反转：取个位 → 降位 → 乘前反算后累加 / segment 2, digit by digit reversal with an overflow reflection
WHILE (nRest <> DL_ZERO) AND (nGuard < DL_LOOP_MAX) DO
    nGuard := nGuard + 1;                                   // 守卫自增 / advance the guard
    nDigit := nRest MOD DL_TEN;                             // 取个位 / take the units digit
    nRest  := nRest / DL_TEN;                               // 降一位 / shift one digit down
    IF nRev > ((DL_MAX_UDINT - nDigit) / DL_TEN) THEN
        nRev      := DL_MAX_UDINT;                          // 反算超界，饱和退出 / the reflection overshoots, saturate and stop
        bOverflow := TRUE;
        EXIT;
    END_IF
    nRev := (nRev * DL_TEN) + nDigit;                       // 旧位左移一位并接上新位 / shift the old digits and append
END_WHILE

// 段 3｜出口 / segment 3, exit
FC_DL_IntReverseDigitsUdint := nRev;    // 反转值或饱和值 / the reversed value or the saturation value
END_FUNCTION
