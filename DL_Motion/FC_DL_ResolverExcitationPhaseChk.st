(* ===========================================================================
   组件名   : FC_DL_ResolverExcitationPhaseChk
   分类     : DL_Motion / 旋转变压器励磁相位校验
   一句话   : 校验励磁与输出的相位差是否命中期望值，并据此判定接线相序是否反接
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fExcPhase 励磁相位 [rad]；fOutPhase 输出相位 [rad]
              fExpectedDiff 期望相位差 [rad]；fTol 容差 [rad]
   输出契约 : 返回值 = 卷绕到 (−π, π] 的实测相位差 [rad]
              xPhaseOk 相位差落在期望值容差内；xSeqReversed 判为相序反接（差 180°）
              xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverExcitationPhaseChk : REAL
VAR_INPUT
    fExcPhase : REAL;                  // 励磁相位 [rad] | excitation phase [rad]
    fOutPhase : REAL;                  // 输出相位 [rad] | output phase [rad]
    fExpectedDiff : REAL := 0.0;       // 期望相位差 [rad] | expected phase difference [rad]
    fTol : REAL := 0.2;                // 相位容差 [rad] | phase tolerance [rad]
END_VAR
VAR_OUTPUT
    xPhaseOk : BOOL;                   // 相位差合格 | phase difference acceptable
    xSeqReversed : BOOL;               // 相序反接（差 180°） | wiring reversed (180 deg)
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fDiff : REAL;                     // 卷绕后相位差 [rad] | wrapped phase difference [rad]
    _fErrFwd : REAL;                   // 与期望值的偏差（正接） [rad] | error, forward wiring [rad]
    _fErrRev : REAL;                   // 与期望值的偏差（反接） [rad] | error, reversed wiring [rad]
    _fTmp : REAL;                      // 卷绕中间量 [rad] | wrap intermediate [rad]
END_VAR

// ---- 输出预置 ----
xPhaseOk := FALSE;
xSeqReversed := FALSE;
xValid := FALSE;
FC_DL_ResolverExcitationPhaseChk := 0.0;

// ---- 非有限值拦截 ----
IF (fExcPhase <> fExcPhase) OR ((fExcPhase - fExcPhase) <> (fExcPhase - fExcPhase)) THEN
    RETURN;
END_IF
IF (fOutPhase <> fOutPhase) OR ((fOutPhase - fOutPhase) <> (fOutPhase - fOutPhase)) THEN
    RETURN;
END_IF
IF (fTol <> fTol) OR ((fTol - fTol) <> (fTol - fTol)) OR (fTol <= 0.0) THEN
    RETURN;
END_IF

// ---- 实测相位差并卷绕到 (−π, π] ----
_fDiff := fOutPhase - fExcPhase;
IF _fDiff > 1000000.0 THEN
    _fDiff := 1000000.0;                           // 上限钳位，防 TRUNC 溢出
ELSIF _fDiff < -1000000.0 THEN
    _fDiff := -1000000.0;
END_IF
_fDiff := _fDiff - 6.283185307 * TRUNC(_fDiff / 6.283185307);
IF _fDiff > 3.141592654 THEN
    _fDiff := _fDiff - 6.283185307;
ELSIF _fDiff <= -3.141592654 THEN
    _fDiff := _fDiff + 6.283185307;
END_IF
FC_DL_ResolverExcitationPhaseChk := _fDiff;

// ---- 正接偏差：实测差 − 期望差，再卷绕 ----
_fTmp := _fDiff - fExpectedDiff;
IF _fTmp > 3.141592654 THEN
    _fTmp := _fTmp - 6.283185307;
ELSIF _fTmp <= -3.141592654 THEN
    _fTmp := _fTmp + 6.283185307;
END_IF
_fErrFwd := ABS(_fTmp);                            // 绝对值即偏差幅度

// ---- 反接偏差：正接偏差再叠加 180° ----
_fTmp := _fTmp + 3.141592654;
IF _fTmp > 3.141592654 THEN
    _fTmp := _fTmp - 6.283185307;
ELSIF _fTmp <= -3.141592654 THEN
    _fTmp := _fTmp + 6.283185307;
END_IF
_fErrRev := ABS(_fTmp);

// ---- 判定：容差比较一律用小于等于，不做浮点等值判定 ----
IF _fErrFwd <= fTol THEN
    xPhaseOk := TRUE;                              // 正接合格
ELSIF _fErrRev <= fTol THEN
    xSeqReversed := TRUE;                          // 差 180° 判为相序反接
END_IF
xValid := TRUE;
END_FUNCTION
