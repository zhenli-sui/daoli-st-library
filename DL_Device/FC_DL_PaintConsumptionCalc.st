(*
  Name: FC_DL_PaintConsumptionCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：单件涂料消耗与利用率：实际用量按流量×节拍÷件数折算，理论用量按膜厚×面积÷固含量折算。
  边界条件：① 六入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 件数为除子（≥ 1 件）、固含量为除子（5~100 %）、面积为理论用量乘数，全部域闸拦截；
            ③ 利用率 = 理论湿漆量 ÷ 实际用量 × 100，可超 100 %（表明实际用量偏低，照实上报不钳位）。
  量纲自证：ml/min × s ÷ 60 = ml；μm × m2 = ml（1 μm·m2 = 1 ml）；两者同量纲故比值无量纲。
*)
FUNCTION FC_DL_PaintConsumptionCalc : REAL
VAR_INPUT
    fFlowMlmin : REAL;      (* 喷枪湿漆流量 [ml/min] Wet paint flow [ml/min] *)
    fCycleTimeS : REAL;     (* 单次喷涂节拍 [s] Coating cycle time [s] *)
    nParts : INT;           (* 单次节拍内件数 [件] Parts per cycle *)
    fSolidPct : REAL;       (* 固含量（质量） [%] Solids content [%] *)
    fFilmUm : REAL;         (* 目标干膜厚度 [μm] Target dry film thickness [um] *)
    fAreaM2 : REAL;         (* 单件喷涂面积 [m2] Coated area per part [m2] *)
END_VAR
VAR_OUTPUT
    fPaintPerPartMl : REAL; (* 单件实际消耗 [ml] Paint consumption per part [ml] *)
    fUtilPct : REAL;        (* 涂料利用率 [%] Paint utilization [%] *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_SECMIN : REAL := 60.0;       (* 每秒 → 每分钟换算 [s/min] Second to minute *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
    DL_F_MIN : REAL := 1.0;         (* 流量下限 [ml/min] Flow floor [ml/min] *)
    DL_F_MAX : REAL := 2000.0;      (* 流量上限 [ml/min] Flow ceiling [ml/min] *)
    DL_T_MIN : REAL := 1.0;         (* 节拍下限 [s] Cycle floor [s] *)
    DL_T_MAX : REAL := 3600.0;      (* 节拍上限 [s] Cycle ceiling [s] *)
    DL_N_MAX : INT := 500;          (* 件数上限 [件] Part count ceiling *)
    DL_S_MIN : REAL := 5.0;         (* 固含量下限 [%] Solids floor [%] *)
    DL_S_MAX : REAL := 100.0;       (* 固含量上限 [%] Solids ceiling [%] *)
    DL_FILM_MIN : REAL := 1.0;      (* 膜厚下限 [μm] Film floor [um] *)
    DL_FILM_MAX : REAL := 200.0;    (* 膜厚上限 [μm] Film ceiling [um] *)
    DL_A_MIN : REAL := 0.001;       (* 面积下限 [m2] Area floor [m2] *)
    DL_A_MAX : REAL := 100.0;       (* 面积上限 [m2] Area ceiling [m2] *)
END_VAR
VAR
    fActualMl : REAL;   (* 单次节拍实际用量 [ml] Actual paint per cycle [ml] *)
    fTheoryMl : REAL;   (* 单件理论湿漆量 [ml] Theoretical wet paint per part [ml] *)
END_VAR
(* 出口预置：三出口统一预置（R256） *)
fPaintPerPartMl := 0.0; fUtilPct := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，五浮点入参全枚举（R272） *)
IF (fFlowMlmin <> fFlowMlmin) OR ((fFlowMlmin - fFlowMlmin) <> 0.0)
   OR (fCycleTimeS <> fCycleTimeS) OR ((fCycleTimeS - fCycleTimeS) <> 0.0)
   OR (fSolidPct <> fSolidPct) OR ((fSolidPct - fSolidPct) <> 0.0)
   OR (fFilmUm <> fFilmUm) OR ((fFilmUm - fFilmUm) <> 0.0)
   OR (fAreaM2 <> fAreaM2) OR ((fAreaM2 - fAreaM2) <> 0.0) THEN
    FC_DL_PaintConsumptionCalc := -1.0;     (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：流量、节拍、件数、固含量、膜厚、面积逐项定域（件数与固含为除子） *)
IF (fFlowMlmin < DL_F_MIN) OR (fFlowMlmin > DL_F_MAX)
   OR (fCycleTimeS < DL_T_MIN) OR (fCycleTimeS > DL_T_MAX)
   OR (nParts < 1) OR (nParts > DL_N_MAX)
   OR (fSolidPct < DL_S_MIN) OR (fSolidPct > DL_S_MAX)
   OR (fFilmUm < DL_FILM_MIN) OR (fFilmUm > DL_FILM_MAX)
   OR (fAreaM2 < DL_A_MIN) OR (fAreaM2 > DL_A_MAX) THEN
    FC_DL_PaintConsumptionCalc := -1.0;     (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 单次节拍实际用量：ml/min × s ÷ 60 = ml *)
fActualMl := fFlowMlmin * fCycleTimeS / DL_SECMIN;
(* 单件实际用量：件数已过下限闸，绝无零除 *)
fPaintPerPartMl := fActualMl / INT_TO_REAL(nParts);
(* 单件理论湿漆量：膜厚[μm] × 面积[m2] = ml（湿体积），再除固含量折算湿漆 *)
fTheoryMl := (fFilmUm * fAreaM2) / (fSolidPct / DL_PCT);
(* 利用率：理论 ÷ 实际 × 100，实际用量已由流量下限保证为正 *)
fUtilPct := (fTheoryMl / fPaintPerPartMl) * DL_PCT;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_PaintConsumptionCalc := fPaintPerPartMl;
END_FUNCTION
