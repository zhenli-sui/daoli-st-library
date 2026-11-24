(*
  ============================================================
  组件名 : FC_DL_WaterRecoveryRatio
  分类   : DL_Process
  功能   : 水处理系统回收率计算，含进料产水浓水三流股的物料平衡校核
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WaterRecoveryRatio : REAL
VAR_INPUT
    rPermeate_m3h        : REAL; // 产水流量 [m3/h] permeate flow [m3 per hour]
    rFeed_m3h            : REAL; // 进料流量 [m3/h] feed flow [m3 per hour]
    rConc_m3h            : REAL; // 浓水流量 [m3/h] concentrate flow [m3 per hour]
    bCheckMassBalance    : BOOL; // 真为启用物料平衡校核 enable the mass balance check when true
END_VAR
VAR_OUTPUT
    rRecoveryPct  : REAL; // 回收率 [%] recovery percentage [%]
    rMassBalErrPct: REAL; // 物料平衡偏差 [%] mass balance error [%]
    bValid        : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_HUNDRED   : REAL := 100.0; // 百分制换算系数 percentage scale factor
    DL_BAL_LIMIT : REAL := 5.0; // 物料平衡允许偏差 [%] admissible balance error [%]
    DL_EPS_R     : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin : BOOL := FALSE; // 三实数输入有限性判定 finiteness verdict of the three real inputs
    _rRec : REAL := 0.0; // 回收率中间量 [%] intermediate recovery [%]
    _rBal : REAL := 0.0; // 平衡偏差中间量 [%] intermediate balance error [%]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WaterRecoveryRatio := 0.0; // 缺省返回零 default zero return
rRecoveryPct := 0.0; // 回收率预置零 recovery preset to zero
rMassBalErrPct := 0.0; // 平衡偏差预置零 balance error preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rPermeate_m3h = rPermeate_m3h) AND (rFeed_m3h = rFeed_m3h) AND (rConc_m3h = rConc_m3h); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜进料分母闸与负流量闸 feed divisor gate and negative flow gate
IF rFeed_m3h <= DL_EPS_R THEN
    RETURN; // 进料非正无法折算回收率 a non positive feed cannot carry a recovery
END_IF
IF (rPermeate_m3h < 0.0) OR (rConc_m3h < 0.0) THEN
    RETURN; // 负流量属采集异常 a negative flow is a measurement fault
END_IF
// 段 4｜回收率与物料平衡 recovery and the mass balance
_rRec := rPermeate_m3h / rFeed_m3h * DL_HUNDRED; // 产水占进料百分比 permeate over feed as a percentage
_rBal := (rFeed_m3h - rPermeate_m3h - rConc_m3h) / rFeed_m3h * DL_HUNDRED; // 三流股闭合偏差 closure error of the three streams
rRecoveryPct := _rRec; // 回收率落定 land the recovery
rMassBalErrPct := _rBal; // 平衡偏差落定 land the balance error
// 段 5｜按需物料平衡校核 conditional mass balance check
IF bCheckMassBalance AND (ABS(_rBal) > DL_BAL_LIMIT) THEN
    RETURN; // 平衡超差判无效 an excessive balance error is void
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_WaterRecoveryRatio := _rRec; // 函数返回回收率 return the recovery
END_FUNCTION
