(*
  DL Factory R88 | FC_DL_EpitaxyGrowthRateCalc
  功能：由厚度/时长算外延生长速率，并给 Arrhenius 归一化因子 exp(-Ea/(k·T))（T 由 °C 换算 K）
  开源溯源：无（clean-room 自研，依据公开工艺公式 生长速率与 Arrhenius 温度依赖式 exp(-Ea/kT)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_EpitaxyGrowthRateCalc : REAL
VAR_INPUT
    fThkUm : REAL := 2.0; // 外延层厚度 [µm] / epitaxial layer thickness [um]
    fDurMin : REAL := 30.0; // 生长时长 [min] / growth duration [min]
    fTempC : REAL := 1100.0; // 生长温度（摄氏） [°C] / growth temperature in Celsius [degC]
    fEaEV : REAL := 3.5; // 激活能 Ea（Si 外延常用 1.0~3.5 区间高端） [eV] / activation energy [eV]
END_VAR
VAR_OUTPUT
    fRateUmMin : REAL; // 生长速率 =厚度/时长 [µm/min] / growth rate [um/min]
    fArrheniusFactor : REAL; // Arrhenius 归一化因子 exp(-Ea/kT) [-] / Arrhenius factor [-]
END_VAR
VAR
    fTempK : REAL; // 绝对温度 T [K] / absolute temperature [K]
    fKtEV : REAL; // k·T（除零判据） [eV] / thermal energy, the divisor [eV]
    fExpArg : REAL; // 指数自变量 -Ea/(k·T) [-] / exponent argument [-]
END_VAR

// 段 1｜出口预置
FC_DL_EpitaxyGrowthRateCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fRateUmMin := 0.0; // 生长速率预置零 [µm/min] / rate preset zero [um/min]
fArrheniusFactor := 0.0; // Arrhenius 因子预置零 [-] / Arrhenius factor preset zero [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fThkUm > -1.0E30 AND fThkUm < 1.0E30) OR NOT (fDurMin > -1.0E30 AND fDurMin < 1.0E30) THEN
    RETURN; // 厚度/时长任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fTempC > -1.0E30 AND fTempC < 1.0E30) OR NOT (fEaEV > -1.0E30 AND fEaEV < 1.0E30) THEN
    RETURN; // 温度/激活能任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fThkUm < 0.0 OR fDurMin < 1.0E-9 THEN
    RETURN; // 厚度非负闸 + 时长正域闸（同为本式分母，防除零） [µm, min] / positive gates
END_IF
IF fTempC < -273.15 OR fEaEV <= 0.0 THEN
    RETURN; // 绝对零度闸 + 激活能正域闸（非正值使指数项退化为 1） [°C, eV] / temperature and energy gates
END_IF

// 段 3｜计算（EXP 的上/下饱和统一放到段 4 处理，避免同拍抹除计算结果）
fRateUmMin := fThkUm / fDurMin; // µm ÷ min = µm/min，生长速率 [µm/min] / [um] / [min] = [um/min]
fTempK := fTempC + 273.15; // °C + 273.15 = K，温度换算 [K] / [degC] + 273.15 = [K]
fKtEV := 8.617333E-5 * fTempK; // (eV/K) × K = eV，热能 kT（k=8.617333e-5 eV/K） [eV] / [eV]
IF fKtEV < 1.0E-9 THEN
    RETURN; // 除法前分母闸：k·T 必须大于 1E-9 才可作除数 [eV] / denominator gate [eV]
END_IF
fExpArg := -fEaEV / fKtEV; // eV ÷ eV = 无量纲并取负，指数自变量 [-] / [-] dimensionless argument
fArrheniusFactor := EXP(fExpArg); // 无量纲 → 无量纲，Arrhenius 归一化因子 [-] / Arrhenius factor [-]

// 段 4｜判定与饱和
IF NOT (fRateUmMin > -1.0E30 AND fRateUmMin < 1.0E30) OR NOT (fArrheniusFactor > -1.0E30 AND fArrheniusFactor < 1.0E30) THEN
    RETURN; // 两出口非有限再拦一次 [-] / re-check both results for finiteness [-]
END_IF
IF fExpArg < -80.0 THEN
    fArrheniusFactor := 0.0; // 下饱和：自变量过小按 0 夹紧（物理上趋于冻结），不依赖编译器下溢行为 [-] / clamp underflow to zero
ELSIF fArrheniusFactor > 1.0 THEN
    fArrheniusFactor := 1.0; // 上饱和：归一化因子理论上限为 1 [-] / saturate the factor at one [-]
END_IF

// 段 5｜出口自检
IF fRateUmMin < 0.0 THEN
    RETURN; // 出口自检：生长速率不得为负（负值说明厚度符号错） [µm/min] / rate must not be negative [um/min]
END_IF
FC_DL_EpitaxyGrowthRateCalc := fRateUmMin; // 返回生长速率 [µm/min] / return the growth rate [um/min]
END_FUNCTION
