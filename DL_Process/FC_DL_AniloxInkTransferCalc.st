(*
  DL Factory R83 | FC_DL_AniloxInkTransferCalc
  功能：由网穴容积、转移率与油墨密度算单位面积传墨量及每小时耗墨量。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_AniloxInkTransferCalc : REAL
VAR_INPUT
    fCellVolCm3M2 : REAL; // 网穴容积（单位面积）[cm³/m²] / Cell volume per area [cm^3/m^2]
    fTransferPct  : REAL; // 网穴转移率（0~100）[%] / Cell transfer ratio [%]
    fInkDensity   : REAL; // 油墨密度 [g/cm³] / Ink density [g/cm^3]
    fWebWidthM    : REAL; // 料带幅宽 [m] / Web width [m]
    fSpeedMpm     : REAL; // 印刷速度 [m/min] / Press speed [m/min]
END_VAR
VAR_OUTPUT
    fInkGsr : REAL; // 单位面积传墨量 [g/m²] / Ink transfer per area [g/m^2]
    fInkKgH : REAL; // 每小时耗墨量 [kg/h] / Ink consumption per hour [kg/h]
    xValid  : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fAreaM2H : REAL; // 每小时过墨面积 [m²/h] / Inked area per hour [m^2/h]
END_VAR
// 出口预置：三出口统一预置（R256）
fInkGsr := 0.0; fInkKgH := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fCellVolCm3M2 > -1.0E30 AND fCellVolCm3M2 < 1.0E30) OR NOT (fTransferPct > -1.0E30 AND fTransferPct < 1.0E30) OR NOT (fInkDensity > -1.0E30 AND fInkDensity < 1.0E30) OR NOT (fWebWidthM > -1.0E30 AND fWebWidthM < 1.0E30) OR NOT (fSpeedMpm > -1.0E30 AND fSpeedMpm < 1.0E30) OR fCellVolCm3M2 < 0.0 OR fInkDensity <= 0.0 OR fWebWidthM <= 0.0 THEN
    FC_DL_AniloxInkTransferCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 转移率域闸：0~100% 之外按边界钳位后继续（码级不断链）
IF fTransferPct < 0.0 THEN
    fInkGsr := 0.0;                 // 负转移率按零处理 [g/m²] / Negative ratio as zero
ELSIF fTransferPct > 100.0 THEN
    fInkGsr := fCellVolCm3M2 * fInkDensity;   // 满转移上限 [g/m²] / Full transfer ceiling
ELSE
    // cm³/m² × g/cm³ × % / 100 = g/m²（量纲自洽）/ Dimension chain: cm^3/m^2 * g/cm^3 = g/m^2
    fInkGsr := fCellVolCm3M2 * fInkDensity * (fTransferPct / 100.0); // 单位面积传墨量 [g/m²]
END_IF
// 每小时过墨面积：幅宽 × 速度 × 60，m × m/min × min/h = m²/h
fAreaM2H := fWebWidthM * fSpeedMpm * 60.0;    // 过墨面积 [m²/h] / Inked area [m^2/h]
// 耗墨量：g/m² × m²/h ÷ 1000 = kg/h（m² 约去）
fInkKgH := fInkGsr * fAreaM2H / 1000.0;       // 每小时耗墨 [kg/h] / Ink per hour [kg/h]
xValid  := TRUE;                              // 链路有效 / Chain valid
FC_DL_AniloxInkTransferCalc := fInkGsr;       // 返回单位面积传墨量 [g/m²] / Return [g/m^2]
END_FUNCTION
