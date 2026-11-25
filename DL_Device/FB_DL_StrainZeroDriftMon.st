(* ===========================================================================
   组件名   : FB_DL_StrainZeroDriftMon
   分类     : DL_Device / 应变零点漂移监控
   一句话   : 空载窗口内平滑跟踪零点并累计漂移速率与总漂移量，超限锁存报警
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnable 监控使能；fReading 当前读数 [µε]；xNoLoad 空载窗口标志
              fZeroNominal 标称零点 [µε]；fDtSec 采样周期 [s]；fWindowSec 窗口最短判定时长 [s]
              fRateLimit 漂移速率限值 [µε/min]；fAbsLimit 总漂移限值 [µε]；xReset 复位沿
   输出契约 : fZeroEst 跟踪零点 [µε]；fDriftRate 漂移速率 [µε/min]
              fDriftTotal 相对标称零点的总漂移 [µε]；fWindowSecOut 当前窗口时长 [s]
              xAlarm 超限锁存；xValid 输入有效
              iErrorCode 0=正常 1=非有限 2=参数非法 3=漂移超限
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION_BLOCK FB_DL_StrainZeroDriftMon
VAR_INPUT
    xEnable : BOOL;                     // 监控使能 | monitoring enable
    fReading : REAL;                    // 当前读数 [µε] | current reading [µε]
    xNoLoad : BOOL;                     // 空载窗口标志 | no-load window flag
    fZeroNominal : REAL := 0.0;         // 标称零点 [µε] | nominal zero [µε]
    fDtSec : REAL := 0.01;              // 采样周期 [s] | sample period [s]
    fWindowSec : REAL := 30.0;          // 窗口最短判定时长 [s] | min window duration [s]
    fRateLimit : REAL := 2.0;           // 漂移速率限值 [µε/min] | drift rate limit [µε/min]
    fAbsLimit : REAL := 20.0;           // 总漂移限值 [µε] | total drift limit [µε]
    xReset : BOOL;                      // 报警复位上升沿 | alarm reset rising edge
END_VAR
VAR_OUTPUT
    fZeroEst : REAL;                    // 跟踪零点 [µε] | tracked zero [µε]
    fDriftRate : REAL;                  // 漂移速率 [µε/min] | drift rate [µε/min]
    fDriftTotal : REAL;                 // 总漂移量 [µε] | total drift [µε]
    fWindowSecOut : REAL;               // 当前窗口时长 [s] | current window duration [s]
    xAlarm : BOOL;                      // 漂移超限锁存 | latched drift alarm
    xValid : BOOL;                      // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                   // 故障码 0=无故障 | error code
END_VAR
VAR
    _fDt : REAL;                        // 钳位后采样周期 [s] | clamped dt [s]
    _fWin : REAL;                       // 窗口累计时长 [s] | accumulated window [s]
    _fZeroStart : REAL;                 // 窗口起始零点 [µε] | zero at window start [µε]
    _fZero : REAL;                      // 内部跟踪零点 [µε] | internal tracked zero [µε]
    _xBad : BOOL;                       // 输入非有限标志 | not-finite flag
    _xBadPar : BOOL;                    // 参数非法标志 | invalid parameter flag
    _rtReset : R_TRIG;                  // 复位上升沿 | reset rising edge
END_VAR

// ---- 无条件每周期调用：复位沿检测 ----
_rtReset(CLK := xReset);

// ---- 非有限检测 ----
_xBad := (fReading <> fReading) OR ((fReading - fReading) <> (fReading - fReading))
      OR (fZeroNominal <> fZeroNominal) OR ((fZeroNominal - fZeroNominal) <> (fZeroNominal - fZeroNominal))
      OR (fDtSec <> fDtSec) OR ((fDtSec - fDtSec) <> (fDtSec - fDtSec));

// ---- 参数合法性 ----
_xBadPar := (fDtSec <= 0.0) OR (fWindowSec <= 0.0) OR (fRateLimit <= 0.0) OR (fAbsLimit <= 0.0);

// ---- 输出预置：报警为锁存量，不在本处清零 ----
fDriftRate := 0.0;
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
ELSIF _fDt > 0.5 THEN
    _fDt := 0.5;
END_IF

IF xValid AND xEnable THEN
    IF xNoLoad THEN
        IF _fWin <= 0.0 THEN
            _fZeroStart := fReading;               // 窗口起点锁定零点基准
            _fZero := fReading;
        ELSE
            _fZero := _fZero + 0.05 * (fReading - _fZero);   // 指数平滑跟踪，抑制噪声
        END_IF
        _fWin := _fWin + _fDt;

        // ---- 速率计算：窗口至少满 1 s 才有意义（防除零） ----
        IF _fWin > 1.0 THEN
            fDriftRate := (_fZero - _fZeroStart) / _fWin * 60.0;   // 分母已守卫
        END_IF
    ELSE
        _fWin := 0.0;                              // 退出空载窗口即重新开始
    END_IF

    // ---- 总漂移相对标称零点 ----
    fDriftTotal := _fZero - fZeroNominal;

    // ---- 超限置位：窗口须先满最短判定时长，避免上电瞬间误报 ----
    IF (_fWin >= fWindowSec) THEN
        IF (ABS(fDriftRate) > fRateLimit) OR (ABS(fDriftTotal) > fAbsLimit) THEN
            xAlarm := TRUE;
        END_IF
    END_IF
END_IF

// ---- 报警锁存与唯一解除路径 ----
// 解除门要求 NOT xEnable，必须放在使能门控块之外评估，否则该路径永不可达
IF _rtReset.Q AND NOT xEnable THEN
    xAlarm := FALSE;
END_IF
IF xAlarm THEN
    iErrorCode := 3;
END_IF

fZeroEst := _fZero;
fWindowSecOut := _fWin;
END_FUNCTION_BLOCK
