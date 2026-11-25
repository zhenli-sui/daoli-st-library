(* ===========================================================================
   组件名   : FC_DL_StrainBridgeNonlinCorr
   分类     : DL_Device / 桥路非线性修正
   一句话   : 用三次多项式修正大应变下桥路输出的非线性误差，保留原始符号
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fRawStrain 原始应变 [µε]；fK2 二次项系数 [1/µε]；fK3 三次项系数 [1/µε²]
   输出契约 : 返回值 = 修正后应变 [µε]；fCorrTerm 修正量 [µε]；xValid 输入有效
   算法说明 : ε_corr = ε_raw + K2·ε_raw² + K3·ε_raw³；二次项破坏奇对称性，故系数须由标定给定，
              未标定时置 0 即为旁路；输入超过 ±1e6 µε 视为超量程而判无效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainBridgeNonlinCorr : REAL
VAR_INPUT
    fRawStrain : REAL;                 // 原始应变 [µε] | raw strain [µε]
    fK2 : REAL := 0.0;                 // 二次项系数 [1/µε] | quadratic coefficient [1/µε]
    fK3 : REAL := 0.0;                 // 三次项系数 [1/µε²] | cubic coefficient [1/µε^2]
    fRangeLimit : REAL := 1000000.0;   // 量程上限 [µε] | range limit [µε]
END_VAR
VAR_OUTPUT
    fCorrTerm : REAL;                  // 修正量 [µε] | correction term [µε]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fSq : REAL;                       // 应变平方 [(µε)²] | squared strain
    _fCub : REAL;                      // 应变立方 [(µε)³] | cubed strain
    _fOut : REAL;                      // 修正结果 [µε] | corrected result [µε]
END_VAR

// ---- 输出预置 ----
fCorrTerm := 0.0;
xValid := FALSE;
FC_DL_StrainBridgeNonlinCorr := 0.0;

// ---- 非有限值拦截 ----
IF (fRawStrain <> fRawStrain) OR ((fRawStrain - fRawStrain) <> (fRawStrain - fRawStrain)) THEN
    RETURN;
END_IF
IF (fK2 <> fK2) OR ((fK2 - fK2) <> (fK2 - fK2)) THEN
    RETURN;
END_IF
IF (fK3 <> fK3) OR ((fK3 - fK3) <> (fK3 - fK3)) THEN
    RETURN;
END_IF

// ---- 量程守卫：上限非正或超量程一律判无效，避免三次项数值爆炸 ----
IF (fRangeLimit <= 0.0) THEN
    RETURN;
END_IF
IF ABS(fRawStrain) > fRangeLimit THEN
    RETURN;
END_IF

// ---- 多项式修正：先算平方与立方再合成，避免重复乘法产生不同舍入路径 ----
_fSq := fRawStrain * fRawStrain;
_fCub := _fSq * fRawStrain;
fCorrTerm := fK2 * _fSq + fK3 * _fCub;
_fOut := fRawStrain + fCorrTerm;

// ---- 结果二次守卫：修正后仍须在量程内，否则判无效 ----
IF ABS(_fOut) > (fRangeLimit * 2.0) THEN
    xValid := FALSE;
    RETURN;
END_IF

xValid := TRUE;
FC_DL_StrainBridgeNonlinCorr := _fOut;
END_FUNCTION
