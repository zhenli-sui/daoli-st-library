(*
  Component : FC_DL_CompactionPressureCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 压制压力核算：按压坯相对密度与材料常数算单位压制压力，并折算压机吨位需求（含安全系数）。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 松装密度、材料常数、压制面积、安全系数须 > 1e-9，否则返回哨兵 -1；
              ② 相对密度 <= 1（压坯未致密化）时压制压力按 0 输出并置 xValid 真（合法空工况）；
              ③ 吨位折算：MPa(N/mm²) × mm² ÷ 1000 = kN。
*)
FUNCTION FC_DL_CompactionPressureCalc : REAL
VAR_INPUT
    fGreenDensGcm3 : REAL;   (* 压坯密度 [g/cm³] Green compact density *)
    fAppDensGcm3   : REAL;   (* 松装密度 [g/cm³] Apparent density *)
    fMatKMPa       : REAL;   (* 材料压制常数 [MPa] Material compaction constant *)
    fPartAreaMm2   : REAL;   (* 压坯投影面积 [mm²] Compact projected area *)
    fSafetyFactor  : REAL;   (* 压机吨位安全系数 [-] Press tonnage safety factor *)
END_VAR
VAR_OUTPUT
    fRelDensity : REAL;   (* 相对密度（压坯/松装） [-] Relative density *)
    fPressMPa   : REAL;   (* 单位压制压力 [MPa] Compaction pressure *)
    fTonnageKN  : REAL;   (* 压机吨位需求 [kN] Required press tonnage *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_N_PER_KN : REAL := 1000.0;   (* 牛转千牛系数 [N/kN] Newtons per kilonewton *)
    DL_ONE      : REAL := 1.0;      (* 单位常数 [-] Unity constant *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：四出口统一预置 *)
fRelDensity := 0.0; fPressMPa := 0.0; fTonnageKN := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fGreenDensGcm3 <> fGreenDensGcm3) OR ((fGreenDensGcm3 - fGreenDensGcm3) <> 0.0)
   OR (fAppDensGcm3 <> fAppDensGcm3) OR ((fAppDensGcm3 - fAppDensGcm3) <> 0.0)
   OR (fMatKMPa <> fMatKMPa) OR ((fMatKMPa - fMatKMPa) <> 0.0)
   OR (fPartAreaMm2 <> fPartAreaMm2) OR ((fPartAreaMm2 - fPartAreaMm2) <> 0.0)
   OR (fSafetyFactor <> fSafetyFactor) OR ((fSafetyFactor - fSafetyFactor) <> 0.0) THEN
    FC_DL_CompactionPressureCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：松装密度为除子，材料常数/面积/安全系数须为正 *)
IF (fAppDensGcm3 <= DL_EPS) OR (fMatKMPa <= DL_ZERO) OR (fPartAreaMm2 <= DL_EPS)
   OR (fSafetyFactor <= DL_ZERO) OR (fGreenDensGcm3 < DL_ZERO) THEN
    FC_DL_CompactionPressureCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 相对密度：rho_rel = 压坯密度 / 松装密度，分母已过域闸 *)
fRelDensity := fGreenDensGcm3 / fAppDensGcm3;
IF fRelDensity <= DL_ONE THEN
    xValid := TRUE;                       (* 合法空工况：未致密化，无压制压力 *)
    FC_DL_CompactionPressureCalc := DL_ZERO;
    RETURN;
END_IF
(* 单位压制压力：p = K·(rho_rel - 1) [MPa] *)
fPressMPa := fMatKMPa * (fRelDensity - DL_ONE);
(* 压机吨位需求：p(N/mm²) × A(mm²) = N，除 1000 得 kN，再乘安全系数 *)
fTonnageKN := fPressMPa * fPartAreaMm2 / DL_N_PER_KN * fSafetyFactor;
xValid := TRUE;                           (* 链路有效 / Chain valid *)
FC_DL_CompactionPressureCalc := fPressMPa;  (* 返回压制压力 [MPa] / Return compaction pressure *)
END_FUNCTION
