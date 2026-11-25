(*
  DL Factory R88 | FC_DL_GearContactRatioCalc
  功能：算端面重合度 εα=[√(ra1²-rb1²)+√(ra2²-rb2²)-a·sinα]/(π·m·cosα)，并按 1.2 判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 端面重合度式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearContactRatioCalc : REAL
VAR_INPUT
    fModule1Mm : REAL := 3.0; // 小齿轮模数 m1 [mm] / pinion module [mm]
    nTeeth1 : DINT := 20; // 小齿轮齿数 z1（整数入参，无 NaN 可能） [枚] / pinion tooth count [-]
    fModule2Mm : REAL := 3.0; // 大齿轮模数 m2 [mm] / gear module [mm]
    nTeeth2 : DINT := 40; // 大齿轮齿数 z2（整数入参，无 NaN 可能） [枚] / gear tooth count [-]
    fCentreDistMm : REAL := 90.0; // 实际中心距 a [mm] / actual centre distance [mm]
    fPressureDeg : REAL := 20.0; // 压力角 α（度制，域闸 10~30） [°] / pressure angle in degrees [-]
END_VAR
VAR_OUTPUT
    fEpsAlpha : REAL; // 端面重合度 εα [-] / transverse contact ratio [-]
    xAccept : BOOL; // TRUE=εα 不小于 1.2 的工程合格线 [-] / TRUE when the ratio meets 1.2 [-]
END_VAR
VAR
    fZ1 : REAL; // 小齿轮齿数实数化 [-] / pinion teeth as real [-]
    fZ2 : REAL; // 大齿轮齿数实数化 [-] / gear teeth as real [-]
    fAlphaRad : REAL; // 压力角弧度值 [rad] / pressure angle in radians [rad]
    fRad1 : REAL; // 小齿轮被开方数 ra1²-rb1²（ha*=1） [mm²] / pinion radicand [mm^2]
    fRad2 : REAL; // 大齿轮被开方数 ra2²-rb2²（ha*=1） [mm²] / gear radicand [mm^2]
    fDenom : REAL; // 分母基节 π·m·cosα（除零判据） [mm] / base pitch, the divisor [mm]
END_VAR

// 段 1｜出口预置
FC_DL_GearContactRatioCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fEpsAlpha := 0.0; // 重合度预置零 [-] / contact ratio preset zero [-]
xAccept := FALSE; // 合格位预置 FALSE（未判定前不认合格） [-] / accept flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fModule1Mm > -1.0E30 AND fModule1Mm < 1.0E30) OR NOT (fModule2Mm > -1.0E30 AND fModule2Mm < 1.0E30) OR NOT (fCentreDistMm > -1.0E30 AND fCentreDistMm < 1.0E30) THEN
    RETURN; // 两模数/中心距任一非有限即拒算 [-] / any non finite geometry rejected [-]
END_IF
IF NOT (fPressureDeg > -1.0E30 AND fPressureDeg < 1.0E30) THEN
    RETURN; // 压力角非有限则域闸与判据同时失效，故先拦 [°] / alpha must be finite [deg]
END_IF
IF fModule1Mm < 1.0E-9 OR fModule2Mm < 1.0E-9 OR fCentreDistMm < 1.0E-9 OR fPressureDeg <= 10.0 OR fPressureDeg >= 30.0 OR nTeeth1 < 3 OR nTeeth2 < 3 THEN
    RETURN; // 模数/中心距正域闸 + 压力角开区间闸 (10°,30°) + 齿数下限闸（整数域无 NaN 可能） / geometry gates
END_IF

// 段 3｜计算
fZ1 := DINT_TO_REAL(nTeeth1); // DINT→REAL 标准转换函数（R10） [-] / standard conversion (R10) [-]
fZ2 := DINT_TO_REAL(nTeeth2); // DINT→REAL 标准转换函数（R10） [-] / standard conversion (R10) [-]
fAlphaRad := fPressureDeg * 0.0174532925; // 度 × (π/180) = rad，换算常数 0.0174532925 [rad] / degrees to radians [rad]
fRad1 := (fModule1Mm * (fZ1 + 2.0) * 0.5) * (fModule1Mm * (fZ1 + 2.0) * 0.5) - (fModule1Mm * fZ1 * COS(fAlphaRad) * 0.5) * (fModule1Mm * fZ1 * COS(fAlphaRad) * 0.5); // mm²，ra1²-rb1² [mm²] / pinion radicand [mm^2]
fRad2 := (fModule2Mm * (fZ2 + 2.0) * 0.5) * (fModule2Mm * (fZ2 + 2.0) * 0.5) - (fModule2Mm * fZ2 * COS(fAlphaRad) * 0.5) * (fModule2Mm * fZ2 * COS(fAlphaRad) * 0.5); // mm²，ra2²-rb2² [mm²] / gear radicand [mm^2]
IF fRad1 < 0.0 OR fRad2 < 0.0 THEN
    RETURN; // 被开方数闸：负值会经 SQRT 产生 NaN，必须先拦 [mm²] / radicand gate before SQRT [mm^2]
END_IF
fDenom := 3.14159265 * fModule1Mm * COS(fAlphaRad); // 无量纲 × mm × 无量纲 = mm，基节 pb=π·m·cosα [mm] / base pitch [mm]
IF fDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：基节必须大于 1E-9 才可作除数 [mm] / denominator gate before the division [mm]
END_IF
fEpsAlpha := (SQRT(fRad1) + SQRT(fRad2) - fCentreDistMm * SIN(fAlphaRad)) / fDenom; // mm ÷ mm = 无量纲，εα [-] / [mm] / [mm] = [-]

// 段 4｜判定与饱和
xAccept := fEpsAlpha >= 1.2; // 重合度与工程合格线 1.2 直比（含边界） [-] / compare against 1.2 [-]

// 段 5｜出口自检
IF NOT (fEpsAlpha > -1.0E30 AND fEpsAlpha < 1.0E30) OR fEpsAlpha <= 0.0 THEN
    RETURN; // 出口自检：非有限或非正即退回哨兵（NaN 不得外泄） [-] / exit self-check on the result [-]
END_IF
FC_DL_GearContactRatioCalc := fEpsAlpha; // 返回端面重合度 εα [-] / return the contact ratio [-]
END_FUNCTION
