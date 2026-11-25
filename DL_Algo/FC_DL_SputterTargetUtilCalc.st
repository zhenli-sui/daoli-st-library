(*
  DL Factory R88 | FC_DL_SputterTargetUtilCalc
  功能：按侵蚀环近似算靶材利用率 =已用体积 π(R²-r²)h / 靶体积 πR²t（π 对消），超 80% 提示换靶
  开源溯源：无（clean-room 自研，依据公开工艺公式 靶材利用率体积比定义式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_SputterTargetUtilCalc : REAL
VAR_INPUT
    fTargetRmm : REAL := 150.0; // 靶材有效半径 R [mm] / target radius [mm]
    fErosionRmm : REAL := 80.0; // 侵蚀环内边界半径 r（环宽 R-r） [mm] / erosion ring inner radius [mm]
    fErosionDepthMm : REAL := 4.0; // 侵蚀环最大深度 h [mm] / erosion depth [mm]
    fTargetThkMm : REAL := 10.0; // 靶材原始厚度 t [mm] / original target thickness [mm]
    fReplacePct : REAL := 80.0; // 换靶提示阈值（利用率超过即换靶） [%] / replacement threshold [%]
END_VAR
VAR_OUTPUT
    fUtilPct : REAL; // 靶材利用率（体积比） [%] / target utilisation [%]
    xReplace : BOOL; // TRUE=利用率超过阈值，需换靶 [-] / TRUE when replacement is due [-]
END_VAR
VAR
    fTargetVolMm3 : REAL; // 靶材总体积 πR²t（除零判据） [mm³] / total target volume, the divisor [mm^3]
    fR2MinusR2 : REAL; // R²-r²（符号闸判据） [mm²] / difference of squares [mm^2]
END_VAR

// 段 1｜出口预置
FC_DL_SputterTargetUtilCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fUtilPct := 0.0; // 利用率预置零 [%] / utilisation preset zero [%]
xReplace := FALSE; // 换靶位预置 FALSE（未判定前不提示） [-] / replace flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fTargetRmm > -1.0E30 AND fTargetRmm < 1.0E30) OR NOT (fErosionRmm > -1.0E30 AND fErosionRmm < 1.0E30) OR NOT (fErosionDepthMm > -1.0E30 AND fErosionDepthMm < 1.0E30) THEN
    RETURN; // 靶半径/侵蚀半径/侵蚀深度任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fTargetThkMm > -1.0E30 AND fTargetThkMm < 1.0E30) OR NOT (fReplacePct > -1.0E30 AND fReplacePct < 1.0E30) THEN
    RETURN; // 靶厚/换靶阈值任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fTargetRmm < 1.0E-9 OR fTargetThkMm < 1.0E-9 OR fErosionDepthMm < 0.0 THEN
    RETURN; // 靶半径/靶厚正域闸（分母）+ 侵蚀深度非负闸 [mm] / positive geometry gates [mm]
END_IF
IF fErosionRmm < 0.0 OR fErosionRmm >= fTargetRmm THEN
    RETURN; // 侵蚀环几何闸：0≤r<R，否则环带面积为零或负 [mm] / erosion ring geometry gate [mm]
END_IF
IF fReplacePct <= 0.0 OR fReplacePct > 100.0 THEN
    RETURN; // 换靶阈值区间闸 (0,100]：超出则判据无意义 [%] / replacement threshold gate [%]
END_IF

// 段 3｜计算（侵蚀环按矩形截面近似，π 在比值中约去）
fR2MinusR2 := fTargetRmm * fTargetRmm - fErosionRmm * fErosionRmm; // mm² - mm² = mm²，环带相当面积 [mm²] / [mm^2]
fTargetVolMm3 := 3.14159265 * fTargetRmm * fTargetRmm * fTargetThkMm; // 无量纲 × mm² × mm = mm³，靶体积 [mm³] / [mm^3]
IF fR2MinusR2 <= 0.0 OR fTargetVolMm3 < 1.0E-9 THEN
    RETURN; // 平方差闸 + 除法前分母闸：两者须为正，否则体积链失效 [mm², mm³] / volume chain gates
END_IF
fUtilPct := 3.14159265 * fR2MinusR2 * fErosionDepthMm / fTargetVolMm3 * 100.0; // (mm³ ÷ mm³) × 100 = %，体积利用率 [%] / [%]

// 段 4｜判定与饱和
IF NOT (fUtilPct > -1.0E30 AND fUtilPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
IF fUtilPct > 100.0 THEN
    fUtilPct := 100.0; // 上饱和：体积比不可能超过 100%，超出按 100% 夹紧 [%] / saturate at 100 percent [%]
END_IF
xReplace := fUtilPct > fReplacePct; // 严格大于阈值为需换靶，等于阈值仍可继续 [%] / strict compare [%]

// 段 5｜出口自检
IF fUtilPct < 0.0 THEN
    RETURN; // 出口自检：利用率不得为负（负值说明几何参数错） [%] / utilisation must not be negative [%]
END_IF
FC_DL_SputterTargetUtilCalc := fUtilPct; // 返回靶材利用率 [%] / return the target utilisation [%]
END_FUNCTION
