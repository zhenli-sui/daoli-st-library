(*
  DL Factory R84 | FB_DL_CncLoadUnloadSeq
  功能：机床上下料八相时序状态机，逐相超时置故障码并锁存至复位沿
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
TYPE E_DL_CncUsState :
(
    eIdle := 0, // 空闲待启动 [-] / idle, waiting for start [-]
    eDoorOpen := 1, // 开门相 [-] / door opening phase [-]
    eClampOpen := 2, // 夹具松开相 [-] / clamp opening phase [-]
    ePartLoad := 3, // 上料相 [-] / part loading phase [-]
    eClampClose := 4, // 夹具夹紧相 [-] / clamp closing phase [-]
    eDoorClose := 5, // 关门相 [-] / door closing phase [-]
    eCycleStart := 6, // 加工启动相 [-] / cycle start phase [-]
    eDone := 7, // 完成相 [-] / done phase [-]
    eFault := 8 // 故障锁存相 [-] / fault latched phase [-]
) := eIdle;
END_TYPE

FUNCTION_BLOCK FB_DL_CncLoadUnloadSeq
VAR_INPUT
    xStart : BOOL; // 启动按钮 [-] / start pushbutton [-]
    xReset : BOOL; // 复位按钮（上升沿清故障码） [-] / reset pushbutton [-]
    xDoorOpened : BOOL; // 门开到位反馈 [-] / door open limit [-]
    xDoorClosed : BOOL; // 门关到位反馈 [-] / door closed limit [-]
    xClampOpened : BOOL; // 夹具松开到位反馈 [-] / clamp open limit [-]
    xClampClosed : BOOL; // 夹具夹紧到位反馈 [-] / clamp closed limit [-]
    xPartPresent : BOOL; // 工件在位检测 [-] / part present sensor [-]
    xCycleAllowed : BOOL; // 加工许可互锁（外部给定） [-] / cycle permit interlock [-]
    xCycleDone : BOOL; // 加工完成反馈 [-] / cycle finished feedback [-]
    tPhaseLimit : TIME := T#10S; // 单相超时门限 [s] / per phase timeout limit [s]
END_VAR
VAR_OUTPUT
    eState : E_DL_CncUsState; // 当前时序状态 [-] / current sequence state [-]
    iErrCode : INT; // 故障码 0=正常，101~106=逐相超时，201=非法相位 [-] / error code [-]
    xBusy : BOOL; // 时序执行中 [-] / sequence busy [-]
    xDone : BOOL; // 完成单拍脉冲 [-] / done one-shot pulse [-]
END_VAR
VAR
    rtStart : R_TRIG; // 启动上升沿实例 [-] / start rising edge instance [-]
    rtReset : R_TRIG; // 复位上升沿实例 [-] / reset rising edge instance [-]
    tonPhase : TON; // 相超时定时器（全相共用） [-] / shared phase timeout timer [-]
    xTimerRun : BOOL; // 定时器运行使能 [-] / timer run enable [-]
    tLimit : TIME; // 当前相超时设定 [s] / current phase timeout preset [s]
    xTimeout : BOOL; // 本拍超时标志 [-] / timeout flag of this scan [-]
    xDoneInt : BOOL; // 完成内部锁存位 [-] / internal done latch [-]
    xDonePrev : BOOL; // 完成前拍快照 [-] / done previous scan snapshot [-]
    _eState : E_DL_CncUsState := E_DL_CncUsState.eIdle; // 内部相位（CASE 唯一写目标） [-] / internal phase [-]
    _ePrev : E_DL_CncUsState := E_DL_CncUsState.eIdle; // 相位前拍快照（供自复位判沿） [-] / previous phase snapshot [-]
    xPhaseChg : BOOL; // 相位切换当拍标志 [-] / phase change flag of this scan [-]
    _iErr : INT; // 故障码内部锁存 [-] / latched error code [-]
END_VAR

// 段 0｜边沿实例无条件周期刷新（R7）
rtStart(CLK := xStart); // 启动沿每拍必调 [-] / start edge called every scan [-]
rtReset(CLK := xReset); // 复位沿每拍必调 [-] / reset edge called every scan [-]

// 段 1｜按相位选超时预设（必须在定时器调用之前完成）
CASE _eState OF
    E_DL_CncUsState.eIdle: tLimit := T#0S; // 空闲不计时 [s] / no timing in idle [s]
    E_DL_CncUsState.eDone: tLimit := T#0S; // 完成不计时 [s] / no timing in done [s]
    E_DL_CncUsState.eFault: tLimit := T#0S; // 故障不计时 [s] / no timing in fault [s]
ELSE
    tLimit := tPhaseLimit; // 其余工作相按门限计时 [s] / working phases use the limit [s]
END_CASE

// 段 2｜定时器无条件周期刷新（CASE 之外，无 IF 包裹；换相即自复位，R7/R188）
xPhaseChg := _eState <> _ePrev; // 相位切换沿 [-] / phase change edge [-]
xTimerRun := (((_eState <> E_DL_CncUsState.eIdle) AND (_eState <> E_DL_CncUsState.eDone)) AND (_eState <> E_DL_CncUsState.eFault)) AND NOT xPhaseChg; // 工作相定时使能，换相当拍拉低以复位计时 [-] / timing enable, dropped on a phase change to restart [-]
tonPhase(IN := xTimerRun, PT := tLimit); // 无条件刷新 [-] / unconditional refresh [-]
xTimeout := tonPhase.Q; // 本拍超时判定 [-] / timeout verdict of this scan [-]
_ePrev := _eState; // 相位快照在定时器之后更新（本拍迁移下一拍生效） [-] / phase snapshot updated after the timer call [-]

// 段 3｜复位沿：清单为故障码 + 内部锁存 + 相位，不含 Prev/Acc 保持量（R189）
IF rtReset.Q THEN
    _iErr := 0; // 清故障码 [-] / clear error code [-]
    xDoneInt := FALSE; // 清完成锁存 [-] / clear done latch [-]
    _eState := E_DL_CncUsState.eIdle; // 回空闲相 [-] / back to idle [-]
END_IF

// 段 4｜主状态机（合法事件优先于超时迁移，R275）
CASE _eState OF
    E_DL_CncUsState.eIdle: // 空闲相 [-] / idle [-]
        xDoneInt := FALSE; // 空闲清完成锁存 [-] / clear done latch in idle [-]
        IF rtStart.Q THEN
            _eState := E_DL_CncUsState.eDoorOpen; // 启动沿开安全门 [-] / start edge opens the door [-]
        END_IF
    E_DL_CncUsState.eDoorOpen: // 开门相 [-] / door opening [-]
        IF xDoorOpened THEN
            _eState := E_DL_CncUsState.eClampOpen; // 门开到位转松夹 [-] / door open leads to clamp open [-]
        ELSIF xTimeout THEN
            _iErr := 101; _eState := E_DL_CncUsState.eFault; // 开门超时 [-] / door open timeout [-]
        END_IF
    E_DL_CncUsState.eClampOpen: // 松夹相 [-] / clamp opening [-]
        IF xClampOpened THEN
            _eState := E_DL_CncUsState.ePartLoad; // 松夹到位转上料 [-] / clamp open leads to loading [-]
        ELSIF xTimeout THEN
            _iErr := 102; _eState := E_DL_CncUsState.eFault; // 松夹超时 [-] / clamp open timeout [-]
        END_IF
    E_DL_CncUsState.ePartLoad: // 上料相 [-] / part loading [-]
        IF xPartPresent AND NOT xTimeout THEN
            _eState := E_DL_CncUsState.eClampClose; // 工件在位转夹紧（带超时复检） [-] / part present leads to clamp close [-]
        ELSIF xTimeout THEN
            _iErr := 103; _eState := E_DL_CncUsState.eFault; // 上料超时（工件未到位） [-] / loading timeout [-]
        END_IF
    E_DL_CncUsState.eClampClose: // 夹紧相 [-] / clamp closing [-]
        IF xClampClosed THEN
            _eState := E_DL_CncUsState.eDoorClose; // 夹紧到位转关门 [-] / clamp closed leads to door close [-]
        ELSIF xTimeout THEN
            _iErr := 104; _eState := E_DL_CncUsState.eFault; // 夹紧超时 [-] / clamp close timeout [-]
        END_IF
    E_DL_CncUsState.eDoorClose: // 关门相 [-] / door closing [-]
        IF xDoorClosed THEN
            _eState := E_DL_CncUsState.eCycleStart; // 关门到位转加工启动 [-] / door closed leads to cycle start [-]
        ELSIF xTimeout THEN
            _iErr := 105; _eState := E_DL_CncUsState.eFault; // 关门超时 [-] / door close timeout [-]
        END_IF
    E_DL_CncUsState.eCycleStart: // 加工启动相（执行类安全相，入相全量复检） [-] / cycle start [-]
        IF xCycleDone THEN
            _eState := E_DL_CncUsState.eDone; // 加工完成转完成相 [-] / cycle done leads to done [-]
        ELSIF NOT (xCycleAllowed AND xDoorClosed) THEN
            _iErr := 106; _eState := E_DL_CncUsState.eFault; // 许可消失即故障（不空等） [-] / permit lost becomes fault [-]
        ELSIF xTimeout THEN
            _iErr := 106; _eState := E_DL_CncUsState.eFault; // 加工未完成超时 [-] / cycle start timeout [-]
        END_IF
    E_DL_CncUsState.eDone: // 完成相 [-] / done [-]
        xDoneInt := TRUE; // 置完成锁存（出口统一映射单拍） [-] / raise done latch [-]
        IF NOT xStart THEN
            _eState := E_DL_CncUsState.eIdle; // 松开启动即回空闲 [-] / start released returns to idle [-]
        END_IF
    E_DL_CncUsState.eFault: // 故障相：码值锁存回放，仅复位沿出 [-] / fault, exit only on reset edge [-]
        ; // 锁存回放，不按当下输入重新推断（R28） [-] / replay the latch only [-]
ELSE
    _iErr := 201; _eState := E_DL_CncUsState.eFault; // 非法相位兜底 [-] / illegal phase fallback [-]
END_CASE

// 段 5｜出口映射（名实双出口，同源赋值）
eState := _eState; // 状态出口 [-] / state outlet [-]
iErrCode := _iErr; // 故障码出口（锁存值） [-] / error code outlet [-]
xBusy := ((_eState <> E_DL_CncUsState.eIdle) AND (_eState <> E_DL_CncUsState.eDone)) AND (_eState <> E_DL_CncUsState.eFault); // 忙 = 工作相镜像 [-] / busy mirrors a working phase [-]
xDone := xDoneInt AND NOT xDonePrev; // 完成单拍（内部锁存 → 出口映射） [-] / done one-shot [-]
xDonePrev := xDoneInt; // 本拍快照供下拍比较 [-] / snapshot for the next scan [-]
END_FUNCTION_BLOCK
