(*
  Name: FC_DL_SprayFlowRateCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：喷枪流量与雾化压力匹配：按喷嘴孔径、供压、粘度算体积流量并按泵上限钳位，同时给出雾化压力建议值。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 孔口流量用 Q = Cd·A·√(2ΔP/ρ)，Cd = 0.62、ρ = 1200 kg/m3 为涂料通用常量；
            ③ 粘度修正 kμ = 1/(1 + 0.3·√(ν/100))，ν 为运动粘度 [cSt]，量与基准同量纲故无量纲；
            ④ 雾化压力取供压的 85 % 并钳 0.5~6 bar（低压雾化枪工艺域），钳位只在量值上，不改有效性。
  量纲自证：m2 × √(Pa/(kg/m3)) = m2 × m/s = m3/s；m3/s × 1e6 = ml/s；×60 = ml/min。
*)
FUNCTION FC_DL_SprayFlowRateCalc : REAL
VAR_INPUT
    fNozzleDiaMm : REAL;        (* 喷嘴孔径 [mm] Nozzle orifice diameter [mm] *)
    fPressBar : REAL;           (* 供漆压力 [bar] Paint supply pressure [bar] *)
    fViscCst : REAL;            (* 运动粘度 [cSt] Kinematic viscosity [cSt] *)
    fFlowMaxMlmin : REAL;       (* 泵/枪流量上限 [ml/min] Flow ceiling [ml/min] *)
