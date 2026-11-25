(*==============================================================================
 * 组件名称 (Component)  : FC_DL_InterpTwoPointSlope
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS），零厂商私有库
 * 功能描述 (Function)   : 两点定斜率线性插值 / 受限外推。
 *                           k  = (y2 - y1) / (x2 - x1)                 —— 由两点确定
 *                           y  = y1 + k × (xin - x1)                    —— 通用式（插值外推同一式）
 *                         外推保护：外推距离 = |xin - 近端节点 X|，若超过 fMaxExtrap
 *                         （默认 0.0 = 禁止外推，仅区间内插值），则把 xin 钳到
 *                         「近端节点 ± fMaxExtrap」后再取值，并置 bExtrapolated
 *                         与信息级 eExtrapClamped。**钳位的是 xin 而非 y**，
 *                         这样斜率信息仍可复用（调用方可用 fSlope 自行延续）。
 * 接口     (Interface)  : 输入 fX1/fY1 节点 1、fX2/fY2 节点 2、fXin 查询点、
 *                         fMaxExtrap 允许的最大外推距离 [X 单位，0 = 禁止外推]；
 *                         输出 fYout 结果 [Y 单位]、fSlope 斜率 [Y/X]、
 *                         bExtrapolated 是否发生外推、eErrCode（E_DL_InterpSlopeErr）；
 *                         返回值 = bValid 结果可信标志（TRUE = fYout 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做两点定斜率，不做多点表遍历、不做曲线拟合。
 *                         ② 全浮点入参（7 个）非有限双判，逐一枚举。
 *                         ③ 两点 X 重合（|x2-x1| < 1E-9）→ 故障级 eDegenerateNodes
 *                         （斜率无定义，禁止除零；**先判零后除**）。
 *                         ④ fMaxExtrap < 0 → 故障级 eBadParam（负外推距离无意义）。
 *                         ⑤ fMaxExtrap = 0 表示禁止外推：xin 越界即钳到节点 X，结果 = 端点 Y。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_InterpLogLinear` 分工：对数域归那件、线性域归本件；
 *                         与 `FC_DL_InterpHoldLast` 分工：保持型（不外推只保持）归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 2×LREAL + BOOL +
 *                         本文件内定义 enum E_DL_InterpSlopeErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 全入参非有限双判 + 两点 X 重合判零（除零防护）+ 外推距离上限 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 4）
 * 验收向量 (Acceptance) : ① fX1=0, fY1=0, fX2=10, fY2=100, fXin=5, fMaxExtrap=0 → k=10,
 *                         fYout=50.0, bExtrapolated=FALSE, eOk；
 *                         ② 同上, fXin=12, fMaxExtrap=5 → 外推 2 <= 5 → fYout=120.0, eExtrapolated；
 *                         ③ 同上, fXin=20, fMaxExtrap=5 → 钳 xin 到 15 → fYout=150.0, eExtrapClamped；
 *                         ④ fX1=fX2=5 → 返回 FALSE, fYout=0, eDegenerateNodes；
 *                         ⑤ fXin=0, fMaxExtrap=0 → fYout=0.0（左端外推钳到 x1）。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_InterpSlopeErr（两点定斜率插值错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_InterpSlopeErr :
(
    eOk             := 0,   // 信息级：区间内插值 / Info: in-range interpolation
    eExtrapolated   := 1,   // 信息级：受限外推（未超限） / Info: bounded extrapolation within limit
    eExtrapClamped  := 2,   // 信息级：外推超限已钳位 / Info: extrapolation clamped to limit
    eDegenerateNodes:= 3,   // 故障级：两点 X 重合，斜率无定义 / Fault: coincident X, undefined slope
    eBadParam       := 4,   // 故障级：外推距离参数为负 / Fault: negative extrapolation distance
    eNonFinite      := 5    // 故障级：入参非有限 / Fault: non-finite input
);
END_TYPE

FUNCTION FC_DL_InterpTwoPointSlope : BOOL
VAR_INPUT
    fX1        : LREAL;  // 节点 1 的 X [X 单位] / Node one X
    fY1        : LREAL;  // 节点 1 的 Y [Y 单位] / Node one Y
    fX2        : LREAL;  // 节点 2 的 X [X 单位] / Node two X
    fY2        : LREAL;  // 节点 2 的 Y [Y 单位] / Node two Y
    fXin       : LREAL;  // 查询点 X [X 单位] / Query X
    fMaxExtrap : LREAL;  // 允许的最大外推距离（0 = 禁止外推） [X 单位] / Max extrapolation distance, zero forbids
END_VAR
VAR_OUTPUT
    fYout         : LREAL;  // 插值 / 外推结果 [Y 单位] / Interpolated or extrapolated result
    fSlope        : LREAL;  // 两点定出的斜率 [Y/X 单位比] / Slope determined by the two nodes
    bExtrapolated : BOOL;   // 是否发生外推 [-] / Whether extrapolation occurred
    eErrCode      : E_DL_InterpSlopeErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 入参非有限标志 [-] / Non-finite input flag
    _fDx     : LREAL;  // X 方向增量 [X 单位] / X increment
    _fOut    : LREAL;  // 外推距离（带符号） [X 单位] / Signed extrapolation distance
    _fXUse   : LREAL;  // 钳位后实际使用的 X [-] / Actually used X after clamping
    _fLo     : LREAL;  // 允许区间左界 [X 单位] / Allowed lower bound
    _fHi     : LREAL;  // 允许区间右界 [X 单位] / Allowed upper bound
END_VAR
VAR CONSTANT
    DL_ITS_ZERO : LREAL := 0.0;     // 零基准 [-] / Zero base
    DL_ITS_TINY : LREAL := 1.0E-9;  // 两点 X 重合阈值 [X 单位] / Coincident X threshold
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_InterpTwoPointSlope := FALSE;                // 返回值预置无效 / Return preset invalid
fYout         := DL_ITS_ZERO;                      // 结果哨兵 0 / Result sentinel
fSlope        := DL_ITS_ZERO;                      // 斜率哨兵 0 / Slope sentinel
bExtrapolated := FALSE;                            // 外推标志预置否 / Extrapolation preset false
eErrCode      := E_DL_InterpSlopeErr.eBadParam;    // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（6 个浮点入参逐一枚举） —— *)
_bNonFin := (fX1 <> fX1) OR ((fX1 - fX1) <> DL_ITS_ZERO);            // X1 非有限 / X1 non-finite
_bNonFin := _bNonFin OR (fY1 <> fY1) OR ((fY1 - fY1) <> DL_ITS_ZERO); // Y1 非有限 / Y1 non-finite
_bNonFin := _bNonFin OR (fX2 <> fX2) OR ((fX2 - fX2) <> DL_ITS_ZERO); // X2 非有限 / X2 non-finite
_bNonFin := _bNonFin OR (fY2 <> fY2) OR ((fY2 - fY2) <> DL_ITS_ZERO); // Y2 非有限 / Y2 non-finite
_bNonFin := _bNonFin OR (fXin <> fXin) OR ((fXin - fXin) <> DL_ITS_ZERO);       // 查询点非有限 / Query non-finite
_bNonFin := _bNonFin OR (fMaxExtrap <> fMaxExtrap) OR ((fMaxExtrap - fMaxExtrap) <> DL_ITS_ZERO); // 外推上限非有限
IF _bNonFin THEN
    eErrCode := E_DL_InterpSlopeErr.eNonFinite;    // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：外推距离参数域闸（不得为负） —— *)
IF fMaxExtrap < DL_ITS_ZERO THEN
    eErrCode := E_DL_InterpSlopeErr.eBadParam;     // 故障级：参数非法 / Fault: illegal parameter
    RETURN;
END_IF

(* —— 段 3：两点 X 重合判零（先判零后做除法，R4 除零防护） —— *)
_fDx := fX2 - fX1;                                 // X 方向增量（分母） / X increment denominator
IF ABS(_fDx) < DL_ITS_TINY THEN
    eErrCode := E_DL_InterpSlopeErr.eDegenerateNodes;  // 故障级：斜率无定义 / Fault: undefined slope
    RETURN;                                        // 早退，杜绝除零 / Early exit, avoids division by zero
END_IF

(* —— 段 4：斜率计算 —— *)
fSlope := (fY2 - fY1) / _fDx;                      // k = dy / dx / Slope

(* —— 段 5：外推距离判定与钳位（钳 xin，不钳 y） —— *)
IF fXin < fX1 THEN
    _fOut := fX1 - fXin;                           // 左向外推距离（正数） / Left extrapolation distance
    IF _fOut > fMaxExtrap THEN
        _fXUse   := fX1 - fMaxExtrap;              // 钳到允许的最远点 / Clamp to farthest allowed point
        eErrCode := E_DL_InterpSlopeErr.eExtrapClamped;   // 信息级：超限钳位 / Info: clamped
    ELSE
        _fXUse   := fXin;                          // 未超限：原值使用 / Within limit: use as-is
        eErrCode := E_DL_InterpSlopeErr.eExtrapolated;    // 信息级：受限外推 / Info: bounded extrapolation
    END_IF
    bExtrapolated := TRUE;                         // 左向外推 / Left extrapolation
ELSIF fXin > fX2 THEN
    _fOut := fXin - fX2;                           // 右向外推距离（正数） / Right extrapolation distance
    IF _fOut > fMaxExtrap THEN
        _fXUse   := fX2 + fMaxExtrap;              // 钳到允许的最远点 / Clamp to farthest allowed point
        eErrCode := E_DL_InterpSlopeErr.eExtrapClamped;   // 信息级：超限钳位 / Info: clamped
    ELSE
        _fXUse   := fXin;                          // 未超限：原值使用 / Within limit: use as-is
        eErrCode := E_DL_InterpSlopeErr.eExtrapolated;    // 信息级：受限外推 / Info: bounded extrapolation
    END_IF
    bExtrapolated := TRUE;                         // 右向外推 / Right extrapolation
ELSE
    _fXUse        := fXin;                         // 区间内插值，无外推 / In-range interpolation
    bExtrapolated := FALSE;
    eErrCode      := E_DL_InterpSlopeErr.eOk;      // 信息级成功 / Info success
END_IF

(* —— 段 6：取值（插值与外推同一式） —— *)
fYout := fY1 + fSlope * (_fXUse - fX1);            // y = y1 + k*(x - x1)

(* —— 段 7：结果非有限复检兜底 —— *)
IF (fYout <> fYout) OR ((fYout - fYout) <> DL_ITS_ZERO) THEN
    fYout         := DL_ITS_ZERO;                  // 复检异常回哨兵 / Recheck failed: sentinel
    fSlope        := DL_ITS_ZERO;
    bExtrapolated := FALSE;
    eErrCode      := E_DL_InterpSlopeErr.eNonFinite;   // 故障级码 / Fault-level code
    RETURN;
END_IF

FC_DL_InterpTwoPointSlope := TRUE;                 // 结果有效 / Result valid

END_FUNCTION
