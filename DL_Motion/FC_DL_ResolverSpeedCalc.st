(* ===========================================================================
   组件名   : FC_DL_ResolverSpeedCalc
   分类     : DL_Motion / 旋转变压器测速
   一句话   : 由相邻两拍角度差分解算转速，含跨零解卷绕与一阶低通滤波（状态由调用方持有）
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fAngleNow 本拍角度 [rad] 0..2π；fAnglePrev 上拍角度 [rad] 0..2π
              fDtSec 采样周期 [s]；fSpeedPrev 上拍滤波后转速 [rad/s]；fLpfAlpha 低通系数 0..1
   输出契约 : 返回值 = 本拍滤波后转速 [rad/s]；fDeltaUnwrapped 解卷绕后角增量 [rad]
              xWrapFlag 本拍发生跨零解卷绕；xValid 输入有效
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION FC_DL_ResolverSpeedCalc : REAL
VAR_INPUT
    fAngleNow : REAL;                  // 本拍角度 [rad] 0..2π | current angle [rad]
    fAnglePrev : REAL;                 // 上拍角度 [rad] 0..2π | previous angle [rad]
    fDtSec : REAL := 0.004;            // 采样周期 [s] | sample period [s]
    fSpeedPrev : REAL;                 // 上拍滤波后转速 [rad/s] | previous filtered speed [rad/s]
    fLpfAlpha : REAL := 0.2;           // 一阶低通系数 0..1 | first order lpf alpha
END_VAR
VAR_OUTPUT
    fDeltaUnwrapped : REAL;            // 解卷绕后角增量 [rad] | unwrapped angle delta [rad]
    fSpeedRaw : REAL;                  // 原始转速 [rad/s] | raw speed [rad/s]
    xWrapFlag : BOOL;                  // 是否发生跨零解卷绕 | wrap corrected flag
    xValid : BOOL;                     // 输入有效标志 | inputs valid flag
END_VAR
VAR
    _fDelta : REAL;                    // 角增量 [rad] | angle delta [rad]
    _fDt : REAL;                       // 钳位后采样周期 [s] | clamped dt [s]
    _fAlpha : REAL;                    // 钳位后低通系数 | clamped alpha
    _fSpeed : REAL;                    // 滤波后转速 [rad/s] | filtered speed [rad/s]
END_VAR

// ---- 输出预置 ----
fDeltaUnwrapped := 0.0;
fSpeedRaw := 0.0;
xWrapFlag := FALSE;
xValid := FALSE;
FC_DL_ResolverSpeedCalc := 0.0;

// ---- 非有限值拦截 ----
IF (fAngleNow <> fAngleNow) OR ((fAngleNow - fAngleNow) <> (fAngleNow - fAngleNow)) THEN
    RETURN;
END_IF
IF (fAnglePrev <> fAnglePrev) OR ((fAnglePrev - fAnglePrev) <> (fAnglePrev - fAnglePrev)) THEN
    RETURN;
END_IF
IF (fSpeedPrev <> fSpeedPrev) OR ((fSpeedPrev - fSpeedPrev) <> (fSpeedPrev - fSpeedPrev)) THEN
    RETURN;
END_IF

// ---- 周期钳位：防止零除与超大解算步长 ----
_fDt := fDtSec;
IF _fDt < 0.000001 THEN
    _fDt := 0.000001;
ELSIF _fDt > 0.2 THEN
    _fDt := 0.2;
END_IF

// ---- 角度跨零解卷绕：增量超出 ±π 即判为绕圈并补偿 2π ----
_fDelta := fAngleNow - fAnglePrev;
IF _fDelta > 3.141592654 THEN
    _fDelta := _fDelta - 6.283185307;              // 正向跨零
    xWrapFlag := TRUE;
ELSIF _fDelta < -3.141592654 THEN
    _fDelta := _fDelta + 6.283185307;              // 反向跨零
    xWrapFlag := TRUE;
END_IF
fDeltaUnwrapped := _fDelta;

// ---- 原始转速：分母已守卫 ----
fSpeedRaw := _fDelta / _fDt;

// ---- 一阶低通：系数钳位到 0..1 ----
_fAlpha := fLpfAlpha;
IF _fAlpha < 0.0 THEN
    _fAlpha := 0.0;
ELSIF _fAlpha > 1.0 THEN
    _fAlpha := 1.0;
END_IF
_fSpeed := fSpeedPrev + _fAlpha * (fSpeedRaw - fSpeedPrev);

xValid := TRUE;
FC_DL_ResolverSpeedCalc := _fSpeed;
END_FUNCTION
