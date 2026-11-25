(*
  DL Factory R88 | FC_DL_GearSpanMeasurementCalc
  功能：由模数/齿数/压力角算跨 k 齿公法线长度 Wk=m·cosα·[π(k-0.5)+z·invα]
  开源溯源：无（clean-room 自研，依据公开工艺公式 跨齿公法线长度式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearSpanMeasurementCalc : REAL
VAR_INPUT
    fModuleMm : REAL := 3.0; // 模数 m [mm] / module [mm]
    nTeeth : DINT := 20; // 齿数 z（整数入参，无 NaN 可能，需 z>=5） [枚] / tooth count [-]
    fPressureDeg : REAL := 20.0; // 分度圆压力角 α（度制，域闸 10~30） [°] / pressure angle in degrees [-]
END_VAR
VAR_OUTPUT
    fWkMm : REAL; // 跨 k 齿公法线长度 Wk [mm] / span measurement over k teeth [mm]
    nSpanTeeth : REAL; // 跨齿数 k（REAL 承载的近似整数） [枚] / number of spanned teeth as a real [-]
END_VAR
VAR
    fTeeth : REAL; // 齿数实数化结果 [-] / tooth count converted to REAL [-]
    fAlphaRad : REAL; // 压力角弧度值 [rad] / pressure angle in radians [rad]
    fInvAlpha : REAL; // 渐开线函数 invα=tanα-α(rad) [rad] / involute function [rad]
    fK : REAL; // 取整后的跨齿数 [枚] / truncated span count [-]
    fCosAlpha : REAL; // 压力角余弦 [-] / cosine of the pressure angle [-]
END_VAR

// 段 1｜出口预置
FC_DL_GearSpanMeasurementCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fWkMm := 0.0; // 公法线长度预置零 [mm] / span measurement preset zero [mm]
nSpanTeeth := 0.0; // 跨齿数预置零 [枚] / span teeth preset zero [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fModuleMm > -1.0E30 AND fModuleMm < 1.0E30) OR NOT (fPressureDeg > -1.0E30 AND fPressureDeg < 1.0E30) THEN
    RETURN; // 模数/压力角任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fModuleMm < 1.0E-9 THEN
    RETURN; // 模数正域闸 [mm] / positive module gate [mm]
END_IF
IF fPressureDeg <= 10.0 OR fPressureDeg >= 30.0 THEN
    RETURN; // 压力角开区间域闸 (10°,30°)，防 invα 与 k 估算同时失真 [°] / open interval gate on alpha [deg]
END_IF
IF nTeeth < 5 THEN
    RETURN; // 齿数下限闸：z<5 时跨齿数估算式不成立 [枚] / span formula invalid below 5 teeth [-]
END_IF

// 段 3｜计算
fTeeth := DINT_TO_REAL(nTeeth); // DINT→REAL 标准转换函数（R10 禁构造函数式） [-] / standard conversion (R10) [-]
fAlphaRad := fPressureDeg * 0.0174532925; // 度 × (π/180) = rad，换算常数 0.0174532925 [rad] / degrees to radians [rad]
fInvAlpha := TAN(fAlphaRad) - fAlphaRad; // tanα-α 均取弧度，结果弧度制 [rad] / involute function in radians [rad]
fCosAlpha := COS(fAlphaRad); // 无量纲 [-] / dimensionless cosine [-]
// 跨齿数估算：k = ROUND(z·α/180 + 0.5)（标准表 z=20/α=20°→3、z=30→4、z=40→5）；正数下 ROUND 等价 TRUNC(x+1)
fK := TRUNC(fTeeth * fPressureDeg / 180.0 + 1.0); // 数学等价 ROUND(z·α/180+0.5)（R88 修复：原式少 1 齿） [枚] / span count [-]
IF fK < 1.0 THEN
    fK := 1.0; // 饱和：跨齿数至少 1，防 k<=0 使公式失效 [枚] / saturate the span count at one [-]
END_IF
nSpanTeeth := fK; // 跨齿数出口（REAL 承载近似整数） [枚] / export span teeth as a real [-]
fWkMm := fModuleMm * fCosAlpha * (3.14159265 * (fK - 0.5) + fTeeth * fInvAlpha); // mm × [-] × [-] = mm，Wk [mm] / span measurement [mm]
IF fWkMm <= 0.0 THEN
    RETURN; // 结果闸：公法线长度必须为正，否则跨齿数取值失败 [mm] / span length must be positive [mm]
END_IF

// 段 4｜判定与饱和
IF NOT (fWkMm > -1.0E30 AND fWkMm < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF

// 段 5｜出口自检
IF nSpanTeeth < 1.0 OR nSpanTeeth >= fTeeth THEN
    RETURN; // 出口自检：跨齿数须在 [1,z) 内，否则出口不自洽 [枚] / span count must lie in [1,z) [-]
END_IF
FC_DL_GearSpanMeasurementCalc := fWkMm; // 返回跨 k 齿公法线长度 [mm] / return the span measurement [mm]
END_FUNCTION
