(*
  DL Factory R88 | FC_DL_WaferThermalBudgetCalc
  功能：单段热预算 Dt=T·Δt（°C·min），并折算为参考温度（默认 1000°C）下的等效停留秒数，超限提示
  开源溯源：无（clean-room 自研，依据公开工艺公式 热预算定义式 Dt=ΣT·Δt，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_WaferThermalBudgetCalc : REAL
VAR_INPUT
    fTempC : REAL := 900.0; // 该段工艺温度 T（摄氏） [°C] / process temperature [degC]
    fDurMin : REAL := 30.0; // 该段停留时长 Δt [min] / dwell duration [min]
    fLimitDegCmin : REAL := 30000.0; // 热预算上限（防止扩散过度） [°C·min] / thermal budget limit [degC*min]
    fRefTempC : REAL := 1000.0; // 归一化参考温度（等效秒数的基准，默认 1000） [°C] / reference temperature [degC]
END_VAR
VAR_OUTPUT
    fBudgetDegCmin : REAL; // 单段热预算 T·Δt [°C·min] / thermal budget of the segment [degC*min]
    fEquiv1000Cs : REAL; // 参考温度下的等效停留秒数 [s] / equivalent dwell seconds at the reference temperature [s]
    xOverLimit : BOOL; // TRUE=热预算超过上限 [-] / TRUE when above the limit [-]
END_VAR
VAR
    fBudgetDegCs : REAL; // 热预算换算为 °C·s（归一化前的分子） [°C·s] / budget in degC*s [degC*s]
    fRefDenom : REAL; // 参考温度分母（除零判据） [°C] / reference temperature divisor [degC]
END_VAR

// 段 1｜出口预置
FC_DL_WaferThermalBudgetCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fBudgetDegCmin := 0.0; // 热预算预置零 [°C·min] / budget preset zero [degC*min]
fEquiv1000Cs := 0.0; // 等效秒数预置零 [s] / equivalent seconds preset zero [s]
xOverLimit := FALSE; // 超限位预置 FALSE（未判定前不报警） [-] / over-limit flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fTempC > -1.0E30 AND fTempC < 1.0E30) OR NOT (fDurMin > -1.0E30 AND fDurMin < 1.0E30) THEN
    RETURN; // 温度/时长任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fLimitDegCmin > -1.0E30 AND fLimitDegCmin < 1.0E30) OR NOT (fRefTempC > -1.0E30 AND fRefTempC < 1.0E30) THEN
    RETURN; // 上限/参考温度任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fTempC < 0.0 OR fDurMin < 1.0E-9 OR fLimitDegCmin <= 0.0 OR fRefTempC < 1.0E-9 THEN
    RETURN; // 温度非负闸 + 时长正域闸 + 上限正域闸 + 参考温度正域闸（归一化分母） [°C, min] / positive gates
END_IF

// 段 3｜计算（归一化：Dt[°C·min] × 60 s/min ÷ T_ref[°C] = 参考温度下的等效秒数 [s]）
fBudgetDegCmin := fTempC * fDurMin; // °C × min = °C·min，单段热预算 [°C·min] / [degC] x [min] = [degC*min]
fBudgetDegCs := fBudgetDegCmin * 60.0; // (°C·min) × 60 s/min = °C·s，换算到秒口径 [°C·s] / [degC*s]
fRefDenom := fRefTempC; // 取参考温度作除数 [°C] / take the reference temperature as divisor [degC]
IF fRefDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：参考温度必须大于 1E-9 才可作除数 [°C] / denominator gate [degC]
END_IF
fEquiv1000Cs := fBudgetDegCs / fRefDenom; // °C·s ÷ °C = s，参考温度下的等效停留秒数 [s] / [degC*s] / [degC] = [s]

// 段 4｜判定与饱和
IF NOT (fBudgetDegCmin > -1.0E30 AND fBudgetDegCmin < 1.0E30) OR NOT (fEquiv1000Cs > -1.0E30 AND fEquiv1000Cs < 1.0E30) THEN
    RETURN; // 两出口非有限再拦一次 [-] / re-check both results for finiteness [-]
END_IF
xOverLimit := fBudgetDegCmin > fLimitDegCmin; // 严格大于上限为超预算，等于上限仍判合格 [°C·min] / strict compare [degC*min]

// 段 5｜出口自检
IF fBudgetDegCmin < 0.0 THEN
    RETURN; // 出口自检：热预算不得为负（负值说明温度符号错） [°C·min] / budget must not be negative [degC*min]
END_IF
FC_DL_WaferThermalBudgetCalc := fBudgetDegCmin; // 返回单段热预算 [°C·min] / return the thermal budget [degC*min]
END_FUNCTION
