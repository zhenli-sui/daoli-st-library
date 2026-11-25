(*
 * FC_DL_TobaccoFillValueCalc | C1 | DL_Process
 * 功能：烟丝填充值（松装单位质量体积）与工艺区间判定       单位：质量 [g]、体积 [mL]，填充值 [cm³/g]
 * 工况边界：仅适用于松装法（标准量筒自由落料）测量；样品质量须 >0（入分母）；膨胀丝填充值工艺区间 8~12 cm³/g，超出仅置信息位不判故障
 * 代数值回代：m=50 g、V=500 mL → FV=500/50=10.0 cm³/g，落在 8~12 → xInRange=TRUE（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_TobaccoFillValueCalc : BOOL
VAR_INPUT
    rSampleMassG    : REAL := 50.0;   // 样品质量 | sample mass [g]
    rCylinderVolMl  : REAL := 500.0;  // 量筒松装体积 | loose bulk volume in the cylinder [mL]
END_VAR
VAR_OUTPUT
    rFillValueCm3g : REAL;            // 填充值 | fill value [cm³/g]
    xInRange       : BOOL;            // 落在膨胀丝工艺区间 8~12 | inside the expanded tobacco range 8 to 12
    xValid         : BOOL;            // 输出有效 | outputs valid
    nFaultCode     : INT;             // 0=无 / 9511=样品质量或体积非法 | 0 none, 9511 illegal sample mass or volume
END_VAR
VAR
    xFinMass : BOOL;                  // 质量有限性 | mass is finite
    xFinVol  : BOOL;                  // 体积有限性 | volume is finite
END_VAR
VAR CONSTANT
    DL_TFV_MASS_MIN : REAL := 1.0E-6;  // 质量下限（防零除）| mass lower bound guarding the division [g]
    DL_TFV_RANGE_LO : REAL := 8.0;     // 工艺区间下限 | process range lower bound [cm³/g]
    DL_TFV_RANGE_HI : REAL := 12.0;    // 工艺区间上限 | process range upper bound [cm³/g]
    DL_TFV_EPS      : REAL := 1.0E-6;  // 浮点比较容差 | floating comparison tolerance [cm³/g]
END_VAR

// 段1｜非有限闸（R19）
xFinMass := (rSampleMassG = rSampleMassG) AND ((rSampleMassG - rSampleMassG) = 0.0);
xFinVol := (rCylinderVolMl = rCylinderVolMl) AND ((rCylinderVolMl - rCylinderVolMl) = 0.0);
IF (NOT xFinMass) OR (NOT xFinVol) THEN
    rFillValueCm3g := 0.0;            // 安全值：填充值 0 | safe value, zero fill value
    xInRange := FALSE;
    xValid := FALSE;
    nFaultCode := 9511;
    FC_DL_TobaccoFillValueCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：质量入分母必须 >0，体积必须 >0
IF (rSampleMassG <= DL_TFV_MASS_MIN) OR (rCylinderVolMl <= 0.0) THEN
    rFillValueCm3g := 0.0;
    xInRange := FALSE;
    xValid := FALSE;
    nFaultCode := 9511;
    FC_DL_TobaccoFillValueCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：FV = V/m（mL = cm³，量纲直接相通）
rFillValueCm3g := rCylinderVolMl / rSampleMassG;

// 段4｜区间判定（判据与出口同源于原始测量值）
xInRange := (rFillValueCm3g >= (DL_TFV_RANGE_LO - DL_TFV_EPS))
             AND (rFillValueCm3g <= (DL_TFV_RANGE_HI + DL_TFV_EPS));
nFaultCode := 0;
xValid := TRUE;
FC_DL_TobaccoFillValueCalc := TRUE;
END_FUNCTION
