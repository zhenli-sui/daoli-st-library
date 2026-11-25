// FC_DL_DiacetylRestWindowCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 双乙酰还原时长：速率 = 参考速率·2^((T − Tref)/10)（Q10 = 2 工程近似，每升 10 °C 翻倍），
        时长 = LN(当前/目标)/速率 [h]；当前不高于目标时直接返回 0（已达标，不判错）。
  邻件/码位: 与 FC_DL_FermentAttenuationCalc 同属发酵后段件（主发酵终点 vs 还原终点）；
             16#0002_9236 = 非有限、浓度非正、参考速率非正或速率近零拒收。
*)
FUNCTION FC_DL_DiacetylRestWindowCalc : REAL
VAR_INPUT
    fTemp           : REAL := 14.0; // 还原温度 [°C] / Rest temperature [degC]
    fDiacetylNow    : REAL := 0.30; // 当前双乙酰 [mg/L]，域 > 0 / Current diacetyl [mg/L]
    fDiacetylTarget : REAL := 0.10; // 目标双乙酰 [mg/L]，域 > 0 / Target diacetyl [mg/L]
    fRateRef        : REAL := 0.05; // 参考温度衰减速率 [1/h]，域 > 0 / Decay rate at reference
    fTempRef        : REAL := 20.0; // 参考温度 [°C] / Reference temperature [degC]
END_VAR
VAR_OUTPUT
    fHoursNeeded : REAL;            // 预计还原时长 [h] / Estimated rest duration [h]
    bValid       : BOOL;            // 结果有效回执 [-] / Result validity receipt
    uErrorId     : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fRate : REAL := 0.0;            // 实际衰减速率 [1/h] / Effective decay rate [1/h]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fHoursNeeded := 0.0;                // 时长缺省零 / Duration default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_DiacetylRestWindowCalc := 0.0;    // 返回值缺省零（镜像时长）/ Return default zero
// 段 1：非有限闸（五入参全枚举）/ Non-finite gate over all inputs
IF (fTemp <> fTemp) OR (fDiacetylNow <> fDiacetylNow) OR (fDiacetylTarget <> fDiacetylTarget)
   OR (fRateRef <> fRateRef) OR (fTempRef <> fTempRef)
   OR (ABS(fTemp) >= 3.0E38) OR (ABS(fDiacetylNow) >= 3.0E38) OR (ABS(fDiacetylTarget) >= 3.0E38)
   OR (ABS(fRateRef) >= 3.0E38) OR (ABS(fTempRef) >= 3.0E38) THEN
    uErrorId := 16#0002_9236;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（浓度与参考速率非正拒收 + 已达标快通道，R4）/ Domain gate
IF (fDiacetylNow <= 0.0) OR (fDiacetylTarget <= 0.0) THEN
    uErrorId := 16#0002_9236;   // 浓度非正，LN 无意义 / Non-positive concentration
    RETURN;
END_IF
IF fRateRef <= 1.0E-6 THEN
    uErrorId := 16#0002_9236;   // 参考速率非正 / Non-positive reference rate
    RETURN;
END_IF
IF fDiacetylNow <= fDiacetylTarget THEN
    bValid := TRUE;             // 已达标：时长零，仍为有效解 / Already compliant, valid
    RETURN;                     // 时长已由段 0 置零 / Duration stays zero from stage 0
END_IF
// 段 3：主计算（Q10 温度修正 → LN 比值 → 时长）/ Main computation
fRate := fRateRef * EXP((fTemp - fTempRef) / 10.0 * 0.693147180559945);     // ref·2^expo [1/h] / Effective rate
IF fRate <= 1.0E-9 THEN
    uErrorId := 16#0002_9236;   // 速率近零，时长发散 / Rate too small, duration diverges
    RETURN;
END_IF
fHoursNeeded := LN(fDiacetylNow / fDiacetylTarget) / fRate;     // 时长 [h] / Rest duration
// 段 4：出口闸（非有限复核 + 非负复核）/ Outlet gate
IF (fHoursNeeded <> fHoursNeeded) OR (ABS(fHoursNeeded) >= 3.0E38) OR (fHoursNeeded < 0.0) THEN
    fHoursNeeded := 0.0;        // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9236;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_DiacetylRestWindowCalc := fHoursNeeded;   // 返回值镜像时长 / Return mirrors duration
END_FUNCTION
