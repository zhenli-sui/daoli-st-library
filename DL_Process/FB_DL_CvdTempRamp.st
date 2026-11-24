(*
  FB_DL_CvdTempRamp  —  CVD/扩散炉多段 Ramp/Soak 曲线跟随 + 均匀性判据 / CVD furnace multi-segment ramp-soak tracking with uniformity
  分类 Category : DL_Process
  码位 Code     : 16#06_0_91
  版本 Version  : 1.0.0
  溯源 Source   : LGF Technology 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 多段 Ramp/Soak 工艺曲线跟随（复用 FB_DL_RampSoakProfile 设定源，全部温区共用同一条曲线）；
                  2) 均匀性判据：各温区统计均值与设定偏差逐区复核，全区进窗才置 bUniformOk；
                  3) Ramp 段跟随失败升级（|实测 − 设定| 持续超限 → 段故障锁存）。
  边界 Boundary : ① 均匀性测点 < 2 不出结论（信息级，禁单点冒充均匀性）；
                  ② 任一温区无效：该区判定冻结并置码，禁塞伪值；
                  ③ Ramp 段斜率跟随偏差超限持续 N 拍判跟随失败升级（非死等）；
                  ④ Soak 终点窗带独立超时出口（计时超限升级）；
                  ⑤ 与 FB_DL_LaminatorTempProfile 职责边界：本件面向 CVD/扩散炉多段（1..8 段可配）
                     工艺曲线 + 跨温区均匀性判据；层压机件为固定三段真空/加压配方 + 保温保持出口，
                     二者行业参数集与判据分立，互不替代。
  依赖 Depends  : FB_DL_RampSoakProfile × 1（设定源，每拍无条件调用）
                  FB_DL_SignalStatistics × 4（逐温区偏差统计，每拍无条件调用）

  码表 Error codes（本件子码步进 16#30 · 本格 91 与既有 9X 子码段冲突，错位至 C1/D1 避让）:
    16#0002_06C1 故障级：组态非法（段数越界 / 终点窗或跟随门限 <= 0 / 目标温度非有限）
    16#0002_06D1 故障级：跟随失败（Ramp 段偏差持续超门限）或 Soak 超时（锁存需复位）
    16#0002_06B1 信息级：温区无效判定冻结 / 有效测点 < 2 不出均匀性结论（不置 bError）
*)

