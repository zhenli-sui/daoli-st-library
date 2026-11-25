(* ===========================================================================
   组件名   : FB_DL_ServoBrakeReleaseSeq
   分类     : DL_Motion / 伺服抱闸时序
   一句话   : 抱闸释放与闭合时序：先励磁后释放、先卸转矩后抱闸，含确认反馈与逐步超时
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xOpenReq 释放请求；xCloseReq 闭合请求；xExciteFbk 励磁就绪反馈
              xBrakeOpenFbk 抱闸已释放反馈；xBrakeClosedFbk 抱闸已闭合反馈
              lrTorqueFbk 实际转矩反馈 [%]；lrTorqueZeroBand 零转矩判定带宽 [%]
              t*Timeout 各步超时；xReset 复位上升沿
   输出契约 : xExciteCmd 励磁指令；xBrakeReleaseCmd 抱闸释放指令 TRUE=释放
              xTorqueHoldCmd 零转矩保持指令；xOpenDone / xCloseDone 完成标志
              xError 故障锁存（唯一解除路径 = xReset 上升沿 AND 无释放请求）
              iErrorCode 1=励磁超时 2=释放超时 3=卸转矩超时 4=闭合超时 5=转矩非有限 9=非法状态
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_ServoBrakeState :
(
    eIdle := 0,           // 空闲 | idle
    eExcite := 1,         // 下发励磁 | issue excitation
    eWaitExcite := 2,     // 等待励磁反馈 | wait excitation feedback
    eReleaseBrake := 3,   // 下发抱闸释放 | issue brake release
    eWaitBrakeOpen := 4,  // 等待抱闸释放反馈 | wait brake open feedback
    eReady := 5,          // 释放完成保持 | release done hold
    eHoldTorque := 6,     // 卸转矩到零 | unload torque to zero
    eCloseBrake := 7,     // 下发抱闸闭合 | issue brake close
    eWaitBrakeClose := 8, // 等待抱闸闭合反馈 | wait brake close feedback
    eDone := 9,           // 闭合完成 | close done
    eFault := 10          // 故障锁存态 | latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_ServoBrakeReleaseSeq
VAR_INPUT
    xOpenReq : BOOL;                        // 抱闸释放请求 | brake open request
    xCloseReq : BOOL;                       // 抱闸闭合请求 | brake close request
    xExciteFbk : BOOL;                      // 励磁就绪反馈 | excitation ready feedback
    xBrakeOpenFbk : BOOL;                   // 抱闸已释放反馈 | brake opened feedback
    xBrakeClosedFbk : BOOL;                 // 抱闸已闭合反馈 | brake closed feedback
    lrTorqueFbk : LREAL;                    // 实际转矩反馈 [%] | actual torque feedback [%]
    lrTorqueZeroBand : LREAL := 2.0;        // 零转矩判定带宽 [%] | zero torque band [%]
    tExciteTimeout : TIME := T#2S;          // 励磁超时 | excitation timeout
    tBrakeOpenTimeout : TIME := T#2S;       // 抱闸释放超时 | brake open timeout
    tTorqueZeroTimeout : TIME := T#5S;      // 卸转矩超时 | torque unload timeout
    tBrakeCloseTimeout : TIME := T#2S;      // 抱闸闭合超时 | brake close timeout
    xReset : BOOL;                          // 故障复位上升沿 | fault reset rising edge
END_VAR
VAR_OUTPUT
    xExciteCmd : BOOL;                      // 励磁指令 | excitation command
    xBrakeReleaseCmd : BOOL;                // 抱闸释放指令 TRUE=释放 | brake release command
    xTorqueHoldCmd : BOOL;                  // 零转矩保持指令 | zero torque hold command
    xOpenDone : BOOL;                       // 释放完成 | open done
    xCloseDone : BOOL;                      // 闭合完成 | close done
    xError : BOOL;                          // 故障锁存 | latched fault
    iErrorCode : INT;                       // 故障码 0=无故障 | error code
    eStateOut : E_DL_ServoBrakeState;         // 当前状态观测 | current state observation
END_VAR
VAR
    _eState : E_DL_ServoBrakeState := eIdle;  // 内部状态机状态 | internal state
    _xTorqueOk : BOOL;                      // 转矩已到零带内 | torque within zero band
    _tonExcite : TON;                       // 励磁等待定时器 | excitation wait timer
    _tonOpen : TON;                         // 释放等待定时器 | open wait timer
    _tonTorque : TON;                       // 卸转矩定时器 | torque unload timer
    _tonClose : TON;                        // 闭合等待定时器 | close wait timer
    _rtReset : R_TRIG;                      // 复位上升沿 | reset rising edge
END_VAR

// ---- 转矩零带判定：带宽须为正且转矩值须有限 ----
_xTorqueOk := FALSE;
IF (lrTorqueZeroBand > 0.0)
   AND NOT ((lrTorqueFbk <> lrTorqueFbk) OR ((lrTorqueFbk - lrTorqueFbk) <> (lrTorqueFbk - lrTorqueFbk)))
   AND (ABS(lrTorqueFbk) < lrTorqueZeroBand) THEN
    _xTorqueOk := TRUE;
END_IF

// ---- 定时器与边沿：无条件每周期调用 ----
_tonExcite(IN := (_eState = eWaitExcite), PT := tExciteTimeout);
_tonOpen(IN := (_eState = eWaitBrakeOpen), PT := tBrakeOpenTimeout);
_tonTorque(IN := (_eState = eHoldTorque), PT := tTorqueZeroTimeout);
_tonClose(IN := (_eState = eWaitBrakeClose), PT := tBrakeCloseTimeout);
_rtReset(CLK := xReset);

// ---- 逐拍输出预置：非锁存量复位，xError / iErrorCode 保持 ----
xExciteCmd := FALSE;
xBrakeReleaseCmd := FALSE;
xTorqueHoldCmd := FALSE;

CASE _eState OF
    eIdle:
        IF xOpenReq AND NOT xError THEN
            _eState := eExcite;
        END_IF

    eExcite:
        xExciteCmd := TRUE;                      // 先建励磁，保证抱闸打开时无溜车
        _eState := eWaitExcite;

    eWaitExcite:
        xExciteCmd := TRUE;
        IF xExciteFbk THEN
            _eState := eReleaseBrake;
        ELSIF _tonExcite.Q THEN
            xError := TRUE; iErrorCode := 1;     // 励磁超时
            _eState := eFault;
        END_IF

    eReleaseBrake:
        xExciteCmd := TRUE;
        xBrakeReleaseCmd := TRUE;                // 励磁已就绪，释放抱闸
        _eState := eWaitBrakeOpen;

    eWaitBrakeOpen:
        xExciteCmd := TRUE;
        xBrakeReleaseCmd := TRUE;
        IF xBrakeOpenFbk THEN
            _eState := eReady;
        ELSIF _tonOpen.Q THEN
            xError := TRUE; iErrorCode := 2;     // 抱闸释放超时
            _eState := eFault;
        END_IF

    eReady:
        xExciteCmd := TRUE;
        xBrakeReleaseCmd := TRUE;
        IF xCloseReq OR NOT xOpenReq THEN
            _eState := eHoldTorque;              // 收到闭合请求或撤请求，先卸转矩
        END_IF

    eHoldTorque:
        xExciteCmd := TRUE;
        xBrakeReleaseCmd := TRUE;                // 抱闸仍保持释放，仅撤转矩
        xTorqueHoldCmd := TRUE;
        IF _xTorqueOk THEN
            _eState := eCloseBrake;
        ELSIF _tonTorque.Q THEN
            xError := TRUE; iErrorCode := 3;     // 卸转矩超时
            _eState := eFault;
        END_IF

    eCloseBrake:
        xExciteCmd := TRUE;
        xTorqueHoldCmd := TRUE;
        xBrakeReleaseCmd := FALSE;               // 转矩已到零，闭合抱闸
        _eState := eWaitBrakeClose;

    eWaitBrakeClose:
        xExciteCmd := TRUE;
        xTorqueHoldCmd := TRUE;
        IF xBrakeClosedFbk THEN
            _eState := eDone;
        ELSIF _tonClose.Q THEN
            xError := TRUE; iErrorCode := 4;     // 抱闸闭合超时
            _eState := eFault;
        END_IF

    eDone:
        IF NOT xOpenReq THEN
            _eState := eIdle;                    // 请求撤销后回空闲
        END_IF

    eFault:
        xError := TRUE;                          // 故障锁存保持，抱闸因失电而夹紧
        IF _rtReset.Q AND NOT xOpenReq THEN
            xError := FALSE;                     // 唯一解除路径：复位沿且无释放请求
            iErrorCode := 0;
            _eState := eIdle;
        END_IF

ELSE
    xError := TRUE; iErrorCode := 9;             // 非法状态兜底
    _eState := eFault;
END_CASE;

// ---- 完成标志统一出口映射 ----
xOpenDone := (_eState = eReady);
xCloseDone := (_eState = eDone);
eStateOut := _eState;
END_FUNCTION_BLOCK
