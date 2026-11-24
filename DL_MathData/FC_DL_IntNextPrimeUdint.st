(*==============================================================================
 * 组件名称 : FC_DL_IntNextPrimeUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 求「≥ nVal + 1 的最小素数」（严格大于入参）。供哈希桶数取素数、抖动模数
 *            选取、伪随机种子上限归整使用。试除条件写作 nD <= nCand / nD，禁 i*i 防溢出。
 * 契约     : 找到即返回该素数、bValid := TRUE；nVal ≥ 16#FFFF_FFF0（无足够向上空间）
 *            或 2000 步内未找到（防死循环）或推进中将越过 UDINT 上界 → 返回 0、
 *            bError := TRUE、bValid := FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现：试除内联），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（nD ≥ 2）+ 步数上限 + 加法溢出兜底
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : nVal = 0 或 1 时起点取 2（2 是 ≥ 2 的最小素数）；候选逐 1 递增（不跳偶），
 *            保证 2000 步覆盖 2000 个连续整数，远大于 2³² 内的最大素数间隙（≈336），
 *            故「步数命中」只可能发生在接近上界处，与上界兜底互为双保险。
 * 修订历史 : 2026-11-24 R79-B 首版（整数数论族补位）
 *============================================================================*)
FUNCTION FC_DL_IntNextPrimeUdint : UDINT
VAR_INPUT
    nVal : UDINT := 0; // 参考值，本件返回严格大于它的最小素数 [无量纲] / the reference value, the result is strictly above it
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 无解或搜索步数越界时为真 / TRUE when no answer exists or the search budget is exhausted
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO  : UDINT := 0;            // 无符号零哨兵 / unsigned zero sentinel
    DL_ONE   : UDINT := 1;            // 无符号一哨兵 / unsigned one sentinel
    DL_TWO   : UDINT := 2;            // 无符号二哨兵，最小素数 / unsigned two, the smallest prime
    DL_THREE : UDINT := 3;            // 无符号三哨兵，试除起点 / unsigned three, the trial division start
    DL_NEAR  : UDINT := 16#FFFF_FFF0; // 上界保护带起点，超过即判无解 / the guard band start near the ceiling
    DL_GUARD : UDINT := 16#FFFF_FFFE; // 推进溢出兜底线 / the increment overflow guard line
    DL_STEP  : DINT  := 2000;         // 候选搜索步数预算 [步] / the candidate search budget
    DL_STEP0 : DINT  := 0;            // 步数计数初值 [步] / the step counter start value
    DL_STEP1 : DINT  := 1;            // 步数计数步长 [步] / the step counter increment
END_VAR
VAR
    nCand  : UDINT; // 当前候选整数 [无量纲] / the current candidate
    nD     : UDINT; // 试除因子，奇数 3, 5, 7, … [无量纲] / the odd trial divisor
    nStep  : DINT;  // 已消耗的候选步数 [步] / the consumed candidate steps
    bPrime : BOOL;  // 当前候选的素性结论 / the primality verdict of the current candidate
    bFound : BOOL;  // 找到标志 / the found flag
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntNextPrimeUdint := DL_ZERO;  // 缺省零哨兵 / default zero sentinel
eErr    := 0;                        // 零码位范式 / zero-code rule
bError  := FALSE;                    // 预置无故障 / preset no fault
bValid  := FALSE;                    // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜上界域闸：无足够向上空间即判无解 / segment 2, the ceiling gate
IF nVal >= DL_NEAR THEN
    bError := TRUE;                  // 上界保护带内不搜索 / no search inside the guard band
    RETURN;                          // 返回 0 / return the preset zero
END_IF

// 段 3｜起点：严格大于入参，且不低于 2 / segment 3, the start candidate
nCand  := nVal + DL_ONE;             // 严格大于入参 / strictly above the argument
IF nCand < DL_TWO THEN nCand := DL_TWO; END_IF  // 0/1 的最小数答案是 2 / two is the answer for zero and one
nStep  := DL_STEP0;                  // 步数清零 / clear the step counter
bFound := FALSE;                     // 未找到 / nothing found yet

// 段 4｜候选搜索：逐 1 递增，超出预算即停（防死循环）/ segment 4, the candidate search
WHILE (NOT bFound) AND (nStep < DL_STEP) DO
    nStep  := nStep + DL_STEP1;      // 消耗一步 / consume one step
    bPrime := TRUE;                  // 先假定素数 / assume prime first
    IF (nCand > DL_TWO) AND ((nCand MOD DL_TWO) = DL_ZERO) THEN bPrime := FALSE; END_IF  // 大于 2 的偶数必合数 / every even number above two is composite
    IF bPrime AND (nCand > DL_THREE) THEN
        nD := DL_THREE;              // 试除起点 3 / start from three
        WHILE nD <= (nCand / nD) DO  // 等价于 nD² ≤ nCand 但永不溢出 / equivalent to the square test without overflow
            IF (nCand MOD nD) = DL_ZERO THEN
                bPrime := FALSE;     // 找到因子即合数 / a divisor means composite
                EXIT;                // 跳出试除循环 / leave the trial division loop
            END_IF
            nD := nD + DL_TWO;       // 只试奇数 / odd divisors only
        END_WHILE
    END_IF
    IF bPrime THEN
        bFound := TRUE;              // 候选即答案 / the candidate is the answer
    ELSIF nCand >= DL_GUARD THEN
        bError := TRUE;              // 再推进将越过上界 / another step would overflow the ceiling
        bFound := TRUE;              // 以故障方式结束搜索 / end the search as a fault
        nCand  := DL_ZERO;           // 结果置零哨兵 / force the zero sentinel
    ELSE
        nCand := nCand + DL_ONE;     // 推进到下一候选 / advance to the next candidate
    END_IF
END_WHILE

// 段 5｜出口：未找到（预算耗尽）判故障，找到则回写 / segment 5, the exit
IF (NOT bFound) OR bError THEN
    bError := TRUE;                  // 预算耗尽或无解 / the budget ran out or no answer exists
    RETURN;                          // 返回 0 哨兵 / return the zero sentinel
END_IF
FC_DL_IntNextPrimeUdint := nCand;    // 回写素数 / publish the prime
bValid := TRUE;                      // 返回值可用 / the return value is usable
END_FUNCTION
