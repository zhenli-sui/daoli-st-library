(*
  Name: FC_DL_StripTensionRefCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：带钢张力设定：按断面面积与单位张力算总张力，并按设备张力上限钳位输出。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 断面尺寸与单位张力按工程域闸限定（宽 100~2500 mm、厚 0.1~6 mm、单位张力 10~200 MPa）；
            ③ 钳位属量值饱和：xClamped = TRUE 表示设定被设备上限截断，xValid 仍为 TRUE（事实未伪造）。
  量纲自证：W[mm]/1000 × T[mm]/1000 = m2；m2 × σ[MPa = MN/m2] = MN = 1000 kN；故 ÷1000 得 kN。
*)
FUNCTION FC_DL_StripTensionRefCalc : REAL
VAR_INPUT
    fWidthMm : REAL;         (* 带钢宽度 [mm] Strip width [mm] *)
    fThkMm : REAL;           (* 带钢厚度 [mm] Strip thickness [mm] *)
    fUnitTensionMpa : REAL;  (* 单位张力 [MPa] Unit tension [MPa] *)
    fTensionMaxKN : REAL;    (* 设备张力上限 [kN] Equipment tension ceiling [kN] *)
END_VAR
VAR_OUTPUT
    fTensionKN : REAL;       (* 张力设定值 [kN] Tension setpoint [kN] *)
    xClamped : BOOL;         (* 已按上限钳位 [-] Clamped by ceiling *)
    xValid : BOOL;           (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_MM_TO_M : REAL := 1000.0;    (* 毫米 → 米换算 [mm/m] Millimetre to metre *)
    DL_MN_TO_KN : REAL := 1000.0;   (* 兆牛 → 千牛换算 [kN/MN] Meganewton to kilonewton *)
    DL_W_MIN : REAL := 100.0;       (* 带宽下限 [mm] Width floor [mm] *)
    DL_W_MAX : REAL := 2500.0;      (* 带宽上限 [mm] Width ceiling [mm] *)
    DL_T_MIN : REAL := 0.1;         (* 带厚下限 [mm] Thickness floor [mm] *)
    DL_T_MAX : REAL := 6.0;         (* 带厚上限 [mm] Thickness ceiling [mm] *)
    DL_U_MIN : REAL := 10.0;        (* 单位张力下限 [MPa] Unit tension floor [MPa] *)
    DL_U_MAX : REAL := 200.0;       (* 单位张力上限 [MPa] Unit tension ceiling [MPa] *)
    DL_F_MIN : REAL := 1.0;         (* 设备上限下限 [kN] Equipment ceiling floor [kN] *)
    DL_F_MAX : REAL := 500.0;       (* 设备上限上限 [kN] Equipment ceiling top [kN] *)
END_VAR
VAR
    fAreaM2 : REAL;     (* 断面面积 [m2] Cross-section area [m2] *)
    fForceMN : REAL;    (* 张力（兆牛） [MN] Tension in meganewtons [MN] *)
END_VAR
(* 出口预置：三出口统一预置（R256） *)
fTensionKN := 0.0; xClamped := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fWidthMm <> fWidthMm) OR ((fWidthMm - fWidthMm) <> 0.0)
   OR (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0)
   OR (fUnitTensionMpa <> fUnitTensionMpa) OR ((fUnitTensionMpa - fUnitTensionMpa) <> 0.0)
   OR (fTensionMaxKN <> fTensionMaxKN) OR ((fTensionMaxKN - fTensionMaxKN) <> 0.0) THEN
    FC_DL_StripTensionRefCalc := -1.0;      (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：断面与单位张力、设备上限逐项定域 *)
IF (fWidthMm < DL_W_MIN) OR (fWidthMm > DL_W_MAX)
   OR (fThkMm < DL_T_MIN) OR (fThkMm > DL_T_MAX)
   OR (fUnitTensionMpa < DL_U_MIN) OR (fUnitTensionMpa > DL_U_MAX)
   OR (fTensionMaxKN < DL_F_MIN) OR (fTensionMaxKN > DL_F_MAX) THEN
    FC_DL_StripTensionRefCalc := -1.0;      (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 断面面积：mm → m 后相乘，量纲 m2 *)
fAreaM2 := (fWidthMm / DL_MM_TO_M) * (fThkMm / DL_MM_TO_M);
(* 张力：m2 × MPa = MN（1 MPa = 1 MN/m2），再折 kN *)
fForceMN := fAreaM2 * fUnitTensionMpa;
fTensionKN := fForceMN * DL_MN_TO_KN;
(* 上限钳位：量值饱和并置钳位标志，有效性不受影响 *)
IF fTensionKN > fTensionMaxKN THEN
    fTensionKN := fTensionMaxKN;
    xClamped := TRUE;
END_IF
IF fTensionKN < DL_EPS THEN
    fTensionKN := 0.0;                      (* 微负残差归零 / Negative residual to zero *)
END_IF
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_StripTensionRefCalc := fTensionKN;
END_FUNCTION
