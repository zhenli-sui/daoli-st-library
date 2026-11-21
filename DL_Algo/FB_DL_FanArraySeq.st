// =====================================================================
// FB_DL_FanArraySeq.st
// 风机阵列轮值与变频/工频混拖调度（轮值均衡 + 分级投切 + 混拖互斥）
// Fan array duty rotation and VFD/direct staging scheduler
// 所属子库: DL_Algo    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0002_3729 ~ 16#0002_372D (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: hvac, fan-array, duty-rotation, staging
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 17)
// 分层声明: 本件为阵列级编排, 轮值均衡沿用库内轮值件范式、分级投切沿用
//           风机阵列分级件范式, 单台风机本体控制不在本件复现;
//           混拖互斥: 同一台风机同一拍至多处于变频或工频一种模式
// =====================================================================
FUNCTION_BLOCK FB_DL_FanArraySeq
VAR_INPUT
    bEnable    : BOOL  := FALSE;    // 使能 / Enable
    uReqStages : USINT := 2;        // 需求台数 0~6, 越界钳位 / Required stages, clamped
    abFanAvail : ARRAY[1..6] OF BOOL;   // 各台风机可用反馈 / Fan availability
    abVfdEn    : ARRAY[1..6] OF BOOL;   // 各台变频位（真 = 具备变频能力）/ VFD-capable flag
    tMinRun    : TIME  := T#30S;    // 最短运行时间（防振颤与轮值门槛）T#1S~T#60M / Min run time [s]
    bRotateReq : BOOL  := FALSE;    // 轮值请求命令 / Rotation request
END_VAR
VAR_OUTPUT
    abFanRun     : ARRAY[1..6] OF BOOL;   // 各台运行输出 / Fan run outputs
    abFanVfdMode : ARRAY[1..6] OF BOOL;   // 各台变频模式输出 / Fan VFD mode outputs
    uRunCount    : USINT := 0;      // 运行台数 / Running count
    eErr         : UDINT := 16#0002_3729;  // 错误码 / Error code
END_VAR
VAR
    rtrRotate  : R_TRIG;            // 轮值请求沿, 每拍无条件刷新 / Rotate edge, refreshed every cycle
    aTonRun    : ARRAY[1..6] OF TON;    // 各台运行计时, 每拍无条件刷新 / Per-fan run timers, refreshed every cycle
    abRunSel   : ARRAY[1..6] OF BOOL;   // 本拍期望运行集 / Desired run set this cycle
    uLeadIdx   : USINT := 1;       // 轮值起始索引 / Rotation lead index
    uReq       : USINT := 0;       // 钳位后需求台数 / Clamped demand
    uTarget    : USINT := 0;       // 实际目标台数 / Effective target
    uAvailCnt  : USINT := 0;       // 可用台数 / Available count
    uSelCnt    : USINT := 0;       // 已选台数 / Selected count
    uK         : USINT := 0;       // 轮转探测偏移 / Rotation probe offset
    uIdx       : USINT := 1;       // 轮转探测索引 / Rotation probe index
    uNext      : USINT := 1;       // 轮值推进探测索引 / Lead advance probe index
    uProbe     : USINT := 0;       // 轮值推进守卫计数 / Lead advance guard counter
    bClamp     : BOOL := FALSE;     // 需求越界钳位标记 / Demand clamp flag
    bShort     : BOOL := FALSE;     // 需求超可用标记 / Demand exceeds availability flag
    bRotOk     : BOOL := FALSE;     // 轮值允许标记 / Rotation allowed flag
    bStarted   : BOOL := FALSE;     // 本拍已投一台标记 / Started one this cycle flag
    bStopped   : BOOL := FALSE;     // 本拍已停一台标记 / Stopped one this cycle flag
    uZi        : INT   := 1;       // 1..6 数组下标 / Array subscript 1..6
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0002_3729 信息 阵列调度正常
//   16#0002_372A 信息 需求台数越界钳位（大于 6 已钳到 6）
//   16#0002_372B 信息 需求超可用（只投可用台数, 缺口提示）
//   16#0002_372C 信息 轮值等待（存在未达最短运行时间的运行台, 轮值请求挂起）
//   16#0002_372D 信息 待机未使能（全停安全侧）
// ---------------------------------------------------------------------

// ---- 需求钳位 / Demand clamp ----
bClamp := FALSE;
uReq := uReqStages;
IF uReqStages > 6 THEN
    uReq := 6;                      // 上界钳位 / Clamp upper
    bClamp := TRUE;                 // 置钳位信息 / Set clamp info
END_IF

// ---- 可用台数 / Available count ----
uAvailCnt := 0;
FOR uZi := 1 TO 6 DO
    IF abFanAvail[uZi] THEN
        uAvailCnt := uAvailCnt + 1;
    END_IF
END_FOR

// ---- 目标台数（不超可用, 台数 0 → 全停安全侧）/ Effective target ----
uTarget := uReq;
IF uTarget > uAvailCnt THEN
    uTarget := uAvailCnt;           // 只投可用数 / Only available count
    bShort := TRUE;                 // 置缺口信息 / Set shortfall info
END_IF