END_VAR
VAR_OUTPUT
    fFlowMlmin : REAL;          (* 计算流量（已钳位） [ml/min] Flow rate, clamped [ml/min] *)
    fAtomPressBar : REAL;       (* 雾化压力建议值 [bar] Recommended atomizing pressure [bar] *)
    xClamped : BOOL;            (* 流量已按上限钳位 [-] Flow clamped by ceiling *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_CD : REAL := 0.62;           (* 孔口流量系数 [-] Orifice discharge coefficient *)
    DL_RHO : REAL := 1200.0;        (* 涂料密度（通用常量） [kg/m3] Paint density [kg/m3] *)
    DL_BAR_PA : REAL := 100000.0;   (* bar → Pa 换算 [Pa/bar] Bar to pascal *)
    DL_MM2_M2 : REAL := 1.0E6;      (* mm2 → m2 换算 [mm2/m2] Square millimetre to square metre *)
    DL_M3_ML : REAL := 1.0E6;       (* m3 → ml 换算 [ml/m3] Cubic metre to millilitre *)
    DL_SECMIN : REAL := 60.0;       (* 每秒 → 每分钟换算 [s/min] Second to minute *)
    DL_KVISC : REAL := 0.3;         (* 粘度修正系数 [-] Viscosity correction coefficient *)
    DL_VISC_REF : REAL := 100.0;    (* 粘度修正基准 [cSt] Viscosity reference [cSt] *)
    DL_ATOM_RATIO : REAL := 0.85;   (* 雾化压力/供压比 [-] Atomizing to supply ratio *)
    DL_ATOM_MIN : REAL := 0.5;      (* 雾化压力下限 [bar] Atomizing pressure floor [bar] *)
    DL_ATOM_MAX : REAL := 6.0;      (* 雾化压力上限 [bar] Atomizing pressure ceiling [bar] *)
    DL_PI_Q : REAL := 0.7853981633974483;  (* π/4（圆面积系数） [-] Quarter pi *)
    DL_DIA_MIN : REAL := 0.2;       (* 孔径下限 [mm] Diameter floor [mm] *)
    DL_DIA_MAX : REAL := 5.0;       (* 孔径上限 [mm] Diameter ceiling [mm] *)
    DL_P_MIN : REAL := 0.5;         (* 供压下限 [bar] Pressure floor [bar] *)
    DL_P_MAX : REAL := 10.0;        (* 供压上限 [bar] Pressure ceiling [bar] *)
    DL_V_MIN : REAL := 5.0;         (* 粘度下限 [cSt] Viscosity floor [cSt] *)
    DL_V_MAX : REAL := 2000.0;      (* 粘度上限 [cSt] Viscosity ceiling [cSt] *)
    DL_Q_MIN : REAL := 10.0;        (* 流量上限下限 [ml/min] Ceiling floor [ml/min] *)
    DL_Q_MAX : REAL := 5000.0;      (* 流量上限上限 [ml/min] Ceiling top [ml/min] *)
END_VAR
VAR
    fAreaM2 : REAL;     (* 孔口面积 [m2] Orifice area [m2] *)
    fDpPa : REAL;       (* 压差 [Pa] Differential pressure [Pa] *)
    fKvisc : REAL;      (* 粘度修正系数 [-] Viscosity correction factor *)
    fQm3s : REAL;       (* 体积流量 [m3/s] Volumetric flow [m3/s] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fFlowMlmin := 0.0; fAtomPressBar := 0.0; xClamped := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fNozzleDiaMm <> fNozzleDiaMm) OR ((fNozzleDiaMm - fNozzleDiaMm) <> 0.0)
   OR (fPressBar <> fPressBar) OR ((fPressBar - fPressBar) <> 0.0)
   OR (fViscCst <> fViscCst) OR ((fViscCst - fViscCst) <> 0.0)
   OR (fFlowMaxMlmin <> fFlowMaxMlmin) OR ((fFlowMaxMlmin - fFlowMaxMlmin) <> 0.0) THEN
    FC_DL_SprayFlowRateCalc := -1.0;        (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：孔径、供压、粘度、泵上限逐项定域 *)
IF (fNozzleDiaMm < DL_DIA_MIN) OR (fNozzleDiaMm > DL_DIA_MAX)
   OR (fPressBar < DL_P_MIN) OR (fPressBar > DL_P_MAX)
   OR (fViscCst < DL_V_MIN) OR (fViscCst > DL_V_MAX)
   OR (fFlowMaxMlmin < DL_Q_MIN) OR (fFlowMaxMlmin > DL_Q_MAX) THEN
    FC_DL_SprayFlowRateCalc := -1.0;        (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 孔口面积：π/4·d² [mm2] ÷ 1e6 = m2 *)
fAreaM2 := (DL_PI_Q * fNozzleDiaMm * fNozzleDiaMm) / DL_MM2_M2;
(* 压差：bar × 1e5 = Pa *)
fDpPa := fPressBar * DL_BAR_PA;
(* 粘度修正：ν/100 无量纲，开方后按 0.3 权重并入分母，恒在 (0, 1] 区间 *)
fKvisc := 1.0 / (1.0 + DL_KVISC * SQRT(fViscCst / DL_VISC_REF));
(* 孔口流量：m2 × √(Pa/(kg/m3)) = m2 × m/s = m3/s *)
fQm3s := DL_CD * fAreaM2 * SQRT((2.0 * fDpPa) / DL_RHO) * fKvisc;
(* 单位换算：m3/s → ml/min *)
fFlowMlmin := fQm3s * DL_M3_ML * DL_SECMIN;
(* 泵上限钳位：置钳位标志，有效性不变（事实未伪造） *)
IF fFlowMlmin > fFlowMaxMlmin THEN
    fFlowMlmin := fFlowMaxMlmin;
    xClamped := TRUE;
END_IF
(* 雾化压力：供压 85 %，钳 0.5~6 bar *)
fAtomPressBar := fPressBar * DL_ATOM_RATIO;
IF fAtomPressBar < DL_ATOM_MIN THEN
    fAtomPressBar := DL_ATOM_MIN;
ELSIF fAtomPressBar > DL_ATOM_MAX THEN
    fAtomPressBar := DL_ATOM_MAX;
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_SprayFlowRateCalc := fFlowMlmin;
END_FUNCTION
