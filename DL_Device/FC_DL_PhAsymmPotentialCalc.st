(* ============================================================
   DL_Device / FC_DL_PhAsymmPotentialCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：pH 零点不对称电位 E_asym = mV_meas + S(T)·(pH − 7.00) [mV]，
         S(T) = 59.16 × (273.15 + T) / 298.15 [mV/pH]（Nernst 温度修正）。
   边界：温度 ∉ [−5, 80]°C → 钳定后计算并报码 1（温补系数不许外推）；
         任一入参非有限 → 码 2、出口写 0（N1：判据与实值同源落安全侧）；
         |E_asym| > 30 mV → 码 3（电极钝化/污染），值照给供上层告警。
   依赖：仅 IEC 61131-3（ABS） ｜ 溯源：DLF-D-WATERANA（内部原创线）
   验收：mV=3.0/pH=7.00/T=25 → +3.0 mV、码 0；mV=+62.16/pH=6.00/T=25 →
         62.16 − 59.16 = +3.0 mV；T=100 → 钳到 80°C 计算、码 1（不外推）。
   ============================================================ *)
FUNCTION FC_DL_PhAsymmPotentialCalc : BOOL
VAR_INPUT
    fMvMeas : REAL;  // 电极实测电位 [mV] / Measured electrode potential in millivolts
    fPhMeas : REAL;  // 实测 pH 值（同点采样）[pH] / Measured pH value taken at the same instant
    fTempC  : REAL;  // 溶液温度 [°C] / Solution temperature in Celsius degrees
END_VAR
VAR_OUTPUT
    fAsymmV : REAL;   // 不对称电位（零点偏移）[mV] / Asymmetry potential, the zero point shift
    uErrId  : UDINT;  // 码 0 正常 / 1 温度越域 / 2 非有限 / 3 不对称超 30 mV [-] / Outlet code
END_VAR
VAR
    _fT     : REAL;  // 钳定后温度 [°C] / Clamped temperature
    _fSlope : REAL;  // 温度修正后理论斜率 [mV/pH] / Temperature corrected theoretical slope
    _fAsym  : REAL;  // 不对称电位中间值 [mV] / Intermediate asymmetry potential
    _bTLim  : BOOL;  // 温度越域标志 [-] / Temperature out of range flag
END_VAR
VAR CONSTANT
    DL_PHA_S25   : REAL := 59.16;   // 25 摄氏度理论斜率 [mV/pH] / Theoretical slope at twenty five Celsius
    DL_PHA_TREF  : REAL := 25.0;    // 参考温度 [°C] / Reference temperature
    DL_PHA_TK    : REAL := 273.15;  // 绝对零度偏移 [K] / Kelvin offset of the Celsius scale
    DL_PHA_TPT7  : REAL := 7.00;    // pH 零点 [pH] / Neutral pH reference point
    DL_PHA_TLO   : REAL := -5.0;    // 温度域下限 [°C] / Lower temperature bound
    DL_PHA_THI   : REAL := 80.0;    // 温度域上限 [°C] / Upper temperature bound
    DL_PHA_AMAX  : REAL := 30.0;    // 不对称电位接收上限 [mV] / Acceptance bound of the asymmetry
END_VAR

(* 段 0：出口预置安全侧（0 mV、码取最严，N1/N3） *)
FC_DL_PhAsymmPotentialCalc := FALSE;
fAsymmV := 0.0;  uErrId := 2;  _bTLim := FALSE;

(* 段 1：非有限闸（三入参 + 温度差） *)
IF (fMvMeas <> fMvMeas) OR (fPhMeas <> fPhMeas) OR (fTempC <> fTempC) THEN RETURN; END_IF
IF ((fTempC - fTempC) <> (fTempC - fTempC)) THEN RETURN; END_IF

(* 段 2：温度域闸（越域钳定并报码，禁外推） *)
_fT := fTempC;
IF fTempC < DL_PHA_TLO THEN
    _fT := DL_PHA_TLO;  _bTLim := TRUE;
ELSIF fTempC > DL_PHA_THI THEN
    _fT := DL_PHA_THI;  _bTLim := TRUE;
END_IF

(* 段 3：斜率与不对称电位（除子 298.15 为常量非零） *)
_fSlope := DL_PHA_S25 * (_fT + DL_PHA_TK) / (DL_PHA_TREF + DL_PHA_TK);
_fAsym  := fMvMeas + _fSlope * (fPhMeas - DL_PHA_TPT7);

(* 段 4：结果复检（非有限保持段 0 安全侧） *)
IF (_fAsym <> _fAsym) OR ((_fAsym - _fAsym) <> (_fAsym - _fAsym)) THEN RETURN; END_IF

(* 段 5：单一出口裁决（判据与出口同源于 _fAsym，N4/R23） *)
fAsymmV := _fAsym;
IF _bTLim THEN
    uErrId := 1;                        // 温度越域：值照给（已钳），FALSE 供上层记录
ELSIF ABS(_fAsym) > DL_PHA_AMAX THEN
    uErrId := 3;                        // 电极失效判据：值照给供上层告警
ELSE
    uErrId := 0;  FC_DL_PhAsymmPotentialCalc := TRUE;
END_IF
END_FUNCTION
