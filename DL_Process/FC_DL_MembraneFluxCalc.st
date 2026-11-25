(*
  ============================================================
  组件名 : FC_DL_MembraneFluxCalc
  分类   : DL_Process
  功能   : 膜通量计算，由产水流量与膜面积求通量并折算相对基准通量的比值
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_MembraneFluxCalc : REAL
VAR_INPUT
    rPermeateFlow_m3h : REAL; // 产水流量 [m3/h] permeate flow [m3 per hour]
    rMembraneArea_m2  : REAL; // 膜面积 [m2] membrane area [m2]
    rFluxRef          : REAL; // 基准通量 [L/m2/h] reference flux [litre per square metre per hour]
END_VAR
VAR_OUTPUT
    rFluxLmh   : REAL; // 实测通量 [L/m2/h] measured flux [litre per square metre per hour]
    rFluxRatio : REAL; // 通量与基准之比 [无量纲] ratio of the flux to the reference [dimensionless]
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_M3_TO_L : REAL := 1000.0; // 每立方米升数 litres per cubic metre
END_VAR
VAR
    _bFin : BOOL := FALSE; // 三输入有限性判定 finiteness verdict of the three inputs
    _rFlux: REAL := 0.0; // 通量中间量 [L/m2/h] intermediate flux [litre per square metre per hour]
    _rRat : REAL := 0.0; // 比值中间量 [无量纲] intermediate ratio [dimensionless]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_MembraneFluxCalc := 0.0; // 缺省返回零 default zero return
rFluxLmh := 0.0; // 通量预置零 flux preset to zero
rFluxRatio := 0.0; // 比值预置零 ratio preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rPermeateFlow_m3h = rPermeateFlow_m3h) AND (rMembraneArea_m2 = rMembraneArea_m2) AND (rFluxRef = rFluxRef); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜面积与流量闸 area and flow gate
IF (rMembraneArea_m2 <= 0.0) OR (rPermeateFlow_m3h < 0.0) THEN
    RETURN; // 面积非正或负流量属配置非法 an illegal area or a negative flow
END_IF
// 段 4｜主体通量 main flux
_rFlux := rPermeateFlow_m3h * DL_M3_TO_L / rMembraneArea_m2; // 流量折算升后除面积 flow in litres over the area
rFluxLmh := _rFlux; // 通量落定 land the flux
// 段 5｜基准比值闸 reference ratio gate
IF rFluxRef <= 0.0 THEN
    RETURN; // 基准通量非正无法求比值 a non positive reference cannot carry a ratio
END_IF
_rRat := _rFlux / rFluxRef; // 实测对基准比值 measured over reference
rFluxRatio := _rRat; // 比值落定 land the ratio
bValid := TRUE; // 结果可用 result usable
FC_DL_MembraneFluxCalc := _rFlux; // 函数返回通量 return the flux
END_FUNCTION
