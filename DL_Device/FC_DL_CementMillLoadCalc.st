(*
  DL Factory R84 | FC_DL_CementMillLoadCalc
  功能：算管磨机填充率与循环负荷，并按目标区间判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_CementMillLoadCalc : REAL
VAR_INPUT
    fBallChargeT : REAL := 120.0; // 磨内钢球装载量 [t] / grinding ball charge mass [t]
    fMillVolM3 : REAL := 100.0; // 磨机有效容积 [m³] / effective mill volume [m^3]
    fBulkDensityTm3 : REAL := 4.6; // 钢球堆密度 [t/m³] / ball bulk density [t/m^3]
    fRejectTph : REAL := 120.0; // 选粉机返料（粗粉）量 [t/h] / separator rejects [t/h]
    fProductTph : REAL := 100.0; // 成品产量 [t/h] / finished product rate [t/h]
    fFillLoPct : REAL := 24.0; // 填充率合格下限 [%] / filling degree lower bound [%]
    fFillHiPct : REAL := 32.0; // 填充率合格上限 [%] / filling degree upper bound [%]
END_VAR
VAR_OUTPUT
    fCircLoad : REAL; // 循环负荷（返料/成品） [-] / circulating load ratio [-]
    xPass : BOOL; // 填充率落在目标区间 [-] / filling degree inside the band [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fFillPct : REAL; // 填充率中间量 [%] / filling degree intermediate [%]
    fBallVolM3 : REAL; // 钢球堆积体积 [m³] / ball bulk volume [m^3]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_CementMillLoadCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fCircLoad := 0.0; // 循环负荷预置零 [-] / circulating load preset zero [-]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fBallChargeT > -1.0E30 AND fBallChargeT < 1.0E30) OR NOT (fMillVolM3 > -1.0E30 AND fMillVolM3 < 1.0E30) OR NOT (fBulkDensityTm3 > -1.0E30 AND fBulkDensityTm3 < 1.0E30) THEN
    RETURN; // 装载量/容积/堆密度任一非有限即拒算 [-] / any non finite charge, volume or density rejected [-]
END_IF
IF NOT (fRejectTph > -1.0E30 AND fRejectTph < 1.0E30) OR NOT (fProductTph > -1.0E30 AND fProductTph < 1.0E30) OR NOT (fFillLoPct > -1.0E30 AND fFillLoPct < 1.0E30) OR NOT (fFillHiPct > -1.0E30 AND fFillHiPct < 1.0E30) THEN
    RETURN; // 返料/成品/区间任一非有限即拒算 [-] / any non finite flow or band rejected [-]
END_IF
IF fMillVolM3 < 1.0E-9 OR fBulkDensityTm3 < 1.0E-9 OR fProductTph < 1.0E-9 OR fBallChargeT < 0.0 OR fRejectTph < 0.0 THEN
    RETURN; // 容积/堆密度/产量正域分母闸（防除零） [m³, t/m³, t/h] / positive denominator gate [-]
END_IF
IF NOT (fFillLoPct < fFillHiPct) THEN
    RETURN; // 目标区间组态闸：下限必须严格小于上限 [%] / band config gate [%]
END_IF

// 段 3｜填充率 = 装载量 / (容积 × 钢球堆密度)
fBallVolM3 := fBallChargeT / fBulkDensityTm3; // t ÷ t/m³ = m³ / [t] / [t/m^3] = [m^3]
fFillPct := (fBallVolM3 / fMillVolM3) * 100.0; // m³ ÷ m³ × 100 = % / [m^3] / [m^3] × 100 = [%]
IF NOT (fFillPct > -1.0E30 AND fFillPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜循环负荷 = 返料 / 成品，与区间判定
fCircLoad := fRejectTph / fProductTph; // t/h ÷ t/h = 无量纲 / [t/h] / [t/h] = [-]
IF NOT (fCircLoad > -1.0E30 AND fCircLoad < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
xPass := (fFillPct >= fFillLoPct) AND (fFillPct <= fFillHiPct); // 双边直比，禁浮点等值 [-] / two sided band compare [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_CementMillLoadCalc := fFillPct; // 返回填充率 [%] / return the filling degree [%]
END_FUNCTION
