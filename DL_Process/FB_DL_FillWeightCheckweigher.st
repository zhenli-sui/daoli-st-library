// =====================================================================
// FB_DL_FillWeightCheckweigher.st
// 称重剔除秤（动态称重稳定窗 + 欠/超重两向四档 + 剔除脉冲与计数）
// Checkweigher with stable window, two-way 4-band grading and reject pulse
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_0480 ~ 16#0005_0484 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: packaging, checkweigher, oiml, reject-count
// 枚举属主: E_DL_WeightClass 属主为 DL_Process FB_DL_WeightClassifySort
//           同文件（R30 序 9）, 本件只引用不重声明
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 11)
// 口径声明: fTolPct = 0 时退化为判等, 采用 ±1E-6 g 容差声明（浮点禁直接判等）;
//           四档归属闭区间口径, 等于阈值归更严档
// =====================================================================
FUNCTION_BLOCK FB_DL_FillWeightCheckweigher
VAR_INPUT
    bWeightValid  : BOOL  := FALSE;  // 称重有效（件在秤台）/ Weight valid, part on scale
    fWeight_g     : REAL  := 0.0;    // 称重值 0~5000 g / Measured weight [g]
    fNominal_g    : REAL  := 500.0;  // 标称重量 0~5000 g / Nominal weight [g]
    fTolPct       : REAL  := 2.0;    // 容差百分比 0~50 百分比 / Tolerance [pct]
    fStableBand_g : REAL  := 2.0;    // 稳定判波动门槛 0~100 g / Stability band [g]
    tStableWin    : TIME  := T#200MS;  // 稳定窗 T#10MS~T#5S / Stability window [ms]
    tRejectPulse  : TIME  := T#200MS;  // 剔除脉冲宽度 T#10MS~T#5S, 可配置 / Reject pulse width [ms]
    bRejectArm    : BOOL  := FALSE;  // 剔除口布防 / Reject gate armed
END_VAR
VAR_OUTPUT
    eClass        : E_DL_WeightClass := E_DL_WeightClass.eOK;  // 判档结果 / Classification result
    bRejectOut    : BOOL  := FALSE;  // 剔除脉冲输出（宽度按 tRejectPulse）/ Reject pulse output
    uRejectCount  : UDINT := 0;      // 剔除计数 / Reject count
    eErr          : UDINT := 16#0005_0480;  // 错误码 / Error code
END_VAR
VAR
    rtrValid      : R_TRIG;          // 称重有效沿, 每拍无条件刷新 / Weight valid edge, refreshed every cycle
    rtrStable     : R_TRIG;          // 稳定窗完成沿, 每拍无条件刷新 / Stable edge, refreshed every cycle
    tonStab       : TON;             // 稳定窗定时器, 每拍无条件刷新 / Stability timer, refreshed every cycle
    tonRej        : TON;             // 剔除脉冲定时器, 每拍无条件刷新 / Reject pulse timer, refreshed every cycle
    fSnap         : REAL  := 0.0;    // 稳定窗起点重量快照 / Weight snapshot at window start [g]
    fDev          : REAL  := 0.0;    // 与标称偏差 / Deviation from nominal [g]
    fTol          : REAL  := 0.0;    // 单向容差 / One-side tolerance [g]
    bRejHold      : BOOL  := FALSE;  // 剔除脉冲保持标志 / Reject pulse hold flag
    bCfgErr       : BOOL  := FALSE;  // 组态非法标记 / Configuration error flag
    bUnstable     : BOOL  := FALSE;  // 稳定窗未满足标记 / Unstable flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_0480 信息 判档完成正常（合格或常规欠/超重四档）
//   16#0005_0481 故障 重量非有限（传感器故障, 本拍不判档）,
//                解除式 = 称重值恢复有限且量程内
//   16#0005_0482 故障 去皮错误（称重值为负, 皮重偏移非法, 本拍不判档）,
//                解除式 = 称重值回正域
//   16#0005_0483 故障 组态非法（标称/容差/稳定门槛非有限或越域）,
//                解除式 = 恢复合法组态
//   16#0005_0484 信息 稳定窗未满足（动态称重未稳, 延后判档, 不计数）
// ---------------------------------------------------------------------

