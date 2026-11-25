(*
  DL Factory R88 | FC_DL_H2LeakRateCalc
  功能：压降法算泄漏率 Q=V·Δp/Δt（Pa·m³/s），换算为标准状态 NmL/min，并判是否超限
  开源溯源：无（clean-room 自研，依据公开工艺公式 压降法泄漏率式 Q=V·dp/dt，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_H2LeakRateCalc : REAL
VAR_INPUT
    fVolL : REAL := 50.0; // 被测封闭容积 V [L] / test volume [L]
    fDropPa : REAL := 500.0; // 保压期间压降 Δp（取正值） [Pa] / pressure drop over the hold time [Pa]
    fDurS : REAL := 60.0; // 保压时长 Δt [s] / hold duration [s]
    fLimitNmlMin : REAL := 10.0; // 泄漏率报警上限（标准状态） [NmL/min] / leak rate alarm limit [NmL/min]
    fPatmPa : REAL := 101325.0; // 标准大气压（换算基准） [Pa] / standard atmospheric pressure [Pa]
END_VAR
VAR_OUTPUT
    fLeakNmlMin : REAL; // 泄漏率（标准状态体积流量） [NmL/min] / leak rate at standard conditions [NmL/min]
    xOverLimit : BOOL; // TRUE=泄漏率超过报警上限 [-] / TRUE when above the alarm limit [-]
END_VAR
VAR
    fVolM3 : REAL; // 容积换算为 m³ [m³] / volume in cubic metres [m^3]
    fLeakPam3PerS : REAL; // 泄漏率原始量 Q [Pa·m³/s] / raw leak rate [Pa*m^3/s]
    fLeakNm3PerS : REAL; // 标准状态体积流量 [Nm³/s] / standard volumetric flow [Nm^3/s]
END_VAR

// 段 1｜出口预置
FC_DL_H2LeakRateCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fLeakNmlMin := 0.0; // 泄漏率预置零 [NmL/min] / leak rate preset zero [NmL/min]
xOverLimit := FALSE; // 超限位预置 FALSE（未判定前不报警） [-] / over-limit flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fVolL > -1.0E30 AND fVolL < 1.0E30) OR NOT (fDropPa > -1.0E30 AND fDropPa < 1.0E30) OR NOT (fDurS > -1.0E30 AND fDurS < 1.0E30) THEN
    RETURN; // 容积/压降/时长任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fLimitNmlMin > -1.0E30 AND fLimitNmlMin < 1.0E30) OR NOT (fPatmPa > -1.0E30 AND fPatmPa < 1.0E30) THEN
    RETURN; // 上限/基准压力任一非有限则判据与换算链失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fVolL < 1.0E-9 OR fDropPa < 0.0 OR fDurS < 1.0E-9 THEN
    RETURN; // 容积正域闸 + 压降非负闸 + 时长正域闸（分母不得为零） [L, Pa, s] / positive volume and duration
END_IF
IF fPatmPa < 1.0E-9 OR fLimitNmlMin <= 0.0 THEN
    RETURN; // 基准压力正域闸（换算分母）+ 上限正域闸 [Pa, NmL/min] / reference pressure and limit gates
END_IF

// 段 3｜计算（Pa·m³/s → Nm³/s → NmL/min 三段换算，逐项量纲见行尾注释）
fVolM3 := fVolL * 0.001; // L × 0.001 m³/L = m³，容积换算 [m³] / [L] x [m^3/L] = [m^3]
fLeakPam3PerS := fVolM3 * fDropPa / fDurS; // m³ × Pa ÷ s = Pa·m³/s，压降法泄漏率 [Pa·m³/s] / [Pa*m^3/s]
fLeakNm3PerS := fLeakPam3PerS / fPatmPa; // (Pa·m³/s) ÷ Pa = m³/s（标准状态） [Nm³/s] / [Nm^3/s]
fLeakNmlMin := fLeakNm3PerS * 1.0E6 * 60.0; // (Nm³/s) × 1e6 mL/m³ × 60 s/min = NmL/min [NmL/min] / [NmL/min]

// 段 4｜判定与饱和
IF NOT (fLeakNmlMin > -1.0E30 AND fLeakNmlMin < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xOverLimit := fLeakNmlMin > fLimitNmlMin; // 严格大于上限为超限，等于上限仍判合格 [NmL/min] / strict compare [NmL/min]

// 段 5｜出口自检
IF fLeakNmlMin < 0.0 THEN
    RETURN; // 出口自检：泄漏率不得为负（负值说明压降符号错） [NmL/min] / leak rate must not be negative [NmL/min]
END_IF
FC_DL_H2LeakRateCalc := fLeakNmlMin; // 返回标准状态泄漏率 [NmL/min] / return the leak rate [NmL/min]
END_FUNCTION
