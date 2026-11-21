// =====================================================================
// FB_DL_PowderDosingLoss.st
// 粉料失重秤增量式配料（皮重→粗给/慢给→落差补偿→稳定结算→学习）
// Loss-in-weight powder dosing FB
// 码位: 16#0005_0458 ~ 16#0005_045C (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 18)
// =====================================================================
FUNCTION_BLOCK FB_DL_PowderDosingLoss
VAR_INPUT
    bEnable      : BOOL  := FALSE;    // 使能 / Enable
    bStart       : BOOL  := FALSE;    // 上升沿开始一批 / Start batch on edge
    bReset       : BOOL  := FALSE;    // 复位 / Reset
    fWeight_g    : REAL  := 0.0;      // 秤读数 0~500000 g / Scale weight [g]
    fTarget_g    : REAL  := 1000.0;   // 目标投料量 >0 g / Target dose [g]
    fTare_g      : REAL  := 0.0;      // 皮重 ≥0 g / Tare [g]
    fSlowBand_g  : REAL  := 100.0;    // 转慢速余量 >0 g / Slow-down band [g]
    fLead_g      : REAL  := 0.0;      // 落差学习初值 0~500 g / Lead compensation [g]
    fLeadMax_g   : REAL  := 300.0;    // 落差限幅 1~2000 g / Lead limit [g]
    fDevMax_g    : REAL  := 5.0;      // 允许偏差 >0 g / Allowed deviation [g]
    bSlowCmd     : BOOL  := FALSE;    // 慢速输出确认 / Slow feed ack
    tSettleTime  : TIME  := T#500MS;  // 停料稳定时 T#10MS~T#10S / Settle time [s]
    tBatchMax    : TIME  := T#2M;     // 单批超时 T#1S~T#30M / Batch timeout [s]
END_VAR
VAR_OUTPUT
    fNet_g       : REAL;              // 本批净投料 g / Net dosed [g]
    fErr_g       : REAL;              // 本批偏差 g / Deviation [g]
    bDone        : BOOL;              // 批完成（单拍）/ Batch done pulse
    bBusy        : BOOL;              // 配料中 / Busy
    fLeadLearn_g : REAL;              // 更新后落差学习值 g / Learned lead [g]
    eErr         : UDINT;             // 错误码 / Error code
END_VAR
VAR
    rtrigStart   : R_TRIG;            // 启动沿检测（无条件刷新）/ Start edge detector
    tonSettle    : TON;               // 停料稳定定时器（无条件刷新）/ Settle timer
    tonBatch     : TON;               // 单批超时定时器（无条件刷新）/ Batch timeout timer
    fTareSnap_g  : REAL;              // 批开始皮重快照 / Tare snapshot at batch start [g]
    fWeightPrev  : REAL;              // 上拍秤读数快照 / Previous weight snapshot [g]
    fNetNow_g    : REAL;              // 本拍净重 / Net weight this cycle [g]
    fNetStart_g  : REAL;              // 批开始净重基准 / Net baseline at batch start [g]
    fStopPt_g    : REAL;              // 提前停止点（目标-慢带-落差）/ Early stop point [g]
    bFastPhase   : BOOL;              // 高速给料相 / Fast feed phase
    bSettling    : BOOL;              // 停料稳定相 / Settling phase
    tSettleS     : REAL;              // 稳定时秒值 / Settle seconds [s]
    tBatchMaxS   : REAL;              // 批超时秒值 / Batch timeout seconds [s]
    bAbortLatch  : BOOL := FALSE;     // 中止锁存（方向反/超时）/ Abort latch
    xFirstScan   : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0005_0458 信息 批完成、偏差在容差内
//   16#0005_0459 故障 秤值非有限 / 皮重为负或超量程 / tSettleTime 非法
//   16#0005_045A 故障 fTarget_g ≤ 0 / fSlowBand_g ≥ fTarget_g / fLeadMax_g ≤ 0（组态错）
//   16#0005_045B 信息 批完成但偏差 > fDevMax_g → 结算照出、落差不学习
//   16#0005_045C 故障 进料期重量上升（方向反）或超 tBatchMax → 中止锁存（方向反优先）
// ---------------------------------------------------------------------

