(* ============================================================
   DL_Device / FC_DL_ChlorineDpdAbsorbCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：DPD 比色吸光度 → 余氯。slope = 满量程浓度 / 满量程吸光度 [mg/L per AU]，
         C = slope · (A_meas − A_zero)，再按量程钳制。
   边界：满量程吸光度 ≤ 1E-6（未标定/空皿）→ 浓度与斜率同拍写 0、返回 FALSE（N1）；
         任一浮点入参非有限 → 两出口写 0、返回 FALSE；
         nRangeSel：0=低量程 2.00 mg/L、1=高量程 5.00 mg/L，其余按低量程处理并
         返回 FALSE（档位非法）。C 越出 [0, 满量程] → 钳端点并置 bOutOfRange。
         签名无出口码，闸序即归因序（非有限 → 满量程非法 → 档位非法）。
         量纲清单（N5）：吸光度 AU 无量纲；1 AU 满量程对应档位浓度；DPD 摩尔
         吸光系数已并入斜率，不再单独换算。
   依赖：仅 IEC 61131-3（无外部依赖，纯算术） ｜ 溯源：DLF-D-WATERANA
   验收：A=0.40/A_zero=0.02/A_span=1.00/档位 0 → slope=2.0、C=0.76 mg/L；
         档位 1 → slope=5.0、C=1.90 mg/L；A_span=0 → 两出口 0、返回 FALSE。
   ============================================================ *)
FUNCTION FC_DL_ChlorineDpdAbsorbCalc : BOOL
VAR_INPUT
    fAbsMeas  : REAL;  // 样品吸光度 [AU] / Absorbance of the sample
    fAbsZero  : REAL;  // 空白（零点）吸光度 [AU] / Absorbance of the blank reference
    fAbsSpan  : REAL;  // 满量程吸光度，有效域 > 1E-6 [AU] / Full scale absorbance
    nRangeSel : INT;   // 量程档位 0=2.00 mg/L 1=5.00 mg/L [-] / Measurement range selector
END_VAR
VAR_OUTPUT
    fChlorineMgL : REAL;  // 余氯浓度 [mg/L] / Free chlorine concentration
    fSlopeMgLAu  : REAL;  // 换算斜率 [mg/L per AU] / Conversion slope in mg per liter per absorbance unit
    bOutOfRange  : BOOL;  // 换算值被钳到量程端点 [-] / Value clamped to a range end
END_VAR
VAR
    _fFull : REAL;  // 档位满量程浓度 [mg/L] / Full scale concentration of the selected range
    _fSlo  : REAL;  // 斜率中间值 [mg/L per AU] / Intermediate slope value
    _fC    : REAL;  // 浓度中间值 [mg/L] / Intermediate concentration value
    _bRng  : BOOL;  // 档位非法标志 [-] / Illegal range selector flag
END_VAR
VAR CONSTANT
    DL_DPD_RANGE_LO : REAL := 2.00;    // 低量程满量程 [mg/L] / Low range full scale
    DL_DPD_RANGE_HI : REAL := 5.00;    // 高量程满量程 [mg/L] / High range full scale
    DL_DPD_EPS      : REAL := 1.0E-6;  // 满量程吸光度判零下限 [AU] / Zero floor of the full scale absorbance
END_VAR

(* 段 0：出口预置安全侧（两出口 0、越限置位，N1/N3） *)
FC_DL_ChlorineDpdAbsorbCalc := FALSE;
fChlorineMgL := 0.0;  fSlopeMgLAu := 0.0;  bOutOfRange := TRUE;
_bRng := FALSE;

(* 段 1：非有限闸（三个浮点入参；NaN 自反 + Inf 差值自减双判，R79/R272） *)
IF (fAbsMeas <> fAbsMeas) OR (fAbsZero <> fAbsZero) OR (fAbsSpan <> fAbsSpan) THEN RETURN; END_IF
(* Inf 双判须覆盖 fAbsSpan：满量程 +Inf 使斜率算成 0、浓度算成 0 却返回 TRUE（假安全） *)
IF ((fAbsMeas - fAbsMeas) <> (fAbsMeas - fAbsMeas))
   OR ((fAbsZero - fAbsZero) <> (fAbsZero - fAbsZero))
   OR ((fAbsSpan - fAbsSpan) <> (fAbsSpan - fAbsSpan)) THEN RETURN; END_IF

(* 段 2：满量程域闸（防除零，除子在段 4 才使用） *)
IF ABS(fAbsSpan) <= DL_DPD_EPS THEN RETURN; END_IF

(* 段 3：档位分派（非法按低量程，归因独立） *)
CASE nRangeSel OF
0:      _fFull := DL_DPD_RANGE_LO;
1:      _fFull := DL_DPD_RANGE_HI;
ELSE
    _fFull := DL_DPD_RANGE_LO;  _bRng := TRUE;
END_CASE

(* 段 4：斜率与浓度（除子已证 > 1E-6） *)
_fSlo := _fFull / fAbsSpan;
_fC   := _fSlo * (fAbsMeas - fAbsZero);

(* 段 5：结果复检（非有限保持段 0 安全侧） *)
IF (_fC <> _fC) OR ((_fC - _fC) <> (_fC - _fC)) THEN RETURN; END_IF

(* 段 6：单一出口裁决（判据与出口同源于 _fC 与 _fFull，N4/R23） *)
fSlopeMgLAu := _fSlo;
bOutOfRange := ((_fC < 0.0) OR (_fC > _fFull));
IF _fC < 0.0 THEN
    fChlorineMgL := 0.0;                // 负值保护：钳零后上报
ELSIF _fC > _fFull THEN
    fChlorineMgL := _fFull;             // 饱和上报：钳顶后值仍可读
ELSE
    fChlorineMgL := _fC;
END_IF
FC_DL_ChlorineDpdAbsorbCalc := NOT _bRng;    // 档位非法：值照给、返回 FALSE
END_FUNCTION
