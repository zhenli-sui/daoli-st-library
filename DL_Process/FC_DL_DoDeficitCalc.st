(*
  ============================================================
  组件名 : FC_DL_DoDeficitCalc
  分类   : DL_Process
  功能   : 溶解氧偏差与饱和度计算，按实测值与设定值求欠氧量并双向分档
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_DoDeficitCalc : REAL
VAR_INPUT
    rDoAct_mgL : REAL; // 实测溶解氧 [mg/L] measured dissolved oxygen [mg per litre]
    rDoSp_mgL  : REAL; // 溶解氧设定值 [mg/L] dissolved oxygen set point [mg per litre]
    rDoLow     : REAL; // 偏低判定阈值 [mg/L] low verdict threshold [mg per litre]
    rDoHigh    : REAL; // 偏高判定阈值 [mg/L] high verdict threshold [mg per litre]
END_VAR
VAR_OUTPUT
    rDeficit       : REAL; // 溶解氧欠量，设定减实测 [mg/L] oxygen deficit, set point minus actual [mg per litre]
    rSaturationPct : REAL; // 实测相对设定的百分比 [%] actual relative to the set point [%]
    nStatus        : INT; // 分档 0正常 1偏低 2偏高 [档] status 0 normal, 1 low, 2 high [band]
    bValid         : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_HUNDRED : REAL := 100.0; // 百分制换算系数 percentage scale factor
    DL_EPS_R   : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    _bFin : BOOL := FALSE; // 四输入有限性判定 finiteness verdict of the four inputs
    _rDef : REAL := 0.0; // 欠量中间量 [mg/L] intermediate deficit [mg per litre]
    _rSat : REAL := 0.0; // 百分比中间量 [%] intermediate percentage [%]
    _rLow : REAL := 0.0; // 钳位后的偏低阈值 [mg/L] clamped low threshold [mg per litre]
    _rHigh: REAL := 0.0; // 钳位后的偏高阈值 [mg/L] clamped high threshold [mg per litre]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_DoDeficitCalc := 0.0; // 缺省返回零 default zero return
rDeficit := 0.0; // 欠量预置零 deficit preset to zero
rSaturationPct := 0.0; // 百分比预置零 percentage preset to zero
nStatus := 0; // 分档预置正常 status preset normal
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rDoAct_mgL = rDoAct_mgL) AND (rDoSp_mgL = rDoSp_mgL) AND (rDoLow = rDoLow) AND (rDoHigh = rDoHigh); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜设定值分母闸 set point divisor gate
IF rDoSp_mgL <= DL_EPS_R THEN
    RETURN; // 设定值非正无法折算百分比 a non positive set point cannot carry a percentage
END_IF
// 段 4｜欠量与百分比 deficit and the percentage
_rDef := rDoSp_mgL - rDoAct_mgL; // 设定减实测 set point minus actual
_rSat := rDoAct_mgL / rDoSp_mgL * DL_HUNDRED; // 实测占设定百分比 actual over the set point
rDeficit := _rDef; // 欠量落定 land the deficit
rSaturationPct := _rSat; // 百分比落定 land the percentage
// 段 5｜双向分档判定 directional status verdict
_rLow := rDoLow; // 取偏低阈值 take the low threshold
_rHigh := rDoHigh; // 取偏高阈值 take the high threshold
IF _rLow > _rHigh THEN
    _rLow := rDoHigh; // 阈值倒置时偏低阈值取原偏高 an inverted pair swaps the low threshold
    _rHigh := rDoLow; // 阈值倒置时偏高阈值取原偏低 an inverted pair swaps the high threshold
END_IF
IF rDoAct_mgL < _rLow THEN
    nStatus := 1; // 实测偏低 the reading is too low
ELSIF rDoAct_mgL > _rHigh THEN
    nStatus := 2; // 实测偏高 the reading is too high
ELSE
    nStatus := 0; // 区间内正常 inside the normal band
END_IF
bValid := TRUE; // 结果可用 result usable
FC_DL_DoDeficitCalc := _rDef; // 函数返回欠量 return the deficit
END_FUNCTION
