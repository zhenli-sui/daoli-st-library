(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StatsRmsCalc
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（SQRT / ABS），零厂商私有库
 * 功能描述 (Function)   : 有效值 RMS 计算（交流量监测）：
 *                           RMS = SQRT( Σ x_i² / n )
 *                         与「均值」的本质差别：RMS 保留交流分量的能量（直流表读 0，
 *                         RMS 表读出真实有效值），故适用于电流/电压有效值、
 *                         振动加速度有效值、阀线圈 PWM 电流有效值的单批核算。
 *                         **溢出前置防护**：LREAL 可表到 1.8E308，故 |x| > 1E150 时
 *                         x² 会越过可表上限。本件在累加前先扫一遍最大绝对值，
 *                         超阈即判故障级 eOverflowRisk 并拒绝计算（不输出 Inf）。
 * 接口     (Interface)  : 输入 afSample 样本数组 [EU]、iCount 有效样本数 [个]（1..64）；
 *                         输出 fRms 有效值 [EU]、fPeak 最大绝对值（峰值） [EU]、
 *                         fSumSq 平方和（诊断用） [EU^2]、bValid 结果可信、
 *                         eErrCode（E_DL_StatsRmsErr）；
 *                         返回值 = bValid。
 * 边界     (Boundary)   : ① 属主边界：只算单批 RMS，不做跨周期累计（跨周期归 FB）、
 *                         不做真有效值（含谐波分量的时域积分，需更高采样率）。
 *                         ② 样本数域闸 1..64；越域 → 故障级 eBadCount。
 *                         n=1 时 RMS = |x1|，合法。
 *                         ③ 非有限双判：全部有效样本逐项枚举。
 *                         ④ 溢出前置防护阈值 DL_SRC_MAG_MAX = 1E150（平方后 1E300，仍在 LREAL 域内）。
 *                         ⑤ 平方和与 RMS 均做非有限复检；RMS 必须 >= 0（负值判内部不一致）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StatsMeanStdDev` 分工：均值/标准差（去直流）归那件、
 *                         含直流的有效值归本件；与 `FC_DL_StatsZeroCrossRate` 分工：
 *                         频率特征归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 3×LREAL +
 *                         本文件内定义 enum E_DL_StatsRmsErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸 + 全样本非有限双判 + 平方溢出前置防护 + 结果复检 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 19）
 * 验收向量 (Acceptance) : ① afSample=[3,4], iCount=2 → 平方和 25，RMS=SQRT(12.5)≈3.535533906
 *                         （容差 1E-9），fPeak=4.0；
 *                         ② afSample=[1,-1,1,-1], iCount=4 → 平方和 4，RMS=1.0（直流为 0 但 RMS 非 0）；
 *                         ③ afSample=[0,0,0], iCount=3 → fRms=0.0, fPeak=0.0, eOk；
 *                         ④ afSample=[1E200], iCount=1 → 返回 FALSE, eOverflowRisk（不输出 Inf）；
 *                         ⑤ iCount=65 → 返回 FALSE, eBadCount。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StatsRmsErr（有效值统计错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StatsRmsErr :
(
    eOk           := 0,   // 信息级：计算完成 / Info: computed
    eBadCount     := 1,   // 故障级：样本数越域 / Fault: sample count out of domain
    eNonFinite    := 2,   // 故障级：样本含非有限值 / Fault: non-finite sample present
    eOverflowRisk := 3,   // 故障级：量值平方将越出可表域 / Fault: squaring would overflow the representable range
    eInternal     := 9    // 故障级：RMS 为负等内部不一致 / Fault: negative RMS or other internal inconsistency
);
END_TYPE

FUNCTION FC_DL_StatsRmsCalc : BOOL
VAR_INPUT
    afSample : ARRAY[1..64] OF LREAL;  // 样本数组 [EU] / Sample array
    iCount   : INT;                    // 有效样本数（1..64） [个] / Valid sample count, 1..64
END_VAR
VAR_OUTPUT
    fRms      : LREAL;  // 有效值 [EU] / Root mean square
    fPeak     : LREAL;  // 最大绝对值 [EU] / Peak absolute value
    fSumSq    : LREAL;  // 平方和（诊断用） [EU^2] / Sum of squares for diagnostics
    bValid    : BOOL;   // 结果可信标志 [-] / Result trustworthy flag
    eErrCode  : E_DL_StatsRmsErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i        : INT;    // 样本遍历下标 [-] / Sample index
    _bNonFin  : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fAbs     : LREAL;  // 当前样本绝对值 [EU] / Current absolute value
    _fPeak    : LREAL;  // 最大绝对值累计 [EU] / Peak accumulator
    _fSumSq   : LREAL;  // 平方和累计 [EU^2] / Sum of squares accumulator
    _fMeanSq  : LREAL;  // 均方值 [EU^2] / Mean square value
END_VAR
VAR CONSTANT
    DL_SRC_CNT_MIN : INT := 1;          // 样本数下限 [个] / Count lower bound
    DL_SRC_CNT_MAX : INT := 64;         // 样本数上限（数组容量） [个] / Count upper bound
    DL_SRC_MAG_MAX : LREAL := 1.0E150;  // 平方溢出前置阈值（平方后 1E300 仍可表） [EU] / Pre-square overflow threshold
    DL_SRC_ZERO    : LREAL := 0.0;      // 零基准（含非有限判零） [-] / Zero base including non-finite probe
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StatsRmsCalc := FALSE;                       // 返回值预置无效 / Return preset invalid
fRms     := DL_SRC_ZERO;                           // RMS 哨兵 / RMS sentinel
fPeak    := DL_SRC_ZERO;                           // 峰值哨兵 / Peak sentinel
fSumSq   := DL_SRC_ZERO;                           // 平方和哨兵 / Sum of squares sentinel
bValid   := FALSE;                                 // 可信标志预置否 / Trust flag preset false
eErrCode := E_DL_StatsRmsErr.eBadCount;            // 预置最严码 / Preset strictest code

(* —— 段 1：样本数域闸 —— *)
IF (iCount < DL_SRC_CNT_MIN) OR (iCount > DL_SRC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸 + 量值上限扫描（平方溢出前置防护，一遍完成两件事） —— *)
_bNonFin := FALSE;
_fPeak   := DL_SRC_ZERO;
_i := 1;
WHILE _i <= iCount DO
    IF (afSample[_i] <> afSample[_i]) OR ((afSample[_i] - afSample[_i]) <> DL_SRC_ZERO) THEN
        _bNonFin := TRUE;                          // 样本非有限 / Sample non-finite
    ELSE
        _fAbs := ABS(afSample[_i]);                // 绝对值 / Absolute value
        IF _fAbs > _fPeak THEN
            _fPeak := _fAbs;                       // 更新峰值 / Update peak
        END_IF
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_StatsRmsErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF
IF _fPeak > DL_SRC_MAG_MAX THEN
    eErrCode := E_DL_StatsRmsErr.eOverflowRisk;    // 故障级：平方将溢出 / Fault: squaring would overflow
    RETURN;                                        // 拒绝计算，绝不输出 Inf / Refuse rather than emit Inf
END_IF

(* —— 段 3：平方和累加 —— *)
_fSumSq := DL_SRC_ZERO;
_i := 1;
WHILE _i <= iCount DO
    _fSumSq := _fSumSq + afSample[_i] * afSample[_i];   // 逐点平方累加 / Accumulate squares
    _i := _i + 1;
END_WHILE

(* —— 段 4：均方与 RMS（分母 n 已由段 1 保证 >= 1，无除零） —— *)
_fMeanSq := _fSumSq / INT_TO_LREAL(iCount);        // 均方值 / Mean square
fRms     := SQRT(_fMeanSq);                        // 有效值 / Root mean square

(* —— 段 5：结果复检（非有限 + 非负 + 不超峰值） —— *)
IF (fRms <> fRms) OR (_fSumSq <> _fSumSq) THEN
    fRms     := DL_SRC_ZERO;                       // 复检异常回哨兵 / Recheck failed: sentinel
    fSumSq   := DL_SRC_ZERO;
    fPeak    := DL_SRC_ZERO;
    eErrCode := E_DL_StatsRmsErr.eNonFinite;
    RETURN;
END_IF
IF (fRms < DL_SRC_ZERO) OR (fRms > _fPeak) THEN
    fRms     := DL_SRC_ZERO;                       // RMS 必在 [0, peak] 内，否则内部不一致 / RMS must lie in 0..peak
    fSumSq   := DL_SRC_ZERO;
    fPeak    := DL_SRC_ZERO;
    eErrCode := E_DL_StatsRmsErr.eInternal;
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
fSumSq   := _fSumSq;                               // 导出平方和 / Export sum of squares
fPeak    := _fPeak;                                // 导出峰值 / Export peak
bValid   := TRUE;
eErrCode := E_DL_StatsRmsErr.eOk;                  // 信息级成功 / Info success
FC_DL_StatsRmsCalc := TRUE;                        // 结果可信 / Result trustworthy

END_FUNCTION
