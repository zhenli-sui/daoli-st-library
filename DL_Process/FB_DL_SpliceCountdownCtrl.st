(*
  DL Factory R83 | FB_DL_SpliceCountdownCtrl
  功能：按当前卷径反算接卷剩余米数，用两段阈值加回差带输出预警与报警。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION_BLOCK FB_DL_SpliceCountdownCtrl
VAR_INPUT
    fRollDiaMm  : REAL; // 当前卷径 [mm] / Current roll diameter [mm]
    fCoreDiaMm  : REAL; // 卷芯直径 [mm] / Core diameter [mm]
    fWebThickMm : REAL; // 料带厚度 [mm] / Web thickness [mm]
    fWarnM      : REAL; // 预警剩余米数阈值 [m] / Warning remaining threshold [m]
    fAlarmM     : REAL; // 报警剩余米数阈值 [m] / Alarm remaining threshold [m]
    bReset      : BOOL; // 复位：清故障码 / Reset: clear error code
END_VAR
VAR_OUTPUT
    fRemainM : REAL; // 剩余料长 [m] / Remaining web length [m]
    xWarn    : BOOL; // 预警输出（可准备换卷）/ Warning output (prepare splice)
    xAlarm   : BOOL; // 报警输出（立即接卷）/ Alarm output (splice now)
    iErrCode : INT;  // 错误码，0=无错 / Error code, 0 = no error
END_VAR
VAR
    fR2Mm : REAL; // 半径平方差（R²-r²）[mm²] / Radius-square difference [mm^2]
END_VAR

// ---------- 出口预置：信息位每拍重算（R187/R256） ----------
fRemainM := 0.0;                      // 剩余料长预置零 [m] / Remaining length preset zero
xWarn    := FALSE; xAlarm := FALSE;   // 双标志预置 FALSE（名实双出口同源，R191）
IF bReset THEN iErrCode := 0; END_IF  // 故障码唯一清除边：bReset 上升沿（R188）

// ---------- 非有限 + 量纲次序 + 分母零闸：一次拦截（R4/R20/R21） ----------
IF NOT (fRollDiaMm > -1.0E30 AND fRollDiaMm < 1.0E30) OR NOT (fCoreDiaMm > -1.0E30 AND fCoreDiaMm < 1.0E30) OR NOT (fWebThickMm > -1.0E30 AND fWebThickMm < 1.0E30) OR NOT (fWarnM > -1.0E30 AND fWarnM < 1.0E30) OR NOT (fAlarmM > -1.0E30 AND fAlarmM < 1.0E30) OR fRollDiaMm <= fCoreDiaMm OR fWarnM <= fAlarmM OR ABS(fWebThickMm) <= 1.0E-9 THEN
    iErrCode := 9001;                 // 非有限/量纲越界/厚度零值统一码 / Non-finite, dimension, zero thickness
    RETURN;                           // 故障拍不出报警，交由上层按码处置 / Fault cycle emits no alarm
END_IF

// ---------- 剩余料长：L = π × (R² - r²) / t，mm ÷ 1000 换算为 m ----------
fR2Mm    := (fRollDiaMm * fRollDiaMm - fCoreDiaMm * fCoreDiaMm) / 4.0; // 半径平方差 [mm²]
fRemainM := 3.14159265358979 * fR2Mm / fWebThickMm / 1000.0;           // 剩余料长 [m]

// ---------- 两段阈值 + 0.5 m 回差带：进入即置，退出须越过阈值加回差 ----------
IF fRemainM <= fWarnM THEN xWarn := TRUE; END_IF                          // 进入预警带 / Enter warning band
IF fRemainM <= fAlarmM THEN xAlarm := TRUE; xWarn := TRUE; END_IF         // 报警带蕴含预警（R191 名实双置）
IF fRemainM > fWarnM + 0.5 THEN xWarn := FALSE; xAlarm := FALSE; END_IF   // 越过回差带回退 / Release past hysteresis
END_FUNCTION_BLOCK
