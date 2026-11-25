(*
  DL Factory R84 | FC_DL_ClinkerLsfCalc
  功能：算熟料石灰饱和系数 LSF 并附硅率 SM 与铝率 IM 率值
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ClinkerLsfCalc : REAL
VAR_INPUT
    fCaO : REAL := 65.0; // 氧化钙含量 [%] / calcium oxide content [%]
    fSiO2 : REAL := 21.0; // 二氧化硅含量 [%] / silica content [%]
    fAl2O3 : REAL := 5.2; // 三氧化二铝含量 [%] / alumina content [%]
    fFe2O3 : REAL := 3.4; // 三氧化二铁含量 [%] / ferric oxide content [%]
    fLsfLo : REAL := 92.0; // LSF 合格下限 [-] / LSF lower acceptance bound [-]
    fLsfHi : REAL := 98.0; // LSF 合格上限 [-] / LSF upper acceptance bound [-]
END_VAR
VAR_OUTPUT
    fSm : REAL; // 硅率 SM [-] / silica modulus [-]
    fIm : REAL; // 铝率 IM [-] / alumina modulus [-]
    xPass : BOOL; // LSF 落在合格带 [-] / LSF inside the acceptance band [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fNum : REAL; // LSF 分子（CaO − 1.65Al − 0.35Fe） [%] / LSF numerator [%]
    fLsf : REAL; // LSF 中间量 [-] / LSF intermediate [-]
    fAlFe : REAL; // 铝铁合计（SM 分母） [%] / alumina plus ferric sum [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ClinkerLsfCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fSm := 0.0; // 硅率预置零 [-] / silica modulus preset zero [-]
fIm := 0.0; // 铝率预置零 [-] / alumina modulus preset zero [-]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fCaO > -1.0E30 AND fCaO < 1.0E30) OR NOT (fSiO2 > -1.0E30 AND fSiO2 < 1.0E30) OR NOT (fAl2O3 > -1.0E30 AND fAl2O3 < 1.0E30) OR NOT (fFe2O3 > -1.0E30 AND fFe2O3 < 1.0E30) THEN
    RETURN; // 四项氧化物任一非有限即拒算 [-] / any non finite oxide rejected [-]
END_IF
IF fCaO < 0.0 OR fSiO2 < 1.0E-9 OR fAl2O3 < 0.0 OR fFe2O3 < 1.0E-9 THEN
    RETURN; // SiO2 与 Fe2O3 正域分母闸 + 其余非负闸 [%] / positive denominator gate [%]
END_IF
IF NOT (fLsfLo > -1.0E30 AND fLsfLo < 1.0E30) OR NOT (fLsfHi > -1.0E30 AND fLsfHi < 1.0E30) OR NOT (fLsfLo < fLsfHi) THEN
    RETURN; // 合格带组态闸：下限必须严格小于上限 [-] / acceptance band config gate [-]
END_IF

// 段 3｜LSF = (CaO − 1.65Al2O3 − 0.35Fe2O3) / (2.8 SiO2)
fNum := (fCaO - (1.65 * fAl2O3)) - (0.35 * fFe2O3); // % − % − % = %（系数无量纲） / [%] - [%] - [%] = [%]
fLsf := fNum / (2.8 * fSiO2); // % ÷ % = 无量纲 / [%] / [%] = [-]
IF NOT (fLsf > -1.0E30 AND fLsf < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜率值：SM = SiO2/(Al+Fe)，IM = Al/Fe
fAlFe := fAl2O3 + fFe2O3; // % + % = % / [%] + [%] = [%]
IF fAlFe < 1.0E-9 THEN
    RETURN; // 分母闸：铝铁合计趋零 [%] / denominator gate on the alumina plus ferric sum [%]
END_IF
fSm := fSiO2 / fAlFe; // % ÷ % = 无量纲 / [%] / [%] = [-]
fIm := fAl2O3 / fFe2O3; // % ÷ % = 无量纲 / [%] / [%] = [-]
IF NOT (fSm > -1.0E30 AND fSm < 1.0E30) OR NOT (fIm > -1.0E30 AND fIm < 1.0E30) THEN
    RETURN; // 率值非有限再拦一次 [-] / second finiteness gate on the moduli [-]
END_IF
xPass := (fLsf >= fLsfLo) AND (fLsf <= fLsfHi); // 带内判据，双边直比 [-] / band verdict with two sided compares [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ClinkerLsfCalc := fLsf; // 返回 LSF [-] / return the LSF [-]
END_FUNCTION
