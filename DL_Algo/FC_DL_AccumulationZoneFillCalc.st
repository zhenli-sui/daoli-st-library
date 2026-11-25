(*
  DL Factory R83 | FC_DL_AccumulationZoneFillCalc
  功能：按积放区长度与料箱节距算容量件数，并算当前占位率与满料判定。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_AccumulationZoneFillCalc : REAL
VAR_INPUT
    fZoneLenM : REAL; // 积放区有效长度 [m] / Accumulation zone effective length [m]
    fToteLenM : REAL; // 料箱长度 [m] / Tote length [m]
    fGapMinM  : REAL; // 最小净间距 [m] / Minimum clear gap [m]
    iToteCnt  : INT;  // 区内实际料箱数 [件] / Actual totes in zone [-]
END_VAR
VAR_OUTPUT
    iCapCnt : INT;  // 区内理论容量件数 [件] / Theoretical capacity [pcs]
    fOccPct : REAL; // 占位率（实际/容量）[%] / Occupancy ratio [%]
    xFull   : BOOL; // 满料判定（占位率不低于 90%）/ Full flag, occupancy at or above 90 percent
    xValid  : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fPitchM : REAL; // 单箱占用节距（箱长+净距）[m] / Per-tote pitch [m]
END_VAR
// 出口预置：四出口统一预置，满料标志预置 FALSE（安全侧）
iCapCnt := 0; fOccPct := 0.0; xFull := FALSE; xValid := FALSE;
// 非有限拦截 + 量纲自检 + 计数器域闸（R20/R21）
IF NOT (fZoneLenM > -1.0E30 AND fZoneLenM < 1.0E30) OR NOT (fToteLenM > -1.0E30 AND fToteLenM < 1.0E30) OR NOT (fGapMinM > -1.0E30 AND fGapMinM < 1.0E30) OR fZoneLenM <= 0.0 OR fToteLenM <= 0.0 OR fGapMinM < 0.0 OR iToteCnt < 0 THEN
    FC_DL_AccumulationZoneFillCalc := -1.0; RETURN; // 哨兵 -1：非有限或量纲/计数越界 / Sentinel -1
END_IF
// 单箱节距：箱长 + 最小净距，同量纲相加得 m
fPitchM := fToteLenM + fGapMinM;    // 单箱节距 [m] / Per-tote pitch [m]
// 容量：区长 ÷ 节距 向下取整（禁 TRUNC+1 写法，R28）；节距分母显式零闸（R4/R21）
IF ABS(fPitchM) > 1.0E-9 THEN       // 节距分母显式零闸 / Explicit zero gate on pitch
    iCapCnt := REAL_TO_INT(fZoneLenM / fPitchM);  // 理论容量 [件] / Theoretical capacity
ELSE
    iCapCnt := 0;                   // 除零防御缺省 [件] / Divide-by-zero default
END_IF
// 占位率：实际 ÷ 容量 × 100，容量为零时按零并标记无效（R4/R21）
IF iCapCnt > 0 THEN
    fOccPct := (INT_TO_REAL(iToteCnt) / INT_TO_REAL(iCapCnt)) * 100.0; // 占位率 [%] / Occupancy [%]
    xValid  := TRUE;                // 链路有效 / Chain valid
ELSE
    fOccPct := 0.0;                 // 容量为零不可算占位率 / Zero capacity, occupancy undefined
    xValid  := FALSE;               // 标记无效 / Flag invalid
END_IF
// 满料判定：占位率不低于 90%（含实际数超过理论容量的挤压工况）
xFull := fOccPct >= 90.0;           // 满料布尔 / Full boolean
FC_DL_AccumulationZoneFillCalc := fOccPct; // 返回占位率 [%] / Return occupancy [%]
END_FUNCTION
