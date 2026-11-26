(* ============================================================
   DL_Device / FC_DL_SodiumPnaCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：钠离子 pNa 换算 pNa = (0 − E_mv) / S(T) [−]，S(T) = S25 · (273.15 + T) / 298.15
         [mV/decade]；内部按 [Na] = 23 g/mol 折算 µg/L = 23 · 10^(6 − pNa) 用于量程判据。
   边界：斜率 ≤ 0 或温度越出 [−5, 80]°C → 钳定后仍不可解：pNa 写 0、bOutOfRange=TRUE；
         任一入参非有限 → pNa 写 0、bOutOfRange=TRUE（N1 安全侧）；
         nSlopeSel：0=理论斜率 59.16，1=实测钠电极斜率 56.0，其余按理论斜率并
         判为量程外（档位非法）。签名只有一个 REAL 出口，故 pNa 为主出口，
         µg/L 仅在内部参与量程判据（本件相对规划的收窄点，不改签名）。
         量纲清单（N5）：1 mol/L NaCl = 23 g/L；1 mg/L = 1000 µg/L；
         量程 0.1 ~ 100000 µg/L ↔ pNa 8.36 ~ 2.36。
   依赖：仅 IEC 61131-3（EXPT / ABS） ｜ 溯源：DLF-D-WATERANA
   验收：mV=−325、T=25、档位 0 → S=59.16 → pNa≈5.494、未越限；
         档位 1 → S=56.0 → pNa≈5.804；斜率不可解 → pNa=0、越限。
   ============================================================ *)
FUNCTION FC_DL_SodiumPnaCalc : BOOL
VAR_INPUT
    fMvMeas   : REAL;  // 钠电极实测电位 [mV] / Measured sodium electrode potential
    fTempC    : REAL;  // 水样温度 [°C] / Sample temperature in Celsius degrees
    nSlopeSel : INT;   // 斜率档位 0=理论 1=实测钠电极 [-] / Slope selector
END_VAR
VAR_OUTPUT
    fPna        : REAL;  // 钠离子 pNa 值 [-] / Sodium pNa value
    bOutOfRange : BOOL;  // pNa 越出测量量程或输入非法 [-] / pNa outside the measurement range or illegal input
END_VAR
VAR
    _fT     : REAL;  // 钳定后温度 [°C] / Clamped temperature
    _fS25   : REAL;  // 25°C 下的斜率基值 [mV/decade] / Slope base at twenty five Celsius
    _fSlope : REAL;  // 温度修正后斜率 [mV/decade] / Temperature corrected slope
    _fPna   : REAL;  // pNa 中间值 [-] / Intermediate pNa value
    _fUgL   : REAL;  // 折算钠浓度 [µg/L] / Converted sodium concentration
    _bBad   : BOOL;  // 输入或档位非法标志 [-] / Illegal input or selector flag
END_VAR
VAR CONSTANT
    DL_SOD_S25  : REAL := 59.16;    // 25 摄氏度理论斜率 [mV/decade] / Theoretical slope at twenty five Celsius
    DL_SOD_S56  : REAL := 56.0;     // 实测钠电极斜率（25°C）[mV/decade] / Measured sodium electrode slope
    DL_SOD_TREF : REAL := 25.0;     // 参考温度 [°C] / Reference temperature
    DL_SOD_TK   : REAL := 273.15;   // 绝对零度偏移 [K] / Kelvin offset of the Celsius scale
    DL_SOD_TLO  : REAL := -5.0;     // 温度域下限 [°C] / Lower temperature bound
    DL_SOD_THI  : REAL := 80.0;     // 温度域上限 [°C] / Upper temperature bound
    DL_SOD_MOL  : REAL := 23.0;     // 钠摩尔质量 [g/mol] / Molar mass of sodium
    DL_SOD_UGLO : REAL := 0.1;      // 折算浓度下限 [µg/L] / Lower bound of the converted concentration
    DL_SOD_UGHI : REAL := 100000.0; // 折算浓度上限 [µg/L] / Upper bound of the converted concentration
    DL_SOD_DEC  : REAL := 6.0;      // pNa → µg/L 的十进制移位 [-] / Decade shift from pNa to micrograms per liter
END_VAR

(* 段 0：出口预置安全侧（pNa 0、越限置位，N1/N3） *)
FC_DL_SodiumPnaCalc := FALSE;
fPna := 0.0;  bOutOfRange := TRUE;
_bBad := FALSE;

(* 段 1：非有限闸（两个浮点入参） *)
IF (fMvMeas <> fMvMeas) OR (fTempC <> fTempC) THEN RETURN; END_IF

(* 段 2：温度域闸（越域钳定并判为越限，禁外推） *)
_fT := fTempC;
IF fTempC < DL_SOD_TLO THEN
    _fT := DL_SOD_TLO;  _bBad := TRUE;
ELSIF fTempC > DL_SOD_THI THEN
    _fT := DL_SOD_THI;  _bBad := TRUE;
END_IF

(* 段 3：斜率分派（非法档位按理论斜率并判越限） *)
CASE nSlopeSel OF
0:      _fS25 := DL_SOD_S25;
1:      _fS25 := DL_SOD_S56;
ELSE
    _fS25 := DL_SOD_S25;  _bBad := TRUE;
END_CASE
_fSlope := _fS25 * (_fT + DL_SOD_TK) / (DL_SOD_TREF + DL_SOD_TK);

(* 段 4：pNa 与折算浓度（除子已证 > 0，S25 恒为正） *)
IF _fSlope <= 0.0 THEN RETURN; END_IF
_fPna := (0.0 - fMvMeas) / _fSlope;
IF (_fPna <> _fPna) OR ((_fPna - _fPna) <> (_fPna - _fPna)) THEN RETURN; END_IF
_fUgL := DL_SOD_MOL * EXPT(10.0, DL_SOD_DEC - _fPna);

(* 段 5：单一出口裁决（判据与出口同源于 _fPna/_fUgL，N4/R23） *)
IF _bBad OR (_fUgL <> _fUgL) OR ((_fUgL - _fUgL) <> (_fUgL - _fUgL)) THEN
    fPna := 0.0;                        // 非有限或组态非法：落安全侧
    bOutOfRange := TRUE;
    RETURN;
END_IF
IF (_fUgL < DL_SOD_UGLO) OR (_fUgL > DL_SOD_UGHI) THEN
    fPna := _fPna;                      // 出量程：值照给供上层记录
    bOutOfRange := TRUE;
    RETURN;
END_IF
fPna := _fPna;
bOutOfRange := FALSE;
FC_DL_SodiumPnaCalc := TRUE;
END_FUNCTION
