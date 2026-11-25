(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StatsMinMaxWindow
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 窗口极值与发生时刻。在 afSample[1..iCount] 中找最小值与最大值，
 *                         并回传它们**首次出现**的位置下标与对应时刻（afStamp 为并行时刻表，
 *                         单位通常为相对秒 [s]）。并列时取**首次出现**（严格 < / > 比较），
 *                         行为确定可复现。
 *                         用途：压力峰值出现时刻、温度最低点定位、批次内极值-时刻归档、
 *                         配合趋势图做极值标注。
 * 接口     (Interface)  : 输入 afSample 样本数组 [EU]、afStamp 时刻表 [s]（与样本一一对应）、
 *                         iCount 有效样本数 [个]（1..64）；
 *                         输出 fMin 最小值 [EU]、fMax 最大值 [EU]、
 *                         iMinIndex / iMaxIndex 极值下标 [1..iCount]、
 *                         fMinStamp / fMaxStamp 极值时刻 [s]、
 *                         bValid 结果可信标志、eErrCode（E_DL_StatsMmErr）；
 *                         返回值 = bValid（TRUE = 六个出口量均可信）。
 * 边界     (Boundary)   : ① 属主边界：只取极值与时刻，不做滑动窗口跨周期保持（跨周期归 FB）、
 *                         不做极值个数统计。
 *                         ② 样本数域闸 1..64：1 点合法（min = max = 该点，下标 1）。
 *                         ③ 非有限双判：afSample 与 afStamp **两表**全部有效元素逐个枚举，
 *                         任一非有限 → 故障级 eNonFinite。只查样本表而漏查时刻表，
 *                         会让极值时刻静默变成 NaN 却被判「成功」。
 *                         ④ 全常量样本（min = max）合法：两下标同为首次出现位置。
 *                         ⑤ 时刻表不要求单调递增（允许环形缓冲乱序），本件不做序校验。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StatsMeanStdDev` 分工：一二阶矩归那件、极值归本件；
 *                         与 `FB_DL_PeakHoldFilter` 分工：跨周期峰值保持归那件、
 *                         单批窗口极值归本件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 2×LREAL + 2×INT + 2×LREAL +
 *                         本文件内定义 enum E_DL_StatsMmErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸 + 双表全元素非有限双判 + 下标复检 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 17）
 * 验收向量 (Acceptance) : ① afSample=[5,2,9,4], afStamp=[0,1,2,3], iCount=4 →
 *                         fMin=2.0（下标 2，时刻 1.0）, fMax=9.0（下标 3，时刻 2.0）, eOk；
 *                         ② afSample=[7,7,7], afStamp=[0,1,2], iCount=3 →
 *                         fMin=fMax=7.0，两下标均 1（首次出现）, 时刻均 0.0；
 *                         ③ iCount=0 → 返回 FALSE, eBadCount, 各出口哨兵 0；
 *                         ④ afStamp[2]=NaN, iCount=4 → 返回 FALSE, eNonFinite（漏查时刻表的反例）；
 *                         ⑤ iCount=1, afSample=[3.5], afStamp=[10.0] → fMin=fMax=3.5，时刻 10.0。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StatsMmErr（窗口极值统计错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StatsMmErr :
(
    eOk        := 0,   // 信息级：统计完成 / Info: statistics computed
    eBadCount  := 1,   // 故障级：样本数越域 / Fault: sample count out of domain
    eNonFinite := 2,   // 故障级：样本或时刻含非有限值 / Fault: non-finite sample or stamp
    eInternal  := 9    // 故障级：极值下标越域（内部不一致） / Fault: extreme index out of domain
);
END_TYPE

FUNCTION FC_DL_StatsMinMaxWindow : BOOL
VAR_INPUT
    afSample : ARRAY[1..64] OF LREAL;  // 样本数组 [EU] / Sample array
    afStamp  : ARRAY[1..64] OF LREAL;  // 时刻表（与样本一一对应） [s] / Stamp table aligned with samples
    iCount   : INT;                    // 有效样本数（1..64） [个] / Valid sample count, 1..64
END_VAR
VAR_OUTPUT
    fMin      : LREAL;  // 最小值 [EU] / Minimum value
    fMax      : LREAL;  // 最大值 [EU] / Maximum value
    iMinIndex : INT;    // 最小值下标（首次出现） [1..iCount] / Minimum index, first occurrence
    iMaxIndex : INT;    // 最大值下标（首次出现） [1..iCount] / Maximum index, first occurrence
    fMinStamp : LREAL;  // 最小值发生时刻 [s] / Minimum stamp
    fMaxStamp : LREAL;  // 最大值发生时刻 [s] / Maximum stamp
    bValid    : BOOL;   // 结果可信标志 [-] / Result trustworthy flag
    eErrCode  : E_DL_StatsMmErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i         : INT;    // 样本遍历下标 [-] / Sample index
    _iMin      : INT;    // 最小值下标累计 [-] / Minimum index accumulator
    _iMax      : INT;    // 最大值下标累计 [-] / Maximum index accumulator
    _bNonFin   : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fMin      : LREAL;  // 最小值累计 [EU] / Minimum accumulator
    _fMax      : LREAL;  // 最大值累计 [EU] / Maximum accumulator
END_VAR
VAR CONSTANT
    DL_SMM_CNT_MIN : INT := 1;        // 样本数下限 [个] / Count lower bound
    DL_SMM_CNT_MAX : INT := 64;       // 样本数上限（数组容量） [个] / Count upper bound
    DL_SMM_ZERO    : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_SMM_ONE     : INT := 1;        // 起始下标（IEC 1 基） [-] / Start index, IEC one-based
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StatsMinMaxWindow := FALSE;                  // 返回值预置无效 / Return preset invalid
fMin      := DL_SMM_ZERO;                          // 最小值哨兵 / Minimum sentinel
fMax      := DL_SMM_ZERO;                          // 最大值哨兵 / Maximum sentinel
iMinIndex := 0;                                    // 最小值下标哨兵 / Minimum index sentinel
iMaxIndex := 0;                                    // 最大值下标哨兵 / Maximum index sentinel
fMinStamp := DL_SMM_ZERO;                          // 最小值时刻哨兵 / Minimum stamp sentinel
fMaxStamp := DL_SMM_ZERO;                          // 最大值时刻哨兵 / Maximum stamp sentinel
bValid    := FALSE;                                // 可信标志预置否 / Trust flag preset false
eErrCode  := E_DL_StatsMmErr.eBadCount;            // 预置最严码 / Preset strictest code

(* —— 段 1：样本数域闸 —— *)
IF (iCount < DL_SMM_CNT_MIN) OR (iCount > DL_SMM_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（样本表 + 时刻表双表逐项枚举） —— *)
_bNonFin := FALSE;
_i := 1;
WHILE _i <= iCount DO
    IF (afSample[_i] <> afSample[_i]) OR ((afSample[_i] - afSample[_i]) <> DL_SMM_ZERO) THEN
        _bNonFin := TRUE;                          // 样本非有限 / Sample non-finite
    END_IF
    IF (afStamp[_i] <> afStamp[_i]) OR ((afStamp[_i] - afStamp[_i]) <> DL_SMM_ZERO) THEN
        _bNonFin := TRUE;                          // 时刻非有限 / Stamp non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_StatsMmErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：极值扫描（严格比较 → 并列取首次出现） —— *)
_fMin  := afSample[DL_SMM_ONE];                    // 以首样本为初值 / Seed with first sample
_fMax  := afSample[DL_SMM_ONE];
_iMin  := DL_SMM_ONE;
_iMax  := DL_SMM_ONE;
_i     := 1;
WHILE _i <= iCount DO
    IF afSample[_i] < _fMin THEN
        _fMin := afSample[_i];                     // 更小值 / Smaller value
        _iMin := _i;
    END_IF
    IF afSample[_i] > _fMax THEN
        _fMax := afSample[_i];                     // 更大值 / Greater value
        _iMax := _i;
    END_IF
    _i := _i + 1;
END_WHILE

(* —— 段 4：下标复检（必须落在 1..iCount，否则判内部不一致） —— *)
IF (_iMin < DL_SMM_CNT_MIN) OR (_iMin > iCount) OR (_iMax < DL_SMM_CNT_MIN) OR (_iMax > iCount) THEN
    eErrCode := E_DL_StatsMmErr.eInternal;         // 故障级：下标越域 / Fault: index out of domain
    RETURN;
END_IF

(* —— 段 5：结果非有限复检（极值） —— *)
IF (_fMin <> _fMin) OR (_fMax <> _fMax) THEN
    eErrCode := E_DL_StatsMmErr.eNonFinite;
    RETURN;
END_IF

(* —— 段 6：成功出口（导出极值、下标与时刻） —— *)
fMin      := _fMin;
fMax      := _fMax;
iMinIndex := _iMin;
iMaxIndex := _iMax;
fMinStamp := afStamp[_iMin];                       // 极值时刻按下标回查 / Stamp looked up by index
fMaxStamp := afStamp[_iMax];
bValid    := TRUE;
eErrCode  := E_DL_StatsMmErr.eOk;                  // 信息级成功 / Info success
FC_DL_StatsMinMaxWindow := TRUE;                   // 统计可信 / Statistics trustworthy

END_FUNCTION
