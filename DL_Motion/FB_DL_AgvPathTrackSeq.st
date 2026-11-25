// FB_DL_AgvPathTrackSeq v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: AGV 路径跟踪序列相位机：IDLE →(xStart∧xEnable) ALIGN →(双容差对齐) TRACK
        →(xObstacle) AVOID →(障碍解除∧保持 2 s) TRACK；TRACK →(xDockZone) DOCK
        →(对齐∧dist<0.05) IDLE 置 xDone。速度按 0.5 m/s² 斜坡逼近（增量 0.5·fCycleS，不阶跃），
        AVOID 与 FAULT 相强制零速零转。几何律全部委托外部 FC，本件不含三角函数。
  邻件: 对桩律 FC_DL_AgvChargeDockAlignCalc、限速 FC_DL_AgvSpeedLimitProfileCalc 为上游计算件。
  码表: 9311 入参非有限｜9312 组态非法(fSpeedLimit/fCycleS≤0)｜9313 相超时(ALIGN 5s/AVOID 保持/DOCK 15s)
        9314 相位落 ELSE 兜底｜9315 信息级序列完成（不置故障）。故障码锁存至 xReset 上升沿。
  边界: 无方法块/无属性块/无全局变量/无物理 IO 地址；三 TON 单相独占且无条件刷新。
*)
TYPE E_DL_AgvTrackState :
(
    IDLE  := 0,     // 空闲：等启动指令 [-] / Idle, waiting start
    ALIGN := 10,    // 对准：横向与角度对桩 [-] / Aligning to dock
    TRACK := 20,    // 跟踪：沿路径行驶 [-] / Tracking the path
    AVOID := 30,    // 避障：零速等待障碍解除 [-] / Avoiding obstacle
    DOCK  := 40,    // 入桩：末端贴近充电桩 [-] / Docking approach
    FAULT := 90     // 故障：锁存，仅复位沿可出 [-] / Fault latched
);
END_TYPE
FUNCTION_BLOCK FB_DL_AgvPathTrackSeq
VAR_INPUT
    xEnable     : BOOL := FALSE;        // 使能，FALSE 时全相冻结 [-] / Enable gate
    xStart      : BOOL := FALSE;        // 启动指令，上升沿有效 [-] / Start rising edge
    xReset      : BOOL := FALSE;        // 复位，上升沿清故障锁存 [-] / Reset rising edge
    xObstacle   : BOOL := FALSE;        // 障碍检测输入 [-] / Obstacle detected
    xDockZone   : BOOL := FALSE;        // 入桩区检测输入 [-] / Dock zone detected
    fOffsetY    : REAL := 0.0;          // 横向偏差 [m]，左正 / Lateral offset [m]
    fAngleErr   : REAL := 0.0;          // 角度偏差 [rad]，左正 / Angular error [rad]
    fDist       : REAL := 2.0;          // 到桩距离 [m] / Distance to dock [m]
    fSpeedLimit : REAL := 1.0;          // 允许限速 [m/s]，域 > 0 / Speed limit [m/s]
    fCycleS     : REAL := 0.01;         // 任务周期 [s]，域 > 0 / Task cycle time [s]
END_VAR
VAR_OUTPUT
    eState      : E_DL_AgvTrackState;   // 相位出口，段尾单点映射 [-] / Phase outlet
    xRun        : BOOL;                 // 运行中标志（非 IDLE 非 FAULT）[-] / Running flag
    fSpeedCmd   : REAL;                 // 前进速度指令 [m/s] / Speed command [m/s]
    fYawRateCmd : REAL;                 // 转向角速度指令 [rad/s] / Yaw rate command [rad/s]
    xDone       : BOOL;                 // 序列完成单拍脉冲 [-] / Done one-shot pulse
    xFault      : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    uErrorId    : UDINT;                // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonAlign  : TON;                    // ALIGN 相超时 5 s，单相独占刷新 / Align timeout
    tonAvoid  : TON;                    // AVOID 障碍保持窗 2 s，单相独占刷新 / Avoid hold window
    tonDock   : TON;                    // DOCK 相超时 15 s，单相独占刷新 / Dock timeout
    rtStart   : R_TRIG;                 // 启动沿实例，无条件刷新 / Start edge instance
    rtReset   : R_TRIG;                 // 复位沿实例，无条件刷新 / Reset edge instance
    _eState   : E_DL_AgvTrackState := E_DL_AgvTrackState.IDLE;  // 内部相位，CASE 唯一写入 / Internal phase
    _fSpeed   : REAL := 0.0;            // 斜坡速度内部量 [m/s] / Ramp speed [m/s]
    _fSpTar   : REAL := 0.0;            // 本相速度目标 [m/s] / Phase speed target [m/s]
    _fYawTar  : REAL := 0.0;            // 本相转向目标 [rad/s] / Phase yaw target [rad/s]
    _fStep    : REAL := 0.0;            // 本周期斜坡增量 [m/s] / Per-cycle ramp step [m/s]
    _bAligned : BOOL := FALSE;          // 本拍对齐判据 [-] / Alignment judgement
    _bFault   : BOOL := FALSE;          // 故障锁存位（锁存量，仅复位沿清）/ Latched fault bit
    _uFault   : UDINT := 16#0000;       // 故障码锁存（锁存量，仅复位沿清）/ Latched fault code
    _uInfo    : UDINT := 16#0000;       // 信息码，每拍重算 / Transient info code
