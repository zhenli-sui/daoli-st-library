(*==============================================================================
 * 组件名称 (Component)  : FC_DL_TableReverseLookupX
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 由 Y 反查 X（单调表反解）。给定单调的 afY 表与对应 afX 表，
 *                         输入 fYin 反求 X：
 *                           ① 先做**全表单调性校验**：逐对比较相邻 afY，全升或全降才合法；
 *                             平坦段（|ΔY| < 1E-9）允许多个连续，但整表必须同向；
 *                           ② 再在 afY 中定位区间并按线性插值反解 X：
 *                              x = x_i + (x_{i+1} - x_i) × (yin - y_i) / (y_{i+1} - y_i)
 *                           ③ fYin 超出 afY 范围 → 钳到端点并置 bClamped（不外推，
 *                             反解外推在工艺上几乎总是错的）。
 *                         用途：由实测压力反查饱和温度、由输出反馈反查指令给定（阀位反解）。
 * 接口     (Interface)  : 输入 afY 单调表 [Y 单位]、afX 对应表 [X 单位]、
 *                         iCount 有效点数 [个]（2..32）、fYin 查询值 [Y 单位]；
 *                         输出 fXout 反解结果 [X 单位]、iSeg 区间下标、
 *                         bIncreasing 表是否升序（诊断）、bClamped 越界钳位回执、
 *                         eErrCode（E_DL_TblRevErr）；
 *                         返回值 = bValid 反解可信标志（TRUE = fXout 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单调表反解，不做非单调表的「多值择一」
 *                         （非单调 → 故障级 eNotMonotonic，**拒绝而非猜测**）。
 *                         ② 点数域闸 2..32；越域 → 故障级 eBadCount。
 *                         ③ 非有限双判：查询值 + afY 与 afX 双表全部元素逐项枚举。
 *                         ④ 段宽（ΔY）近似零 → 该段内反解取左端 X 并置信息级 eDegenerateSeg
 *                         （除零防护；平坦段反解本身欠定，取左端是确定性选择）。
 *                         ⑤ 单调性校验含符号一致性：先用首对非平坦段定方向，
 *                         后续任何反向段即判 eNotMonotonic。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_TableIndexBinarySearch` 分工：正查（X→区间）归那件、
 *                         反查（Y→X）归本件；与 `FC_DL_InterpHoldLast` 分工：
 *                         保持型正查归那件，本件同样禁止外推。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL + INT + 2×BOOL +
 *                         本文件内定义 enum E_DL_TblRevErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 双表全元素非有限双判 + ΔY 判零（除零防护）+ 单调性校验 + 越界钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 7）
 * 验收向量 (Acceptance) : ① afY=[0,100,200], afX=[0,10,20], iCount=3, fYin=150 →
 *                         bIncreasing=TRUE, iSeg=2, fXout=15.0（容差 1E-9）, eOk, TRUE；
 *                         ② afY=[200,100,0]（降序）, afX=[0,10,20], fYin=150 →
 *                         bIncreasing=FALSE, fXout=5.0（容差 1E-9）；
 *                         ③ afY=[0,100,200], fYin=999 → fXout=20.0（钳到末端点）, bClamped=TRUE；
 *                         ④ afY=[0,100,50]（非单调）→ 返回 FALSE, eNotMonotonic；
 *                         ⑤ fYin=NaN → 返回 FALSE, eNonFinite。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TblRevErr（单调表反解错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TblRevErr :
(
    eOk            := 0,   // 信息级：反解完成 / Info: reverse lookup done
    eDegenerateSeg := 1,   // 信息级：ΔY 近似零，取左端 X / Info: flat segment, left X used
    eBadCount      := 2,   // 故障级：点数越域 / Fault: point count out of domain
    eNonFinite     := 3,   // 故障级：任一入参或表元素非有限 / Fault: any input or table entry non-finite
    eNotMonotonic  := 4    // 故障级：表非单调，反解多值 / Fault: non-monotonic table, multiple solutions
);
END_TYPE

FUNCTION FC_DL_TableReverseLookupX : BOOL
VAR_INPUT
    afY    : ARRAY[1..32] OF LREAL;  // 单调值表 [Y 单位] / Monotonic value table in Y
    afX    : ARRAY[1..32] OF LREAL;  // 对应自变量表 [X 单位] / Corresponding argument table in X
    iCount : INT;                    // 有效点数（2..32） [个] / Valid point count, 2..32
    fYin   : LREAL;                  // 查询值 [Y 单位] / Query value in Y
END_VAR
VAR_OUTPUT
    fXout       : LREAL;  // 反解结果 [X 单位] / Reverse-solved X
    iSeg        : INT;    // 区间下标（1..iCount-1） [-] / Segment index
    bIncreasing : BOOL;   // 表是否升序（诊断） [-] / Whether the table is ascending
    bClamped    : BOOL;   // 越界钳位回执 [-] / Out-of-range clamp receipt
    eErrCode    : E_DL_TblRevErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i        : INT;    // 循环下标 [-] / Loop index
    _iSeg     : INT;    // 命中区间下标 [-] / Hit segment index
    _bFound   : BOOL;   // 区间命中标志 [-] / Segment found flag
    _bNonFin  : BOOL;   // 非有限标志 [-] / Non-finite flag
    _bInc     : BOOL;   // 方向已定标志 [-] / Direction determined flag
    _bUp      : BOOL;   // 方向：升序 = TRUE [-] / Direction, ascending equals TRUE
    _fDy      : LREAL;  // ΔY（分母） [Y 单位] / Delta Y denominator
    _fRatio   : LREAL;  // 段内比例 [-] / In-segment ratio
END_VAR
VAR CONSTANT
    DL_TRC_CNT_MIN : INT := 2;        // 点数下限 [个] / Count lower bound
    DL_TRC_CNT_MAX : INT := 32;       // 点数上限（数组容量） [个] / Count upper bound
    DL_TRC_TINY    : LREAL := 1.0E-9; // ΔY 近似零阈值（平坦段） [Y 单位] / Flat segment threshold
    DL_TRC_ZERO    : LREAL := 0.0;    // 零基准与比例下限 [-] / Zero base and ratio lower bound
    DL_TRC_ONE     : LREAL := 1.0;    // 比例上限 [-] / Ratio upper bound
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_TableReverseLookupX := FALSE;                // 返回值预置无效 / Return preset invalid
fXout       := DL_TRC_ZERO;                        // 结果哨兵 0 / Result sentinel
iSeg        := 0;                                  // 下标哨兵 / Index sentinel
bIncreasing := FALSE;                              // 方向标志预置否 / Direction preset false
bClamped    := FALSE;                              // 钳位回执预置否 / Clamp receipt preset false
eErrCode    := E_DL_TblRevErr.eBadCount;           // 预置最严码 / Preset strictest code

(* —— 段 1：点数域闸 —— *)
IF (iCount < DL_TRC_CNT_MIN) OR (iCount > DL_TRC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：非有限域闸（查询值 + afY 与 afX 双表逐项枚举） —— *)
_bNonFin := (fYin <> fYin) OR ((fYin - fYin) <> DL_TRC_ZERO);
_i := 1;
WHILE _i <= iCount DO
    IF (afY[_i] <> afY[_i]) OR ((afY[_i] - afY[_i]) <> DL_TRC_ZERO) THEN
        _bNonFin := TRUE;                          // Y 表元素非有限 / Y entry non-finite
    END_IF
    IF (afX[_i] <> afX[_i]) OR ((afX[_i] - afX[_i]) <> DL_TRC_ZERO) THEN
        _bNonFin := TRUE;                          // X 表元素非有限 / X entry non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_TblRevErr.eNonFinite;
    RETURN;
END_IF

(* —— 段 3：全表单调性校验（首对非平坦段定向，后续任一反向即判非单调） —— *)
_bInc   := FALSE;                                  // 方向尚未确定 / Direction not yet determined
_bUp    := TRUE;                                   // 方向暂定升序 / Direction provisionally ascending
_i      := 1;
WHILE _i < iCount DO
    _fDy := afY[_i + 1] - afY[_i];                 // 相邻差 / Adjacent difference
    IF ABS(_fDy) >= DL_TRC_TINY THEN
        IF NOT _bInc THEN
            _bInc := TRUE;                         // 首对非平坦段定方向 / First non-flat pair determines direction
            _bUp  := (_fDy > DL_TRC_ZERO);
        ELSE
            IF (_bUp AND (_fDy < DL_TRC_ZERO)) OR ((NOT _bUp) AND (_fDy > DL_TRC_ZERO)) THEN
                eErrCode := E_DL_TblRevErr.eNotMonotonic;   // 方向反转：非单调 / Direction reversal
                RETURN;
            END_IF
        END_IF
    END_IF
    _i := _i + 1;
END_WHILE
IF NOT _bInc THEN
    eErrCode := E_DL_TblRevErr.eNotMonotonic;      // 全表平坦：反解多值 / Fully flat: multiple solutions
    RETURN;
END_IF
bIncreasing := _bUp;                               // 导出方向诊断 / Export direction diagnostic

(* —— 段 4：越界钳位（低于首端 / 高于末端，均不外推） —— *)
IF _bUp THEN
    IF fYin <= afY[1] THEN
        fXout    := afX[1];
        iSeg     := 1;
        bClamped := TRUE;
        eErrCode := E_DL_TblRevErr.eOk;
        FC_DL_TableReverseLookupX := TRUE;
        RETURN;
    END_IF
    IF fYin >= afY[iCount] THEN
        fXout    := afX[iCount];
        iSeg     := iCount - 1;
        bClamped := TRUE;
        eErrCode := E_DL_TblRevErr.eOk;
        FC_DL_TableReverseLookupX := TRUE;
        RETURN;
    END_IF
ELSE
    IF fYin >= afY[1] THEN
        fXout    := afX[1];
        iSeg     := 1;
        bClamped := TRUE;
        eErrCode := E_DL_TblRevErr.eOk;
        FC_DL_TableReverseLookupX := TRUE;
        RETURN;
    END_IF
    IF fYin <= afY[iCount] THEN
        fXout    := afX[iCount];
        iSeg     := iCount - 1;
        bClamped := TRUE;
        eErrCode := E_DL_TblRevErr.eOk;
        FC_DL_TableReverseLookupX := TRUE;
        RETURN;
    END_IF
END_IF

(* —— 段 5：区间定位（按方向取包围区间） —— *)
_i      := 1;
_bFound := FALSE;
_iSeg   := 1;
WHILE (_i < iCount) AND (NOT _bFound) DO
    IF _bUp THEN
        IF (fYin >= afY[_i]) AND (fYin <= afY[_i + 1]) THEN
            _bFound := TRUE;
            _iSeg   := _i;
        END_IF
    ELSE
        IF (fYin <= afY[_i]) AND (fYin >= afY[_i + 1]) THEN
            _bFound := TRUE;
            _iSeg   := _i;
        END_IF
    END_IF
    IF NOT _bFound THEN
        _i := _i + 1;
    END_IF
END_WHILE
IF NOT _bFound THEN
    eErrCode := E_DL_TblRevErr.eNotMonotonic;      // 未命中：与单调性矛盾 / Not found: contradicts monotonicity
    RETURN;
END_IF

(* —— 段 6：ΔY 判零后反解（除零防护） —— *)
_fDy := afY[_iSeg + 1] - afY[_iSeg];               // ΔY / Delta Y
IF ABS(_fDy) < DL_TRC_TINY THEN
    fXout    := afX[_iSeg];                        // 平坦段：取左端 X（确定性选择） / Flat: deterministic left X
    eErrCode := E_DL_TblRevErr.eDegenerateSeg;     // 信息级码 / Info code
ELSE
    _fRatio  := (fYin - afY[_iSeg]) / _fDy;        // 段内比例 / In-segment ratio
    _fRatio  := MIN(MAX(_fRatio, DL_TRC_ZERO), DL_TRC_ONE);   // 显式约束 0..1 / Constrain 0..1
    fXout    := afX[_iSeg] + (afX[_iSeg + 1] - afX[_iSeg]) * _fRatio;   // 线性反解 X / Linear reverse solve
    eErrCode := E_DL_TblRevErr.eOk;                // 信息级成功 / Info success
END_IF
iSeg := _iSeg;

(* —— 段 7：结果非有限复检兜底 —— *)
IF (fXout <> fXout) OR ((fXout - fXout) <> DL_TRC_ZERO) THEN
    fXout    := DL_TRC_ZERO;
    iSeg     := 0;
    eErrCode := E_DL_TblRevErr.eNonFinite;
    RETURN;
END_IF

FC_DL_TableReverseLookupX := TRUE;                 // 反解有效 / Reverse lookup valid

END_FUNCTION