// ---- 时间转秒 / Times to seconds ----
tSettleS := TIME_TO_REAL(tSettleTime) / 1000.0;     // 稳定时秒 / Settle [s]
tBatchMaxS := TIME_TO_REAL(tBatchMax) / 1000.0;     // 批超时秒 / Batch max [s]

// ---- 启动沿检测（无条件刷新）/ Start edge, unconditional ----
rtrigStart(CLK := bStart);      // 沿检测 / Edge detection

// ---- 非有限与皮重闸（故障级）/ Finite and tare gate ----
IF (fWeight_g <> fWeight_g) OR (ABS(fWeight_g) >= 1.0E12)
   OR (fTare_g < 0.0) OR (fTare_g > 500000.0)
   OR (tSettleTime = T#0MS) OR (tSettleS < 0.01) OR (tSettleS > 10.0) THEN
    bBusy := FALSE;             // 停止 / Not busy
    bAbortLatch := TRUE;        // 中止锁存 / Abort latch
    eErr := 16#0005_0459;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fTarget_g <= 0.0) OR (fSlowBand_g >= fTarget_g) OR (fLeadMax_g <= 0.0)
   OR (fDevMax_g <= 0.0)
   OR (tBatchMax = T#0MS) OR (tBatchMaxS < 1.0) OR (tBatchMaxS > 1800.0) THEN
    eErr := 16#0005_045A;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    fLeadLearn_g := fLead_g;    // 学习值取初值 / Learn value from init
    fWeightPrev := fWeight_g;   // 快照对齐 / Snapshot align
    bDone := FALSE;             // 脉冲复位 / Pulse reset
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 完成脉冲单拍化 / Done pulse one-cycle ----
IF bDone THEN
    bDone := FALSE;             // 下一拍清 / Clear next cycle
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bBusy := FALSE;             // 停止 / Not busy
    bFastPhase := FALSE;        // 粗给退出 / Fast off
    bSettling := FALSE;         // 稳定退出 / Settle off
    eErr := 16#0005_0458;       // 信息级：空闲 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 复位：清中止锁存与学习值回初值 / Reset: clear latch, learn back to init ----
IF bReset THEN
    bAbortLatch := FALSE;       // 解锁存 / Release latch
    bBusy := FALSE;             // 停止 / Not busy
    bFastPhase := FALSE;        // 粗给退出 / Fast off
    bSettling := FALSE;         // 稳定退出 / Settle off
    fLeadLearn_g := fLead_g;    // 学习值回初值 / Learn to init
END_IF

// ---- 中止锁存路径 / Abort latch path ----
IF bAbortLatch THEN
    bBusy := FALSE;             // 停止（保留已投量）/ Stopped, dose kept
    eErr := 16#0005_045C;       // 故障码回放 / Fault code replay
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 每拍净重与方向监控 / Per-cycle net and direction monitor ----
fNetNow_g := fWeight_g - fTare_g;   // 净重 / Net [g]
IF fNetNow_g < 0.0 THEN
    fNetNow_g := 0.0;           // 负值钳 0 / Clamp to 0
    eErr := 16#0005_0459;       // 槽 2 登记 / Slot 2
END_IF

// ---- 启动沿受理（bBusy=FALSE 才受理）/ Accept start edge when idle ----
IF rtrigStart.Q AND (NOT bBusy) THEN
    fTareSnap_g := fTare_g;     // 皮重快照 / Tare snapshot
    fNetStart_g := fNetNow_g;   // 净重基准 / Net baseline
    fWeightPrev := fWeight_g;   // 快照对齐 / Snapshot align
    fStopPt_g := fTarget_g - fSlowBand_g - fLeadLearn_g;    // 提前停止点含落差 / Stop point with lead
    IF fStopPt_g < 0.0 THEN
        fStopPt_g := 0.0;       // 防负停止点 / Guard negative stop
    END_IF
    bBusy := TRUE;              // 配料中 / Busy
    bFastPhase := TRUE;         // 粗给开始 / Fast feed
    bSettling := FALSE;         // 非稳定相 / Not settling
END_IF

// ---- 批运行路径 / Batch active path ----
IF bBusy THEN
    // 单批超时监控 / Batch timeout monitor
    tonBatch(IN := bBusy, PT := tBatchMax);     // 无条件刷新 / Unconditional refresh

    // 方向监控：进料期重量上升 → 方向反（根因优先，先于超时判）/ Direction: rising weight fault first
    IF fWeight_g > (fWeightPrev + 1.0) THEN
        bAbortLatch := TRUE;    // 中止锁存 / Abort latch
        bBusy := FALSE;         // 停止 / Not busy
        bFastPhase := FALSE;    // 粗给退出 / Fast off
        bSettling := FALSE;     // 稳定退出 / Settle off
        eErr := 16#0005_045C;   // 故障码：方向反 / Fault code: reversed
        fWeightPrev := fWeight_g;   // 快照对齐 / Align snapshot
        RETURN;                 // 本拍结束 / End of cycle
    END_IF

    // 批超时（方向反已优先返回）/ Batch timeout after direction check
    IF tonBatch.Q THEN
        bAbortLatch := TRUE;    // 中止锁存 / Abort latch
        bBusy := FALSE;         // 停止（保留已投量）/ Stopped, dose kept
        bFastPhase := FALSE;    // 粗给退出 / Fast off
        bSettling := FALSE;     // 稳定退出 / Settle off
        eErr := 16#0005_045C;   // 故障码：超时 / Fault code: timeout
        RETURN;                 // 本拍结束 / End of cycle
    END_IF

    // ---- 给料相控制 / Feed phase control ----
    IF bFastPhase THEN
        // 高速粗给：净投量未达提前停止点 / Fast: below stop point
        IF (fNetNow_g - fNetStart_g) >= fStopPt_g THEN
            bFastPhase := FALSE;    // 转慢速精给 / To slow feed
        END_IF
        // 慢速转换确认（bSlowCmd 为外部确认，此处登记不强制）/ Slow ack registered externally
    END_IF

    // 停料判定：慢给相已达目标（含落差提前）/ Stop: reached target with lead
    IF (NOT bFastPhase) AND ((fNetNow_g - fNetStart_g) >= (fTarget_g - fLeadLearn_g)) THEN
        bSettling := TRUE;      // 停料稳定相 / Settling
        tonSettle(IN := TRUE, PT := tSettleTime);   // 稳定计时 / Settle timing
    END_IF

    // ---- 稳定后结算 / Settle then finalize ----
    IF bSettling THEN
        tonSettle(IN := TRUE, PT := tSettleTime);   // 无条件刷新 / Unconditional refresh
        IF tonSettle.Q THEN
            fNet_g := fNetNow_g - fNetStart_g;  // 结算净投量 / Finalize net
            fErr_g := fNet_g - fTarget_g;       // 偏差 / Deviation
            bDone := TRUE;      // 完成脉冲 / Done pulse
            bBusy := FALSE;     // 停止 / Not busy
            bSettling := FALSE; // 稳定退出 / Settle off
            IF ABS(fErr_g) <= fDevMax_g THEN
                // 落差学习：LIMIT(0, fLead + 0.5×fErr, fLeadMax)，0.5 阻尼防振荡
                // Lead learning: LIMIT with 0.5 damping factor
                fLeadLearn_g := fLeadLearn_g + 0.5 * fErr_g;    // 学习更新 / Learn update
                IF fLeadLearn_g < 0.0 THEN
                    fLeadLearn_g := 0.0;    // 下限 / Lower limit
                ELSIF fLeadLearn_g > fLeadMax_g THEN
                    fLeadLearn_g := fLeadMax_g;     // 上限 / Upper limit
                END_IF
                eErr := 16#0005_0458;   // 信息级：批完成 / Info: done
            ELSE
                eErr := 16#0005_045B;   // 信息级：超差结算不学习 / Info: no learning
            END_IF
        END_IF
    END_IF
ELSE
    tonBatch(IN := FALSE, PT := tBatchMax);     // 定时器复位 / Timer reset
    tonSettle(IN := FALSE, PT := tSettleTime);  // 定时器复位 / Timer reset
END_IF

// ---- 上拍快照更新 / Previous snapshot update ----
fWeightPrev := fWeight_g;       // 快照 / Snapshot

END_FUNCTION_BLOCK
