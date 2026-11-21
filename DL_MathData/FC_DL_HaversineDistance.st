(*
  Name        : FC_DL_HaversineDistance
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 球面两点大圆距离（Haversine 公式，双精度），供 AGV/巡检定位换算；输入为十进制度，输出为米；/ Great-circle distance between two points via the Haversine formula in double precision; inputs in decimal degrees, output in metres
  溯源        : t2-1-lgf-math ◐/自研，clean-room 实现
  Boundary    : ① 入口有限性闸：任一输入 NaN（x = x 自反）或 Inf（(x-x) = (x-x) 差判）→ bValid = FALSE，返回 0.0（哨兵零点）；
                ② 输入域钳位：纬度钳 -90..90，经度差归一化到 -180..180（不钳位经度本身，跨 180° 子午线正确）；
                ③ 除零前置：公式内除子为常量（2/半径换算）与 asin 域保护（根号项钳 0..1）；
                ④ 钳位是各中间量的最后一次写（纬度/经度差/根号项），钳完不被覆盖；
                ⑤ 返回值 = 两点球面距离 [m]，bValid = FALSE 时不得使用返回值（上层契约）。
*)
FUNCTION FC_DL_HaversineDistance : LREAL
VAR_INPUT
    fLat1 : LREAL;                           (* 点 1 纬度，域 -90..90（越域钳位）[°] / Point 1 latitude *)
    fLon1 : LREAL;                           (* 点 1 经度 [°] / Point 1 longitude *)
    fLat2 : LREAL;                           (* 点 2 纬度，域 -90..90（越域钳位）[°] / Point 2 latitude *)
    fLon2 : LREAL;                           (* 点 2 经度 [°] / Point 2 longitude *)
END_VAR
VAR_OUTPUT
    bValid : BOOL;                           (* 结果有效标志（FALSE 时返回值为哨兵零点）[-] / Result validity flag *)
END_VAR
VAR CONSTANT
    DL_HAV_R_EARTH : LREAL := 6371008.8;     (* 地球平均半径 [m] / Earth mean radius *)
    DL_HAV_DEG2RAD : LREAL := 0.017453292519943295;   (* 度→弧度换算常量 π/180 [-] / Degrees to radians factor *)
    DL_HAV_LATMAX  : LREAL := 90.0;          (* 纬度钳位绝对值上限 [°] / Latitude clamp magnitude *)
    DL_HAV_LONSPAN : LREAL := 360.0;         (* 经度整圆跨度（归一化用）[°] / Longitude full circle span *)
    DL_HAV_HALF    : LREAL := 0.5;           (* 半角换算常量 [-] / Half factor *)
    DL_HAV_TWO     : LREAL := 2.0;           (* 反正弦倍率常量 [-] / Arc-sine multiplier *)
END_VAR
VAR
    _fLat1   : LREAL;                        (* 钳位后点 1 纬度 [°] / Clamped latitude 1 *)
    _fLat2   : LREAL;                        (* 钳位后点 2 纬度 [°] / Clamped latitude 2 *)
    _fDLon   : LREAL;                        (* 归一化后经度差 [°] / Normalised longitude delta *)
    _fPhi1   : LREAL;                        (* 点 1 纬度弧度 [rad] / Latitude 1 in radians *)
    _fPhi2   : LREAL;                        (* 点 2 纬度弧度 [rad] / Latitude 2 in radians *)
    _fDPhi   : LREAL;                        (* 纬度差弧度 [rad] / Latitude delta radians *)
    _fDLam   : LREAL;                        (* 经度差弧度 [rad] / Longitude delta radians *)
    _fSinDp  : LREAL;                        (* sin(Δφ/2) 中间量 [-] / Half-chord sine term 1 *)
    _fSinDl  : LREAL;                        (* sin(Δλ/2) 中间量 [-] / Half-chord sine term 2 *)
    _fA      : LREAL;                        (* Haversine a 中间量 [-] / Haversine a term *)
    _fC      : LREAL;                        (* Haversine c 中间量（asin 域已钳）[-] / Haversine c term *)
END_VAR

(* —— 段 0：入口有限性闸（NaN 自反 + Inf 差判，四输入逐项） —— *)
bValid := TRUE;                                                                (* 有效标志预置（任一闸命中即翻 FALSE） / Validity preset *)
IF NOT ((fLat1 = fLat1) AND ((fLat1 - fLat1) = (fLat1 - fLat1))) THEN
    bValid := FALSE;                                                           (* 纬度 1 非有限 / Latitude 1 non-finite *)
