(*
  DL Factory R83 | FC_DL_ImpulseSealDwellCalc
  功能：按热封面积、膜厚与温升用能量平衡算通电时间，并给出保压冷却时间。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_ImpulseSealDwellCalc : REAL
VAR_INPUT
    fSealAreaMm2  : REAL; // 热封有效面积 [mm²] / Effective seal area [mm^2]
    fFilmThickUm  : REAL; // 封合膜总厚度 [µm] / Total film thickness [um]
    fSealTempC    : REAL; // 热封目标温度 [°C] / Seal target temperature [degC]
    fAmbTempC     : REAL; // 环境（初始）温度 [°C] / Ambient initial temperature [degC]
    fHeaterPowerW : REAL; // 热封头有效功率 [W] / Effective sealer power [W]
END_VAR
VAR_OUTPUT
    fHeatTimeMs  : REAL; // 通电加热时间 [ms] / Power-on heating time [ms]
    fDwellTimeMs : REAL; // 保压冷却时间 [ms] / Dwell cooling time [ms]
    xValid       : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fMassG    : REAL; // 封合区膜料质量 [g] / Film mass in seal zone [g]
    fEnergyJ  : REAL; // 所需热量 [J] / Required heat energy [J]
    cDensity  : REAL := 0.92; // 膜密度常量 [g/cm³]，已引用（R19）/ Film density [g/cm^3]
    cSpecHeat : REAL := 1.70; // 比热容常量 [J/(g·K)]，已引用（R19）/ Specific heat [J/(g.K)]
    cEff      : REAL := 0.35; // 热效率常量 [-]，已引用（R19）/ Thermal efficiency [-]
END_VAR
// 出口预置：三出口统一预置（R256）
fHeatTimeMs := 0.0; fDwellTimeMs := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 温升方向检查（R20/R21）
IF NOT (fSealAreaMm2 > -1.0E30 AND fSealAreaMm2 < 1.0E30) OR NOT (fFilmThickUm > -1.0E30 AND fFilmThickUm < 1.0E30) OR NOT (fSealTempC > -1.0E30 AND fSealTempC < 1.0E30) OR NOT (fAmbTempC > -1.0E30 AND fAmbTempC < 1.0E30) OR NOT (fHeaterPowerW > -1.0E30 AND fHeaterPowerW < 1.0E30) OR fSealAreaMm2 <= 0.0 OR fFilmThickUm <= 0.0 OR fHeaterPowerW <= 0.0 OR fSealTempC <= fAmbTempC THEN
    FC_DL_ImpulseSealDwellCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲/温升越界 / Sentinel -1
END_IF
// 质量：mm² × µm × 1E-6 = cm³，再乘 g/cm³ 得 g（量纲自洽：1 µm = 1E-3 mm，故 1E-3 mm³ = 1E-6 cm³）
fMassG := fSealAreaMm2 * fFilmThickUm * 1.0E-6 * cDensity;   // 封合区质量 [g] / Film mass [g]
// 热量：Q = m × c × ΔT，ΔT 为设定与环境之差（K 与 °C 同尺度，故可直接相减）
fEnergyJ := fMassG * cSpecHeat * (fSealTempC - fAmbTempC);   // 所需热量 [J] / Required energy [J]
// 通电时间：J ÷ W = s，×1000 = ms，再除以热效率放大（含热损，故非恒等式）
fHeatTimeMs := (fEnergyJ / fHeaterPowerW) * 1000.0 / cEff;   // 通电时间 [ms] / Heating time [ms]
// 保压时间：取通电时间 40% 加厚膜附加项，保证熔接层冷却定型
fDwellTimeMs := fHeatTimeMs * 0.40 + 50.0 + fFilmThickUm * 0.5; // 保压时间 [ms] / Dwell time [ms]
xValid := TRUE;                                                // 链路有效 / Chain valid
FC_DL_ImpulseSealDwellCalc := fHeatTimeMs;                     // 返回通电时间 [ms] / Return heating time
END_FUNCTION
