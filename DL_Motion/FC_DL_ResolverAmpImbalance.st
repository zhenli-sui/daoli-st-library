(* ===========================================================================
   组件名   : FC_DL_ResolverAmpImbalance
   分类     : DL_Motion / 旋转变压器幅值不平衡
   一句话   : 计算 sin/cos 两路幅值不平衡度百分比并判定是否超限
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fSinAmp 正弦路峰值幅值 [V]；fCosAmp 余弦路峰值幅值 [V]
              fLimitPct 不平衡度限值 [%]
   输出契约 : 返回值 = 不平衡度 [%]（|A−B| / 均值 × 100）
              xOverLimit 是否超限；xValid 输入有效；fMeanAmp 两路均值 [V]
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverAmpImbalance : REAL
VAR_INPUT
    fSinAmp : REAL;                    // 正弦路峰值幅值 [V] | sine channel amplitude [V]
    fCosAmp : REAL;                    // 余弦路峰值幅值 [V] | cosine channel amplitude [V]
    fLimitPct : REAL := 5.0;           // 不平衡度限值 [%] | imbalance limit [%]
END_VAR
VAR_OUTPUT
    xOverLimit : BOOL;                 // 不平衡超限标志 | imbalance over limit
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
    fMeanAmp : REAL;                   // 两路均值幅值 [V] | mean amplitude [V]
END_VAR
VAR
    _fSum : REAL;                      // 两路幅值之和 [V] | sum of amplitudes [V]
    _fDiff : REAL;                      // 两路幅值之差 [V] | difference of amplitudes [V]
    _fPct : REAL;                      // 不平衡度 [%] | imbalance [%]
END_VAR

// ---- 输出预置：防止调用方读到未初始化值 ----
xOverLimit := FALSE;
xValid := FALSE;
fMeanAmp := 0.0;
_fPct := 0.0;
FC_DL_ResolverAmpImbalance := 0.0;

// ---- 非有限值拦截 ----
IF (fSinAmp <> fSinAmp) OR ((fSinAmp - fSinAmp) <> (fSinAmp - fSinAmp)) THEN
    RETURN;
END_IF
IF (fCosAmp <> fCosAmp) OR ((fCosAmp - fCosAmp) <> (fCosAmp - fCosAmp)) THEN
    RETURN;
END_IF
IF (fLimitPct <> fLimitPct) OR ((fLimitPct - fLimitPct) <> (fLimitPct - fLimitPct)) THEN
    RETURN;
END_IF

_fSum := ABS(fSinAmp) + ABS(fCosAmp);
fMeanAmp := _fSum * 0.5;

// ---- 零幅值保护：均值为零时不平衡度无定义，判无效 ----
IF fMeanAmp > 0.000000001 THEN
    _fDiff := ABS(ABS(fSinAmp) - ABS(fCosAmp));
    _fPct := _fDiff / fMeanAmp * 100.0;            // 分母已守卫
    xValid := TRUE;
    IF fLimitPct > 0.0 THEN
        xOverLimit := (_fPct > fLimitPct);         // 用大于比较，不做浮点等值判定
    END_IF
END_IF

FC_DL_ResolverAmpImbalance := _fPct;
END_FUNCTION
