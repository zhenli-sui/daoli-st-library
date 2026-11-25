(*
 * FC_DL_TrolleyPendulumAngleCalc | C2 | DL_Motion
 * 功能：由小车加(减)速度与绳长估算吊重单摆等效摆角及小摆固有周期       单位：加速度 [m/s²]、绳长 [m]、摆角 [°]、周期 [s]
 * 工况边界：小摆线性化适用区（摆角钳 ±15°）；绳长须 >0.1 m 且 g>0，否则判 9301；任一入参 NaN/±Inf 一律拒算并输出安全值 0；加速度越限只告警不影响出口
 * 代数值回代：a=0.5 m/s²、L=20 m、g=9.80665 → θ=2.92°、T=8.97 s（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_TrolleyPendulumAngleCalc : BOOL
VAR_INPUT
    rAccelMps2  : REAL;              // 小车加(减)速度 | trolley acceleration [m/s²]
    rRopeLenM   : REAL;              // 起升绳长（小车至吊钩）| rope length from trolley to hook [m]
    rGravity    : REAL := 9.80665;   // 重力加速度 | gravitational acceleration [m/s²]
    rAccelLimit : REAL := 1.0;       // 设备允许加减速度上限 | permitted acceleration limit [m/s²]
END_VAR
VAR_OUTPUT
    rSwayAngleDeg : REAL;            // 等效摆角（取绝对值后钳 ±15）| equivalent sway angle, absolute value clamped to ±15 [°]
    rPeriodS      : REAL;            // 小摆固有周期 | small-oscillation natural period [s]
    xOverAccel    : BOOL;            // 加速度越限告警（信息级，不置故障）| acceleration over-limit warning, informational only
    xValid        : BOOL;            // 输出有效 | outputs valid
    xFault        : BOOL;            // 故障标志 | fault flag
    nFaultCode    : INT;             // 故障码 0=无 / 9301=绳长或重力非法 | fault code 0=none, 9301=illegal rope length or gravity
END_VAR
VAR
    xFinAcc  : BOOL;                 // 加速度有限性 | acceleration is finite
    xFinRope : BOOL;                 // 绳长有限性 | rope length is finite
    xFinGrav : BOOL;                 // 重力有限性 | gravity is finite
    rAngleRad : REAL;                // 未钳位摆角（弧度）| unclamped sway angle [rad]
END_VAR
VAR CONSTANT
    DL_TPA_RAD2DEG : REAL := 57.29577951308232;   // 弧度转角度系数 180/π（等价 DEG 标准函数）| radians to degrees factor 180/pi [°/rad]
    DL_TPA_SWAY_MAX_DEG : REAL := 15.0;           // 摆角钳位上限（小摆线性化边界）| sway clamp limit, small-angle boundary [°]
    DL_TPA_ROPE_MIN_M : REAL := 0.1;              // 绳长适用下限 | lower rope length limit [m]
    DL_TPA_TWO_PI : REAL := 6.283185307179586;    // 2π 常数 | two times pi [rad]
END_VAR

// 段1｜非有限闸（R19：判出 NaN/Inf 即赋安全值并置 xValid=FALSE，绝不让非有限值流入出口）
xFinAcc := (rAccelMps2 = rAccelMps2) AND ((rAccelMps2 - rAccelMps2) = 0.0);
xFinRope := (rRopeLenM = rRopeLenM) AND ((rRopeLenM - rRopeLenM) = 0.0);
xFinGrav := (rGravity = rGravity) AND ((rGravity - rGravity) = 0.0);
IF (NOT xFinAcc) OR (NOT xFinRope) OR (NOT xFinGrav) THEN
    rSwayAngleDeg := 0.0;            // 安全值：摆角 0，下游按静止处理 | safe value, downstream treats it as at rest
    rPeriodS := 0.0;                 // 安全值：周期 0，禁止据此投用防摇补偿 | safe value, anti-sway must not be enabled
    xOverAccel := FALSE;
    xValid := FALSE;
    xFault := TRUE;
    nFaultCode := 9301;
    FC_DL_TrolleyPendulumAngleCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：绳长与重力（除数源头，先判后用）
IF (rRopeLenM <= DL_TPA_ROPE_MIN_M) OR (rGravity <= 0.0) THEN
    rSwayAngleDeg := 0.0;            // 安全值：摆角 0 | safe value, zero sway
    rPeriodS := 0.0;                 // 安全值：周期 0 | safe value, zero period
    xOverAccel := FALSE;
    xValid := FALSE;
    xFault := TRUE;
    nFaultCode := 9301;
    FC_DL_TrolleyPendulumAngleCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：θ = DEG(ATAN2(|a|, g)) 并钳 ±15°；T = 2π·SQRT(L/g)
rAngleRad := ATAN2(ABS(rAccelMps2), rGravity);
rSwayAngleDeg := rAngleRad * DL_TPA_RAD2DEG;
IF rSwayAngleDeg > DL_TPA_SWAY_MAX_DEG THEN
    rSwayAngleDeg := DL_TPA_SWAY_MAX_DEG;   // 上限钳位，超界即线性化失效 | upper clamp, beyond this the linearisation is invalid
ELSIF rSwayAngleDeg < -DL_TPA_SWAY_MAX_DEG THEN
    rSwayAngleDeg := -DL_TPA_SWAY_MAX_DEG;  // 下限钳位（本件取绝对值后不会触发，保留对称性）| lower clamp kept for symmetry
END_IF
rPeriodS := DL_TPA_TWO_PI * SQRT(rRopeLenM / rGravity);   // 分母已由段2保证 >0 | denominator proven positive in segment 2

// 段4｜告警与出口：判据与出口同源于原始加速度（R24）
xOverAccel := ABS(rAccelMps2) > rAccelLimit;
nFaultCode := 0;
xFault := FALSE;
xValid := TRUE;
FC_DL_TrolleyPendulumAngleCalc := TRUE;
END_FUNCTION
