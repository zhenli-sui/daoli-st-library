(*
  FB_DL_ProcessKitTimer  —  腔体部件保养计时器 / Chamber kit maintenance timer (pieces + hours dual criterion)
  分类 Category : DL_Device
  码位 Code     : 16#03_2_07
  版本 Version  : 1.0.0
  溯源 Source   : ISA-88 设备保养语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 工艺拍计数与运行时长双口径累计（时长口径复用 FB_DL_RuntimeMeter）；
                  2) 双阈值任一到即锁存 bMaintDue，解除必须经显式确认且运行中禁复位；
                  3) 计数饱和不回绕。
  边界 Boundary : ① 双阈值任一到即锁存（先到先锁，锁存源诊断输出）；
                  ② 解除必须经显式 bMaintAck 且运行中（bRunTimeEn）禁复位；
                  ③ 时长口径暂停不累计（bRunTimeEn FALSE 不计时，与 FB_DL_BatchPhaseBase 暂停语义一致）；
                  ④ 阈值 0 表示禁用该口径（语义写进头注释）；
                  ⑤ 输出三行同向：累计值 → 到期锁存 → 锁存源。
  依赖 Depends  : FB_DL_RuntimeMeter × 1（时长口径，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0307 故障级：组态非法（双阈值同时为 0 = 双口径全禁用）
    16#0002_0317 故障级：相 ID 越界（枚举兜底路径）
    16#0002_0327 信息级：运行中确认被拒（安全侧，不置 bError）
*)

