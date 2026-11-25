(*
  Component : FC_DL_CastingSolidificationTimeCalc
  Category  : DL_Process
  Type      : FC
  Complexity: C1
  VERSION   : v1.0.0
  功能      : Chvorinov 凝固时间核算：t = B·(V/A)² 算铸件凝固时间，并由铸件模数与冷铁判据判断是否需要加冷铁。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 铸件体积与散热表面积须 > 1e-9，否则返回哨兵 -1（体积按 cm³、面积按 cm² 输入）；
              ② 冷铁判据以模数为唯一依据：模数大于临界模数即建议加冷铁；
              ③ 凝固时间常数 B 须为正，负值判组态非法。
*)
FUNCTION FC_DL_CastingSolidificationTimeCalc : REAL
VAR_INPUT
    fVolCm3        : REAL;   (* 铸件体积 [cm³] Casting volume *)
    fSurfAreaCm2   : REAL;   (* 有效散热表面积 [cm²] Effective cooling surface *)
    fChvorinovBS   : REAL;   (* Chvorinov 时间常数 [s/cm²] Chvorinov constant *)
    fModulusCritCm : REAL;   (* 冷铁判据临界模数 [cm] Critical modulus for chill *)
END_VAR
VAR_OUTPUT
    fModulusCm  : REAL;   (* 铸件模数 V/A [cm] Casting modulus *)
    fSolidTimeS : REAL;   (* 凝固时间 [s] Solidification time *)
    xNeedChill  : BOOL;   (* 建议加冷铁标志 [-] Chill recommended flag *)
    xValid      : BOOL;   (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS  : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_ZERO : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR
(* 出口预置：四出口统一预置 *)
fModulusCm := 0.0; fSolidTimeS := 0.0; xNeedChill := FALSE; xValid := FALSE;
(* 非有限拦截：自反判 NaN，自身差值判 Inf *)
IF (fVolCm3 <> fVolCm3) OR ((fVolCm3 - fVolCm3) <> 0.0)
   OR (fSurfAreaCm2 <> fSurfAreaCm2) OR ((fSurfAreaCm2 - fSurfAreaCm2) <> 0.0)
   OR (fChvorinovBS <> fChvorinovBS) OR ((fChvorinovBS - fChvorinovBS) <> 0.0)
   OR (fModulusCritCm <> fModulusCritCm) OR ((fModulusCritCm - fModulusCritCm) <> 0.0) THEN
    FC_DL_CastingSolidificationTimeCalc := -1.0;  (* 哨兵 -1：输入非有限 / Sentinel -1 non-finite *)
    RETURN;
END_IF
(* 组态域闸：体积、面积均为除子或比例基，时间常数须为正 *)
IF (fVolCm3 <= DL_EPS) OR (fSurfAreaCm2 <= DL_EPS) OR (fChvorinovBS <= DL_ZERO)
   OR (fModulusCritCm <= DL_ZERO) THEN
    FC_DL_CastingSolidificationTimeCalc := -1.0;  (* 哨兵 -1：组态非法 / Sentinel -1 bad config *)
    RETURN;
END_IF
(* 铸件模数：M = V/A [cm]，分母已过域闸 *)
fModulusCm := fVolCm3 / fSurfAreaCm2;
(* Chvorinov：t = B·M² [s] *)
fSolidTimeS := fChvorinovBS * fModulusCm * fModulusCm;
(* 冷铁判据：模数超过临界模数即建议局部加冷铁 *)
xNeedChill := fModulusCm > fModulusCritCm;
xValid := TRUE;                                 (* 链路有效 / Chain valid *)
FC_DL_CastingSolidificationTimeCalc := fSolidTimeS;  (* 返回凝固时间 [s] / Return solidification time *)
END_FUNCTION
