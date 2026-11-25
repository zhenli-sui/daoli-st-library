(*
  DL Factory R88 | FC_DL_HoneCrosshatchAngleCalc
  功能：由往复速度与旋转线速度算珩磨网纹夹角 θ=2·atan(vr/vt)，按 20°~60° 判带宽
  开源溯源：无（clean-room 自研，依据公开工艺公式 珩磨网纹角式 θ=2·atan(vr/vt)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_HoneCrosshatchAngleCalc : REAL
VAR_INPUT
    fRecipSpeedMPerMin : REAL := 15.0; // 珩磨头往复速度 vr [m/min] / reciprocating speed [m/min]
    fRotSpeedMPerMin : REAL := 45.0; // 工件旋转线速度 vt（按孔径处分度线速度折算） [m/min] / rotational surface speed [m/min]
    fBandMinDeg : REAL := 20.0; // 网纹角允许下限（工艺带宽） [°] / lower crosshatch band [deg]
    fBandMaxDeg : REAL := 60.0; // 网纹角允许上限（工艺带宽） [°] / upper crosshatch band [deg]
END_VAR
VAR_OUTPUT
    fAngleDeg : REAL; // 网纹夹角 θ [°] / crosshatch included angle [deg]
    xInBand : BOOL; // TRUE=网纹角落在允许带宽内 [-] / TRUE when the angle is inside the band [-]
END_VAR
VAR
    fRatio : REAL; // 速度比 vr/vt（正切值） [-] / speed ratio, the tangent value [-]
    fAngleRad : REAL; // 半网纹角 atan(vr/vt) [rad] / half crosshatch angle [rad]
    fDenom : REAL; // 分母 vt（除零判据） [m/min] / denominator before the division [m/min]
END_VAR

// 段 1｜出口预置
FC_DL_HoneCrosshatchAngleCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fAngleDeg := 0.0; // 网纹角预置零 [°] / angle preset zero [deg]
xInBand := FALSE; // 带宽位预置 FALSE [-] / band flag preset false [-]
fRatio := 0.0; // 速度比预置零 [-] / ratio preset zero [-]
fAngleRad := 0.0; // 半角预置零 [rad] / half angle preset zero [rad]
fDenom := 0.0; // 分母预置零 [m/min] / denominator preset zero [m/min]

// 段 2｜非有限拦截 + 域闸
IF NOT (fRecipSpeedMPerMin > -1.0E30 AND fRecipSpeedMPerMin < 1.0E30) OR NOT (fRotSpeedMPerMin > -1.0E30 AND fRotSpeedMPerMin < 1.0E30) THEN
    RETURN; // 两速度任一非有限即拒算 [-] / any non finite speed rejected [-]
END_IF
IF NOT (fBandMinDeg > -1.0E30 AND fBandMinDeg < 1.0E30) OR NOT (fBandMaxDeg > -1.0E30 AND fBandMaxDeg < 1.0E30) THEN
    RETURN; // 带宽上下限任一非有限则判据静默失效，故先拦 [-] / band limits must be finite or the check fades [-]
END_IF
IF fRecipSpeedMPerMin < 0.0 OR fRotSpeedMPerMin <= 0.0 THEN
    RETURN; // 往复速度非负闸 + 旋转速度正域闸（分母不得为零） [m/min] / non negative vr and positive vt [m/min]
END_IF
IF fBandMinDeg <= 0.0 OR fBandMaxDeg <= fBandMinDeg THEN
    RETURN; // 带宽自洽闸：下限须为正、上限须严格大于下限 [°] / band consistency gate [deg]
END_IF

// 段 3｜计算
fDenom := fRotSpeedMPerMin; // 取旋转线速度作除数 [m/min] / take the rotational speed as divisor [m/min]
IF fDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：vt 必须大于 1E-9 才可作除数 [m/min] / denominator gate before the division [m/min]
END_IF
fRatio := fRecipSpeedMPerMin / fDenom; // (m/min) ÷ (m/min) = 无量纲 [-] / dimensionless ratio [-]
fAngleRad := ATAN(fRatio); // 无量纲 → 弧度，半网纹角 [rad] / half angle in radians [rad]
fAngleDeg := 2.0 * fAngleRad * 57.2957795; // 2 × rad × (180/π) = 度，换算常数 57.2957795 [°] / radians to degrees [deg]

// 段 4｜判定与饱和
IF NOT (fAngleDeg > -1.0E30 AND fAngleDeg < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xInBand := (fAngleDeg >= fBandMinDeg) AND (fAngleDeg <= fBandMaxDeg); // 双侧闭区间直比 [°] / closed two sided band compare [deg]

// 段 5｜出口自检
IF fAngleDeg <= 0.0 THEN
    RETURN; // 出口自检：网纹角须为正（零值说明往复速度为零） [°] / angle must be positive [deg]
END_IF
FC_DL_HoneCrosshatchAngleCalc := fAngleDeg; // 返回网纹夹角 θ [°] / return the crosshatch angle [deg]
END_FUNCTION
