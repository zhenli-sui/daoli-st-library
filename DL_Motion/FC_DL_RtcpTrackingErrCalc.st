(* ============================================================
   DL_Motion / FC_DL_RtcpTrackingErrCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：RTCP 下编程点与实绩点三维偏差模长 √(dX²+dY²+dZ²) [mm]：
         分量 = 编程 − 实绩；模长超 5 mm 门限置码 1（供上层降速/停机）
   边界：分量非有限 → 模长 0、码 2（N1：判据与出口同源改写）；门限≤0 → 码 3；
         平方和溢出为非有限 → 同走码 2
   依赖：仅 IEC 61131-3（SQRT） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_RtcpTrackingErrCalc : BOOL
VAR_INPUT
    fProgXmm : LREAL;  // 编程点 X [mm] / Programmed point X
    fProgYmm : LREAL;  // 编程点 Y [mm] / Programmed point Y
    fProgZmm : LREAL;  // 编程点 Z [mm] / Programmed point Z
    fActXmm  : LREAL;  // 实绩点 X [mm] / Actual point X
    fActYmm  : LREAL;  // 实绩点 Y [mm] / Actual point Y
    fActZmm  : LREAL;  // 实绩点 Z [mm] / Actual point Z
END_VAR
VAR_OUTPUT
    fErrMagMm : LREAL;  // 三维偏差模长 [mm] / Magnitude of the deviation
    uErrId    : UDINT;  // 出口码 0 正常 / 1 超差 / 2 非有限 / 3 门限非法 [-] / Outlet code
END_VAR
VAR
    _fDx  : LREAL;  // X 向分量 [mm] / Deviation component in X
    _fDy  : LREAL;  // Y 向分量 [mm] / Deviation component in Y
    _fDz  : LREAL;  // Z 向分量 [mm] / Deviation component in Z
    _fSum : LREAL;  // 三分量平方和 [mm²] / Sum of squared components
END_VAR
VAR CONSTANT
    DL_RTE_LIMIT : LREAL := 5.0;  // 跟踪误差门限 [mm] / Tracking error threshold
END_VAR

(* 段 0：出口预置安全侧 *)
FC_DL_RtcpTrackingErrCalc := FALSE;
fErrMagMm := 0.0;  uErrId := 2;

(* 段 1：非有限闸（六个入参全量枚举） *)
IF (fProgXmm <> fProgXmm) OR (fProgYmm <> fProgYmm) OR (fProgZmm <> fProgZmm)
   OR (fActXmm <> fActXmm) OR (fActYmm <> fActYmm) OR (fActZmm <> fActZmm) THEN
    RETURN;
END_IF
IF ((fProgXmm - fProgXmm) <> (fProgXmm - fProgXmm)) THEN RETURN; END_IF

(* 段 2：三分量与模长 *)
_fDx := fProgXmm - fActXmm;  _fDy := fProgYmm - fActYmm;  _fDz := fProgZmm - fActZmm;
_fSum := _fDx * _fDx + _fDy * _fDy + _fDz * _fDz;
IF (_fSum <> _fSum) OR ((_fSum - _fSum) <> (_fSum - _fSum)) OR (_fSum < 0.0) THEN
    RETURN;                                              // 平方和非有限或为负：结构性兜底
END_IF
fErrMagMm := SQRT(_fSum);

(* 段 3：门限判据（门限先过域闸，禁先夹量程再判超限）与出口裁决（N4） *)
IF DL_RTE_LIMIT <= 0.0 THEN
    uErrId := 3;
ELSIF fErrMagMm > DL_RTE_LIMIT THEN
    uErrId := 1;                                         // 超差：模长照给，返回 FALSE
ELSE
    uErrId := 0;  FC_DL_RtcpTrackingErrCalc := TRUE;
END_IF
END_FUNCTION
