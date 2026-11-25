(*
  Name: FC_DL_ForgeLoadTonCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：锻造载荷：投影面积 × 变形抗力 × 形状系数得锻造力，折算吨位与压机利用率。
  边界条件：① 三入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 投影面积 100~5e6 mm2、变形抗力 20~400 MPa、形状系数 1.0~3.0 为工程域，越域返回哨兵 -1；
            ③ 压机额定载荷为常量 DL_FLT_PRESS_KN（默认 20000 kN），利用率可超 100 %（超载照实上报不钳位）。
  量纲自证：mm2 × (N/mm2) = N；N/1000 = kN；kN ÷ 9.80665[kN/tf] = tf 折算吨位。
*)
FUNCTION FC_DL_ForgeLoadTonCalc : REAL
VAR_INPUT
    fProjAreaMm2 : REAL;        (* 锻件投影面积 [mm2] Forging projected area [mm2] *)
    fFlowStressMpa : REAL;      (* 变形抗力（流动应力） [MPa] Flow stress [MPa] *)
    fShapeFactor : REAL;        (* 形状系数（1.0~3.0） [-] Shape factor *)
END_VAR
VAR_OUTPUT
    fLoadKN : REAL;             (* 锻造力 [kN] Forging load [kN] *)
    fLoadTon : REAL;            (* 折算吨位 [tf] Load in tonne-force [tf] *)
    fPressUtilPct : REAL;       (* 压机利用率（可超 100 %） [%] Press utilization [%] *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_KN_PER_N : REAL := 1000.0;       (* 牛 → 千牛换算 [N/kN] Newton to kilonewton *)
    DL_KN_PER_TF : REAL := 9.80665;     (* 吨力 → 千牛换算 [kN/tf] Kilonewton per tonne-force *)
    DL_FLT_PRESS_KN : REAL := 20000.0;  (* 压机额定载荷（可改常量） [kN] Press rated load [kN] *)
    DL_PCT : REAL := 100.0;             (* 百分数基准 [%] Percent base *)
    DL_A_MIN : REAL := 100.0;           (* 投影面积下限 [mm2] Area floor [mm2] *)
    DL_A_MAX : REAL := 5000000.0;       (* 投影面积上限 [mm2] Area ceiling [mm2] *)
    DL_S_MIN : REAL := 20.0;            (* 变形抗力下限 [MPa] Flow stress floor [MPa] *)
    DL_S_MAX : REAL := 400.0;           (* 变形抗力上限 [MPa] Flow stress ceiling [MPa] *)
    DL_F_MIN : REAL := 1.0;             (* 形状系数下限 [-] Shape factor floor *)
    DL_F_MAX : REAL := 3.0;             (* 形状系数上限 [-] Shape factor ceiling *)
END_VAR
VAR
    fForceN : REAL;     (* 锻造力（牛） [N] Forging force [N] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fLoadKN := 0.0; fLoadTon := 0.0; fPressUtilPct := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，三入参全枚举 *)
IF (fProjAreaMm2 <> fProjAreaMm2) OR ((fProjAreaMm2 - fProjAreaMm2) <> 0.0)
   OR (fFlowStressMpa <> fFlowStressMpa) OR ((fFlowStressMpa - fFlowStressMpa) <> 0.0)
   OR (fShapeFactor <> fShapeFactor) OR ((fShapeFactor - fShapeFactor) <> 0.0) THEN
    FC_DL_ForgeLoadTonCalc := -1.0;         (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：面积、变形抗力、形状系数逐项定域 *)
IF (fProjAreaMm2 < DL_A_MIN) OR (fProjAreaMm2 > DL_A_MAX)
   OR (fFlowStressMpa < DL_S_MIN) OR (fFlowStressMpa > DL_S_MAX)
   OR (fShapeFactor < DL_F_MIN) OR (fShapeFactor > DL_F_MAX) THEN
    FC_DL_ForgeLoadTonCalc := -1.0;         (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 锻造力：mm2 × N/mm2 = N，再乘无量纲形状系数 *)
fForceN := fProjAreaMm2 * fFlowStressMpa * fShapeFactor;
(* 折算 kN 与吨位：kN ÷ kN/tf = tf *)
fLoadKN := fForceN / DL_KN_PER_N;
fLoadTon := fLoadKN / DL_KN_PER_TF;
(* 压机利用率：常量额定载荷恒正，超载照实超 100 %（事实不钳位） *)
fPressUtilPct := (fLoadKN / DL_FLT_PRESS_KN) * DL_PCT;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_ForgeLoadTonCalc := fLoadKN;
END_FUNCTION
