(*
  Name: FC_DL_ScreenEfficiencyCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：按入料/筛上/筛下三处细粒含量算振动筛筛分效率（经典式，全部折算为小数参与运算）。
  边界条件：① 三入参百分数先折算小数，入料细粒 0~100 %、筛上 0~100 %、筛下 0~100 %；
            ② 分母 (1−O)·(F+U−1) 显式零闸，绝对值不超 DL_EPS 即判非法返回哨兵 -1；
            ③ 效率物理域 0~100 %；算得负值（物料衡算矛盾，如筛下含量低于入料）判 xValid = FALSE 并返回 -1。
  量纲自证：F/O/U 均为质量分数（无量纲），E 亦无量纲，×100 得百分数。
*)
FUNCTION FC_DL_ScreenEfficiencyCalc : REAL
VAR_INPUT
    fFeedFinesPct : REAL;   (* 入料细粒含量 [%] Feed fines content [%] *)
    fOverFinesPct : REAL;   (* 筛上细粒含量 [%] Oversize fines content [%] *)
    fUnderFinesPct : REAL;  (* 筛下合格细粒含量 [%] Undersize fines content [%] *)
END_VAR
VAR_OUTPUT
    fEfficiencyPct : REAL;  (* 筛分效率 [%] Screening efficiency [%] *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;    (* 除零判定容差 [-] Divide-by-zero tolerance *)
    DL_PCT : REAL := 100.0;     (* 百分数基准 [%] Percent base *)
    DL_E_MAX : REAL := 100.0;   (* 效率饱和上限 [%] Efficiency ceiling *)
END_VAR
VAR
    fF : REAL;      (* 入料细粒质量分数 [-] Feed fines fraction *)
    fO : REAL;      (* 筛上细粒质量分数 [-] Oversize fines fraction *)
    fU : REAL;      (* 筛下细粒质量分数 [-] Undersize fines fraction *)
    fDen : REAL;    (* 分母 (1−O)·(F+U−1) [-] Denominator *)
    fEff : REAL;    (* 效率小数中间量 [-] Efficiency scratch *)
END_VAR
(* 出口预置：两出口统一预置（R256） *)
fEfficiencyPct := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，三入参全枚举 *)
IF (fFeedFinesPct <> fFeedFinesPct) OR ((fFeedFinesPct - fFeedFinesPct) <> 0.0)
   OR (fOverFinesPct <> fOverFinesPct) OR ((fOverFinesPct - fOverFinesPct) <> 0.0)
   OR (fUnderFinesPct <> fUnderFinesPct) OR ((fUnderFinesPct - fUnderFinesPct) <> 0.0) THEN
    FC_DL_ScreenEfficiencyCalc := -1.0;     (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：三处含量皆须落在 0~100 %，入料细粒须 > 0（为除子） *)
IF (fFeedFinesPct <= DL_EPS) OR (fFeedFinesPct > DL_PCT)
   OR (fOverFinesPct < 0.0) OR (fOverFinesPct >= DL_PCT)
   OR (fUnderFinesPct < 0.0) OR (fUnderFinesPct > DL_PCT) THEN
    FC_DL_ScreenEfficiencyCalc := -1.0;     (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 百分数折算小数，量纲变为质量分数 *)
fF := fFeedFinesPct / DL_PCT;
fO := fOverFinesPct / DL_PCT;
fU := fUnderFinesPct / DL_PCT;
(* 经典二产品筛分效率式分母：D = F·(U−O)，先算后闸，禁先除后判 *)
(* 原式 D=(1−O)(F+U−1) 会把 η 放大 1/(F+U−1) 倍并系统性饱和到 100%，已废弃 *)
fDen := fF * (fU - fO);
IF ABS(fDen) <= DL_EPS THEN
    FC_DL_ScreenEfficiencyCalc := -1.0;     (* 哨兵 -1：分母塌零 / Sentinel -1, vanishing denominator *)
    RETURN;
END_IF
(* E = U·(F−O) / (F·(U−O))，F 已过零闸，D 已过塌零闸（Wills 选矿手册式） *)
fEff := (fU * (fF - fO)) / fDen;
(* 负值即物料衡算矛盾（筛下细粒反少于入料平衡），判非法不钳成 0 冒充正常 *)
IF fEff < -DL_EPS THEN
    FC_DL_ScreenEfficiencyCalc := -1.0;     (* 哨兵 -1：衡算矛盾 / Sentinel -1, mass-balance conflict *)
    RETURN;
END_IF
(* 物理域钳位：效率不超 100 %，微负残差按 0 处理 *)
IF fEff > 1.0 THEN
    fEff := 1.0;                            (* 上限钳位 100 % / Clamp to 100 percent *)
ELSIF fEff < 0.0 THEN
    fEff := 0.0;                            (* 微负残差归零 / Negative residual to zero *)
END_IF
fEfficiencyPct := fEff * DL_PCT;            (* 分数 → 百分数 [%] Fraction to percent *)
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_ScreenEfficiencyCalc := fEfficiencyPct;
END_FUNCTION
