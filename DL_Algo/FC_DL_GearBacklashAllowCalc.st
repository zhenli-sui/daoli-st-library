(*
  DL Factory R88 | FC_DL_GearBacklashAllowCalc
  功能：齿侧间隙允许值 jn=jBase+a·αth·ΔT（工程近似式，仅计基础间隙与热膨胀附加量），出口换算 µm
  开源溯源：无（clean-room 自研，依据公开工艺公式 齿侧间隙热膨胀补偿近似式 jn=j0+a·αth·ΔT，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_GearBacklashAllowCalc : REAL
VAR_INPUT
    fBaseMm : REAL := 0.05; // 基础装配齿侧间隙 j0（中心距为零、无温差时的给定值） [mm] / base backlash [mm]
    fCentreDistMm : REAL := 100.0; // 齿轮副中心距 a [mm] / centre distance [mm]
    fThermalExpPerK : REAL := 11.5E-6; // 材料线膨胀系数 αth（钢 11.5e-6，箱体铝 23e-6） [1/K] / thermal expansion coefficient [1/K]
    fDeltaTK : REAL := 40.0; // 相对装配温度的温升 ΔT（可负=降温收缩） [K] / temperature rise [K]
    fMinUm : REAL := 20.0; // 允许间隙下限（工程经验带宽） [µm] / lower backlash band [um]
    fMaxUm : REAL := 300.0; // 允许间隙上限（工程经验带宽） [µm] / upper backlash band [um]
END_VAR
VAR_OUTPUT
    fBacklashUm : REAL; // 齿侧间隙允许值 jn（含热膨胀附加量） [µm] / allowed backlash [um]
    xInBand : BOOL; // TRUE=允许值落在 [fMinUm,fMaxUm] 工程带内 [-] / TRUE when inside the band [-]
END_VAR
VAR
    fThermalMm : REAL; // 热膨胀附加间隙 a·αth·ΔT [mm] / thermal backlash addition [mm]
    fTotalMm : REAL; // 合成间隙 mm 值（换算前） [mm] / combined backlash before conversion [mm]
END_VAR

// 段 1｜出口预置
FC_DL_GearBacklashAllowCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fBacklashUm := 0.0; // 允许间隙预置零 [µm] / allowed backlash preset zero [um]
xInBand := FALSE; // 带宽位预置 FALSE（未判定前不认合格） [-] / band flag preset false [-]
fThermalMm := 0.0; // 热膨胀附加量预置零 [mm] / thermal addition preset zero [mm]
fTotalMm := 0.0; // 合成间隙预置零 [mm] / combined backlash preset zero [mm]

// 段 2｜非有限拦截 + 域闸
IF NOT (fBaseMm > -1.0E30 AND fBaseMm < 1.0E30) OR NOT (fCentreDistMm > -1.0E30 AND fCentreDistMm < 1.0E30) THEN
    RETURN; // 基础间隙/中心距任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fThermalExpPerK > -1.0E30 AND fThermalExpPerK < 1.0E30) OR NOT (fDeltaTK > -1.0E30 AND fDeltaTK < 1.0E30) THEN
    RETURN; // 膨胀系数/温升任一非有限即拒算 [-] / any non finite thermal input rejected [-]
END_IF
IF NOT (fMinUm > -1.0E30 AND fMinUm < 1.0E30) OR NOT (fMaxUm > -1.0E30 AND fMaxUm < 1.0E30) THEN
    RETURN; // 带宽上下限任一非有限即拒算 [-] / any non finite band limit rejected [-]
END_IF
IF fCentreDistMm < 1.0E-9 OR fBaseMm < 0.0 THEN
    RETURN; // 中心距正域闸 + 基础间隙非负闸 [mm] / positive centre distance and non negative base [mm]
END_IF
IF fMinUm <= 0.0 OR fMaxUm <= fMinUm THEN
    RETURN; // 带宽自洽闸：下限须为正、上限须严格大于下限 [µm] / band consistency gate [um]
END_IF

// 段 3｜计算（本式为工程近似：忽略齿形修形、装配偏心与离心量）
fThermalMm := fCentreDistMm * fThermalExpPerK * fDeltaTK; // mm × (1/K) × K = mm，量纲自洽 [mm] / [mm] x [1/K] x [K] = [mm]
fTotalMm := fBaseMm + fThermalMm; // mm + mm = mm，jn=j0+a·αth·ΔT [mm] / combined backlash [mm]
fBacklashUm := fTotalMm * 1000.0; // mm × 1000 µm/mm = µm / [mm] x [um/mm] = [um]

// 段 4｜判定与饱和
IF NOT (fBacklashUm > -1.0E30 AND fBacklashUm < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次（防溢出成 Inf） [-] / re-check the result for finiteness [-]
END_IF
xInBand := (fBacklashUm >= fMinUm) AND (fBacklashUm <= fMaxUm); // 双侧闭区间直比 [µm] / closed two sided band compare [um]

// 段 5｜出口自检
IF fBacklashUm <= 0.0 THEN
    RETURN; // 出口自检：允许间隙应为正（负值说明温差或基础值给错） [µm] / backlash must be positive [um]
END_IF
FC_DL_GearBacklashAllowCalc := fBacklashUm; // 返回齿侧间隙允许值 [µm] / return the allowed backlash [um]
END_FUNCTION
