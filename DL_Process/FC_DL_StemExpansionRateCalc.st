(*
 * FC_DL_StemExpansionRateCalc | C2 | DL_Process
 * 功能：梗丝膨胀率（膨胀前/后堆积密度比）       单位：堆积密度 [g/cm³]、膨胀率 [%]
 * 工况边界：仅适用于蒸汽/CO2 膨胀后梗丝的堆积密度法测膨胀率；膨胀后密度须 >0（入分母），两密度须有限且非负；不修正含水率差异（须在等水分条件下取样）
 * 代数值回代：before=0.35、after=0.18 g/cm³ → rate=(0.35/0.18−1)×100=94.4 %（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_StemExpansionRateCalc : BOOL
VAR_INPUT
    rBulkDensBefore : REAL := 0.35;  // 膨胀前堆积密度 | bulk density before expansion [g/cm³]
    rBulkDensAfter  : REAL := 0.18;  // 膨胀后堆积密度 | bulk density after expansion [g/cm³]
END_VAR
VAR_OUTPUT
    rExpansionPct : REAL;            // 膨胀率 | expansion rate [%]
    xValid        : BOOL;            // 输出有效 | outputs valid
    nFaultCode    : INT;             // 0=无 / 9311=膨胀后密度非法 | 0 none, 9311 illegal post-expansion density
END_VAR
VAR
    xFinBefore : BOOL;               // 膨胀前密度有限性 | pre-expansion density is finite
    xFinAfter  : BOOL;               // 膨胀后密度有限性 | post-expansion density is finite
END_VAR
VAR CONSTANT
    DL_SER_DENS_MIN : REAL := 1.0E-9;   // 除零保护阈值 | division guard threshold [g/cm³]
END_VAR

// 段1｜非有限闸（R19）
xFinBefore := (rBulkDensBefore = rBulkDensBefore) AND ((rBulkDensBefore - rBulkDensBefore) = 0.0);
xFinAfter := (rBulkDensAfter = rBulkDensAfter) AND ((rBulkDensAfter - rBulkDensAfter) = 0.0);
IF (NOT xFinBefore) OR (NOT xFinAfter) THEN
    rExpansionPct := 0.0;            // 安全值：膨胀率 0 | safe value, zero rate
    xValid := FALSE;
    nFaultCode := 9311;
    FC_DL_StemExpansionRateCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：膨胀后密度入分母，必须为正；膨胀前密度不得为负
IF (rBulkDensAfter <= DL_SER_DENS_MIN) OR (rBulkDensBefore < 0.0) THEN
    rExpansionPct := 0.0;
    xValid := FALSE;
    nFaultCode := 9311;
    FC_DL_StemExpansionRateCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：rate = (before/after − 1)×100
rExpansionPct := (rBulkDensBefore / rBulkDensAfter - 1.0) * 100.0;
nFaultCode := 0;
xValid := TRUE;
FC_DL_StemExpansionRateCalc := TRUE;
END_FUNCTION
