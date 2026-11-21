// =====================================================================
// FB_DL_PalletizerStation.st
// 码垛整跺工站编排（进箱→分层码放→层完成→缠膜→出跺，逐相超时）
// Palletizer station sequencing FB via I_DL_Cylinder contracts
// 码位: 16#0005_044E ~ 16#0005_0452 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 16)
// =====================================================================
FUNCTION_BLOCK FB_DL_PalletizerStation
VAR_INPUT
    bEnable       : BOOL  := FALSE;    // 使能 / Enable
    bStart        : BOOL  := FALSE;    // 上升沿启动一跺 / Start on edge
    bReset        : BOOL  := FALSE;    // 复位故障 / Reset
    uLayerCount   : USINT  := 10;      // 每跺层数 1~30 / Layers per pallet
    uBoxPerLayer  : USINT  := 6;       // 每层箱数 1~20 / Boxes per layer
    bBoxPresent   : BOOL  := FALSE;    // 入口有箱 / Box present
    bPlaceDone    : BOOL  := FALSE;    // 单箱落位确认 / Box placed
    bLayerDone    : BOOL  := FALSE;    // 层排布完成（外部层序件回馈）/ Layer done
    bStretchDone  : BOOL  := FALSE;    // 缠膜完成 / Stretch done
    bOutReady     : BOOL  := FALSE;    // 出跺通道就绪 / Discharge ready
    bGripClosed   : BOOL  := FALSE;    // 夹爪已闭合反馈 / Gripper closed
    tStepMax      : TIME  := T#20S;    // 单相超时 T#1S~T#300S / Step timeout [s]
END_VAR
VAR_IN_OUT
    iCylGrip      : I_DL_Cylinder;     // 夹爪气缸契约 / Gripper cylinder
    iCylLift      : I_DL_Cylinder;     // 升降气缸契约 / Lift cylinder
END_VAR
VAR_OUTPUT
    eState        : E_DL_PalletizerState;  // 当前相 / State
    uLayerIdx     : USINT;             // 当前层号 0~30 / Layer index
    uBoxIdx       : USINT;             // 当前层内箱号 0~20 / Box index
    bBusy         : BOOL;              // 运行中 / Busy
    bDone         : BOOL;              // 一跺完成（单拍）/ Pallet done pulse
    eErr          : UDINT;             // 错误码 / Error code
END_VAR
VAR
    rtrigStart    : R_TRIG;            // 启动沿检测（无条件刷新）/ Start edge detector
    tonStep       : TON;               // 本相超时定时器（每相进入时重置，禁跨相复用 R21）/ Step timer, reset per phase entry
    bStepTimerOn  : BOOL;              // 相内定时使能 / Phase timer enable
    bLockoutLatch : BOOL := FALSE;     // 联锁错锁存 / Interlock fault latch
    tStepMaxS     : REAL;              // 超时秒值 / Timeout seconds [s]
    xFirstScan    : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0005_044E 信息 帧内正常运行
//   16#0005_044F 故障 tStepMax 非法 / 气缸接口未就绪
//   16#0005_0450 故障 uLayerCount=0 / uBoxPerLayer=0 / bEnable 期 iCylGrip.bError
//   16#0005_0451 信息 单相超时 → 停在当前相、bBusy=FALSE
//   16#0005_0452 故障 ePlace 相内 bGripClosed=FALSE（联锁）或跺中途 bReset → 锁存
// ---------------------------------------------------------------------

// ---- 超时秒值 / Timeout seconds ----
tStepMaxS := TIME_TO_REAL(tStepMax) / 1000.0;   // 秒值 / Seconds [s]

// ---- 启动沿检测（无条件刷新）/ Start edge, unconditional ----
rtrigStart(CLK := bStart);      // 沿检测 / Edge detection

