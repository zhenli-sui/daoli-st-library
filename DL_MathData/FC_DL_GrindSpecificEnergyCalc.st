(*
  DL Factory R88 | FC_DL_GrindSpecificEnergyCalc
  功能：算比磨削能 u=P/Qw，其中 Qw=ae·vf·b（mm³/s），功率 kW 按 ×1000 换 W，超 60 J/mm³ 提示
  开源溯源：无（clean-room 自研，依据公开工艺公式 比磨削能定义式 u=P/Qw，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GrindSpecificEnergyCalc : REAL
VAR_INPUT
    fPowerKW : REAL := 5.0; // 磨削净功率 P（扣除空载） [kW] / net grinding power [kW]
    fAeMm : REAL := 0.02; // 径向切深 ae [mm] / radial depth of cut [mm]
    fVfMmPerS : REAL := 30.0; // 工件进给速度 vf [mm/s] / workpiece feed speed [mm/s]
    fWidthMm : REAL := 20.0; // 磨削接触宽度 b [mm] / grinding contact width [mm]
    fHighLimitJPerMm3 : REAL := 60.0; // 比能偏高阈值（烧伤风险提示） [J/mm³] / high specific energy limit [J/mm^3]
END_VAR
VAR_OUTPUT
    fEnergyJPerMm3 : REAL; // 比磨削能 u [J/mm³] / specific grinding energy [J/mm^3]
    xHigh : BOOL; // TRUE=比能高于阈值，存在烧伤风险 [-] / TRUE when above the limit [-]
END_VAR
VAR
    fPowerW : REAL; // 功率换算为 W [W] / power in watts [W]
    fQwMm3PerS : REAL; // 材料去除率 Qw（除零判据） [mm³/s] / material removal rate, the divisor [mm^3/s]
END_VAR

// 段 1｜出口预置
FC_DL_GrindSpecificEnergyCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fEnergyJPerMm3 := 0.0; // 比能预置零 [J/mm³] / specific energy preset zero [J/mm^3]
xHigh := FALSE; // 偏高位预置 FALSE（未判定前不报警） [-] / high flag preset false [-]
fPowerW := 0.0; // 功率 W 值预置零 [W] / power in watts preset zero [W]
fQwMm3PerS := 0.0; // 去除率预置零 [mm³/s] / removal rate preset zero [mm^3/s]

// 段 2｜非有限拦截 + 域闸
IF NOT (fPowerKW > -1.0E30 AND fPowerKW < 1.0E30) OR NOT (fAeMm > -1.0E30 AND fAeMm < 1.0E30) THEN
    RETURN; // 功率/切深任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fVfMmPerS > -1.0E30 AND fVfMmPerS < 1.0E30) OR NOT (fWidthMm > -1.0E30 AND fWidthMm < 1.0E30) THEN
    RETURN; // 进给速度/接触宽度任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fHighLimitJPerMm3 > -1.0E30 AND fHighLimitJPerMm3 < 1.0E30) THEN
    RETURN; // 阈值非有限则偏高判据失效，故先拦 [J/mm³] / the limit must be finite [J/mm^3]
END_IF
IF fPowerKW < 0.0 OR fAeMm < 0.0 OR fVfMmPerS < 0.0 OR fWidthMm < 1.0E-9 THEN
    RETURN; // 功率/切深/进给非负闸 + 宽度正域闸（分母不得为零） [kW, mm] / non negative terms and positive width
END_IF
IF fHighLimitJPerMm3 <= 0.0 THEN
    RETURN; // 阈值正域闸：非正阈值会使提示恒真 [J/mm³] / positive limit gate [J/mm^3]
END_IF

// 段 3｜计算
fPowerW := fPowerKW * 1000.0; // kW × 1000 W/kW = W，量纲换算 [W] / [kW] x [W/kW] = [W]
fQwMm3PerS := fAeMm * fVfMmPerS * fWidthMm; // mm × (mm/s) × mm = mm³/s，Qw=ae·vf·b / [mm^3/s]
IF fQwMm3PerS < 1.0E-9 THEN
    RETURN; // 除法前分母闸：去除率须大于 1E-9（零切深会除零） [mm³/s] / denominator gate [mm^3/s]
END_IF
fEnergyJPerMm3 := fPowerW / fQwMm3PerS; // (J/s) ÷ (mm³/s) = J/mm³，即比磨削能 [J/mm³] / [J/mm^3]

// 段 4｜判定与饱和
IF NOT (fEnergyJPerMm3 > -1.0E30 AND fEnergyJPerMm3 < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xHigh := fEnergyJPerMm3 > fHighLimitJPerMm3; // 严格大于阈值为偏高，等于阈值仍判正常 [J/mm³] / strict compare [J/mm^3]

// 段 5｜出口自检
IF fEnergyJPerMm3 < 0.0 THEN
    RETURN; // 出口自检：比能不得为负（负值说明功率符号错） [J/mm³] / energy must not be negative [J/mm^3]
END_IF
FC_DL_GrindSpecificEnergyCalc := fEnergyJPerMm3; // 返回比磨削能 [J/mm³] / return the specific energy [J/mm^3]
END_FUNCTION
