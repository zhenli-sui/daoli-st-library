// =====================================================================
// FB_DL_CoolantLoopBal.st
// 机台冷却水 4 支路流量均衡（增量总和强制归零，保总流量守恒）
// Coolant 4-branch flow balance FB
// 码位: 16#0003_03C0 ~ 16#0003_03C4 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 7)
// =====================================================================
FUNCTION_BLOCK FB_DL_CoolantLoopBal
VAR_INPUT
    bEnable       : BOOL  := FALSE;    // 使能 / Enable
    abFlowValid   : ARRAY[1..4] OF BOOL;   // 支路流量有效 / Branch flow valid
    afFlow_lpm    : ARRAY[1..4] OF REAL;   // 支路流量 0~500 L/min / Branch flow [L/min]
    fFlowMin_lpm  : REAL  := 5.0;      // 均衡投入最低总流量 >0 L/min / Min total flow [L/min]
    fGain         : REAL  := 0.5;      // 均衡增益 0.05~2.0 / Balance gain [-]
    fTrimMax_pct  : REAL  := 5.0;      // 单拍最大阀位增量 0.1~20 % / Max step [%]
    fDevMax_pct   : REAL  := 20.0;     // 失衡报警阈值 1~100 % / Imbalance alarm [%]
    tWin          : TIME  := T#2S;     // 均值窗口 T#200MS~T#30S / Averaging window [s]
END_VAR
VAR_OUTPUT
    afValve_pct   : ARRAY[1..4] OF REAL;    // 支路阀位 0~100 %（本件独占写）/ Branch valve [%]
    fFlowAvg_lpm  : REAL;               // 窗口平均总流量 L/min / Average total flow [L/min]
    fImb_pct      : REAL;               // 最大支路偏差 % / Max imbalance [%]
    bBalanced     : BOOL;               // 失衡 ≤ 5 % / Balanced
    bFrozen       : BOOL;               // 冻结中 / Frozen
    eErr          : UDINT;              // 错误码 / Error code
END_VAR
VAR
    aDelta        : ARRAY[1..4] OF REAL;    // 各路增量暂存 / Per-branch delta [%]
    fDeltaSum     : REAL;               // 增量代数和 / Delta sum [%]
    fDeltaMean    : REAL;               // 增量均值 / Delta mean [%]
    uValidCnt     : UDINT;              // 有效支路数 / Valid branch count
    uIdx          : UDINT;              // 循环下标 / Loop index
    uZi           : INT;                // 1..4 数组下标 / Array subscript 1..4
    fTotal        : REAL;               // 有效支路总流量 / Total valid flow [L/min]
    fAvgBranch    : REAL;               // 有效支路平均流量 / Average branch flow [L/min]
    fImbMax       : REAL;               // 最大偏差 / Max imbalance [%]
    fDevRel       : REAL;               // 支路相对偏差 / Relative deviation [-]
    tWinS         : REAL;               // 窗口秒值 / Window in seconds [s]
    fBase         : REAL;               // 均值窗口基准（首拍锁定）/ Window baseline, locked on first cycle [L/min]
    xHasBase      : BOOL  := FALSE;     // 基准已锁定标记 / Baseline locked flag
    xFirstScan    : BOOL  := TRUE;      // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0003_03C0 信息 均衡运行正常
//   16#0003_03C1 故障 流量值非有限 / tWin 非法
//   16#0003_03C2 故障 fGain ≤ 0 / fTrimMax_pct ≤ 0 / fFlowMin_lpm ≤ 0（组态错）
//   16#0003_03C3 信息 单支路阀位触 0/100 % 或流量计无效 → 该路冻结；有效支路 < 2 → 不均衡
//   16#0003_03C4 信息 总流量 < fFlowMin_lpm → 全冻结（bFrozen=TRUE），fImb_pct 照算供上位看
// ---------------------------------------------------------------------

// ---- 窗口转秒 / Window to seconds ----
tWinS := TIME_TO_REAL(tWin) / 1000.0;       // 秒值 / Seconds [s]

