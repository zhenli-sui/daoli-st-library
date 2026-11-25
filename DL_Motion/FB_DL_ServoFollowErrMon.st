(* ===========================================================================
   组件名   : FB_DL_ServoFollowErrMon
   分类     : DL_Motion / 伺服跟随误差监控
   一句话   : 位置指令与反馈之差经一阶低通后按预警/停机两级阈值分级报警，含非有限值拦截
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnable 监控使能；lrPosCmd / lrPosFbk 位置指令与反馈 [mm]
              lrWarnLimit / lrStopLimit 两级阈值 [mm]；fLpfAlpha 低通系数 0..1
              tTripDelay 停机确认延时；xReset 复位上升沿
   输出契约 : lrFollowErr 滤波后跟随误差 [mm]；xWarn 预警（每拍重算，信息级）
              xStopTrip 停机锁存（唯一解除路径 = xReset 上升沿 AND 监控未使能）
              xValid 输入有效；iErrorCode 0=正常 1=输入非有限 2=阈值非法
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

FUNCTION_BLOCK FB_DL_ServoFollowErrMon
VAR_INPUT
    xEnable : BOOL;                     // 监控使能 | monitoring enable
    lrPosCmd : LREAL;                   // 位置指令 [mm] | position command [mm]
    lrPosFbk : LREAL;                   // 位置反馈 [mm] | position feedback [mm]
    lrWarnLimit : LREAL := 5.0;         // 预警阈值 [mm] | warning limit [mm]
    lrStopLimit : LREAL := 10.0;        // 停机阈值 [mm] | stop limit [mm]
    fLpfAlpha : LREAL := 0.2;           // 一阶低通系数 0..1 | first order lpf alpha
    tTripDelay : TIME := T#50MS;        // 停机确认延时 | trip confirm delay
    xReset : BOOL;                      // 故障复位上升沿 | fault reset rising edge
END_VAR
VAR_OUTPUT
    lrFollowErr : LREAL;                // 滤波后跟随误差 [mm] | filtered following error [mm]
    xWarn : BOOL;                       // 预警输出（每拍重算） | warning output recomputed
    xStopTrip : BOOL;                   // 停机锁存输出 | latched stop trip
    xValid : BOOL;                      // 输入有效标志 | inputs valid flag
    iErrorCode : INT;                   // 故障码 0=无故障 | error code
END_VAR
VAR
    _lrErrMag : LREAL;                  // 误差绝对值 [mm] | absolute error [mm]
    _lrAlpha : LREAL;                   // 钳位后低通系数 | clamped lpf alpha
    _xBadCmd : BOOL;                    // 指令非有限 | command not finite
    _xBadFbk : BOOL;                    // 反馈非有限 | feedback not finite
    _xBadLim : BOOL;                    // 阈值非有限 | limits not finite
    _tonTrip : TON;                     // 停机确认定时器 | trip confirm timer
    _rtReset : R_TRIG;                  // 复位上升沿 | reset rising edge
END_VAR

// ---- 无条件每周期调用：复位沿检测 ----
_rtReset(CLK := xReset);

// ---- 非有限检测：NaN 用自反比较，Inf 用 (x-x)<>(x-x) ----
_xBadCmd := (lrPosCmd <> lrPosCmd) OR ((lrPosCmd - lrPosCmd) <> (lrPosCmd - lrPosCmd));
_xBadFbk := (lrPosFbk <> lrPosFbk) OR ((lrPosFbk - lrPosFbk) <> (lrPosFbk - lrPosFbk));
_xBadLim := (lrWarnLimit <> lrWarnLimit) OR ((lrWarnLimit - lrWarnLimit) <> (lrWarnLimit - lrWarnLimit))
         OR (lrStopLimit <> lrStopLimit) OR ((lrStopLimit - lrStopLimit) <> (lrStopLimit - lrStopLimit));

xValid := NOT (_xBadCmd OR _xBadFbk OR _xBadLim);
xWarn := FALSE;
iErrorCode := 0;
IF _xBadLim THEN
    iErrorCode := 2;                                  // 阈值非有限
ELSIF _xBadCmd OR _xBadFbk THEN
    iErrorCode := 1;                                  // 位置量非有限
END_IF
IF xValid AND ((lrWarnLimit <= 0.0) OR (lrStopLimit <= lrWarnLimit)) THEN
    xValid := FALSE;                                  // 阈值须为正值且停机阈值大于预警阈值
    iErrorCode := 2;
END_IF

// ---- 一阶低通：系数钳位到 0..1，避免发散 ----
_lrAlpha := fLpfAlpha;
IF _lrAlpha < 0.0 THEN
    _lrAlpha := 0.0;
ELSIF _lrAlpha > 1.0 THEN
    _lrAlpha := 1.0;
END_IF
IF xValid THEN
    _lrErrMag := ABS(lrPosCmd - lrPosFbk);
    lrFollowErr := lrFollowErr + _lrAlpha * (_lrErrMag - lrFollowErr);
ELSE
    lrFollowErr := 0.0;                               // 非法输入不污染滤波器状态
END_IF

// ---- 停机确认定时器：无条件每周期调用 ----
_tonTrip(IN := (lrFollowErr > lrStopLimit) AND xValid, PT := tTripDelay);

// ---- 两级分级判定 ----
xWarn := xValid AND (lrFollowErr > lrWarnLimit);
IF _tonTrip.Q THEN
    xStopTrip := TRUE;                                // 超阈值持续到延时后锁存
END_IF
IF _rtReset.Q AND NOT xEnable THEN
    xStopTrip := FALSE;                               // 唯一解除路径：复位沿且监控未使能
END_IF
IF NOT xEnable THEN
    xWarn := FALSE;                                   // 未使能时预警不对外输出
END_IF
END_FUNCTION_BLOCK
