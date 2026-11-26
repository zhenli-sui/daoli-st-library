(* ============================================================
   DL_Device / FC_DL_PhSlopeEffCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：pH 电极斜率效率 fSlopePct = |S| / 59.16 × 100 [%]，
         S = (mV2 − mV1) / (pH2 − pH1) [mV/pH]，正常电极 S 为负值。
   边界：|ΔpH| ≤ 0.01 → 码 1（效率 0）；任一入参非有限 → 码 2（效率 0，N1 同拍改写）；
         效率 ∉ [85, 115]% → 码 3（效率照给 + bOutOfLim）。理论斜率取 25°C 名义
         59.16 mV/pH（R95 代理假设：覆盖 15~35°C 常规水样；恒温高精度场合由
         调用方按 Nernst 式补正后回灌，本件签名无温度引脚，不做温度修正）。
   依赖：仅 IEC 61131-3（ABS） ｜ 溯源：DLF-D-WATERANA（内部原创线）
   验收：mV1=0/pH1=7.00、mV2=+177.5/pH2=4.00 → S=−59.17、效率 100.0%、码 0；
         pH1=pH2 → 码 1、效率 0；效率 120% → 码 3、bOutOfLim=TRUE。
   ============================================================ *)
FUNCTION FC_DL_PhSlopeEffCalc : BOOL
VAR_INPUT
    fMv1 : REAL;  // 标定点 1 电极电位 [mV] / Electrode potential of calibration point one
    fPh1 : REAL;  // 标定点 1 的 pH 值 [pH] / pH value of calibration point one
    fMv2 : REAL;  // 标定点 2 电极电位 [mV] / Electrode potential of calibration point two
    fPh2 : REAL;  // 标定点 2 的 pH 值 [pH] / pH value of calibration point two
END_VAR
VAR_OUTPUT
    fSlopePct : REAL;   // 斜率效率 [%] / Slope efficiency in percent
    uErrId    : UDINT;  // 码 0 正常 / 1 两点重合 / 2 非有限 / 3 效率越限 [-] / Outlet code
    bOutOfLim : BOOL;   // 效率越出 85~115% [-] / Efficiency outside the acceptance band
END_VAR
VAR
    _fDph : REAL;  // pH 差 pH2 − pH1 [pH] / pH difference of the two points
    _fS   : REAL;  // 实测斜率 [mV/pH] / Measured slope in millivolts per pH
    _fEff : REAL;  // 效率中间值 [%] / Intermediate efficiency value
END_VAR
VAR CONSTANT
    DL_PHS_THEORY : REAL := 59.16;  // 25 摄氏度理论斜率 [mV/pH] / Theoretical slope at twenty five Celsius
    DL_PHS_MIND   : REAL := 0.01;   // 两点最小 pH 差 [pH] / Minimum pH distance of the two points
    DL_PHS_LO     : REAL := 85.0;   // 效率接收下限 [%] / Lower acceptance bound
    DL_PHS_HI     : REAL := 115.0;  // 效率接收上限 [%] / Upper acceptance bound
    DL_PHS_HUND   : REAL := 100.0;  // 百分比换算系数 [%] / Percent conversion factor
END_VAR

(* 段 0：出口预置安全侧（效率 0、越限置位，N1/N3） *)
FC_DL_PhSlopeEffCalc := FALSE;
fSlopePct := 0.0;  uErrId := 2;  bOutOfLim := TRUE;

(* 段 1：非有限闸（四入参 + 电位差） *)
IF (fMv1 <> fMv1) OR (fPh1 <> fPh1) OR (fMv2 <> fMv2) OR (fPh2 <> fPh2) THEN RETURN; END_IF
IF ((fMv2 - fMv1) - (fMv2 - fMv1)) <> ((fMv2 - fMv1) - (fMv2 - fMv1)) THEN RETURN; END_IF

(* 段 2：两点可分辨（pH 差域闸，防除零） *)
_fDph := fPh2 - fPh1;
IF ABS(_fDph) <= DL_PHS_MIND THEN uErrId := 1; RETURN; END_IF

(* 段 3：斜率与效率（除子已证 |ΔpH| > 0.01） *)
_fS   := (fMv2 - fMv1) / _fDph;
_fEff := ABS(_fS) / DL_PHS_THEORY * DL_PHS_HUND;
IF (_fEff <> _fEff) OR ((_fEff - _fEff) <> (_fEff - _fEff)) THEN RETURN; END_IF

(* 段 4：单一出口裁决（判据与出口同源于 _fEff，N4/R23） *)
fSlopePct := _fEff;
bOutOfLim := ((_fEff < DL_PHS_LO) OR (_fEff > DL_PHS_HI));
IF bOutOfLim THEN
    uErrId := 3;                        // 越限：效率照给，返回值 FALSE 供上层告警
ELSE
    uErrId := 0;  FC_DL_PhSlopeEffCalc := TRUE;
END_IF
END_FUNCTION
