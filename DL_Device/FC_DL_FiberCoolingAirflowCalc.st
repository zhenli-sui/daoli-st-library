// FC_DL_FiberCoolingAirflowCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 丝束冷却风量：ΔT = 出风 − 进风 [K]，ΔT ≤ 0.5 K 拒收（换热量不可分辨）；
        质量流量 = Q[kW]/(1.005·ΔT) [kg/s]（1.005 为空气定压比热 kJ/(kg·K)），
        体积风量 = 质量流量/密度×3600 [m³/h]。
  邻件/码位: 与 FC_DL_BushingPowerBalanceCalc 同属热平衡链（丝束冷却侧 vs 漏板本体散热）；
             16#0002_9228 = 非有限、热量/密度非正或温差不足 0.5 K 拒收。
*)
FUNCTION FC_DL_FiberCoolingAirflowCalc : REAL
VAR_INPUT
    fHeatToRemove  : REAL := 8.0;       // 需带走热量 [kW]，域 > 0 / Heat to remove [kW]
    fAirInletTemp  : REAL := 30.0;      // 进风温度 [°C] / Inlet air temperature [degC]
    fAirOutletTemp : REAL := 45.0;      // 出风温度 [°C] / Outlet air temperature [degC]
    fAirDensity    : REAL := 1.15;      // 空气密度 [kg/m³]，域 > 0 / Air density [kg/m^3]
END_VAR
VAR_OUTPUT
    fAirflowM3h : REAL;                 // 体积风量 [m³/h] / Volumetric airflow [m^3/h]
    bValid      : BOOL;                 // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;                // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fDeltaT : REAL := 0.0;              // 进出风温差 [K] / Temperature rise [K]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fAirflowM3h := 0.0;                 // 风量缺省零 / Airflow default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_FiberCoolingAirflowCalc := 0.0;   // 返回值缺省零（镜像风量）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fHeatToRemove <> fHeatToRemove) OR (fAirInletTemp <> fAirInletTemp)
   OR (fAirOutletTemp <> fAirOutletTemp) OR (fAirDensity <> fAirDensity)
   OR (ABS(fHeatToRemove) >= 3.0E38) OR (ABS(fAirInletTemp) >= 3.0E38)
   OR (ABS(fAirOutletTemp) >= 3.0E38) OR (ABS(fAirDensity) >= 3.0E38) THEN
    uErrorId := 16#0002_9228;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（热量与密度为正 + 温差可分辨，R4）/ Domain gate
IF (fHeatToRemove <= 1.0E-6) OR (fAirDensity <= 1.0E-6) THEN
    uErrorId := 16#0002_9228;   // 热量或密度非正 / Non-positive heat or density
    RETURN;
END_IF
fDeltaT := fAirOutletTemp - fAirInletTemp;                      // 温差 [K] / Temperature rise
IF fDeltaT <= 0.5 THEN
    uErrorId := 16#0002_9228;   // 温差不足 0.5 K，风量解发散 / Rise too small
    RETURN;
END_IF
// 段 3：主计算（质量流量 → 体积风量）/ Main computation
fAirflowM3h := (fHeatToRemove / (1.005 * fDeltaT)) / fAirDensity * 3600.0;  // [m³/h] / Airflow
// 段 4：出口闸（非有限复核 + 正数复核）/ Outlet gate
IF (fAirflowM3h <> fAirflowM3h) OR (ABS(fAirflowM3h) >= 3.0E38) OR (fAirflowM3h <= 0.0) THEN
    fAirflowM3h := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9228;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_FiberCoolingAirflowCalc := fAirflowM3h;   // 返回值镜像风量 / Return mirrors airflow
END_FUNCTION
