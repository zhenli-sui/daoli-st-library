(* ===========================================================================
   组件名   : FB_DL_ServoStiffnessSwitch
   分类     : DL_Motion / 伺服刚性档位
   一句话   : 静止/低速/高速三档增益组切换，切换须零速且增益按斜坡过渡，禁止带速硬切
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnable 功能使能；eGearReq 目标档位请求；fVelAbs 当前速度绝对值 [rpm]
              fZeroSpeedBand 零速判定带宽 [rpm]；afKp/afKi/afKd 三档增益表 [1..3]
              fRampRate 增益过渡速率 [1/s]；fDtSec 采样周期 [s]
   输出契约 : fKpAct/fKiAct/fKdAct 生效增益；eGearAct 生效档位；xSwitchBusy 过渡中
              xSwitchBlocked 因速度过高被拒切换；xValid 输入有效
              iErrorCode 0=正常 1=非有限 2=参数非法 9=非法档位
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_StiffGear :
(
    eStaticGain := 0,    // 静止高刚性档 | standstill high stiffness
    eLowSpeedGain := 1,  // 低速中刚性档 | low speed medium stiffness
    eHighSpeedGain := 2  // 高速低刚性档 | high speed low stiffness
);
END_TYPE

FUNCTION_BLOCK FB_DL_ServoStiffnessSwitch
VAR_INPUT
    xEnable : BOOL;                             // 功能使能 | function enable
    eGearReq : E_DL_StiffGear := eStaticGain;   // 目标档位请求 | requested gear
    fVelAbs : REAL;                             // 速度绝对值 [rpm] | absolute speed [rpm]
    fZeroSpeedBand : REAL := 5.0;               // 零速判定带宽 [rpm] | zero speed band [rpm]
    afKp : ARRAY[1..3] OF REAL;                 // 三档比例增益表 | three gear kp table
    afKi : ARRAY[1..3] OF REAL;                 // 三档积分增益表 | three gear ki table
    afKd : ARRAY[1..3] OF REAL;                 // 三档微分增益表 | three gear kd table
    fRampRate : REAL := 20.0;                   // 增益过渡速率 [1/s] | gain ramp rate [1/s]
    fDtSec : REAL := 0.004;                     // 采样周期 [s] | sample period [s]
END_VAR
VAR_OUTPUT
    fKpAct : REAL;                              // 生效比例增益 | active kp
    fKiAct : REAL;                              // 生效积分增益 | active ki
    fKdAct : REAL;                              // 生效微分增益 | active kd
    eGearAct : E_DL_StiffGear;                  // 生效档位（默认首项=静止档） | active gear
    xSwitchBusy : BOOL;                         // 增益过渡进行中 | gain ramp in progress
    xSwitchBlocked : BOOL;                      // 带速切换被拒 | switch rejected at speed
    xValid : BOOL;                              // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                           // 故障码 0=无故障 | error code
END_VAR
VAR
    _iIdxAct : INT := 1;                        // 生效档位数组下标 1..3 | active index
    _iIdxReq : INT := 1;                        // 请求档位数组下标 1..3 | requested index
    _i : INT := 1;                              // 循环下标 | loop index
    _fDt : REAL;                                // 钳位后采样周期 [s] | clamped dt [s]
    _fStep : REAL;                              // 单拍增益步长 | gain step per cycle
    _afAct : ARRAY[1..3] OF REAL;               // 当前生效增益缓存 | active gain buffer
    _afTgt : ARRAY[1..3] OF REAL;               // 目标增益缓存 | target gain buffer
    _xBad : BOOL;                               // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                            // 参数非法标志 | invalid parameter flag
END_VAR

// ---- 非有限检测 ----
_xBad := (fVelAbs <> fVelAbs) OR ((fVelAbs - fVelAbs) <> (fVelAbs - fVelAbs))
      OR (fRampRate <> fRampRate) OR ((fRampRate - fRampRate) <> (fRampRate - fRampRate))
      OR (fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec));
_i := 1;
WHILE _i <= 3 DO
    IF ((afKp[_i] <> afKp[_i]) OR (afKi[_i] <> afKi[_i]) OR (afKd[_i] <> afKd[_i])) THEN
        _xBad := TRUE;                          // 任一档增益非有限即判无效
    END_IF
    _i := _i + 1;
