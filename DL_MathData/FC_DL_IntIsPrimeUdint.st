(*==============================================================================
 * 组件名称 : FC_DL_IntIsPrimeUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : UDINT 素性判定（试除法）。供伪随机序列、哈希桶数选取、周期分解等调用方。
 *            循环条件写作 nD <= nVal / nD，用除法代替 nD × nD，从根上排除乘法溢出（禁 i*i）。
 * 契约     : 返回 TRUE 表示素数、FALSE 表示合数或 nVal < 2；两者均为合法答案，
 *            bValid := TRUE、bError 保持 FALSE（本件无故障级路径，全为信息级语义）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（nD ≥ 3 恒定）+ 禁 i*i
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : nVal < 2（含 0、1）非素数；2 为唯一偶素数，其余偶数短路；
 *            循环天然终止（nD 严格递增、nVal / nD 单调递减），故不设守卫计数；
 *            最坏步数 ⌊√(2³²−1)⌋ / 2 ≈ 32768 次，请在毫秒级任务中避免逐周期调用。
 * 修订历史 : 2026-11-24 R79-B 首版（整数数论族 8/8）
 *============================================================================*)
FUNCTION FC_DL_IntIsPrimeUdint : BOOL
VAR_INPUT
    nVal : UDINT := 0; // 待判定整数 [无量纲] / the value to be tested
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 故障标志，本件恒 FALSE（素性判定无故障级）/ the fault flag, always FALSE here
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO  : UDINT := 0; // 无符号零哨兵 / unsigned zero sentinel
    DL_ONE   : UDINT := 1; // 无符号一哨兵 / unsigned one sentinel
    DL_TWO   : UDINT := 2; // 无符号二哨兵，唯一偶素数 / unsigned two, the only even prime
    DL_THREE : UDINT := 3; // 无符号三哨兵，试除起点 / unsigned three, the trial division start
END_VAR
VAR
    nD : UDINT; // 试除因子，仅取奇数 3, 5, 7, … [无量纲] / the odd trial divisor
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntIsPrimeUdint := FALSE;  // 缺省合数 / default to composite
eErr   := 0;                     // 零码位范式 / zero-code rule
bError := FALSE;                 // 本件无故障级 / this component has no fault level
bValid := FALSE;                 // 判定完成前不认出参 / the result is unusable until the decision is made

// 段 2｜小于 2 的域闸：0 与 1 都不是素数，属合法答案不算故障 / segment 2, the lower domain gate
IF nVal < DL_TWO THEN
    bValid := TRUE;              // FALSE 是合法答案 / FALSE is a legal answer
    RETURN;                      // 返回 FALSE / return the preset FALSE
END_IF

// 段 3｜2 与偶数短路：2 是唯一偶素数 / segment 3, the two and the even number short circuits
IF nVal = DL_TWO THEN
    FC_DL_IntIsPrimeUdint := TRUE;  // 2 为素数 / two is prime
    bValid := TRUE;                 // 判定可用 / the decision is usable
    RETURN;                         // 返回 TRUE / return TRUE
END_IF
IF (nVal MOD DL_TWO) = DL_ZERO THEN
    bValid := TRUE;              // 合数是合法答案 / composite is a legal answer
    RETURN;                      // 返回 FALSE / return the preset FALSE
END_IF

// 段 4｜奇数试除：条件写 nD <= nVal / nD，等价于 nD² <= nVal 但永不溢出 / segment 4, the odd trial division
nD := DL_THREE;                  // 试除起点 3 / start from three
WHILE nD <= (nVal / nD) DO       // 除零不可达：nD ≥ 3 / the divisor is at least three, so no division by zero
    IF (nVal MOD nD) = DL_ZERO THEN
        bValid := TRUE;          // 合数是合法答案 / composite is a legal answer
        RETURN;                  // 返回 FALSE / return the preset FALSE
    END_IF
    nD := nD + DL_TWO;           // 只试奇数 / odd divisors only
END_WHILE

// 段 5｜无因子即素数 / segment 5, no divisor means prime
FC_DL_IntIsPrimeUdint := TRUE;   // 素数 / prime
bValid := TRUE;                  // 判定可用 / the decision is usable
END_FUNCTION
