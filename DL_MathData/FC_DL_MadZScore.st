(*==============================================================================
 * 组件名称 (Component)  : FC_DL_MadZScore
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 中位数绝对偏差（MAD）稳健离群评分（纯函数 FC）。
 *                         对样本数组取中位数 → 各样本绝对偏差取中位数（MAD）
 *                         → 稳健 z 分 = (x - median) / (1.4826·MAD)，1.4826
 *                         使 MAD 一致估计正态 σ。中位数/MAD 均为次序统计量，
 *                         抗粗大误差；与 SignalStatistics/OscillationIndex
 *                         （均值域统计）分工：本件是鲁棒统计缺口。
 * 来源标签 (Origin)     : 源矩阵 T2-1 LGF Measurement ◐ 统计族待挖（R18 备注既有），自研 clean-room
 * 边界语义 (Boundary)   : ① 样本数域闸 1..32（越域/含非有限样本 → 返回
 *                         FALSE，输出哨兵 0，还原方向不饱和 R81）；
 *                         ② MAD <= eps（过半样本恒等值）→ 无尺度基准，返回
 *                         FALSE + z 哨兵 0（退化声明，R332 端点语义）；
 *                         ③ 排序用插入排序（副本数组，不改输入）；
 *                         ④ 除法仅 z 分一处，除子 MAD 已过 eps 闸，无除零。
 * 输出语义 (Fallback)   : 返回 FALSE → fMedian/fMad/fZ 哨兵 0（调用方以返回
 *                         值判有效性，非故障级）。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码（纯函数无错误码）。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（MAD eps 闸）/NaN 拒收/域闸 ✓｜R5 双语同行注释 ✓
 *                         R6 纯函数无顺序逻辑（CASE 无涉）✓｜R7 无定时器实例 ✓
 * 验收向量 (Acceptance) : V1 样本 {1,2,3,4,100}、x=3 → median=3、MAD=1、
 *                         z=0（中位数点稳健零分，均值法被 100 拖歪而本法不受）；
 *                         V2 同样本、x=100 → z=(100-3)/(1.4826·1)≈65.42
 *                         （粗大误差高分离群分）；
 *                         V3 样本 {5,5,5,5} → MAD=0 → 返回 FALSE + z 哨兵 0
 *                         （退化声明 V3 与边界②对齐）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 4 · 序号 20）
 *==============================================================================*)
FUNCTION FC_DL_MadZScore : BOOL        // 返回 TRUE = 评分有效（median/MAD/z 可信）/ TRUE = score valid
VAR_IN_OUT
    afSamples : ARRAY[1..32] OF LREAL;   (* 样本数组（IN_OUT 免整组拷贝，本件不写回）[工程单位] / Sample array, read-only usage *)
END_VAR
VAR_INPUT
    nCount : INT;                        (* 有效样本数，域 1..32 [点] / Valid sample count *)
    fX     : LREAL;                      (* 待评分查询值 [工程单位] / Query value *)
END_VAR
VAR_OUTPUT
    fMedian : LREAL;                     (* 样本中位数 [工程单位] / Sample median *)
    fMad    : LREAL;                     (* 绝对偏差中位数 MAD [工程单位] / Median absolute deviation *)
    fZ      : LREAL;                     (* 稳健 z 分 [-] / Robust z score *)
END_VAR
VAR
    afWork : ARRAY[1..32] OF LREAL;      (* 排序副本工作量（不改输入数组）[-] / Sort work copy *)
    afDev  : ARRAY[1..32] OF LREAL;      (* 绝对偏差工作量 [工程单位] / Deviation work *)
    i      : INT;                        (* 外层排序游标（FC 局部量允许标准名）[-] / Outer sort cursor *)
    j      : INT;                        (* 内层排序游标 [-] / Inner sort cursor *)
    nMid   : INT;                        (* 中位下标工作量 [-] / Median index work *)
    fKey   : LREAL;                      (* 插入排序关键值工作量 [-] / Insertion key work *)
    fScale : LREAL;                      (* 尺度因子 1.4826·MAD 工作量 [工程单位] / Scale factor work *)
    bFin   : BOOL;                       (* 全样本有限当拍量 [-] / All-finite flag *)
END_VAR
VAR CONSTANT
    DL_MZD_NMAX : INT := 32;             (* 样本容量上限（与数组界一致）[点] / Sample capacity *)
    DL_MZD_EPS  : LREAL := 1.0E-12;      (* MAD 判零容差 [工程单位] / MAD epsilon *)
    DL_MZD_K    : LREAL := 1.4826;       (* MAD → σ 一致性系数（公开统计常数）[-] / Consistency constant *)
END_VAR

(* —— 段 0：输出哨兵预置（还原方向不饱和，R81） —— *)
fMedian := 0.0;                          (* 中位数哨兵 / Median sentinel *)
fMad := 0.0;                             (* MAD 哨兵 / MAD sentinel *)
fZ := 0.0;                               (* z 分哨兵 / Z sentinel *)
FC_DL_MadZScore := FALSE;                (* 返回值预置无效 / Return preset invalid *)

