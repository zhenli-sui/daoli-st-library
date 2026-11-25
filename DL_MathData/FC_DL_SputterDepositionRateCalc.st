(*
  DL Factory R88 | FC_DL_SputterDepositionRateCalc
  功能：按工程简化式算溅射沉积速率 r=Y·P/(A·ρ)（Y 为含产额与几何折算的综合系数），并按带宽判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 溅射速率 r∝溅射产额×功率/(靶面积×密度)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_SputterDepositionRateCalc : REAL
VAR_INPUT
    fSputterYield : REAL := 2.5; // 综合速率系数 Y（含溅射产额/几何/单位折算） [-] / lumped rate coefficient [-]
    fPowerKW : REAL := 5.0; // 靶面输入功率 P [kW] / target input power [kW]
    fTargetAreaCm2 : REAL := 300.0; // 靶材有效溅射面积 A [cm²] / effective target area [cm^2]
    fDensityGcm3 : REAL := 10.2; // 靶材密度 ρ（铜 8.96，钼 10.2，铝 2.70） [g/cm³] / target density [g/cm^3]
    fMinNmMin : REAL := 10.0; // 速率允许下限（工艺带宽） [nm/min] / lower rate band [nm/min]
    fMaxNmMin : REAL := 200.0; // 速率允许上限（工艺带宽） [nm/min] / upper rate band [nm/min]
END_VAR
VAR_OUTPUT
    fRateNmMin : REAL; // 沉积速率 r [nm/min] / deposition rate [nm/min]
    xInBand : BOOL; // TRUE=速率落在允许带宽内 [-] / TRUE when inside the band [-]
END_VAR
VAR
    fDenom : REAL; // 分母 A·ρ（除零判据，单位 g/cm） [-] / denominator, the divisor [-]
    fNum : REAL; // 分子 Y·P [kW] / numerator [kW]
END_VAR

// 段 1｜出口预置
FC_DL_SputterDepositionRateCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fRateNmMin := 0.0; // 沉积速率预置零 [nm/min] / rate preset zero [nm/min]
xInBand := FALSE; // 带宽位预置 FALSE（未判定前不认合格） [-] / band flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fSputterYield > -1.0E30 AND fSputterYield < 1.0E30) OR NOT (fPowerKW > -1.0E30 AND fPowerKW < 1.0E30) OR NOT (fTargetAreaCm2 > -1.0E30 AND fTargetAreaCm2 < 1.0E30) THEN
    RETURN; // 综合系数/功率/靶面积任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fDensityGcm3 > -1.0E30 AND fDensityGcm3 < 1.0E30) OR NOT (fMinNmMin > -1.0E30 AND fMinNmMin < 1.0E30) OR NOT (fMaxNmMin > -1.0E30 AND fMaxNmMin < 1.0E30) THEN
    RETURN; // 密度/带宽上下限任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fSputterYield <= 0.0 OR fPowerKW < 0.0 OR fTargetAreaCm2 < 1.0E-9 OR fDensityGcm3 < 1.0E-9 THEN
    RETURN; // 综合系数正域闸 + 功率非负闸 + 面积/密度正域闸（分母不得为零） [-] / positive gates
END_IF
IF fMinNmMin <= 0.0 OR fMaxNmMin <= fMinNmMin THEN
    RETURN; // 带宽自洽闸：下限须为正、上限须严格大于下限 [nm/min] / band consistency gate [nm/min]
END_IF

// 段 3｜计算（工程简化：不计靶面侵蚀不均、挡板遮挡与基片距离修正）
fNum := fSputterYield * fPowerKW; // [-] × kW = kW，分子合成 [kW] / [-] x [kW] = [kW]
fDenom := fTargetAreaCm2 * fDensityGcm3; // cm² × g/cm³ = g/cm，分母合成 [-] / [g/cm^3 x cm^2]
IF fDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：A·ρ 必须大于 1E-9 才可作除数 [-] / denominator gate before the division [-]
END_IF
fRateNmMin := fNum / fDenom; // 综合系数已含单位折算，商即 nm/min [nm/min] / rate [nm/min]

// 段 4｜判定与饱和
IF NOT (fRateNmMin > -1.0E30 AND fRateNmMin < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xInBand := (fRateNmMin >= fMinNmMin) AND (fRateNmMin <= fMaxNmMin); // 双侧闭区间直比 [nm/min] / closed two sided band compare [nm/min]

// 段 5｜出口自检
IF fRateNmMin < 0.0 THEN
    RETURN; // 出口自检：速率不得为负（负值说明功率符号错） [nm/min] / rate must not be negative [nm/min]
END_IF
FC_DL_SputterDepositionRateCalc := fRateNmMin; // 返回沉积速率 [nm/min] / return the deposition rate [nm/min]
END_FUNCTION
