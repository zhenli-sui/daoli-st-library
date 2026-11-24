(*
  ============================================================
  组件名 : FC_DL_StatsGeoMeanCalc
  分类   : DL_MathData
  功能   : 定长样本的几何平均值计算，非正值剔除后按自然对数均值再取指数
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C1
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_StatsGeoMeanCalc : REAL
VAR_INPUT
    aData  : ARRAY[0..31] OF REAL; // 样本数组，定长三十二 [工程单位] sample array of thirty two fixed slots [engineering unit]
    nCount : INT; // 有效样本数 1~32 [个] effective sample count from one to thirty two [count]
    rMinPos: REAL; // 正样本下限，非正或非有限时回默认值 [工程单位] positive sample floor, non positive values fall back to the default [engineering unit]
END_VAR
VAR_OUTPUT
    rGeoMean : REAL; // 几何平均值 [工程单位] geometric mean [engineering unit]
    nSkipped : INT; // 被剔除的样本数 [个] skipped sample count [count]
    bValid   : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    DL_CAP  : INT := 32; // 数组容量 [个] array capacity [count]
    DL_POS_FLOOR : REAL := 1.0E-9; // 正样本下限默认值 default positive sample floor
END_VAR
VAR
    i      : INT := 0; // 遍历游标 [个] walk cursor [count]
    nOk    : INT := 0; // 参与取对数的样本数 [个] sample count entering the logarithm [count]
    _rSumLn: REAL := 0.0; // 自然对数和 [无量纲] sum of natural logarithms [dimensionless]
    _rFloor: REAL := 0.0; // 钳位后的正样本下限 [工程单位] clamped positive sample floor [engineering unit]
    _rGeo  : REAL := 0.0; // 几何均值中间量 [工程单位] intermediate geometric mean [engineering unit]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_StatsGeoMeanCalc := 0.0; // 缺省返回零 default zero return
rGeoMean := 0.0; // 几何均值预置零 geometric mean preset to zero
nSkipped := 0; // 剔除数预置零 skipped count preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜点数闸与下限整形 count gate and floor reshape
IF (nCount < 1) OR (nCount > DL_CAP) THEN
    RETURN; // 点数越界即无效 an out of range count is void
END_IF
_rFloor := rMinPos; // 取入参正样本下限 take the positive floor input
IF _rFloor <> _rFloor THEN
    _rFloor := DL_POS_FLOOR; // 非有限下限回默认值 a non finite floor falls back to the default
ELSIF _rFloor <= 0.0 THEN
    _rFloor := DL_POS_FLOOR; // 非正下限回默认值 a non positive floor falls back to the default
END_IF
// 段 3｜剔除与对数累加 skip the ineligible samples and accumulate logarithms
FOR i := 0 TO (nCount - 1) DO
    IF (aData[i] <> aData[i]) OR (aData[i] < _rFloor) THEN
        nSkipped := nSkipped + 1; // 非有限或非正样本剔除 skip a non finite or a non positive sample
    ELSE
        _rSumLn := _rSumLn + LN(aData[i]); // 自然对数累加 accumulate the natural logarithm
        nOk := nOk + 1; // 有效样本计数 count the usable sample
    END_IF
END_FOR
// 段 4｜全剔除闸 the all skipped gate
IF nOk <= 0 THEN
    RETURN; // 无正样本时几何均值无定义 an all skipped set has no geometric mean
END_IF
// 段 5｜指数还原与出口 exponent restore and the exit
_rGeo := EXP(_rSumLn / INT_TO_REAL(nOk)); // 对数均值取指数，除子为已证正计数 exponent of the mean logarithm
IF (_rGeo <> _rGeo) OR (ABS(_rGeo) > 1.0E30) THEN
    RETURN; // 结果非有限拒收 refuse a non finite result
END_IF
rGeoMean := _rGeo; // 几何均值落定 land the geometric mean
bValid := TRUE; // 结果可用 result usable
FC_DL_StatsGeoMeanCalc := _rGeo; // 函数返回几何均值 return the geometric mean
END_FUNCTION
