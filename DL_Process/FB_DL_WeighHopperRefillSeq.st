(*
  ============================================================
  组件名 : FB_DL_WeighHopperRefillSeq
  分类   : DL_Process
  功能   : 料斗补料顺序控制，开阀快加慢加关阀稳定，含阀超时、稳定超时与人工停止故障
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
*)

TYPE E_DL_HopperState :
(
    eIdle      := 0, // 待机，等待启动命令 idle awaiting the start command
    eValveOpen := 1, // 开阀建流单拍相 the single scan valve opening phase
    eFastFeed  := 2, // 快速加料相 the fast feed phase
    eSlowFeed  := 3, // 慢速加料相 the slow feed phase
    eSettle    := 4, // 关阀后稳定相 the settle phase after the valve closes
    eFault     := 5, // 故障锁存相 the latched fault phase
    eDone      := 6  // 配料完成相 the dosing done phase
);
END_TYPE

FUNCTION_BLOCK FB_DL_WeighHopperRefillSeq
VAR_INPUT
    bStart         : BOOL; // 启动命令 start command
    bStop          : BOOL; // 停止命令 stop command
    rWeight        : REAL; // 料斗实测重量 [kg] measured hopper weight [kg]
    rTargetHigh    : REAL; // 高料位目标 [kg] high level target [kg]
    rTargetLow     : REAL; // 快慢切换点 [kg] fast to slow switching point [kg]
    rSettleBand    : REAL; // 稳定允差带 [kg] settle band [kg]
    tValveTimeout  : TIME; // 加料阀超时窗 [ms] feed valve timeout window
    tSettleTimeout : TIME; // 稳定超时窗 [ms] settle timeout window
END_VAR
VAR_OUTPUT
    bValveOpen : BOOL; // 加料阀开命令 feed valve open command
    bFastFeed  : BOOL; // 快加料命令 fast feed command
    bSlowFeed  : BOOL; // 慢加料命令 slow feed command
    eState     : E_DL_HopperState; // 当前状态 current state
    bDone      : BOOL; // 完成标志，保持到复位沿 done flag held until the reset edge
    nFaultCode : INT; // 故障码 0无 1阀超时 2稳定超时 3人工停止 [码] fault code 0 none, 1 valve, 2 settle, 3 manual stop [code]
END_VAR
VAR
    _eState  : E_DL_HopperState := E_DL_HopperState.eIdle; // 内部状态 internal state
    _bDone   : BOOL := FALSE; // 完成锁存内部量 internal done latch
    _nFault  : INT := 0; // 故障码锁存内部量 latched fault code
    _rBand   : REAL := 0.0; // 钳位后的稳定带 [kg] clamped settle band [kg]
    tonValve : TON; // 加料阀累计超时计时 accumulated valve timeout timer
    tonSettle: TON; // 稳定超时计时 settle timeout timer
    rtStart  : R_TRIG; // 启动命令上升沿 start command rising edge
    rtStop   : R_TRIG; // 停止命令上升沿 stop command rising edge
END_VAR

// 段 0｜定时器与沿实例无条件周期刷新 unconditional cyclic refresh of timers and edges
rtStart(CLK := bStart); // 启动沿刷新 refresh the start edge
rtStop(CLK := bStop); // 停止沿刷新 refresh the stop edge
tonValve(IN := ((_eState = E_DL_HopperState.eValveOpen) OR (_eState = E_DL_HopperState.eFastFeed) OR (_eState = E_DL_HopperState.eSlowFeed)) AND (_nFault = 0), PT := tValveTimeout); // 加料阀累计超时 valve cumulative timeout
tonSettle(IN := (_eState = E_DL_HopperState.eSettle) AND (_nFault = 0), PT := tSettleTimeout); // 稳定超时 settle timeout
// 段 1｜出口预置与输入整形 preset the outputs and reshape the inputs
bValveOpen := FALSE; // 阀命令每拍先关 valve command closed each scan first
bFastFeed := FALSE; // 快加命令每拍先关 fast feed off each scan first
bSlowFeed := FALSE; // 慢加命令每拍先关 slow feed off each scan first
_rBand := rSettleBand; // 取入参稳定带 take the settle band input
IF _rBand < 0.0 THEN
    _rBand := ABS(_rBand); // 负稳定带取幅值 a negative band becomes its magnitude
END_IF
IF (rWeight <> rWeight) OR (rTargetHigh <> rTargetHigh) OR (rTargetLow <> rTargetLow) OR (rSettleBand <> rSettleBand) THEN
    eState := _eState; // 非有限测量或组态拒收，状态保持 refuse a non finite reading or configuration and hold the state
    bDone := _bDone; // 完成标志按锁存量输出 map the latched done flag
    nFaultCode := _nFault; // 故障码按锁存量输出 map the latched fault code
    RETURN; // 早退保护 early return for protection
