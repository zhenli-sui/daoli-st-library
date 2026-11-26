(* ============================================================
   DL_Motion / FC_DL_RtcpPivotOffsetCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：RTCP 摆动轴枢轴偏置在工件坐标系的三向分量 [mm]；
         刀具轴单位向量 v=(sinB·cosA, −sinA, cosA·cosB)，偏移 = L·(v − (0,0,1))
   边界：摆角先折叠到 (−180°,180°]，超 8 次折叠即钳位并置 bFolded；
         枢轴长度≤0 或非有限 → 三分量同步写 0、返回 FALSE（N1）
   依赖：仅 IEC 61131-3（SIN / COS） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_RtcpPivotOffsetCalc : BOOL
VAR_INPUT
    fPivotLenMm : LREAL;  // 枢轴长度（主轴端面到摆心）[mm] / Pivot length from face to swivel center
    fTiltADeg   : REAL;   // 摆动轴 A 角（绕 X）[deg] / Swivel axis A angle about X
    fTiltBDeg   : REAL;   // 摆动轴 B 角（绕 Y）[deg] / Swivel axis B angle about Y
END_VAR
VAR_OUTPUT
    fDxMm   : REAL;   // 枢轴偏置 X 分量 [mm] / Pivot offset in X
    fDyMm   : REAL;   // 枢轴偏置 Y 分量 [mm] / Pivot offset in Y
    fDzMm   : REAL;   // 枢轴偏置 Z 分量 [mm] / Pivot offset in Z
    bFolded : BOOL;   // 摆角发生 360° 折叠 [-] / Angle folding happened
END_VAR
VAR
    _fA   : LREAL;  // 折叠后 A 角 [deg] / Folded angle of axis A
    _fB   : LREAL;  // 折叠后 B 角 [deg] / Folded angle of axis B
    _fAr  : LREAL;  // A 角弧度值 [rad] / Angle A in radians
    _fBr  : LREAL;  // B 角弧度值 [rad] / Angle B in radians
    _nIdx : INT;    // 折叠循环索引（上限 8 防死循环）[-] / Bounded fold loop index
END_VAR
VAR CONSTANT
    DL_RTPV_PI : LREAL := 3.14159265358979324;  // 圆周率（LREAL 全精度）[-] / Pi at full precision
END_VAR

(* 段 0：出口预置安全侧 + 非有限闸 *)
FC_DL_RtcpPivotOffsetCalc := FALSE;
fDxMm := 0.0;  fDyMm := 0.0;  fDzMm := 0.0;  bFolded := FALSE;
IF (fPivotLenMm <> fPivotLenMm) OR (fTiltADeg <> fTiltADeg) OR (fTiltBDeg <> fTiltBDeg) THEN
    RETURN;
END_IF
IF (fPivotLenMm - fPivotLenMm) <> (fPivotLenMm - fPivotLenMm) THEN RETURN; END_IF
IF fPivotLenMm <= 0.0 THEN RETURN; END_IF               // 组态非法：三分量保持 0

(* 段 1：摆角折叠到 (−180°,180°]，次数有界（N2：折叠结果为当拍值） *)
_fA := REAL_TO_LREAL(fTiltADeg);
_fB := REAL_TO_LREAL(fTiltBDeg);
FOR _nIdx := 1 TO 8 DO
    IF _fA > 180.0 THEN
        _fA := _fA - 360.0;  bFolded := TRUE;
    ELSIF _fA <= -180.0 THEN
        _fA := _fA + 360.0;  bFolded := TRUE;
    END_IF
    IF _fB > 180.0 THEN
        _fB := _fB - 360.0;  bFolded := TRUE;
    ELSIF _fB <= -180.0 THEN
        _fB := _fB + 360.0;  bFolded := TRUE;
    END_IF
END_FOR
IF _fA > 180.0 THEN _fA := 180.0; END_IF                 // 超 8 次折叠仍越域：钳位
IF _fA < -180.0 THEN _fA := -180.0; END_IF
IF _fB > 180.0 THEN _fB := 180.0; END_IF
IF _fB < -180.0 THEN _fB := -180.0; END_IF

(* 段 2：角度换算弧度，三向分量 = L × (v − 单位 Z) *)
_fAr := _fA * DL_RTPV_PI / 180.0;
_fBr := _fB * DL_RTPV_PI / 180.0;
fDxMm := LREAL_TO_REAL(fPivotLenMm * (SIN(_fBr) * COS(_fAr)));
fDyMm := LREAL_TO_REAL(fPivotLenMm * (0.0 - SIN(_fAr)));
fDzMm := LREAL_TO_REAL(fPivotLenMm * (COS(_fAr) * COS(_fBr) - 1.0));

(* 段 3：结果复检 + 单一出口裁决（N4） *)
IF (fDxMm <> fDxMm) OR (fDyMm <> fDyMm) OR (fDzMm <> fDzMm) THEN
    fDxMm := 0.0;  fDyMm := 0.0;  fDzMm := 0.0;  RETURN;
END_IF
FC_DL_RtcpPivotOffsetCalc := TRUE;
END_FUNCTION
