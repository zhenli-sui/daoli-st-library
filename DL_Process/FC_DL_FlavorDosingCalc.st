(*
 * FC_DL_FlavorDosingCalc | C2 | DL_Process
 * 功能：加香比例给定与香精瞬时体积流量换算，并回算实际加香比例       单位：流量 [kg/h]、比例 [%]、密度 [kg/L]、体积流量 [L/h]
 * 工况边界：烟丝流量须 >0、密度须 >0（均入分母）；rActualFlowLh 为现场流量计读数，未接入时置 0 即得实际比例 0 并判负偏差；香精密度随温度变化，超 0.90~1.00 须现场标定
 * 代数值回代：G=4000 kg/h、目标 0.8 %、ρ=0.95 kg/L → setFlow=4000×0.8/100/0.95=33.68 L/h；实际流量 33.68 L/h → 实际比例 0.800 %、偏差 0.000 %（量纲自洽）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_FlavorDosingCalc : BOOL
VAR_INPUT
    rCutTobaccoKgH : REAL := 4000.0; // 烟丝流量 | cut tobacco mass flow [kg/h]
    rTargetPct     : REAL := 0.8;    // 目标加香比例 | target flavor ratio [%]
    rDensityKgL    : REAL := 0.95;   // 香精密度 | flavor density [kg/L]
    rActualFlowLh  : REAL;           // 香精实际体积流量（流量计）| actual flavor volumetric flow [L/h]
END_VAR
VAR_OUTPUT
    rSetFlowLh  : REAL;              // 香精给定体积流量 | flavor setpoint volumetric flow [L/h]
    rActualPct  : REAL;              // 实际加香比例 | actual flavor ratio [%]
    rDevPct     : REAL;              // 相对目标的偏差 | deviation from the target [%]
    xValid      : BOOL;              // 输出有效 | outputs valid
END_VAR
VAR
    xFinG   : BOOL;                  // 烟丝流量有限性 | tobacco flow is finite
    xFinTg  : BOOL;                  // 目标有限性 | target is finite
    xFinRho : BOOL;                  // 密度有限性 | density is finite
    xFinAct : BOOL;                  // 实际流量有限性 | actual flow is finite
END_VAR
VAR CONSTANT
    DL_FDC_PCT   : REAL := 100.0;    // 百分数换算系数 | percentage factor [%]
    DL_FDC_DMIN  : REAL := 1.0E-9;   // 除零保护阈值 | division guard threshold
END_VAR

// 段1｜非有限闸（R19）
xFinG := (rCutTobaccoKgH = rCutTobaccoKgH) AND ((rCutTobaccoKgH - rCutTobaccoKgH) = 0.0);
xFinTg := (rTargetPct = rTargetPct) AND ((rTargetPct - rTargetPct) = 0.0);
xFinRho := (rDensityKgL = rDensityKgL) AND ((rDensityKgL - rDensityKgL) = 0.0);
xFinAct := (rActualFlowLh = rActualFlowLh) AND ((rActualFlowLh - rActualFlowLh) = 0.0);
IF (NOT xFinG) OR (NOT xFinTg) OR (NOT xFinRho) OR (NOT xFinAct) THEN
    rSetFlowLh := 0.0;               // 安全值：给定流量 0 | safe value, zero setpoint
    rActualPct := 0.0;
    rDevPct := 0.0;
    xValid := FALSE;
    FC_DL_FlavorDosingCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：烟丝流量与密度必须为正（入分母），目标与实际流量非负
IF (rCutTobaccoKgH <= DL_FDC_DMIN) OR (rDensityKgL <= DL_FDC_DMIN)
   OR (rTargetPct < 0.0) OR (rActualFlowLh < 0.0) THEN
    rSetFlowLh := 0.0;
    rActualPct := 0.0;
    rDevPct := 0.0;
    xValid := FALSE;
    FC_DL_FlavorDosingCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：setFlow = G×rate/100/ρ；actualPct = actualFlow×ρ/G×100
rSetFlowLh := rCutTobaccoKgH * rTargetPct / DL_FDC_PCT / rDensityKgL;
rActualPct := rActualFlowLh * rDensityKgL / rCutTobaccoKgH * DL_FDC_PCT;

// 段4｜偏差与出口
rDevPct := rActualPct - rTargetPct;
xValid := TRUE;
FC_DL_FlavorDosingCalc := TRUE;
END_FUNCTION
