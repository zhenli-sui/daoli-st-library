(* ============================================================
   DL_Algo / FC_DL_GoldenSectionIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：黄金分割单步（纯几何探针发生器）：两内探针
         fX1 = b − 0.618·L、fX2 = a + 0.618·L；一次收缩后宽度 = 0.618·L；
         函数值由调用方在探针点求值后回灌（本件无函数指针，R16 只出探针）
   边界：区间退化（L ≤ 1E-12）→ 探针归到 a 端、宽度 0、bConverged=TRUE；
         fTol ≤ 0 取内部下限 1E-12（防未缩小即判收敛）；非有限 → 探针与宽度写 0、
         不置收敛（N1：实值与判据同拍落安全侧）
   依赖：仅 IEC 61131-3（MIN） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_GoldenSectionIterStep : BOOL
VAR_INPUT
    fA   : LREAL;  // 区间下界 [-] / Lower interval bound
    fB   : LREAL;  // 区间上界 [-] / Upper interval bound
    fTol : LREAL;  // 宽度收敛容差，域 > 0 [-] / Convergence tolerance on the interval width
END_VAR
VAR_OUTPUT
    fX1        : LREAL;  // 左探针点 [-] / Left probe point
    fX2        : LREAL;  // 右探针点 [-] / Right probe point
    fWidthNew  : LREAL;  // 一次收缩后的区间宽度 [-] / Interval width after one shrink
    bConverged : BOOL;   // 收缩后宽度已达容差 [-] / Shrunk width within tolerance
END_VAR
VAR
    _fLen : LREAL;  // 原区间长度 [-] / Original interval length
    _fTol : LREAL;  // 生效容差 [-] / Effective tolerance
END_VAR
VAR CONSTANT
    DL_GSD_PHI   : LREAL := 6.18033988749894848E-1;  // 1/φ（全精度）[-] / Golden ratio reciprocal
    DL_GSD_FLOOR : LREAL := 1.0E-12;                 // 容差与长度判零下限 [-] / Floor for tolerance and length
END_VAR

(* 段 0：出口预置安全侧（探针与宽度 0、不置收敛，N1/N3） *)
FC_DL_GoldenSectionIterStep := FALSE;
fX1 := 0.0;  fX2 := 0.0;  fWidthNew := 0.0;  bConverged := FALSE;

(* 段 1：非有限闸 + 容差兜底 *)
IF (fA <> fA) OR (fB <> fB) OR (fTol <> fTol) THEN RETURN; END_IF
IF ((fB - fA) - (fB - fA)) <> ((fB - fA) - (fB - fA)) THEN RETURN; END_IF
IF fTol > DL_GSD_FLOOR THEN _fTol := fTol; ELSE _fTol := DL_GSD_FLOOR; END_IF

(* 段 2：区间退化 → 探针塌缩到端点并判收敛 *)
_fLen := fB - fA;
IF _fLen <= DL_GSD_FLOOR THEN
    fX1 := fA;  fX2 := fA;  fWidthNew := 0.0;  bConverged := TRUE;
    FC_DL_GoldenSectionIterStep := TRUE;  RETURN;
END_IF

(* 段 3：两内探针（0.618 与 0.382 对称布置）与收缩宽度 *)
fX1 := fB - DL_GSD_PHI * _fLen;
fX2 := fA + DL_GSD_PHI * _fLen;
fWidthNew := DL_GSD_PHI * _fLen;
bConverged := (fWidthNew <= _fTol);

(* 段 4：结果复检（出口闸位于最后一次赋值之后，N4） *)
IF (fX1 <> fX1) OR (fX2 <> fX2) OR (fWidthNew <> fWidthNew) THEN
    fX1 := 0.0;  fX2 := 0.0;  fWidthNew := 0.0;  bConverged := FALSE;  RETURN;
END_IF
FC_DL_GoldenSectionIterStep := TRUE;
END_FUNCTION
