(*
  Component : FC_DL_WortExtractYieldCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : 1.0.0            (* 版本 / Version *)
  功能      : 麦汁收得率核算：由麦汁体积与柏拉图度折算浸出物质量，除以麦芽投料量得收得率，并与理论收得率比较算糖化效率。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 麦汁体积、麦芽量、理论收得率须 > 1e-9，否则返回哨兵 -1（麦芽量为除子）；
              ② 柏拉图度域闸 0~30 °P，越界返回哨兵（经验密度式仅在啤酒麦汁区间可信）；
              ③ 糖化效率 = 实际收得率 / 理论收得率，不做上限钳位，便于暴露计量偏差。
*)
FUNCTION FC_DL_WortExtractYieldCalc : REAL
VAR_INPUT
    fWortVolL      : REAL;   (* 麦汁体积 [L] Wort volume *)
    fPlatoPct      : REAL;   (* 麦汁柏拉图度 [°P] Wort degrees Plato *)
    fMaltKg        : REAL;   (* 麦芽投料量 [kg] Malt charge *)
    fMaxYieldPct   : REAL;   (* 麦芽理论收得率 [%] Theoretical malt yield *)
    fTargetYieldPct: REAL;   (* 目标收得率 [%] Target yield *)
END_VAR
VAR_OUTPUT
    fWortDensKgL : REAL;   (* 麦汁密度 [kg/L] Wort density *)
    fExtractKg   : REAL;   (* 浸出物质量 [kg] Extract mass *)
    fYieldPct    : REAL;   (* 实际收得率 [%] Actual yield *)
    fBrewhouseEffPct : REAL;(* 糖化效率 [%] Brewhouse efficiency *)
    xBelowTarget : BOOL;   (* 收得率低于目标标志 [-] Below target flag *)
    xValid       : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_DENS_B0  : REAL := 1.004;    (* 密度式常数项 [kg/L] Density intercept *)
    DL_DENS_K   : REAL := 0.0038;   (* 密度式柏拉图度斜率 [kg/L per °P] Density slope *)
    DL_PLATO_MAX: REAL := 30.0;     (* 柏拉图度可表上限 [°P] Plato upper bound *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：六出口统一预置 *)
fWortDensKgL := 0.0; fExtractKg := 0.0; fYieldPct := 0.0; fBrewhouseEffPct := 0.0;
xBelowTarget := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fWortVolL <> fWortVolL) OR ((fWortVolL - fWortVolL) <> 0.0)
   OR (fPlatoPct <> fPlatoPct) OR ((fPlatoPct - fPlatoPct) <> 0.0)
   OR (fMaltKg <> fMaltKg) OR ((fMaltKg - fMaltKg) <> 0.0)
   OR (fMaxYieldPct <> fMaxYieldPct) OR ((fMaxYieldPct - fMaxYieldPct) <> 0.0) THEN
    FC_DL_WortExtractYieldCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：体积与麦芽量为比例基/除子，柏拉图度须落在经验式可表区间 *)
IF (fWortVolL <= DL_EPS) OR (fMaltKg <= DL_EPS) OR (fMaxYieldPct <= DL_EPS)
   OR (fPlatoPct < DL_ZERO) OR (fPlatoPct > DL_PLATO_MAX) THEN
    FC_DL_WortExtractYieldCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 麦汁密度经验式：[kg/L]，仅用于柏拉图度换算 *)
fWortDensKgL := DL_DENS_B0 + DL_DENS_K * fPlatoPct;
(* 浸出物质量：m = V · rho · °P/100 [kg] *)
fExtractKg := fWortVolL * fWortDensKgL * (fPlatoPct / DL_PCT_BASE);
(* 实际收得率：浸出物 / 麦芽投料量，除子麦芽量已过域闸 *)
fYieldPct := fExtractKg / fMaltKg * DL_PCT_BASE;
(* 糖化效率：实际 / 理论，理论收得率已过域闸 *)
fBrewhouseEffPct := fYieldPct / fMaxYieldPct * DL_PCT_BASE;
(* 与目标比较：低于目标即置标志，供班组调整糖化工艺 *)
xBelowTarget := fYieldPct < fTargetYieldPct;
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_WortExtractYieldCalc := fYieldPct;        (* 返回收得率 [%] / Return yield percent *)
END_FUNCTION
