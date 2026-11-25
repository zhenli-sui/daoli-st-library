(*
  ============================================================
  组件名 : FC_DL_StatsIqrCalc
  分类   : DL_MathData
  功能   : 定长样本的四分位距与异常栅栏计算，先插入排序再按位置线性插值
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  口径说明 : 分位位置取 (n-1) 法，Q1 位置 0.25×(n-1)、Q3 位置 0.75×(n-1)，
             位置非整数时按相邻两个样本线性插值；栅栏取 Q1-1.5×IQR 与 Q3+1.5×IQR。
             样本数小于二时四分位无定义，本件判无效。
*)

FUNCTION FC_DL_StatsIqrCalc : REAL
VAR_INPUT
    aData  : ARRAY[0..31] OF REAL; // 样本数组，定长三十二 [工程单位] sample array of thirty two fixed slots [engineering unit]
    nCount : INT; // 有效样本数 2~32 [个] effective sample count from two to thirty two [count]
END_VAR
VAR_OUTPUT
    rQ1        : REAL; // 下四分位 [工程单位] lower quartile [engineering unit]
    rQ3        : REAL; // 上四分位 [工程单位] upper quartile [engineering unit]
    rIqr       : REAL; // 四分位距 [工程单位] interquartile range [engineering unit]
    rFenceLow  : REAL; // 下栅栏 [工程单位] lower fence [engineering unit]
    rFenceHigh : REAL; // 上栅栏 [工程单位] upper fence [engineering unit]
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_CAP   : INT := 32; // 数组容量 [个] array capacity [count]
    DL_Q1    : REAL := 0.25; // 下四分位位置系数 lower quartile position factor
    DL_Q3    : REAL := 0.75; // 上四分位位置系数 upper quartile position factor
    DL_FENCE : REAL := 1.5; // 栅栏系数 fence factor
END_VAR
VAR
    aBuf  : ARRAY[0..31] OF REAL; // 排序副本 [工程单位] sorted copy [engineering unit]
    i     : INT := 0; // 外层游标 [个] outer cursor [count]
    j     : INT := 0; // 内层游标 [个] inner cursor [count]
    nIdx  : INT := 0; // 插值左邻下标 [个] left neighbour index [count]
    _rKey : REAL := 0.0; // 插入排序待插值 [工程单位] insertion key [engineering unit]
    _rPos : REAL := 0.0; // 分位位置 [位] quantile position [slot]
    _rFrac: REAL := 0.0; // 位置小数部分 [无量纲] fractional part of the position [dimensionless]
    _rQ1  : REAL := 0.0; // 下四分位中间量 [工程单位] intermediate lower quartile [engineering unit]
    _rQ3  : REAL := 0.0; // 上四分位中间量 [工程单位] intermediate upper quartile [engineering unit]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_StatsIqrCalc := 0.0; // 缺省返回零 default zero return
rQ1 := 0.0; // 下四分位预置零 lower quartile preset to zero
rQ3 := 0.0; // 上四分位预置零 upper quartile preset to zero
rIqr := 0.0; // 四分位距预置零 interquartile range preset to zero
rFenceLow := 0.0; // 下栅栏预置零 lower fence preset to zero
rFenceHigh := 0.0; // 上栅栏预置零 upper fence preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜点数闸 sample count gate
IF (nCount < 2) OR (nCount > DL_CAP) THEN
    RETURN; // 点数越界或不足二即无效 an out of range or a too small count is void
END_IF
// 段 3｜拷贝并插入排序 copy then insertion sort
FOR i := 0 TO (nCount - 1) DO
    IF aData[i] <> aData[i] THEN
        RETURN; // 非有限样本拒收，出口保持零点 refuse a non finite sample
    END_IF
    aBuf[i] := aData[i]; // 逐点拷贝 copy sample by sample
END_FOR
FOR i := 1 TO (nCount - 1) DO
    _rKey := aBuf[i]; // 待插值取当前点 the key is the current sample
    j := i - 1; // 内层游标从左邻起 the inner cursor starts at the left neighbour
    WHILE (j >= 0) AND (aBuf[j] > _rKey) DO
        aBuf[j + 1] := aBuf[j]; // 后移空位 shift right to open a slot
        j := j - 1; // 游标左退 step the cursor left
    END_WHILE
    aBuf[j + 1] := _rKey; // 落位 drop the key in place
END_FOR
// 段 4｜下四分位插值 lower quartile interpolation
_rPos := DL_Q1 * INT_TO_REAL(nCount - 1); // 下四分位位置 lower quartile position
nIdx := REAL_TO_INT(FLOOR(_rPos)); // 左邻下标，先向下取整再转整型 floor then convert to integer
IF nIdx > (nCount - 2) THEN
    nIdx := nCount - 2; // 左邻下标钳位 clamp the left neighbour index
END_IF
_rFrac := _rPos - INT_TO_REAL(nIdx); // 位置小数部分 fractional part of the position
_rQ1 := aBuf[nIdx] + _rFrac * (aBuf[nIdx + 1] - aBuf[nIdx]); // 相邻样本线性插值 linear blend of the neighbours
// 段 5｜上四分位插值 upper quartile interpolation
_rPos := DL_Q3 * INT_TO_REAL(nCount - 1); // 上四分位位置 upper quartile position
nIdx := REAL_TO_INT(FLOOR(_rPos)); // 左邻下标，先向下取整再转整型 floor then convert to integer
IF nIdx > (nCount - 2) THEN
    nIdx := nCount - 2; // 左邻下标钳位 clamp the left neighbour index
END_IF
_rFrac := _rPos - INT_TO_REAL(nIdx); // 位置小数部分 fractional part of the position
_rQ3 := aBuf[nIdx] + _rFrac * (aBuf[nIdx + 1] - aBuf[nIdx]); // 相邻样本线性插值 linear blend of the neighbours
// 段 6｜四分位距与栅栏 interquartile range and the fences
rQ1 := _rQ1; // 下四分位落定 land the lower quartile
rQ3 := _rQ3; // 上四分位落定 land the upper quartile
rIqr := _rQ3 - _rQ1; // 四分位距 interquartile range
rFenceLow := _rQ1 - DL_FENCE * rIqr; // 下栅栏 lower fence
rFenceHigh := _rQ3 + DL_FENCE * rIqr; // 上栅栏 upper fence
bValid := TRUE; // 结果可用 result usable
FC_DL_StatsIqrCalc := rIqr; // 函数返回四分位距 return the range
END_FUNCTION
