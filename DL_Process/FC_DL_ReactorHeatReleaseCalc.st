(*
  DL Factory R84 | FC_DL_ReactorHeatReleaseCalc
  功能：由夹套温差流量算移热功率，叠加釜内蓄热反算放热速率与单位质量放热
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ReactorHeatReleaseCalc : REAL
VAR_INPUT
    fFlowKgh : REAL := 3000.0; // 夹套冷却介质流量 [kg/h] / jacket coolant flow [kg/h]
    fCpKjKgK : REAL := 4.18; // 冷却介质比热 [kJ/(kg·K)] / coolant specific heat [kJ/(kg*K)]
    fTinC : REAL := 25.0; // 夹套进口温度 [℃] / jacket inlet temperature [C]
    fToutC : REAL := 30.0; // 夹套出口温度 [℃] / jacket outlet temperature [C]
    fMassKg : REAL := 2000.0; // 釜内物料总质量 [kg] / batch mass [kg]
    fCpBatchKjKgK : REAL := 3.2; // 釜内物料比热 [kJ/(kg·K)] / batch specific heat [kJ/(kg*K)]
    fHeatRateKmin : REAL := 0.2; // 釜内温升速率 [K/min] / batch heating rate [K/min]
    fAccumKj : REAL := 1000.0; // 累计放热量 [kJ] / accumulated heat released [kJ]
END_VAR
VAR_OUTPUT
    fQremKw : REAL; // 夹套移热功率 [kW] / removed heat duty [kW]
    fQrelKjKg : REAL; // 单位质量累计放热 [kJ/kg] / specific heat released [kJ/kg]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fQAccumKw : REAL; // 釜内蓄热功率 [kW] / batch accumulation duty [kW]
    fQrelKw : REAL; // 总放热速率 [kW] / total release rate [kW]
END_VAR
VAR CONSTANT
    DL_RHR_SECH : REAL := 3600.0; // 小时转秒常量 [s/h] / seconds per hour [s/h]
    DL_RHR_MIN : REAL := 60.0; // 分钟转秒常量 [s/min] / seconds per minute [s/min]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ReactorHeatReleaseCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fQremKw := 0.0; // 移热功率预置零 [kW] / removed duty preset zero [kW]
fQrelKjKg := 0.0; // 单位放热预置零 [kJ/kg] / specific heat preset zero [kJ/kg]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fFlowKgh > -1.0E30 AND fFlowKgh < 1.0E30) OR NOT (fCpKjKgK > -1.0E30 AND fCpKjKgK < 1.0E30) OR NOT (fTinC > -1.0E30 AND fTinC < 1.0E30) OR NOT (fToutC > -1.0E30 AND fToutC < 1.0E30) OR NOT (fMassKg > -1.0E30 AND fMassKg < 1.0E30) THEN
    RETURN; // 温度/流量/比热任一非有限即拒算 [-] / any non finite thermal input rejected [-]
END_IF
IF NOT (fCpBatchKjKgK > -1.0E30 AND fCpBatchKjKgK < 1.0E30) OR NOT (fHeatRateKmin > -1.0E30 AND fHeatRateKmin < 1.0E30) OR NOT (fAccumKj > -1.0E30 AND fAccumKj < 1.0E30) THEN
    RETURN; // 物料比热/温升速率/累积量任一非有限即拒算 [-] / any non finite batch input rejected [-]
END_IF
IF fCpKjKgK < 1.0E-9 OR fCpBatchKjKgK < 1.0E-9 OR fMassKg < 1.0E-9 OR fFlowKgh < 0.0 THEN
    RETURN; // 比热与质量正域分母闸（防除零） [kJ/(kg·K), kg] / positive cp and mass denominator gate [-]
END_IF

// 段 3｜夹套移热 Q = m·cp·ΔT（kg/s 化后即 kW）
fQremKw := (fFlowKgh / DL_RHR_SECH) * fCpKjKgK * (fToutC - fTinC); // kg/h ÷ 3600 = kg/s；kg/s × kJ/(kg·K) × K = kJ/s = kW / [kg/h] / 3600 × [kJ/(kg*K)] × [K] = [kW]
IF NOT (fQremKw > -1.0E30 AND fQremKw < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜釜内蓄热功率（温升速率 K/min 化到 K/s）
fQAccumKw := (fMassKg * fCpBatchKjKgK * fHeatRateKmin) / DL_RHR_MIN; // kg × kJ/(kg·K) × K/min ÷ 60 = kJ/s = kW / [kg] × [kJ/(kg*K)] × [K/min] / 60 = [kW]

// 段 5｜总放热速率与单位质量放热
fQrelKw := fQremKw + fQAccumKw; // kW + kW = kW（放热 = 移热 + 蓄热） / [kW] + [kW] = [kW]
fQrelKjKg := fAccumKj / fMassKg; // kJ ÷ kg = kJ/kg / [kJ] / [kg] = [kJ/kg]
IF NOT (fQrelKw > -1.0E30 AND fQrelKw < 1.0E30) OR NOT (fQrelKjKg > -1.0E30 AND fQrelKjKg < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ReactorHeatReleaseCalc := fQrelKw; // 返回放热速率 [kW] / return the release rate [kW]
END_FUNCTION
