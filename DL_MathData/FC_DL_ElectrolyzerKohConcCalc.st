(*
  DL Factory R88 | FC_DL_ElectrolyzerKohConcCalc
  功能：由碱液密度反算 KOH 质量分数 w%=(ρ-1.0)/0.0105，并给经验电导率估计（线性经验式）
  开源溯源：无（clean-room 自研，依据公开工艺公式 碱液密度-浓度线性近似与电导率经验式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_ElectrolyzerKohConcCalc : REAL
VAR_INPUT
    fDensityGcm3 : REAL := 1.28; // 碱液密度 ρ（20~25°C 实测） [g/cm³] / electrolyte density [g/cm^3]
    fSlopeGcm3PerPct : REAL := 0.0105; // 密度对质量分数的经验斜率（每 1% 浓度） [g/cm³/%] / empirical density slope [g/cm^3 per pct]
    fCondCoeffSPerCm : REAL := 0.02; // 电导率经验系数（满量程前置系数） [S/cm] / empirical conductivity coefficient [S/cm]
END_VAR
VAR_OUTPUT
    fMassPct : REAL; // KOH 质量分数 w [%] / KOH mass fraction [%]
    fCondSPerCm : REAL; // 电导率经验估计 σ [S/cm] / estimated conductivity [S/cm]
END_VAR
VAR
    fSlope : REAL; // 斜率缓存（除零判据） [g/cm³/%] / cached slope, the divisor [g/cm^3 per pct]
    fNetDensity : REAL; // 密度超出水的部分 ρ-1.0 [g/cm³] / density above that of water [g/cm^3]
END_VAR

// 段 1｜出口预置
FC_DL_ElectrolyzerKohConcCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fMassPct := 0.0; // 质量分数预置零 [%] / mass fraction preset zero [%]
fCondSPerCm := 0.0; // 电导率预置零 [S/cm] / conductivity preset zero [S/cm]
fSlope := 0.0; // 斜率缓存预置零 [g/cm³/%] / slope preset zero [g/cm^3 per pct]
fNetDensity := 0.0; // 密度余量预置零 [g/cm³] / density surplus preset zero [g/cm^3]

// 段 2｜非有限拦截 + 域闸
IF NOT (fDensityGcm3 > -1.0E30 AND fDensityGcm3 < 1.0E30) OR NOT (fSlopeGcm3PerPct > -1.0E30 AND fSlopeGcm3PerPct < 1.0E30) THEN
    RETURN; // 密度/斜率任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fCondCoeffSPerCm > -1.0E30 AND fCondCoeffSPerCm < 1.0E30) THEN
    RETURN; // 电导系数非有限则第二出口无意义，故先拦 [S/cm] / the coefficient must be finite [S/cm]
END_IF
IF fDensityGcm3 <= 1.0 OR fDensityGcm3 >= 1.35 THEN
    RETURN; // 密度开区间域闸 (1.0,1.35)：低于水或超饱和则线性近似失效 [g/cm³] / density open interval gate [g/cm^3]
END_IF
IF fSlopeGcm3PerPct < 1.0E-9 THEN
    RETURN; // 除法前分母闸：斜率必须大于 1E-9（同时为正域闸） [g/cm³/%] / denominator gate [g/cm^3 per pct]
END_IF
IF fCondCoeffSPerCm <= 0.0 THEN
    RETURN; // 电导系数正域闸：非正值会使第二出口恒零 [S/cm] / positive coefficient gate [S/cm]
END_IF

// 段 3｜计算（经验式：非标准定义，仅用于 25°C 附近粗估）
fSlope := fSlopeGcm3PerPct; // 取斜率作除数缓存 [g/cm³/%] / cache the slope as divisor [g/cm^3 per pct]
fNetDensity := fDensityGcm3 - 1.0; // g/cm³ - g/cm³ = g/cm³，扣掉水的密度 [g/cm³] / density above water [g/cm^3]
fMassPct := fNetDensity / fSlope; // (g/cm³) ÷ (g/cm³/%) = %，线性近似反算浓度 [%] / [g/cm^3] / [g/cm^3 per pct] = [%]
IF fMassPct <= 0.0 OR fMassPct >= 100.0 THEN
    RETURN; // 浓度开区间闸 (0,100)：反算越界说明线性近似不适用 [%] / open interval gate on the fraction [%]
END_IF
fCondSPerCm := fCondCoeffSPerCm * fMassPct * (1.0 - fMassPct * 0.01); // S/cm × % × 无量纲 = S/cm，抛物线型经验式 [S/cm] / [S/cm]

// 段 4｜判定与饱和
IF NOT (fMassPct > -1.0E30 AND fMassPct < 1.0E30) OR NOT (fCondSPerCm > -1.0E30 AND fCondSPerCm < 1.0E30) THEN
    RETURN; // 两出口非有限再拦一次 [-] / re-check both results for finiteness [-]
END_IF

// 段 5｜出口自检
IF fCondSPerCm <= 0.0 THEN
    RETURN; // 出口自检：电导率须为正，否则经验式参数被误用 [S/cm] / conductivity must be positive [S/cm]
END_IF
FC_DL_ElectrolyzerKohConcCalc := fMassPct; // 返回 KOH 质量分数 [%] / return the KOH mass fraction [%]
END_FUNCTION
