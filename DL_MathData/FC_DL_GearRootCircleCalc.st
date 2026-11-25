(*
  DL Factory R88 | FC_DL_GearRootCircleCalc
  功能：由模数/齿数算齿根圆直径 df=m(z-2.5)（等价 d-2hf，hf=1.25m），齿数域闸 z>=8
  开源溯源：无（clean-room 自研，依据公开工艺公式 齿根圆直径式 df=m(z-2.5)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearRootCircleCalc : REAL
VAR_INPUT
    fModuleMm : REAL := 3.0; // 模数 m [mm] / module [mm]
    nTeeth : DINT := 20; // 齿数 z，域闸 z>=8 防齿根自交 [枚] / tooth count, gated at 8 or more [-]
    fDedFactor : REAL := 1.25; // 齿根高系数 hf*=1.25，使 2hf*=2.5 与公式一致 [-] / dedendum coefficient [-]
END_VAR
VAR_OUTPUT
    fDfMm : REAL; // 齿根圆直径 df [mm] / root circle diameter [mm]
    fDedendumMm : REAL; // 齿根高 hf=hf*·m [mm] / dedendum height [mm]
END_VAR
VAR
    fTeeth : REAL; // 齿数实数化结果 [-] / tooth count converted to REAL [-]
    fPitchDiaMm : REAL; // 分度圆直径 d=m·z [mm] / pitch circle diameter [mm]
END_VAR

// 段 1｜出口预置
FC_DL_GearRootCircleCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fDfMm := 0.0; // 齿根圆直径预置零 [mm] / root diameter preset zero [mm]
fDedendumMm := 0.0; // 齿根高预置零 [mm] / dedendum preset zero [mm]
fTeeth := 0.0; // 齿数实数预置零 [-] / real teeth preset zero [-]
fPitchDiaMm := 0.0; // 分度圆直径预置零 [mm] / pitch diameter preset zero [mm]

// 段 2｜非有限拦截 + 域闸
IF NOT (fModuleMm > -1.0E30 AND fModuleMm < 1.0E30) OR NOT (fDedFactor > -1.0E30 AND fDedFactor < 1.0E30) THEN
    RETURN; // 模数/齿根高系数任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fModuleMm < 1.0E-9 THEN
    RETURN; // 模数正域闸 [mm] / positive module gate [mm]
END_IF
IF fDedFactor < 0.8 OR fDedFactor > 1.6 THEN
    RETURN; // 齿根高系数工程域闸（0.8~1.6，标准 1.25） [-] / dedendum coefficient domain gate [-]
END_IF
IF nTeeth < 8 THEN
    RETURN; // 齿数域闸 z>=8：低于 8 齿时齿根圆退化、公式失真 [枚] / root circle degenerates below 8 teeth [-]
END_IF

// 段 3｜计算
fTeeth := DINT_TO_REAL(nTeeth); // DINT→REAL 标准转换函数（R10） [-] / standard conversion function (R10) [-]
fDedendumMm := fDedFactor * fModuleMm; // 无量纲 × mm = mm，hf=hf*·m / [-] × [mm] = [mm]
fPitchDiaMm := fModuleMm * fTeeth; // mm × 无量纲 = mm，d=m·z / [mm] × [-] = [mm]
fDfMm := fPitchDiaMm - 2.0 * fDedendumMm; // mm - mm = mm，df=d-2hf=m(z-2.5) / [mm]

// 段 4｜判定与饱和
IF fDfMm <= 0.0 THEN
    RETURN; // 结果闸：齿根圆直径必须为正，否则齿形无意义 [mm] / root diameter must be positive [mm]
END_IF
IF fDfMm >= fPitchDiaMm THEN
    RETURN; // 结构自洽闸：齿根圆必须小于分度圆 [mm] / structural check df < d [mm]
END_IF

// 段 5｜出口自检
IF NOT (fDfMm > -1.0E30 AND fDfMm < 1.0E30) THEN
    RETURN; // 出口自检：结果非有限即退回哨兵 [mm] / exit self-check on finiteness [mm]
END_IF
FC_DL_GearRootCircleCalc := fDfMm; // 返回齿根圆直径 [mm] / return the root circle diameter [mm]
END_FUNCTION
