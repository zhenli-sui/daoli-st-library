(*
  ============================================================
  组件名 : FC_DL_PneuLeakRateCalc
  分类   : DL_Device
  功能   : 气密保压试验泄漏率计算，由起止压力、容积与试验时长求泄漏量与压降百分比
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_PneuLeakRateCalc : REAL
VAR_INPUT
    rPressStart_bar : REAL; // 试验起始压力 [bar] test start pressure [bar]
    rPressEnd_bar   : REAL; // 试验结束压力 [bar] test end pressure [bar]
    rVolume_l       : REAL; // 试件与管路容积 [l] specimen and piping volume [litre]
    rTestTimeS      : REAL; // 保压试验时长 [s] holding test duration [s]
    rTempC          : REAL; // 试验环境温度 [摄氏度] ambient test temperature [degree celsius]
END_VAR
VAR_OUTPUT
    rLeak_lpm      : REAL; // 标准状态泄漏量 [Nl/min] leak rate at standard state [normal litre per minute]
    rLeakPctPerMin : REAL; // 每分钟压降百分比 [%/min] pressure decay percentage per minute [% per minute]
    bValid         : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_ATM_BAR   : REAL := 1.01325; // 标准大气压 [bar] standard atmosphere [bar]
    DL_SEC_PER_MIN : REAL := 60.0; // 每分钟秒数 seconds per minute
    DL_KELVIN    : REAL := 273.15; // 摄氏到开尔文偏移 celsius to kelvin offset
    DL_T_REF_K   : REAL := 293.15; // 标准状态参考温度 [K] reference temperature at standard state [K]
    DL_HUNDRED   : REAL := 100.0; // 百分制换算系数 percentage scale factor
    DL_EPS_R     : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 五输入有限性判定 finiteness verdict of the five inputs
    _rDropBar: REAL := 0.0; // 压力降 [bar] pressure drop [bar]
    _rTempK  : REAL := 0.0; // 绝对温度 [K] absolute temperature [K]
    _rVolStd : REAL := 0.0; // 标准状态泄漏体积 [Nl] normal leak volume [normal litre]
    _rLeak   : REAL := 0.0; // 泄漏量中间量 [Nl/min] intermediate leak rate [normal litre per minute]
    _rPct    : REAL := 0.0; // 每分钟压降百分比中间量 [%/min] intermediate decay percentage [% per minute]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_PneuLeakRateCalc := 0.0; // 缺省返回零 default zero return
rLeak_lpm := 0.0; // 泄漏量预置零 leak rate preset to zero
rLeakPctPerMin := 0.0; // 压降百分比预置零 decay percentage preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rPressStart_bar = rPressStart_bar) AND (rPressEnd_bar = rPressEnd_bar) AND (rVolume_l = rVolume_l) AND (rTestTimeS = rTestTimeS) AND (rTempC = rTempC); // 五输入自反判定 self comparison of the five inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜时长压力与容积闸 duration pressure and volume gate
IF (rTestTimeS <= DL_EPS_R) OR (rPressStart_bar <= DL_EPS_R) OR (rVolume_l <= 0.0) THEN
    RETURN; // 时长压力容积非正无法折算 a non positive duration pressure or volume cannot be converted
END_IF
IF rPressEnd_bar < 0.0 THEN
    RETURN; // 终压为负属采集异常 a negative end pressure is a measurement fault
END_IF
// 段 4｜标准状态泄漏体积 normal leak volume
_rDropBar := rPressStart_bar - rPressEnd_bar; // 试验段压力降 pressure drop over the test window
_rTempK := rTempC + DL_KELVIN; // 摄氏折算开尔文 convert celsius to kelvin
IF _rTempK <= DL_EPS_R THEN
    RETURN; // 绝对温度非正无法折算 a non positive absolute temperature cannot be converted
END_IF
_rVolStd := _rDropBar * rVolume_l / DL_ATM_BAR * (DL_T_REF_K / _rTempK); // 压降乘容积折标准状态 drop times volume normalised to the standard state
// 段 5｜泄漏率与压降百分比 leak rate and the decay percentage
_rLeak := _rVolStd / rTestTimeS * DL_SEC_PER_MIN; // 折算到每分钟 per minute leak rate
_rPct := (_rDropBar / rPressStart_bar * DL_HUNDRED) / (rTestTimeS / DL_SEC_PER_MIN); // 每分钟压降百分比 pressure decay percentage per minute
IF (_rLeak <> _rLeak) OR (ABS(_rLeak) > 1.0E30) OR (_rPct <> _rPct) OR (ABS(_rPct) > 1.0E30) THEN
    RETURN; // 结果非有限拒收 refuse a non finite result
END_IF
rLeak_lpm := _rLeak; // 泄漏量落定 land the leak rate
rLeakPctPerMin := _rPct; // 压降百分比落定 land the decay percentage
bValid := TRUE; // 结果可用 result usable
FC_DL_PneuLeakRateCalc := _rLeak; // 函数返回泄漏量 return the leak rate
END_FUNCTION
