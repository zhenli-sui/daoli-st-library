(* ===========================================================================
   组件名   : FC_DL_StrainMultiPointCalib
   分类     : DL_Device / 应变多点标定插值
   一句话   : 按标定点表分段线性插值反算工程量，段号钳位并对表外输入做平段外推
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fRaw 原始读数 [µε]；afRawPT 标定原始值表 [1..8]；afEngPT 标定工程量表 [1..8]
              iCount 有效点数 2..8（自动钳位）
   输出契约 : 返回值 = 工程量；iSeg 命中的段号（1..iCount−1）；fRawClamped 钳位后原始值
              xValid 表数据有效（升序且有限）
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainMultiPointCalib : REAL
VAR_INPUT
    fRaw : REAL;                       // 原始读数 [µε] | raw reading [µε]
    afRawPT : ARRAY[1..8] OF REAL;     // 标定原始值表 | calibration raw points
    afEngPT : ARRAY[1..8] OF REAL;     // 标定工程量表 | calibration engineering points
    iCount : INT := 8;                 // 有效点数 2..8 | valid point count 2..8
END_VAR
VAR_OUTPUT
    iSeg : INT;                        // 命中段号 | hit segment index
    fRawClamped : REAL;                // 钳位后原始值 [µε] | clamped raw value [µε]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _iN : INT;                         // 钳位后点数 | clamped point count
    _i : INT;                          // 循环下标 | loop index
    _fDen : REAL;                      // 段宽 | segment width
    _fSlope : REAL;                    // 段斜率 | segment slope
    _fOut : REAL;                      // 插值结果 | interpolation result
    _xMono : BOOL;                     // 表单调升序标志 | monotonic ascending flag
END_VAR

// ---- 输出预置 ----
iSeg := 1;
fRawClamped := 0.0;
xValid := FALSE;
FC_DL_StrainMultiPointCalib := 0.0;

// ---- 非有限值拦截 ----
IF (fRaw <> fRaw) OR ((fRaw - fRaw) <> (fRaw - fRaw)) THEN
    RETURN;
END_IF

// ---- 点数钳位：至少 2 点，最多 8 点 ----
_iN := iCount;
IF _iN < 2 THEN
    _iN := 2;
ELSIF _iN > 8 THEN
    _iN := 8;
END_IF

// ---- 表数据校验：全部有限且原始值严格升序（插值前提） ----
_xMono := TRUE;
_i := 1;
WHILE _i <= _iN DO
    IF (afRawPT[_i] <> afRawPT[_i]) OR ((afRawPT[_i] - afRawPT[_i]) <> (afRawPT[_i] - afRawPT[_i])) THEN
        _xMono := FALSE;
    END_IF
    IF (afEngPT[_i] <> afEngPT[_i]) OR ((afEngPT[_i] - afEngPT[_i]) <> (afEngPT[_i] - afEngPT[_i])) THEN
        _xMono := FALSE;
    END_IF
    IF _i >= 2 THEN
        IF (afRawPT[_i] - afRawPT[_i - 1]) <= 0.000000001 THEN
            _xMono := FALSE;                       // 非严格升序即判表非法
        END_IF
    END_IF
    _i := _i + 1;
END_WHILE
IF NOT _xMono THEN
    RETURN;
END_IF

// ---- 输入钳位到标定区间：表外输入按平段外推，不外插 ----
_fOut := fRaw;
IF fRaw < afRawPT[1] THEN
    _fOut := afRawPT[1];
ELSIF fRaw > afRawPT[_iN] THEN
    _fOut := afRawPT[_iN];
END_IF
fRawClamped := _fOut;

// ---- 定位命中段：段号限制在 1.._iN−1，防数组越界 ----
iSeg := 1;
_i := 1;
WHILE _i <= (_iN - 1) DO
    IF (_fOut >= afRawPT[_i]) AND (_fOut <= afRawPT[_i + 1]) THEN
        iSeg := _i;                                // 命中区间 [i, i+1]
    END_IF
    _i := _i + 1;
END_WHILE
IF iSeg < 1 THEN
    iSeg := 1;
ELSIF iSeg > (_iN - 1) THEN
    iSeg := _iN - 1;                               // 下标钳位
END_IF

// ---- 分段线性插值 ----
_fDen := afRawPT[iSeg + 1] - afRawPT[iSeg];
IF ABS(_fDen) < 0.000000001 THEN
    _fSlope := 0.0;                                // 段宽为零则退化为平段，避免除零
ELSE
    _fSlope := (afEngPT[iSeg + 1] - afEngPT[iSeg]) / _fDen;   // 分母已守卫
END_IF
_fOut := afEngPT[iSeg] + (_fOut - afRawPT[iSeg]) * _fSlope;

xValid := TRUE;
FC_DL_StrainMultiPointCalib := _fOut;
END_FUNCTION