TYPE E_DL_CtrPhase :
(
    eIdle   := 0,   // 空闲 / Idle
    eRun    := 10,  // 曲线跟随中 / Profile tracking
    eSoakOk := 20,  // 全区保温进窗 / All zones in soak window
    eDone   := 30,  // 曲线完成 / Profile done
    eFrozen := 40,  // 全部温区无效冻结 / All zones frozen
    eFault  := 90   // 跟随失败/超时锁定 / Tracking failure or timeout locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_CvdTempRamp
VAR_INPUT
    bStart        : BOOL;                           // 启动指令，上升沿生效 / Profile start, edge
    bHold         : BOOL;                           // 外部保持 / External hold
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    nSegCount     : INT := 4;                       // 有效段数 [段]，1..8 / Active segment count
    aSegTgtC      : ARRAY[1..8] OF REAL;            // 各段目标温度 [°C] / Segment targets [degC]
    aSegRampT     : ARRAY[1..8] OF TIME;            // 各段斜坡时间 [s]，0 = 阶跃直达 / Segment ramp times
    aSegSoakT     : ARRAY[1..8] OF TIME;            // 各段保温时间 [s]，0 = 无保温 / Segment soak times
    aZoneTempC    : ARRAY[1..4] OF REAL;            // 各温区实测温度 [°C] / Zone measured temperature [degC]
    nZoneCount    : INT := 4;                       // 温区数 [区]，1..4（均匀性测点数）/ Zone count
    fFollowMaxK   : REAL := 15.0;                   // Ramp 跟随偏差门限 [K]，域 > 0 / Tracking deviation limit [K]
    uFollowConfirm: UINT := 10;                     // 跟随失败确认拍数 [拍] / Tracking failure confirm scans
    fEndWinK      : REAL := 3.0;                    // Soak 终点窗半宽 [K]，域 > 0 / Soak end window half width [K]
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fSetpointC    : REAL;                           // 曲线设定输出 [°C] / Profile setpoint output [degC]
    nSegAct       : INT;                            // 当前段号 1..nSegCount / Active segment
    bSoakInWindow : BOOL;                           // 全区保温进窗（多拍确认）/ All zones in soak window
    bUniformOk    : BOOL;                           // 均匀性结论（全区偏差窗内）/ Uniformity verdict
    bProfileDone  : BOOL;                           // 曲线完成标志（保持型）/ Profile done, held
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_CtrPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_CtrPhase := E_DL_CtrPhase.eIdle;  // 内部状态 / Internal state
    fbRs          : FB_DL_RampSoakProfile;          // 曲线设定源实例（无条件调用）/ Profile setpoint source
    afbStat       : ARRAY[1..4] OF FB_DL_SignalStatistics;  // 逐温区偏差统计（无条件调用）/ Per-zone deviation statistics
    rtrStart      : R_TRIG;                         // 启动沿 / Start edge
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    abZoneOk      : ARRAY[1..4] OF BOOL;            // 温区有效掩码 / Zone validity mask
    abZoneInWin   : ARRAY[1..4] OF BOOL;            // 温区进窗掩码 / Zone in-window mask
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bAnyOk        : BOOL;                           // 存在有效温区 / Any valid zone
    bAllInvalid   : BOOL;                           // 全部温区无效 / All zones invalid
    bInRamp       : BOOL;                           // 本拍处于 Ramp 段 / In ramp segment this scan
    bDevOver      : BOOL;                           // 跟随偏差超限（电平）/ Deviation over limit
    uFollowCnt    : UINT;                           // 跟随失败确认计数 [拍] / Tracking failure counter
    bSoakTout     : BOOL;                           // Soak 终点窗超时 / Soak end-window timeout
    fSoakElapsed  : REAL;                           // 进窗后累计等待 [s] / Elapsed wait after in-window [s]
    nZ            : INT;                            // 温区遍历索引 / Zone loop index
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_CTR_ZMAX   : INT := 4;                       // 温区数上限 [区] / Zone count upper bound
    DL_CTR_INFMAX : REAL := 1.0E30;                 // 温度有限值幅值上限 [°C] / Temperature finite bound [degC]
    DL_CTR_SOAK_TOUT : REAL := 60.0;                // Soak 终点窗独立超时 [s] / Soak end-window timeout [s]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrStart(CLK := bStart);                          // 每拍刷新启动沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (nSegCount >= 1) AND (nSegCount <= 8)   // 段数域闸
          AND (nZoneCount >= 1) AND (nZoneCount <= DL_CTR_ZMAX)
          AND (fFollowMaxK > fEps) AND (fEndWinK > fEps)       // 门限正域
          AND (fbRs.fSetpoint = fbRs.fSetpoint);  // 实例侧哨兵（首拍未运行恒真）
FOR nZ := 1 TO 8 DO
    bCfgOk := bCfgOk AND (aSegTgtC[nZ] = aSegTgtC[nZ])         // 段目标 NaN 自反
              AND (ABS(aSegTgtC[nZ]) < DL_CTR_INFMAX);         // 段目标幅值域
END_FOR
IF NOT bCfgOk THEN
    uFault := 16#0002_06C1;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
    uFollowCnt := UINT#0;                         // 跟随确认计数复位
    fSoakElapsed := 0.0;                          // 进窗等待清零
    FOR nZ := 1 TO DL_CTR_ZMAX DO
        abZoneInWin[nZ] := FALSE;                 // 进窗掩码复位
    END_FOR
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 曲线设定源实例（无条件调用）与温区域闸 === *)
fbRs(bStart := rtrStart.Q,                        // 启动沿透传
     bHold := bHold,                              // 外部保持透传
     fStartValue := aZoneTempC[1],                // 首段斜坡起点取 1 区实测（无效时实例域闸兜底）
     nSegCount := INT_TO_USINT(MAX(nSegCount, 1)),// 段数下限防 0
     aTarget := aSegTgtC,                         // 段目标表
     aRampTime := aSegRampT,                      // 段斜坡表
     aSoakTime := aSegSoakT,                      // 段保温表
     bLoopProfile := FALSE,                       // 单次工艺曲线不循环
     bReset := rtrReset.Q);                       // 复位沿透传
fSetpointC := fbRs.fSetpoint;                     // 设定输出
nSegAct := fbRs.nSegAct;                          // 段号输出
bInRamp := (fbRs.ePhase = E_DL_RampSoakPhase.eRamp);  // Ramp 相判据（枚举成员对齐属主件）
bAnyOk := FALSE;                                  // 有效区汇总先清
bAllInvalid := TRUE;                              // 全无效假设先置
FOR nZ := 1 TO DL_CTR_ZMAX DO
    abZoneOk[nZ] := (nZ <= nZoneCount)
                    AND (aZoneTempC[nZ] = aZoneTempC[nZ])
                    AND (ABS(aZoneTempC[nZ]) < DL_CTR_INFMAX);  // NaN 自反 + 幅值闸
    bAnyOk := bAnyOk OR abZoneOk[nZ];             // 汇总有效
    bAllInvalid := bAllInvalid AND (NOT abZoneOk[nZ]);  // 汇总全无效
    afbStat[nZ](fIn := aZoneTempC[nZ] - fSetpointC,             // 偏差量统计（无效值由实例域闸拒绝）
                bSample := abZoneOk[nZ] AND (NOT bHold),        // 无效/保持拍不采
                nWindow := 16,                    // 偏差窗 16 样本
                bClear := rtrStart.Q);            // 启动沿清窗重计
    abZoneInWin[nZ] := abZoneOk[nZ] AND afbStat[nZ].bValid
                       AND (ABS(afbStat[nZ].fMean) <= fEndWinK + fEps);  // 均值偏差进窗
