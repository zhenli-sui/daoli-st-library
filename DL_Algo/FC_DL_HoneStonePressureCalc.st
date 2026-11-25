(*
  DL Factory R88 | FC_DL_HoneStonePressureCalc
  功能：算珩磨油石比压 p=F/(n·L·W)，N/mm² 按 ×10 换算为 bar，并按工艺带宽判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 接触比压定义式 p=F/A，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_HoneStonePressureCalc : REAL
VAR_INPUT
    fForceN : REAL := 1200.0; // 油石总法向压紧力 F [N] / total normal stone force [N]
    nStoneCount : DINT := 6; // 油石条数 n（整数入参，无 NaN 可能） [条] / number of stones [-]
    fStoneLengthMm : REAL := 100.0; // 单条油石接触长度 L [mm] / stone contact length [mm]
    fStoneWidthMm : REAL := 10.0; // 单条油石接触宽度 W [mm] / stone contact width [mm]
    fMinBar : REAL := 2.0; // 比压允许下限（工艺带宽） [bar] / lower pressure band [bar]
    fMaxBar : REAL := 8.0; // 比压允许上限（工艺带宽） [bar] / upper pressure band [bar]
END_VAR
VAR_OUTPUT
    fPressBar : REAL; // 油石比压 p（N/mm²×10） [bar] / stone specific pressure [bar]
    xInBand : BOOL; // TRUE=比压落在允许带宽内 [-] / TRUE when inside the band [-]
END_VAR
VAR
    fStones : REAL; // 油石条数实数化 [-] / stone count as real [-]
    fAreaTotalMm2 : REAL; // 总接触面积 n·L·W（除零判据） [mm²] / total contact area, the divisor [mm^2]
    fPressMpa : REAL; // 比压 N/mm²（数值等同 MPa） [N/mm²] / specific pressure [N/mm^2]
END_VAR

// 段 1｜出口预置
FC_DL_HoneStonePressureCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fPressBar := 0.0; // 比压预置零 [bar] / pressure preset zero [bar]
xInBand := FALSE; // 带宽位预置 FALSE（未判定前不认合格） [-] / band flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fForceN > -1.0E30 AND fForceN < 1.0E30) OR NOT (fStoneLengthMm > -1.0E30 AND fStoneLengthMm < 1.0E30) OR NOT (fStoneWidthMm > -1.0E30 AND fStoneWidthMm < 1.0E30) THEN
    RETURN; // 压紧力/油石长宽任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fMinBar > -1.0E30 AND fMinBar < 1.0E30) OR NOT (fMaxBar > -1.0E30 AND fMaxBar < 1.0E30) THEN
    RETURN; // 带宽上下限任一非有限则判据静默失效，故先拦 [bar] / band limits must be finite [bar]
END_IF
IF fForceN < 0.0 OR fStoneLengthMm < 1.0E-9 OR fStoneWidthMm < 1.0E-9 THEN
    RETURN; // 力非负闸 + 长宽正域闸（分母不得为零） [N, mm] / non negative force and positive geometry [N, mm]
END_IF
IF nStoneCount < 1 OR fMinBar <= 0.0 OR fMaxBar <= fMinBar THEN
    RETURN; // 条数下限闸 + 带宽自洽闸（整数域无 NaN 可能） [条, bar] / count and band gates
END_IF

// 段 3｜计算
fStones := DINT_TO_REAL(nStoneCount); // DINT→REAL 标准转换函数（R10） [-] / standard conversion (R10) [-]
fAreaTotalMm2 := fStones * fStoneLengthMm * fStoneWidthMm; // 无量纲 × mm × mm = mm²，A=n·L·W [mm²] / [mm^2]
IF fAreaTotalMm2 < 1.0E-9 THEN
    RETURN; // 除法前分母闸：总面积必须大于 1E-9 才可作除数 [mm²] / denominator gate [mm^2]
END_IF
fPressMpa := fForceN / fAreaTotalMm2; // N ÷ mm² = N/mm²（数值等同 MPa） [N/mm²] / [N] / [mm^2] = [N/mm^2]
fPressBar := fPressMpa * 10.0; // 1 N/mm² = 1 MPa = 10 bar，故 ×10 换算 [bar] / 1 MPa equals 10 bar [bar]

// 段 4｜判定与饱和
IF NOT (fPressBar > -1.0E30 AND fPressBar < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xInBand := (fPressBar >= fMinBar) AND (fPressBar <= fMaxBar); // 双侧闭区间直比 [bar] / closed two sided band compare [bar]

// 段 5｜出口自检
IF fPressBar < 0.0 THEN
    RETURN; // 出口自检：比压不得为负（负值说明力符号错） [bar] / pressure must not be negative [bar]
END_IF
FC_DL_HoneStonePressureCalc := fPressBar; // 返回油石比压 [bar] / return the stone specific pressure [bar]
END_FUNCTION
