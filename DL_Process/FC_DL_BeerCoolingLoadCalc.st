// FC_DL_BeerCoolingLoadCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 冷却负荷：体积流量 = 流量[hL/h]·100/1000 [m³/h]，质量流量 = 体积流量·ρ/3600 [kg/s]，
        显热负荷 = 质量流量·cp·(进料 − 出料) [kW]（kJ/s = kW），总冷负荷 = 显热 + 发酵放热。
  邻件/码位: 与 FC_DL_DiacetylRestWindowCalc、FC_DL_KegFillingCounterPressureCalc 同属后段冷工链；
             16#0002_9239 = 非有限、流量/密度/比热非正、出料不低于进料或发酵热为负拒收。
*)
FUNCTION FC_DL_BeerCoolingLoadCalc : REAL
VAR_INPUT
    fFlow        : REAL := 200.0;   // 流量 [hL/h]，域 > 0 / Flow rate [hL/h]
    fTempIn      : REAL := 12.0;    // 进料温度 [°C] / Inlet temperature [degC]
    fTempOut     : REAL := 2.0;     // 出料温度 [°C]，域 < 进料 / Outlet temperature [degC]
    fCp          : REAL := 3.85;    // 比热 [kJ/(kg·K)]，域 > 0 / Specific heat [kJ/(kg K)]
    fDensity     : REAL := 1010.0;  // 密度 [kg/m³]，域 > 0 / Density [kg/m^3]
    fFermentHeat : REAL := 5.0;     // 发酵放热 [kW]，域 >= 0 / Fermentation heat [kW]
END_VAR
VAR_OUTPUT
    fCoolLoad : REAL;               // 总冷负荷 [kW] / Total cooling load [kW]
    bValid    : BOOL;               // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fMassFlow : REAL := 0.0;        // 质量流量 [kg/s] / Mass flow [kg/s]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fCoolLoad := 0.0;                   // 冷负荷缺省零 / Cooling load default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_BeerCoolingLoadCalc := 0.0;   // 返回值缺省零（镜像冷负荷）/ Return default zero
// 段 1：非有限闸（六入参全枚举）/ Non-finite gate over all inputs
IF (fFlow <> fFlow) OR (fTempIn <> fTempIn) OR (fTempOut <> fTempOut)
   OR (fCp <> fCp) OR (fDensity <> fDensity) OR (fFermentHeat <> fFermentHeat)
   OR (ABS(fFlow) >= 3.0E38) OR (ABS(fTempIn) >= 3.0E38) OR (ABS(fTempOut) >= 3.0E38)
   OR (ABS(fCp) >= 3.0E38) OR (ABS(fDensity) >= 3.0E38) OR (ABS(fFermentHeat) >= 3.0E38) THEN
    uErrorId := 16#0002_9239;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（流量/密度/比热为正 + 出料低于进料 + 发酵热非负，R4）/ Domain gate
IF (fFlow <= 1.0E-6) OR (fDensity <= 1.0E-6) OR (fCp <= 1.0E-6) THEN
    uErrorId := 16#0002_9239;   // 流量、密度或比热非正 / Non-positive flow, density or capacity
    RETURN;
END_IF
IF fTempOut >= fTempIn THEN
    uErrorId := 16#0002_9239;   // 出料不低于进料，无冷却需求 / Outlet not colder than inlet
    RETURN;
END_IF
IF fFermentHeat < 0.0 THEN
    uErrorId := 16#0002_9239;   // 发酵放热为负 / Negative fermentation heat
    RETURN;
END_IF
// 段 3：主计算（体积→质量流量 → 显热 → 总负荷）/ Main computation
fMassFlow := fFlow * 100.0 / 1000.0 * fDensity / 3600.0;        // 质量流量 [kg/s] / Mass flow
fCoolLoad := fMassFlow * fCp * (fTempIn - fTempOut) + fFermentHeat;     // 总冷负荷 [kW] / Total load
// 段 4：出口闸（非有限复核 + 正数复核）/ Outlet gate
IF (fCoolLoad <> fCoolLoad) OR (ABS(fCoolLoad) >= 3.0E38) OR (fCoolLoad <= 0.0) THEN
    fCoolLoad := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9239;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_BeerCoolingLoadCalc := fCoolLoad;         // 返回值镜像总冷负荷 / Return mirrors load
END_FUNCTION
