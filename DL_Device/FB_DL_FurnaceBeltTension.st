// =====================================================================
// FB_DL_FurnaceBeltTension.st
// 烧结炉网带张力闭环 + 边缘跑偏纠偏（双环加权共用执行器）
// Furnace belt tension loop + edge steering FB
// 码位: 16#0003_03D4 ~ 16#0003_03D8 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 11)
// =====================================================================
FUNCTION_BLOCK FB_DL_FurnaceBeltTension
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    bWebRun        : BOOL  := FALSE;   // 网带运行 / Web running
    fTension_N     : REAL  := 0.0;     // 实测张力 0~5000 N / Measured tension [N]
    fTensionSp_N   : REAL  := 800.0;   // 张力设定 0~5000 N / Tension setpoint [N]
    fEdgePos_mm    : REAL  := 0.0;     // 边缘位置 -50~50 mm（正=右偏）/ Edge position [mm]
    fEdgeCenter_mm : REAL  := 0.0;     // 边缘中心基准 -50~50 mm / Edge center [mm]
    fEdgeTol_mm    : REAL  := 3.0;     // 跑偏容差 0.1~20 mm / Edge tolerance [mm]
    fTensionTolPct : REAL  := 5.0;     // 张力容差 0.5~50 % / Tension tolerance [%]
    fKpT           : REAL  := 0.02;    // 张力环增益 0.001~1 %/N / Tension gain [%/N]
    fKpE           : REAL  := 0.5;     // 纠偏环增益 0.01~5 %/mm / Edge gain [%/mm]
    fTrimMax_pct   : REAL  := 10.0;    // 输出限幅 0.5~50 % / Output limit [%]
    fWeightT       : REAL  := 0.7;     // 张力权重 0~1 / Tension weight [-]
END_VAR
VAR_OUTPUT
    fTrimOut_pct   : REAL;              // 速度微调 -100~100 % / Speed trim [%]
    fDev_N         : REAL;              // 张力偏差 N / Tension deviation [N]
    fEdgeDev_mm    : REAL;              // 边缘偏差 mm / Edge deviation [mm]
    bTensionAlarm  : BOOL;              // 张力超差 / Tension alarm
    bEdgeAlarm     : BOOL;              // 跑偏超差 / Edge alarm
    eErr           : UDINT;             // 错误码 / Error code
END_VAR
VAR
    fWeightTSafe   : REAL;              // 钳 [0,1] 后张力权重 / Clamped tension weight [-]
    fWeightE       : REAL;              // 纠偏权重 = 1-张力权重 / Edge weight [-]
    fTensionTrim   : REAL;              // 张力环输出项 / Tension loop term [%]
    fEdgeTrim      : REAL;              // 纠偏环输出项 / Edge loop term [%]
    fTolPctSafe    : REAL;              // 张力容差处理值 / Sanitized tension tolerance [%]
    fEdgeTolSafe   : REAL;              // 跑偏容差处理值 / Sanitized edge tolerance [mm]
    bSatLatch      : BOOL := FALSE;     // 饱和故障锁存 / Saturation fault latch
    tonSat         : TON;               // 饱和持续计时（无条件刷新）/ Saturation timer
    bSatCond       : BOOL;              // 饱和条件当前值 / Saturation condition
    xFirstScan     : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0003_03D4 信息 双环运行正常
//   16#0003_03D5 故障 输入非有限
//   16#0003_03D6 故障 fTensionSp_N ≤ 0 / fTrimMax_pct ≤ 0 / fKpT ≤ 0 / fKpE < 0（组态错）；fEdgeTol ≤ 0 兜底登记同槽
//   16#0003_03D7 信息 bWebRun=FALSE 或 bEdgeAlarm=TRUE → 输出归 0 / 张力环冻结，积分保持
//   16#0003_03D8 故障 张力环输出持续 10 s 触限仍同向偏差 > 容差 → 锁存，解除需 bReset
// ---------------------------------------------------------------------

// ---- 非有限闸 / Finite gate ----
IF (fTension_N <> fTension_N) OR (ABS(fTension_N) >= 1.0E12)
   OR (fTensionSp_N <> fTensionSp_N) OR (ABS(fTensionSp_N) >= 1.0E12)
   OR (fEdgePos_mm <> fEdgePos_mm) OR (ABS(fEdgePos_mm) >= 1.0E12)
   OR (fEdgeCenter_mm <> fEdgeCenter_mm) OR (ABS(fEdgeCenter_mm) >= 1.0E12)
   OR (fEdgeTol_mm <> fEdgeTol_mm) OR (ABS(fEdgeTol_mm) >= 1.0E12)
   OR (fTensionTolPct <> fTensionTolPct) OR (ABS(fTensionTolPct) >= 1.0E12)
   OR (fKpT <> fKpT) OR (ABS(fKpT) >= 1.0E12)
   OR (fKpE <> fKpE) OR (ABS(fKpE) >= 1.0E12)
   OR (fTrimMax_pct <> fTrimMax_pct) OR (ABS(fTrimMax_pct) >= 1.0E12)
   OR (fWeightT <> fWeightT) OR (ABS(fWeightT) >= 1.0E12) THEN
    fTrimOut_pct := 0.0;        // 输出归 0（安全侧）/ Output zero
    bTensionAlarm := FALSE;     // 报警复位 / Alarm reset
    eErr := 16#0003_03D5;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fTensionSp_N <= 0.0) OR (fTrimMax_pct <= 0.0) OR (fKpT <= 0.0) OR (fKpE < 0.0) THEN
    fTrimOut_pct := 0.0;        // 输出归 0 / Output zero
    bTensionAlarm := FALSE;     // 不误报超差 / No false alarm
    bEdgeAlarm := FALSE;        // 报警复位 / Alarm reset
    eErr := 16#0003_03D6;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    fTrimOut_pct := 0.0;        // 输出从 0 起步 / Output starts at zero
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 权重钳位与归一（和恒为 1，不得双环各自满幅叠加）/ Weight clamp and normalize ----
fWeightTSafe := fWeightT;       // 原值 / As-is
IF fWeightTSafe < 0.0 THEN
    fWeightTSafe := 0.0;        // 下限 / Lower clamp
