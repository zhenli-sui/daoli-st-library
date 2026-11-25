(*
 * FC_DL_CrahCoolingCapacityCalc | C2 | DL_Device
 * 功能：精密空调显热制冷量（按风量、送回风温差与空气物性）       单位：风量 [m³/h]、温差 [K]、密度 [kg/m³]、比热 [kJ/(kg·K)]、制冷量 [kW]
 * 工况边界：适用于干工况显热计算（不含潜热与风机温升）；风量、密度、比热须 >0 且有限，回风温度须高于送风温度，否则制冷量按 0 发布并置 xValid=FALSE；ρ、cp 取标准空气 1.2 / 1.005，高原或高温工况须现场修正
 * 代数值回代：V=8000 m³/h、ΔT=13 K、ρ=1.2、cp=1.005 → 1.2×1.005×2.2222×13=34.83 kW（spec 记 34.8 kW，一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CrahCoolingCapacityCalc : BOOL
VAR_INPUT
    rAirflowM3h : REAL := 8000.0;    // 送风量 | supply air volume flow [m³/h]
    rTreturnC   : REAL := 35.0;      // 回风温度 | return air temperature [℃]
    rTsupplyC   : REAL := 22.0;      // 送风温度 | supply air temperature [℃]
    rRho        : REAL := 1.2;       // 空气密度 | air density [kg/m³]
    rCp         : REAL := 1.005;     // 空气定压比热 | air specific heat at constant pressure [kJ/(kg·K)]
END_VAR
VAR_OUTPUT
    rCoolingKw : REAL;               // 显热制冷量 | sensible cooling capacity [kW]
    rDeltaTK   : REAL;               // 送回风温差 | return to supply temperature difference [K]
    rMassFlowKgs : REAL;             // 空气质量流量 | air mass flow [kg/s]
    xValid     : BOOL;               // 输出有效 | outputs valid
END_VAR
VAR
    xFinV   : BOOL;                  // 风量有限性 | airflow is finite
    xFinTr  : BOOL;                  // 回风温度有限性 | return temperature is finite
    xFinTs  : BOOL;                  // 送风温度有限性 | supply temperature is finite
    xFinRho : BOOL;                  // 密度有限性 | density is finite
    xFinCp  : BOOL;                  // 比热有限性 | specific heat is finite
    rVolM3s : REAL;                  // 体积流量（m³/s）| volume flow in SI units [m³/s]
END_VAR
VAR CONSTANT
    DL_CCC_SEC_PER_HOUR : REAL := 3600.0;   // 小时转秒系数 | hours to seconds factor [s/h]
END_VAR

// 段1｜非有限闸（R19）
xFinV := (rAirflowM3h = rAirflowM3h) AND ((rAirflowM3h - rAirflowM3h) = 0.0);
xFinTr := (rTreturnC = rTreturnC) AND ((rTreturnC - rTreturnC) = 0.0);
xFinTs := (rTsupplyC = rTsupplyC) AND ((rTsupplyC - rTsupplyC) = 0.0);
xFinRho := (rRho = rRho) AND ((rRho - rRho) = 0.0);
xFinCp := (rCp = rCp) AND ((rCp - rCp) = 0.0);
IF (NOT xFinV) OR (NOT xFinTr) OR (NOT xFinTs) OR (NOT xFinRho) OR (NOT xFinCp) THEN
    rCoolingKw := 0.0;               // 安全值：制冷量 0 | safe value, zero capacity
    rDeltaTK := 0.0;
    rMassFlowKgs := 0.0;
    xValid := FALSE;
    FC_DL_CrahCoolingCapacityCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：风量/密度/比热须为正（均入乘积链），回风须高于送风
IF (rAirflowM3h <= 0.0) OR (rRho <= 0.0) OR (rCp <= 0.0) OR (rTreturnC <= rTsupplyC) THEN
    rCoolingKw := 0.0;
    rDeltaTK := 0.0;
    rMassFlowKgs := 0.0;
    xValid := FALSE;
    FC_DL_CrahCoolingCapacityCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：Q_kW = ρ×cp×V(m³/s)×ΔT
rDeltaTK := rTreturnC - rTsupplyC;
rVolM3s := rAirflowM3h / DL_CCC_SEC_PER_HOUR;
rMassFlowKgs := rRho * rVolM3s;
rCoolingKw := rMassFlowKgs * rCp * rDeltaTK;

// 段4｜出口
xValid := TRUE;
FC_DL_CrahCoolingCapacityCalc := TRUE;
END_FUNCTION
