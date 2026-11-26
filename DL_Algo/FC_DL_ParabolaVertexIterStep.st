(* ============================================================
   DL_Algo / FC_DL_ParabolaVertexIterStep ｜ v1.0.0 ｜ 2026-11-25
   功能：抛物线插值顶点步。三点唯一确定抛物线，顶点横坐标
         xv = 0.5·[x1²(f2−f3)+x2²(f3−f1)+x3²(f1−f2)] / [x1(f2−f3)+x2(f3−f1)+x3(f1−f2)]；
         二阶系数 a（>0 为极小）由三点差商式给出，出 fCurv
   边界：横坐标重合（|Δx|≤1E-12）或分母近零（三点共线）→ bDegenerate=TRUE，
         fXv 取三点横坐标中位数、fCurv=0（N1：判据位与实值同源置位）
   依赖：仅 IEC 61131-3（ABS / MIN / MAX） ｜ 溯源：DLF-B-ROOTSTEP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_ParabolaVertexIterStep : BOOL
VAR_INPUT
    fX1 : LREAL;  // 第一点横坐标 [-] / Abscissa of the first point
    fX2 : LREAL;  // 第二点横坐标 [-] / Abscissa of the second point
    fX3 : LREAL;  // 第三点横坐标 [-] / Abscissa of the third point
    fF1 : LREAL;  // 第一点函数值 [-] / Function value of the first point
    fF2 : LREAL;  // 第二点函数值 [-] / Function value of the second point
    fF3 : LREAL;  // 第三点函数值 [-] / Function value of the third point
END_VAR
VAR_OUTPUT
    fXv         : LREAL;  // 顶点横坐标 [-] / Abscissa of the parabola vertex
    fCurv       : REAL;   // 二阶系数 a（>0 极小 / <0 极大）[-] / Quadratic coefficient
    bDegenerate : BOOL;   // 三点共线或横坐标重合 [-] / Collinear points or repeated abscissae
END_VAR
VAR
    _fNum  : LREAL;  // 顶点公式分子 [-] / Numerator of the vertex formula
    _fDen  : LREAL;  // 顶点公式分母 [-] / Denominator of the vertex formula
    _fDx12 : LREAL;  // x1 − x2 [-] / Difference of the first and second abscissae
    _fDx13 : LREAL;  // x1 − x3 [-] / Difference of the first and third abscissae
    _fDx23 : LREAL;  // x2 − x3 [-] / Difference of the second and third abscissae
    _fMid  : LREAL;  // 三点横坐标中位数 [-] / Median abscissa
END_VAR
VAR CONSTANT
    DL_PRV_EPS : LREAL := 1.0E-12;  // 分母判零容差 [-] / Denominator zero tolerance
END_VAR

(* 段 0：出口预置安全侧（顶点 0、曲率 0、标退化，N1/N3） *)
FC_DL_ParabolaVertexIterStep := FALSE;
fXv := 0.0;  fCurv := 0.0;  bDegenerate := TRUE;

(* 段 1：非有限闸（六个入参全量枚举） *)
IF (fX1 <> fX1) OR (fX2 <> fX2) OR (fX3 <> fX3)
   OR (fF1 <> fF1) OR (fF2 <> fF2) OR (fF3 <> fF3) THEN
    RETURN;
END_IF

(* 段 2：横坐标互异判据（三点必须互异） *)
_fDx12 := fX1 - fX2;  _fDx13 := fX1 - fX3;  _fDx23 := fX2 - fX3;
_fMid := MAX(MIN(fX1, fX2), MIN(MAX(fX1, fX2), fX3));   // 三数中位数
fXv := _fMid;                                          // 退化出口先落中位数
IF (ABS(_fDx12) <= DL_PRV_EPS) OR (ABS(_fDx13) <= DL_PRV_EPS) OR (ABS(_fDx23) <= DL_PRV_EPS) THEN
    RETURN;
END_IF

(* 段 3：顶点分子/分母与三点共线判据 *)
_fNum := fX1 * fX1 * (fF2 - fF3) + fX2 * fX2 * (fF3 - fF1) + fX3 * fX3 * (fF1 - fF2);
_fDen := fX1 * (fF2 - fF3) + fX2 * (fF3 - fF1) + fX3 * (fF1 - fF2);
IF ABS(_fDen) <= DL_PRV_EPS THEN RETURN; END_IF           // 共线：无唯一顶点

(* 段 4：顶点与二阶系数（除子已证非零） *)
fXv := 0.5 * _fNum / _fDen;
fCurv := LREAL_TO_REAL((fF1 * _fDx23 + fF2 * (fX3 - fX1) + fF3 * _fDx12)
        / (_fDx12 * _fDx13 * _fDx23));

(* 段 5：结果复检（判据位与实值同源，N4） *)
IF (fXv <> fXv) OR ((fXv - fXv) <> (fXv - fXv)) OR (fCurv <> fCurv) THEN
    fXv := _fMid;  fCurv := 0.0;  bDegenerate := TRUE;  RETURN;
END_IF
bDegenerate := FALSE;  FC_DL_ParabolaVertexIterStep := TRUE;
END_FUNCTION
