(* ===========================================================================
   组件名   : FB_DL_ServoVelLoopBand
   分类     : DL_Motion / 速度环带宽估算
   一句话   : 由速度指令阶跃响应的 10%→90% 上升时间估算闭环带宽并判定是否达标
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnable 功能使能；xArm 测量许可（FALSE 复位）；fVelRef 速度指令 [rpm]
              fVelFbk 速度反馈 [rpm]；fDtSec 采样周期 [s]；fStepThr 阶跃识别阈值 [rpm]
              fRiseLowFrac/fRiseHighFrac 上升时间取点分数；fTimeoutSec 测量超时 [s]
              fBandFactor 上升时间-带宽系数（一阶近似 0.35）；fBandTargetHz 达标带宽 [Hz]
   输出契约 : fRiseTimeSec 上升时间 [s]；fBandwidthHz 估算带宽 [Hz]；xDone 测量完成
              xBandOk 带宽达标（容差比较）；xValid 输入有效
              iErrorCode 0=正常 1=输入非有限 2=测量超时 3=上升时间过小 9=非法状态
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_RiseMeasState :
(
    eIdle := 0,       // 空闲待命 | idle
    eWaitStep := 1,   // 等待阶跃发生 | wait for step
    eRising := 2,     // 上升沿测量中 | rising measurement
    eDone := 3,       // 测量完成 | measurement done
    eFail := 4        // 测量失败 | measurement failed
);
END_TYPE

FUNCTION_BLOCK FB_DL_ServoVelLoopBand
VAR_INPUT
    xEnable : BOOL;                       // 功能使能 | function enable
    xArm : BOOL;                          // 测量许可 FALSE=复位 | measurement arm
    fVelRef : REAL;                       // 速度指令 [rpm] | velocity reference [rpm]
    fVelFbk : REAL;                       // 速度反馈 [rpm] | velocity feedback [rpm]
    fDtSec : REAL := 0.004;               // 采样周期 [s] | sample period [s]
    fStepThr : REAL := 50.0;              // 阶跃识别阈值 [rpm] | step detect threshold [rpm]
    fRiseLowFrac : REAL := 0.1;           // 上升时间起点分数 | rise time low fraction
    fRiseHighFrac : REAL := 0.9;          // 上升时间终点分数 | rise time high fraction
    fTimeoutSec : REAL := 5.0;            // 测量超时 [s] | measurement timeout [s]
    fBandFactor : REAL := 0.35;           // 上升时间-带宽系数 | rise time band factor
    fBandTargetHz : REAL := 100.0;        // 达标带宽 [Hz] | target bandwidth [Hz]
END_VAR
VAR_OUTPUT
    fRiseTimeSec : REAL;                  // 上升时间 [s] | rise time [s]
    fBandwidthHz : REAL;                  // 估算带宽 [Hz] | estimated bandwidth [Hz]
    xDone : BOOL;                         // 测量完成 | measurement done
    xBandOk : BOOL;                       // 带宽达标 | bandwidth acceptable
    xValid : BOOL;                        // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                     // 故障码 0=无故障 | error code
    eStateOut : E_DL_RiseMeasState;       // 当前状态观测 | current state observation
END_VAR
VAR
    _eState : E_DL_RiseMeasState := eIdle;  // 内部状态机状态 | internal state
    _fRefPrev : REAL;                     // 上一拍速度指令 [rpm] | previous reference [rpm]
    _fStart : REAL;                       // 阶跃起点值 [rpm] | step start value [rpm]
    _fAmp : REAL;                         // 阶跃幅值 [rpm] | step amplitude [rpm]
    _fElapsed : REAL;                     // 阶跃后累计时间 [s] | elapsed since step [s]
    _fProg : REAL;                        // 归一化响应进度 | normalized response progress
    _fT10 : REAL;                         // 10% 时刻 [s] | time at low fraction [s]
    _fT90 : REAL;                         // 90% 时刻 [s] | time at high fraction [s]
    _fDt : REAL;                          // 钳位后采样周期 [s] | clamped dt [s]
    _xGot10 : BOOL;                       // 已捕获低分数时刻 | low fraction captured
    _xGot90 : BOOL;                       // 已捕获高分数时刻 | high fraction captured
    _xBad : BOOL;                         // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                      // 参数非法标志 | invalid parameter flag
END_VAR

// ---- 非有限检测 ----
_xBad := (fVelRef <> fVelRef) OR ((fVelRef - fVelRef) <> (fVelRef - fVelRef))
      OR (fVelFbk <> fVelFbk) OR ((fVelFbk - fVelFbk) <> (fVelFbk - fVelFbk))
      OR (fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec))
      OR (fBandFactor <> fBandFactor) OR ((fBandFactor - fBandFactor) <> (fBandFactor - fBandFactor));