END_IF
// 段 2｜停止命令优先消化，置于状态机之前 stop command digested ahead of the state machine
IF bStop AND (_eState <> E_DL_HopperState.eFault) THEN
    _nFault := 3; // 人工停止故障码 manual stop fault code
    _eState := E_DL_HopperState.eFault; // 立即迁入故障相 migrate to the fault phase at once
END_IF
// 段 3｜主状态机 main state machine
CASE _eState OF
E_DL_HopperState.eIdle: // 待机 idle
    _bDone := FALSE; // 待机相清完成锁存 clear the done latch while idle
    IF rtStart.Q AND (NOT bStop) THEN
        _eState := E_DL_HopperState.eValveOpen; // 启动沿有效则迁开阀 a valid start edge opens the valve phase
    END_IF
E_DL_HopperState.eValveOpen: // 开阀建流单拍相 single scan valve opening phase
    bValveOpen := TRUE; // 本拍只开阀 this scan only opens the valve
    _eState := E_DL_HopperState.eFastFeed; // 拍 N 进入开阀相，本拍行为只建流不作重量判据，拍 N+1 转出至快加相
E_DL_HopperState.eFastFeed: // 快速加料相 fast feed phase
    bValveOpen := TRUE; // 阀保持开 the valve stays open
    bFastFeed := TRUE; // 快加料输出有效 the fast feed output is active
    IF rWeight >= rTargetHigh THEN
        _eState := E_DL_HopperState.eSettle; // 到高料位关阀转稳定 the high target closes the valve and starts the settle phase
    ELSIF rWeight >= rTargetLow THEN
        _eState := E_DL_HopperState.eSlowFeed; // 到切换点转慢加 the switching point starts the slow feed phase
    END_IF
E_DL_HopperState.eSlowFeed: // 慢速加料相 slow feed phase
    bValveOpen := TRUE; // 阀保持开 the valve stays open
    bSlowFeed := TRUE; // 慢加料输出有效 the slow feed output is active
    IF rWeight >= rTargetHigh THEN
        _eState := E_DL_HopperState.eSettle; // 到高料位关阀转稳定 the high target closes the valve and starts the settle phase
    END_IF
E_DL_HopperState.eSettle: // 关阀后稳定相 settle phase after the valve closes
    IF ABS(rWeight - rTargetHigh) <= _rBand THEN
        _bDone := TRUE; // 稳定带内判完成 a weight inside the band completes the dosing
        _eState := E_DL_HopperState.eDone; // 迁完成相 migrate to the done phase
    ELSIF tonSettle.Q THEN
        _nFault := 2; // 稳定超时故障码 settle timeout fault code
        _eState := E_DL_HopperState.eFault; // 迁故障相 migrate to the fault phase
    END_IF
E_DL_HopperState.eDone: // 配料完成相 dosing done phase
    IF NOT bStart THEN
        _bDone := FALSE; // 启动命令消失清完成锁存 a vanished start command clears the done latch
        _eState := E_DL_HopperState.eIdle; // 回待机 return to idle
    END_IF
E_DL_HopperState.eFault: // 故障锁存相 latched fault phase
    IF rtStop.Q OR (rtStart.Q AND (NOT bStop)) THEN
        _nFault := 0; // 复位清故障码 the reset edge clears the fault code
        _bDone := FALSE; // 复位清完成锁存 the reset edge clears the done latch
        _eState := E_DL_HopperState.eIdle; // 复位回待机 the reset edge returns to idle
    END_IF
ELSE // 非法状态枚举兜底 the illegal state fallback
    _eState := E_DL_HopperState.eIdle; // 非法状态回落待机 an illegal state falls back to idle
END_CASE
// 段 4｜加料阀累计超时看门狗 the accumulated feed valve watchdog
IF tonValve.Q AND ((_eState = E_DL_HopperState.eFastFeed) OR (_eState = E_DL_HopperState.eSlowFeed) OR (_eState = E_DL_HopperState.eValveOpen)) THEN
    _nFault := 1; // 阀超时故障码 valve timeout fault code
    _eState := E_DL_HopperState.eFault; // 迁故障相 migrate to the fault phase
END_IF
// 段 5｜统一出口映射 the unified exit mapping
bDone := _bDone; // 完成标志出口 map the done flag
nFaultCode := _nFault; // 故障码出口 map the fault code
eState := _eState; // 状态出口 map the state
END_FUNCTION_BLOCK
