(*
  ============================================================
  组件名 : FC_DL_RefSatPressToTemp
  分类   : DL_Device
  功能   : 制冷剂饱和压力转饱和温度，内置 R134a 与 R410A 分段线性表并做区间插值
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  表口径 : 压力为绝对压力 [bar abs]，温度为 [摄氏度]，两行表按 R134a 与 R410A 顺序平铺，
           行内压力严格升序；压力越出表范围时取端点温度并置 bValid 为假。
*)

FUNCTION FC_DL_RefSatPressToTemp : REAL
VAR_INPUT
    rPressBarA    : REAL; // 饱和绝对压力 [bar abs] saturation absolute pressure [bar abs]
    nRefrigerant  : INT; // 制冷剂 1=R134a 2=R410A [代号] refrigerant 1 for R134a and 2 for R410A [code]
END_VAR
VAR_OUTPUT
    rTempC : REAL; // 饱和温度 [摄氏度] saturation temperature [degree celsius]
    bValid : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR CONSTANT
    afPress : ARRAY[0..1, 0..7] OF REAL := [1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 14.0, 18.0, 1.0, 2.0, 4.0, 6.0, 8.0, 10.0, 14.0, 18.0]; // 饱和压力表 [bar abs] saturation pressure table [bar abs]
    afTemp  : ARRAY[0..1, 0..7] OF REAL := [-26.1, -10.1, 8.9, 21.6, 31.3, 39.4, 52.4, 62.5, -51.4, -34.1, -14.1, 0.4, 11.4, 20.5, 34.4, 45.0]; // 饱和温度表 [摄氏度] saturation temperature table [degree celsius]
    DL_IDX_LAST : INT := 7; // 表末下标 last table index
    DL_EPS_R    : REAL := 1.0E-6; // 实数零判定阈值 real zero threshold
END_VAR
VAR
    nRow  : INT := 0; // 表行号 0=R134a 1=R410A [行] table row number [row]
    nSeg  : INT := -1; // 命中区间下标，负为未命中 [段] hit segment index, negative when missing [segment]
    i     : INT := 0; // 区间游标 [段] segment cursor [segment]
    _rSpan: REAL := 0.0; // 区间压力跨度 [bar] segment pressure span [bar]
    _rFrac: REAL := 0.0; // 区间插值比例 [无量纲] interpolation fraction [dimensionless]
    _rT   : REAL := 0.0; // 温度中间量 [摄氏度] intermediate temperature [degree celsius]
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_RefSatPressToTemp := 0.0; // 缺省返回零 default zero return
rTempC := 0.0; // 温度预置零 temperature preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜非有限闸与制冷剂代号闸 finiteness gate and refrigerant code gate
IF (rPressBarA <> rPressBarA) OR (nRefrigerant < 1) OR (nRefrigerant > 2) THEN
    RETURN; // 非有限或代号非法即无效 non finite or an illegal code is void
END_IF
nRow := nRefrigerant - 1; // 行号由代号减一得出 the row index is the code minus one
// 段 3｜区间搜索 segment search over the ascending pressure table
FOR i := 0 TO (DL_IDX_LAST - 1) DO
    IF (rPressBarA >= afPress[nRow, i]) AND (rPressBarA <= afPress[nRow, i + 1]) THEN
        nSeg := i; // 命中升序区间 a segment is hit
    END_IF
END_FOR
// 段 4｜越界端点处理 endpoint handling for the out of table pressures
IF nSeg < 0 THEN
    IF rPressBarA < afPress[nRow, 0] THEN
        rTempC := afTemp[nRow, 0]; // 低于表底取表首温度 a pressure below the table takes the first temperature
    ELSE
        rTempC := afTemp[nRow, DL_IDX_LAST]; // 高于表顶取表末温度 a pressure above the table takes the last temperature
    END_IF
    RETURN; // 越界置无效并输出端点值 the out of table case is void with the endpoint emitted
END_IF
// 段 5｜线性插值 linear interpolation inside the hit segment
_rSpan := afPress[nRow, nSeg + 1] - afPress[nRow, nSeg]; // 区间压力跨度 segment pressure span
IF ABS(_rSpan) < DL_EPS_R THEN
    RETURN; // 跨度近零无法插值 a near zero span cannot interpolate
END_IF
_rFrac := (rPressBarA - afPress[nRow, nSeg]) / _rSpan; // 区间内插值比例 the fraction inside the segment
_rT := afTemp[nRow, nSeg] + _rFrac * (afTemp[nRow, nSeg + 1] - afTemp[nRow, nSeg]); // 端点温度线性插值 linear blend of the two temperatures
rTempC := _rT; // 温度落定 land the temperature
bValid := TRUE; // 结果可用 result usable
FC_DL_RefSatPressToTemp := _rT; // 函数返回饱和温度 return the saturation temperature
END_FUNCTION
