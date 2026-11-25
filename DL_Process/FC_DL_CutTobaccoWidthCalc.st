(*
 * FC_DL_CutTobaccoWidthCalc | C2 | DL_Process
 * 功能：由线速、刀辊转速与刀片数推算切丝宽度并判定丝宽合格       单位：线速 [m/s]、转速 [r/min]、刀数 [片]、丝宽 [mm]
 * 工况边界：nRpm 与 nBlades 须 >0（入分母），线速须 ≥0 且有限；仅适用于定刀数圆盘切丝机，不含刀片磨损补偿；入参非法一律 xValid=FALSE 且丝宽取 0
 * 代数值回代：v=0.5 m/s、rpm=3000、blades=10 → w=0.5×1000×60/(3000×10)=1.0 mm，目标 1.0 mm → 合格（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CutTobaccoWidthCalc : BOOL
VAR_INPUT
    rLineSpeedMps : REAL;            // 烟片线速度 | tobacco line speed [m/s]
    nRpm          : INT;             // 刀辊转速 | cutter drum speed [r/min]
    nBlades       : INT;             // 刀片数 | blade count [片]
    rTargetMm     : REAL := 1.0;     // 目标丝宽 | target cut width [mm]
    rTolMm        : REAL := 0.1;     // 丝宽公差（±）| cut width tolerance [mm]
END_VAR
VAR_OUTPUT
    rWidthMm      : REAL;            // 实际丝宽 | actual cut width [mm]
    rDevMm        : REAL;            // 相对目标的偏差 | deviation from the target [mm]
    xInTolerance  : BOOL;            // 丝宽在公差带内 | cut width within tolerance
    xValid        : BOOL;            // 输出有效 | outputs valid
END_VAR
VAR
    xFinV  : BOOL;                   // 线速有限性 | line speed is finite
    xFinTg : BOOL;                   // 目标有限性 | target is finite
    xFinTol: BOOL;                   // 公差有限性 | tolerance is finite
    rRpm   : REAL;                   // 转速的实数形式 | drum speed as a real number [r/min]
    rBlades: REAL;                   // 刀数的实数形式 | blade count as a real number [片]
    rDen   : REAL;                   // 分母（转速×刀数）| denominator, speed times blade count [1/min]
END_VAR
VAR CONSTANT
    DL_CTW_SEC_PER_MIN : REAL := 60.0;      // 分转秒系数 | minutes to seconds factor [s/min]
    DL_CTW_M_TO_MM     : REAL := 1000.0;    // 米转毫米系数 | metres to millimetres factor [mm/m]
    DL_CTW_DEN_MIN     : REAL := 1.0E-9;    // 除零保护阈值 | division guard threshold [1/min]
    DL_CTW_TOL_EPS     : REAL := 1.0E-6;    // 浮点比较容差 | floating comparison tolerance [mm]
END_VAR

// 段1｜非有限闸（R19）
xFinV := (rLineSpeedMps = rLineSpeedMps) AND ((rLineSpeedMps - rLineSpeedMps) = 0.0);
xFinTg := (rTargetMm = rTargetMm) AND ((rTargetMm - rTargetMm) = 0.0);
xFinTol := (rTolMm = rTolMm) AND ((rTolMm - rTolMm) = 0.0);
IF (NOT xFinV) OR (NOT xFinTg) OR (NOT xFinTol) THEN
    rWidthMm := 0.0;                 // 安全值：丝宽 0 | safe value, zero width
    rDevMm := 0.0;
    xInTolerance := FALSE;
    xValid := FALSE;
    FC_DL_CutTobaccoWidthCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：转速与刀数必须为正（入分母），线速不得为负，公差须为正
IF (nRpm <= 0) OR (nBlades <= 0) OR (rLineSpeedMps < 0.0) OR (rTolMm <= 0.0) THEN
    rWidthMm := 0.0;
    rDevMm := 0.0;
    xInTolerance := FALSE;
    xValid := FALSE;
    FC_DL_CutTobaccoWidthCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：w_mm = (v×1000×60)/(rpm×nBlades)，分母显式防零
rRpm := INT_TO_REAL(nRpm);
rBlades := INT_TO_REAL(nBlades);
rDen := rRpm * rBlades;
IF rDen > DL_CTW_DEN_MIN THEN
    rWidthMm := (rLineSpeedMps * DL_CTW_M_TO_MM * DL_CTW_SEC_PER_MIN) / rDen;
ELSE
    rWidthMm := 0.0;                 // 理论不可达（段2已排除），防御性兜底 | unreachable defence
END_IF

// 段4｜合格判定：偏差与公差同源于原始丝宽（R24）
rDevMm := rWidthMm - rTargetMm;
xInTolerance := ABS(rDevMm) <= (rTolMm + DL_CTW_TOL_EPS);
xValid := TRUE;
FC_DL_CutTobaccoWidthCalc := TRUE;
END_FUNCTION
