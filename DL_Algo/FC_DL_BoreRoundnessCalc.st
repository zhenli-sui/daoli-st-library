(*
  DL Factory R88 | FC_DL_BoreRoundnessCalc
  功能：由固定四测点半径读数算孔圆度 (rmax-rmin)，并按 fTolUm 判合格（不用数组，逐测点标量入参）
  开源溯源：无（clean-room 自研，依据公开工艺公式 圆度最小区域近似式 R=max(r)-min(r)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_BoreRoundnessCalc : REAL
VAR_INPUT
    fR0Um : REAL := 50.0; // 测点 0 半径偏差读数（相对名义半径） [µm] / radius reading at point 0 [um]
    fR1Um : REAL := 52.0; // 测点 1 半径偏差读数 [µm] / radius reading at point 1 [um]
    fR2Um : REAL := 49.0; // 测点 2 半径偏差读数 [µm] / radius reading at point 2 [um]
    fR3Um : REAL := 51.0; // 测点 3 半径偏差读数 [µm] / radius reading at point 3 [um]
    fTolUm : REAL := 10.0; // 圆度公差上限 [µm] / roundness tolerance [um]
END_VAR
VAR_OUTPUT
    fRoundnessUm : REAL; // 圆度值 rmax-rmin [µm] / roundness value [um]
    xPass : BOOL; // TRUE=圆度不超过公差 [-] / TRUE when within tolerance [-]
END_VAR
VAR
    fMaxUm : REAL; // 四测点最大值 rmax [µm] / maximum radius reading [um]
    fMinUm : REAL; // 四测点最小值 rmin [µm] / minimum radius reading [um]
END_VAR

// 段 1｜出口预置
FC_DL_BoreRoundnessCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fRoundnessUm := 0.0; // 圆度预置零 [µm] / roundness preset zero [um]
xPass := FALSE; // 合格位预置 FALSE（未判定前不认合格） [-] / pass flag preset false [-]
fMaxUm := 0.0; // 最大值预置零 [µm] / maximum preset zero [um]
fMinUm := 0.0; // 最小值预置零 [µm] / minimum preset zero [um]

// 段 2｜非有限拦截 + 域闸
IF NOT (fR0Um > -1.0E30 AND fR0Um < 1.0E30) OR NOT (fR1Um > -1.0E30 AND fR1Um < 1.0E30) THEN
    RETURN; // 测点 0/1 任一非有限即拒算 [-] / any non finite reading rejected [-]
END_IF
IF NOT (fR2Um > -1.0E30 AND fR2Um < 1.0E30) OR NOT (fR3Um > -1.0E30 AND fR3Um < 1.0E30) THEN
    RETURN; // 测点 2/3 任一非有限即拒算 [-] / any non finite reading rejected [-]
END_IF
IF NOT (fTolUm > -1.0E30 AND fTolUm < 1.0E30) THEN
    RETURN; // 公差非有限则判据静默失效，故先拦 [µm] / the tolerance must be finite [um]
END_IF
IF fTolUm <= 0.0 THEN
    RETURN; // 公差正域闸：非正公差使判定恒为不合格 [µm] / positive tolerance gate [um]
END_IF

// 段 3｜计算（四点极值法，等价 rmax-rmin 的两级 Max/Min 归约）
fMaxUm := MAX(MAX(fR0Um, fR1Um), MAX(fR2Um, fR3Um)); // 两级取大得 rmax [µm] / two stage maximum [um]
fMinUm := MIN(MIN(fR0Um, fR1Um), MIN(fR2Um, fR3Um)); // 两级取小得 rmin [µm] / two stage minimum [um]
fRoundnessUm := fMaxUm - fMinUm; // µm - µm = µm，圆度=rmax-rmin [µm] / [um] / [um] = [um]

// 段 4｜判定与饱和
IF NOT (fRoundnessUm > -1.0E30 AND fRoundnessUm < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xPass := fRoundnessUm <= fTolUm; // 圆度不超过公差即合格（含边界） [µm] / within tolerance, boundary included [um]

// 段 5｜出口自检
IF fRoundnessUm < 0.0 THEN
    RETURN; // 出口自检：圆度不得为负（负值说明极值归约出错） [µm] / roundness must not be negative [um]
END_IF
FC_DL_BoreRoundnessCalc := fRoundnessUm; // 返回圆度值 [µm] / return the roundness value [um]
END_FUNCTION
