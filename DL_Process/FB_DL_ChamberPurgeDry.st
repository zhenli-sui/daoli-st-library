(*
  FB_DL_ChamberPurgeDry  —  腔体干燥吹扫顺控 / Chamber purge and dry sequence control
  分类 Category : DL_Process
  码位 Code     : 16#06_0_82
  版本 Version  : 1.0.1
  溯源 Source   : OSCAT Building 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  修改记录 Hist : v1.0.1 2026-11-23 R75 修复——FC_DL_DewPointCalc 调用补
                  uErrorId / fVaporPa / bInRange 三出参显式回执（R73 零回执
                  挂账点修，与 VaporPressureSat 族回执口径对齐），bInRange
                  并入有效判据，主顺控逻辑零改动
  功能 Function : 1) 露点判据收敛：吹扫 → 静置 → 复测 三态循环，直到复测露点低于目标；
                  2) 三段计时各用独立 TON，且每段 IN := (在相) AND NOT ton.Q 自复位（FB33-2 硬判据）；
                  3) 复测未收敛不无限等待，超过 nMaxRetry 次即转超时态并报码。
  边界 Boundary : ① 露点入参先过有限性与物理域闸（RH 0~100 %、温度 −40~120 °C），域外不出结论；
                  ② 吹扫/静置/复测计时用三实例分段 TON，每段自复位；
                  ③ 复测超次即超时升级，不得延续吹扫无限等待；
                  ④ 超时/故障三行同向：吹扫阀关 → 干燥气阀关 → 进度标志 FALSE。
  依赖 Depends  : FC_DL_DewPointCalc（露点换算，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0682 故障级：露点入参域外或露点函数返回无效（域闸锁存，输入恢复后自解）
    16#0002_0692 故障级：计时参数为 0 或重试上限 < 1（组态闸锁存，需 bReset 清除）
    16#0002_06A2 信息级：复测超次转超时（不置 bError，仅提示）
*)

