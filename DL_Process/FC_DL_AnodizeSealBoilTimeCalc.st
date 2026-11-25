(*
  Component : FC_DL_AnodizeSealBoilTimeCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : 沸水封孔时间核算：按膜厚乘单位膜厚基准时间，再叠加温度窗口修正，判定 pH/温度窗口与最终封孔合格性。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 膜厚与单位膜厚时间须 > 1e-9，否则返回哨兵 -1；
              ② pH 窗口 5.5~6.5、温度窗口 95~100 °C，任一越窗即判不合格但不拒算；
              ③ 温度修正系数钳位 1.0~2.0，温度偏低延长封孔时间。
*)
FUNCTION FC_DL_AnodizeSealBoilTimeCalc : REAL
VAR_INPUT
    fFilmUm    : REAL;   (* 氧化膜厚 [μm] Oxide film thickness *)
    fBathTempC : REAL;   (* 封孔槽液温度 [°C] Sealing bath temperature *)
    fPh        : REAL;   (* 封孔槽液 pH [-] Sealing bath pH *)
    fMinPerUm  : REAL;   (* 单位膜厚基准封孔时间 [min/μm] Base sealing time per um *)
    fFilmMinUm : REAL;   (* 可封孔最小膜厚 [μm] Minimum sealable film thickness *)
END_VAR
VAR_OUTPUT
    fSealTimeMin : REAL;  (* 封孔时间 [min] Sealing time *)
    fTempCoef    : REAL;  (* 温度修正系数 [-] Temperature correction coefficient *)
    xWindowOk    : BOOL;  (* pH 与温度窗口合格标志 [-] Window valid flag *)
    xQualified   : BOOL;  (* 封孔合格标志 [-] Sealing qualified flag *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PH_LO    : REAL := 5.5;      (* pH 窗口下限 [-] pH window lower bound *)
    DL_PH_HI    : REAL := 6.5;      (* pH 窗口上限 [-] pH window upper bound *)
    DL_TMP_LO   : REAL := 95.0;     (* 温度窗口下限 [°C] Temperature window lower bound *)
    DL_TMP_HI   : REAL := 100.0;    (* 温度窗口上限 [°C] Temperature window upper bound *)
    DL_TMP_REF  : REAL := 100.0;    (* 温度修正基准 [°C] Temperature reference *)
    DL_TMP_SLOPE: REAL := 0.25;     (* 每 10 °C 温度修正量 [-] Slope per 10 degC *)
    DL_COEF_MAX : REAL := 2.0;      (* 温度修正上限 [-] Temperature coefficient clamp *)
END_VAR
VAR
    fGapC : REAL;   (* 相对基准温度的温差 [°C] Temperature gap from reference *)
END_VAR
(* 出口预置：五出口统一预置 *)
fSealTimeMin := 0.0; fTempCoef := 1.0; xWindowOk := FALSE; xQualified := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fFilmUm <> fFilmUm) OR ((fFilmUm - fFilmUm) <> 0.0)
   OR (fBathTempC <> fBathTempC) OR ((fBathTempC - fBathTempC) <> 0.0)
   OR (fPh <> fPh) OR ((fPh - fPh) <> 0.0) THEN
    FC_DL_AnodizeSealBoilTimeCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：膜厚与单位膜厚时间均为比例基 *)
IF (fFilmUm < DL_EPS) OR (fMinPerUm <= DL_EPS) THEN
    FC_DL_AnodizeSealBoilTimeCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 窗口判定：pH 与温度双窗口，任一越窗即判不合格（不拒算，便于上位诊断） *)
IF (fPh >= DL_PH_LO) AND (fPh <= DL_PH_HI)
   AND (fBathTempC >= DL_TMP_LO) AND (fBathTempC <= DL_TMP_HI) THEN
    xWindowOk := TRUE;
END_IF
(* 温度修正：低于基准温度每 10 °C 延长 25 %，双侧钳位 *)
fGapC := DL_TMP_REF - fBathTempC;
IF fGapC > 0.0 THEN
    fTempCoef := 1.0 + (fGapC / 10.0) * DL_TMP_SLOPE;
ELSE
    fTempCoef := 1.0;                       (* 达到或高于基准：不缩短，防欠封 *)
END_IF
IF fTempCoef > DL_COEF_MAX THEN
    fTempCoef := DL_COEF_MAX;               (* 上限钳位 [-] / Upper clamp *)
END_IF
(* 封孔时间：t = 膜厚 × 单位膜厚时间 × 温度修正，分母均已过域闸 *)
fSealTimeMin := fFilmUm * fMinPerUm * fTempCoef;
(* 合格判定：窗口合格且膜厚达可封孔最小值 *)
xQualified := xWindowOk AND (fFilmUm >= fFilmMinUm);
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_AnodizeSealBoilTimeCalc := fSealTimeMin;  (* 返回封孔时间 [min] / Return sealing minutes *)
END_FUNCTION
