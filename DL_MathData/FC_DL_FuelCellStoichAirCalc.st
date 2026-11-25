(*
  DL Factory R88 | FC_DL_FuelCellStoichAirCalc
  功能：算燃料电池空气计量比 λ=实际空气质量流量/理论需求量（理论=O2 摩尔流×M_O2/0.232），λ<1.5 判偏稀
  开源溯源：无（clean-room 自研，依据公开工艺公式 电化学氧耗与空气计量比定义式 λ=m_air/m_air,st，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_FuelCellStoichAirCalc : REAL
VAR_INPUT
    fCurrentA : REAL := 300.0; // 电堆电流 I [A] / stack current [A]
    fCells : REAL := 400.0; // 串联单胞数量 n [个] / number of series cells [-]
    fAirFlowKgH : REAL := 60.0; // 实测干空气质量流量 [kg/h] / measured dry air mass flow [kg/h]
    fLambdaMin : REAL := 1.5; // 计量比合格下限（λ<1.5 判偏稀） [-] / lean threshold [-]
END_VAR
VAR_OUTPUT
    fLambda : REAL; // 空气计量比 λ [-] / air stoichiometry [-]
    xLean : BOOL; // TRUE=计量比低于下限，偏稀需加风 [-] / TRUE when the air is lean [-]
END_VAR
VAR
    fFaradayC : REAL; // 法拉第常数 F [C/mol] / faraday constant [C/mol]
    fFourF : REAL; // 分母 4F（每摩 O2 需 4 mol 电子） [C/mol] / the 4F divisor [C/mol]
    fAirTheoKgH : REAL; // 理论干空气质量流量（除零判据） [kg/h] / theoretical air flow, the divisor [kg/h]
END_VAR

// 段 1｜出口预置
FC_DL_FuelCellStoichAirCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fLambda := 0.0; // 计量比预置零 [-] / stoichiometry preset zero [-]
xLean := FALSE; // 偏稀位预置 FALSE（未判定前不报警） [-] / lean flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fCurrentA > -1.0E30 AND fCurrentA < 1.0E30) OR NOT (fCells > -1.0E30 AND fCells < 1.0E30) THEN
    RETURN; // 电流/单胞数任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fAirFlowKgH > -1.0E30 AND fAirFlowKgH < 1.0E30) OR NOT (fLambdaMin > -1.0E30 AND fLambdaMin < 1.0E30) THEN
    RETURN; // 空气流量/下限任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fCurrentA < 0.0 OR fCells < 1.0 OR fAirFlowKgH < 0.0 THEN
    RETURN; // 电流非负闸 + 单胞下限闸 + 空气流量非负闸 [A, 个, kg/h] / non negative gates
END_IF
IF fLambdaMin <= 0.0 THEN
    RETURN; // 下限正域闸：非正下限会使判据恒假 [-] / positive threshold gate [-]
END_IF

// 段 3｜计算（I→O2 mol/s→空气质量→kg/h 链路，逐项量纲见行尾注释）
fFaradayC := 96485.0; // 法拉第常数装入 [C/mol] / load the faraday constant [C/mol]
fFourF := 4.0 * fFaradayC; // 4 × C/mol = C/mol，每摩 O2 需 4 摩电子 [C/mol] / [C/mol]
IF fFourF < 1.0E-9 THEN
    RETURN; // 除法前分母闸：4F 必须大于 1E-9 才可作除数 [C/mol] / denominator gate [C/mol]
END_IF
fAirTheoKgH := (fCurrentA * fCells / fFourF) * 32.0 * 0.001 / 0.232 * 3600.0; // (mol/s)×32 g/mol×0.001 kg/g÷0.232(空气质量分数)×3600 s/h = kg/h [kg/h] / [kg/h]
IF fAirTheoKgH < 1.0E-9 THEN
    RETURN; // 除法前分母闸：理论空气量必须大于 1E-9（零电流时无意义） [kg/h] / denominator gate [kg/h]
END_IF
fLambda := fAirFlowKgH / fAirTheoKgH; // (kg/h) ÷ (kg/h) = 无量纲，计量比 λ [-] / dimensionless stoichiometry [-]

// 段 4｜判定与饱和
IF NOT (fLambda > -1.0E30 AND fLambda < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xLean := fLambda < fLambdaMin; // 严格小于下限判偏稀，等于下限仍判合格 [-] / strict compare against the threshold [-]

// 段 5｜出口自检
IF fLambda < 1.0 THEN
    xLean := TRUE; // 出口自检：λ<1 已属缺氧区（低于电化学计量），强制置偏稀 [-] / below unity is oxygen starved [-]
END_IF
FC_DL_FuelCellStoichAirCalc := fLambda; // 返回空气计量比 λ [-] / return the air stoichiometry [-]
END_FUNCTION
