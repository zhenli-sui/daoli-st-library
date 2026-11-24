(*==============================================================================
 * 组件名称 (Component)  : FC_DL_TableLookupDescending
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : **降序**节点表区间定位（返回区间下标 + 段内比例）。
 *                         适用场景：工艺曲线以「高压→低压」「高温→低温」顺序录入的表格
 *                         （与升序表件互为镜像，避免调用方每次传入前自行反转数组）。
 *                         定位规则：找到 i 使 afX[i] >= fXin >= afX[i+1]，返回
 *                         iSeg = i（区间左端下标）与 fRatio = (afX[i]-fXin)/(afX[i]-afX[i+1])
 *                         （0 = 落在左端节点，1 = 落在右端节点）。
 *                         越界处理：fXin 高于首节点 → iSeg=1、fRatio=0 并置 bClamped；
 *                         fXin 低于末节点 → iSeg=iCount-1、fRatio=1 并置 bClamped
 *                         （钳位语义：不外推，结果恒落在表端点上）。
 * 接口     (Interface)  : 输入 afX 降序节点表 [任意工程量]、iCount 有效点数 [个]（2..32）、
 *                         fXin 查询点 [同 afX 单位]；
 *                         输出 iSeg 区间左端下标 [1..iCount-1]、fRatio 段内比例 [0..1]、
 *                         bClamped 越界钳位回执、eErrCode（E_DL_TblDescErr）；
 *                         返回值 = bValid 定位可信标志（TRUE = iSeg/fRatio 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做定位，不做插值取值（取值归插值族），不修改表。
 *                         ② 点数域闸 2..32；越域 → 故障级 eBadCount。
 *                         ③ 非有限双判：fXin 与**全部参与判据的表元素**（1..iCount）逐个判，
 *                         任一非有限 → 故障级 eNonFinite（漏判单个元素会使距离/比较静默失效）。
 *                         ④ 降序性校验：定位循环未命中即判 eTableNotDesc（表录入违反降序约定），
 *                         不做「假设有序继续算」的静默容错。
 *                         ⑤ 段宽近似零（|afX[i]-afX[i+1]| < 1E-9）→ fRatio 置 0 并置信息级
 *                         eDegenerateSeg（退化段，避免除零；重复节点属录入缺陷需上游修）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_TableIndexBinarySearch`（升序 / O(log n)）互为镜像，
 *                         本件为降序线性扫描；与 `FC_DL_InterpSegmentWeight` 分工：
 *                         权重归那件，本件只给下标与比例。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + 2×LREAL + BOOL +
 *                         本文件内定义 enum E_DL_TblDescErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸 + 全表元素非有限双判 + 段宽判零 + 越界钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 1）
 * 验收向量 (Acceptance) : ① afX=[100,80,60,40], iCount=4, fXin=90 → 区间 1，
 *                         fRatio=(100-90)/(100-80)=0.5, bClamped=FALSE, eOk；
 *                         ② afX 同上, fXin=110 → iSeg=1, fRatio=0.0, bClamped=TRUE, eOk；
 *                         ③ afX 同上, fXin=10 → iSeg=3, fRatio=1.0, bClamped=TRUE, eOk；
 *                         ④ iCount=1 → 返回 FALSE, iSeg=0, eBadCount；
 *                         ⑤ afX=[100,80,90,40]（非降序）, fXin=85 → 返回 FALSE, eTableNotDesc。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TblDescErr（降序表定位错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TblDescErr :
(
    eOk             := 0,   // 信息级：定位完成 / Info: located
    eDegenerateSeg  := 1,   // 信息级：段宽近似零，比例已置 0 / Info: degenerate segment, ratio forced to zero
    eBadCount       := 2,   // 故障级：点数越域 / Fault: point count out of domain
    eNonFinite      := 3,   // 故障级：查询点或表元素非有限 / Fault: query or table entry non-finite
    eTableNotDesc   := 4    // 故障级：表不满足降序约定 / Fault: table violates descending contract
);
END_TYPE

FUNCTION FC_DL_TableLookupDescending : BOOL
VAR_INPUT
    afX    : ARRAY[1..32] OF LREAL;  // 降序节点表 [任意工程量] / Descending node table, any engineering unit
    iCount : INT;                    // 有效点数（2..32） [个] / Valid point count, 2..32
    fXin   : LREAL;                  // 查询点 [同 afX 单位] / Query value, same unit as afX
END_VAR
VAR_OUTPUT
    iSeg     : INT;    // 区间左端下标（1..iCount-1） [-] / Segment left index
    fRatio   : LREAL;  // 段内比例（0 = 左端节点，1 = 右端节点） [-] / In-segment ratio
    bClamped : BOOL;   // 越界钳位回执 [-] / Out-of-range clamp receipt
    eErrCode : E_DL_TblDescErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i        : INT;    // 循环下标 [-] / Loop index
    _bFound   : BOOL;   // 区间命中标志 [-] / Segment found flag
    _bNonFin  : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fDen     : LREAL;  // 段宽（分母） [-] / Segment width denominator
    _fRatioIn : LREAL;  // 未钳位比例 [-] / Raw ratio before clamping
END_VAR
VAR CONSTANT
    DL_TDC_CNT_MIN : INT := 2;        // 点数下限 [个] / Count lower bound
    DL_TDC_CNT_MAX : INT := 32;       // 点数上限（数组容量） [个] / Count upper bound, array capacity
    DL_TDC_TINY    : LREAL := 1.0E-9; // 段宽近似零阈值 [-] / Degenerate segment threshold
    DL_TDC_ZERO    : LREAL := 0.0;    // 零与比例下限 [-] / Zero and ratio lower bound
    DL_TDC_ONE     : LREAL := 1.0;    // 比例上限 [-] / Ratio upper bound
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_TableLookupDescending := FALSE;              // 返回值预置无效 / Return preset invalid
iSeg     := 0;                                     // 下标哨兵 0（非法下标） / Index sentinel zero
fRatio   := DL_TDC_ZERO;                           // 比例哨兵 0 / Ratio sentinel
bClamped := FALSE;                                 // 钳位回执预置否 / Clamp receipt preset false
eErrCode := E_DL_TblDescErr.eBadCount;             // 预置最严码 / Preset strictest code

(* —— 段 1：点数域闸（数组容量可表性反算） —— *)
IF (iCount < DL_TDC_CNT_MIN) OR (iCount > DL_TDC_CNT_MAX) THEN
    RETURN;                                        // 点数越域：保持故障码与哨兵 / Count out of domain
END_IF

(* —— 段 2：非有限域闸（查询点 + 全部参与判据的表元素逐项枚举） —— *)
_bNonFin := (fXin <> fXin) OR ((fXin - fXin) <> DL_TDC_ZERO);   // 查询点非有限 / Query non-finite
_i := 1;
WHILE _i <= iCount DO
    IF (afX[_i] <> afX[_i]) OR ((afX[_i] - afX[_i]) <> DL_TDC_ZERO) THEN
        _bNonFin := TRUE;                          // 表元素非有限 / Table entry non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_TblDescErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：上越界钳位（高于首节点：落于首段左端） —— *)
IF fXin >= afX[1] THEN
    iSeg     := 1;
    fRatio   := DL_TDC_ZERO;
    bClamped := TRUE;                              // 钳位回执 / Clamp receipt
    eErrCode := E_DL_TblDescErr.eOk;
    FC_DL_TableLookupDescending := TRUE;
    RETURN;
END_IF

(* —— 段 4：下越界钳位（低于末节点：落于末段右端） —— *)
IF fXin <= afX[iCount] THEN
    iSeg     := iCount - 1;
    fRatio   := DL_TDC_ONE;
    bClamped := TRUE;                              // 钳位回执 / Clamp receipt
    eErrCode := E_DL_TblDescErr.eOk;
    FC_DL_TableLookupDescending := TRUE;
    RETURN;
END_IF

(* —— 段 5：线性扫描定位区间（降序：afX[i] >= fXin >= afX[i+1]） —— *)
_i      := 1;
_bFound := FALSE;
WHILE (_i < iCount) AND (NOT _bFound) DO
    IF (fXin <= afX[_i]) AND (fXin >= afX[_i + 1]) THEN
        _bFound := TRUE;                           // 命中区间 / Segment hit
    ELSE
        _i := _i + 1;                              // 继续右移 / Advance
    END_IF
END_WHILE

IF NOT _bFound THEN
    eErrCode := E_DL_TblDescErr.eTableNotDesc;     // 表不满足降序约定 / Table violates descending contract
    RETURN;                                        // 保持哨兵输出 / Keep sentinel outputs
END_IF

(* —— 段 6：段内比例计算（段宽判零，退化段置 0） —— *)
_fDen := afX[_i] - afX[_i + 1];                    // 降序段宽恒 >= 0 / Descending segment width
IF ABS(_fDen) < DL_TDC_TINY THEN
    fRatio   := DL_TDC_ZERO;                       // 退化段：比例置 0，杜绝除零 / Degenerate: ratio zero, no division
    eErrCode := E_DL_TblDescErr.eDegenerateSeg;    // 信息级码 / Info code
ELSE
    _fRatioIn := (afX[_i] - fXin) / _fDen;         // (左端值 - 查询值) / 段宽 / Ratio formula
    fRatio    := MIN(MAX(_fRatioIn, DL_TDC_ZERO), DL_TDC_ONE);   // 显式约束 0..1 / Constrain into 0..1
    eErrCode  := E_DL_TblDescErr.eOk;              // 信息级成功 / Info success
END_IF
iSeg := _i;                                        // 导出区间左端下标 / Export left index

(* —— 段 7：结果复检（下标必须在 1..iCount-1，比例必须落在 0..1） —— *)
IF (iSeg < 1) OR (iSeg > (iCount - 1)) THEN
    iSeg     := 0;                                 // 下标复检失败回哨兵 / Index recheck failed
    fRatio   := DL_TDC_ZERO;
    eErrCode := E_DL_TblDescErr.eTableNotDesc;     // 保持故障级 / Keep fault-level
    RETURN;
END_IF

FC_DL_TableLookupDescending := TRUE;               // 定位有效 / Lookup valid

END_FUNCTION
