(*
  ============================================================
  组件名 : FC_DL_RefCopCalc
  分类   : DL_Device
  功能   : 制冷机组能效比计算，由制冷量与输入功率求 COP 及其与额定值的比值
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_RefCopCalc : REAL
VAR_INPUT
    rCoolingCap_kW : REAL; // 制冷量 [kW] cooling capacity [kW]
    rPowerIn_kW    : REAL; // 输入功率 [kW] electrical power input [kW]
    rCopRated      : REAL; // 额定能效比 [无量纲] rated coefficient of performance [dimensionless]
END_VAR
VAR_OUTPUT
    rCop      : REAL; // 实测能效比 [无量纲] measured coefficient of performance [dimensionless]
    rCopRatio : REAL; // 实测与额定能效比之比 [无量纲] ratio of the measured to the rated value [dimensionless]
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_POWER_FLOOR : REAL := 0.01; // 功率有效下限 [kW] power effective floor [kW]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 三输入有限性判定 finiteness verdict of the three inputs
    _rCop  : REAL := 0.0; // 能效比中间量 [无量纲] intermediate coefficient [dimensionless]
    _rRat  : REAL := 0.0; // 比值中间量 [无量纲] intermediate ratio [dimensionless]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefCopCalc := 0.0; // 缺省返回零 default zero return
rCop := 0.0; // 能效比预置零 coefficient preset to zero
rCopRatio := 0.0; // 比值预置零 ratio preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rCoolingCap_kW = rCoolingCap_kW) AND (rPowerIn_kW = rPowerIn_kW) AND (rCopRated = rCopRated); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜功率分母闸 power divisor gate
IF rPowerIn_kW <= DL_POWER_FLOOR THEN
    RETURN; // 功率低于有效下限判无效 a power below the floor is void
END_IF
// 段 4｜主体能效比 main coefficient of performance
_rCop := rCoolingCap_kW / rPowerIn_kW; // 制冷量除以输入功率 capacity over the power input
rCop := _rCop; // 能效比落定 land the coefficient
// 段 5｜额定比值闸 rated ratio gate
IF rCopRated <= 0.0 THEN
    RETURN; // 额定值非正无法求比值 a non positive rating cannot carry a ratio
END_IF
_rRat := _rCop / rCopRated; // 实测对额定比值 measured over rated
rCopRatio := _rRat; // 比值落定 land the ratio
bValid := TRUE; // 结果可用 result usable
FC_DL_RefCopCalc := _rCop; // 函数返回能效比 return the coefficient
END_FUNCTION
