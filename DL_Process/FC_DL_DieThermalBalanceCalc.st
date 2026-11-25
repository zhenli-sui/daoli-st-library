(*
  Component : FC_DL_DieThermalBalanceCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 压铸模热平衡核算：按循环周期与金属放热算平均热流，再由冷却水流量算水温升与模温估计，给出模温机负荷。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 循环周期、金属质量、比热、冷却水流量均须 > 1e-9，否则返回哨兵 -1；
              ② 放热按金属从浇注温度降到顶出温度的显热估算，不含凝固潜热；
              ③ 浇注温度低于顶出温度时放热量归零；模温机余量上限钳位 100 %（折算系数上限 2.0）。
*)
FUNCTION FC_DL_DieThermalBalanceCalc : REAL
VAR_INPUT
    fCycleS       : REAL;   (* 压铸循环周期 [s] Die casting cycle time *)
    fMetalMassKg  : REAL;   (* 单模金属质量 [kg] Metal mass per shot *)
    fMetalCpKJkgK : REAL;   (* 金属比热容 [kJ/(kg·K)] Metal specific heat *)
    fPourC        : REAL;   (* 浇注温度 [°C] Pouring temperature *)
    fEjectC       : REAL;   (* 顶出温度 [°C] Ejection temperature *)
    fWaterFlowLmin: REAL;   (* 冷却水流量 [L/min] Cooling water flow *)
    fWaterInC     : REAL;   (* 冷却水进水温度 [°C] Cooling water inlet temperature *)
    fMarginPct    : REAL;   (* 模温机负荷余量 [%] Thermolator load margin *)
END_VAR
VAR_OUTPUT
    fHeatRateKW  : REAL;  (* 模具平均热流 [kW] Average heat flux into die *)
    fCoolLoadKW  : REAL;  (* 模温机所需冷却负荷 [kW] Required cooling load *)
    fWaterDeltaTK: REAL;  (* 冷却水温升 [K] Cooling water temperature rise *)
    fMoldEstC    : REAL;  (* 模温估计 [°C] Estimated die temperature *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_S_PER_MIN: REAL := 60.0;     (* 分钟转秒换算系数 [s/min] Seconds per minute *)
    DL_WATER_CP : REAL := 4.187;    (* 水比热容 [kJ/(kg·K)] Water specific heat *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fHeatKJ    : REAL;   (* 单模放热量 [kJ] Heat per shot *)
    fFlowKgS   : REAL;   (* 冷却水质量流量 [kg/s] Cooling water mass flow *)
    fMarginK   : REAL;   (* 余量折算系数 [-] Margin factor *)
END_VAR
(* 出口预置：五出口统一预置 *)
fHeatRateKW := 0.0; fCoolLoadKW := 0.0; fWaterDeltaTK := 0.0; fMoldEstC := 0.0; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fCycleS <> fCycleS) OR ((fCycleS - fCycleS) <> 0.0)
   OR (fMetalMassKg <> fMetalMassKg) OR ((fMetalMassKg - fMetalMassKg) <> 0.0)
   OR (fMetalCpKJkgK <> fMetalCpKJkgK) OR ((fMetalCpKJkgK - fMetalCpKJkgK) <> 0.0)
   OR (fPourC <> fPourC) OR ((fPourC - fPourC) <> 0.0)
   OR (fEjectC <> fEjectC) OR ((fEjectC - fEjectC) <> 0.0)
   OR (fWaterFlowLmin <> fWaterFlowLmin) OR ((fWaterFlowLmin - fWaterFlowLmin) <> 0.0)
   OR (fWaterInC <> fWaterInC) OR ((fWaterInC - fWaterInC) <> 0.0)
   OR (fMarginPct <> fMarginPct) OR ((fMarginPct - fMarginPct) <> 0.0) THEN
    FC_DL_DieThermalBalanceCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：周期、质量、比热为比例基；流量为水温升的除子 *)
IF (fCycleS <= DL_EPS) OR (fMetalMassKg <= DL_EPS) OR (fMetalCpKJkgK <= DL_EPS)
   OR (fWaterFlowLmin <= DL_EPS) OR (fMarginPct < DL_ZERO) THEN
    FC_DL_DieThermalBalanceCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 单模显热：Q = m·cp·ΔT [kJ]，ΔT 为浇注与顶出温差 *)
fHeatKJ := fMetalMassKg * fMetalCpKJkgK * (fPourC - fEjectC);
IF fHeatKJ < DL_ZERO THEN
    fHeatKJ := DL_ZERO;                       (* 负温差归零 [kJ] / Negative heat clamp *)
END_IF
(* 平均热流：Q / 周期 [kJ/s = kW] *)
fHeatRateKW := fHeatKJ / fCycleS;
(* 模温机负荷：平均热流 × (1 + 余量)，余量钳位 0~100 % *)
fMarginK := 1.0 + fMarginPct / DL_PCT_BASE;
IF fMarginK > 2.0 THEN
    fMarginK := 2.0;                          (* 余量上限钳位 [-] / Margin upper clamp *)
END_IF
fCoolLoadKW := fHeatRateKW * fMarginK;
(* 水温升：Q = m·cp·ΔT，水质量流量 L/min ÷ 60 = kg/s，分母已过域闸 *)
fFlowKgS := fWaterFlowLmin / DL_S_PER_MIN;
fWaterDeltaTK := fHeatRateKW / (fFlowKgS * DL_WATER_CP);
(* 模温估计：进水温度叠加水温升（模具侧平均近似） *)
fMoldEstC := fWaterInC + fWaterDeltaTK;
xValid := TRUE;                               (* 链路有效 / Chain valid *)
FC_DL_DieThermalBalanceCalc := fCoolLoadKW;   (* 返回冷却负荷 [kW] / Return cooling load *)
END_FUNCTION
