// FB_DL_BushingDrawStartSeq v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 拉丝启动八相顺控：IDLE→HEAT→(达标保持300s)DRIP→(检滴料)ATTACH→(丝根附着)RAMP
        →(达目标速度)STEADY→(断丝)BREAK→(重接)RAMP；RAMP 按 20 m/min² 斜坡（增量 (20/60)·fCycleS）。
        联锁：①HEAT 相温度未达 fTempTarget − 5 °C 前 xWinderEnable 必须 FALSE；
              ②BREAK 相速度降至 fSpeedTarget·0.3 并保持 60 s 等重接，超时锁存；
              ③FAULT 相 xWinderEnable = FALSE 且 fSpeedCmd = 0（安全侧），仅 xReset 解除。
  邻件: 与 FC_DL_BushingTempZoneCalc（分区温度）、FC_DL_BushingPowerBalanceCalc（功率平衡）同族，本件不调用 FC。
  码表: 9331 入参非有限｜9332 组态非法(fCycleS/fTempTarget/fSpeedTarget≤0)｜9333 相超时(1800/60/60/120/60 s)
        9334 相位落 ELSE 兜底｜9335 信息级进入稳态拉丝。故障码锁存至 xReset 上升沿。
  边界: 无方法块/无属性块/无全局变量/无物理 IO 地址；六 TON 单相独占且无条件刷新；速度单位统一 m/min。
*)
TYPE E_DL_DrawStartPhase :
(
    IDLE   := 0,        // 空闲：等启动指令 [-] / Idle, waiting start
    HEAT   := 10,       // 升温：漏板升到目标 − 5 °C 并保持 [-] / Heating bushing
    DRIP   := 20,       // 滴料：等玻璃液滴料 [-] / Waiting for drip
    ATTACH := 30,       // 附着：等丝根附着 [-] / Waiting for attachment
    RAMP   := 40,       // 升速：按 20 m/min² 升至目标 [-] / Ramping up
    STEADY := 50,       // 稳态：稳态拉丝 [-] / Steady drawing
    BREAK  := 60,       // 断丝：降速至 30% 待重接 [-] / Break, slow for re-attach
    FAULT  := 90        // 故障：锁存，仅复位沿可出 [-] / Fault latched
);
END_TYPE
FUNCTION_BLOCK FB_DL_BushingDrawStartSeq
VAR_INPUT
    xEnable         : BOOL := FALSE;    // 使能，FALSE 时冻结在 IDLE [-] / Enable gate
    xStart          : BOOL := FALSE;    // 启动指令，上升沿有效 [-] / Start rising edge
    xReset          : BOOL := FALSE;    // 复位，上升沿清故障锁存 [-] / Reset rising edge
    fBushingTemp    : REAL := 25.0;     // 漏板实测温度 [°C] / Measured bushing temperature [degC]
    fTempTarget     : REAL := 1250.0;   // 漏板目标温度 [°C]，域 > 0 / Target temperature [degC]
    xDripDetected   : BOOL := FALSE;    // 滴料检出反馈 [-] / Drip detected
    xStrandAttached : BOOL := FALSE;    // 丝根附着反馈 [-] / Strand attached
    fWinderSpeed    : REAL := 0.0;      // 卷绕实测线速 [m/min] / Measured winder speed [m/min]
    fSpeedTarget    : REAL := 900.0;    // 目标拉丝线速 [m/min]，域 > 0 / Target speed [m/min]
    xBreakDetected  : BOOL := FALSE;    // 断丝检出反馈 [-] / Break detected
    fCycleS         : REAL := 0.01;     // 任务周期 [s]，域 > 0 / Task cycle time [s]
