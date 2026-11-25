(*
  Name: FC_DL_BallMillPowerDrawCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：球磨机轴功率与比能耗估算（筒径/筒长/转速率/装球率经验幂律），并折算单位给矿能耗。
  边界条件：① 五入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 筒径 0.5~8 m、筒长 0.5~15 m、临界转速率 30~100 %、装球率 10~55 % 为工程域，越域返回哨兵 -1；
            ③ 给矿量为 0 属正常运行工况（空转），比能耗输出 0 而不判非法，功率照常有效；
            ④ 幂次 2.5 以 D·D·SQRT(D) 展开实现，不引入 EXPT 原语（R140 委托纪律）。
  量纲自证：K[kW/m^3.5] × D^2.5[m^2.5] × L[m] = kW；转速率与装球率为无量纲百分比折算。
*)
FUNCTION FC_DL_BallMillPowerDrawCalc : REAL
VAR_INPUT
    fMillDiaM : REAL;        (* 磨机筒体有效内径 [m] Mill effective diameter [m] *)
    fMillLenM : REAL;        (* 磨机筒体有效长度 [m] Mill effective length [m] *)
    fSpeedPct : REAL;        (* 临界转速百分比 [%] Percent of critical speed [%] *)
    fMediaLoadPct : REAL;    (* 装球率（磨机容积占比） [%] Ball charge volume ratio [%] *)
    fFeedTph : REAL;         (* 给矿量 [t/h] Feed rate [t/h] *)
END_VAR
VAR_OUTPUT
    fPowerKW : REAL;         (* 磨机轴功率 [kW] Mill shaft power [kW] *)
    fSpecificKWhT : REAL;    (* 单位给矿能耗 [kWh/t] Specific energy per tonne [kWh/t] *)
    xValid : BOOL;           (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_K_POWER : REAL := 26.0;      (* 功率经验系数 [kW/m^3.5] Empirical power coefficient *)
    DL_D_MIN : REAL := 0.5;         (* 筒径下限 [m] Diameter floor [m] *)
    DL_D_MAX : REAL := 8.0;         (* 筒径上限 [m] Diameter ceiling [m] *)
    DL_L_MIN : REAL := 0.5;         (* 筒长下限 [m] Length floor [m] *)
    DL_L_MAX : REAL := 15.0;        (* 筒长上限 [m] Length ceiling [m] *)
    DL_SPD_MIN : REAL := 30.0;      (* 转速率下限 [%] Speed ratio floor [%] *)
    DL_SPD_MAX : REAL := 100.0;     (* 转速率上限 [%] Speed ratio ceiling [%] *)
    DL_MED_MIN : REAL := 10.0;      (* 装球率下限 [%] Media load floor [%] *)
    DL_MED_MAX : REAL := 55.0;      (* 装球率上限 [%] Media load ceiling [%] *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
END_VAR
VAR
    fD25 : REAL;    (* 筒径 2.5 次幂 [m^2.5] Diameter to the power 2.5 *)
    fKspd : REAL;   (* 转速率折算系数 [-] Speed ratio factor *)
    fKmed : REAL;   (* 装球率折算系数 [-] Media load factor *)
END_VAR
(* 出口预置：三出口统一预置（R256） *)
fPowerKW := 0.0; fSpecificKWhT := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，五入参全枚举 *)
IF (fMillDiaM <> fMillDiaM) OR ((fMillDiaM - fMillDiaM) <> 0.0)
   OR (fMillLenM <> fMillLenM) OR ((fMillLenM - fMillLenM) <> 0.0)
   OR (fSpeedPct <> fSpeedPct) OR ((fSpeedPct - fSpeedPct) <> 0.0)
   OR (fMediaLoadPct <> fMediaLoadPct) OR ((fMediaLoadPct - fMediaLoadPct) <> 0.0)
   OR (fFeedTph <> fFeedTph) OR ((fFeedTph - fFeedTph) <> 0.0) THEN
    FC_DL_BallMillPowerDrawCalc := -1.0;    (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：几何与工艺参数逐项定域，给矿量允许为 0（空转） *)
IF (fMillDiaM < DL_D_MIN) OR (fMillDiaM > DL_D_MAX)
   OR (fMillLenM < DL_L_MIN) OR (fMillLenM > DL_L_MAX)
   OR (fSpeedPct < DL_SPD_MIN) OR (fSpeedPct > DL_SPD_MAX)
   OR (fMediaLoadPct < DL_MED_MIN) OR (fMediaLoadPct > DL_MED_MAX)
   OR (fFeedTph < 0.0) THEN
    FC_DL_BallMillPowerDrawCalc := -1.0;    (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 幂次展开：D^2.5 = D·D·√D，量纲 m^2.5 *)
fD25 := fMillDiaM * fMillDiaM * SQRT(fMillDiaM);
(* 两百分比折算为无量纲系数 *)
fKspd := fSpeedPct / DL_PCT;
fKmed := fMediaLoadPct / DL_PCT;
(* 轴功率：K[kW/m^3.5] × D^2.5 × L × kspd × kmed，量纲收敛为 kW *)
fPowerKW := DL_K_POWER * fD25 * fMillLenM * fKspd * fKmed;
(* 比能耗：给矿为 0 时输出 0（除零保护，且空转不产比能耗事实） *)
IF fFeedTph > DL_EPS THEN
    fSpecificKWhT := fPowerKW / fFeedTph;   (* kW ÷ (t/h) = kWh/t *)
ELSE
    fSpecificKWhT := 0.0;                   (* 空转：无比能耗 / No specific energy at no feed *)
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_BallMillPowerDrawCalc := fPowerKW;
END_FUNCTION
