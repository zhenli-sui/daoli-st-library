(* ============================================================
   DL_Algo / FC_DL_RegulaFalsiIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：试位法（弦线法）单步：x = fA − fFa·(fB−fA)/(fFb−fFa) 并夹回括号；
         同时出「新点入括号后保守宽度上界」MAX(x−a, b−x)（本件不求值 f(x)）
   边界：差分 < fDenEps（含入参≤0 时取内部下限）或两端同号 → 退二分中点；
         任一入参非有限 → 新点写 0、宽度 0（N1：实值与判据同拍改写）
   依赖：仅 IEC 61131-3（ABS / MIN / MAX / LIMIT） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_RegulaFalsiIterStep : BOOL
VAR_INPUT
    fA      : LREAL;  // 括号下界 [-] / Lower bracket bound
    fB      : LREAL;  // 括号上界 [-] / Upper bracket bound
    fFa     : LREAL;  // 下界函数值 [-] / Function value at the lower bound
    fFb     : LREAL;  // 上界函数值 [-] / Function value at the upper bound
    fDenEps : LREAL;  // 差分下限（防零），建议 > 0 [-] / Minimum difference guarding the division
END_VAR
VAR_OUTPUT
    fXnew     : LREAL;  // 弦线插值新点（已夹回括号）[-] / Interpolated point clamped into the bracket
    fWidthNew : LREAL;  // 保守宽度上界 [-] / Conservative width upper bound
END_VAR
VAR
    _fDen  : LREAL;  // 弦线分母 = fFb − fFa [-] / Chord slope denominator
    _fEps  : LREAL;  // 生效判零下限 [-] / Effective denominator floor
    _fLo   : LREAL;  // 括号小端 [-] / Smaller bracket end
    _fHi   : LREAL;  // 括号大端 [-] / Larger bracket end
    _fMid  : LREAL;  // 二分中点 [-] / Bisection midpoint
END_VAR
VAR CONSTANT
    DL_RGZ_FLOOR : LREAL := 1.0E-12;  // 差分判零内部下限 [-] / Internal floor for the denominator
END_VAR

(* 段 0：出口预置安全侧（新点 0、宽度 0，防 NaN 直穿） *)
FC_DL_RegulaFalsiIterStep := FALSE;
fXnew := 0.0;  fWidthNew := 0.0;

(* 段 1：非有限闸（原始入参判定） *)
IF (fA <> fA) OR (fB <> fB) OR (fFa <> fFa) OR (fFb <> fFb) OR (fDenEps <> fDenEps) THEN
    RETURN;
END_IF
IF ((fB - fA) - (fB - fA)) <> ((fB - fA) - (fB - fA)) THEN RETURN; END_IF

(* 段 2：括号排序、中点与退化处理 *)
_fLo := MIN(fA, fB);  _fHi := MAX(fA, fB);
_fMid := _fLo + (_fHi - _fLo) / 2.0;
fXnew := _fMid;                               // 缺省即二分中点
IF (_fHi - _fLo) <= DL_RGZ_FLOOR THEN RETURN; END_IF

(* 段 3：分母与括号有效性（不可解均退二分，不置错） *)
IF fDenEps > DL_RGZ_FLOOR THEN _fEps := fDenEps; ELSE _fEps := DL_RGZ_FLOOR; END_IF
_fDen := fFb - fFa;
IF ABS(_fDen) <= _fEps THEN
    fWidthNew := MAX(_fMid - _fLo, _fHi - _fMid);
    FC_DL_RegulaFalsiIterStep := TRUE;  RETURN;
END_IF
IF ((fFa > 0.0) AND (fFb > 0.0)) OR ((fFa < 0.0) AND (fFb < 0.0)) THEN
    fWidthNew := MAX(_fMid - _fLo, _fHi - _fMid);   // 同号：括号失效，退二分
    FC_DL_RegulaFalsiIterStep := TRUE;  RETURN;
END_IF

(* 段 4：弦线插值并夹回括号（夹界即 N4 出口闸），除子已证 |den| > _fEps *)
fXnew := LIMIT(_fLo, fA - fFa * (fB - fA) / _fDen, _fHi);
fWidthNew := MAX(fXnew - _fLo, _fHi - fXnew);

(* 段 5：结果复检 *)
IF (fXnew <> fXnew) OR ((fXnew - fXnew) <> (fXnew - fXnew)) THEN
    fXnew := _fMid;  fWidthNew := 0.0;  RETURN;
END_IF
FC_DL_RegulaFalsiIterStep := TRUE;
END_FUNCTION
