(*
  Name: FC_DL_AnnealSoakTimeCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：退火保温时间：基准每毫米时间 × 厚度 × 装炉系数（装炉量越大保温越久）。
  边界条件：① 三入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 厚度 0.2~8 mm（冷轧退火带）、基准 0.1~5 min/mm、装炉系数 1.0~2.5 为工程域，越域返回哨兵 -1；
            ③ 装炉系数按经验域钳位后再乘，量值饱和不伪造事实。
  量纲自证：min/mm × mm = min；装炉系数无量纲，量纲保持 min。
*)
FUNCTION FC_DL_AnnealSoakTimeCalc : REAL
VAR_INPUT
    fThkMm : REAL;              (* 带钢厚度 [mm] Strip thickness [mm] *)
    fBatchFactor : REAL;        (* 装炉系数（1.0 单卷 ~ 2.5 满炉） [-] Batch loading factor *)
    fBaseMinPerMm : REAL;       (* 基准保温时间 [min/mm] Base soak time per mm [min/mm] *)
END_VAR
VAR_OUTPUT
    fSoakMin : REAL;            (* 保温时间 [min] Soak time [min] *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_T_MIN : REAL := 0.2;         (* 厚度下限 [mm] Thickness floor [mm] *)
    DL_T_MAX : REAL := 8.0;         (* 厚度上限 [mm] Thickness ceiling [mm] *)
    DL_B_MIN : REAL := 0.1;         (* 基准时间下限 [min/mm] Base time floor [min/mm] *)
    DL_B_MAX : REAL := 5.0;         (* 基准时间上限 [min/mm] Base time ceiling [min/mm] *)
    DL_F_MIN : REAL := 1.0;         (* 装炉系数下限 [-] Batch factor floor *)
    DL_F_MAX : REAL := 2.5;         (* 装炉系数上限 [-] Batch factor ceiling *)
END_VAR
VAR
    fBatch : REAL;  (* 钳位后装炉系数 [-] Clamped batch factor *)
END_VAR
(* 出口预置：两出口统一预置（R256） *)
fSoakMin := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，三入参全枚举 *)
IF (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0)
   OR (fBatchFactor <> fBatchFactor) OR ((fBatchFactor - fBatchFactor) <> 0.0)
   OR (fBaseMinPerMm <> fBaseMinPerMm) OR ((fBaseMinPerMm - fBaseMinPerMm) <> 0.0) THEN
    FC_DL_AnnealSoakTimeCalc := -1.0;       (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：厚度、基准时间、装炉系数逐项定域 *)
IF (fThkMm < DL_T_MIN) OR (fThkMm > DL_T_MAX)
   OR (fBaseMinPerMm < DL_B_MIN) OR (fBaseMinPerMm > DL_B_MAX)
   OR (fBatchFactor < DL_F_MIN) OR (fBatchFactor > DL_F_MAX) THEN
    FC_DL_AnnealSoakTimeCalc := -1.0;       (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 装炉系数二阶钳定：域内直通，边界外按域几何内点收紧（R117 两级回退） *)
fBatch := fBatchFactor;
IF fBatch < DL_F_MIN THEN
    fBatch := DL_F_MIN;
ELSIF fBatch > DL_F_MAX THEN
    fBatch := DL_F_MAX;
END_IF
(* 保温时间：min/mm × mm × 无量纲 = min *)
fSoakMin := fBaseMinPerMm * fThkMm * fBatch;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_AnnealSoakTimeCalc := fSoakMin;
END_FUNCTION
