(*
  DL Factory R88 | FC_DL_PlasmaPowerDensityCalc
  功能：算等离子体功率密度 P/A，并按 1~5 W/cm² 工艺带宽判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 功率密度定义式 P/A，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_PlasmaPowerDensityCalc : REAL
VAR_INPUT
    fPowerW : REAL := 800.0; // 射频/直流输入功率 P [W] / RF or DC input power [W]
    fAreaCm2 : REAL := 400.0; // 电极（或基片）有效面积 A [cm²] / effective electrode area [cm^2]
    fMinWPerCm2 : REAL := 1.0; // 功率密度允许下限 [W/cm²] / lower density band [W/cm^2]
    fMaxWPerCm2 : REAL := 5.0; // 功率密度允许上限 [W/cm²] / upper density band [W/cm^2]
END_VAR
VAR_OUTPUT
    fDensityWPerCm2 : REAL; // 功率密度 [W/cm²] / power density [W/cm^2]
    xInBand : BOOL; // TRUE=功率密度落在允许带宽内 [-] / TRUE when inside the band [-]
END_VAR
VAR
    fAreaDenom : REAL; // 面积分母（除零判据） [cm²] / area divisor [cm^2]
END_VAR

// 段 1｜出口预置
FC_DL_PlasmaPowerDensityCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fDensityWPerCm2 := 0.0; // 功率密度预置零 [W/cm²] / density preset zero [W/cm^2]
xInBand := FALSE; // 带宽位预置 FALSE（未判定前不认合格） [-] / band flag preset false [-]
fAreaDenom := 0.0; // 面积分母预置零 [cm²] / area divisor preset zero [cm^2]

// 段 2｜非有限拦截 + 域闸
IF NOT (fPowerW > -1.0E30 AND fPowerW < 1.0E30) OR NOT (fAreaCm2 > -1.0E30 AND fAreaCm2 < 1.0E30) THEN
    RETURN; // 功率/面积任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fMinWPerCm2 > -1.0E30 AND fMinWPerCm2 < 1.0E30) OR NOT (fMaxWPerCm2 > -1.0E30 AND fMaxWPerCm2 < 1.0E30) THEN
    RETURN; // 带宽上下限任一非有限则判据静默失效，故先拦 [W/cm²] / band limits must be finite [W/cm^2]
END_IF
IF fPowerW < 0.0 THEN
    RETURN; // 功率非负闸（负功率无物理意义） [W] / non negative power gate [W]
END_IF
IF fAreaCm2 < 1.0E-9 THEN
    RETURN; // 面积正域闸（同时是分母，防除零） [cm²] / positive area, also the divisor [cm^2]
END_IF
IF fMinWPerCm2 <= 0.0 OR fMaxWPerCm2 <= fMinWPerCm2 THEN
    RETURN; // 带宽自洽闸：下限须为正、上限须严格大于下限 [W/cm²] / band consistency gate [W/cm^2]
END_IF

// 段 3｜计算
fAreaDenom := fAreaCm2; // 取面积作除数 [cm²] / take the area as divisor [cm^2]
IF fAreaDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：面积必须大于 1E-9 才可作除数 [cm²] / denominator gate before the division [cm^2]
END_IF
fDensityWPerCm2 := fPowerW / fAreaDenom; // W ÷ cm² = W/cm²，功率密度 [W/cm²] / [W] / [cm^2] = [W/cm^2]

// 段 4｜判定与饱和
IF NOT (fDensityWPerCm2 > -1.0E30 AND fDensityWPerCm2 < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xInBand := (fDensityWPerCm2 >= fMinWPerCm2) AND (fDensityWPerCm2 <= fMaxWPerCm2); // 双侧闭区间直比 [W/cm²] / closed two sided band compare [W/cm^2]

// 段 5｜出口自检
IF fDensityWPerCm2 < 0.0 THEN
    RETURN; // 出口自检：功率密度不得为负（负值说明输入符号错） [W/cm²] / must not be negative [W/cm^2]
END_IF
FC_DL_PlasmaPowerDensityCalc := fDensityWPerCm2; // 返回功率密度 [W/cm²] / return the power density [W/cm^2]
END_FUNCTION
