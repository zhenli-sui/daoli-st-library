(*==============================================================================
 * 组件名称 : FC_DL_IntDigitSumUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 无符号整数的十进制各位数字之和（数字根母函数）。逐次取余取位再整除降位，
 *            纯整数实现，禁字符串转换（字符串转换在多平台补零/符号口径不一致）。
 * 契约     : 返回各位数字之和（最大 10 位 × 9 = 90）；nVal = 0 返回 0。
 *            循环次数以 nVal 位数为上界，结构性有限。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达（本件结构性不置 bError）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除数为常量 10、循环上界固定
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 3/8）
 *============================================================================*)
FUNCTION FC_DL_IntDigitSumUdint : UDINT
VAR_INPUT
    nVal        : UDINT;    // 被分解整数，全域 0~16#FFFF_FFFF [无量纲] / value to decompose over the whole unsigned range
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid      : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_TEN      : UDINT := 10;              // 十进制基数 [无量纲] / decimal radix, dimensionless
    DL_ZERO     : UDINT := 0;               // 整数零哨兵 [无量纲] / integer zero sentinel, dimensionless
    DL_LOOP_MAX : UDINT := 10;              // UDINT 十进制最大位数，循环上界 [位] / largest decimal width of an unsigned value [digit]
END_VAR
VAR
    nRest       : UDINT;    // 降位过程中的剩余值 / remaining value while descending
    nSum        : UDINT;    // 各位数字累计和 / accumulated digit sum
    nGuard      : UDINT;    // 循环守卫计数，防遍历失控 / loop guard counter
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntDigitSumUdint := 0;    // 缺省 0 / default zero
eErr   := 0;                    // 零码位范式 / zero-code rule
bError := FALSE;                // 本件不产生故障级 / this component raises no fault
bValid := TRUE;                 // 分解对全定义域恒可完成 / the decomposition always completes over the whole domain
nRest  := nVal;                 // 从输入起步 / start from the input
nSum   := DL_ZERO;              // 累计清零 / clear the accumulator
nGuard := DL_ZERO;              // 守卫清零 / clear the guard

// 段 2｜逐位取余累加，整除降位；剩余为 0 即停 / segment 2, take the remainder, add it, divide down
WHILE (nRest <> DL_ZERO) AND (nGuard < DL_LOOP_MAX) DO
    nGuard := nGuard + 1;                       // 守卫自增 / advance the guard
    nSum   := nSum + (nRest MOD DL_TEN);        // 取个位并累加 / take the units digit and accumulate
    nRest  := nRest / DL_TEN;                   // 降一位 / shift one digit down
END_WHILE

// 段 3｜出口 / segment 3, exit
FC_DL_IntDigitSumUdint := nSum;                 // 各位数字之和 / the digit sum
END_FUNCTION
