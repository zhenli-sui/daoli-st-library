(* ============================================================
   DL_Device / FC_DL_OrpRefOffsetCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：ORP 参比电位偏移修正 E_ref(T) = E_ref(25°C) + k·(T − 25) [mV]，
         fOffsetMv 为加到读数上换到 SHE 的修正量，fRefCorrMv = E_ref(T) − 实测参比。
   边界：nRefType ∉ {0,1,2} → 按 SHE（0 mV、k=0）处理并返回 FALSE；
         温度 ∉ [−5, 80]°C → 钳定并返回 FALSE（温补系数不外推）；
         任一浮点入参非有限 → 两出口同拍写 0（N1）。签名无出口码，故各闸
         一律以返回值 FALSE 上报，闸序即归因序（类型 → 非有限 → 温度）。
         量纲清单（N5）：k 单位 mV/°C；Ag/AgCl(3.5M KCl)=+0.20、饱和甘汞 SCE=+0.24、
         SHE=0.0；回代：25°C Ag/AgCl 标称 199 mV → E_SHE = E_meas + 199。
   依赖：仅 IEC 61131-3（无外部依赖，纯算术） ｜ 溯源：DLF-D-WATERANA
   验收：E_meas=550/T=25/标称 199/实测 199/类型 0 → 修正 199 mV、偏移 0 mV、TRUE；
         nRefType=7 → 按 SHE 折算（修正 0 mV）并返回 FALSE。
   ============================================================ *)
FUNCTION FC_DL_OrpRefOffsetCalc : BOOL
VAR_INPUT
    fMeasMv       : REAL;  // ORP 表实测读数（相对自身参比）[mV] / Measured ORP reading against its own reference
    fRefNominalMv : REAL;  // 参比标称电位（25°C 相对 SHE）[mV] / Nominal reference potential at twenty five Celsius
    fRefMeasMv    : REAL;  // 参比实测电位（相对 SHE）[mV] / Measured reference potential against the hydrogen electrode
    fSampleTempC  : REAL;  // 水样温度 [°C] / Sample temperature in Celsius degrees
    nRefType      : DINT;  // 参比类型 0=Ag/AgCl 1=SCE 2=SHE [-] / Reference electrode type selector
END_VAR
VAR_OUTPUT
    fOffsetMv  : REAL;  // 换算到 SHE 的修正量（加到读数上）[mV] / Correction added to the reading to reach SHE
    fRefCorrMv : REAL;  // 实测参比相对标称的偏移 [mV] / Measured reference deviation from the nominal value
END_VAR
VAR
    _fT    : REAL;  // 钳定后温度 [°C] / Clamped temperature
    _fK    : REAL;  // 温补系数 [mV/°C] / Temperature coefficient of the reference electrode
    _fNom  : REAL;  // 实际采用的参比标称电位 [mV] / Nominal reference potential actually used
    _fRefT : REAL;  // 温度修正后参比电位 [mV] / Temperature corrected reference potential
    _bTLim : BOOL;  // 温度越域标志 [-] / Temperature out of range flag
    _bType : BOOL;  // 参比类型非法标志 [-] / Illegal reference type flag
END_VAR
VAR CONSTANT
    DL_ORP_TREF   : REAL := 25.0;   // 参考温度 [°C] / Reference temperature
    DL_ORP_TLO    : REAL := -5.0;   // 温度域下限 [°C] / Lower temperature bound
    DL_ORP_THI    : REAL := 80.0;   // 温度域上限 [°C] / Upper temperature bound
    DL_ORP_K_AGCL : REAL := 0.20;   // Ag/AgCl 温补系数 [mV/°C] / Temperature coefficient of the silver chloride reference
    DL_ORP_K_SCE  : REAL := 0.24;   // 饱和甘汞温补系数 [mV/°C] / Temperature coefficient of the calomel reference
END_VAR

(* 段 0：出口预置安全侧（两出口 0，N1/N3） *)
FC_DL_OrpRefOffsetCalc := FALSE;
fOffsetMv := 0.0;  fRefCorrMv := 0.0;
_bTLim := FALSE;   _bType := FALSE;

(* 段 1：非有限闸（四个浮点入参；NaN 自反 + Inf 差值自减双判，R79/R272） *)
IF (fMeasMv <> fMeasMv) OR (fRefNominalMv <> fRefNominalMv)
   OR (fRefMeasMv <> fRefMeasMv) OR (fSampleTempC <> fSampleTempC) THEN RETURN; END_IF
IF ((fMeasMv - fMeasMv) <> (fMeasMv - fMeasMv))
   OR ((fRefNominalMv - fRefNominalMv) <> (fRefNominalMv - fRefNominalMv))
   OR ((fRefMeasMv - fRefMeasMv) <> (fRefMeasMv - fRefMeasMv))
   OR ((fSampleTempC - fSampleTempC) <> (fSampleTempC - fSampleTempC)) THEN RETURN; END_IF

(* 段 2：参比类型分派（非法按 SHE，k=0、基准 0 mV） *)
CASE nRefType OF
0:      _fK := DL_ORP_K_AGCL;  _fNom := fRefNominalMv;
1:      _fK := DL_ORP_K_SCE;   _fNom := fRefNominalMv;
2:      _fK := 0.0;            _fNom := 0.0;
ELSE
    _fK := 0.0;  _fNom := 0.0;  _bType := TRUE;   // 非法类型：按 SHE 折算
END_CASE

(* 段 3：温度域闸（越域钳定，禁外推） *)
_fT := fSampleTempC;
IF fSampleTempC < DL_ORP_TLO THEN
    _fT := DL_ORP_TLO;  _bTLim := TRUE;
ELSIF fSampleTempC > DL_ORP_THI THEN
    _fT := DL_ORP_THI;  _bTLim := TRUE;
END_IF

(* 段 4：温度修正后的参比电位与偏移（乘加，无除法） *)
_fRefT := _fNom + _fK * (_fT - DL_ORP_TREF);

(* 段 5：单一出口裁决（两出口同源赋值一次，N4） *)
fOffsetMv  := _fRefT;
fRefCorrMv := _fRefT - fRefMeasMv;
IF (fOffsetMv <> fOffsetMv) OR (fRefCorrMv <> fRefCorrMv)
   OR ((fOffsetMv - fOffsetMv) <> (fOffsetMv - fOffsetMv))
   OR ((fRefCorrMv - fRefCorrMv) <> (fRefCorrMv - fRefCorrMv)) THEN
    fOffsetMv := 0.0;  fRefCorrMv := 0.0;   // 出口非有限：实值同拍写 0 且返回 FALSE（N1）
    RETURN;
END_IF
IF _bType OR _bTLim THEN
    FC_DL_OrpRefOffsetCalc := FALSE;    // 类型非法/温度越域：值照给，供上层记录
    RETURN;
END_IF
FC_DL_OrpRefOffsetCalc := TRUE;
END_FUNCTION
