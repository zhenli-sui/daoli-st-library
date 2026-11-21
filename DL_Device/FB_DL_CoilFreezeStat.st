// =====================================================================
// FB_DL_CoilFreezeStat.st
// 盘管防冻统计判据（只判不控：低温累计 + 温降速率，预警/报警锁存）
// Coil freeze statistics FB (detect only)
// 码位: 16#0003_03CA ~ 16#0003_03CE (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 9)
// =====================================================================
FUNCTION_BLOCK FB_DL_CoilFreezeStat
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    bReset         : BOOL  := FALSE;   // 复位锁存 / Reset
    bTempValid     : BOOL  := FALSE;   // 温度有效 / Temp valid
    fCoilTemp_C    : REAL  := 12.0;    // 盘管温度 -40~80 ℃ / Coil temperature [degC]
    fFreezeLimit_C : REAL  := 2.0;     // 冻结判定限 -10~10 ℃ / Freeze limit [degC]
    fRateAlarm_Cmin : REAL := 1.0;     // 温降速率报警 0.1~20 K/min / Cooling rate alarm [K/min]
    tAccumWarn     : TIME  := T#5M;    // 累计预警 T#10S~T#2H / Accumulate warn [s]
    tAccumAlarm    : TIME  := T#10M;   // 累计报警 T#10S~T#8H / Accumulate alarm [s]
    fDecayFactor   : REAL  := 0.5;     // 回暖衰减系数 0~1 / Decay factor [-]
    bFanRun        : BOOL  := FALSE;   // 风机运行 / Fan running
    tCycle         : TIME  := T#1S;    // 周期 T#100MS~T#10S / Cycle [s]
END_VAR
VAR_OUTPUT
    tColdAccum     : TIME;             // 低温累计时长 / Cold accumulate [s]
    fRate_Cmin     : REAL;             // 温降速率 K/min / Cooling rate [K/min]
    bWarn          : BOOL;             // 预警 / Warning
    bAlarm         : BOOL;             // 报警（锁存）/ Alarm latched
    eErr           : UDINT;            // 错误码 / Error code
END_VAR
VAR
    fTempPrev      : REAL  := 12.0;    // 上拍温度快照 / Previous temperature snapshot [degC]
    fTempAcc       : REAL  := 0.0;     // 累计秒值（内部实数实现）/ Accumulated seconds, internal [s]
    tWarnS         : REAL;             // 预警阈值秒 / Warn threshold seconds [s]
    tAlarmS        : REAL;             // 报警阈值秒 / Alarm threshold seconds [s]
    tCycleS        : REAL;             // 周期秒值（钳 ≥0.1）/ Cycle seconds, clamped [s]
    fDelta         : REAL;             // 温度差 / Temperature delta [K]
    fRateRaw       : REAL;             // 原始速率 K/min / Raw rate [K/min]
    fRateMaxLim    : REAL;             // 速率显示上限 / Rate display limit [K/min]
    bRateTrip      : BOOL;             // 速率越限 / Rate trip flag
    tAccumUpperS   : REAL;             // 累计上界 = 2×报警阈值 / Accum upper bound [s]
    bDecayOK       : BOOL;             // 衰减可执行标记 / Decay allowed flag
    xFirstScan     : BOOL  := TRUE;    // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0003_03CA 信息 统计正常（未越限）
//   16#0003_03CB 故障 温度非有限 / tCycle 非法
//   16#0003_03CC 故障 tAccumAlarm ≤ tAccumWarn / fDecayFactor < 0 / fDecayFactor > 1（组态错）
//   16#0003_03CD 信息 bTempValid=FALSE → 累计冻结（不增不减）
//   16#0003_03CE 故障 tColdAccum ≥ tAccumAlarm 或 fRate_Cmin ≥ fRateAlarm_Cmin → bAlarm=TRUE 锁存
// ---------------------------------------------------------------------

// ---- 周期与阈值转秒 / Cycle and thresholds to seconds ----
tCycleS  := TIME_TO_REAL(tCycle) / 1000.0;      // 周期秒值 / Cycle seconds [s]
tWarnS   := TIME_TO_REAL(tAccumWarn) / 1000.0;  // 预警阈值秒 / Warn threshold [s]
tAlarmS  := TIME_TO_REAL(tAccumAlarm) / 1000.0; // 报警阈值秒 / Alarm threshold [s]
IF tCycleS < 0.1 THEN
    tCycleS := 0.1;             // 钳 ≥0.1 s 防差分噪声放大 / Clamp 0.1 s min
END_IF

