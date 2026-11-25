(*
  Name: FC_DL_SlitterKnifeClearanceCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：分条圆盘刀侧间隙与刀盘重叠量：基准间隙率随抗拉强度线性修正后乘厚度。
  边界条件：① 三入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 间隙率修正以 400 MPa 为基准点、每 100 MPa 增减 0.5 个百分点，修正后钳位 2~14 %；
            ③ 重叠量取侧间隙的 15 %（薄料防刀口顶死经验值），随间隙同比缩放，无量纲系数见常量；
            ④ 钳位属量值饱和，置 xValid 保持 TRUE（厚度与强度均已合法）。
  量纲自证：pct[%]/100 无量纲；thk[mm] × 无量纲 = mm。
*)
FUNCTION FC_DL_SlitterKnifeClearanceCalc : REAL
VAR_INPUT
    fThkMm : REAL;          (* 带钢厚度 [mm] Strip thickness [mm] *)
    fTensileMpa : REAL;     (* 抗拉强度 [MPa] Tensile strength [MPa] *)
    fClearPctBase : REAL;   (* 基准间隙率（400 MPa 基准点） [%] Base clearance ratio at 400 MPa [%] *)
END_VAR
VAR_OUTPUT
    fClearanceMm : REAL;    (* 侧间隙 [mm] Side clearance [mm] *)
    fOverlapMm : REAL;      (* 刀盘重叠量 [mm] Knife overlap [mm] *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_KNIFE_TSREF : REAL := 400.0;     (* 间隙率基准强度 [MPa] Reference tensile strength [MPa] *)
    DL_KNIFE_SLOPE : REAL := 0.5;       (* 每 100 MPa 间隙率增量 [%/100MPa] Ratio increment per 100 MPa *)
    DL_KNIFE_OVL : REAL := 0.15;        (* 重叠量/侧间隙比 [-] Overlap to clearance ratio *)
    DL_KNIFE_PCT_LO : REAL := 2.0;      (* 间隙率下限 [%] Clearance ratio floor [%] *)
    DL_KNIFE_PCT_HI : REAL := 14.0;     (* 间隙率上限 [%] Clearance ratio ceiling [%] *)
    DL_PCT : REAL := 100.0;             (* 百分数基准 [%] Percent base *)
    DL_T_MIN : REAL := 0.1;             (* 带厚下限 [mm] Thickness floor [mm] *)
    DL_T_MAX : REAL := 6.0;             (* 带厚上限 [mm] Thickness ceiling [mm] *)
    DL_TS_MIN : REAL := 200.0;          (* 强度下限 [MPa] Tensile floor [MPa] *)
    DL_TS_MAX : REAL := 1500.0;         (* 强度上限 [MPa] Tensile ceiling [MPa] *)
    DL_B_MIN : REAL := 1.0;             (* 基准间隙率下限 [%] Base ratio floor [%] *)
    DL_B_MAX : REAL := 15.0;            (* 基准间隙率上限 [%] Base ratio ceiling [%] *)
END_VAR
VAR
    fPct : REAL;    (* 修正后间隙率 [%] Corrected clearance ratio [%] *)
END_VAR
(* 出口预置：三出口统一预置（R256） *)
fClearanceMm := 0.0; fOverlapMm := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，三入参全枚举 *)
IF (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0)
   OR (fTensileMpa <> fTensileMpa) OR ((fTensileMpa - fTensileMpa) <> 0.0)
   OR (fClearPctBase <> fClearPctBase) OR ((fClearPctBase - fClearPctBase) <> 0.0) THEN
    FC_DL_SlitterKnifeClearanceCalc := -1.0;    (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：厚度、强度、基准间隙率逐项定域 *)
IF (fThkMm < DL_T_MIN) OR (fThkMm > DL_T_MAX)
   OR (fTensileMpa < DL_TS_MIN) OR (fTensileMpa > DL_TS_MAX)
   OR (fClearPctBase < DL_B_MIN) OR (fClearPctBase > DL_B_MAX) THEN
    FC_DL_SlitterKnifeClearanceCalc := -1.0;    (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 强度线性修正：pct = base + slope·(σ − σref)/100，斜率单位 %/100MPa *)
fPct := fClearPctBase + DL_KNIFE_SLOPE * ((fTensileMpa - DL_KNIFE_TSREF) / DL_PCT);
(* 修正后钳位：低于下限刀口挤压、高于上限毛刺超差 *)
IF fPct < DL_KNIFE_PCT_LO THEN
    fPct := DL_KNIFE_PCT_LO;
ELSIF fPct > DL_KNIFE_PCT_HI THEN
    fPct := DL_KNIFE_PCT_HI;
END_IF
(* 侧间隙：thk[mm] × pct[%]/100 = mm *)
fClearanceMm := fThkMm * (fPct / DL_PCT);
(* 重叠量：侧间隙 × 经验比，无量纲系数，量纲保持 mm *)
fOverlapMm := fClearanceMm * DL_KNIFE_OVL;
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_SlitterKnifeClearanceCalc := fClearanceMm;
END_FUNCTION
