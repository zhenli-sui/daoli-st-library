(*==============================================================================
 * 组件名称 : FC_DL_IntIsPerfectSquareUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 判定无符号整数是否为完全平方数。先牛顿迭代求 ⌊√nVal⌋，再回乘比较 ——
 *            回乘前先判根是否 > 65535：UDINT 域内平方根最大 65535，越界者
 *            平方必超 2^32，回乘会回绕，故直接判否（溢出结构性拦在乘法之前）。
 * 契约     : 返回 TRUE=完全平方数（0 视为完全平方）；迭代未收敛时置 bError 并返回 FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 回乘前溢出反算 + 迭代上限 + 除零前置
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 2/8）
 *============================================================================*)
FUNCTION FC_DL_IntIsPerfectSquareUdint : BOOL
VAR_INPUT
    nVal        : UDINT;    // 待判定整数，全域 0~16#FFFF_FFFF [无量纲] / candidate over the whole unsigned range
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 迭代未收敛为真（结构性不可达） / TRUE when the iteration fails to converge, unreachable in theory
    bValid      : BOOL;     // 判定可用标志 / TRUE when the verdict is usable
END_VAR
VAR CONSTANT
    DL_TWO      : UDINT := 2;               // 牛顿迭代除数 [无量纲] / Newton divisor, dimensionless
    DL_ONE      : UDINT := 1;               // 整数一 [无量纲] / integer one, dimensionless
    DL_ZERO     : UDINT := 0;               // 整数零哨兵 [无量纲] / integer zero sentinel, dimensionless
    DL_ITER_MAX : UDINT := 64;              // 迭代次数上限 [次] / iteration cap [count]
    DL_ROOT_MAX : UDINT := 65535;           // UDINT 域内平方根上限，超过则平方必溢出 [无量纲] / largest root that still squares inside the unsigned range
END_VAR
VAR
    nApprox     : UDINT;    // 当前试值 / current trial value
    nNext       : UDINT;    // 下一试值 / next trial value
    nIter       : UDINT;    // 已用迭代次数 / iterations consumed so far
    nSquare     : UDINT;    // 根的回乘结果 / square of the resolved root
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntIsPerfectSquareUdint := FALSE;     // 缺省非完全平方 / default not a perfect square
eErr   := 0;                                // 零码位范式 / zero-code rule
bError := FALSE;                            // 预置无故障 / preset no fault
bValid := FALSE;                            // 迭代结束前不认判定 / unusable until the iteration ends

// 段 2｜零边界：0 = 0²，直接判真 / segment 2, the zero boundary
IF nVal = DL_ZERO THEN
    bValid := TRUE;                         // 判定可用 / the verdict is usable
    FC_DL_IntIsPerfectSquareUdint := TRUE;  // 零是完全平方 / zero is a perfect square
    RETURN;
END_IF

// 段 3｜牛顿迭代求根（与求根族同法，内联自足不跨件调用） / segment 3, inline Newton root
nApprox := (nVal / DL_TWO) + DL_ONE;        // 上界初值 / upper bound start
nIter   := DL_ZERO;
WHILE nIter < DL_ITER_MAX DO
    nIter := nIter + DL_ONE;                // 计数 / count
    nNext := (nApprox + (nVal / nApprox)) / DL_TWO;    // 下一试值 / next trial
    IF nNext >= nApprox THEN
        EXIT;                               // 收敛 / converged
    END_IF
    nApprox := nNext;
END_WHILE
IF nIter >= DL_ITER_MAX THEN
    bError := TRUE;                         // 未收敛（理论不可达）/ not converged, unreachable in theory
    RETURN;                                 // 返回 FALSE 且 bValid 保持 FALSE / return FALSE with bValid still FALSE
END_IF

// 段 4｜回乘比较：先拦溢出再乘 / segment 4, overflow reflection before the multiplication
IF nApprox > DL_ROOT_MAX THEN
    bValid := TRUE;                         // 判定成立：根超 65535 必非域内平方 / a root above 65535 cannot square inside the domain
    RETURN;                                 // 返回 FALSE / return FALSE
END_IF
nSquare := nApprox * nApprox;               // 根 ≤ 65535，平方 ≤ 16#FFFE_0001 不溢出 / the square stays inside the unsigned range
IF nSquare = nVal THEN
    FC_DL_IntIsPerfectSquareUdint := TRUE;  // 回乘相等即完全平方 / an equal square proves the verdict
END_IF
bValid := TRUE;                             // 判定可用 / the verdict is usable
END_FUNCTION
