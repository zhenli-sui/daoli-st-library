(*
  DL Factory R84 | FC_DL_KilnSpecificHeatCalc
  功能：算单位熟料热耗并折算标准煤耗与实物煤耗
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_KilnSpecificHeatCalc : REAL
VAR_INPUT
    fFuelKgh : REAL := 8000.0; // 燃料消耗量（实物煤） [kg/h] / fuel consumption [kg/h]
    fLhvKcalkg : REAL := 5500.0; // 燃料低位热值 [kcal/kg] / lower heating value [kcal/kg]
    fClinkerTph : REAL := 250.0; // 熟料产量 [t/h] / clinker output [t/h]
    fKgceKcalkg : REAL := 7000.0; // 标准煤当量热值 [kcal/kgce] / standard coal equivalent [kcal/kgce]
END_VAR
VAR_OUTPUT
    fKgcePerT : REAL; // 折标准煤耗 [kgce/t] / standard coal consumption [kgce/t]
    fCoalRate : REAL; // 实物煤耗 [kg/t] / actual coal rate [kg/t]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fKcalH : REAL; // 小时供热量 [kcal/h] / hourly heat input [kcal/h]
    fClinkerKgh : REAL; // 熟料小时产量折算 [kg/h] / clinker output in kilograms [kg/h]
    fSpecKcalkg : REAL; // 单位熟料热耗 [kcal/kg] / specific heat consumption [kcal/kg]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_KilnSpecificHeatCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fKgcePerT := 0.0; // 标煤耗预置零 [kgce/t] / standard coal preset zero [kgce/t]
fCoalRate := 0.0; // 实物煤耗预置零 [kg/t] / actual coal rate preset zero [kg/t]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fFuelKgh > -1.0E30 AND fFuelKgh < 1.0E30) OR NOT (fLhvKcalkg > -1.0E30 AND fLhvKcalkg < 1.0E30) OR NOT (fClinkerTph > -1.0E30 AND fClinkerTph < 1.0E30) OR NOT (fKgceKcalkg > -1.0E30 AND fKgceKcalkg < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fFuelKgh < 0.0 OR fLhvKcalkg < 1.0E-9 OR fKgceKcalkg < 1.0E-9 THEN
    RETURN; // 热值与标煤当量正域分母闸（防除零） [kcal/kg] / positive denominator gate [kcal/kg]
END_IF
IF fClinkerTph < 1.0E-9 THEN
    RETURN; // 熟料产量正域分母闸（防除零） [t/h] / clinker output denominator gate [t/h]
END_IF

// 段 3｜单位热耗 = 燃料量 × 低位热值 / 熟料产量
fKcalH := fFuelKgh * fLhvKcalkg; // kg/h × kcal/kg = kcal/h / [kg/h] × [kcal/kg] = [kcal/h]
fClinkerKgh := fClinkerTph * 1000.0; // t/h × 1000 kg/t = kg/h / [t/h] × [kg/t] = [kg/h]
fSpecKcalkg := fKcalH / fClinkerKgh; // kcal/h ÷ kg/h = kcal/kg / [kcal/h] / [kg/h] = [kcal/kg]
IF NOT (fSpecKcalkg > -1.0E30 AND fSpecKcalkg < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜折标煤与实物煤耗
fKgcePerT := (fSpecKcalkg / fKgceKcalkg) * 1000.0; // (kcal/kg ÷ kcal/kgce) × 1000 kg/t = kgce/t / [kcal/kg]/[kcal/kgce]×[kg/t] = [kgce/t]
fCoalRate := fFuelKgh / fClinkerTph; // kg/h ÷ t/h = kg/t / [kg/h] / [t/h] = [kg/t]
IF NOT (fKgcePerT > -1.0E30 AND fKgcePerT < 1.0E30) OR NOT (fCoalRate > -1.0E30 AND fCoalRate < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_KilnSpecificHeatCalc := fSpecKcalkg; // 返回单位热耗 [kcal/kg] / return the specific heat [kcal/kg]
END_FUNCTION
