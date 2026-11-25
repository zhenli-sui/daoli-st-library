(* ===========================================================================
   组件名   : FC_DL_StrainBridgeExcitationComp
   分类     : DL_Device / 桥压激励补偿
   一句话   : 按实测激励电压与额定值之比归一化桥路输出，消除激励波动引起的比例误差
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fRawValue 原始读数（已换算值）；fExcMeasV 实测激励电压 [V]
              fExcRatedV 额定激励电压 [V]；fRatioMin/fRatioMax 比例合理区间
   输出契约 : 返回值 = 归一化后读数；fRatio 归一化比例（额定/实测）
              xValid 输入有效（比例须落在合理区间内）
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainBridgeExcitationComp : REAL
VAR_INPUT
    fRawValue : REAL;                  // 原始读数 | raw reading
    fExcMeasV : REAL := 5.0;           // 实测激励电压 [V] | measured excitation [V]
    fExcRatedV : REAL := 5.0;          // 额定激励电压 [V] | rated excitation [V]
    fRatioMin : REAL := 0.5;           // 比例下限 | ratio lower bound
    fRatioMax : REAL := 2.0;           // 比例上限 | ratio upper bound
END_VAR
VAR_OUTPUT
    fRatio : REAL;                     // 归一化比例 | normalization ratio
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fR : REAL;                        // 比例工作值 | ratio working value
    _fOut : REAL;                      // 归一化结果 | normalized result
END_VAR

// ---- 输出预置 ----
fRatio := 1.0;
xValid := FALSE;
FC_DL_StrainBridgeExcitationComp := 0.0;

// ---- 非有限值拦截 ----
IF (fRawValue <> fRawValue) OR ((fRawValue - fRawValue) <> (fRawValue - fRawValue)) THEN
    RETURN;
END_IF
IF (fExcMeasV <> fExcMeasV) OR ((fExcMeasV - fExcMeasV) <> (fExcMeasV - fExcMeasV)) THEN
    RETURN;
END_IF
IF (fExcRatedV <> fExcRatedV) OR ((fExcRatedV - fExcRatedV) <> (fExcRatedV - fExcRatedV)) THEN
    RETURN;
END_IF

// ---- 防除零：实测与额定激励都必须显著非零 ----
IF (ABS(fExcMeasV) < 0.000000001) OR (ABS(fExcRatedV) < 0.000000001) THEN
    RETURN;
END_IF

// ---- 比例 = 额定 / 实测 ----
_fR := fExcRatedV / fExcMeasV;                     // 分母已守卫
fRatio := _fR;

// ---- 合理性区间守卫：比例越界说明激励异常，宁判无效也不外推 ----
IF (fRatioMin <= 0.0) OR (fRatioMax <= fRatioMin) THEN
    RETURN;
END_IF
IF (_fR < fRatioMin) OR (_fR > fRatioMax) THEN
    RETURN;
END_IF

_fOut := fRawValue * _fR;
xValid := TRUE;
FC_DL_StrainBridgeExcitationComp := _fOut;
END_FUNCTION
