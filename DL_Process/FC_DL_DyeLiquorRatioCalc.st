(*
  DL Factory R83 | FC_DL_DyeLiquorRatioCalc
  功能：按织物重量与浴比算染浴总液量，并给出需补加液量与补加耗时。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_DyeLiquorRatioCalc : REAL
VAR_INPUT
    fFabricKg    : REAL; // 投染织物重量 [kg] / Fabric batch weight [kg]
    fLiquorRatio : REAL; // 浴比（每 kg 织物配液量）[L/kg] / Liquor ratio [L/kg]
    fBathVolL    : REAL; // 染缸现有液量 [L] / Existing bath volume [L]
    fAddRateLpm  : REAL; // 补水/补液流量 [L/min] / Replenish flow rate [L/min]
END_VAR
VAR_OUTPUT
    fTotalL : REAL; // 工艺要求总液量 [L] / Required total liquor volume [L]
    fAddL   : REAL; // 尚需补加液量（负偏差按零）[L] / Volume still to add, clamped at zero [L]
    fAddMin : REAL; // 补加所需时间 [min] / Time needed to add [min]
    xValid  : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fDiffL : REAL; // 总液量与现有液量之差 [L] / Volume difference [L]
END_VAR
fTotalL := 0.0; fAddL := 0.0; fAddMin := 0.0; xValid := FALSE;  // 出口预置（R256）
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fFabricKg > -1.0E30 AND fFabricKg < 1.0E30) OR NOT (fLiquorRatio > -1.0E30 AND fLiquorRatio < 1.0E30) OR NOT (fBathVolL > -1.0E30 AND fBathVolL < 1.0E30) OR NOT (fAddRateLpm > -1.0E30 AND fAddRateLpm < 1.0E30) OR fFabricKg <= 0.0 OR fLiquorRatio <= 0.0 OR fBathVolL < 0.0 THEN
    FC_DL_DyeLiquorRatioCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 浴比域闸：0.5~50 L/kg 之外钳位（工艺可执行区间）
IF fLiquorRatio < 0.5 THEN
    fLiquorRatio := 0.5;            // 下限钳位 [L/kg] / Clamp to 0.5 L/kg
ELSIF fLiquorRatio > 50.0 THEN
    fLiquorRatio := 50.0;           // 上限钳位 [L/kg] / Clamp to 50 L/kg
END_IF
// 总液量：kg × L/kg = L（量纲自洽，kg 约去）
fTotalL := fFabricKg * fLiquorRatio;   // 工艺总液量 [L] / Required total volume [L]
// 补加量：差值负值按零，避免抽液反算（单向补加语义）
fDiffL := fTotalL - fBathVolL;      // 液量差 [L] / Volume difference [L]
IF fDiffL > 0.0 THEN
    fAddL := fDiffL;                // 需要补加 [L] / Volume to add [L]
ELSE
    fAddL := 0.0;                   // 已够量，不抽液 [L] / Already sufficient [L]
END_IF
// 补加时间：L ÷ (L/min) = min，流量分母显式零闸（R4/R21）
IF ABS(fAddRateLpm) > 1.0E-9 THEN   // 分母显式零闸 / Explicit denominator zero gate
    fAddMin := fAddL / fAddRateLpm; // 补加时间 [min] / Add time [min]
ELSE
    fAddMin := 0.0;                 // 无流量时不可估时，缺省零 / No flow, default zero
END_IF
xValid := TRUE; FC_DL_DyeLiquorRatioCalc := fTotalL;  // 链路有效并返回总液量 [L] / Return volume
END_FUNCTION
