(*==============================================================================
 * 组件名称 : FC_DL_StatsEntropyCalc ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 香农熵 H = −Σ p·log2(p) [bit]，供直方图分布集中度、缺陷类别混杂度、
 *            多路料仓配比均匀度评估。概率先求和再归一化（q = p / Σp），故入参不要求
 *            严格和为 1（计数直方图可直接喂入）。
 * 契约     : 1 ≤ nCnt ≤ 8、各 p ≥ 0 且有限、Σp > 1.0E-12 → 返回 H ≥ 0、bValid := TRUE；
 *            nCnt 越界、任一 p 为负或非有限、Σp ≤ 1.0E-12（全零/近零，熵无定义）→
 *            返回 0、bError := TRUE、bValid := FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），仅用标准库 LN；log2(p) 以 LN(p)/LN(2) 实现
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（Σp 域闸、LN(2) 为常量）+ 跳过 log(0)
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 *            R17 数组显式定长 ARRAY[1..8]，nCnt 已域闸，无 VLA
 * 遗留假设 : 概率阈值 1.0E-12 以下的项整体跳过（p·log2 p → 0 的极限口径，也避免 LN(0)）；
 *            归一化后才取对数，故入参是计数或百分比皆可；nCnt 之外的数组槽位不参与运算；
 *            H 的量纲为 bit（底数 2），理论上界为 log2(8) = 3.0 bit。
 * 修订历史 : 2026-11-24 R79-B 首版（统计族 2/2）
 *============================================================================*)
FUNCTION FC_DL_StatsEntropyCalc : LREAL
VAR_INPUT
    aProb : ARRAY[1..8] OF LREAL; // 概率或计数数组，元素须 ≥ 0，仅前 nCnt 项参与 [无量纲] / the probability or count vector, only the first nCnt entries are used
    nCnt  : INT := 0;             // 有效元素个数，1..8 [个] / the number of valid entries
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 个数越界、元素非法或总和近零时为真 / TRUE on a bad count, an illegal entry or a near zero sum
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO : LREAL := 0.0;                // 实数零哨兵 [无量纲] / the real zero sentinel
    DL_EPS  : LREAL := 1.0E-12;            // 可忽略概率 / 近零总和阈值 [无量纲] / the negligible probability and near zero sum threshold
    DL_LN2  : LREAL := 0.6931471805599453; // ln2，换底用 [无量纲] / the natural logarithm of two used for the base change
    DL_CNT1 : INT   := 1;                  // 元素个数下界 [个] / the lower entry count bound
    DL_CNT8 : INT   := 8;                  // 元素个数上界 [个] / the upper entry count bound
    DL_ONE  : INT   := 1;                  // 循环起点下标 [无量纲] / the loop start index
    DL_STEP : INT   := 1;                  // 下标步长 [无量纲] / the index step
END_VAR
VAR
    nI    : INT;   // 数组下标 1..nCnt [无量纲] / the array index
    fSum  : LREAL; // 概率总和 Σp [无量纲] / the sum of the probabilities
    fQ    : LREAL; // 归一化概率 p / Σp [无量纲] / the normalised probability
    fH    : LREAL; // 熵累加量 [bit] / the entropy accumulator
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsEntropyCalc := DL_ZERO;  // 缺省零 / default zero
eErr   := 0;                        // 零码位范式 / zero-code rule
bError := FALSE;                    // 预置无故障 / preset no fault
bValid := FALSE;                    // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜元素个数域闸：数组定长 1..8，越界下标不可触 / segment 2, the entry count gate
IF (nCnt < DL_CNT1) OR (nCnt > DL_CNT8) THEN
    bError := TRUE;                 // 个数越界 / the count is out of range
    RETURN;                         // 返回 0 / return the preset zero
END_IF

// 段 3｜求和与元素合法性：负概率无意义，非有限入参直接拦 / segment 3, the sum and the entry checks
fSum := DL_ZERO;                    // 总和清零 / clear the sum
FOR nI := DL_ONE TO nCnt DO         // 只遍历有效槽位 / loop over the valid entries only
    IF (aProb[nI] <> aProb[nI]) THEN
        bError := TRUE;             // NaN 元素 / a NaN entry
        RETURN;                     // 返回 0 / return the preset zero
    END_IF
    IF ((aProb[nI] - aProb[nI]) <> DL_ZERO) OR (aProb[nI] < DL_ZERO) THEN
        bError := TRUE;             // Inf 元素或负概率 / an infinite entry or a negative probability
        RETURN;                     // 返回 0 / return the preset zero
    END_IF
    fSum := fSum + aProb[nI];       // 累加 / accumulate
END_FOR

// 段 4｜总和域闸：全零或近零时熵无定义，且归一化会除零 / segment 4, the sum gate
IF fSum <= DL_EPS THEN
    bError := TRUE;                 // 总和近零 / the sum is negligible
    RETURN;                         // 返回 0 / return the preset zero
END_IF
IF (fSum - fSum) <> DL_ZERO THEN    // 溢出成 Inf 的兜底 / the overflow to infinity guard
    bError := TRUE;                 // 总和非有限 / the sum is not finite
    RETURN;                         // 返回 0 / return the preset zero
END_IF

// 段 5｜熵求值：H = −Σ q·log2(q)，q = p / Σp，log2 用 LN(q)/LN(2) / segment 5, the entropy
fH := DL_ZERO;                      // 熵清零 / clear the entropy
FOR nI := DL_ONE TO nCnt DO         // 第二遍：归一化后逐项累加 / second pass over the normalised terms
    IF aProb[nI] > DL_EPS THEN      // 跳过可忽略项，等价 ln(0) 极限且防 log(0) / skip negligible terms to avoid the logarithm of zero
        fQ := aProb[nI] / fSum;     // 归一化（fSum 已证 > 1E-12）/ normalise, the sum is proven positive
        fH := fH - (fQ * (LN(fQ) / DL_LN2));  // 累减 q·log2 q [bit] / subtract the term
    END_IF
END_FOR

// 段 6｜出口 / segment 6, the exit
FC_DL_StatsEntropyCalc := fH;       // 回写熵 [bit] / publish the entropy
bValid := TRUE;                     // 返回值可用 / the return value is usable
END_FUNCTION
