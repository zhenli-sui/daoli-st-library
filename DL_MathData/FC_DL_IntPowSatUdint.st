(*==============================================================================
 * 组件名称 : FC_DL_IntPowSatUdint ｜ 子库 : DL_MathData ｜ v1.0.2 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 无符号整数快速幂（平方求幂），溢出即饱和到 16#FFFF_FFFF 并置 bOverflow。
 *            乘前反算上界：被乘数 > 上限 DIV 乘数 即判溢出，绝不让乘法先回绕。
 * 契约     : 返回 nBase^nExp；nExp = 0 返回 1（含 0^0 口径取 1）；饱和时返回
 *            16#FFFF_FFFF 且 bOverflow := TRUE，bValid 仍为 TRUE（饱和值是确定结论）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，饱和以 bOverflow 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 乘前反算防溢出、除零前置、循环上限 32 次
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 5/8）
 *============================================================================*)
FUNCTION FC_DL_IntPowSatUdint : UDINT
VAR_INPUT
    nBase       : UDINT;    // 底数，全域 [无量纲] / base over the whole unsigned range
    nExp        : UDINT;    // 指数，全域 [无量纲] / exponent over the whole unsigned range
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid      : BOOL;     // 结果可用标志，饱和亦为可用结论 / TRUE even when saturated, saturation is a definite verdict
    bOverflow   : BOOL;     // 结果已饱和到 UDINT 上界 / TRUE when the result saturated at the unsigned upper bound
END_VAR
VAR CONSTANT
    DL_MAX_UDINT : UDINT := 16#FFFF_FFFF;   // UDINT 上界，饱和目标值 [无量纲] / unsigned upper bound and saturation target
    DL_TWO       : UDINT := 2;              // 指数折半基数 [无量纲] / exponent halving radix
    DL_ONE       : UDINT := 1;              // 整数一 / integer one
    DL_ZERO      : UDINT := 0;              // 整数零哨兵 / integer zero sentinel
    DL_ITER_MAX  : UDINT := 32;             // 指数最多 32 位，迭代上限 [次] / an exponent has at most thirty two bits [count]
END_VAR
VAR
    nBaseUse    : UDINT;    // 迭代中的底数（含平方） / running base, includes the squaring steps
    nExpUse     : UDINT;    // 迭代中的指数（逐次折半） / running exponent, halved every step
    nRes        : UDINT;    // 结果累乘器 / result accumulator
    nIter       : UDINT;    // 已用迭代次数 / iterations consumed so far
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntPowSatUdint := 0;      // 缺省 0 / default zero
eErr      := 0;                 // 零码位范式 / zero-code rule
bError    := FALSE;             // 本件不产生故障级 / this component raises no fault
bValid    := TRUE;              // 全定义域给出确定结论 / a definite verdict for the whole domain
bOverflow := FALSE;             // 预置未饱和 / preset unsaturated
nRes      := DL_ONE;            // 累乘器初值 1 / accumulator starts at one

// 段 2｜零指数边界：任何底数的 0 次幂为 1 / segment 2, the zero exponent boundary
IF nExp = DL_ZERO THEN
    FC_DL_IntPowSatUdint := DL_ONE;     // 结果为 1 / the result is one
    RETURN;
END_IF

// 段 3｜平方求幂：逐位判断，乘前反算溢出 / segment 3, square and multiply with an overflow reflection
nBaseUse := nBase;                  // 底数工作副本 / working copy of the base
nExpUse  := nExp;                   // 指数工作副本 / working copy of the exponent
nIter    := DL_ZERO;
WHILE (nExpUse > DL_ZERO) AND (nIter < DL_ITER_MAX) DO
    nIter := nIter + DL_ONE;                        // 守卫自增 / advance the guard
    IF (nExpUse MOD DL_TWO) = DL_ONE THEN           // 当前最低位为 1 才乘 / multiply only when the low bit is set
        IF (nBaseUse <> DL_ZERO) AND (nRes > (DL_MAX_UDINT / nBaseUse)) THEN
            nRes      := DL_MAX_UDINT;              // 反算超界，直接饱和 / the reflection overshoots, saturate at once
            bOverflow := TRUE;
        ELSE
            nRes := nRes * nBaseUse;                // 安全乘法 / safe multiplication
        END_IF
    END_IF
    nExpUse := nExpUse / DL_TWO;                    // 指数折半，除数为常量 2 / halve the exponent
    IF nExpUse > DL_ZERO THEN
        IF (nBaseUse <> DL_ZERO) AND (nBaseUse > (DL_MAX_UDINT / nBaseUse)) THEN
            nBaseUse  := DL_MAX_UDINT;              // 平方超界，钳到上限 / the squaring overshoots, clamp to the ceiling
            bOverflow := TRUE;                      // 平方已越界 = 真溢出（v1.0.2 修：v1.0.1 前此处无回执，静默出残值）/ squaring overflowed, raise the receipt (silent residue before v1.0.2)
        ELSE
            nBaseUse := nBaseUse * nBaseUse;        // 安全平方 / safe squaring
        END_IF
    END_IF
END_WHILE
(* v1.0.2 更正：v1.0.1 曾在此按 nIter 触顶置 bOverflow，但 nBase <= 1 且 nExp >= 2^31 时
   循环合法打满 32 次仍应收敛（1^N = 1），该判据造成假溢出回执，已删除；
   溢出回执改为只在「乘前反算越界」与「平方钳位」两处产生（唯一真溢出来源）。 *)

// 段 4｜出口 / segment 4, exit
FC_DL_IntPowSatUdint := nRes;                   // 结果或饱和值 / the result or the saturation value
END_FUNCTION
