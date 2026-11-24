(*
  Component : FC_DL_MashStrikeWaterTempCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  功能      : 糖化投料水温核算：按麦芽量/比热/初温与水量做能量平衡，反算达到目标醪温所需的投料水温，并含设备热损修正。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 麦芽量、水量、两侧比热均须 > 1e-9，否则返回哨兵 -1（水量热容为除子）；
              ② 热损按目标醪温的百分比上调所需焓，热损率钳位 0~30 %；
              ③ 反算水温可低于 0 °C（需预冷），不下钳位，仅照实输出供上位判断。
*)
FUNCTION FC_DL_MashStrikeWaterTempCalc : REAL
VAR_INPUT
    fMaltKg      : REAL;   (* 麦芽投料量 [kg] Malt charge *)
    fMaltCpKJkgK : REAL;   (* 麦芽比热容 [kJ/(kg·K)] Malt specific heat *)
    fMaltT0C     : REAL;   (* 麦芽初始温度 [°C] Malt initial temperature *)
    fWaterKg     : REAL;   (* 投料水量 [kg] Strike water mass *)
    fWaterCpKJkgK: REAL;   (* 水比热容 [kJ/(kg·K)] Water specific heat *)
    fTargetMashC : REAL;   (* 目标醪液温度 [°C] Target mash temperature *)
    fLossPct     : REAL;   (* 设备热损率 [%] Equipment heat loss ratio *)
END_VAR
VAR_OUTPUT
    fStrikeWaterC : REAL;  (* 所需投料水温 [°C] Required strike water temperature *)
    fHeatCapMaltKJK: REAL; (* 麦芽热容 [kJ/K] Malt heat capacity *)
    fHeatCapWaterKJK: REAL;(* 水热容 [kJ/K] Water heat capacity *)
    xValid        : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1 + 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_LOSS_MAX : REAL := 30.0;     (* 热损率上限 [%] Heat loss upper clamp *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fTargetEffC : REAL;   (* 含热损修正的目标温度 [°C] Loss-corrected target temperature *)
    fLossUnit   : REAL;   (* 热损率折算系数 [-] Heat loss as fraction *)
END_VAR
(* 出口预置：四出口统一预置 *)
fStrikeWaterC := 0.0; fHeatCapMaltKJK := 0.0; fHeatCapWaterKJK := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fMaltKg <> fMaltKg) OR ((fMaltKg - fMaltKg) <> 0.0)
   OR (fMaltCpKJkgK <> fMaltCpKJkgK) OR ((fMaltCpKJkgK - fMaltCpKJkgK) <> 0.0)
   OR (fMaltT0C <> fMaltT0C) OR ((fMaltT0C - fMaltT0C) <> 0.0)
   OR (fWaterKg <> fWaterKg) OR ((fWaterKg - fWaterKg) <> 0.0)
   OR (fWaterCpKJkgK <> fWaterCpKJkgK) OR ((fWaterCpKJkgK - fWaterCpKJkgK) <> 0.0)
   OR (fTargetMashC <> fTargetMashC) OR ((fTargetMashC - fTargetMashC) <> 0.0) THEN
    FC_DL_MashStrikeWaterTempCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
(* removed *)
(* 组态域闸：两侧质量与比热均为比例基，水量热容为除子 *)
IF (fMaltKg <= DL_EPS) OR (fWaterKg <= DL_EPS) OR (fMaltCpKJkgK <= DL_EPS)
   OR (fWaterCpKJkgK <= DL_EPS) OR (fLossPct < DL_ZERO) OR (fLossPct > DL_LOSS_MAX) THEN
    FC_DL_MashStrikeWaterTempCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 两侧热容：C = m·cp [kJ/K] *)
fHeatCapMaltKJK  := fMaltKg * fMaltCpKJkgK;
fHeatCapWaterKJK := fWaterKg * fWaterCpKJkgK;
(* 热损修正：需把目标温度按热损率上调，等效为多带入焓 *)
fLossUnit := fLossPct / DL_PCT_BASE;
fTargetEffC := fTargetMashC * (1.0 + fLossUnit);
(* 能量平衡：T_w = [T_eff·(Cm+Cw) - Cm·Tm] / Cw，除子水热容已过域闸 *)
fStrikeWaterC := (fTargetEffC * (fHeatCapMaltKJK + fHeatCapWaterKJK)
                  - fHeatCapMaltKJK * fMaltT0C) / fHeatCapWaterKJK;
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_MashStrikeWaterTempCalc := fStrikeWaterC; (* 返回投料水温 [°C] / Return strike water temp *)
END_FUNCTION
