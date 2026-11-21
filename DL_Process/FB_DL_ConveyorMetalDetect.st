// =====================================================================
// FB_DL_ConveyorMetalDetect.st
// 金属检测机剔除联动与过检率统计（延时排队/冻结补偿/确认超时锁存）
// Metal detector reject linkage and statistics FB
// 码位: 16#0005_0462 ~ 16#0005_0466 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 20)
// =====================================================================
FUNCTION_BLOCK FB_DL_ConveyorMetalDetect
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    bReset         : BOOL  := FALSE;   // 复位（清统计）/ Reset
    bDetect        : BOOL  := FALSE;   // 检出脉冲（上升沿计数）/ Metal detected
    bRejectAck     : BOOL  := FALSE;   // 剔除完成确认 / Reject acknowledged
    fLineSpeed_mpm : REAL  := 0.0;     // 线速 0~200 m/min / Line speed [m/min]
    fSpeedMin_mpm  : REAL  := 1.0;     // 有效输送最小线速 >0 m/min / Min line speed [m/min]
    tRejectDelay   : TIME  := T#300MS; // 检测到剔除延时 T#10MS~T#5S / Reject delay [s]
    tRejectWidth   : TIME  := T#200MS; // 剔除脉冲宽度 T#20MS~T#2S / Reject pulse width [s]
    tAckMax        : TIME  := T#2S;    // 确认超时 T#100MS~T#30S / Ack timeout [s]
    uJamCnt        : USINT  := 3;      // 连续失败判卡滞次数 1~20 / Jam count
END_VAR
VAR_OUTPUT
    bRejectCmd     : BOOL;             // 剔除输出 / Reject command
    uDetectCnt     : UDINT;            // 累计检出数 / Detect count
    uRejectCnt     : UDINT;            // 累计已剔除数 / Rejected count
    fAckFailPct    : REAL;             // 确认失败率 0~100 % / Ack failure rate [%]
    bPending       : BOOL;             // 有剔除排队中 / Queue pending
    eErr           : UDINT;            // 错误码 / Error code
END_VAR
VAR
    rtrigDetect    : R_TRIG;           // 检出沿检测（无条件刷新）/ Detect edge detector
    tonDelay       : TON;              // 延时计时（皮带停时 IN 置 FALSE 冻结）/ Delay timer, frozen when belt stopped
    tonWidth       : TON;              // 脉宽计时 / Pulse width timer
    tonAck         : TON;              // 确认超时计时 / Ack timeout timer
    tDelayS        : REAL;             // 延时秒值 / Delay seconds [s]
    tWidthS        : REAL;             // 脉宽秒值 / Width seconds [s]
    tAckMaxS       : REAL;             // 超时秒值 / Timeout seconds [s]
    bDelaying      : BOOL;             // 延时排队中 / Delaying flag
    bRejecting     : BOOL;             // 剔除脉冲中 / Rejecting flag
    bAwaitingAck   : BOOL;             // 等确认中 / Awaiting ack flag
    bAckTimeoutLatch : BOOL := FALSE;  // 确认超时锁存 / Ack timeout latch
    uAckFailRun    : USINT;            // 连续确认失败计数 / Consecutive ack failure count
    bBeltMoving    : BOOL;             // 皮带运行判 / Belt moving flag
    uQueueDepth    : USINT;            // 排队深度（上限 8）/ Queue depth, cap 8
    xFirstScan     : BOOL  := TRUE;    // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0005_0462 信息 正常（无检出 / 剔除正常）
//   16#0005_0463 故障 线速非有限 / 任一 TIME 参数为 0 或非法
//   16#0005_0464 故障 fSpeedMin_mpm ≤ 0 / tRejectWidth ≥ tAckMax（组态错）
//   16#0005_0465 信息 排队冻结（fLineSpeed_mpm < fSpeedMin_mpm）→ 延时计时不走、bPending=TRUE
//   16#0005_0466 故障 单次确认超 tAckMax 或连续 uJamCnt 次失败 → 锁存；排队超 8 丢弃新检出同槽
// ---------------------------------------------------------------------

