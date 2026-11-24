(*
  DL Factory R83 | FC_DL_DiverterLeadTimeCalc
  功能：按执行机构动作时间与线速算分流器提前量，反算触发延时并判可实现性。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_DiverterLeadTimeCalc : REAL
VAR_INPUT
    fConvSpeedMps   : REAL; // 输送线速度 [m/s] / Conveyor speed [m/s]
    fActuatorMs     : REAL; // 分流器全行程动作时间 [ms] / Diverter full-stroke time [ms]
    fSensorToPivotM : REAL; // 检测位到分流点距离 [m] / Sensor-to-pivot distance [m]
    fItemLenM       : REAL; // 物件长度 [m] / Item length along travel [m]
END_VAR
VAR_OUTPUT
    fLeadM          : REAL; // 需提前动作的等效距离 [m] / Required lead distance [m]
    fTriggerDelayMs : REAL; // 从检测沿到发出动作指令的延时 [ms] / Trigger delay after sensor edge [ms]
    xFeasible       : BOOL; // 时序可实现（延时非负且不超总输送时间）/ Timing feasible flag
    xValid          : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fTotalMs : REAL; // 检测位到分流点总输送时间 [ms] / Total transit time [ms]
END_VAR
// 出口预置：四出口统一预置，可实现标志预置 FALSE（安全侧）
fLeadM := 0.0; fTriggerDelayMs := 0.0; xFeasible := FALSE; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 速度零闸（R4/R20/R21）
IF NOT (fConvSpeedMps > -1.0E30 AND fConvSpeedMps < 1.0E30) OR NOT (fActuatorMs > -1.0E30 AND fActuatorMs < 1.0E30) OR NOT (fSensorToPivotM > -1.0E30 AND fSensorToPivotM < 1.0E30) OR NOT (fItemLenM > -1.0E30 AND fItemLenM < 1.0E30) OR fConvSpeedMps <= 0.0 OR fActuatorMs < 0.0 OR fSensorToPivotM <= 0.0 OR fItemLenM < 0.0 THEN
    FC_DL_DiverterLeadTimeCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 提前量：线速 × 动作时间(s) + 半件长（使物件中心对准分流点），m/s × s = m
fLeadM := fConvSpeedMps * (fActuatorMs / 1000.0) + fItemLenM / 2.0; // 提前量 [m] / Lead distance [m]
// 总输送时间：m ÷ (m/s) = s，×1000 = ms（分母已判正）
fTotalMs := (fSensorToPivotM / fConvSpeedMps) * 1000.0;   // 总输送时间 [ms] / Total transit time [ms]
// 触发延时：总输送时间 - 提前量对应时间（m ÷ m/s × 1000 = ms，量纲自洽）
fTriggerDelayMs := fTotalMs - (fLeadM / fConvSpeedMps) * 1000.0; // 触发延时 [ms] / Trigger delay [ms]
// 可实现性闸：负延时=前置距离不足；延时超总时间=参数逻辑倒置
IF fTriggerDelayMs < 0.0 THEN
    fTriggerDelayMs := 0.0;         // 负延时钳零（立即动作）/ Negative delay clamped, act at once
    xFeasible       := FALSE;       // 前置距离不足，不可分拣 / Insufficient lead distance
    xValid          := TRUE;        // 计算有效，仅结论不可行 / Calculation valid, conclusion infeasible
ELSIF fTriggerDelayMs <= fTotalMs THEN
    xFeasible := TRUE;              // 时序可实现 / Timing feasible
    xValid    := TRUE;              // 链路有效 / Chain valid
ELSE
    fTriggerDelayMs := fTotalMs;    // 延时超总时间钳位 / Clamp delay to total transit
    xFeasible       := FALSE;       // 逻辑倒置判不可行 / Inverted logic flagged
    xValid          := FALSE;       // 参数异常 / Parameter anomaly
END_IF
FC_DL_DiverterLeadTimeCalc := fTriggerDelayMs; // 返回触发延时 [ms] / Return trigger delay [ms]
END_FUNCTION
