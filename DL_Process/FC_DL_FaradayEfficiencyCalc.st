(*
  DL Factory R83 | FC_DL_FaradayEfficiencyCalc
  功能：用「天平实测增重」与「法拉第理论量」两条独立路径反算镀液电流效率。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_FaradayEfficiencyCalc : REAL
VAR_INPUT
    fCurrentA   : REAL; // 实测槽电流 [A] / Measured bath current [A]
    fTimeS      : REAL; // 通电时间 [s] / Plating time [s]
    fMassGainG  : REAL; // 天平实测增重（独立路径 B）[g] / Measured mass gain, path B [g]
    fEquivMgC   : REAL; // 电化当量 [mg/C] / Electrochemical equivalent [mg/C]
    fDepAreaDm2 : REAL; // 受镀面积（量纲自检用）[dm²] / Plated area for dimension check [dm^2]
END_VAR
VAR_OUTPUT
    fEffPct     : REAL; // 电流效率 [%] / Current efficiency [%]
    fMassTheoG  : REAL; // 理论沉积质量（路径 A，纯法拉第）[g] / Theoretical mass, path A [g]
    fMassAreaG  : REAL; // 实测单位面积增重（路径 B 派生）[g/dm²] / Measured mass per area [g/dm^2]
    xValid      : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fRatio : REAL; // 实测/理论质量比 [-] / Measured-over-theoretical mass ratio
END_VAR
// 出口预置：四出口统一预置（R256）
fEffPct := 0.0; fMassTheoG := 0.0; fMassAreaG := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fCurrentA > -1.0E30 AND fCurrentA < 1.0E30) OR NOT (fTimeS > -1.0E30 AND fTimeS < 1.0E30) OR NOT (fMassGainG > -1.0E30 AND fMassGainG < 1.0E30) OR NOT (fEquivMgC > -1.0E30 AND fEquivMgC < 1.0E30) OR NOT (fDepAreaDm2 > -1.0E30 AND fDepAreaDm2 < 1.0E30) OR fCurrentA <= 0.0 OR fTimeS <= 0.0 OR fMassGainG <= 0.0 OR fEquivMgC <= 0.0 OR fDepAreaDm2 <= 0.0 THEN
    FC_DL_FaradayEfficiencyCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 路径 A（理论，纯法拉第）：只用电流与时间，完全不接触天平值
// mg/C ÷ 1000 = g/C；g/C × A × s = g（量纲自洽：1 C = 1 A·s）
fMassTheoG := (fEquivMgC / 1000.0) * fCurrentA * fTimeS; // 理论沉积质量 [g] / Theoretical mass [g]
// 路径 B（实测，称重法）：天平增重 ÷ 受镀面积得单位面积实测增重 [g/dm²]
fMassAreaG := fMassGainG / fDepAreaDm2;                  // 实测单位面积增重 [g/dm²]
// 效率：实测 ÷ 理论 × 100；理论量分母显式零闸（R4/R21）
IF ABS(fMassTheoG) > 1.0E-9 THEN                         // 理论量分母显式零闸 / Explicit zero gate
    fRatio := fMassGainG / fMassTheoG;                   // 质量比 [-] / Mass ratio
ELSE
    fRatio := 0.0;                                       // 除零防御缺省 / Divide-by-zero default
END_IF
// 量纲自检：效率物理上限取 120%（含阳极副反应容差），越界判采集异常
IF fRatio > 0.0 AND fRatio < 1.2 THEN
    fEffPct := fRatio * 100.0;      // 电流效率 [%] / Current efficiency [%]
    xValid  := TRUE;                // 采集链路可信 / Measurement chain trustworthy
ELSE
    fEffPct := 0.0;                 // 超物理上限或非正增重，判无效 / Over limit or non-positive, invalid
END_IF
FC_DL_FaradayEfficiencyCalc := fEffPct; // 返回电流效率 [%] / Return current efficiency [%]
END_FUNCTION
