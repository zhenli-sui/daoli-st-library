// FC_DL_StanleySteerAngleCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: Stanley 前轮转角 δ = ψe + ATAN(k·e/(|v| + v_soft))，限幅 ±0.6 rad；
        软化速度负值归零，分母另设 1e-6 硬下限（双保险防除零）。
  邻件/码位: 与 FC_DL_AckermannSteerPairCalc 串联（转角→内外轮），与纯跟踪件互为替代律；
             16#0002_9205 = 域外或非有限拒收。
*)
FUNCTION FC_DL_StanleySteerAngleCalc : REAL
VAR_INPUT
    fHeadingErr : REAL := 0.0;      // 航向偏差 ψe [rad]，左正 / Heading error [rad]
    fCrossTrack : REAL := 0.0;      // 横向偏差 e [m]，左正 / Cross-track error [m]
    fSpeed      : REAL := 0.5;      // 车速 [m/s] / Vehicle speed [m/s]
    fGain       : REAL := 1.5;      // 横向增益 k [-]，域有限 / Cross-track gain [-]
    fSoft       : REAL := 0.2;      // 低速软化速度 [m/s]，负值取 0 / Softening speed [m/s]
END_VAR
VAR_OUTPUT
    fSteerAngle : REAL;             // 前轮转角 δ [rad]，限幅 ±0.6 / Steer angle [rad]
    bSaturated  : BOOL;             // 限幅命中标志 [-] / Saturation hit flag
    bValid      : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fSoftSafe : REAL := 0.0;        // 软化速度安全值 [m/s] / Sanitized softening speed [m/s]
    fDen      : REAL := 0.0;        // 分母 |v| + v_soft [m/s] / Denominator [m/s]
    fRaw      : REAL := 0.0;        // 未限幅转角 [rad] / Unsaturated angle [rad]
END_VAR
// 段 0：全路径出口安全缺省（转角零 = 直行）/ Safe defaults, zero angle means straight
fSteerAngle := 0.0;             // 转角缺省零 / Steer angle default zero
bSaturated := FALSE;            // 限幅标志预清 / Saturation preset clear
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_StanleySteerAngleCalc := 0.0;     // 返回值缺省零 / Return default zero
// 段 1：非有限闸（五入参全枚举）/ Non-finite gate over all inputs
IF (fHeadingErr <> fHeadingErr) OR (fCrossTrack <> fCrossTrack) OR (fSpeed <> fSpeed)
   OR (fGain <> fGain) OR (fSoft <> fSoft)
   OR (ABS(fHeadingErr) >= 3.0E38) OR (ABS(fCrossTrack) >= 3.0E38) OR (ABS(fSpeed) >= 3.0E38)
   OR (ABS(fGain) >= 3.0E38) OR (ABS(fSoft) >= 3.0E38) THEN
    uErrorId := 16#0002_9205;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（软化速度负值归零 + 分母硬下限）/ Domain gate, R4 divide-by-zero guard
fSoftSafe := fSoft;                                             // 软化速度先直取 / Take as-is
IF fSoftSafe < 0.0 THEN
    fSoftSafe := 0.0;                                           // 负值归零 / Clamp negative
END_IF
fDen := ABS(fSpeed) + fSoftSafe;                                // 分母组装 / Build denominator
IF fDen < 1.0E-6 THEN
    fDen := 1.0E-6;                                             // 分母硬下限 / Hard lower bound
END_IF
// 段 3：主计算（航向项 + 横向项，再限幅）/ Main computation with clamping
fRaw := fHeadingErr + ATAN(fGain * fCrossTrack / fDen);         // δ = ψe + atan(k·e/den) / Stanley law
IF fRaw > 0.6 THEN
    fSteerAngle := 0.6;                                         // 上饱和 / Upper saturation
    bSaturated := TRUE;                                         // 置限幅标志 / Set saturation flag
ELSIF fRaw < -0.6 THEN
    fSteerAngle := -0.6;                                        // 下饱和 / Lower saturation
    bSaturated := TRUE;                                         // 置限幅标志 / Set saturation flag
ELSE
    fSteerAngle := fRaw;                                        // 未饱和直通 / Pass through
END_IF
// 段 4：出口闸（转角非有限复核 + 直行兜底）/ Outlet gate
IF (fSteerAngle <> fSteerAngle) OR (ABS(fSteerAngle) >= 3.0E38) THEN
    fSteerAngle := 0.0;         // 复核失败回直行 / Fallback to straight ahead
    bSaturated := TRUE;         // 异常亦视为饱和 / Abnormal treated as saturated
    uErrorId := 16#0002_9205;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_StanleySteerAngleCalc := fSteerAngle;     // 返回值镜像转角 / Return mirrors angle
END_FUNCTION