END_IF
IF NOT ((fLon1 = fLon1) AND ((fLon1 - fLon1) = (fLon1 - fLon1))) THEN
    bValid := FALSE;                                                           (* 经度 1 非有限 / Longitude 1 non-finite *)
END_IF
IF NOT ((fLat2 = fLat2) AND ((fLat2 - fLat2) = (fLat2 - fLat2))) THEN
    bValid := FALSE;                                                           (* 纬度 2 非有限 / Latitude 2 non-finite *)
END_IF
IF NOT ((fLon2 = fLon2) AND ((fLon2 - fLon2) = (fLon2 - fLon2))) THEN
    bValid := FALSE;                                                           (* 经度 2 非有限 / Longitude 2 non-finite *)
END_IF

(* —— 段 1：无效输入早退（返回哨兵零点） —— *)
IF NOT bValid THEN
    FC_DL_HaversineDistance := 0.0;                                            (* 哨兵零点返回 / Sentinel zero return *)
    RETURN;
END_IF

(* —— 段 2：输入域钳位与经度差归一化（各自中间量最后一次写） —— *)
_fLat1 := fLat1;                                                               (* 点 1 纬度装载 / Load latitude 1 *)
IF _fLat1 > DL_HAV_LATMAX THEN
    _fLat1 := DL_HAV_LATMAX;                                                   (* 纬度上限钳位 / Latitude upper clamp *)
END_IF
IF _fLat1 < -DL_HAV_LATMAX THEN
    _fLat1 := -DL_HAV_LATMAX;                                                  (* 纬度下限钳位 / Latitude lower clamp *)
END_IF
_fLat2 := fLat2;                                                               (* 点 2 纬度装载 / Load latitude 2 *)
IF _fLat2 > DL_HAV_LATMAX THEN
    _fLat2 := DL_HAV_LATMAX;                                                   (* 纬度上限钳位 / Latitude upper clamp *)
END_IF
IF _fLat2 < -DL_HAV_LATMAX THEN
    _fLat2 := -DL_HAV_LATMAX;                                                  (* 纬度下限钳位 / Latitude lower clamp *)
END_IF
_fDLon := fLon2 - fLon1;                                                       (* 原始经度差 [°] / Raw longitude delta *)
_fDLon := _fDLon - DL_HAV_LONSPAN * TRUNC(_fDLon / DL_HAV_LONSPAN);            (* 整圈折返到 (-360, 360)（除子为常量） / Fold into one circle *)
IF _fDLon > 180.0 THEN
    _fDLon := _fDLon - DL_HAV_LONSPAN;                                         (* 折回 (-180, 180]，跨 180° 子午线正确 / Fold back across antimeridian *)
ELSIF _fDLon <= -180.0 THEN
    _fDLon := _fDLon + DL_HAV_LONSPAN;                                         (* 折回 (-180, 180] / Fold back *)
END_IF

(* —— 段 3：Haversine 公式本体（除子全为常量，无运行期除零） —— *)
_fPhi1 := _fLat1 * DL_HAV_DEG2RAD;                                             (* 点 1 纬度弧度 [rad] / Latitude 1 radians *)
_fPhi2 := _fLat2 * DL_HAV_DEG2RAD;                                             (* 点 2 纬度弧度 [rad] / Latitude 2 radians *)
_fDPhi := (_fLat2 - _fLat1) * DL_HAV_DEG2RAD;                                  (* 纬度差弧度 [rad] / Latitude delta radians *)
_fDLam := _fDLon * DL_HAV_DEG2RAD;                                             (* 经度差弧度 [rad] / Longitude delta radians *)
_fSinDp := SIN(_fDPhi * DL_HAV_HALF);                                          (* sin(Δφ/2) [-] / Sine term 1 *)
_fSinDl := SIN(_fDLam * DL_HAV_HALF);                                          (* sin(Δλ/2) [-] / Sine term 2 *)
_fA := _fSinDp * _fSinDp + COS(_fPhi1) * COS(_fPhi2) * _fSinDl * _fSinDl;      (* Haversine a [-] / Haversine a *)
IF _fA > 1.0 THEN
    _fA := 1.0;                                                                (* a 上界钳 1（浮点溢出防护，asin 定义域） / Clamp a to domain *)
ELSIF _fA < 0.0 THEN
    _fA := 0.0;                                                                (* a 下界钳 0（asin 定义域） / Clamp a to domain *)
END_IF
_fC := ASIN(SQRT(_fA)) * DL_HAV_TWO;                                           (* 大圆角距 c（定义域已钳）[rad] / Central angle *)
FC_DL_HaversineDistance := DL_HAV_R_EARTH * _fC;                               (* 球面距离 = R × c [m] / Distance = R times c *)
END_FUNCTION
