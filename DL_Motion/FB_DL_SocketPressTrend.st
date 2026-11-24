// =====================================================================
// FB_DL_SocketPressTrend.st
// 压装压力-位移曲线特征提取与包络判定（峰值/位移窗/刚度 → OK·NG）
// Press force-position curve feature extraction and envelope FB
// 码位: 16#0004_034F ~ 16#0004_0353 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 15)
// =====================================================================
FUNCTION_BLOCK FB_DL_SocketPressTrend
VAR_INPUT
    bEnable       : BOOL  := FALSE;    // 使能 / Enable
    bPressStart   : BOOL  := FALSE;    // 上升沿开始采集一次 / Press start on edge
    bPressDone    : BOOL  := FALSE;    // 压装到行程结束 / Press done
    fForce_N      : REAL  := 0.0;      // 实时压力 0~50000 N / Force [N]
    fPos_mm       : REAL  := 0.0;      // 实时位移 0~200 mm / Position [mm]
    fForceMin_N   : REAL  := 500.0;    // 压力下限 >0 N / Min force [N]
    fForceMax_N   : REAL  := 5000.0;   // 压力上限 >下限 N / Max force [N]
    fPosWinLo_mm  : REAL  := 2.0;      // 峰值位移窗下限 ≥0 mm / Position window low [mm]
    fPosWinHi_mm  : REAL  := 8.0;      // 峰值位移窗上限 >下限 mm / Position window high [mm]
    fStiffMin_Nmm : REAL  := 200.0;    // 刚度下限 ≥0 N/mm / Min stiffness [N/mm]
    fReboundPct   : REAL  := 20.0;     // 峰值后取段百分比 5~50 % / Rebound segment [%]
END_VAR
VAR_OUTPUT
    fForcePeak_N  : REAL;              // 峰值压力 N / Peak force [N]
    fPosAtPeak_mm : REAL;              // 峰值处位移 mm / Position at peak [mm]
    fStiff_Nmm    : REAL;              // 刚度估计 N/mm / Stiffness [N/mm]
    bCurveOk      : BOOL;              // 曲线判 OK / Curve OK
    uCurveCnt     : UDINT;             // 已判定曲线数 / Judged curve count
    uNgCode       : USINT;             // NG 码 0=OK 1=低压 2=高压 3=位移窗 4=刚度 / NG code
    eErr          : UDINT;             // 错误码 / Error code
END_VAR
VAR
    rtrigStart    : R_TRIG;            // 启动沿检测（无条件刷新）/ Start edge detector
    rtrigDone     : R_TRIG;            // 完成沿检测（无条件刷新）/ Done edge detector
    aForceBuf     : ARRAY[0..511] OF REAL;     // 压力采集缓冲 / Force capture buffer [N]
    aPosBuf       : ARRAY[0..511] OF REAL;     // 位移采集缓冲 / Position capture buffer [mm]
    uSampleCnt    : UDINT;             // 已采样点数 / Sample count
    uIdx          : UDINT;             // 循环下标 / Loop index
    uK            : INT;               // 采样下标 / Sample subscript
    bCollecting   : BOOL  := FALSE;    // 采集中 / Collecting flag
    bJudged       : BOOL  := FALSE;    // 本曲线已结算 / Judged flag
    bStarted      : BOOL  := FALSE;    // 曾收到启动沿 / Ever started flag
    uPeakIdx      : UDINT;             // 峰值采样序号 / Peak sample index
    fForceLimit   : REAL;              // 峰值后回弹取段力阈 / Rebound segment force threshold [N]
    fReboundHi    : REAL;              // 回弹区间位移上界 / Rebound position upper [mm]
    fPosRef       : REAL;              // 刚度段参考位移 / Stiffness reference position [mm]
    fFRef         : REAL;              // 刚度段参考力 / Stiffness reference force [N]
    fDPos         : REAL;              // 位移差 / Position delta [mm]
    fDForce       : REAL;              // 力差 / Force delta [N]
    xFirstScan    : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0004_034F 信息 曲线判定 OK
