(*==============================================================================
 * 组件名称 (Component)  : FC_DL_TableIndexBinarySearch
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : **升序**节点表二分查找定位（O(log n)），返回区间左端下标与段内比例。
 *                         迭代式二分：维护 [iLo, iHi] 使 afX[iLo] <= fXin <= afX[iHi]，
 *                         每次收缩一半，直到 iHi - iLo = 1，此时 iSeg = iLo。
 *                         32 点表最多 5 次迭代（2^5 = 32），循环上界显式封顶 8 次，
 *                         结构上不可能死循环（R6 周期安全：纯函数虽无跨周期状态，
 *                         仍对不可终止循环做硬保护）。
 *                         用途：大表（温压补偿、阀门口径选型）的高频查表，替代线性扫描。
 * 接口     (Interface)  : 输入 afX 升序节点表 [任意工程量]、iCount 有效点数 [个]（2..32）、
 *                         fXin 查询点 [同 afX 单位]；
 *                         输出 iSeg 区间左端下标 [1..iCount-1]、fRatio 段内比例 [0..1]、
 *                         bExact 是否恰命中节点、bClamped 越界钳位回执、
 *                         eErrCode（E_DL_TblBsearchErr）；
 *                         返回值 = bValid 定位可信标志（TRUE = iSeg/fRatio 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做定位，不做取值；表必须升序（降序表用
 *                         FC_DL_TableLookupDescending）。
 *                         ② 点数域闸 2..32；越域 → 故障级 eBadCount。
 *                         ③ 非有限双判：查询点 + 全部表元素逐项枚举（漏判单个元素会使比较静默失效）。
 *                         ④ 升序性校验：二分不校验全序，但会校验命中区间的两个端点是否满足
 *                         afX[iSeg] <= afX[iSeg+1]，违反即判 eTableNotAsc（防止强序假设）。
 *                         ⑤ 段宽近似零 → fRatio 置 0 并置信息级 eDegenerateSeg（除零防护）。
 *                         ⑥ 迭代次数硬上界 DL_TBC_ITER_MAX = 8，超出即判 eSearchOverflow
 *                         （理论上不可达，作为不可终止循环的兜底闸）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_TableLookupDescending` 分工：降序 / 线性归那件、
 *                         升序 / 二分归本件；与 `FC_DL_InterpSegmentWeight` 分工：
 *                         权重归那件、本件只给下标与比例。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + LREAL + 2×BOOL +
 *                         本文件内定义 enum E_DL_TblBsearchErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸 + 全表非有限双判 + 段宽判零 + 迭代次数硬上界 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机；循环不可终止风险由迭代上限拦截） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 5）
 * 验收向量 (Acceptance) : ① afX=[0,10,20,30], iCount=4, fXin=15 → iSeg=2,
 *                         fRatio=(15-10)/(20-10)=0.5, bExact=FALSE, bClamped=FALSE, eOk；
 *                         ② afX 同上, fXin=20 → iSeg=2（恰命中右端）, bExact=TRUE；
 *                         ③ afX 同上, fXin=-5 → iSeg=1, fRatio=0.0, bClamped=TRUE, eOk；
 *                         ④ afX 同上, fXin=100 → iSeg=3, fRatio=1.0, bClamped=TRUE, eOk；
 *                         ⑤ iCount=40 → 返回 FALSE, iSeg=0, eBadCount。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TblBsearchErr（升序表二分查找错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TblBsearchErr :
(
    eOk              := 0,   // 信息级：定位完成 / Info: located
    eDegenerateSeg   := 1,   // 信息级：段宽近似零，比例置 0 / Info: degenerate segment, ratio zeroed
    eBadCount        := 2,   // 故障级：点数越域 / Fault: point count out of domain
    eNonFinite       := 3,   // 故障级：查询点或表元素非有限 / Fault: query or table entry non-finite
    eTableNotAsc     := 4,   // 故障级：表不满足升序约定 / Fault: table violates ascending contract
    eSearchOverflow  := 5    // 故障级：迭代超上限（不可达兜底） / Fault: iteration overflow, unreachable guard
);
END_TYPE

FUNCTION FC_DL_TableIndexBinarySearch : BOOL
VAR_INPUT
    afX    : ARRAY[1..32] OF LREAL;  // 升序节点表 [任意工程量] / Ascending node table
    iCount : INT;                    // 有效点数（2..32） [个] / Valid point count, 2..32
    fXin   : LREAL;                  // 查询点 [同 afX 单位] / Query value
END_VAR
VAR_OUTPUT
    iSeg     : INT;    // 区间左端下标（1..iCount-1） [-] / Segment left index
    fRatio   : LREAL;  // 段内比例（0 = 左端，1 = 右端） [-] / In-segment ratio
    bExact   : BOOL;   // 是否恰命中节点 [-] / Whether a node was hit exactly
    bClamped : BOOL;   // 越界钳位回执 [-] / Out-of-range clamp receipt
    eErrCode : E_DL_TblBsearchErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i       : INT;    // 表元素遍历下标 [-] / Table traversal index
    _iLo     : INT;    // 二分下界 [-] / Binary search low bound
    _iHi     : INT;    // 二分上界 [-] / Binary search high bound
    _iMid    : INT;    // 二分中点 [-] / Binary search midpoint
    _iIter   : INT;    // 迭代计数 [-] / Iteration counter
    _bNonFin : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fDen    : LREAL;  // 段宽（分母） [-] / Segment width denominator
    _fRatio  : LREAL;  // 未钳位比例 [-] / Raw ratio
END_VAR
VAR CONSTANT
    DL_TBC_CNT_MIN  : INT := 2;        // 点数下限 [个] / Count lower bound
    DL_TBC_CNT_MAX  : INT := 32;       // 点数上限（数组容量） [个] / Count upper bound
    DL_TBC_ITER_MAX : INT := 8;        // 迭代次数硬上界（2^8 > 32） [次] / Hard iteration bound
    DL_TBC_TINY     : LREAL := 1.0E-9; // 段宽与命中近似零阈值 [-] / Degenerate and exact threshold
    DL_TBC_ZERO     : LREAL := 0.0;    // 零与比例下限 [-] / Zero and ratio lower bound
    DL_TBC_ONE      : LREAL := 1.0;    // 比例上限 [-] / Ratio upper bound
    DL_TBC_HALF     : INT := 2;        // 二分除数（整数除） [-] / Binary divisor, integer division
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_TableIndexBinarySearch := FALSE;             // 返回值预置无效 / Return preset invalid
iSeg     := 0;                                     // 下标哨兵 / Index sentinel
fRatio   := DL_TBC_ZERO;                           // 比例哨兵 / Ratio sentinel
bExact   := FALSE;                                 // 恰命中标志预置否 / Exact flag preset false
bClamped := FALSE;                                 // 钳位回执预置否 / Clamp receipt preset false
eErrCode := E_DL_TblBsearchErr.eBadCount;          // 预置最严码 / Preset strictest code

(* —— 段 1：点数域闸 —— *)
IF (iCount < DL_TBC_CNT_MIN) OR (iCount > DL_TBC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（查询点 + 全部表元素逐项枚举） —— *)
_bNonFin := (fXin <> fXin) OR ((fXin - fXin) <> DL_TBC_ZERO);
_i := 1;
WHILE _i <= iCount DO
    IF (afX[_i] <> afX[_i]) OR ((afX[_i] - afX[_i]) <> DL_TBC_ZERO) THEN
        _bNonFin := TRUE;
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_TblBsearchErr.eNonFinite;
    RETURN;
END_IF

(* —— 段 3：上下越界早退（钳到端段，避免二分越出下标域） —— *)
IF fXin <= afX[1] THEN
    iSeg     := 1;
    fRatio   := DL_TBC_ZERO;
    bClamped := TRUE;
    bExact   := (ABS(afX[1] - fXin) < DL_TBC_TINY);   // 恰落在首节点 / Exactly on first node
    eErrCode := E_DL_TblBsearchErr.eOk;
    FC_DL_TableIndexBinarySearch := TRUE;
    RETURN;
END_IF
IF fXin >= afX[iCount] THEN
    iSeg     := iCount - 1;
    fRatio   := DL_TBC_ONE;
    bClamped := TRUE;
    bExact   := (ABS(afX[iCount] - fXin) < DL_TBC_TINY);   // 恰落在末节点 / Exactly on last node
    eErrCode := E_DL_TblBsearchErr.eOk;
    FC_DL_TableIndexBinarySearch := TRUE;
    RETURN;
END_IF

(* —— 段 4：迭代式二分收缩（迭代次数硬上界，不可终止即兜底判错） —— *)
_iLo   := 1;
_iHi   := iCount;
_iIter := 0;
WHILE ((_iHi - _iLo) > 1) AND (_iIter < DL_TBC_ITER_MAX) DO
    _iMid := (_iLo + _iHi) / DL_TBC_HALF;          // 整数除取中点 / Integer midpoint
    IF fXin >= afX[_iMid] THEN
        _iLo := _iMid;                             // 抬下界 / Raise low bound
    ELSE
        _iHi := _iMid;                             // 压下界 / Lower high bound
    END_IF
    _iIter := _iIter + 1;
END_WHILE

IF (_iHi - _iLo) > 1 THEN
    eErrCode := E_DL_TblBsearchErr.eSearchOverflow; // 迭代未收敛：兜底判错 / Not converged: guard fault
    RETURN;
END_IF

(* —— 段 5：区间端点升序校验（防止强序假设静默失效） —— *)
IF afX[_iLo + 1] < afX[_iLo] THEN
    eErrCode := E_DL_TblBsearchErr.eTableNotAsc;   // 表不满足升序 / Table violates ascending contract
    RETURN;
END_IF

(* —— 段 6：段内比例计算（段宽判零） —— *)
_fDen := afX[_iLo + 1] - afX[_iLo];                // 升序段宽恒 >= 0 / Ascending segment width
IF ABS(_fDen) < DL_TBC_TINY THEN
    fRatio   := DL_TBC_ZERO;                       // 退化段：比例置 0 / Degenerate: ratio zero
    eErrCode := E_DL_TblBsearchErr.eDegenerateSeg; // 信息级码 / Info code
ELSE
    _fRatio  := (fXin - afX[_iLo]) / _fDen;        // 标准比例式 / Standard ratio
    fRatio   := MIN(MAX(_fRatio, DL_TBC_ZERO), DL_TBC_ONE);   // 显式约束 0..1 / Constrain 0..1
    eErrCode := E_DL_TblBsearchErr.eOk;            // 信息级成功 / Info success
END_IF
iSeg := _iLo;                                      // 导出下标 / Export index

(* —— 段 7：恰命中判定（两端节点任一在容差内） —— *)
bExact := (ABS(afX[_iLo] - fXin) < DL_TBC_TINY) OR (ABS(afX[_iLo + 1] - fXin) < DL_TBC_TINY);

(* —— 段 8：下标复检（必须落在 1..iCount-1） —— *)
IF (iSeg < 1) OR (iSeg > (iCount - 1)) THEN
    iSeg     := 0;
    fRatio   := DL_TBC_ZERO;
    bExact   := FALSE;
    eErrCode := E_DL_TblBsearchErr.eTableNotAsc;
    RETURN;
END_IF

FC_DL_TableIndexBinarySearch := TRUE;              // 定位有效 / Lookup valid

END_FUNCTION
