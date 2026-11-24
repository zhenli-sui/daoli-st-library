(*
  Component : FC_DL_MolassesExhaustionCalc
  Category  : DL_MathData
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : 废蜜纯度与糖分排出率核算：按糖膏纯度与废蜜纯度算糖分排出率（提净率）与随废蜜损失的糖分比例。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 糖膏纯度须 > 1e-9（为除子），否则返回哨兵 -1；
              ② 废蜜纯度高于糖膏纯度时排出率为负（数据异常），照实输出供诊断不钳位；
              ③ 两个纯度均须落在 0~100 % 理化可表区间。
*)
FUNCTION FC_DL_MolassesExhaustionCalc : REAL
VAR_INPUT
    fMassePurityPct   : REAL;   (* 糖膏（母液）纯度 [%] Massecuite purity *)
    fMolassesPurityPct: REAL;   (* 废蜜纯度 [%] Molasses purity *)
END_VAR
VAR_OUTPUT
    fExhaustPct : REAL;   (* 糖分排出率（提净率） [%] Exhaustion percent *)
    fLossPct    : REAL;   (* 随废蜜损失的糖分比例 [%] Sugar loss percent *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：三出口统一预置 *)
fExhaustPct := 0.0; fLossPct := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fMassePurityPct <> fMassePurityPct) OR ((fMassePurityPct - fMassePurityPct) <> 0.0)
   OR (fMolassesPurityPct <> fMolassesPurityPct)
   OR ((fMolassesPurityPct - fMolassesPurityPct) <> 0.0) THEN
    FC_DL_MolassesExhaustionCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 理化域闸：糖膏纯度为除子，两纯度须落在 0~100 % *)
IF (fMassePurityPct <= DL_EPS) OR (fMassePurityPct > DL_PCT_BASE)
   OR (fMolassesPurityPct < DL_ZERO) OR (fMolassesPurityPct > DL_PCT_BASE) THEN
    FC_DL_MolassesExhaustionCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 糖分排出率：(糖膏纯度 - 废蜜纯度) / 糖膏纯度，除子已过域闸 *)
fExhaustPct := (fMassePurityPct - fMolassesPurityPct) / fMassePurityPct * DL_PCT_BASE;
(* 糖分损失比例：废蜜纯度占糖膏纯度的份额 *)
fLossPct := fMolassesPurityPct / fMassePurityPct * DL_PCT_BASE;
xValid := TRUE;                           (* 链路有效 / Chain valid *)
FC_DL_MolassesExhaustionCalc := fExhaustPct;  (* 返回排出率 [%] / Return exhaustion percent *)
END_FUNCTION
