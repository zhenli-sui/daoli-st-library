(*
  ============================================================
  组件名 : FC_DL_WeighBatchYieldCalc
  分类   : DL_Process
  功能   : 批次实际投料与理论投料的收得率百分比计算与公差判定
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighBatchYieldCalc : REAL
VAR_INPUT
    rActualFeed  : REAL; // 实际投料量 [kg] actual feed quantity [kg]
    rTheoryFeed  : REAL; // 理论投料量 [kg] theoretical feed quantity [kg]
    rTolPct      : REAL; // 收得率公差 [%] yield tolerance [%]
END_VAR
VAR_OUTPUT
    rYieldPct : REAL; // 收得率 [%] yield percentage [%]
    bInTol    : BOOL; // 收得率在公差内标志 yield inside tolerance flag
    bValid    : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_EPS_R : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
    DL_HUNDRED : REAL := 100.0; // 百分制换算系数 percentage scale factor
END_VAR
VAR
    _bFin : BOOL := FALSE; // 两实数输入有限性判定 finiteness verdict of both real inputs
    _rTol : REAL := 0.0; // 钳位后的公差 [%] clamped tolerance [%]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighBatchYieldCalc := 0.0; // 缺省返回零 default zero return
rYieldPct := 0.0; // 收得率预置零 yield preset to zero
bInTol := FALSE; // 公差内标志预置假 tolerance flag preset false
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rActualFeed = rActualFeed) AND (rTheoryFeed = rTheoryFeed) AND (rTolPct = rTolPct); // 三输入自反判定 self comparison of the three inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜理论投料量分母闸 theoretical feed divisor gate
IF rTheoryFeed <= DL_EPS_R THEN
    RETURN; // 理论量非正无法折算收得率 a non positive theory cannot carry a yield
END_IF
// 段 4｜收得率与公差判定 yield computation and the tolerance verdict
rYieldPct := rActualFeed / rTheoryFeed * DL_HUNDRED; // 收得率百分比 yield percentage
_rTol := rTolPct; // 取入参公差 take the tolerance input
IF _rTol < 0.0 THEN
    _rTol := ABS(_rTol); // 负公差取幅值 a negative tolerance becomes its magnitude
END_IF
bInTol := ABS(rYieldPct - DL_HUNDRED) <= _rTol; // 对百分之百的双向公差带 symmetric tolerance band around one hundred percent
bValid := TRUE; // 结果可用 result usable
FC_DL_WeighBatchYieldCalc := rYieldPct; // 函数返回收得率 return the yield
END_FUNCTION
