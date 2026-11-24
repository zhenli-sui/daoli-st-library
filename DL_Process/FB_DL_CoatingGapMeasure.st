// =====================================================================
// FB_DL_CoatingGapMeasure.st
// 涂布留白（Gap）宽度与边缘对齐判定（像素到毫米标定 + 区间带 + 窗口一致性）
// Coating gap width judge with pixel calibration and band check
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_048A ~ 16#0005_048E (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: lithium-battery, coating, vision-metrology, tolerance
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 13)
// 分层声明: 带判定消费 DL_Base 的 FC_DL_IntervalMembership（双闭组合,
//           恰好落在带端点判带内）; 窗口一致性消费 DL_MathData 的
//           FB_DL_SignalStatistics（窗口均值/极差经引脚注入, 本件不重写统计）
// =====================================================================
FUNCTION_BLOCK FB_DL_CoatingGapMeasure
VAR_INPUT
    afPixEdge1    : REAL := 0.0;    // 第一边缘像素坐标 / First edge pixel coordinate [px]
    afPixEdge2    : REAL := 0.0;    // 第二边缘像素坐标 / Second edge pixel coordinate [px]
    fPixToMm      : REAL := 0.01;   // 标定系数 0~10 mm/px / Calibration factor [mm/px]
    afGapLo_mm    : REAL := 8.0;    // 留白带下限 0~100 mm / Gap band lower [mm]
    afGapHi_mm    : REAL := 12.0;   // 留白带上限 0~100 mm / Gap band upper [mm]
    fWinTolPct    : REAL := 10.0;   // 窗口一致性容差（相对带宽）0~100 百分比 / Window consistency tolerance [pct]
    uWinSize      : USINT := 8;     // 窗口样本数配置（传给上游统计件）2~256 / Window size config
    fWinMean_mm   : REAL := 0.0;    // 窗口均值注入（统计件 fMean 语义）/ Window mean injected [mm]
    fWinRange_mm  : REAL := 0.0;    // 窗口极差注入（统计件 fRange 语义）/ Window range injected [mm]
    bWinStatValid : BOOL := FALSE;  // 窗口统计有效注入（统计件 bValid 语义）/ Window stat valid injected
END_VAR
VAR_OUTPUT
    fGap_mm         : REAL  := 0.0;   // 留白宽度 / Gap width [mm]
    bGapOk          : BOOL  := FALSE; // 带内判定 / In-band flag
    bWindowConsist  : BOOL  := FALSE; // 窗口一致性 / Window consistency flag
    eErr            : UDINT := 16#0005_048A;  // 错误码 / Error code
END_VAR
VAR
    bCfgErr    : BOOL  := FALSE;      // 组态非法标记 / Configuration error flag
    bSnsErr    : BOOL  := FALSE;      // 传感器故障标记（边缘序颠倒）/ Sensor error flag
    fBandSpan  : REAL  := 0.0;        // 带宽 / Band span [mm]
    bInBand    : BOOL  := FALSE;      // 区间判定返回 / Interval membership return
    fGapL      : LREAL := 0.0;        // 留白宽度双精度临时量 / Gap width LREAL temporary [mm]
    fLoL       : LREAL := 0.0;        // 带下限双精度临时量 / Band lower LREAL temporary [mm]
    fHiL       : LREAL := 0.0;        // 带上限双精度临时量 / Band upper LREAL temporary [mm]
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_048A 信息 留白判定正常（带内且窗口一致性满足）
//   16#0005_048B 信息 留白越带（带外, 判定值仍逐拍输出）
//   16#0005_048C 故障 组态非法（标定系数非有限或不大于 0, 带倒置, 容差越域,
//                窗口样本数小于 2）; 解除式 = 恢复合法组态
//   16#0005_048D 故障 边缘序颠倒（第二边缘不大于第一边缘 → 负留白, 传感器故障）,
//                解除式 = 边缘序恢复正差
//   16#0005_048E 信息 窗口一致性不满足（均值/极差注入超容差或统计无效）
// ---------------------------------------------------------------------

