(*
  Name: FC_DL_ElectrostaticVoltageCalc
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：静电喷涂电压-电流-距离校核：算电场强度（kV/mm），并分别给出电压上限与距离下限判定。
  边界条件：① 四入参全部过非有限闸，任一非有限返回哨兵 -1；
            ② 枪距为电场强度除子，须 50~500 mm，绝无零除；
            ③ 归因分离（R190）：xVoltSafe 只判电压对上限，xDistSafe 只判距离对下限，两判据不合并；
               电场强度仅作诊断输出，超限不并入任一安全位（避免出口归因混淆）；
            ④ 电流 fCurrentUa 仅参与域闸与诊断，不参与安全位（本件不做电流积分判定）。
  量纲自证：kV ÷ mm = kV/mm；电压与上限、距离与下限各自同量纲比较。
*)
FUNCTION FC_DL_ElectrostaticVoltageCalc : REAL
VAR_INPUT
    fDistMm : REAL;         (* 喷枪到工件距离 [mm] Gun-to-part distance [mm] *)
    fVoltKv : REAL;         (* 静电电压 [kV] Electrostatic voltage [kV] *)
    fCurrentUa : REAL;      (* 静电电流 [μA] Electrostatic current [uA] *)
    fVoltMaxKv : REAL;      (* 电压上限 [kV] Voltage ceiling [kV] *)
    fDistMinMm : REAL;      (* 枪距下限 [mm] Distance floor [mm] *)
END_VAR
VAR_OUTPUT
    fFieldKvPerMm : REAL;   (* 电场强度（诊断量） [kV/mm] Field strength [kV/mm] *)
    xVoltSafe : BOOL;       (* 电压不超上限 [-] Voltage within ceiling *)
    xDistSafe : BOOL;       (* 枪距不低于下限 [-] Distance above floor *)
    xValid : BOOL;          (* 计算有效性标志 [-] Calculation valid flag *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_D_MIN : REAL := 50.0;        (* 枪距量程下限 [mm] Distance floor [mm] *)
    DL_D_MAX : REAL := 500.0;       (* 枪距量程上限 [mm] Distance ceiling [mm] *)
    DL_V_MIN : REAL := 1.0;         (* 电压量程下限 [kV] Voltage floor [kV] *)
    DL_V_MAX : REAL := 120.0;       (* 电压量程上限 [kV] Voltage ceiling [kV] *)
    DL_I_MIN : REAL := 0.0;         (* 电流量程下限 [μA] Current floor [uA] *)
    DL_I_MAX : REAL := 200.0;       (* 电流量程上限 [μA] Current ceiling [uA] *)
    DL_VM_MIN : REAL := 1.0;        (* 电压上限下限 [kV] Voltage ceiling floor [kV] *)
    DL_VM_MAX : REAL := 120.0;      (* 电压上限上限 [kV] Voltage ceiling top [kV] *)
    DL_DM_MIN : REAL := 50.0;       (* 枪距下限下限 [mm] Distance floor floor [mm] *)
    DL_DM_MAX : REAL := 500.0;      (* 枪距下限上限 [mm] Distance floor top [mm] *)
END_VAR
(* 出口预置：四出口统一预置（R256） *)
fFieldKvPerMm := 0.0; xVoltSafe := FALSE; xDistSafe := FALSE; xValid := FALSE;
(* 非有限闸：NaN 自反判 + Inf 差值自减判，五入参全枚举（R272） *)
IF (fDistMm <> fDistMm) OR ((fDistMm - fDistMm) <> 0.0)
   OR (fVoltKv <> fVoltKv) OR ((fVoltKv - fVoltKv) <> 0.0)
   OR (fCurrentUa <> fCurrentUa) OR ((fCurrentUa - fCurrentUa) <> 0.0)
   OR (fVoltMaxKv <> fVoltMaxKv) OR ((fVoltMaxKv - fVoltMaxKv) <> 0.0)
   OR (fDistMinMm <> fDistMinMm) OR ((fDistMinMm - fDistMinMm) <> 0.0) THEN
    FC_DL_ElectrostaticVoltageCalc := -1.0; (* 哨兵 -1：入参非有限 / Sentinel -1, non-finite input *)
    RETURN;
END_IF
(* 组态域闸：枪距、电压、电流、两限值逐项定域（枪距为除子） *)
IF (fDistMm < DL_D_MIN) OR (fDistMm > DL_D_MAX)
   OR (fVoltKv < DL_V_MIN) OR (fVoltKv > DL_V_MAX)
   OR (fCurrentUa < DL_I_MIN) OR (fCurrentUa > DL_I_MAX)
   OR (fVoltMaxKv < DL_VM_MIN) OR (fVoltMaxKv > DL_VM_MAX)
   OR (fDistMinMm < DL_DM_MIN) OR (fDistMinMm > DL_DM_MAX) THEN
    FC_DL_ElectrostaticVoltageCalc := -1.0; (* 哨兵 -1：组态非法 / Sentinel -1, bad configuration *)
    RETURN;
END_IF
(* 电场强度：kV ÷ mm = kV/mm，枪距已过下限闸绝无零除 *)
fFieldKvPerMm := fVoltKv / fDistMm;
(* 归因唯一：电压判据只比电压上限；距离判据只比距离下限 *)
xVoltSafe := fVoltKv <= fVoltMaxKv;
xDistSafe := fDistMm >= fDistMinMm;
xValid := TRUE;                             (* 链路有效 / Chain valid *)
FC_DL_ElectrostaticVoltageCalc := fFieldKvPerMm;
END_FUNCTION
