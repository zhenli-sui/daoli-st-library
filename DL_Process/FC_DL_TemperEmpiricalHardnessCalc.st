(*
  Component : FC_DL_TemperEmpiricalHardnessCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 回火温度-硬度经验曲线核算：按四点节点表分段线性插值得到基准 HRC，再按含碳量修正，超界双向钳位。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 节点表必须严格升序且首末温差 > 1e-9，否则返回哨兵 -1；
              ② 回火温度超出节点区间时取端点值并置 xClamped，禁外推；
              ③ 含碳量修正量双侧钳位 ±8 HRC，防小样本经验式发散。
*)
FUNCTION FC_DL_TemperEmpiricalHardnessCalc : REAL
VAR_INPUT
    fTemperC    : REAL;               (* 回火温度 [°C] Tempering temperature *)
    afTempKnot  : ARRAY[0..3] OF REAL;(* 节点温度表（升序） [°C] Knot temperatures ascending *)
    afHrcKnot   : ARRAY[0..3] OF REAL;(* 节点硬度表 [HRC] Knot hardness values *)
    fCarbonPct  : REAL;               (* 钢材含碳量 [%] Carbon content *)
END_VAR
VAR_OUTPUT
    fHrc      : REAL;   (* 插值得到的回火硬度 [HRC] Interpolated hardness *)
    fHrcCorr  : REAL;   (* 含碳量修正后的硬度 [HRC] Carbon-corrected hardness *)
    xClamped  : BOOL;   (* 超界钳位标志 [-] Out-of-range clamp flag *)
    xValid    : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_CORR_K    : REAL := 30.0;     (* 含碳量修正斜率 [HRC/%C] Carbon correction slope *)
    DL_CORR_BASE : REAL := 0.40;     (* 含碳量修正基准 [%C] Carbon correction base *)
    DL_CORR_LIM  : REAL := 8.0;      (* 含碳量修正钳位 [HRC] Carbon correction clamp *)
END_VAR
VAR
    nIdx  : INT;    (* 插值段循环下标 [-] Interpolation segment index *)
    nBad  : INT;    (* 节点表非有限计数，0 = 全部有限 [-] Non-finite knot counter *)
    fDen  : REAL;   (* 当前段温度跨度 [°C] Segment temperature span *)
    fCorr : REAL;   (* 含碳量修正量 [HRC] Carbon correction amount *)
END_VAR
(* 出口预置：四出口统一预置 *)
fHrc := 0.0; fHrcCorr := 0.0; xClamped := FALSE; xValid := FALSE; nBad := 0;
(* 非有限拦截：标量输入自反判 NaN，自身差值判 Inf *)
IF (fTemperC <> fTemperC) OR ((fTemperC - fTemperC) <> 0.0)
   OR (fCarbonPct <> fCarbonPct) OR ((fCarbonPct - fCarbonPct) <> 0.0) THEN
    FC_DL_TemperEmpiricalHardnessCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 节点表非有限拦截：四个温度节点与四个硬度节点逐个判（越界读前先判界） *)
FOR nIdx := 0 TO 3 DO
    IF (nIdx >= 0) AND (nIdx <= 3) THEN
        IF (afTempKnot[nIdx] <> afTempKnot[nIdx])
           OR ((afTempKnot[nIdx] - afTempKnot[nIdx]) <> 0.0)
           OR (afHrcKnot[nIdx] <> afHrcKnot[nIdx])
           OR ((afHrcKnot[nIdx] - afHrcKnot[nIdx]) <> 0.0) THEN
            nBad := nBad + 1;
        END_IF
    END_IF
END_FOR
IF nBad > 0 THEN
    FC_DL_TemperEmpiricalHardnessCalc := -1.0;  (* 哨兵 -1：节点表非有限 / Sentinel -1 bad knots *)
    RETURN;
END_IF
(* 节点表域闸：首末温差必须为正，保证区间可插值与升序约定 *)
IF (afTempKnot[3] - afTempKnot[0]) <= DL_EPS THEN
    FC_DL_TemperEmpiricalHardnessCalc := -1.0;  (* 哨兵 -1：节点表非法 / Sentinel -1 bad knot table *)
    RETURN;
END_IF
(* 超界钳位：低于首节点取首值，高于末节点取末值，禁外推 *)
IF fTemperC <= afTempKnot[0] THEN
    fHrc := afHrcKnot[0];                       (* 端点取值 [HRC] / Lower endpoint *)
    xClamped := TRUE;                           (* 低位钳位标志 [-] / Low clamp *)
ELSIF fTemperC >= afTempKnot[3] THEN
    fHrc := afHrcKnot[3];                       (* 端点取值 [HRC] / Upper endpoint *)
    xClamped := TRUE;                           (* 高位钳位标志 [-] / High clamp *)
ELSE
    (* 分段线性插值：升序镜像遍历（禁倒序循环关键字），下标上限 2 保证 i+1 <= 3 不越界 *)
    FOR nIdx := 0 TO 2 DO
        IF (fTemperC >= afTempKnot[nIdx]) AND (fTemperC <= afTempKnot[nIdx + 1]) THEN
            fDen := afTempKnot[nIdx + 1] - afTempKnot[nIdx];   (* 段跨度 [°C] / Segment span *)
            IF ABS(fDen) > DL_EPS THEN
                fHrc := afHrcKnot[nIdx]
                        + (afHrcKnot[nIdx + 1] - afHrcKnot[nIdx])
                          * (fTemperC - afTempKnot[nIdx]) / fDen;
            END_IF
        END_IF
    END_FOR
END_IF
(* 含碳量修正：以 0.40 %C 为基准，每 0.1 %C 约 3 HRC，双侧钳位 *)
fCorr := (fCarbonPct - DL_CORR_BASE) * DL_CORR_K;
IF fCorr > DL_CORR_LIM THEN
    fCorr := DL_CORR_LIM;                       (* 上限钳位 [HRC] / Upper clamp *)
ELSIF fCorr < -DL_CORR_LIM THEN
    fCorr := -DL_CORR_LIM;                      (* 下限钳位 [HRC] / Lower clamp *)
END_IF
fHrcCorr := fHrc + fCorr;                       (* 修正后硬度 [HRC] / Corrected hardness *)
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_TemperEmpiricalHardnessCalc := fHrcCorr;  (* 返回修正硬度 [HRC] / Return hardness *)
END_FUNCTION
