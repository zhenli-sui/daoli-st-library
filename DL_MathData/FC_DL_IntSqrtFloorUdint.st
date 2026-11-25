(*==============================================================================
 * 组件名称 : FC_DL_IntSqrtFloorUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 无符号整数平方根向下取整 ⌊√nVal⌋。牛顿迭代：初值 nVal DIV 2 + 1，
 *            下一试值 = (试值 + nVal DIV 试值) DIV 2，试值不再下降即收敛。
 *            纯整数运算，无浮点、无 SQRT，2^32 全域精确。
 * 契约     : 返回 ⌊√nVal⌋；nVal = 0 返回 0；nIter 达上限 64 次仍未收敛时返回最后一次
 *            试值并置 bError（结构性不可达，作为防死循环兜底）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（试值恒 ≥1）、迭代上限兜底、
 *            和式上界 ≤ 2^31+1 不溢出 R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 无类型转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 1/8）
 *============================================================================*)
FUNCTION FC_DL_IntSqrtFloorUdint : UDINT
VAR_INPUT
    nVal        : UDINT;    // 被开方数，全域 0~16#FFFF_FFFF [无量纲] / radicand over the whole unsigned range
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 迭代未收敛为真（结构性不可达） / TRUE when the iteration fails to converge, unreachable in theory
    bValid      : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_TWO      : UDINT := 2;               // 牛顿迭代的除数 2 [无量纲] / Newton divisor, dimensionless
    DL_ONE      : UDINT := 1;               // 整数一 [无量纲] / integer one, dimensionless
    DL_ZERO     : UDINT := 0;               // 整数零哨兵 [无量纲] / integer zero sentinel, dimensionless
    DL_ITER_MAX : UDINT := 64;              // 迭代次数上限，二次收敛下 32 次已足 [次] / iteration cap, quadratic convergence needs far fewer [count]
END_VAR
VAR
    nApprox     : UDINT;    // 当前试值，迭代中单调下降 / current trial value, monotonically decreasing
    nNext       : UDINT;    // 下一试值 / next trial value
    nIter       : UDINT;    // 已用迭代次数 / iterations consumed so far
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntSqrtFloorUdint := 0;   // 缺省 0 / default zero
eErr   := 0;                    // 零码位范式 / zero-code rule
bError := FALSE;                // 预置无故障 / preset no fault
bValid := FALSE;                // 计算完成前不认结果 / unusable until the iteration ends

// 段 2｜零边界：0 的平方根为 0，直接放行，避免初值 1 走迭代 / segment 2, the zero boundary
IF nVal = DL_ZERO THEN
    bValid := TRUE;             // 结果 0 可用 / the zero result is usable
    RETURN;                     // 返回 0 / return zero
END_IF

// 段 3｜牛顿迭代：初值取 nVal DIV 2 + 1，必 ≥ √nVal，故单调下降 / segment 3, Newton iteration from an upper bound
nApprox := (nVal / DL_TWO) + DL_ONE;                // 上界初值，避免 nVal DIV nApprox 除零 / upper bound start, keeps the divisor non zero
nIter   := DL_ZERO;                                 // 迭代计数清零 / clear the counter
WHILE nIter < DL_ITER_MAX DO
    nIter   := nIter + DL_ONE;                      // 先计数后算，保证上限生效 / count first so the cap is honoured
    nNext   := (nApprox + (nVal / nApprox)) / DL_TWO;   // 和式上界约 2^31+1，不溢出 / the sum stays near two to the thirty first, no overflow
    IF nNext >= nApprox THEN
        EXIT;                                       // 试值不再下降即收敛 / the trial stops decreasing, converged
    END_IF
    nApprox := nNext;                               // 继续下降 / keep descending
END_WHILE

// 段 4｜收敛自证：用尽上限仍未收敛按故障处置，返回最后一次试值 / segment 4, convergence self proof
IF nIter >= DL_ITER_MAX THEN
    bError := TRUE;                 // 未收敛（理论不可达）/ not converged, unreachable in theory
    FC_DL_IntSqrtFloorUdint := nApprox;
    RETURN;                         // 返回最后一次试值，bValid 保持 FALSE / return the last trial with bValid still FALSE
END_IF

// 段 5｜出口 / segment 5, exit
FC_DL_IntSqrtFloorUdint := nApprox;     // ⌊√nVal⌋ / floor of the square root
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
