(*
  DL Factory R84 | FC_DL_ToolWearVbCalc
  功能：按磨损速率算后刀面磨损量 VB 与到磨损限值的剩余可用时间
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ToolWearVbCalc : REAL
VAR_INPUT
    fVb0Mm : REAL := 0.05; // 初始后刀面磨损 [mm] / initial flank wear [mm]
    fKMmPerM : REAL := 0.00002; // 磨损系数（每米切削路程增量） [mm/m] / wear coefficient [mm/m]
    fVcMpm : REAL := 200.0; // 切削线速度 [m/min] / cutting speed [m/min]
    fTimeMin : REAL := 10.0; // 累计切削时间 [min] / accumulated cutting time [min]
    fVbLimitMm : REAL := 0.30; // 后刀面磨损限值（换刀判据） [mm] / flank wear limit [mm]
END_VAR
VAR_OUTPUT
    fRemainMin : REAL; // 到限值剩余可用时间 [min] / remaining usable time [min]
    xWorn : BOOL; // 已达磨损限值 [-] / wear limit reached [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fPathM : REAL; // 累计切削路程 [m] / accumulated cutting path [m]
    fVbRaw : REAL; // 磨损量中间量 [mm] / wear intermediate [mm]
    fRateMmPerMin : REAL; // 磨损速率 [mm/min] / wear rate [mm/min]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ToolWearVbCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fRemainMin := 0.0; // 剩余时间预置零 [min] / remaining time preset zero [min]
xWorn := FALSE; // 磨损到位位预置 FALSE [-] / wear flag preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fVb0Mm > -1.0E30 AND fVb0Mm < 1.0E30) OR NOT (fKMmPerM > -1.0E30 AND fKMmPerM < 1.0E30) OR NOT (fVcMpm > -1.0E30 AND fVcMpm < 1.0E30) OR NOT (fTimeMin > -1.0E30 AND fTimeMin < 1.0E30) OR NOT (fVbLimitMm > -1.0E30 AND fVbLimitMm < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fVb0Mm < 0.0 OR fKMmPerM < 0.0 OR fVcMpm < 0.0 OR fTimeMin < 0.0 OR fVbLimitMm < 1.0E-9 THEN
    RETURN; // 磨损量/系数/速度/时间负域或限值非正即非法 [mm] / negative domains or non positive limit [mm]
END_IF

// 段 3｜VB = VB0 + k × (vc × t)
fPathM := fVcMpm * fTimeMin; // m/min × min = m / [m/min] × [min] = [m]
fVbRaw := fVb0Mm + (fKMmPerM * fPathM); // mm + mm/m × m = mm / [mm] + [mm/m] × [m] = [mm]
IF NOT (fVbRaw > -1.0E30 AND fVbRaw < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the result [-]
END_IF

// 段 4｜剩余时间 = (限值 − VB) / 磨损速率
fRateMmPerMin := fKMmPerM * fVcMpm; // mm/m × m/min = mm/min / [mm/m] × [m/min] = [mm/min]
IF fVbRaw >= fVbLimitMm THEN
    xWorn := TRUE; // 已达/超限：剩余时间为零 [-] / limit reached, no remaining time [-]
    fRemainMin := 0.0; // 剩余时间钳零 [min] / clamp remaining time to zero [min]
ELSIF fRateMmPerMin < 1.0E-9 THEN
    fRemainMin := -1.0; // 分母闸：磨损速率趋零则剩余时间不可估 [min] / denominator gate, wear rate near zero [min]
ELSE
    fRemainMin := (fVbLimitMm - fVbRaw) / fRateMmPerMin; // mm ÷ mm/min = min / [mm] / [mm/min] = [min]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ToolWearVbCalc := fVbRaw; // 返回磨损量 [mm] / return the flank wear [mm]
END_FUNCTION
