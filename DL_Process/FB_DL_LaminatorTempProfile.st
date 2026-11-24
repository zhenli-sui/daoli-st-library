(*
  FB_DL_LaminatorTempProfile  —  层压机多温区配方曲线跟随 / Laminator multi-zone temperature profile
  分类 Category : DL_Process
  码位 Code     : 16#06_0_8D
  版本 Version  : 1.0.0
  溯源 Source   : LGF Technology 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 每温区按「升温 → 保温 → 降温」三段配方跟随（复用 FB_DL_RampSoakProfile 多实例按温区展开）；
                  2) 全部温区过各自终点窗才置 bProfileDone（单区完成不算完成）；
                  3) 任一温区实测温度无效：该区冻结判定保持末次设定，其余区继续。
  边界 Boundary : ① 段表非法（斜率 <= 0 折算斜坡时间 <= 0、保温时长 < 0、温区数越界）出厂报码；
                  ② 实测温度非有限判 NE43 无效：该温区冻结判定并置信息码，禁塞伪值；
                  ③ 段切换沿冻结一拍防设定阶跃（切换拍不更新区设定输出）；
                  ④ 超时未达窗升级为段故障（锁存），不死等；
                  ⑤ 输出三行同向：区段号 → 区设定 → 完成标志。
  依赖 Depends  : FB_DL_RampSoakProfile × DL_LAM_ZMAX（设定源实例，每拍无条件调用）
  职责边界 Note : 与 FB_DL_CvdTempRamp 同用 RampSoakProfile，但本件面向层压机三段真空/加压
                  配方（段数固定 3、有 bHoldActive 保温保持出口），CVD 件面向多段 Ramp/Soak +
                  均匀性判据，二者行业参数集与判据分立，互不替代。

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_068D 故障级：段表组态非法（温区数越界 / 斜坡或保温时长 < 0 / 目标温度非有限）
    16#0002_069D 故障级：段超时（保温段计时超限时仍未达窗，锁存需复位）
    16#0002_06AD 信息级：某温区实测温度无效，该区判定已冻结（不置 bError）
*)

TYPE E_DL_LtpPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eRun     := 10,  // 曲线跟随中 / Profile running
    eDone    := 20,  // 全区完成 / All zones done
    eFrozen  := 30,  // 全部温区无效冻结 / All zones frozen by invalid feedback
    eFault   := 90   // 段故障锁定 / Segment fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaminatorTempProfile
VAR_INPUT
    bStart        : BOOL;                           // 启动指令，上升沿生效 / Profile start, edge
    bHold         : BOOL;                           // 外部保持（暂停整条曲线）/ External hold
    bReset        : BOOL;                           // 复位，上升沿清段故障 / Reset, clears segment fault
    nZoneCount    : INT := 3;                       // 温区数 [区]，1..DL_LAM_ZMAX / Zone count
    aTgtRampC     : ARRAY[1..4] OF REAL;            // 升温段目标 [°C] × 区 / Ramp segment target [degC] per zone
    aTgtSoakC     : ARRAY[1..4] OF REAL;            // 保温段目标 [°C] × 区 / Soak segment target [degC] per zone
    aTgtCoolC     : ARRAY[1..4] OF REAL;            // 降温段目标 [°C] × 区 / Cool segment target [degC] per zone
    aTempActC     : ARRAY[1..4] OF REAL;            // 各温区实测温度 [°C] / Measured zone temperature [degC]
    tRampUp       : TIME := T#600S;                 // 升温段斜坡时间 [s] / Ramp-up duration
    tSoak         : TIME := T#900S;                 // 保温段保持时间 [s] / Soak duration
    tCoolDown     : TIME := T#600S;                 // 降温段斜坡时间 [s] / Cool-down duration
    fEndWinK      : REAL := 3.0;                    // 终点窗半宽 [K]，域 > 0 / End window half width [K]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    afZoneSpC     : ARRAY[1..4] OF REAL;            // 各温区设定输出 [°C] / Zone setpoint output [degC]
    anZoneSeg     : ARRAY[1..4] OF INT;             // 各温区当前段号 1..3 / Active segment per zone
    bProfileDone  : BOOL;                           // 全部温区过终点窗 / All zones past end window
    bHoldActive   : BOOL;                           // 保温段激活标志（任一区在保温段）/ Any zone in soak segment
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_LtpPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_LtpPhase := E_DL_LtpPhase.eIdle;  // 内部状态 / Internal state
    afbRs         : ARRAY[1..4] OF FB_DL_RampSoakProfile;  // 每温区一条曲线实例（无条件调用）/ Per-zone profile instance
    rtrStart      : R_TRIG;                         // 启动沿 / Start edge
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    abZoneFrozen  : ARRAY[1..4] OF BOOL;            // 温区冻结掩码（实测无效）/ Zone frozen mask
    abZoneDone    : ARRAY[1..4] OF BOOL;            // 温区过终点窗掩码 / Zone end-window mask
    abSegChgPrev  : ARRAY[1..4] OF BOOL;            // 上拍段切换沿（冻结一拍用）/ Previous segment-change edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bZoneOk       : BOOL;                           // 本拍温度数组有效（逐区判定）/ Zone validity this scan
    bAnyFrozen    : BOOL;                           // 存在冻结区 / Any zone frozen
    bAllInvalid   : BOOL;                           // 全部温区无效 / All zones invalid
    nZ            : INT;                            // 温区遍历索引 / Zone loop index
    nSegMax       : INT;                            // 全区最大段号（输出口径）/ Max segment across zones
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
    bTonArmed     : BOOL;                           // 段超时定时器装载条件 / Segment timeout arming condition
