(* ===========================================================================
   组件名   : FC_DL_ResolverElecAngleUnwrap
   分类     : DL_Motion / 旋转变压器电角度解卷绕
   一句话   : 跨 0/2π 边界时累加圈数，输出连续电角度与圈数
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fAngleNow 本拍电角度 [rad] 0..2π；fAnglePrev 上拍电角度 [rad] 0..2π
              iTurnPrev 上拍累计圈数
   输出契约 : 返回值 = 连续电角度 [rad]（可超出 0..2π）
              iTurns 本拍累计圈数；fDelta 解卷绕后电角增量 [rad]；xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverElecAngleUnwrap : REAL
VAR_INPUT
    fAngleNow : REAL;                  // 本拍电角度 [rad] | current electrical angle [rad]
    fAnglePrev : REAL;                 // 上拍电角度 [rad] | previous electrical angle [rad]
    iTurnPrev : INT := 0;              // 上拍累计圈数 | previous turn count
END_VAR
VAR_OUTPUT
    iTurns : INT;                      // 本拍累计圈数 | current turn count
    fDelta : REAL;                     // 解卷绕后增量 [rad] | unwrapped delta [rad]
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fD : REAL;                        // 本拍角差 [rad] | angle difference [rad]
    _iT : INT;                         // 累计圈数工作值 | turn count working value
END_VAR

// ---- 输出预置 ----
iTurns := 0;
fDelta := 0.0;
xValid := FALSE;
FC_DL_ResolverElecAngleUnwrap := 0.0;

// ---- 非有限值拦截 ----
IF (fAngleNow <> fAngleNow) OR ((fAngleNow - fAngleNow) <> (fAngleNow - fAngleNow)) THEN
    RETURN;
END_IF
IF (fAnglePrev <> fAnglePrev) OR ((fAnglePrev - fAnglePrev) <> (fAnglePrev - fAnglePrev)) THEN
    RETURN;
END_IF

// ---- 圈数钳位：防止长时间运行后整型溢出 ----
_iT := iTurnPrev;
IF _iT > 1000000 THEN
    _iT := 1000000;
ELSIF _iT < -1000000 THEN
    _iT := -1000000;
END_IF

// ---- 解卷绕：正向跨零（差 < −π）圈数 +1，反向跨零（差 > π）圈数 −1 ----
_fD := fAngleNow - fAnglePrev;
IF _fD > 3.141592654 THEN
    _fD := _fD - 6.283185307;                      // 反向跨零补偿
    _iT := _iT - 1;
ELSIF _fD < -3.141592654 THEN
    _fD := _fD + 6.283185307;                      // 正向跨零补偿
    _iT := _iT + 1;
END_IF

// ---- 圈数二次钳位：补偿后仍须落在可表范围内 ----
IF _iT > 1000000 THEN
    _iT := 1000000;
ELSIF _iT < -1000000 THEN
    _iT := -1000000;
END_IF

fDelta := _fD;
iTurns := _iT;
xValid := TRUE;

// ---- 连续角 = 圈数 × 2π + 本拍角 ----
FC_DL_ResolverElecAngleUnwrap := INT_TO_REAL(_iT) * 6.283185307 + fAngleNow;
END_FUNCTION
