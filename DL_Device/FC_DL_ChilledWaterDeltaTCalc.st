(*
 * FC_DL_ChilledWaterDeltaTCalc | C1 | DL_Device
 * 功能：冷冻水供回水温差与「目标温差下的需求流量」互算       单位：冷量 [kW]、流量 [m³/h]、密度 [kg/m³]、比热 [kJ/(kg·K)]、温差 [K]
 * 工况边界：热平衡式 Q=ρ·cp·V̇·ΔT，cp 取 4.186 kJ/(kg·K)、ρ 取 1000 kg/m³（纯水 20 ℃）；流量须 >0 且有限；含乙二醇或高温水须重标 ρ/cp
 * 代数值回代：Q=100 kW、V=17.2 m³/h → V̇=0.004778 m³/s → ΔT=100/(1000×0.004778×4.186)=5.00 K；反算目标 5 K 时流量 17.2 m³/h（闭环自洽，与 spec 回代值 5.0 K 一致）
 * 量纲修正说明：spec 原式写作 100000/(ρ·cp·V̇) 并以 kJ 级 cp=4.186 代入，分子分母相差 1000 倍；本件按 spec 回代值 ΔT=5.0 K 采用 kW 与 kJ 同阶一致式（分子取 kW，不乘 1000）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_ChilledWaterDeltaTCalc : BOOL
VAR_INPUT
    rLoadKw         : REAL := 100.0;   // 冷冻水侧冷负荷 | chilled water cooling load [kW]
    rFlowM3h        : REAL := 17.2;    // 冷冻水体积流量 | chilled water volume flow [m³/h]
    rRho            : REAL := 1000.0;  // 水密度 | water density [kg/m³]
    rCp             : REAL := 4.186;   // 水定压比热 | water specific heat [kJ/(kg·K)]
    rTargetDeltaTK  : REAL := 5.0;     // 目标温差（用于反算需求流量；spec 未列，按 5 K 缺省）| target delta T for the flow back-calculation [K]
END_VAR
VAR_OUTPUT
    rDeltaTK          : REAL;          // 实际供回水温差 | actual supply to return temperature difference [K]
    rFlowForTargetM3h : REAL;          // 目标温差下的需求流量 | flow required for the target delta T [m³/h]
    xValid            : BOOL;          // 输出有效 | outputs valid
END_VAR
VAR
    xFinQ  : BOOL;                     // 冷负荷有限性 | load is finite
    xFinV  : BOOL;                     // 流量有限性 | flow is finite
    xFinR  : BOOL;                     // 密度有限性 | density is finite
    xFinCp : BOOL;                     // 比热有限性 | specific heat is finite
    xFinTg : BOOL;                     // 目标温差有限性 | target delta T is finite
    rVolM3s : REAL;                    // 体积流量（m³/s）| volume flow in SI units [m³/s]
    rCapKwPerK : REAL;                 // 热容流率 ρ×cp×V̇ | thermal capacity flow rate [kW/K]
END_VAR
VAR CONSTANT
    DL_CWD_SEC_PER_HOUR : REAL := 3600.0;  // 小时转秒系数 | hours to seconds factor [s/h]
    DL_CWD_CAP_MIN      : REAL := 1.0E-9;  // 除零保护阈值 | division guard threshold [kW/K]
END_VAR

// 段1｜非有限闸（R19）
xFinQ := (rLoadKw = rLoadKw) AND ((rLoadKw - rLoadKw) = 0.0);
xFinV := (rFlowM3h = rFlowM3h) AND ((rFlowM3h - rFlowM3h) = 0.0);
xFinR := (rRho = rRho) AND ((rRho - rRho) = 0.0);
xFinCp := (rCp = rCp) AND ((rCp - rCp) = 0.0);
xFinTg := (rTargetDeltaTK = rTargetDeltaTK) AND ((rTargetDeltaTK - rTargetDeltaTK) = 0.0);
IF (NOT xFinQ) OR (NOT xFinV) OR (NOT xFinR) OR (NOT xFinCp) OR (NOT xFinTg) THEN
    rDeltaTK := 0.0;                 // 安全值：温差 0 | safe value, zero delta T
    rFlowForTargetM3h := 0.0;
    xValid := FALSE;
    FC_DL_ChilledWaterDeltaTCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：流量/密度/比热/目标温差均须为正（全部入分母链）
IF (rFlowM3h <= 0.0) OR (rRho <= 0.0) OR (rCp <= 0.0) OR (rTargetDeltaTK <= 0.0)
   OR (rLoadKw < 0.0) THEN
    rDeltaTK := 0.0;
    rFlowForTargetM3h := 0.0;
    xValid := FALSE;
    FC_DL_ChilledWaterDeltaTCalc := FALSE;
    RETURN;
END_IF

// 段3｜实际温差：ΔT = Q/(ρ×cp×V̇)，V̇ 由 m³/h 换算为 m³/s
rVolM3s := rFlowM3h / DL_CWD_SEC_PER_HOUR;
rCapKwPerK := rRho * rCp * rVolM3s;
IF rCapKwPerK > DL_CWD_CAP_MIN THEN
    rDeltaTK := rLoadKw / rCapKwPerK;
ELSE
    rDeltaTK := 0.0;                 // 理论不可达（段2已排除），防御性兜底 | unreachable defence
END_IF

// 段4｜反算目标温差下的需求流量：V = 3600×Q/(ρ×cp×ΔT_target)
rFlowForTargetM3h := DL_CWD_SEC_PER_HOUR * rLoadKw / (rRho * rCp * rTargetDeltaTK);
xValid := TRUE;
FC_DL_ChilledWaterDeltaTCalc := TRUE;
END_FUNCTION
