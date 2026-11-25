(* ===========================================================================
   组件名   : FB_DL_ServoOverloadDerate
   分类     : DL_Motion / 伺服过载降额
   一句话   : 按连续负载率与 I2t 累积量计算转矩降额系数，恢复时带滞回并锁存过载报警
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnable 功能使能；fLoadRatio 连续负载率 1.0=额定；fDtSec 采样周期 [s]
              fI2tLimit 累积限值 [%·s]；fCoolGain 冷却泄放增益 [1/s]
              fDerateStart 降额起始负载率；fDerateMin 最小降额系数；fHyst 恢复滞回带
              xReset 过载锁存复位沿
   输出契约 : fDerateFactor 降额系数 0..1；fI2tAccum 累积量 [%·s]
              xDerated 降额生效（滞回保持）；xOverload 过载锁存
              xValid 输入有效；iErrorCode 0=正常 1=非有限 2=参数非法 3=过载
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION_BLOCK FB_DL_ServoOverloadDerate
VAR_INPUT
    xEnable : BOOL;                     // 降额功能使能 | derating enable
    fLoadRatio : REAL;                  // 连续负载率 1.0=额定 | continuous load ratio
    fDtSec : REAL := 0.004;             // 采样周期 [s] | sample period [s]
    fI2tLimit : REAL := 100.0;          // I2t 累积限值 [%·s] | i2t limit [%·s]
    fCoolGain : REAL := 1.0;            // 冷却泄放增益 [1/s] | cooling decay gain [1/s]
    fDerateStart : REAL := 0.8;         // 降额起始负载率 | derate start ratio
    fDerateMin : REAL := 0.3;           // 最小降额系数 | minimum derate factor
    fHyst : REAL := 0.05;               // 恢复滞回带宽 | recovery hysteresis band
    xReset : BOOL;                      // 过载锁存复位沿 | overload reset edge
END_VAR
VAR_OUTPUT
    fDerateFactor : REAL;               // 转矩降额系数 0..1 | torque derate factor
    fI2tAccum : REAL;                   // I2t 累积量 [%·s] | i2t accumulator [%·s]
    xDerated : BOOL;                    // 降额生效标志（滞回） | derating active with hysteresis
    xOverload : BOOL;                   // 过载锁存报警 | latched overload alarm
    xValid : BOOL;                      // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                   // 故障码 0=无故障 | error code
END_VAR
VAR
    _fDt : REAL;                        // 钳位后采样周期 [s] | clamped dt [s]
    _fR : REAL;                         // 钳位后负载率 | clamped load ratio
    _fI2t : REAL;                       // 内部 I2t 累积量 [%·s] | internal i2t accumulator
    _fDen : REAL;                       // 降额计算分母 | derate denominator
    _xBad : BOOL;                       // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                    // 参数非法标志 | invalid parameter flag
    _rtReset : R_TRIG;                  // 复位上升沿 | reset rising edge
END_VAR

// ---- 无条件每周期调用：复位沿检测 ----
_rtReset(CLK := xReset);

// ---- 非有限值检测 ----
_xBad := (fLoadRatio <> fLoadRatio) OR ((fLoadRatio - fLoadRatio) <> (fLoadRatio - fLoadRatio))
      OR (fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec))
      OR (fI2tLimit <> fI2tLimit) OR ((fI2tLimit - fI2tLimit) <> (fI2tLimit - fI2tLimit))
      OR (fCoolGain <> fCoolGain) OR ((fCoolGain - fCoolGain) <> (fCoolGain - fCoolGain));

// ---- 参数合法性：所有分母与滞回带必须为正 ----
_xBadPar := (fI2tLimit <= 0.0) OR (fCoolGain <= 0.0) OR (fHyst < 0.0)
         OR (fDerateStart <= 0.0) OR (fDerateStart >= 1.0)
         OR (fDerateMin <= 0.0) OR (fDerateMin >= 1.0);

// ---- 输出预置：xDerated / xOverload 为保持量，不在本处清零 ----
fDerateFactor := 1.0;
xValid := FALSE;
iErrorCode := 0;
IF _xBad THEN
    iErrorCode := 1;                                  // 输入非有限
ELSIF _xBadPar THEN
    iErrorCode := 2;                                  // 参数非法
END_IF

IF _xBad OR _xBadPar THEN
    fDerateFactor := 1.0;                             // 参数不可信时保守输出满转矩
    fI2tAccum := _fI2t;
ELSE
    xValid := TRUE;

    // 周期钳位：防止零除与超大积分步长
    _fDt := fDtSec;
    IF _fDt < 0.000001 THEN
        _fDt := 0.000001;
    ELSIF _fDt > 0.2 THEN
        _fDt := 0.2;
    END_IF
    _fR := fLoadRatio;
    IF _fR < 0.0 THEN
        _fR := 0.0;
    ELSIF _fR > 10.0 THEN
        _fR := 10.0;
    END_IF

    // ---- I2t 累积与冷却泄放 ----
    IF _fR > 1.0 THEN
        _fI2t := _fI2t + (_fR * _fR - 1.0) * _fDt;    // 过载段净累积
    ELSE
        _fI2t := _fI2t - fCoolGain * (1.0 - _fR) * _fDt;  // 轻载段泄放
    END_IF
    IF _fI2t < 0.0 THEN
        _fI2t := 0.0;                                 // 累积量不取负值
    END_IF

    // ---- 滞回判定降额生效：进入无滞回，退出需低于起始值且累积已泄完 ----
    IF _fR >= fDerateStart THEN
        xDerated := TRUE;
    ELSIF (_fR < (fDerateStart - fHyst)) AND (_fI2t <= 0.0) THEN
        xDerated := FALSE;
    END_IF

    // ---- 降额系数：起始负载率到额定线性过渡 ----
    IF xDerated THEN
        _fDen := 1.0 - fDerateStart;
        IF _fDen > 0.000000001 THEN
            fDerateFactor := 1.0 - (1.0 - fDerateMin) * (_fR - fDerateStart) / _fDen;
        END_IF
        IF fDerateFactor < fDerateMin THEN
            fDerateFactor := fDerateMin;
        ELSIF fDerateFactor > 1.0 THEN
            fDerateFactor := 1.0;
        END_IF
    END_IF

    // ---- 过载锁存与唯一解除路径 ----
    IF _fI2t >= fI2tLimit THEN
        xOverload := TRUE;
    END_IF
    IF _rtReset.Q AND NOT xEnable THEN
        xOverload := FALSE;                           // 解除路径：复位沿且功能未使能
        _fI2t := 0.0;
    END_IF
    IF xOverload THEN
        iErrorCode := 3;                              // 过载锁存状态优先
    END_IF
    fI2tAccum := _fI2t;
END_IF
END_FUNCTION_BLOCK
