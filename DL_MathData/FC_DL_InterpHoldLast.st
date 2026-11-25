(*==============================================================================
 * 组件名称 (Component)  : FC_DL_InterpHoldLast
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 保持型查表（clamp / hold-at-ends 语义）：区间内线性插值，
 *                         **超出末节点保持末节点值，低于首节点保持首节点值，绝不外推**。
 *                         与 FC_DL_InterpTwoPointSlope（可受限外推）形成互补：
 *                         凡是外推会产出无物理意义值（负压力、负流量、超量程阀位）的场合，
 *                         一律用本件，宁可饱和到端点也不产生越界数。
 *                         用途：量程上下限饱和映射、传感器特性表端点延拓、执行器输出限幅映射。
 * 接口     (Interface)  : 输入 afX 升序节点表 [X 单位]、afY 对应值表 [Y 单位]、
 *                         iCount 有效点数 [个]（2..32）、fXin 查询点 [X 单位]；
 *                         输出 fYout 结果（恒在 [afY[1], afY[iCount]] 的包络内） [Y 单位]、
 *                         iSeg 区间下标（越界时为 1 或 iCount-1）[-]、
 *                         bHeld 是否发生端点保持、eErrCode（E_DL_InterpHoldErr）；
 *                         返回值 = bValid 结果可信标志（TRUE = fYout 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做保持型查表，**不做外推**（外推归 TwoPointSlope 件）。
 *                         ② 点数域闸 2..32；越域 → 故障级 eBadCount。
 *                         ③ 非有限双判：查询点 + afX 与 afY **两表**全部元素逐项枚举
 *                         （只查 afX 或只查 afY 都会让插值静默产出非有限值）。
 *                         ④ 段宽近似零 → 比例置 0（取左端值）并置信息级 eDegenerateSeg。
 *                         ⑤ 单调性校验：命中区间两端必须满足 afX[i] <= afX[i+1]，
 *                         违反 → 故障级 eTableNotAsc（不假设强序）。
 *                         ⑥ 结果复检：fYout 必须非有限外，且必须落在两端 afY 的闭包内
 *                         （插值性质保证，越出即说明表或比例异常 → eInternal）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_InterpTwoPointSlope` 分工：可外推归那件、保持归本件；
 *                         与 `FC_DL_TableIndexBinarySearch` 分工：定位归那件、取值归本件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL + INT + BOOL +
 *                         本文件内定义 enum E_DL_InterpHoldErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 双表全元素非有限双判 + 段宽判零 + 结果包络复检 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 6）
 * 验收向量 (Acceptance) : ① afX=[0,10,20], afY=[0,100,200], iCount=3, fXin=15 →
 *                         fYout=150.0, iSeg=2, bHeld=FALSE, eOk, TRUE；
 *                         ② 同上, fXin=100 → fYout=200.0（保持末值）, iSeg=2, bHeld=TRUE, eOk；
 *                         ③ 同上, fXin=-50 → fYout=0.0（保持首值）, iSeg=1, bHeld=TRUE, eOk；
 *                         ④ 同上, fXin=0 → fYout=0.0, iSeg=1, bHeld=FALSE（恰在首节点，非保持）；
 *                         ⑤ afY[2]=NaN → 返回 FALSE, fYout=0, eNonFinite。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_InterpHoldErr（保持型查表错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_InterpHoldErr :
(
    eOk            := 0,   // 信息级：区间内插值完成 / Info: in-range interpolation done
    eDegenerateSeg := 1,   // 信息级：段宽近似零，取左端值 / Info: degenerate segment, left value used
    eBadCount      := 2,   // 故障级：点数越域 / Fault: point count out of domain
    eNonFinite     := 3,   // 故障级：任一入参或表元素非有限 / Fault: any input or table entry non-finite
    eTableNotAsc   := 4,   // 故障级：表不满足升序约定 / Fault: table violates ascending contract
    eInternal      := 9    // 故障级：结果越出端点包络，内部不一致 / Fault: result outside endpoint envelope
);
END_TYPE

FUNCTION FC_DL_InterpHoldLast : BOOL
VAR_INPUT
    afX    : ARRAY[1..32] OF LREAL;  // 升序节点表 [X 单位] / Ascending node table in X
    afY    : ARRAY[1..32] OF LREAL;  // 对应值表 [Y 单位] / Corresponding value table in Y
    iCount : INT;                    // 有效点数（2..32） [个] / Valid point count, 2..32
    fXin   : LREAL;                  // 查询点 [X 单位] / Query value in X
END_VAR
VAR_OUTPUT
    fYout    : LREAL;  // 结果（恒在端点包络内） [Y 单位] / Result always inside endpoint envelope
    iSeg     : INT;    // 区间下标（越界时为端段） [-] / Segment index, end segment when held
    bHeld    : BOOL;   // 是否发生端点保持 [-] / Whether endpoint hold occurred
    eErrCode : E_DL_InterpHoldErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i       : INT;    // 循环下标 [-] / Loop index
    _iSeg    : INT;    // 命中区间下标 [-] / Hit segment index
    _bFound  : BOOL;   // 区间命中标志 [-] / Segment found flag
    _bNonFin : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fDen    : LREAL;  // 段宽（分母） [X 单位] / Segment width denominator
    _fRatio  : LREAL;  // 段内比例 [-] / In-segment ratio
    _fLo     : LREAL;  // 端点包络下界 [Y 单位] / Envelope lower bound
    _fHi     : LREAL;  // 端点包络上界 [Y 单位] / Envelope upper bound
END_VAR
VAR CONSTANT
    DL_IHC_CNT_MIN : INT := 2;        // 点数下限 [个] / Count lower bound
    DL_IHC_CNT_MAX : INT := 32;       // 点数上限（数组容量） [个] / Count upper bound
    DL_IHC_TINY    : LREAL := 1.0E-9; // 段宽近似零阈值 [-] / Degenerate segment threshold
    DL_IHC_ZERO    : LREAL := 0.0;    // 零与比例下限 [-] / Zero and ratio lower bound
    DL_IHC_ONE     : LREAL := 1.0;    // 比例上限 [-] / Ratio upper bound
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_InterpHoldLast := FALSE;                     // 返回值预置无效 / Return preset invalid
fYout    := DL_IHC_ZERO;                           // 结果哨兵 0 / Result sentinel
iSeg     := 0;                                     // 下标哨兵 / Index sentinel
bHeld    := FALSE;                                 // 保持标志预置否 / Hold flag preset false
eErrCode := E_DL_InterpHoldErr.eBadCount;          // 预置最严码 / Preset strictest code

(* —— 段 1：点数域闸 —— *)
IF (iCount < DL_IHC_CNT_MIN) OR (iCount > DL_IHC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（查询点 + afX 与 afY 双表逐项枚举） —— *)
_bNonFin := (fXin <> fXin) OR ((fXin - fXin) <> DL_IHC_ZERO);
_i := 1;
WHILE _i <= iCount DO
    IF (afX[_i] <> afX[_i]) OR ((afX[_i] - afX[_i]) <> DL_IHC_ZERO) THEN
        _bNonFin := TRUE;                          // X 表元素非有限 / X entry non-finite
    END_IF
    IF (afY[_i] <> afY[_i]) OR ((afY[_i] - afY[_i]) <> DL_IHC_ZERO) THEN
        _bNonFin := TRUE;                          // Y 表元素非有限 / Y entry non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_InterpHoldErr.eNonFinite;
    RETURN;
END_IF

(* —— 段 3：端点保持分支（低于首节点 / 高于末节点，均不外推） —— *)
IF fXin < afX[1] THEN
    fYout    := afY[1];                            // 保持首节点值 / Hold first node value
    iSeg     := 1;
    bHeld    := TRUE;
    eErrCode := E_DL_InterpHoldErr.eOk;
    FC_DL_InterpHoldLast := TRUE;
    RETURN;
END_IF
IF fXin > afX[iCount] THEN
    fYout    := afY[iCount];                       // 保持末节点值 / Hold last node value
    iSeg     := iCount - 1;
    bHeld    := TRUE;
    eErrCode := E_DL_InterpHoldErr.eOk;
    FC_DL_InterpHoldLast := TRUE;
    RETURN;
END_IF

(* —— 段 4：区间定位（升序：afX[i] <= fXin <= afX[i+1]） —— *)
_i      := 1;
_bFound := FALSE;
_iSeg   := 1;
WHILE (_i < iCount) AND (NOT _bFound) DO
    IF (fXin >= afX[_i]) AND (fXin <= afX[_i + 1]) THEN
        _bFound := TRUE;
        _iSeg   := _i;                             // 记录命中区间 / Record hit segment
    ELSE
        _i := _i + 1;
    END_IF
END_WHILE
IF NOT _bFound THEN
    eErrCode := E_DL_InterpHoldErr.eTableNotAsc;   // 未命中：表不满足升序 / Not found: table not ascending
    RETURN;
END_IF

(* —— 段 5：区间升序复检 + 段内比例计算（段宽判零） —— *)
IF afX[_iSeg + 1] < afX[_iSeg] THEN
    eErrCode := E_DL_InterpHoldErr.eTableNotAsc;   // 端点倒序 / Endpoints reversed
    RETURN;
END_IF
_fDen := afX[_iSeg + 1] - afX[_iSeg];              // 段宽 / Segment width
IF ABS(_fDen) < DL_IHC_TINY THEN
    _fRatio  := DL_IHC_ZERO;                       // 退化段取左端 / Degenerate: use left node
    eErrCode := E_DL_InterpHoldErr.eDegenerateSeg; // 信息级码 / Info code
ELSE
    _fRatio  := (fXin - afX[_iSeg]) / _fDen;       // 标准比例 / Standard ratio
    eErrCode := E_DL_InterpHoldErr.eOk;            // 信息级成功 / Info success
END_IF
_fRatio := MIN(MAX(_fRatio, DL_IHC_ZERO), DL_IHC_ONE);   // 显式约束 0..1 / Constrain 0..1

(* —— 段 6：线性插值取值 —— *)
fYout := afY[_iSeg] + (afY[_iSeg + 1] - afY[_iSeg]) * _fRatio;
iSeg  := _iSeg;
bHeld := FALSE;                                    // 区间内不属保持 / In-range, not a hold

(* —— 段 7：结果复检（非有限 + 端点包络） —— *)
IF (fYout <> fYout) OR ((fYout - fYout) <> DL_IHC_ZERO) THEN
    fYout    := DL_IHC_ZERO;
    iSeg     := 0;
    eErrCode := E_DL_InterpHoldErr.eNonFinite;
    RETURN;
END_IF
_fLo := MIN(afY[_iSeg], afY[_iSeg + 1]);           // 包络下界 / Envelope lower bound
_fHi := MAX(afY[_iSeg], afY[_iSeg + 1]);           // 包络上界 / Envelope upper bound
IF (fYout < _fLo) OR (fYout > _fHi) THEN
    fYout    := DL_IHC_ZERO;                       // 越出包络：内部不一致 / Outside envelope: internal fault
    iSeg     := 0;
    eErrCode := E_DL_InterpHoldErr.eInternal;
    RETURN;
END_IF

FC_DL_InterpHoldLast := TRUE;                      // 结果有效 / Result valid

END_FUNCTION