TYPE E_DL_PurgeDryPhase :
(
    eIdle      := 0,   // 空闲 / Idle
    ePurge     := 10,  // 吹扫段 / Purge stage
    eSoak      := 20,  // 静置段 / Soak stage
    eRemeasure := 30,  // 复测段 / Re-measure stage
    eDone      := 40,  // 干燥达标 / Dry target reached
    eTimeout   := 50,  // 复测超次超时 / Retry timeout
    eFault     := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChamberPurgeDry
VAR_INPUT
    bEnable        : BOOL;                        // 总使能，FALSE 回空闲关阀 / Master enable
    bStart         : BOOL;                        // 启动，上升沿有效 / Start, rising edge
    bReset         : BOOL;                        // 复位，上升沿清故障与超时 / Reset, clears fault and timeout
    fTempC         : REAL;                        // 腔体干球温度 [degC]，域 −40~120 / Chamber dry-bulb temperature [degC]
    fRhPct         : REAL;                        // 腔体相对湿度 [%]，域 0~100 / Chamber relative humidity [%]
    fDewTargetC    : REAL := -20.0;               // 露点目标 [degC]，复测低于此值判达标 / Dew point target [degC]
    fDewHystC      : REAL := 2.0;                 // 露点达标迟滞 [degC]，防边界抖动 / Dew point hysteresis [degC]
    tPurgeTime     : TIME := T#60S;               // 吹扫段时长 [ms]，域 > 0 / Purge stage duration
    tSoakTime      : TIME := T#30S;               // 静置段时长 [ms]，域 > 0 / Soak stage duration
    tRemeasureTime : TIME := T#20S;               // 复测段时长 [ms]，域 > 0 / Re-measure stage duration
    tDewSampleTime : TIME := T#500MS;             // 露点采样节拍 [ms]，自复位心跳 / Dew sample tick, self-resetting
    nMaxRetry      : INT := 5;                    // 最大复测次数 [次]，域 >= 1 / Max re-measure count
END_VAR
VAR_OUTPUT
    bPurgeValve    : BOOL;                        // 吹扫进气阀 [开关] / Purge inlet valve
    bDryAirValve   : BOOL;                        // 干燥气补充阀 [开关] / Dry air makeup valve
    bExhaustValve  : BOOL;                        // 排气阀 [开关] / Exhaust valve
    fDewNowC       : REAL;                        // 当前露点 [degC]，采样节拍刷新 / Current dew point [degC]
    bDewValid      : BOOL;                        // 露点有效标志 / Dew point valid flag
    nRetry         : INT;                         // 已复测次数 [次] / Re-measure count
    bInProgress    : BOOL;                        // 顺控进行中 / Sequence in progress
    bDone          : BOOL;                        // 达标完成（保持型）/ Dry done, level held
    bTimeout       : BOOL;                        // 超时标志（保持型）/ Timeout flag, level held
    bError         : BOOL;                        // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId       : UDINT;                       // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut      : E_DL_PurgeDryPhase;          // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState        : E_DL_PurgeDryPhase := E_DL_PurgeDryPhase.eIdle;  // 内部状态 / Internal state
    rtrStart       : R_TRIG;                      // 启动沿 / Start edge
    rtrReset       : R_TRIG;                      // 复位沿 / Reset edge
    tonPurge       : TON;                         // 吹扫段计时（自复位）/ Purge stage timer, self-resetting
    tonSoak        : TON;                         // 静置段计时（自复位）/ Soak stage timer, self-resetting
    tonRemeasure   : TON;                         // 复测段计时（自复位）/ Re-measure stage timer
    tonDewTick     : TON;                         // 露点采样心跳（自复位）/ Dew sample tick, self-resetting
    fDewCalcC      : REAL;                        // 露点函数返回暂存 [degC] / Dew point function result
    fDewHoldC      : REAL;                        // 采样节拍锁存露点 [degC] / Latched dew point at tick
    bInputOk       : BOOL;                        // 露点入参域闸结果 / Dew input domain result
    bCfgOk         : BOOL;                        // 计时/重试组态合法 / Timer and retry configuration valid
    bConverged     : BOOL;                        // 复测收敛标志 / Convergence flag
    uFault         : UDINT;                       // 锁存故障码 / Latched fault code
    uInfo          : UDINT;                       // 信息级码 / Information code
    uDewErr        : UDINT;                       // 露点函数回执码（v1.0.1 新增接收）/ Dew point FC receipt, new in v1.0.1
    fVaporPaBuf    : REAL;                        // 露点函数水汽压回执 [Pa]（v1.0.1 新增接收，诊断）/ Dew point FC vapor pressure receipt [Pa]
    bDewInRange    : BOOL;                        // 露点函数域内回执 [-]（v1.0.1 新增接收）/ Dew point FC in-range receipt
END_VAR
VAR CONSTANT
    DL_PD_TMIN     : REAL := -40.0;               // 温度有效域下限 [degC] / Temperature domain low [degC]
    DL_PD_TMAX     : REAL := 120.0;               // 温度有效域上限 [degC] / Temperature domain high [degC]
    DL_PD_RHMIN    : REAL := 0.0;                 // 湿度有效域下限 [%] / Humidity domain low [%]
    DL_PD_RHMAX    : REAL := 100.0;               // 湿度有效域上限 [%] / Humidity domain high [%]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用，自复位节拍）=== *)
rtrStart(CLK := bStart);                          // 每拍刷新启动沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿
tonPurge(IN := (_eState = E_DL_PurgeDryPhase.ePurge) AND (NOT tonPurge.Q), PT := tPurgeTime);      // 自复位
tonSoak(IN := (_eState = E_DL_PurgeDryPhase.eSoak) AND (NOT tonSoak.Q), PT := tSoakTime);           // 自复位
tonRemeasure(IN := (_eState = E_DL_PurgeDryPhase.eRemeasure) AND (NOT tonRemeasure.Q), PT := tRemeasureTime); // 自复位
tonDewTick(IN := NOT tonDewTick.Q, PT := tDewSampleTime);                                            // 采样心跳自复位

(* === 段 1 · 域闸：入参有限性 + 物理域，域外不出结论 === *)
bInputOk := (fTempC = fTempC) AND (fRhPct = fRhPct)                          // NaN 自反判据
            AND (ABS(fTempC) < 1.0E30) AND (ABS(fRhPct) < 1.0E30)            // Inf 上限兜底
            AND (fTempC >= DL_PD_TMIN) AND (fTempC <= DL_PD_TMAX)            // 温度物理域闸
            AND (fRhPct >= DL_PD_RHMIN) AND (fRhPct <= DL_PD_RHMAX);         // 湿度物理域闸
fDewCalcC := FC_DL_DewPointCalc(fTempC := fTempC, fRhPct := fRhPct,
                                uErrorId => uDewErr, fVaporPa => fVaporPaBuf,
                                bInRange => bDewInRange);                   // 露点换算每拍无条件调用 + 三出参回执（v1.0.1）
IF bInputOk AND bDewInRange AND (fDewCalcC = fDewCalcC) AND (ABS(fDewCalcC) < 1.0E30) THEN   // 域内回执并入判据（v1.0.1）
    IF tonDewTick.Q THEN
        fDewHoldC := fDewCalcC;                   // 采样节拍到时锁存露点（每 N 时间采一次）
        bDewValid := TRUE;                        // 露点有效
    END_IF
ELSE
    bDewValid := FALSE;                           // 域外：露点无效，不清零旧值（保持诊断可读）
END_IF
bCfgOk := (tPurgeTime > T#0MS) AND (tSoakTime > T#0MS) AND (tRemeasureTime > T#0MS)
          AND (tDewSampleTime > T#0MS) AND (nMaxRetry >= 1);                 // 计时与重试组态闸
IF NOT bCfgOk THEN
    uFault := 16#0002_0692;                       // 故障级：计时参数为 0 或重试上限非法
END_IF
IF NOT bInputOk THEN
    uFault := 16#0002_0682;                       // 故障级：露点入参域外（输入恢复后段 2 自解）
END_IF
IF bInputOk AND bCfgOk THEN
    IF uFault = 16#0002_0682 THEN
        uFault := 16#0000;                        // 输入恢复即自解域闸故障（复位路径可达）
    END_IF
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（组态已合法才允许）
END_IF

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PurgeDryPhase.eIdle :
    nRetry := 0;                                  // 新一轮复测计数清零
    bDone := FALSE;                               // 完成标志复位
    bTimeout := FALSE;                            // 超时标志复位
    bConverged := FALSE;                          // 收敛标志复位
    uInfo := 16#0000;                             // 信息码清零（条件不满足则保持 0）
    IF uFault = 16#0002_0692 THEN
        _eState := E_DL_PurgeDryPhase.eFault;     // 组态故障优先拦截
    ELSIF rtrStart.Q THEN
        _eState := E_DL_PurgeDryPhase.ePurge;     // 本拍进入吹扫相
    END_IF

E_DL_PurgeDryPhase.ePurge :
    IF tonPurge.Q THEN
        _eState := E_DL_PurgeDryPhase.eSoak;      // 本拍行为：吹扫到时长，拍末转静置
    END_IF

E_DL_PurgeDryPhase.eSoak :
    IF tonSoak.Q THEN
        _eState := E_DL_PurgeDryPhase.eRemeasure; // 静置到时长，转复测相
    END_IF

E_DL_PurgeDryPhase.eRemeasure :
    IF tonRemeasure.Q THEN
        bConverged := bDewValid AND (fDewHoldC <= (fDewTargetC - fDewHystC));   // 露点低于目标减迟滞才判收敛
        nRetry := nRetry + 1;                     // 复测次数累加
        IF bConverged THEN
            _eState := E_DL_PurgeDryPhase.eDone;  // 收敛：转达标态
            bDone := TRUE;                        // 置位型：完成标志，段尾不清零
        ELSIF nRetry >= nMaxRetry THEN
            _eState := E_DL_PurgeDryPhase.eTimeout;   // 超次：超时升级，不无限等待
            bTimeout := TRUE;                     // 置位型：超时标志
            uInfo := 16#0002_06A2;                // 信息级：复测超次（不置 bError）
        ELSE
            _eState := E_DL_PurgeDryPhase.ePurge; // 未收敛且余次：回吹扫再循环
        END_IF
    END_IF

E_DL_PurgeDryPhase.eDone :
    bDone := TRUE;                                // 达标保持直到复位或再启动
    IF rtrStart.Q OR rtrReset.Q THEN
        _eState := E_DL_PurgeDryPhase.eIdle;      // 再启动/复位回空闲
    END_IF

E_DL_PurgeDryPhase.eTimeout :
    bTimeout := TRUE;                             // 超时标志保持，等人为处理
    IF rtrReset.Q THEN
        bTimeout := FALSE;                        // 复位沿解除超时（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码同步清除
        _eState := E_DL_PurgeDryPhase.eIdle;
    END_IF

E_DL_PurgeDryPhase.eFault :
    IF (uFault = 16#0000) THEN
        _eState := E_DL_PurgeDryPhase.eIdle;      // 故障已解锁回空闲
    END_IF

ELSE
    _eState := E_DL_PurgeDryPhase.eFault;         // 非法状态拦截
    uFault := 16#0002_0692;                       // 故障级：相 ID 越界（枚举兜底路径）
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_PurgeDryPhase.eIdle;          // 失能最高优先回空闲
    bInProgress := FALSE;                         // 进度标志随之为 FALSE
END_IF

(* === 段 3 · 输出映射（安全三行同向：阀门关 → 露点值 → 进度判据）=== *)
bPurgeValve   := (_eState = E_DL_PurgeDryPhase.ePurge);      // 吹扫阀仅吹扫相开
bDryAirValve  := (_eState = E_DL_PurgeDryPhase.ePurge) OR (_eState = E_DL_PurgeDryPhase.eSoak);  // 干燥气随吹扫/静置
bExhaustValve := (_eState = E_DL_PurgeDryPhase.ePurge) OR (_eState = E_DL_PurgeDryPhase.eSoak)
                 OR (_eState = E_DL_PurgeDryPhase.eRemeasure);   // 排气阀复测相亦开
IF (_eState = E_DL_PurgeDryPhase.eTimeout) OR (_eState = E_DL_PurgeDryPhase.eFault)
   OR (_eState = E_DL_PurgeDryPhase.eIdle) THEN
    bPurgeValve := FALSE;                         // 超时/故障/空闲：吹扫阀强制关
    bDryAirValve := FALSE;                        // 干燥气阀强制关
    bExhaustValve := FALSE;                       // 排气阀强制关
END_IF
fDewNowC := fDewHoldC;                            // 露点输出取采样锁存值
bInProgress := (_eState = E_DL_PurgeDryPhase.ePurge) OR (_eState = E_DL_PurgeDryPhase.eSoak)
               OR (_eState = E_DL_PurgeDryPhase.eRemeasure);   // 进度判据与阀门同向
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
