(* ===========================================================================
   组件名   : FB_DL_ServoEnableSeq
   分类     : DL_Motion / 伺服使能时序
   一句话   : 主回路就绪→使能→抱闸释放→就绪的上电使能时序，含超时与失败回退
   复杂度   : 2        版本 : v1.0.0        日期 : 2026-11-24
   开源溯源 : 无（clean-room 自研，未借鉴任何开源实现）
   输入契约 : xEnableReq 使能请求；xMainsReady 主回路就绪；xEnableFbk 使能反馈
              xBrakeFbk 抱闸释放到位反馈；t*Timeout 各步超时；xReset 复位上升沿
   输出契约 : xEnableCmd 使能指令；xBrakeReleaseCmd 抱闸释放指令；xReady 时序就绪
              xError 故障锁存（唯一解除路径 = xReset 上升沿 AND 无使能请求）
              iErrorCode 1=主回路超时 2=使能超时 3=抱闸超时 4=使能丢失 9=非法状态
   修改记录 : v1.0.0 2026-11-24 初版
   =========================================================================== *)

TYPE E_DL_ServoEnableState :
(
    eIdle := 0,          // 空闲 | idle
    eWaitMains := 1,     // 等待主回路就绪 | wait mains ready
    eEnable := 2,        // 下发使能指令 | issue enable command
    eWaitEnable := 3,    // 等待使能反馈 | wait enable feedback
    eReleaseBrake := 4,  // 下发抱闸释放 | issue brake release
    eWaitBrake := 5,     // 等待抱闸反馈 | wait brake feedback
    eReady := 6,         // 时序完成就绪 | sequence ready
    eFault := 7          // 故障锁存态 | latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_ServoEnableSeq
VAR_INPUT
    xEnableReq : BOOL;                    // 使能请求 TRUE=上使能 | enable request
    xMainsReady : BOOL;                   // 主回路就绪反馈 | main circuit ready feedback
    xEnableFbk : BOOL;                    // 驱动器使能反馈 | drive enabled feedback
    xBrakeFbk : BOOL;                     // 抱闸释放到位反馈 | brake released feedback
    xReset : BOOL;                        // 故障复位上升沿有效 | fault reset rising edge
    tMainsTimeout : TIME := T#5S;         // 主回路就绪超时 | mains ready timeout
    tEnableTimeout : TIME := T#2S;        // 使能反馈超时 | enable feedback timeout
    tBrakeTimeout : TIME := T#2S;         // 抱闸反馈超时 | brake feedback timeout
END_VAR
VAR_OUTPUT
    xEnableCmd : BOOL;                    // 使能指令输出 | enable command output
    xBrakeReleaseCmd : BOOL;              // 抱闸释放指令 TRUE=释放 | brake release command
    xReady : BOOL;                        // 时序完成就绪 | sequence ready
    xError : BOOL;                        // 故障锁存标志 | latched fault flag
    iErrorCode : INT;                     // 故障码 0=无故障 | error code
    eStateOut : E_DL_ServoEnableState;    // 当前状态观测输出 | current state observation
END_VAR
VAR
    _eState : E_DL_ServoEnableState := eIdle;  // 内部状态机状态 | internal state
    _tonMains : TON;                      // 主回路等待定时器 | mains wait timer
    _tonEnable : TON;                     // 使能等待定时器 | enable wait timer
    _tonBrake : TON;                      // 抱闸等待定时器 | brake wait timer
    _rtReset : R_TRIG;                    // 复位上升沿检测 | reset edge detect
END_VAR

// ---- 定时器与边沿检测：无条件每周期调用，禁止放入条件分支 ----
_tonMains(IN := (_eState = eWaitMains), PT := tMainsTimeout);
_tonEnable(IN := (_eState = eWaitEnable), PT := tEnableTimeout);
_tonBrake(IN := (_eState = eWaitBrake), PT := tBrakeTimeout);
_rtReset(CLK := xReset);

// ---- 逐拍输出预置：仅非锁存量复位；xError / iErrorCode 保持锁存 ----
xEnableCmd := FALSE;
xBrakeReleaseCmd := FALSE;
xReady := FALSE;

CASE _eState OF
    eIdle:
        IF xEnableReq AND NOT xError THEN
            IF xMainsReady THEN
                _eState := eEnable;                  // 主回路已就绪，直接进使能
            ELSE
                _eState := eWaitMains;               // 否则先等主回路就绪
            END_IF
        END_IF

    eWaitMains:
        IF xMainsReady THEN
            _eState := eEnable;                      // 主回路就绪，转入使能
        ELSIF _tonMains.Q THEN
            xError := TRUE; iErrorCode := 1;         // 主回路就绪超时
            _eState := eFault;
        END_IF

    eEnable:
        xEnableCmd := TRUE;                          // 本拍下发使能指令
        _eState := eWaitEnable;                      // 下一拍起等待反馈

    eWaitEnable:
        xEnableCmd := TRUE;
        IF xEnableFbk THEN
            _eState := eReleaseBrake;                // 使能确认后再动抱闸
        ELSIF _tonEnable.Q THEN
            xError := TRUE; iErrorCode := 2;         // 使能反馈超时
            _eState := eFault;
        END_IF

    eReleaseBrake:
        xEnableCmd := TRUE;
        xBrakeReleaseCmd := TRUE;                    // 先励磁使能，后释放抱闸
        _eState := eWaitBrake;

    eWaitBrake:
        xEnableCmd := TRUE;
        xBrakeReleaseCmd := TRUE;
        IF xBrakeFbk THEN
            xReady := TRUE;
            _eState := eReady;
        ELSIF _tonBrake.Q THEN
            xError := TRUE; iErrorCode := 3;         // 抱闸释放反馈超时
            _eState := eFault;
        END_IF

    eReady:
        xEnableCmd := TRUE;
        xBrakeReleaseCmd := TRUE;
        xReady := TRUE;
        IF NOT xEnableReq THEN
            _eState := eIdle;                        // 撤请求回空闲（抱闸交由下使能时序）
        ELSIF NOT xEnableFbk THEN
            xError := TRUE; iErrorCode := 4;         // 就绪后使能意外丢失
            _eState := eFault;
        END_IF

    eFault:
        xError := TRUE;                              // 故障锁存保持，不在故障相重新推断
        IF _rtReset.Q AND NOT xEnableReq THEN
            xError := FALSE;                         // 唯一解除路径：复位沿且无使能请求
            iErrorCode := 0;
            _eState := eIdle;
        END_IF

ELSE
    xError := TRUE; iErrorCode := 9;                 // 非法状态兜底：锁存并回安全态
    _eState := eFault;
END_CASE;

eStateOut := _eState;                                // 状态统一出口映射
END_FUNCTION_BLOCK
