(*
  DL Factory R84 | FC_DL_CoolantConcCalc
  功能：由折光读数算切削液浓度，并按两液混合守恒算补原液量与补水量
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_CoolantConcCalc : REAL
VAR_INPUT
    fRefractBrix : REAL := 3.0; // 折光仪读数（Brix 刻度） [%] / refractometer reading [%]
    fRefractCoef : REAL := 2.0; // 折光换算系数（无量纲） [-] / refractometer conversion factor [-]
    fVolL : REAL := 500.0; // 当前槽液体积 [L] / current sump volume [L]
    fTargetPct : REAL := 8.0; // 目标工作浓度 [%] / target working concentration [%]
END_VAR
VAR_OUTPUT
    fAddConcL : REAL; // 需补原液体积 [L] / raw concentrate to add [L]
    fAddWaterL : REAL; // 需补清水体积 [L] / water to add [L]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fCurPct : REAL; // 当前实测浓度 [%] / measured concentration [%]
    fDen : REAL; // 混合守恒分母（无量纲/百分比项） [-] / conservation denominator [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_CoolantConcCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fAddConcL := 0.0; // 补原液预置零 [L] / concentrate preset zero [L]
fAddWaterL := 0.0; // 补水预置零 [L] / water preset zero [L]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fRefractBrix > -1.0E30 AND fRefractBrix < 1.0E30) OR NOT (fRefractCoef > -1.0E30 AND fRefractCoef < 1.0E30) OR NOT (fVolL > -1.0E30 AND fVolL < 1.0E30) OR NOT (fTargetPct > -1.0E30 AND fTargetPct < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fRefractCoef < 1.0E-9 OR fVolL < 0.0 OR fTargetPct < 1.0E-9 OR fTargetPct > 99.0 THEN
    RETURN; // 系数/体积/目标浓度域闸（含除零防护） [%/L] / factor, volume and target domain gate [%/L]
END_IF

// 段 3｜当前浓度 = 折光读数 × 折光系数
fCurPct := fRefractBrix * fRefractCoef; // % × 无量纲 = % / [%] × [-] = [%]

// 段 4｜两液混合守恒：原液按 100% 计，水按 0% 计
IF fCurPct < fTargetPct THEN
    fDen := 100.0 - fTargetPct; // 100% − 目标% = 百分点 / [%] minus [%] = [%]
    IF fDen < 1.0E-9 THEN
        RETURN; // 分母闸：目标浓度逼近 100% 无解 [%] / denominator gate near 100 [%]
    END_IF
    fAddConcL := (fVolL * (fTargetPct - fCurPct)) / fDen; // L × % ÷ % = L（守恒：V·c + 100·a = t·(V+a)） / [L] × [%] / [%] = [L]
    fAddWaterL := 0.0; // 浓度偏低不补水 [L] / no water while low [L]
ELSE
    IF fTargetPct < 1.0E-9 THEN
        RETURN; // 分母闸：目标浓度趋零 [%] / denominator gate on zero target [%]
    END_IF
    fAddWaterL := (fVolL * (fCurPct - fTargetPct)) / fTargetPct; // L × % ÷ % = L（守恒：V·c = t·(V+w)） / [L] × [%] / [%] = [L]
    fAddConcL := 0.0; // 浓度偏高不补原液 [L] / no concentrate while high [L]
END_IF
IF NOT (fAddConcL > -1.0E30 AND fAddConcL < 1.0E30) OR NOT (fAddWaterL > -1.0E30 AND fAddWaterL < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the results [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_CoolantConcCalc := fCurPct; // 返回当前浓度 [%] / return the measured concentration [%]
END_FUNCTION
