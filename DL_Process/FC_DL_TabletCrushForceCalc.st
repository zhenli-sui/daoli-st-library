(*
  DL Factory R84 | FC_DL_TabletCrushForceCalc
  功能：由片剂径向破碎力算硬度 kp 与径向抗张强度 σt
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_TabletCrushForceCalc : REAL
VAR_INPUT
    fCrushForceN : REAL := 80.0; // 径向破碎力（实测） [N] / radial crushing force [N]
    fDiaMm : REAL := 10.0; // 片剂直径 [mm] / tablet diameter [mm]
    fThickMm : REAL := 4.0; // 片剂厚度 [mm] / tablet thickness [mm]
END_VAR
VAR_OUTPUT
    fTensileMpa : REAL; // 径向抗张强度 [MPa] / radial tensile strength [MPa]
    fForceN : REAL; // 破碎力回显（链路校验） [N] / crushing force echo [N]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fKpRaw : REAL; // 硬度中间量 [kp] / hardness intermediate [kp]
    fAreaMm2 : REAL; // 断裂截面积 π·D·t [mm²] / fracture section area [mm^2]
END_VAR
VAR CONSTANT
    DL_TAB_GRAV : REAL := 9.80665; // 标准重力加速度（1 kp = 9.807 N） [N/kp] / standard gravity [N/kp]
    DL_TAB_PI : REAL := 3.14159265358979; // 圆周率常量（无量纲） [-] / pi constant [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_TabletCrushForceCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fTensileMpa := 0.0; // 抗张强度预置零 [MPa] / tensile strength preset zero [MPa]
fForceN := 0.0; // 破碎力回显预置零 [N] / force echo preset zero [N]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 几何域闸（R4/R20）
IF NOT (fCrushForceN > -1.0E30 AND fCrushForceN < 1.0E30) OR NOT (fDiaMm > -1.0E30 AND fDiaMm < 1.0E30) OR NOT (fThickMm > -1.0E30 AND fThickMm < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fCrushForceN < 0.0 OR fDiaMm < 1.0E-9 OR fThickMm < 1.0E-9 THEN
    RETURN; // 力非负 + 直径/厚度正域分母闸（防除零） [N, mm] / force and geometry gate [N, mm]
END_IF

// 段 3｜硬度 kp = F / 9.807
fKpRaw := fCrushForceN / DL_TAB_GRAV; // N ÷ N/kp = kp / [N] / [N/kp] = [kp]
IF NOT (fKpRaw > -1.0E30 AND fKpRaw < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜抗张强度 σt = 2F / (π·D·t)
fAreaMm2 := (DL_TAB_PI * fDiaMm) * fThickMm; // 无量纲 × mm × mm = mm²（圆柱受载投影截面） / [-] × [mm] × [mm] = [mm^2]
IF fAreaMm2 < 1.0E-9 THEN
    RETURN; // 分母闸：截面积趋零 [mm²] / denominator gate on the section area [mm^2]
END_IF
fTensileMpa := (2.0 * fCrushForceN) / fAreaMm2; // N ÷ mm² = MPa / [N] / [mm^2] = [MPa]
IF NOT (fTensileMpa > -1.0E30 AND fTensileMpa < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
fForceN := fCrushForceN; // 回显实测破碎力（未做换算） / echo the measured force unchanged
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_TabletCrushForceCalc := fKpRaw; // 返回硬度 [kp] / return the hardness [kp]
END_FUNCTION
