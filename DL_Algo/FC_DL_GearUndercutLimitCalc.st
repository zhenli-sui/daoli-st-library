(*
  DL Factory R88 | FC_DL_GearUndercutLimitCalc
  功能：算不根切最小齿数 zmin=2ha*/sin²α，并判定实际齿数是否达到该下限
  开源溯源：无（clean-room 自研，依据公开工艺公式 不根切最小齿数式 zmin=2ha*/sin²α，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearUndercutLimitCalc : REAL
VAR_INPUT
    fAddFactor : REAL := 1.0; // 齿顶高系数 ha*（标准齿 1.0，短齿 0.8） [-] / addendum coefficient [-]
    fPressureDeg : REAL := 20.0; // 压力角 α（度制，域闸 10~30） [°] / pressure angle in degrees [-]
    nTeeth : DINT := 20; // 被校核齿轮的实际齿数 z（整数入参，无 NaN 可能） [枚] / actual tooth count [-]
END_VAR
VAR_OUTPUT
    fZmin : REAL; // 不根切最小齿数 zmin（实数，常带小数） [枚] / minimum tooth count without undercut [-]
    xSafe : BOOL; // TRUE=实际齿数不小于 zmin，无根切风险 [-] / TRUE when no undercut risk [-]
END_VAR
VAR
    fAlphaRad : REAL; // 压力角弧度值 [rad] / pressure angle in radians [rad]
    fSinAlpha : REAL; // 压力角正弦 [-] / sine of the pressure angle [-]
    fSin2Alpha : REAL; // 正弦平方 sin²α（除零判据） [-] / squared sine, the divisor [-]
    fTeeth : REAL; // 实际齿数实数化 [-] / actual teeth as real [-]
END_VAR

// 段 1｜出口预置
FC_DL_GearUndercutLimitCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fZmin := 0.0; // 最小齿数预置零 [枚] / minimum teeth preset zero [-]
xSafe := FALSE; // 安全位预置 FALSE（未判定前不认安全） [-] / safety flag preset false [-]
fAlphaRad := 0.0; // 弧度预置零 [rad] / radians preset zero [rad]
fSinAlpha := 0.0; // 正弦预置零 [-] / sine preset zero [-]
fSin2Alpha := 0.0; // 正弦平方预置零 [-] / squared sine preset zero [-]
fTeeth := 0.0; // 齿数实数预置零 [-] / real teeth preset zero [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fAddFactor > -1.0E30 AND fAddFactor < 1.0E30) OR NOT (fPressureDeg > -1.0E30 AND fPressureDeg < 1.0E30) THEN
    RETURN; // 齿顶高系数/压力角任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fAddFactor < 0.4 OR fAddFactor > 1.6 THEN
    RETURN; // 齿顶高系数工程域闸（0.4~1.6） [-] / addendum coefficient domain gate [-]
END_IF
IF fPressureDeg <= 10.0 OR fPressureDeg >= 30.0 THEN
    RETURN; // 压力角开区间域闸 (10°,30°)，同时保护 sin²α 远离零 [°] / open interval gate on alpha [deg]
END_IF
IF nTeeth < 1 THEN
    RETURN; // 齿数下限闸（整数域，仅做范围拦截） [枚] / tooth count lower gate [-]
END_IF

// 段 3｜计算
fTeeth := DINT_TO_REAL(nTeeth); // DINT→REAL 标准转换函数（R10） [-] / standard conversion (R10) [-]
fAlphaRad := fPressureDeg * 0.0174532925; // 度 × (π/180) = rad，换算常数 0.0174532925 [rad] / degrees to radians [rad]
fSinAlpha := SIN(fAlphaRad); // 无量纲 [-] / dimensionless sine [-]
fSin2Alpha := fSinAlpha * fSinAlpha; // 无量纲 × 无量纲 = 无量纲，sin²α [-] / squared sine [-]

// 段 4｜判定与饱和
IF fSin2Alpha < 1.0E-9 THEN
    RETURN; // 除法前分母闸：sin²α 必须大于 1E-9 才可作除数 [-] / denominator gate before the division [-]
END_IF
fZmin := (2.0 * fAddFactor) / fSin2Alpha; // (无量纲) ÷ 无量纲 = 无量纲，zmin=2ha*/sin²α（单位=齿数） [枚] / minimum teeth [-]
xSafe := fTeeth >= fZmin; // 实际齿数与下限直比（含边界） [枚] / compare the actual count against zmin [-]

// 段 5｜出口自检
IF NOT (fZmin > -1.0E30 AND fZmin < 1.0E30) OR fZmin <= 0.0 THEN
    RETURN; // 出口自检：zmin 须有限且为正，否则退回哨兵 [枚] / exit self-check on zmin [teeth]
END_IF
FC_DL_GearUndercutLimitCalc := fZmin; // 返回不根切最小齿数 [枚] / return the undercut limit tooth count [-]
END_FUNCTION
