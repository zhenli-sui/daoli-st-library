// FC_DL_AckermannSteerPairCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 阿克曼内外轮角：R = L/tan|δ|，δin = ATAN(L/(R − T/2))，δout = ATAN(L/(R + T/2))，
        按 δ 符号回填正负；|δ| < 1e-4 视为直行，两轮同角（避开 tan 近零除爆）。
  邻件/码位: 与 FC_DL_StanleySteerAngleCalc 串联，把中心轮转角展开为内外轮；
             16#0002_9206 = 非有限、轴距轮距非正或转向几何不可达拒收。
*)
FUNCTION FC_DL_AckermannSteerPairCalc : REAL
VAR_INPUT
    fSteerCenter : REAL := 0.0;     // 中心轮转角 δ [rad]，右转为正 / Center steer angle [rad]
    fWheelBase   : REAL := 2.5;     // 轴距 L [m]，域 > 0 / Wheel base [m]
    fTrackWidth  : REAL := 1.5;     // 轮距 T [m]，域 > 0 / Track width [m]
END_VAR
VAR_OUTPUT
    fSteerInner : REAL;             // 内轮转角 [rad]，与中心同号 / Inner angle [rad]
    fSteerOuter : REAL;             // 外轮转角 [rad]，与中心同号 / Outer angle [rad]
    bValid      : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fAbsDelta : REAL := 0.0;        // 中心转角绝对值 [rad] / Absolute center angle [rad]
    fRadius   : REAL := 0.0;        // 后轴中心转弯半径 R [m] / Turning radius [m]
    fHalfTrk  : REAL := 0.0;        // 半轮距 T/2 [m] / Half track width [m]
    fInner    : REAL := 0.0;        // 内轮转角幅值 [rad] / Inner angle magnitude [rad]
    fOuter    : REAL := 0.0;        // 外轮转角幅值 [rad] / Outer angle magnitude [rad]
END_VAR
// 段 0：全路径出口安全缺省（内外轮零 = 直行）/ Safe defaults, zero angles mean straight
fSteerInner := 0.0;             // 内轮转角缺省零 / Inner angle default zero
fSteerOuter := 0.0;             // 外轮转角缺省零 / Outer angle default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_AckermannSteerPairCalc := 0.0;    // 返回值缺省零（镜像内轮）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fSteerCenter <> fSteerCenter) OR (fWheelBase <> fWheelBase) OR (fTrackWidth <> fTrackWidth)
   OR (ABS(fSteerCenter) >= 3.0E38) OR (ABS(fWheelBase) >= 3.0E38) OR (ABS(fTrackWidth) >= 3.0E38) THEN
    uErrorId := 16#0002_9206;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（轴距轮距为正 + 直行快通道 + 转向几何可达）/ Domain gate
IF (fWheelBase <= 1.0E-6) OR (fTrackWidth <= 1.0E-6) THEN
    uErrorId := 16#0002_9206;   // 轴距或轮距非正 / Non-positive base or track
    RETURN;
END_IF
fAbsDelta := fSteerCenter;                                      // 先直取中心转角 / Take center angle
IF fAbsDelta < 0.0 THEN
    fAbsDelta := -fAbsDelta;                                    // 取绝对值 / Absolute value
END_IF
IF fAbsDelta < 1.0E-4 THEN                                       // 直行快通道 / Straight fast path
    bValid := TRUE;                                             // 直行亦为有效解 / Straight is valid
    RETURN;                                                     // 两轮同角零已由段 0 给出 / Both zero from stage 0
END_IF
fHalfTrk := fTrackWidth / 2.0;                                  // 半轮距 / Half track
fRadius := fWheelBase / TAN(fAbsDelta);                         // R = L/tan|δ| [m] / Turning radius
IF (fRadius - fHalfTrk) <= 1.0E-6 THEN
    uErrorId := 16#0002_9206;   // 内轮半径非正，几何不可达 / Geometry unreachable
    RETURN;
END_IF
// 段 3：主计算（内外轮幅值 + 符号回填）/ Main computation
fInner := ATAN(fWheelBase / (fRadius - fHalfTrk));               // 内轮幅值 / Inner magnitude
fOuter := ATAN(fWheelBase / (fRadius + fHalfTrk));               // 外轮幅值 / Outer magnitude
fSteerInner := fInner;                                          // 先按右转（正）落值 / Assume right turn first
fSteerOuter := fOuter;                                          // 先按右转（正）落值 / Assume right turn first
IF fSteerCenter < 0.0 THEN
    fSteerInner := -fInner;                                     // 左转回填负号 / Negative for left turn
    fSteerOuter := -fOuter;                                     // 左转回填负号 / Negative for left turn
END_IF
// 段 4：出口闸（双角非有限复核 + 内大于外几何自检）/ Outlet gate
IF (fSteerInner <> fSteerInner) OR (fSteerOuter <> fSteerOuter)
   OR (ABS(fSteerInner) >= 3.0E38) OR (ABS(fSteerOuter) >= 3.0E38)
   OR (ABS(fSteerInner) < ABS(fSteerOuter)) THEN
    fSteerInner := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    fSteerOuter := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9206;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_AckermannSteerPairCalc := fSteerInner;    // 返回值镜像内轮 / Return mirrors inner angle
END_FUNCTION
