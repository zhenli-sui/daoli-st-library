(*
  Name: FC_DL_BoothFilterLifeCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：过滤棉剩余寿命：按压差累积法算寿命消耗百分比，并按当前压差增长率外推剩余运行小时。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 新棉压差必须 > 0 且报废压差必须高于新棉压差（否则分母 ΔP 塌零，返回哨兵 -1）；
            ③ 已用压差 Δp − Δp_new 为除子，外推前显式判零：低于 DL_EPS 时剩余小时按满寿命处理；
            ④ 寿命百分比钳 0~100 %（量值饱和）；报警门限 90 %，超报废压差即 100 % 并报警。
  量纲自证：(ΔP − ΔP_new)/(ΔP_end − ΔP_new) 无量纲；h × 无量纲 = h。
*)
FUNCTION FC_DL_BoothFilterLifeCalc : REAL
VAR_INPUT
    fDpPa : REAL;           (* 当前滤棉压差 [Pa] Current filter pressure drop [Pa] *)
    fDpNewPa : REAL;        (* 新棉压差（洁净基线） [Pa] Clean filter pressure drop [Pa] *)
    fDpEndPa : REAL;        (* 报废压差 [Pa] End-of-life pressure drop [Pa] *)
    fRunHours : REAL;       (* 滤棉已运行小时 [h] Filter accumulated run hours [h] *)
END_VAR
VAR_OUTPUT
    fLifeUsedPct : REAL;    (* 寿命消耗百分比 [%] Life used [%] *)
    fRemainHours : REAL;    (* 剩余可用小时（外推） [h] Remaining hours, extrapolated [h] *)
    xReplaceAlarm : BOOL;   (* 更换报警（寿命 ≥ 90 %） [-] Replace alarm *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
    DL_ALARM_PCT : REAL := 90.0;    (* 更换报警门限 [%] Replace alarm threshold [%] *)
    DL_P_NEW_MAX : REAL := 500.0;   (* 新棉压差上限 [Pa] Clean pressure ceiling [Pa] *)
    DL_P_END_MIN : REAL := 100.0;   (* 报废压差下限 [Pa] End pressure floor [Pa] *)
    DL_P_END_MAX : REAL := 5000.0;  (* 报废压差上限 [Pa] End pressure ceiling [Pa] *)
    DL_H_MAX : REAL := 100000.0;    (* 运行小时上限 [h] Run hours ceiling [h] *)
END_VAR
VAR
    fSpanPa : REAL;     (* 全寿命压差跨度 [Pa] Full-life pressure span [Pa] *)
    fUsedPa : REAL;     (* 已消耗压差 [Pa] Consumed pressure drop [Pa] *)
    fPct : REAL;        (* 寿命消耗中间量 [%] Life used scratch [%] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fLifeUsedPct := 0.0; fRemainHours := 0.0; xReplaceAlarm := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fDpPa <> fDpPa) OR ((fDpPa - fDpPa) <> 0.0)
   OR (fDpNewPa <> fDpNewPa) OR ((fDpNewPa - fDpNewPa) <> 0.0)
   OR (fDpEndPa <> fDpEndPa) OR ((fDpEndPa - fDpEndPa) <> 0.0)
   OR (fRunHours <> fRunHours) OR ((fRunHours - fRunHours) <> 0.0) THEN
    FC_DL_BoothFilterLifeCalc := -1.0;      (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：压差三点与运行小时定域，报废压差须高于新棉压差 *)
IF (fDpNewPa < DL_EPS) OR (fDpNewPa > DL_P_NEW_MAX)
   OR (fDpEndPa < DL_P_END_MIN) OR (fDpEndPa > DL_P_END_MAX)
   OR ((fDpEndPa - fDpNewPa) <= DL_EPS)
   OR (fDpPa < 0.0) OR (fDpPa > (fDpEndPa * 1.5))
   OR (fRunHours < 0.0) OR (fRunHours > DL_H_MAX) THEN
    FC_DL_BoothFilterLifeCalc := -1.0;      (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 全寿命压差跨度已过正性闸，绝无零除 *)
fSpanPa := fDpEndPa - fDpNewPa;
(* 已消耗压差：低于新棉基线按 0 处理（新棉初期压差抖动不产生负寿命） *)
fUsedPa := fDpPa - fDpNewPa;
IF fUsedPa < 0.0 THEN
    fUsedPa := 0.0;
END_IF
(* 寿命消耗百分比 *)
fPct := (fUsedPa / fSpanPa) * DL_PCT;
IF fPct > DL_PCT THEN
    fPct := DL_PCT;                         (* 量值饱和：超报废压差即 100 % / Saturation at 100 % *)
END_IF
fLifeUsedPct := fPct;
(* 剩余小时外推：h × (剩余压差/已耗压差)；已耗压差塌零时按满寿命 + 无穷处置为 0 剩余待定 *)
IF fUsedPa <= DL_EPS THEN
    fRemainHours := DL_H_MAX;               (* 近乎新棉：剩余小时按可表上限 / Effectively new filter *)
ELSE
    fRemainHours := fRunHours * ((fSpanPa - fUsedPa) / fUsedPa);
    IF fRemainHours < 0.0 THEN
        fRemainHours := 0.0;                (* 已超报废压差：剩余 0 h / Past end of life *)
    END_IF
END_IF
xReplaceAlarm := fLifeUsedPct >= DL_ALARM_PCT;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_BoothFilterLifeCalc := fLifeUsedPct;
END_FUNCTION
