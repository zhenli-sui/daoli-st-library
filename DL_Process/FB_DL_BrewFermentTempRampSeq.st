// FB_DL_BrewFermentTempRampSeq v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 发酵温度阶梯七相顺控：IDLE→PITCH→MAIN→REST→COOL→HOLD→IDLE 置 xDone。
        判据：PITCH 达 fPitchTemp±0.5 °C；MAIN 当 fExtract ≤ fExtractEnd；REST 满 48 h；
        COOL 达 fCoolTemp±0.5 °C；HOLD 满 24 h。设定值 _fSp 按 fRampRate [°C/h] 逐周期逼近目标，
        单周期增量 = fRampRate·fCycleS/3600 [°C]，严禁阶跃（相切换不回跳）。
        阀位：实测高于设定 0.2 °C 开冷却阀，低于 0.2 °C 开加热阀，两阀互斥，互锁复核失败双阀 FALSE 并锁存。
  邻件: 与 FC_DL_FermentAttenuationCalc、FC_DL_DiacetylRestWindowCalc、FC_DL_BeerCoolingLoadCalc 同族，本件不调用 FC。
  码表: 9341 入参非有限｜9342 组态非法(fRampRate/fCycleS≤0)｜9343 相超时(12/240/24 h)
        9344 温控失效或双阀互锁违例｜9345 相位落 ELSE 兜底｜9346 信息级序列完成。故障码锁存至 xReset 上升沿。
  边界: 无方法块/无属性块/无全局变量/无物理 IO 地址；六 TON 无条件刷新；温度非有限 → FAULT 且双阀 FALSE。
*)
TYPE E_DL_FermentRampPhase :
(
    IDLE  := 0,         // 空闲：等启动指令 [-] / Idle, waiting start
    PITCH := 10,        // 接种：控温至接种温度 [-] / Pitching temperature
    MAIN  := 20,        // 主发酵：控温至主发酵温度 [-] / Main fermentation
    REST  := 30,        // 还原：升温双乙酰还原 [-] / Diacetyl rest
    COOL  := 40,        // 降温：降至贮酒温度 [-] / Cooling down
    HOLD  := 50,        // 贮酒：低温保持 [-] / Cold holding
    FAULT := 90         // 故障：锁存，仅复位沿可出 [-] / Fault latched
);
END_TYPE
FUNCTION_BLOCK FB_DL_BrewFermentTempRampSeq
VAR_INPUT
    xEnable     : BOOL := FALSE;    // 使能，FALSE 时冻结在 IDLE [-] / Enable gate
    xStart      : BOOL := FALSE;    // 启动指令，上升沿有效 [-] / Start rising edge
    xReset      : BOOL := FALSE;    // 复位，上升沿清故障锁存 [-] / Reset rising edge
    fTankTemp   : REAL := 8.0;      // 罐内实测温度 [°C] / Measured tank temperature [degC]
    fPitchTemp  : REAL := 9.0;      // 接种温度设定 [°C] / Pitching temperature [degC]
    fMainTemp   : REAL := 11.0;     // 主发酵温度设定 [°C] / Main temperature [degC]
    fRestTemp   : REAL := 16.0;     // 还原温度设定 [°C] / Rest temperature [degC]
    fCoolTemp   : REAL := 1.0;      // 贮酒温度设定 [°C] / Cold storage temperature [degC]
    fRampRate   : REAL := 0.5;      // 斜坡速率 [°C/h]，域 > 0 / Ramp rate [degC/h]
    fExtract    : REAL := 12.0;     // 当前外观浓度 [°P] / Current extract [degP]
    fExtractEnd : REAL := 3.0;      // 主发酵终点浓度 [°P] / End-of-main extract [degP]
    fCycleS     : REAL := 0.01;     // 任务周期 [s]，域 > 0 / Task cycle time [s]
