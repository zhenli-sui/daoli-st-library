(*
  ============================================================
  组件名 : FB_DL_HydroPressRampSeq
  分类   : DL_Device
  功能   : 液压建压斜坡顺序控制，建压升压保压泄压按斜率给定并含超时保护
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
  配比约束 : tonRamp 与 tonHold 共用 tHoldTimeout 作为监视窗（升压窗与保压窗各一实例，
             两者互不累计）；tReleaseTimeout 单独覆盖泄压相。默认值须全部大于零。
  降级语义 : 实测压力非有限时冻结斜坡并保持上一有限设定输出，bPressOk 置假，不置故障码。
  故障码   : 1 保压超时 / 2 升压超时 / 3 泄压超时。码 3 不可由 1 与 2 观测——1 与 2 只在
             升压相与保压相置位，泄压相进入故障时码必为 0，故单开 3 以区分成因。
             复位唯一路径：bBuildCmd 或 bReleaseCmd 上升沿。
  ============================================================
*)

TYPE E_DL_HydroRampState :
(
    eIdle     := 0, // 待机，设定保持在零 idle with the set point at zero
    eRampUp   := 1, // 升压相，按斜率逼近目标 pressure ramp up towards the target
    eHold     := 2, // 保压相，设定保持目标 pressure hold at the target
    eRampDown := 3, // 泄压相，按斜率降到零 pressure ramp down to zero
    eFault    := 4  // 故障锁存相 latched fault phase
);
END_TYPE

FUNCTION_BLOCK FB_DL_HydroPressRampSeq
VAR_INPUT
    bBuildCmd      : BOOL; // 建压命令 pressure build command
    bReleaseCmd    : BOOL; // 泄压命令 pressure release command
    rPressAct      : REAL; // 实测压力 [bar] actual pressure [bar]
    rPressTarget   : REAL; // 目标压力 [bar] target pressure [bar]
    rRampBarPerS   : REAL; // 升压斜率 [bar/s] ramp rate [bar per second]
    rHoldBand      : REAL; // 保压允差带 [bar] hold band [bar]
    tHoldTimeout   : TIME; // 保压与升压监视窗 [ms] hold and ramp watchdog window
    tReleaseTimeout: TIME; // 泄压监视窗 [ms] release watchdog window
END_VAR
VAR_OUTPUT
    rPressSp   : REAL; // 压力设定输出 [bar] pressure set point [bar]
    eState     : E_DL_HydroRampState; // 当前状态 current state
    bPressOk   : BOOL; // 保压到位标志 pressure reached flag
    nFaultCode : INT; // 故障码 0无 1保压超时 2升压超时 3泄压超时 [码] fault code [code]
END_VAR
VAR
    _eState  : E_DL_HydroRampState := E_DL_HydroRampState.eIdle; // 内部状态 internal state
    _rSp     : REAL := 0.0; // 斜坡积分设定量 [bar] ramped set point [bar]
    _nFault  : INT := 0; // 故障码锁存内部量 latched fault code
    _bFin    : BOOL := FALSE; // 实数输入有限性判定 finiteness verdict of the real inputs
    _rBand   : REAL := 0.0; // 钳位后的允差带 [bar] clamped hold band [bar]
    tonTick  : TON; // 一秒节拍计时 one second tick timer
    tonHold  : TON; // 保压超时计时 hold timeout timer
    tonRamp  : TON; // 升压超时计时 ramp timeout timer
    tonRelease : TON; // 泄压超时计时 release timeout timer
    rtBuild  : R_TRIG; // 建压命令上升沿 build command rising edge
    rtRelease: R_TRIG; // 泄压命令上升沿 release command rising edge
END_VAR

