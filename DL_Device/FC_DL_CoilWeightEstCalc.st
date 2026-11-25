(*
  Name: FC_DL_CoilWeightEstCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：钢卷重量估算：按带长、带宽、带厚与材料密度算理论重量。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 负值与零值一律剔除（长度 ≤ 0、宽厚 ≤ 0 视为无料），返回哨兵 -1，不静默输出 0 kg；
            ③ 尺寸与密度按工程域闸限定，密度取钢 7000~8000 kg/m3 带宽区间含不锈钢与碳钢。
  量纲自证：L[m] × W[m] × T[m] = m3；m3 × ρ[kg/m3] = kg。
*)
FUNCTION FC_DL_CoilWeightEstCalc : REAL
VAR_INPUT
    fLengthM : REAL;        (* 带长 [m] Strip length [m] *)
    fWidthMm : REAL;        (* 带宽 [mm] Strip width [mm] *)
    fThkMm : REAL;          (* 带厚 [mm] Strip thickness [mm] *)
    fDensityKgM3 : REAL;    (* 材料密度 [kg/m3] Material density [kg/m3] *)
END_VAR
VAR_OUTPUT
    fWeightKg : REAL;       (* 钢卷重量 [kg] Coil weight [kg] *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_MM_TO_M : REAL := 1000.0;    (* 毫米 → 米换算 [mm/m] Millimetre to metre *)
    DL_L_MAX : REAL := 100000.0;    (* 带长上限 [m] Length ceiling [m] *)
    DL_W_MIN : REAL := 100.0;       (* 带宽下限 [mm] Width floor [mm] *)
    DL_W_MAX : REAL := 2500.0;      (* 带宽上限 [mm] Width ceiling [mm] *)
    DL_T_MIN : REAL := 0.05;        (* 带厚下限 [mm] Thickness floor [mm] *)
    DL_T_MAX : REAL := 12.0;        (* 带厚上限 [mm] Thickness ceiling [mm] *)
    DL_RHO_MIN : REAL := 7000.0;    (* 密度下限 [kg/m3] Density floor [kg/m3] *)
    DL_RHO_MAX : REAL := 8000.0;    (* 密度上限 [kg/m3] Density ceiling [kg/m3] *)
END_VAR
VAR
    fVolM3 : REAL;  (* 带钢体积 [m3] Strip volume [m3] *)
END_VAR
(* 出口预置：两出口统一预置（R256） *)
fWeightKg := 0.0; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，四入参全枚举 *)
IF (fLengthM <> fLengthM) OR ((fLengthM - fLengthM) <> 0.0)
   OR (fWidthMm <> fWidthMm) OR ((fWidthMm - fWidthMm) <> 0.0)
   OR (fThkMm <> fThkMm) OR ((fThkMm - fThkMm) <> 0.0)
   OR (fDensityKgM3 <> fDensityKgM3) OR ((fDensityKgM3 - fDensityKgM3) <> 0.0) THEN
    FC_DL_CoilWeightEstCalc := -1.0;        (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：零与负值一律剔除，尺寸与密度按工程域限定 *)
IF (fLengthM <= DL_EPS) OR (fLengthM > DL_L_MAX)
   OR (fWidthMm < DL_W_MIN) OR (fWidthMm > DL_W_MAX)
   OR (fThkMm < DL_T_MIN) OR (fThkMm > DL_T_MAX)
   OR (fDensityKgM3 < DL_RHO_MIN) OR (fDensityKgM3 > DL_RHO_MAX) THEN
    FC_DL_CoilWeightEstCalc := -1.0;        (* 哨兵 -1：无料或越域 / Sentinel -1, no material or out of range *)
    RETURN;
END_IF
(* 体积：mm → m 后三向相乘，量纲 m3 *)
fVolM3 := fLengthM * (fWidthMm / DL_MM_TO_M) * (fThkMm / DL_MM_TO_M);
(* 重量：m3 × kg/m3 = kg *)
fWeightKg := fVolM3 * fDensityKgM3;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_CoilWeightEstCalc := fWeightKg;
END_FUNCTION
