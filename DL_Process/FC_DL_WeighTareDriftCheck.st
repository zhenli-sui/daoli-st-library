(*
  ============================================================
  组件名 : FC_DL_WeighTareDriftCheck
  分类   : DL_Process
  功能   : 单点皮重相对标定基准的漂移量与漂移百分比监视，超限置位
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighTareDriftCheck : BOOL
VAR_INPUT
    rTareNow    : REAL; // 当前实测皮重 [kg] current measured tare [kg]
    rTareRef    : REAL; // 标定基准皮重 [kg] calibrated reference tare [kg]
    rDriftLimit : REAL; // 漂移报警限 [kg] drift alarm limit [kg]
    nSamples    : INT; // 采样点数 [个] sample count [count]
END_VAR
VAR_OUTPUT
    rDrift         : REAL; // 皮重漂移量 [kg] tare drift [kg]
    rDriftPct      : REAL; // 漂移百分比 [%] drift percentage [%]
    bDriftExceeded : BOOL; // 漂移超限标志 drift exceeded flag
    bValid         : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_EPS_R : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin : BOOL := FALSE; // 三实数输入有限性判定 finiteness verdict of the three real inputs
    _rLim : REAL := 0.0; // 钳位后的漂移限 [kg] clamped drift limit [kg]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighTareDriftCheck := FALSE; // 缺省返回未超限 default not exceeded
rDrift := 0.0; // 漂移量预置零 drift preset to zero
rDriftPct := 0.0; // 漂移百分比预置零 drift percentage preset to zero
bDriftExceeded := FALSE; // 超限标志预置假 exceeded flag preset false
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸与点数闸 finiteness gate and sample count gate
_bFin := (rTareNow = rTareNow) AND (rTareRef = rTareRef) AND (rDriftLimit = rDriftLimit); // 三输入自反判定 self comparison of the three inputs
IF (NOT _bFin) OR (nSamples < 1) THEN
    RETURN; // 非有限或无采样即无效 non finite or no sample means invalid
END_IF
// 段 3｜漂移量与百分比 drift value and percentage
rDrift := rTareNow - rTareRef; // 单点滑动漂移量 single point sliding drift
IF ABS(rTareRef) < DL_EPS_R THEN
    RETURN; // 基准皮重近零无法折算百分比 a zero reference cannot carry a percentage
END_IF
rDriftPct := rDrift / rTareRef * 100.0; // 相对基准的漂移百分比 drift relative to the reference [%]
// 段 4｜限值整形与超限判定 limit reshape and the exceed verdict
_rLim := rDriftLimit; // 取入参限值 take the limit input
IF _rLim < 0.0 THEN
    _rLim := ABS(_rLim); // 负限值取幅值 a negative limit becomes its magnitude
END_IF
bDriftExceeded := ABS(rDrift) > _rLim; // 双向漂移均计入超限 drift counts in both directions
bValid := TRUE; // 结果可用 result usable
FC_DL_WeighTareDriftCheck := bDriftExceeded; // 函数返回超限标志 return the exceeded flag
END_FUNCTION
