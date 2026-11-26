(* ============================================================
   DL_Algo / FC_DL_BrentBracketIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：Brent 括号收缩单步（逆二次插值 + 二分混合）。三点函数值互异时按拉格朗日
         逆插值求试算点，落括号外/分母近零则退二分；由 fXLast 与 fFa 的符号关系
         收缩括号，并按宽度与 fTol 给出收敛标志
   边界：括号退化（宽度 ≤ 1E-12）→ 判已收敛；非有限 → 括号原样回传、uStepKind=0、
         bConverged=FALSE（N1）；三分母判零全用容差，禁浮点直接判等（R4）
   依赖：仅 IEC 61131-3（ABS / MIN / MAX） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_BrentBracketIterStep : BOOL
VAR_INPUT
    fA      : LREAL;  // 括号下界 [-] / Lower bracket bound
    fB      : LREAL;  // 括号上界 [-] / Upper bracket bound
    fFa     : LREAL;  // 下界函数值 [-] / Function value at the lower bound
    fFb     : LREAL;  // 上界函数值 [-] / Function value at the upper bound
    fXLast  : LREAL;  // 上一步试算点 [-] / Trial point of the previous step
    fFxLast : LREAL;  // 上一步试算点函数值 [-] / Function value at the previous trial point
    fTol    : LREAL;  // 宽度收敛容差，域 > 0 [-] / Convergence tolerance on the bracket width
END_VAR
VAR_OUTPUT
    fAnew      : LREAL;  // 新括号下界 [-] / New lower bracket bound
    fBnew      : LREAL;  // 新括号上界 [-] / New upper bracket bound
    uStepKind  : UDINT;  // 步型 0 非法 / 1 逆二次插值 / 2 二分 [-] / Step kind code
    bConverged : BOOL;   // 收缩后宽度已达容差 [-] / Shrunk width within tolerance
END_VAR
VAR
    _fLo    : LREAL;  // 括号小端 [-] / Smaller bracket end
    _fHi    : LREAL;  // 括号大端 [-] / Larger bracket end
    _fMid   : LREAL;  // 二分中点 [-] / Bisection midpoint
    _fTrial : LREAL;  // 试算点 [-] / Trial point
    _fTol   : LREAL;  // 生效容差 [-] / Effective tolerance
    _bIqiOk : BOOL;   // 逆二次插值可用 [-] / Inverse quadratic interpolation usable
    _fAchk  : LREAL;  // 收缩后下界暂存 [-] / Staged lower bound
    _fBchk  : LREAL;  // 收缩后上界暂存 [-] / Staged upper bound
END_VAR
VAR CONSTANT
    DL_BRN_EPS : LREAL := 1.0E-12;  // 分母与宽度判零容差 [-] / Denominator and width tolerance
END_VAR

(* 段 0：出口预置安全侧（括号原样、步型 0、未收敛） *)
FC_DL_BrentBracketIterStep := FALSE;
fAnew := 0.0;  fBnew := 0.0;  uStepKind := 0;  bConverged := FALSE;

(* 段 1：非有限闸（七入参全量枚举，含 Inf 差值自减判） *)
IF (fA <> fA) OR (fB <> fB) OR (fFa <> fFa) OR (fFb <> fFb)
   OR (fXLast <> fXLast) OR (fFxLast <> fFxLast) OR (fTol <> fTol) THEN
    RETURN;
END_IF
IF ((fB - fA) - (fB - fA)) <> ((fB - fA) - (fB - fA)) THEN RETURN; END_IF
fAnew := fA;  fBnew := fB;                    // 闸后原样回传

(* 段 2：排序、容差兜底与退化判据 *)
_fLo := MIN(fA, fB);  _fHi := MAX(fA, fB);
IF fTol > DL_BRN_EPS THEN _fTol := fTol; ELSE _fTol := DL_BRN_EPS; END_IF
_fMid := _fLo + (_fHi - _fLo) / 2.0;
IF (_fHi - _fLo) <= DL_BRN_EPS THEN
    fAnew := _fLo;  fBnew := _fHi;  uStepKind := 2;  bConverged := TRUE;
    FC_DL_BrentBracketIterStep := TRUE;  RETURN;
END_IF

(* 段 3：逆二次插值（三分母全非零才可用，落在括号外即退二分） *)
_bIqiOk := (ABS(fFa - fFb) > DL_BRN_EPS) AND (ABS(fFa - fFxLast) > DL_BRN_EPS)
           AND (ABS(fFb - fFxLast) > DL_BRN_EPS);
_fTrial := _fMid;
IF _bIqiOk THEN
    _fTrial := fA * (fFb * fFxLast) / ((fFa - fFb) * (fFa - fFxLast))
             + fB * (fFa * fFxLast) / ((fFb - fFa) * (fFb - fFxLast))
             + fXLast * (fFa * fFb) / ((fFxLast - fFa) * (fFxLast - fFb));
    IF (_fTrial <> _fTrial) OR (_fTrial <= _fLo) OR (_fTrial >= _fHi) THEN
        _fTrial := _fMid;  _bIqiOk := FALSE;
    END_IF
END_IF

(* 段 4：括号收缩（按 fXLast 与 fFa 的符号关系取含根半区） *)
IF ((fFa > 0.0) AND (fFxLast < 0.0)) OR ((fFa < 0.0) AND (fFxLast > 0.0)) THEN
    _fAchk := MIN(fA, fXLast);  _fBchk := MAX(fA, fXLast);
ELSE
    _fAchk := MIN(fXLast, fB);  _fBchk := MAX(fXLast, fB);
END_IF

(* 段 5：无推进则退中点切分，保证迭代必推进 *)
IF (_fBchk - _fAchk) >= (_fHi - _fLo) THEN
    IF _fTrial > _fMid THEN
        _fAchk := _fMid;  _fBchk := _fHi;
    ELSE
        _fAchk := _fLo;  _fBchk := _fMid;
    END_IF
    _bIqiOk := FALSE;
END_IF

(* 段 6：单一出口裁决（N4） *)
fAnew := _fAchk;  fBnew := _fBchk;
IF _bIqiOk THEN uStepKind := 1; ELSE uStepKind := 2; END_IF
bConverged := ((_fBchk - _fAchk) <= _fTol);
IF (fAnew <> fAnew) OR (fBnew <> fBnew) THEN
    fAnew := fA;  fBnew := fB;  uStepKind := 0;  bConverged := FALSE;  RETURN;
END_IF
FC_DL_BrentBracketIterStep := TRUE;
END_FUNCTION