TYPE E_DL_PktPhase :
(
    eIdle  := 0,  // 空闲 / Idle
    eCount := 10, // 双口径累计中 / Dual-criterion accumulating
    eDue   := 20, // 保养到期锁存 / Maintenance due latched
    eFault := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_ProcessKitTimer
VAR_INPUT
    bPiecePulse   : BOOL;                           // 工艺拍计数脉冲（上升沿计一件）/ Piece count pulse, edge
    bRunTimeEn    : BOOL;                           // 运行时长使能（电平，FALSE 暂停不累计）/ Runtime enable, level
    uDeltaTimeMs  : UDINT;                          // 本任务周期耗时 [ms]，调用方注入 / Cycle time in ms, injected
    uMaxPieces    : UDINT := UDINT#50000;           // 保养阈值-拍数 [件]，0 = 禁用该口径 / Piece threshold, 0 = disabled
    uMaxHours     : REAL := 2000.0;                 // 保养阈值-时长 [h]，0 = 禁用该口径 / Hours threshold, 0 = disabled
    bMaintAck     : BOOL;                           // 保养确认（显式复位口径）/ Maintenance acknowledge
    bReset        : BOOL;                           // 复位，上升沿清全部累计 / Reset, clears all totals
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    uPiecesTotal  : UDINT;                          // 累计工艺拍数 [件]，饱和不回绕 / Total pieces, saturated
    fHoursRun     : REAL;                           // 累计运行时长 [h]（时长口径）/ Total runtime hours
    bMaintDue     : BOOL;                           // 保养到期锁存 / Maintenance due, latched
    bDueByPieces  : BOOL;                           // 锁存源：拍数口径 / Due source: pieces
    bDueByHours   : BOOL;                           // 锁存源：时长口径 / Due source: hours
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_PktPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_PktPhase := E_DL_PktPhase.eIdle;  // 内部状态 / Internal state
    fbMeter       : FB_DL_RuntimeMeter;             // 时长口径实例（无条件调用）/ Runtime meter instance
    rtrPulse      : R_TRIG;                         // 拍脉冲上升沿 / Piece pulse edge
    rtrAck        : R_TRIG;                         // 确认上升沿 / Acknowledge edge
    rtrReset      : R_TRIG;                         // 复位上升沿 / Reset edge
    bPiecesEn     : BOOL;                           // 拍数口径启用（阈值 > 0）/ Pieces criterion enabled
    bHoursEn      : BOOL;                           // 时长口径启用（阈值 > 0）/ Hours criterion enabled
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_PKT_PIECE_MAX : UDINT := 16#FFFF_FFFE;       // 拍计数饱和上限，不回绕 / Piece counter saturation limit
    DL_PKT_HOURS_MAX : REAL  := 1.0E9;              // 时长累计饱和上限 [h] / Hours saturation limit [h]
END_VAR

(* === 段 0 · 实例刷新（沿检测无条件周期刷新）=== *)
rtrPulse(CLK := bPiecePulse);                     // 每拍刷新拍脉冲沿
rtrAck(CLK := bMaintAck);                         // 每拍刷新确认沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸（双口径全禁用即组态非法）=== *)
bPiecesEn := (uMaxPieces > UDINT#0);              // 阈值 0 = 禁用该口径（头注释语义）
bHoursEn := (uMaxHours > fEps);                   // 时长阈值 0 = 禁用该口径
IF (NOT bPiecesEn) AND (NOT bHoursEn) THEN
    uFault := 16#0002_0307;                       // 故障级：双口径全禁用（无保养判据可依赖）
END_IF
IF rtrReset.Q THEN
    uFault := 16#0000;                            // 复位沿清组态锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 时长口径实例（无条件调用，暂停不累计）=== *)
fbMeter(bRunning := bRunTimeEn,                   // 运行使能透传（FALSE 暂停不累计，与批次相暂停语义一致）
        uDeltaTimeMs := uDeltaTimeMs,             // 周期耗时注入
        uMaintIntervalMin := UDINT#0,             // 实例内保养预警关闭（到期判据由本件双口径统一承担）
        bMaintAck := FALSE,                       // 实例侧不确认（避免双口径复位不同步）
        bReset := rtrReset.Q);                    // 复位沿透传清零
fHoursRun := fbMeter.fRunHours;                   // 时长累计输出
IF fHoursRun > DL_PKT_HOURS_MAX THEN
    fHoursRun := DL_PKT_HOURS_MAX;                // 时长饱和不回绕
END_IF

(* === 段 3 · 拍计数（沿触发，饱和不回绕）=== *)
IF rtrPulse.Q AND (_eState <> E_DL_PktPhase.eFault) THEN
    IF uPiecesTotal < DL_PKT_PIECE_MAX THEN
        uPiecesTotal := uPiecesTotal + UDINT#1;   // 计数累加（饱和守卫，不回绕）
    END_IF
END_IF

(* === 段 4 · 双口径到期判据与锁存 === *)
bDueByPieces := bPiecesEn AND (uPiecesTotal >= uMaxPieces);    // 拍数口径到达
bDueByHours := bHoursEn AND (fHoursRun >= uMaxHours);          // 时长口径到达
IF bDueByPieces OR bDueByHours THEN
    bMaintDue := TRUE;                            // 任一到达即锁存（先到先锁）
END_IF

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PktPhase.eIdle :
    bMaintDue := FALSE;                           // 空闲未锁存
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PktPhase.eFault;          // 故障优先
    ELSIF bPiecesEn OR bHoursEn THEN
        _eState := E_DL_PktPhase.eCount;          // 任一口径启用进累计相
    END_IF

E_DL_PktPhase.eCount :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PktPhase.eFault;          // 故障转出
    ELSIF bMaintDue THEN
        _eState := E_DL_PktPhase.eDue;            // 到期转锁存相
    END_IF

E_DL_PktPhase.eDue :
    bMaintDue := TRUE;                            // 锁存保持（防同拍抹除）
    bDueByPieces := bPiecesEn AND (uPiecesTotal >= uMaxPieces);    // 锁存源保持诊断
    bDueByHours := bHoursEn AND (fHoursRun >= uMaxHours);
    IF rtrAck.Q AND (NOT bRunTimeEn) THEN
        bMaintDue := FALSE;                       // 显式确认且非运行中：解除（运行中确认被拒）
        uPiecesTotal := UDINT#0;                  // 拍计数同步清零（保养后新周期）
        fbMeter(bRunning := FALSE, uDeltaTimeMs := uDeltaTimeMs,   // 实例确认复位时长口径
                uMaintIntervalMin := UDINT#0, bMaintAck := TRUE, bReset := FALSE);
        fHoursRun := 0.0;                         // 时长同步清零
        _eState := E_DL_PktPhase.eCount;          // 回累计相
    ELSIF rtrAck.Q AND bRunTimeEn THEN
        uInfo := 16#0002_0327;                    // 信息级：运行中确认被拒（安全侧）
    END_IF

E_DL_PktPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_PktPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_PktPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0317;                       // 故障级：相 ID 越界
END_CASE

(* === 段 6 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
