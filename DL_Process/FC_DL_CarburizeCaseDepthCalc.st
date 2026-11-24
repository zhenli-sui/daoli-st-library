(*
  Component : FC_DL_CarburizeCaseDepthCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 气体渗碳层深 Harris 公式核算：x = K*sqrt(t)，K 由 Arrhenius 温度修正，并支持由目标层深反算保温时间。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 保温时长须 >= 0 且参考系数/温度须 > 0，否则返回哨兵 -1；
              ② Arrhenius 指数项双侧钳位 [-50, +50]，防 EXP 上溢/下溢；
              ③ 反算时间用 (x/K)^2，K 过小时不下发时间而回哨兵。
*)
FUNCTION FC_DL_CarburizeCaseDepthCalc : REAL
VAR_INPUT
    fTempC      : REAL;   (* 渗碳保温温度 [°C] Carburizing temperature *)
    fHoldH      : REAL;   (* 保温时长 [h] Hold time *)
    fKRefMmSqh  : REAL;   (* 参考温度下的 K 系数 [mm/sqrt(h)] K coefficient at reference *)
    fTRefC      : REAL;   (* K 系数的参考温度 [°C] Reference temperature for K *)
    fEnergyJmol : REAL;   (* 扩散激活能 [J/mol] Activation energy *)
    fTargetMm   : REAL;   (* 目标层深 [mm] Target case depth *)
END_VAR
VAR_OUTPUT
    fCaseMm      : REAL;  (* 实际渗碳层深 [mm] Actual case depth *)
    fKCoef       : REAL;  (* 当前温度下的 K 系数 [mm/sqrt(h)] K coefficient at temperature *)
    fTimeTargetH : REAL;  (* 达目标层深所需保温时长 [h] Time to reach target depth *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS     : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_KELVIN  : REAL := 273.15;   (* 摄氏度转开尔文偏置 [K] Celsius to Kelvin offset *)
    DL_RGAS    : REAL := 8.314;    (* 通用气体常数 [J/(mol·K)] Universal gas constant *)
    DL_EXP_MAX : REAL := 50.0;     (* 指数项上钳位 [-] Exponent upper clamp *)
    DL_EXP_MIN : REAL := -50.0;    (* 指数项下钳位 [-] Exponent lower clamp *)
END_VAR
VAR
    fTK     : REAL;   (* 绝对温度 [K] Absolute temperature *)
    fTRefK  : REAL;   (* 参考绝对温度 [K] Reference absolute temperature *)
    fExp    : REAL;   (* Arrhenius 指数项 [-] Arrhenius exponent *)
END_VAR
(* 出口预置：四出口统一预置 *)
fCaseMm := 0.0; fKCoef := 0.0; fTimeTargetH := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fTempC <> fTempC) OR ((fTempC - fTempC) <> 0.0)
   OR (fHoldH <> fHoldH) OR ((fHoldH - fHoldH) <> 0.0)
   OR (fKRefMmSqh <> fKRefMmSqh) OR ((fKRefMmSqh - fKRefMmSqh) <> 0.0)
   OR (fEnergyJmol <> fEnergyJmol) OR ((fEnergyJmol - fEnergyJmol) <> 0.0)
   OR (fTRefC <> fTRefC) OR ((fTRefC - fTRefC) <> 0.0)
   OR (fTargetMm <> fTargetMm) OR ((fTargetMm - fTargetMm) <> 0.0) THEN
    FC_DL_CarburizeCaseDepthCalc := -1.0;   (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：保温时长非负、参考系数正、激活能非负、反算温度可表 *)
fTK := fTempC + DL_KELVIN;
fTRefK := fTRefC + DL_KELVIN;
IF (fHoldH < 0.0) OR (fKRefMmSqh <= DL_EPS) OR (fEnergyJmol < 0.0)
   OR (fTK <= DL_EPS) OR (fTRefK <= DL_EPS) THEN
    FC_DL_CarburizeCaseDepthCalc := -1.0;   (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* Arrhenius 温度修正：K = Kref * exp(-(Q/R)*(1/T - 1/Tref)) *)
fExp := -(fEnergyJmol / DL_RGAS) * ((1.0 / fTK) - (1.0 / fTRefK));
IF fExp > DL_EXP_MAX THEN
    fExp := DL_EXP_MAX;                     (* 指数上钳位，防 EXP 上溢 [-] / Clamp high *)
ELSIF fExp < DL_EXP_MIN THEN
    fExp := DL_EXP_MIN;                     (* 指数下钳位，防 EXP 下溢 [-] / Clamp low *)
END_IF
fKCoef := fKRefMmSqh * EXP(fExp);           (* 当前温度 K 系数 [mm/sqrt(h)] / K at temperature *)
(* Harris 层深：x = K*sqrt(t)，开方前已保证 t >= 0 *)
fCaseMm := fKCoef * SQRT(fHoldH);
(* 反算保温时间：t = (x/K)^2，K 已过域闸 *)
IF fTargetMm > 0.0 THEN
    fTimeTargetH := (fTargetMm / fKCoef) * (fTargetMm / fKCoef);
END_IF
(* 输出自检：K 极小或 t 极大时 (x/K)^2 可上溢 Inf，出口一律复检非有限 *)
IF (fCaseMm <> fCaseMm) OR ((fCaseMm - fCaseMm) <> 0.0)
   OR (fKCoef <= DL_EPS)
   OR (fTimeTargetH <> fTimeTargetH) OR ((fTimeTargetH - fTimeTargetH) <> 0.0) THEN
    fCaseMm := 0.0; fKCoef := 0.0; fTimeTargetH := 0.0;
    xValid := FALSE;                         (* 输出不可信 / Output not trustworthy *)
    FC_DL_CarburizeCaseDepthCalc := -1.0;    (* 哨兵 -1：输出溢出 / Sentinel -1 overflow *)
    RETURN;
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_CarburizeCaseDepthCalc := fCaseMm;    (* 返回层深 [mm] / Return case depth *)
END_FUNCTION
