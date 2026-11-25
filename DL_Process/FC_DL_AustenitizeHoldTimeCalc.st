(*
  Component : FC_DL_AustenitizeHoldTimeCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 奥氏体化保温时间核算：按有效厚度乘以单位厚度基准时间，再叠加厚度分段系数、升温速率修正与目标温度修正。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 有效厚度/升温速率/单位厚度时间均须 > 1e-9，否则返回哨兵 -1；
              ② 厚度分三段（<=25 / <=50 / >50 mm），系数逐段离散，段内不插值；
              ③ 升温速率修正与温度修正均双侧钳位，防经验式外推发散。
*)
FUNCTION FC_DL_AustenitizeHoldTimeCalc : REAL
VAR_INPUT
    fThkMm      : REAL;   (* 工件有效厚度 [mm] Effective thickness *)
    fRateCmin   : REAL;   (* 实际升温速率 [°C/min] Actual heating rate *)
    fRateRefCmin: REAL;   (* 参考升温速率（分段基准） [°C/min] Reference heating rate *)
    fTargetC    : REAL;   (* 目标奥氏体化温度 [°C] Target austenitizing temperature *)
    fTempRefC   : REAL;   (* 参考目标温度（分段基准） [°C] Reference target temperature *)
    fMinPerMm   : REAL;   (* 单位厚度基准保温时间 [min/mm] Base hold time per mm *)
END_VAR
VAR_OUTPUT
    fHoldMin   : REAL;    (* 保温时间计算结果 [min] Computed hold time *)
    fThkCoef   : REAL;    (* 厚度分段系数 [-] Thickness segment coefficient *)
    fRateCoef  : REAL;    (* 升温速率修正系数 [-] Heating rate correction coefficient *)
    xValid     : BOOL;    (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_RATE_MIN  : REAL := 0.80;     (* 速率修正下限 [-] Rate correction lower clamp *)
    DL_RATE_MAX  : REAL := 1.30;     (* 速率修正上限 [-] Rate correction upper clamp *)
    DL_TEMP_K    : REAL := 0.002;    (* 目标温度每 °C 修正斜率 [1/°C] Temperature slope *)
    DL_THK_MID   : REAL := 25.0;     (* 厚度分段第一界 [mm] First thickness boundary *)
    DL_THK_HIGH  : REAL := 50.0;     (* 厚度分段第二界 [mm] Second thickness boundary *)
END_VAR
(* 出口预置：全出口统一预置 *)
fHoldMin := 0.0; fThkCoef := 1.0; fRateCoef := 1.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0)
   OR (fRateCmin <> fRateCmin) OR ((fRateCmin - fRateCmin) <> 0.0)
   OR (fRateRefCmin <> fRateRefCmin) OR ((fRateRefCmin - fRateRefCmin) <> 0.0)
   OR (fTargetC <> fTargetC) OR ((fTargetC - fTargetC) <> 0.0)
   OR (fTempRefC <> fTempRefC) OR ((fTempRefC - fTempRefC) <> 0.0)
   OR (fMinPerMm <> fMinPerMm) OR ((fMinPerMm - fMinPerMm) <> 0.0) THEN
    FC_DL_AustenitizeHoldTimeCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：厚度、实际升温速率、单位厚度时间三者为除子或比例基 *)
IF (fThkMm <= DL_EPS) OR (fRateCmin <= DL_EPS) OR (fMinPerMm <= DL_EPS) THEN
    FC_DL_AustenitizeHoldTimeCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 厚度分段系数：三段离散，段内不插值，防止经验式在厚壁区外推 *)
IF fThkMm <= DL_THK_MID THEN
    fThkCoef := 1.00;                       (* 薄件段 [-] / Thin section *)
ELSIF fThkMm <= DL_THK_HIGH THEN
    fThkCoef := 1.15;                       (* 中厚段 [-] / Medium section *)
ELSE
    fThkCoef := 1.35;                       (* 厚壁段（心部透热滞后） [-] / Thick section *)
END_IF
(* 升温速率修正：升温越慢，组织转变越充分，保温时间可缩短，双侧钳位 *)
fRateCoef := fRateRefCmin / fRateCmin;
IF fRateCoef < DL_RATE_MIN THEN
    fRateCoef := DL_RATE_MIN;               (* 下限钳位 [-] / Lower clamp *)
ELSIF fRateCoef > DL_RATE_MAX THEN
    fRateCoef := DL_RATE_MAX;               (* 上限钳位 [-] / Upper clamp *)
END_IF
(* 目标温度修正：温度偏低需延长保温 *)
IF fTargetC > fTempRefC THEN
    fHoldMin := fMinPerMm * fThkMm * fThkCoef * fRateCoef;
    fHoldMin := fHoldMin * (1.0 - (fTargetC - fTempRefC) * DL_TEMP_K);
ELSE
    fHoldMin := fMinPerMm * fThkMm * fThkCoef * fRateCoef;
    fHoldMin := fHoldMin * (1.0 + (fTempRefC - fTargetC) * DL_TEMP_K);
END_IF
(* 结果下钳位：保温时间不得为负，防温度修正项越界 *)
IF fHoldMin < DL_EPS THEN
    fHoldMin := DL_EPS;                     (* 非负钳位 [min] / Non-negative clamp *)
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_AustenitizeHoldTimeCalc := fHoldMin;  (* 返回保温时间 [min] / Return hold minutes *)
END_FUNCTION
