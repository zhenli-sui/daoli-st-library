(*
  DL Factory R88 | FC_DL_FilmSheetResistanceCalc
  功能：由电阻率与膜厚算方块电阻 Rs=ρ/t（厚度 nm 按 ÷1e7 换算 cm），并按带宽判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 方块电阻定义式 Rs=ρ/t，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_FilmSheetResistanceCalc : REAL
VAR_INPUT
    fResistivityOhmCm : REAL := 1.0E-4; // 薄膜电阻率 ρ [Ω·cm] / film resistivity [ohm*cm]
    fThkNm : REAL := 500.0; // 薄膜厚度 t [nm] / film thickness [nm]
    fMinOhmSq : REAL := 0.1; // 方块电阻允许下限（工艺带宽） [Ω/□] / lower sheet resistance band [ohm/sq]
    fMaxOhmSq : REAL := 100.0; // 方块电阻允许上限（工艺带宽） [Ω/□] / upper sheet resistance band [ohm/sq]
END_VAR
VAR_OUTPUT
    fSheetOhmSq : REAL; // 方块电阻 Rs [Ω/□] / sheet resistance [ohm/sq]
    xInBand : BOOL; // TRUE=方块电阻落在允许带宽内 [-] / TRUE when inside the band [-]
END_VAR
VAR
    fThkCm : REAL; // 厚度换算为 cm（除零判据） [cm] / thickness in centimetres, the divisor [cm]
    fNmToCm : REAL; // nm→cm 换算因数 1e-7 [cm/nm] / conversion factor from nm to cm [cm/nm]
END_VAR

// 段 1｜出口预置
FC_DL_FilmSheetResistanceCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fSheetOhmSq := 0.0; // 方块电阻预置零 [Ω/□] / sheet resistance preset zero [ohm/sq]
xInBand := FALSE; // 带宽位预置 FALSE（未判定前不认合格） [-] / band flag preset false [-]
fThkCm := 0.0; // 厚度 cm 值预置零 [cm] / thickness preset zero [cm]
fNmToCm := 0.0; // 换算因数预置零 [cm/nm] / conversion factor preset zero [cm/nm]

// 段 2｜非有限拦截 + 域闸
IF NOT (fResistivityOhmCm > -1.0E30 AND fResistivityOhmCm < 1.0E30) OR NOT (fThkNm > -1.0E30 AND fThkNm < 1.0E30) THEN
    RETURN; // 电阻率/膜厚任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fMinOhmSq > -1.0E30 AND fMinOhmSq < 1.0E30) OR NOT (fMaxOhmSq > -1.0E30 AND fMaxOhmSq < 1.0E30) THEN
    RETURN; // 带宽上下限任一非有限则判据静默失效，故先拦 [Ω/□] / band limits must be finite [ohm/sq]
END_IF
IF fResistivityOhmCm < 1.0E-9 THEN
    RETURN; // 电阻率正域闸：须大于 1E-9（防零电阻率使结果恒零） [Ω·cm] / positive resistivity gate [ohm*cm]
END_IF
IF fThkNm < 1.0E-9 THEN
    RETURN; // 膜厚正域闸（同时是分母，防除零） [nm] / positive thickness, also the divisor [nm]
END_IF
IF fMinOhmSq <= 0.0 OR fMaxOhmSq <= fMinOhmSq THEN
    RETURN; // 带宽自洽闸：下限须为正、上限须严格大于下限 [Ω/□] / band consistency gate [ohm/sq]
END_IF

// 段 3｜计算
fNmToCm := 1.0E-7; // 1 nm = 1e-7 cm，换算因数装入 [cm/nm] / nm to cm factor [cm/nm]
fThkCm := fThkNm * fNmToCm; // nm × (cm/nm) = cm，厚度换算（等价 ÷1e7） [cm] / [nm] x [cm/nm] = [cm]
IF fThkCm < 1.0E-9 THEN
    RETURN; // 除法前分母闸：厚度 cm 值必须大于 1E-9 才可作除数 [cm] / denominator gate [cm]
END_IF
fSheetOhmSq := fResistivityOhmCm / fThkCm; // (Ω·cm) ÷ cm = Ω/□，方块电阻 [Ω/□] / [ohm*cm] / [cm] = [ohm/sq]

// 段 4｜判定与饱和
IF NOT (fSheetOhmSq > -1.0E30 AND fSheetOhmSq < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次（防溢出成 Inf） [Ω/□] / re-check the result for finiteness [ohm/sq]
END_IF
xInBand := (fSheetOhmSq >= fMinOhmSq) AND (fSheetOhmSq <= fMaxOhmSq); // 双侧闭区间直比 [Ω/□] / closed two sided band compare [ohm/sq]

// 段 5｜出口自检
IF fSheetOhmSq < 0.0 THEN
    RETURN; // 出口自检：方块电阻不得为负（负值说明电阻率符号错） [Ω/□] / must not be negative [ohm/sq]
END_IF
FC_DL_FilmSheetResistanceCalc := fSheetOhmSq; // 返回方块电阻 [Ω/□] / return the sheet resistance [ohm/sq]
END_FUNCTION
