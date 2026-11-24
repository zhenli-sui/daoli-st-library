(*
  DL Factory R83 | FC_DL_FabricWeightAreaCalc
  功能：由试样质量与面积算单位面积克重，回潮修正后给出每米克重。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_FabricWeightAreaCalc : REAL
VAR_INPUT
    fSampleMassG   : REAL; // 试样质量 [g] / Sample mass [g]
    fSampleAreaCm2 : REAL; // 试样面积 [cm²] / Sample area [cm^2]
    fWidthM        : REAL; // 成品门幅 [m] / Finished fabric width [m]
    fMoisturePct   : REAL; // 回潮率（0~30）[%] / Moisture regain [%]
END_VAR
VAR_OUTPUT
    fGsm    : REAL; // 实测单位面积克重（含潮）[g/m²] / Measured grammage as-is [g/m^2]
    fGsmDry : REAL; // 公定回潮折算克重 [g/m²] / Grammage at standard regain [g/m^2]
    fGm     : REAL; // 每米克重（按门幅）[g/m] / Mass per running metre [g/m]
    xValid  : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    cCm2ToM2 : REAL := 10000.0; // cm²→m² 换算常量，已引用（R19）/ cm^2 to m^2 factor
END_VAR
// 出口预置：四出口统一预置（R256）
fGsm := 0.0; fGsmDry := 0.0; fGm := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fSampleMassG > -1.0E30 AND fSampleMassG < 1.0E30) OR NOT (fSampleAreaCm2 > -1.0E30 AND fSampleAreaCm2 < 1.0E30) OR NOT (fWidthM > -1.0E30 AND fWidthM < 1.0E30) OR NOT (fMoisturePct > -1.0E30 AND fMoisturePct < 1.0E30) OR fSampleMassG <= 0.0 OR fSampleAreaCm2 <= 0.0 OR fWidthM <= 0.0 OR fMoisturePct < -100.0 THEN
    FC_DL_FabricWeightAreaCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 回潮率域闸：0~30% 之外钳位（纺织常规区间）
IF fMoisturePct < 0.0 THEN
    fMoisturePct := 0.0;            // 下限钳位 [%] / Clamp lower bound
ELSIF fMoisturePct > 30.0 THEN
    fMoisturePct := 30.0;           // 上限钳位 [%] / Clamp upper bound
END_IF
// 实测克重：g ÷ cm² × 10000 = g/m²（面积分母已零闸，R4/R21；量纲 cm² 约去）
IF ABS(fSampleAreaCm2) > 1.0E-9 THEN          // 试样面积分母显式零闸 / Explicit zero gate
    fGsm := fSampleMassG / fSampleAreaCm2 * cCm2ToM2; // 实测克重 [g/m²] / Measured grammage
ELSE
    fGsm := 0.0;                    // 除零防御缺省 / Divide-by-zero default
END_IF
// 回潮折算：公定克重 = 实测 × 100 ÷ (100 + 回潮率)，分母因回潮率已钳非负而恒正
fGsmDry := fGsm * 100.0 / (100.0 + fMoisturePct); // 公定克重 [g/m²] / Standard-regain grammage
// 每米克重：g/m² × 门幅 m = g/m（m² 约去一维）
fGm    := fGsmDry * fWidthM;        // 每米克重 [g/m] / Mass per metre [g/m]
xValid := TRUE;                     // 链路有效 / Chain valid
FC_DL_FabricWeightAreaCalc := fGsm; // 返回实测克重 [g/m²] / Return measured grammage [g/m^2]
END_FUNCTION
