(*
  DL Factory R84 | FC_DL_StockConsistencyCalc
  功能：由稀释前后流量浓度守恒求稀释后浓度，并输出需加清水量与绝干产量
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_StockConsistencyCalc : REAL
VAR_INPUT
    fFeedM3h : REAL := 300.0; // 浓浆进料体积流量 [m³/h] / thick stock volumetric flow [m^3/h]
    fFeedConcPct : REAL := 3.5; // 进料浓度 [%] / feed consistency [%]
    fTargetConcPct : REAL := 1.2; // 目标（稀释后）浓度 [%] / target consistency after dilution [%]
    fDensityTm3 : REAL := 1.0; // 浆料密度 [t/m³] / stock density [t/m^3]
END_VAR
VAR_OUTPUT
    fWaterM3h : REAL; // 需加清水的体积流量 [m³/h] / white water to add [m^3/h]
    fBoneDryTph : REAL; // 绝干浆产量 [t/h] / bone dry stock rate [t/h]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fOutM3h : REAL; // 稀释后总流量 [m³/h] / diluted total flow [m^3/h]
    fConcBackPct : REAL; // 回代校核浓度 [%] / back calculated consistency [%]
    xNoDil : BOOL; // 无需稀释（进料已达标或偏稀） [-] / no dilution required [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_StockConsistencyCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fWaterM3h := 0.0; // 清水量预置零 [m³/h] / water preset zero [m^3/h]
fBoneDryTph := 0.0; // 绝干产量预置零 [t/h] / bone dry rate preset zero [t/h]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fFeedM3h > -1.0E30 AND fFeedM3h < 1.0E30) OR NOT (fFeedConcPct > -1.0E30 AND fFeedConcPct < 1.0E30) OR NOT (fTargetConcPct > -1.0E30 AND fTargetConcPct < 1.0E30) OR NOT (fDensityTm3 > -1.0E30 AND fDensityTm3 < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fFeedM3h < 0.0 OR fFeedConcPct < 0.0 OR fFeedConcPct > 100.0 OR fTargetConcPct > 100.0 OR fDensityTm3 < 1.0E-9 THEN
    RETURN; // 流量/浓度/密度域闸（浓度 0~100%，密度正域） [%, t/m³] / flow, consistency and density domain gate [-]
END_IF
IF fTargetConcPct < 1.0E-9 THEN
    RETURN; // 目标浓度正域分母闸（防除零） [%] / target consistency denominator gate [%]
END_IF

// 段 3｜绝干守恒：进料绝干量不随稀释改变
fBoneDryTph := ((fFeedM3h * fFeedConcPct) / 100.0) * fDensityTm3; // m³/h × % ÷ 100 × t/m³ = t/h / [m^3/h] × [%] / 100 × [t/m^3] = [t/h]

// 段 4｜加水后总流量（守恒反解），并给清水量
fOutM3h := (fFeedM3h * fFeedConcPct) / fTargetConcPct; // m³/h × % ÷ % = m³/h（绝干量守恒） / [m^3/h] × [%] / [%] = [m^3/h]
fWaterM3h := fOutM3h - fFeedM3h; // m³/h − m³/h = m³/h / [m^3/h] minus [m^3/h] = [m^3/h]
xNoDil := fWaterM3h < 0.0; // 进料已偏稀：无需加水，仅提示 [-] / feed already thin, no dilution needed [-]
IF xNoDil THEN
    fWaterM3h := 0.0; // 清水量钳零（偏稀工况须走浓缩路径，不在本件处理） [m³/h] / clamp to zero, thickening is out of scope [m^3/h]
END_IF

// 段 5｜回代校核浓度（m³/h × % ÷ m³/h = %）
fConcBackPct := (fFeedM3h * fFeedConcPct) / (fFeedM3h + fWaterM3h); // % 回代 / back calculated consistency [%]
IF NOT (fConcBackPct > -1.0E30 AND fConcBackPct < 1.0E30) OR NOT (fBoneDryTph > -1.0E30 AND fBoneDryTph < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_StockConsistencyCalc := fConcBackPct; // 返回稀释后实际浓度 [%] / return the diluted consistency [%]
END_FUNCTION