// ---- 时间转秒 / Times to seconds ----
tDelayS  := TIME_TO_REAL(tRejectDelay) / 1000.0;    // 延时秒 / Delay [s]
tWidthS  := TIME_TO_REAL(tRejectWidth) / 1000.0;    // 脉宽秒 / Width [s]
tAckMaxS := TIME_TO_REAL(tAckMax) / 1000.0;         // 超时秒 / Timeout [s]

// ---- 检出沿检测（无条件刷新）/ Detect edge, unconditional ----
rtrigDetect(CLK := bDetect);    // 沿检测 / Edge detection

// ---- 非有限与时间参数闸 / Finite and time validity gate ----
IF (fLineSpeed_mpm <> fLineSpeed_mpm) OR (ABS(fLineSpeed_mpm) >= 1.0E12)
   OR (fSpeedMin_mpm <> fSpeedMin_mpm) OR (ABS(fSpeedMin_mpm) >= 1.0E12)
   OR (tRejectDelay = T#0MS) OR (tDelayS < 0.01) OR (tDelayS > 5.0)
   OR (tRejectWidth = T#0MS) OR (tWidthS < 0.02) OR (tWidthS > 2.0)
   OR (tAckMax = T#0MS) OR (tAckMaxS < 0.1) OR (tAckMaxS > 30.0) THEN
    bRejectCmd := FALSE;        // 剔除撤销（安全侧）/ Reject off
    eErr := 16#0005_0463;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fSpeedMin_mpm <= 0.0) OR (tRejectWidth >= tAckMax) THEN
    bRejectCmd := FALSE;        // 剔除撤销 / Reject off
    eErr := 16#0005_0464;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    bRejectCmd := FALSE;        // 剔除初始关 / Reject init off
    bPending := FALSE;          // 排队复位 / Pending reset
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 复位：清统计与队列 / Reset: clear statistics and queue ----
IF bReset THEN
    uDetectCnt := 0;            // 检出清零 / Detect cleared
    uRejectCnt := 0;            // 剔除清零 / Reject cleared
    fAckFailPct := 0.0;         // 失败率清零 / Fail rate cleared
    uAckFailRun := 0;           // 连败计数清零 / Fail run cleared
    bAckTimeoutLatch := FALSE;  // 锁存解除 / Latch released
    bDelaying := FALSE;         // 排队清空 / Queue cleared
    bRejecting := FALSE;        // 脉冲复位 / Pulse reset
    bAwaitingAck := FALSE;      // 等待复位 / Awaiting reset
    uQueueDepth := 0;           // 深度清零 / Depth cleared
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bRejectCmd := FALSE;        // 剔除撤销 / Reject off
    bDelaying := FALSE;         // 排队清空 / Queue cleared
    bRejecting := FALSE;        // 脉冲复位 / Pulse reset
    bAwaitingAck := FALSE;      // 等待复位 / Awaiting reset
    bPending := FALSE;          // 排队复位 / Pending reset
    eErr := 16#0005_0462;       // 信息级：空闲 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 确认超时锁存路径（漏剔是质量事故，宁可停线）/ Ack timeout latch path ----
IF bAckTimeoutLatch THEN
    bRejectCmd := FALSE;        // 剔除撤销 / Reject off
    eErr := 16#0005_0466;       // 故障码回放 / Fault code replay
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 皮带运行判 / Belt moving check ----
bBeltMoving := (fLineSpeed_mpm >= fSpeedMin_mpm);   // 运行判 / Moving flag

// ---- 检出沿计数与排队（队列上限 8：超限丢弃并置槽 5，宁停线不漏剔）
// Detect edge: count and enqueue, cap 8, drop new on overflow (documented trade-off)
IF rtrigDetect.Q THEN
    uDetectCnt := uDetectCnt + 1;   // 检出计数 / Detect count
    IF uQueueDepth < 8 THEN
        uQueueDepth := uQueueDepth + 1;     // 入队 / Enqueue
        bDelaying := TRUE;          // 延时排队 / Delaying
    ELSE
        // 队列满：丢弃新检出并置故障（宁可停线不可静默漏剔）/ Queue full: drop and fault
        bAckTimeoutLatch := TRUE;   // 锁存停线 / Latch stop line
        eErr := 16#0005_0466;       // 故障码 / Fault code
        RETURN;                     // 本拍结束 / End of cycle
    END_IF
END_IF

bPending := (uQueueDepth > 0);      // 排队标志 / Pending flag

// ---- 延时相（皮带停时冻结计时，TON IN 置 FALSE）/ Delay phase, frozen when stopped ----
IF bDelaying THEN
    tonDelay(IN := bBeltMoving, PT := tRejectDelay);    // 停带即冻结 / Freeze on stop
    IF NOT bBeltMoving THEN
        eErr := 16#0005_0465;   // 信息级：排队冻结 / Info: frozen
        RETURN;                 // 冻结期间不推进 / Hold while frozen
    END_IF
    IF tonDelay.Q THEN
        bDelaying := FALSE;     // 延时完成 / Delay done
        bRejecting := TRUE;     // 进入剔除脉冲 / Rejecting
        uQueueDepth := uQueueDepth - 1;     // 出队（简化单件深度模型）/ Dequeue
        tonWidth(IN := FALSE, PT := tRejectWidth);  // 脉宽重置 / Width reset
    END_IF
END_IF

// ---- 剔除脉冲相 / Reject pulse phase ----
IF bRejecting THEN
    bRejectCmd := TRUE;         // 剔除输出 / Reject on
    tonWidth(IN := TRUE, PT := tRejectWidth);   // 无条件刷新 / Unconditional refresh
    IF tonWidth.Q THEN
        bRejecting := FALSE;    // 脉宽结束 / Pulse done
        bRejectCmd := FALSE;    // 剔除撤销 / Reject off
        bAwaitingAck := TRUE;   // 等确认 / Awaiting ack
        tonAck(IN := FALSE, PT := tAckMax);     // 超时重置 / Timeout reset
    END_IF
ELSIF bAwaitingAck THEN
    // ---- 确认等待相 / Ack wait phase ----
    tonAck(IN := TRUE, PT := tAckMax);      // 无条件刷新 / Unconditional refresh
    IF bRejectAck THEN
        // 确认成功 / Ack success
        uRejectCnt := uRejectCnt + 1;       // 剔除计数 / Reject count
        uAckFailRun := 0;                   // 连败清零 / Fail run cleared
        bAwaitingAck := FALSE;              // 等待结束 / Wait done
        eErr := 16#0005_0462;               // 信息级：剔除正常 / Info: normal
    ELSIF tonAck.Q THEN
        // 单次确认超时 → 锁存（漏剔停线）/ Single ack timeout: latch
        bAckTimeoutLatch := TRUE;           // 锁存 / Latch
        uAckFailRun := uAckFailRun + 1;     // 连败计数 / Fail count
        IF uAckFailRun >= uJamCnt THEN
            // 连续失败判剔除器卡滞（同槽 5）/ Consecutive failures: jam, same slot
        END_IF
        bAwaitingAck := FALSE;              // 等待结束 / Wait done
        eErr := 16#0005_0466;               // 故障码 / Fault code
        RETURN;                             // 本拍结束 / End of cycle
    END_IF
ELSE
    bRejectCmd := FALSE;        // 剔除关 / Reject off
END_IF

// ---- 确认失败率（分母下限闸：0 → 输出 0）/ Ack failure rate, denominator guard ----
IF uDetectCnt > 0 THEN
    fAckFailPct := UDINT_TO_REAL(uDetectCnt - uRejectCnt) / UDINT_TO_REAL(uDetectCnt) * 100.0;   // 失败率 / Fail rate [%]
    IF fAckFailPct < 0.0 THEN
        fAckFailPct := 0.0;     // 下限 / Lower clamp
    ELSIF fAckFailPct > 100.0 THEN
        fAckFailPct := 100.0;   // 上限 / Upper clamp
    END_IF
ELSE
    fAckFailPct := 0.0;         // 无检出输出 0 / Zero when no detects
END_IF

// ---- 正常码兜底 / Normal code fallback ----
IF eErr <> 16#0005_0465 THEN
    eErr := 16#0005_0462;       // 信息级：正常 / Info: normal
END_IF

END_FUNCTION_BLOCK
