(* ============================================================
   DL_Device / FC_DL_KcellConstCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：电导池常数标定反算 Kcell = σ_std · R_meas [1/cm]（σ 由 µS/cm ×1E-6 转 S/cm），
         温度修正 K_tcorr = Kcell / (1 + α·(T − 25))，α = fTempCoefPct / 100。
   边界：标准液电导率 ≤ 0 或实测电阻 ≤ 0 → 两出口写 0、码 1（N1：值与判据同拍改写）；
         任一入参非有限 → 两出口写 0、码 2；温补分母 ≤ 0.01 → 码 3 且温度修正值
         回退为未修正值（不给伪修正结果）。
         量纲清单（N5）：1 S/cm = 1E6 µS/cm；1 Ω⁻¹ = 1 S；Kcell 单位 1/cm；
         回代：σ=1413 µS/cm、R=100 Ω → 0.1413 1/cm。
   依赖：仅 IEC 61131-3（无外部依赖，纯算术） ｜ 溯源：DLF-D-WATERANA
   验收：1413 µS/cm、100 Ω → Kcell=0.1413 1/cm、码 0；T=35、α=2%/°C →
         K_tcorr = 0.1413 / 1.2 = 0.1178 1/cm；σ=0 → 码 1、两出口 0。
   ============================================================ *)
FUNCTION FC_DL_KcellConstCalc : BOOL
VAR_INPUT
    fStdUsCm     : REAL;  // 标准液电导率（25°C 标称值）[µS/cm] / Conductivity of the standard solution
    fRMeasOhm    : REAL;  // 实测电导池电阻 [Ω] / Measured conductivity cell resistance
    fTempC       : REAL;  // 标准液实测温度 [°C] / Measured temperature of the standard solution
    fTempCoefPct : REAL;  // 电导率温补系数（%/°C，常取 2.0）[%/°C] / Conductivity temperature coefficient
END_VAR
VAR_OUTPUT
    fKcell      : REAL;   // 未温度修正的池常数 [1/cm] / Cell constant without temperature correction
    fKcellTcorr : REAL;   // 温度修正后池常数 [1/cm] / Temperature corrected cell constant
    uErrId      : UDINT;  // 码 0 正常 / 1 域闸 / 2 非有限 / 3 温补分母非法 [-] / Outlet code
END_VAR
VAR
    _fK     : REAL;  // 未修正池常数中间值 [1/cm] / Intermediate uncorrected cell constant
    _fDen   : REAL;  // 温补分母 (1 + α·(T−25)) [-] / Temperature correction denominator
    _bDen   : BOOL;  // 温补分母非法标志 [-] / Illegal denominator flag
END_VAR
VAR CONSTANT
    DL_KCL_US_TO_S : REAL := 1.0E-6;  // µS/cm → S/cm 换算系数 [S·cm/µS] / Microsiemens per centimeter to siemens per centimeter
    DL_KCL_TREF    : REAL := 25.0;    // 参考温度 [°C] / Reference temperature
    DL_KCL_HUND    : REAL := 100.0;   // 百分比换算系数 [%] / Percent conversion factor
    DL_KCL_DFLOOR  : REAL := 0.01;    // 温补分母下限 [-] / Lower bound of the temperature denominator
    DL_KCL_DCEIL   : REAL := 10.0;    // 温补分母上限（防分母虚高致池常数偏低）[-] / Upper bound of the temperature denominator
END_VAR

(* 段 0：出口预置安全侧（两出口 0、码取最严，N1/N3） *)
FC_DL_KcellConstCalc := FALSE;
fKcell := 0.0;  fKcellTcorr := 0.0;  uErrId := 2;
_bDen := FALSE;

(* 段 1：非有限闸（四个入参全量枚举；NaN 自反 + Inf 差值自减双判，R79/R272） *)
IF (fStdUsCm <> fStdUsCm) OR (fRMeasOhm <> fRMeasOhm)
   OR (fTempC <> fTempC) OR (fTempCoefPct <> fTempCoefPct) THEN RETURN; END_IF
(* Inf 双判须覆盖 fTempC：温度 +Inf 使温补分母为 Inf、修正值算成 0，却报 uErrId=0
   成功（伪有效池常数，下游按 k=0 换算全量程失真） *)
IF ((fStdUsCm - fStdUsCm) <> (fStdUsCm - fStdUsCm))
   OR ((fRMeasOhm - fRMeasOhm) <> (fRMeasOhm - fRMeasOhm))
   OR ((fTempC - fTempC) <> (fTempC - fTempC))
   OR ((fTempCoefPct - fTempCoefPct) <> (fTempCoefPct - fTempCoefPct)) THEN RETURN; END_IF

(* 段 2：域闸（电导率与电阻必须为正，防零与负物理量） *)
IF (fStdUsCm <= 0.0) OR (fRMeasOhm <= 0.0) THEN
    uErrId := 1;                        // 域闸：无池常数可解
    RETURN;
END_IF

(* 段 3：池常数（乘加，无除法） *)
_fK := fStdUsCm * DL_KCL_US_TO_S * fRMeasOhm;
IF (_fK <> _fK) OR ((_fK - _fK) <> (_fK - _fK)) THEN RETURN; END_IF

(* 段 4：温补分母（除子结构判定，不做伪修正） *)
_fDen := 1.0 + (fTempCoefPct / DL_KCL_HUND) * (fTempC - DL_KCL_TREF);
IF (_fDen <= DL_KCL_DFLOOR) OR (_fDen > DL_KCL_DCEIL) THEN _bDen := TRUE; END_IF   // 双端闸：分母过小放大、过大压缩均判非法 / two-sided guard

(* 段 5：单一出口裁决（两出口同源赋值一次，N4/R23） *)
fKcell := _fK;
IF _bDen THEN
    fKcellTcorr := _fK;                 // 分母非法：回退未修正值
    uErrId      := 3;
ELSE
    fKcellTcorr := _fK / _fDen;         // 分母已证 > 0.01
    uErrId      := 0;  FC_DL_KcellConstCalc := TRUE;
END_IF

(* 段 6：出口非有限复检（同族补修：比值溢出同样禁报码 0 成功，N1） *)
IF (fKcell <> fKcell) OR ((fKcell - fKcell) <> (fKcell - fKcell))
   OR (fKcellTcorr <> fKcellTcorr) OR ((fKcellTcorr - fKcellTcorr) <> (fKcellTcorr - fKcellTcorr)) THEN
    fKcell := 0.0;  fKcellTcorr := 0.0;  uErrId := 2;  FC_DL_KcellConstCalc := FALSE;
END_IF
END_FUNCTION
