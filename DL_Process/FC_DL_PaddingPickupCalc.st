(*
  DL Factory R83 | FC_DL_PaddingPickupCalc
  功能：由轧车前干重与轧后湿重算轧余率，并按克重门幅速度换算带液量。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_PaddingPickupCalc : REAL
VAR_INPUT
    fWetMassG : REAL; // 轧后湿重试样质量 [g] / Wet mass after padding [g]
    fDryMassG : REAL; // 轧前干重试样质量 [g] / Dry mass before padding [g]
    fSpeedMpm : REAL; // 轧车线速度 [m/min] / Padder line speed [m/min]
    fWidthM   : REAL; // 织物门幅 [m] / Fabric width [m]
    fGsm      : REAL; // 织物干克重 [g/m²] / Dry grammage [g/m^2]
END_VAR
VAR_OUTPUT
    fPickupPct : REAL; // 轧余率（带液量占干布重）[%] / Wet pickup [%]
    fCarryLpm  : REAL; // 每分钟带液量（密度按 1 kg/L 近似）[L/min] / Liquor carry-over [L/min]
    fCarryKgH  : REAL; // 每小时带液量 [kg/h] / Liquor carry-over [kg/h]
    xValid     : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fDryKgMin : REAL; // 每分钟干布质量 [kg/min] / Dry fabric mass per minute [kg/min]
END_VAR
// 出口预置：四出口统一预置（R256）
fPickupPct := 0.0; fCarryLpm := 0.0; fCarryKgH := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 湿干重次序闸（R20/R21）
IF NOT (fWetMassG > -1.0E30 AND fWetMassG < 1.0E30) OR NOT (fDryMassG > -1.0E30 AND fDryMassG < 1.0E30) OR NOT (fSpeedMpm > -1.0E30 AND fSpeedMpm < 1.0E30) OR NOT (fWidthM > -1.0E30 AND fWidthM < 1.0E30) OR NOT (fGsm > -1.0E30 AND fGsm < 1.0E30) OR fDryMassG <= 0.0 OR fSpeedMpm <= 0.0 OR fWidthM <= 0.0 OR fGsm <= 0.0 OR fWetMassG < fDryMassG THEN
    FC_DL_PaddingPickupCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲/次序越界 / Sentinel -1
END_IF
// 轧余率：(湿重 - 干重) ÷ 干重 × 100，干重分母已零闸（R4/R21）
IF ABS(fDryMassG) > 1.0E-9 THEN                // 干重分母显式零闸 / Explicit zero gate on dry mass
    fPickupPct := (fWetMassG - fDryMassG) / fDryMassG * 100.0; // 轧余率 [%] / Wet pickup [%]
ELSE
    fPickupPct := 0.0;              // 除零防御缺省 [%] / Divide-by-zero default
END_IF
// 每分钟干布质量：g/m² × m × m/min ÷ 1000 = kg/min（m² 与 m 相乘后 g→kg 需除 1000）
fDryKgMin := fGsm * fWidthM * fSpeedMpm / 1000.0;  // 干布质量流率 [kg/min] / Dry mass flow
// 带液量：干布流率 × 轧余率 ÷ 100，密度按 1 kg/L 近似故 kg/min 与 L/min 数值等同
fCarryLpm := fDryKgMin * (fPickupPct / 100.0);     // 每分钟带液 [L/min] / Carry-over [L/min]
fCarryKgH := fCarryLpm * 60.0;                    // 每小时带液 [kg/h] / Carry-over [kg/h]
xValid    := TRUE;                                 // 链路有效 / Chain valid
FC_DL_PaddingPickupCalc := fPickupPct;             // 返回轧余率 [%] / Return wet pickup [%]
END_FUNCTION