// ---- 超时与接口合法性闸 / Timeout and interface validity gate ----
IF (tStepMax = T#0MS) OR (tStepMaxS < 1.0) OR (tStepMaxS > 300.0)
   OR (NOT __ISVALIDREF(iCylGrip)) OR (NOT __ISVALIDREF(iCylLift)) THEN
    eState := E_DL_PalletizerState.eFault;  // 故障态 / Fault
    bBusy := FALSE;             // 停止运行 / Not busy
    eErr := 16#0005_044F;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸（含气缸执行器错）/ Configuration and actuator fault gate ----
IF (uLayerCount = 0) OR (uBoxPerLayer = 0) OR (bEnable AND iCylGrip.bError) THEN
    eState := E_DL_PalletizerState.eFault;  // 故障态 / Fault
    bBusy := FALSE;             // 停止运行 / Not busy
    eErr := 16#0005_0450;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    eState := E_DL_PalletizerState.eIdle;   // 空闲 / Idle
    uLayerIdx := 0;             // 层号清零 / Layer cleared
    uBoxIdx := 0;               // 箱号清零 / Box cleared
    bDone := FALSE;             // 脉冲复位 / Pulse reset
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 完成脉冲单拍化 / Done pulse one-cycle ----
IF bDone THEN
    bDone := FALSE;             // 下一拍清 / Clear next cycle
END_IF

// ---- 使能撤销：气缸回安全位（夹爪保持、升降下落）/ Disable: cylinders to safe side ----
IF NOT bEnable THEN
    iCylGrip.Hold();            // 夹爪保持 / Gripper hold
    iCylLift.GotoLower();       // 升降下落 / Lift lower
    eState := E_DL_PalletizerState.eIdle;   // 空闲 / Idle
    uLayerIdx := 0;             // 层号清零 / Layer cleared
    uBoxIdx := 0;               // 箱号清零 / Box cleared
    bBusy := FALSE;             // 停止运行 / Not busy
    bLockoutLatch := FALSE;     // 锁存复位 / Latch reset
    eErr := 16#0005_044E;       // 信息级：空闲 / Info: idle
    bStepTimerOn := FALSE;      // 相定时关 / Timer off
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 故障锁存路径（联锁错/非法复位）/ Fault latch path ----
IF bLockoutLatch THEN
    eState := E_DL_PalletizerState.eFault;  // 故障态 / Fault
    bBusy := FALSE;             // 停止运行 / Not busy
    eErr := 16#0005_0452;       // 故障码回放 / Fault code replay
    IF bReset THEN
        bLockoutLatch := FALSE;     // 解除锁存 / Release latch
        // 未完成跺强制从进箱等待重起并清层号 / Restart from wait, clear indices
        eState := E_DL_PalletizerState.eWaitBox;    // 回进箱等待 / Back to wait
        uLayerIdx := 0;         // 清层号 / Clear layer
        uBoxIdx := 0;           // 清箱号 / Clear box
    END_IF
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 跺中途非法复位 → 锁存 / Illegal reset mid-pallet → latch ----
IF bReset AND bBusy THEN
    bLockoutLatch := TRUE;      // 锁存 / Latch
    eState := E_DL_PalletizerState.eFault;  // 故障态 / Fault
    bBusy := FALSE;             // 停止运行 / Not busy
    eErr := 16#0005_0452;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 空闲态受理启动沿 / Idle accepts start edge ----
IF (eState = E_DL_PalletizerState.eIdle) OR (eState = E_DL_PalletizerState.eWaitBox) THEN
    eErr := 16#0005_044E;       // 信息级：正常 / Info: normal
    IF rtrigStart.Q AND (eState = E_DL_PalletizerState.eIdle) THEN
        eState := E_DL_PalletizerState.eWaitBox;    // 进入进箱等待 / Go to wait
        uLayerIdx := 1;         // 层号从 1 起 / Layer starts at 1
        uBoxIdx := 1;           // 箱号从 1 起 / Box starts at 1
        bBusy := TRUE;          // 运行 / Busy
        bStepTimerOn := FALSE;  // 相定时未启 / Timer off
    END_IF
END_IF

// ---- 相超时定时器（每相进入时重置，R21 禁跨相复用）/ Step timer, reset per phase entry ----
tonStep(IN := bStepTimerOn, PT := tStepMax);    // 无条件刷新 / Unconditional refresh
IF bStepTimerOn AND tonStep.Q THEN
    bStepTimerOn := FALSE;      // 相定时关 / Timer off
    bBusy := FALSE;             // 停在当前相 / Stay in current phase
    eErr := 16#0005_0451;       // 信息级：单相超时 / Info: step timeout
    RETURN;                     // 不自动跳步 / No auto skip
END_IF

// ---- 状态机 / State machine ----
CASE eState OF

    E_DL_PalletizerState.eIdle: // 空闲态 / Idle
        bBusy := FALSE;         // 非运行 / Not busy
        bStepTimerOn := FALSE;  // 定时关 / Timer off

    E_DL_PalletizerState.eWaitBox:  // 进箱等待 / Wait for box
        bBusy := TRUE;          // 运行 / Busy
        bStepTimerOn := TRUE;   // 相定时启 / Timer on
        IF bBoxPresent THEN
            // 有箱：夹爪闭合准备抓取 / Box present: close gripper
            iCylGrip.GotoUpper();   // 夹爪闭合（接口语义：上位=夹紧）/ Gripper close
            bStepTimerOn := FALSE;  // 相定时重置 / Timer reset
            eState := E_DL_PalletizerState.ePlace;  // 进入码放相 / Go to place
            tonStep(IN := FALSE, PT := tStepMax);   // 相进入重置（R21）/ Reset on entry
        END_IF

    E_DL_PalletizerState.ePlace:    // 分层码放 / Placing
        bBusy := TRUE;          // 运行 / Busy
        bStepTimerOn := TRUE;   // 相定时启 / Timer on
        // 联锁：夹爪未闭合就允许下压 → 故障锁存 / Interlock: no grip while lowering
        IF NOT bGripClosed THEN
            bLockoutLatch := TRUE;  // 锁存 / Latch
            eErr := 16#0005_0452;   // 故障码 / Fault code
            RETURN;             // 本拍结束 / End of cycle
        END_IF
        iCylLift.GotoLower();   // 升降下压 / Lift lower
        IF bPlaceDone THEN
            iCylGrip.GotoLower();   // 夹爪松开（接口语义：下位=松开）/ Gripper open
            uBoxIdx := uBoxIdx + 1; // 箱号递增 / Box increment
            IF uBoxIdx > uBoxPerLayer THEN
                uBoxIdx := 1;   // 显式回绕到层首 / Wrap to layer first
                bStepTimerOn := FALSE;  // 相定时重置 / Timer reset
                eState := E_DL_PalletizerState.eLayerDone;  // 层完成相 / Layer done phase
                tonStep(IN := FALSE, PT := tStepMax);   // 相进入重置 / Reset on entry
            ELSE
                // 还有箱：回进箱等待取下一箱 / More boxes: back to wait
                bStepTimerOn := FALSE;  // 相定时重置 / Timer reset
                eState := E_DL_PalletizerState.eWaitBox;    // 回等待 / Back to wait
                tonStep(IN := FALSE, PT := tStepMax);   // 相进入重置 / Reset on entry
            END_IF
        END_IF

    E_DL_PalletizerState.eLayerDone:    // 层完成等待 / Layer done wait
        bBusy := TRUE;          // 运行 / Busy
        bStepTimerOn := TRUE;   // 相定时启 / Timer on
        IF bLayerDone THEN
            IF uLayerIdx >= uLayerCount THEN
                // 满跺：进入缠膜 / Full pallet: stretch phase
                bStepTimerOn := FALSE;  // 相定时重置 / Timer reset
                eState := E_DL_PalletizerState.eStretch;    // 缠膜相 / Stretch phase
                tonStep(IN := FALSE, PT := tStepMax);   // 相进入重置 / Reset on entry
            ELSE
                uLayerIdx := uLayerIdx + 1;     // 层号递增 / Layer increment
                uBoxIdx := 1;   // 箱号回层首 / Box to first
                bStepTimerOn := FALSE;  // 相定时重置 / Timer reset
                eState := E_DL_PalletizerState.eWaitBox;    // 回进箱等待 / Back to wait
                tonStep(IN := FALSE, PT := tStepMax);   // 相进入重置 / Reset on entry
            END_IF
        END_IF

    E_DL_PalletizerState.eStretch:  // 缠膜等待 / Stretch wait
        bBusy := TRUE;          // 运行 / Busy
        bStepTimerOn := TRUE;   // 相定时启 / Timer on
        IF bStretchDone THEN
            bStepTimerOn := FALSE;  // 相定时重置 / Timer reset
            eState := E_DL_PalletizerState.eDischarge;  // 出跺相 / Discharge phase
            tonStep(IN := FALSE, PT := tStepMax);   // 相进入重置 / Reset on entry
        END_IF

    E_DL_PalletizerState.eDischarge:    // 出跺等待 / Discharge wait
        bBusy := TRUE;          // 运行 / Busy
        bStepTimerOn := TRUE;   // 相定时启 / Timer on
        IF bOutReady THEN
            bStepTimerOn := FALSE;  // 相定时关 / Timer off
            bDone := TRUE;      // 一跺完成脉冲 / Done pulse
            eState := E_DL_PalletizerState.eDone;   // 完成态 / Done state
            tonStep(IN := FALSE, PT := tStepMax);   // 定时重置 / Reset
        END_IF

    E_DL_PalletizerState.eDone:     // 完成态（下一拍回等待）/ Done, back next cycle
        bBusy := FALSE;         // 非运行 / Not busy
        eState := E_DL_PalletizerState.eWaitBox;    // 回进箱等待 / Back to wait
        uLayerIdx := 0;         // 层号清零 / Layer cleared
        uBoxIdx := 0;           // 箱号清零 / Box cleared

    E_DL_PalletizerState.eFault:    // 故障态 / Fault
        bBusy := FALSE;         // 非运行 / Not busy
        bStepTimerOn := FALSE;  // 定时关 / Timer off

    ELSE                        // 非法状态拦截 / Illegal state interception
        eState := E_DL_PalletizerState.eFault;  // 落故障态 / Fall to fault
        bBusy := FALSE;         // 非运行 / Not busy
        eErr := 16#0005_044E;   // 信息级（状态机兜底非故障源）/ Info
END_CASE

// ---- 气缸执行器错实时登记 / Actuator error live registration ----
IF iCylGrip.bError OR iCylLift.bError THEN
    eErr := 16#0005_0450;       // 故障码 / Fault code
    eState := E_DL_PalletizerState.eFault;  // 故障态 / Fault
    bBusy := FALSE;             // 停止运行 / Not busy
END_IF

END_FUNCTION_BLOCK
