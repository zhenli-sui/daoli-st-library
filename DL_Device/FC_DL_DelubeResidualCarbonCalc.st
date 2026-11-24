(*
  Component : FC_DL_DelubeResidualCarbonCalc
  Category  : DL_Device
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 润滑剂烧除残碳估算：按烧除区露点、温度与停留时间三个修正因子折算残碳百分比，并与限值比较给出合格判定。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 三个基准量（露点、温度、停留时间）须 > 1e-9，否则返回哨兵 -1；
              ② 各修正因子双侧钳位 0.5~2.0，防单因子离群拉爆残碳估算；
              ③ 露点越高、温度越低、停留越短则残碳越高（三者方向各不相同，逐项显式建模）。
*)
FUNCTION FC_DL_DelubeResidualCarbonCalc : REAL
VAR_INPUT
    fLubePct     : REAL;   (* 润滑剂添加量 [%] Lubricant content *)
    fDewPointC   : REAL;   (* 烧除区露点 [°C] Delube zone dew point *)
    fZoneTempC   : REAL;   (* 烧除区温度 [°C] Delube zone temperature *)
    fResidTimeMin: REAL;   (* 烧除区停留时间 [min] Delube zone residence time *)
    fDewRefC     : REAL;   (* 露点基准 [°C] Dew point reference *)
    fTempRefC    : REAL;   (* 温度基准 [°C] Temperature reference *)
    fTimeRefMin  : REAL;   (* 停留时间基准 [min] Residence time reference *)
    fLimitPct    : REAL;   (* 残碳合格限 [%] Residual carbon limit *)
END_VAR
VAR_OUTPUT
    fResidualPct : REAL;  (* 残碳估算值 [%] Estimated residual carbon *)
    fKCoef       : REAL;  (* 综合修正系数 [-] Composite correction coefficient *)
    xQualified   : BOOL;  (* 残碳合格标志 [-] Residual carbon qualified flag *)
    xValid       : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_K_MIN    : REAL := 0.5;      (* 修正因子下限 [-] Correction factor lower clamp *)
    DL_K_MAX    : REAL := 2.0;      (* 修正因子上限 [-] Correction factor upper clamp *)
    DL_DEW_K    : REAL := 0.02;     (* 露点修正斜率 [1/°C] Dew point slope *)
    DL_TMP_K    : REAL := 0.002;    (* 温度修正斜率 [1/°C] Temperature slope *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fKDew  : REAL;   (* 露点修正因子 [-] Dew point factor *)
    fKTmp  : REAL;   (* 温度修正因子 [-] Temperature factor *)
    fKTime : REAL;   (* 停留时间修正因子 [-] Residence time factor *)
END_VAR
(* 出口预置：四出口统一预置 *)
fResidualPct := 0.0; fKCoef := 1.0; xQualified := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fLubePct <> fLubePct) OR ((fLubePct - fLubePct) <> 0.0)
   OR (fDewPointC <> fDewPointC) OR ((fDewPointC - fDewPointC) <> 0.0)
   OR (fZoneTempC <> fZoneTempC) OR ((fZoneTempC - fZoneTempC) <> 0.0)
   OR (fResidTimeMin <> fResidTimeMin) OR ((fResidTimeMin - fResidTimeMin) <> 0.0)
   OR (fDewRefC <> fDewRefC) OR ((fDewRefC - fDewRefC) <> 0.0)
   OR (fTempRefC <> fTempRefC) OR ((fTempRefC - fTempRefC) <> 0.0)
   OR (fTimeRefMin <> fTimeRefMin) OR ((fTimeRefMin - fTimeRefMin) <> 0.0)
   OR (fLimitPct <> fLimitPct) OR ((fLimitPct - fLimitPct) <> 0.0) THEN
    FC_DL_DelubeResidualCarbonCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：停留时间为除子，三个基准量为比例基，限值须为正 *)
IF (fResidTimeMin <= DL_EPS) OR (fTimeRefMin <= DL_EPS) OR (fLimitPct <= DL_ZERO)
   OR (fLubePct < DL_ZERO) THEN
    FC_DL_DelubeResidualCarbonCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 露点修正：露点越高越缺氧，烧除越不完全，残碳升高 *)
fKDew := 1.0 + (fDewPointC - fDewRefC) * DL_DEW_K;
IF fKDew < DL_K_MIN THEN
    fKDew := DL_K_MIN;
ELSIF fKDew > DL_K_MAX THEN
    fKDew := DL_K_MAX;
END_IF
(* 温度修正：温度越低烧除越不完全，残碳升高 *)
fKTmp := 1.0 + (fTempRefC - fZoneTempC) * DL_TMP_K;
IF fKTmp < DL_K_MIN THEN
    fKTmp := DL_K_MIN;
ELSIF fKTmp > DL_K_MAX THEN
    fKTmp := DL_K_MAX;
END_IF
(* 停留时间修正：停留越短烧除越不完全，残碳升高 *)
fKTime := fTimeRefMin / fResidTimeMin;
IF fKTime < DL_K_MIN THEN
    fKTime := DL_K_MIN;
ELSIF fKTime > DL_K_MAX THEN
    fKTime := DL_K_MAX;
END_IF
(* 综合修正系数与残碳估算：分母均已过域闸 *)
fKCoef := fKDew * fKTmp * fKTime;
fResidualPct := fLubePct * fKCoef;
(* 合格判定：残碳不超过限值 *)
xQualified := fResidualPct <= fLimitPct;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_DelubeResidualCarbonCalc := fResidualPct;  (* 返回残碳 [%] / Return residual carbon *)
END_FUNCTION
