(* ===========================================================================
   组件名   : FC_DL_ResolverPolePairAngle
   分类     : DL_Motion / 旋转变压器电角度换算
   一句话   : 由机械角与极对数换算电角度，含取模与负角归一化处理
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fMechAngle 机械角 [rad]；iPolePairs 极对数 1..64；fMechOffset 机械零位偏置 [rad]
   输出契约 : 返回值 = 电角度 [rad]，范围 [0, 2π)；fElecTurns 电角累计整圈数
              xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverPolePairAngle : REAL
VAR_INPUT
    fMechAngle : REAL;                 // 机械角 [rad] | mechanical angle [rad]
    iPolePairs : INT := 1;             // 极对数 1..64 | pole pairs 1..64
    fMechOffset : REAL := 0.0;         // 机械零位偏置 [rad] | mechanical zero offset [rad]
END_VAR
VAR_OUTPUT
    fElecTurns : REAL;                 // 电角整圈数（截断值） | electrical whole turns
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fRaw : REAL;                      // 未归一电角度 [rad] | unnormalized electrical angle [rad]
    _fCyc : REAL;                      // 整圈数值 | whole turns value
    _fOut : REAL;                      // 归一化电角度 [rad] | normalized electrical angle [rad]
    _iPP : INT;                        // 钳位后极对数 | clamped pole pairs
END_VAR

// ---- 输出预置 ----
fElecTurns := 0.0;
xValid := FALSE;
FC_DL_ResolverPolePairAngle := 0.0;

// ---- 非有限值拦截 ----
IF (fMechAngle <> fMechAngle) OR ((fMechAngle - fMechAngle) <> (fMechAngle - fMechAngle)) THEN
    RETURN;
END_IF
IF (fMechOffset <> fMechOffset) OR ((fMechOffset - fMechOffset) <> (fMechOffset - fMechOffset)) THEN
    RETURN;
END_IF

// ---- 极对数钳位：上限 64 防乘后数值过大，下限 1 防退化为零角 ----
_iPP := iPolePairs;
IF _iPP < 1 THEN
    _iPP := 1;
ELSIF _iPP > 64 THEN
    _iPP := 64;
END_IF

// ---- 电角度 = （机械角 − 零位偏置）× 极对数 ----
_fRaw := (fMechAngle - fMechOffset) * INT_TO_REAL(_iPP);
IF _fRaw > 1000000.0 THEN
    _fRaw := 1000000.0;                            // 上限钳位，防 TRUNC 溢出
ELSIF _fRaw < -1000000.0 THEN
    _fRaw := -1000000.0;
END_IF

// ---- 取模归一：先截断圈数再扣余量，避免正向循环累减 ----
_fCyc := TRUNC(_fRaw / 6.283185307);               // 常量分母，非零
_fOut := _fRaw - 6.283185307 * _fCyc;              // 余量落在 (−2π, 2π)

// ---- 负角归一化到 [0, 2π) ----
IF _fOut < 0.0 THEN
    _fOut := _fOut + 6.283185307;
END_IF
IF _fOut >= 6.283185307 THEN
    _fOut := _fOut - 6.283185307;                  // 浮点余量兜底，单次修正足够
END_IF

fElecTurns := _fCyc;
xValid := TRUE;
FC_DL_ResolverPolePairAngle := _fOut;
END_FUNCTION
