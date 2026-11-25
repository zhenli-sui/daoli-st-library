(*
  DL Factory R88 | FC_DL_GrindWheelPeripheralSpeedCalc
  功能：由砂轮直径与转速算外周线速度 v=π·D·n/60000（mm,rpm→m/s），超 35 m/s 报警
  开源溯源：无（clean-room 自研，依据公开工艺公式 砂轮线速度式 v=π·D·n，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GrindWheelPeripheralSpeedCalc : REAL
VAR_INPUT
    fDiaMm : REAL := 400.0; // 砂轮外径 D [mm] / wheel outer diameter [mm]
    fRpm : REAL := 1500.0; // 主轴转速 n [r/min] / spindle speed [rpm]
    fLimitMPerS : REAL := 35.0; // 线速度报警阈值（常规树脂结合剂 35 m/s） [m/s] / overspeed alarm limit [m/s]
END_VAR
VAR_OUTPUT
    fSpeedMPerS : REAL; // 砂轮外周线速度 v [m/s] / peripheral speed [m/s]
    xOverLimit : BOOL; // TRUE=线速度超过阈值，需报警 [-] / TRUE when above the alarm limit [-]
END_VAR
VAR
    fCircMMm : REAL; // 单转行程 π·D [mm/rev] / travel per revolution [mm/rev]
    fMMPerMin : REAL; // 每分钟行程 π·D·n [mm/min] / travel per minute [mm/min]
END_VAR

// 段 1｜出口预置
FC_DL_GrindWheelPeripheralSpeedCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fSpeedMPerS := 0.0; // 线速度预置零 [m/s] / speed preset zero [m/s]
xOverLimit := FALSE; // 超限位预置 FALSE（未判定前不报超限） [-] / over-speed flag preset false [-]
fCircMMm := 0.0; // 单转行程预置零 [mm/rev] / circumference preset zero [mm/rev]
fMMPerMin := 0.0; // 每分钟行程预置零 [mm/min] / travel per minute preset zero [mm/min]

// 段 2｜非有限拦截 + 域闸
IF NOT (fDiaMm > -1.0E30 AND fDiaMm < 1.0E30) OR NOT (fRpm > -1.0E30 AND fRpm < 1.0E30) THEN
    RETURN; // 直径/转速任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fLimitMPerS > -1.0E30 AND fLimitMPerS < 1.0E30) THEN
    RETURN; // 阈值非有限则报警判据失效，故先拦 [m/s] / the alarm limit must be finite [m/s]
END_IF
IF fDiaMm < 1.0E-9 OR fRpm < 0.0 THEN
    RETURN; // 直径正域闸 + 转速非负闸 [mm, r/min] / positive diameter and non negative speed
END_IF
IF fLimitMPerS <= 0.0 THEN
    RETURN; // 阈值正域闸：非正阈值会使报警恒真或恒假 [m/s] / positive limit gate [m/s]
END_IF

// 段 3｜计算
fCircMMm := 3.14159265 * fDiaMm; // 无量纲 × mm = mm/rev，每转行程 π·D [mm/rev] / [mm] per revolution
fMMPerMin := fCircMMm * fRpm; // (mm/rev) × (r/min) = mm/min，每分钟行程 [mm/min] / [mm/min]
fSpeedMPerS := fMMPerMin / 60000.0; // (mm/min) ÷ 60000 = m/s；60000=1000 mm/m × 60 s/min 恒正 [m/s] / [m/s]

// 段 4｜判定与饱和
IF NOT (fSpeedMPerS > -1.0E30 AND fSpeedMPerS < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次（防溢出成 Inf） [m/s] / re-check the result for finiteness [m/s]
END_IF
xOverLimit := fSpeedMPerS > fLimitMPerS; // 严格大于阈值为超限，等于阈值仍判合格 [m/s] / strict compare against the limit [m/s]

// 段 5｜出口自检
IF fSpeedMPerS < 0.0 THEN
    RETURN; // 出口自检：线速度不得为负（负值说明输入符号错） [m/s] / speed must not be negative [m/s]
END_IF
FC_DL_GrindWheelPeripheralSpeedCalc := fSpeedMPerS; // 返回砂轮线速度 [m/s] / return the peripheral speed [m/s]
END_FUNCTION
