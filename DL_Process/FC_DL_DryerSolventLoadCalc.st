(*
  DL Factory R83 | FC_DL_DryerSolventLoadCalc
  功能：由耗墨量、溶剂配比与排风量估算干燥箱溶剂负荷浓度并做安全裕度校验。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_DryerSolventLoadCalc : REAL
VAR_INPUT
    fInkKgH     : REAL; // 单位时间油墨耗量 [kg/h] / Ink consumption rate [kg/h]
    fSolventPct : REAL; // 油墨中溶剂质量占比（0~100）[%] / Solvent mass fraction [%]
    fAirFlowM3H : REAL; // 干燥箱排风量 [m³/h] / Dryer exhaust air flow [m^3/h]
    fLelGm3     : REAL; // 溶剂爆炸下限浓度 [g/m³] / Lower explosive limit [g/m^3]
    fSafetyPct  : REAL; // 安全裕度（允许占 LEL 比例，0~100）[%] / Safety margin of LEL [%]
END_VAR
VAR_OUTPUT
    fSolventKgH : REAL; // 溶剂挥发速率 [kg/h] / Solvent evaporation rate [kg/h]
    fConcGm3    : REAL; // 排风溶剂浓度 [g/m³] / Solvent concentration in exhaust [g/m^3]
    xSafe       : BOOL; // 安全裕度内（TRUE=可继续生产）/ Within safety margin, TRUE = safe
END_VAR
VAR
    fLimitGm3 : REAL; // 允许浓度上限 [g/m³] / Allowed concentration ceiling [g/m^3]
END_VAR
fSolventKgH := 0.0; fConcGm3 := 0.0; xSafe := FALSE;  // 出口预置，安全侧默认不可继续
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fInkKgH > -1.0E30 AND fInkKgH < 1.0E30) OR NOT (fSolventPct > -1.0E30 AND fSolventPct < 1.0E30) OR NOT (fAirFlowM3H > -1.0E30 AND fAirFlowM3H < 1.0E30) OR NOT (fLelGm3 > -1.0E30 AND fLelGm3 < 1.0E30) OR NOT (fSafetyPct > -1.0E30 AND fSafetyPct < 1.0E30) OR fInkKgH < 0.0 OR fLelGm3 <= 0.0 OR fSafetyPct <= 0.0 THEN
    FC_DL_DryerSolventLoadCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 溶剂配比域闸：0~100% 之外钳位
IF fSolventPct < 0.0 THEN
    fSolventPct := 0.0;             // 下限钳位 [%] / Clamp lower bound
ELSIF fSolventPct > 100.0 THEN
    fSolventPct := 100.0;           // 上限钳位 [%] / Clamp upper bound
END_IF
// 溶剂挥发速率：kg/h × 质量占比 = kg/h（量纲保持）
fSolventKgH := fInkKgH * (fSolventPct / 100.0);   // 挥发速率 [kg/h] / Evaporation rate [kg/h]
// 排风量零闸后换算浓度：kg/h × 1000 ÷ (m³/h) = g/m³（R4/R21）
IF ABS(fAirFlowM3H) > 1.0E-9 THEN    // 分母显式零闸 / Explicit denominator zero gate
    fConcGm3 := fSolventKgH * 1000.0 / fAirFlowM3H;  // 排风浓度 [g/m³] / Exhaust concentration
ELSE
    fConcGm3 := 0.0;                 // 无排风时浓度不可算，由 xSafe 拦截 / No airflow, default zero
END_IF
// 安全裕度：允许浓度 = LEL × 裕度比例（g/m³ × 无量纲 = g/m³）
fLimitGm3 := fLelGm3 * (fSafetyPct / 100.0);  // 允许浓度上限 [g/m³] / Allowed ceiling [g/m^3]
IF fAirFlowM3H > 0.0 AND fConcGm3 < fLimitGm3 THEN
    xSafe := TRUE;                   // 浓度低于裕度上限 / Concentration below ceiling
ELSE
    xSafe := FALSE;                  // 无排风或浓度超限 / No airflow or over limit
END_IF
FC_DL_DryerSolventLoadCalc := fConcGm3;   // 返回排风浓度 [g/m³] / Return exhaust concentration
END_FUNCTION
