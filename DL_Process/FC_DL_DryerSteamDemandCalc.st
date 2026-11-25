(*
  DL Factory R84 | FC_DL_DryerSteamDemandCalc
  功能：按蒸发水量与汽化潜热折算烘缸蒸汽耗量及单位汽耗
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_DryerSteamDemandCalc : REAL
VAR_INPUT
    fEvapRateKgh : REAL := 8000.0; // 蒸发水量 [kg/h] / evaporated water rate [kg/h]
    fLatentKjkg : REAL := 2200.0; // 水汽化潜热 [kJ/kg] / latent heat of vaporisation [kJ/kg]
    fSensKjkg : REAL := 250.0; // 水与纸幅显热当量 [kJ/kg] / sensible heat allowance [kJ/kg]
    fSteamEnthKjkg : REAL := 2100.0; // 蒸汽可用焓降 [kJ/kg] / available steam enthalpy drop [kJ/kg]
    fEff : REAL := 0.85; // 烘缸组热效率（0~1） [-] / dryer thermal efficiency [0,1]
    fPaperTph : REAL := 20.0; // 纸机产量 [t/h] / paper machine output [t/h]
END_VAR
VAR_OUTPUT
    fSpecSteam : REAL; // 单位汽耗 [t 汽/t 纸] / specific steam consumption [t/t]
    fEvapKgh : REAL; // 蒸发水量回显（链路校验） [kg/h] / evaporation echo [kg/h]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fHeatKjh : REAL; // 需热量 [kJ/h] / heat demand [kJ/h]
    fSteamKgh : REAL; // 蒸汽耗量 [kg/h] / steam demand [kg/h]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_DryerSteamDemandCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fSpecSteam := 0.0; // 单位汽耗预置零 [t/t] / specific steam preset zero [t/t]
fEvapKgh := 0.0; // 蒸发量回显预置零 [kg/h] / evaporation echo preset zero [kg/h]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fEvapRateKgh > -1.0E30 AND fEvapRateKgh < 1.0E30) OR NOT (fLatentKjkg > -1.0E30 AND fLatentKjkg < 1.0E30) OR NOT (fSensKjkg > -1.0E30 AND fSensKjkg < 1.0E30) THEN
    RETURN; // 蒸发量与两项热量任一非有限即拒算 [-] / any non finite evaporation or heat term rejected [-]
END_IF
IF NOT (fSteamEnthKjkg > -1.0E30 AND fSteamEnthKjkg < 1.0E30) OR NOT (fEff > -1.0E30 AND fEff < 1.0E30) OR NOT (fPaperTph > -1.0E30 AND fPaperTph < 1.0E30) THEN
    RETURN; // 焓降/效率/产量任一非有限即拒算 [-] / any non finite enthalpy, efficiency or output rejected [-]
END_IF
IF fEvapRateKgh < 0.0 OR fLatentKjkg < 1.0E-9 OR fSensKjkg < 0.0 THEN
    RETURN; // 蒸发量非负 + 潜热正域闸 [kg/h, kJ/kg] / non negative evaporation and positive latent heat gate [-]
END_IF
IF fSteamEnthKjkg < 1.0E-9 OR fEff < 1.0E-9 OR fPaperTph < 1.0E-9 THEN
    RETURN; // 焓降/效率/产量正域分母闸（防除零） [kJ/kg, t/h] / positive denominator gate [kJ/kg, t/h]
END_IF
IF fEff > 1.0 THEN
    RETURN; // 效率上限闸：大于一违反热力学 [-] / efficiency above one is not physical [-]
END_IF

// 段 3｜需热量与蒸汽耗量
fHeatKjh := fEvapRateKgh * (fLatentKjkg + fSensKjkg); // kg/h × kJ/kg = kJ/h / [kg/h] × [kJ/kg] = [kJ/h]
fSteamKgh := (fHeatKjh / fSteamEnthKjkg) / fEff; // kJ/h ÷ kJ/kg = kg/h；÷ 无量纲 仍 kg/h / [kJ/h] / [kJ/kg] / [-] = [kg/h]
IF NOT (fSteamKgh > -1.0E30 AND fSteamKgh < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜单位汽耗 = 汽量 / 纸量（同除 kg/h 得无量纲，即 t/t）
fSpecSteam := fSteamKgh / (fPaperTph * 1000.0); // kg/h ÷ (t/h × 1000 kg/t) = 无量纲（t 汽/t 纸） / [kg/h] / [kg/h] = [-] = [t/t]
IF NOT (fSpecSteam > -1.0E30 AND fSpecSteam < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
fEvapKgh := fEvapRateKgh; // 回显蒸发水量 [kg/h] / echo the evaporated water [kg/h]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_DryerSteamDemandCalc := fSteamKgh; // 返回蒸汽耗量 [kg/h] / return the steam demand [kg/h]
END_FUNCTION