END_WHILE

// ---- 参数合法性 ----
_xBadPar := (fZeroSpeedBand <= 0.0) OR (fRampRate <= 0.0) OR (fDtSec <= 0.0);

// ---- 输出预置：非锁存量复位 ----
xSwitchBusy := FALSE;
xSwitchBlocked := FALSE;
xValid := NOT (_xBad OR _xBadPar);
iErrorCode := 0;
IF _xBad THEN
    iErrorCode := 1;
ELSIF _xBadPar THEN
    iErrorCode := 2;
END_IF

// ---- 档位到数组下标映射：禁止枚举直接转型，用 CASE 显式映射 ----
CASE eGearAct OF
    eStaticGain: _iIdxAct := 1;
    eLowSpeedGain: _iIdxAct := 2;
    eHighSpeedGain: _iIdxAct := 3;
ELSE
    _iIdxAct := 1;                              // 非法生效档位兜底回静止档
    iErrorCode := 9;
END_CASE
CASE eGearReq OF
    eStaticGain: _iIdxReq := 1;
    eLowSpeedGain: _iIdxReq := 2;
    eHighSpeedGain: _iIdxReq := 3;
ELSE
    _iIdxReq := 1;                              // 非法请求档位兜底回静止档
    iErrorCode := 9;
END_CASE
IF _iIdxAct < 1 THEN
    _iIdxAct := 1;
ELSIF _iIdxAct > 3 THEN
    _iIdxAct := 3;
END_IF
IF _iIdxReq < 1 THEN
    _iIdxReq := 1;
ELSIF _iIdxReq > 3 THEN
    _iIdxReq := 3;
END_IF

// ---- 切换许可：须功能使能且零速，否则拒绝并置阻塞标志 ----
IF (_iIdxReq <> _iIdxAct) AND xValid AND xEnable THEN
    IF ABS(fVelAbs) < fZeroSpeedBand THEN
        eGearAct := eGearReq;                   // 零速许可切换
        _iIdxAct := _iIdxReq;
    ELSE
        xSwitchBlocked := TRUE;                 // 带速切换被拒，保持原档
    END_IF
END_IF

// ---- 增益斜坡过渡（受使能与合法性门控） ----
_fDt := fDtSec;
IF _fDt > 0.2 THEN
    _fDt := 0.2;                                // 周期上限，防大步长跳变
END_IF
_fStep := fRampRate * _fDt;
IF NOT xValid THEN
    _fStep := 0.0;                              // 非法输入时冻结过渡
END_IF

_afAct[1] := fKpAct;
_afAct[2] := fKiAct;
_afAct[3] := fKdAct;
_afTgt[1] := afKp[_iIdxAct];
_afTgt[2] := afKi[_iIdxAct];
_afTgt[3] := afKd[_iIdxAct];

FOR _i := 1 TO 3 DO
    IF _afAct[_i] < _afTgt[_i] THEN
        _afAct[_i] := _afAct[_i] + _fStep;
        IF _afAct[_i] > _afTgt[_i] THEN
            _afAct[_i] := _afTgt[_i];
        END_IF
    ELSIF _afAct[_i] > _afTgt[_i] THEN
        _afAct[_i] := _afAct[_i] - _fStep;
        IF _afAct[_i] < _afTgt[_i] THEN
            _afAct[_i] := _afTgt[_i];
        END_IF
    END_IF
END_FOR

// ---- 过渡完成判定：三路增益均已收敛（用容差比较，禁止浮点等值） ----
xSwitchBusy := (ABS(_afAct[1] - _afTgt[1]) > 0.000000001)
            OR (ABS(_afAct[2] - _afTgt[2]) > 0.000000001)
            OR (ABS(_afAct[3] - _afTgt[3]) > 0.000000001);

fKpAct := _afAct[1];
fKiAct := _afAct[2];
fKdAct := _afAct[3];
IF NOT xEnable THEN
    xSwitchBlocked := FALSE;                    // 未使能时不上报阻塞
END_IF
END_FUNCTION_BLOCK
