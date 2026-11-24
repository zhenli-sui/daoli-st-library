(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StatsMeanStdDev
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（SQRT / ABS），零厂商私有库
 * 功能描述 (Function)   : 均值与标准差，采用 **Welford 单遍递推**（数值稳定、防溢出）：
 *                           k := k + 1
 *                           delta := x - mean
 *                           mean  := mean + delta / k
 *                           m2    := m2 + delta × (x - mean)
 *                         var := m2 / (k - 1)（样本方差，无偏），std := SQRT(var)。
 *                         相比「先求和再求平方和」的朴素两式算法，Welford 不会因
 *                         大均值配小方差发生灾难性抵消，也不要求预存全样本。
 *                         用途：称重一致性、加工尺寸波动、批次质量 SPC 判据输入。
 * 接口     (Interface)  : 输入 afSample 样本数组 [EU]、iCount 有效样本数 [个]（2..64）；
 *                         输出 fMean 均值 [EU]、fStdDev 样本标准差 [EU]、fVariance 样本方差 [EU^2]、
 *                         fSum 样本和 [EU]、bValid 结果可信标志、eErrCode（E_DL_StatsMsdErr）；
 *                         返回值 = bValid（TRUE = 三个统计量均可信）。
 * 边界     (Boundary)   : ① 属主边界：只算一阶/二阶统计量，不做离群剔除、不做分布检验。
 *                         ② 样本数域闸 2..64：<2 无样本方差定义（分母 k-1 = 0）→ 故障级 eBadCount，
 *                         **除零在结构上被排除**（先判点数后递推）。
 *                         ③ 非有限双判：全部参与计算的样本逐个枚举（i = 1..iCount），
 *                         任一非有限 → 故障级 eNonFinite（漏判单个样本会污染全部统计量）。
 *                         ④ 结果复检：mean / stddev / var 三者均做非有限复检；var 出现极小负值
 *                         （浮点舍入残差）→ 钳 0 并置信息级 eVarClamped，**不输出 NaN**。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StatsRmsCalc` 分工：RMS 含直流分量归那件、
 *                         均值+去均值标准差归本件；与 `FC_DL_StatsOutlierCount` 分工：
 *                         离群计数归那件（其内部自带 Welford，不跨件调用）。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 4×LREAL +
 *                         本文件内定义 enum E_DL_StatsMsdErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸（除零结构性排除）+ 全样本非有限双判 + 负方差钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 16）
 * 验收向量 (Acceptance) : ① afSample=[2,4,4,4,5,5,7,9], iCount=8 → fMean=5.0，
 *                         fVariance=32/7≈4.571428571，fStdDev≈2.138089935（容差 1E-6）；
 *                         ② afSample=[1,1,1], iCount=3 → fMean=1.0, fStdDev=0.0, eOk；
 *                         ③ iCount=1 → 返回 FALSE, eBadCount, fMean/fStdDev 哨兵 0；
 *                         ④ afSample[3]=NaN, iCount=8 → 返回 FALSE, eNonFinite；
 *                         ⑤ afSample=[10,10], iCount=2 → fMean=10.0, fVariance=0.0, fStdDev=0.0。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StatsMsdErr（均值/标准差统计错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StatsMsdErr :
(
    eOk          := 0,   // 信息级：统计完成 / Info: statistics computed
    eVarClamped  := 1,   // 信息级：方差负残差已钳 0 / Info: negative variance residual clamped to zero
    eBadCount    := 2,   // 故障级：样本数越域 / Fault: sample count out of domain
    eNonFinite   := 3    // 故障级：样本含非有限值 / Fault: non-finite sample present
);
END_TYPE

FUNCTION FC_DL_StatsMeanStdDev : BOOL
VAR_INPUT
    afSample : ARRAY[1..64] OF LREAL;  // 样本数组 [EU] / Sample array
    iCount   : INT;                    // 有效样本数（2..64） [个] / Valid sample count, 2..64
END_VAR
VAR_OUTPUT
    fMean     : LREAL;  // 算术均值 [EU] / Arithmetic mean
    fStdDev   : LREAL;  // 样本标准差（分母 n-1） [EU] / Sample standard deviation
    fVariance : LREAL;  // 样本方差 [EU^2] / Sample variance
    fSum      : LREAL;  // 样本和（诊断用） [EU] / Sample sum for diagnostics
    bValid    : BOOL;   // 结果可信标志 [-] / Result trustworthy flag
    eErrCode  : E_DL_StatsMsdErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i       : INT;    // 样本遍历下标 [-] / Sample index
    _bNonFin : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fMean   : LREAL;  // Welford 递推均值 [EU] / Recursive mean
    _fM2     : LREAL;  // Welford 二阶中心矩累加 [EU^2] / Second central moment accumulator
    _fDelta  : LREAL;  // 样本与当前均值之差 [EU] / Delta between sample and running mean
    _fSum    : LREAL;  // 样本和累加 [EU] / Sample sum accumulator
    _fVar    : LREAL;  // 方差（钳位前） [EU^2] / Variance before clamping
END_VAR
VAR CONSTANT
    DL_SMS_CNT_MIN : INT := 2;        // 样本数下限（n-1 必须 > 0） [个] / Count lower bound
    DL_SMS_CNT_MAX : INT := 64;       // 样本数上限（数组容量） [个] / Count upper bound
    DL_SMS_ZERO    : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_SMS_ONE     : LREAL := 1.0;    // 单位常数（Welford 分母 k-1 的基准） [-] / Unit constant
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StatsMeanStdDev := FALSE;                    // 返回值预置无效 / Return preset invalid
fMean     := DL_SMS_ZERO;                          // 均值哨兵 / Mean sentinel
fStdDev   := DL_SMS_ZERO;                          // 标准差哨兵 / Standard deviation sentinel
fVariance := DL_SMS_ZERO;                          // 方差哨兵 / Variance sentinel
fSum      := DL_SMS_ZERO;                          // 样本和哨兵 / Sum sentinel
bValid    := FALSE;                                // 可信标志预置否 / Trust flag preset false
eErrCode  := E_DL_StatsMsdErr.eBadCount;           // 预置最严码 / Preset strictest code

(* —— 段 1：样本数域闸（先判点数，方差分母 n-1 的除零被结构性排除） —— *)
IF (iCount < DL_SMS_CNT_MIN) OR (iCount > DL_SMS_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（全部参与计算的样本逐项枚举） —— *)
_bNonFin := FALSE;
_i := 1;
WHILE _i <= iCount DO
    IF (afSample[_i] <> afSample[_i]) OR ((afSample[_i] - afSample[_i]) <> DL_SMS_ZERO) THEN
        _bNonFin := TRUE;                          // 样本非有限 / Sample non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_StatsMsdErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：Welford 单遍递推（数值稳定，防灾难性抵消与溢出） —— *)
_fMean := DL_SMS_ZERO;
_fM2   := DL_SMS_ZERO;
_fSum  := DL_SMS_ZERO;
_i     := 1;
WHILE _i <= iCount DO
    _fSum   := _fSum + afSample[_i];               // 样本和 / Sample sum
    _fDelta := afSample[_i] - _fMean;              // 与当前均值之差 / Delta from running mean
    _fMean  := _fMean + _fDelta / INT_TO_LREAL(_i);   // 均值更新（分母 i >= 1，无除零） / Mean update
    _fM2    := _fM2 + _fDelta * (afSample[_i] - _fMean);   // 二阶中心矩累加 / M2 accumulation
    _i := _i + 1;
END_WHILE

(* —— 段 4：方差与标准差（分母 n-1 已由段 1 保证 >= 1） —— *)
_fVar := _fM2 / INT_TO_LREAL(iCount - 1);          // 样本方差（无偏） / Unbiased sample variance
IF _fVar < DL_SMS_ZERO THEN
    _fVar    := DL_SMS_ZERO;                       // 浮点残差负值钳 0，绝不输出 NaN / Clamp residual negative
    eErrCode := E_DL_StatsMsdErr.eVarClamped;      // 信息级码 / Info code
ELSE
    eErrCode := E_DL_StatsMsdErr.eOk;              // 信息级成功 / Info success
END_IF
fStdDev := SQRT(_fVar);                            // 标准差（非负） / Standard deviation, non-negative

(* —— 段 5：结果复检（三个统计量逐一非有限复检） —— *)
IF (fStdDev <> fStdDev) OR (_fVar <> _fVar) OR (_fMean <> _fMean) THEN
    fMean     := DL_SMS_ZERO;                      // 复检异常全部回哨兵 / Recheck failed: all sentinels
    fStdDev   := DL_SMS_ZERO;
    fVariance := DL_SMS_ZERO;
    fSum      := DL_SMS_ZERO;
    eErrCode  := E_DL_StatsMsdErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF
IF (fStdDev < DL_SMS_ZERO) OR (_fVar < DL_SMS_ZERO) THEN
    fMean     := DL_SMS_ZERO;                      // 负统计量不可能，判内部不一致 / Negative statistics impossible
    fStdDev   := DL_SMS_ZERO;
    fVariance := DL_SMS_ZERO;
    fSum      := DL_SMS_ZERO;
    eErrCode  := E_DL_StatsMsdErr.eNonFinite;
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
fMean     := _fMean;                               // 导出均值 / Export mean
fVariance := _fVar;                                // 导出方差 / Export variance
fSum      := _fSum;                                // 导出样本和 / Export sum
bValid    := TRUE;
FC_DL_StatsMeanStdDev := TRUE;                     // 统计可信 / Statistics trustworthy

END_FUNCTION
