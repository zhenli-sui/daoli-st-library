(*
  Name: FC_DL_StripCrownCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：板凸度与平直度指数：由中部/边部厚度差算凸度（μm）、凸度率与 I-unit 平直度。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 边部厚度为凸度率除子，须 ≥ 0.05 mm；凸度差取中部减边部，允许负值（负凸度照实输出）；
            ③ 平直度按「凸度差 ÷ 半宽」的应变 × 1e5 折算 I-unit，半宽为除子，带宽须 ≥ 200 mm；
            ④ fRefCrownPct 仅作域闸用的目标凸度率基准（0.1~5 %），不参与输出计算。
  量纲自证：(中部−边部)[mm]×1000 = μm；Δmm/(W/2)[mm] 无量纲 ×1e5 = I-unit。
*)
FUNCTION FC_DL_StripCrownCalc : REAL
VAR_INPUT
    fCenterThkMm : REAL;    (* 中部厚度 [mm] Center thickness [mm] *)
    fEdgeThkMm : REAL;      (* 边部厚度（距边 25 mm 处） [mm] Edge thickness [mm] *)
    fWidthMm : REAL;        (* 带钢宽度 [mm] Strip width [mm] *)
    fRefCrownPct : REAL;    (* 目标凸度率（域闸基准） [%] Reference crown ratio [%] *)
END_VAR
VAR_OUTPUT
    fCrownUm : REAL;        (* 凸度（中部−边部） [μm] Crown in micrometres [um] *)
    fCrownPct : REAL;       (* 凸度率（相对边部厚度） [%] Crown ratio [%] *)
    fFlatnessIu : REAL;     (* 平直度指数 [I-unit] Flatness index [I-unit] *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_UM : REAL := 1000.0;         (* 毫米 → 微米换算 [μm/mm] Millimetre to micrometre *)
    DL_IU : REAL := 1.0E5;          (* 应变 → I-unit 换算 [-] Strain to I-unit *)
    DL_HALF : REAL := 2.0;          (* 半宽除数 [-] Half-width divisor *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
    DL_C_MIN : REAL := 0.05;        (* 厚度下限 [mm] Thickness floor [mm] *)
    DL_C_MAX : REAL := 12.0;        (* 厚度上限 [mm] Thickness ceiling [mm] *)
    DL_W_MIN : REAL := 200.0;       (* 带宽下限 [mm] Width floor [mm] *)
    DL_W_MAX : REAL := 2500.0;      (* 带宽上限 [mm] Width ceiling [mm] *)
    DL_R_MIN : REAL := 0.1;         (* 目标凸度率下限 [%] Reference ratio floor [%] *)
    DL_R_MAX : REAL := 5.0;         (* 目标凸度率上限 [%] Reference ratio ceiling [%] *)
END_VAR
VAR
    fCrownMm : REAL;    (* 凸度差（mm） [mm] Crown difference [mm] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fCrownUm := 0.0; fCrownPct := 0.0; fFlatnessIu := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fCenterThkMm <> fCenterThkMm) OR ((fCenterThkMm - fCenterThkMm) <> 0.0)
   OR (fEdgeThkMm <> fEdgeThkMm) OR ((fEdgeThkMm - fEdgeThkMm) <> 0.0)
   OR (fWidthMm <> fWidthMm) OR ((fWidthMm - fWidthMm) <> 0.0)
   OR (fRefCrownPct <> fRefCrownPct) OR ((fRefCrownPct - fRefCrownPct) <> 0.0) THEN
    FC_DL_StripCrownCalc := -1.0;           (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：两侧厚度、带宽、目标凸度率逐项定域（边厚为凸度率除子） *)
IF (fCenterThkMm < DL_C_MIN) OR (fCenterThkMm > DL_C_MAX)
   OR (fEdgeThkMm < DL_C_MIN) OR (fEdgeThkMm > DL_C_MAX)
   OR (fWidthMm < DL_W_MIN) OR (fWidthMm > DL_W_MAX)
   OR (fRefCrownPct < DL_R_MIN) OR (fRefCrownPct > DL_R_MAX) THEN
    FC_DL_StripCrownCalc := -1.0;           (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 凸度差：中部 − 边部，允许负值（负凸度照实上报，不做单向钳位） *)
fCrownMm := fCenterThkMm - fEdgeThkMm;
(* 凸度：mm × 1000 = μm *)
fCrownUm := fCrownMm * DL_UM;
(* 凸度率：÷ 边部厚度（已过下限闸），×100 得百分数 *)
fCrownPct := (fCrownMm / fEdgeThkMm) * DL_PCT;
(* 平直度：Δmm ÷ 半宽[mm] 得应变，×1e5 得 I-unit；半宽 = W/2 > 100 mm 恒正 *)
fFlatnessIu := (fCrownMm / (fWidthMm / DL_HALF)) * DL_IU;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_StripCrownCalc := fCrownUm;
END_FUNCTION
