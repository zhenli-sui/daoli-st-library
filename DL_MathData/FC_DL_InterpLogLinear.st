(*==============================================================================
 * 组件名称 (Component)  : FC_DL_InterpLogLinear
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（LN / ABS），零厂商私有库
 * 功能描述 (Function)   : 对数-线性插值（X 取对数、Y 线性）：跨数量级工艺曲线插值。
 *                           y = y1 + (y2 - y1) × (LN(x) - LN(x1)) / (LN(x2) - LN(x1))
 *                         典型用途：流量-压差（孔板特性）、风机风量-静压、传感器对数刻度。
 *                         **适用域**：x1 > 0 且 x2 > 0 且 xin > 0（对数定义域），
 *                         任一为 0 或负 → 故障级 eOutOfLogDomain，**不静默取绝对值**。
 *                         xin 允许落在 [x1, x2] 之外的近邻区（线性于对数域外推），
 *                         但外推幅度受 fExtrapRatio 上限（默认 1.0，即最多外推一个
 *                         对数区间的宽度）钳制；超限钳位并置信息级 eExtrapClamped。
 * 接口     (Interface)  : 输入 fX1/fY1 左节点、fX2/fY2 右节点、fXin 查询点、
 *                         fExtrapRatio 允许的最大外推比例 [倍数，默认 1.0]；
 *                         输出 fYout 插值结果 [Y 单位]、fSel 实际使用的对数域位置比 [0..1+外推]、
 *                         bExtrapolated 是否发生外推、eErrCode（E_DL_InterpLogErr）；
 *                         返回值 = bValid 插值可信标志（TRUE = fYout 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做两点对数-线性插值，不做多点表遍历（表遍历归查表族）。
 *                         ② 全浮点入参（5 个）非有限双判，逐一枚举，漏一个即静默失效。
 *                         ③ 对数域闸：x1 <= 0 或 x2 <= 0 或 xin <= 0 → 故障级 eOutOfLogDomain。
 *                         ④ 对数区间宽度判零：|LN(x2)-LN(x1)| < 1E-12 → 故障级 eDegenerateSeg
 *                         （两节点 X 相同，插值无定义），避免除零。
 *                         ⑤ 外推上限：fExtrapRatio <= 0 视为非法参数 → 故障级 eBadParam。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_InterpTwoPointSlope` 分工：线性斜率外推归那件、
 *                         对数域插值归本件；与 `FC_DL_InterpHoldLast` 分工：保持型归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 2×LREAL + BOOL +
 *                         本文件内定义 enum E_DL_InterpLogErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 全入参非有限双判 + 对数域闸 + 对数区间判零 + 外推钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 3）
 * 验收向量 (Acceptance) : ① fX1=1, fY1=0, fX2=10, fY2=100, fXin=3.16227766（=√10）, fExtrapRatio=1.0 →
 *                         LN 位置比 = LN(3.16227766)/LN(10) = 0.5 → fYout = 50.0（容差 1E-6）；
 *                         ② 同上, fXin=1.0 → 位置比 0 → fYout = 0.0, bExtrapolated=FALSE；
 *                         ③ fX1=0 → 返回 FALSE, fYout=0, eOutOfLogDomain；
 *                         ④ fX1=5, fX2=5（区间退化）→ 返回 FALSE, eDegenerateSeg；
 *                         ⑤ fExtrapRatio=0.0 → 返回 FALSE, eBadParam。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_InterpLogErr（对数-线性插值错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_InterpLogErr :
(
    eOk             := 0,   // 信息级：插值完成，无外推 / Info: interpolated, no extrapolation
    eExtrapolated   := 1,   // 信息级：发生受限外推 / Info: bounded extrapolation performed
    eExtrapClamped  := 2,   // 信息级：外推超限已钳位 / Info: extrapolation clamped to limit
    eOutOfLogDomain := 3,   // 故障级：X 非正，超出对数定义域 / Fault: non-positive X, outside log domain
    eDegenerateSeg  := 4,   // 故障级：对数区间宽度为零 / Fault: zero log interval width
    eBadParam       := 5,   // 故障级：外推比例参数非法 / Fault: illegal extrapolation ratio parameter
    eNonFinite      := 6    // 故障级：入参非有限 / Fault: non-finite input
);
END_TYPE

FUNCTION FC_DL_InterpLogLinear : BOOL
VAR_INPUT
    fX1         : LREAL;  // 左节点 X（必须 > 0） [X 单位] / Left node X, must be positive
    fY1         : LREAL;  // 左节点 Y [Y 单位] / Left node Y
    fX2         : LREAL;  // 右节点 X（必须 > 0） [X 单位] / Right node X, must be positive
    fY2         : LREAL;  // 右节点 Y [Y 单位] / Right node Y
    fXin        : LREAL;  // 查询点（必须 > 0） [X 单位] / Query X, must be positive
    fExtrapRatio: LREAL;  // 允许的最大外推比例（对数区间宽度的倍数） [倍数] / Allowed extrapolation ratio
END_VAR
VAR_OUTPUT
    fYout         : LREAL;  // 插值结果 [Y 单位] / Interpolated result
    fSel          : LREAL;  // 对数域位置比（0 = 左节点，1 = 右节点） [-] / Position ratio in log domain
    bExtrapolated : BOOL;   // 是否发生外推 [-] / Whether extrapolation occurred
    eErrCode      : E_DL_InterpLogErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 入参非有限标志 [-] / Non-finite input flag
    _fL1     : LREAL;  // 左节点自然对数 [-] / Natural log of left node
    _fL2     : LREAL;  // 右节点自然对数 [-] / Natural log of right node
    _fLin    : LREAL;  // 查询点自然对数 [-] / Natural log of query
    _fDen    : LREAL;  // 对数区间宽度（分母） [-] / Log interval width denominator
    _fPos    : LREAL;  // 未钳位位置比 [-] / Raw position ratio
    _fLo     : LREAL;  // 位置比下界（负外推上限） [-] / Position lower bound
    _fHi     : LREAL;  // 位置比上界（正外推上限） [-] / Position upper bound
END_VAR
VAR CONSTANT
    DL_ILC_ZERO : LREAL := 0.0;    // 零与位置比左端 [-] / Zero and ratio origin
    DL_ILC_ONE  : LREAL := 1.0;    // 位置比右端 [-] / Ratio at right node
    DL_ILC_TINY : LREAL := 1.0E-12; // 对数区间宽度近似零阈值 [-] / Degenerate log width threshold
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_InterpLogLinear := FALSE;                    // 返回值预置无效 / Return preset invalid
fYout         := DL_ILC_ZERO;                      // 结果哨兵 0 / Result sentinel
fSel          := DL_ILC_ZERO;                      // 位置比哨兵 0 / Ratio sentinel
bExtrapolated := FALSE;                            // 外推标志预置否 / Extrapolation preset false
eErrCode      := E_DL_InterpLogErr.eBadParam;      // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（5 个浮点入参逐一枚举） —— *)
_bNonFin := (fX1 <> fX1) OR ((fX1 - fX1) <> DL_ILC_ZERO);            // X1 非有限 / X1 non-finite
_bNonFin := _bNonFin OR (fY1 <> fY1) OR ((fY1 - fY1) <> DL_ILC_ZERO); // Y1 非有限 / Y1 non-finite
_bNonFin := _bNonFin OR (fX2 <> fX2) OR ((fX2 - fX2) <> DL_ILC_ZERO); // X2 非有限 / X2 non-finite
_bNonFin := _bNonFin OR (fY2 <> fY2) OR ((fY2 - fY2) <> DL_ILC_ZERO); // Y2 非有限 / Y2 non-finite
_bNonFin := _bNonFin OR (fXin <> fXin) OR ((fXin - fXin) <> DL_ILC_ZERO);   // X 查询非有限 / Query non-finite
_bNonFin := _bNonFin OR (fExtrapRatio <> fExtrapRatio) OR ((fExtrapRatio - fExtrapRatio) <> DL_ILC_ZERO); // 外推比非有限
IF _bNonFin THEN
    eErrCode := E_DL_InterpLogErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：对数域闸（三个 X 均须严格为正） —— *)
IF (fX1 <= DL_ILC_ZERO) OR (fX2 <= DL_ILC_ZERO) OR (fXin <= DL_ILC_ZERO) THEN
    eErrCode := E_DL_InterpLogErr.eOutOfLogDomain; // 故障级：超出对数定义域 / Fault: outside log domain
    RETURN;
END_IF

(* —— 段 3：外推比例参数域闸（必须 > 0，否则外推窗无意义） —— *)
IF fExtrapRatio <= DL_ILC_ZERO THEN
    eErrCode := E_DL_InterpLogErr.eBadParam;       // 故障级：参数非法 / Fault: illegal parameter
    RETURN;
END_IF

(* —— 段 4：对数区间宽度计算与判零（防除零） —— *)
_fL1  := LN(fX1);                                  // 左节点对数 / Log of left node
_fL2  := LN(fX2);                                  // 右节点对数 / Log of right node
_fLin := LN(fXin);                                 // 查询点对数 / Log of query
_fDen := _fL2 - _fL1;                              // 对数区间宽度 / Log interval width
IF ABS(_fDen) < DL_ILC_TINY THEN
    eErrCode := E_DL_InterpLogErr.eDegenerateSeg;  // 故障级：区间退化 / Fault: degenerate interval
    RETURN;                                        // 早退，杜绝除零 / Early exit, avoids division by zero
END_IF

(* —— 段 5：位置比计算与受限外推钳位 —— *)
_fPos := (_fLin - _fL1) / _fDen;                   // 对数域位置比 / Position ratio in log domain
_fLo  := DL_ILC_ZERO - fExtrapRatio;               // 负外推上限 / Lower extrapolation bound
_fHi  := DL_ILC_ONE + fExtrapRatio;                // 正外推上限 / Upper extrapolation bound

IF _fPos < DL_ILC_ZERO THEN
    bExtrapolated := TRUE;                         // 负向外推 / Negative extrapolation
    IF _fPos < _fLo THEN
        _fPos    := _fLo;                          // 外推超限钳位 / Clamp extrapolation
        eErrCode := E_DL_InterpLogErr.eExtrapClamped;
    ELSE
        eErrCode := E_DL_InterpLogErr.eExtrapolated;
    END_IF
ELSIF _fPos > DL_ILC_ONE THEN
    bExtrapolated := TRUE;                         // 正向外推 / Positive extrapolation
    IF _fPos > _fHi THEN
        _fPos    := _fHi;                          // 外推超限钳位 / Clamp extrapolation
        eErrCode := E_DL_InterpLogErr.eExtrapClamped;
    ELSE
        eErrCode := E_DL_InterpLogErr.eExtrapolated;
    END_IF
ELSE
    bExtrapolated := FALSE;                        // 区间内正常插值 / Normal in-range interpolation
    eErrCode      := E_DL_InterpLogErr.eOk;
END_IF

(* —— 段 6：插值取值 —— *)
fYout       := fY1 + (fY2 - fY1) * _fPos;          // y = y1 + (y2-y1)*位置比 / Linear in Y over log position
fSel        := _fPos;                              // 导出位置比 / Export position ratio

(* —— 段 7：结果非有限复检兜底 —— *)
IF (fYout <> fYout) OR ((fYout - fYout) <> DL_ILC_ZERO) THEN
    fYout    := DL_ILC_ZERO;                       // 复检异常回哨兵 / Recheck failed: sentinel
    fSel     := DL_ILC_ZERO;
    eErrCode := E_DL_InterpLogErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF

FC_DL_InterpLogLinear := TRUE;                     // 插值有效 / Interpolation valid

END_FUNCTION