END_VAR
VAR_OUTPUT
    ePhase        : E_DL_DrawStartPhase;    // 相位出口，段尾单点映射 [-] / Phase outlet
    xHeatEnable   : BOOL;                   // 漏板加热使能（仅 HEAT 相）[-] / Heat enable
    xWinderEnable : BOOL;                   // 卷绕使能（温度达标后）[-] / Winder enable
    fSpeedCmd     : REAL;                   // 线速指令 [m/min] / Speed command [m/min]
    xSteady       : BOOL;                   // 稳态标志（STEADY 相电平）[-] / Steady flag
    xFault        : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrorId      : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonHeat   : TON;                        // 温度达标保持窗 300 s，无条件刷新 / Temperature dwell
    tonHeatTo : TON;                        // 升温相总超时 1800 s，无条件刷新 / Heat timeout
    tonDrip   : TON;                        // 滴料相超时 60 s，无条件刷新 / Drip timeout
    tonAttach : TON;                        // 附着相超时 60 s，无条件刷新 / Attach timeout
    tonRamp   : TON;                        // 升速相超时 120 s，无条件刷新 / Ramp timeout
    tonBreak  : TON;                        // 断丝保持窗 60 s，无条件刷新 / Break hold window
    rtStart   : R_TRIG;                     // 启动沿实例，无条件刷新 / Start edge instance
    rtReset   : R_TRIG;                     // 复位沿实例，无条件刷新 / Reset edge instance
    _ePhase   : E_DL_DrawStartPhase := E_DL_DrawStartPhase.IDLE;    // 内部相位，CASE 唯一写入 / Internal phase
    _fSpeed   : REAL := 0.0;                // 速度斜坡内部量 [m/min] / Ramp speed [m/min]
    _bReady   : BOOL := FALSE;              // 温度达标判据 [-] / Temperature ready judgement
    _bFault   : BOOL := FALSE;              // 故障锁存位（锁存量，仅复位沿清）/ Latched fault bit
    _uFault   : UDINT := 16#0000;           // 故障码锁存（锁存量，仅复位沿清）/ Latched fault code
    _uInfo    : UDINT := 16#0000;           // 信息码，每拍重算 / Transient info code
