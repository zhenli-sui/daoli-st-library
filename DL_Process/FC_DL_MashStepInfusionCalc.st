// FC_DL_MashStepInfusionCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 糖化升温热量与蒸汽：Q = m·cp·(T末 − T初)/(1 − 热损率/100) [kJ]，蒸汽 = Q/潜热 [kg]；
        未计入罐体蓄热与投料比热差（工程简化）。
  邻件/码位: 与 FC_DL_WortAerationRateCalc、FC_DL_WortBoilEvaporationCalc 同属前段热工链；
             16#0002_9231 = 非有限、质量/比热/潜热非正、末温不高于初温或热损率越界拒收。
*)
FUNCTION FC_DL_MashStepInfusionCalc : REAL
VAR_INPUT
    fMashMass    : REAL := 5000.0;  // 醪液质量 [kg]，域 > 0 / Mash mass [kg]
    fCp          : REAL := 3.9;     // 醪液比热 [kJ/(kg·K)]，域 > 0 / Specific heat [kJ/(kg K)]
    fTempStart   : REAL := 50.0;    // 升温初温 [°C] / Initial temperature [degC]
    fTempEnd     : REAL := 65.0;    // 升温末温 [°C]，域 > 初温 / Target temperature [degC]
    fLossRate    : REAL := 5.0;     // 热损率 [%]，域 [0, 100) / Heat loss ratio [%]
    fSteamLatent : REAL := 2100.0;  // 蒸汽潜热 [kJ/kg]，域 > 0 / Steam latent heat [kJ/kg]
END_VAR
VAR_OUTPUT
    fHeatNeed  : REAL;              // 需热量 [kJ] / Required heat [kJ]
    fSteamNeed : REAL;              // 需蒸汽量 [kg] / Required steam [kg]
    bValid     : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fHeatNeed := 0.0;                   // 需热量缺省零 / Required heat default zero
fSteamNeed := 0.0;                  // 需蒸汽缺省零 / Required steam default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_MashStepInfusionCalc := 0.0;  // 返回值缺省零（镜像需蒸汽）/ Return default zero
// 段 1：非有限闸（六入参全枚举）/ Non-finite gate over all inputs
IF (fMashMass <> fMashMass) OR (fCp <> fCp) OR (fTempStart <> fTempStart)
   OR (fTempEnd <> fTempEnd) OR (fLossRate <> fLossRate) OR (fSteamLatent <> fSteamLatent)
   OR (ABS(fMashMass) >= 3.0E38) OR (ABS(fCp) >= 3.0E38) OR (ABS(fTempStart) >= 3.0E38)
   OR (ABS(fTempEnd) >= 3.0E38) OR (ABS(fLossRate) >= 3.0E38) OR (ABS(fSteamLatent) >= 3.0E38) THEN
    uErrorId := 16#0002_9231;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（质量/比热/潜热为正 + 末温高于初温 + 热损率上界，R4）/ Domain gate
IF (fMashMass <= 1.0E-6) OR (fCp <= 1.0E-6) OR (fSteamLatent <= 1.0E-6) THEN
    uErrorId := 16#0002_9231;   // 质量、比热或潜热非正 / Non-positive mass, capacity or latent
    RETURN;
END_IF
IF fTempEnd <= fTempStart THEN
    uErrorId := 16#0002_9231;   // 末温不高于初温，无需升温 / Target not above initial
    RETURN;
END_IF
IF (fLossRate < 0.0) OR (fLossRate >= 100.0) THEN
    uErrorId := 16#0002_9231;   // 热损率越界（分母近零）/ Heat loss ratio out of range
    RETURN;
END_IF
// 段 3：主计算（需热量 → 需蒸汽）/ Main computation
fHeatNeed := fMashMass * fCp * (fTempEnd - fTempStart) / (1.0 - fLossRate / 100.0);   // 需热量 [kJ]
fSteamNeed := fHeatNeed / fSteamLatent;                         // 需蒸汽 [kg] / Required steam
// 段 4：出口闸（双输出非有限复核 + 正数复核）/ Outlet gate
IF (fHeatNeed <> fHeatNeed) OR (fSteamNeed <> fSteamNeed)
   OR (ABS(fHeatNeed) >= 3.0E38) OR (ABS(fSteamNeed) >= 3.0E38)
   OR (fHeatNeed <= 0.0) OR (fSteamNeed <= 0.0) THEN
    fHeatNeed := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    fSteamNeed := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9231;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_MashStepInfusionCalc := fSteamNeed;       // 返回值镜像需蒸汽 / Return mirrors steam demand
END_FUNCTION
