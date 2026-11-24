(*
  DL Factory R83 | FC_DL_RinseDragOutCalc
  功能：由带出液量与浓度差算稀释补水率，并给每小时换槽次数与稳态浓度。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_RinseDragOutCalc : REAL
VAR_INPUT
    fDragLph       : REAL; // 工件带出液量 [L/h] / Drag-out volume rate [L/h]
    fRinseVolL     : REAL; // 漂洗槽有效容积 [L] / Rinse tank working volume [L]
    fDragConcPct   : REAL; // 带出液主成分浓度 [%] / Drag-out main component concentration [%]
    fTargetConcPct : REAL; // 漂洗槽允许稳态浓度 [%] / Allowed steady concentration [%]
END_VAR
VAR_OUTPUT
    fDilutionLph : REAL; // 稀释补水率（负值按零）[L/h] / Dilution make-up rate [L/h]
    fTurnsPh     : REAL; // 每小时换槽次数（槽容周转率）[次/h] / Tank turnovers per hour [1/h]
    fSteadyPct   : REAL; // 无补水时稳态平衡浓度 [%] / Steady concentration without make-up [%]
    xValid       : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
// 出口预置：四出口统一预置（R256）
fDilutionLph := 0.0; fTurnsPh := 0.0; fSteadyPct := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fDragLph > -1.0E30 AND fDragLph < 1.0E30) OR NOT (fRinseVolL > -1.0E30 AND fRinseVolL < 1.0E30) OR NOT (fDragConcPct > -1.0E30 AND fDragConcPct < 1.0E30) OR NOT (fTargetConcPct > -1.0E30 AND fTargetConcPct < 1.0E30) OR fDragLph < 0.0 OR fRinseVolL <= 0.0 OR fDragConcPct <= 0.0 OR fTargetConcPct <= 0.0 THEN
    FC_DL_RinseDragOutCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 浓度次序闸：目标浓度不严于带出浓度时无需稀释
IF fTargetConcPct >= fDragConcPct THEN
    fDilutionLph := 0.0;            // 无需补水 [L/h] / No make-up needed
    fSteadyPct   := fDragConcPct;   // 稳态即带出浓度 [%] / Steady equals drag-out concentration
ELSE
    // 物料平衡：带出带入溶质 = 补水带走溶质，故补水率 = 带出量 × (带出浓度/目标浓度 - 1)
    // 浓度比无量纲，量纲保持 L/h（量纲自洽）
    fDilutionLph := fDragLph * (fDragConcPct / fTargetConcPct - 1.0); // 稀释补水率 [L/h]
    fSteadyPct   := fTargetConcPct; // 补水到位后稳态浓度即目标值 [%] / Steady state hits target
END_IF
// 槽容周转率：L/h ÷ L = 1/h，槽容分母显式零闸（R4/R21）
IF ABS(fRinseVolL) > 1.0E-9 THEN    // 槽容分母显式零闸 / Explicit zero gate on tank volume
    fTurnsPh := fDragLph / fRinseVolL;  // 每小时换槽次数 [次/h] / Tank turnovers per hour
ELSE
    fTurnsPh := 0.0;                // 除零防御缺省 / Divide-by-zero default
END_IF
xValid := TRUE;                             // 链路有效 / Chain valid
FC_DL_RinseDragOutCalc := fDilutionLph;     // 返回稀释补水率 [L/h] / Return dilution rate [L/h]
END_FUNCTION
