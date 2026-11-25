(*
  DL Factory R88 | FC_DL_SurfaceRoughnessRzFromRaCalc
  功能：由 Ra 按经验因子换算 Rz（Rz≈k·Ra，车/磨区间 k=3.5~5.0），并判定因子是否落在经验带内
  开源溯源：无（clean-room 自研，依据公开工艺公式 Ra-Rz 经验换算式 Rz≈(3.5~5.0)·Ra，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_SurfaceRoughnessRzFromRaCalc : REAL
VAR_INPUT
    fRaUm : REAL := 1.6; // 算术平均偏差 Ra [µm] / arithmetic mean roughness Ra [um]
    fProcessFactor : REAL := 4.0; // 工艺经验因子 k（车/磨 3.5~5.0，非标准定义） [-] / empirical process factor [-]
    fMinFactor : REAL := 3.5; // 经验带下限 [-] / lower empirical band [-]
    fMaxFactor : REAL := 5.0; // 经验带上限 [-] / upper empirical band [-]
END_VAR
VAR_OUTPUT
    fRzUm : REAL; // 十点高度 Rz 估计值 [µm] / estimated Rz [um]
    xInBand : BOOL; // TRUE=所用因子落在经验带内，估计可信 [-] / TRUE when the factor is inside the band [-]
END_VAR
VAR
    fFactorLo : REAL; // 实际参与计算的因子下限（缓存） [-] / lower factor bound in use [-]
    fFactorHi : REAL; // 实际参与计算的因子上限（缓存） [-] / upper factor bound in use [-]
END_VAR

// 段 1｜出口预置
FC_DL_SurfaceRoughnessRzFromRaCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fRzUm := 0.0; // Rz 估计值预置零 [µm] / Rz estimate preset zero [um]
xInBand := FALSE; // 带宽位预置 FALSE（未判定前不认可信） [-] / band flag preset false [-]
fFactorLo := 0.0; // 因子下限缓存预置零 [-] / lower factor preset zero [-]
fFactorHi := 0.0; // 因子上限缓存预置零 [-] / upper factor preset zero [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fRaUm > -1.0E30 AND fRaUm < 1.0E30) OR NOT (fProcessFactor > -1.0E30 AND fProcessFactor < 1.0E30) THEN
    RETURN; // Ra/工艺因子任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fMinFactor > -1.0E30 AND fMinFactor < 1.0E30) OR NOT (fMaxFactor > -1.0E30 AND fMaxFactor < 1.0E30) THEN
    RETURN; // 经验带上下限任一非有限则判据静默失效，故先拦 [-] / band limits must be finite [-]
END_IF
IF fRaUm < 0.0 THEN
    RETURN; // Ra 非负闸：粗糙度不得为负 [µm] / non negative Ra gate [um]
END_IF
IF fProcessFactor < 1.0 OR fProcessFactor > 10.0 THEN
    RETURN; // 因子工程域闸 (1,10)：越界则换算关系不再成立 [-] / factor domain gate [-]
END_IF
IF fMinFactor <= 0.0 OR fMaxFactor <= fMinFactor THEN
    RETURN; // 经验带自洽闸：下限须为正、上限须严格大于下限 [-] / band consistency gate [-]
END_IF

// 段 3｜计算（经验换算，不是标准定义：Rz 与 Ra 无通用解析关系）
fFactorLo := fMinFactor; // 取经验带下限参与判定 [-] / take the lower factor bound [-]
fFactorHi := fMaxFactor; // 取经验带上限参与判定 [-] / take the upper factor bound [-]
fRzUm := fProcessFactor * fRaUm; // 无量纲 × µm = µm，Rz≈k·Ra [µm] / [-] x [um] = [um]

// 段 4｜判定与饱和
IF NOT (fRzUm > -1.0E30 AND fRzUm < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次（防溢出成 Inf） [µm] / re-check the result for finiteness [um]
END_IF
xInBand := (fProcessFactor >= fFactorLo) AND (fProcessFactor <= fFactorHi); // 因子与经验带双侧直比 [-] / factor against the empirical band [-]

// 段 5｜出口自检
IF fRzUm < fRaUm THEN
    RETURN; // 出口自检：Rz 不应小于 Ra（因子域闸已保证 k>1，否则换算链被破坏） [µm] / Rz must not fall below Ra [um]
END_IF
FC_DL_SurfaceRoughnessRzFromRaCalc := fRzUm; // 返回 Rz 估计值 [µm] / return the estimated Rz [um]
END_FUNCTION
