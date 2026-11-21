// =====================================================================
// FB_DL_FoupDoorSeq.st
// FOUP 开合门与载具联锁顺控（解锁-开门-载具在位-再锁定确认窗）
// FOUP door interlock sequencing with relock confirm window
// 所属子库: DL_Device    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0003_03DE ~ 16#0003_03E2 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: semiconductor, door-interlock, sequencing, foup
// 枚举属主: E_DL_FoupDoorState —— 本文件为全库唯一属主, 其他件只引用不重声明
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 2)
// =====================================================================
// ---------------------------------------------------------------------
// 枚举定义: E_DL_FoupDoorState (全库唯一属主, 其他件只引用不重声明)
// ---------------------------------------------------------------------
TYPE E_DL_FoupDoorState :
(
    eIdle,          // 空闲（门锁闭等待）/ Idle, locked
    eUnlocking,     // 解锁保持中 / Unlocking
    eDoorOpen,      // 门已开等待传输 / Door open
    eTransfer,      // 载具传输中 / Transfer in progress
    eRelocking,     // 再锁定确认窗 / Relocking confirm window
    eFault          // 故障锁存 / Fault latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_FoupDoorSeq
VAR_INPUT
    bEnable         : BOOL  := FALSE;   // 使能 / Enable
    bDoorClosed     : BOOL  := FALSE;   // 门磁关到位反馈 / Door closed feedback
    bDoorOpen       : BOOL  := FALSE;   // 门磁开到位反馈 / Door open feedback
    bCarrierPresent : BOOL  := FALSE;   // 载具在位检测 / Carrier present detection
    bUnlockCmd      : BOOL  := FALSE;   // 解锁命令 / Unlock command
    bLockCmd        : BOOL  := FALSE;   // 锁定命令 / Lock command
    bVacuumOk       : BOOL  := FALSE;   // 真空解锁条件就绪 / Vacuum release ready
    tUnlockHold     : TIME  := T#3S;    // 解锁保持超时窗 T#100MS~T#60S / Unlock hold timeout window [s]
    tRelockWin      : TIME  := T#5S;    // 再锁定确认窗 T#100MS~T#60S / Relock confirm window [s]
    bReset          : BOOL  := FALSE;   // 故障复位命令 / Fault reset command
END_VAR
VAR_OUTPUT
    bUnlockOut      : BOOL := FALSE;    // 解锁输出, 安全侧为假 / Unlock output, safe side FALSE
    bLockOut        : BOOL := FALSE;    // 锁定输出 / Lock output
    eState          : E_DL_FoupDoorState := E_DL_FoupDoorState.eIdle;  // 顺控状态 / Sequence state
    bTransferPermit : BOOL := FALSE;    // 载具传输允许 / Transfer permit
    eErr            : UDINT := 16#0003_03DE;  // 错误码 / Error code
END_VAR
VAR
    eErrLatch       : UDINT := 16#0003_03DE;  // 故障锁存码回放 / Latched fault code replay
    bDoorConflict   : BOOL := FALSE;    // 门磁双反馈矛盾 / Door feedback conflict
    rtrReset        : R_TRIG;           // 复位上升沿检测, 每拍无条件刷新 / Reset edge, refreshed every cycle
    tonUnlock       : TON;              // 解锁保持超时定时器, 每拍无条件刷新 / Unlock hold timer, refreshed every cycle
    tonRelock       : TON;              // 再锁定确认窗定时器, 每拍无条件刷新 / Relock window timer, refreshed every cycle
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0003_03DE 信息 顺控正常（空闲或顺控执行中）
//   16#0003_03DF 故障 解锁保持超时（解锁输出有效而门未开超时）, 解除式 = bReset 上升沿 且 门磁回到关到位 且 无矛盾反馈
//   16#0003_03E0 故障 再锁定确认窗超时（窗内门磁未回关到位）, 解除式同 03DF
//   16#0003_03E1 故障 门磁双反馈矛盾（关到位与开到位同时有效）, 解除式同 03DF
//   16#0003_03E2 故障 非法状态兜底（状态机 ELSE 拦截）, 解除式同 03DF
// ---------------------------------------------------------------------

// ---- 门磁矛盾判（最高优先级拦截）/ Door feedback conflict: highest priority ----
bDoorConflict := bDoorClosed AND bDoorOpen;     // 双反馈同有效 = 组态或接线矛盾 / Both active = conflict
IF bDoorConflict THEN
    eState    := E_DL_FoupDoorState.eFault;     // 任意相直接落故障 / Fall to fault from any phase
    eErrLatch := 16#0003_03E1;                  // 锁存矛盾码 / Latch conflict code
END_IF

// ---- 非故障相下使能撤销 → 回空闲（安全侧）/ Disable in non-fault phase returns to idle ----
IF (NOT bEnable) AND (eState <> E_DL_FoupDoorState.eFault) THEN
    eState := E_DL_FoupDoorState.eIdle;         // 退回空闲 / Return to idle
END_IF

// ---- 定时器与边沿实例无条件周期刷新（调用本身不进任何 IF 分支）/ Unconditional timer and edge refresh ----
tonUnlock(IN := (eState = E_DL_FoupDoorState.eUnlocking) AND (NOT bDoorOpen),
          PT := tUnlockHold);                   // 解锁保持计时 / Unlock hold timing
tonRelock(IN := (eState = E_DL_FoupDoorState.eRelocking) AND (NOT bDoorClosed),
          PT := tRelockWin);                    // 再锁定确认窗计时 / Relock window timing
rtrReset(CLK := bReset);                        // 复位沿检测 / Reset edge detection

// ---- 默认输出（安全侧全 0, 各相按需覆盖）/ Default outputs (safe side) ----
bUnlockOut      := FALSE;   // 解锁输出缺省断开 / Unlock default off
bLockOut        := FALSE;   // 锁定输出缺省断开 / Lock default off
bTransferPermit := FALSE;   // 传输允许缺省禁止 / Permit default denied

// ---- 状态机 / State machine ----
IF eState = E_DL_FoupDoorState.eFault THEN
    // 故障相: 输出全 0, 锁存码回放 / Fault phase: outputs all off, latch replay
    eErr := eErrLatch;
    // 解除式: bReset 上升沿 且 门磁回到关到位 且 无矛盾反馈 / Release: reset edge AND closed AND no conflict
    IF rtrReset.Q AND bDoorClosed AND (NOT bDoorOpen) AND (NOT bDoorConflict) THEN
        eState    := E_DL_FoupDoorState.eIdle;  // 解除故障回空闲 / Release to idle
        eErrLatch := 16#0003_03DE;              // 清锁存码 / Clear latch code
    END_IF
ELSE
    CASE eState OF
        E_DL_FoupDoorState.eIdle:       // 空闲: 门锁闭等待解锁命令 / Idle: locked, wait unlock
            bLockOut := bDoorClosed;    // 锁定输出随关到位反馈 / Lock output follows closed feedback
            IF bUnlockCmd AND bVacuumOk AND (NOT bDoorConflict) THEN
                eState := E_DL_FoupDoorState.eUnlocking;    // 拍 N 进入解锁相 / Enter unlocking
            END_IF
        E_DL_FoupDoorState.eUnlocking:  // 解锁保持: 输出有效等待门开 / Unlocking: output on, wait door open
            bUnlockOut := TRUE;         // 解锁输出有效 / Unlock output on
            // 本拍行为: 门开转开门相, 真空条件丢失回空闲, 超时落故障 / Open to door phase, vacuum loss to idle, timeout to fault
            IF bDoorOpen AND (NOT bDoorConflict) THEN
                eState := E_DL_FoupDoorState.eDoorOpen;     // 拍 N+1 转开门相 / To door-open phase
            ELSIF NOT bVacuumOk THEN
                eState := E_DL_FoupDoorState.eIdle;         // 真空条件丢失中止解锁 / Vacuum lost, abort unlock
            ELSIF tonUnlock.Q THEN
                eState    := E_DL_FoupDoorState.eFault;     // 解锁有效但门未开超时 / Unlock valid but not open in time
                eErrLatch := 16#0003_03DF;                  // 锁存超时码 / Latch timeout code
            END_IF
        E_DL_FoupDoorState.eDoorOpen:   // 门已开: 允许传输, 等载具在位或锁定命令 / Door open: permit, wait carrier or lock cmd
            bUnlockOut      := TRUE;    // 开门期间保持解锁 / Hold unlock while open
            bTransferPermit := TRUE;    // 允许载具传输 / Permit transfer
            IF bCarrierPresent THEN
                eState := E_DL_FoupDoorState.eTransfer;     // 载具在位转传输相 / Carrier present, to transfer
            ELSIF bLockCmd AND (NOT bDoorConflict) THEN
                eState := E_DL_FoupDoorState.eRelocking;    // 直接收到锁定命令转确认窗 / Lock cmd, to relocking
            END_IF
        E_DL_FoupDoorState.eTransfer:   // 载具传输中: 保持允许, 等锁定命令 / Transfer: permit held, wait lock cmd
            bUnlockOut      := TRUE;    // 传输期间保持解锁 / Hold unlock during transfer
            bTransferPermit := TRUE;    // 保持传输允许 / Hold transfer permit
            IF bLockCmd AND (NOT bDoorConflict) THEN
                eState := E_DL_FoupDoorState.eRelocking;    // 收到锁定命令转确认窗 / Lock cmd, to relocking
            END_IF
        E_DL_FoupDoorState.eRelocking:  // 再锁定确认窗: 门磁必须回关到位 / Relocking: door must return closed
            bLockOut := TRUE;           // 锁定输出有效 / Lock output on
            // 本拍行为: 门关到位转空闲, 窗超时落故障 / Closed to idle, window timeout to fault
            IF bDoorClosed AND (NOT bDoorConflict) THEN
                eState := E_DL_FoupDoorState.eIdle;     // 再锁定完成回空闲 / Relock done, to idle
            ELSIF tonRelock.Q THEN
                eState    := E_DL_FoupDoorState.eFault; // 确认窗内门磁未回关到位 / Door not closed in window
                eErrLatch := 16#0003_03E0;              // 锁存确认窗超时码 / Latch window timeout code
            END_IF
        ELSE                                    // 非法状态兜底拦截 / Illegal state fallback
            eState    := E_DL_FoupDoorState.eFault;     // 落故障相 / Fall to fault
            eErrLatch := 16#0003_03E2;                  // 锁存兜底码 / Latch fallback code
        END_CASE
    // 本拍错误码: 刚落故障则回放锁存码, 否则正常码 / Error code of this cycle
    IF eState = E_DL_FoupDoorState.eFault THEN
        eErr := eErrLatch;          // 回放锁存码 / Replay latch code
    ELSE
        eErr := 16#0003_03DE;       // 顺控正常 / Sequence normal
    END_IF
END_IF

END_FUNCTION_BLOCK
