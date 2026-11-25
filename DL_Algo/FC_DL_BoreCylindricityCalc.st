(*
  DL Factory R88 | FC_DL_BoreCylindricityCalc
  功能：由两截面各四测点半径读数算圆柱度=两截面圆度取大 + 母线直线度近似，并按公差判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式 圆柱度=最大圆度与母线直线度合成，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_BoreCylindricityCalc : REAL
VAR_INPUT
    fR0Um : REAL := 50.0; // 截面 1 测点 0 半径偏差 [µm] / section 1 radius reading 0 [um]
    fR1Um : REAL := 52.0; // 截面 1 测点 1 半径偏差 [µm] / section 1 radius reading 1 [um]
    fR2Um : REAL := 49.0; // 截面 1 测点 2 半径偏差 [µm] / section 1 radius reading 2 [um]
    fR3Um : REAL := 51.0; // 截面 1 测点 3 半径偏差 [µm] / section 1 radius reading 3 [um]
    fS0Um : REAL := 53.0; // 截面 2 测点 0 半径偏差 [µm] / section 2 radius reading 0 [um]
    fS1Um : REAL := 48.0; // 截面 2 测点 1 半径偏差 [µm] / section 2 radius reading 1 [um]
    fS2Um : REAL := 55.0; // 截面 2 测点 2 半径偏差 [µm] / section 2 radius reading 2 [um]
    fS3Um : REAL := 50.0; // 截面 2 测点 3 半径偏差 [µm] / section 2 radius reading 3 [um]
    fAxisDevUm : REAL := 3.0; // 母线直线度偏差读数（轴向最大偏离） [µm] / axis straightness deviation [um]
    fTolUm : REAL := 15.0; // 圆柱度公差上限 [µm] / cylindricity tolerance [um]
END_VAR
VAR_OUTPUT
    fCylUm : REAL; // 圆柱度值（截面圆度取大 + 直线度） [µm] / cylindricity value [um]
    xPass : BOOL; // TRUE=圆柱度不超过公差 [-] / TRUE when within tolerance [-]
END_VAR
VAR
    fRound1Um : REAL; // 截面 1 圆度 [µm] / roundness of section 1 [um]
    fRound2Um : REAL; // 截面 2 圆度 [µm] / roundness of section 2 [um]
    fMaxRoundUm : REAL; // 两截面圆度取大值 [µm] / larger roundness of the two sections [um]
END_VAR

// 段 1｜出口预置
FC_DL_BoreCylindricityCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fCylUm := 0.0; // 圆柱度预置零 [µm] / cylindricity preset zero [um]
xPass := FALSE; // 合格位预置 FALSE（未判定前不认合格） [-] / pass flag preset false [-]
fRound1Um := 0.0; // 截面 1 圆度预置零 [µm] / section 1 roundness preset zero [um]
fRound2Um := 0.0; // 截面 2 圆度预置零 [µm] / section 2 roundness preset zero [um]
fMaxRoundUm := 0.0; // 圆度大值预置零 [µm] / larger roundness preset zero [um]

// 段 2｜非有限拦截 + 域闸
IF NOT (fR0Um > -1.0E30 AND fR0Um < 1.0E30) OR NOT (fR1Um > -1.0E30 AND fR1Um < 1.0E30) OR NOT (fR2Um > -1.0E30 AND fR2Um < 1.0E30) OR NOT (fR3Um > -1.0E30 AND fR3Um < 1.0E30) THEN
    RETURN; // 截面 1 任一测点非有限即拒算 [-] / any section 1 reading non finite rejected [-]
END_IF
IF NOT (fS0Um > -1.0E30 AND fS0Um < 1.0E30) OR NOT (fS1Um > -1.0E30 AND fS1Um < 1.0E30) OR NOT (fS2Um > -1.0E30 AND fS2Um < 1.0E30) OR NOT (fS3Um > -1.0E30 AND fS3Um < 1.0E30) THEN
    RETURN; // 截面 2 任一测点非有限即拒算 [-] / any section 2 reading non finite rejected [-]
END_IF
IF NOT (fAxisDevUm > -1.0E30 AND fAxisDevUm < 1.0E30) OR NOT (fTolUm > -1.0E30 AND fTolUm < 1.0E30) THEN
    RETURN; // 直线度/公差非有限则判据静默失效，故先拦 [µm] / straightness and tolerance must be finite [um]
END_IF
IF fTolUm <= 0.0 OR fAxisDevUm < 0.0 THEN
    RETURN; // 公差正域闸 + 直线度非负闸 [µm] / positive tolerance and non negative deviation [um]
END_IF

// 段 3｜计算
fRound1Um := MAX(MAX(fR0Um, fR1Um), MAX(fR2Um, fR3Um)) - MIN(MIN(fR0Um, fR1Um), MIN(fR2Um, fR3Um)); // µm，截面 1 极差 [µm] / section 1 spread [um]
fRound2Um := MAX(MAX(fS0Um, fS1Um), MAX(fS2Um, fS3Um)) - MIN(MIN(fS0Um, fS1Um), MIN(fS2Um, fS3Um)); // µm，截面 2 极差 [µm] / section 2 spread [um]
fMaxRoundUm := MAX(fRound1Um, fRound2Um); // 两截面圆度取大 [µm] / larger of the two roundness values [um]
fCylUm := fMaxRoundUm + fAxisDevUm; // µm + µm = µm，圆柱度合成（工程近似） [µm] / [um] + [um] = [um]

// 段 4｜判定与饱和
IF NOT (fCylUm > -1.0E30 AND fCylUm < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xPass := fCylUm <= fTolUm; // 圆柱度不超过公差即合格（含边界） [µm] / within tolerance, boundary included [um]

// 段 5｜出口自检
IF fCylUm < fMaxRoundUm THEN
    RETURN; // 出口自检：合成值不得小于任一截面圆度（说明合成链被破坏） [µm] / synthetic value must not fall below [um]
END_IF
FC_DL_BoreCylindricityCalc := fCylUm; // 返回圆柱度值 [µm] / return the cylindricity value [um]
END_FUNCTION
