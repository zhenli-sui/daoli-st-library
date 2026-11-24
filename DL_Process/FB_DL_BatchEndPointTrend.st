(*
  FB_DL_BatchEndPointTrend  —  批次反应终点趋势判据 / Batch reaction end-point trend criterion
  分类 Category : DL_Process
  码位 Code     : 16#06_0_8A
  版本 Version  : 1.0.0
  溯源 Source   : ISA-88 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 以斜率收敛（|斜率| <= 门限）+ 终点窗（值落入窗内）双判据确认反应终点；
                  2) 斜率由微分实例给出，采样周期为 0 时不出结论（防除零）；
                  3) 终点窗另设独立超时出口：趋势虽收敛但一直不达窗 → 超时升级，不死等。
  边界 Boundary : ① 斜率计算防采样周期为 0（tSampleTime 为 0 时微分实例不刷新、本件不出结论）；
                  ② 终点超时独立出口（bEndTimeout），趋势收敛但长期不达窗即升级；
                  ③ 相 ID 非法（枚举兜底）时不得置相完成（bEndReached 保持 FALSE）；
                  ④ 结论三行同向：斜率 → 终点窗判据 → 完成标志。
  依赖 Depends  : FB_DL_Differentiator（斜率，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_068A 故障级：组态非法（终点窗上下限倒置 / 采样周期 <= 0 / 斜率门限 <= 0）
    16#0002_069A 故障级：相 ID 越界（枚举兜底路径，禁止置完成）
    16#0002_06AA 信息级：终点超时（趋势收敛但未达窗，超时升级提示）
*)

TYPE E_DL_BepPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eTrack   := 10,  // 趋势跟踪 / Trend tracking
    eSettle  := 20,  // 斜率已收敛 / Slope converged
    eEnd     := 30,  // 到达终点 / End point reached
    eTimeout := 40,  // 终点超时 / End-point timeout
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchEndPointTrend
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bStart       : BOOL;                          // 批次开始，上升沿复位判据 / Batch start, rising edge
    bReset       : BOOL;                          // 复位，上升沿清故障与计时 / Reset
    fValue       : REAL;                          // 被监视过程量（如转化率）[%] / Monitored process value [%]
    fSlopeThresh : REAL := 0.05;                  // 斜率收敛门限 [%/s]，域 > 0 / Slope convergence threshold
    fEndWinLo    : REAL := 98.0;                  // 终点窗下限 [%] / End window low [%]
    fEndWinHi    : REAL := 100.0;                 // 终点窗上限 [%] / End window high [%]
    tStableTime  : TIME := T#30S;                 // 斜率收敛驻留时间 [ms] / Slope stable dwell time [ms]
    tEndTimeout  : TIME := T#30M;                 // 终点超时 [ms]，0 = 不监控 / End-point timeout [ms]
    tSampleTime  : TIME := T#500MS;               // 采样周期 [ms]，域 > 0 / Sample period [ms]
    tCycle       : TIME := T#10MS;                // 任务周期 [ms]，驻留累加步长 / Task cycle [ms]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fSlopeOut    : REAL;                          // 斜率输出 [%/s] / Slope output [%/s]
    bConverged   : BOOL;                          // 斜率已收敛 / Slope converged
    bInEndWindow : BOOL;                          // 值在终点窗内 / Value inside the end window
    bEndReached  : BOOL;                          // 终点确认（保持型）/ End point confirmed, held
    bEndTimeout  : BOOL;                          // 终点超时（保持型）/ End-point timeout, held
    tStableNow   : TIME;                          // 当前收敛驻留时长 [ms] / Current stable dwell [ms]
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_BepPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_BepPhase := E_DL_BepPhase.eIdle;  // 内部状态 / Internal state
    rtrStart     : R_TRIG;                        // 批次开始沿 / Batch start edge
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    fbSlope      : FB_DL_Differentiator;          // 斜率微分实例（无条件调用）/ Slope differentiator
    tonEndTo     : TON;                           // 终点超时计时（无条件刷新）/ End-point timeout timer
    bCfgOk       : BOOL;                          // 组态合法标志 / Configuration valid
    bValueOk     : BOOL;                          // 过程量有效标志 / Value valid flag
    tStable      : TIME;                          // 收敛驻留累计 [ms] / Stable dwell accumulator
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_BEP_PCTMAX : REAL := 1000.0;               // 过程量物理域上限 [%] / Value domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrStart(CLK := bStart);                          // 每拍刷新批次开始沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿
tonEndTo(IN := (_eState = E_DL_BepPhase.eTrack) OR (_eState = E_DL_BepPhase.eSettle),
         PT := tEndTimeout);                      // 终点超时计时，无条件刷新

