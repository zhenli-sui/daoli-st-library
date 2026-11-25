(*
  Component : FC_DL_QuenchOilTempRiseCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 淬火油槽温升与换热负荷核算：由油量/比热/工件带入热量与换热器能力算单周期温升、热平衡稳态油温与超温判定。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 油量/比热/周期时长/换热能力均须 > 1e-9，组态非法返回哨兵 -1；
              ② 稳态油温按集总热平衡估算，不含辐射与强制对流分段模型；
              ③ 超限判定用容差比较，禁浮点等值比较。
*)
FUNCTION FC_DL_QuenchOilTempRiseCalc : REAL
VAR_INPUT
    fOilMassKg  : REAL;   (* 油槽油量 [kg] Oil mass in tank *)
    fOilCpKJkgK : REAL;   (* 油比热容 [kJ/(kg·K)] Oil specific heat capacity *)
    fPartHeatKJ : REAL;   (* 单周期工件带入热量 [kJ] Heat input by parts per cycle *)
    fOilTemp0C  : REAL;   (* 初始油温 [°C] Initial oil temperature *)
    fCycleTimeS : REAL;   (* 生产周期时长 [s] Production cycle time *)
    fExchCapKWperK : REAL; (* 换热器换热能力（k·A 传导率）[kW/K] Heat exchanger conductance k*A *)
    fTempLimC   : REAL;   (* 油温允许上限 [°C] Oil temperature limit *)
END_VAR
VAR_OUTPUT
    fTempRiseK   : REAL;  (* 单周期油温升幅 [K] Temperature rise per cycle *)
    fSteadyTempC : REAL;  (* 热平衡稳态油温 [°C] Steady-state oil temperature *)
    xOverTemp    : BOOL;  (* 稳态油温超限标志 [-] Over-limit flag *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
END_VAR
(* 出口预置：四出口统一预置，杜绝幽灵值 *)
fTempRiseK := 0.0; fSteadyTempC := 0.0; xOverTemp := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf，禁阈值近似判定 *)
IF (fOilMassKg <> fOilMassKg) OR ((fOilMassKg - fOilMassKg) <> 0.0)
   OR (fOilCpKJkgK <> fOilCpKJkgK) OR ((fOilCpKJkgK - fOilCpKJkgK) <> 0.0)
   OR (fPartHeatKJ <> fPartHeatKJ) OR ((fPartHeatKJ - fPartHeatKJ) <> 0.0)
   OR (fOilTemp0C <> fOilTemp0C) OR ((fOilTemp0C - fOilTemp0C) <> 0.0)
   OR (fCycleTimeS <> fCycleTimeS) OR ((fCycleTimeS - fCycleTimeS) <> 0.0)
   OR (fExchCapKWperK <> fExchCapKWperK) OR ((fExchCapKWperK - fExchCapKWperK) <> 0.0)
   OR (fTempLimC <> fTempLimC) OR ((fTempLimC - fTempLimC) <> 0.0) THEN
    FC_DL_QuenchOilTempRiseCalc := -1.0;   (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：覆盖每一个参与判据换算的分母引脚 *)
IF (fOilMassKg <= DL_EPS) OR (fOilCpKJkgK <= DL_EPS)
   OR (fCycleTimeS <= DL_EPS) OR (fExchCapKWperK <= DL_EPS) THEN
    FC_DL_QuenchOilTempRiseCalc := -1.0;   (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 单周期温升：dT = Q / (m*cp)，分母已过域闸 *)
fTempRiseK := fPartHeatKJ / (fOilMassKg * fOilCpKJkgK);
(* 热平衡稳态：热源平均功率 P = Q/t [kJ/s = kW]；稳态温升 dT = P / (k*A) [kW / (kW/K) = K]，量纲自洽 *)
fSteadyTempC := fOilTemp0C + (fPartHeatKJ / fCycleTimeS) / fExchCapKWperK;
(* 超限判定：容差比较，禁等值比较 *)
xOverTemp := fSteadyTempC > (fTempLimC + DL_EPS);
xValid := TRUE;                            (* 链路有效 / Chain valid *)
FC_DL_QuenchOilTempRiseCalc := fSteadyTempC;   (* 返回稳态油温 [°C] / Return steady temp *)
END_FUNCTION
