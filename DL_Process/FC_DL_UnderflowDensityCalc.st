(*
  Name: FC_DL_UnderflowDensityCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：由底流管压力变送器读数与取压点高度反算浆体密度，再换算底流固体质量浓度与体积浓度。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 取压点高度为除子（P = ρ·g·h 反解），须 0.2~20 m；压力须 ≥ 0 且 ≤ 500 kPa；
            ③ 固体密度必须高于浆体密度且高于水密度，否则质量浓度式分母塌零或无物理意义，返回哨兵 -1；
            ④ 质量浓度物理域 0~100 %，越域（传感器零漂）判非法返回哨兵 -1，不静默钳位。
  量纲自证：P[kPa]×1000 = Pa = N/m2；N/m2 ÷ (m/s2 × m) = kg/m3；浓度式无量纲。
*)
FUNCTION FC_DL_UnderflowDensityCalc : REAL
VAR_INPUT
    fPressKPa : REAL;            (* 取压点表压 [kPa] Gauge pressure at tapping point [kPa] *)
    fHeightM : REAL;             (* 取压点距液面高度 [m] Tapping height below surface [m] *)
    fSlurryDensityKgM3 : REAL;   (* 浆体密度（用于浓度换算的复核值） [kg/m3] Slurry density [kg/m3] *)
    fSolidDensityKgM3 : REAL;    (* 固体真密度 [kg/m3] Solids true density [kg/m3] *)
END_VAR
VAR_OUTPUT
    fMassConcPct : REAL;         (* 固体质量浓度 [%] Solids mass concentration [%] *)
    fVolConcPct : REAL;          (* 固体体积浓度 [%] Solids volume concentration [%] *)
    xValid : BOOL;               (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;         (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_G : REAL := 9.80665;          (* 标准重力加速度 [m/s2] Standard gravity [m/s2] *)
    DL_RHO_W : REAL := 998.2;        (* 水密度（20 ℃） [kg/m3] Water density at 20 degC [kg/m3] *)
    DL_PCT : REAL := 100.0;          (* 百分数基准 [%] Percent base *)
    DL_PA_PER_KPA : REAL := 1000.0;  (* kPa → Pa 换算 [Pa/kPa] Kilopascal to pascal *)
    DL_H_MIN : REAL := 0.2;          (* 取压高度下限 [m] Tapping height floor [m] *)
    DL_H_MAX : REAL := 20.0;         (* 取压高度上限 [m] Tapping height ceiling [m] *)
    DL_P_MAX : REAL := 500.0;        (* 压力上限 [kPa] Pressure ceiling [kPa] *)
    DL_SL_MIN : REAL := 1000.0;      (* 浆体密度下限 [kg/m3] Slurry density floor [kg/m3] *)
    DL_SL_MAX : REAL := 2200.0;      (* 浆体密度上限 [kg/m3] Slurry density ceiling [kg/m3] *)
    DL_SD_MIN : REAL := 1500.0;      (* 固体密度下限 [kg/m3] Solids density floor [kg/m3] *)
    DL_SD_MAX : REAL := 5000.0;      (* 固体密度上限 [kg/m3] Solids density ceiling [kg/m3] *)
END_VAR
VAR
    fRhoCalc : REAL;    (* 由压差反算的浆体密度 [kg/m3] Slurry density from pressure [kg/m3] *)
    fDensDiff : REAL;   (* 固液密度差 [kg/m3] Solids minus water density [kg/m3] *)
    fCm : REAL;         (* 质量浓度小数 [-] Mass concentration fraction *)
END_VAR
(* 出口预置：三出口统一预置（R256） *)
fMassConcPct := 0.0; fVolConcPct := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fPressKPa <> fPressKPa) OR ((fPressKPa - fPressKPa) <> 0.0)
   OR (fHeightM <> fHeightM) OR ((fHeightM - fHeightM) <> 0.0)
   OR (fSlurryDensityKgM3 <> fSlurryDensityKgM3) OR ((fSlurryDensityKgM3 - fSlurryDensityKgM3) <> 0.0)
   OR (fSolidDensityKgM3 <> fSolidDensityKgM3) OR ((fSolidDensityKgM3 - fSolidDensityKgM3) <> 0.0) THEN
    FC_DL_UnderflowDensityCalc := -1.0;     (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：高度为除子，两密度须物理可行且固相明显重于液相 *)
IF (fHeightM < DL_H_MIN) OR (fHeightM > DL_H_MAX)
   OR (fPressKPa < 0.0) OR (fPressKPa > DL_P_MAX)
   OR (fSlurryDensityKgM3 < DL_SL_MIN) OR (fSlurryDensityKgM3 > DL_SL_MAX)
   OR (fSolidDensityKgM3 < DL_SD_MIN) OR (fSolidDensityKgM3 > DL_SD_MAX)
   OR ((fSolidDensityKgM3 - fSlurryDensityKgM3) < DL_EPS) THEN
    FC_DL_UnderflowDensityCalc := -1.0;     (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 反算浆体密度：ρ = P/(g·h)，量纲 Pa ÷ (m/s2·m) = kg/m3 *)
fRhoCalc := (fPressKPa * DL_PA_PER_KPA) / (DL_G * fHeightM);
(* 固液密度差已过正性闸，绝无零除 *)
fDensDiff := fSolidDensityKgM3 - DL_RHO_W;
(* 质量浓度：Cm = ρs(ρsl − ρw) / (ρsl(ρs − ρw))，无量纲 *)
IF fRhoCalc <= DL_EPS THEN
    FC_DL_UnderflowDensityCalc := -1.0;     (* 哨兵 -1：反算密度塌零 / Sentinel -1, vanishing density *)
    RETURN;
END_IF
fCm := (fSolidDensityKgM3 * (fRhoCalc - DL_RHO_W)) / (fRhoCalc * fDensDiff);
(* 物理域检查：质量浓度越 0~1 说明零漂或密度参数不匹配，判非法不钳位 *)
IF (fCm < 0.0) OR (fCm > 1.0) THEN
    FC_DL_UnderflowDensityCalc := -1.0;     (* 哨兵 -1：浓度越物理域 / Sentinel -1, out of physical domain *)
    RETURN;
END_IF
fMassConcPct := fCm * DL_PCT;
(* 体积浓度：Cv = Cm·ρsl/ρs *)
fVolConcPct := (fCm * fRhoCalc / fSolidDensityKgM3) * DL_PCT;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_UnderflowDensityCalc := fMassConcPct;
END_FUNCTION
