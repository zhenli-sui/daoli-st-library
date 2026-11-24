(*==============================================================================
 * 组件名称 : FC_DL_IntFloorLog2Udint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : UDINT 下取整二进制对数 ⌊log2 nVal⌋。供位宽探测、二叉树层数、分频档位、
 *            哈希桶数 2 的幂归整使用。纯移位实现（逐次除 2 计数），禁浮点 LN，无精度问题。
 * 契约     : nVal ≥ 1 → 返回 0..31、bValid := TRUE；nVal = 0 → 返回 −1 且 bError := TRUE
 *            （log 在 0 处无定义，−1 为哨兵值而非合法结果，调用方必须查 bError）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（被除数恒 2，无需域闸）+ 无浮点
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 返回值 −1 是故障哨兵，与「0 哨兵」范式不同：log2 的合法值含 0（nVal = 1），
 *            故不能用 0 表达故障；循环天然终止（nW 单调减半，最多 31 步），不设守卫。
 * 修订历史 : 2026-11-24 R79-B 首版（整数数论族补位）
 *============================================================================*)
FUNCTION FC_DL_IntFloorLog2Udint : DINT
VAR_INPUT
    nVal : UDINT := 0; // 待求对数的正整数 [无量纲] / the positive value whose binary logarithm is wanted
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 入参为零时为真 / TRUE when the argument is zero
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO : UDINT := 0; // 无符号零哨兵 / unsigned zero sentinel
    DL_ONE  : UDINT := 1; // 无符号一哨兵，循环终止阈值 / unsigned one, the loop exit threshold
    DL_TWO  : UDINT := 2; // 无符号二哨兵，移位基数 / unsigned two, the halving base
    DL_SENT : DINT  := -1; // 零入参故障哨兵 [无量纲] / the fault sentinel returned for a zero argument
    DL_ONEI : DINT  := 1;  // 整型一，计数步长 [次] / integer one, the counting step
    DL_NONE : DINT  := 0;  // 整型零，计数初值 [次] / integer zero, the counting start value
END_VAR
VAR
    nW   : UDINT; // 逐次减半的工作副本 [无量纲] / the working copy halved each pass
    nRes : DINT;  // 已减半次数，即 ⌊log2 nVal⌋ [次] / the number of halvings, that is the floor logarithm
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntFloorLog2Udint := DL_NONE;  // 缺省零 / default zero
eErr   := 0;                         // 零码位范式 / zero-code rule
bError := FALSE;                     // 预置无故障 / preset no fault
bValid := FALSE;                     // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜零入参域闸：log2(0) 无定义，返回 −1 哨兵 / segment 2, the zero argument gate
IF nVal = DL_ZERO THEN
    FC_DL_IntFloorLog2Udint := DL_SENT;  // 故障哨兵 −1 / the fault sentinel minus one
    bError := TRUE;                      // 故障级 / fault level
    RETURN;                              // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 3｜移位计数：nW 单调减半，nVal = 1 时零步即得 0 / segment 3, the halving count
nW   := nVal;                        // 工作副本 / the working copy
nRes := DL_NONE;                     // 计数清零 / clear the counter
WHILE nW > DL_ONE DO                 // 除零不可达：被除数恒为 2 / the divisor is the constant two
    nW   := nW / DL_TWO;             // 减半 / halve
    nRes := nRes + DL_ONEI;          // 计一次 / count one halving
END_WHILE

// 段 4｜出口 / segment 4, the exit
FC_DL_IntFloorLog2Udint := nRes;     // 回写 ⌊log2 nVal⌋ / publish the floor logarithm
bValid := TRUE;                      // 返回值可用 / the return value is usable
END_FUNCTION
