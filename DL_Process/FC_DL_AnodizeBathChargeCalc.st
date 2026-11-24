(*
  Component : FC_DL_AnodizeBathChargeCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 阳极氧化槽法拉第电量核算：Q = I·t，换算电量密度与膜厚，并按电流效率由目标膜厚反算所需时间。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 氧化面积、电流效率、单位电量膜厚系数须 > 1e-9 且效率不超过 100 %，否则返回哨兵 -1；
              ② 电流为 0 时膜厚为 0 且反算时间回 0（合法空工况，xValid 置真）；
              ③ 反算时间不下发负值，目标膜厚 <= 0 时直接回 0。
*)
FUNCTION FC_DL_AnodizeBathChargeCalc : REAL
VAR_INPUT
    fCurrentA     : REAL;   (* 整流器输出电流 [A] Rectifier output current *)
    fAreaDm2      : REAL;   (* 氧化有效面积 [dm²] Effective anodizing area *)
    fTimeS        : REAL;   (* 通电时长 [s] Energizing time *)
    fEffPct       : REAL;   (* 电流效率 [%] Current efficiency *)
    fUmPerAsDm2   : REAL;   (* 单位电量膜厚系数 [μm/(A·s/dm²)] Film thickness per charge density *)
    fThickTargetUm: REAL;   (* 目标膜厚 [μm] Target film thickness *)
END_VAR
VAR_OUTPUT
    fChargeC       : REAL;  (* 累计电量 [C] Accumulated charge *)
    fChgDensAsDm2  : REAL;  (* 电量密度 [A·s/dm²] Charge density *)
    fFilmUm        : REAL;  (* 实测对应膜厚 [μm] Film thickness from charge *)
    fTimeForTargetS: REAL;  (* 达目标膜厚所需时间 [s] Time to reach target thickness *)
    xValid         : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fDensADm2 : REAL;   (* 电流密度 [A/dm²] Current density *)
    fEffUnit  : REAL;   (* 效率折算系数 [-] Efficiency as fraction *)
END_VAR
(* 出口预置：五出口统一预置 *)
fChargeC := 0.0; fChgDensAsDm2 := 0.0; fFilmUm := 0.0; fTimeForTargetS := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fCurrentA <> fCurrentA) OR ((fCurrentA - fCurrentA) <> 0.0)
   OR (fAreaDm2 <> fAreaDm2) OR ((fAreaDm2 - fAreaDm2) <> 0.0)
   OR (fTimeS <> fTimeS) OR ((fTimeS - fTimeS) <> 0.0)
   OR (fEffPct <> fEffPct) OR ((fEffPct - fEffPct) <> 0.0)
   OR (fUmPerAsDm2 <> fUmPerAsDm2) OR ((fUmPerAsDm2 - fUmPerAsDm2) <> 0.0) THEN
    FC_DL_AnodizeBathChargeCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：面积与系数为除子/比例基，电流与时长须非负，效率须在 (0,100] *)
IF (fAreaDm2 <= DL_EPS) OR (fUmPerAsDm2 <= DL_EPS) OR (fEffPct <= DL_ZERO)
   OR (fEffPct > DL_PCT_BASE) OR (fCurrentA < DL_ZERO) OR (fTimeS < DL_ZERO) THEN
    FC_DL_AnodizeBathChargeCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
fEffUnit := fEffPct / DL_PCT_BASE;             (* 效率折算 [-] / Efficiency as fraction *)
(* 电量：Q = I·t [C] = [A·s] *)
fChargeC := fCurrentA * fTimeS;
(* 电量密度与电流密度：分母面积已过域闸 *)
fChgDensAsDm2 := fChargeC / fAreaDm2;
fDensADm2 := fCurrentA / fAreaDm2;
(* 膜厚：δ = 电量密度 × 单位膜厚系数 × 电流效率 [μm] *)
fFilmUm := fChgDensAsDm2 * fUmPerAsDm2 * fEffUnit;
(* 反算时间：t = 目标膜厚 / (电流密度 × 系数 × 效率)，电流密度为 0 时回 0 *)
IF (fDensADm2 > DL_EPS) AND (fThickTargetUm > DL_ZERO) THEN
    fTimeForTargetS := fThickTargetUm / (fDensADm2 * fUmPerAsDm2 * fEffUnit);
END_IF
xValid := TRUE;                                (* 链路有效 / Chain valid *)
FC_DL_AnodizeBathChargeCalc := fFilmUm;        (* 返回膜厚 [μm] / Return film thickness *)
END_FUNCTION
