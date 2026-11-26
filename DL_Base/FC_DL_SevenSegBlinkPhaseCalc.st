(* ============================================================
   DL_Base / FC_DL_SevenSegBlinkPhaseCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：段码闪烁相位判定（毫秒整数域）：rem = tNow MOD tPeriod，
         bOn = (rem < tOn)，fPhase = rem / tPeriod ∈ [0,1)
   边界：tPeriod ≤ 0 → 恒定点亮（bOn=TRUE、fPhase=1.0，N3 先亮最安全）；
         tOn ≤ 0 → 恒定点灭；tOn > tPeriod → 钳到 tPeriod；tNow < 0 按 0；
         MOD 除子已闸非零，无浮点判等（R4）
   依赖：仅 IEC 61131-3（TIME_TO_DINT / DINT_TO_REAL） ｜ 溯源：DLF-C-SEVENSEG
   ============================================================ *)
FUNCTION FC_DL_SevenSegBlinkPhaseCalc : BOOL
VAR_INPUT
    tNow    : TIME;  // 当前时刻（任务时基）[ms] / Current task time base
    tOn     : TIME;  // 一个周期内点亮时长 [ms] / On duration inside one period
    tPeriod : TIME;  // 闪烁周期，> 0 才闪烁 [ms] / Blink period, only a positive value blinks
END_VAR
VAR_OUTPUT
    bOn    : BOOL;  // 本拍应点亮 [-] / Segment should be lit this scan
    fPhase : REAL;  // 周期内相位 [0,1) [-] / Phase inside the period
END_VAR
VAR
    _nNow    : DINT;  // 当前时刻毫秒值 [ms] / Current time in milliseconds
    _nPeriod : DINT;  // 周期毫秒值 [ms] / Period in milliseconds
    _nOn     : DINT;  // 点亮时长毫秒值（已钳定）[ms] / Clamped on duration
    _nRem    : DINT;  // 周期内余量 [ms] / Remainder inside the period
END_VAR

(* 段 0：出口预置安全侧（先亮，无显示熄灭风险） *)
FC_DL_SevenSegBlinkPhaseCalc := FALSE;
bOn := TRUE;  fPhase := 1.0;

(* 段 1：周期域闸（≤ 0 → 恒亮） *)
_nPeriod := TIME_TO_DINT(tPeriod);
IF _nPeriod <= 0 THEN
    bOn := TRUE;  fPhase := 1.0;  FC_DL_SevenSegBlinkPhaseCalc := TRUE;  RETURN;
END_IF

(* 段 2：时刻与点亮时长归一（负时刻按 0；tOn 钳到 [0, tPeriod]） *)
_nNow := TIME_TO_DINT(tNow);
IF _nNow < 0 THEN _nNow := 0; END_IF              // 时刻回绕：不产生负相位
_nOn := TIME_TO_DINT(tOn);
IF _nOn < 0 THEN
    _nOn := 0;
ELSIF _nOn > _nPeriod THEN
    _nOn := _nPeriod;                             // 占空 100%
END_IF

(* 段 3：相位与点亮判据（除子已证 > 0） *)
_nRem := _nNow MOD _nPeriod;
fPhase := DINT_TO_REAL(_nRem) / DINT_TO_REAL(_nPeriod);
IF _nRem < _nOn THEN bOn := TRUE; ELSE bOn := FALSE; END_IF

(* 段 4：相位复检（越 [0,1) 即钳，N4） *)
IF (fPhase <> fPhase) OR (fPhase < 0.0) OR (fPhase >= 1.0) THEN fPhase := 0.0; END_IF
FC_DL_SevenSegBlinkPhaseCalc := TRUE;
END_FUNCTION
