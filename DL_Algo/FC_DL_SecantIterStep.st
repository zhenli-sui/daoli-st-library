(* ============================================================
   DL_Algo / FC_DL_SecantIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：割线法单步（无导数、四点输入）：x = fX1 − fF1·(fX1−fX0)/(fF1−fF0)，
         并出位移 fDelta；uIter 透传，仅用于差分近零时的扰动方向（偶 +1/奇 −1）
   边界：差分 |fF1−fF0| ≤ 1E-12 → 退化，走相对尺度扰动步 MAX(|x|·1E-3, 1E-6)，
         保证不零步空转；非有限 → 新点/位移写 0（N1），bDegenerate=TRUE
   依赖：仅 IEC 61131-3（ABS / MAX / MOD） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SecantIterStep : BOOL
VAR_INPUT
    fX0   : LREAL;  // 前一点 [-] / Previous iterate
    fX1   : LREAL;  // 当前点 [-] / Current iterate
    fF0   : LREAL;  // 前一点函数值 [-] / Function value at the previous iterate
    fF1   : LREAL;  // 当前点函数值 [-] / Function value at the current iterate
    uIter : UDINT;  // 迭代序号（透传，仅定扰动方向）[-] / Iteration index passed through
END_VAR
VAR_OUTPUT
    fXnew       : LREAL;  // 割线外推新点 [-] / New secant iterate
    fDelta      : LREAL;  // 本步位移 = fXnew − fX1 [-] / Step displacement
    bDegenerate : BOOL;   // 差分近零或非有限 [-] / Degenerate slope or non-finite value
END_VAR
VAR
    _fDen    : LREAL;  // 差分 = fF1 − fF0 [-] / Difference of function values
    _fJitter : LREAL;  // 退化扰动步长 [-] / Jitter step used when the slope degenerates
END_VAR
VAR CONSTANT
    DL_SEC_EPS   : LREAL := 1.0E-12;  // 差分判零容差 [-] / Slope zero tolerance
    DL_SEC_REL   : LREAL := 1.0E-3;   // 扰动相对尺度系数 [-] / Relative jitter scale
    DL_SEC_FLOOR : LREAL := 1.0E-6;   // 扰动绝对下限 [-] / Absolute jitter floor
END_VAR

(* 段 0：出口预置安全侧（新点 0、位移 0、标退化，N1/N3） *)
FC_DL_SecantIterStep := FALSE;
fXnew := 0.0;  fDelta := 0.0;  bDegenerate := TRUE;

(* 段 1：非有限闸（四个浮点入参全量枚举：NaN 自反，R79/R272） *)
IF (fX0 <> fX0) OR (fX1 <> fX1) OR (fF0 <> fF0) OR (fF1 <> fF1) THEN RETURN; END_IF
(* 段 1b：Inf 双判必须覆盖 fX0/fF0 —— 只判 fX1/fF1 时 fF0=+Inf 使差分 −Inf，
   位移算成 0 却报 bDegenerate=FALSE 且返回 TRUE（静默零步空转） *)
IF ((fX0 - fX0) <> (fX0 - fX0)) OR ((fX1 - fX1) <> (fX1 - fX1))
   OR ((fF0 - fF0) <> (fF0 - fF0)) OR ((fF1 - fF1) <> (fF1 - fF1)) THEN RETURN; END_IF

(* 段 2：差分近零 → 相对尺度扰动（对称试探，防单侧卡死） *)
_fDen := fF1 - fF0;
IF ABS(_fDen) <= DL_SEC_EPS THEN
    _fJitter := MAX(ABS(fX1) * DL_SEC_REL, DL_SEC_FLOOR);
    IF (uIter MOD 2) = 0 THEN
        fXnew := fX1 + _fJitter;              // 偶序号向右
    ELSE
        fXnew := fX1 - _fJitter;              // 奇序号向左
    END_IF
    fDelta := fXnew - fX1;
    bDegenerate := TRUE;  FC_DL_SecantIterStep := TRUE;  RETURN;
END_IF

(* 段 3：割线外推（除子已证 |den| > EPS） *)
fXnew := fX1 - fF1 * (fX1 - fX0) / _fDen;
bDegenerate := FALSE;

(* 段 4：结果复检（非有限回退当前点，出口闸在最后，N4） *)
IF (fXnew <> fXnew) OR ((fXnew - fXnew) <> (fXnew - fXnew)) THEN
    fXnew := fX1;  fDelta := 0.0;  bDegenerate := TRUE;  RETURN;
END_IF
fDelta := fXnew - fX1;
FC_DL_SecantIterStep := TRUE;
END_FUNCTION
