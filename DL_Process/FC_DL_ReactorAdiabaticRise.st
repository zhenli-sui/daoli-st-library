(*
  DL Factory R84 | FC_DL_ReactorAdiabaticRise
  功能：由累积投料摩尔与反应焓算绝热温升，并带投料完成度修正
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ReactorAdiabaticRise : REAL
VAR_INPUT
    fChargedMol : REAL := 500.0; // 已累积投料摩尔数 [mol] / charged moles so far [mol]
    fTargetMol : REAL := 800.0; // 计划满批摩尔数 [mol] / planned full batch moles [mol]
    fHrKjMol : REAL := 120.0; // 反应焓（放热取正） [kJ/mol] / heat of reaction, exotherm positive [kJ/mol]
    fMassKg : REAL := 2000.0; // 釜内物料总质量 [kg] / total batch mass [kg]
    fCpKjKgK : REAL := 3.2; // 物料比热 [kJ/(kg·K)] / batch specific heat [kJ/(kg*K)]
END_VAR
VAR_OUTPUT
    fAccumMol : REAL; // 累积投料摩尔（回显链路量） [mol] / accumulated charged moles [mol]
    fFillRatio : REAL; // 投料完成度（钳位 0~1） [-] / charge completion ratio, clamped [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fDTadFullK : REAL; // 满批绝热温升 [K] / full batch adiabatic rise [K]
    fDTadK : REAL; // 修正后绝热温升 [K] / corrected adiabatic rise [K]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ReactorAdiabaticRise := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fAccumMol := 0.0; // 累积摩尔预置零 [mol] / accumulated moles preset zero [mol]
fFillRatio := 0.0; // 完成度预置零 [-] / completion preset zero [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fChargedMol > -1.0E30 AND fChargedMol < 1.0E30) OR NOT (fTargetMol > -1.0E30 AND fTargetMol < 1.0E30) OR NOT (fHrKjMol > -1.0E30 AND fHrKjMol < 1.0E30) OR NOT (fMassKg > -1.0E30 AND fMassKg < 1.0E30) OR NOT (fCpKjKgK > -1.0E30 AND fCpKjKgK < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fTargetMol < 1.0E-9 OR fMassKg < 1.0E-9 OR fCpKjKgK < 1.0E-9 OR fChargedMol < 0.0 THEN
    RETURN; // 满批摩尔分母闸 + 质量/比热正域闸（防除零） [mol, kg] / denominator and positive domain gate [-]
END_IF

// 段 3｜满批绝热温升 ΔTad = (n·ΔHr)/(m·cp)
fDTadFullK := (fTargetMol * fHrKjMol) / (fMassKg * fCpKjKgK); // (mol × kJ/mol) ÷ (kg × kJ/(kg·K)) = K / [mol]×[kJ/mol] / ([kg]×[kJ/(kg*K)]) = [K]
IF NOT (fDTadFullK > -1.0E30 AND fDTadFullK < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜投料完成度修正（钳位 0~1，超投按满批计）
fFillRatio := fChargedMol / fTargetMol; // mol ÷ mol = 无量纲 / [mol] / [mol] = [-]
IF fFillRatio > 1.0 THEN
    fFillRatio := 1.0; // 超投钳位：温升潜力按满批封顶 [-] / clamp high, potential capped at full batch [-]
END_IF
IF fFillRatio < 0.0 THEN
    fFillRatio := 0.0; // 负投料钳零 [-] / clamp low to zero [-]
END_IF
fDTadK := fDTadFullK * fFillRatio; // K × 无量纲 = K（等价于按累积摩尔计） / [K] × [-] = [K]
IF NOT (fDTadK > -1.0E30 AND fDTadK < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
fAccumMol := fChargedMol; // 回显累积投料摩尔 [mol] / echo the accumulated moles [mol]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ReactorAdiabaticRise := fDTadK; // 返回绝热温升 [K] / return the adiabatic rise [K]
END_FUNCTION