// ---- 非有限与窗口合法性闸 / Finite and window validity gate ----
IF (tWin = T#0MS) OR (tWinS < 0.2) OR (tWinS > 30.0)
   OR (fGain <> fGain) OR (ABS(fGain) >= 1.0E12)
   OR (fFlowMin_lpm <> fFlowMin_lpm) OR (ABS(fFlowMin_lpm) >= 1.0E12)
   OR (fTrimMax_pct <> fTrimMax_pct) OR (ABS(fTrimMax_pct) >= 1.0E12) THEN
    bFrozen := TRUE;            // 安全冻结 / Safe freeze
    eErr    := 16#0003_03C1;    // 故障码 / Fault code
    RETURN;                     // 阀位保持不动 / Valves hold
END_IF

// ---- 逐支路流量非有限判界（多 ARRAY 各自判）/ Per-branch finite check ----
FOR uZi := 1 TO 4 DO
    IF (afFlow_lpm[uZi] <> afFlow_lpm[uZi]) OR (ABS(afFlow_lpm[uZi]) >= 1.0E12) THEN
        bFrozen := TRUE;        // 安全冻结 / Safe freeze
        eErr    := 16#0003_03C1;    // 故障码 / Fault code
        RETURN;                 // 阀位保持不动 / Valves hold
    END_IF
END_FOR

// ---- 组态错闸 / Configuration fault gate ----
IF (fGain <= 0.0) OR (fTrimMax_pct <= 0.0) OR (fFlowMin_lpm <= 0.0) THEN
    bFrozen := TRUE;            // 安全冻结 / Safe freeze
    eErr    := 16#0003_03C2;    // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化：阀位从外部给定基准起（R16 首扫纪律）/ First-scan init ----
IF xFirstScan THEN
    FOR uZi := 1 TO 4 DO
        afValve_pct[uZi] := 50.0;   // 阀位初值 50 % / Valve init 50 %
        aDelta[uZi] := 0.0;     // 增量清零 / Delta cleared
    END_FOR
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销：全冻结（阀位保持）/ Disable: hold valves ----
IF NOT bEnable THEN
    bFrozen   := FALSE;         // 非欠流冻结 / Not underflow freeze
    bBalanced := FALSE;         // 结论失效 / Verdict invalid
    eErr      := 16#0003_03C0;  // 信息级：空闲 / Info: idle
    RETURN;                     // 阀位保持不动 / Valves hold
END_IF

// ---- 有效支路统计 / Valid branch counting ----
uValidCnt := 0;                 // 计数清零 / Reset count
fTotal := 0.0;                  // 总量清零 / Reset total
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] THEN
        uValidCnt := uValidCnt + 1;     // 有效计数 / Count valid
        fTotal := fTotal + afFlow_lpm[uZi]; // 累加流量 / Accumulate flow
    END_IF
END_FOR

// ---- 均值分母钳 ≥1 / Denominator clamp ≥1 ----
IF uValidCnt >= 1 THEN
    fAvgBranch := fTotal / UDINT_TO_REAL(uValidCnt);    // 平均支路流量 / Average branch flow
ELSE
    fAvgBranch := 0.0;          // 无有效路 / No valid branch
END_IF
fFlowAvg_lpm := fAvgBranch * UDINT_TO_REAL(uValidCnt);  // 窗口平均总流量（有效口径）/ Average total flow

// ---- 有效支路数 < 2 → 不均衡并置槽 4（单支路无相对量）/ Fewer than 2 valid branches ----
IF uValidCnt < 2 THEN
    bFrozen := TRUE;            // 冻结 / Freeze
    bBalanced := FALSE;         // 结论失效 / Verdict invalid
    fImb_pct := 0.0;            // 偏差无意义置 0 / Imbalance meaningless
    eErr := 16#0003_03C3;       // 信息级：路数不足 / Info: insufficient branches
    RETURN;                     // 阀位保持不动 / Valves hold
END_IF

// ---- 失衡统计（照算供上位看）/ Imbalance statistics (always computed) ----
fImbMax := 0.0;                 // 最大偏差复位 / Reset max
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] THEN
        IF fAvgBranch > 0.0 THEN
            fDevRel := ABS(afFlow_lpm[uZi] - fAvgBranch) / fAvgBranch * 100.0;  // 相对偏差 % / Relative deviation [%]
        ELSE
            fDevRel := 0.0;     // 分母保护 / Denominator guard
        END_IF
        IF fDevRel > fImbMax THEN
            fImbMax := fDevRel; // 取最大 / Keep max
        END_IF
    END_IF
END_FOR
fImb_pct := fImbMax;            // 输出最大偏差 / Output max imbalance
bBalanced := (fImbMax <= 5.0);  // 失衡 ≤ 5 % 判 / Balanced verdict

// ---- 总流量欠流 → 全冻结（阀位不变，偏差照算）/ Underflow: freeze all ----
IF fTotal < fFlowMin_lpm THEN
    bFrozen := TRUE;            // 冻结标志 / Frozen flag
    eErr := 16#0003_03C4;       // 信息级：欠流冻结 / Info: underflow freeze
    RETURN;                     // 阀位保持不动 / Valves hold
