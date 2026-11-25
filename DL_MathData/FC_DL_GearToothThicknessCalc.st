(*
  DL Factory R88 | FC_DL_GearToothThicknessCalc
  功能：由模数/齿数算分度圆弦齿厚 s=m·z·sin(π/(2z))，并给出弧齿厚 πm/2 参考值，齿数域闸 z>=6
  开源溯源：无（clean-room 自研，依据公开工艺公式 分度圆弦齿厚式 s=d·sin(π/2z)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearToothThicknessCalc : REAL
VAR_INPUT
    fModuleMm : REAL := 3.0; // 模数 m [mm] / module [mm]
    nTeeth : DINT := 20; // 齿数 z，域闸 z>=6 [枚] / tooth count, gated at 6 or more [-]
    fHalfAngleMaxRad : REAL := 1.5; // 半齿角上限保护（π/(2z) 须小于此值，防高齿数误用） [rad] / half tooth angle ceiling [rad]
END_VAR
VAR_OUTPUT
    fChordThkMm : REAL; // 分度圆弦齿厚 s [mm] / chordal tooth thickness [mm]
    fArcThkMm : REAL; // 分度圆弧齿厚 πm/2（参考值） [mm] / circular tooth thickness reference [mm]
END_VAR
VAR
    fTeeth : REAL; // 齿数实数化结果 [-] / tooth count converted to REAL [-]
    fHalfAngleRad : REAL; // 半齿角 π/(2z) [rad] / half tooth angle [rad]
    fDenomTeeth : REAL; // 半齿角分母 2z（除零判据） [枚] / half angle denominator [-]
END_VAR

// 段 1｜出口预置
FC_DL_GearToothThicknessCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fChordThkMm := 0.0; // 弦齿厚预置零 [mm] / chordal thickness preset zero [mm]
fArcThkMm := 0.0; // 弧齿厚预置零 [mm] / circular thickness preset zero [mm]
fTeeth := 0.0; // 齿数实数预置零 [-] / real teeth preset zero [-]
fHalfAngleRad := 0.0; // 半齿角预置零 [rad] / half angle preset zero [rad]
fDenomTeeth := 0.0; // 分母预置零 [枚] / denominator preset zero [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fModuleMm > -1.0E30 AND fModuleMm < 1.0E30) OR NOT (fHalfAngleMaxRad > -1.0E30 AND fHalfAngleMaxRad < 1.0E30) THEN
    RETURN; // 模数/保护限任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fModuleMm < 1.0E-9 THEN
    RETURN; // 模数正域闸 [mm] / positive module gate [mm]
END_IF
IF fHalfAngleMaxRad <= 0.0 THEN
    RETURN; // 保护限正域闸：须为正，否则后面判据失效 [rad] / positive ceiling gate [rad]
END_IF
IF nTeeth < 6 THEN
    RETURN; // 齿数域闸 z>=6：齿数过低时弦齿厚式与齿形均失真 [枚] / tooth count gate for the chord formula [-]
END_IF

// 段 3｜计算
fTeeth := DINT_TO_REAL(nTeeth); // DINT→REAL 标准转换函数（R10） [-] / standard conversion function (R10) [-]
fDenomTeeth := 2.0 * fTeeth; // 无量纲 × 无量纲 = 无量纲，即 2z [-] / the 2z denominator [-]
IF fDenomTeeth < 1.0E-9 THEN
    RETURN; // 除法前分母闸：2z 必须大于 1E-9 才可作除数 [-] / denominator gate before the division [-]
END_IF
fHalfAngleRad := 3.14159265 / fDenomTeeth; // 无量纲 ÷ 无量纲 = rad，π/(2z) [rad] / half tooth angle [rad]
IF fHalfAngleRad >= fHalfAngleMaxRad THEN
    RETURN; // 半齿角上限闸：超出说明齿数或输入落入误用区间 [rad] / half angle ceiling check [rad]
END_IF
fChordThkMm := fModuleMm * fTeeth * SIN(fHalfAngleRad); // mm × [-] × [-] = mm，s=m·z·sin(π/2z) / [mm]
fArcThkMm := 3.14159265 * fModuleMm * 0.5; // 无量纲 × mm × 0.5 = mm，πm/2（以乘 0.5 替除 2） / [mm]

// 段 4｜判定与饱和
IF fChordThkMm <= 0.0 OR fChordThkMm >= fArcThkMm THEN
    RETURN; // 结构自洽闸：弦齿厚须为正且小于弧齿厚 [mm] / chord thickness must lie in (0, arc) [mm]
END_IF

// 段 5｜出口自检
IF NOT (fChordThkMm > -1.0E30 AND fChordThkMm < 1.0E30) THEN
    RETURN; // 出口自检：结果非有限即退回哨兵 [mm] / exit self-check on finiteness [mm]
END_IF
FC_DL_GearToothThicknessCalc := fChordThkMm; // 返回分度圆弦齿厚 [mm] / return the chordal tooth thickness [mm]
END_FUNCTION
