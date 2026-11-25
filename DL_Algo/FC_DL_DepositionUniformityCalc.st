(*
  DL Factory R88 | FC_DL_DepositionUniformityCalc
  功能：由固定五点膜厚算均匀性 (max-min)/(2·mean)×100%，并按 3% 判合格（不用数组，逐点标量入参）
  开源溯源：无（clean-room 自研，依据公开工艺公式 膜厚均匀性式 (max-min)/(2·mean)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_DepositionUniformityCalc : REAL
VAR_INPUT
    fT1 : REAL := 100.0; // 测点 1 膜厚（中心） [nm] / thickness at site 1, centre [nm]
    fT2 : REAL := 98.0; // 测点 2 膜厚 [nm] / thickness at site 2 [nm]
    fT3 : REAL := 102.0; // 测点 3 膜厚 [nm] / thickness at site 3 [nm]
    fT4 : REAL := 99.0; // 测点 4 膜厚 [nm] / thickness at site 4 [nm]
    fT5 : REAL := 101.0; // 测点 5 膜厚 [nm] / thickness at site 5 [nm]
    fTolPct : REAL := 3.0; // 均匀性公差上限 [%] / uniformity tolerance [%]
END_VAR
VAR_OUTPUT
    fUniformityPct : REAL; // 膜厚不均匀度 [%] / thickness non uniformity [%]
    xPass : BOOL; // TRUE=不均匀度不超过公差 [-] / TRUE when within tolerance [-]
END_VAR
VAR
    fMaxT : REAL; // 五点最大膜厚 [nm] / maximum thickness [nm]
    fMinT : REAL; // 五点最小膜厚 [nm] / minimum thickness [nm]
    fMeanT : REAL; // 五点平均膜厚（除零判据） [nm] / mean thickness, the divisor [nm]
END_VAR

// 段 1｜出口预置
FC_DL_DepositionUniformityCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fUniformityPct := 0.0; // 不均匀度预置零 [%] / non uniformity preset zero [%]
xPass := FALSE; // 合格位预置 FALSE（未判定前不认合格） [-] / pass flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fT1 > -1.0E30 AND fT1 < 1.0E30) OR NOT (fT2 > -1.0E30 AND fT2 < 1.0E30) OR NOT (fT3 > -1.0E30 AND fT3 < 1.0E30) THEN
    RETURN; // 测点 1/2/3 任一非有限即拒算 [-] / any non finite thickness rejected [-]
END_IF
IF NOT (fT4 > -1.0E30 AND fT4 < 1.0E30) OR NOT (fT5 > -1.0E30 AND fT5 < 1.0E30) OR NOT (fTolPct > -1.0E30 AND fTolPct < 1.0E30) THEN
    RETURN; // 测点 4/5 与公差任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fT1 < 0.0 OR fT2 < 0.0 OR fT3 < 0.0 OR fT4 < 0.0 OR fT5 < 0.0 THEN
    RETURN; // 膜厚非负闸：负厚度无物理意义 [nm] / non negative thickness gate [nm]
END_IF
IF fTolPct <= 0.0 THEN
    RETURN; // 公差正域闸：非正公差会使判定恒不合格 [%] / positive tolerance gate [%]
END_IF

// 段 3｜计算（五点极值 + 算术平均，等价 max/min/sum 三路归约）
fMaxT := MAX(MAX(fT1, fT2), MAX(fT3, MAX(fT4, fT5))); // 三级取大得 max [nm] / nested maximum [nm]
fMinT := MIN(MIN(fT1, fT2), MIN(fT3, MIN(fT4, fT5))); // 三级取小得 min [nm] / nested minimum [nm]
fMeanT := (fT1 + fT2 + fT3 + fT4 + fT5) * 0.2; // nm × 0.2 = nm，五点算术平均（乘 0.2 替除 5） [nm] / [nm]
IF fMeanT < 1.0E-9 THEN
    RETURN; // 除法前分母闸：平均膜厚必须大于 1E-9（全零测点无意义） [nm] / denominator gate [nm]
END_IF
fUniformityPct := (fMaxT - fMinT) / (2.0 * fMeanT) * 100.0; // (nm ÷ nm) × 100 = %，极差折半归一到均值 [%] / [%]

// 段 4｜判定与饱和
IF NOT (fUniformityPct > -1.0E30 AND fUniformityPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xPass := fUniformityPct <= fTolPct; // 不均匀度不超过公差即合格（含边界） [%] / within tolerance, boundary included [%]

// 段 5｜出口自检
IF fMaxT < fMinT THEN
    RETURN; // 出口自检：极值关系被破坏说明归约链出错 [nm] / extremum order violated [nm]
END_IF
FC_DL_DepositionUniformityCalc := fUniformityPct; // 返回膜厚不均匀度 [%] / return the non uniformity [%]
END_FUNCTION
