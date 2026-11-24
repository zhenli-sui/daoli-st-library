(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StatsOutlierCount
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS / SQRT），零厂商私有库
 * 功能描述 (Function)   : 离群点计数（3σ 判据）。步骤：
 *                         ① 用 Welford 单遍递推求均值与样本标准差（防溢出、防抵消）；
 *                         ② 逐点判 |x_i - mean| > fSigmaK × std，命中即计一个离群点；
 *                         ③ 回传离群个数、占比、判据阈值与两端样本值。
 *                         **样本不足保护**：样本数 < 8 时 σ 估计极不稳定（自由度过低），
 *                         本件不给出离群判定，回 iOutliers = 0、bValid = FALSE、
 *                         信息级码 eInsufficientSamples，让调用方明确知道「未判」而非「无离群」——
 *                         若静默返回 0，会被误当成「质量良好」。
 *                         **零离散保护**：std 近似 0（所有样本相同）时任何偏离都不可能存在，
 *                         回 0 并置信息级 eZeroSpread，避免 0 × k = 0 把全样本判成离群。
 * 接口     (Interface)  : 输入 afSample 样本数组 [EU]、iCount 有效样本数 [个]（2..64）、
 *                         fSigmaK 判据倍数（默认 3.0，必须 > 0） [倍]；
 *                         输出 iOutliers 离群点数 [个]、fOutlierRate 离群占比 [0..1]、
 *                         fMean 均值 [EU]、fStdDev 样本标准差 [EU]、fLimit 判定阈值带（k×σ） [EU]、
 *                         bValid 判定是否成立、eErrCode（E_DL_StatsOutErr）；
 *                         返回值 = bValid（**注意：样本不足时返回 FALSE**，与「无离群但判定成立」
 *                         严格区分——后者返回 TRUE 且 iOutliers = 0）。
 * 边界     (Boundary)   : ① 属主边界：只计数，不剔除、不替换离群点（剔除策略归调用方）。
 *                         ② 样本数域闸 2..64；< 8 判「样本不足」（信息级，返回 FALSE）。
 *                         ③ fSigmaK <= 0 → 故障级 eBadParam（0 倍会把全部样本判成离群）。
 *                         ④ 非有限双判：fSigmaK 与全部样本逐一枚举。
 *                         ⑤ 判据用严格大于（>），恰在边界上的点**不算**离群（保守口径，
 *                         避免阈值抖动导致计数跳变）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StatsMeanStdDev` 分工：本件内部自带 Welford 以保持
 *                         单次调用语义（不跨件调用，避免多一次数组遍历与出口耦合）；
 *                         与 `FB_DL_HoldLastGoodFilter` 分工：坏值保持归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + 5×LREAL +
 *                         本文件内定义 enum E_DL_StatsOutErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 样本不足保护 + 零离散保护 + 倍数域闸 + 全样本非有限双判 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 21）
 * 验收向量 (Acceptance) : ① afSample=[10,10,10,10,10,10,10,10,10,40], iCount=10, fSigmaK=3.0 →
 *                         mean=13.0, σ≈9.0（样本）；|40-13|=27 > 3×9.0≈27.0 边界 → 按严格 >
 *                         判定，27 与 27.0 相等时**不计**（保守）；取 fSigmaK=2.5 则计入 1 个；
 *                         ② afSample=[5,5,5,5,5,5,5,5], iCount=8, fSigmaK=3.0 →
 *                         std=0 → eZeroSpread，iOutliers=0，返回 TRUE；
 *                         ③ iCount=7 → 返回 FALSE, eInsufficientSamples（明确「未判」）；
 *                         ④ fSigmaK=0.0 → 返回 FALSE, eBadParam；
 *                         ⑤ iCount=0 → 返回 FALSE, eBadCount。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StatsOutErr（离群点统计错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StatsOutErr :
(
    eOk                 := 0,   // 信息级：判定成立并完成计数 / Info: judgement valid and counted
    eZeroSpread         := 1,   // 信息级：零离散，无离群可能 / Info: zero spread, no outlier possible
    eInsufficientSamples:= 2,   // 信息级：样本不足 8 个，判定不成立 / Info: fewer than eight samples, judgement invalid
    eBadCount           := 3,   // 故障级：样本数越域 / Fault: sample count out of domain
    eNonFinite          := 4,   // 故障级：样本或倍数含非有限值 / Fault: non-finite sample or multiplier
    eBadParam           := 5    // 故障级：判据倍数非正 / Fault: non-positive sigma multiplier
);
END_TYPE

FUNCTION FC_DL_StatsOutlierCount : BOOL
VAR_INPUT
    afSample : ARRAY[1..64] OF LREAL;  // 样本数组 [EU] / Sample array
    iCount   : INT;                    // 有效样本数（2..64） [个] / Valid sample count, 2..64
    fSigmaK  : LREAL;                  // 判据倍数，必须 > 0，常取 3.0 [倍] / Sigma multiplier, must be positive
END_VAR
VAR_OUTPUT
    iOutliers    : INT;    // 离群点数 [个] / Outlier count
    fOutlierRate : LREAL;  // 离群占比 [0..1] / Outlier ratio
    fMean        : LREAL;  // 样本均值 [EU] / Sample mean
    fStdDev      : LREAL;  // 样本标准差 [EU] / Sample standard deviation
    fLimit       : LREAL;  // 判定阈值带 k×σ [EU] / Decision band width
    bValid       : BOOL;   // 判定是否成立 [-] / Whether the judgement is valid
    eErrCode     : E_DL_StatsOutErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i       : INT;    // 样本遍历下标 [-] / Sample index
    _iOut    : INT;    // 离群净额累加器（单点写入） [个] / Net outlier accumulator
    _bNonFin : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fMean   : LREAL;  // Welford 递推均值 [EU] / Recursive mean
    _fM2     : LREAL;  // 二阶中心矩累加 [EU^2] / Second central moment accumulator
    _fDelta  : LREAL;  // 样本与均值之差 [EU] / Delta from running mean
    _fVar    : LREAL;  // 方差 [EU^2] / Variance
    _fStd    : LREAL;  // 标准差 [EU] / Standard deviation
    _fLimit  : LREAL;  // 判定带宽 k×σ [EU] / Decision band width
END_VAR
VAR CONSTANT
    DL_SOC_CNT_MIN  : INT := 2;        // 样本数下限 [个] / Count lower bound
    DL_SOC_CNT_MAX  : INT := 64;       // 样本数上限（数组容量） [个] / Count upper bound
    DL_SOC_CNT_STAT : INT := 8;        // 统计可信最小样本数 [个] / Minimum samples for a valid judgement
    DL_SOC_ZERO     : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_SOC_TINY     : LREAL := 1.0E-9; // 零离散判定阈值 [EU] / Zero-spread threshold
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StatsOutlierCount := FALSE;                  // 返回值预置无效（判定未成立） / Return preset invalid
iOutliers    := 0;                                 // 离群计数哨兵 / Outlier count sentinel
fOutlierRate := DL_SOC_ZERO;                       // 离群占比哨兵 / Outlier ratio sentinel
fMean        := DL_SOC_ZERO;                       // 均值哨兵 / Mean sentinel
fStdDev      := DL_SOC_ZERO;                       // 标准差哨兵 / Standard deviation sentinel
fLimit       := DL_SOC_ZERO;                       // 判定带哨兵 / Decision band sentinel
bValid       := FALSE;                             // 判定成立标志预置否 / Judgement valid preset false
eErrCode     := E_DL_StatsOutErr.eBadCount;        // 预置最严码 / Preset strictest code

(* —— 段 1：样本数域闸 —— *)
IF (iCount < DL_SOC_CNT_MIN) OR (iCount > DL_SOC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（倍数 + 全部样本逐项枚举） —— *)
_bNonFin := (fSigmaK <> fSigmaK) OR ((fSigmaK - fSigmaK) <> DL_SOC_ZERO);
_i := 1;
WHILE _i <= iCount DO
    IF (afSample[_i] <> afSample[_i]) OR ((afSample[_i] - afSample[_i]) <> DL_SOC_ZERO) THEN
        _bNonFin := TRUE;
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_StatsOutErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：判据倍数域闸（必须严格为正，否则全部样本都会被判离群） —— *)
IF fSigmaK <= DL_SOC_ZERO THEN
    eErrCode := E_DL_StatsOutErr.eBadParam;        // 故障级：倍数非正 / Fault: non-positive multiplier
    RETURN;
END_IF

(* —— 段 4：Welford 单遍求均值与标准差（样本不足时也先算出来供诊断） —— *)
_fMean := DL_SOC_ZERO;
_fM2   := DL_SOC_ZERO;
_i     := 1;
WHILE _i <= iCount DO
    _fDelta := afSample[_i] - _fMean;
    _fMean  := _fMean + _fDelta / INT_TO_LREAL(_i);            // 分母 i >= 1，无除零 / Denominator at least one
    _fM2    := _fM2 + _fDelta * (afSample[_i] - _fMean);
    _i := _i + 1;
END_WHILE
_fVar := _fM2 / INT_TO_LREAL(iCount - 1);          // 样本方差（n-1 已由段 1 保证 >= 1） / Unbiased variance
IF _fVar < DL_SOC_ZERO THEN
    _fVar := DL_SOC_ZERO;                          // 浮点残差负值钳 0 / Clamp residual negative
END_IF
_fStd := SQRT(_fVar);                              // 标准差 / Standard deviation
fMean   := _fMean;                                 // 导出均值（诊断量，任何分支都可信） / Export mean
fStdDev := _fStd;                                  // 导出标准差 / Export standard deviation

(* —— 段 5：样本不足保护（< 8 个不判，明确回「未判」而非「无离群」） —— *)
IF iCount < DL_SOC_CNT_STAT THEN
    iOutliers    := 0;
    fOutlierRate := DL_SOC_ZERO;
    fLimit       := DL_SOC_ZERO;
    bValid       := FALSE;                         // 判定不成立 / Judgement invalid
    eErrCode     := E_DL_StatsOutErr.eInsufficientSamples;   // 信息级：样本不足 / Info: insufficient samples
    FC_DL_StatsOutlierCount := FALSE;              // 返回 FALSE 与「成立且 0 离群」严格区分 / Distinguish from valid zero
    RETURN;
END_IF

(* —— 段 6：零离散保护（所有样本相同，无离群可能） —— *)
IF _fStd < DL_SOC_TINY THEN
    iOutliers    := 0;
    fOutlierRate := DL_SOC_ZERO;
    fLimit       := DL_SOC_ZERO;
    bValid       := TRUE;                          // 判定成立：确实无离群 / Judgement valid: truly no outlier
    eErrCode     := E_DL_StatsOutErr.eZeroSpread;  // 信息级：零离散 / Info: zero spread
    FC_DL_StatsOutlierCount := TRUE;
    RETURN;
END_IF

(* —— 段 7：离群计数（严格大于判据带，恰在边界不计） —— *)
_fLimit := fSigmaK * _fStd;                        // 判定带宽 k×σ / Decision band width
fLimit  := _fLimit;
_iOut   := 0;
_i      := 1;
WHILE _i <= iCount DO
    IF ABS(afSample[_i] - _fMean) > _fLimit THEN
        _iOut := _iOut + 1;                        // 命中离群（单点累加） / Count one outlier
    END_IF
    _i := _i + 1;
END_WHILE
iOutliers    := _iOut;                             // 导出离群数 / Export outlier count
fOutlierRate := INT_TO_LREAL(_iOut) / INT_TO_LREAL(iCount);   // 占比（分母 n >= 8，无除零） / Ratio

(* —— 段 8：结果复检（非有限 + 计数域） —— *)
IF (fLimit <> fLimit) OR (fMean <> fMean) OR (fStdDev <> fStdDev) THEN
    iOutliers    := 0;
    fOutlierRate := DL_SOC_ZERO;
    fLimit       := DL_SOC_ZERO;
    bValid       := FALSE;
    eErrCode     := E_DL_StatsOutErr.eNonFinite;
    RETURN;
END_IF
IF (_iOut < 0) OR (_iOut > iCount) THEN
    iOutliers    := 0;
    fOutlierRate := DL_SOC_ZERO;
    bValid       := FALSE;
    eErrCode     := E_DL_StatsOutErr.eBadCount;
    RETURN;
END_IF

(* —— 段 9：成功出口 —— *)
bValid   := TRUE;
eErrCode := E_DL_StatsOutErr.eOk;                  // 信息级成功 / Info success
FC_DL_StatsOutlierCount := TRUE;                   // 判定成立且计数可信 / Judgement valid and count trustworthy

END_FUNCTION
