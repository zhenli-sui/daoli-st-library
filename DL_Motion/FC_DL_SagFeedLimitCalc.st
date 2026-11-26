(* ============================================================
   DL_Motion / FC_DL_SagFeedLimitCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：按允许弦高、向心加速度上限与采样周期反解进给上限 [mm/min]：
         v_sag = √(8·R·e)/T，v_acc = √(a·R)，取小值 ×60
   边界：半径≤0 / 弦高≤0 / 加速度≤0 / 周期=0 或非有限 → 上限写 0、bLimited=TRUE（N1/N3）
         bLimited=TRUE 表示被弦高约束压死（向心约束更紧时为 FALSE）
   依赖：仅 IEC 61131-3（SQRT / MIN / TIME_TO_REAL） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SagFeedLimitCalc : BOOL
VAR_INPUT
    fSagTolMm   : LREAL;  // 允许弦高（垂度）容差，域 > 0 [mm] / Allowed chord sag tolerance
    fRadiusMm   : LREAL;  // 路径曲率半径，域 > 0 [mm] / Path curvature radius
    fAccMaxMmS2 : LREAL;  // 向心加速度上限，域 > 0 [mm/s²] / Centripetal acceleration ceiling
    tCycle      : TIME;   // 插补采样周期，域 > 0 [ms] / Interpolation sampling period
END_VAR
VAR_OUTPUT
    fFeedMaxMmMin : LREAL;  // 进给率上限 [mm/min] / Feed rate ceiling
    bLimited      : BOOL;   // 输出被弦高约束压死 [-] / Output bound by the sag constraint
END_VAR
VAR
    _fTSec : LREAL;  // 采样周期换算值 [s] / Sampling period in seconds
    _fVSag : LREAL;  // 弦高约束允许速度 [mm/s] / Speed allowed by the sag constraint
    _fVAcc : LREAL;  // 向心约束允许速度 [mm/s] / Speed allowed by the centripetal constraint
END_VAR
VAR CONSTANT
    DL_SAG_MS_PER_S : LREAL := 1000.0;  // 毫秒 → 秒换算系数 [ms/s] / Milliseconds per second
END_VAR

(* 段 0：出口预置安全侧（上限 0 = 禁止运动，N3） *)
FC_DL_SagFeedLimitCalc := FALSE;
fFeedMaxMmMin := 0.0;  bLimited := TRUE;

(* 段 1：非有限闸 + 四域闸 *)
IF (fSagTolMm <> fSagTolMm) OR (fRadiusMm <> fRadiusMm) OR (fAccMaxMmS2 <> fAccMaxMmS2) THEN
    RETURN;
END_IF
IF (fRadiusMm <= 0.0) OR (fSagTolMm <= 0.0) OR (fAccMaxMmS2 <= 0.0) THEN RETURN; END_IF
_fTSec := TIME_TO_REAL(tCycle) / DL_SAG_MS_PER_S;        // ms → s
IF _fTSec <= 0.0 THEN RETURN; END_IF

(* 段 2：两约束允许速度（开方前已证根号内 > 0） *)
_fVSag := SQRT(8.0 * fRadiusMm * fSagTolMm) / _fTSec;
_fVAcc := SQRT(fAccMaxMmS2 * fRadiusMm);

(* 段 3：取小值、判约束源，同步落进给上限（N4 单段裁决） *)
IF _fVSag < _fVAcc THEN
    fFeedMaxMmMin := _fVSag * 60.0;  bLimited := TRUE;   // 弦高约束更紧
ELSE
    fFeedMaxMmMin := _fVAcc * 60.0;  bLimited := FALSE;  // 向心约束更紧
END_IF

(* 段 4：结果复检（出口闸位于最后一次赋值之后） *)
IF (fFeedMaxMmMin <> fFeedMaxMmMin)
   OR ((fFeedMaxMmMin - fFeedMaxMmMin) <> (fFeedMaxMmMin - fFeedMaxMmMin)) THEN
    fFeedMaxMmMin := 0.0;  bLimited := TRUE;  RETURN;
END_IF
FC_DL_SagFeedLimitCalc := TRUE;
END_FUNCTION