END_VAR
VAR_OUTPUT
    ePhase     : E_DL_FermentRampPhase;     // 相位出口，段尾单点映射 [-] / Phase outlet
    fTempSp    : REAL;                      // 温度设定出口 [°C] / Temperature setpoint outlet [degC]
    xCoolValve : BOOL;                      // 冷却阀指令 [-] / Cooling valve command
    xHeatValve : BOOL;                      // 加热阀指令 [-] / Heating valve command
    xDone      : BOOL;                      // 序列完成单拍脉冲 [-] / Done one-shot pulse
    xFault     : BOOL;                      // 故障锁存标志 [-] / Fault latch flag
    uErrorId   : UDINT;                     // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonPitch  : TON;                        // 接种相超时 12 h，无条件刷新 / Pitch timeout
    tonMain   : TON;                        // 主发酵相超时 240 h，无条件刷新 / Main timeout
    tonRest   : TON;                        // 还原相定时 48 h，无条件刷新 / Rest timer
    tonCool   : TON;                        // 降温相超时 24 h，无条件刷新 / Cool timeout
    tonHold   : TON;                        // 贮酒相定时 24 h，无条件刷新 / Hold timer
    tonDev    : TON;                        // 温控偏差持续窗 600 s，无条件刷新 / Deviation window
    rtStart   : R_TRIG;                     // 启动沿实例，无条件刷新 / Start edge instance
    rtReset   : R_TRIG;                     // 复位沿实例，无条件刷新 / Reset edge instance
    _ePhase   : E_DL_FermentRampPhase := E_DL_FermentRampPhase.IDLE;    // 内部相位，CASE 唯一写入 / Internal phase
    _fSp      : REAL := 0.0;                // 温度设定斜坡量 [°C] / Ramp setpoint [degC]
    _fSpTar   : REAL := 0.0;                // 本相设定目标 [°C] / Phase setpoint target [degC]
    _fStep    : REAL := 0.0;                // 本周期斜坡增量 [°C] / Per-cycle ramp step [degC]
    _xCoolOn  : BOOL := FALSE;              // 冷却阀内部选择位 [-] / Internal cooling selection
    _xHeatOn  : BOOL := FALSE;              // 加热阀内部选择位 [-] / Internal heating selection
    _bFault   : BOOL := FALSE;              // 故障锁存位（锁存量，仅复位沿清）/ Latched fault bit
    _uFault   : UDINT := 16#0000;           // 故障码锁存（锁存量，仅复位沿清）/ Latched fault code
    _uInfo    : UDINT := 16#0000;           // 信息码，每拍重算 / Transient info code
