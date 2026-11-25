(*
  DL Factory R83 | FC_DL_ChuteFullPredict
  功能：按入流与出流净流量预测滑槽从当前填充率到满料所需时间。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_ChuteFullPredict : REAL
VAR_INPUT
    fFillPct     : REAL; // 当前填充率（0~100）[%] / Current fill ratio [%]
    fInflowPpm   : REAL; // 入流件率 [件/min] / Inflow rate [pcs/min]
    fOutflowPpm  : REAL; // 出流件率 [件/min] / Outflow rate [pcs/min]
    fCapacityPcs : REAL; // 滑槽容量 [件] / Chute capacity [pcs]
END_VAR
VAR_OUTPUT
    fNetPpm      : REAL; // 净流入件率（入-出）[件/min] / Net accumulation rate [pcs/min]
    fTimeToFullS : REAL; // 到满料剩余时间（净流非正时为 0）[s] / Time to full, 0 = never [s]
    xCritical    : BOOL; // 满料风险（净流入且剩余不足 60 s）/ Full-risk flag
    xValid       : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fRoomPcs : REAL; // 剩余可容纳件数 [件] / Remaining free capacity [pcs]
END_VAR
fNetPpm := 0.0; fTimeToFullS := 0.0; xCritical := FALSE; xValid := FALSE;  // 出口预置（安全侧）
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fFillPct > -1.0E30 AND fFillPct < 1.0E30) OR NOT (fInflowPpm > -1.0E30 AND fInflowPpm < 1.0E30) OR NOT (fOutflowPpm > -1.0E30 AND fOutflowPpm < 1.0E30) OR NOT (fCapacityPcs > -1.0E30 AND fCapacityPcs < 1.0E30) OR fInflowPpm < 0.0 OR fOutflowPpm < 0.0 OR fCapacityPcs <= 0.0 THEN
    FC_DL_ChuteFullPredict := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 填充率域闸：0~100% 之外钳位
IF fFillPct < 0.0 THEN
    fFillPct := 0.0;                // 下限钳位 [%] / Clamp lower bound
ELSIF fFillPct > 100.0 THEN
    fFillPct := 100.0;              // 上限钳位 [%] / Clamp upper bound
END_IF
// 净流入：入流减出流，同量纲相减得 件/min（负值表示正在清空）
fNetPpm := fInflowPpm - fOutflowPpm;   // 净累积率 [件/min] / Net accumulation rate
// 剩余容量：容量 × (100 - 填充率) ÷ 100 = 件（% 约去，量纲自洽）
fRoomPcs := fCapacityPcs * ((100.0 - fFillPct) / 100.0); // 剩余容量 [件] / Remaining capacity [pcs]
// 净流正负双分支：净流非正时不溢出，给 0 与无风险标志
IF fNetPpm > 1.0E-9 THEN           // 净流分母显式零闸（R4/R21）/ Explicit zero gate on net rate
    // 件 ÷ (件/min) = min，×60 = s（量纲自洽）
    fTimeToFullS := fRoomPcs / fNetPpm * 60.0;  // 到满时间 [s] / Time to full [s]
    IF fTimeToFullS < 60.0 THEN
        xCritical := TRUE;          // 60 s 内将满料 / Will be full within 60 s
    END_IF
ELSE
    fTimeToFullS := 0.0;            // 净流非正，不会满料 / Net drain, never full
    xCritical    := FALSE;          // 无满料风险 / No full risk
END_IF
xValid := TRUE; FC_DL_ChuteFullPredict := fTimeToFullS;  // 返回到满时间 [s] / Return time to full
END_FUNCTION
