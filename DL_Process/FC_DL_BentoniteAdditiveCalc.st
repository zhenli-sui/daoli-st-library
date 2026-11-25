(*
 * FC_DL_BentoniteAdditiveCalc | C2 | DL_Process
 * 功能：按亚甲基蓝吸附量差额计算膨润土补加比例与补加量       单位：吸附量 [mL/100g]、比例 [%]、流量 [kg/h]、效率 [%]
 * 工况边界：经验系数 0.15 %/(mL/100g)（spec 采纳值），仅适用于湿型砂单一膨润土体系；实测值已达或超过目标时补加量为 0（xNeedAdd=FALSE，不判故障）；砂处理量须 ≥0、效率须在 (0,100] %
 * 代数值回代：mb=35、target=40 → deficit=5；addPct=5×0.15=0.75 %；sandRate=120000 kg/h → 补加 900 kg/h（spec 采纳 0.15 系数回代值 900 kg/h，一致）
 * 系数修正说明：spec 初版给 addKgH = sandRate×(deficit/100)×(100/eff)，回代得 9231 kg/h 明显超出工艺量级，spec 已明确改用 0.15 系数，本件按采纳值实现
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_BentoniteAdditiveCalc : BOOL
VAR_INPUT
    rMbValueMl    : REAL := 35.0;      // 实测亚甲基蓝吸附量 | measured methylene blue adsorption [mL/100g]
    rMbTarget     : REAL := 40.0;      // 目标亚甲基蓝吸附量 | target methylene blue adsorption [mL/100g]
    rSandRateKgH  : REAL := 120000.0;  // 砂处理量 | sand throughput [kg/h]
    rEffPct       : REAL := 65.0;      // 膨润土有效利用率 | bentonite effective utilisation [%]
END_VAR
VAR_OUTPUT
    rDeficitMb    : REAL;              // 吸附量差额（目标−实测）| adsorption deficit, target minus measured [mL/100g]
    rAddPct       : REAL;              // 补加比例 | additive ratio [%]
    rBentoniteKgH : REAL;              // 膨润土补加量 | bentonite additive rate [kg/h]
    xNeedAdd      : BOOL;              // 需要补加（差额 >0）| additive required, deficit above zero
    xValid        : BOOL;              // 输出有效 | outputs valid
    nFaultCode    : INT;               // 0=无 / 9713=输入非法 | 0 none, 9713 illegal input
END_VAR
VAR
    xFinMb   : BOOL;                   // 实测值有限性 | measured value is finite
    xFinTg   : BOOL;                   // 目标值有限性 | target is finite
    xFinRate : BOOL;                   // 处理量有限性 | throughput is finite
    xFinEff  : BOOL;                   // 效率有限性 | efficiency is finite
END_VAR
VAR CONSTANT
    DL_BAC_PCT_PER_ML : REAL := 0.15;  // 每 1 mL/100g 差额对应的膨润土比例（spec 采纳系数）| bentonite ratio per unit deficit [%/(mL/100g)]
    DL_BAC_PCT        : REAL := 100.0; // 百分数换算系数 | percentage factor [%]
END_VAR

// 段1｜非有限闸（R19）
xFinMb := (rMbValueMl = rMbValueMl) AND ((rMbValueMl - rMbValueMl) = 0.0);
xFinTg := (rMbTarget = rMbTarget) AND ((rMbTarget - rMbTarget) = 0.0);
xFinRate := (rSandRateKgH = rSandRateKgH) AND ((rSandRateKgH - rSandRateKgH) = 0.0);
xFinEff := (rEffPct = rEffPct) AND ((rEffPct - rEffPct) = 0.0);
IF (NOT xFinMb) OR (NOT xFinTg) OR (NOT xFinRate) OR (NOT xFinEff) THEN
    rDeficitMb := 0.0;                 // 安全值：不补加 | safe value, no addition
    rAddPct := 0.0;
    rBentoniteKgH := 0.0;
    xNeedAdd := FALSE;
    xValid := FALSE;
    nFaultCode := 9713;
    FC_DL_BentoniteAdditiveCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：处理量非负、效率在 (0,100]
IF (rSandRateKgH < 0.0) OR (rEffPct <= 0.0) OR (rEffPct > DL_BAC_PCT) OR (rMbValueMl < 0.0) THEN
    rDeficitMb := 0.0;
    rAddPct := 0.0;
    rBentoniteKgH := 0.0;
    xNeedAdd := FALSE;
    xValid := FALSE;
    nFaultCode := 9713;
    FC_DL_BentoniteAdditiveCalc := FALSE;
    RETURN;
END_IF

// 段3｜差额（判据与出口同源于原始吸附量）
rDeficitMb := rMbTarget - rMbValueMl;
IF rDeficitMb > 0.0 THEN
    xNeedAdd := TRUE;
    rAddPct := rDeficitMb * DL_BAC_PCT_PER_ML;                 // 补加比例 = 差额×0.15
    rBentoniteKgH := rSandRateKgH * rAddPct / DL_BAC_PCT;      // 补加量 = 处理量×比例/100
ELSE
    xNeedAdd := FALSE;                                         // 无需补加：不判故障 | no addition needed, not a fault
    rAddPct := 0.0;
    rBentoniteKgH := 0.0;
END_IF

// 段4｜出口
nFaultCode := 0;
xValid := TRUE;
FC_DL_BentoniteAdditiveCalc := TRUE;
END_FUNCTION
