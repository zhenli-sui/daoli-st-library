(* ===========================================================================
   组件名   : FC_DL_StrainBridgeMillivolt
   分类     : DL_Device / 应变桥信号换算
   一句话   : 由激励电压与实测差分电压算桥路输出 mV/V 与等效微应变
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fExcitationV 桥路激励电压 [V]；fDiffV 实测差分电压 [mV]
              fGaugeFactor 应变片灵敏系数（典型 2.0）
   输出契约 : 返回值 = 桥路输出 [mV/V]；fMvPerV 同返回值（显式输出）
              fMicroStrain 等效微应变 [µε]（= mV/V × 1000 / GF）；xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainBridgeMillivolt : REAL
VAR_INPUT
    fExcitationV : REAL := 5.0;        // 桥路激励电压 [V] | bridge excitation [V]
    fDiffV : REAL;                     // 实测差分电压 [mV] | measured differential [mV]
    fGaugeFactor : REAL := 2.0;        // 应变片灵敏系数 | gauge factor
END_VAR
VAR_OUTPUT
    fMvPerV : REAL;                    // 桥路输出 [mV/V] | bridge output [mV/V]
    fMicroStrain : REAL;               // 等效微应变 [µε] | equivalent micro strain [µε]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fRatio : REAL;                    // 差分/激励 比值 | differential over excitation
END_VAR

// ---- 输出预置 ----
fMvPerV := 0.0;
fMicroStrain := 0.0;
xValid := FALSE;
FC_DL_StrainBridgeMillivolt := 0.0;

// ---- 非有限值拦截 ----
IF (fExcitationV <> fExcitationV) OR ((fExcitationV - fExcitationV) <> (fExcitationV - fExcitationV)) THEN
    RETURN;
END_IF
IF (fDiffV <> fDiffV) OR ((fDiffV - fDiffV) <> (fDiffV - fDiffV)) THEN
    RETURN;
END_IF
IF (fGaugeFactor <> fGaugeFactor) OR ((fGaugeFactor - fGaugeFactor) <> (fGaugeFactor - fGaugeFactor)) THEN
    RETURN;
END_IF

// ---- 防除零：激励电压与灵敏系数必须显著非零 ----
IF (ABS(fExcitationV) < 0.000000001) OR (ABS(fGaugeFactor) < 0.000000001) THEN
    RETURN;
END_IF

// ---- mV/V = 差分电压 [mV] / 激励电压 [V] ----
_fRatio := fDiffV / fExcitationV;                  // 分母已守卫
fMvPerV := _fRatio;

// ---- 微应变 = (mV/V) × 1000 / GF，全桥条件下 GF=2 时 1 mV/V ≈ 500 µε ----
fMicroStrain := _fRatio * 1000.0 / fGaugeFactor;   // 分母已守卫

xValid := TRUE;
FC_DL_StrainBridgeMillivolt := _fRatio;
END_FUNCTION
