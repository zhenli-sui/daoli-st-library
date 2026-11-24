(*
  DL Factory R83 | FC_DL_BarrelRotationRpmCalc
  功能：按滚筒内径与零件贴壁尺寸算临界转速，并给出实际转速与临界转速之比。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_BarrelRotationRpmCalc : REAL
VAR_INPUT
    fBarrelDiaMm : REAL; // 滚筒内径 [mm] / Barrel inner diameter [mm]
    fRpm         : REAL; // 实测滚筒转速 [rpm] / Measured barrel speed [rpm]
    fPartDiaMm   : REAL; // 零件特征尺寸（贴壁层厚近似）[mm] / Part characteristic size [mm]
    fFillPct     : REAL; // 装载率（0~60）[%] / Barrel fill ratio [%]
END_VAR
VAR_OUTPUT
    fCritRpm  : REAL; // 临界转速（物料离心贴壁起始）[rpm] / Critical speed [rpm]
    fRpmRatio : REAL; // 转速比（实际÷临界，工艺宜 0.3~0.6）[-] / Speed ratio, window 0.3 to 0.6
    xValid    : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fEffDiaM : REAL; // 有效内径（扣除贴壁层）[m] / Effective inner diameter [m]
    fSqrtD   : REAL; // 有效内径平方根 [m^0.5] / Square root of effective diameter [m^0.5]
END_VAR
fCritRpm := 0.0; fRpmRatio := 0.0; xValid := FALSE;  // 出口预置（R256）
// 非有限拦截 + 几何量纲自检（R20/R21）
IF NOT (fBarrelDiaMm > -1.0E30 AND fBarrelDiaMm < 1.0E30) OR NOT (fRpm > -1.0E30 AND fRpm < 1.0E30) OR NOT (fPartDiaMm > -1.0E30 AND fPartDiaMm < 1.0E30) OR NOT (fFillPct > -1.0E30 AND fFillPct < 1.0E30) OR fBarrelDiaMm <= 0.0 OR fRpm < 0.0 OR fPartDiaMm < 0.0 OR fPartDiaMm >= fBarrelDiaMm THEN
    FC_DL_BarrelRotationRpmCalc := -1.0; RETURN;  // 哨兵 -1：非有限或几何越界 / Sentinel -1
END_IF
// 装载率域闸：0~60% 之外钳位（超装将改变物料运动形态）
IF fFillPct < 0.0 THEN fFillPct := 0.0; ELSIF fFillPct > 60.0 THEN fFillPct := 60.0; END_IF
// 有效内径：滚筒内径扣减两层零件贴壁厚度，mm ÷ 1000 = m（量纲自洽）
fEffDiaM := (fBarrelDiaMm - 2.0 * fPartDiaMm) / 1000.0; // 有效内径 [m] / Effective inner diameter
// 开方前非负闸（R4），再按经验式 n_c = 42.3 / √D 算临界转速（D 单位 m，n_c 单位 rpm）
IF fEffDiaM > 0.0 THEN
    fSqrtD := SQRT(fEffDiaM);       // 内径平方根 [m^0.5] / Square root of diameter
    IF ABS(fSqrtD) > 1.0E-9 THEN fCritRpm := 42.3 / fSqrtD; ELSE fCritRpm := 0.0; END_IF
ELSE
    fCritRpm := 0.0;                // 内径非正不可算，缺省零 / Non-positive diameter, default zero
END_IF
// 转速比：实际 ÷ 临界，临界转速分母显式零闸（R4/R21）
IF ABS(fCritRpm) > 1.0E-9 THEN      // 临界转速分母显式零闸 / Explicit zero gate
    fRpmRatio := fRpm / fCritRpm;   // 转速比 [-]/ Speed ratio
ELSE
    fRpmRatio := 0.0;               // 除零防御缺省 / Divide-by-zero default
END_IF
xValid := TRUE; FC_DL_BarrelRotationRpmCalc := fRpmRatio;  // 返回转速比 [-] / Return speed ratio
END_FUNCTION
