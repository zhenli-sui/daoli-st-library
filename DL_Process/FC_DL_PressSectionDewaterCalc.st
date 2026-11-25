(*
  DL Factory R84 | FC_DL_PressSectionDewaterCalc
  功能：压榨部脱水，按入口干度与压榨比压、车速经验式估算出口干度与断纸风险
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_PressSectionDewaterCalc : REAL
VAR_INPUT
    fInDryPct : REAL := 20.0; // 压榨入口干度 [%] / inlet dryness [%]
    fPressMpa : REAL := 0.8; // 压榨线比压 [MPa] / press nip line load converted to pressure [MPa]
    fSpeedMpm : REAL := 900.0; // 车速 [m/min] / machine speed [m/min]
    fGainCoefPctMpa : REAL := 8.0; // 压榨增益系数（单位比压干度提升） [%/MPa] / gain coefficient [%/MPa]
    fSpeedCoef : REAL := 0.001; // 车速衰减系数 [min/m] / speed decay coefficient [min/m]
    fDryMaxPct : REAL := 50.0; // 出口干度上限（压榨能力极限） [%] / maximum outlet dryness [%]
    fDryMinPct : REAL := 30.0; // 断纸风险干度下限 [%] / dryness floor against web breaks [%]
END_VAR
VAR_OUTPUT
    fGainPct : REAL; // 干度提升量 [%] / dryness gain [%]
    xRisk : BOOL; // 断纸风险位（出口干度低于下限） [-] / web break risk flag [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fDen : REAL; // 车速衰减项（已加下限闸） [-] / speed decay term with a floor [-]
    fOutPct : REAL; // 出口干度中间量 [%] / outlet dryness intermediate [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_PressSectionDewaterCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fGainPct := 0.0; // 干度提升预置零 [%] / gain preset zero [%]
xRisk := FALSE; // 风险位预置 FALSE [-] / risk preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fInDryPct > -1.0E30 AND fInDryPct < 1.0E30) OR NOT (fPressMpa > -1.0E30 AND fPressMpa < 1.0E30) OR NOT (fSpeedMpm > -1.0E30 AND fSpeedMpm < 1.0E30) THEN
    RETURN; // 干度/比压/车速任一非有限即拒算 [-] / any non finite dryness, pressure or speed rejected [-]
END_IF
IF NOT (fGainCoefPctMpa > -1.0E30 AND fGainCoefPctMpa < 1.0E30) OR NOT (fSpeedCoef > -1.0E30 AND fSpeedCoef < 1.0E30) THEN
    RETURN; // 增益与衰减系数任一非有限即拒算 [-] / any non finite coefficient rejected [-]
END_IF
IF fInDryPct < 0.0 OR fInDryPct >= 100.0 OR fPressMpa < 0.0 OR fSpeedMpm < 0.0 OR fSpeedCoef < 0.0 THEN
    RETURN; // 干度开区间 + 比压与车速非负域闸 [%, MPa, m/min] / dryness open interval and non negative gate [-]
END_IF
IF fDryMaxPct < 1.0E-9 OR NOT (fDryMinPct < fDryMaxPct) THEN
    RETURN; // 干度上限正域闸 + 门限组态闸（下限须小于上限） [%] / dryness ceiling and threshold config gate [%]
END_IF

// 段 3｜经验式：增益 = k×比压 / (1 + 车速衰减项)
fDen := 1.0 + (fSpeedCoef * fSpeedMpm); // 无量纲：1 + (min/m × m/min) = - / dimensionless one plus the speed term
IF fDen < 1.0E-9 THEN
    RETURN; // 分母闸：衰减项退化 [无量纲] / denominator gate on the speed term [-]
END_IF
fGainPct := (fGainCoefPctMpa * fPressMpa) / fDen; // (%/MPa × MPa) ÷ 无量纲 = % / [%/MPa] × [MPa] / [-] = [%]
IF fGainPct < 0.0 THEN
    fGainPct := 0.0; // 负增益钳零（压榨不会使干度下降） [%] / clamp to zero, pressing never lowers dryness [%]
END_IF

// 段 4｜出口干度与上限钳位
fOutPct := fInDryPct + fGainPct; // % + % = % / [%] + [%] = [%]
IF fOutPct > fDryMaxPct THEN
    fGainPct := fDryMaxPct - fInDryPct; // 反算实际可提升量（封顶后） [%] / recompute the gain after capping [%]
    fOutPct := fDryMaxPct; // 出口干度封顶（压榨能力极限） [%] / cap the outlet dryness [%]
END_IF
IF fOutPct > 99.0 THEN
    fOutPct := 99.0; // 物理上限兜底：干度不可能达 100% [%] / physical ceiling, dryness cannot reach one hundred [%]
END_IF
IF NOT (fOutPct > -1.0E30 AND fOutPct < 1.0E30) OR NOT (fGainPct > -1.0E30 AND fGainPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF

// 段 5｜断纸风险判定：出口干度低于下限即湿部断纸风险
xRisk := fOutPct < fDryMinPct; // 直比门限，禁浮点等值 [-] / direct compare against the floor [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_PressSectionDewaterCalc := fOutPct; // 返回出口干度 [%] / return the outlet dryness [%]
END_FUNCTION
