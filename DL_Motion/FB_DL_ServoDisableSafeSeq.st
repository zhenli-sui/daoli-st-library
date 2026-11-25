(* ===========================================================================
   组件名   : FB_DL_ServoDisableSafeSeq
   分类     : DL_Motion / 伺服安全下使能时序
   一句话   : 先减速到零速→撤使能→确认抱闸夹紧的安全下使能时序，任一步超时转故障态
   复杂度   : 1        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xDisableReq 下使能请求；fVelAbs 速度绝对值 [rpm]；fZeroBand 零速带 [rpm]
              xEnableFbk 驱动器使能反馈；xBrakeClosedFbk 抱闸夹紧反馈
    工况边界  : 本件为「SS1 型受控停车序」（IEC 60204-1 停止类别 1 语义）：
                减速到零 -> 保持使能撤除 -> 抱闸闭合。适用于水平轴 / 无重力负载轴。
                **重力负载轴（垂直 Z 轴、举升轴）请改用 FB_DL_AxisBrakeSeq**：
                该件为抱闸优先序（先合抱闸建立力矩再撤使能），防自由滑落。
                二者顺序相反是工况差异所致，非缺陷；属主边界以本声明为准。
              t*Timeout 三步超时；xReset 复位上升沿
   输出契约 : xDecelCmd 减速指令；xEnableCmd 使能指令（撤使能后为 FALSE）
              xBrakeReleaseCmd 恒为 FALSE（失电夹紧为安全侧）
              xDone 时序完成；xError 故障锁存；iErrorCode 1=减速超时 2=撤使能超时
              3=抱闸超时 9=非法状态
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_DisableSeqState :
(
    eIdle := 0,          // 空闲 | idle
    eDecel := 1,         // 下发减速 | issue deceleration
    eWaitZero := 2,      // 等待零速 | wait zero speed
    eDisable := 3,       // 撤销使能 | drop enable
    eWaitDisable := 4,   // 等待使能撤销确认 | wait enable dropped
    eBrake := 5,         // 下发抱闸夹紧 | issue brake clamp
    eWaitBrake := 6,     // 等待抱闸确认 | wait brake confirm
    eDone := 7,          // 时序完成 | sequence done
    eFault := 8          // 故障锁存态 | latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_ServoDisableSafeSeq
VAR_INPUT
    xDisableReq : BOOL;                     // 下使能请求 | disable request
    fVelAbs : REAL;                         // 速度绝对值 [rpm] | absolute speed [rpm]
    fZeroBand : REAL := 5.0;                // 零速判定带宽 [rpm] | zero speed band [rpm]
    xEnableFbk : BOOL;                      // 驱动器使能反馈 | drive enabled feedback
    xBrakeClosedFbk : BOOL;                 // 抱闸夹紧反馈 | brake clamped feedback
    tDecelTimeout : TIME := T#10S;          // 减速超时 | deceleration timeout
    tDisableTimeout : TIME := T#2S;         // 撤使能超时 | disable timeout
    tBrakeTimeout : TIME := T#2S;           // 抱闸夹紧超时 | brake timeout
    xReset : BOOL;                          // 故障复位上升沿 | fault reset rising edge
END_VAR
VAR_OUTPUT
    xDecelCmd : BOOL;                       // 减速指令 | deceleration command
    xEnableCmd : BOOL;                      // 使能指令 | enable command
    xBrakeReleaseCmd : BOOL;                // 抱闸释放指令（安全侧恒 FALSE） | brake release, always FALSE
    xDone : BOOL;                           // 时序完成 | sequence done
    xError : BOOL;                          // 故障锁存 | latched fault
    iErrorCode : INT;                       // 故障码 0=无故障 | error code
    eStateOut : E_DL_DisableSeqState;       // 当前状态观测 | current state observation
END_VAR
VAR
    _eState : E_DL_DisableSeqState := eIdle;  // 内部状态机状态 | internal state
    _xBadVel : BOOL;                      // 速度非有限或带宽非法 | velocity invalid
    _tonDecel : TON;                      // 减速等待定时器 | deceleration wait timer
    _tonDisable : TON;                    // 撤使能等待定时器 | disable wait timer
    _tonBrake : TON;                      // 抱闸等待定时器 | brake wait timer
    _rtReset : R_TRIG;                    // 复位上升沿 | reset rising edge
END_VAR

// ---- 速度合法性：非有限或带宽非正时视为未达零速 ----
_xBadVel := (fVelAbs <> fVelAbs) OR ((fVelAbs - fVelAbs) <> (fVelAbs - fVelAbs)) OR (fZeroBand <= 0.0);

// ---- 定时器与边沿：无条件每周期调用 ----
_tonDecel(IN := (_eState = eWaitZero), PT := tDecelTimeout);
_tonDisable(IN := (_eState = eWaitDisable), PT := tDisableTimeout);
_tonBrake(IN := (_eState = eWaitBrake), PT := tBrakeTimeout);
_rtReset(CLK := xReset);

// ---- 逐拍输出预置：非锁存量复位；抱闸释放恒 FALSE 为安全侧 ----
xDecelCmd := FALSE;
xEnableCmd := FALSE;
xBrakeReleaseCmd := FALSE;
xDone := FALSE;

CASE _eState OF
    eIdle:
        IF xDisableReq AND NOT xError THEN
            _eState := eDecel;
        END_IF

    eDecel:
        xDecelCmd := TRUE;
        xEnableCmd := TRUE;                      // 减速段必须保持使能，否则失控滑行
        _eState := eWaitZero;

    eWaitZero:
        xDecelCmd := TRUE;
        xEnableCmd := TRUE;
        IF (NOT _xBadVel) AND (ABS(fVelAbs) < fZeroBand) THEN
            _eState := eDisable;                 // 已到零速，可撤使能
        ELSIF _tonDecel.Q THEN
            xError := TRUE; iErrorCode := 1;     // 减速超时
            _eState := eFault;
        END_IF

    eDisable:
        _eState := eWaitDisable;                 // 本拍起使能指令保持 FALSE

    eWaitDisable:
        IF NOT xEnableFbk THEN
            _eState := eBrake;                   // 使能已撤销，再动抱闸
        ELSIF _tonDisable.Q THEN
            xError := TRUE; iErrorCode := 2;     // 撤使能超时
            _eState := eFault;
        END_IF

    eBrake:
        _eState := eWaitBrake;                   // 抱闸释放指令保持 FALSE，失电夹紧

    eWaitBrake:
        IF xBrakeClosedFbk THEN
            _eState := eDone;
        ELSIF _tonBrake.Q THEN
            xError := TRUE; iErrorCode := 3;     // 抱闸夹紧超时
            _eState := eFault;
        END_IF

    eDone:
        xDone := TRUE;
        IF NOT xDisableReq THEN
            _eState := eIdle;                    // 请求撤销后回空闲
        END_IF

    eFault:
        xError := TRUE;                          // 故障锁存保持，输出维持安全侧
        IF _rtReset.Q AND NOT xDisableReq THEN
            xError := FALSE;                     // 唯一解除路径：复位沿且无请求
            iErrorCode := 0;
            _eState := eIdle;
        END_IF

ELSE
    xError := TRUE; iErrorCode := 9;             // 非法状态兜底
    _eState := eFault;
END_CASE;

eStateOut := _eState;
END_FUNCTION_BLOCK