// ---- 组态闸 / Configuration gate ----
bCfgErr := FALSE;                   // 组态标记复位 / Reset config flag
IF (fPixToMm <> fPixToMm) OR (fPixToMm <= 0.0) OR (fPixToMm > 10.0) THEN
    bCfgErr := TRUE;                // 标定系数非法 / Illegal calibration
END_IF
IF (afGapLo_mm <> afGapLo_mm) OR (afGapHi_mm <> afGapHi_mm)
   OR (afGapHi_mm < afGapLo_mm) THEN
    bCfgErr := TRUE;                // 带非法或倒置 / Illegal or inverted band
END_IF
IF (fWinTolPct <> fWinTolPct) OR (fWinTolPct < 0.0) OR (fWinTolPct > 100.0) THEN
    bCfgErr := TRUE;                // 容差越域 / Illegal tolerance
END_IF
IF uWinSize < 2 THEN
    bCfgErr := TRUE;                // 窗口过小, 统计无意义 / Window too small
END_IF

// ---- 输出缺省收口 / Output defaults ----
fGap_mm := 0.0;                     // 缺省零 / Default zero
bGapOk := FALSE;                    // 缺省带外 / Default out of band
bWindowConsist := FALSE;            // 缺省不一致 / Default inconsistent
bSnsErr := FALSE;                   // 传感器标记复位 / Reset sensor flag

IF NOT bCfgErr THEN
    IF (afPixEdge1 <> afPixEdge1) OR (ABS(afPixEdge1) >= 1.0E12)
       OR (afPixEdge2 <> afPixEdge2) OR (ABS(afPixEdge2) >= 1.0E12) THEN
        bSnsErr := TRUE;            // 边缘坐标非有限 / Non-finite edge coordinate
    ELSE
        fGap_mm := (afPixEdge2 - afPixEdge1) * fPixToMm;    // 像素差换算毫米 / Pixel diff to mm
        IF fGap_mm < 0.0 THEN
            bSnsErr := TRUE;        // 边缘序颠倒判负留白 / Reversed edges, negative gap
        ELSE
            // 带判定消费区间判定函数（双闭组合, 端点恰落判带内）/ Band via interval membership
            fGapL := REAL_TO_LREAL(fGap_mm);
            fLoL  := REAL_TO_LREAL(afGapLo_mm);
            fHiL  := REAL_TO_LREAL(afGapHi_mm);
            bInBand := FC_DL_IntervalMembership(fGapL, fLoL, fHiL,
                        E_DL_IntervalKind.eClosedClosed, 1.0E-9);
            bGapOk := bInBand;      // 带内判定 / In-band result
            // 窗口一致性消费注入统计量（不重写统计）/ Window consistency via injected stats
            fBandSpan := afGapHi_mm - afGapLo_mm;   // 带宽 / Band span [mm]
            IF bWinStatValid AND (fWinMean_mm = fWinMean_mm) AND (fWinRange_mm = fWinRange_mm) THEN
                bWindowConsist := (ABS(fWinMean_mm - fGap_mm) <= (fBandSpan * fWinTolPct / 100.0))
                               AND (fWinRange_mm <= (2.0 * fBandSpan * fWinTolPct / 100.0));
            ELSE
                bWindowConsist := FALSE;    // 统计无效或注入非有限判不一致 / Invalid stats judged inconsistent
            END_IF
        END_IF
    END_IF
END_IF

// ---- 错误码仲裁 / Error arbitration ----
IF bCfgErr THEN
    eErr := 16#0005_048C;           // 组态非法 / Config fault
ELSIF bSnsErr THEN
    eErr := 16#0005_048D;           // 边缘序颠倒 / Reversed edges
ELSIF NOT bGapOk THEN
    eErr := 16#0005_048B;           // 留白越带 / Out of band
ELSIF NOT bWindowConsist THEN
    eErr := 16#0005_048E;           // 窗口一致性不满足 / Window inconsistent
ELSE
    eErr := 16#0005_048A;           // 判定正常 / Judgement normal
END_IF

END_FUNCTION_BLOCK
