(* ============================================================
   DL_Motion / FC_DL_HelicalTurnAdvanceCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：螺旋插补每转 Z 向进给 [mm/rev] 与切向合成进给 [mm/min]：
         合成 = √(切向² + (螺距×转速)²)，并用每转弧长 2πR 校验升角。
   边界：螺距≤0/半径≤0/转速≤0 → 码 1/2/3；非有限 → 码 4（实值同步写 0，N1）；
         螺距 > 2πR（升角>45°，自锁性丧失）→ 码 5，值照给但返回 FALSE。
   依赖：仅 IEC 61131-3（SQRT） ｜ 溯源：DLF-A-RTCP（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_HelicalTurnAdvanceCalc : BOOL
VAR_INPUT
    fPitchMmRev    : LREAL;  // 螺距即每转 Z 进给，域 > 0 [mm/rev] / Helical pitch per revolution
    fRadiusMm      : LREAL;  // 螺旋中心线半径，域 > 0 [mm] / Helical centerline radius
    fFeedProgMmMin : LREAL;  // 编程切向进给率，域 > 0 [mm/min] / Programmed tangential feed rate
    fSpindleRpm    : REAL;   // 主轴转速，域 > 0 [r/min] / Spindle speed per minute
END_VAR
VAR_OUTPUT
    fZPerRev        : REAL;   // 每转 Z 向进给（等于螺距）[mm/rev] / Z advance per revolution
    fHelixFeedMmMin : REAL;   // 切向合成进给率 [mm/min] / Resulting helical feed rate
    uErrId          : UDINT;  // 出口码 0/1/2/3/4/5 [-] / Outlet code
END_VAR
VAR
    _fRpS       : LREAL;  // 转速实数值 [r/min] / Spindle speed as a real number
    _fArcPerRev : LREAL;  // 每转弧长 2πR [mm/rev] / Arc length per revolution
    _fVzMmMin   : LREAL;  // 轴向速率 = 螺距×转速 [mm/min] / Axial velocity from pitch times speed
    _fSumSq     : LREAL;  // 合成平方和 [mm²/min²] / Sum of squared velocity components
    _uCode      : UDINT;  // 出口码暂存 [-] / Staged outlet code
END_VAR
VAR CONSTANT
    DL_HEL_PI : LREAL := 3.14159265358979324;  // 圆周率（LREAL 全精度）[-] / Pi at full precision
END_VAR

(* 段 0：出口预置安全侧 *)
FC_DL_HelicalTurnAdvanceCalc := FALSE;
fZPerRev := 0.0;  fHelixFeedMmMin := 0.0;  uErrId := 4;

(* 段 1：非有限闸 + 三域闸（防零） *)
IF (fPitchMmRev <> fPitchMmRev) OR (fRadiusMm <> fRadiusMm)
   OR (fFeedProgMmMin <> fFeedProgMmMin) OR (fSpindleRpm <> fSpindleRpm) THEN
    RETURN;
END_IF
IF fPitchMmRev <= 0.0 THEN uErrId := 1; RETURN; END_IF
IF fRadiusMm <= 0.0 THEN uErrId := 2; RETURN; END_IF
IF fSpindleRpm <= 0.0 THEN uErrId := 3; RETURN; END_IF

(* 段 2：轴向速率、每转弧长与合成进给 *)
_fRpS := REAL_TO_LREAL(fSpindleRpm);
_fVzMmMin := fPitchMmRev * _fRpS;                        // mm/rev × r/min = mm/min
_fArcPerRev := 2.0 * DL_HEL_PI * fRadiusMm;              // 每转弧长 / Arc length per revolution
_fSumSq := fFeedProgMmMin * fFeedProgMmMin + _fVzMmMin * _fVzMmMin;
IF ((_fVzMmMin - _fVzMmMin) <> (_fVzMmMin - _fVzMmMin)) OR (_fSumSq < 0.0) THEN
    RETURN;                                              // 轴向速率 ±Inf 或平方和异常 / Non-finite axial rate
END_IF
fZPerRev := LREAL_TO_REAL(fPitchMmRev);
fHelixFeedMmMin := LREAL_TO_REAL(SQRT(_fSumSq));

(* 段 3：升角校验（螺距 > 每转弧长 ⇔ 升角 > 45°） *)
_uCode := 0;
IF fPitchMmRev > _fArcPerRev THEN _uCode := 5; END_IF

(* 段 4：结果复检 + 单一出口裁决（N4） *)
IF (fZPerRev <> fZPerRev) OR (fHelixFeedMmMin <> fHelixFeedMmMin)
   OR ((fHelixFeedMmMin - fHelixFeedMmMin) <> (fHelixFeedMmMin - fHelixFeedMmMin)) THEN
    fZPerRev := 0.0;  fHelixFeedMmMin := 0.0;  _uCode := 4;
END_IF
uErrId := _uCode;
IF _uCode = 0 THEN FC_DL_HelicalTurnAdvanceCalc := TRUE; END_IF
END_FUNCTION
