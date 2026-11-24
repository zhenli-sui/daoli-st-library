(*
  ============================================================
  组件名 : FC_DL_RefCondApproach
  分类   : DL_Device
  功能   : 冷凝器逼近度计算，由冷凝饱和温度与进风温度求逼近度并判换热面污染
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_RefCondApproach : REAL
VAR_INPUT
    rCondSatTempC   : REAL; // 冷凝饱和温度 [摄氏度] condensing saturation temperature [degree celsius]
    rAirInTempC     : REAL; // 冷凝器进风温度 [摄氏度] condenser entering air temperature [degree celsius]
    rApproachRef    : REAL; // 设计逼近度基准 [K] design approach reference [kelvin]
    rApproachAlarm  : REAL; // 逼近度报警限 [K] approach alarm limit [kelvin]
END_VAR
VAR_OUTPUT
    rApproachK : REAL; // 实测逼近度 [K] measured approach [kelvin]
    bFouling   : BOOL; // 换热面污染判据标志 fouling verdict flag
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    _bFin : BOOL := FALSE; // 四输入有限性判定 finiteness verdict of the four inputs
    _rAp  : REAL := 0.0; // 逼近度中间量 [K] intermediate approach [kelvin]
    _rLim : REAL := 0.0; // 钳位后的报警限 [K] clamped alarm limit [kelvin]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefCondApproach := 0.0; // 缺省返回零 default zero return
rApproachK := 0.0; // 逼近度预置零 approach preset to zero
bFouling := FALSE; // 污染标志预置假 fouling flag preset false
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rCondSatTempC = rCondSatTempC) AND (rAirInTempC = rAirInTempC) AND (rApproachRef = rApproachRef) AND (rApproachAlarm = rApproachAlarm); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜主体逼近度 main approach
_rAp := rCondSatTempC - rAirInTempC; // 冷凝饱和温度减进风温度 condensing saturation minus the entering air
rApproachK := _rAp; // 逼近度落定 land the approach
// 段 4｜报警限整形与污染判定 alarm limit reshape and the fouling verdict
_rLim := rApproachAlarm; // 取入参报警限 take the alarm limit input
IF _rLim < 0.0 THEN
    _rLim := ABS(_rLim); // 负报警限取幅值 a negative limit becomes its magnitude
END_IF
bFouling := _rAp > _rLim; // 超限判换热面污染 an exceeded limit indicates fouling
bValid := TRUE; // 结果可用 result usable
FC_DL_RefCondApproach := _rAp; // 函数返回逼近度 return the approach
END_FUNCTION
