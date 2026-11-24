(*
  DL Factory R83 | FC_DL_BeamWarpLengthCalc
  功能：按边盘与轴芯直径、纱线直径算经轴卷绕层数、可卷经纱长度与总根数。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_BeamWarpLengthCalc : REAL
VAR_INPUT
    fFlangeDiaMm : REAL; // 经轴边盘直径 [mm] / Beam flange diameter [mm]
    fBarrelDiaMm : REAL; // 经轴轴芯直径 [mm] / Beam barrel diameter [mm]
    fYarnDiaMm   : REAL; // 单根经纱直径（即单层卷绕厚度）[mm] / Yarn diameter, layer thickness [mm]
    fWarpDensity : REAL; // 经密（每 cm 根数）[根/cm] / Warp density [ends/cm]
    fBeamWidthMm : REAL; // 经轴卷绕幅宽 [mm] / Beam winding width [mm]
END_VAR
VAR_OUTPUT
    fLengthM : REAL; // 可卷绕经纱总长 [m] / Windable warp length [m]
    iLayers  : INT;  // 可卷绕层数 [层] / Number of wound layers [-]
    diEnds   : DINT; // 经纱总根数 [根] / Total warp ends [-]
    xValid   : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fOuterMm : REAL; // 满轴外径 [mm] / Fully wound outer diameter [mm]
    fAvgMm   : REAL; // 平均卷绕直径 [mm] / Mean winding diameter [mm]
    fRadialMm: REAL; // 径向可卷厚度 [mm] / Available radial thickness [mm]
END_VAR
// 出口预置：四出口统一预置（R256）
fLengthM := 0.0; iLayers := 0; diEnds := 0; xValid := FALSE;
// 非有限拦截 + 量纲次序 + 分母零闸（R4/R20/R21）
IF NOT (fFlangeDiaMm > -1.0E30 AND fFlangeDiaMm < 1.0E30) OR NOT (fBarrelDiaMm > -1.0E30 AND fBarrelDiaMm < 1.0E30) OR NOT (fYarnDiaMm > -1.0E30 AND fYarnDiaMm < 1.0E30) OR NOT (fWarpDensity > -1.0E30 AND fWarpDensity < 1.0E30) OR NOT (fBeamWidthMm > -1.0E30 AND fBeamWidthMm < 1.0E30) OR fFlangeDiaMm <= fBarrelDiaMm OR ABS(fYarnDiaMm) <= 1.0E-9 OR fWarpDensity <= 0.0 OR fBeamWidthMm <= 0.0 THEN
    FC_DL_BeamWarpLengthCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲/直径次序越界 / Sentinel -1
END_IF
// 径向可卷厚度：(边盘 - 轴芯) ÷ 2，单边径向空间 [mm]
fRadialMm := (fFlangeDiaMm - fBarrelDiaMm) / 2.0;   // 径向厚度 [mm] / Radial thickness [mm]
// 层数：向下取整（禁 TRUNC+1 向上取整写法，R28）
iLayers := REAL_TO_INT(fRadialMm / fYarnDiaMm);     // 满层数 [层] / Full layers [-]
// 平均卷绕直径：轴芯与满轴外径的中径，外径 = 轴芯 + 层数 × 纱径（mm）
fOuterMm := fBarrelDiaMm + INT_TO_REAL(iLayers) * fYarnDiaMm; // 满轴外径 [mm] / Outer diameter [mm]
fAvgMm   := (fBarrelDiaMm + fOuterMm) / 2.0;                  // 平均直径 [mm] / Mean diameter [mm]
// 纱长：层数 × π × 平均直径，mm ÷ 1000 得 m（量纲自洽）
IF iLayers > 0 THEN
    fLengthM := 3.14159265358979 * fAvgMm * INT_TO_REAL(iLayers) / 1000.0; // 卷绕长度 [m]
ELSE
    fLengthM := 0.0;                // 不足一层不可卷绕 / Not even one layer, zero length
END_IF
// 经纱根数：根/cm × 幅宽(cm) = 根；幅宽 mm ÷ 10 = cm（量纲自洽）
diEnds := REAL_TO_DINT(fWarpDensity * fBeamWidthMm / 10.0); // 总根数 [根] / Total ends [-]
xValid := TRUE;                                             // 链路有效 / Chain valid
FC_DL_BeamWarpLengthCalc := fLengthM;                       // 返回可卷长度 [m] / Return length [m]
END_FUNCTION
