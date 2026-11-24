(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WaferHandoffSeq
 * 所属子库 (Sublibrary) : DL_Device
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 双机械手晶圆交接防碰撞握手公开工艺语义（行业池），
 *                         道莅 clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 双机械手交接防碰撞握手顺控件。步序：A/B 就位 →
 *                         A 释放 → B 吸持 → A 撤离 → B 撤离 → 完成。
 *                         互斥核心写死：任一方未撤离交接区，另一方不得获得
 *                         移动放行；防碰撞为安全侧语义。双请求同拍按固定
 *                         优先 A 先（头注释留档）。到位信号非预期跳变
 *                         即中止锁故障。不套通用 InterlockMatrix（判定段
 *                         与执行段不共享状态机教训，本件自带专用互锁）。
 * 状态机   (States)     : eIdle 待机 / eMoveAIn A 进场 / eMoveBIn B 进场 /
 *                         eARelease A 释放 / eWaitGripB B 吸持确认 /
 *                         eAExit A 撤离 / eBExit B 撤离 / eDone 单拍完成 /
 *                         eFault 故障锁定（CASE 带 ELSE 兜底）。
 * 码位     (Codes)      : 16#0003_03F2 信息级：双请求同拍（A 优先留档，
 *                                      不置 bError）
 *                         16#0003_03F3 故障级：步超时
 *                         16#0003_03F4 故障级：移动互锁违例（防御断言）
 *                         16#0003_03F5 故障级：到位/吸持反馈矛盾（非预期跳变）
 *                         16#0003_03F6 故障级：状态非法（ELSE 兜底）
 * 边界防错 (Boundary)   : 1 移动放行由状态机逐拍重算派生，非锁存量；
 *                         2 步超时 TON 按步断输入（步切换拍单拍断输入）；
 *                         3 TON/R_TRIG 实例每拍无条件刷新；
 *                         4 故障锁存可达解除路径：撤使能（bEn 下降）回待机清码；
 *                         5 bDone 为单拍脉冲（R27 跨拍须清零）。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 9）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_HandoffStep（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HandoffStep :
(
    eIdle      := 0,    // 待机：等待双方请求 / Idle, waiting for both requests
    eMoveAIn   := 10,   // A 进场：放行 A 至就位 / A entering, move permit to A
    eMoveBIn   := 20,   // B 进场：放行 B 至就位 / B entering, move permit to B
    eARelease  := 30,   // A 释放：等待 A 吸持反馈消失 / A releasing, wait grip-A drop
    eWaitGripB := 40,   // B 吸持：等待 B 吸持确认 / B gripping, wait grip-B confirm
    eAExit     := 50,   // A 撤离：放行 A 至出场 / A exiting, move permit to A
    eBExit     := 60,   // B 撤离：放行 B 至出场 / B exiting, move permit to B
    eDone      := 70,   // 完成：单拍脉冲后回待机 / Done, one-scan pulse then idle
    eFault     := 99    // 故障：锁定等待撤使能复位 / Fault, latched until disabled
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_WaferHandoffSeq
 * 调用约定: 每个扫描周期无条件调用一次；bMoveA/bMoveB 为移动放行指令。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_WaferHandoffSeq
VAR_INPUT
    bReqA    : BOOL := FALSE;         // 机械手 A 交接请求 / Robot A handoff request
    bReqB    : BOOL := FALSE;         // 机械手 B 交接请求 / Robot B handoff request
    bPosA    : BOOL := FALSE;         // A 交接区就位反馈 / Robot A in-position feedback
    bPosB    : BOOL := FALSE;         // B 交接区就位反馈 / Robot B in-position feedback
    bGripA   : BOOL := FALSE;         // A 吸持反馈 / Robot A grip feedback
    bGripB   : BOOL := FALSE;         // B 吸持反馈 / Robot B grip feedback
    bEn      : BOOL := FALSE;         // 使能，下降沿为故障可达解除路径 / Enable, falling edge is fault release path
    tStep    : TIME := T#5S;          // 单步超时 [毫秒] / Per-step timeout [ms]
END_VAR
VAR_OUTPUT
    eStep    : E_DL_HandoffStep;      // 当前步状态 / Current handshake step
    bMoveA   : BOOL;                  // A 移动放行（互锁派生）/ Robot A move permit, interlocked
    bMoveB   : BOOL;                  // B 移动放行（互锁派生）/ Robot B move permit, interlocked
    bDone    : BOOL;                  // 交接完成单拍脉冲（R27）/ Handoff done one-scan pulse
    bError   : BOOL;                  // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    tonStep  : TON;                   // 步超时定时器，每拍无条件刷新 / Step timeout timer, refreshed every scan
    rTrigA   : R_TRIG;                // A 请求沿检测，每拍无条件刷新 / Request-A edge detector
    rTrigB   : R_TRIG;                // B 请求沿检测，每拍无条件刷新 / Request-B edge detector
    eStatePrev : E_DL_HandoffStep;    // 上一拍步快照 / Previous step snapshot
    bStepRst : BOOL;                  // 步切换拍单拍断超时输入 / One-scan timeout input break on step change
    uInfoOne : UDINT;                 // 信息级单拍码暂存 / One-scan info code staging
    uCodeLatch : UDINT;               // 故障级锁存码 / Latched fault code
    bInit    : BOOL := TRUE;          // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_WHS_ZERO : UDINT := 16#0000_0000; // 零码常量 / Zero code constant
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigA(CLK := bReqA);                                 // A 请求沿检测 / Request-A edge detection
rTrigB(CLK := bReqB);                                 // B 请求沿检测 / Request-B edge detection
tonStep(IN := (eStep <> eIdle) AND (eStep <> eDone) AND (eStep <> eFault)
        AND (NOT bStepRst), PT := tStep);             // 步超时计时，步切换拍断输入 / Step timing, broken on step change

// ---- 段 2｜步切换检测（供超时按步断输入）----------------------------------------
bStepRst := (eStep <> eStatePrev) OR bInit;           // 步变化即断输入 / Step change breaks timing input
eStatePrev := eStep;                                  // 快照留痕 / Snapshot previous step
bInit := FALSE;                                       // 清首扫标志 / Clear first-scan flag

// ---- 段 3｜移动放行派生：互斥核心，任一方未撤离另一方不得放行 --------------------
bMoveA := (eStep = eMoveAIn) OR (eStep = eAExit);     // A 放行仅进场/撤离步 / A permit only in enter/exit steps
bMoveB := (eStep = eMoveBIn) OR (eStep = eBExit);     // B 放行仅进场/撤离步 / B permit only in enter/exit steps

// ---- 段 4｜状态机（CASE 带 ELSE 兜底锁故障）--------------------------------------
CASE eStep OF
    eIdle:
        bDone := FALSE;                               // 待机清完成脉冲 / Idle clears done pulse
        IF bEn AND rTrigA.Q AND rTrigB.Q THEN
            uInfoOne := 16#0003_03F2;                 // 信息级：双请求同拍 A 优先 / Info: simultaneous requests, A first
        END_IF
        IF bEn AND (bReqA OR bReqB) AND (rTrigA.Q OR rTrigB.Q) THEN
            eStep := eMoveAIn;                        // 任一请求沿启动，A 先动 / Any request edge starts, A first
        END_IF
    eMoveAIn:
        IF NOT bEn THEN
            eStep := eIdle;                           // 撤使能回待机 / Disable returns to idle
        ELSIF tonStep.Q THEN
            eStep := eFault;                          // 步超时锁故障 / Step timeout latches fault
            uCodeLatch := 16#0003_03F3;               // 码位：步超时 / Code: step timeout
        ELSIF bPosA AND (NOT bGripA) THEN
            eStep := eFault;                          // 就位未持片反馈矛盾 / In-position without wafer, contradiction
            uCodeLatch := 16#0003_03F5;               // 码位：反馈矛盾 / Code: feedback contradiction
        ELSIF bPosA AND bGripA THEN
            eStep := eMoveBIn;                        // A 就位且持片转 B 进场 / A placed with wafer, B enters
        END_IF
    eMoveBIn:
        IF NOT bEn THEN
            eStep := eIdle;                           // 撤使能回待机 / Disable returns to idle
        ELSIF tonStep.Q THEN
            eStep := eFault;                          // 步超时锁故障 / Step timeout latches fault
            uCodeLatch := 16#0003_03F3;               // 码位：步超时 / Code: step timeout
        ELSIF (NOT bPosA) OR (NOT bGripA) THEN
            eStep := eFault;                          // A 就位窗口非预期丢失 / Unexpected loss of A window
            uCodeLatch := 16#0003_03F5;               // 码位：反馈矛盾 / Code: feedback contradiction
        ELSIF bPosB THEN
            eStep := eARelease;                       // B 就位转 A 释放 / B placed, A releases
        END_IF
    eARelease:
        IF NOT bEn THEN
            eStep := eIdle;                           // 撤使能回待机 / Disable returns to idle
        ELSIF tonStep.Q THEN
            eStep := eFault;                          // 步超时锁故障 / Step timeout latches fault
            uCodeLatch := 16#0003_03F3;               // 码位：步超时 / Code: step timeout
        ELSIF (NOT bPosA) THEN
            eStep := eFault;                          // A 就位窗口非预期丢失 / Unexpected loss of A window
            uCodeLatch := 16#0003_03F5;               // 码位：反馈矛盾 / Code: feedback contradiction
        ELSIF NOT bGripA THEN
            eStep := eWaitGripB;                      // A 释放完成转 B 吸持确认 / A released, wait grip-B
        END_IF
    eWaitGripB:
        IF NOT bEn THEN
            eStep := eIdle;                           // 撤使能回待机 / Disable returns to idle
        ELSIF tonStep.Q THEN
            eStep := eFault;                          // 步超时锁故障 / Step timeout latches fault
            uCodeLatch := 16#0003_03F3;               // 码位：步超时 / Code: step timeout
        ELSIF (NOT bPosA) OR (NOT bPosB) THEN
            eStep := eFault;                          // 就位窗口非预期跳变 / Unexpected position jump
            uCodeLatch := 16#0003_03F5;               // 码位：反馈矛盾 / Code: feedback contradiction
        ELSIF bGripB AND (NOT bGripA) THEN
            eStep := eAExit;                          // B 吸持确认且 A 已释放 / B gripping and A released
        END_IF
    eAExit:
        IF NOT bEn THEN
            eStep := eIdle;                           // 撤使能回待机 / Disable returns to idle
        ELSIF tonStep.Q THEN
            eStep := eFault;                          // 步超时锁故障 / Step timeout latches fault
            uCodeLatch := 16#0003_03F3;               // 码位：步超时 / Code: step timeout
        ELSIF NOT bGripB THEN
            eStep := eFault;                          // B 持片窗口非预期丢失 / Unexpected loss of B wafer
            uCodeLatch := 16#0003_03F5;               // 码位：反馈矛盾 / Code: feedback contradiction
        ELSIF NOT bPosA THEN
            eStep := eBExit;                          // A 撤离完成转 B 撤离 / A exited, B exits
        END_IF
    eBExit:
        IF NOT bEn THEN
            eStep := eIdle;                           // 撤使能回待机 / Disable returns to idle
        ELSIF tonStep.Q THEN
            eStep := eFault;                          // 步超时锁故障 / Step timeout latches fault
            uCodeLatch := 16#0003_03F3;               // 码位：步超时 / Code: step timeout
        ELSIF bPosA THEN
            eStep := eFault;                          // A 非预期重返交接区 / A unexpectedly re-enters zone
            uCodeLatch := 16#0003_03F5;               // 码位：反馈矛盾 / Code: feedback contradiction
        ELSIF NOT bPosB THEN
            eStep := eDone;                           // B 撤离完成转完成态 / B exited, to done
        END_IF
    eDone:
        bDone := TRUE;                                // 完成单拍脉冲 / One-scan done pulse
        eStep := eIdle;                               // 下拍回待机 / Back to idle next scan
    eFault:
        bMoveA := FALSE;                              // 故障态撤 A 放行 / Fault revokes A permit
        bMoveB := FALSE;                              // 故障态撤 B 放行 / Fault revokes B permit
        bDone  := FALSE;                              // 故障态清完成脉冲 / Fault clears done pulse
        IF NOT bEn THEN
            eStep := eIdle;                           // 可达解除路径：撤使能复位 / Reachable release: disable
            uCodeLatch := DL_WHS_ZERO;                // 清锁存码 / Clear latched code
        END_IF
    ELSE
        eStep := eFault;                              // 非法状态兜底 / Illegal state fallback
        uCodeLatch := 16#0003_03F6;                   // 码位：状态非法 / Code: illegal state
END_CASE

// ---- 段 5｜防御断言：双放行同拍为互锁违例（构造上不可达，留档兜底）--------------
IF bMoveA AND bMoveB THEN
    bMoveA := FALSE;                                  // 安全侧撤 A 放行 / Safe side revokes A permit
    bMoveB := FALSE;                                  // 安全侧撤 B 放行 / Safe side revokes B permit
    eStep := eFault;                                  // 互锁违例锁故障 / Interlock violation latches fault
    uCodeLatch := 16#0003_03F4;                       // 码位：互锁违例 / Code: interlock violation
END_IF

// ---- 段 6｜错误码装配：故障锁存回放优先，信息级单拍居次 --------------------------
IF eStep = eFault THEN
    bError   := TRUE;                                 // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
ELSIF uInfoOne <> DL_WHS_ZERO THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := uInfoOne;                             // 信息级单拍输出 / One-scan info output
    uInfoOne := DL_WHS_ZERO;                          // 发完即清 / Clear after emit
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := DL_WHS_ZERO;                          // 无码 / No code
END_IF
END_FUNCTION_BLOCK
