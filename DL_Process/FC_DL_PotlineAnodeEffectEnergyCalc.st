// FC_DL_PotlineAnodeEffectEnergyCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 效应能耗核算：单次能耗 = V·I[kA]·t[min]/60 [kWh]（kA·V·min/60 = kWh），
        日能耗 = 单次 × 日次数；效应系数按「次/槽日」出口（统计窗为 24 h 槽日）。
  邻件/码位: 与 FC_DL_PotlineCellVoltageBudgetCalc 分域（效应附加电耗 vs 正常槽电压）；
             16#0002_9213 = 非有限、电压/电流/时长非正或次数为负拒收。
*)
FUNCTION FC_DL_PotlineAnodeEffectEnergyCalc : REAL
VAR_INPUT
    fEffectVoltage : REAL := 8.0;   // 效应净增电压 [V]，域 > 0 / Net effect voltage [V]
    fLineCurrentKA : REAL := 400.0; // 系列电流 [kA]，域 > 0 / Line current [kA]
    fEffectMin     : REAL := 3.0;   // 单次效应时长 [min]，域 > 0 / Effect duration [min]
    fEffectsPerDay : REAL := 0.5;   // 日效应次数 [次/日]，域 >= 0 / Effects per day [count/day]
END_VAR
VAR_OUTPUT
    fEnergyPerEffect   : REAL;      // 单次效应能耗 [kWh] / Energy per effect [kWh]
    fEffectCoefficient : REAL;      // 效应系数 [次/槽日] / Effect coefficient [count/pot-day]
    fDailyEnergy       : REAL;      // 日效应能耗 [kWh/日] / Daily energy [kWh/day]
    bValid             : BOOL;      // 结果有效回执 [-] / Result validity receipt
    uErrorId           : UDINT;     // 事件码，0 = 无事件 / Event code
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fEnergyPerEffect := 0.0;            // 单次能耗缺省零 / Per-effect default zero
fEffectCoefficient := 0.0;          // 效应系数缺省零 / Coefficient default zero
fDailyEnergy := 0.0;                // 日能耗缺省零 / Daily energy default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_PotlineAnodeEffectEnergyCalc := 0.0;  // 返回值缺省零（镜像单次能耗）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fEffectVoltage <> fEffectVoltage) OR (fLineCurrentKA <> fLineCurrentKA)
   OR (fEffectMin <> fEffectMin) OR (fEffectsPerDay <> fEffectsPerDay)
   OR (ABS(fEffectVoltage) >= 3.0E38) OR (ABS(fLineCurrentKA) >= 3.0E38)
   OR (ABS(fEffectMin) >= 3.0E38) OR (ABS(fEffectsPerDay) >= 3.0E38) THEN
    uErrorId := 16#0002_9213;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（电压/电流/时长为正 + 次数非负）/ Domain gate
IF (fEffectVoltage <= 0.0) OR (fLineCurrentKA <= 1.0E-6) OR (fEffectMin <= 1.0E-6) THEN
    uErrorId := 16#0002_9213;   // 电压、电流或时长非正 / Non-positive voltage, current or duration
    RETURN;
END_IF
IF fEffectsPerDay < 0.0 THEN
    uErrorId := 16#0002_9213;   // 效应次数为负 / Negative effect count
    RETURN;
END_IF
// 段 3：主计算（单次能耗 → 效应系数 → 日能耗）/ Main computation
fEnergyPerEffect := fEffectVoltage * fLineCurrentKA * fEffectMin / 60.0;    // V·I·t/60 [kWh] / Per effect
fEffectCoefficient := fEffectsPerDay;                           // 24 h 槽日内即次数本身 / Count over 24h
fDailyEnergy := fEnergyPerEffect * fEffectsPerDay;              // 日能耗 / Daily energy
// 段 4：出口闸（三输出非有限复核 + 非负复核）/ Outlet gate
IF (fEnergyPerEffect <> fEnergyPerEffect) OR (fEffectCoefficient <> fEffectCoefficient)
   OR (fDailyEnergy <> fDailyEnergy)
   OR (ABS(fEnergyPerEffect) >= 3.0E38) OR (ABS(fEffectCoefficient) >= 3.0E38)
   OR (ABS(fDailyEnergy) >= 3.0E38) THEN
    fEnergyPerEffect := 0.0;        // 复核失败回缺省 / Fallback on recheck failure
    fEffectCoefficient := 0.0;      // 复核失败回缺省 / Fallback on recheck failure
    fDailyEnergy := 0.0;            // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9213;       // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                     // 有效回执 / Validity receipt
FC_DL_PotlineAnodeEffectEnergyCalc := fEnergyPerEffect;     // 返回值镜像单次能耗 / Return mirrors
END_FUNCTION
