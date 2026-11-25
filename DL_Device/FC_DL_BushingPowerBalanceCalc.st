// FC_DL_BushingPowerBalanceCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 漏板电热功率平衡：输入功率 = I²·R [W]→[kW]（mΩ 除 1000 转 Ω，W 除 1000 转 kW），
        对流 = 12·A·ΔT/1000 [kW]（12 为自然对流综合换热系数 W/(m²·K)），
        辐射 = εσ·A·(T_K⁴ − Ta_K⁴)/1000 [kW]（ε = 0.85，σ = 5.67e-8），
        热效率 = 1 − (对流 + 辐射)/输入功率。
  邻件/码位: 与 FC_DL_BushingTempZoneCalc 为热平衡两侧（温度设定 vs 实际电功率与散热）；
             16#0002_9227 = 非有限、电阻/面积非正、温度不高于绝对零度、输入功率近零或效率出物理域。
*)
FUNCTION FC_DL_BushingPowerBalanceCalc : REAL
VAR_INPUT
    fCurrent     : REAL := 300.0;   // 漏板电流 [A]，域 > 0 / Bushing current [A]
    fResistance  : REAL := 30.0;    // 漏板电阻 [mΩ]，域 > 0 / Bushing resistance [mOhm]
    fSurfaceArea : REAL := 0.5;     // 漏板表面积 [m²]，域 > 0 / Surface area [m^2]
    fTemp        : REAL := 1200.0;  // 漏板温度 [°C] / Bushing temperature [degC]
    fAmbient     : REAL := 30.0;    // 环境温度 [°C] / Ambient temperature [degC]
END_VAR
VAR_OUTPUT
    fPowerIn    : REAL;             // 输入电功率 [kW] / Electrical input power [kW]
    fLossConv   : REAL;             // 对流散热 [kW] / Convective loss [kW]
    fLossRad    : REAL;             // 辐射散热 [kW] / Radiative loss [kW]
    fEfficiency : REAL;             // 热效率 [-] / Thermal efficiency
    bValid      : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fTK  : REAL := 0.0;             // 板绝对温度 [K] / Bushing absolute temperature [K]
    fTaK : REAL := 0.0;             // 环境绝对温度 [K] / Ambient absolute temperature [K]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fPowerIn := 0.0;                    // 输入功率缺省零 / Input power default zero
fLossConv := 0.0;                   // 对流散热缺省零 / Convective loss default zero
fLossRad := 0.0;                    // 辐射散热缺省零 / Radiative loss default zero
fEfficiency := 0.0;                 // 热效率缺省零 / Efficiency default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_BushingPowerBalanceCalc := 0.0;   // 返回值缺省零（镜像热效率）/ Return default zero
// 段 1：非有限闸（五入参全枚举）/ Non-finite gate over all inputs
IF (fCurrent <> fCurrent) OR (fResistance <> fResistance) OR (fSurfaceArea <> fSurfaceArea)
   OR (fTemp <> fTemp) OR (fAmbient <> fAmbient)
   OR (ABS(fCurrent) >= 3.0E38) OR (ABS(fResistance) >= 3.0E38) OR (ABS(fSurfaceArea) >= 3.0E38)
   OR (ABS(fTemp) >= 3.0E38) OR (ABS(fAmbient) >= 3.0E38) THEN
    uErrorId := 16#0002_9227;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（电阻/面积为正 + 温度高于绝对零度 + 输入功率近零，R4）/ Domain gate
IF (fResistance <= 1.0E-6) OR (fSurfaceArea <= 1.0E-6) THEN
    uErrorId := 16#0002_9227;   // 电阻或面积非正 / Non-positive resistance or area
    RETURN;
END_IF
IF (fTemp <= -273.15) OR (fAmbient <= -273.15) THEN
    uErrorId := 16#0002_9227;   // 温度不高于绝对零度，四次方无意义 / At or below absolute zero
    RETURN;
END_IF
fPowerIn := fCurrent * fCurrent * (fResistance / 1000.0) / 1000.0;      // I²R [kW] / Input power
IF fPowerIn <= 1.0E-6 THEN
    uErrorId := 16#0002_9227;   // 输入功率近零，效率不可解 / Input power too small
    RETURN;
END_IF
// 段 3：主计算（对流 + 辐射 + 效率）/ Main computation
fTK := fTemp + 273.15;                                          // 板绝对温度 [K] / Absolute temperature
fTaK := fAmbient + 273.15;                                      // 环境绝对温度 [K] / Ambient absolute temperature
fLossConv := 12.0 * fSurfaceArea * (fTemp - fAmbient) / 1000.0;  // 对流散热 [kW] / Convective loss
fLossRad := 5.67E-8 * 0.85 * fSurfaceArea * ((fTK * fTK * fTK * fTK) - (fTaK * fTaK * fTaK * fTaK)) / 1000.0;
fEfficiency := 1.0 - (fLossConv + fLossRad) / fPowerIn;         // 热效率 / Thermal efficiency
// 段 4：出口闸（四输出非有限复核 + 效率区间复核）/ Outlet gate
IF (fPowerIn <> fPowerIn) OR (fLossConv <> fLossConv) OR (fLossRad <> fLossRad)
   OR (fEfficiency <> fEfficiency)
   OR (ABS(fPowerIn) >= 3.0E38) OR (ABS(fLossConv) >= 3.0E38)
   OR (ABS(fLossRad) >= 3.0E38) OR (ABS(fEfficiency) >= 3.0E38) THEN
    fPowerIn := 0.0;            // 复核失败回缺省 / Fallback on recheck failure
    fLossConv := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    fLossRad := 0.0;            // 复核失败回缺省 / Fallback on recheck failure
    fEfficiency := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9227;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF (fEfficiency > 1.0) OR (fEfficiency < -1.0) THEN
    uErrorId := 16#0002_9227;   // 信息级：效率出物理域 / Info: efficiency out of physical range
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_BushingPowerBalanceCalc := fEfficiency;   // 返回值镜像热效率 / Return mirrors efficiency
END_FUNCTION
