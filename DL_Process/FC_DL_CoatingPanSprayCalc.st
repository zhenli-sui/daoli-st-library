(*
  DL Factory R84 | FC_DL_CoatingPanSprayCalc
  功能：按片床重量与目标增重算包衣液总量、喷射时长与回算干增重
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_CoatingPanSprayCalc : REAL
VAR_INPUT
    fBedKg : REAL := 200.0; // 片床重量 [kg] / tablet bed mass [kg]
    fGainPct : REAL := 3.0; // 目标增重（干基） [%] / target weight gain [%]
    fSolidPct : REAL := 12.0; // 包衣液固含量 [%] / coating suspension solids [%]
    fSprayRateGmin : REAL := 120.0; // 喷量速率 [g/min] / spray rate [g/min]
    fDensityGml : REAL := 1.05; // 包衣液密度 [g/mL] / suspension density [g/mL]
END_VAR
VAR_OUTPUT
    fTotalSolL : REAL; // 包衣液总量 [L] / total suspension volume [L]
    fSprayMin : REAL; // 喷射时长 [min] / spray duration [min]
    fDryGainPct : REAL; // 回算干增重（校验用） [%] / back calculated dry gain [%]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fBedG : REAL; // 片床重量折算 [g] / bed mass in grams [g]
    fDryGainG : REAL; // 目标干增重质量 [g] / target dry gain mass [g]
    fLiquidG : REAL; // 包衣液总质量（湿） [g] / total liquid mass [g]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_CoatingPanSprayCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fTotalSolL := 0.0; // 液量预置零 [L] / volume preset zero [L]
fSprayMin := 0.0; // 时长预置零 [min] / duration preset zero [min]
fDryGainPct := 0.0; // 干增重预置零 [%] / dry gain preset zero [%]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fBedKg > -1.0E30 AND fBedKg < 1.0E30) OR NOT (fGainPct > -1.0E30 AND fGainPct < 1.0E30) OR NOT (fSolidPct > -1.0E30 AND fSolidPct < 1.0E30) OR NOT (fSprayRateGmin > -1.0E30 AND fSprayRateGmin < 1.0E30) OR NOT (fDensityGml > -1.0E30 AND fDensityGml < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fBedKg < 1.0E-9 OR fGainPct < 1.0E-9 OR fSolidPct < 1.0E-9 OR fSolidPct > 100.0 THEN
    RETURN; // 片床/增重/固含域闸（固含须在 (0,100]） [%] / bed, gain and solids domain gate [%]
END_IF
IF fSprayRateGmin < 1.0E-9 OR fDensityGml < 1.0E-9 THEN
    RETURN; // 喷量与密度正域分母闸（防除零） [g/min, g/mL] / spray rate and density denominator gate [-]
END_IF

// 段 3｜干增重 → 湿液量
fBedG := fBedKg * 1000.0; // kg × 1000 g/kg = g / [kg] × [g/kg] = [g]
fDryGainG := (fBedG * fGainPct) / 100.0; // g × % ÷ 100 = g / [g] × [%] / 100 = [g]
fLiquidG := (fDryGainG * 100.0) / fSolidPct; // g × 100 ÷ % = g（固含折算湿液） / [g] × 100 / [%] = [g]

// 段 4｜液量体积与喷射时长
fTotalSolL := fLiquidG / fDensityGml / 1000.0; // g ÷ g/mL = mL；mL ÷ 1000 = L / [g] / [g/mL] = [mL], [mL] / 1000 = [L]
fSprayMin := fLiquidG / fSprayRateGmin; // g ÷ g/min = min / [g] / [g/min] = [min]
IF NOT (fTotalSolL > -1.0E30 AND fTotalSolL < 1.0E30) OR NOT (fSprayMin > -1.0E30 AND fSprayMin < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF

// 段 5｜回算干增重（校验链：g × % ÷ g × 100 = %）
fDryGainPct := ((fLiquidG * fSolidPct) / 100.0 / fBedG) * 100.0; // [g] × [%] / [g] × 100 = [%]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_CoatingPanSprayCalc := fSprayRateGmin; // 返回采用的喷量速率 [g/min] / return the adopted spray rate [g/min]
END_FUNCTION
