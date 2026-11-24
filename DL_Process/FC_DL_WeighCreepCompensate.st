(*
  ============================================================
  组件名 : FC_DL_WeighCreepCompensate
  分类   : DL_Process
  功能   : 称重传感器蠕变补偿，按加载时长、蠕变速率与温度因子修正原始读数
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighCreepCompensate : REAL
VAR_INPUT
    rRaw              : REAL; // 传感器原始读数 [kg] raw load cell reading [kg]
    rLoadTimeS        : REAL; // 持续加载时长 [s] continuous loaded duration [s]
    rCreepRatePctPerH : REAL; // 每小时蠕变百分比 [%/h] creep percentage per hour [%/h]
    rTempFactor       : REAL; // 温度修正因子 1.0 为常温 [无量纲] temperature factor, one at ambient [dimensionless]
END_VAR
VAR_OUTPUT
    rCorrected : REAL; // 蠕变补偿后的读数 [kg] creep corrected reading [kg]
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_SEC_PER_HOUR : REAL := 3600.0; // 每小时秒数 seconds per hour
    DL_HUNDRED      : REAL := 100.0; // 百分制换算系数 percentage scale factor
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 四输入有限性判定 finiteness verdict of the four inputs
    _rRel  : REAL := 0.0; // 累计相对蠕变量 [无量纲] accumulated relative creep [dimensionless]
    _rCorr : REAL := 0.0; // 修正后的读数中间量 [kg] intermediate corrected reading [kg]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighCreepCompensate := 0.0; // 缺省返回零 default zero return
rCorrected := 0.0; // 修正值预置零 corrected value preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rRaw = rRaw) AND (rLoadTimeS = rLoadTimeS) AND (rCreepRatePctPerH = rCreepRatePctPerH) AND (rTempFactor = rTempFactor); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜时长与速率方向闸 duration and rate direction gate
IF (rLoadTimeS < 0.0) OR (rCreepRatePctPerH < 0.0) THEN
    RETURN; // 负时长或负速率属配置非法 a negative duration or rate is an illegal configuration
END_IF
// 段 4｜蠕变量折算与主体补偿 creep quantity and the main compensation
_rRel := rCreepRatePctPerH / DL_HUNDRED * (rLoadTimeS / DL_SEC_PER_HOUR) * rTempFactor; // 相对蠕变量 relative creep quantity
_rCorr := rRaw * (1.0 + _rRel); // 原始读数按蠕变量放大 amplify the raw reading by the creep quantity
IF (_rCorr <> _rCorr) OR (ABS(_rCorr) > 1.0E30) THEN
    RETURN; // 结果非有限拒收 refuse a non finite result
END_IF
rCorrected := _rCorr; // 修正值落定 land the corrected value
bValid := TRUE; // 结果可用 result usable
FC_DL_WeighCreepCompensate := _rCorr; // 函数返回修正值 return the corrected value
END_FUNCTION
