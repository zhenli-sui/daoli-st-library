(*==============================================================================
 * 组件名称 : FC_DL_IntDigitCountUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 无符号整数的十进制位数（0 计 1 位）。循环整除 10 计数，纯整数实现，
 *            不使用字符串转换 —— 各平台 INT_TO_STRING 的前导空格/补零口径互不相同。
 * 契约     : 返回 1~10（UDINT 十进制最大 10 位）；nVal = 0 返回 1。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达（本件结构性不置 bError）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除数为常量 10、循环上界固定
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 4/8）
 *============================================================================*)
FUNCTION FC_DL_IntDigitCountUdint : UDINT
VAR_INPUT
    nVal        : UDINT;    // 待测位数的整数，全域 0~16#FFFF_FFFF [无量纲] / value whose decimal width is requested
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 故障标志，本件结构性不置位 / fault flag, never raised by this component
    bValid      : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_TEN      : UDINT := 10;              // 十进制基数 [无量纲] / decimal radix, dimensionless
    DL_ONE      : UDINT := 1;               // 整数一，零值也占一位 [位] / integer one, zero still occupies one digit [digit]
    DL_LOOP_MAX : UDINT := 10;              // 循环上界，等于最大位数 [位] / loop cap equal to the largest width [digit]
END_VAR
VAR
    nRest       : UDINT;    // 降位过程中的剩余值 / remaining value while descending
    nDigits     : UDINT;    // 已计位数 / digits counted so far
    nGuard      : UDINT;    // 循环守卫计数 / loop guard counter
END_VAR

// 段 1｜出口预置：零值占一位，故计数从 1 起 / segment 1, preset with one digit because zero occupies one position
FC_DL_IntDigitCountUdint := 0;  // 缺省 0 / default zero
eErr    := 0;                   // 零码位范式 / zero-code rule
bError  := FALSE;               // 本件不产生故障级 / this component raises no fault
bValid  := TRUE;                // 全定义域恒可完成 / always completes over the whole domain
nRest   := nVal;                // 从输入起步 / start from the input
nDigits := DL_ONE;              // 零值即一位 / zero already occupies one digit
nGuard  := 0;                   // 守卫清零 / clear the guard

// 段 2｜降位：剩余值 ≥ 10 才进一位 / segment 2, divide down while the remainder is ten or more
WHILE (nRest >= DL_TEN) AND (nGuard < DL_LOOP_MAX) DO
    nGuard  := nGuard + DL_ONE;         // 守卫自增 / advance the guard
    nRest   := nRest / DL_TEN;          // 降一位 / shift one digit down
    nDigits := nDigits + DL_ONE;        // 位数加一 / one more digit
END_WHILE

// 段 3｜出口 / segment 3, exit
FC_DL_IntDigitCountUdint := nDigits;    // 1~10 / one to ten
END_FUNCTION
