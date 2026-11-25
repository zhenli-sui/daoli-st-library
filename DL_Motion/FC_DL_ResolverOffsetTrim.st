(* ===========================================================================
   组件名   : FC_DL_ResolverOffsetTrim
   分类     : DL_Motion / 旋转变压器零位标定
   一句话   : 记录安装零位偏置并按偏置修正输出角，两模式共用同一取模归一逻辑
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fAngleRaw 原始机械角 [rad]；fOffset 已存偏置 [rad]；fAngleRef 参考零位 [rad]
              xCapture TRUE=标定本拍（记录偏置），FALSE=应用偏置
   输出契约 : 返回值 = 修正后机械角 [rad]，范围 [0, 2π)；fOffsetOut 生效偏置 [rad]
              xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverOffsetTrim : REAL
VAR_INPUT
    fAngleRaw : REAL;                  // 原始机械角 [rad] | raw mechanical angle [rad]
    fOffset : REAL;                    // 已存零位偏置 [rad] | stored zero offset [rad]
    fAngleRef : REAL := 0.0;           // 参考零位 [rad] | reference zero angle [rad]
    xCapture : BOOL;                   // TRUE=标定模式 | TRUE=capture mode
END_VAR
VAR_OUTPUT
    fOffsetOut : REAL;                 // 生效偏置 [rad] | effective offset [rad]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fTmp : REAL;                      // 取模中间量 [rad] | modulo intermediate [rad]
    _fCyc : REAL;                      // 圈数整数值 | integer turns value
    _fOut : REAL;                      // 修正角 [rad] | corrected angle [rad]
END_VAR

// ---- 输出预置 ----
fOffsetOut := 0.0;
xValid := FALSE;
FC_DL_ResolverOffsetTrim := 0.0;

// ---- 非有限值拦截 ----
IF (fAngleRaw <> fAngleRaw) OR ((fAngleRaw - fAngleRaw) <> (fAngleRaw - fAngleRaw)) THEN
    RETURN;
END_IF
IF (fOffset <> fOffset) OR ((fOffset - fOffset) <> (fOffset - fOffset)) THEN
    RETURN;
END_IF
IF (fAngleRef <> fAngleRef) OR ((fAngleRef - fAngleRef) <> (fAngleRef - fAngleRef)) THEN
    RETURN;
END_IF

IF xCapture THEN
    // ---- 标定模式：偏置 = 原始角 − 参考零位，取模到 [0, 2π) ----
    _fTmp := fAngleRaw - fAngleRef;
    IF _fTmp > 1000000.0 THEN
        _fTmp := 1000000.0;                        // 上限钳位，防 TRUNC 溢出
    ELSIF _fTmp < -1000000.0 THEN
        _fTmp := -1000000.0;
    END_IF
    _fCyc := TRUNC(_fTmp / 6.283185307);           // 常量分母，非零
    _fTmp := _fTmp - 6.283185307 * _fCyc;
    IF _fTmp < 0.0 THEN
        _fTmp := _fTmp + 6.283185307;
    END_IF
    IF _fTmp >= 6.283185307 THEN
        _fTmp := _fTmp - 6.283185307;
    END_IF
    fOffsetOut := _fTmp;
    _fOut := fAngleRaw;                            // 标定拍不改变已解算角
    xValid := TRUE;
ELSE
    // ---- 应用模式：偏置取模后从原始角扣除 ----
    _fTmp := fOffset;
    IF _fTmp > 1000000.0 THEN
        _fTmp := 1000000.0;
    ELSIF _fTmp < -1000000.0 THEN
        _fTmp := -1000000.0;
    END_IF
    _fCyc := TRUNC(_fTmp / 6.283185307);
    _fTmp := _fTmp - 6.283185307 * _fCyc;
    IF _fTmp < 0.0 THEN
        _fTmp := _fTmp + 6.283185307;
    END_IF
    IF _fTmp >= 6.283185307 THEN
        _fTmp := _fTmp - 6.283185307;
    END_IF
    fOffsetOut := _fTmp;

    _fOut := fAngleRaw - _fTmp;
    IF _fOut < 0.0 THEN
        _fOut := _fOut + 6.283185307;              // 负角归一
    END_IF
    IF _fOut >= 6.283185307 THEN
        _fOut := _fOut - 6.283185307;
    END_IF
    xValid := TRUE;
END_IF

FC_DL_ResolverOffsetTrim := _fOut;
END_FUNCTION
