(*
  Name: FC_DL_BilletTempUniformCalc
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：坯料截面温度均匀性：表心温差、厚度方向温度梯度与均匀性判定。
  边界条件：① 五入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 厚度 ≤ 0 时半厚为除子会塌零，故厚度按 10~1200 mm 域闸拦截；容差 1~100 ℃；
            ③ 温差取绝对值（表心温差为对称量），梯度 = 温差 ÷ 半厚，量纲 ℃/mm。
  量纲自证：|ΔT|[℃] ÷ (thk/2)[mm] = ℃/mm；容差比较两侧同量纲。
*)
FUNCTION FC_DL_BilletTempUniformCalc : REAL
VAR_INPUT
    fSurfaceC : REAL;       (* 表面温度 [℃] Surface temperature [degC] *)
    fCenterC : REAL;        (* 心部温度 [℃] Core temperature [degC] *)
    fTolC : REAL;           (* 均匀性容差（表心温差上限） [℃] Uniformity tolerance [degC] *)
    fThkMm : REAL;          (* 坯料厚度 [mm] Billet thickness [mm] *)
END_VAR
VAR_OUTPUT
    fDeltaC : REAL;         (* 表心温差（绝对值） [℃] Surface-to-core delta [degC] *)
    fGradCperMm : REAL;     (* 厚度方向温度梯度 [℃/mm] Through-thickness gradient [degC/mm] *)
    xUniformOk : BOOL;      (* 温差在容差内 [-] Delta within tolerance *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_HALF : REAL := 2.0;          (* 半厚除数 [-] Half-thickness divisor *)
    DL_T_MIN : REAL := -50.0;       (* 温度下限 [℃] Temperature floor [degC] *)
    DL_T_MAX : REAL := 1400.0;      (* 温度上限 [℃] Temperature ceiling [degC] *)
    DL_TOL_MIN : REAL := 1.0;       (* 容差下限 [℃] Tolerance floor [degC] *)
    DL_TOL_MAX : REAL := 100.0;     (* 容差上限 [℃] Tolerance ceiling [degC] *)
    DL_THK_MIN : REAL := 10.0;      (* 厚度下限 [mm] Thickness floor [mm] *)
    DL_THK_MAX : REAL := 1200.0;    (* 厚度上限 [mm] Thickness ceiling [mm] *)
END_VAR
VAR
    fHalfMm : REAL;     (* 半厚（心部到表面距离） [mm] Half thickness [mm] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fDeltaC := 0.0; fGradCperMm := 0.0; xUniformOk := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fSurfaceC <> fSurfaceC) OR ((fSurfaceC - fSurfaceC) <> 0.0)
   OR (fCenterC <> fCenterC) OR ((fCenterC - fCenterC) <> 0.0)
   OR (fTolC <> fTolC) OR ((fTolC - fTolC) <> 0.0)
   OR (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0) THEN
    FC_DL_BilletTempUniformCalc := -1.0;    (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：两温度、容差、厚度逐项定域（厚度为半厚基准） *)
IF (fSurfaceC < DL_T_MIN) OR (fSurfaceC > DL_T_MAX)
   OR (fCenterC < DL_T_MIN) OR (fCenterC > DL_T_MAX)
   OR (fTolC < DL_TOL_MIN) OR (fTolC > DL_TOL_MAX)
   OR (fThkMm < DL_THK_MIN) OR (fThkMm > DL_THK_MAX) THEN
    FC_DL_BilletTempUniformCalc := -1.0;    (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 表心温差：取绝对值（正负偏差同属温差量，不合并判方向） *)
fDeltaC := ABS(fSurfaceC - fCenterC);
(* 梯度：温差 ÷ 半厚，半厚已过厚度域闸恒 ≥ 5 mm *)
fHalfMm := fThkMm / DL_HALF;
IF fHalfMm <= DL_EPS THEN
    FC_DL_BilletTempUniformCalc := -1.0;    (* 哨兵 -1：半厚塌零 / Sentinel -1, vanishing half thickness *)
    RETURN;
END_IF
fGradCperMm := fDeltaC / fHalfMm;
(* 均匀性判定：温差不超过容差即合格（两侧同量纲，禁浮点判等） *)
xUniformOk := fDeltaC <= fTolC;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_BilletTempUniformCalc := fDeltaC;
END_FUNCTION