// ---- 边沿与定时器实例无条件周期刷新（调用不进任何 IF 分支）/ Unconditional refresh ----
rtrValid(CLK := bWeightValid);              // 称重有效沿 / Weight valid edge
tonStab(IN := bWeightValid, PT := tStableWin);   // 稳定窗计时 / Stability timing
rtrStable(CLK := tonStab.Q);                // 稳定窗完成沿 / Stable edge
tonRej(IN := bRejHold, PT := tRejectPulse); // 剔除脉冲计时 / Reject pulse timing

// ---- 稳定窗起点快照 / Snapshot at window start ----
IF rtrValid.Q THEN
    fSnap := fWeight_g;         // 采样起点快照 / Capture start snapshot
END_IF

// ---- 组态闸 / Configuration gate ----
bCfgErr := FALSE;               // 组态标记复位 / Reset config flag
IF (fNominal_g <> fNominal_g) OR (fNominal_g <= 0.0) OR (fNominal_g > 5000.0) THEN
    bCfgErr := TRUE;            // 标称非法 / Nominal illegal
END_IF
IF (fTolPct <> fTolPct) OR (fTolPct < 0.0) OR (fTolPct > 50.0) THEN
    bCfgErr := TRUE;            // 容差非法 / Tolerance illegal
END_IF
IF (fStableBand_g <> fStableBand_g) OR (fStableBand_g < 0.0) OR (fStableBand_g > 100.0) THEN
    bCfgErr := TRUE;            // 稳定门槛非法 / Stability band illegal
END_IF

// ---- 剔除脉冲宽度管理 / Reject pulse width management ----
IF tonRej.Q THEN
    bRejHold := FALSE;          // 脉冲窗完成收口 / Pulse window done
END_IF

// ---- 稳定沿触发判档 / Stable edge triggers classification ----
IF rtrStable.Q AND bWeightValid THEN
    IF (fWeight_g <> fWeight_g) OR (ABS(fWeight_g) >= 1.0E12) THEN
        eErr := 16#0005_0481;   // 非有限故障, 本拍不判档不计数 / Non-finite, skip
    ELSIF fWeight_g < 0.0 THEN
        eErr := 16#0005_0482;   // 去皮错误独立码 / Tare error, skip
    ELSIF bCfgErr THEN
        eErr := 16#0005_0483;   // 组态非法不判档 / Config fault, skip
    ELSIF ABS(fWeight_g - fSnap) >= fStableBand_g THEN
        bUnstable := TRUE;      // 窗内波动超门槛, 延后判档 / Fluctuation too big, defer
        eErr := 16#0005_0484;
    ELSE
        // 两向四档判档（闭区间口径, 等于阈值归更严档）/ Two-way 4-band grading
        fDev := fWeight_g - fNominal_g;             // 偏差 / Deviation [g]
        fTol := fNominal_g * fTolPct / 100.0;       // 单向容差 / One-side tolerance [g]
        IF ABS(fTol) < 1E-6 THEN
            fTol := 1E-6;       // 容差为 0 退化为判等 ±1E-6 g 声明 / Zero tolerance degrades to equality
        END_IF
        IF fDev >= (2.0 * fTol) THEN
            eClass := E_DL_WeightClass.eHH;     // 严重超重 / Severely over
        ELSIF fDev >= fTol THEN
            eClass := E_DL_WeightClass.eH;      // 超重 / Over
        ELSIF fDev <= (-2.0 * fTol) THEN
            eClass := E_DL_WeightClass.eLL;     // 严重欠重 / Severely under
        ELSIF fDev <= (-fTol) THEN
            eClass := E_DL_WeightClass.eL;      // 欠重 / Under
        ELSE
            eClass := E_DL_WeightClass.eOK;     // 合格 / Ok
        END_IF
        IF eClass <> E_DL_WeightClass.eOK THEN
            uRejectCount := uRejectCount + 1;   // 剔除计数 / Count reject
            bRejHold := TRUE;                   // 启动剔除脉冲窗 / Start reject pulse
        END_IF
        eErr := 16#0005_0480;   // 判档正常 / Classification normal
    END_IF
END_IF

// ---- 剔除脉冲输出（布防门控 + 脉冲保持）/ Reject output with arm gate ----
bRejectOut := bRejectArm AND bRejHold;

END_FUNCTION_BLOCK
