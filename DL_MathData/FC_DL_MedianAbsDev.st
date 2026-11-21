(*==============================================================================
 * 组件名称 (Component)  : FC_DL_MedianAbsDev
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅用 FOR 循环、赋值与 ABS，无任何厂商内建函数（连排序库都不用）
 * 功能描述 (Function)   : 中位绝对偏差 MAD（Median Absolute Deviation），鲁棒离散度指标。
 *                           步骤：① 取前 nCount 个样本复制到本地缓冲（不改调用方数组）；
 *                                 ② 插入排序求中位数 fMedian；
 *                                 ③ 各样本减中位数取绝对值，再次插入排序求中位数 fMad。
 *                         返回 fMad。MAD 对离群点不敏感（崩溃点 50%），在传感器脏数据、
 *                         偶发尖峰场景下比标准差可靠：一个 10 倍离群点能把标准差抬高数倍，
 *                         而 MAD 几乎不变。
 *                         小样本策略：nCount < 3 → 无稳健意义，bValid=FALSE、返回 0；
 *                         nCount > 16 → 钳到 16（缓冲上界），bClamped=TRUE，结果按前 16 个算。
 *                         偶数样本的中位数取中间两数的算术平均（IEC 惯例，写死在此）。
 * 无状态边界 (Stateless): **本 FC 零内部状态**——本地缓冲 afWork / afDev 均为 VAR 临时量，
 *                         每次调用重新填装；IEC 61131-3 的 FC 本就不允许持有静态变量，本件遵守。
 *                         因此同一组样本重复调用结果完全一致，可重入、可并发、可放在任意 POU。
 *                         调用方若需"跨窗统计"，请自行保存样本数组，而不是期望 FC 记住上次数据。
 * 接口     (Interface)  : 入 afSample 样本数组（VAR_IN_OUT，本件只读，按 nCount 截取）、
 *                         nCount 有效样本数（1..16）；出 fMedian 中位数、fMad 中位绝对偏差、
 *                         bValid 结果有效（nCount >= 3）、bClamped 样本数被钳到 16。
 * 边界     (Boundary)   : ① 样本数下限：nCount < 3 无稳健离散意义 → bValid=FALSE、fMedian/fMad 置 0
 *                         （**0 不是"无离散"的断言**，调用方须查 bValid）；
 *                         ② 样本数上限：nCount > 16 → 钳到 16 并置 bClamped（绝不越 ARRAY 上界）；
 *                         ③ nCount <= 0 → bValid=FALSE、返回 0（防 nCount−1 为负导致的循环越界）；
 *                         ④ 非有限样本（NaN/Inf）会让排序结果失去意义：本件**不静默吞掉**，
 *                         检出即 bNonFin=TRUE、bValid=FALSE、返回 0（宁可不报，不可乱报）；
 *                         ⑤ 插入排序 O(n²)，n<=16 时最坏 256 次比较/两轮，代价可接受且无递归。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 来源标签 (Source Tag) : T2-1 ◐（MAD 为公开经典鲁棒统计量，Hampel 1974；插入排序为教科书算法；
 *                         ST 实现为道莅自研，零代码行复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。异常出口为 BOOL（bValid / bClamped / bNonFin）；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组边界钳位 + 循环上界由钳位量派生 + 非有限闸
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 N/A（无状态机）
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 3 · 序号 15）
 *==============================================================================*)
FUNCTION FC_DL_MedianAbsDev : REAL
VAR_IN_OUT
    afSample : ARRAY[0..15] OF REAL;    // 样本数组（本件只读，按 nCount 截取） [工程单位] / Sample array, read-only here, sliced by nCount
END_VAR
VAR_INPUT
    nCount : INT := 3;                  // 有效样本数，域 1..16（>16 被钳位） [个] / Valid sample count, 1..16, clamped above
END_VAR
VAR_OUTPUT
    fMedian  : REAL;                    // 样本中位数 [工程单位] / Sample median [engineering unit]
    bValid   : BOOL;                    // 结果有效（3 <= 有效样本数 <= 16） [-] / Result valid
    bClamped : BOOL;                    // 样本数被钳到 16 [-] / Sample count clamped to 16
    bNonFin  : BOOL;                    // 样本中存在 NaN/Inf，结果不可信 [-] / A non-finite sample was found
END_VAR
VAR
    afWork : ARRAY[0..15] OF REAL;      // 工作副本（排序用，不动调用方数组） [工程单位] / Working copy for sorting
    afDev  : ARRAY[0..15] OF REAL;      // 绝对偏差数组（排序用） [工程单位] / Absolute-deviation array for sorting
    nUse   : INT;                       // 实际参与计算的样本数（钳位后） [个] / Actual sample count after clamping
    i      : INT;                       // 外层遍历索引 / Outer loop index
    j      : INT;                       // 插入排序内层索引 / Inner index for the insertion sort
    fKey   : REAL;                      // 插入排序暂存键 [工程单位] / Key kept while inserting
    fLo    : REAL;                      // 偶数样本时中位数取中间两值之一 [工程单位] / One of the two middle values
    fHi    : REAL;                      // 偶数样本时中位数取中间两值之另一 [工程单位] / The other middle value
    nMidi  : INT;                       // 中位数取位下标（下中位） [个] / Lower middle index
