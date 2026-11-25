(* ===========================================================================
   组件名   : FB_DL_ResolverAngleTrackObs
   分类     : DL_Motion / 旋转变压器角度跟踪观测器
   一句话   : 二阶跟踪环由 sin/cos 直接跟踪角度与转速，无需反三角运算且天然解卷绕
   复杂度   : 3        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : fSin/fCos 两路瞬时值 [V]；fKp 角度环增益 [1/s]；fKi 速度环增益 [1/s²]
              fDtSec 采样周期 [s]；fAmpMin 最小有效幅值 [V]；fSpeedMax 转速限幅 [rad/s]
              fLockBand 锁定判定带宽（归一化误差） | lock band
   输出契约 : fAngleEst 跟踪角 [rad] 0..2π；fSpeedEst 跟踪转速 [rad/s]
              fErrorNorm 归一化角度误差（≈sin(θin−θest)） | normalized angle error
              xLocked 已锁定；xValid 输入有效；eStateOut 状态观测
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_TrackState :
(
    eTrackInit := 0,     // 初始化（粗定位） | init by coarse seed
    eTracking := 1,      // 正常跟踪 | normal tracking
    eSignalLost := 2     // 信号丢失冻结 | signal lost freeze
);
END_TYPE

FUNCTION_BLOCK FB_DL_ResolverAngleTrackObs
VAR_INPUT
    fSin : REAL;                        // 正弦路瞬时值 [V] | sine channel value [V]
    fCos : REAL;                        // 余弦路瞬时值 [V] | cosine channel value [V]
    fKp : REAL := 60.0;                 // 角度环增益 [1/s] | angle loop gain [1/s]
    fKi : REAL := 2000.0;               // 速度环增益 [1/s²] | speed loop gain [1/s^2]
    fDtSec : REAL := 0.0001;            // 采样周期 [s] | sample period [s]
    fAmpMin : REAL := 0.5;              // 最小有效幅值 [V] | minimum valid amplitude [V]
    fSpeedMax : REAL := 500.0;          // 转速限幅 [rad/s] | speed clamp [rad/s]
    fLockBand : REAL := 0.02;           // 锁定判定带宽（归一化） | lock band normalized
END_VAR
VAR_OUTPUT
    fAngleEst : REAL;                   // 跟踪角度 [rad] 0..2π | estimated angle [rad]
    fSpeedEst : REAL;                   // 跟踪转速 [rad/s] | estimated speed [rad/s]
    fErrorNorm : REAL;                  // 归一化角度误差 | normalized angle error
    xLocked : BOOL;                     // 已锁定标志 | locked flag
    xValid : BOOL;                      // 输入有效标志 | inputs valid flag
    eStateOut : E_DL_TrackState;        // 当前状态观测 | current state observation
END_VAR
VAR
    _eState : E_DL_TrackState := eTrackInit;  // 内部状态机状态 | internal state
    _fAngle : REAL;                     // 内部跟踪角 [rad] | internal tracked angle [rad]
    _fSpeed : REAL;                     // 内部跟踪转速 [rad/s] | internal tracked speed [rad/s]
    _fAmp : REAL;                       // 合成幅值 [V] | resultant amplitude [V]
    _fErr : REAL;                       // 原始角度误差 [V] | raw angle error [V]
    _fDt : REAL;                        // 钳位后采样周期 [s] | clamped dt [s]
    _xBad : BOOL;                       // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                    // 参数非法标志 | invalid parameter flag
END_VAR

// ---- 非有限检测 ----
_xBad := (fSin <> fSin) OR ((fSin - fSin) <> (fSin - fSin))
      OR (fCos <> fCos) OR ((fCos - fCos) <> (fCos - fCos))
      OR (fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec));

// ---- 参数合法性 ----
_xBadPar := (fDtSec <= 0.0) OR (fAmpMin <= 0.0) OR (fSpeedMax <= 0.0)
         OR (fLockBand <= 0.0) OR (fKp < 0.0) OR (fKi < 0.0);

// ---- 周期钳位：跟踪环对步长极敏感，必须限幅 ----
_fDt := fDtSec;
IF _fDt < 0.000001 THEN
    _fDt := 0.000001;
ELSIF _fDt > 0.01 THEN
    _fDt := 0.01;
END_IF

// ---- 输出预置：角度与转速为积分状态，不做每拍清零 ----
fErrorNorm := 0.0;
xLocked := FALSE;
xValid := NOT (_xBad OR _xBadPar);

// ---- 合成幅值 ----
_fAmp := 0.0;
IF NOT _xBad THEN
    _fAmp := SQRT(fSin * fSin + fCos * fCos);
END_IF

CASE _eState OF
    eTrackInit:
        _fSpeed := 0.0;
        IF xValid AND (_fAmp >= fAmpMin) THEN
            // 粗定位种子：以 cos 符号区分半平面，跟踪环在后续拍内自动收敛
            IF fCos >= 0.0 THEN
                _fAngle := 0.0;
            ELSE
                _fAngle := 3.141592654;
            END_IF
            _eState := eTracking;
        END_IF
        fAngleEst := _fAngle;
        fSpeedEst := _fSpeed;

    eTracking:
        IF (NOT xValid) OR (_fAmp < fAmpMin) THEN
            _eState := eSignalLost;                // 幅值不足转冻结态
            fAngleEst := _fAngle;                  // 冻结输出保持最后可信值
            fSpeedEst := 0.0;
        ELSE
            // 误差：sin(θin)·cos(θest) − cos(θin)·sin(θest) = A·sin(θin−θest)
            _fErr := fSin * COS(_fAngle) - fCos * SIN(_fAngle);
            fErrorNorm := _fErr / _fAmp;           // 分母已由 fAmpMin 守卫

            // 二阶跟踪环：速度积分 + 角度积分
            _fSpeed := _fSpeed + fKi * fErrorNorm * _fDt;
            IF _fSpeed > fSpeedMax THEN
                _fSpeed := fSpeedMax;              // 转速限幅
            ELSIF _fSpeed < -fSpeedMax THEN
                _fSpeed := -fSpeedMax;
            END_IF

            _fAngle := _fAngle + (_fSpeed + fKp * fErrorNorm) * _fDt;
            IF _fAngle >= 6.283185307 THEN
                _fAngle := _fAngle - 6.283185307;  // 归一化到 0..2π
            ELSIF _fAngle < 0.0 THEN
                _fAngle := _fAngle + 6.283185307;
            END_IF

            fAngleEst := _fAngle;
            fSpeedEst := _fSpeed;
            xLocked := (ABS(fErrorNorm) < fLockBand);
        END_IF

    eSignalLost:
        fAngleEst := _fAngle;                      // 冻结保持，不按坏信号重新推断
        fSpeedEst := 0.0;
        IF xValid AND (_fAmp >= fAmpMin) THEN
            _eState := eTracking;                   // 信号恢复后从冻结角继续跟踪
        END_IF

ELSE
    _eState := eTrackInit;                          // 非法状态兜底回初始化
    fAngleEst := 0.0;
    fSpeedEst := 0.0;
    _fAngle := 0.0;
    _fSpeed := 0.0;
END_CASE

eStateOut := _eState;
END_FUNCTION_BLOCK
