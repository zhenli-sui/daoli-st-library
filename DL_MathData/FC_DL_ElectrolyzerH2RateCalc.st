(*
  DL Factory R88 | FC_DL_ElectrolyzerH2RateCalc
  功能：法拉第定律算电解槽产氢体积流量 V_H2=n·I·η_F/(2F)·Vm，并给出电流密度（按单槽活性面积）
  开源溯源：无（clean-room 自研，依据公开工艺公式 法拉第电解定律 V=n·I·η/(2F)·Vm，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_ElectrolyzerH2RateCalc : REAL
VAR_INPUT
    fCurrentA : REAL := 10000.0; // 电解电源电流 I（整堆串联电流，各槽相同） [A] / stack current [A]
    fCells : REAL := 100.0; // 串联电解槽（单胞）数量 n [个] / number of series cells [-]
    fFaradEff : REAL := 0.98; // 法拉第效率 η_F（0~1，含气体交叉损失） [-] / faradaic efficiency [-]
    fCellAreaCm2 : REAL := 1000.0; // 单槽活性面积 A [cm²] / single cell active area [cm^2]
END_VAR
VAR_OUTPUT
    fH2Nm3h : REAL; // 标准状态产氢体积流量 [Nm³/h] / hydrogen flow at standard conditions [Nm^3/h]
    fCurrentDensityAPerCm2 : REAL; // 电流密度 i=I/A [A/cm²] / current density [A/cm^2]
END_VAR
VAR
    fFaradayC : REAL; // 法拉第常数 F（库仑/摩尔电子） [C/mol] / faraday constant [C/mol]
    fTwoF : REAL; // 分母 2F（每摩尔 H2 需 2 mol 电子） [C/mol] / the 2F divisor [C/mol]
    fMolPerS : REAL; // 产氢摩尔流率 [mol/s] / hydrogen molar flow [mol/s]
END_VAR

// 段 1｜出口预置
FC_DL_ElectrolyzerH2RateCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fH2Nm3h := 0.0; // 产氢流量预置零 [Nm³/h] / hydrogen flow preset zero [Nm^3/h]
fCurrentDensityAPerCm2 := 0.0; // 电流密度预置零 [A/cm²] / current density preset zero [A/cm^2]

// 段 2｜非有限拦截 + 域闸
IF NOT (fCurrentA > -1.0E30 AND fCurrentA < 1.0E30) OR NOT (fCells > -1.0E30 AND fCells < 1.0E30) THEN
    RETURN; // 电流/槽数任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fFaradEff > -1.0E30 AND fFaradEff < 1.0E30) OR NOT (fCellAreaCm2 > -1.0E30 AND fCellAreaCm2 < 1.0E30) THEN
    RETURN; // 法拉第效率/活性面积任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fCurrentA < 0.0 OR fCells < 1.0 THEN
    RETURN; // 电流非负闸 + 槽数下限闸（整数语义，至少 1 个单胞） [A, 个] / non negative current and one cell at least
END_IF
IF fFaradEff <= 0.0 OR fFaradEff > 1.0 OR fCellAreaCm2 < 1.0E-9 THEN
    RETURN; // 法拉第效率开区间闸 (0,1] + 活性面积正域闸（面积是分母） [-] / efficiency and area gates
END_IF

// 段 3｜计算（A→mol/s→Nm³/h 链路，逐项量纲见行尾注释）
fFaradayC := 96485.0; // 法拉第常数装入 [C/mol] / load the faraday constant [C/mol]
fTwoF := 2.0 * fFaradayC; // 2 × C/mol = C/mol，每摩 H2 需 2 摩电子 [C/mol] / [C/mol]
IF fTwoF < 1.0E-9 THEN
    RETURN; // 除法前分母闸：2F 必须大于 1E-9 才可作除数 [C/mol] / denominator gate [C/mol]
END_IF
fMolPerS := fCurrentA * fCells * fFaradEff / fTwoF; // A × 个 × 无量纲 ÷ (C/mol) = mol/s，法拉第定律 [mol/s] / [mol/s]
fH2Nm3h := fMolPerS * 22.414 * 3600.0 * 0.001; // (mol/s) × 22.414 L/mol × 3600 s/h × 0.001 m³/L = Nm³/h [Nm³/h] / [Nm^3/h]
IF fCellAreaCm2 < 1.0E-9 THEN
    RETURN; // 除法前分母闸：活性面积必须大于 1E-9 才可作除数 [cm²] / denominator gate [cm^2]
END_IF
fCurrentDensityAPerCm2 := fCurrentA / fCellAreaCm2; // A ÷ cm² = A/cm²，电流密度 [A/cm²] / [A/cm^2]

// 段 4｜判定与饱和
IF NOT (fH2Nm3h > -1.0E30 AND fH2Nm3h < 1.0E30) OR NOT (fCurrentDensityAPerCm2 > -1.0E30 AND fCurrentDensityAPerCm2 < 1.0E30) THEN
    RETURN; // 两出口非有限再拦一次 [-] / re-check both results for finiteness [-]
END_IF

// 段 5｜出口自检
IF fH2Nm3h < 0.0 THEN
    RETURN; // 出口自检：产氢流量不得为负（负值说明电流符号错） [Nm³/h] / flow must not be negative [Nm^3/h]
END_IF
FC_DL_ElectrolyzerH2RateCalc := fH2Nm3h; // 返回标准状态产氢体积流量 [Nm³/h] / return the hydrogen flow [Nm^3/h]
END_FUNCTION
