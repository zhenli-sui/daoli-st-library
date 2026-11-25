(*
  Name: FC_DL_CrusherThroughputCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：按排矿口开口比产能法算颚式/圆锥破碎机实际产能，并以单程合格率反算闭路循环负荷率。
  边界条件：① 五入参全部过非有限闸（NaN 自反判 / Inf 差值自减判），任一非有限返回哨兵 -1；
            ② 排矿口 < 3 mm 或给料粒度不高于排矿口 1.2 倍（无有效破碎比）判组态非法，返回哨兵 -1；
            ③ 单程合格率下限 0.1，循环负荷率钳位 0~500 %（钳的是量值不钳事实，有效性不受影响）。
  量纲自证：q0[t/(h·mm)] × gap[mm] = t/h；kH / kD 无量纲；CL=(1/p−1)×100 无量纲。
*)
FUNCTION FC_DL_CrusherThroughputCalc : REAL
VAR_INPUT
    fFeedTph : REAL;        (* 给料量（新给矿） [t/h] Feed rate, fresh feed *)
    fGapMm : REAL;          (* 排矿口开口（闭侧） [mm] Closed-side gap [mm] *)
    fFeedSizeMm : REAL;     (* 给料粒度（95% 通过粒径） [mm] Feed size, 95% passing *)
    fHardnessIdx : REAL;    (* 硬度指数（1.0 为基准矿） [-] Hardness index, 1.0 baseline *)
    fBulkDensity : REAL;    (* 堆密度 [t/m3] Bulk density [t/m3] *)
END_VAR
VAR_OUTPUT
    fThroughputTph : REAL;      (* 实际破碎通过量 [t/h] Actual throughput [t/h] *)
    fCirculatingLoadPct : REAL; (* 闭路循环负荷率 [%] Circulating load ratio [%] *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_Q0 : REAL := 2.5;            (* 单位开口基准产能 [t/(h·mm)] Specific capacity per gap *)
    DL_DENS_REF : REAL := 1.6;      (* 基准堆密度 [t/m3] Reference bulk density *)
    DL_RR_MIN : REAL := 1.2;        (* 最小有效破碎比 [-] Minimum reduction ratio *)
    DL_CL_MAX : REAL := 500.0;      (* 循环负荷率饱和上限 [%] Circulating load ceiling *)
    DL_PASS_MIN : REAL := 0.1;      (* 单程合格率下限 [-] Minimum single-pass fraction *)
    DL_GAP_MIN : REAL := 3.0;       (* 排矿口工程下限 [mm] Minimum engineering gap *)
    DL_H_MIN : REAL := 0.2;         (* 硬度指数下限 [-] Hardness index floor *)
    DL_H_MAX : REAL := 5.0;         (* 硬度指数上限 [-] Hardness index ceiling *)
    DL_D_MIN : REAL := 0.5;         (* 堆密度下限 [t/m3] Bulk density floor *)
    DL_D_MAX : REAL := 4.0;         (* 堆密度上限 [t/m3] Bulk density ceiling *)
END_VAR
VAR
    fRr : REAL;     (* 破碎比 = 给料粒度/排矿口 [-] Reduction ratio *)
    fKh : REAL;     (* 硬度修正系数 [-] Hardness correction factor *)
    fKd : REAL;     (* 密度修正系数 [-] Density correction factor *)
    fQcap : REAL;   (* 排矿口通过能力 [t/h] Gap capability [t/h] *)
    fPass : REAL;   (* 单程合格率 [-] Single-pass pass fraction *)
    fQout : REAL;   (* 当拍通过量中间量 [t/h] Throughput scratch [t/h] *)
END_VAR
(* 出口预置：三出口统一预置安全值（R256） *)
fThroughputTph := 0.0; fCirculatingLoadPct := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，五入参全枚举（R272） *)
IF (fFeedTph <> fFeedTph) OR ((fFeedTph - fFeedTph) <> 0.0)
   OR (fGapMm <> fGapMm) OR ((fGapMm - fGapMm) <> 0.0)
   OR (fFeedSizeMm <> fFeedSizeMm) OR ((fFeedSizeMm - fFeedSizeMm) <> 0.0)
   OR (fHardnessIdx <> fHardnessIdx) OR ((fHardnessIdx - fHardnessIdx) <> 0.0)
   OR (fBulkDensity <> fBulkDensity) OR ((fBulkDensity - fBulkDensity) <> 0.0) THEN
    FC_DL_CrusherThroughputCalc := -1.0;    (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：给料、开口、粒度、硬度、密度逐项定域（禁 NaN 判假即放行，全用正向不等号） *)
IF (fFeedTph <= DL_EPS) OR (fGapMm < DL_GAP_MIN)
   OR (fFeedSizeMm <= fGapMm * DL_RR_MIN)
   OR (fHardnessIdx < DL_H_MIN) OR (fHardnessIdx > DL_H_MAX)
   OR (fBulkDensity < DL_D_MIN) OR (fBulkDensity > DL_D_MAX) THEN
    FC_DL_CrusherThroughputCalc := -1.0;    (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 破碎比：给料粒度 ÷ 排矿口，除子已过工程下限闸，量纲 mm/mm = 无量纲 *)
fRr := fFeedSizeMm / fGapMm;
(* 硬度修正：kH = 1/(0.6+0.4·H)，H = 1.0 时恰为 1.0，硬矿按比例降产能 *)
fKh := 1.0 / (0.6 + 0.4 * fHardnessIdx);
(* 密度修正：kD = ρ/ρref，无量纲 *)
fKd := fBulkDensity / DL_DENS_REF;
(* 排矿口通过能力：q0[t/(h·mm)] × gap[mm] × kH × kD，量纲收敛为 t/h *)
fQcap := DL_Q0 * fGapMm * fKh * fKd;
(* 实际通过量取给料与能力较小者：能力不足即积料，不虚报产能 *)
IF fFeedTph > fQcap THEN
    fQout := fQcap;
ELSE
    fQout := fFeedTph;
END_IF
(* 单程合格率：p = 1/(1+0.5·(Rr−1))，破碎比越大单程越粗、合格率越低 *)
fPass := 1.0 / (1.0 + 0.5 * (fRr - 1.0));
IF fPass < DL_PASS_MIN THEN
    fPass := DL_PASS_MIN;                   (* 下限钳位，防循环负荷率发散 / Clamp to avoid divergence *)
END_IF
(* 循环负荷率：CL = (1/p − 1)×100，除子 p 已过下限钳位，绝无零除 *)
fThroughputTph := fQout;
fCirculatingLoadPct := (1.0 / fPass - 1.0) * 100.0;
IF fCirculatingLoadPct > DL_CL_MAX THEN
    fCirculatingLoadPct := DL_CL_MAX;       (* 量值饱和钳位（事实量不饱和） / Value saturation *)
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_CrusherThroughputCalc := fThroughputTph;
END_FUNCTION