END_VAR
// 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内，R7）/ Unconditional refresh
rtStart(CLK := xStart);                                              // 启动沿每拍必调 / Start edge
rtReset(CLK := xReset);                                              // 复位沿每拍必调 / Reset edge
tonAlign(IN := (_eState = E_DL_AgvTrackState.ALIGN), PT := T#5S);    // 对准相超时 / Align timeout
tonAvoid(IN := (_eState = E_DL_AgvTrackState.AVOID), PT := T#2S);    // 避障保持窗 / Avoid window
tonDock(IN := (_eState = E_DL_AgvTrackState.DOCK), PT := T#15S);     // 入桩相超时 / Dock timeout
// 段 1：单拍量预清零（锁存量 _bFault/_uFault/_fSpeed 不入清单，R187）/ One-shot clear
_uInfo := 16#0000;                  // 信息码每拍重算 / Info code recomputed
xDone := FALSE;                     // 完成脉冲缺省清 / Done pulse clear
_fSpTar := 0.0;                     // 速度目标缺省零 / Speed target default zero
_fYawTar := 0.0;                    // 转向目标缺省零 / Yaw target default zero
_bAligned := FALSE;                 // 对齐判据缺省假 / Alignment default false
// 段 2：非有限闸与组态域闸（归因唯一，逐因独立码，R190）/ Gate stage
IF (fOffsetY <> fOffsetY) OR (fAngleErr <> fAngleErr) OR (fDist <> fDist)
   OR (fSpeedLimit <> fSpeedLimit) OR (fCycleS <> fCycleS)
   OR (ABS(fOffsetY) >= 3.0E38) OR (ABS(fAngleErr) >= 3.0E38) OR (ABS(fDist) >= 3.0E38)
   OR (ABS(fSpeedLimit) >= 3.0E38) OR (ABS(fCycleS) >= 3.0E38) THEN
    _uFault := 16#0002_9311;        // 故障级：入参非有限 / Fault: non-finite input
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
IF (fSpeedLimit <= 1.0E-6) OR (fCycleS <= 1.0E-6) THEN
    _uFault := 16#0002_9312;        // 故障级：组态非法 / Fault: illegal configuration
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
// 段 3：复位沿（FAULT 唯一解除路径）/ Reset edge, the only exit from fault
IF rtReset.Q THEN                   // rtReset.Q = 当拍量 / Reset edge is per-scan
    IF _eState = E_DL_AgvTrackState.FAULT THEN
        _eState := E_DL_AgvTrackState.IDLE;     // 故障相迁出回空闲 / Fault exits to idle
    END_IF
    _fSpeed := 0.0;                 // 斜坡量归零（锁存量解除）/ Ramp cleared on reset
    _bFault := FALSE;               // 清故障锁存位（仅此解除沿可清）/ Clear latched bit
    _uFault := 16#0000;             // 清故障锁存码（仅此解除沿可清）/ Clear latched code
END_IF
// 段 3b：对齐判据（ALIGN 与 DOCK 共用）/ Alignment judgement shared by two phases
IF (ABS(fOffsetY) <= 0.02) AND (ABS(fAngleErr) <= 0.03) THEN
    _bAligned := TRUE;              // 双容差内判对齐 / Within both tolerances
END_IF
// 段 4：相位机（本拍合法事件优先于超时，R275）/ Phase machine
CASE _eState OF
E_DL_AgvTrackState.IDLE:
    IF _bFault THEN
        _eState := E_DL_AgvTrackState.FAULT;        // 聚合故障进故障相 / Enter fault
    ELSIF rtStart.Q AND xEnable THEN
        _fSpeed := 0.0;                             // 起步斜坡复位 / Reset ramp on start
        _eState := E_DL_AgvTrackState.ALIGN;        // 进对准相 / Enter align
    END_IF
E_DL_AgvTrackState.ALIGN:
    IF _bFault THEN
        _eState := E_DL_AgvTrackState.FAULT;        // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _eState := E_DL_AgvTrackState.IDLE;         // 使能撤销回空闲 / Enable dropped
    ELSIF _bAligned THEN
        _eState := E_DL_AgvTrackState.TRACK;        // 对齐到位进跟踪 / Aligned, track
    ELSIF tonAlign.Q THEN
        _uFault := 16#0002_9313;                    // 故障级：对准相超时 / Align timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _eState := E_DL_AgvTrackState.FAULT;        // 进故障相 / Enter fault
    ELSE
        IF fDist > 0.0 THEN
            _fSpTar := 0.3 * fDist;                 // 距离比例降速 / Distance speed
        ELSE
            _fSpTar := 0.0;                         // 距离为负/零：零速（R92 修，禁倒车指令）
        END_IF
        IF _fSpTar > 0.2 THEN
            _fSpTar := 0.2;                         // 对准相限速上限 / Align ceiling
        END_IF
        _fYawTar := 1.5 * fAngleErr;                // 角度比例转向 / Angular yaw
    END_IF
E_DL_AgvTrackState.TRACK:
    IF _bFault THEN
        _eState := E_DL_AgvTrackState.FAULT;        // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _eState := E_DL_AgvTrackState.IDLE;         // 使能撤销回空闲 / Enable dropped
    ELSIF xObstacle THEN
        _eState := E_DL_AgvTrackState.AVOID;        // 障碍进避障 / Obstacle, avoid
    ELSIF xDockZone THEN
        _eState := E_DL_AgvTrackState.DOCK;         // 入桩区进入桩 / Dock zone, dock
    ELSE
        _fSpTar := fSpeedLimit;                     // 跟踪取限速 / Tracking uses limit
        _fYawTar := 1.0 * fAngleErr;                // 航向保持转向 / Heading hold yaw
    END_IF
E_DL_AgvTrackState.AVOID:
    IF NOT xEnable THEN
        _eState := E_DL_AgvTrackState.IDLE;         // 使能撤销回空闲 / Enable dropped
    ELSIF (NOT xObstacle) AND tonAvoid.Q THEN
        _eState := E_DL_AgvTrackState.TRACK;        // 障碍解除且保持到位回跟踪 / Cleared with hold
    ELSE
        _fSpeed := 0.0;                             // 避障零速（安全侧）/ Avoid zero speed
    END_IF
E_DL_AgvTrackState.DOCK:
    IF _bFault THEN
        _eState := E_DL_AgvTrackState.FAULT;        // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _eState := E_DL_AgvTrackState.IDLE;         // 使能撤销回空闲 / Enable dropped
    ELSIF _bAligned AND (fDist < 0.05) THEN
        _fSpeed := 0.0;                             // 到位停稳 / Stop on position
        xDone := TRUE;                              // 完成脉冲单拍 / One-shot done
        _uInfo := 16#0002_9315;                     // 信息级：序列完成 / Info: done
        _eState := E_DL_AgvTrackState.IDLE;         // 回空闲 / Return to idle
    ELSIF tonDock.Q THEN
        _uFault := 16#0002_9313;                    // 故障级：入桩相超时 / Dock timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _eState := E_DL_AgvTrackState.FAULT;        // 进故障相 / Enter fault
    ELSE
        IF fDist > 0.0 THEN
            _fSpTar := 0.3 * fDist;                 // 末端贴近降速 / Final approach
        ELSE
            _fSpTar := 0.0;                         // 距离为负/零：零速（R92 修）
        END_IF
        IF _fSpTar > 0.1 THEN
            _fSpTar := 0.1;                         // 入桩相限速上限 / Dock ceiling
        END_IF
        _fYawTar := 1.5 * fAngleErr;                // 末段角度纠正 / Final angular fix
    END_IF
E_DL_AgvTrackState.FAULT:
    _fSpeed := 0.0;                                 // 故障相零速保持 / Fault zero speed
    IF rtReset.Q THEN
        _eState := E_DL_AgvTrackState.IDLE;         // 复位沿解除（段 3 已清锁存）/ Reset releases
    END_IF
ELSE
    _uFault := 16#0002_9314;                        // 故障级：非法相位兜底 / Illegal phase id
    _bFault := TRUE;                                // 置故障锁存（R45 配对）/ Set latch
    _fSpeed := 0.0;                                 // 非法相位零速 / Illegal phase zero speed
    _eState := E_DL_AgvTrackState.FAULT;            // 强制进故障相 / Force into fault
END_CASE
// 段 4b：转向目标限幅 ±0.4 rad/s / Yaw target clamping
IF _fYawTar > 0.4 THEN
    _fYawTar := 0.4;                                // 上饱和 / Upper saturation
ELSIF _fYawTar < -0.4 THEN
    _fYawTar := -0.4;                               // 下饱和 / Lower saturation
END_IF
// 段 4c：速度斜坡（禁阶跃；AVOID/FAULT 相不回填）/ Speed ramp, no step allowed
IF (_eState = E_DL_AgvTrackState.AVOID) OR (_eState = E_DL_AgvTrackState.FAULT) THEN
    _fSpeed := 0.0;                                 // 安全相斜坡归零 / Safety phases zero
ELSE
    _fStep := 0.5 * fCycleS;                        // 增量 = 0.5·fCycleS / Per-cycle step
    IF _fSpeed < _fSpTar THEN
        _fSpeed := _fSpeed + _fStep;                // 斜坡升速 / Ramp up
        IF _fSpeed > _fSpTar THEN
            _fSpeed := _fSpTar;                     // 不得越过目标 / No overshoot
        END_IF
    ELSIF _fSpeed > _fSpTar THEN
        _fSpeed := _fSpeed - _fStep;                // 斜坡降速 / Ramp down
        IF _fSpeed < _fSpTar THEN
            _fSpeed := _fSpTar;                     // 不得越过目标 / No overshoot
        END_IF
    END_IF
END_IF
// 段 5：出口单点映射（名实双出口，R191）/ Outlet mapping
eState := _eState;                                  // 相位出口单点映射 / Phase outlet
IF (_eState = E_DL_AgvTrackState.FAULT) OR _bFault THEN
    fSpeedCmd := 0.0;                               // 故障侧速度硬零 / Fault speed hard zero
    fYawRateCmd := 0.0;                             // 故障侧转向硬零 / Fault yaw hard zero
    xRun := FALSE;                                  // 故障侧非运行 / Not running
    xFault := TRUE;                                 // 故障锁存回放 / Replay latched flag
    uErrorId := _uFault;                            // 故障码锁存回放 / Replay latched code
ELSIF _eState = E_DL_AgvTrackState.IDLE THEN
    fSpeedCmd := 0.0;                               // 空闲相零速 / Idle zero speed
    fYawRateCmd := 0.0;                             // 空闲相零转 / Idle zero yaw
    xRun := FALSE;                                  // 空闲相非运行 / Not running
    xFault := FALSE;                                // 无故障 / No fault
    uErrorId := _uInfo;                             // 信息码重组 / Transient info code
ELSE
    fSpeedCmd := _fSpeed;                           // 运行相输出斜坡速度 / Ramp speed outlet
    fYawRateCmd := _fYawTar;                        // 运行相输出限幅转向 / Clamped yaw outlet
    xRun := TRUE;                                   // 运行中 / Running
    xFault := FALSE;                                // 无故障 / No fault
    uErrorId := _uInfo;                             // 信息码重组 / Transient info code
END_IF
IF (fSpeedCmd <> fSpeedCmd) OR (fYawRateCmd <> fYawRateCmd)
   OR (ABS(fSpeedCmd) >= 3.0E38) OR (ABS(fYawRateCmd) >= 3.0E38) OR (fSpeedCmd < 0.0) THEN
    fSpeedCmd := 0.0;                               // 出口复核失败回零速 / Outlet recheck zero
    fYawRateCmd := 0.0;                             // 出口复核失败回零转 / Outlet recheck zero
    xRun := FALSE;                                  // 复核失败撤运行 / Clear running
    xFault := TRUE;                                 // 复核失败置故障 / Raise fault
    uErrorId := 16#0002_9311;                       // 故障级：出口非有限 / Fault: non-finite outlet
END_IF
END_FUNCTION_BLOCK