END_FOR
IF bAllInvalid THEN
    uInfo := 16#0002_06B1;                        // 信息级：温区无效判定冻结
END_IF

(* === 段 3 · 全区进窗汇总 / 跟随失败与 Soak 超时判据 === *)
bSoakInWindow := (nZoneCount >= 2) AND (NOT bAllInvalid);      // 测点 < 2 不出进窗结论
FOR nZ := 1 TO nZoneCount DO
    bSoakInWindow := bSoakInWindow AND abZoneInWin[nZ];        // 全区进窗才成立
END_FOR
IF (NOT bSoakInWindow) AND (nZoneCount < 2) AND bAnyOk THEN
    uInfo := 16#0002_06B1;                        // 信息级：有效测点不足不出结论
END_IF
bDevOver := FALSE;                                // 跟随偏差超限本拍重算
FOR nZ := 1 TO nZoneCount DO
    bDevOver := bDevOver OR (abZoneOk[nZ] AND afbStat[nZ].bValid
               AND (ABS(afbStat[nZ].fMean) > fFollowMaxK));      // 任一有效区均值偏差超门限
END_FOR
IF bInRamp AND bDevOver THEN
    uFollowCnt := uFollowCnt + UINT#1;            // Ramp 段偏差超限确认计数
    IF uFollowCnt >= uFollowConfirm THEN
        uFault := 16#0002_06D1;                   // 故障级：跟随失败升级（锁存，非死等）
    END_IF
ELSE
    uFollowCnt := UINT#0;                         // 未超限/非 Ramp 段：计数归零
END_IF
bSoakTout := FALSE;                               // Soak 超时本拍重算
IF bSoakInWindow THEN
    fSoakElapsed := fSoakElapsed + 0.1;           // 进窗后等待累计（周期 0.1 s 口径，与实例采样对齐）
    IF fSoakElapsed > DL_CTR_SOAK_TOUT THEN
        bSoakTout := TRUE;                        // 终点窗独立超时出口
        uFault := 16#0002_06D1;                   // 故障级：Soak 超时（锁存）
    END_IF
ELSE
    fSoakElapsed := 0.0;                          // 未持续进窗：等待清零
END_IF

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_CtrPhase.eIdle :
    bProfileDone := FALSE;                        // 空闲未完成
    bSoakInWindow := FALSE;                       // 空闲无进窗
    IF uFault <> 16#0000 THEN
        _eState := E_DL_CtrPhase.eFault;          // 故障优先
    ELSIF fbRs.nSegAct > 0 THEN
        _eState := E_DL_CtrPhase.eRun;            // 设定源已启动进运行相
    END_IF

E_DL_CtrPhase.eRun :
    bUniformOk := bSoakInWindow;                  // 均匀性结论与进窗同判据（均值偏差窗）
    IF uFault <> 16#0000 THEN
        _eState := E_DL_CtrPhase.eFault;          // 跟随失败/超时转故障
    ELSIF bAllInvalid THEN
        _eState := E_DL_CtrPhase.eFrozen;         // 全区无效转冻结
    ELSIF fbRs.bDone THEN
        bProfileDone := TRUE;                     // 曲线完成（保持型）
        _eState := E_DL_CtrPhase.eDone;           // 转完成相
    ELSIF bSoakInWindow THEN
        _eState := E_DL_CtrPhase.eSoakOk;         // 全区进窗转保温合格相
    END_IF

E_DL_CtrPhase.eSoakOk :
    bUniformOk := TRUE;                           // 均匀性保持
    bSoakInWindow := TRUE;                        // 进窗保持（防同拍抹除）
    IF uFault <> 16#0000 THEN
        _eState := E_DL_CtrPhase.eFault;          // 故障转出
    ELSIF fbRs.bDone THEN
        bProfileDone := TRUE;                     // 曲线完成
        _eState := E_DL_CtrPhase.eDone;           // 转完成相
    ELSIF NOT bAnyOk THEN
        _eState := E_DL_CtrPhase.eFrozen;         // 全区无效转冻结
    END_IF

E_DL_CtrPhase.eDone :
    bProfileDone := TRUE;                         // 完成保持
    IF rtrStart.Q THEN
        bProfileDone := FALSE;                    // 新启动沿重开
        _eState := E_DL_CtrPhase.eRun;            // 回运行相
    END_IF

E_DL_CtrPhase.eFrozen :
    bProfileDone := FALSE;                        // 冻结相不出完成
    bSoakInWindow := FALSE;                       // 冻结相不出进窗
    IF bAnyOk AND (uFault = 16#0000) THEN
        _eState := E_DL_CtrPhase.eRun;            // 任一区恢复回运行（解除路径可达）
    END_IF

E_DL_CtrPhase.eFault :
    bSoakInWindow := FALSE;                       // 故障相不出进窗
    IF uFault = 16#0000 THEN
        _eState := E_DL_CtrPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_CtrPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06C1;                       // 故障级：相 ID 越界复用组态码段
END_CASE

(* === 段 5 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
