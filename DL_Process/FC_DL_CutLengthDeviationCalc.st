(*
  DL Factory R83 | FC_DL_CutLengthDeviationCalc
  功能：比较定长裁切设定值与实测值，输出偏差、反向补偿量并做死区判稳。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_CutLengthDeviationCalc : REAL
VAR_INPUT
    fSetLenMm   : REAL; // 定长设定值 [mm] / Cut length setpoint [mm]
    fMeasLenMm  : REAL; // 实测裁切长度 [mm] / Measured cut length [mm]
    fDeadbandMm : REAL; // 死区（不补偿带宽）[mm] / Deadband, no-compensation band [mm]
    fCompGain   : REAL; // 补偿增益（0~200）[%] / Compensation gain [%]
END_VAR
VAR_OUTPUT
    fDevMm  : REAL; // 长度偏差（实测-设定，正=偏长）[mm] / Deviation, + = too long [mm]
    fCompMm : REAL; // 补偿量（叠加设定值，符号与偏差相反）[mm] / Compensation to add [mm]
    xInBand : BOOL; // 在死区内（TRUE=无需补偿）/ Inside deadband, TRUE = no trim
END_VAR
VAR
    fAbsDev : REAL; // 偏差绝对值 [mm] / Absolute deviation [mm]
    fGainK  : REAL; // 增益归一化系数 [-]/ Normalised gain factor
END_VAR
// 出口预置：预置在带内（无动作安全侧），非有限拍不产生补偿
fDevMm := 0.0; fCompMm := 0.0; xInBand := TRUE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fSetLenMm > -1.0E30 AND fSetLenMm < 1.0E30) OR NOT (fMeasLenMm > -1.0E30 AND fMeasLenMm < 1.0E30) OR NOT (fDeadbandMm > -1.0E30 AND fDeadbandMm < 1.0E30) OR NOT (fCompGain > -1.0E30 AND fCompGain < 1.0E30) OR fSetLenMm <= 0.0 OR fDeadbandMm < 0.0 THEN
    FC_DL_CutLengthDeviationCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 增益域闸：0~200% 之外按边界钳位后继续
IF fCompGain < 0.0 THEN
    fGainK := 0.0;                  // 负增益等价不补偿 [-] / Negative gain equals no compensation
ELSIF fCompGain > 200.0 THEN
    fGainK := 2.0;                  // 增益上限 2.0 倍 [-] / Gain clamped to 2.0
ELSE
    fGainK := fCompGain / 100.0;    // 归一化增益 [-] / Normalised gain
END_IF
// 偏差：实测减设定，同量纲（mm）直接相减
fDevMm  := fMeasLenMm - fSetLenMm;   // 长度偏差 [mm] / Length deviation [mm]
fAbsDev := ABS(fDevMm);              // 偏差绝对值 [mm] / Absolute deviation [mm]
// 死区判定与补偿：带内不补偿，带外按增益反向补偿（浮点比较只用绝对差与不等）
IF fAbsDev <= fDeadbandMm THEN
    xInBand := TRUE;                 // 在死区内不动作 / In deadband, no action
    fCompMm := 0.0;                  // 补偿量为零 [mm] / Compensation zero
ELSE
    xInBand := FALSE;                // 越出死区 / Outside deadband
    fCompMm := -fDevMm * fGainK;     // 反向补偿量 [mm] / Reverse compensation [mm]
END_IF
FC_DL_CutLengthDeviationCalc := fDevMm;   // 返回长度偏差 [mm] / Return deviation [mm]
END_FUNCTION
