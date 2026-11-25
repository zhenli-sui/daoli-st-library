(*
 * FC_DL_RackAirflowDemandCalc | C2 | DL_Device
 * 功能：按机柜热负荷与允许温升反算所需送风量       单位：热负荷 [kW]、温升 [K]、密度 [kg/m³]、比热 [kJ/(kg·K)]、风量 [m³/h]
 * 工况边界：仅适用于封闭冷通道的机柜级风量估算（假定全部热负荷由送风带走，无旁通）；温升 rDeltaTC 须 >0（入分母），密度与比热须 >0；热负荷为 0 时风量为 0 仍有效
 * 代数值回代：Q=8 kW、ΔT=12 K、ρ=1.2、cp=1.005 → 3600×8/(1.2×1.005×12)=1990.0 m³/h（spec 记 1990 m³/h，一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_RackAirflowDemandCalc : BOOL
VAR_INPUT
    rRackLoadKw : REAL := 8.0;       // 机柜热负荷 | rack heat load [kW]
    rDeltaTC    : REAL := 12.0;      // 允许进回风温升 | permitted inlet to outlet temperature rise [K]
    rRho        : REAL := 1.2;       // 空气密度 | air density [kg/m³]
    rCp         : REAL := 1.005;     // 空气定压比热 | air specific heat at constant pressure [kJ/(kg·K)]
END_VAR
VAR_OUTPUT
    rAirflowM3h : REAL;              // 需求送风量 | required supply airflow [m³/h]
    xValid      : BOOL;              // 输出有效 | outputs valid
END_VAR
VAR
    xFinQ   : BOOL;                  // 热负荷有限性 | heat load is finite
    xFinDT  : BOOL;                  // 温升有限性 | temperature rise is finite
    xFinRho : BOOL;                  // 密度有限性 | density is finite
    xFinCp  : BOOL;                  // 比热有限性 | specific heat is finite
    rDen    : REAL;                  // 分母 ρ×cp×ΔT | denominator rho times cp times delta T [kW/(m³/h)]
END_VAR
VAR CONSTANT
    DL_RAD_SEC_PER_HOUR : REAL := 3600.0;  // 秒转小时系数 | seconds to hours factor [s/h]
    DL_RAD_DEN_MIN      : REAL := 1.0E-9;  // 除零保护阈值 | division guard threshold [kW/(m³/h)]
END_VAR

// 段1｜非有限闸（R19）
xFinQ := (rRackLoadKw = rRackLoadKw) AND ((rRackLoadKw - rRackLoadKw) = 0.0);
xFinDT := (rDeltaTC = rDeltaTC) AND ((rDeltaTC - rDeltaTC) = 0.0);
xFinRho := (rRho = rRho) AND ((rRho - rRho) = 0.0);
xFinCp := (rCp = rCp) AND ((rCp - rCp) = 0.0);
IF (NOT xFinQ) OR (NOT xFinDT) OR (NOT xFinRho) OR (NOT xFinCp) THEN
    rAirflowM3h := 0.0;              // 安全值：风量 0 | safe value, zero airflow
    xValid := FALSE;
    FC_DL_RackAirflowDemandCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：温升入分母必须 >0，密度与比热须 >0，热负荷不得为负
IF (rDeltaTC <= 0.0) OR (rRho <= 0.0) OR (rCp <= 0.0) OR (rRackLoadKw < 0.0) THEN
    rAirflowM3h := 0.0;
    xValid := FALSE;
    FC_DL_RackAirflowDemandCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：V(m³/h) = 3600×Q/(ρ×cp×ΔT)，分母显式防零
rDen := rRho * rCp * rDeltaTC;
IF rDen > DL_RAD_DEN_MIN THEN
    rAirflowM3h := DL_RAD_SEC_PER_HOUR * rRackLoadKw / rDen;
ELSE
    rAirflowM3h := 0.0;              // 理论不可达（段2已排除），防御性兜底 | unreachable defence
END_IF

// 段4｜出口
xValid := TRUE;
FC_DL_RackAirflowDemandCalc := TRUE;
END_FUNCTION