(* —— 段 1：样本数域闸 + 非有限拒收（NaN 自反 + Inf 差判） —— *)
IF (nCount < 1) OR (nCount > DL_MZD_NMAX) THEN
    RETURN;                              (* 数越域：哨兵 + FALSE（无后处理须补，R94） / Count out of domain *)
END_IF
bFin := TRUE;                            (* 有限标志预置 / Finite flag preset *)
i := 1;                                  (* 校验游标重置（R227） / Check cursor reset *)
WHILE i <= nCount DO                     (* 逐样本非有限校验 / Per-sample finiteness *)
    IF (afSamples[i] <> afSamples[i]) OR ((afSamples[i] - afSamples[i]) <> (afSamples[i] - afSamples[i])) THEN
        bFin := FALSE;                   (* 命中非有限样本 / Non-finite hit *)
    END_IF
    i := i + 1;                          (* 游标递进 / Cursor advance *)
END_WHILE
IF NOT bFin THEN
    RETURN;                              (* 含坏样本：哨兵 + FALSE（边界①） / Bad sample: return FALSE *)
END_IF

(* —— 段 2：副本排序（插入排序，O(n²) 对 32 点可接受） —— *)
i := 1;                                  (* 副本游标重置 / Copy cursor reset *)
WHILE i <= nCount DO
    afWork[i] := afSamples[i];           (* 复制样本（不改输入，边界③） / Copy sample *)
    i := i + 1;                          (* 游标递进 / Cursor advance *)
END_WHILE
i := 2;                                  (* 插入排序外层起点 / Insertion outer start *)
WHILE i <= nCount DO
    fKey := afWork[i];                   (* 取关键值 / Take key *)
    j := i - 1;                          (* 内层起点 / Inner start *)
    WHILE (j >= 1) AND (afWork[j] > fKey) DO
        afWork[j + 1] := afWork[j];      (* 右移腾位 / Shift right *)
        j := j - 1;                      (* 游标递退 / Cursor back *)
    END_WHILE
    afWork[j + 1] := fKey;               (* 插入落位 / Insert key *)
    i := i + 1;                          (* 外层递进 / Outer advance *)
END_WHILE

(* —— 段 3：中位数（奇取中点，偶取双中均值，除子常量 2 无除零） —— *)
nMid := (nCount + 1) / 2;                (* 中位下标（INT 整除向下取整口径） / Median index *)
IF (nCount MOD 2) = 1 THEN
    fMedian := afWork[nMid];             (* 奇数样本取中点 / Odd: middle *)
ELSE
    fMedian := 0.5 * (afWork[nCount / 2] + afWork[nCount / 2 + 1]);   (* 偶数样本取双中均值 / Even: mean of two middles *)
END_IF

(* —— 段 4：绝对偏差数组及其排序（逐行自含注释，相对指代省写为 R92 禁项） —— *)
i := 1;                                  (* 偏差游标重置 / Deviation cursor reset *)
WHILE i <= nCount DO
    afDev[i] := ABS(afSamples[i] - fMedian);   (* 绝对偏差 / Absolute deviation *)
    i := i + 1;                          (* 游标递进 / Cursor advance *)
END_WHILE
i := 1;                                  (* 偏差副本入排序工作区 / Copy deviations *)
WHILE i <= nCount DO
    afWork[i] := afDev[i];               (* 复制偏差到工作区 / Copy to work *)
    i := i + 1;                          (* 游标递进 / Cursor advance *)
END_WHILE
i := 2;                                  (* 偏差排序外层起点 / Deviation sort outer *)
WHILE i <= nCount DO
    fKey := afWork[i];                   (* 取关键值 / Take key *)
    j := i - 1;                          (* 内层起点 / Inner start *)
    WHILE (j >= 1) AND (afWork[j] > fKey) DO
        afWork[j + 1] := afWork[j];      (* 右移腾位 / Shift right *)
        j := j - 1;                      (* 游标递退 / Cursor back *)
    END_WHILE
    afWork[j + 1] := fKey;               (* 插入落位 / Insert key *)
    i := i + 1;                          (* 外层递进 / Outer advance *)
END_WHILE
IF (nCount MOD 2) = 1 THEN
    fMad := afWork[nMid];                (* 奇数 MAD 取中点 / Odd MAD middle *)
ELSE
    fMad := 0.5 * (afWork[nCount / 2] + afWork[nCount / 2 + 1]);   (* 偶数 MAD 双中均值 / Even MAD mean *)
END_IF

(* —— 段 5：尺度闸与 z 分（MAD 退化端点声明，R332；除子已过 eps 闸） —— *)
fScale := DL_MZD_K * fMad;               (* 尺度因子（乘法无除零） / Scale factor *)
IF fScale <= DL_MZD_EPS THEN
    RETURN;                              (* MAD 退化：哨兵 + FALSE（边界②） / Degenerate MAD: return FALSE *)
END_IF
fZ := (fX - fMedian) / fScale;           (* 稳健 z 分（除子 fScale > eps，无除零） / Robust z *)
FC_DL_MadZScore := TRUE;                 (* 评分有效 / Valid *)
END_FUNCTION