//   16#0004_0350 故障 压力/位移非有限
//   16#0004_0351 故障 fForceMax_N ≤ fForceMin_N / fPosWinHi_mm ≤ fPosWinLo_mm / fStiffMin_Nmm < 0（组态错）
//   16#0004_0352 信息 曲线 NG（bCurveOk=FALSE 且 uNgCode>0）——NG 是产品判据不是设备故障
//   16#0004_0353 信息 bPressDone 在从未收到 bPressStart 时置位（时序错）→ 丢弃本次、不出结论
// ---------------------------------------------------------------------

// ---- 沿检测（每拍无条件刷新，R7 纪律）/ Edge detection, unconditional ----
rtrigStart(CLK := bPressStart); // 启动沿 / Start edge
rtrigDone(CLK := bPressDone);   // 完成沿 / Done edge

// ---- 非有限闸 / Finite gate ----
IF (fForce_N <> fForce_N) OR (ABS(fForce_N) >= 1.0E12)
   OR (fPos_mm <> fPos_mm) OR (ABS(fPos_mm) >= 1.0E12) THEN
    eErr := 16#0004_0350;       // 故障码 / Fault code
    RETURN;                     // 采集暂停保持 / Collection holds
END_IF

// ---- 组态错闸 / Configuration fault gate ----
IF (fForceMax_N <= fForceMin_N)
   OR (fPosWinHi_mm <= fPosWinLo_mm)
   OR (fStiffMin_Nmm < 0.0)
   OR (fForceMin_N <= 0.0) THEN
    eErr := 16#0004_0351;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    bCurveOk := FALSE;          // 结论复位 / Verdict reset
    uNgCode := 0;               // NG 码复位 / NG code reset
    fForcePeak_N := 0.0;        // 峰值清零 / Peak cleared
    fPosAtPeak_mm := 0.0;       // 峰位清零 / Peak position cleared
    fStiff_Nmm := 0.0;          // 刚度清零 / Stiffness cleared
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bCollecting := FALSE;       // 采集退出 / Collection off
    bStarted := FALSE;          // 启动历史复位 / Started reset
    eErr := 16#0004_034F;       // 信息级：空闲 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 时序错：未收到启动沿就收到完成沿 → 丢弃不出结论 / Sequence error: done without start ----
IF rtrigDone.Q AND (NOT bStarted) THEN
    bCollecting := FALSE;       // 采集复位 / Collection reset
    bJudged := FALSE;           // 结算标志复位 / Judged reset
    eErr := 16#0004_0353;       // 信息级：时序错 / Info: sequence error
    RETURN;                     // uCurveCnt 不变 / Count unchanged
END_IF

// ---- 启动沿：开新曲线采集 / Start edge: begin new capture ----
IF rtrigStart.Q THEN
    bCollecting := TRUE;        // 采集开始 / Collecting
    bStarted := TRUE;           // 启动历史置位 / Started set
    bJudged := FALSE;           // 结算标志复位 / Judged reset
    uSampleCnt := 0;            // 采样计数清零 / Sample count reset
    fForcePeak_N := 0.0;        // 峰值清零 / Peak cleared
    fPosAtPeak_mm := 0.0;       // 峰位清零 / Peak position cleared
    fStiff_Nmm := 0.0;          // 刚度清零 / Stiffness cleared
    bCurveOk := FALSE;          // 结论复位 / Verdict reset
    uNgCode := 0;               // NG 码复位 / NG code reset
END_IF

// ---- 采集路径 / Collection path ----
IF bCollecting AND (NOT bJudged) THEN
    // 缓冲上限 512 点（到限停止记录并置槽 4，不覆盖前段）/ Buffer cap 512
    IF uSampleCnt < 512 THEN
        uSampleCnt := uSampleCnt + 1;   // 计数 / Count
        aForceBuf[UDINT_TO_INT(uSampleCnt - 1)] := fForce_N;    // 存力 / Store force
        aPosBuf[UDINT_TO_INT(uSampleCnt - 1)] := fPos_mm;       // 存位移 / Store position
        // 峰值跟踪 / Peak tracking
        IF fForce_N > fForcePeak_N THEN
            fForcePeak_N := fForce_N;           // 更新峰值 / Update peak
            fPosAtPeak_mm := fPos_mm;           // 峰位 / Peak position
            uPeakIdx := uSampleCnt - 1;         // 峰序号 / Peak index
        END_IF
    ELSE
        eErr := 16#0004_0352;       // 信息级：缓冲满登记 / Info: buffer full
    END_IF
