// FC_DL_WortBoilEvaporationCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 煮沸蒸发：总蒸发率 = 100·(前体积 − 后体积)/前体积 [%]，蒸发强度 = 总蒸发率·60/时长 [%/h]。
        煮沸中体积只减不增，后体积大于前体积直接判数据非法。
  邻件/码位: 位于煮沸工序，是麦汁浓度定标的关键质量指标；与 FC_DL_FermentAttenuationCalc 的原浓耦合；
             16#0002_9233 = 非有限、前体积或时长非正、后体积大于前体积或为负拒收。
*)
FUNCTION FC_DL_WortBoilEvaporationCalc : REAL
VAR_INPUT
    fVolBefore : REAL := 250.0;     // 煮沸前体积 [hL]，域 > 0 / Volume before boil [hL]
    fVolAfter  : REAL := 225.0;     // 煮沸后体积 [hL]，域 <= 前体积 / Volume after boil [hL]
    fBoilMin   : REAL := 60.0;      // 煮沸时长 [min]，域 > 0 / Boil duration [min]
END_VAR
VAR_OUTPUT
    fEvapRate  : REAL;              // 蒸发强度 [%/h] / Evaporation intensity [%/h]
    fTotalEvap : REAL;              // 总蒸发率 [%] / Total evaporation [%]
    bValid     : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fEvapRate := 0.0;                   // 蒸发强度缺省零 / Intensity default zero
fTotalEvap := 0.0;                  // 总蒸发率缺省零 / Total evaporation default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_WortBoilEvaporationCalc := 0.0;   // 返回值缺省零（镜像蒸发强度）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fVolBefore <> fVolBefore) OR (fVolAfter <> fVolAfter) OR (fBoilMin <> fBoilMin)
   OR (ABS(fVolBefore) >= 3.0E38) OR (ABS(fVolAfter) >= 3.0E38) OR (ABS(fBoilMin) >= 3.0E38) THEN
    uErrorId := 16#0002_9233;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（前体积与时长为正 + 后体积不得增大，R4）/ Domain gate
IF (fVolBefore <= 1.0E-6) OR (fBoilMin <= 1.0E-6) THEN
    uErrorId := 16#0002_9233;   // 前体积或时长非正 / Non-positive volume or duration
    RETURN;
END_IF
IF fVolAfter > fVolBefore THEN
    uErrorId := 16#0002_9233;   // 后体积大于前体积，体积不得增加 / Volume increased
    RETURN;
END_IF
IF fVolAfter < 0.0 THEN
    uErrorId := 16#0002_9233;   // 后体积为负 / Negative volume after boil
    RETURN;
END_IF
// 段 3：主计算（总蒸发率 → 蒸发强度）/ Main computation
fTotalEvap := 100.0 * (fVolBefore - fVolAfter) / fVolBefore;    // 总蒸发率 [%] / Total evaporation
fEvapRate := fTotalEvap * 60.0 / fBoilMin;                      // 折算每小时强度 [%/h] / Hourly intensity
// 段 4：出口闸（双输出非有限复核 + 非负复核）/ Outlet gate
IF (fEvapRate <> fEvapRate) OR (fTotalEvap <> fTotalEvap)
   OR (ABS(fEvapRate) >= 3.0E38) OR (ABS(fTotalEvap) >= 3.0E38)
   OR (fEvapRate < 0.0) OR (fTotalEvap < 0.0) THEN
    fEvapRate := 0.0;           // 复核失败回缺省 / Fallback on recheck failure
    fTotalEvap := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9233;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_WortBoilEvaporationCalc := fEvapRate;     // 返回值镜像蒸发强度 / Return mirrors intensity
END_FUNCTION
