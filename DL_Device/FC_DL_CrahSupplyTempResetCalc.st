(*
 * FC_DL_CrahSupplyTempResetCalc | C2 | DL_Device
 * 功能：按最不利机柜进风温度重置精密空调送风温度设定值       单位：温度 [℃]、增益 [1]
 * 工况边界：单回路比例重置，适用于机柜进风温度反馈可信（无传感器故障）场合；上下限须满足 min<max 且增益 ≥0，否则 xValid=FALSE 并输出下限安全值；clamped 判定以未钳位的原始计算值为准（R24，禁止先夹再判）
 * 代数值回代：worst=27、target=24、gain=0.6、base=20、限 [18,27] → sp=20+0.6×3=21.8 ℃，未打限幅 → xClamped=FALSE（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CrahSupplyTempResetCalc : BOOL
VAR_INPUT
    rWorstRackInletC : REAL := 27.0;  // 最不利机柜进风温度 | worst rack inlet temperature [℃]
    rRackTargetC     : REAL := 24.0;  // 机柜进风目标温度 | rack inlet target temperature [℃]
    rGain            : REAL := 0.6;   // 重置增益 | reset gain [1]
    rMinC            : REAL := 18.0;  // 送风设定下限 | supply setpoint lower limit [℃]
    rMaxC            : REAL := 27.0;  // 送风设定上限 | supply setpoint upper limit [℃]
    rBaseC           : REAL := 20.0;  // 基准送风温度 | base supply temperature [℃]
END_VAR
VAR_OUTPUT
    rSupplySetpointC : REAL;          // 送风温度设定值 | supply temperature setpoint [℃]
    rRawSetpointC    : REAL;          // 未钳位的原始计算值 | raw setpoint before clamping [℃]
    xClamped         : BOOL;          // 已打限幅（信息级）| clamped against the limits, informational
    xValid           : BOOL;          // 输出有效 | outputs valid
END_VAR
VAR
    xFinWorst : BOOL;                 // 最不利温度有限性 | worst temperature is finite
    xFinTg    : BOOL;                 // 目标温度有限性 | target temperature is finite
    xFinGain  : BOOL;                 // 增益有限性 | gain is finite
    xFinMin   : BOOL;                 // 下限有限性 | lower limit is finite
    xFinMax   : BOOL;                 // 上限有限性 | upper limit is finite
    xFinBase  : BOOL;                 // 基准有限性 | base temperature is finite
END_VAR
VAR CONSTANT
    DL_CSR_EPS : REAL := 1.0E-6;      // 浮点比较容差 | floating comparison tolerance [℃]
END_VAR

// 段1｜非有限闸（R19：非有限即输出下限安全值，避免 NaN 流入设定值）
xFinWorst := (rWorstRackInletC = rWorstRackInletC) AND ((rWorstRackInletC - rWorstRackInletC) = 0.0);
xFinTg := (rRackTargetC = rRackTargetC) AND ((rRackTargetC - rRackTargetC) = 0.0);
xFinGain := (rGain = rGain) AND ((rGain - rGain) = 0.0);
xFinMin := (rMinC = rMinC) AND ((rMinC - rMinC) = 0.0);
xFinMax := (rMaxC = rMaxC) AND ((rMaxC - rMaxC) = 0.0);
xFinBase := (rBaseC = rBaseC) AND ((rBaseC - rBaseC) = 0.0);
IF (NOT xFinWorst) OR (NOT xFinTg) OR (NOT xFinGain) OR (NOT xFinMin)
   OR (NOT xFinMax) OR (NOT xFinBase) THEN
    rSupplySetpointC := 18.0;        // 安全值：取下限（不结露的保守侧）| safe value, the conservative lower limit
    rRawSetpointC := 18.0;
    xClamped := TRUE;
    xValid := FALSE;
    FC_DL_CrahSupplyTempResetCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：限幅区间有效且增益非负
IF (rMaxC <= rMinC) OR (rGain < 0.0) THEN
    rSupplySetpointC := rMinC;       // 安全值：取下限 | safe value, the lower limit
    rRawSetpointC := rMinC;
    xClamped := TRUE;
    xValid := FALSE;
    FC_DL_CrahSupplyTempResetCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：sp = base + gain×(worst − target)
rRawSetpointC := rBaseC + rGain * (rWorstRackInletC - rRackTargetC);

// 段4｜限幅与打限标志（判据取自未钳位原始值，R24）
xClamped := (rRawSetpointC > (rMaxC + DL_CSR_EPS)) OR (rRawSetpointC < (rMinC - DL_CSR_EPS));
rSupplySetpointC := LIMIT(rMinC, rRawSetpointC, rMaxC);

// 段5｜出口
xValid := TRUE;
FC_DL_CrahSupplyTempResetCalc := TRUE;
END_FUNCTION
