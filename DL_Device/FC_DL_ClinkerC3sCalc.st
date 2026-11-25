(*
  DL Factory R84 | FC_DL_ClinkerC3sCalc
  功能：Bogue 法算熟料 C3S 含量并附 C2S / C3A / C4AF，负值按 0 钳位
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ClinkerC3sCalc : REAL
VAR_INPUT
    fCaO : REAL := 65.0; // 氧化钙含量 [%] / calcium oxide content [%]
    fSiO2 : REAL := 21.0; // 二氧化硅含量 [%] / silica content [%]
    fAl2O3 : REAL := 5.2; // 三氧化二铝含量 [%] / alumina content [%]
    fFe2O3 : REAL := 3.4; // 三氧化二铁含量 [%] / ferric oxide content [%]
    fSO3 : REAL := 1.0; // 三氧化硫含量 [%] / sulfur trioxide content [%]
END_VAR
VAR_OUTPUT
    fC2s : REAL; // 硅酸二钙 C2S 含量 [%] / dicalcium silicate content [%]
    fC3a : REAL; // 铝酸三钙 C3A 含量 [%] / tricalcium aluminate content [%]
    fC4af : REAL; // 铁铝酸四钙 C4AF 含量 [%] / tetracalcium aluminoferrite content [%]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fC3sRaw : REAL; // 未钳位 C3S 计算值 [%] / unclamped C3S value [%]
    fC3sClamp : REAL; // 钳位后 C3S [%] / clamped C3S [%]
    fC2sRaw : REAL; // 未钳位 C2S 计算值 [%] / unclamped C2S value [%]
    fC3aRaw : REAL; // 未钳位 C3A 计算值 [%] / unclamped C3A value [%]
    fC4afRaw : REAL; // 未钳位 C4AF 计算值 [%] / unclamped C4AF value [%]
    i : INT; // 钳位循环游标 [-] / clamp loop cursor [-]
    fArr : ARRAY[0..2] OF REAL; // 待钳位三相暂存（C2S/C3A/C4AF） [%] / staged phases for clamping [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ClinkerC3sCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fC2s := 0.0; // C2S 预置零 [%] / C2S preset zero [%]
fC3a := 0.0; // C3A 预置零 [%] / C3A preset zero [%]
fC4af := 0.0; // C4AF 预置零 [%] / C4AF preset zero [%]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fCaO > -1.0E30 AND fCaO < 1.0E30) OR NOT (fSiO2 > -1.0E30 AND fSiO2 < 1.0E30) OR NOT (fAl2O3 > -1.0E30 AND fAl2O3 < 1.0E30) OR NOT (fFe2O3 > -1.0E30 AND fFe2O3 < 1.0E30) OR NOT (fSO3 > -1.0E30 AND fSO3 < 1.0E30) THEN
    RETURN; // 五项氧化物任一非有限即拒算 [-] / any non finite oxide rejected [-]
END_IF
IF fCaO < 0.0 OR fSiO2 < 0.0 OR fAl2O3 < 0.0 OR fFe2O3 < 0.0 OR fSO3 < 0.0 THEN
    RETURN; // 化学分析值非负域闸（负含量物理非法） [%] / non negative chemical analysis gate [%]
END_IF

// 段 3｜C3S = 4.071CaO − 7.6SiO2 − 6.718Al2O3 − 1.43Fe2O3 − 2.852SO3
fC3sRaw := ((((4.071 * fCaO) - (7.6 * fSiO2)) - (6.718 * fAl2O3)) - (1.43 * fFe2O3)) - (2.852 * fSO3); // % 各项线性组合 = %（系数无量纲） / linear combination of [%] terms = [%]
IF NOT (fC3sRaw > -1.0E30 AND fC3sRaw < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜C2S = 2.867SiO2 − 0.7544C3S（按未钳位 C3S 计，符合 Bogue 原式）
fC2sRaw := (2.867 * fSiO2) - (0.7544 * fC3sRaw); // % − % = % / [%] minus [%] = [%]
fC3aRaw := (2.65 * fAl2O3) - (1.692 * fFe2O3); // % − % = % / [%] minus [%] = [%]
fC4afRaw := 3.043 * fFe2O3; // % × 无量纲 = % / [%] × [-] = [%]

// 段 5｜负值钳位：四相统一走定长数组，正向游标 0→2（禁反向递减循环）
fC3sClamp := fC3sRaw; // 先接未钳位值 [%] / take the raw C3S [%]
IF fC3sClamp < 0.0 THEN
    fC3sClamp := 0.0; // C3S 负值钳零 [%] / clamp negative C3S to zero [%]
END_IF
fArr[0] := fC2sRaw; // 装入 C2S [%] / load C2S [%]
fArr[1] := fC3aRaw; // 装入 C3A [%] / load C3A [%]
fArr[2] := fC4afRaw; // 装入 C4AF [%] / load C4AF [%]
FOR i := 0 TO 2 DO
    IF fArr[i] < 0.0 THEN
        fArr[i] := 0.0; // 负值钳零（矿物含量物理非负） [%] / clamp to zero, mineral content is non negative [%]
    END_IF
END_FOR
fC2s := fArr[0]; // C2S 落定 [%] / land C2S [%]
fC3a := fArr[1]; // C3A 落定 [%] / land C3A [%]
fC4af := fArr[2]; // C4AF 落定 [%] / land C4AF [%]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ClinkerC3sCalc := fC3sClamp; // 返回钳位后 C3S [%] / return the clamped C3S [%]
END_FUNCTION
