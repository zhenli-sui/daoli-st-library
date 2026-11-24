(*==============================================================================
 * 组件名称 : FC_DL_StatsRunLengthMax ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 定长样本的最长「连续同值游程」（run length）长度。相邻两样本差值
 *            不超过 fTol 即视为同值，游程在容差内延续。用于：称重稳定判定、
 *            光电信号连续遮挡时长、清洗液浓度平台段长度、批次工艺稳态持续时间。
 * 契约     : 返回最长游程长度（1~nCnt）；nCnt < 1 时返回 0 且 bError := TRUE；
 *            nCnt > 10 钳到 10；fTol 取绝对值（负容差按同值正容差处理），
 *            非有限 fTol 返回 0 且 bError := TRUE。数组定长 ARRAY[1..10]（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 点数先钳位后扫描、容差常量化、
 *            浮点差值比较走 ABS 容差不用等号、NaN 自反判据 ｜ R5 双语注释
 *            R6 N/A（无状态机）R7 N/A（无定时器/沿实例）R10 无类型转换
 *            R11 全声明行分号 R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 8/8）
 *============================================================================*)
FUNCTION FC_DL_StatsRunLengthMax : DINT
VAR_INPUT
    aVals   : ARRAY[1..10] OF LREAL;    // 样本数组，1..10 定长 [工程单位] / sample array of fixed length [engineering unit]
    nCnt    : INT;                      // 有效样本数，1~10，越界钳位 [个] / effective sample count from one to ten, clamped [count]
    fTol    : LREAL;                    // 同值容差，取绝对值使用 [工程单位] / equality tolerance, used as a magnitude [engineering unit]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;                    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;                     // 无样本或容差非有限为真 / TRUE when no sample exists or the tolerance is not finite
    bValid  : BOOL;                     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_PTS_MAX : INT := 10;             // 样本定长上限 [个] / fixed sample capacity [count]
    DL_PTS_MIN : INT := 1;              // 最少样本数 [个] / minimum sample count [count]
    DL_ONE     : INT := 1;              // 数组首下标与最短游程 [个] / first index and the shortest possible run [count]
    DL_ZERO    : INT := 0;              // 整数零哨兵 / integer zero sentinel
    DL_FIN_LIM : LREAL := 1.0E308;      // 有限性上界 [工程单位] / finiteness ceiling [engineering unit]
END_VAR
VAR
    nUse    : INT;                      // 钳位后的有效点数 [个] / effective point count after clamping [count]
    nRun    : INT;                      // 当前游程长度 [个] / the run being measured [count]
    nBest   : INT;                      // 历史最长游程 [个] / the longest run seen so far [count]
    i       : INT;                      // 遍历游标，从第 2 点起 [个] / loop cursor starting at the second point [count]
    fTolUse : LREAL;                    // 生效容差 [工程单位] / effective tolerance [engineering unit]
    fDiff   : LREAL;                    // 相邻样本差值 [工程单位] / difference of neighbouring samples [engineering unit]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsRunLengthMax := DL_ZERO;     // 缺省 0 / default zero
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 计算完成前不认结果 / unusable until the scan ends

// 段 2｜点数钳位与容差整形 / segment 2, clamp the count and normalise the tolerance
nUse := nCnt;
IF nUse > DL_PTS_MAX THEN
    nUse := DL_PTS_MAX;                 // 钳到定长上限 / clamp to the fixed capacity
END_IF
IF nUse < DL_PTS_MIN THEN
    bError := TRUE;                     // 无样本可扫描 / no sample to scan
    RETURN;
END_IF
IF (fTol <> fTol) OR (ABS(fTol) > DL_FIN_LIM) THEN
    bError := TRUE;                     // 容差非数或无穷 / the tolerance is not finite
    RETURN;
END_IF
fTolUse := ABS(fTol);                   // 负容差按同值正容差处理 / a negative tolerance folds to its magnitude

// 段 3｜首点起算：单个样本本身构成游程 1 / segment 3, the first sample seeds a run of one
nRun  := DL_ONE;
nBest := DL_ONE;

// 段 4｜单趟扫描：差值在容差内则游程加一，否则重新起算 / segment 4, one pass over the neighbours
FOR i := (DL_ONE + DL_ONE) TO nUse DO
    fDiff := ABS(aVals[i] - aVals[i - DL_ONE]);     // 相邻差值 / neighbouring difference
    IF fDiff <= fTolUse THEN
        nRun := nRun + DL_ONE;                      // 游程延续 / the run continues
        IF nRun > nBest THEN
            nBest := nRun;                          // 刷新最长 / refresh the record
        END_IF
    ELSE
        nRun := DL_ONE;                             // 新值起算新游程 / a new value starts a new run
    END_IF
END_FOR

// 段 5｜出口：nBest 已证落在 1..nUse / segment 5, the record is proven to be inside the range
FC_DL_StatsRunLengthMax := nBest;       // 最长游程 / the longest run
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