// 段 0｜定时器与沿实例无条件周期刷新 unconditional cyclic refresh of timers and edges
tonTick(IN := NOT tonTick.Q, PT := T#1S); // 一秒自复位节拍 one second self reset tick
tonHold(IN := (_eState = E_DL_HydroRampState.eHold) AND (_nFault = 0), PT := tHoldTimeout); // 保压超时 hold timeout
tonRamp(IN := (_eState = E_DL_HydroRampState.eRampUp) AND (_nFault = 0), PT := tHoldTimeout); // 升压超时 ramp timeout
tonRelease(IN := (_eState = E_DL_HydroRampState.eRampDown) AND (_nFault = 0), PT := tReleaseTimeout); // 泄压超时 release timeout
rtBuild(CLK := bBuildCmd); // 建压沿刷新 refresh the build edge
rtRelease(CLK := bReleaseCmd); // 泄压沿刷新 refresh the release edge
// 段 1｜出口预置与输入整形 preset the outputs and reshape the inputs
bPressOk := FALSE; // 到位标志每拍先假 the reached flag is false each scan first
_rBand := rHoldBand; // 取入参允差带 take the hold band input
IF _rBand < 0.0 THEN
    _rBand := ABS(_rBand); // 负允差带取幅值 a negative band becomes its magnitude
END_IF
_bFin := (rPressAct = rPressAct) AND (rPressTarget = rPressTarget) AND (rRampBarPerS = rRampBarPerS) AND (rHoldBand = rHoldBand); // 四输入自反判定 self comparison of the four inputs
IF NOT _bFin THEN
    rPressSp := _rSp; // 冻结斜坡并输出上一有限设定 freeze the ramp and emit the last finite set point
    eState := _eState; // 状态出口按锁存量 map the state
    nFaultCode := _nFault; // 故障码出口按锁存量 map the fault code
    RETURN; // 非有限测量不迁相，早退 the non finite reading changes no phase
END_IF
// 段 2｜主状态机 main state machine
CASE _eState OF
E_DL_HydroRampState.eIdle: // 待机相 idle phase
    _rSp := 0.0; // 待机设定归零 the set point returns to zero
    IF rtBuild.Q AND (NOT bReleaseCmd) AND (rPressTarget > 0.0) AND (rRampBarPerS > 0.0) THEN
        _eState := E_DL_HydroRampState.eRampUp; // 组态合法才迁升压相 migrate only when the configuration is legal
    END_IF
E_DL_HydroRampState.eRampUp: // 升压相 ramp up phase
    IF tonTick.Q THEN
        _rSp := LIMIT(0.0, _rSp + rRampBarPerS, rPressTarget); // 每满一秒按斜率推进 advance one ramp step per full second
    END_IF
    IF (rPressAct >= (rPressTarget - _rBand)) AND (ABS(_rSp - rPressTarget) < 1.0E-3) THEN
        _eState := E_DL_HydroRampState.eHold; // 设定到位且反馈入带则迁保压 both the set point and the feedback are in place
    ELSIF tonRamp.Q THEN
        _nFault := 2; // 升压超时故障码 ramp timeout fault code
        _eState := E_DL_HydroRampState.eFault; // 迁故障相 migrate to the fault phase
    END_IF
E_DL_HydroRampState.eHold: // 保压相 hold phase
    _rSp := rPressTarget; // 设定保持目标 the set point holds the target
    IF ABS(rPressAct - rPressTarget) <= _rBand THEN
        bPressOk := TRUE; // 反馈在允差带内 the feedback sits inside the band
    END_IF
    IF rtRelease.Q OR bReleaseCmd THEN
        _eState := E_DL_HydroRampState.eRampDown; // 泄压命令优先于超时 the release command outranks the timeout
    ELSIF tonHold.Q THEN
        _nFault := 1; // 保压超时故障码 hold timeout fault code
        _eState := E_DL_HydroRampState.eFault; // 迁故障相 migrate to the fault phase
    END_IF
E_DL_HydroRampState.eRampDown: // 泄压相 ramp down phase
    IF tonTick.Q THEN
        _rSp := LIMIT(0.0, _rSp - rRampBarPerS, rPressTarget); // 每满一秒按斜率回落 fall one ramp step per full second
    END_IF
    IF (rPressAct < 0.5) AND (_rSp < 1.0E-3) THEN
        _rSp := 0.0; // 设定归零 the set point lands at zero
        _eState := E_DL_HydroRampState.eIdle; // 回待机 return to idle
    ELSIF tonRelease.Q THEN
        _nFault := 3; // 泄压超时故障码 release timeout fault code
        _eState := E_DL_HydroRampState.eFault; // 迁故障相 migrate to the fault phase
    END_IF
E_DL_HydroRampState.eFault: // 故障锁存相 latched fault phase
    IF rtBuild.Q OR rtRelease.Q THEN
        _nFault := 0; // 复位清故障码 the reset edge clears the fault code
        _rSp := 0.0; // 复位设定归零 the reset edge clears the set point
        _eState := E_DL_HydroRampState.eIdle; // 复位回待机 the reset edge returns to idle
    END_IF
ELSE // 非法状态枚举兜底 the illegal state fallback
    _eState := E_DL_HydroRampState.eIdle; // 非法状态回落待机 an illegal state falls back to idle
END_CASE
// 段 3｜统一出口映射 the unified exit mapping
rPressSp := _rSp; // 设定出口 map the set point
eState := _eState; // 状态出口 map the state
nFaultCode := _nFault; // 故障码出口 map the fault code
END_FUNCTION_BLOCK
