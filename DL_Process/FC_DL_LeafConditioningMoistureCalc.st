(*
 * FC_DL_LeafConditioningMoistureCalc | C2 | DL_Process
 * 功能：松散回潮加水量的计算（干物料守恒，含蒸汽凝结水计入总加水量）       单位：流量 [kg/h]、含水率 [%]
 * 工况边界：入口含水率与出口含水率须在 0~100 %，出口不得达 100 %（入分母）；出口含水率低于入口时判为干燥工况，加水量按 0 发布并置信息位；蒸汽量按全部凝结计入总加水（不区分排汽损失）
 * 代数值回代：G=6000 kg/h、w1=12 %、w2=18 %、蒸汽 0 → Gd=6000×88/100=5280 kg/h；Wadd=5280×6/82=386.3 kg/h；总加水=386.3 kg/h（量纲自洽）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_LeafConditioningMoistureCalc : BOOL
VAR_INPUT
    rFeedKgH     : REAL := 6000.0;   // 入口叶片流量（湿基）| inlet leaf mass flow, wet basis [kg/h]
    rMoistInPct  : REAL := 12.0;     // 入口含水率 | inlet moisture [%]
    rMoistOutPct : REAL := 18.0;     // 出口含水率目标 | outlet moisture target [%]
    rSteamKgH    : REAL;             // 直接蒸汽流量（全部凝结计入）| direct steam flow, fully condensed [kg/h]
END_VAR
VAR_OUTPUT
    rWaterAddKgH   : REAL;           // 达到出口水分所需加水量 | water needed to reach the outlet moisture [kg/h]
    rTotalWaterKgH : REAL;           // 总加水量（含蒸汽凝结水）| total water including the condensed steam [kg/h]
    rDryMatterKgH  : REAL;           // 绝干物料流量 | dry matter mass flow [kg/h]
    xReverseMoist  : BOOL;           // 出口水分低于入口（干燥工况，信息级）| outlet below inlet, informational
    xValid         : BOOL;           // 输出有效 | outputs valid
END_VAR
VAR
    xFinG    : BOOL;                 // 入口流量有限性 | inlet flow is finite
    xFinW1   : BOOL;                 // 入口水分有限性 | inlet moisture is finite
    xFinW2   : BOOL;                 // 出口水分有限性 | outlet moisture is finite
    xFinStm  : BOOL;                 // 蒸汽流量有限性 | steam flow is finite
    rDenPct  : REAL;                 // 分母 (100−w2) | denominator 100 minus w2 [%]
END_VAR
VAR CONSTANT
    DL_LCM_PCT_MAX : REAL := 100.0;  // 含水率上限 | upper moisture limit [%]
    DL_LCM_DEN_MIN : REAL := 1.0E-6; // 除零保护阈值 | division guard threshold [%]
END_VAR

// 段1｜非有限闸（R19）
xFinG := (rFeedKgH = rFeedKgH) AND ((rFeedKgH - rFeedKgH) = 0.0);
xFinW1 := (rMoistInPct = rMoistInPct) AND ((rMoistInPct - rMoistInPct) = 0.0);
xFinW2 := (rMoistOutPct = rMoistOutPct) AND ((rMoistOutPct - rMoistOutPct) = 0.0);
xFinStm := (rSteamKgH = rSteamKgH) AND ((rSteamKgH - rSteamKgH) = 0.0);
IF (NOT xFinG) OR (NOT xFinW1) OR (NOT xFinW2) OR (NOT xFinStm) THEN
    rWaterAddKgH := 0.0;             // 安全值：加水 0 | safe value, zero water
    rTotalWaterKgH := 0.0;
    rDryMatterKgH := 0.0;
    xReverseMoist := FALSE;
    xValid := FALSE;
    FC_DL_LeafConditioningMoistureCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：流量非负、含水率范围、出口不得达 100 %
IF (rFeedKgH < 0.0) OR (rSteamKgH < 0.0)
   OR (rMoistInPct < 0.0) OR (rMoistInPct >= DL_LCM_PCT_MAX)
   OR (rMoistOutPct < 0.0) OR (rMoistOutPct >= DL_LCM_PCT_MAX) THEN
    rWaterAddKgH := 0.0;
    rTotalWaterKgH := 0.0;
    rDryMatterKgH := 0.0;
    xReverseMoist := FALSE;
    xValid := FALSE;
    FC_DL_LeafConditioningMoistureCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：Gd = G×(100−w1)/100；Wadd = Gd×(w2−w1)/(100−w2)
rDryMatterKgH := rFeedKgH * (DL_LCM_PCT_MAX - rMoistInPct) / DL_LCM_PCT_MAX;
rDenPct := DL_LCM_PCT_MAX - rMoistOutPct;
IF rDenPct > DL_LCM_DEN_MIN THEN
    rWaterAddKgH := rDryMatterKgH * (rMoistOutPct - rMoistInPct) / rDenPct;
ELSE
    rWaterAddKgH := 0.0;             // 理论不可达（段2已排除），防御性兜底 | unreachable defence
END_IF
IF rWaterAddKgH < 0.0 THEN
    xReverseMoist := TRUE;           // 干燥工况：出口按 0 | drying case, zero published
    rWaterAddKgH := 0.0;
ELSE
    xReverseMoist := FALSE;
END_IF

// 段4｜总加水量（蒸汽凝结水按 100 % 计入）
rTotalWaterKgH := rWaterAddKgH + rSteamKgH;
xValid := TRUE;
FC_DL_LeafConditioningMoistureCalc := TRUE;
END_FUNCTION