END_VAR
VAR CONSTANT
    DL_MAD_MAXN : INT := 16;            // 样本容量（与 ARRAY 上界一致） [个] / Sample capacity matching the array bounds
    DL_MAD_MINN : INT := 3;             // 稳健统计所需最少样本数 [个] / Minimum sample count for robust statistics
END_VAR

(* —— 段 1：出口初始化（任何路径下返回值确定） —— *)
FC_DL_MedianAbsDev := 0.0;      // 缺省返回 0，须配 bValid 才可用 / Default 0, meaningful only with bValid
fMedian  := 0.0;                // 中位数清零 / Median cleared
bValid   := FALSE;              // 先假定无效 / Assume invalid
bClamped := FALSE;              // 钳位标志清零 / Clamp flag cleared
bNonFin  := FALSE;              // 非有限标志清零 / Non-finite flag cleared

(* —— 段 2：样本数钳位（先钳后循环，循环上界全部由 nUse 派生） —— *)
IF nCount <= 0 THEN
    RETURN;                     // 无样本：直接返回哨兵 0 / No samples: return the sentinel
END_IF
nUse := nCount;                 // 取请求样本数 / Take the requested count
IF nUse > DL_MAD_MAXN THEN
    nUse := DL_MAD_MAXN;        // 上界钳到容量 / Clamp to capacity
    bClamped := TRUE;           // 标记被钳 / Mark the clamp
END_IF

(* —— 段 3：复制到本地缓冲 + 非有限闸（NaN/Inf 会让排序失去意义，检出即拒算） —— *)
FOR i := 0 TO nUse - 1 DO
    afWork[i] := afSample[i];                               // 复制样本，不改调用方数组 / Copy, never modify the caller array
    IF (afWork[i] <> afWork[i]) OR ((afWork[i] - afWork[i]) <> (afWork[i] - afWork[i])) THEN
        bNonFin := TRUE;                                    // NaN 自反判 或 Inf 判（Inf−Inf 得 NaN） / NaN or Inf detected
    END_IF
END_FOR
IF bNonFin THEN
    RETURN;                     // 拒算：bValid 仍为假，返回 0 / Refuse: bValid stays false, 0 returned
END_IF

(* —— 段 4：插入排序（升序），小样本下比快排更省代码且无递归 —— *)
FOR i := 1 TO nUse - 1 DO
    fKey := afWork[i];                                      // 取出待插入键 / Take the key to insert
    j := i - 1;                                             // 从上一元素起向前扫 / Start scanning backwards
    WHILE (j >= 0) AND (afWork[j] > fKey) DO
        afWork[j + 1] := afWork[j];                         // 元素后移腾位 / Shift the element up
        j := j - 1;                                         // 索引前移（j 可到 −1，循环条件已含下界） / Step back, the loop condition covers -1
    END_WHILE
    afWork[j + 1] := fKey;                                  // 插入到位 / Insert at its place
END_FOR

(* —— 段 5：中位数（偶数样本取中间两值平均，写死口径） —— *)
nMidi := nUse / 2;                                          // 下中位下标（整除，nUse>=3 时 >=1） / Lower middle index
IF (nUse MOD 2) = 0 THEN
    fLo := afWork[nMidi - 1];                               // 中间左值 / Left middle value
    fHi := afWork[nMidi];                                   // 中间右值 / Right middle value
    fMedian := (fLo + fHi) * 0.5;                           // 偶数样本：算术平均 / Even count: arithmetic mean
ELSE
    fMedian := afWork[nMidi];                               // 奇数样本：正中值 / Odd count: the exact middle
END_IF

(* —— 段 6：绝对偏差数组 + 再次插入排序 —— *)
FOR i := 0 TO nUse - 1 DO
    afDev[i] := ABS(afWork[i] - fMedian);                   // 各样本到中位数的绝对距离 / Absolute distance to the median
END_FOR
FOR i := 1 TO nUse - 1 DO
    fKey := afDev[i];                                       // 取出待插入键 / Take the key
    j := i - 1;                                             // 从上一元素起向前扫 / Scan backwards
    WHILE (j >= 0) AND (afDev[j] > fKey) DO
        afDev[j + 1] := afDev[j];                           // 元素后移腾位 / Shift up
        j := j - 1;                                         // 索引前移 / Step back
    END_WHILE
    afDev[j + 1] := fKey;                                   // 插入到位 / Insert
END_FOR

(* —— 段 7：MAD 中位数 + 有效性判定（nUse >= 3 才算稳健） —— *)
nMidi := nUse / 2;                                          // 偏差数组的下中位下标 / Lower middle index of the deviations
IF (nUse MOD 2) = 0 THEN
    fLo := afDev[nMidi - 1];                                // 中间左值 / Left middle
    fHi := afDev[nMidi];                                    // 中间右值 / Right middle
    FC_DL_MedianAbsDev := (fLo + fHi) * 0.5;                // 偶数：平均 / Even: mean
ELSE
    FC_DL_MedianAbsDev := afDev[nMidi];                     // 奇数：正中值 / Odd: exact middle
END_IF
IF nUse >= DL_MAD_MINN THEN
    bValid := TRUE;                                         // 样本足够，结果有效 / Enough samples, result valid
ELSE
    bValid := FALSE;                                        // 样本过少，结果不宣称（返回值为 0） / Too few samples, nothing claimed
    FC_DL_MedianAbsDev := 0.0;                              // 明确置 0，避免半算值外溢 / Zero it explicitly
END_IF

END_FUNCTION
