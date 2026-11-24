// =====================================================================
// FB_DL_ElectrodeRollDiameter.st
// 极卷直径跟踪与换卷预警（卷径递推 + 低速保护 + 单调校核 + 换卷阈值预警）
// Electrode roll diameter tracking with change-over warning
// 所属子库: DL_Motion    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0004_035E ~ 16#0004_0362 (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: lithium-battery, winding, coil-diameter, warning
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 16)
// 分层声明: 卷径换算公式与 FC_DL_CoilDiameterCalc 口径一致（本件只加跟踪
//           与预警层, 不重写公式件）: D = v·k/(π·n), k = 1000 mm/m
// =====================================================================
FUNCTION_BLOCK FB_DL_ElectrodeRollDiameter
VAR_INPUT
    fLineSpd_mmin : REAL := 0.0;    // 线速度 0~300 m/min / Line speed [m/min]
    fRollRpm      : REAL := 0.0;    // 卷轴转速 0~3000 r/min / Roll speed [r/min]
    fPrevDia_mm   : REAL := 500.0;  // 上次卷径注入 0~2000 mm / Previous diameter injected [mm]
    fCoreDia_mm   : REAL := 76.0;   // 卷芯直径 0~2000 mm / Core diameter [mm]
    fThick_um     : REAL := 25.0;   // 层厚校核值 0~500 um / Layer thickness [um]
    fWarnDia_mm   : REAL := 120.0;  // 换卷预警径 0~2000 mm / Change warning diameter [mm]
END_VAR
VAR_OUTPUT
    fDia_mm     : REAL := 0.0;      // 当前卷径 / Current diameter [mm]
    bChangeWarn : BOOL := FALSE;    // 换卷预警 / Change-over warning
    bAtCore     : BOOL := FALSE;    // 卷径触及芯径 / At core flag
    eErr        : UDINT := 16#0004_035E;  // 错误码 / Error code
END_VAR
VAR
    rPi     : REAL := 3.14159265358979;   // 圆周率 / Pi constant
    fSpdMin : REAL := 1.0;          // 低速门限（线速度）m/min, 工程固定门限 / Min line speed gate
    fRpmMin : REAL := 5.0;          // 低速门限（转速）r/min, 工程固定门限 / Min roll speed gate
    fCalcDia: REAL := 0.0;          // 本拍换算卷径 / Calculated diameter this cycle [mm]
    fTolDia : REAL := 0.0;          // 单调校核容差（双倍层厚换算）/ Monotonic tolerance from thickness [mm]
    bCfgErr : BOOL := FALSE;        // 组态非法标记 / Configuration error flag
    bHoldErr: BOOL := FALSE;        // 递推保持标记（非有限或单调违反）/ Recursion hold flag
    bLowSpd : BOOL := FALSE;        // 低速保护标记 / Low speed protection flag
    xFirst  : BOOL := TRUE;         // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0004_035E 信息 卷径跟踪正常
//   16#0004_035F 故障 组态非法（芯径/预警径非有限或不大于 0, 或芯径不低于
//                预警径倒置）; 解除式 = 恢复合法组态
//   16#0004_0360 故障 递推保持（速度/转速非有限, 或新卷径违反放卷单调递减）,
//                卷径保持上拍值; 解除式 = 输入恢复有限且差分恢复单调
//   16#0004_0361 信息 低速保护冻结（线速或转速低于门限, 卷径保持不递推）
//   16#0004_0362 信息 换卷预警（卷径不大于预警径, 含触及芯径）
// ---------------------------------------------------------------------

// ---- 首扫: 以注入的上次卷径为初始跟踪值 / First scan: seed from injected ----
IF xFirst THEN
    fDia_mm := fPrevDia_mm;     // 初始卷径 / Initial diameter [mm]
    xFirst := FALSE;            // 清首扫标记 / Clear flag
END_IF

// ---- 组态闸 / Configuration gate ----
bCfgErr := FALSE;
IF (fCoreDia_mm <> fCoreDia_mm) OR (fCoreDia_mm <= 0.0) OR (fCoreDia_mm > 2000.0) THEN
    bCfgErr := TRUE;            // 芯径非法 / Illegal core diameter
END_IF
IF (fWarnDia_mm <> fWarnDia_mm) OR (fWarnDia_mm <= 0.0) OR (fWarnDia_mm > 2000.0) THEN
    bCfgErr := TRUE;            // 预警径非法 / Illegal warning diameter
END_IF
IF (NOT bCfgErr) AND (fCoreDia_mm >= fWarnDia_mm) THEN
    bCfgErr := TRUE;            // 芯径不低于预警径 = 倒置 / Inverted config
END_IF

// ---- 输出缺省 / Output defaults ----
bHoldErr := FALSE;
bLowSpd  := FALSE;

IF bCfgErr THEN
    // 组态非法: 卷径保持, 安全侧不递推 / Config fault: hold, no recursion
    eErr := 16#0004_035F;
ELSE
    // ---- 低速保护判 / Low speed protection judge ----
    bLowSpd := (fLineSpd_mmin < fSpdMin) OR (fRollRpm < fRpmMin);
    // ---- 非有限判 / Finite judge ----
    IF (fLineSpd_mmin <> fLineSpd_mmin) OR (ABS(fLineSpd_mmin) >= 1.0E12)
       OR (fRollRpm <> fRollRpm) OR (ABS(fRollRpm) >= 1.0E12)
       OR (fPrevDia_mm <> fPrevDia_mm) THEN
        bHoldErr := TRUE;       // 非有限保持 / Non-finite hold
        eErr := 16#0004_0360;
    ELSIF bLowSpd THEN
        // 低速保护: 冻结递推, 卷径保持 / Freeze recursion on low speed
        eErr := 16#0004_0361;
    ELSE
        // ---- 卷径递推: D = v·k/(π·n), k = 1000 mm/m, 转速门限已保证不为零
        //      Diameter recursion with guarded division ----
        fCalcDia := (fLineSpd_mmin * 1000.0) / (rPi * fRollRpm);
        // 层厚校核容差: 允许的单拍回升量 = 两倍层厚换算 / Monotonic tolerance from thickness
        fTolDia := 2.0 * fThick_um / 1000.0;
        IF fCalcDia > (fDia_mm + fTolDia) THEN
            // 放卷单调递减违反: 保持 + 故障码 / Monotonic violation: hold
            bHoldErr := TRUE;
            eErr := 16#0004_0360;
        ELSE
            fDia_mm := fCalcDia;    // 递推更新 / Update diameter
            // 卷径下限钳卷芯径 / Clamp to core diameter
            IF fDia_mm < fCoreDia_mm THEN
                fDia_mm := fCoreDia_mm;
            END_IF
            eErr := 16#0004_035E;   // 跟踪正常 / Tracking normal
        END_IF
    END_IF
END_IF

// ---- 预警与触芯输出（闭口径: 恰好等于预警径即触发）/ Warning and at-core ----
bChangeWarn := fDia_mm <= fWarnDia_mm;      // 恰好等于预警径与更低均触发 / Trigger at and below
bAtCore := (fDia_mm - fCoreDia_mm) < 1.0E-6;    // 容差判触芯 / At core with tolerance

END_FUNCTION_BLOCK
