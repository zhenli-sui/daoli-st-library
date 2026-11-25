(*
  DL Factory R88 | FC_DL_FuelCellWaterBalanceCalc
  功能：由法拉第定律算产水速率 m=I·n/(2F)·M_H2O，与排气携水量相减得净水量（正=积液风险）
  开源溯源：无（clean-room 自研，依据公开工艺公式 电化学产水率式 m=n·I·M/(2F)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_FuelCellWaterBalanceCalc : REAL
VAR_INPUT
    fCurrentA : REAL := 300.0; // 电堆电流 I [A] / stack current [A]
    fCells : REAL := 400.0; // 串联单胞数量 n [个] / number of series cells [-]
    fExhaustWaterKgH : REAL := 30.0; // 排气实际携水质量流量（实测折算） [kg/h] / water leaving with the exhaust [kg/h]
    fFloodThrKgH : REAL := 0.0; // 积液风险判据阈值（净水量超过即报警） [kg/h] / flooding threshold [kg/h]
END_VAR
VAR_OUTPUT
    fWaterNetKgH : REAL; // 净水量（产水-携水，正=积液风险） [kg/h] / net water, positive means flooding risk [kg/h]
    xFloodRisk : BOOL; // TRUE=净水量超过阈值，存在积液风险 [-] / TRUE when flooding risk exists [-]
END_VAR
VAR
    fFaradayC : REAL; // 法拉第常数 F [C/mol] / faraday constant [C/mol]
    fTwoF : REAL; // 分母 2F（每摩 H2O 需 2 mol 电子） [C/mol] / the 2F divisor [C/mol]
    fWaterMolPerS : REAL; // 产水摩尔流率 [mol/s] / water molar rate [mol/s]
    fProdKgH : REAL; // 产水质量流量 [kg/h] / produced water flow [kg/h]
END_VAR

// 段 1｜出口预置
FC_DL_FuelCellWaterBalanceCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fWaterNetKgH := 0.0; // 净水量预置零 [kg/h] / net water preset zero [kg/h]
xFloodRisk := FALSE; // 积液风险位预置 FALSE（未判定前不报警） [-] / risk flag preset false [-]
fFaradayC := 96485.0; // 法拉第常数装入 [C/mol] / load the faraday constant [C/mol]
fTwoF := 0.0; // 分母预置零 [C/mol] / divisor preset zero [C/mol]
fWaterMolPerS := 0.0; // 摩尔流率预置零 [mol/s] / molar rate preset zero [mol/s]
fProdKgH := 0.0; // 产水量预置零 [kg/h] / produced water preset zero [kg/h]

// 段 2｜非有限拦截 + 域闸
IF NOT (fCurrentA > -1.0E30 AND fCurrentA < 1.0E30) OR NOT (fCells > -1.0E30 AND fCells < 1.0E30) THEN
    RETURN; // 电流/单胞数任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fExhaustWaterKgH > -1.0E30 AND fExhaustWaterKgH < 1.0E30) OR NOT (fFloodThrKgH > -1.0E30 AND fFloodThrKgH < 1.0E30) THEN
    RETURN; // 携水量/阈值任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fCurrentA < 0.0 OR fCells < 1.0 THEN
    RETURN; // 电流非负闸 + 单胞数下限闸 [A, 个] / non negative current and at least one cell
END_IF
IF fExhaustWaterKgH < 0.0 THEN
    RETURN; // 携水量非负闸（负值表示折算错误） [kg/h] / non negative exhaust gate [kg/h]
END_IF

// 段 3｜计算（mol/s→kg/h 链路，逐项量纲见行尾注释）
fTwoF := 2.0 * fFaradayC; // 2 × C/mol = C/mol，每摩 H2O 需 2 摩电子 [C/mol] / [C/mol]
IF fTwoF < 1.0E-9 THEN
    RETURN; // 除法前分母闸：2F 必须大于 1E-9 才可作除数 [C/mol] / denominator gate [C/mol]
END_IF
fWaterMolPerS := fCurrentA * fCells / fTwoF; // A × 个 ÷ (C/mol) = mol/s，产水摩尔率 [mol/s] / [mol/s]
fProdKgH := fWaterMolPerS * 18.015 * 0.001 * 3600.0; // (mol/s)×18.015 g/mol×0.001 kg/g×3600 s/h = kg/h [kg/h] / [kg/h]
fWaterNetKgH := fProdKgH - fExhaustWaterKgH; // kg/h - kg/h = kg/h，正值为积液 [kg/h] / [kg/h] - [kg/h] = [kg/h]

// 段 4｜判定与饱和
IF NOT (fWaterNetKgH > -1.0E30 AND fWaterNetKgH < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xFloodRisk := fWaterNetKgH > fFloodThrKgH; // 净水量严格超过阈值即判积液风险 [kg/h] / strict compare [kg/h]

// 段 5｜出口自检
IF fProdKgH < 0.0 THEN
    RETURN; // 出口自检：产水量不得为负（负值说明电流符号错） [kg/h] / produced water must not be negative [kg/h]
END_IF
FC_DL_FuelCellWaterBalanceCalc := fWaterNetKgH; // 返回净水量（正=积液风险） [kg/h] / return the net water [kg/h]
END_FUNCTION