// ---- 参数合法性：所有做分母/做取点的量必须为正且分数有序 ----
_xBadPar := (fDtSec <= 0.0) OR (fStepThr <= 0.0) OR (fTimeoutSec <= 0.0)
         OR (fBandFactor <= 0.0) OR (fBandTargetHz <= 0.0)
         OR (fRiseLowFrac <= 0.0) OR (fRiseHighFrac <= fRiseLowFrac);

xValid := NOT (_xBad OR _xBadPar);
iErrorCode := 0;
IF _xBad THEN
    iErrorCode := 1;
ELSIF _xBadPar THEN
    iErrorCode := 2;
END_IF

// ---- 周期钳位 ----
_fDt := fDtSec;
IF _fDt < 0.000001 THEN
    _fDt := 0.000001;
ELSIF _fDt > 0.2 THEN
    _fDt := 0.2;
END_IF

CASE _eState OF
    eIdle:
        xDone := FALSE;
        IF NOT xEnable THEN
            iErrorCode := 0;
        ELSIF xArm AND xValid THEN
            fRiseTimeSec := 0.0;
            fBandwidthHz := 0.0;
            xBandOk := FALSE;
            _fElapsed := 0.0;
            _eState := eWaitStep;
        END_IF

    eWaitStep:
        IF NOT xArm OR NOT xEnable THEN
            _eState := eIdle;
        ELSIF ABS(fVelRef - _fRefPrev) > fStepThr THEN
            _fStart := _fRefPrev;                    // 阶跃起点
            _fAmp := fVelRef - _fRefPrev;            // 阶跃幅值
            IF ABS(_fAmp) > 0.000000001 THEN          // 防零除：幅值必须显著
                _fElapsed := 0.0;
                _fT10 := 0.0;
                _fT90 := 0.0;
                _xGot10 := FALSE;
                _xGot90 := FALSE;
                _eState := eRising;
            ELSE
                iErrorCode := 3;                     // 幅值过小视为无效阶跃
                _eState := eFail;
            END_IF
        END_IF

    eRising:
        IF NOT xArm OR NOT xEnable THEN
            _eState := eIdle;
        ELSE
            _fElapsed := _fElapsed + _fDt;
            _fProg := 0.0;
            IF ABS(_fAmp) > 0.000000001 THEN
                _fProg := (fVelFbk - _fStart) / _fAmp;   // 归一化进度，分母已守卫
            END_IF
            IF NOT _xGot10 AND (_fProg >= fRiseLowFrac) THEN
                _fT10 := _fElapsed;
                _xGot10 := TRUE;
            END_IF
            IF _xGot10 AND NOT _xGot90 AND (_fProg >= fRiseHighFrac) THEN
                _fT90 := _fElapsed;
                _xGot90 := TRUE;
            END_IF
            IF _xGot90 THEN
                fRiseTimeSec := _fT90 - _fT10;
                IF fRiseTimeSec > 0.000001 THEN
                    fBandwidthHz := fBandFactor / fRiseTimeSec;   // 分母已守卫
                    xDone := TRUE;
                    _eState := eDone;
                ELSE
                    iErrorCode := 3;                 // 上升时间过小，估算不可信
                    _eState := eFail;
                END_IF
            ELSIF _fElapsed > fTimeoutSec THEN
                iErrorCode := 2;                     // 响应未达 90%，测量超时
                _eState := eFail;
            END_IF
        END_IF

    eDone:
        IF NOT xArm OR NOT xEnable THEN
            xDone := FALSE;
            _eState := eIdle;                        // 结果保持至下一次重新测量
        END_IF

    eFail:
        xDone := FALSE;
        IF NOT xArm OR NOT xEnable THEN
            iErrorCode := 0;
            _eState := eIdle;
        END_IF

ELSE
    iErrorCode := 9;                                 // 非法状态兜底
    xDone := FALSE;
    _eState := eIdle;
END_CASE;

// ---- 达标判定：仅在测量完成后用容差比较带宽 ----
IF _eState = eDone THEN
    xBandOk := (fBandwidthHz + 0.000001) >= fBandTargetHz;
END_IF

_fRefPrev := fVelRef;                                // 指令历史留到拍末更新
eStateOut := _eState;
END_FUNCTION_BLOCK
