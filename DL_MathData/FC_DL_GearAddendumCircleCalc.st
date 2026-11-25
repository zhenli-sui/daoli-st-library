(*
  DL Factory R88 | FC_DL_GearAddendumCircleCalc
  功能：由模数/齿数/齿顶高系数算齿顶圆直径 da 与分度圆直径 d=m·z（da=d+2·ha*·m，标准齿 ha*=1）
  开源溯源：无（clean-room 自研，依据公开工艺公式 齿顶圆直径式 da=m·z+2·ha*·m，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearAddendumCircleCalc : REAL
VAR_INPUT
    fModuleMm : REAL := 3.0; // 模数 m [mm] / module [mm]
    nTeeth : DINT := 20; // 齿数 z（整数入参，不可能为 NaN） [枚] / tooth count, integer input cannot be NaN [-]
    fAddFactor : REAL := 1.0; // 齿顶高系数 ha*（标准齿 1.0，短齿 0.8，长齿 1.2） [-] / addendum coefficient [-]
END_VAR
VAR_OUTPUT
    fDaMm : REAL; // 齿顶圆直径 da [mm] / addendum circle diameter [mm]
    fPitchDiaMm : REAL; // 分度圆直径 d [mm] / pitch circle diameter [mm]
END_VAR
VAR
    fTeeth : REAL; // 齿数实数化结果 [-] / tooth count converted to REAL [-]
    fAddendumMm : REAL; // 齿顶高 ha=ha*·m [mm] / addendum height [mm]
END_VAR

// 段 1｜出口预置
FC_DL_GearAddendumCircleCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fDaMm := 0.0; // 齿顶圆直径预置零 [mm] / addendum diameter preset zero [mm]
fPitchDiaMm := 0.0; // 分度圆直径预置零 [mm] / pitch diameter preset zero [mm]
fTeeth := 0.0; // 齿数实数预置零 [-] / real teeth preset zero [-]
fAddendumMm := 0.0; // 齿顶高预置零 [mm] / addendum preset zero [mm]

// 段 2｜非有限拦截 + 域闸
IF NOT (fModuleMm > -1.0E30 AND fModuleMm < 1.0E30) OR NOT (fAddFactor > -1.0E30 AND fAddFactor < 1.0E30) THEN
    RETURN; // 模数/齿顶高系数任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fModuleMm < 1.0E-9 THEN
    RETURN; // 模数正域闸 [mm] / positive module gate [mm]
END_IF
IF fAddFactor < 0.4 OR fAddFactor > 1.6 THEN
    RETURN; // 齿顶高系数工程域闸（远离 0 防退化齿形） [-] / addendum coefficient domain gate [-]
END_IF
IF nTeeth < 1 THEN
    RETURN; // 齿数下限闸（整数域，无 NaN 可能，仅做范围拦截） [枚] / tooth count lower gate [-]
END_IF

// 段 3｜计算
fTeeth := DINT_TO_REAL(nTeeth); // DINT→REAL 标准转换函数（R10 禁构造函数式） [-] / standard conversion function (R10) [-]
fAddendumMm := fAddFactor * fModuleMm; // 无量纲 × mm = mm，ha=ha*·m / [-] × [mm] = [mm]
fPitchDiaMm := fModuleMm * fTeeth; // mm × 无量纲 = mm，d=m·z / [mm] × [-] = [mm]
fDaMm := fPitchDiaMm + 2.0 * fAddendumMm; // mm + mm = mm，da=d+2·ha=m·z+2·ha*·m [mm] / [mm]

// 段 4｜判定与饱和
IF fDaMm <= fPitchDiaMm THEN
    RETURN; // 结构自洽闸：齿顶圆必须严格大于分度圆 [mm] / structural check da > d [mm]
END_IF

// 段 5｜出口自检
IF NOT (fDaMm > -1.0E30 AND fDaMm < 1.0E30) OR fDaMm < 1.0E-9 THEN
    RETURN; // 出口自检：齿顶圆有限且为正，否则退回哨兵 [mm] / exit self-check on da [mm]
END_IF
FC_DL_GearAddendumCircleCalc := fDaMm; // 返回齿顶圆直径 [mm] / return the addendum diameter [mm]
END_FUNCTION
