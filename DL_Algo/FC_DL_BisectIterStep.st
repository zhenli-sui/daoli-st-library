(* ============================================================
   DL_Algo / FC_DL_BisectIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：二分法单步。括号 [fA,fB] 取中点后按单调方向 bIncreasing 与 fFa 符号
         保留含根半区（无函数指针，故以单调性假设选定半区）
   边界：两端同号（容差判零）/ 区间退化 / 任一入参非有限 → 新括号写 0（禁 NaN/Inf
         直穿出口）、bBrktLost=TRUE（N1：判据位与实值同源，不推进）
   依赖：仅 IEC 61131-3（ABS） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_BisectIterStep : BOOL
VAR_INPUT
    fA          : LREAL;  // 括号下界 [-] / Lower bracket bound
    fB          : LREAL;  // 括号上界 [-] / Upper bracket bound
    fFa         : LREAL;  // 下界函数值 [-] / Function value at the lower bound
    fFb         : LREAL;  // 上界函数值 [-] / Function value at the upper bound
    bIncreasing : BOOL;   // TRUE=f 单调递增 [-] / TRUE for a monotonically increasing residual
END_VAR
VAR_OUTPUT
    fAnew     : LREAL;  // 新括号下界 [-] / New lower bracket bound
    fBnew     : LREAL;  // 新括号上界 [-] / New upper bracket bound
    bBrktLost : BOOL;   // 括号失效或退化 [-] / Bracket lost or degenerate
END_VAR
VAR
    _fMid : LREAL;  // 中点 [-] / Midpoint of the bracket
END_VAR
VAR CONSTANT
    DL_BIS_EPS : LREAL := 1.0E-12;  // 区间退化与判零容差 [-] / Degeneracy and zero tolerance
END_VAR

(* 段 0：出口预置安全值（0，禁原始入参直穿出口，N3/R19） *)
FC_DL_BisectIterStep := FALSE;
fAnew := 0.0;  fBnew := 0.0;  bBrktLost := TRUE;

(* 段 1：非有限闸（NaN 自反 + Inf 差值自减，四入参全量枚举，R79/R272） *)
IF (fA <> fA) OR (fB <> fB) OR (fFa <> fFa) OR (fFb <> fFb) THEN RETURN; END_IF
IF ((fA - fA) <> (fA - fA)) OR ((fB - fB) <> (fB - fB))
   OR ((fFa - fFa) <> (fFa - fFa)) OR ((fFb - fFb) <> (fFb - fFb)) THEN RETURN; END_IF

(* 段 1b：闸后回传净化括号（此处起两入参已证有限，退化/同号分支可原样回传） *)
fAnew := fA;  fBnew := fB;

(* 段 1c：区间与判零闸 *)
IF ((fB - fA) - (fB - fA)) <> ((fB - fA) - (fB - fA)) THEN RETURN; END_IF
IF ABS(fB - fA) <= DL_BIS_EPS THEN RETURN; END_IF
IF (ABS(fFa) <= DL_BIS_EPS) OR (ABS(fFb) <= DL_BIS_EPS) THEN RETURN; END_IF

(* 段 2：括号有效性（fFa × fFb > 0 的同号判据，避免乘积溢出） *)
IF ((fFa > 0.0) AND (fFb > 0.0)) OR ((fFa < 0.0) AND (fFb < 0.0)) THEN RETURN; END_IF

(* 段 3：取中点并按单调方向保留含根半区 *)
_fMid := fA + (fB - fA) / 2.0;                // 中点式避免 fA+fB 溢出
IF bIncreasing THEN
    IF fFa < 0.0 THEN
        fAnew := _fMid;  fBnew := fB;         // 递增且下界为负：根在右半
    ELSE
        fAnew := fA;  fBnew := _fMid;
    END_IF
ELSE
    IF fFa < 0.0 THEN
        fAnew := fA;  fBnew := _fMid;         // 递减：半区反转
    ELSE
        fAnew := _fMid;  fBnew := fB;
    END_IF
END_IF

(* 段 4：单一出口裁决（N4） *)
bBrktLost := FALSE;  FC_DL_BisectIterStep := TRUE;
END_FUNCTION
