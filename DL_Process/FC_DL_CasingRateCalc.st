(*
 * FC_DL_CasingRateCalc | C2 | DL_Process
 * 功能：叶片加料比例与实际料液体积流量（按料液密度换算）       单位：流量 [kg/h]、比例 [%]、密度 [kg/L]、体积流量 [L/h]
 * 工况边界：叶片流量须 >0（入分母）；料液密度取 1.05 kg/L 固定常数（糖香料液典型值），密度差异超出 ±0.05 须现场标定；料液流量不得为负
 * 代数值回代：leaf=5000 kg/h、casing=150 kg/h → rate=150/5000×100=3.0 %（=目标 3.0 %，合格）；flow=150/1.05=142.9 L/h（与 spec 比例式一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CasingRateCalc : BOOL
VAR_INPUT
    rLeafKgH     : REAL := 5000.0;   // 叶片流量 | leaf tobacco mass flow [kg/h]
    rCasingKgH   : REAL;             // 料液质量流量 | casing mass flow [kg/h]
    rTargetPct   : REAL := 3.0;      // 目标加料比例 | target casing ratio [%]
    rTolPct      : REAL := 0.2;      // 加料比例公差（±）| casing ratio tolerance [%]
END_VAR
VAR_OUTPUT
    rRatePct      : REAL;            // 实际加料比例 | actual casing ratio [%]
    rCasingFlowLh : REAL;            // 料液体积流量（按密度换算）| casing volumetric flow [L/h]
    rDevPct       : REAL;            // 相对目标的偏差 | deviation from the target [%]
    xInTolerance  : BOOL;            // 比例在公差带内 | ratio within tolerance
    xValid        : BOOL;            // 输出有效 | outputs valid
END_VAR
VAR
    xFinLeaf : BOOL;                 // 叶片流量有限性 | leaf flow is finite
    xFinCase : BOOL;                 // 料液流量有限性 | casing flow is finite
    xFinTg   : BOOL;                 // 目标有限性 | target is finite
    xFinTol  : BOOL;                 // 公差有限性 | tolerance is finite
END_VAR
VAR CONSTANT
    DL_CRC_PCT   : REAL := 100.0;    // 百分数换算系数 | percentage factor [%]
    DL_CRC_DENS  : REAL := 1.05;     // 料液密度（固定常数，需现场标定）| casing density, a fixed constant to be calibrated on site [kg/L]
    DL_CRC_DMIN  : REAL := 1.0E-9;   // 除零保护阈值 | division guard threshold [kg/h]
    DL_CRC_EPS   : REAL := 1.0E-6;   // 浮点比较容差 | floating comparison tolerance [%]
END_VAR

// 段1｜非有限闸（R19）
xFinLeaf := (rLeafKgH = rLeafKgH) AND ((rLeafKgH - rLeafKgH) = 0.0);
xFinCase := (rCasingKgH = rCasingKgH) AND ((rCasingKgH - rCasingKgH) = 0.0);
xFinTg := (rTargetPct = rTargetPct) AND ((rTargetPct - rTargetPct) = 0.0);
xFinTol := (rTolPct = rTolPct) AND ((rTolPct - rTolPct) = 0.0);
IF (NOT xFinLeaf) OR (NOT xFinCase) OR (NOT xFinTg) OR (NOT xFinTol) THEN
    rRatePct := 0.0;                 // 安全值：比例 0 | safe value, zero ratio
    rCasingFlowLh := 0.0;
    rDevPct := 0.0;
    xInTolerance := FALSE;
    xValid := FALSE;
    FC_DL_CasingRateCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：叶片流量 >0、料液流量 ≥0、公差 ≥0
IF (rLeafKgH <= DL_CRC_DMIN) OR (rCasingKgH < 0.0) OR (rTolPct < 0.0) THEN
    rRatePct := 0.0;
    rCasingFlowLh := 0.0;
    rDevPct := 0.0;
    xInTolerance := FALSE;
    xValid := FALSE;
    FC_DL_CasingRateCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：rate = casing/leaf×100；体积流量 = 质量流量/密度
rRatePct := rCasingKgH / rLeafKgH * DL_CRC_PCT;
rCasingFlowLh := rCasingKgH / DL_CRC_DENS;     // 密度为常数 1.05，恒非零 | the density constant is never zero

// 段4｜合格判定（判据与出口同源于原始流量）
rDevPct := rRatePct - rTargetPct;
xInTolerance := ABS(rDevPct) <= (rTolPct + DL_CRC_EPS);
xValid := TRUE;
FC_DL_CasingRateCalc := TRUE;
END_FUNCTION
