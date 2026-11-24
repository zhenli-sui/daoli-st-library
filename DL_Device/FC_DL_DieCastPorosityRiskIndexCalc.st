(*
  Component : FC_DL_DieCastPorosityRiskIndexCalc
  Category  : DL_Device
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 压铸气孔风险指数评估：按卷气（压射速度）、模温差、排气能力三因子加权算 0~100 风险指数并给出 1~4 风险等级。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 三个基准量（参考速度、参考温差、参考排气面积）须 > 1e-9，否则返回哨兵 -1；
              ② 各单因子先归一化为 0~100 并双侧钳位，再做加权，避免单因子拉爆总分；
              ③ 排气因子取反向：排气面积越小风险越高。
*)
FUNCTION FC_DL_DieCastPorosityRiskIndexCalc : REAL
VAR_INPUT
    fShotVelMs     : REAL;   (* 空压射速度 [m/s] Dry shot velocity *)
    fVelRefMs      : REAL;   (* 卷气基准速度（工艺窗口上限） [m/s] Velocity reference *)
    fTempDiffK     : REAL;   (* 模面温差 [K] Die surface temperature difference *)
    fTempDiffRefK  : REAL;   (* 温差基准（允许上限） [K] Temperature difference reference *)
    fVentAreaMm2   : REAL;   (* 排气截面积 [mm²] Vent cross-section area *)
    fVentRefMm2    : REAL;   (* 排气基准面积（设计值） [mm²] Vent reference area *)
END_VAR
VAR_OUTPUT
    fRiskIdx    : REAL;   (* 综合气孔风险指数 0~100 [-] Composite porosity risk index *)
    fVelFactor  : REAL;   (* 卷气因子 0~100 [-] Air entrapment factor *)
    fTempFactor : REAL;   (* 温差因子 0~100 [-] Temperature factor *)
    fVentFactor : REAL;   (* 排气因子 0~100 [-] Venting factor *)
    nRiskGrade  : INT;    (* 风险等级 1~4 [-] Risk grade *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_W_VEL    : REAL := 0.40;     (* 卷气因子权重 [-] Velocity factor weight *)
    DL_W_TEMP   : REAL := 0.35;     (* 温差因子权重 [-] Temperature factor weight *)
    DL_W_VENT   : REAL := 0.25;     (* 排气因子权重 [-] Venting factor weight *)
    DL_ONE      : REAL := 1.0;      (* 单位常数 [-] Unity constant *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
VAR
    fRawV : REAL;   (* 卷气因子原始值 [-] Raw velocity factor *)
    fRawT : REAL;   (* 温差因子原始值 [-] Raw temperature factor *)
    fRawE : REAL;   (* 排气因子原始值 [-] Raw venting factor *)
END_VAR
(* 出口预置：六出口统一预置 *)
fRiskIdx := 0.0; fVelFactor := 0.0; fTempFactor := 0.0; fVentFactor := 0.0;
nRiskGrade := 1; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fShotVelMs <> fShotVelMs) OR ((fShotVelMs - fShotVelMs) <> 0.0)
   OR (fTempDiffK <> fTempDiffK) OR ((fTempDiffK - fTempDiffK) <> 0.0)
   OR (fVentAreaMm2 <> fVentAreaMm2) OR ((fVentAreaMm2 - fVentAreaMm2) <> 0.0)
   OR (fVelRefMs <> fVelRefMs) OR ((fVelRefMs - fVelRefMs) <> 0.0)
   OR (fTempDiffRefK <> fTempDiffRefK) OR ((fTempDiffRefK - fTempDiffRefK) <> 0.0)
   OR (fVentRefMm2 <> fVentRefMm2) OR ((fVentRefMm2 - fVentRefMm2) <> 0.0) THEN
    FC_DL_DieCastPorosityRiskIndexCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：三个基准量全部为除子 *)
IF (fVelRefMs <= DL_EPS) OR (fTempDiffRefK <= DL_EPS) OR (fVentRefMm2 <= DL_EPS)
   OR (fShotVelMs < DL_ZERO) THEN
    FC_DL_DieCastPorosityRiskIndexCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 卷气因子：速度越高卷气越重，归一化后双侧钳位 0~100 *)
fRawV := fShotVelMs / fVelRefMs * DL_PCT_BASE;
IF fRawV > DL_PCT_BASE THEN
    fVelFactor := DL_PCT_BASE;
ELSIF fRawV < DL_ZERO THEN
    fVelFactor := DL_ZERO;
ELSE
    fVelFactor := fRawV;
END_IF
(* 温差因子：温差越大热节越重，归一化后双侧钳位 0~100 *)
fRawT := fTempDiffK / fTempDiffRefK * DL_PCT_BASE;
IF fRawT > DL_PCT_BASE THEN
    fTempFactor := DL_PCT_BASE;
ELSIF fRawT < DL_ZERO THEN
    fTempFactor := DL_ZERO;
ELSE
    fTempFactor := fRawT;
END_IF
(* 排气因子：排气面积越小风险越高，取 1 - 面积比 并双侧钳位 *)
fRawE := (DL_ONE - fVentAreaMm2 / fVentRefMm2) * DL_PCT_BASE;
IF fRawE > DL_PCT_BASE THEN
    fVentFactor := DL_PCT_BASE;
ELSIF fRawE < DL_ZERO THEN
    fVentFactor := DL_ZERO;
ELSE
    fVentFactor := fRawE;
END_IF
(* 加权合成：三因子权重之和为 1，结果为 0~100 *)
fRiskIdx := fVelFactor * DL_W_VEL + fTempFactor * DL_W_TEMP + fVentFactor * DL_W_VENT;
(* 风险分级：<25 优 / <50 良 / <75 中 / 其余 差 *)
IF fRiskIdx < 25.0 THEN
    nRiskGrade := 1;
ELSIF fRiskIdx < 50.0 THEN
    nRiskGrade := 2;
ELSIF fRiskIdx < 75.0 THEN
    nRiskGrade := 3;
ELSE
    nRiskGrade := 4;
END_IF
xValid := TRUE;                                  (* 链路有效 / Chain valid *)
FC_DL_DieCastPorosityRiskIndexCalc := fRiskIdx;  (* 返回风险指数 [-] / Return risk index *)
END_FUNCTION
