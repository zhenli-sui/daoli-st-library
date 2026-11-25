(*
  Component : FC_DL_ExtrusionBilletHeatCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 铝挤压铸锭感应加热负荷核算：按锭重/比热/温升/效率算所需电功率与总能耗 kWh。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 锭重、加热时长须 > 1e-9，锭数须 >= 1，效率须在 (0, 100] % 内，否则返回哨兵 -1；
              ② 温升目标不高于起始温度时，能耗与功率均输出 0 且 xValid 置真（合法空工况）；
              ③ 效率按百分数折算，不做效率外推补偿。
*)
FUNCTION FC_DL_ExtrusionBilletHeatCalc : REAL
VAR_INPUT
    fBilletKg  : REAL;   (* 单锭质量 [kg] Billet mass *)
    fCpKJkgK   : REAL;   (* 铝比热容 [kJ/(kg·K)] Aluminium specific heat *)
    fT0C       : REAL;   (* 入炉锭温 [°C] Billet inlet temperature *)
    fT1C       : REAL;   (* 目标出炉锭温 [°C] Billet target temperature *)
    fEffPct    : REAL;   (* 感应加热总效率 [%] Overall induction efficiency *)
    fHeatTimeS : REAL;   (* 允许加热时长 [s] Allowed heating time *)
    nBilletCnt : INT;    (* 同时加热锭数 [件] Number of billets *)
END_VAR
VAR_OUTPUT
    fDeltaTK  : REAL;   (* 单锭温升 [K] Temperature rise per billet *)
    fPowerKW  : REAL;   (* 所需电功率（含效率折算） [kW] Electrical power required *)
    fEnergyKWh: REAL;   (* 本批总电耗 [kWh] Total electrical energy *)
    xValid    : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_KWH_KJ   : REAL := 3600.0;   (* 千焦转千瓦时换算系数 [kJ/kWh] kJ per kWh *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fHeatKJ  : REAL;   (* 本批所需热量 [kJ] Required heat of the batch *)
    fEffUnit : REAL;   (* 效率折算系数 [-] Efficiency as fraction *)
END_VAR
(* 出口预置：四出口统一预置 *)
fDeltaTK := 0.0; fPowerKW := 0.0; fEnergyKWh := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fBilletKg <> fBilletKg) OR ((fBilletKg - fBilletKg) <> 0.0)
   OR (fCpKJkgK <> fCpKJkgK) OR ((fCpKJkgK - fCpKJkgK) <> 0.0)
   OR (fT0C <> fT0C) OR ((fT0C - fT0C) <> 0.0)
   OR (fT1C <> fT1C) OR ((fT1C - fT1C) <> 0.0)
   OR (fEffPct <> fEffPct) OR ((fEffPct - fEffPct) <> 0.0)
   OR (fHeatTimeS <> fHeatTimeS) OR ((fHeatTimeS - fHeatTimeS) <> 0.0) THEN
    FC_DL_ExtrusionBilletHeatCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：质量/比热/时长/效率/锭数逐引脚覆盖 *)
IF (fBilletKg <= DL_EPS) OR (fCpKJkgK <= DL_EPS) OR (fHeatTimeS <= DL_EPS)
   OR (fEffPct <= DL_ZERO) OR (fEffPct > DL_PCT_BASE) OR (nBilletCnt < 1) THEN
    FC_DL_ExtrusionBilletHeatCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
fEffUnit := fEffPct / DL_PCT_BASE;          (* 效率折算为小数 [-] / Efficiency as fraction *)
fDeltaTK := fT1C - fT0C;                    (* 单锭温升 [K] / Temperature rise *)
IF fDeltaTK <= DL_ZERO THEN
    xValid := TRUE;                         (* 合法空工况：无需加热 / Legal no-heating case *)
    FC_DL_ExtrusionBilletHeatCalc := DL_ZERO;
    RETURN;
END_IF
(* 本批热量：Q = n * m * cp * dT [kJ] *)
fHeatKJ := INT_TO_REAL(nBilletCnt) * fBilletKg * fCpKJkgK * fDeltaTK;
(* 电功率：热功率 / 效率，kJ/s = kW *)
fPowerKW := (fHeatKJ / fHeatTimeS) / fEffUnit;
(* 电耗：kJ 除以 3600 得 kWh，效率折算进热量侧 *)
fEnergyKWh := (fHeatKJ / fEffUnit) / DL_KWH_KJ;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_ExtrusionBilletHeatCalc := fPowerKW;  (* 返回电功率 [kW] / Return electrical power *)
END_FUNCTION
