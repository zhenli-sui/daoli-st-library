(*
  Component : FC_DL_ExtrusionDieWearIndexCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 挤压模具磨损指数核算：按累计挤压吨位、型材周长比与温度因子加权算磨损指数（0~100+），并折算剩余寿命百分比。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 额定吨位、参考周长、磨损限值须 > 1e-9，否则返回哨兵 -1；
              ② 温度因子钳位 0.5~2.0，周长比钳位 0.2~5.0，防离群输入拉爆指数；
              ③ 剩余寿命在 0~100 % 之间双侧钳位，指数达限值即判寿命终止。
*)
FUNCTION FC_DL_ExtrusionDieWearIndexCalc : REAL
VAR_INPUT
    fTonnageT       : REAL;   (* 累计挤压吨位 [t] Accumulated extrusion tonnage *)
    fRatedTonnageT  : REAL;   (* 模具额定寿命吨位 [t] Rated die life tonnage *)
    fPerimeterMm    : REAL;   (* 型材周长 [mm] Profile perimeter *)
    fRefPerimeterMm : REAL;   (* 参考周长（模具基准） [mm] Reference perimeter *)
    fTempFactor     : REAL;   (* 温度加速因子 [-] Temperature acceleration factor *)
    fWearLimit      : REAL;   (* 磨损指数报废限 [-] Wear index scrap limit *)
END_VAR
VAR_OUTPUT
    fWearIndex  : REAL;   (* 无量纲磨损指数 [-] Dimensionless wear index *)
    fRemainPct  : REAL;   (* 剩余寿命百分比 [%] Remaining life percent *)
    xLifeExpired: BOOL;   (* 寿命终止标志 [-] Life expired flag *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_TF_MIN   : REAL := 0.5;      (* 温度因子下限 [-] Temperature factor lower clamp *)
    DL_TF_MAX   : REAL := 2.0;      (* 温度因子上限 [-] Temperature factor upper clamp *)
    DL_PR_MIN   : REAL := 0.2;      (* 周长比下限 [-] Perimeter ratio lower clamp *)
    DL_PR_MAX   : REAL := 5.0;      (* 周长比上限 [-] Perimeter ratio upper clamp *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fPerimRatio : REAL;   (* 周长比（实际/参考） [-] Perimeter ratio *)
    fTempF      : REAL;   (* 钳位后温度因子 [-] Clamped temperature factor *)
    fTonnRatio  : REAL;   (* 吨位比（累计/额定） [-] Tonnage ratio *)
END_VAR
(* 出口预置：四出口统一预置 *)
fWearIndex := 0.0; fRemainPct := 100.0; xLifeExpired := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fTonnageT <> fTonnageT) OR ((fTonnageT - fTonnageT) <> 0.0)
   OR (fRatedTonnageT <> fRatedTonnageT) OR ((fRatedTonnageT - fRatedTonnageT) <> 0.0)
   OR (fPerimeterMm <> fPerimeterMm) OR ((fPerimeterMm - fPerimeterMm) <> 0.0)
   OR (fRefPerimeterMm <> fRefPerimeterMm) OR ((fRefPerimeterMm - fRefPerimeterMm) <> 0.0)
   OR (fTempFactor <> fTempFactor) OR ((fTempFactor - fTempFactor) <> 0.0)
   OR (fWearLimit <> fWearLimit) OR ((fWearLimit - fWearLimit) <> 0.0) THEN
    FC_DL_ExtrusionDieWearIndexCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：额定吨位、参考周长、磨损限值三者均为除子 *)
IF (fRatedTonnageT <= DL_EPS) OR (fRefPerimeterMm <= DL_EPS)
   OR (fWearLimit <= DL_EPS) OR (fTonnageT < DL_ZERO) OR (fPerimeterMm <= DL_ZERO) THEN
    FC_DL_ExtrusionDieWearIndexCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 温度因子双侧钳位：避免极端温度把指数拉爆 *)
IF fTempFactor < DL_TF_MIN THEN
    fTempF := DL_TF_MIN;                      (* 下限钳位 [-] / Lower clamp *)
ELSIF fTempFactor > DL_TF_MAX THEN
    fTempF := DL_TF_MAX;                      (* 上限钳位 [-] / Upper clamp *)
ELSE
    fTempF := fTempFactor;                    (* 原值通过 [-] / Pass-through *)
END_IF
(* 周长比双侧钳位：细长型材与超宽型材均不得线性外推 *)
fPerimRatio := fPerimeterMm / fRefPerimeterMm;
IF fPerimRatio < DL_PR_MIN THEN
    fPerimRatio := DL_PR_MIN;                 (* 下限钳位 [-] / Lower clamp *)
ELSIF fPerimRatio > DL_PR_MAX THEN
    fPerimRatio := DL_PR_MAX;                 (* 上限钳位 [-] / Upper clamp *)
END_IF
(* 磨损指数：吨位比 × 周长比 × 温度因子 × 100，分母均已过域闸 *)
fTonnRatio := fTonnageT / fRatedTonnageT;
fWearIndex := fTonnRatio * fPerimRatio * fTempF * DL_PCT_BASE;
(* 剩余寿命：1 - 指数/限值，双侧钳位 0~100 % *)
fRemainPct := (1.0 - fWearIndex / fWearLimit) * DL_PCT_BASE;
IF fRemainPct < DL_ZERO THEN
    fRemainPct := DL_ZERO;                    (* 下限钳位 [%] / Lower clamp *)
ELSIF fRemainPct > DL_PCT_BASE THEN
    fRemainPct := DL_PCT_BASE;                (* 上限钳位 [%] / Upper clamp *)
END_IF
xLifeExpired := fWearIndex >= fWearLimit;     (* 达限即寿命终止 / Life expired *)
xValid := TRUE;                               (* 链路有效 / Chain valid *)
FC_DL_ExtrusionDieWearIndexCalc := fWearIndex;  (* 返回磨损指数 [-] / Return wear index *)
END_FUNCTION
