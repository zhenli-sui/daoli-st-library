(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SlurryStirrerCtrl
 * 所属子库 (Sublibrary) : DL_Device
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG / ABS / MAX / MIN，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 浆料搅拌双电机同步控制公开工艺语义（行业池），
 *                         道莅 clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 浆料搅拌双电机同步件。双电机主从同启（启差不超过
 *                         tSync 防涌流）；同步监视为两机扭矩偏差百分数超
 *                         fSyncTol 持续 tConf 即摘从机降级；单机扭矩超
 *                         fTrqMax 持续 tConf 停该机锁故障。扭矩非有限按
 *                         传感器失效摘除该机，不猜值。等级到健康映射写死
 *                         本头注释。粘度趋势判据依赖库内 FB_DL_Differentiator
 *                         （引脚注入消费，不内联），见依赖表。
 * 依赖表   (Depends)    : E_DL_Ne107Status（属主 I_DL_DeviceHealth.st，只引用
 *                         不重声明）；FB_DL_Differentiator（上层粘度趋势
 *                         判据注入消费，本件本体不调用）。
 * 健康映射 (Health map) : eFailure = 扭矩超限锁故障；eMaintenanceReq = 同步
 *                         失稳摘从机降级；eOutOfSpec = 传感器失效摘除；
 *                         eCheckFunction = 启动暂态（主从启差期间）；eOk = 正常。
 * 码位     (Codes)      : 16#0003_03F7 信息级：传感器失效摘除、参数钳位、
 *                                      扭矩监视禁用（不置 bError）
 *                         16#0003_03F8 故障级：单机扭矩超限（锁存）
 *                         16#0003_03F9 故障级：同步失稳（锁存）
 *                         16#0003_03FA 故障级：状态非法（ELSE 兜底，锁存）
 *                         16#0003_03FB 保留未启用（码表与实现对齐，不虚声明）
 * 边界防错 (Boundary)   : 1 扭矩非有限（x<>x 自反判加幅值界）摘该机不猜值；
 *                         2 均值防除零取 max(均值, 1.0E-6)；
 *                         3 TON/R_TRIG 实例每拍无条件刷新；
 *                         4 CASE 带 ELSE 锁故障兜底；
 *                         5 故障锁存可达解除路径：bRun 撤除回待机清码；
 *                         6 fSyncTol 非正钳 1.0；fTrqMax 非正禁用超限监视并
 *                           记信息码（禁用留档，不静默）。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 10）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_StirState（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StirState :
(
    eIdle     := 0,    // 待机：双机停 / Idle, both motors stopped
    eStart1   := 10,   // 主机启动态：仅主机得电 / Main-start state, main motor only
    eRun      := 20,   // 双机运行态：主从同步 / Run state, both motors synchronized
    eDegrade  := 30,   // 降级态：从机已摘除 / Degraded state, follower removed
    eFault    := 99    // 故障态：锁存等待撤运行 / Fault state, latched until run dropped
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SlurryStirrerCtrl
 * 调用约定: 每个扫描周期无条件调用一次；扭矩信号经引脚注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_SlurryStirrerCtrl
VAR_INPUT
    bRun     : BOOL := FALSE;         // 运行指令（电平）/ Run command, level active
    fTrq1    : REAL := 0.0;           // 电机 1 扭矩 [牛米] / Motor 1 torque [Nm]
    fTrq2    : REAL := 0.0;           // 电机 2 扭矩 [牛米] / Motor 2 torque [Nm]
    fTrqMax  : REAL := 50.0;          // 单机扭矩上限 [牛米]，非正禁用监视 / Per-motor torque limit [Nm], non-positive disables monitor
    fSyncTol : REAL := 10.0;          // 同步偏差容差 [百分数] / Sync deviation tolerance [%]
    tConf    : TIME := T#2S;          // 判级确认时长 [毫秒] / Judgement confirm duration [ms]
    tSync    : TIME := T#1S;          // 主从启差上限 [毫秒] / Start stagger limit [ms]
END_VAR
VAR_OUTPUT
    bStart1  : BOOL;                  // 电机 1 启动指令 / Motor 1 start command
    bStart2  : BOOL;                  // 电机 2 启动指令 / Motor 2 start command
    bSyncOk  : BOOL;                  // 同步合格标志 / Synchronization OK flag
    eHealth  : E_DL_Ne107Status;      // 健康出口（引用库内枚举，只引用不重声明）/ Health output, library enum referenced only
    bError   : BOOL;                  // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigRun : R_TRIG;                // 运行沿检测，每拍无条件刷新 / Run edge detector, refreshed every scan
    tonStag  : TON;                   // 主从启差定时器，每拍无条件刷新 / Start stagger timer, refreshed every scan
    tonSync  : TON;                   // 同步失稳确认定时器，每拍无条件刷新 / Sync instability timer, refreshed every scan
    tonTrq   : TON;                   // 扭矩超限确认定时器，每拍无条件刷新 / Torque overlimit timer, refreshed every scan
    eState   : E_DL_StirState;        // 内部状态机 / Internal state machine
    bSen1Ok  : BOOL;                  // 电机 1 传感器有效 / Motor 1 sensor valid
    bSen2Ok  : BOOL;                  // 电机 2 传感器有效 / Motor 2 sensor valid
    bSenBad  : BOOL;                  // 任一传感器失效 / Any sensor failed
    bDevNow  : BOOL;                  // 本拍同步偏差超限 / Sync deviation out of band this scan
    bOv1     : BOOL;                  // 电机 1 扭矩超限 / Motor 1 torque overlimit
    bOv2     : BOOL;                  // 电机 2 扭矩超限 / Motor 2 torque overlimit
    bOvNow   : BOOL;                  // 本拍任一机超限 / Any overlimit this scan
    fTolEff  : REAL;                  // 钳位后生效容差 [百分数] / Effective clamped tolerance [%]
    fDevPct  : REAL;                  // 扭矩偏差百分数 [%] / Torque deviation percent [%]
    fMean    : REAL;                  // 双机扭矩均值防除零基准 [牛米] / Torque mean with divide guard [Nm]
    bTrqMonOn: BOOL;                  // 超限监视使能（上限合法）/ Overlimit monitor enabled
    uCodeLatch: UDINT;                // 故障级锁存码 / Latched fault code
    bInfoTrq : BOOL;                  // 本拍参数/监视禁用信息 / Parameter or monitor info this scan
END_VAR
VAR CONSTANT
    DL_SSC_FIN   : REAL := 1.0E30;    // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_SSC_EPS   : REAL := 1.0E-6;    // 均值防除零容差 [牛米] / Mean divide-guard tolerance [Nm]
    DL_SSC_TOLMIN: REAL := 1.0;       // 同步容差钳位下限 [百分数] / Tolerance clamp floor [%]
    DL_SSC_PCT   : REAL := 100.0;     // 百分数换算系数 / Percent conversion factor
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigRun(CLK := bRun);                                // 运行沿检测 / Run edge detection
tonStag(IN := (eState = eStart1), PT := tSync);       // 启差计时按态断输入 / Stagger timing input per state
tonSync(IN := bDevNow, PT := tConf);                  // 失稳确认无条件计时 / Instability timing unconditionally
tonTrq(IN := bOvNow, PT := tConf);                    // 超限确认无条件计时 / Overlimit timing unconditionally

// ---- 段 2｜传感器有效性与参数钳位 ----------------------------------------------
bSen1Ok := (fTrq1 = fTrq1) AND (ABS(fTrq1) < DL_SSC_FIN); // 电机 1 扭矩有限 / Motor 1 torque finite
bSen2Ok := (fTrq2 = fTrq2) AND (ABS(fTrq2) < DL_SSC_FIN); // 电机 2 扭矩有限 / Motor 2 torque finite
bSenBad := (NOT bSen1Ok) OR (NOT bSen2Ok);            // 任一失效 / Any sensor failed
fTolEff := fSyncTol;                                  // 容差原值 / Tolerance as-is
bInfoTrq := FALSE;                                    // 信息标志先清 / Clear info flag
IF fTolEff <= 0.0 THEN
    fTolEff := DL_SSC_TOLMIN;                         // 非正容差钳下限 / Clamp non-positive tolerance
    bInfoTrq := TRUE;                                 // 记参数钳位 / Record parameter clamp
END_IF
bTrqMonOn := (fTrqMax > 0.0) AND (fTrqMax < DL_SSC_FIN); // 上限合法才使能监视 / Monitor only with legal limit
IF NOT bTrqMonOn THEN
    bInfoTrq := TRUE;                                 // 监视禁用记信息码 / Monitor disabled records info
END_IF

// ---- 段 3｜同步偏差与超限判据（均值防除零）--------------------------------------
IF bSen1Ok AND bSen2Ok THEN
    fMean := MAX(0.5 * (ABS(fTrq1) + ABS(fTrq2)), DL_SSC_EPS); // 均值防除零 / Mean with divide guard
    fDevPct := ABS(fTrq1 - fTrq2) / fMean * DL_SSC_PCT;        // 偏差百分数 / Deviation percent
    bDevNow := fDevPct > fTolEff;                              // 本拍超差 / Out of band this scan
    bOv1 := bTrqMonOn AND (fTrq1 > fTrqMax);                   // 电机 1 超限判定 / Motor 1 overlimit
    bOv2 := bTrqMonOn AND (fTrq2 > fTrqMax);                   // 电机 2 超限判定 / Motor 2 overlimit
ELSE
    fDevPct := 0.0;                                            // 异常路径确定值 / Deterministic fallback
    bDevNow := FALSE;                                          // 传感器失效不判同步 / No sync judge with bad sensor
    bOv1 := FALSE;                                             // 失效机不判超限 / No overlimit judge
    bOv2 := FALSE;                                             // 失效机不判超限 / No overlimit judge
END_IF
bOvNow := bOv1 OR bOv2;                                        // 任一超限 / Any overlimit

// ---- 段 4｜状态机（CASE 带 ELSE 锁故障兜底）--------------------------------------
CASE eState OF
    eIdle:
        bStart1 := FALSE;                             // 待机双机停 / Both stopped in idle
        bStart2 := FALSE;                             // 待机双机停 / Both stopped in idle
        IF rTrigRun.Q THEN
            eState := eStart1;                        // 运行沿进主机启动 / Run edge starts main motor
        END_IF
    eStart1:
        bStart1 := bRun;                              // 主机随运行指令 / Main follows run command
        bStart2 := FALSE;                             // 从机未得电 / Follower not powered
        IF NOT bRun THEN
            eState := eIdle;                          // 撤运行回待机 / Run drop returns to idle
        ELSIF tonStag.Q THEN
            eState := eRun;                           // 启差满双机运行 / Stagger elapsed, both run
        END_IF
    eRun:
        bStart1 := bRun AND bSen1Ok;                  // 主机指令带传感器门控 / Main gated by sensor
        bStart2 := bRun AND bSen2Ok AND (NOT tonSync.Q); // 从机失稳即摘除 / Follower removed on instability
        IF NOT bRun THEN
            eState := eIdle;                          // 撤运行回待机 / Run drop returns to idle
        ELSIF tonTrq.Q THEN
            eState := eFault;                         // 超限确认锁故障 / Overlimit confirmed, fault
            uCodeLatch := 16#0003_03F8;               // 码位：扭矩超限 / Code: torque overlimit
        ELSIF tonSync.Q THEN
            eState := eDegrade;                       // 同步失稳摘从机降级 / Sync lost, degrade
            uCodeLatch := 16#0003_03F9;               // 码位：同步失稳 / Code: sync instability
        END_IF
    eDegrade:
        bStart1 := bRun AND bSen1Ok;                  // 降级态仅主机 / Only main in degraded
        bStart2 := FALSE;                             // 从机保持摘除 / Follower stays removed
        IF NOT bRun THEN
            eState := eIdle;                          // 可达解除：撤运行回待机清码 / Reachable release: run drop
            uCodeLatch := 16#0000_0000;               // 清锁存码 / Clear latched code
        END_IF
    eFault:
        bStart1 := FALSE;                             // 故障停主机（该机）/ Main stopped in fault
        bStart2 := FALSE;                             // 故障停从机 / Follower stopped in fault
        IF NOT bRun THEN
            eState := eIdle;                          // 可达解除：撤运行回待机 / Reachable release: run drop
            uCodeLatch := 16#0000_0000;               // 清锁存码 / Clear latched code
        END_IF
    ELSE
        eState := eFault;                             // 非法状态兜底 / Illegal state fallback
        uCodeLatch := 16#0003_03FA;                   // 码位：状态非法 / Code: illegal state
END_CASE

// ---- 段 5｜同步合格与健康出口装配（映射写死头注释）------------------------------
bSyncOk := (eState = eRun) AND (NOT bDevNow) AND (NOT bSenBad) AND (NOT bOvNow); // 同步合格 / Sync OK
IF eState = eFault THEN
    eHealth := eFailure;                              // 扭矩超限锁故障 / Torque overlimit failure
ELSIF eState = eDegrade THEN
    eHealth := eMaintenanceReq;                       // 失稳降级 / Degraded maintenance
ELSIF bSenBad THEN
    eHealth := eOutOfSpec;                            // 传感器失效摘除 / Sensor failure out-of-spec
ELSIF eState = eStart1 THEN
    eHealth := eCheckFunction;                        // 启动暂态 / Starting transient
ELSIF (eState = eRun) OR (eState = eIdle) THEN
    eHealth := eOk;                                   // 正常 / Normal
ELSE
    eHealth := eUnknown;                              // 兜底未知 / Fallback unknown
END_IF

// ---- 段 6｜错误码装配：故障锁存回放优先，信息级居次 ------------------------------
IF eState = eFault THEN
    bError   := TRUE;                                 // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
ELSIF bSenBad OR bInfoTrq THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0003_03F7;                         // 信息级：失效/钳位/禁用 / Info: sensor or parameter
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
