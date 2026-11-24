(*
  DL Factory R83 | FB_DL_DyeBathReplenishCtrl
  功能：按液位偏差比例开补水阀，并按浓度差联动助剂加注泵流量。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION_BLOCK FB_DL_DyeBathReplenishCtrl
VAR_INPUT
    fLevelPct    : REAL; // 实测液位 [%] / Measured bath level [%]
    fLevelSpPct  : REAL; // 液位设定 [%] / Level setpoint [%]
    fChemConcPct : REAL; // 实测助剂浓度 [%] / Measured chemical concentration [%]
    fChemSpPct   : REAL; // 助剂浓度设定 [%] / Chemical concentration setpoint [%]
    fValveLpm    : REAL; // 补水阀额定流量 [L/min] / Rated make-up valve flow [L/min]
    bEnable      : BOOL; // 联动使能（FALSE 时全阀关闭）/ Cascade enable, FALSE = valves closed
END_VAR
VAR_OUTPUT
    fWaterLpm  : REAL; // 补水指令流量 [L/min] / Make-up water command [L/min]
    fChemLpm   : REAL; // 助剂加注指令流量 [L/min] / Chemical dosing command [L/min]
    xValveOpen : BOOL; // 补水阀开许可 / Make-up valve open permit
    iErrCode   : INT;  // 错误码，0=无错 / Error code, 0 = no error
END_VAR
VAR
    fDevPct  : REAL; // 液位偏差（设定-实测，正=缺水）[%] / Level deviation, + = low level [%]
    fConcDev : REAL; // 浓度偏差（设定-实测，正=偏稀）[%] / Concentration deviation [%]
END_VAR
fWaterLpm := 0.0; fChemLpm := 0.0; xValveOpen := FALSE; iErrCode := 0;  // 出口预置（故障安全侧）
// 非有限拦截 + 量纲自检（R21）
IF NOT (fLevelPct > -1.0E30 AND fLevelPct < 1.0E30) OR NOT (fLevelSpPct > -1.0E30 AND fLevelSpPct < 1.0E30) OR NOT (fChemConcPct > -1.0E30 AND fChemConcPct < 1.0E30) OR NOT (fChemSpPct > -1.0E30 AND fChemSpPct < 1.0E30) OR NOT (fValveLpm > -1.0E30 AND fValveLpm < 1.0E30) OR fValveLpm < 0.0 OR fLevelSpPct <= 0.0 OR fChemSpPct < 0.0 THEN
    iErrCode := 9101; RETURN;       // 非有限或量纲越界，故障拍不开阀 / Fault cycle keeps valves closed
END_IF
// 串级闸：使能才计算，门控挂布尔状态量而非单拍位
IF bEnable THEN
    fDevPct  := fLevelSpPct - fLevelPct;    // 液位偏差，正=缺水 [%] / Level deviation [%]
    fConcDev := fChemSpPct - fChemConcPct;  // 浓度偏差，正=偏稀 [%] / Concentration deviation [%]
    // 补水：偏差超 1% 死区才开阀，10% 偏差对应满流量（比例带 10%，无量纲放大）
    IF fDevPct > 1.0 THEN
        fWaterLpm := fValveLpm * (fDevPct / 10.0);   // 比例补水流量 [L/min] / Proportional flow
        IF fWaterLpm > fValveLpm THEN
            fWaterLpm := fValveLpm;                 // 上限钳位到额定流量 [L/min] / Clamp to rated
        END_IF
        xValveOpen := TRUE;                         // 阀开许可置位 / Valve permit set
    END_IF
    // 助剂：随补水量按浓度差加注；偏差为负（偏浓）时加注为零（不抽液）
    IF fDevPct > 1.0 AND fConcDev > 0.0 THEN
        fChemLpm := fWaterLpm * (fConcDev / 100.0); // 助剂加注量 [L/min] / Chemical dosing flow
    END_IF
ELSE
    fWaterLpm := 0.0; fChemLpm := 0.0; xValveOpen := FALSE;  // 停用相：全阀关闭 / Disabled, valves closed
END_IF
END_FUNCTION_BLOCK
