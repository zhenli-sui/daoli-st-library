(*
  ============================================================
  组件名 : FC_DL_StatsPooledStd
  分类   : DL_MathData
  功能   : 两组样本的合并方差与合并标准差计算，按自由度加权
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_StatsPooledStd : REAL
VAR_INPUT
    rVar1 : REAL; // 第一组样本方差 [工程单位平方] variance of the first group [engineering unit squared]
    rVar2 : REAL; // 第二组样本方差 [工程单位平方] variance of the second group [engineering unit squared]
    n1    : INT; // 第一组样本数 [个] first group sample count [count]
    n2    : INT; // 第二组样本数 [个] second group sample count [count]
END_VAR
VAR_OUTPUT
    rPooledVar : REAL; // 合并方差 [工程单位平方] pooled variance [engineering unit squared]
    rPooledStd : REAL; // 合并标准差 [工程单位] pooled standard deviation [engineering unit]
    nDf        : INT; // 合并自由度 [个] pooled degrees of freedom [count]
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    _bFin : BOOL := FALSE; // 两实数输入有限性判定 finiteness verdict of both real inputs
    _rNum : REAL := 0.0; // 自由度加权分子 [工程单位平方] weighted numerator [engineering unit squared]
    _rVar : REAL := 0.0; // 合并方差中间量 [工程单位平方] intermediate pooled variance [engineering unit squared]
    _rStd : REAL := 0.0; // 合并标准差中间量 [工程单位] intermediate pooled deviation [engineering unit]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_StatsPooledStd := 0.0; // 缺省返回零 default zero return
rPooledVar := 0.0; // 合并方差预置零 pooled variance preset to zero
rPooledStd := 0.0; // 合并标准差预置零 pooled deviation preset to zero
nDf := 0; // 自由度预置零 degrees of freedom preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸 finiteness gate
_bFin := (rVar1 = rVar1) AND (rVar2 = rVar2); // 两输入自反判定 self comparison of both inputs
IF NOT _bFin THEN
    RETURN; // 非有限即无效 non finite means invalid
END_IF
// 段 3｜方差方向闸与样本数闸 variance direction gate and count gate
IF (rVar1 < 0.0) OR (rVar2 < 0.0) THEN
    RETURN; // 负方差属计算异常 a negative variance is an illegal input
END_IF
IF (n1 < 1) OR (n2 < 1) THEN
    RETURN; // 组样本数非正无法加权 a non positive group count cannot be weighted
END_IF
// 段 4｜自由度与合并方差 degrees of freedom and the pooled variance
nDf := n1 + n2 - 2; // 合并自由度 pooled degrees of freedom
IF nDf <= 0 THEN
    RETURN; // 自由度非正无法求方差 a non positive freedom cannot carry a variance
END_IF
_rNum := INT_TO_REAL(n1 - 1) * rVar1 + INT_TO_REAL(n2 - 1) * rVar2; // 自由度加权分子 weighted numerator
_rVar := _rNum / INT_TO_REAL(nDf); // 合并方差，除子已证为正 pooled variance over a proven positive divisor
rPooledVar := _rVar; // 合并方差落定 land the pooled variance
// 段 5｜合并标准差与出口 pooled deviation and the exit
_rStd := SQRT(_rVar); // 方差开方得标准差 the square root of the variance
rPooledStd := _rStd; // 合并标准差落定 land the pooled deviation
bValid := TRUE; // 结果可用 result usable
FC_DL_StatsPooledStd := _rStd; // 函数返回合并标准差 return the pooled deviation
END_FUNCTION
