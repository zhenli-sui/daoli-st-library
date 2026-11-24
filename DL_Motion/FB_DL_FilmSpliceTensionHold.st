// =====================================================================
// FB_DL_FilmSpliceTensionHold.st
// 接膜瞬间张力双回路无扰交接（给定斜坡 + 权重交叉淡入淡出）
// Film splice tension handover FB
// 码位: 16#0004_0345 ~ 16#0004_0349 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 13)
// =====================================================================
FUNCTION_BLOCK FB_DL_FilmSpliceTensionHold
VAR_INPUT
    bEnable       : BOOL  := FALSE;    // 使能 / Enable
    bSpliceStart  : BOOL  := FALSE;    // 上升沿启动交接 / Splice start on edge
    bReset        : BOOL  := FALSE;    // 复位 / Reset
    fTensionA_N   : REAL  := 0.0;      // A 卷实测张力 0~2000 N / A tension [N]
    fTensionANow_N: REAL  := 0.0;      // A 卷当前指令值 0~2000 N / A command [N]
    fTensionBSp_N : REAL  := 200.0;    // B 卷目标张力 0~2000 N / B setpoint [N]
    bBMeasValid   : BOOL  := FALSE;    // B 卷张力实测有效 / B measurement valid
    fRamp_Ns      : REAL  := 200.0;    // 给定斜坡速率 1~5000 N/s / Ramp rate [N/s]
    fDevMax_N     : REAL  := 40.0;     // 交接允许偏差 1~500 N / Max deviation [N]
    tHoldMax      : TIME  := T#3S;     // 交接最长时间 T#100MS~T#30S / Max handover time [s]
    tCycle        : TIME  := T#10MS;   // 周期 T#1MS~T#200MS / Cycle [s]
END_VAR
VAR_OUTPUT
    fTensionCmd_N : REAL;              // 交接后张力给定 0~2000 N / Tension command [N]
    fBlendPct     : REAL;              // B 回路权重 0~100 % / Blend weight [%]
    bHoldActive   : BOOL;              // 交接进行中 / Handover active
    bHandoverDone : BOOL;              // 交接完成（单拍脉冲）/ Handover done pulse
    bCutPermit    : BOOL;              // 允许裁切 / Cut permit
    eErr          : UDINT;             // 错误码 / Error code
END_VAR
VAR
    rtrigStart    : R_TRIG;            // 启动沿检测（无条件刷新）/ Start edge detector
    fStepN        : REAL;              // 单拍给定增量 / Step per cycle [N]
    tHoldMaxS     : REAL;              // 上限秒值 / Hold max seconds [s]
    tCycleS       : REAL;              // 周期秒值 / Cycle seconds [s]
    bHoldLatch    : BOOL := FALSE;     // 交接超时中止锁存 / Handover abort latch
    bDevFrozen    : BOOL := FALSE;     // 偏差超限冻结标志 / Deviation freeze flag
    fStartCmd     : REAL;              // 交接起始给定快照 / Handover start command snapshot [N]
    tonHold       : TON;               // 交接超时定时器（无条件刷新）/ Handover timeout timer
    xFirstScan    : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0004_0345 信息 交接完成 / 未启动
//   16#0004_0346 故障 张力非有限 / tCycle 非法
//   16#0004_0347 故障 fRamp_Ns ≤ 0 / fTensionBSp_N ≤ 0 / tHoldMax 非法（组态错）
//   16#0004_0348 信息 交接中偏差超 fDevMax_N → 冻结斜坡与权重，bHoldActive 保持
//   16#0004_0349 故障 交接超 tHoldMax 未达 100 % → 中止、bCutPermit=FALSE 锁存
// ---------------------------------------------------------------------

// ---- 时间转秒 / Times to seconds ----
tHoldMaxS := TIME_TO_REAL(tHoldMax) / 1000.0;   // 上限秒值 / Hold max [s]
tCycleS   := TIME_TO_REAL(tCycle) / 1000.0;     // 周期秒值 / Cycle [s]

