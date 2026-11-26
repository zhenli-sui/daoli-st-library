(* ============================================================
   DL_Motion / FC_DL_ArcCenterOffsetCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：由起点/终点/半径反解圆心相对起点偏移 [mm]；bCcw=TRUE 取劣弧（垂距正），
         FALSE 取优弧（垂距负）。弦向量左法向 × 垂距 h 即偏移。
   边界：半径<半弦长 或 起终点重合 → uErrId=1；半径≤0 或非有限 → uErrId=2，
         且实值出口同拍写 0（N1：判据与出口同源，禁 NaN 直穿）
   依赖：仅 IEC 61131-3（SQRT / MAX） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_ArcCenterOffsetCalc : BOOL
VAR_INPUT
    fX1       : LREAL;   // 起点 X 坐标 [mm] / Start point X in mm
    fY1       : LREAL;   // 起点 Y 坐标 [mm] / Start point Y in mm
    fX2       : LREAL;   // 终点 X 坐标 [mm] / End point X in mm
    fY2       : LREAL;   // 终点 Y 坐标 [mm] / End point Y in mm
    fRadiusMm : LREAL;   // 圆弧半径，有效域 > 0 [mm] / Arc radius, domain above zero
    bCcw      : BOOL;    // TRUE=劣弧（圆心在弦左）[-] / TRUE selects the minor arc
END_VAR
VAR_OUTPUT
    fDx    : LREAL;   // 圆心相对起点 X 偏移 [mm] / Center offset in X
    fDy    : LREAL;   // 圆心相对起点 Y 偏移 [mm] / Center offset in Y
    uErrId : UDINT;   // 出口码 0 正常 / 1 几何不可解 / 2 入参非法 [-] / Outlet code
    bOk    : BOOL;    // 结果可信标志，与返回值同源 [-] / Result trustworthy flag
END_VAR
VAR
    _fCx   : LREAL;  // 弦向量 X 分量 [mm] / Chord vector X component
    _fCy   : LREAL;  // 弦向量 Y 分量 [mm] / Chord vector Y component
    _fLen  : LREAL;  // 弦长 [mm] / Chord length
    _fHalf : LREAL;  // 半弦长 [mm] / Half chord length
    _fH    : LREAL;  // 圆心到弦中点垂距 [mm] / Perpendicular from chord midpoint to center
END_VAR
VAR CONSTANT
    DL_ARC_EPS : LREAL := 1.0E-9;  // 几何判零容差 [mm] / Geometric zero tolerance
END_VAR

(* 段 0：出口预置安全侧 + 非有限双判闸（NaN 自反 + Inf 差值自减，R79） *)
FC_DL_ArcCenterOffsetCalc := FALSE;
fDx := 0.0;  fDy := 0.0;  uErrId := 2;  bOk := FALSE;
IF (fX1 <> fX1) OR (fY1 <> fY1) OR (fX2 <> fX2) OR (fY2 <> fY2) OR (fRadiusMm <> fRadiusMm) THEN
    RETURN;                                          // NaN：判据与出口同源于原始入参（N1）
END_IF
IF ((fX1 - fX1) <> (fX1 - fX1)) OR ((fY1 - fY1) <> (fY1 - fY1))
   OR ((fX2 - fX2) <> (fX2 - fX2)) OR ((fY2 - fY2) <> (fY2 - fY2))
   OR ((fRadiusMm - fRadiusMm) <> (fRadiusMm - fRadiusMm)) THEN
    RETURN;                                          // ±Inf：半径 +Inf 会直穿到出口 ±Inf 并报码 0
END_IF

(* 段 1：弦向量、半弦长与退化判定 *)
_fCx := fX2 - fX1;  _fCy := fY2 - fY1;
_fLen := SQRT(_fCx * _fCx + _fCy * _fCy);
IF _fLen <> _fLen THEN RETURN; END_IF               // 弦长运算产生 NaN 的兜底（入参 Inf 已由段 0 拦截）
IF _fLen <= DL_ARC_EPS THEN uErrId := 1; RETURN; END_IF  // 起终点重合 / Coincident points
_fHalf := _fLen / 2.0;

(* 段 2：半径域闸与可解性 *)
IF fRadiusMm <= 0.0 THEN RETURN; END_IF
IF fRadiusMm < (_fHalf - DL_ARC_EPS) THEN uErrId := 1; RETURN; END_IF

(* 段 3：垂距与位移分量（劣弧取正、优弧取负） *)
_fH := SQRT(MAX(0.0, fRadiusMm * fRadiusMm - _fHalf * _fHalf));
IF bCcw THEN
    fDx := (_fCx / 2.0) + _fH * (0.0 - _fCy) / _fLen;
    fDy := (_fCy / 2.0) + _fH * _fCx / _fLen;
ELSE
    fDx := (_fCx / 2.0) - _fH * (0.0 - _fCy) / _fLen;
    fDy := (_fCy / 2.0) - _fH * _fCx / _fLen;
END_IF

(* 段 4：结果复检 + 单一出口裁决（N4：实值与 bOk 同源改写） *)
IF (fDx <> fDx) OR (fDy <> fDy)
   OR ((fDx - fDx) <> (fDx - fDx)) OR ((fDy - fDy) <> (fDy - fDy)) THEN
    fDx := 0.0;  fDy := 0.0;  uErrId := 2;  bOk := FALSE;  RETURN;
END_IF
uErrId := 0;  bOk := TRUE;  FC_DL_ArcCenterOffsetCalc := TRUE;
END_FUNCTION
