(*==============================================================================
 * 组件名称 : FC_DL_StatsMadFixed ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 定长样本的中位数绝对偏差 MAD = median(|xi − median(x)|)。
 *            MAD 对离群点不敏感，是比标准差更稳的离散度量 —— 传感器毛刺、
 *            单点跳变不会把 MAD 拉偏，适合做在线异常判据。排序用自实现插入排序，
 *            不调用未经验证的排序件（R16）。
 * 契约     : 返回 MAD（≥ 0）；nCnt < 1 时返回 0 且 bError := TRUE；nCnt > 10 钳到 10。
 *            偶数样本的中位数取中间两值的算术平均。数组定长 ARRAY[1..10]（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 点数先钳位、局部数组下标恒在 1..10、
 *            偶数中位数除数为常量 2 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 无类型转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 非有限样本不剔除（MAD 的稳健性以有限样本为前提）；含 NaN 时比较全为假，
 *            排序不崩但 MAD 结果无意义 —— 调用方须先做非有限过滤。
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 3/8）
 *============================================================================*)
FUNCTION FC_DL_StatsMadFixed : LREAL
VAR_INPUT
    aVals   : ARRAY[1..10] OF LREAL;    // 样本数组，1..10 定长 [工程单位] / sample array of fixed length [engineering unit]
    nCnt    : INT;                      // 有效样本数，1~10，越界钳位 [个] / effective sample count from one to ten, clamped [count]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;                    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;                     // 有效样本数为零为真 / TRUE when no usable sample exists
    bValid  : BOOL;                     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_PTS_MAX : INT := 10;             // 样本定长上限 [个] / fixed sample capacity [count]
    DL_PTS_MIN : INT := 1;              // 最少样本数 [个] / minimum sample count [count]
    DL_ONE     : INT := 1;              // 数组首下标 [个] / first array index [count]
    DL_TWO     : INT := 2;              // 偶数中位数的除数 [个] / divisor of the even median [count]
    DL_TWO_L   : LREAL := 2.0;          // 实数二，偶数中位数平均用 [无量纲] / real two used by the even median
    DL_ZERO_L  : LREAL := 0.0;          // 实数零哨兵 [工程单位] / real zero sentinel [engineering unit]
END_VAR
VAR
    aBuf    : ARRAY[1..10] OF LREAL;    // 排序用样本副本 [工程单位] / sorted copy of the samples [engineering unit]
    aDev    : ARRAY[1..10] OF LREAL;    // 绝对偏差数组 [工程单位] / absolute deviation array [engineering unit]
    nUse    : INT;                      // 钳位后的有效点数 [个] / effective point count after clamping [count]
    nMid    : INT;                      // 中位位置 [个] / the middle position [count]
    i       : INT;                      // 外层游标 [个] / outer cursor [count]
    j       : INT;                      // 内层游标 [个] / inner cursor [count]
    fKey    : LREAL;                    // 插入排序的待插值 [工程单位] / key of the insertion sort [engineering unit]
    fMed    : LREAL;                    // 样本中位数 [工程单位] / median of the samples [engineering unit]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsMadFixed := DL_ZERO_L;       // 缺省 0 / default zero
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 计算完成前不认结果 / unusable until the median walk ends

// 段 2｜点数钳位：上越界静默钳位，零样本按故障退出 / segment 2, clamp the count
nUse := nCnt;
IF nUse > DL_PTS_MAX THEN
    nUse := DL_PTS_MAX;
END_IF
IF nUse < DL_PTS_MIN THEN
    bError := TRUE;                     // 无样本可统计 / no sample to scan
    RETURN;
END_IF

// 段 3｜拷贝并插入排序：小规模（≤10）下插入排序最稳，无递归无额外内存 / segment 3, copy and insertion sort
FOR i := DL_ONE TO nUse DO
    aBuf[i] := aVals[i];                // 拷贝，保持入参只读 / copy so the input stays read only
END_FOR
FOR i := DL_TWO TO nUse DO
    fKey := aBuf[i];                    // 待插值 / the key to insert
    j    := i - DL_ONE;
    WHILE (j >= DL_ONE) AND (aBuf[j] > fKey) DO
        aBuf[j + DL_ONE] := aBuf[j];    // 后移空位 / shift right to open a slot
        j := j - DL_ONE;
    END_WHILE
    aBuf[j + DL_ONE] := fKey;           // 落位 / drop the key in place
END_FOR

// 段 4｜样本中位数：奇数取正中，偶数取中间两值平均 / segment 4, the median of the samples
IF (nUse MOD DL_TWO) = DL_ONE THEN
    nMid := (nUse + DL_ONE) / DL_TWO;                   // 正中位置 / the exact middle
    fMed := aBuf[nMid];
ELSE
    nMid := nUse / DL_TWO;                              // 中间左侧位置 / the left middle
    fMed := (aBuf[nMid] + aBuf[nMid + DL_ONE]) / DL_TWO_L;
END_IF

// 段 5｜绝对偏差数组：|xi − 中位数| / segment 5, the absolute deviation array
FOR i := DL_ONE TO nUse DO
    aDev[i] := ABS(aBuf[i] - fMed);
END_FOR

// 段 6｜偏差再排序，其中位数即 MAD / segment 6, sort the deviations and take their median
FOR i := DL_TWO TO nUse DO
    fKey := aDev[i];
    j    := i - DL_ONE;
    WHILE (j >= DL_ONE) AND (aDev[j] > fKey) DO
        aDev[j + DL_ONE] := aDev[j];
        j := j - DL_ONE;
    END_WHILE
    aDev[j + DL_ONE] := fKey;
END_FOR
IF (nUse MOD DL_TWO) = DL_ONE THEN
    nMid := (nUse + DL_ONE) / DL_TWO;
    FC_DL_StatsMadFixed := aDev[nMid];                  // 奇数取正中 / odd counts take the exact middle
ELSE
    nMid := nUse / DL_TWO;
    FC_DL_StatsMadFixed := (aDev[nMid] + aDev[nMid + DL_ONE]) / DL_TWO_L;   // 偶数取中间两值平均 / even counts average the middle pair
END_IF
bValid := TRUE;                                         // 结果可用 / the result is usable
END_FUNCTION