(* === 段 1 · 组态闸 === *)
bCfgOk := (fEndWinHi > fEndWinLo) AND (fSlopeThresh > fEps)
          AND (tSampleTime > T#0MS) AND (tCycle > T#0MS)
          AND (fEndWinHi = fEndWinHi) AND (fEndWinLo = fEndWinLo);   // 含 NaN 自反判据
IF NOT bCfgOk THEN
    uFault := 16#0002_068A;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存
    bEndReached := FALSE;                         // 完成标志复位
    bEndTimeout := FALSE;                         // 超时标志复位
    tStable := T#0MS;                             // 驻留累计复位
END_IF
bValueOk := (fValue = fValue) AND (ABS(fValue) < 1.0E30)
            AND (fValue >= -DL_BEP_PCTMAX) AND (fValue <= DL_BEP_PCTMAX);   // NaN 自反 + 域闸

(* === 段 2 · 斜率微分实例（每拍无条件调用，采样周期已判 > 0）=== *)
fbSlope(bEnable := bEnable AND bValueOk,          // 值有效才微分
        fIn := fValue,                            // 过程量
        tFiltTime := T#2S,                        // 速率低通 [ms]
        rRateMin := -1.0E6,                       // 速率下限
        rRateMax := 1.0E6,                        // 速率上限
        bTrack := rtrStart.Q,                     // 批次开始沿：无扰跟踪清零
        fTrackValue := 0.0,                       // 跟踪值 0
        tSampleTime := tSampleTime);              // 采样周期（> 0 已由组态闸保证）
fSlopeOut := fbSlope.fRateOut;                    // 斜率输出
bConverged := bValueOk AND fbSlope.bValid AND (ABS(fSlopeOut) <= fSlopeThresh);   // 收敛判据带门限
bInEndWindow := bValueOk AND (fValue >= fEndWinLo) AND (fValue <= fEndWinHi);     // 终点窗判据

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_BepPhase.eIdle :
    bEndReached := FALSE;                         // 空闲不置完成
    bEndTimeout := FALSE;                         // 空闲不置超时
    tStable := T#0MS;                             // 驻留清零
    uInfo := 16#0000;                             // 信息码清零
    IF uFault <> 16#0000 THEN
        _eState := E_DL_BepPhase.eFault;          // 故障优先
    ELSIF bEnable AND rtrStart.Q THEN
        _eState := E_DL_BepPhase.eTrack;          // 本拍进入跟踪相
    END_IF

E_DL_BepPhase.eTrack :
    IF bConverged THEN
        tStable := tStable + tCycle;              // 收敛驻留累加
        IF tStable >= tStableTime THEN
            _eState := E_DL_BepPhase.eSettle;     // 本拍行为：驻留满，转收敛确认相
        END_IF
    ELSE
        tStable := T#0MS;                         // 未收敛：驻留清零（要求连续收敛）
    END_IF
    IF bInEndWindow AND bConverged AND (tStable >= tStableTime) THEN
        _eState := E_DL_BepPhase.eEnd;            // 收敛 + 在窗：直接到终点
        bEndReached := TRUE;                      // 置位型：完成标志，段尾不清零
    END_IF
    IF tonEndTo.Q THEN
        bEndTimeout := TRUE;                      // 置位型：终点超时
        uInfo := 16#0002_06AA;                    // 信息级：超时升级
        _eState := E_DL_BepPhase.eTimeout;
    END_IF

E_DL_BepPhase.eSettle :
    IF bInEndWindow THEN
        bEndReached := TRUE;                      // 收敛且在窗：确认终点
        _eState := E_DL_BepPhase.eEnd;
    ELSIF NOT bConverged THEN
        tStable := T#0MS;                         // 斜率再次发散：驻留清零
        _eState := E_DL_BepPhase.eTrack;          // 回跟踪相
    ELSIF tonEndTo.Q THEN
        bEndTimeout := TRUE;                      // 收敛却长期不达窗：超时升级，不死等
        uInfo := 16#0002_06AA;                    // 信息级：超时
        _eState := E_DL_BepPhase.eTimeout;
    END_IF

E_DL_BepPhase.eEnd :
    bEndReached := TRUE;                          // 完成标志保持
    IF rtrReset.Q OR rtrStart.Q THEN
        bEndReached := FALSE;                     // 复位/新批次清完成
        _eState := E_DL_BepPhase.eIdle;
    END_IF

E_DL_BepPhase.eTimeout :
    bEndTimeout := TRUE;                          // 超时标志保持
    IF rtrReset.Q THEN
        bEndTimeout := FALSE;                     // 复位沿解除（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码清除
        _eState := E_DL_BepPhase.eIdle;
    END_IF

E_DL_BepPhase.eFault :
    bEndReached := FALSE;                         // 故障态禁止置完成
    IF uFault = 16#0000 THEN
        _eState := E_DL_BepPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_BepPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_069A;                       // 故障级：相 ID 越界
    bEndReached := FALSE;                         // 非法相绝不置完成（硬判据）
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_BepPhase.eIdle;               // 失能最高优先回空闲
    bEndReached := FALSE;                         // 失能清完成
END_IF

(* === 段 4 · 输出映射（三行同向：斜率 → 在窗判据 → 完成标志）=== *)
tStableNow := tStable;                            // 驻留时长输出
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
