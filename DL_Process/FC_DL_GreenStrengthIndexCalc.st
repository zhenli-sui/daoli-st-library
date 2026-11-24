(*
  Component : FC_DL_GreenStrengthIndexCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 生坯强度指数核算：按压制成型压力、润滑剂含量与生坯密度算无量纲强度指数，并与安全阈值比较给出脱模安全判定。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 参考密度与安全阈值须 > 1e-9，压制压力须非负，润滑剂含量须在 0~5 % 内，否则返回哨兵 -1；
              ② 压力项取开方（压力对强度是次线性贡献），开方前已钳位非负；
              ③ 润滑剂含量越高生坯强度越低，折算系数下限钳位 0.3。
*)
FUNCTION FC_DL_GreenStrengthIndexCalc : REAL
VAR_INPUT
    fPressMPa    : REAL;   (* 压制压力 [MPa] Compaction pressure *)
    fLubePct     : REAL;   (* 润滑剂含量 [%] Lubricant content *)
    fGreenDens   : REAL;   (* 生坯密度 [g/cm³] Green density *)
    fDensRef     : REAL;   (* 参考密度（工艺目标） [g/cm³] Reference density *)
    fSafeIdx     : REAL;   (* 脱模安全指数阈值 [-] Safe ejection index threshold *)
END_VAR
VAR_OUTPUT
    fStrengthIdx : REAL;  (* 生坯强度指数 [-] Green strength index *)
    fLubeFactor  : REAL;  (* 润滑剂折减因子 [-] Lubricant reduction factor *)
    xEjectSafe   : BOOL;  (* 脱模安全标志 [-] Safe ejection flag *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_GAIN     : REAL := 3.0;      (* 压力项标定增益 [-] Pressure term gain *)
    DL_LUBE_K   : REAL := 0.9;      (* 润滑剂折减系数 [-] Lubricant reduction coefficient *)
    DL_LUBE_MAX : REAL := 5.0;      (* 润滑剂含量上限 [%] Lubricant upper bound *)
    DL_LF_MIN   : REAL := 0.3;      (* 润滑剂因子下限 [-] Lubricant factor floor *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fPressPos : REAL;   (* 非负压制压力 [MPa] Non-negative pressure *)
END_VAR
(* 出口预置：四出口统一预置 *)
fStrengthIdx := 0.0; fLubeFactor := 1.0; xEjectSafe := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fPressMPa <> fPressMPa) OR ((fPressMPa - fPressMPa) <> 0.0)
   OR (fLubePct <> fLubePct) OR ((fLubePct - fLubePct) <> 0.0)
   OR (fGreenDens <> fGreenDens) OR ((fGreenDens - fGreenDens) <> 0.0)
   OR (fDensRef <> fDensRef) OR ((fDensRef - fDensRef) <> 0.0)
   OR (fSafeIdx <> fSafeIdx) OR ((fSafeIdx - fSafeIdx) <> 0.0) THEN
    FC_DL_GreenStrengthIndexCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：参考密度与安全阈值为比例基，润滑剂含量与压力取可表区间 *)
IF (fDensRef <= DL_EPS) OR (fSafeIdx <= DL_EPS) OR (fPressMPa < DL_ZERO)
   OR (fLubePct < DL_ZERO) OR (fLubePct > DL_LUBE_MAX) OR (fGreenDens < DL_ZERO) THEN
    FC_DL_GreenStrengthIndexCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 润滑剂折减因子：含量越高强度越低，下限钳位 0.3 防归零 *)
fLubeFactor := 1.0 - (fLubePct / DL_PCT_BASE) * DL_LUBE_K;
IF fLubeFactor < DL_LF_MIN THEN
    fLubeFactor := DL_LF_MIN;                 (* 下限钳位 [-] / Lower clamp *)
END_IF
(* 压力项非负钳位后开方（开方前判非负） *)
fPressPos := fPressMPa;
IF fPressPos < DL_ZERO THEN
    fPressPos := DL_ZERO;
END_IF
(* 强度指数：sqrt(p) × 增益 × 润滑剂因子 × 密度比，参考密度已过域闸 *)
fStrengthIdx := SQRT(fPressPos) * DL_GAIN * fLubeFactor * (fGreenDens / fDensRef);
(* 脱模安全判定：指数达阈值即可安全脱模 *)
xEjectSafe := fStrengthIdx >= fSafeIdx;
xValid := TRUE;                               (* 链路有效 / Chain valid *)
FC_DL_GreenStrengthIndexCalc := fStrengthIdx; (* 返回强度指数 [-] / Return strength index *)
END_FUNCTION