END_VAR
VAR CONSTANT
    DL_LAM_ZMAX   : INT := 4;                       // 温区数上限 [区] / Zone count upper bound
    DL_LAM_INFMAX : REAL := 1.0E30;                 // 温度有限值幅值上限 [°C] / Temperature finite bound [degC]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrStart(CLK := bStart);                          // 每拍刷新启动沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (nZoneCount >= 1) AND (nZoneCount <= DL_LAM_ZMAX)    // 温区数域闸
          AND (TIME_TO_REAL(tRampUp) > 0.0)                     // 升温时长 > 0（斜率合法性由时长承载）
          AND (TIME_TO_REAL(tCoolDown) > 0.0) AND (TIME_TO_REAL(tSoak) >= 0.0)
          AND (fEndWinK > fEps);                                // 终点窗半宽正域
FOR nZ := 1 TO DL_LAM_ZMAX DO
    bCfgOk := bCfgOk AND (aTgtRampC[nZ] = aTgtRampC[nZ])        // 目标温度 NaN 自反
              AND (aTgtSoakC[nZ] = aTgtSoakC[nZ]) AND (aTgtCoolC[nZ] = aTgtCoolC[nZ])
              AND (ABS(aTgtRampC[nZ]) < DL_LAM_INFMAX)          // 幅值域闸（仅组态域，实测另行判定）
              AND (ABS(aTgtSoakC[nZ]) < DL_LAM_INFMAX) AND (ABS(aTgtCoolC[nZ]) < DL_LAM_INFMAX);
