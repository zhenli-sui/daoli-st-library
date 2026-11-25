(* ===========================================================================
   组件名   : FC_DL_StrainCreepComp
   分类     : DL_Device / 应变蠕变补偿
   一句话   : 按载荷保持时间与蠕变系数用指数饱和模型修正读数漂移
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fRawStrain 原始应变 [µε]；fHoldSec 载荷保持时间 [s]
              fCreepK 蠕变系数（0..0.1，无量纲） | creep coefficient
              fTauSec 蠕变时间常数 [s]
   输出契约 : 返回值 = 蠕变修正后应变 [µε]；fCreepTerm 蠕变量 [µε]
              fCreepFrac 蠕变完成度 0..1；xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_StrainCreepComp : REAL
VAR_INPUT
    fRawStrain : REAL;                 // 原始应变 [µε] | raw strain [µε]
    fHoldSec : REAL := 0.0;            // 载荷保持时间 [s] | load hold time [s]
    fCreepK : REAL := 0.01;            // 蠕变系数 0..0.1 | creep coefficient 0..0.1
    fTauSec : REAL := 60.0;            // 蠕变时间常数 [s] | creep time constant [s]
END_VAR
VAR_OUTPUT
    fCreepTerm : REAL;                 // 蠕变量 [µε] | creep amount [µε]
    fCreepFrac : REAL;                 // 蠕变完成度 0..1 | creep completion 0..1
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fRatio : REAL;                    // 保持时间/时间常数 | hold over tau
    _fFrac : REAL;                     // 蠕变完成度 | creep completion
    _fOut : REAL;                      // 修正结果 [µε] | corrected result [µε]
END_VAR

// ---- 输出预置 ----
fCreepTerm := 0.0;
fCreepFrac := 0.0;
xValid := FALSE;
FC_DL_StrainCreepComp := 0.0;

// ---- 非有限值拦截 ----
IF (fRawStrain <> fRawStrain) OR ((fRawStrain - fRawStrain) <> (fRawStrain - fRawStrain)) THEN
    RETURN;
END_IF
IF (fHoldSec <> fHoldSec) OR ((fHoldSec - fHoldSec) <> (fHoldSec - fHoldSec)) THEN
    RETURN;
END_IF
IF (fCreepK <> fCreepK) OR ((fCreepK - fCreepK) <> (fCreepK - fCreepK)) THEN
    RETURN;
END_IF
IF (fTauSec <> fTauSec) OR ((fTauSec - fTauSec) <> (fTauSec - fTauSec)) THEN
    RETURN;
END_IF

// ---- 防除零与参数守卫：时间常数必须为正，蠕变系数限于 0..0.1 ----
IF (fTauSec < 0.000001) OR (fCreepK < 0.0) OR (fCreepK > 0.1) OR (fHoldSec < 0.0) THEN
    RETURN;
END_IF

// ---- 指数饱和模型：完成度 = 1 − exp(−t/τ)，比值上限 50 防下溢 ----
_fRatio := fHoldSec / fTauSec;                     // 分母已守卫
IF _fRatio > 50.0 THEN
    _fRatio := 50.0;
END_IF
_fFrac := 1.0 - EXP(-_fRatio);
fCreepFrac := _fFrac;

// ---- 蠕变量按原始读数比例给出，再从读数中扣除 ----
fCreepTerm := fRawStrain * fCreepK * _fFrac;
_fOut := fRawStrain - fCreepTerm;

xValid := TRUE;
FC_DL_StrainCreepComp := _fOut;
END_FUNCTION
