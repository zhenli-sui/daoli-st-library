(*==============================================================================
 * 组件名称 : FC_DL_StatsTrimmedMeanFixed ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 定长样本的截尾均值（trimmed mean）—— 先排序，两侧各去掉 nTrimEachSide 个
 *            极值，再对剩余求算术平均。截尾均值同时抗离群点与保留分布信息，
 *            是比全样本均值更稳的过程中心估计，常用于称重剔除工位与温度场均衡判定。
 * 契约     : 返回截尾均值；nCnt < 1 时返回 0 且 bError := TRUE；nCnt > 10 钳到 10；
 *            nTrimEachSide 自动钳到 0~(nCnt−1)/2，保证至少留 1 个样本参与平均。
 *            排序用自实现插入排序，数组定长 ARRAY[1..10]（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 点数与截尾数双钳位、剩余样本数恒 ≥ 1 后
 *            才做除法 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 *            R17 定长数组 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 4/8）
 *============================================================================*)
FUNCTION FC_DL_StatsTrimmedMeanFixed : LREAL
VAR_INPUT
    aVals    : ARRAY[1..10] OF LREAL;   // 样本数组，1..10 定长 [工程单位] / sample array of fixed length [engineering unit]
    nCnt     : INT;                     // 有效样本数，1~10，越界钳位 [个] / effective sample count from one to ten, clamped [count]
    nTrimEachSide : INT;                // 每侧截去的极值个数，自动钳位 [个] / values trimmed from each side, clamped [count]
END_VAR
VAR_OUTPUT
    eErr     : UDINT;                   // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError   : BOOL;                    // 有效样本数为零为真 / TRUE when no usable sample exists
    bValid   : BOOL;                    // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_PTS_MAX : INT := 10;             // 样本定长上限 [个] / fixed sample capacity [count]
    DL_PTS_MIN : INT := 1;              // 最少样本数 [个] / minimum sample count [count]
    DL_ONE     : INT := 1;              // 数组首下标 [个] / first array index [count]
    DL_TWO     : INT := 2;              // 截尾上限式的除数 [个] / divisor of the trim cap [count]
    DL_ZERO    : INT := 0;              // 整数零哨兵 / integer zero sentinel
    DL_ZERO_L  : LREAL := 0.0;          // 实数零哨兵 [工程单位] / real zero sentinel [engineering unit]
END_VAR
VAR
    aBuf     : ARRAY[1..10] OF LREAL;   // 排序后的样本副本 [工程单位] / sorted copy of the samples [engineering unit]
    nUse     : INT;                     // 钳位后的有效点数 [个] / effective point count after clamping [count]
    nTrim    : INT;                     // 钳位后的单侧截尾数 [个] / effective trim per side [count]
    nKeep    : INT;                     // 截尾后剩余样本数 [个] / samples left after trimming [count]
    i        : INT;                     // 外层游标 [个] / outer cursor [count]
    j        : INT;                     // 内层游标 [个] / inner cursor [count]
    fKey     : LREAL;                   // 插入排序待插值 [工程单位] / key of the insertion sort [engineering unit]
    fSum     : LREAL;                   // 剩余样本累加 [工程单位] / accumulated sum of the kept samples [engineering unit]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsTrimmedMeanFixed := DL_ZERO_L;   // 缺省 0 / default zero
eErr   := 0;                                // 零码位范式 / zero-code rule
bError := FALSE;                            // 预置无故障 / preset no fault
bValid := FALSE;                            // 计算完成前不认结果 / unusable until the average ends

// 段 2｜点数钳位：上越界静默钳位，零样本按故障退出 / segment 2, clamp the count
nUse := nCnt;
IF nUse > DL_PTS_MAX THEN
    nUse := DL_PTS_MAX;
END_IF
IF nUse < DL_PTS_MIN THEN
    bError := TRUE;                         // 无样本可统计 / no sample to scan
    RETURN;
END_IF

// 段 3｜截尾数钳位：单侧最多去到只剩 1 个样本 / segment 3, clamp the trim so that one sample survives
nTrim := nTrimEachSide;
IF nTrim < DL_ZERO THEN
    nTrim := DL_ZERO;                       // 负截尾按 0 处理 / a negative trim means none
END_IF
IF nTrim > ((nUse - DL_ONE) / DL_TWO) THEN
    nTrim := (nUse - DL_ONE) / DL_TWO;      // 单侧上限，保证剩余至少 1 个 / the cap that keeps one sample alive
END_IF
nKeep := nUse - (DL_TWO * nTrim);           // 剩余样本数，恒 ≥ 1 / the kept count, always at least one

// 段 4｜拷贝并插入排序：升序，极值集中在两端以便截尾 / segment 4, copy and insertion sort in ascending order
FOR i := DL_ONE TO nUse DO
    aBuf[i] := aVals[i];                    // 拷贝，保持入参只读 / copy so the input stays read only
END_FOR
FOR i := DL_TWO TO nUse DO
    fKey := aBuf[i];
    j    := i - DL_ONE;
    WHILE (j >= DL_ONE) AND (aBuf[j] > fKey) DO
        aBuf[j + DL_ONE] := aBuf[j];        // 后移空位 / shift right to open a slot
        j := j - DL_ONE;
    END_WHILE
    aBuf[j + DL_ONE] := fKey;               // 落位 / drop the key in place
END_FOR

// 段 5｜截尾求和：下标 (1+nTrim) ~ (nUse−nTrim)，不会越界 / segment 5, sum the kept window
fSum := DL_ZERO_L;
FOR i := (DL_ONE + nTrim) TO (nUse - nTrim) DO
    fSum := fSum + aBuf[i];
END_FOR

// 段 6｜出口：剩余数已证 ≥ 1，除法安全 / segment 6, the divisor is proven to be at least one
FC_DL_StatsTrimmedMeanFixed := fSum / INT_TO_LREAL(nKeep);   // 截尾均值 / the trimmed mean
bValid := TRUE;                                              // 结果可用 / the result is usable
END_FUNCTION
