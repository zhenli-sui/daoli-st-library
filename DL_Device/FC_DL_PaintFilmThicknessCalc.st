(*
  Name: FC_DL_PaintFilmThicknessCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：漆膜厚度估算：湿漆流量 × 密度 × 固含量 ÷ 干膜密度 ÷ 单位时间喷涂面积 = 干膜厚度。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 喷涂面积为除子，按 0.01~100 m2/min 域闸拦截，绝无零除；
            ③ 干膜密度取常量 DL_PFT_RHO_FILM = 1.2 g/cm3（通用涂料干膜密度），属工艺常量非实测；
            ④ 固含量按下限 5 % 域闸拦截，避免固含趋零导致膜厚趋零的伪结论。
  量纲自证：ml/min × g/ml = g/min；× 固含 = 固体 g/min；÷ g/cm3 = cm3/min；÷ m2/min = cm3/m2，
            而 1 cm3 均布于 1 m2 即 1 μm，故数值直接为 μm。
*)
FUNCTION FC_DL_PaintFilmThicknessCalc : REAL
VAR_INPUT
    fFlowMlmin : REAL;          (* 湿漆流量 [ml/min] Wet paint flow [ml/min] *)
    fSolidPct : REAL;           (* 固含量（质量） [%] Solids content by mass [%] *)
    fAreaM2min : REAL;          (* 单位时间喷涂面积 [m2/min] Coated area per minute [m2/min] *)
    fDensityGml : REAL;         (* 湿漆密度 [g/ml] Wet paint density [g/ml] *)
END_VAR
VAR_OUTPUT
    fFilmUm : REAL;             (* 干膜厚度 [μm] Dry film thickness [um] *)
    xValid : BOOL;              (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_PFT_RHO_FILM : REAL := 1.2;  (* 干膜密度（工艺常量） [g/cm3] Dry film density [g/cm3] *)
    DL_PCT : REAL := 100.0;         (* 百分数基准 [%] Percent base *)
    DL_F_MIN : REAL := 1.0;         (* 流量下限 [ml/min] Flow floor [ml/min] *)
    DL_F_MAX : REAL := 2000.0;      (* 流量上限 [ml/min] Flow ceiling [ml/min] *)
    DL_S_MIN : REAL := 5.0;         (* 固含量下限 [%] Solids floor [%] *)
    DL_S_MAX : REAL := 100.0;       (* 固含量上限 [%] Solids ceiling [%] *)
    DL_A_MIN : REAL := 0.01;        (* 面积下限 [m2/min] Area floor [m2/min] *)
    DL_A_MAX : REAL := 100.0;       (* 面积上限 [m2/min] Area ceiling [m2/min] *)
    DL_D_MIN : REAL := 0.7;         (* 湿漆密度下限 [g/ml] Density floor [g/ml] *)
    DL_D_MAX : REAL := 2.0;         (* 湿漆密度上限 [g/ml] Density ceiling [g/ml] *)
END_VAR
VAR
    fSolidGmin : REAL;  (* 固体质量流量 [g/min] Solids mass flow [g/min] *)
    fVolCm3min : REAL;  (* 固体体积流量 [cm3/min] Solids volume flow [cm3/min] *)
END_VAR
(* 出口预置：两出口统一预置（R256） *)
fFilmUm := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fFlowMlmin <> fFlowMlmin) OR ((fFlowMlmin - fFlowMlmin) <> 0.0)
   OR (fSolidPct <> fSolidPct) OR ((fSolidPct - fSolidPct) <> 0.0)
   OR (fAreaM2min <> fAreaM2min) OR ((fAreaM2min - fAreaM2min) <> 0.0)
   OR (fDensityGml <> fDensityGml) OR ((fDensityGml - fDensityGml) <> 0.0) THEN
    FC_DL_PaintFilmThicknessCalc := -1.0;   (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：流量、固含量、面积为除子、密度逐项定域 *)
IF (fFlowMlmin < DL_F_MIN) OR (fFlowMlmin > DL_F_MAX)
   OR (fSolidPct < DL_S_MIN) OR (fSolidPct > DL_S_MAX)
   OR (fAreaM2min < DL_A_MIN) OR (fAreaM2min > DL_A_MAX)
   OR (fDensityGml < DL_D_MIN) OR (fDensityGml > DL_D_MAX) THEN
    FC_DL_PaintFilmThicknessCalc := -1.0;   (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 固体质量流量：ml/min × g/ml = g/min，再乘固含比例 *)
fSolidGmin := fFlowMlmin * fDensityGml * (fSolidPct / DL_PCT);
(* 固体体积流量：g/min ÷ g/cm3 = cm3/min，干膜密度为常量恒正 *)
fVolCm3min := fSolidGmin / DL_PFT_RHO_FILM;
(* 膜厚：cm3/min ÷ m2/min = cm3/m2 ≡ μm，面积已过下限闸 *)
fFilmUm := fVolCm3min / fAreaM2min;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_PaintFilmThicknessCalc := fFilmUm;
END_FUNCTION
