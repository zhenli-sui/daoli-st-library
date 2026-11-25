// FC_DL_WinderTraversePitchCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Device，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 排线节距 = 带宽·(1 − 搭接率) [mm]；换向次数 = (卷绕线速·1000/60)/(2·排线行程) [次/min]；
        排线速度 = 节距·换向次数/60 [mm/s]。此为等比近似工程式：以排线行程近似替代卷径，
        适用于定行程往复排线的稳态估算，卷径变化需上层按卷径比修正。
  邻件/码位: 与 FC_DL_FiberDiameterFromDrawRateCalc 同属拉丝后端件（卷绕面 vs 直径面）；
             16#0002_9224 = 非有限、搭接率越界或带宽/行程/线速非正拒收。
*)
FUNCTION FC_DL_WinderTraversePitchCalc : REAL
VAR_INPUT
    fStrandWidth  : REAL := 20.0;   // 丝束带宽 [mm]，域 > 0 / Strand band width [mm]
    fOverlapRatio : REAL := 0.2;    // 搭接率 [-]，域 [0, 1) / Overlap ratio
    fWinderSpeed  : REAL := 900.0;  // 卷绕线速 [m/min]，域 > 0 / Winding speed [m/min]
    fTraverseLen  : REAL := 250.0;  // 排线行程 [mm]，域 > 0 / Traverse stroke [mm]
END_VAR
VAR_OUTPUT
    fPitch          : REAL;         // 排线节距 [mm] / Traverse pitch [mm]
    fTraverseSpeed  : REAL;         // 排线速度 [mm/s] / Traverse speed [mm/s]
    fReversalPerMin : REAL;         // 每分钟换向次数 [次/min] / Reversals per minute
    bValid          : BOOL;         // 结果有效回执 [-] / Result validity receipt
    uErrorId        : UDINT;        // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fSpeedMmS    : REAL := 0.0;     // 卷绕线速 [mm/s] / Winding speed [mm/s]
    fRoundTripMm : REAL := 0.0;     // 往返行程长度 [mm] / Round-trip travel [mm]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fPitch := 0.0;                      // 节距缺省零 / Pitch default zero
fTraverseSpeed := 0.0;              // 排线速度缺省零 / Traverse speed default zero
fReversalPerMin := 0.0;             // 换向次数缺省零 / Reversal rate default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_WinderTraversePitchCalc := 0.0;   // 返回值缺省零（镜像节距）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fStrandWidth <> fStrandWidth) OR (fOverlapRatio <> fOverlapRatio)
   OR (fWinderSpeed <> fWinderSpeed) OR (fTraverseLen <> fTraverseLen)
   OR (ABS(fStrandWidth) >= 3.0E38) OR (ABS(fOverlapRatio) >= 3.0E38)
   OR (ABS(fWinderSpeed) >= 3.0E38) OR (ABS(fTraverseLen) >= 3.0E38) THEN
    uErrorId := 16#0002_9224;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（搭接率 [0,1) 防节距非正 + 带宽/行程/线速为正，R4）/ Domain gate
IF (fOverlapRatio < 0.0) OR (fOverlapRatio >= 1.0) THEN
    uErrorId := 16#0002_9224;   // 搭接率越界，节距将非正 / Overlap ratio out of range
    RETURN;
END_IF
IF (fStrandWidth <= 1.0E-6) OR (fTraverseLen <= 1.0E-6) OR (fWinderSpeed <= 1.0E-6) THEN
    uErrorId := 16#0002_9224;   // 带宽、行程或线速非正 / Non-positive width, stroke or speed
    RETURN;
END_IF
// 段 3：主计算（节距 → 换向次数 → 排线速度）/ Main computation
fPitch := fStrandWidth * (1.0 - fOverlapRatio);                 // 节距 [mm] / Pitch
fRoundTripMm := 2.0 * fTraverseLen;                             // 往返行程 [mm] / Round-trip travel
fSpeedMmS := fWinderSpeed * 1000.0 / 60.0;                      // 卷绕线速 [mm/s] / Winding speed
fReversalPerMin := fSpeedMmS / fRoundTripMm * 60.0;             // 换向次数 [次/min] / Reversal rate
fTraverseSpeed := fPitch * fReversalPerMin / 60.0;              // 排线速度 [mm/s] / Traverse speed
// 段 4：出口闸（三输出非有限复核 + 正数复核）/ Outlet gate
IF (fPitch <> fPitch) OR (fTraverseSpeed <> fTraverseSpeed) OR (fReversalPerMin <> fReversalPerMin)
   OR (ABS(fPitch) >= 3.0E38) OR (ABS(fTraverseSpeed) >= 3.0E38) OR (ABS(fReversalPerMin) >= 3.0E38)
   OR (fPitch <= 0.0) OR (fTraverseSpeed <= 0.0) THEN
    fPitch := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    fTraverseSpeed := 0.0;      // 复核失败回缺省 / Fallback on recheck failure
    fReversalPerMin := 0.0;     // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9224;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_WinderTraversePitchCalc := fPitch;    // 返回值镜像节距 / Return mirrors pitch
END_FUNCTION