// ---- 轮值沿与运行计时实例无条件周期刷新 / Unconditional edge and timer refresh ----
rtrRotate(CLK := bRotateReq);
FOR uZi := 1 TO 6 DO
    aTonRun[uZi](IN := abFanRun[uZi], PT := tMinRun);   // 运行计时 / Run timing
END_FOR

// ---- 未使能全停（安全侧）/ All stop when disabled ----
IF NOT bEnable THEN
    FOR uZi := 1 TO 6 DO
        abFanRun[uZi] := FALSE;     // 全停 / All stop
    END_FOR
END_IF

// ---- 轮值允许判: 全部运行台已达最短运行时间 / Rotation allowed judge ----
bRotOk := TRUE;
FOR uZi := 1 TO 6 DO
    IF abFanRun[uZi] AND (NOT aTonRun[uZi].Q) THEN
        bRotOk := FALSE;            // 存在未达门槛的运行台 / Some fan below min run
    END_IF
END_FOR

// ---- 轮值推进: 全部运行台达门槛时沿探测推进起始索引（守卫计数防死循环）
//      Lead advance on rotation request ----
IF rtrRotate.Q AND bEnable AND bRotOk THEN
    uNext := uLeadIdx;              // 自当前起始索引探测 / Probe from lead
    uProbe := 0;
    WHILE uProbe < 6 DO
        uNext := uNext + 1;
        IF uNext > 6 THEN
            uNext := 1;             // 回绕 / Wrap
        END_IF
        uProbe := uProbe + 1;
        IF abFanAvail[uNext] THEN
            uLeadIdx := uNext;      // 推进起始索引 / Advance lead
            uProbe := 6;            // 提前退出 / Early exit
        END_IF
    END_WHILE
END_IF

// ---- 分级投切选择: 变频台优先, 轮值序探测, 工频补位 / Staging selection ----
FOR uZi := 1 TO 6 DO
    abRunSel[uZi] := FALSE;         // 期望集清空 / Clear desired set
END_FOR
uSelCnt := 0;
IF bEnable AND (uTarget > 0) THEN
    // 第一遍: 沿轮值序选变频台 / Pass 1: VFD-capable fans in rotation order
    uK := 0;
    WHILE (uK < 6) AND (uSelCnt < uTarget) DO
        uIdx := uLeadIdx + uK;
        IF uIdx > 6 THEN
            uIdx := uIdx - 6;       // 条件回绕, 不用取余 / Conditional wrap
        END_IF
        uK := uK + 1;
        IF abFanAvail[uIdx] AND abVfdEn[uIdx] AND (NOT abRunSel[uIdx]) THEN
            abRunSel[uIdx] := TRUE;
            uSelCnt := uSelCnt + 1;
        END_IF
    END_WHILE
    // 第二遍: 沿轮值序用工频台补位 / Pass 2: direct-on-line fans fill
    uK := 0;
    WHILE (uK < 6) AND (uSelCnt < uTarget) DO
        uIdx := uLeadIdx + uK;
        IF uIdx > 6 THEN
            uIdx := uIdx - 6;
        END_IF
        uK := uK + 1;
        IF abFanAvail[uIdx] AND (NOT abRunSel[uIdx]) THEN
            abRunSel[uIdx] := TRUE;
            uSelCnt := uSelCnt + 1;
        END_IF
    END_WHILE
END_IF

// ---- 分级投切执行: 同拍至多投一台、停一台（防振颤, 未达门槛不停机）
//      Staged apply: at most one start and one stop per cycle ----
bStarted := FALSE;
bStopped := FALSE;
FOR uZi := 1 TO 6 DO
    IF abRunSel[uZi] AND (NOT abFanRun[uZi]) AND (NOT bStarted) THEN
        abFanRun[uZi] := TRUE;      // 投入一台 / Start one
        bStarted := TRUE;
    END_IF
END_FOR
FOR uZi := 1 TO 6 DO
    IF (NOT abRunSel[uZi]) AND abFanRun[uZi] AND aTonRun[uZi].Q AND (NOT bStopped) THEN
        abFanRun[uZi] := FALSE;     // 停运一台（已达最短运行时间才停）/ Stop one eligible
        bStopped := TRUE;
    END_IF
END_FOR

// ---- 混拖模式输出（一台一拍至多一种模式）/ Mode outputs, one mode per fan ----
FOR uZi := 1 TO 6 DO
    abFanVfdMode[uZi] := abFanRun[uZi] AND abVfdEn[uZi];
END_FOR

// ---- 运行台数 / Running count ----
uRunCount := 0;
FOR uZi := 1 TO 6 DO
    IF abFanRun[uZi] THEN
        uRunCount := uRunCount + 1;
    END_IF
END_FOR

// ---- 错误码仲裁 / Error arbitration ----
IF NOT bEnable THEN
    eErr := 16#0002_372D;           // 待机全停 / Standby all stop
ELSIF bClamp THEN
    eErr := 16#0002_372A;           // 需求钳位 / Demand clamped
ELSIF bShort THEN
    eErr := 16#0002_372B;           // 需求超可用 / Short of availability
ELSIF bRotateReq AND (NOT bRotOk) THEN
    eErr := 16#0002_372C;           // 轮值等待 / Rotation pending
ELSE
    eErr := 16#0002_3729;           // 调度正常 / Normal
END_IF

END_FUNCTION_BLOCK
