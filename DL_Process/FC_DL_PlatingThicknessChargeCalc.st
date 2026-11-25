(*
  DL Factory R83 | FC_DL_PlatingThicknessChargeCalc
  功能：按法拉第定律由电流密度、时间与电流效率算镀层厚度并折算电量。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_PlatingThicknessChargeCalc : REAL
VAR_INPUT
    fCurrentDens  : REAL; // 阴极电流密度 [A/dm²] / Cathodic current density [A/dm^2]
    fTimeS        : REAL; // 通电时间 [s] / Plating time [s]
    fEffPct       : REAL; // 电流效率（0~100）[%] / Current efficiency [%]
    fEquivMgC     : REAL; // 电化当量 [mg/C] / Electrochemical equivalent [mg/C]
    fMetalDensity : REAL; // 镀层金属密度 [g/cm³] / Deposit density [g/cm^3]
END_VAR
VAR_OUTPUT
    fMassG    : REAL; // 单位面积沉积质量 [g/dm²] / Deposited mass per area [g/dm^2]
    fThickUm  : REAL; // 镀层厚度 [µm] / Deposit thickness [um]
    fChargeAh : REAL; // 单位面积电量 [Ah/dm²] / Charge per area [Ah/dm^2]
    xValid    : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fEffK : REAL; // 电流效率归一化系数 [-]/ Normalised efficiency factor
END_VAR
// 出口预置：四出口统一预置（R256）
fMassG := 0.0; fThickUm := 0.0; fChargeAh := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fCurrentDens > -1.0E30 AND fCurrentDens < 1.0E30) OR NOT (fTimeS > -1.0E30 AND fTimeS < 1.0E30) OR NOT (fEffPct > -1.0E30 AND fEffPct < 1.0E30) OR NOT (fEquivMgC > -1.0E30 AND fEquivMgC < 1.0E30) OR NOT (fMetalDensity > -1.0E30 AND fMetalDensity < 1.0E30) OR fCurrentDens < 0.0 OR fTimeS < 0.0 OR fEquivMgC <= 0.0 OR fMetalDensity <= 0.0 THEN
    FC_DL_PlatingThicknessChargeCalc := -1.0; RETURN; // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 电流效率域闸：0~100% 之外钳位（效率不可能超 100）
IF fEffPct < 0.0 THEN
    fEffK := 0.0;                   // 效率零下限 [-] / Efficiency lower bound zero
ELSIF fEffPct > 100.0 THEN
    fEffK := 1.0;                   // 效率满上限 [-] / Efficiency upper bound unity
ELSE
    fEffK := fEffPct / 100.0;       // 归一化效率 [-] / Normalised efficiency
END_IF
// 沉积质量：mg/C ÷ 1000 = g/C；g/C × A/dm² × s = g/dm²（量纲自洽：C = A·s）
fMassG := (fEquivMgC / 1000.0) * fEffK * fCurrentDens * fTimeS; // 单位面积质量 [g/dm²]
// 厚度：1 dm² = 100 cm²，故 µm = 100 × (g/dm²) ÷ (g/cm³)，密度分母显式零闸（R4/R21）
IF ABS(fMetalDensity) > 1.0E-9 THEN            // 密度分母显式零闸 / Explicit zero gate on density
    fThickUm := 100.0 * fMassG / fMetalDensity; // 镀层厚度 [µm] / Deposit thickness [um]
ELSE
    fThickUm := 0.0;                // 除零防御缺省 [µm] / Divide-by-zero default
END_IF
// 电量：A/dm² × s ÷ 3600 = Ah/dm²（s→h 换算常数 3600）
fChargeAh := fCurrentDens * fTimeS / 3600.0;   // 单位面积电量 [Ah/dm²] / Charge per area
xValid    := TRUE;                             // 链路有效 / Chain valid
FC_DL_PlatingThicknessChargeCalc := fThickUm;  // 返回镀层厚度 [µm] / Return deposit thickness
END_FUNCTION
