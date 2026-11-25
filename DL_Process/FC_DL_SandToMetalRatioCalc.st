(*
 * FC_DL_SandToMetalRatioCalc | C1 | DL_Process
 * 功能：砂铁比（单位铸铁合格件对应的砂循环量）       单位：流量 [kg/h]、比值 [kg/kg]
 * 工况边界：仅适用于连续生产的砂处理线（砂循环量与铁水消耗量同口径统计）；金属流量须 >0（入分母），砂流量须 ≥0 且有限；不区分新旧砂，只算总量比值
 * 代数值回代：sand=120000 kg/h、metal=15000 kg/h → 比值 8.0 kg/kg（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_SandToMetalRatioCalc : BOOL
VAR_INPUT
    rSandKgH  : REAL := 120000.0;    // 砂循环量 | sand circulation rate [kg/h]
    rMetalKgH : REAL := 15000.0;     // 铁水消耗量 | molten metal consumption rate [kg/h]
END_VAR
VAR_OUTPUT
    rRatio     : REAL;               // 砂铁比 | sand to metal ratio [kg/kg]
    xValid     : BOOL;               // 输出有效 | outputs valid
    nFaultCode : INT;                // 0=无 / 9711=金属流量非法 | 0 none, 9711 illegal metal flow
END_VAR
VAR
    xFinSand  : BOOL;                // 砂流量有限性 | sand flow is finite
    xFinMetal : BOOL;                // 金属流量有限性 | metal flow is finite
END_VAR
VAR CONSTANT
    DL_SMR_METAL_MIN : REAL := 1.0E-9;  // 金属流量下限（防零除）| metal flow lower bound [kg/h]
END_VAR

// 段1｜非有限闸（R19）
xFinSand := (rSandKgH = rSandKgH) AND ((rSandKgH - rSandKgH) = 0.0);
xFinMetal := (rMetalKgH = rMetalKgH) AND ((rMetalKgH - rMetalKgH) = 0.0);
IF (NOT xFinSand) OR (NOT xFinMetal) THEN
    rRatio := 0.0;                   // 安全值：比值 0 | safe value, zero ratio
    xValid := FALSE;
    nFaultCode := 9711;
    FC_DL_SandToMetalRatioCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：金属流量入分母必须 >0，砂流量不得为负
IF (rMetalKgH <= DL_SMR_METAL_MIN) OR (rSandKgH < 0.0) THEN
    rRatio := 0.0;
    xValid := FALSE;
    nFaultCode := 9711;
    FC_DL_SandToMetalRatioCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法与出口
rRatio := rSandKgH / rMetalKgH;
nFaultCode := 0;
xValid := TRUE;
FC_DL_SandToMetalRatioCalc := TRUE;
END_FUNCTION