END_IF

// ---- 完成沿结算（同一曲线不重复结算）/ Done edge: settle once ----
IF rtrigDone.Q AND bStarted AND (NOT bJudged) THEN
    bJudged := TRUE;            // 结算标志 / Judged set
    bCollecting := FALSE;       // 采集结束 / Collection off
    uCurveCnt := uCurveCnt + 1; // 判定计数 / Count increment

    // ---- 空压/漏装独立判：峰值 < 下限 → NG 码 1 / Under-force: NG 1 ----
    IF fForcePeak_N < fForceMin_N THEN
        bCurveOk := FALSE;      // NG / Not OK
        uNgCode := 1;           // 低压码 / Low force code
        eErr := 16#0004_0352;   // 信息级：NG / Info: NG
        RETURN;                 // 结算完成返回 / Settled
    END_IF

    // ---- 高压判 → NG 码 2 / Over force: NG 2 ----
    IF fForcePeak_N > fForceMax_N THEN
        bCurveOk := FALSE;      // NG / Not OK
        uNgCode := 2;           // 高压码 / High force code
        eErr := 16#0004_0352;   // 信息级：NG / Info: NG
        RETURN;                 // 结算完成返回 / Settled
    END_IF

    // ---- 位移窗判 → NG 码 3 / Position window: NG 3 ----
    IF (fPosAtPeak_mm < fPosWinLo_mm) OR (fPosAtPeak_mm > fPosWinHi_mm) THEN
        bCurveOk := FALSE;      // NG / Not OK
        uNgCode := 3;           // 位移窗码 / Window code
        eErr := 16#0004_0352;   // 信息级：NG / Info: NG
        RETURN;                 // 结算完成返回 / Settled
    END_IF

    // ---- 刚度估计：峰值后回弹段斜率（负斜率段不计入）/ Stiffness: rebound slope, skip negative ----
    fReboundHi := fPosWinHi_mm * 2.0;   // 搜索上界（全程扫描替代百分比近似窗）/ Search upper bound
    fPosRef := 0.0;             // 参考位移复位 / Reset ref
    fFRef := 0.0;               // 参考力复位 / Reset ref
    fStiff_Nmm := 0.0;          // 刚度复位 / Reset stiffness
    // 从峰值向后找首个有效正斜率段（回弹区间内）/ Find first valid positive slope after peak
    FOR uIdx := uPeakIdx + 1 TO uSampleCnt - 1 DO
        uK := UDINT_TO_INT(uIdx);           // 下标 / Subscript
        fDPos := aPosBuf[uK] - aPosBuf[uK - 1];     // 位移差 / Position delta
        fDForce := aForceBuf[uK] - aForceBuf[uK - 1];   // 力差 / Force delta
        IF (fDPos >= 0.01) AND (fDForce > 0.0) THEN     // 正斜率且位移够大 / Valid slope
            fStiff_Nmm := fDForce / fDPos;  // 刚度估计 / Stiffness [N/mm]
            fPosRef := aPosBuf[uK];         // 参考点 / Reference point
            fFRef := aForceBuf[uK];         // 参考力 / Reference force
        END_IF
        IF fPosRef > 0.0 THEN
            uIdx := uSampleCnt;             // 找到即提前退出扫描 / Early exit
        END_IF
    END_FOR

    // ---- 刚度判 → NG 码 4 / Stiffness: NG 4 ----
    IF fStiff_Nmm < fStiffMin_Nmm THEN
        bCurveOk := FALSE;      // NG / Not OK
        uNgCode := 4;           // 刚度码 / Stiffness code
        eErr := 16#0004_0352;   // 信息级：NG / Info: NG
        RETURN;                 // 结算完成返回 / Settled
    END_IF

    // ---- 全部通过 → OK / All passed ----
    bCurveOk := TRUE;           // OK / OK
    uNgCode := 0;               // 无 NG 码 / No NG code
    eErr := 16#0004_034F;       // 信息级：判定 OK / Info: OK
END_IF

END_FUNCTION_BLOCK
