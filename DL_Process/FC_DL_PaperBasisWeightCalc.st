(*
  DL Factory R84 | FC_DL_PaperBasisWeightCalc
  功能：由卷重/幅宽/长度算纸张定量并做水分修正与偏差判定
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_PaperBasisWeightCalc : REAL
VAR_INPUT
    fRollKg : REAL := 1200.0; // 卷筒重量（含水分） [kg] / roll mass including moisture [kg]
    fWidthM : REAL := 3.5; // 幅宽 [m] / web width [m]
    fLengthM : REAL := 8000.0; // 卷长 [m] / roll length [m]
    fMoistPct : REAL := 7.0; // 成纸水分 [%] / paper moisture [%]
    fTargetGm2 : REAL := 80.0; // 目标定量 [g/m²] / target basis weight [g/m^2]
    fTolPct : REAL := 3.0; // 定量偏差允差 [%] / basis weight tolerance [%]
END_VAR
VAR_OUTPUT
    fDevPct : REAL; // 定量相对偏差 [%] / relative basis weight deviation [%]
    fBoneDryG : REAL; // 绝干质量 [g] / bone dry mass [g]
    xPass : BOOL; // 定量判合格 [-] / basis weight passed [-]
END_VAR
VAR
    fAreaM2 : REAL; // 纸幅面积 [m²] / web area [m^2]
    fBasisGm2 : REAL; // 绝干定量 [g/m²] / bone dry basis weight [g/m^2]
    xValid : BOOL; // 计算有效标志（内部） [-] / internal validity flag [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_PaperBasisWeightCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fDevPct := 0.0; // 偏差预置零 [%] / deviation preset zero [%]
fBoneDryG := 0.0; // 绝干质量预置零 [g] / bone dry mass preset zero [g]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fRollKg > -1.0E30 AND fRollKg < 1.0E30) OR NOT (fWidthM > -1.0E30 AND fWidthM < 1.0E30) OR NOT (fLengthM > -1.0E30 AND fLengthM < 1.0E30) THEN
    RETURN; // 卷重/幅宽/卷长任一非有限即拒算 [-] / any non finite roll geometry rejected [-]
END_IF
IF NOT (fMoistPct > -1.0E30 AND fMoistPct < 1.0E30) OR NOT (fTargetGm2 > -1.0E30 AND fTargetGm2 < 1.0E30) OR NOT (fTolPct > -1.0E30 AND fTolPct < 1.0E30) THEN
    RETURN; // 水分/目标定量/允差任一非有限即拒算 [-] / any non finite moisture or target rejected [-]
END_IF
IF fRollKg <= 0.0 OR fWidthM < 1.0E-9 OR fLengthM < 1.0E-9 OR fTargetGm2 < 1.0E-9 OR fTolPct < 0.0 THEN
    RETURN; // 面积与目标定量正域分母闸（防除零） [m, g/m²] / positive denominator gate [m, g/m^2]
END_IF
IF fMoistPct < 0.0 OR fMoistPct >= 100.0 THEN
    RETURN; // 水分开区间域闸 [0,100) [%] / moisture open interval gate [%]
END_IF

// 段 3｜绝干质量与面积
fBoneDryG := (fRollKg * 1000.0) * (1.0 - (fMoistPct / 100.0)); // kg × 1000 g/kg × 无量纲 = g / [kg] × [g/kg] × [-] = [g]
fAreaM2 := fWidthM * fLengthM; // m × m = m² / [m] × [m] = [m^2]
IF fAreaM2 < 1.0E-9 THEN
    RETURN; // 分母闸：面积趋零 [m²] / denominator gate on the area [m^2]
END_IF

// 段 4｜定量与偏差
fBasisGm2 := fBoneDryG / fAreaM2; // g ÷ m² = g/m² / [g] / [m^2] = [g/m^2]
fDevPct := ((fBasisGm2 - fTargetGm2) / fTargetGm2) * 100.0; // (g/m² ÷ g/m²) × 100 = % / [g/m^2] / [g/m^2] × 100 = [%]
IF NOT (fBasisGm2 > -1.0E30 AND fBasisGm2 < 1.0E30) OR NOT (fDevPct > -1.0E30 AND fDevPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF
xPass := ABS(fDevPct) <= fTolPct; // 偏差绝对值与允差直比 [-] / absolute deviation against the tolerance [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_PaperBasisWeightCalc := fBasisGm2; // 返回绝干定量 [g/m²] / return the basis weight [g/m^2]
END_FUNCTION