// ---- 启动沿检测（无条件周期刷新）/ Start edge, unconditional refresh ----
rtrigStart(CLK := bSpliceStart);    // 沿检测 / Edge detection

// ---- 非有限与周期合法性闸 / Finite and cycle validity gate ----
IF (tCycle = T#0MS) OR (tCycleS < 0.001) OR (tCycleS > 0.2)
   OR (fTensionA_N <> fTensionA_N) OR (ABS(fTensionA_N) >= 1.0E12)
   OR (fTensionANow_N <> fTensionANow_N) OR (ABS(fTensionANow_N) >= 1.0E12)
   OR (fTensionBSp_N <> fTensionBSp_N) OR (ABS(fTensionBSp_N) >= 1.0E12)
   OR (fRamp_Ns <> fRamp_Ns) OR (ABS(fRamp_Ns) >= 1.0E12)
   OR (fDevMax_N <> fDevMax_N) OR (ABS(fDevMax_N) >= 1.0E12) THEN
    bHoldActive := FALSE;       // 交接退出 / Handover off
    bHoldLatch  := FALSE;       // 锁存复位（本闸自动恢复）/ Latch reset
    eErr := 16#0004_0346;       // 故障码 / Fault code
    RETURN;                     // 给定保持不动 / Command holds
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fRamp_Ns <= 0.0) OR (fTensionBSp_N <= 0.0)
   OR (tHoldMax = T#0MS) OR (tHoldMaxS < 0.1) OR (tHoldMaxS > 30.0) THEN
    bHoldActive := FALSE;       // 交接退出 / Handover off
    eErr := 16#0004_0347;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 纪律：首扫 bCutPermit=FALSE）/ First-scan init ----
IF xFirstScan THEN
    fTensionCmd_N := fTensionANow_N;    // 给定对齐 A 当前指令 / Command aligns to A
    fBlendPct := 0.0;           // B 权重 0 / Blend 0
    bCutPermit := FALSE;        // 裁切禁止 / Cut denied
    bHandoverDone := FALSE;     // 脉冲复位 / Pulse reset
    bHoldActive := FALSE;       // 非交接 / Inactive
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 完成脉冲单拍化（上拍 TRUE 本拍清）/ Done pulse: one cycle only ----
IF bHandoverDone THEN
    bHandoverDone := FALSE;     // 下一拍清 / Clear next cycle
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bHoldActive := FALSE;       // 交接退出 / Handover off
    bHoldLatch := FALSE;        // 锁存复位 / Latch reset
    bDevFrozen := FALSE;        // 冻结复位 / Freeze reset
    bCutPermit := FALSE;        // 裁切禁止 / Cut denied
    fBlendPct := 0.0;           // 权重回 0 / Blend 0
    eErr := 16#0004_0345;       // 信息级：未启动 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 超时中止锁存与解除 / Abort latch and release ----
IF bHoldLatch THEN
    bHoldActive := FALSE;       // 交接退出 / Handover off
    bCutPermit  := FALSE;       // 绝不裁切 / Never cut
    eErr := 16#0004_0349;       // 故障码回放（给定停在中间值不回退）/ Replay, command holds
    IF bReset THEN
        bHoldLatch := FALSE;    // 解除锁存 / Release latch
        fBlendPct := 0.0;       // 权重回 0 / Blend reset
        fTensionCmd_N := fTensionANow_N;    // 给定对齐 A / Realign to A
    END_IF
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- B 实测无效：拒绝启动（给定不变）/ B invalid: refuse to start ----
IF NOT bBMeasValid THEN
    bHoldActive := FALSE;       // 不启动交接 / Not started
    bCutPermit  := FALSE;       // 裁切禁止 / Cut denied
    eErr := 16#0004_0345;       // 信息级：未启动 / Info: idle
    RETURN;                     // 给定保持不动 / Command holds
END_IF

// ---- 启动沿受理（B 有效才受理）/ Accept start edge with valid B ----
IF rtrigStart.Q AND (fBlendPct < 100.0) AND (NOT bDevFrozen) THEN
    fStartCmd := fTensionCmd_N; // 快照起始给定 / Snapshot start command
    bHoldActive := TRUE;        // 交接进行 / Active
    bDevFrozen := FALSE;        // 冻结复位 / Freeze reset
END_IF

// ---- 单拍给定增量 / Step per cycle ----
fStepN := fRamp_Ns * tCycleS;   // N/s × s = N / Step [N]

// ---- 交接进行路径 / Handover active path ----
IF bHoldActive THEN
    // 交接中张力偏差超限 → 立即冻结斜坡与权重（保张力优先）/ Deviation over limit: freeze
    IF ABS(fTensionA_N - fTensionCmd_N) > fDevMax_N THEN
        bDevFrozen := TRUE;     // 冻结标志 / Freeze flag
        eErr := 16#0004_0348;   // 信息级：冻结 / Info: frozen
    ELSE
        bDevFrozen := FALSE;    // 偏差恢复 → 解除冻结 / Unfreeze
    END_IF

    IF NOT bDevFrozen THEN
        // 分母防护：B 目标与起点重合则直接完成 / Denominator guard: equal targets → done
        IF ABS(fTensionBSp_N - fStartCmd) < 0.001 THEN
            fBlendPct := 100.0;     // 权重直接满 / Blend full
        ELSE
            fBlendPct := fBlendPct + (fStepN / ABS(fTensionBSp_N - fStartCmd)) * 100.0;   // 权重按斜坡推进 / Blend advance
        END_IF
        // 单调递增且钳 [0,100] / Monotonic, clamp
        IF fBlendPct > 100.0 THEN
            fBlendPct := 100.0; // 上限 / Upper clamp
        ELSIF fBlendPct < 0.0 THEN
            fBlendPct := 0.0;   // 下限保护 / Lower guard
        END_IF
        // 给定从 A 起点向 B 目标斜坡过渡 / Command ramps from A start to B target
        fTensionCmd_N := fStartCmd + (fTensionBSp_N - fStartCmd) * fBlendPct / 100.0;   // 插值 / Interpolated
    END_IF

    // ---- 交接完成判 / Completion check ----
    IF fBlendPct >= 100.0 THEN
        fTensionCmd_N := fTensionBSp_N;     // 给定收口到 B 目标 / Command to B target
        fBlendPct := 100.0;     // 权重收口 / Blend full
        bHoldActive := FALSE;   // 交接结束 / Handover off
        bHandoverDone := TRUE;  // 完成脉冲（单拍）/ Done pulse
        eErr := 16#0004_0345;   // 信息级：交接完成 / Info: done
    ELSE
        // ---- 超时监控 / Timeout monitor ----
        tonHold(IN := TRUE, PT := tHoldMax);    // 定时器无条件刷新 / Unconditional refresh
        IF tonHold.Q THEN
            bHoldActive := FALSE;   // 中止交接 / Abort handover
            bHoldLatch := TRUE;     // 锁存 / Latch
            bCutPermit := FALSE;    // 绝不裁切 / Never cut
            eErr := 16#0004_0349;   // 故障码 / Fault code
            RETURN;                 // 本拍结束 / End of cycle
        END_IF
    END_IF
ELSE
    // 非交接期：给定保持，正常码 / Inactive: command holds
    IF eErr <> 16#0004_0348 THEN
        eErr := 16#0004_0345;   // 信息级：未启动 / Info: idle
    END_IF
    tonHold(IN := FALSE, PT := tHoldMax);   // 定时器复位 / Timer reset
END_IF

// ---- 裁切许可：仅权重满且无故障才 TRUE / Cut permit: full blend and no fault ----
bCutPermit := (fBlendPct >= 100.0)
              AND (eErr <> 16#0004_0349)
              AND (eErr <> 16#0004_0347)
              AND (eErr <> 16#0004_0346);   // 许可判 / Permit verdict

END_FUNCTION_BLOCK
