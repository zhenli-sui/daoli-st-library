(*
  DL Factory R84 | FC_DL_FluidBedDryLossCalc
  功能：算流化床干燥失重 LOD 与干基含水率，并按 2% 典型限判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_FluidBedDryLossCalc : REAL
VAR_INPUT
    fWetG : REAL := 100.0; // 干燥前湿重 [g] / wet mass before drying [g]
    fDryG : REAL := 98.0; // 干燥后干重 [g] / dry mass after drying [g]
    fLimitPct : REAL := 2.0; // LOD 合格上限（典型 2%） [%] / LOD acceptance limit [%]
END_VAR
VAR_OUTPUT
    fWaterPct : REAL; // 干基含水率（水分/干固） [%] / moisture on dry basis [%]
    xPass : BOOL; // LOD 判合格 [-] / LOD passed [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fLossG : REAL; // 失重质量 [g] / mass loss [g]
    fLodPct : REAL; // 湿基失重中间量 [%] / wet basis loss intermediate [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_FluidBedDryLossCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fWaterPct := 0.0; // 含水率预置零 [%] / moisture preset zero [%]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 质量域闸（R4/R20）
IF NOT (fWetG > -1.0E30 AND fWetG < 1.0E30) OR NOT (fDryG > -1.0E30 AND fDryG < 1.0E30) OR NOT (fLimitPct > -1.0E30 AND fLimitPct < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fWetG < 1.0E-9 OR fDryG < 0.0 THEN
    RETURN; // 湿重分母闸 + 干重非负闸 [g] / wet mass denominator gate and non negative dry mass [g]
END_IF
IF fDryG > fWetG THEN
    RETURN; // 干重大于湿重违反质量守恒，拒算 [g] / dry above wet violates mass balance [g]
END_IF
IF fLimitPct <= 0.0 THEN
    RETURN; // 限值正域闸 [%] / positive limit gate [%]
END_IF

// 段 3｜LOD = (湿重 − 干重) / 湿重 × 100
fLossG := fWetG - fDryG; // g − g = g / [g] minus [g] = [g]
fLodPct := (fLossG / fWetG) * 100.0; // g ÷ g × 100 = % / [g] / [g] × 100 = [%]
IF NOT (fLodPct > -1.0E30 AND fLodPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜干基含水率 = 失重 / 干固 × 100（与湿基 LOD 区分）
IF fDryG >= 1.0E-9 THEN
    fWaterPct := (fLossG / fDryG) * 100.0; // g ÷ g × 100 = % / [g] / [g] × 100 = [%]
ELSE
    fWaterPct := -1.0; // 干重趋零：干基含水率无界，置哨兵 [%] / zero dry mass gives no finite basis [%]
END_IF
xPass := fLodPct <= fLimitPct; // 直比上限，禁浮点等值 [-] / direct compare against the limit [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_FluidBedDryLossCalc := fLodPct; // 返回 LOD [%] / return the LOD [%]
END_FUNCTION
