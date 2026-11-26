(* ============================================================
   DL_Device / FC_DL_DoSalinityPermCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：溶解氧膜渗透与盐度/温度修正
         C_corr = (C_raw + k_S · S) · K_perm · (1 + k_T · (T − 25)) [mg/L]，
         k_S = 0.084 mg/L 每 ‰（盐度使表观溶解度下降，故加回），k_T = 引脚 %/°C ÷ 100。
   边界：量程上限 ≤ 0 或渗透因子 ≤ 0 → 浓度写 0、返回 FALSE（N1/N3）；
         任一入参非有限 → 浓度写 0、返回 FALSE；盐度 < 0 按 0 处理且 bSalApplied=FALSE；
         C_corr 越出 [0, 上限] → 钳端点并置 bOutOfRange。签名无出口码，闸序即归因序。
         量纲清单（N5）：1 ‰ = 1 g/kg 盐度；k_S = 0.084 mg/L per ‰ = 84 µg/L 每 g/kg；
         回代：S = 35 ‰ 时表观溶解度下降 2.94 mg/L。
   依赖：仅 IEC 61131-3（无外部依赖，纯算术） ｜ 溯源：DLF-D-WATERANA
   验收：C=8.00/T=25/S=0/K=1.0/上限 20/kT=2.0 → 8.00 mg/L、未越限、TRUE；
         S=35 → (8.00 + 2.94) = 10.94 mg/L、bSalApplied=TRUE。
   ============================================================ *)
FUNCTION FC_DL_DoSalinityPermCalc : BOOL
VAR_INPUT
    fDoRaw       : REAL;  // 表读溶解氧浓度 [mg/L] / Dissolved oxygen reading from the probe
    fTempC       : REAL;  // 水温 [°C] / Water temperature in Celsius degrees
    fSalinityPpt : REAL;  // 盐度，有效域 ≥ 0 [‰] / Salinity in parts per thousand
    fPermK       : REAL;  // 膜渗透系标定因子，有效域 > 0 [-] / Membrane permeability calibration factor
    fDoMax       : REAL;  // 量程上限，有效域 > 0 [mg/L] / Upper range limit of the measurement
    fTempCoefPct : REAL;  // 温度修正系数（%/°C，可为负）[%/°C] / Temperature correction coefficient
END_VAR
VAR_OUTPUT
    fDoCorrMgL  : REAL;  // 修正后溶解氧浓度 [mg/L] / Corrected dissolved oxygen concentration
    bOutOfRange : BOOL;  // 修正值被钳到量程端点 [-] / Corrected value clamped to a range end
    bSalApplied : BOOL;  // 盐度修正已生效（盐度 > 0）[-] / Salinity correction actually applied
END_VAR
VAR
    _fSal : REAL;  // 归零后的盐度 [‰] / Normalized salinity
    _fKt  : REAL;  // 温度修正因子 (1 + k_T·(T−25)) [-] / Temperature correction factor
    _fC   : REAL;  // 修正中间值 [mg/L] / Intermediate corrected value
END_VAR
VAR CONSTANT
    DL_DOS_KS   : REAL := 0.084;  // 盐度溶解度系数 [mg/L per ‰] / Salinity solubility coefficient
    DL_DOS_TREF : REAL := 25.0;   // 参考温度 [°C] / Reference temperature
    DL_DOS_HUND : REAL := 100.0;  // 百分比换算系数 [%] / Percent conversion factor
END_VAR

(* 段 0：出口预置安全侧（0 mg/L、两标志置位，N1/N3） *)
FC_DL_DoSalinityPermCalc := FALSE;
fDoCorrMgL := 0.0;  bOutOfRange := TRUE;  bSalApplied := FALSE;

(* 段 1：非有限闸（六个入参全量枚举） *)
IF (fDoRaw <> fDoRaw) OR (fTempC <> fTempC) OR (fSalinityPpt <> fSalinityPpt)
   OR (fPermK <> fPermK) OR (fDoMax <> fDoMax) OR (fTempCoefPct <> fTempCoefPct) THEN RETURN; END_IF

(* 段 2：域闸（量程上限与渗透因子必须为正） *)
IF (fDoMax <= 0.0) OR (fPermK <= 0.0) THEN RETURN; END_IF

(* 段 3：盐度归零（负输入按 0 处理，并如实标记未生效） *)
IF fSalinityPpt > 0.0 THEN
    _fSal := fSalinityPpt;  bSalApplied := TRUE;
ELSE
    _fSal := 0.0;           bSalApplied := FALSE;
END_IF

(* 段 4：温度因子与修正（乘加，除子为常量 100） *)
_fKt := 1.0 + (fTempCoefPct / DL_DOS_HUND) * (fTempC - DL_DOS_TREF);
_fC  := (fDoRaw + DL_DOS_KS * _fSal) * fPermK * _fKt;

(* 段 5：结果复检（非有限保持段 0 安全侧） *)
IF (_fC <> _fC) OR ((_fC - _fC) <> (_fC - _fC)) THEN RETURN; END_IF

(* 段 6：单一出口裁决（判据与出口同源于 _fC，N4/R23） *)
bOutOfRange := ((_fC < 0.0) OR (_fC > fDoMax));
IF _fC < 0.0 THEN
    fDoCorrMgL := 0.0;                  // 负值保护：钳零后上报
ELSIF _fC > fDoMax THEN
    fDoCorrMgL := fDoMax;               // 饱和上报：钳顶后值仍可读
ELSE
    fDoCorrMgL := _fC;
END_IF
FC_DL_DoSalinityPermCalc := TRUE;
END_FUNCTION