// ---- 非有限与周期合法性闸 / Finite and cycle validity gate ----
IF (tCycle = T#0MS) OR (tCycleS > 10.0)
   OR (fCoilTemp_C <> fCoilTemp_C) OR (ABS(fCoilTemp_C) >= 1.0E12) THEN
    eErr := 16#0003_03CB;       // 故障码 / Fault code
    RETURN;                     // 累计与报警保持 / Accum and alarm hold
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (tAccumAlarm <= tAccumWarn) OR (fDecayFactor < 0.0) OR (fDecayFactor > 1.0)
   OR (fRateAlarm_Cmin <= 0.0) THEN
    eErr := 16#0003_03CC;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 累计上界 / Accum upper bound ----
tAccumUpperS := 2.0 * tAlarmS;  // 上界 = 2×报警阈值 / Upper bound 2x alarm

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    fTempPrev := fCoilTemp_C;   // 快照对齐当前 / Snapshot align
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销：累计与报警保持，速率清零 / Disable: hold accum, zero rate ----
IF NOT bEnable THEN
    fRate_Cmin := 0.0;          // 速率清零 / Rate zero
    bWarn := FALSE;             // 预警复位 / Warn reset
    eErr := 16#0003_03CA;       // 信息级：空闲正常 / Info: idle normal
    RETURN;                     // 累计与报警锁存保持 / Accum and latch hold
END_IF

// ---- 温度传感器无效 → 冻结累计（不增不减）+ 信息级 / Temp invalid: freeze accum ----
IF NOT bTempValid THEN
    eErr := 16#0003_03CD;       // 信息级：累计冻结 / Info: accum frozen
    fTempPrev := fCoilTemp_C;   // 快照对齐防恢复瞬跳 / Align snapshot to avoid spike
    RETURN;                     // 累计与报警保持 / Accum and alarm hold
END_IF

// ---- 温降速率（一阶差分）/ Cooling rate (first-order difference) ----
fDelta := fCoilTemp_C - fTempPrev;          // 温度差 / Temperature delta [K]
fRateRaw := -fDelta / (tCycleS / 60.0);     // 降温为正，K/min / Positive when cooling [K/min]
IF fRateRaw > 1.0E12 THEN
    fRateRaw := 1.0E12;         // 速率显示上限防溢出 / Rate display clamp
END_IF
fRate_Cmin := fRateRaw;         // 输出速率 / Output rate

// ---- 速率越限判（即使累计未到）/ Rate trip check (even if accum low) ----
bRateTrip := (fRateRaw >= fRateAlarm_Cmin);     // 越限标志 / Trip flag

// ---- 累计逻辑：低温累计，回暖衰减 / Accumulation: cold add, warm decay ----
bDecayOK := FALSE;              // 衰减标记复位 / Reset flag
IF fCoilTemp_C < fFreezeLimit_C THEN
    // 低温：累计递增 / Cold: accumulate
    fTempAcc := fTempAcc + tCycleS;     // 累加 / Add cycle
    IF fTempAcc > tAccumUpperS THEN
        fTempAcc := tAccumUpperS;       // 钳上界防溢出 / Clamp upper bound
    END_IF
ELSE
    // 回暖且风机运行：按衰减系数递减（不得低于 0）/ Warm + fan: decay, floor 0
    IF bFanRun AND (fTempAcc > 0.0) THEN
        fTempAcc := fTempAcc - fDecayFactor * tCycleS;  // 衰减 / Decay
        IF fTempAcc < 0.0 THEN
            fTempAcc := 0.0;    // 下限 0 / Floor 0
        END_IF
        bDecayOK := TRUE;       // 衰减已执行 / Decay executed
    END_IF
END_IF
tColdAccum := REAL_TO_TIME(fTempAcc * 1000.0);  // 输出累计时长 / Output accumulate

// ---- 报警锁存 / Alarm latch ----
IF bRateTrip OR (fTempAcc >= tAlarmS) THEN
    bAlarm := TRUE;             // 锁存 / Latch
END_IF

// ---- 锁存解除式（可达性自证：三条件齐才解除，R28）/ Release path: all three conditions ----
IF bAlarm AND bReset
   AND (fCoilTemp_C > fFreezeLimit_C + 2.0)
   AND (fRate_Cmin < 0.0) THEN
    bAlarm := FALSE;            // 解除报警锁存 / Release alarm latch
    fTempAcc := 0.0;            // 累计清零 / Accum cleared
    tColdAccum := T#0MS;        // 输出同步清零 / Output synced
END_IF

// ---- 预警与错误码（故障级优先，锁存回放不重推断）/ Warn and code, fault replay first ----
IF bAlarm THEN
    bWarn := TRUE;              // 报警含预警 / Alarm implies warn
    eErr  := 16#0003_03CE;      // 故障码回放 / Fault code replay
ELSE
    bWarn := (fTempAcc >= tWarnS);  // 累计预警判 / Accum warn verdict
    IF bWarn THEN
        eErr := 16#0003_03CA;   // 信息级：预警期统计正常口径 / Info: warn period
    ELSE
        eErr := 16#0003_03CA;   // 信息级：统计正常 / Info: normal
    END_IF
END_IF

// ---- 上拍快照更新 / Previous snapshot update ----
fTempPrev := fCoilTemp_C;       // 快照 / Snapshot

END_FUNCTION_BLOCK
