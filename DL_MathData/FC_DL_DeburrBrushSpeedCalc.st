(*
  DL Factory R88 | FC_DL_DeburrBrushSpeedCalc
  功能：算去毛刺刷丝线速度 v=π·D·n/60000 + vf·sinθ（进给修正项），超 25 m/s 报警
  开源溯源：无（clean-room 自研，依据公开工艺公式 刷轮线速度与进给投影叠加式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_DeburrBrushSpeedCalc : REAL
VAR_INPUT
    fDiaMm : REAL := 150.0; // 刷轮外径 D [mm] / brush wheel diameter [mm]
    fRpm : REAL := 2000.0; // 刷轮转速 n [r/min] / brush speed [rpm]
    fFeedMmPerS : REAL := 50.0; // 工件进给速度 vf [mm/s] / workpiece feed speed [mm/s]
    fContactDeg : REAL := 30.0; // 接触角 θ（刷丝与进给方向夹角，度制 0~90） [°] / contact angle in degrees [-]
    fLimitMPerS : REAL := 25.0; // 线速度报警阈值（刷丝飞散风险） [m/s] / overspeed alarm limit [m/s]
END_VAR
VAR_OUTPUT
    fSpeedMPerS : REAL; // 合成刷丝线速度 v [m/s] / resulting brush speed [m/s]
    xOverLimit : BOOL; // TRUE=线速度超过阈值，需报警 [-] / TRUE when above the alarm limit [-]
END_VAR
VAR
    fRotMPerS : REAL; // 旋转分量 π·D·n/60000 [m/s] / rotational component [m/s]
    fFeedMPerS : REAL; // 进给投影分量 vf·sinθ [m/s] / feed projection component [m/s]
    fAngleRad : REAL; // 接触角弧度值 [rad] / contact angle in radians [rad]
END_VAR

// 段 1｜出口预置
FC_DL_DeburrBrushSpeedCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fSpeedMPerS := 0.0; // 合成线速度预置零 [m/s] / speed preset zero [m/s]
xOverLimit := FALSE; // 超限位预置 FALSE（未判定前不报超限） [-] / over-speed flag preset false [-]
fRotMPerS := 0.0; // 旋转分量预置零 [m/s] / rotational component preset zero [m/s]
fFeedMPerS := 0.0; // 进给分量预置零 [m/s] / feed component preset zero [m/s]
fAngleRad := 0.0; // 弧度预置零 [rad] / radians preset zero [rad]

// 段 2｜非有限拦截 + 域闸
IF NOT (fDiaMm > -1.0E30 AND fDiaMm < 1.0E30) OR NOT (fRpm > -1.0E30 AND fRpm < 1.0E30) THEN
    RETURN; // 直径/转速任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fFeedMmPerS > -1.0E30 AND fFeedMmPerS < 1.0E30) OR NOT (fContactDeg > -1.0E30 AND fContactDeg < 1.0E30) THEN
    RETURN; // 进给/接触角任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fLimitMPerS > -1.0E30 AND fLimitMPerS < 1.0E30) THEN
    RETURN; // 阈值非有限则报警判据失效，故先拦 [m/s] / the alarm limit must be finite [m/s]
END_IF
IF fDiaMm < 1.0E-9 OR fRpm < 0.0 OR fFeedMmPerS < 0.0 THEN
    RETURN; // 直径正域闸 + 转速/进给非负闸 [mm, r/min, mm/s] / positive diameter, non negative speeds
END_IF
IF fContactDeg < 0.0 OR fContactDeg > 90.0 THEN
    RETURN; // 接触角闭区间域闸 [0,90]，超界则 sinθ 投影无物理意义 [°] / contact angle closed interval gate [deg]
END_IF
IF fLimitMPerS <= 0.0 THEN
    RETURN; // 阈值正域闸：非正阈值会使报警恒真 [m/s] / positive limit gate [m/s]
END_IF

// 段 3｜计算
fAngleRad := fContactDeg * 0.0174532925; // 度 × (π/180) = rad，换算常数 0.0174532925 [rad] / degrees to radians [rad]
fRotMPerS := 3.14159265 * fDiaMm * fRpm / 60000.0; // mm × r/min ÷ 60000 = m/s；60000 恒正 [m/s] / rotational component [m/s]
fFeedMPerS := fFeedMmPerS * 0.001 * SIN(fAngleRad); // (mm/s) × 0.001 m/mm × [-] = m/s，进给投影项 [m/s] / [m/s]
fSpeedMPerS := fRotMPerS + fFeedMPerS; // m/s + m/s = m/s，两项合成 [m/s] / [m/s] + [m/s] = [m/s]

// 段 4｜判定与饱和
IF NOT (fSpeedMPerS > -1.0E30 AND fSpeedMPerS < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xOverLimit := fSpeedMPerS > fLimitMPerS; // 严格大于阈值为超限，等于阈值仍判合格 [m/s] / strict compare [m/s]

// 段 5｜出口自检
IF fSpeedMPerS < fRotMPerS THEN
    RETURN; // 出口自检：合成值不得小于旋转分量（说明叠加链被破坏） [m/s] / synthetic value must not drop below [m/s]
END_IF
FC_DL_DeburrBrushSpeedCalc := fSpeedMPerS; // 返回合成刷丝线速度 [m/s] / return the brush speed [m/s]
END_FUNCTION
