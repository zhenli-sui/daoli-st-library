(*
  Name: FC_DL_ForgeBilletHeatTimeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：坯料加热时间（透热厚度经验式）：以加热系数乘透热厚度，并按炉温-目标温差势比修正，另给出均热时间。
  边界条件：① 五入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 炉温必须高于目标温度（否则无传热势差，返回哨兵 -1），目标温度必须高于起始温度；
            ③ 势比 = (T炉−T初)/(T炉−T目标)：目标温度越接近炉温，势比越大（加热越慢），量纲无量纲；
            ④ 均热时间取加热时间的 25 %，并设 5 min 下限（薄料均热不因比例过小而失效）。
  量纲自证：k[min/cm] × 厚度[cm] = min；势比无量纲，量纲保持 min。
*)
FUNCTION FC_DL_ForgeBilletHeatTimeCalc : REAL
VAR_INPUT
    fThkMm : REAL;              (* 坯料透热厚度 [mm] Billet through-heating thickness [mm] *)
    fHeatCoefMinPerCm : REAL;   (* 加热系数 [min/cm] Heating coefficient [min/cm] *)
    fFurnaceTempC : REAL;       (* 炉膛温度 [℃] Furnace temperature [degC] *)
    fTargetTempC : REAL;        (* 目标出炉温度 [℃] Target discharge temperature [degC] *)
    fStartTempC : REAL;         (* 入炉起始温度 [℃] Charging temperature [degC] *)
END_VAR
VAR_OUTPUT
    fHeatTimeMin : REAL;        (* 加热时间 [min] Heating time [min] *)
    fSoakTimeMin : REAL;        (* 均热时间 [min] Soak time [min] *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_MM_PER_CM : REAL := 10.0;    (* 毫米 → 厘米换算 [mm/cm] Millimetre to centimetre *)
    DL_SOAK_RATIO : REAL := 0.25;   (* 均热/加热时间比 [-] Soak to heat ratio *)
    DL_SOAK_MIN : REAL := 5.0;      (* 均热时间下限 [min] Soak time floor [min] *)
    DL_T_MIN : REAL := 10.0;        (* 厚度下限 [mm] Thickness floor [mm] *)
    DL_T_MAX : REAL := 1200.0;      (* 厚度上限 [mm] Thickness ceiling [mm] *)
    DL_K_MIN : REAL := 0.5;         (* 加热系数下限 [min/cm] Coefficient floor [min/cm] *)
    DL_K_MAX : REAL := 10.0;        (* 加热系数上限 [min/cm] Coefficient ceiling [min/cm] *)
    DL_F_MIN : REAL := 200.0;       (* 炉温下限 [℃] Furnace floor [degC] *)
    DL_F_MAX : REAL := 1400.0;      (* 炉温上限 [℃] Furnace ceiling [degC] *)
    DL_S_MIN : REAL := -50.0;       (* 起始温度下限 [℃] Start floor [degC] *)
    DL_S_MAX : REAL := 1200.0;      (* 起始温度上限 [℃] Start ceiling [degC] *)
END_VAR
VAR
    fThkCm : REAL;      (* 透热厚度 [cm] Through-heating thickness [cm] *)
    fPotRatio : REAL;   (* 温差势比 [-] Temperature potential ratio *)
    fDenC : REAL;       (* 势比分母（炉温−目标） [℃] Potential denominator [degC] *)
END_VAR
(* 出口预置：三出口统一预置（R256） *)
fHeatTimeMin := 0.0; fSoakTimeMin := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，五入参全枚举 *)
IF (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0)
   OR (fHeatCoefMinPerCm <> fHeatCoefMinPerCm) OR ((fHeatCoefMinPerCm - fHeatCoefMinPerCm) <> 0.0)
   OR (fFurnaceTempC <> fFurnaceTempC) OR ((fFurnaceTempC - fFurnaceTempC) <> 0.0)
   OR (fTargetTempC <> fTargetTempC) OR ((fTargetTempC - fTargetTempC) <> 0.0)
   OR (fStartTempC <> fStartTempC) OR ((fStartTempC - fStartTempC) <> 0.0) THEN
    FC_DL_ForgeBilletHeatTimeCalc := -1.0;  (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：厚度、系数、炉温、起始温度定域，温度须满足 炉温 > 目标 > 起始 *)
IF (fThkMm < DL_T_MIN) OR (fThkMm > DL_T_MAX)
   OR (fHeatCoefMinPerCm < DL_K_MIN) OR (fHeatCoefMinPerCm > DL_K_MAX)
   OR (fFurnaceTempC < DL_F_MIN) OR (fFurnaceTempC > DL_F_MAX)
   OR (fStartTempC < DL_S_MIN) OR (fStartTempC > DL_S_MAX)
   OR (fTargetTempC <= fStartTempC) OR ((fFurnaceTempC - fTargetTempC) <= DL_EPS) THEN
    FC_DL_ForgeBilletHeatTimeCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 透热厚度折算：mm ÷ 10 = cm *)
fThkCm := fThkMm / DL_MM_PER_CM;
(* 势比：分母（炉温−目标）已过正性闸，绝无零除 *)
fDenC := fFurnaceTempC - fTargetTempC;
fPotRatio := (fFurnaceTempC - fStartTempC) / fDenC;
(* 加热时间：k[min/cm] × 厚度[cm] × 势比，量纲 min *)
fHeatTimeMin := fHeatCoefMinPerCm * fThkCm * fPotRatio;
(* 均热时间：25 % 加热时间，并保 5 min 下限 *)
fSoakTimeMin := fHeatTimeMin * DL_SOAK_RATIO;
IF fSoakTimeMin < DL_SOAK_MIN THEN
    fSoakTimeMin := DL_SOAK_MIN;            (* 下限钳位 / Floor clamp *)
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_ForgeBilletHeatTimeCalc := fHeatTimeMin;
END_FUNCTION
