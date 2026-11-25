(*
  ============================================================
  组件名 : FC_DL_RefSatTempToPress
  分类   : DL_Device
  功能   : 制冷剂饱和温度转饱和压力，内置 R134a 与 R410A 分段线性表并做区间插值
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  表口径 : 与压力查温度件同源的两张表，按温度升序重排后以温度为自变量插值压力；
           温度为绝对压力 [bar abs] 输出，温度越出表范围时取端点压力并置 bValid 为假。
*)

FUNCTION FC_DL_RefSatTempToPress : REAL
VAR_INPUT
    rTempC       : REAL; // 饱和温度 [摄氏度] saturation temperature [degree celsius]
    nRefrigerant : INT; // 制冷剂 1=R134a 2=R410A [代号] refrigerant 1 for R134a and 2 for R410A [code]
END_VAR
VAR_OUTPUT
    rPressBarA : REAL; // 饱和绝对压力 [bar abs] saturation absolute pressure [bar abs]
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    afTemp  : ARRAY[0..1, 0..7] OF REAL := [-26.1, -10.1, 8.9, 21.6, 31.3, 39.4, 52.4, 62.5, -51.4, -34.1, -14.1, 0.4, 11.4, 20.5, 34.4, 45.0]; // 饱和温度表，行内升序 [摄氏度] saturation temperature table ascending inside each row [degree celsius]
    afPress : ARRAY[0..1, 0..7] OF REAL := [1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 14.0, 18.0, 1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 14.0, 18.0]; // 饱和压力表 [bar abs] saturation pressure table [bar abs]
    DL_IDX_LAST : INT := 7; // 表末下标 last table index
    DL_EPS_R    : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    nRow  : INT := 0; // 表行号 0=R134a 1=R410A [行] table row number [row]
    nSeg  : INT := -1; // 命中区间下标，负为未命中 [段] hit segment index, negative when missing [segment]
    i     : INT := 0; // 区间游标 [段] segment cursor [segment]
    _rSpan: REAL := 0.0; // 区间温度跨度 [K] segment temperature span [kelvin]
    _rFrac: REAL := 0.0; // 区间插值比例 [无量纲] interpolation fraction [dimensionless]
    _rP   : REAL := 0.0; // 压力中间量 [bar abs] intermediate pressure [bar abs]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefSatTempToPress := 0.0; // 缺省返回零 default zero return
rPressBarA := 0.0; // 压力预置零 pressure preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸与制冷剂代号闸 finiteness gate and refrigerant code gate
IF (rTempC <> rTempC) OR (nRefrigerant < 1) OR (nRefrigerant > 2) THEN
    RETURN; // 非有限或代号非法即无效 non finite or an illegal code is void
END_IF
nRow := nRefrigerant - 1; // 行号由代号减一得出 the row index is the code minus one
// 段 3｜区间搜索 segment search over the ascending temperature table
FOR i := 0 TO (DL_IDX_LAST - 1) DO
    IF (rTempC >= afTemp[nRow, i]) AND (rTempC <= afTemp[nRow, i + 1]) THEN
        nSeg := i; // 命中升序区间 a segment is hit
    END_IF
END_FOR
// 段 4｜越界端点处理 endpoint handling for the out of table temperatures
IF nSeg < 0 THEN
    IF rTempC < afTemp[nRow, 0] THEN
        rPressBarA := afPress[nRow, 0]; // 低于表底取表首压力 a temperature below the table takes the first pressure
    ELSE
        rPressBarA := afPress[nRow, DL_IDX_LAST]; // 高于表顶取表末压力 a temperature above the table takes the last pressure
    END_IF
    RETURN; // 越界置无效并输出端点值 the out of table case is void with the endpoint emitted
END_IF
// 段 5｜线性插值 linear interpolation inside the hit segment
_rSpan := afTemp[nRow, nSeg + 1] - afTemp[nRow, nSeg]; // 区间温度跨度 segment temperature span
IF ABS(_rSpan) < DL_EPS_R THEN
    RETURN; // 跨度近零无法插值 a near zero span cannot interpolate
END_IF
_rFrac := (rTempC - afTemp[nRow, nSeg]) / _rSpan; // 区间内插值比例 the fraction inside the segment
_rP := afPress[nRow, nSeg] + _rFrac * (afPress[nRow, nSeg + 1] - afPress[nRow, nSeg]); // 端点压力线性插值 linear blend of the two pressures
rPressBarA := _rP; // 压力落定 land the pressure
bValid := TRUE; // 结果可用 result usable
FC_DL_RefSatTempToPress := _rP; // 函数返回饱和压力 return the saturation pressure
END_FUNCTION
