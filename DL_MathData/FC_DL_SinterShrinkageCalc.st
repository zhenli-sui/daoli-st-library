(*
  Component : FC_DL_SinterShrinkageCalc
  Category  : DL_MathData
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : 烧结线收缩率与模具尺寸补偿：按烧结前后密度比开立方得线收缩率，并由成品尺寸反算所需模具尺寸。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 生坯密度与烧结密度均须 > 1e-9（均为除子），否则返回哨兵 -1；
              ② 烧结密度低于生坯密度时收缩率为负（膨胀），照实输出不钳位，便于诊断工艺异常；
              ③ 反算模具尺寸用 成品尺寸 / 线性比例因子，比例因子为 0 时不计算。
*)
FUNCTION FC_DL_SinterShrinkageCalc : REAL
VAR_INPUT
    fGreenDensGcm3 : REAL;   (* 烧结前生坯密度 [g/cm³] Green density before sintering *)
    fSinterDensGcm3: REAL;   (* 烧结后密度 [g/cm³] Sintered density *)
    fFinalDimMm    : REAL;   (* 成品目标尺寸 [mm] Final part dimension *)
END_VAR
VAR_OUTPUT
    fLinFactor  : REAL;   (* 线性比例因子（成品/模具） [-] Linear scale factor *)
    fShrinkPct  : REAL;   (* 线收缩率 [%] Linear shrinkage percent *)
    fDieDimMm   : REAL;   (* 反算模具尺寸 [mm] Die dimension *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_THIRD    : REAL := 0.3333333333333333;  (* 立方根指数 [-] Cube-root exponent *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ONE      : REAL := 1.0;      (* 单位常数 [-] Unity constant *)
END_VAR
(* 出口预置：三出口统一预置 *)
fLinFactor := 1.0; fShrinkPct := 0.0; fDieDimMm := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fGreenDensGcm3 <> fGreenDensGcm3) OR ((fGreenDensGcm3 - fGreenDensGcm3) <> 0.0)
   OR (fSinterDensGcm3 <> fSinterDensGcm3) OR ((fSinterDensGcm3 - fSinterDensGcm3) <> 0.0)
   OR (fFinalDimMm <> fFinalDimMm) OR ((fFinalDimMm - fFinalDimMm) <> 0.0) THEN
    FC_DL_SinterShrinkageCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：两个密度均为除子，成品尺寸须为正 *)
IF (fGreenDensGcm3 <= DL_EPS) OR (fSinterDensGcm3 <= DL_EPS) OR (fFinalDimMm <= DL_EPS) THEN
    FC_DL_SinterShrinkageCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 质量守恒：体积比 = 密度比的反比，线比例因子 = 体比例因子的立方根 *)
fLinFactor := EXPT(fGreenDensGcm3 / fSinterDensGcm3, DL_THIRD);
(* 线收缩率：收缩为正，膨胀为负，照实输出便于工艺诊断 *)
fShrinkPct := (DL_ONE - fLinFactor) * DL_PCT_BASE;
(* 反算模具尺寸：成品 = 模具 × 线比例因子，因子为 0 时不下发 *)
IF fLinFactor > DL_EPS THEN
    fDieDimMm := fFinalDimMm / fLinFactor;
END_IF
xValid := TRUE;                            (* 链路有效 / Chain valid *)
FC_DL_SinterShrinkageCalc := fShrinkPct;   (* 返回线收缩率 [%] / Return linear shrinkage *)
END_FUNCTION