END_VAR
// 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内，R7/R188）/ Unconditional refresh
rtStart(CLK := xStart);                                                     // 启动沿每拍必调 / Start edge
rtReset(CLK := xReset);                                                     // 复位沿每拍必调 / Reset edge
tonPitch(IN := (_ePhase = E_DL_FermentRampPhase.PITCH), PT := T#12H);       // 接种相超时 / Pitch timeout
tonMain(IN := (_ePhase = E_DL_FermentRampPhase.MAIN), PT := T#240H);        // 主发酵超时 / Main timeout
tonRest(IN := (_ePhase = E_DL_FermentRampPhase.REST), PT := T#48H);         // 还原 48 h / Rest timer
tonCool(IN := (_ePhase = E_DL_FermentRampPhase.COOL), PT := T#24H);         // 降温超时 / Cool timeout
tonHold(IN := (_ePhase = E_DL_FermentRampPhase.HOLD), PT := T#24H);         // 贮酒 24 h / Hold timer
tonDev(IN := (_ePhase <> E_DL_FermentRampPhase.IDLE) AND (_ePhase <> E_DL_FermentRampPhase.FAULT)
             AND (ABS(fTankTemp - _fSp) > 3.0), PT := T#600S);              // 温控偏差窗 / Deviation window
// 段 1：单拍量与阀位预清零（锁存量 _bFault/_uFault/_fSp 不入清单，R187）/ One-shot clear
_uInfo := 16#0000;                  // 信息码每拍重算 / Info code recomputed
xDone := FALSE;                     // 完成脉冲缺省清 / Done pulse clear
_xCoolOn := FALSE;                  // 冷却阀缺省关（互锁起点）/ Cooling default off
_xHeatOn := FALSE;                  // 加热阀缺省关（互锁起点）/ Heating default off
// 段 2：非有限闸与组态域闸（归因唯一，逐因独立码，R190）/ Gate stage
IF (fTankTemp <> fTankTemp) OR (fPitchTemp <> fPitchTemp) OR (fMainTemp <> fMainTemp)
   OR (fRestTemp <> fRestTemp) OR (fCoolTemp <> fCoolTemp) OR (fRampRate <> fRampRate)
   OR (fExtract <> fExtract) OR (fExtractEnd <> fExtractEnd) OR (fCycleS <> fCycleS)
   OR (ABS(fTankTemp) >= 3.0E38) OR (ABS(fPitchTemp) >= 3.0E38) OR (ABS(fMainTemp) >= 3.0E38)
   OR (ABS(fRestTemp) >= 3.0E38) OR (ABS(fCoolTemp) >= 3.0E38) OR (ABS(fRampRate) >= 3.0E38)
   OR (ABS(fExtract) >= 3.0E38) OR (ABS(fExtractEnd) >= 3.0E38) OR (ABS(fCycleS) >= 3.0E38) THEN
    _uFault := 16#0002_9341;        // 故障级：入参非有限 / Fault: non-finite input
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
IF (fRampRate <= 1.0E-9) OR (fCycleS <= 1.0E-6) THEN
    _uFault := 16#0002_9342;        // 故障级：组态非法 / Fault: illegal configuration
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
// 段 3：温控失效持续窗（偏差超 3 °C 达 600 s）/ Control deviation window
IF tonDev.Q THEN
    _uFault := 16#0002_9344;        // 故障级：温控失效 / Fault: control failure
    _bFault := TRUE;                // 置故障锁存（R45 配对）/ Set fault latch
END_IF
// 段 4：复位沿（FAULT 唯一解除路径）/ Reset edge, only exit from fault
IF rtReset.Q THEN                   // rtReset.Q = 当拍量 / Reset edge per scan
    IF _ePhase = E_DL_FermentRampPhase.FAULT THEN
        _ePhase := E_DL_FermentRampPhase.IDLE;      // 故障相迁出回空闲 / Fault exits to idle
    END_IF
    _fSp := fTankTemp;              // 设定回实测（复位不阶跃）/ Setpoint resumes at measured value
    _bFault := FALSE;               // 清故障锁存位（仅此解除沿可清）/ Clear latched bit
    _uFault := 16#0000;             // 清故障锁存码（仅此解除沿可清）/ Clear latched code
END_IF
// 段 5：相位机（先消化本拍合法事件，再消化超时，R275）/ Phase machine
CASE _ePhase OF
E_DL_FermentRampPhase.IDLE:
    _fSp := fTankTemp;                              // 空闲设定随实测（无阶跃）/ Track measured value
    IF _bFault THEN
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 聚合故障进故障相 / Enter fault
    ELSIF rtStart.Q AND xEnable THEN
        _ePhase := E_DL_FermentRampPhase.PITCH;     // 启动：进接种相 / Start, pitching
    END_IF
E_DL_FermentRampPhase.PITCH:
    _fSpTar := fPitchTemp;                          // 接种相目标 / Pitching target
    IF _bFault THEN
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_FermentRampPhase.IDLE;      // 使能撤销回空闲 / Enable dropped
    ELSIF ABS(fTankTemp - fPitchTemp) <= 0.5 THEN
        _ePhase := E_DL_FermentRampPhase.MAIN;      // 达 ±0.5 °C：进主发酵相 / Go main
    ELSIF tonPitch.Q THEN
        _uFault := 16#0002_9343;                    // 故障级：接种相超时 / Pitch timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_FermentRampPhase.MAIN:
    _fSpTar := fMainTemp;                           // 主发酵目标 / Main target
    IF _bFault THEN
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 故障优先 / Fault first
    ELSIF NOT xEnable THEN
        _ePhase := E_DL_FermentRampPhase.IDLE;      // 使能撤销回空闲 / Enable dropped
    ELSIF fExtract <= fExtractEnd THEN
        _ePhase := E_DL_FermentRampPhase.REST;      // 浓度达终点：进还原相 / Go rest
    ELSIF tonMain.Q THEN
        _uFault := 16#0002_9343;                    // 故障级：主发酵相超时 / Main timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_FermentRampPhase.REST:
    _fSpTar := fRestTemp;                           // 还原温度目标 / Rest target
    IF _bFault THEN
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 故障优先 / Fault first
    ELSIF tonRest.Q THEN
        _ePhase := E_DL_FermentRampPhase.COOL;      // 满 48 h：进降温相 / Rest done, cool
    END_IF
E_DL_FermentRampPhase.COOL:
    _fSpTar := fCoolTemp;                           // 降温目标 / Cooling target
    IF _bFault THEN
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 故障优先 / Fault first
    ELSIF ABS(fTankTemp - fCoolTemp) <= 0.5 THEN
        _ePhase := E_DL_FermentRampPhase.HOLD;      // 达贮酒温度：进贮酒相 / Go hold
    ELSIF tonCool.Q THEN
        _uFault := 16#0002_9343;                    // 故障级：降温相超时 / Cool timeout
        _bFault := TRUE;                            // 置故障锁存（R45 配对）/ Set latch
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 进故障相 / Enter fault
    END_IF
E_DL_FermentRampPhase.HOLD:
    _fSpTar := fCoolTemp;                           // 贮酒温度保持 / Hold target
    IF _bFault THEN
        _ePhase := E_DL_FermentRampPhase.FAULT;     // 故障优先 / Fault first
    ELSIF tonHold.Q THEN
        xDone := TRUE;                              // 满 24 h：完成脉冲单拍 / Done pulse
        _uInfo := 16#0002_9346;                     // 信息级：序列完成 / Info: sequence done
        _ePhase := E_DL_FermentRampPhase.IDLE;      // 回空闲 / Return to idle
    END_IF
E_DL_FermentRampPhase.FAULT:
    _fSpTar := fTankTemp;                           // 故障相设定回实测 / Setpoint tracks measured
    IF rtReset.Q THEN
        _ePhase := E_DL_FermentRampPhase.IDLE;      // 复位沿解除（段 4 已清锁存）/ Reset releases
    END_IF
ELSE
    _uFault := 16#0002_9345;                        // 故障级：非法相位兜底 / Illegal phase id
    _bFault := TRUE;                                // 置故障锁存（R45 配对）/ Set latch
    _fSpTar := fTankTemp;                           // 非法相位设定回实测 / Setpoint tracks measured
    _ePhase := E_DL_FermentRampPhase.FAULT;         // 强制进故障相 / Force into fault
END_CASE
// 段 6：设定值斜坡（增量 = fRampRate·fCycleS/3600，禁阶跃）/ Setpoint ramp
IF (_ePhase = E_DL_FermentRampPhase.IDLE) OR (_ePhase = E_DL_FermentRampPhase.FAULT) THEN
    _fSp := fTankTemp;                              // 空闲/故障相跟随实测 / Track measured value
ELSE
    _fStep := fRampRate * fCycleS / 3600.0;         // 本周期增量 [°C] / Per-cycle step
    IF _fSp < _fSpTar THEN
        _fSp := _fSp + _fStep;                      // 向上逼近 / Ramp upward
        IF _fSp > _fSpTar THEN
            _fSp := _fSpTar;                        // 不得越过目标 / No overshoot
        END_IF
    ELSIF _fSp > _fSpTar THEN
        _fSp := _fSp - _fStep;                      // 向下逼近 / Ramp downward
        IF _fSp < _fSpTar THEN
            _fSp := _fSpTar;                        // 不得越过目标 / No overshoot
        END_IF
    END_IF
END_IF
// 段 7：阀位生成（实测高于设定 0.2 °C 开冷阀，反之开热阀，互斥）/ Valve generation
IF (_ePhase = E_DL_FermentRampPhase.IDLE) OR (_ePhase = E_DL_FermentRampPhase.FAULT) THEN
    _xCoolOn := FALSE;                              // 空闲/故障相不推阀 / No valve action
    _xHeatOn := FALSE;                              // 空闲/故障相不推阀 / No valve action
ELSIF (fTankTemp - _fSp) > 0.2 THEN
    _xCoolOn := TRUE;                               // 偏热：开冷却阀 / Too warm, cool
ELSIF (fTankTemp - _fSp) < -0.2 THEN
    _xHeatOn := TRUE;                               // 偏冷：开加热阀 / Too cold, heat
END_IF
// 段 8：出口单点映射（名实双出口，R191；双阀互锁复核）/ Outlet mapping
ePhase := _ePhase;                                  // 相位出口单点映射 / Phase outlet
IF (_ePhase = E_DL_FermentRampPhase.FAULT) OR _bFault THEN
    fTempSp := fTankTemp;                           // 故障侧设定跟随实测 / Setpoint tracks measured
    xCoolValve := FALSE;                            // 故障侧冷却阀硬关 / Cooling hard off
    xHeatValve := FALSE;                            // 故障侧加热阀硬关 / Heating hard off
    xFault := TRUE;                                 // 故障锁存回放 / Replay latched flag
    uErrorId := _uFault;                            // 故障码锁存回放 / Replay latched code
ELSIF _xCoolOn AND _xHeatOn THEN
    fTempSp := _fSp;                                // 设定值出口 / Setpoint outlet
    xCoolValve := FALSE;                            // 互锁违例：双阀全关 / Interlock: both off
    xHeatValve := FALSE;                            // 互锁违例：双阀全关 / Interlock: both off
    xFault := TRUE;                                 // 互锁违例置故障 / Raise fault on interlock
    uErrorId := 16#0002_9344;                       // 故障级：双阀互锁违例 / Fault: valve interlock
ELSE
    fTempSp := _fSp;                                // 设定值出口 / Setpoint outlet
    xCoolValve := _xCoolOn;                         // 冷却阀出口 / Cooling outlet
    xHeatValve := _xHeatOn;                         // 加热阀出口 / Heating outlet
    xFault := FALSE;                                // 无故障 / No fault
    uErrorId := _uInfo;                             // 信息码每拍重算 / Transient info code
END_IF
IF (fTempSp <> fTempSp) OR (ABS(fTempSp) >= 3.0E38) THEN
    fTempSp := fTankTemp;                           // 出口复核失败回实测 / Outlet recheck fallback
    xCoolValve := FALSE;                            // 出口复核失败关冷却 / Cut cooling
    xHeatValve := FALSE;                            // 出口复核失败关加热 / Cut heating
    xFault := TRUE;                                 // 出口复核失败置故障 / Raise fault
    uErrorId := 16#0002_9341;                       // 故障级：出口非有限 / Fault: non-finite outlet
END_IF
END_FUNCTION_BLOCK
