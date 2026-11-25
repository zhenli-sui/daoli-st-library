(*
  DL Factory R88 | FC_DL_ElectrolyzerStackThermalCalc
  功能：算电堆热负荷 Q=n·I·(U_tn-U_cell)（U_tn=1.48 V），并按 ΔT=5 K、cp=4.18 kJ/(kg·K) 反算冷却液流量
  开源溯源：无（clean-room 自研，依据公开工艺公式 电解槽热平衡 Q=n·I·(U_tn-U)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_ElectrolyzerStackThermalCalc : REAL
VAR_INPUT
    fCurrentA : REAL := 10000.0; // 电堆电流 I [A] / stack current [A]
    fCells : REAL := 100.0; // 串联单槽数量 n [个] / number of series cells [-]
    fCellV : REAL := 1.65; // 实测单槽电压 U_cell [V] / measured cell voltage [V]
    fThermoneutralV : REAL := 1.48; // HHV 热中性电压 U_tn [V] / thermoneutral voltage [V]
    fCoolantDeltaTK : REAL := 5.0; // 冷却液进出口温差 ΔT [K] / coolant temperature rise [K]
    fCpKjPerKgK : REAL := 4.18; // 冷却液比热容 cp（水基冷却液） [kJ/(kg·K)] / coolant specific heat [kJ/(kg*K)]
    fLimitKW : REAL := 200.0; // 热负荷报警上限（超限需加大冷却） [kW] / heat load alarm limit [kW]
END_VAR
VAR_OUTPUT
    fHeatKW : REAL; // 电堆热负荷 Q [kW] / stack heat load [kW]
    fCoolantFlowLpm : REAL; // 所需冷却液体积流量（ρ≈1 kg/L） [L/min] / required coolant flow [L/min]
    xOverHeat : BOOL; // TRUE=热负荷超过报警上限 [-] / TRUE when above the alarm limit [-]
END_VAR
VAR
    fHeatW : REAL; // 热负荷 W 值 [W] / heat load in watts [W]
    fDenomWKg : REAL; // 分母 cp·ΔT（换算为 W 口径，除零判据） [W/(kg/s)] / denominator, the divisor [W/(kg/s)]
    fMassFlowKgS : REAL; // 冷却液质量流量 [kg/s] / coolant mass flow [kg/s]
END_VAR

// 段 1｜出口预置
FC_DL_ElectrolyzerStackThermalCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fHeatKW := 0.0; // 热负荷预置零 [kW] / heat load preset zero [kW]
fCoolantFlowLpm := 0.0; // 冷却流量预置零 [L/min] / coolant flow preset zero [L/min]
xOverHeat := FALSE; // 超热位预置 FALSE（未判定前不报警） [-] / over-heat flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fCurrentA > -1.0E30 AND fCurrentA < 1.0E30) OR NOT (fCells > -1.0E30 AND fCells < 1.0E30) OR NOT (fCellV > -1.0E30 AND fCellV < 1.0E30) THEN
    RETURN; // 电流/槽数/单槽电压任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fThermoneutralV > -1.0E30 AND fThermoneutralV < 1.0E30) OR NOT (fCoolantDeltaTK > -1.0E30 AND fCoolantDeltaTK < 1.0E30) THEN
    RETURN; // 热中性电压/温差任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fCpKjPerKgK > -1.0E30 AND fCpKjPerKgK < 1.0E30) OR NOT (fLimitKW > -1.0E30 AND fLimitKW < 1.0E30) THEN
    RETURN; // 比热/报警上限任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fCurrentA < 0.0 OR fCells < 1.0 OR fCellV <= 0.0 OR fThermoneutralV <= 0.0 OR fLimitKW <= 0.0 THEN
    RETURN; // 电流非负闸 + 槽数下限闸 + 两电压正域闸 + 上限正域闸 [A, 个, V] / value gates
END_IF
IF fCoolantDeltaTK < 1.0E-9 OR fCpKjPerKgK < 1.0E-9 THEN
    RETURN; // 冷却参数正域闸：两者同为分母因子，须大于 1E-9 [K, kJ/(kg·K)] / coolant gates
END_IF

// 段 3｜计算（R88 修正：Q=n·I·(U_cell-U_tn)，U_cell>U_tn 时为正=产热，冷却侧才有正流量需求）
fHeatW := fCells * fCurrentA * (fCellV - fThermoneutralV); // 个 × A × V = W（J/s），热负荷 [W] / [-] x [A] x [V] = [W]
fHeatKW := fHeatW * 0.001; // W × 0.001 kW/W = kW，量纲换算 [kW] / [W] x [kW/W] = [kW]

// 段 4｜判定与饱和（U_cell<=U_tn 时 Q<=0，无净产热：冷却流量保持段 1 的 0，不取反向）
IF fHeatW >= 1.0E-9 THEN
    fDenomWKg := fCpKjPerKgK * 1000.0 * fCoolantDeltaTK; // kJ/(kg·K) × 1000 J/kJ × K = W/(kg/s)，分母 [W/(kg/s)] / [W/(kg/s)]
    IF fDenomWKg < 1.0E-9 THEN RETURN; END_IF // 除法前分母闸：cp·ΔT 须大于 1E-9（段 2 已拦，此处双保险） [W/(kg/s)] / gate
    fMassFlowKgS := fHeatW / fDenomWKg; // W ÷ (W/(kg/s)) = kg/s，质量流量 [kg/s] / [kg/s]
    fCoolantFlowLpm := fMassFlowKgS * 60.0; // (kg/s) × 60 s/min ÷ (1 kg/L) = L/min，ρ≈1 处理 [L/min] / [L/min]
END_IF
xOverHeat := fHeatKW > fLimitKW; // 严格大于上限为超热，等于上限仍判正常 [kW] / strict compare [kW]

// 段 5｜出口自检
IF NOT (fHeatKW > -1.0E30 AND fHeatKW < 1.0E30) OR NOT (fCoolantFlowLpm > -1.0E30 AND fCoolantFlowLpm < 1.0E30) THEN
    RETURN; // 出口自检：两出口非有限即退回哨兵 [-] / exit self-check on finiteness [-]
END_IF
FC_DL_ElectrolyzerStackThermalCalc := fHeatKW; // 返回电堆热负荷 [kW] / return the stack heat load [kW]
END_FUNCTION