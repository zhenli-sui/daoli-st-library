(*
  Component : FC_DL_PowderFillDensityCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : 装粉松装密度与填充高度核算：按粉重、模腔面积与松装密度算填充容积与填充高度，并给出压制压缩比。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 模腔面积与松装密度须 > 1e-9，否则返回哨兵 -1（松装密度为除子）；
              ② 压缩比为压坯密度与松装密度之比，压坯密度为 0 时回 1.0（无压缩）；
              ③ 量纲链：kg→g 除 g/cm³ 得 cm³，再乘 1000 除 mm² 得 mm。
*)
FUNCTION FC_DL_PowderFillDensityCalc : REAL
VAR_INPUT
    fPowderKg     : REAL;   (* 单件装粉质量 [kg] Powder mass per part *)
    fCavityAreaMm2: REAL;   (* 模腔投影面积 [mm²] Cavity cross-section area *)
    fAppDensGcm3  : REAL;   (* 粉末松装密度 [g/cm³] Apparent density *)
    fPressDensGcm3: REAL;   (* 压坯密度 [g/cm³] Green compact density *)
END_VAR
VAR_OUTPUT
    fFillVolCm3 : REAL;   (* 填充容积 [cm³] Fill volume *)
    fFillHeightMm: REAL;  (* 填充高度 [mm] Fill height *)
    fCompRatio  : REAL;   (* 压缩比（压坯/松装） [-] Compression ratio *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_G_PER_KG  : REAL := 1000.0;   (* 千克转克系数 [g/kg] Grams per kilogram *)
    DL_MM3_PER_CM3: REAL := 1000.0;  (* 立方厘米转立方毫米 [mm³/cm³] mm3 per cm3 *)
    DL_ZERO      : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：四出口统一预置 *)
fFillVolCm3 := 0.0; fFillHeightMm := 0.0; fCompRatio := 1.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fPowderKg <> fPowderKg) OR ((fPowderKg - fPowderKg) <> 0.0)
   OR (fCavityAreaMm2 <> fCavityAreaMm2) OR ((fCavityAreaMm2 - fCavityAreaMm2) <> 0.0)
   OR (fAppDensGcm3 <> fAppDensGcm3) OR ((fAppDensGcm3 - fAppDensGcm3) <> 0.0)
   OR (fPressDensGcm3 <> fPressDensGcm3) OR ((fPressDensGcm3 - fPressDensGcm3) <> 0.0) THEN
    FC_DL_PowderFillDensityCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：面积与松装密度均为除子，粉重须非负 *)
IF (fCavityAreaMm2 <= DL_EPS) OR (fAppDensGcm3 <= DL_EPS) OR (fPowderKg < DL_ZERO) THEN
    FC_DL_PowderFillDensityCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 填充容积：V = m / 松装密度 [cm³]，分母已过域闸 *)
fFillVolCm3 := (fPowderKg * DL_G_PER_KG) / fAppDensGcm3;
(* 填充高度：h = V(mm³) / A(mm²) [mm] *)
fFillHeightMm := (fFillVolCm3 * DL_MM3_PER_CM3) / fCavityAreaMm2;
(* 压缩比：压坯密度 / 松装密度，压坯密度为 0 时保持 1.0 *)
IF fPressDensGcm3 > DL_EPS THEN
    fCompRatio := fPressDensGcm3 / fAppDensGcm3;
ELSE
    fCompRatio := 1.0;                    (* 无压坯数据：按无压缩处理 *)
END_IF
xValid := TRUE;                           (* 链路有效 / Chain valid *)
FC_DL_PowderFillDensityCalc := fFillHeightMm;  (* 返回填充高度 [mm] / Return fill height *)
END_FUNCTION
