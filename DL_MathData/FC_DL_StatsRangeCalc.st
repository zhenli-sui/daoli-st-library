(*
  ============================================================
  组件名 : FC_DL_StatsRangeCalc
  分类   : DL_MathData
  功能   : 定长样本的极差统计，返回最小值、最大值与极差
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_StatsRangeCalc : REAL
VAR_INPUT
    aData  : ARRAY[0..31] OF REAL; // 样本数组，定长三十二 [工程单位] sample array of thirty two fixed slots [engineering unit]
    nCount : INT; // 有效样本数 1~32 [个] effective sample count from one to thirty two [count]
END_VAR
VAR_OUTPUT
    rRange : REAL; // 极差 [工程单位] range [engineering unit]
    rMin   : REAL; // 最小值 [工程单位] minimum [engineering unit]
    rMax   : REAL; // 最大值 [工程单位] maximum [engineering unit]
    nUsed  : INT; // 实际参与统计的点数 [个] point count actually used [count]
    bValid : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_CAP  : INT := 32; // 数组容量 [个] array capacity [count]
END_VAR
VAR
    i     : INT := 0; // 遍历游标 [个] walk cursor [count]
    _rMin : REAL := 0.0; // 最小值中间量 [工程单位] intermediate minimum [engineering unit]
    _rMax : REAL := 0.0; // 最大值中间量 [工程单位] intermediate maximum [engineering unit]
    _bFin : BOOL := FALSE; // 当前样本有限性判定 finiteness verdict of the current sample
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_StatsRangeCalc := 0.0; // 缺省返回零 default zero return
rRange := 0.0; // 极差预置零 range preset to zero
rMin := 0.0; // 最小值预置零 minimum preset to zero
rMax := 0.0; // 最大值预置零 maximum preset to zero
nUsed := 0; // 参与点数预置零 used count preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜点数闸 sample count gate
IF (nCount < 1) OR (nCount > DL_CAP) THEN
    RETURN; // 点数越界即无效 an out of range count is void
END_IF
// 段 3｜初值取首样本 the first sample seeds both bounds
_bFin := (aData[0] = aData[0]); // 首样本自反判定 self comparison of the first sample
IF NOT _bFin THEN
    RETURN; // 首样本非有限即无效 a non finite seed is void
END_IF
_rMin := aData[0]; // 最小值初值取首样本 the minimum starts at the first sample
_rMax := aData[0]; // 最大值初值取首样本 the maximum starts at the first sample
// 段 4｜单趟遍历求双向极值 single pass over both bounds
FOR i := 1 TO (nCount - 1) DO
    IF aData[i] <> aData[i] THEN
        RETURN; // 非有限样本拒收，出口回零点 refuse a non finite sample and return the zero outlet
    END_IF
    IF aData[i] < _rMin THEN
        _rMin := aData[i]; // 刷新最小值 refresh the minimum
    END_IF
    IF aData[i] > _rMax THEN
        _rMax := aData[i]; // 刷新最大值 refresh the maximum
    END_IF
END_FOR
// 段 5｜极差与出口 range and the exit
rMin := _rMin; // 最小值落定 land the minimum
rMax := _rMax; // 最大值落定 land the maximum
rRange := _rMax - _rMin; // 极差为最大值减最小值 the range is the maximum minus the minimum
nUsed := nCount; // 参与点数落定 land the used count
bValid := TRUE; // 结果可用 result usable
FC_DL_StatsRangeCalc := rRange; // 函数返回极差 return the range
END_FUNCTION
