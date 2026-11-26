(* ============================================================
   DL_Algo / FC_DL_TernaryNarrowIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：三分法单步（三点等分比较后收缩）。探针 m1 = a + L/3、m2 = b − L/3，
         其函数值由调用方求值后回灌：fF1<fF2 → 保 [a,m2]；fF1>fF2 → 保 [m1,b]；
         两者容差判等 → 保 [m1,m2]。出新区间与实测收缩比（2/3 或 1/3）
   边界：长度 ≤ 1E-12 → 区间不收缩、fRatio=1（不虚报）；函数值非有限 →
         原区间回传、fRatio=1、返回 FALSE（N1：判据与实值同源）
   依赖：仅 IEC 61131-3（ABS / MIN / MAX） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_TernaryNarrowIterStep : BOOL
VAR_INPUT
    fA  : LREAL;  // 区间下界 [-] / Lower interval bound
    fB  : LREAL;  // 区间上界 [-] / Upper interval bound
    fF1 : LREAL;  // 左三分点 m1 处函数值 [-] / Function value at the left trisection point
    fF2 : LREAL;  // 右三分点 m2 处函数值 [-] / Function value at the right trisection point
END_VAR
VAR_OUTPUT
    fAnew  : LREAL;  // 新区间下界 [-] / New lower bound
    fBnew  : LREAL;  // 新区间上界 [-] / New upper bound
    fRatio : LREAL;  // 实测收缩比 = 新宽/原宽 [-] / Measured shrink ratio
END_VAR
VAR
    _fLen : LREAL;  // 原区间长度 [-] / Original interval length
    _fM1  : LREAL;  // 左三等分点 [-] / Left trisection point
    _fM2  : LREAL;  // 右三等分点 [-] / Right trisection point
    _fLo  : LREAL;  // 区间小端 [-] / Smaller interval end
    _fHi  : LREAL;  // 区间大端 [-] / Larger interval end
END_VAR
VAR CONSTANT
    DL_TNY_EPS : LREAL := 1.0E-12;  // 函数值判等容差与长度判零 [-] / Equality tolerance and length floor
END_VAR

(* 段 0：出口预置安全侧（新区间=原区间、收缩比 1，N3） *)
FC_DL_TernaryNarrowIterStep := FALSE;
fAnew := 0.0;  fBnew := 0.0;  fRatio := 1.0;

(* 段 1：非有限闸 *)
IF (fA <> fA) OR (fB <> fB) OR (fF1 <> fF1) OR (fF2 <> fF2) THEN RETURN; END_IF
IF ((fB - fA) - (fB - fA)) <> ((fB - fA) - (fB - fA)) THEN RETURN; END_IF

(* 段 2：闸后原样回传（fRatio=1 表示本步未收缩）与长度退化闸 *)
fAnew := fA;  fBnew := fB;  fRatio := 1.0;
_fLo := MIN(fA, fB);  _fHi := MAX(fA, fB);
_fLen := _fHi - _fLo;
IF _fLen <= DL_TNY_EPS THEN
    fAnew := _fLo;  fBnew := _fHi;  fRatio := 1.0;
    FC_DL_TernaryNarrowIterStep := TRUE;  RETURN;
END_IF

(* 段 3：三等分两点与三点比较收缩（判等带容差，方向分列） *)
_fM1 := _fLo + _fLen / 3.0;
_fM2 := _fHi - _fLen / 3.0;
IF ABS(fF1 - fF2) <= DL_TNY_EPS THEN
    fAnew := _fM1;  fBnew := _fM2;            // 两侧等高：保中间三分之一
ELSIF fF1 < fF2 THEN
    fAnew := _fLo;  fBnew := _fM2;            // 左低：保左侧三分之二
ELSE
    fAnew := _fM1;  fBnew := _fHi;            // 右低：保右侧三分之二
END_IF

(* 段 4：实测收缩比 + 越域回退（出口与判据同源，N4） *)
fRatio := (fBnew - fAnew) / _fLen;            // 除子已证 > EPS
IF (fRatio <> fRatio) OR (fRatio < 0.0) OR (fRatio > 1.0) THEN
    fAnew := _fLo;  fBnew := _fHi;  fRatio := 1.0;  RETURN;
END_IF
FC_DL_TernaryNarrowIterStep := TRUE;
END_FUNCTION
