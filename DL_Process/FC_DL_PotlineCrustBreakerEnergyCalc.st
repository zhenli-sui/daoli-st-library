// FC_DL_PotlineCrustBreakerEnergyCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 打壳机械能：单次冲击 = F[kN]·s[mm]/1000 [kJ]（kN·mm = J，除 1000 得 kJ），
        单次打壳 = 单次冲击 × 冲击数，平均功率 = 单次打壳 × 频次/3600 [kW]（kJ/h ÷ 3600 = kW）。
  邻件/码位: 与 FC_DL_PotlineAnodeEffectEnergyCalc 同为能耗件（本件机械能 vs 电能，不可互换）；
             16#0002_9219 = 非有限、任一量非正或冲击数 < 1 拒收。
*)
FUNCTION FC_DL_PotlineCrustBreakerEnergyCalc : REAL
VAR_INPUT
    fImpactForce     : REAL := 20.0;   // 单次冲击力 [kN]，域 > 0 / Impact force [kN]
    fStroke          : REAL := 50.0;   // 冲击行程 [mm]，域 > 0 / Impact stroke [mm]
    fStrikesPerBreak : REAL := 3.0;    // 单次打壳冲击数 [次]，域 >= 1 / Strikes per break [count]
    fBreaksPerHour   : REAL := 6.0;    // 打壳频次 [次/h]，域 > 0 / Breaks per hour [count/h]
END_VAR
VAR_OUTPUT
    fEnergyPerBreak : REAL;             // 单次打壳机械能 [kJ] / Energy per break [kJ]
    fPowerAvg       : REAL;             // 平均功率 [kW] / Average mechanical power [kW]
    bValid          : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId        : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fEnergyPerStrike : REAL := 0.0;     // 单次冲击机械能 [kJ] / Energy per strike [kJ]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fEnergyPerBreak := 0.0;                 // 单次打壳能量缺省零 / Per-break energy default zero
fPowerAvg := 0.0;                       // 平均功率缺省零 / Average power default zero
bValid := FALSE;                        // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                    // 事件码预清 / Event code preset clear
FC_DL_PotlineCrustBreakerEnergyCalc := 0.0; // 返回值缺省零（镜像单次能量）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fImpactForce <> fImpactForce) OR (fStroke <> fStroke)
   OR (fStrikesPerBreak <> fStrikesPerBreak) OR (fBreaksPerHour <> fBreaksPerHour)
   OR (ABS(fImpactForce) >= 3.0E38) OR (ABS(fStroke) >= 3.0E38)
   OR (ABS(fStrikesPerBreak) >= 3.0E38) OR (ABS(fBreaksPerHour) >= 3.0E38) THEN
    uErrorId := 16#0002_9219;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（力/行程/频次为正 + 冲击数下限，R4）/ Domain gate
IF (fImpactForce <= 0.0) OR (fStroke <= 0.0) OR (fBreaksPerHour <= 0.0) THEN
    uErrorId := 16#0002_9219;   // 力、行程或频次非正 / Non-positive force, stroke or rate
    RETURN;
END_IF
IF fStrikesPerBreak < 1.0 THEN
    uErrorId := 16#0002_9219;   // 冲击数不足 1 次 / Strike count below one
    RETURN;
END_IF
// 段 3：主计算（冲击能 → 单次打壳能 → 平均功率）/ Main computation
fEnergyPerStrike := fImpactForce * fStroke / 1000.0;            // F·s/1000 [kJ] / Energy per strike
fEnergyPerBreak := fEnergyPerStrike * fStrikesPerBreak;         // 单次打壳机械能 [kJ] / Per break
fPowerAvg := fEnergyPerBreak * fBreaksPerHour / 3600.0;         // 平均功率 [kW] / Average power
// 段 4：出口闸（双输出非有限复核 + 非负复核）/ Outlet gate
IF (fEnergyPerBreak <> fEnergyPerBreak) OR (fPowerAvg <> fPowerAvg)
   OR (ABS(fEnergyPerBreak) >= 3.0E38) OR (ABS(fPowerAvg) >= 3.0E38)
   OR (fEnergyPerBreak < 0.0) OR (fPowerAvg < 0.0) THEN
    fEnergyPerBreak := 0.0;     // 复核失败回缺省 / Fallback on recheck failure
    fPowerAvg := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9219;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineCrustBreakerEnergyCalc := fEnergyPerBreak;     // 返回值镜像单次机械能 / Return mirrors
END_FUNCTION
