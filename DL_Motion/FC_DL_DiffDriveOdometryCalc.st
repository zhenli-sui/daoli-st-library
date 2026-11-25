// FC_DL_DiffDriveOdometryCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 差速轮单周期里程计：ds = (dR+dL)/2，dθ = (dR−dL)/B，
        dx = ds·COS(θ + dθ/2)，dy = ds·SIN(θ + dθ/2)，θnew = θ + dθ 归一化到 (−π, π]。
  邻件/码位: 为路径跟踪链的定位侧件（只产生位姿增量，不含跟踪律）；
             16#0002_9203 = 域外、非有限或归一化不收敛拒收。
*)
FUNCTION FC_DL_DiffDriveOdometryCalc : REAL
VAR_INPUT
    fDeltaLeft  : REAL := 0.0;      // 左轮增量位移 [m]，前进正 / Left incremental travel [m]
    fDeltaRight : REAL := 0.0;      // 右轮增量位移 [m]，前进正 / Right incremental travel [m]
    fWheelBase  : REAL := 0.5;      // 轮距 B [m]，域 > 1e-6 / Wheel base [m]
    fThetaPrev  : REAL := 0.0;      // 上周期航向 θ [rad] / Previous heading [rad]
END_VAR
VAR_OUTPUT
    fDeltaX   : REAL;               // 本周期 X 增量 [m] / Incremental X displacement [m]
    fDeltaY   : REAL;               // 本周期 Y 增量 [m] / Incremental Y displacement [m]
    fThetaNew : REAL;               // 归一化新航向 (−π, π] [rad] / Normalized heading [rad]
    fDeltaS   : REAL;               // 本周期弧长增量 [m] / Incremental arc length [m]
    bValid    : BOOL;               // 结果有效回执 [-] / Result validity receipt
    uErrorId  : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fPi    : REAL := 3.14159265358979;  // 圆周率常量 [rad] / Pi constant [rad]
    fTwoPi : REAL := 6.28318530717959;  // 二倍圆周率 [rad] / Two pi constant [rad]
    fDTheta : REAL := 0.0;          // 本周期航向增量 dθ [rad] / Heading increment [rad]
    iGuard : INT := 0;              // 归一化循环守卫计数 [次] / Normalization loop guard
END_VAR
// 段 0：全路径出口安全缺省（航向回绝对零，不回灌上拍）/ Safe defaults, heading to absolute zero
fDeltaX := 0.0;                     // X 增量缺省零 / X increment default zero
fDeltaY := 0.0;                     // Y 增量缺省零 / Y increment default zero
fDeltaS := 0.0;                     // 弧长增量缺省零 / Arc increment default zero
fThetaNew := 0.0;                   // 航向缺省绝对零 / Heading default absolute zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_DiffDriveOdometryCalc := 0.0; // 返回值缺省零（镜像弧长）/ Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fDeltaLeft <> fDeltaLeft) OR (fDeltaRight <> fDeltaRight)
   OR (fWheelBase <> fWheelBase) OR (fThetaPrev <> fThetaPrev)
   OR (ABS(fDeltaLeft) >= 3.0E38) OR (ABS(fDeltaRight) >= 3.0E38)
   OR (ABS(fWheelBase) >= 3.0E38) OR (ABS(fThetaPrev) >= 3.0E38) THEN
    uErrorId := 16#0002_9203;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（轮距为正，dθ 分母非零）/ Domain gate, R4 divide-by-zero guard
IF fWheelBase <= 1.0E-6 THEN
    uErrorId := 16#0002_9203;   // 轮距非正，航向不可解 / Non-positive wheel base
    RETURN;
END_IF
// 段 3：主计算（中点积分 + 航向归一化）/ Main computation with heading normalization
fDeltaS := (fDeltaRight + fDeltaLeft) / 2.0;                    // 弧长增量 / Arc increment
fDTheta := (fDeltaRight - fDeltaLeft) / fWheelBase;             // 航向增量 / Heading increment
fDeltaX := fDeltaS * COS(fThetaPrev + fDTheta / 2.0);           // X 增量（半角）/ X increment half-angle
fDeltaY := fDeltaS * SIN(fThetaPrev + fDTheta / 2.0);           // Y 增量（半角）/ Y increment half-angle
fThetaNew := fThetaPrev + fDTheta;                              // 未归一化航向 / Raw new heading
iGuard := 0;                                                    // 守卫计数清零 / Guard counter clear
WHILE (fThetaNew > fPi) AND (iGuard < 64) DO                    // 超上界折叠 / Fold above upper bound
    fThetaNew := fThetaNew - fTwoPi;                            // 减一整周 / Subtract one turn
    iGuard := iGuard + 1;                                       // 守卫自增 / Guard increment
END_WHILE
WHILE (fThetaNew <= -fPi) AND (iGuard < 64) DO                  // 超下界折叠 / Fold below lower bound
    fThetaNew := fThetaNew + fTwoPi;                            // 加一整周 / Add one turn
    iGuard := iGuard + 1;                                       // 守卫自增 / Guard increment
END_WHILE
// 段 4：出口闸（非有限复核 + 归一化收敛复核）/ Outlet gate
IF (fDeltaX <> fDeltaX) OR (fDeltaY <> fDeltaY) OR (fDeltaS <> fDeltaS) OR (fThetaNew <> fThetaNew)
   OR (ABS(fDeltaX) >= 3.0E38) OR (ABS(fDeltaY) >= 3.0E38)
   OR (ABS(fDeltaS) >= 3.0E38) OR (ABS(fThetaNew) >= 3.0E38) THEN
    fDeltaX := 0.0;             // 复核失败回缺省 / Fallback on recheck failure
    fDeltaY := 0.0;             // 复核失败回缺省 / Fallback on recheck failure
    fDeltaS := 0.0;             // 复核失败回缺省 / Fallback on recheck failure
    fThetaNew := 0.0;           // 复核失败回绝对零 / Heading falls back to absolute zero
    uErrorId := 16#0002_9203;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF iGuard >= 64 THEN
    uErrorId := 16#0002_9203;   // 归一化未收敛（航向超 64 周）/ Normalization not converged
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_DiffDriveOdometryCalc := fDeltaS;     // 返回值镜像弧长增量 / Return mirrors arc increment
END_FUNCTION
