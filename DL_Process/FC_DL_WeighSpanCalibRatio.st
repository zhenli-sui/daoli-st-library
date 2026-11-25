(*
  ============================================================
  组件名 : FC_DL_WeighSpanCalibRatio
  分类   : DL_Process
  功能   : 称重系统量程标定，由零点和量程两点原始值求比例系数与量程误差
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighSpanCalibRatio : REAL
VAR_INPUT
    rRawAtZero : REAL; // 空载时原始值 [count] raw value at no load [count]
    rRawAtSpan : REAL; // 加载标准砝码时原始值 [count] raw value at the reference span [count]
    rRefSpan   : REAL; // 标准砝码标称值 [kg] nominal reference weight [kg]
END_VAR
VAR_OUTPUT
    rRatio        : REAL; // 标定比例系数 [kg/count] calibration ratio [kg per count]
    rSpanErrorPct : REAL; // 量程误差百分比 [%] span error percentage [%]
    bValid        : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_EPS_R    : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
    DL_ERR_LIM  : REAL := 5.0; // 量程误差合理上限 [%] admissible span error ceiling [%]
    DL_HUNDRED  : REAL := 100.0; // 百分制换算系数 percentage scale factor
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 三输入有限性判定 finiteness verdict of the three inputs
    _rDelta : REAL := 0.0; // 两点原始值增量 [count] raw span increment [count]
    _rRatio : REAL := 0.0; // 比例系数中间量 [kg/count] intermediate ratio [kg per count]
    _rErr   : REAL := 0.0; // 量程误差中间量 [%] intermediate span error [%]
    _rPred  : REAL := 0.0; // 按比例反推的砝码值 [kg] weight predicted by the ratio [kg]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighSpanCalibRatio := 0.0; // 缺省返回零 default zero return
rRatio := 0.0; // 比例系数预置零 ratio preset to zero
rSpanErrorPct := 0.0; // 量程误差预置零 span error preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rRawAtZero = rRawAtZero) AND (rRawAtSpan = rRawAtSpan) AND (rRefSpan = rRefSpan); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜两点增量与砝码值闸 span increment and reference weight gate
_rDelta := rRawAtSpan - rRawAtZero; // 量程段原始增量 raw increment over the span
IF (ABS(_rDelta) < DL_EPS_R) OR (rRefSpan <= 0.0) THEN
    RETURN; // 增量近零或砝码非正无法标定 a zero increment or a non positive reference cannot calibrate
END_IF
// 段 4｜比例系数与量程误差 ratio and span error
_rRatio := rRefSpan / _rDelta; // 比例系数 ratio of the reference to the increment
_rPred := _rRatio * rRefSpan; // 按比例反推的砝码值 weight predicted from the ratio
_rErr := (_rPred - rRefSpan) / rRefSpan * DL_HUNDRED; // 量程误差百分比 span error percentage
rRatio := _rRatio; // 比例系数落定 land the ratio
rSpanErrorPct := _rErr; // 量程误差落定 land the span error
// 段 5｜超差合理性闸 span error plausibility gate
IF ABS(_rErr) > DL_ERR_LIM THEN
    RETURN; // 超差判无效，比例系数保留供诊断 an excessive error is void while the ratio stays for diagnosis
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_WeighSpanCalibRatio := _rRatio; // 函数返回比例系数 return the ratio
END_FUNCTION
