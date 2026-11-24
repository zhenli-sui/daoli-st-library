(*
  Component : FC_DL_DieCastShotVelocityCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 压射速度核算：按充填体积/充填时间/冲头面积算空压射速度，做 PQ² 交点速度校核并给出超限降速建议。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 充填时间、冲头直径、充填体积须 > 1e-9，否则返回哨兵 -1（充填时间为除子）；
              ② 速度超工艺上限置 xOverLimit；速度超 PQ² 交点速度置 xPq2Ok = FALSE 并给降速建议；
              ③ 降速建议 = min(0.9 × PQ² 交点速度, 工艺上限)，不越上限。
*)
FUNCTION FC_DL_DieCastShotVelocityCalc : REAL
VAR_INPUT
    fFillVolCm3   : REAL;   (* 型腔充填体积 [cm³] Cavity fill volume *)
    fFillTimeMs   : REAL;   (* 充填时间 [ms] Fill time *)
    fPlungerDiaMm : REAL;   (* 压射冲头直径 [mm] Shot plunger diameter *)
    fMaxVelMs     : REAL;   (* 工艺允许最大速度 [m/s] Process max velocity *)
    fPq2VelMs     : REAL;   (* PQ² 交点速度 [m/s] PQ2 intersection velocity *)
END_VAR
VAR_OUTPUT
    fShotVelMs   : REAL;  (* 空压射速度 [m/s] Dry shot velocity *)
    fPq2Ratio    : REAL;  (* 速度 / PQ² 交点速度比 [-] Velocity to PQ2 ratio *)
    fSuggestVelMs: REAL;  (* 超限降速建议值 [m/s] Suggested reduced velocity *)
    xOverLimit   : BOOL;  (* 超工艺上限标志 [-] Over process limit flag *)
    xPq2Ok       : BOOL;  (* PQ² 校核通过标志 [-] PQ2 check passed flag *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PI       : REAL := 3.14159265358979;  (* 圆周率 [-] Pi *)
    DL_MS_PER_S : REAL := 1000.0;   (* 毫秒转秒换算系数 [ms/s] Milliseconds per second *)
    DL_SAFE_K   : REAL := 0.9;      (* 降速安全系数 [-] Velocity reduction factor *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fAreaMm2 : REAL;   (* 冲头截面积 [mm²] Plunger cross-section *)
    fTimeS   : REAL;   (* 充填时间秒值 [s] Fill time in seconds *)
    fVelCm   : REAL;   (* 中间速度量 [cm³/(mm²·s)] Intermediate velocity *)
    fCand    : REAL;   (* 降速候选值 [m/s] Candidate reduced velocity *)
END_VAR
(* 出口预置：六出口统一预置 *)
fShotVelMs := 0.0; fPq2Ratio := 0.0; fSuggestVelMs := 0.0;
xOverLimit := FALSE; xPq2Ok := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fFillVolCm3 <> fFillVolCm3) OR ((fFillVolCm3 - fFillVolCm3) <> 0.0)
   OR (fFillTimeMs <> fFillTimeMs) OR ((fFillTimeMs - fFillTimeMs) <> 0.0)
   OR (fPlungerDiaMm <> fPlungerDiaMm) OR ((fPlungerDiaMm - fPlungerDiaMm) <> 0.0)
   OR (fMaxVelMs <> fMaxVelMs) OR ((fMaxVelMs - fMaxVelMs) <> 0.0)
   OR (fPq2VelMs <> fPq2VelMs) OR ((fPq2VelMs - fPq2VelMs) <> 0.0) THEN
    FC_DL_DieCastShotVelocityCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：体积/时间/直径为除子，两个速度限须为正 *)
IF (fFillVolCm3 <= DL_EPS) OR (fFillTimeMs <= DL_EPS) OR (fPlungerDiaMm <= DL_EPS)
   OR (fMaxVelMs <= DL_ZERO) OR (fPq2VelMs <= DL_ZERO) THEN
    FC_DL_DieCastShotVelocityCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
fAreaMm2 := DL_PI / 4.0 * fPlungerDiaMm * fPlungerDiaMm;   (* 冲头面积 [mm²] *)
fTimeS := fFillTimeMs / DL_MS_PER_S;                       (* 充填时间 [s] *)
(* 速度换算：cm³/(mm²·s) = 1000 mm³/(mm²·s) = 1000 mm/s = 1 m/s，故量纲直接得 m/s *)
fVelCm := fFillVolCm3 / (fAreaMm2 * fTimeS);
fShotVelMs := fVelCm;
(* PQ² 校核：速度比与通过标志 *)
fPq2Ratio := fShotVelMs / fPq2VelMs;
xPq2Ok := fShotVelMs <= fPq2VelMs;
xOverLimit := fShotVelMs > fMaxVelMs;
(* 降速建议：取 0.9 倍 PQ² 交点速度与工艺上限的较小者 *)
IF xOverLimit OR (NOT xPq2Ok) THEN
    fCand := fPq2VelMs * DL_SAFE_K;
    IF fCand < fMaxVelMs THEN
        fSuggestVelMs := fCand;                 (* 受 PQ² 交点约束 [m/s] / Limited by PQ2 *)
    ELSE
        fSuggestVelMs := fMaxVelMs;             (* 受工艺上限约束 [m/s] / Limited by process cap *)
    END_IF
ELSE
    fSuggestVelMs := fShotVelMs;                (* 未超限：建议保持当前速度 *)
END_IF
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_DieCastShotVelocityCalc := fShotVelMs;    (* 返回空压射速度 [m/s] / Return shot velocity *)
END_FUNCTION
