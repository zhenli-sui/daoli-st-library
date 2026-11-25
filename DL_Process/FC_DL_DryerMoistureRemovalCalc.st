(*
 * FC_DL_DryerMoistureRemovalCalc | C2 | DL_Process
 * 功能：烘丝机水分去除量与干物料流量（按进出口含水率，湿基）       单位：流量 [kg/h]、含水率 [%]
 * 工况边界：含水率须在 0~100 % 且出口 <100 %（入分母）；出口含水率应小于入口，否则去水量为负（回潮工况）时按 0 处理并置 xValid=TRUE（数值合法但非烘干）；仅干基不变量成立，不含热耗与风量
 * 代数值回代：G=5000 kg/h、w1=18 %、w2=12 % → Gd=5000×82/100=4100 kg/h、W=4100×6/88=279.5 kg/h（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_DryerMoistureRemovalCalc : BOOL
VAR_INPUT
    rFeedKgH     : REAL := 5000.0;   // 入口湿基流量 | inlet wet basis mass flow [kg/h]
    rMoistInPct  : REAL := 18.0;     // 入口含水率（湿基）| inlet moisture, wet basis [%]
    rMoistOutPct : REAL := 12.0;     // 出口含水率（湿基）| outlet moisture, wet basis [%]
END_VAR
VAR_OUTPUT
    rWaterRemovedKgH : REAL;         // 去水量 | water removed [kg/h]
    rDryMatterKgH    : REAL;         // 绝干物料流量 | dry matter mass flow [kg/h]
    xReverseMoist    : BOOL;         // 出口含水率高于入口（回潮工况，信息级）| outlet moisture above the inlet, informational
    xValid           : BOOL;         // 输出有效 | outputs valid
END_VAR
VAR
    xFinG  : BOOL;                   // 入口流量有限性 | inlet flow is finite
    xFinW1 : BOOL;                   // 入口水分有限性 | inlet moisture is finite
    xFinW2 : BOOL;                   // 出口水分有限性 | outlet moisture is finite
    rDenPct : REAL;                  // 分母 (100−w2) | denominator 100 minus w2 [%]
END_VAR
VAR CONSTANT
    DL_DMR_PCT_MAX : REAL := 100.0;  // 含水率上限 | upper moisture limit [%]
    DL_DMR_DEN_MIN : REAL := 1.0E-6; // 除零保护阈值 | division guard threshold [%]
END_VAR

// 段1｜非有限闸（R19）
xFinG := (rFeedKgH = rFeedKgH) AND ((rFeedKgH - rFeedKgH) = 0.0);
xFinW1 := (rMoistInPct = rMoistInPct) AND ((rMoistInPct - rMoistInPct) = 0.0);
xFinW2 := (rMoistOutPct = rMoistOutPct) AND ((rMoistOutPct - rMoistOutPct) = 0.0);
IF (NOT xFinG) OR (NOT xFinW1) OR (NOT xFinW2) THEN
    rWaterRemovedKgH := 0.0;         // 安全值：去水 0 | safe value, zero removal
    rDryMatterKgH := 0.0;
    xReverseMoist := FALSE;
    xValid := FALSE;
    FC_DL_DryerMoistureRemovalCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：流量非负、含水率范围、出口含水率不得达 100 %
IF (rFeedKgH < 0.0) OR (rMoistInPct < 0.0) OR (rMoistInPct >= DL_DMR_PCT_MAX)
   OR (rMoistOutPct < 0.0) OR (rMoistOutPct >= DL_DMR_PCT_MAX) THEN
    rWaterRemovedKgH := 0.0;
    rDryMatterKgH := 0.0;
    xReverseMoist := FALSE;
    xValid := FALSE;
    FC_DL_DryerMoistureRemovalCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：Gd = G×(100−w1)/100；W = Gd×(w1−w2)/(100−w2)
rDryMatterKgH := rFeedKgH * (DL_DMR_PCT_MAX - rMoistInPct) / DL_DMR_PCT_MAX;
rDenPct := DL_DMR_PCT_MAX - rMoistOutPct;
IF rDenPct > DL_DMR_DEN_MIN THEN
    rWaterRemovedKgH := rDryMatterKgH * (rMoistInPct - rMoistOutPct) / rDenPct;
ELSE
    rWaterRemovedKgH := 0.0;         // 理论不可达（段2已排除），防御性兜底 | unreachable defence
END_IF
IF rWaterRemovedKgH < 0.0 THEN
    xReverseMoist := TRUE;           // 回潮工况：信息级告警，出口按 0 发布 | humidification case, informational
    rWaterRemovedKgH := 0.0;
ELSE
    xReverseMoist := FALSE;
END_IF

// 段4｜出口
xValid := TRUE;
FC_DL_DryerMoistureRemovalCalc := TRUE;
END_FUNCTION
