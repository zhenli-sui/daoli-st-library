(*
  DL Factory R88 | FC_DL_GearBaseCircleCalc
  功能：由模数/齿数/压力角算基圆直径 db=m·z·cosα，压力角由角度制按 π/180 换算弧度
  开源溯源：无（clean-room 自研，依据公开工艺公式 基圆直径式 db=m·z·cosα，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearBaseCircleCalc : REAL
VAR_INPUT
    fModuleMm : REAL := 3.0; // 模数 m [mm] / module [mm]
    nTeeth : DINT := 20; // 齿数 z（整数入参，无 NaN 可能） [枚] / tooth count, integer input [-]
    fPressureDeg : REAL := 20.0; // 分度圆压力角 α（度制，域闸 10~30） [°] / pressure angle in degrees [-]
END_VAR
VAR_OUTPUT
    fDbMm : REAL; // 基圆直径 db [mm] / base circle diameter [mm]
    fPitchDiaMm : REAL; // 分度圆直径 d=m·z [mm] / pitch circle diameter [mm]
END_VAR
VAR
    fTeeth : REAL; // 齿数实数化结果 [-] / tooth count converted to REAL [-]
    fAlphaRad : REAL; // 压力角弧度值 [rad] / pressure angle in radians [rad]
    fCosAlpha : REAL; // 压力角余弦（缓存，避免重算） [-] / cosine of the pressure angle [-]
END_VAR

// 段 1｜出口预置
FC_DL_GearBaseCircleCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fDbMm := 0.0; // 基圆直径预置零 [mm] / base diameter preset zero [mm]
fPitchDiaMm := 0.0; // 分度圆直径预置零 [mm] / pitch diameter preset zero [mm]
fTeeth := 0.0; // 齿数实数预置零 [-] / real teeth preset zero [-]
fAlphaRad := 0.0; // 弧度预置零 [rad] / radians preset zero [rad]
fCosAlpha := 0.0; // 余弦预置零 [-] / cosine preset zero [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fModuleMm > -1.0E30 AND fModuleMm < 1.0E30) OR NOT (fPressureDeg > -1.0E30 AND fPressureDeg < 1.0E30) THEN
    RETURN; // 模数/压力角任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fModuleMm < 1.0E-9 THEN
    RETURN; // 模数正域闸 [mm] / positive module gate [mm]
END_IF
IF fPressureDeg <= 10.0 OR fPressureDeg >= 30.0 THEN
    RETURN; // 压力角开区间域闸 (10°,30°)：趋零则基圆退化为分度圆 [°] / open interval gate on alpha [deg]
END_IF
IF nTeeth < 1 THEN
    RETURN; // 齿数下限闸（整数域，仅做范围拦截） [枚] / tooth count lower gate [-]
END_IF

// 段 3｜计算
fTeeth := DINT_TO_REAL(nTeeth); // DINT→REAL 标准转换函数（R10） [-] / standard conversion function (R10) [-]
fAlphaRad := fPressureDeg * 0.0174532925; // 度 × (π/180) = rad，换算常数 0.0174532925 [rad] / degrees to radians [rad]
fCosAlpha := COS(fAlphaRad); // 无量纲 [-] / dimensionless cosine [-]
fPitchDiaMm := fModuleMm * fTeeth; // mm × 无量纲 = mm，d=m·z / [mm] × [-] = [mm]
fDbMm := fPitchDiaMm * fCosAlpha; // mm × 无量纲 = mm，db=d·cosα / [mm] × [-] = [mm]

// 段 4｜判定与饱和
IF fDbMm <= 0.0 THEN
    RETURN; // 结果闸：基圆直径必须为正（cosα 在 (10°,30°) 内恒正） [mm] / base diameter must be positive [mm]
END_IF
IF fDbMm >= fPitchDiaMm THEN
    RETURN; // 结构自洽闸：基圆必须小于分度圆（cosα<1） [mm] / structural check db < d [mm]
END_IF

// 段 5｜出口自检
IF NOT (fDbMm > -1.0E30 AND fDbMm < 1.0E30) THEN
    RETURN; // 出口自检：结果非有限即退回哨兵 [mm] / exit self-check on finiteness [mm]
END_IF
FC_DL_GearBaseCircleCalc := fDbMm; // 返回基圆直径 [mm] / return the base circle diameter [mm]
END_FUNCTION
