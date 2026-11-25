// FC_DL_CakeMoistureDryCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 丝饼含水率与干燥时长：当前含水率 = 100·(湿重 − 干重)/湿重 [%]，
        当前水质量 = 湿重 − 干重，目标水质量 = 干重·目标/(100 − 目标)（目标按湿基反解），
        待除水 = 当前水 − 目标水（负值归零），预计时长 = 待除水/干燥速率 [h]。
  邻件/码位: 与 FC_DL_FiberCoolingAirflowCalc 同属后处理热工件（成品干燥 vs 在线冷却）；
             16#0002_9229 = 非有限、湿重不大于干重、目标含水率越界或速率非正拒收。
*)
FUNCTION FC_DL_CakeMoistureDryCalc : REAL
VAR_INPUT
    fWetMass        : REAL := 20.0;     // 湿饼质量 [kg]，域 > 干重 / Wet cake mass [kg]
    fDryMass        : REAL := 14.0;     // 干基质量 [kg]，域 >= 0 / Dry basis mass [kg]
    fTargetMoisture : REAL := 8.0;      // 目标含水率 [%]，域 [0, 100) / Target moisture [%]
    fDryRate        : REAL := 3.0;      // 干燥速率 [kg/h]，域 > 0 / Drying rate [kg/h]
END_VAR
VAR_OUTPUT
    fMoistureNow   : REAL;              // 当前含水率 [%] / Current moisture [%]
    fWaterToRemove : REAL;              // 待除水质量 [kg] / Water to remove [kg]
    fDryTimeH      : REAL;              // 预计干燥时长 [h] / Estimated drying time [h]
    bValid         : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fWaterNow    : REAL := 0.0;         // 当前水质量 [kg] / Current water mass [kg]
    fWaterTarget : REAL := 0.0;         // 目标水质量 [kg] / Target water mass [kg]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fMoistureNow := 0.0;                // 含水率缺省零 / Moisture default zero
fWaterToRemove := 0.0;              // 待除水缺省零 / Water to remove default zero
fDryTimeH := 0.0;                   // 干燥时长缺省零 / Drying time default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_CakeMoistureDryCalc := 0.0;   // 返回值缺省零（镜像待除水）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fWetMass <> fWetMass) OR (fDryMass <> fDryMass)
   OR (fTargetMoisture <> fTargetMoisture) OR (fDryRate <> fDryRate)
   OR (ABS(fWetMass) >= 3.0E38) OR (ABS(fDryMass) >= 3.0E38)
   OR (ABS(fTargetMoisture) >= 3.0E38) OR (ABS(fDryRate) >= 3.0E38) THEN
    uErrorId := 16#0002_9229;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（湿重大于干重且为正 + 干基非负 + 目标区间 + 速率正，R4）/ Domain gate
IF (fWetMass <= 1.0E-6) OR (fWetMass <= fDryMass) THEN
    uErrorId := 16#0002_9229;   // 湿重非正或不大于干重 / Wet mass not above dry mass
    RETURN;
END_IF
IF fDryMass < 0.0 THEN
    uErrorId := 16#0002_9229;   // 干基质量为负 / Negative dry mass
    RETURN;
END_IF
IF (fTargetMoisture < 0.0) OR (fTargetMoisture >= 100.0) THEN
    uErrorId := 16#0002_9229;   // 目标含水率越界（分母近零）/ Target moisture out of range
    RETURN;
END_IF
IF fDryRate <= 1.0E-6 THEN
    uErrorId := 16#0002_9229;   // 干燥速率非正 / Non-positive drying rate
    RETURN;
END_IF
// 段 3：主计算（当前含水率 → 目标水 → 待除水 → 时长）/ Main computation
fWaterNow := fWetMass - fDryMass;                               // 当前水质量 [kg] / Current water
fMoistureNow := 100.0 * fWaterNow / fWetMass;                   // 当前含水率 [%] / Current moisture
fWaterTarget := fDryMass * fTargetMoisture / (100.0 - fTargetMoisture);     // 目标水 [kg] / Target water
fWaterToRemove := fWaterNow - fWaterTarget;                     // 待除水 [kg] / Water to remove
IF fWaterToRemove < 0.0 THEN
    fWaterToRemove := 0.0;                                      // 已达标归零 / Already dry, clamp zero
END_IF
fDryTimeH := fWaterToRemove / fDryRate;                         // 预计时长 [h] / Estimated time
// 段 4：出口闸（三输出非有限复核 + 非负复核）/ Outlet gate
IF (fMoistureNow <> fMoistureNow) OR (fWaterToRemove <> fWaterToRemove) OR (fDryTimeH <> fDryTimeH)
   OR (ABS(fMoistureNow) >= 3.0E38) OR (ABS(fWaterToRemove) >= 3.0E38) OR (ABS(fDryTimeH) >= 3.0E38)
   OR (fMoistureNow < 0.0) OR (fWaterToRemove < 0.0) OR (fDryTimeH < 0.0) THEN
    fMoistureNow := 0.0;        // 复核失败回缺省 / Fallback on recheck failure
    fWaterToRemove := 0.0;      // 复核失败回缺省 / Fallback on recheck failure
    fDryTimeH := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9229;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_CakeMoistureDryCalc := fWaterToRemove;    // 返回值镜像待除水 / Return mirrors water
END_FUNCTION
