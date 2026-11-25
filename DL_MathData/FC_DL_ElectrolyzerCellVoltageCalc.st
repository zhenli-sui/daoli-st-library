(*
  DL Factory R88 | FC_DL_ElectrolyzerCellVoltageCalc
  功能：工程简化单槽电压 U=U_rev+R·i+s·ln(i/i0)（可逆电压+欧姆+塔菲尔），超 2.0 V 报警
  开源溯源：无（clean-room 自研，依据公开工艺公式 电解槽电压分解式 U=U_rev+iR+η_act，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_ElectrolyzerCellVoltageCalc : REAL
VAR_INPUT
    fUrevV : REAL := 1.23; // 可逆（热中性参考）电压 U_rev @25°C [V] / reversible voltage [V]
    fRohmOhmCm2 : REAL := 0.15; // 面积比欧姆电阻（含膜与接触） [Ω·cm²] / area specific ohmic resistance [ohm*cm^2]
    fCurrentDensityAPerCm2 : REAL := 0.5; // 电流密度 i [A/cm²] / current density [A/cm^2]
    fTafelSlopeV : REAL := 0.05; // 塔菲尔斜率 s（每数量级电压增量） [V/dec] / tafel slope [V/dec]
    fExchangeCurrentDensityAPerCm2 : REAL := 1.0E-3; // 交换电流密度 i0（ln 的基准） [A/cm²] / exchange current density [A/cm^2]
    fLimitV : REAL := 2.0; // 单槽电压报警上限（能效恶化提示） [V] / cell voltage alarm limit [V]
END_VAR
VAR_OUTPUT
    fCellV : REAL; // 单槽电压 U [V] / cell voltage [V]
    xOverLimit : BOOL; // TRUE=单槽电压超过报警上限 [-] / TRUE when above the alarm limit [-]
END_VAR
VAR
    fRatio : REAL; // i/i0（对数量纲一化比值） [-] / current density ratio [-]
    fOhmicV : REAL; // 欧姆压降 i·R [V] / ohmic drop [V]
    fActV : REAL; // 活化过电位 s·ln(i/i0) [V] / activation overpotential [V]
END_VAR

// 段 1｜出口预置
FC_DL_ElectrolyzerCellVoltageCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fCellV := 0.0; // 单槽电压预置零 [V] / cell voltage preset zero [V]
xOverLimit := FALSE; // 超限位预置 FALSE（未判定前不报警） [-] / over-limit flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fUrevV > -1.0E30 AND fUrevV < 1.0E30) OR NOT (fRohmOhmCm2 > -1.0E30 AND fRohmOhmCm2 < 1.0E30) OR NOT (fCurrentDensityAPerCm2 > -1.0E30 AND fCurrentDensityAPerCm2 < 1.0E30) THEN
    RETURN; // 可逆电压/欧姆电阻/电流密度任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fTafelSlopeV > -1.0E30 AND fTafelSlopeV < 1.0E30) OR NOT (fExchangeCurrentDensityAPerCm2 > -1.0E30 AND fExchangeCurrentDensityAPerCm2 < 1.0E30) OR NOT (fLimitV > -1.0E30 AND fLimitV < 1.0E30) THEN
    RETURN; // 塔菲尔斜率/i0/上限任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fCurrentDensityAPerCm2 < 1.0E-9 OR fExchangeCurrentDensityAPerCm2 < 1.0E-9 THEN
    RETURN; // ln 的自变量须为正：i 与 i0 都必须大于 1E-9 [A/cm²] / ln argument must be positive [A/cm^2]
END_IF
IF fRohmOhmCm2 < 0.0 OR fTafelSlopeV < 0.0 OR fUrevV <= 0.0 OR fLimitV <= 0.0 THEN
    RETURN; // 物理符号域闸：电阻/斜率非负、可逆电压与上限为正 [Ω·cm², V] / physical sign gates [-]
END_IF

// 段 3｜计算
fRatio := fCurrentDensityAPerCm2 / fExchangeCurrentDensityAPerCm2; // (A/cm²) ÷ (A/cm²) = 无量纲 [-] / dimensionless ratio [-]
IF fRatio < 1.0E-9 THEN
    RETURN; // 除法后复核：比值须为正，否则 LN 产生非有限值 [-] / ratio must stay positive before LN [-]
END_IF
fOhmicV := fRohmOhmCm2 * fCurrentDensityAPerCm2; // (Ω·cm²) × (A/cm²) = V，量纲自洽 [V] / [ohm*cm^2] x [A/cm^2] = [V]
fActV := fTafelSlopeV * LN(fRatio); // V × 无量纲 = V，活化过电位 [V] / [V] x [-] = [V]
fCellV := fUrevV + fOhmicV + fActV; // V + V + V = V，三项分解合成 [V] / [V]

// 段 4｜判定与饱和
IF NOT (fCellV > -1.0E30 AND fCellV < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xOverLimit := fCellV > fLimitV; // 严格大于上限为报警，等于上限仍判正常 [V] / strict compare [V]

// 段 5｜出口自检
IF fCellV < fUrevV THEN
    RETURN; // 出口自检：单槽电压不应低于可逆电压（过电位恒非负） [V] / cell voltage must not drop below U_rev [V]
END_IF
FC_DL_ElectrolyzerCellVoltageCalc := fCellV; // 返回单槽电压 U [V] / return the cell voltage [V]
END_FUNCTION
