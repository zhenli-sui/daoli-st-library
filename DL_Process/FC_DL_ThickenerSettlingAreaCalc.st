(*
  Name: FC_DL_ThickenerSettlingAreaCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：按固体体积衡算求浓密机底流体积流量与溢流量，再用沉降速度法算所需沉降面积与上升流速。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 底流浓度必须显著高于给矿浓度（差值 ≥ 1 %），否则衡算无解，返回哨兵 -1；
            ③ 体积分数 φ 由质量分数与固/液密度反算，分母（固相项 + 液相项）在 0~1 质量分数域内恒正，
               仍以 DL_EPS 兜底防浮点下溢；面积取安全系数 1.15，上升流速 = Qo/A 故恒低于沉降速度。
  量纲自证：Q[m3/h] ÷ v[m/h] = m2；φ 无量纲。
*)
FUNCTION FC_DL_ThickenerSettlingAreaCalc : REAL
VAR_INPUT
    fFeedM3h : REAL;         (* 给矿浆体流量 [m3/h] Feed slurry flow [m3/h] *)
    fFeedSolidsPct : REAL;   (* 给矿固体质量浓度 [%] Feed solids mass concentration [%] *)
    fUnderSolidsPct : REAL;  (* 底流固体质量浓度 [%] Underflow solids mass concentration [%] *)
    fSettlingVel : REAL;     (* 自由沉降速度 [m/h] Free settling velocity [m/h] *)
END_VAR
VAR_OUTPUT
    fAreaM2 : REAL;          (* 所需沉降面积（含安全系数） [m2] Required settling area [m2] *)
    fRiseVel : REAL;         (* 溢流上升流速 [m/h] Overflow rise velocity [m/h] *)
    fOverflowM3h : REAL;     (* 溢流浆体流量 [m3/h] Overflow flow [m3/h] *)
    xSizingOk : BOOL;        (* 上升流速低于沉降速度则 TRUE [-] Rise velocity below settling velocity *)
    xValid : BOOL;           (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;      (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_RHO_S : REAL := 2.7;       (* 固体密度（矿浆通用取值） [t/m3] Solids density [t/m3] *)
    DL_RHO_W : REAL := 1.0;       (* 液相密度（水） [t/m3] Liquid density [t/m3] *)
    DL_SF : REAL := 1.15;         (* 面积安全系数 [-] Area safety factor *)
    DL_PCT : REAL := 100.0;       (* 百分数基准 [%] Percent base *)
    DL_CONC_MIN_DIFF : REAL := 1.0; (* 底流与给矿浓度最小差值 [%] Minimum concentration difference *)
END_VAR
VAR
    fCf : REAL;     (* 给矿质量分数 [-] Feed mass fraction *)
    fCu : REAL;     (* 底流质量分数 [-] Underflow mass fraction *)
    fPhiF : REAL;   (* 给矿固体体积分数 [-] Feed solids volume fraction *)
    fPhiU : REAL;   (* 底流固体体积分数 [-] Underflow solids volume fraction *)
    fQs : REAL;     (* 固体体积流量 [m3/h] Solids volume flow [m3/h] *)
    fQu : REAL;     (* 底流浆体体积流量 [m3/h] Underflow slurry flow [m3/h] *)
    fQo : REAL;     (* 溢流浆体体积流量 [m3/h] Overflow flow [m3/h] *)
END_VAR
(* 出口预置：五出口统一预置（R256） *)
fAreaM2 := 0.0; fRiseVel := 0.0; fOverflowM3h := 0.0; xSizingOk := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举（R272） *)
IF (fFeedM3h <> fFeedM3h) OR ((fFeedM3h - fFeedM3h) <> 0.0)
   OR (fFeedSolidsPct <> fFeedSolidsPct) OR ((fFeedSolidsPct - fFeedSolidsPct) <> 0.0)
   OR (fUnderSolidsPct <> fUnderSolidsPct) OR ((fUnderSolidsPct - fUnderSolidsPct) <> 0.0)
   OR (fSettlingVel <> fSettlingVel) OR ((fSettlingVel - fSettlingVel) <> 0.0) THEN
    FC_DL_ThickenerSettlingAreaCalc := -1.0;    (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：流量与沉降速度为除子，浓度须物理可行且底流显著高于给矿 *)
IF (fFeedM3h <= DL_EPS) OR (fSettlingVel <= DL_EPS)
   OR (fFeedSolidsPct <= 0.0) OR (fFeedSolidsPct >= DL_PCT)
   OR (fUnderSolidsPct <= 0.0) OR (fUnderSolidsPct > DL_PCT)
   OR ((fUnderSolidsPct - fFeedSolidsPct) < DL_CONC_MIN_DIFF) THEN
    FC_DL_ThickenerSettlingAreaCalc := -1.0;    (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
fCf := fFeedSolidsPct / DL_PCT;                 (* 质量分数 [-] Mass fraction *)
fCu := fUnderSolidsPct / DL_PCT;
(* 体积分数：φ = (C/ρs) / (C/ρs + (1−C)/ρw)，固液体积可加性假设 *)
IF ((fCf / DL_RHO_S) + ((1.0 - fCf) / DL_RHO_W)) <= DL_EPS THEN
    FC_DL_ThickenerSettlingAreaCalc := -1.0;    (* 哨兵 -1：体积分数塌零 / Sentinel -1, vanishing phi *)
    RETURN;
END_IF
fPhiF := (fCf / DL_RHO_S) / ((fCf / DL_RHO_S) + ((1.0 - fCf) / DL_RHO_W));
fPhiU := (fCu / DL_RHO_S) / ((fCu / DL_RHO_S) + ((1.0 - fCu) / DL_RHO_W));
(* 固体体积衡算：Qs = Qf·φf；底流体积 Qu = Qs/φu，φu 已过域闸恒正 *)
IF fPhiU <= DL_EPS THEN
    FC_DL_ThickenerSettlingAreaCalc := -1.0;    (* 哨兵 -1：底流体积分数塌零 / Sentinel -1, phi underflow zero *)
    RETURN;
END_IF
fQs := fFeedM3h * fPhiF;                        (* 固体体积流量 [m3/h] Solids volume flow *)
fQu := fQs / fPhiU;                             (* 底流浆体流量 [m3/h] Underflow slurry flow *)
fQo := fFeedM3h - fQu;                          (* 溢流 = 给矿 − 底流 [m3/h] Overflow flow *)
IF fQo <= DL_EPS THEN
    FC_DL_ThickenerSettlingAreaCalc := -1.0;    (* 哨兵 -1：衡算无溢流，组态矛盾 / Sentinel -1, no overflow *)
    RETURN;
END_IF
(* 沉降面积：A = Qo/v × SF，Qo[m3/h] ÷ v[m/h] = m2 *)
fAreaM2 := (fQo / fSettlingVel) * DL_SF;
(* 上升流速：vR = Qo/A，A 已过正性检查（上式保证 ≥ SF 倍正量） *)
IF fAreaM2 <= DL_EPS THEN
    FC_DL_ThickenerSettlingAreaCalc := -1.0;    (* 哨兵 -1：面积塌零 / Sentinel -1, vanishing area *)
    RETURN;
END_IF
fRiseVel := fQo / fAreaM2;
fOverflowM3h := fQo;
(* 校核：上升流速低于自由沉降速度（含安全系数后恒成立，此处照实判定） *)
xSizingOk := fRiseVel < fSettlingVel;
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_ThickenerSettlingAreaCalc := fAreaM2;
END_FUNCTION