END_VAR
// 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内，R7/R188）/ Unconditional refresh
rtStart(CLK := xStart);                                                     // 启动沿每拍必调 / Start edge
rtReset(CLK := xReset);                                                     // 复位沿每拍必调 / Reset edge
tonHeat(IN := (_ePhase = E_DL_DrawStartPhase.HEAT) AND (fBushingTemp >= (fTempTarget - 5.0)), PT := T#300S);
tonHeatTo(IN := (_ePhase = E_DL_DrawStartPhase.HEAT), PT := T#1800S);       // 升温总超时 / Heat timeout
tonDrip(IN := (_ePhase = E_DL_DrawStartPhase.DRIP), PT := T#60S);           // 滴料超时 / Drip timeout
tonAttach(IN := (_ePhase = E_DL_DrawStartPhase.ATTACH), PT := T#60S);       // 附着超时 / Attach timeout
tonRamp(IN := (_ePhase = E_DL_DrawStartPhase.RAMP), PT := T#120S);          // 升速超时 / Ramp timeout
tonBreak(IN := (_ePhase = E_DL_DrawStartPhase.BREAK), PT := T#60S);         // 断丝保持窗 / Break window
// 段 1：单拍量预清零（锁存量 _bFault/_uFault/_fSpeed 不入清单，R187）/ One-shot clear
_uInfo := 16#0000;                  // 信息码每拍重算 / Info code recomputed
_bReady := FALSE;                   // 温度达标判据缺省假 / Ready default false
// 段 2：非有限闸与组态域闸（归因唯一，逐因独立码，R190）/ Gate stage
IF (fBushingTemp <> fBushingTemp) OR (fTempTarget <> fTempTarget)
   OR (fWinderSpeed <> fWinderSpeed) OR (fSpeedTarget <> fSpeedTarget) OR (fCycleS <> fCycleS)
   OR (ABS(fBushingTemp) >= 3.0E38) OR (ABS(fTempTarget) >= 3.0E38)
   OR (ABS(fWinderSpeed) >= 3.0E38) OR (ABS(fSpeedTarget) >= 3.0E38) OR (ABS(fCycleS) >= 3.0E38) THEN
    _uFault := 16#0002_9331;        // 故障级：入参非有限 / Fault: non-finite input
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
IF (fCycleS <= 1.0E-6) OR (fTempTarget <= 1.0E-6) OR (fSpeedTarget <= 1.0E-6) THEN
    _uFault := 16#0002_9332;        // 故障级：组态非法 / Fault: illegal configuration
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
// 段 3：温度达标判据（HEAT 与 DRIP 共用，禁 EQUAL 比较）/ Temperature ready judgement
IF fBushingTemp >= (fTempTarget - 5.0) THEN
    _bReady := TRUE;                // 达目标 − 5 °C / Reached target minus margin
END_IF
// 段 4：复位沿（FAULT 唯一解除路径）/ Reset edge, only exit from fault
IF rtReset.Q THEN                   // rtReset.Q = 当拍量 / Reset edge per scan
    IF _ePhase = E_DL_DrawStartPhase.FAULT THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;    // 故障相迁出回空闲 / Fault exits to idle
    END_IF
    _fSpeed := 0.0;                 // 斜坡量归零（锁存量解除）/ Ramp cleared on reset
    _bFault := FALSE;               // 清故障锁存位（仅此解除沿可清）/ Clear latched bit
    _uFault := 16#0000;             // 清故障锁存码（仅此解除沿可清）/ Clear latched code
END_IF
// 段 5：相位机（本拍合法事件优先于超时，R275）/ Phase machine
CASE _ePhase OF
E_DL_DrawStartPhase.IDLE:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 聚合故障进故障相 / Enter fault
    ELSIF rtStart.Q AND xEnable THEN
        _fSpeed := 0.0;                             // 启动前进度清零 / Ramp reset on start
        _ePhase := E_DL_DrawStartPhase.HEAT;        // 进升温相 / Enter heat
    END_IF
E_DL_DrawStartPhase.HEAT:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 使能撤销回空闲 / Enable dropped
    ELSIF tonHeat.Q THEN
        _ePhase := E_DL_DrawStartPhase.DRIP;        // 达标保持 300 s：进滴料相 / Dwell done, drip
    ELSIF tonHeatTo.Q THEN
        _uFault := 16#0002_9333;                    // 故障级：升温相超时 / Heat timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 进故障相 / Enter fault
    END_IF
E_DL_DrawStartPhase.DRIP:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 使能撤销回空闲（安全侧，R92 修）/ Enable dropped to IDLE
    ELSIF xDripDetected THEN
        _ePhase := E_DL_DrawStartPhase.ATTACH;      // 检出滴料：进附着相 / Drip seen, attach
    ELSIF tonDrip.Q THEN
        _uFault := 16#0002_9333;                    // 故障级：滴料相超时 / Drip timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 进故障相 / Enter fault
    END_IF
E_DL_DrawStartPhase.ATTACH:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 使能撤销回空闲（安全侧，R92 修）/ Enable dropped to IDLE
    ELSIF xStrandAttached THEN
        _fSpeed := 0.0;                             // 升速前进度清零 / Reset ramp before spinning
        _ePhase := E_DL_DrawStartPhase.RAMP;        // 进升速相 / Enter ramp
    ELSIF tonAttach.Q THEN
        _uFault := 16#0002_9333;                    // 故障级：附着相超时 / Attach timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 进故障相 / Enter fault
    END_IF
E_DL_DrawStartPhase.RAMP:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 使能撤销回空闲（安全侧，R92 修）/ Enable dropped to IDLE
    ELSIF xBreakDetected THEN
        _ePhase := E_DL_DrawStartPhase.BREAK;       // 升速中断丝：进断丝相 / Break during ramp
    ELSIF _fSpeed >= fSpeedTarget THEN
        _uInfo := 16#0002_9335;                     // 信息级：进入稳态拉丝 / Info: steady reached
        _ePhase := E_DL_DrawStartPhase.STEADY;      // 达目标：进稳态相 / Target reached
    ELSIF tonRamp.Q THEN
        _uFault := 16#0002_9333;                    // 故障级：升速相超时 / Ramp timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 进故障相 / Enter fault
    END_IF
E_DL_DrawStartPhase.STEADY:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 使能撤销回空闲 / Enable dropped
    ELSIF xBreakDetected THEN
        _ePhase := E_DL_DrawStartPhase.BREAK;       // 断丝：进断丝相 / Break, go break
    END_IF
E_DL_DrawStartPhase.BREAK:
    IF _bFault THEN
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 使能撤销回空闲（安全侧，R92 修）/ Enable dropped to IDLE
    ELSIF xStrandAttached AND (NOT xBreakDetected) THEN
        _ePhase := E_DL_DrawStartPhase.RAMP;        // 重接成功回升速相 / Re-attached, ramp
    ELSIF tonBreak.Q THEN
        _uFault := 16#0002_9333;                    // 故障级：重接等待超时 / Re-attach timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_DrawStartPhase.FAULT;       // 进故障相 / Enter fault
    END_IF
E_DL_DrawStartPhase.FAULT:
    IF rtReset.Q THEN
        _ePhase := E_DL_DrawStartPhase.IDLE;        // 复位沿解除（段 4 已清锁存）/ Reset releases
    END_IF
ELSE
    _uFault := 16#0002_9334;                        // 故障级：非法相位兜底 / Illegal phase id
    _bFault := TRUE;                                // 置故障锁存（R45 配对）/ Set latch
    _ePhase := E_DL_DrawStartPhase.FAULT;           // 强制进故障相 / Force into fault
END_CASE
// 段 6：速度斜坡（增量 = (20/60)·fCycleS，禁阶跃；BREAK 独立降速）/ Speed ramp
IF (_ePhase = E_DL_DrawStartPhase.RAMP) THEN
    _fSpeed := _fSpeed + 20.0 / 60.0 * fCycleS;     // 斜坡升速 [m/min] / Ramp up
    IF _fSpeed > fSpeedTarget THEN
        _fSpeed := fSpeedTarget;                    // 不得越过目标 / No overshoot
    END_IF
ELSIF (_ePhase = E_DL_DrawStartPhase.STEADY) THEN
    _fSpeed := fSpeedTarget;                        // 稳态保持目标速度 / Hold target speed
ELSIF (_ePhase = E_DL_DrawStartPhase.BREAK) THEN
    _fSpeed := fSpeedTarget * 0.3;                  // 断丝相立即降至 30% / Drop to 30 percent
ELSE
    _fSpeed := 0.0;                                 // 其余相（含故障/空闲）速度零 / Other phases zero
END_IF
// 段 7：出口单点映射（名实双出口，R191；安全侧再硬清零）/ Outlet mapping
ePhase := _ePhase;                                  // 相位出口单点映射 / Phase outlet
IF (_ePhase = E_DL_DrawStartPhase.FAULT) OR _bFault THEN
    xHeatEnable := FALSE;                           // 故障侧加热硬零 / Fault heat hard zero
    xWinderEnable := FALSE;                         // 故障侧卷绕硬零 / Fault winder hard zero
    fSpeedCmd := 0.0;                               // 故障侧速度硬零 / Fault speed hard zero
    xSteady := FALSE;                               // 故障侧撤稳态 / Clear steady
    xFault := TRUE;                                 // 故障锁存回放 / Replay latched flag
    uErrorId := _uFault;                            // 故障码锁存回放 / Replay latched code
ELSE
    IF _ePhase = E_DL_DrawStartPhase.HEAT THEN
        xHeatEnable := TRUE;                        // 升温相加热使能 / Heat enable in phase
    ELSE
        xHeatEnable := FALSE;                       // 其余相不加热 / No heating
    END_IF
    IF _bReady AND (_ePhase <> E_DL_DrawStartPhase.IDLE) THEN
        xWinderEnable := TRUE;                      // 温度达标且非空闲才放行卷绕 / Winder allowed
    ELSE
        xWinderEnable := FALSE;                     // 温度未达标强制 FALSE / Winder forced off
    END_IF
    fSpeedCmd := _fSpeed;                           // 速度指令出口 / Speed command outlet
    IF _ePhase = E_DL_DrawStartPhase.STEADY THEN
        xSteady := TRUE;                            // 稳态相电平 / Steady phase level
    ELSE
        xSteady := FALSE;                           // 非稳态相清标志 / Not steady
    END_IF
    xFault := FALSE;                                // 无故障 / No fault
    uErrorId := _uInfo;                             // 信息码每拍重算 / Transient info code
END_IF
IF (fSpeedCmd <> fSpeedCmd) OR (ABS(fSpeedCmd) >= 3.0E38) OR (fSpeedCmd < 0.0) THEN
    fSpeedCmd := 0.0;                               // 出口复核失败回零速 / Outlet recheck zero
    xWinderEnable := FALSE;                         // 出口复核失败切卷绕 / Cut winder
    xFault := TRUE;                                 // 出口复核失败置故障 / Raise fault
    uErrorId := 16#0002_9331;                       // 故障级：出口非有限 / Fault: non-finite outlet
END_IF
END_FUNCTION_BLOCK
