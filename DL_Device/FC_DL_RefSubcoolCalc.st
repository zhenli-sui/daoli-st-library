(*
  ============================================================
  组件名 : FC_DL_RefSubcoolCalc
  分类   : DL_Device
  功能   : 液管过冷度计算，由冷凝饱和温度与液管温度求过冷度并分档判定
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_RefSubcoolCalc : REAL
VAR_INPUT
    rLiquidTempC    : REAL; // 液管实测温度 [摄氏度] measured liquid line temperature [degree celsius]
    rSatLiquidTempC : REAL; // 液管饱和温度 [摄氏度] saturation temperature at the liquid pressure [degree celsius]
    rScLow          : REAL; // 过冷度下限 [K] lower subcooling bound [kelvin]
    rScHigh         : REAL; // 过冷度上限 [K] upper subcooling bound [kelvin]
END_VAR
VAR_OUTPUT
    rSubcoolK : REAL; // 液管过冷度 [K] liquid subcooling [kelvin]
    nStatus   : INT; // 分档 0正常 1偏低 2偏高 [档] status 0 normal, 1 low, 2 high [band]
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 四输入有限性判定 finiteness verdict of the four inputs
    _rSc   : REAL := 0.0; // 过冷度中间量 [K] intermediate subcooling [kelvin]
    _rLo   : REAL := 0.0; // 钳位后的下限 [K] clamped lower bound [kelvin]
    _rHi   : REAL := 0.0; // 钳位后的上限 [K] clamped upper bound [kelvin]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefSubcoolCalc := 0.0; // 缺省返回零 default zero return
rSubcoolK := 0.0; // 过冷度预置零 subcooling preset to zero
nStatus := 0; // 分档预置正常 status preset normal
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rLiquidTempC = rLiquidTempC) AND (rSatLiquidTempC = rSatLiquidTempC) AND (rScLow = rScLow) AND (rScHigh = rScHigh); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜主体过冷度 main subcooling，口径为饱和温度减液管温度 saturation minus the liquid temperature
_rSc := rSatLiquidTempC - rLiquidTempC; // 饱和温度减液管温度 saturation minus the liquid temperature
rSubcoolK := _rSc; // 过冷度落定 land the subcooling
// 段 4｜上下限整形 bound reshape
_rLo := rScLow; // 取下限 take the lower bound
_rHi := rScHigh; // 取上限 take the upper bound
IF _rLo > _rHi THEN
    _rLo := rScHigh; // 上下限倒置时下限取原上限 an inverted pair swaps the lower bound
    _rHi := rScLow; // 上下限倒置时上限取原下限 an inverted pair swaps the upper bound
END_IF
// 段 5｜双向分档判定 directional status verdict
IF _rSc < _rLo THEN
    nStatus := 1; // 过冷度偏低 subcooling too low
ELSIF _rSc > _rHi THEN
    nStatus := 2; // 过冷度偏高 subcooling too high
ELSE
    nStatus := 0; // 区间内正常 inside the normal band
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_RefSubcoolCalc := _rSc; // 函数返回过冷度 return the subcooling
END_FUNCTION