END_IF
bFrozen := FALSE;               // 正常非冻结 / Not frozen

// ---- 增量计算：先算各路增量再减均值（总和强制归零）/ Deltas then subtract mean ----
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] AND (fAvgBranch > 0.0) THEN
        // 相对偏差 → 阀位增量方向：流量低于均值 → 开阀 / Low flow → open valve
        aDelta[uZi] := fGain * ((fAvgBranch - afFlow_lpm[uZi]) / fAvgBranch) * fTrimMax_pct;    // 原始增量 / Raw delta [%]
    ELSE
        aDelta[uZi] := 0.0;     // 无效路不参与 / Invalid branch excluded
    END_IF
END_FOR
fDeltaSum := 0.0;               // 和清零 / Reset sum
FOR uZi := 1 TO 4 DO
    fDeltaSum := fDeltaSum + aDelta[uZi];   // 代数和 / Algebraic sum
END_FOR
fDeltaMean := fDeltaSum / UDINT_TO_REAL(uValidCnt);     // 增量均值（分母=有效路数）/ Delta mean

// ---- 阀位更新：单拍限幅 + 触限冻结 + 归零修正 / Valve update: slew limit + limit freeze + zero-sum ----
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] THEN
        // 单拍最大增量限幅 / Per-cycle max step clamp
        IF aDelta[uZi] > fTrimMax_pct THEN
            aDelta[uZi] := fTrimMax_pct;    // 正向限幅 / Positive clamp
        ELSIF aDelta[uZi] < -fTrimMax_pct THEN
            aDelta[uZi] := -fTrimMax_pct;   // 负向限幅 / Negative clamp
        END_IF
        // 触限后停止同向修正 / Limit reached: stop same-direction trim
        IF (afValve_pct[uZi] >= 100.0) AND (aDelta[uZi] > 0.0) THEN
            aDelta[uZi] := 0.0;     // 上限同向冻结 / Upper freeze
        ELSIF (afValve_pct[uZi] <= 0.0) AND (aDelta[uZi] < 0.0) THEN
            aDelta[uZi] := 0.0;     // 下限同向冻结 / Lower freeze
        END_IF
    ELSE
        aDelta[uZi] := 0.0;         // 冻结支路增量为 0（不被拉走流量）/ Frozen branch zero delta
    END_IF
END_FOR

// ---- 归零修正重算均值（冻结路不参与均值）/ Re-zero with frozen branches excluded ----
fDeltaSum := 0.0;               // 和清零 / Reset sum
uValidCnt := 0;                 // 计数复位 / Reset count
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] THEN
        fDeltaSum := fDeltaSum + aDelta[uZi];   // 有效路代数和 / Valid sum
        uValidCnt := uValidCnt + 1;     // 有效计数 / Valid count
    END_IF
END_FOR
IF uValidCnt >= 1 THEN
    fDeltaMean := fDeltaSum / UDINT_TO_REAL(uValidCnt);     // 均值 / Mean
ELSE
    fDeltaMean := 0.0;          // 保护 / Guard
END_IF

// ---- 应用增量（减均值保总和守恒）/ Apply deltas minus mean (conservation) ----
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] THEN
        afValve_pct[uZi] := afValve_pct[uZi] + (aDelta[uZi] - fDeltaMean);  // 守恒增量 / Conserved delta
        // 最终阀位钳 0~100 % / Final valve clamp
        IF afValve_pct[uZi] < 0.0 THEN
            afValve_pct[uZi] := 0.0;    // 下限 / Lower clamp
        ELSIF afValve_pct[uZi] > 100.0 THEN
            afValve_pct[uZi] := 100.0;  // 上限 / Upper clamp
        END_IF
    END_IF
END_FOR

// ---- 触限信息级 / At-limit info code ----
FOR uZi := 1 TO 4 DO
    IF abFlowValid[uZi] AND ((afValve_pct[uZi] >= 100.0) OR (afValve_pct[uZi] <= 0.0)) THEN
        eErr := 16#0003_03C3;   // 信息级：触限冻结 / Info: at-limit freeze
        RETURN;                 // 已登记直接返回 / Return after marking
    END_IF
END_FOR

// ---- 正常码 / Normal code ----
eErr := 16#0003_03C0;           // 信息级：均衡正常 / Info: balancing normal

END_FUNCTION_BLOCK
