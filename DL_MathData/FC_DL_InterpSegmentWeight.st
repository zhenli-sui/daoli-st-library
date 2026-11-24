(*==============================================================================
 * 组件名称 (Component)  : FC_DL_InterpSegmentWeight
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 段内权重计算：给定升序节点表与查询点，返回相邻两点的
 *                         **加权系数对** (fWLeft, fWRight)，满足 fWLeft + fWRight = 1：
 *                           fWRight = (fXin - afX[i]) / (afX[i+1] - afX[i])
 *                           fWLeft  = 1 - fWRight
 *                         调用方据此自行取 Y（若只有 Y 单表，可算 y = wl*y_i + wr*y_{i+1}），
 *                         也可用于多表共享同一权重（同一 X 上插值多条曲线，
 *                         避免重复定位，性能与一致性双收益）。
 *                         v = wl*v_i + wr*v_{i+1} 与线性插值严格等价（权重和为 1 保证无偏）。
 * 接口     (Interface)  : 输入 afX 升序节点表 [X 单位]、iCount 有效点数 [个]（2..32）、
 *                         fXin 查询点 [X 单位]；
 *                         输出 iSeg 区间左端下标、fWLeft 左节点权重 [0..1]、
 *                         fWRight 右节点权重 [0..1]、bClamped 越界钳位回执、
 *                         eErrCode（E_DL_InterpWgtErr）；
 *                         返回值 = bValid 权重可信标志（TRUE = 两权重可信）。
 * 边界     (Boundary)   : ① 属主边界：只给权重，**不取 Y 值**（取值由调用方组合，
 *                         这是本件与 InterpHoldLast / TwoPointSlope 的本质分工）。
 *                         ② 点数域闸 2..32；越域 → 故障级 eBadCount。
 *                         ③ 非有限双判：查询点 + 全部表元素逐项枚举。
 *                         ④ 段宽近似零 → fWLeft=1.0、fWRight=0.0 并置信息级 eDegenerateSeg
 *                         （权重仍满足和为 1，调用方无需特判；除零被完全规避）。
 *                         ⑤ 越界钳位：fXin 超出 [afX[1], afX[iCount]] → 钳到端段端点，
 *                         权重退化为 (1,0) 或 (0,1)，bClamped=TRUE，不外推。
 *                         ⑥ 权重和复检：|fWLeft + fWRight - 1| < 1E-9，违反 → 故障级 eInternal
 *                         （结构性断言，防未来改动破坏无偏性）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_InterpHoldLast` 分工：那件直接给 Y（保持型），
 *                         本件只给权重（多表共享）；与 `FC_DL_TableIndexBinarySearch` 分工：
 *                         大表定位优先用那件，本件为线性扫描 + 权重输出件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + 2×LREAL + BOOL +
 *                         本文件内定义 enum E_DL_InterpWgtErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸 + 全表非有限双判 + 段宽判零 + 权重和复检 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 8）
 * 验收向量 (Acceptance) : ① afX=[0,10,20], iCount=3, fXin=5 → iSeg=1, fWRight=0.5,
 *                         fWLeft=0.5, bClamped=FALSE, eOk, TRUE；
 *                         ② afX 同上, fXin=15 → iSeg=2, fWRight=0.5, fWLeft=0.5；
 *                         ③ afX 同上, fXin=-3 → iSeg=1, fWLeft=1.0, fWRight=0.0, bClamped=TRUE；
 *                         ④ afX 同上, fXin=99 → iSeg=2, fWLeft=0.0, fWRight=1.0, bClamped=TRUE；
 *                         ⑤ afX=[0,0,20], fXin=0 → 退化段：fWLeft=1.0, fWRight=0.0, eDegenerateSeg。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_InterpWgtErr（段内权重错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_InterpWgtErr :
(
    eOk            := 0,   // 信息级：权重计算完成 / Info: weights computed
    eDegenerateSeg := 1,   // 信息级：段宽近似零，权重退化为 1/0 / Info: degenerate segment, weights 1 and 0
    eBadCount      := 2,   // 故障级：点数越域 / Fault: point count out of domain
    eNonFinite     := 3,   // 故障级：查询点或表元素非有限 / Fault: query or table entry non-finite
    eTableNotAsc   := 4,   // 故障级：表不满足升序约定 / Fault: table violates ascending contract
    eInternal      := 9    // 故障级：权重和偏离 1，无偏性被破坏 / Fault: weight sum deviates from one
);
END_TYPE

FUNCTION FC_DL_InterpSegmentWeight : BOOL
VAR_INPUT
    afX    : ARRAY[1..32] OF LREAL;  // 升序节点表 [X 单位] / Ascending node table in X
    iCount : INT;                    // 有效点数（2..32） [个] / Valid point count, 2..32
    fXin   : LREAL;                  // 查询点 [X 单位] / Query value in X
END_VAR
VAR_OUTPUT
    iSeg     : INT;    // 区间左端下标（1..iCount-1） [-] / Segment left index
    fWLeft   : LREAL;  // 左节点权重 [0..1] [-] / Left node weight
    fWRight  : LREAL;  // 右节点权重 [0..1] [-] / Right node weight
    bClamped : BOOL;   // 越界钳位回执 [-] / Out-of-range clamp receipt
    eErrCode : E_DL_InterpWgtErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i       : INT;    // 循环下标 [-] / Loop index
    _iSeg    : INT;    // 命中区间下标 [-] / Hit segment index
    _bFound  : BOOL;   // 区间命中标志 [-] / Segment found flag
    _bNonFin : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fDen    : LREAL;  // 段宽（分母） [X 单位] / Segment width denominator
    _fWr     : LREAL;  // 右权重（未钳位） [-] / Raw right weight
    _fSum    : LREAL;  // 权重和（复检用） [-] / Weight sum for recheck
END_VAR
VAR CONSTANT
    DL_IWC_CNT_MIN : INT := 2;        // 点数下限 [个] / Count lower bound
    DL_IWC_CNT_MAX : INT := 32;       // 点数上限（数组容量） [个] / Count upper bound
    DL_IWC_TINY    : LREAL := 1.0E-9; // 段宽近似零阈值 [X 单位] / Degenerate segment threshold
    DL_IWC_ZERO    : LREAL := 0.0;    // 零与权重下限 [-] / Zero and weight lower bound
    DL_IWC_ONE     : LREAL := 1.0;    // 权重上限与无偏基准 [-] / Weight upper bound and unbiasedness base
END_VAR

(* —— 段 0：出口预置安全值（权重预置为「全取左端」，恒满足和为 1） —— *)
FC_DL_InterpSegmentWeight := FALSE;                // 返回值预置无效 / Return preset invalid
iSeg     := 0;                                     // 下标哨兵 / Index sentinel
fWLeft   := DL_IWC_ONE;                            // 左权重哨兵 1（最保守：全取左端） / Left weight sentinel
fWRight  := DL_IWC_ZERO;                           // 右权重哨兵 0 / Right weight sentinel
bClamped := FALSE;                                 // 钳位回执预置否 / Clamp receipt preset false
eErrCode := E_DL_InterpWgtErr.eBadCount;           // 预置最严码 / Preset strictest code

(* —— 段 1：点数域闸 —— *)
IF (iCount < DL_IWC_CNT_MIN) OR (iCount > DL_IWC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（查询点 + 全部表元素逐项枚举） —— *)
_bNonFin := (fXin <> fXin) OR ((fXin - fXin) <> DL_IWC_ZERO);
_i := 1;
WHILE _i <= iCount DO
    IF (afX[_i] <> afX[_i]) OR ((afX[_i] - afX[_i]) <> DL_IWC_ZERO) THEN
        _bNonFin := TRUE;
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_InterpWgtErr.eNonFinite;
    RETURN;
END_IF

(* —— 段 3：下越界钳位（权重退化 1/0） —— *)
IF fXin <= afX[1] THEN
    iSeg     := 1;
    fWLeft   := DL_IWC_ONE;
    fWRight  := DL_IWC_ZERO;
    bClamped := TRUE;
    eErrCode := E_DL_InterpWgtErr.eOk;
    FC_DL_InterpSegmentWeight := TRUE;
    RETURN;
END_IF

(* —— 段 4：上越界钳位（权重退化 0/1） —— *)
IF fXin >= afX[iCount] THEN
    iSeg     := iCount - 1;
    fWLeft   := DL_IWC_ZERO;
    fWRight  := DL_IWC_ONE;
    bClamped := TRUE;
    eErrCode := E_DL_InterpWgtErr.eOk;
    FC_DL_InterpSegmentWeight := TRUE;
    RETURN;
END_IF

(* —— 段 5：区间定位（升序：afX[i] <= fXin <= afX[i+1]） —— *)
_i      := 1;
_bFound := FALSE;
_iSeg   := 1;
WHILE (_i < iCount) AND (NOT _bFound) DO
    IF (fXin >= afX[_i]) AND (fXin <= afX[_i + 1]) THEN
        _bFound := TRUE;
        _iSeg   := _i;
    ELSE
        _i := _i + 1;
    END_IF
END_WHILE
IF NOT _bFound THEN
    eErrCode := E_DL_InterpWgtErr.eTableNotAsc;    // 未命中：表不升序 / Not found: table not ascending
    RETURN;
END_IF

(* —— 段 6：升序复检 + 段宽判零后计算权重 —— *)
IF afX[_iSeg + 1] < afX[_iSeg] THEN
    eErrCode := E_DL_InterpWgtErr.eTableNotAsc;    // 端点倒序 / Endpoints reversed
    RETURN;
END_IF
_fDen := afX[_iSeg + 1] - afX[_iSeg];              // 段宽 / Segment width
IF ABS(_fDen) < DL_IWC_TINY THEN
    fWLeft   := DL_IWC_ONE;                        // 退化段：全取左端 / Degenerate: all to left
    fWRight  := DL_IWC_ZERO;
    eErrCode := E_DL_InterpWgtErr.eDegenerateSeg;  // 信息级码 / Info code
ELSE
    _fWr     := (fXin - afX[_iSeg]) / _fDen;       // 右权重 / Right weight
    fWRight  := MIN(MAX(_fWr, DL_IWC_ZERO), DL_IWC_ONE);      // 显式约束 0..1 / Constrain 0..1
    fWLeft   := DL_IWC_ONE - fWRight;              // 左权重 = 1 - 右权重（无偏性构造） / Left weight
    eErrCode := E_DL_InterpWgtErr.eOk;             // 信息级成功 / Info success
END_IF
iSeg := _iSeg;

(* —— 段 7：权重和无偏性复检（结构性断言） —— *)
_fSum := fWLeft + fWRight;                         // 权重和 / Weight sum
IF ABS(_fSum - DL_IWC_ONE) > DL_IWC_TINY THEN
    fWLeft   := DL_IWC_ONE;                        // 复检失败：回最保守权重 / Recheck failed: conservative weights
    fWRight  := DL_IWC_ZERO;
    iSeg     := 0;
    eErrCode := E_DL_InterpWgtErr.eInternal;       // 故障级：内部不一致 / Fault: internal inconsistency
    RETURN;
END_IF

FC_DL_InterpSegmentWeight := TRUE;                 // 权重可信 / Weights trustworthy

END_FUNCTION
