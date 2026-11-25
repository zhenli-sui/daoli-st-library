(*
  DL Factory R84 | FC_DL_CncMrrCalc
  功能：算铣削材料去除率 MRR 并折算 cm³/min 与每分钟切屑质量
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_CncMrrCalc : REAL
VAR_INPUT
    fAp : REAL := 1.0; // 轴向切深 [mm] / axial depth of cut [mm]
    fAe : REAL := 5.0; // 径向切宽 [mm] / radial width of cut [mm]
    fVf : REAL := 800.0; // 进给速度 [mm/min] / feed rate [mm/min]
    fRho : REAL := 7.85; // 材料密度 [g/cm³] / material density [g/cm^3]
END_VAR
VAR_OUTPUT
    fMrrCm3Min : REAL; // 材料去除率折算 [cm³/min] / removal rate in [cm^3/min]
    fChipKgMin : REAL; // 每分钟切屑质量 [kg/min] / chip mass per minute [kg/min]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fMrrMm3 : REAL; // 材料去除率原始量 [mm³/min] / raw removal rate [mm^3/min]
    fGramMin : REAL; // 切屑质量流 [g/min] / chip mass flow [g/min]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_CncMrrCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fMrrCm3Min := 0.0; // cm³/min 预置零 / preset to zero [cm^3/min]
fChipKgMin := 0.0; // 切屑质量预置零 [kg/min] / chip mass preset zero [kg/min]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 物理域闸（R4/R20）
IF NOT (fAp > -1.0E30 AND fAp < 1.0E30) OR NOT (fAe > -1.0E30 AND fAe < 1.0E30) OR NOT (fVf > -1.0E30 AND fVf < 1.0E30) OR NOT (fRho > -1.0E30 AND fRho < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fAp < 0.0 OR fAe < 0.0 OR fVf < 0.0 THEN
    RETURN; // 几何量与进给不得为负 [-] / geometry and feed must not be negative [-]
END_IF
IF fRho <= 1.0E-9 THEN
    RETURN; // 密度正域闸（避免除零与零质量） [g/cm³] / density positive domain gate [g/cm^3]
END_IF

// 段 3｜主算：MRR = ap × ae × vf
fMrrMm3 := (fAp * fAe) * fVf; // mm × mm × mm/min = mm³/min / [mm] × [mm] × [mm/min] = [mm^3/min]
IF fMrrMm3 <= 0.0 THEN
    RETURN; // 零截面或零进给无去除量 [-] / zero section or zero feed removes nothing [-]
END_IF
fMrrCm3Min := fMrrMm3 / 1000.0; // mm³ ÷ 1000 = cm³（1 cm³ = 1000 mm³） / [mm^3] / 1000 = [cm^3]
fGramMin := fMrrCm3Min * fRho; // cm³/min × g/cm³ = g/min / [cm^3/min] × [g/cm^3] = [g/min]
fChipKgMin := fGramMin / 1000.0; // g/min ÷ 1000 = kg/min / [g/min] / 1000 = [kg/min]
IF NOT (fChipKgMin > -1.0E30 AND fChipKgMin < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the result [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_CncMrrCalc := fMrrMm3; // 返回 MRR [mm³/min] / return the removal rate [mm^3/min]
END_FUNCTION
