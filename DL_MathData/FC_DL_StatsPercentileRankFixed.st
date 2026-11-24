(*==============================================================================
 * 组件名称 : FC_DL_StatsPercentileRankFixed ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 定长样本的分位数（最近秩法 nearest-rank）—— 先升序排序，
 *            rank = ceil(pct/100 × n) 并钳到 [1, n]，返回第 rank 个样本。
 *            最近秩法不插值，返回的一定是真实测得的样本值，HMI 展示与判定门槛
 *            不会因插值出现「从未测到的数」。用于节拍 P95、温度 P99 等分位统计。
 * 契约     : 返回分位数（必为样本之一）；nCnt < 1 时返回 0 且 bError := TRUE；
 *            nCnt > 10 钳到 10；fPct 越界钳到 [0,100]（钳位不报错，属正常输入整形）。
 *            排序用自实现插入排序，数组定长 ARRAY[1..10]（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: CEIL
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 点数与百分位双钳位、秩再钳到 [1,n]，
 *            下标恒合法 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 标准转换 R11 全声明行分号 R15 标识符零保留字冲突
 *            R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 最近秩法在 pct = 0 时 rank = 0 会钳到 1（返回最小值），与教科书「P0」口径一致。
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 5/8）
 *============================================================================*)
FUNCTION FC_DL_StatsPercentileRankFixed : LREAL
VAR_INPUT
    aVals   : ARRAY[1..10] OF LREAL;    // 样本数组，1..10 定长 [工程单位] / sample array of fixed length [engineering unit]
    nCnt    : INT;                      // 有效样本数，1~10，越界钳位 [个] / effective sample count from one to ten, clamped [count]
    fPct    : LREAL;                    // 百分位 0~100，越界钳位 [%] / percentile from zero to one hundred, clamped [%]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;                    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;                     // 有效样本数为零为真 / TRUE when no usable sample exists
    bValid  : BOOL;                     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_PTS_MAX : INT := 10;             // 样本定长上限 [个] / fixed sample capacity [count]
    DL_PTS_MIN : INT := 1;              // 最少样本数 [个] / minimum sample count [count]
    DL_ONE     : INT := 1;              // 数组首下标与秩下界 [个] / first index and the lower rank bound [count]
    DL_TWO     : INT := 2;              // 插入排序的起始下标 [个] / starting index of the insertion sort [count]
    DL_PCT_MIN : LREAL := 0.0;          // 百分位下界 [%] / lower percentile bound [%]
    DL_PCT_MAX : LREAL := 100.0;        // 百分位上界 [%] / upper percentile bound [%]
    DL_PCT_DIV : LREAL := 100.0;        // 百分制换算除数 [%] / percentile scale divisor [%]
    DL_ZERO_L  : LREAL := 0.0;          // 实数零哨兵 [工程单位] / real zero sentinel [engineering unit]
END_VAR
VAR
    aBuf    : ARRAY[1..10] OF LREAL;    // 排序后的样本副本 [工程单位] / sorted copy of the samples [engineering unit]
    nUse    : INT;                      // 钳位后的有效点数 [个] / effective point count after clamping [count]
    nRank   : INT;                      // 最近秩 1~nUse [个] / the nearest rank from one to the count [count]
    i       : INT;                      // 外层游标 [个] / outer cursor [count]
    j       : INT;                      // 内层游标 [个] / inner cursor [count]
    fKey    : LREAL;                    // 插入排序待插值 [工程单位] / key of the insertion sort [engineering unit]
    fPctUse : LREAL;                    // 钳位后的百分位 [%] / effective percentile after clamping [%]
    fRank   : LREAL;                    // 秩的实数中间量 [个] / the rank as a real number [count]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsPercentileRankFixed := DL_ZERO_L;    // 缺省 0 / default zero
eErr    := 0;                                   // 零码位范式 / zero-code rule
bError  := FALSE;                               // 预置无故障 / preset no fault
bValid  := FALSE;                               // 计算完成前不认结果 / unusable until the rank walk ends

// 段 2｜点数钳位与百分位整形 / segment 2, clamp the count and normalise the percentile
nUse := nCnt;
IF nUse > DL_PTS_MAX THEN
    nUse := DL_PTS_MAX;
END_IF
IF nUse < DL_PTS_MIN THEN
    bError := TRUE;                             // 无样本可统计 / no sample to scan
    RETURN;
END_IF
fPctUse := fPct;
IF (fPctUse <> fPctUse) OR (fPctUse < DL_PCT_MIN) THEN
    fPctUse := DL_PCT_MIN;                      // 非数或过小按 0 处理 / a not a number or an undershoot becomes zero
ELSIF fPctUse > DL_PCT_MAX THEN
    fPctUse := DL_PCT_MAX;                      // 过大按 100 处理 / an overshoot becomes one hundred
END_IF

// 段 3｜拷贝并插入排序：升序，秩直接映射到下标 / segment 3, copy and insertion sort
FOR i := DL_ONE TO nUse DO
    aBuf[i] := aVals[i];                        // 拷贝，保持入参只读 / copy so the input stays read only
END_FOR
FOR i := DL_TWO TO nUse DO
    fKey := aBuf[i];
    j    := i - DL_ONE;
    WHILE (j >= DL_ONE) AND (aBuf[j] > fKey) DO
        aBuf[j + DL_ONE] := aBuf[j];            // 后移空位 / shift right to open a slot
        j := j - DL_ONE;
    END_WHILE
    aBuf[j + DL_ONE] := fKey;                   // 落位 / drop the key in place
END_FOR

// 段 4｜最近秩：ceil(pct/100 × n)，再钳到 [1, n] / segment 4, the nearest rank
fRank := CEIL((fPctUse / DL_PCT_DIV) * INT_TO_LREAL(nUse));    // 向上取整，整数域内无插值误差 / round up, no interpolation error
nRank := LREAL_TO_DINT(fRank);                                 // 转整数秩 / convert to an integer rank
IF nRank < DL_ONE THEN
    nRank := DL_ONE;                                           // 秩下界钳位 / clamp the lower rank bound
ELSIF nRank > nUse THEN
    nRank := nUse;                                             // 秩上界钳位 / clamp the upper rank bound
END_IF

// 段 5｜出口：秩已证落在 [1, nUse]，下标安全 / segment 5, the rank is proven legal
FC_DL_StatsPercentileRankFixed := aBuf[nRank];      // 该分位的实测样本值 / the measured sample at that percentile
bValid := TRUE;                                     // 结果可用 / the result is usable
END_FUNCTION
