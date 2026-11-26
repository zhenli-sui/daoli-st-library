(* ============================================================
   DL_Motion / FC_DL_SwivelHeadTiltLimitCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：摆动头倾角钳位 + 角速度限幅。模式 0=±110°、1=±90°、其余=±60°（保守侧），
         钳位后按 |Δ| ≤ 速率×dt 限幅，输出回退后指令与角速度 [deg/s]
   边界：速率≤0 或 dt≤0 → 冻结上一拍值（不阶跃，N2）；任一入参非有限 →
         倾角落 0°（垂直安全位）并置 bAtLimit（N1：禁 NaN 直穿倾角出口，N3）
   依赖：仅 IEC 61131-3（ABS） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SwivelHeadTiltLimitCalc : BOOL
VAR_INPUT
    fTiltCmdDeg  : REAL;  // 倾角指令 [deg] / Tilt angle command
    fTiltPrevDeg : REAL;  // 上一拍生效倾角 [deg] / Tilt angle in effect during the previous scan
    fRateMaxDegS : REAL;  // 允许最大角速度，域 > 0 [deg/s] / Maximum allowed angular rate
    fDtSec       : REAL;  // 本拍时长，域 > 0 [s] / Scan duration in seconds
    nLimitMode   : DINT;  // 工艺模式 0/1/其余 [-] / Process mode selecting the soft limit
END_VAR
VAR_OUTPUT
    fTiltOutDeg  : REAL;  // 限幅后倾角指令 [deg] / Limited tilt command
    fRateOutDegS : REAL;  // 本拍实际角速度 [deg/s] / Actual angular rate of this scan
    bAtLimit     : BOOL;  // 钳位或角速度限幅命中 [-] / Clamp or rate limit reached
END_VAR
VAR
    _fLimAbs  : REAL;  // 软限位绝对值 [deg] / Absolute soft limit
    _fClamped : REAL;  // 钳位结果 [deg] / Clamped command
    _fStepMax : REAL;  // 本拍允许最大步进 [deg] / Maximum allowed step this scan
    _tPrev    : REAL;  // 上一拍倾角受控副本 [deg] / Sanitized previous tilt
END_VAR

(* 段 0：出口预置安全侧（倾角回 0° 垂直位，N3） *)
FC_DL_SwivelHeadTiltLimitCalc := FALSE;
fTiltOutDeg := 0.0;  fRateOutDegS := 0.0;  bAtLimit := TRUE;

(* 段 1：非有限闸（原始入参全量枚举） *)
IF (fTiltCmdDeg <> fTiltCmdDeg) OR (fRateMaxDegS <> fRateMaxDegS) OR (fDtSec <> fDtSec)
   OR ((fTiltCmdDeg - fTiltCmdDeg) <> (fTiltCmdDeg - fTiltCmdDeg)) THEN
    RETURN;
END_IF

(* 段 2：上一拍值受控副本（非有限即按 0 重建，防 NaN 搬运） *)
IF (fTiltPrevDeg <> fTiltPrevDeg) OR ((fTiltPrevDeg - fTiltPrevDeg) <> (fTiltPrevDeg - fTiltPrevDeg)) THEN
    _tPrev := 0.0;
ELSE
    _tPrev := fTiltPrevDeg;
END_IF

(* 段 3：组态闸（非法即冻结上一拍安全值，不阶跃） *)
IF (fRateMaxDegS <= 0.0) OR (fDtSec <= 0.0) THEN
    fTiltOutDeg := _tPrev;  fRateOutDegS := 0.0;  bAtLimit := TRUE;  RETURN;
END_IF

(* 段 4：软限位选择（未识别模式取最保守 ±60°） *)
IF nLimitMode = 0 THEN
    _fLimAbs := 110.0;
ELSIF nLimitMode = 1 THEN
    _fLimAbs := 90.0;
ELSE
    _fLimAbs := 60.0;
END_IF

(* 段 5：位置钳位（判据在原始指令上，禁先夹后判） *)
bAtLimit := FALSE;
IF fTiltCmdDeg > _fLimAbs THEN
    _fClamped := _fLimAbs;  bAtLimit := TRUE;
ELSIF fTiltCmdDeg < (0.0 - _fLimAbs) THEN
    _fClamped := 0.0 - _fLimAbs;  bAtLimit := TRUE;
ELSE
    _fClamped := fTiltCmdDeg;
END_IF

(* 段 6：角速度限幅（双向分列） *)
_fStepMax := fRateMaxDegS * fDtSec;
IF (_fClamped - _tPrev) > _fStepMax THEN
    fTiltOutDeg := _tPrev + _fStepMax;  bAtLimit := TRUE;
ELSIF (_tPrev - _fClamped) > _fStepMax THEN
    fTiltOutDeg := _tPrev - _fStepMax;  bAtLimit := TRUE;
ELSE
    fTiltOutDeg := _fClamped;
END_IF

(* 段 7：单一出口裁决（N4：角速度与结果复检统一在此） *)
fRateOutDegS := (fTiltOutDeg - _tPrev) / fDtSec;         // 除子已证 > 0
IF (fTiltOutDeg <> fTiltOutDeg) OR (fRateOutDegS <> fRateOutDegS) THEN
    fTiltOutDeg := 0.0;  fRateOutDegS := 0.0;  bAtLimit := TRUE;  RETURN;
END_IF
FC_DL_SwivelHeadTiltLimitCalc := TRUE;
END_FUNCTION