ELSIF fWeightTSafe > 1.0 THEN
    fWeightTSafe := 1.0;        // 上限 / Upper clamp
END_IF
fWeightE := 1.0 - fWeightTSafe; // 纠偏权重 / Edge weight

// ---- 容差兜底 / Tolerance fallbacks ----
IF fEdgeTol_mm <= 0.0 THEN
    fEdgeTolSafe := 0.1;        // 兜底 0.1 mm / Fallback 0.1 mm
ELSE
    fEdgeTolSafe := fEdgeTol_mm;    // 原值 / As-is
END_IF
IF fTensionTolPct <= 0.0 THEN
    fTolPctSafe := 0.5;         // 兜底 0.5 % / Fallback 0.5 %
ELSE
    fTolPctSafe := fTensionTolPct;  // 原值 / As-is
END_IF

// ---- 饱和故障锁存与解除 / Saturation latch and release ----
IF bSatLatch THEN
    fTrimOut_pct := 0.0;        // 锁存中输出归 0 / Zero output when latched
    bTensionAlarm := FALSE;     // 报警复位 / Alarm reset
    eErr := 16#0003_03D8;       // 故障码回放 / Fault code replay
    IF bReset THEN
        bSatLatch := FALSE;     // 解除锁存 / Release latch
    END_IF
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 使能撤销：双环输出归 0 / Disable: outputs zero ----
IF NOT bEnable THEN
    fTrimOut_pct := 0.0;        // 输出归 0 / Output zero
    bTensionAlarm := FALSE;     // 报警复位 / Alarm reset
    bEdgeAlarm := FALSE;        // 报警复位 / Alarm reset
    eErr := 16#0003_03D4;       // 信息级：空闲 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 偏差计算 / Deviation computation ----
fDev_N := fTensionSp_N - fTension_N;        // 张力偏差 / Tension deviation [N]
fEdgeDev_mm := fEdgePos_mm - fEdgeCenter_mm;    // 边缘偏差 / Edge deviation [mm]

// ---- 张力超差报警（分母有设定值闸，sp>0 已由组态闸保证）/ Tension alarm ----
bTensionAlarm := (ABS(fDev_N) / fTensionSp_N * 100.0 > fTolPctSafe);   // 超差判 / Over-tolerance

// ---- 边缘跑偏报警 / Edge alarm ----
bEdgeAlarm := (ABS(fEdgeDev_mm) > fEdgeTolSafe);    // 跑偏判 / Over-tolerance

// ---- 网带停止：双环输出归 0，积分保持（再启动无扰）/ Web stopped: outputs zero, hold ----
IF NOT bWebRun THEN
    fTrimOut_pct := 0.0;        // 输出归 0 / Output zero
    eErr := 16#0003_03D7;       // 信息级：停机冻结 / Info: stopped freeze
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 双环计算 / Dual loop computation ----
fTensionTrim := fWeightTSafe * fKpT * fDev_N;       // 张力项（跑偏报警时冻结）/ Tension term
fEdgeTrim := fWeightE * fKpE * fEdgeDev_mm;         // 纠偏项 / Edge term

IF bEdgeAlarm THEN
    // 跑偏超差：张力环输出冻结以免叠加扰动，输出只含纠偏项 / Edge alarm: tension frozen
    fTrimOut_pct := fEdgeTrim;  // 只含纠偏项 / Edge term only
    eErr := 16#0003_03D7;       // 信息级：张力环冻结 / Info: tension frozen
ELSE
    fTrimOut_pct := fTensionTrim + fEdgeTrim;   // 双环加权合成 / Weighted sum
    eErr := 16#0003_03D4;       // 信息级：双环正常 / Info: normal
END_IF

// ---- 输出限幅：先钳后使用 / Output clamp ----
IF fTrimOut_pct > fTrimMax_pct THEN
    fTrimOut_pct := fTrimMax_pct;   // 上限钳 / Upper clamp
ELSIF fTrimOut_pct < -fTrimMax_pct THEN
    fTrimOut_pct := -fTrimMax_pct;  // 下限钳 / Lower clamp
END_IF

// ---- 饱和监控：触限 + 同向偏差超容差 持续 10 s → 锁存 / Saturation monitor ----
bSatCond := FALSE;              // 条件复位 / Reset
IF (fTrimOut_pct >= fTrimMax_pct) AND (fDev_N > 0.0)
   AND (ABS(fDev_N) / fTensionSp_N * 100.0 > fTolPctSafe) THEN
    bSatCond := TRUE;           // 正向饱和 / Positive saturation
END_IF
IF (fTrimOut_pct <= -fTrimMax_pct) AND (fDev_N < 0.0)
   AND (ABS(fDev_N) / fTensionSp_N * 100.0 > fTolPctSafe) THEN
    bSatCond := TRUE;           // 负向饱和 / Negative saturation
END_IF
tonSat(IN := bSatCond, PT := T#10S);    // 定时器无条件周期刷新 / Unconditional refresh
IF tonSat.Q THEN
    bSatLatch := TRUE;          // 锁存 / Latch
    fTrimOut_pct := 0.0;        // 输出归 0 / Output zero
    eErr := 16#0003_03D8;       // 故障码 / Fault code
END_IF

END_FUNCTION_BLOCK
