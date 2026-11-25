(*
  ============================================================
  组件名 : FC_DL_StatsDevSumSq
  分类   : DL_MathData
  功能   : 定长样本的离差平方和、自由度与方差计算，支持外部给定均值
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_StatsDevSumSq : REAL
VAR_INPUT
    aData        : ARRAY[0..31] OF REAL; // 样本数组，定长三十二 [工程单位] sample array of thirty two fixed slots [engineering unit]
    nCount       : INT; // 有效样本数 1~32 [个] effective sample count from one to thirty two [count]
    rMeanGiven   : REAL; // 外部给定的均值 [工程单位] externally supplied mean [engineering unit]
    bUseGivenMean: BOOL; // 真为使用给定均值，假为按样本自算 use the supplied mean when true
END_VAR
VAR_OUTPUT
    rSs    : REAL; // 离差平方和 [工程单位平方] sum of squared deviations [engineering unit squared]
    rDf    : REAL; // 自由度 [个] degrees of freedom [count]
    rVar   : REAL; // 方差 [工程单位平方] variance [engineering unit squared]
    bValid : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_CAP : INT := 32; // 数组容量 [个] array capacity [count]
END_VAR
VAR
    i      : INT := 0; // 遍历游标 [个] walk cursor [count]
    _rMean : REAL := 0.0; // 实际使用的均值 [工程单位] mean actually used [engineering unit]
    _rSum  : REAL := 0.0; // 样本和 [工程单位] sum of the samples [engineering unit]
    _rSs   : REAL := 0.0; // 平方和中间量 [工程单位平方] intermediate sum of squares [engineering unit squared]
    _rDev  : REAL := 0.0; // 单点离差 [工程单位] single deviation [engineering unit]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_StatsDevSumSq := 0.0; // 缺省返回零 default zero return
rSs := 0.0; // 平方和预置零 sum of squares preset to zero
rDf := 0.0; // 自由度预置零 freedom preset to zero
rVar := 0.0; // 方差预置零 variance preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜点数闸与有限闸 count gate and finiteness gate
IF (nCount < 1) OR (nCount > DL_CAP) THEN
    RETURN; // 点数越界即无效 an out of range count is void
END_IF
IF (rMeanGiven <> rMeanGiven) OR ((aData[0] <> aData[0])) THEN
    RETURN; // 均值或首样本非有限即无效 a non finite mean or first sample is void
END_IF
// 段 3｜均值来源选择 the mean source selection
IF bUseGivenMean THEN
    _rMean := rMeanGiven; // 使用外部给定均值 use the supplied mean
ELSE
    _rSum := 0.0; // 样本和清零 clear the sum
    FOR i := 0 TO (nCount - 1) DO
        IF aData[i] <> aData[i] THEN
            RETURN; // 非有限样本拒收 refuse a non finite sample
        END_IF
        _rSum := _rSum + aData[i]; // 样本累加 accumulate the sample
    END_FOR
    _rMean := _rSum / INT_TO_REAL(nCount); // 自算均值，除子为已证正计数 the computed mean over a proven positive count
END_IF
// 段 4｜离差平方和 sum of squared deviations
_rSs := 0.0; // 平方和清零 clear the sum of squares
FOR i := 0 TO (nCount - 1) DO
    IF aData[i] <> aData[i] THEN
        RETURN; // 非有限样本拒收 refuse a non finite sample
    END_IF
    _rDev := aData[i] - _rMean; // 单点离差 single deviation
    _rSs := _rSs + _rDev * _rDev; // 平方累加 accumulate the square
END_FOR
rSs := _rSs; // 平方和落定 land the sum of squares
// 段 5｜自由度与方差自由度闸 freedom and the variance gate
rDf := INT_TO_REAL(nCount - 1); // 自由度取样本数减一 the freedom is the count minus one
IF rDf <= 0.0 THEN
    RETURN; // 自由度非正时方差不可求 a non positive freedom carries no variance
END_IF
rVar := _rSs / rDf; // 方差，除子为已证正自由度 variance over a proven positive freedom
bValid := TRUE; // 结果可用 result usable
FC_DL_StatsDevSumSq := _rSs; // 函数返回离差平方和 return the sum of squares
END_FUNCTION
