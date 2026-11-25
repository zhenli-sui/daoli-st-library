// FC_DL_PurePursuitCurvatureCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 纯跟踪曲率律 Ld = MAX(fLookAhead, fMinLook)，alpha = ATAN2(y, x) 以
        ATAN(y/x) + 四象限修正实现（规避方言 ATAN2），κ = 2·SIN(alpha)/Ld。
  邻件/码位: 与 FC_DL_StanleySteerAngleCalc 同为跟踪律（预瞄点几何 vs 偏差反馈）；
             16#0002_9204 = 非有限、预瞄近零或目标点重合拒收。
*)
FUNCTION FC_DL_PurePursuitCurvatureCalc : REAL
VAR_INPUT
    fTargetX   : REAL := 1.0;       // 预瞄点车体坐标 X [m]，前正 / Look-ahead X [m]
    fTargetY   : REAL := 0.0;       // 预瞄点车体坐标 Y [m]，左正 / Look-ahead Y [m]
    fLookAhead : REAL := 1.0;       // 预瞄距离 [m]，域 > 0 / Look-ahead distance [m]
    fMinLook   : REAL := 0.3;       // 最小预瞄距离 [m] / Minimum look-ahead [m]
END_VAR
VAR_OUTPUT
    fCurvature : REAL;              // 期望曲率 κ [1/m]，左转为正 / Desired curvature [1/m]
    fAlpha     : REAL;              // 预瞄角 alpha [rad]，左转为正 / Look-ahead angle [rad]
    bValid     : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fPi     : REAL := 3.14159265358979; // 圆周率常量 [rad] / Pi constant [rad]
    fHalfPi : REAL := 1.5707963267949;  // 半圆周率 [rad] / Half pi constant [rad]
    fLd     : REAL := 0.0;              // 生效预瞄距离 [m] / Effective look-ahead [m]
END_VAR
// 段 0：全路径出口安全缺省（曲率零 = 直行）/ Safe defaults, zero curvature means straight
fCurvature := 0.0;              // 曲率缺省零 / Curvature default zero
fAlpha := 0.0;                  // 预瞄角缺省零 / Alpha default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_PurePursuitCurvatureCalc := 0.0;  // 返回值缺省零 / Return default zero
// 段 1：非有限闸（四入参全枚举）/ Non-finite gate over all inputs
IF (fTargetX <> fTargetX) OR (fTargetY <> fTargetY)
   OR (fLookAhead <> fLookAhead) OR (fMinLook <> fMinLook)
   OR (ABS(fTargetX) >= 3.0E38) OR (ABS(fTargetY) >= 3.0E38)
   OR (ABS(fLookAhead) >= 3.0E38) OR (ABS(fMinLook) >= 3.0E38) THEN
    uErrorId := 16#0002_9204;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（预瞄取大后仍须为正 + 目标点不与原点重合）/ Domain gate
fLd := fLookAhead;                                              // 先取预瞄距离 / Take look-ahead first
IF fMinLook > fLd THEN
    fLd := fMinLook;                                            // 提升到最小预瞄 / Raise to minimum
END_IF
IF (fLd <= 1.0E-3) OR ((ABS(fTargetX) + ABS(fTargetY)) < 1.0E-6) THEN
    uErrorId := 16#0002_9204;   // 预瞄近零或目标点重合原点 / Degenerate look-ahead or target
    RETURN;
END_IF
// 段 3：主计算（ATAN + 四象限修正替代 ATAN2）/ Main computation
IF ABS(fTargetX) < 1.0E-9 THEN                                  // X 近零需定纵轴 / Axis branch
    IF fTargetY >= 0.0 THEN
        fAlpha := fHalfPi;                                      // 正纵轴 / Positive vertical axis
    ELSE
        fAlpha := -fHalfPi;                                     // 负纵轴 / Negative vertical axis
    END_IF
ELSE
    fAlpha := ATAN(fTargetY / fTargetX);                        // 主值分支 / Principal branch
    IF fTargetX < 0.0 THEN                                      // 左半平面补 π / Left half-plane fix
        IF fTargetY >= 0.0 THEN
            fAlpha := fAlpha + fPi;                             // 第二象限 / Second quadrant
        ELSE
            fAlpha := fAlpha - fPi;                             // 第三象限 / Third quadrant
        END_IF
    END_IF
END_IF
fCurvature := 2.0 * SIN(fAlpha) / fLd;                          // κ = 2·sin(alpha)/Ld / Curvature law
// 段 4：出口闸（双输出非有限复核）/ Outlet gate
IF (fCurvature <> fCurvature) OR (fAlpha <> fAlpha)
   OR (ABS(fCurvature) >= 3.0E38) OR (ABS(fAlpha) >= 3.0E38) THEN
    fCurvature := 0.0;          // 复核失败回缺省 / Fallback on recheck failure
    fAlpha := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9204;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PurePursuitCurvatureCalc := fCurvature;   // 返回值镜像曲率 / Return mirrors curvature
END_FUNCTION
