(* ============================================================
   DL_Device / FC_DL_AnalyzerRecalDaysCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：距重新标定天数 nDays = (fDriftLimit − |fDriftNow|) / |fDriftRate| − 已标定天数，
         已标定天数由 tSinceCal 折算（1 天 = 86400 s = 8.64E7 ms）。负值即已超标。
   边界：|fDriftRate| ≤ 1E-9 → 返回哨兵 32767 天、bOverdue=FALSE（永不超期，防除零）；
         允许漂移上限 ≤ 0 → 天数 0、bOverdue=TRUE（组态非法按已超期，安全侧）；
         任一浮点入参非有限 → 天数 0、bOverdue=TRUE（N1）；
         实数转 INT 前先钳到 ±32000（R151：防溢出导致方向翻转）。
         量纲清单（N5）：fDriftRate 为「标定单位/天」，与 fDriftLimit、fDriftNow 同量纲；
         1 天 = 86400 s；TIME_TO_REAL 返回 [ms]，故天数 = ms / 1000 / 86400。
   依赖：仅 IEC 61131-3（ABS / TIME_TO_REAL / REAL_TO_INT） ｜ 溯源：DLF-D-WATERANA
   验收：limit=2.0、now=0.5、rate=0.05/天、已过 10 天 → 1.5/0.05 − 10 = 20 天、FALSE；
         rate=0 → 32767 天；now=2.5 → 负值且 bOverdue=TRUE。
   ============================================================ *)
FUNCTION FC_DL_AnalyzerRecalDaysCalc : BOOL
VAR_INPUT
    fDriftRate  : REAL;  // 漂移速率（标定单位/天，符号无关）[单位/天] / Drift rate per day
    fDriftLimit : REAL;  // 允许总漂移上限 [单位] / Allowed total drift
    fDriftNow   : REAL;  // 当前累计漂移 [单位] / Current accumulated drift
    tSinceCal   : TIME;  // 距上次标定的时长 [ms] / Elapsed time since the last calibration
END_VAR
VAR_OUTPUT
    nDays    : INT;   // 距重新标定的天数（负值 = 已超标）[天] / Days until recalibration, negative means overdue
    bOverdue : BOOL;  // 已超期 [-] / Recalibration overdue
END_VAR
VAR
    _fRate : REAL;  // 漂移速率绝对值 [单位/天] / Absolute drift rate
    _fEla  : REAL;  // 已标定天数 [天] / Days elapsed since the last calibration
    _fRem  : REAL;  // 允许剩余漂移 [单位] / Allowed remaining drift
    _fDay  : REAL;  // 剩余天数（钳定前）[天] / Remaining days before clamping
END_VAR
VAR CONSTANT
    DL_RDC_SEC_DAY  : REAL := 86400.0;   // 每天的秒数 [s/天] / Seconds per day
    DL_RDC_MS_S     : REAL := 1000.0;    // 毫秒 → 秒换算系数 [ms/s] / Milliseconds per second
    DL_RDC_RATE_EPS : REAL := 1.0E-9;    // 漂移速率判零下限 [单位/天] / Zero floor of the drift rate
    DL_RDC_DMAX     : REAL := 32000.0;   // 实数域钳制上限（INT 可表）[天] / Real domain clamp bound
    DL_RDC_SENTINEL : INT  := 32767;     // 永不超期哨兵值 [天] / Sentinel value for never overdue
END_VAR

(* 段 0：出口预置安全侧（0 天 = 立即需标定，N1/N3） *)
FC_DL_AnalyzerRecalDaysCalc := FALSE;
nDays := 0;  bOverdue := TRUE;

(* 段 1：非有限闸（三个浮点入参） *)
IF (fDriftRate <> fDriftRate) OR (fDriftLimit <> fDriftLimit) OR (fDriftNow <> fDriftNow) THEN RETURN; END_IF

(* 段 2：组态闸（允许漂移上限必须为正，否则按已超期） *)
IF fDriftLimit <= 0.0 THEN RETURN; END_IF

(* 段 3：漂移速率判零闸（近零速率 → 永不超期哨兵） *)
_fRate := ABS(fDriftRate);
IF _fRate <= DL_RDC_RATE_EPS THEN
    nDays := DL_RDC_SENTINEL;
    bOverdue := FALSE;                  // 漂移几乎为零：不报超期
    FC_DL_AnalyzerRecalDaysCalc := TRUE;
    RETURN;
END_IF

(* 段 4：剩余天数（除子已证 > 1E-9） *)
_fEla := TIME_TO_REAL(tSinceCal) / DL_RDC_MS_S / DL_RDC_SEC_DAY;
_fRem := fDriftLimit - ABS(fDriftNow);
_fDay := _fRem / _fRate - _fEla;
IF (_fDay <> _fDay) OR ((_fDay - _fDay) <> (_fDay - _fDay)) THEN RETURN; END_IF

(* 段 5：单一出口裁决（先钳后转型，判据与出口同源于 _fDay，N4/R23） *)
IF _fDay > DL_RDC_DMAX THEN
    _fDay := DL_RDC_DMAX;
ELSIF _fDay < (0.0 - DL_RDC_DMAX) THEN
    _fDay := 0.0 - DL_RDC_DMAX;         // 负向钳定：保留超期方向
END_IF
nDays := REAL_TO_INT(_fDay);
bOverdue := (_fDay < 0.0);
FC_DL_AnalyzerRecalDaysCalc := NOT bOverdue;
END_FUNCTION
