(*
  DL Factory R84 | FC_DL_CuttingForceCalc
  功能：按比切削力模型算车削主切削力 Fc 与单位切削功率 Pc
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_CuttingForceCalc : REAL
VAR_INPUT
    fKc : REAL := 2000.0; // 材料比切削力 [N/mm²] / specific cutting force [N/mm^2]
    fAp : REAL := 1.0; // 背吃刀量（切深） [mm] / depth of cut [mm]
    fFeed : REAL := 0.2; // 每转进给量 [mm/r] / feed per revolution [mm/rev]
    fVc : REAL := 150.0; // 切削线速度 [m/min] / cutting speed [m/min]
    fKcRef : REAL := 1.0; // 比切削力修正系数（无量纲） [-] / specific force correction factor [-]
END_VAR
VAR_OUTPUT
    fUnitPowerKw : REAL; // 单位切削功率 [kW] / unit cutting power [kW]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fKcEff : REAL; // 修正后比切削力 [N/mm²] / corrected specific cutting force [N/mm^2]
    fFcRaw : REAL; // 切削力中间量 [N] / cutting force intermediate [N]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_CuttingForceCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fUnitPowerKw := 0.0; // 功率预置零 [kW] / power preset to zero [kW]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 物理域闸（R4/R20）
IF NOT (fKc > -1.0E30 AND fKc < 1.0E30) OR NOT (fAp > -1.0E30 AND fAp < 1.0E30) OR NOT (fFeed > -1.0E30 AND fFeed < 1.0E30) OR NOT (fVc > -1.0E30 AND fVc < 1.0E30) OR NOT (fKcRef > -1.0E30 AND fKcRef < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fKc <= 0.0 OR fAp < 0.0 OR fFeed < 0.0 OR fVc < 0.0 THEN
    RETURN; // 比切削力非正或几何量为负即非法 [-] / non positive force or negative geometry [-]
END_IF
IF ABS(fKcRef) < 1.0E-9 THEN
    RETURN; // 分母闸：修正系数趋零 [-] / denominator gate on correction factor [-]
END_IF

// 段 3｜主算：Fc 与 Pc
fKcEff := fKc / fKcRef; // N/mm² ÷ 无量纲 = N/mm² / [N/mm^2] divided by [-]
fFcRaw := (fKcEff * fAp) * fFeed; // N/mm² × mm × mm/r = N（切屑截面积按每转计） / [N/mm^2] × mm × mm/rev = N
IF fFcRaw <= 0.0 THEN
    RETURN; // 零切深或零进给无切削意义 [-] / zero depth or zero feed carries no cut [-]
END_IF
fUnitPowerKw := fFcRaw * fVc / 60000.0; // N × m/min ÷ 60000 = kW（60000 = 60 s × 1000 W） / [N] × [m/min] / 60000 = kW
IF NOT (fUnitPowerKw > -1.0E30 AND fUnitPowerKw < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate on the result [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_CuttingForceCalc := fFcRaw; // 返回主切削力 [N] / return the cutting force [N]
END_FUNCTION
