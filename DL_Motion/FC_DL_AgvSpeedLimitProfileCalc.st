// FC_DL_AgvSpeedLimitProfileCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 曲率自适应限速：|κ| < 1e-4 判直道并取车最大速度；弯道按侧向加速度约束
        v = SQRT(a_lat/|κ|)，再向车最大速度取小。
  邻件/码位: 与 FC_DL_PurePursuitCurvatureCalc 衔接（曲率→限速）；对桩末端由
             FC_DL_AgvChargeDockAlignCalc 处理；16#0002_9208 = 非有限或域外拒收。
*)
FUNCTION FC_DL_AgvSpeedLimitProfileCalc : REAL
VAR_INPUT
    fPathCurvature : REAL := 0.0;   // 路径曲率 κ [1/m] / Path curvature [1/m]
    fLatAccMax     : REAL := 0.5;   // 允许侧向加速度 [m/s²]，域 > 0 / Lateral acceleration [m/s^2]
    fSpeedMax      : REAL := 1.5;   // 车最大速度 [m/s]，域 > 0 / Vehicle max speed [m/s]
END_VAR
VAR_OUTPUT
    fSpeedLimit : REAL;             // 限速结果 [m/s] / Speed limit result [m/s]
    bStraight   : BOOL;             // 直道标志 [-] / Straight-path flag
    bValid      : BOOL;             // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fAbsKappa : REAL := 0.0;        // 曲率绝对值 |κ| [1/m] / Absolute curvature [1/m]
END_VAR
// 段 0：全路径出口安全缺省（限速零 = 最保守）/ Safe defaults, zero limit is conservative
fSpeedLimit := 0.0;             // 限速缺省零 / Speed limit default zero
bStraight := FALSE;             // 直道标志预清 / Straight flag preset clear
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_AgvSpeedLimitProfileCalc := 0.0;  // 返回值缺省零 / Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fPathCurvature <> fPathCurvature) OR (fLatAccMax <> fLatAccMax) OR (fSpeedMax <> fSpeedMax)
   OR (ABS(fPathCurvature) >= 3.0E38) OR (ABS(fLatAccMax) >= 3.0E38) OR (ABS(fSpeedMax) >= 3.0E38) THEN
    uErrorId := 16#0002_9208;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（侧向加速度与车最大速度为正）/ Domain gate
IF (fLatAccMax <= 1.0E-6) OR (fSpeedMax <= 1.0E-6) THEN
    uErrorId := 16#0002_9208;   // 上限非正，限速不可解 / Non-positive bound
    RETURN;
END_IF
fAbsKappa := ABS(fPathCurvature);                               // 曲率绝对值 / Absolute curvature
// 段 3：主计算（直道快通道 / 弯道侧向加速度约束）/ Main computation
IF fAbsKappa < 1.0E-4 THEN
    fSpeedLimit := fSpeedMax;                                   // 直道取车最大速度 / Straight: max speed
    bStraight := TRUE;                                          // 置直道标志 / Set straight flag
ELSE
    fSpeedLimit := SQRT(fLatAccMax / fAbsKappa);                // v = sqrt(a_lat/|κ|) / Curve-limited speed
    IF fSpeedLimit > fSpeedMax THEN
        fSpeedLimit := fSpeedMax;                               // 向车最大速度取小 / Clamp to max
    END_IF
END_IF
// 段 4：出口闸（非有限复核 + 非负复核）/ Outlet gate
IF (fSpeedLimit <> fSpeedLimit) OR (ABS(fSpeedLimit) >= 3.0E38) OR (fSpeedLimit < 0.0) THEN
    fSpeedLimit := 0.0;         // 复核失败回零速 / Fallback to zero speed
    bStraight := FALSE;         // 复核失败撤直道标志 / Clear straight flag
    uErrorId := 16#0002_9208;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_AgvSpeedLimitProfileCalc := fSpeedLimit;  // 返回值镜像限速 / Return mirrors limit
END_FUNCTION
