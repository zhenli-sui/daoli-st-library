(*
  DL Factory R83 | FC_DL_HexChromeTriRatioCalc
  功能：算六价铬与三价铬浓度比，判定镀液老化并给出需氧化的三价铬过量值。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_HexChromeTriRatioCalc : REAL
VAR_INPUT
    fCr6Gpl   : REAL; // 六价铬浓度 [g/L] / Hexavalent chromium concentration [g/L]
    fCr3Gpl   : REAL; // 三价铬浓度 [g/L] / Trivalent chromium concentration [g/L]
    fRatioMin : REAL; // 允许最低六/三比值 [-]/ Minimum allowed hex-to-tri ratio [-]
    fTempC    : REAL; // 槽液温度 [°C] / Bath temperature [degC]
END_VAR
VAR_OUTPUT
    fRatio     : REAL; // 六价/三价比值 [-]/ Hex-to-tri concentration ratio [-]
    fCr3Excess : REAL; // 三价铬过量（需氧化去除量，负值按零）[g/L] / Excess trivalent [g/L]
    xAged      : BOOL; // 老化判定（TRUE=三价累积超限）/ Ageing flag, TRUE = build-up
    xValid     : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fCr3Limit : REAL; // 三价铬允许上限 [g/L] / Allowed trivalent ceiling [g/L]
END_VAR
// 出口预置：四出口统一预置，老化标志预置 FALSE（安全侧）
fRatio := 0.0; fCr3Excess := 0.0; xAged := FALSE; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fCr6Gpl > -1.0E30 AND fCr6Gpl < 1.0E30) OR NOT (fCr3Gpl > -1.0E30 AND fCr3Gpl < 1.0E30) OR NOT (fRatioMin > -1.0E30 AND fRatioMin < 1.0E30) OR NOT (fTempC > -1.0E30 AND fTempC < 1.0E30) OR fCr6Gpl <= 0.0 OR fCr3Gpl <= 0.0 OR fRatioMin <= 0.0 THEN
    FC_DL_HexChromeTriRatioCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 比值：六价 ÷ 三价，两者同量纲 g/L 故比值为无量纲；三价分母显式零闸（R4/R21）
IF ABS(fCr3Gpl) > 1.0E-9 THEN       // 三价分母显式零闸 / Explicit zero gate on trivalent
    fRatio := fCr6Gpl / fCr3Gpl;    // 六/三比值 [-]/ Hex-to-tri ratio
ELSE
    fRatio := 0.0;                  // 除零防御缺省 / Divide-by-zero default
END_IF
// 三价上限：由比值下限反算 Cr3 <= Cr6 ÷ 比值下限（g/L ÷ 无量纲 = g/L）
IF ABS(fRatioMin) > 1.0E-9 THEN     // 比值下限分母显式零闸 / Zero gate on ratio lower bound
    fCr3Limit := fCr6Gpl / fRatioMin;   // 三价允许上限 [g/L] / Allowed trivalent ceiling
ELSE
    fCr3Limit := fCr3Gpl;           // 下限非正时按当前值兜底，不产生过量 / Fallback, no excess
END_IF
// 过量：三价实测减允许上限，负值按零（单向语义，不做浓缩回算）
IF fCr3Gpl > fCr3Limit THEN
    fCr3Excess := fCr3Gpl - fCr3Limit;  // 超量部分 [g/L] / Excessive part [g/L]
    xAged      := TRUE;             // 三价累积超限判老化 / Build-up flags ageing
ELSE
    fCr3Excess := 0.0;              // 未超限，过量按零 / Not exceeded, zero
    xAged      := FALSE;            // 比值正常 / Ratio within limit
END_IF
xValid := TRUE; FC_DL_HexChromeTriRatioCalc := fRatio;  // 返回六/三比值 [-] / Return ratio
END_FUNCTION
