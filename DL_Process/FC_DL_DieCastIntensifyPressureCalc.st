(*
  Component : FC_DL_DieCastIntensifyPressureCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 增压比压与锁模力校验：按铸件投影面积与增压比压算所需锁模力，并与设备额定锁模力比较输出余量比。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 投影面积、增压比压、安全系数须 > 1e-9，否则返回哨兵 -1；
              ② 所需锁模力 = 投影面积(cm²) × 比压(MPa) / 10 × 安全系数，量纲为 kN；
              ③ 余量比 = 额定/所需，额定为 0 时不计算而回哨兵。
*)
FUNCTION FC_DL_DieCastIntensifyPressureCalc : REAL
VAR_INPUT
    fProjAreaCm2    : REAL;   (* 铸件投影面积（含浇排系统） [cm²] Projected area *)
    fCastPressMPa   : REAL;   (* 压射比压 [MPa] Casting specific pressure *)
    fIntensifyRatio : REAL;   (* 增压比（增压后/压射） [-] Intensification ratio *)
    fRatedClampKN   : REAL;   (* 设备额定锁模力 [kN] Rated clamping force *)
    fSafetyFactor   : REAL;   (* 锁模安全系数 [-] Clamping safety factor *)
END_VAR
VAR_OUTPUT
    fIntPressMPa  : REAL;  (* 增压后比压 [MPa] Intensified specific pressure *)
    fClampNeedKN  : REAL;  (* 所需锁模力 [kN] Required clamping force *)
    fMarginRatio  : REAL;  (* 锁模力余量比（额定/所需） [-] Clamping margin ratio *)
    xClampOk      : BOOL;  (* 锁模力充足标志 [-] Clamping sufficient flag *)
    xValid        : BOOL;  (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_KPA_UNIT : REAL := 10.0;     (* cm²×MPa 换算 kN 的除数 [cm²·MPa/kN] Unit divisor *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：五出口统一预置 *)
fIntPressMPa := 0.0; fClampNeedKN := 0.0; fMarginRatio := 0.0; xClampOk := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fProjAreaCm2 <> fProjAreaCm2) OR ((fProjAreaCm2 - fProjAreaCm2) <> 0.0)
   OR (fCastPressMPa <> fCastPressMPa) OR ((fCastPressMPa - fCastPressMPa) <> 0.0)
   OR (fIntensifyRatio <> fIntensifyRatio) OR ((fIntensifyRatio - fIntensifyRatio) <> 0.0)
   OR (fRatedClampKN <> fRatedClampKN) OR ((fRatedClampKN - fRatedClampKN) <> 0.0)
   OR (fSafetyFactor <> fSafetyFactor) OR ((fSafetyFactor - fSafetyFactor) <> 0.0) THEN
    FC_DL_DieCastIntensifyPressureCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：面积、比压、增压比、安全系数、额定锁模力逐个覆盖 *)
IF (fProjAreaCm2 <= DL_EPS) OR (fCastPressMPa <= DL_ZERO) OR (fIntensifyRatio <= DL_EPS)
   OR (fSafetyFactor <= DL_EPS) OR (fRatedClampKN <= DL_ZERO) THEN
    FC_DL_DieCastIntensifyPressureCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 增压后比压：p2 = p × 增压比 [MPa] *)
fIntPressMPa := fCastPressMPa * fIntensifyRatio;
(* 所需锁模力：A(cm²)=100 mm²，p(MPa)=N/mm²，F=100·A·p N = A·p/10 kN *)
fClampNeedKN := fProjAreaCm2 * fIntPressMPa / DL_KPA_UNIT * fSafetyFactor;
(* 余量比：额定 / 所需，所需已过域闸（面积与比压均正） *)
fMarginRatio := fRatedClampKN / fClampNeedKN;
xClampOk := fMarginRatio >= 1.0;                (* 余量比 >= 1 判充足 / Sufficient margin *)
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_DieCastIntensifyPressureCalc := fClampNeedKN;  (* 返回所需锁模力 [kN] / Return clamp force *)
END_FUNCTION