END_FOR
IF NOT bCfgOk THEN
    uFault := 16#0002_068D;                       // 故障级：段表组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清段故障锁存（解除路径可达）
    FOR nZ := 1 TO DL_LAM_ZMAX DO
        abZoneDone[nZ] := FALSE;                  // 完成掩码同步复位
        abZoneFrozen[nZ] := FALSE;                // 冻结掩码同步复位
    END_FOR
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 逐温区实例调用（无条件）与实测域闸 === *)
bAnyFrozen := FALSE;                              // 冻结汇总先清
bAllInvalid := TRUE;                              // 全无效假设先置
FOR nZ := 1 TO DL_LAM_ZMAX DO
    bZoneOk := (aTempActC[nZ] = aTempActC[nZ]) AND (ABS(aTempActC[nZ]) < DL_LAM_INFMAX);  // NaN 自反 + 幅值闸
    IF bZoneOk THEN
        abZoneFrozen[nZ] := FALSE;                // 该区恢复有效
        abZoneDone[nZ] := abZoneDone[nZ] OR (ABS(aTempActC[nZ] - aTgtCoolC[nZ]) <= fEndWinK + fEps);  // 过终点窗判定（保持型）
        afbRs[nZ](bStart := rtrStart.Q,           // 启动沿下发
                  bHold := bHold OR abZoneFrozen[nZ],   // 外部保持或该区无效冻结（实例内冻结计时）
                  fTrackValue := aTempActC[nZ],   // 无效恢复后无扰回投基准
                  bTrack := FALSE,                // 有效区不跟踪（跟踪入口仅供无效恢复衔接）
                  nSegCount := 3,                 // 固定三段：升温/保温/降温
                  aTarget[1] := aTgtRampC[nZ],    // 段 1 目标：升温
                  aTarget[2] := aTgtSoakC[nZ],    // 段 2 目标：保温
                  aTarget[3] := aTgtCoolC[nZ],    // 段 3 目标：降温
                  aRampTime[1] := tRampUp,        // 段 1 斜坡时间
                  aRampTime[2] := T#0S,           // 段 2 阶跃直达保温目标（保温由时长承载）
                  aRampTime[3] := tCoolDown,      // 段 3 斜坡时间
                  aSoakTime[1] := T#0S,           // 升温到位即切段
                  aSoakTime[2] := tSoak,          // 保温时长
                  aSoakTime[3] := T#0S,           // 降温到位即完成
                  bLoopProfile := FALSE,          // 单次配方不循环
                  bReset := rtrReset.Q);          // 复位沿透传
        IF afbRs[nZ].bSegChange THEN
            abSegChgPrev[nZ] := TRUE;             // 段切换沿：下一拍冻结一拍防设定阶跃
        ELSE
            abSegChgPrev[nZ] := FALSE;            // 非切换拍清标记
        END_IF
        IF NOT abSegChgPrev[nZ] THEN
            afZoneSpC[nZ] := afbRs[nZ].fSetpoint; // 非冻结拍：区设定跟随曲线
        END_IF                                    // 冻结拍：保持上拍设定（防阶跃）
        anZoneSeg[nZ] := afbRs[nZ].nSegAct;       // 段号输出
    ELSE
        abZoneFrozen[nZ] := TRUE;                 // 该区判定冻结（不塞伪值）
        uInfo := 16#0002_06AD;                    // 信息级：温区实测无效该区冻结
        afbRs[nZ](bStart := FALSE, bHold := TRUE, bReset := FALSE,   // 实例仍无条件调用：保持态
                  fTrackValue := aTempActC[nZ], bTrack := TRUE,      // 跟踪入口挂无效值会被实例自身域闸拒绝
                  nSegCount := 3, aTarget[1] := aTgtRampC[nZ], aTarget[2] := aTgtSoakC[nZ],
                  aTarget[3] := aTgtCoolC[nZ], aRampTime[1] := tRampUp, aRampTime[2] := T#0S,
                  aRampTime[3] := tCoolDown, aSoakTime[1] := T#0S, aSoakTime[2] := tSoak,
                  aSoakTime[3] := T#0S, bLoopProfile := FALSE);
        anZoneSeg[nZ] := afbRs[nZ].nSegAct;       // 段号照透传（判定冻结但显示不冻结）
    END_IF
    bAnyFrozen := bAnyFrozen OR abZoneFrozen[nZ]; // 汇总冻结
    bAllInvalid := bAllInvalid AND (NOT bZoneOk); // 汇总全无效
END_FOR

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_LtpPhase.eIdle :
    bProfileDone := FALSE;                        // 空闲未完成
    bHoldActive := FALSE;                         // 空闲无保温
    IF uFault <> 16#0000 THEN
        _eState := E_DL_LtpPhase.eFault;          // 故障优先
    ELSIF bAllInvalid AND bCfgOk THEN
        _eState := E_DL_LtpPhase.eFrozen;         // 全区无效进冻结
    ELSIF (afbRs[1].nSegAct > 0) OR (afbRs[2].nSegAct > 0)
      OR (afbRs[3].nSegAct > 0) OR (afbRs[4].nSegAct > 0) THEN
        _eState := E_DL_LtpPhase.eRun;            // 任一实例段号非零即运行相
    END_IF

E_DL_LtpPhase.eRun :
    nSegMax := 0;                                 // 段号汇总清零
    bHoldActive := FALSE;                         // 保温标志本拍重算
    FOR nZ := 1 TO nZoneCount DO
        IF anZoneSeg[nZ] > nSegMax THEN
            nSegMax := anZoneSeg[nZ];             // 取全区最大段号
        END_IF
        IF anZoneSeg[nZ] = 2 THEN
            bHoldActive := TRUE;                  // 任一区在保温段即置保温标志
        END_IF
        bTonArmed := (anZoneSeg[nZ] = 2) AND (NOT abZoneFrozen[nZ]);   // 保温超时只对有效区计时
        IF bTonArmed AND (afbRs[nZ].fSoakElapsed > TIME_TO_REAL(tSoak) + 10.0) THEN
            uFault := 16#0002_069D;               // 故障级：保温超时仍未达窗（锁存，不死等）
        END_IF
    END_FOR
    IF uFault <> 16#0000 THEN
        _eState := E_DL_LtpPhase.eFault;          // 故障转出
    ELSIF bAllInvalid THEN
        _eState := E_DL_LtpPhase.eFrozen;         // 全区无效转冻结
    ELSE
        bProfileDone := TRUE;                     // 完成假设：逐区复核
        FOR nZ := 1 TO nZoneCount DO
            bProfileDone := bProfileDone AND (abZoneDone[nZ] OR (afbRs[nZ].bDone AND bZoneOk));  // 全区过窗才完成
        END_FOR
        bProfileDone := bProfileDone AND (NOT bAnyFrozen);   // 存在冻结区不出完成
        IF bProfileDone THEN
            _eState := E_DL_LtpPhase.eDone;       // 转完成相
        END_IF
    END_IF

E_DL_LtpPhase.eDone :
    bHoldActive := FALSE;                         // 完成相无保温
    bProfileDone := TRUE;                         // 完成保持（保持型，防同拍抹除）
    IF rtrStart.Q THEN
        bProfileDone := FALSE;                    // 新启动沿重开
        _eState := E_DL_LtpPhase.eRun;            // 回运行相
    END_IF

E_DL_LtpPhase.eFrozen :
    bProfileDone := FALSE;                        // 冻结相不出完成
    IF (NOT bAllInvalid) AND (uFault = 16#0000) THEN
        _eState := E_DL_LtpPhase.eRun;            // 任一区恢复即回运行（解除路径可达）
    END_IF

E_DL_LtpPhase.eFault :
    bHoldActive := FALSE;                         // 故障相无保温
    IF uFault = 16#0000 THEN
        _eState := E_DL_LtpPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_LtpPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_068D;                       // 故障级：相 ID 越界复用组态码段
END_CASE

(* === 段 4 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
