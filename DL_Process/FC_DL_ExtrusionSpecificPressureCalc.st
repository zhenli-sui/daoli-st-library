(*
  Component : FC_DL_ExtrusionSpecificPressureCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 挤压比压核算：按挤压筒面积与挤压力算比压并做摩擦修正，同时按模孔面积算挤压比 R = A0/Af 与镦粗填充比。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 挤压筒直径、模孔面积、坯料直径须 > 1e-9，否则返回哨兵 -1；
              ② 摩擦修正按百分数线性折算并钳位 0~50 %，防人为输入放大比压；
              ③ 挤压比按面积比直接给出，不做温升与应变速率修正。
*)
FUNCTION FC_DL_ExtrusionSpecificPressureCalc : REAL
VAR_INPUT
    fForceKN        : REAL;   (* 挤压力 [kN] Extrusion force *)
    fContainerDiaMm : REAL;   (* 挤压筒内径 [mm] Container bore diameter *)
    fBilletDiaMm    : REAL;   (* 铸锭直径 [mm] Billet diameter *)
    fOrificeAreaMm2 : REAL;   (* 模孔总截面积 [mm²] Total die orifice area *)
    fFrictionPct    : REAL;   (* 摩擦修正系数 [%] Friction correction percent *)
END_VAR
VAR_OUTPUT
    fPressMPa       : REAL;   (* 挤压比压（含摩擦修正） [MPa] Specific pressure with friction *)
    fRatioR         : REAL;   (* 挤压比 A0/Af [-] Extrusion ratio *)
    fUpsetRatio     : REAL;   (* 镦粗填充比 Ac/Ab [-] Upset fill ratio *)
    xValid          : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PI       : REAL := 3.14159265358979;  (* 圆周率 [-] Pi *)
    DL_FRIC_MAX : REAL := 50.0;     (* 摩擦修正上限 [%] Friction correction upper clamp *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fAreaCont : REAL;   (* 挤压筒截面积 [mm²] Container cross-section *)
    fAreaBil  : REAL;   (* 铸锭截面积 [mm²] Billet cross-section *)
    fFricUnit : REAL;   (* 摩擦修正折算系数 [-] Friction factor as fraction *)
END_VAR
(* 出口预置：四出口统一预置 *)
fPressMPa := 0.0; fRatioR := 0.0; fUpsetRatio := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fForceKN <> fForceKN) OR ((fForceKN - fForceKN) <> 0.0)
   OR (fContainerDiaMm <> fContainerDiaMm) OR ((fContainerDiaMm - fContainerDiaMm) <> 0.0)
   OR (fBilletDiaMm <> fBilletDiaMm) OR ((fBilletDiaMm - fBilletDiaMm) <> 0.0)
   OR (fOrificeAreaMm2 <> fOrificeAreaMm2) OR ((fOrificeAreaMm2 - fOrificeAreaMm2) <> 0.0)
   OR (fFrictionPct <> fFrictionPct) OR ((fFrictionPct - fFrictionPct) <> 0.0) THEN
    FC_DL_ExtrusionSpecificPressureCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：两个直径与模孔面积均为除子，挤压力须非负 *)
IF (fContainerDiaMm <= DL_EPS) OR (fBilletDiaMm <= DL_EPS)
   OR (fOrificeAreaMm2 <= DL_EPS) OR (fForceKN < DL_ZERO) THEN
    FC_DL_ExtrusionSpecificPressureCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 摩擦修正：负值归零，超 50 % 钳位，防人为放大比压 *)
IF fFrictionPct < DL_ZERO THEN
    fFricUnit := 1.0;                        (* 负值归零修正 [-] / Negative treated as zero *)
ELSIF fFrictionPct > DL_FRIC_MAX THEN
    fFricUnit := 1.0 + DL_FRIC_MAX / 100.0;  (* 上限钳位 [-] / Upper clamp *)
ELSE
    fFricUnit := 1.0 + fFrictionPct / 100.0; (* 线性折算 [-] / Linear correction *)
END_IF
(* 面积：A = pi/4 * D^2 [mm²] *)
fAreaCont := DL_PI / 4.0 * fContainerDiaMm * fContainerDiaMm;
fAreaBil  := DL_PI / 4.0 * fBilletDiaMm * fBilletDiaMm;
(* 比压：kN -> N 除面积 mm² 即 MPa（N/mm²），再乘摩擦修正 *)
fPressMPa := (fForceKN * 1000.0) / fAreaCont * fFricUnit;
(* 挤压比 R = A0/Af，镦粗填充比 = Ac/Ab，分母均已过域闸 *)
fRatioR := fAreaCont / fOrificeAreaMm2;
fUpsetRatio := fAreaCont / fAreaBil;
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_ExtrusionSpecificPressureCalc := fPressMPa;  (* 返回比压 [MPa] / Return specific pressure *)
END_FUNCTION
