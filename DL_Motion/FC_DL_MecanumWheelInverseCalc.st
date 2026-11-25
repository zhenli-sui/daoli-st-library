// FC_DL_MecanumWheelInverseCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 麦克纳姆轮逆运动学 k = a + b：vFL = vx − vy − ωk，vFR = vx + vy + ωk，
        vRL = vx + vy − ωk，vRR = vx − vy + ωk；fOmegaTotal 为四轮回算角速度自检。
  邻件/码位: 与 FC_DL_MecanumWheelForwardCalc 构成逆/正一对；16#0002_9201 = 域外或非有限拒收。
*)
FUNCTION FC_DL_MecanumWheelInverseCalc : REAL
VAR_INPUT
    fVx      : REAL := 0.0;     // 车体纵向速度 vx [m/s]，前正 / Longitudinal velocity [m/s]
    fVy      : REAL := 0.0;     // 车体横向速度 vy [m/s]，左正 / Lateral velocity [m/s]
    fOmega   : REAL := 0.0;     // 自转角速度 ω [rad/s]，逆时针正 / Yaw rate [rad/s]
    fRadius  : REAL := 0.05;    // 轮半径 [m]，域 >= 1e-3 / Wheel radius [m]
    fHalfLen : REAL := 0.3;     // 半轴距 a [m]，纵向半跨 / Half wheelbase [m]
    fHalfWid : REAL := 0.25;    // 半轮距 b [m]，横向半跨 / Half track [m]
END_VAR
VAR_OUTPUT
    fVelFL      : REAL;         // 左前轮线速度 [m/s] / Front-left speed [m/s]
    fVelFR      : REAL;         // 右前轮线速度 [m/s] / Front-right speed [m/s]
    fVelRL      : REAL;         // 左后轮线速度 [m/s] / Rear-left speed [m/s]
    fVelRR      : REAL;         // 右后轮线速度 [m/s] / Rear-right speed [m/s]
    fOmegaTotal : REAL;         // 四轮回算角速度 [rad/s] / Recomposed yaw rate [rad/s]
    bOverSpeed  : BOOL;         // 超速告警，仅告警不否决 [-] / Over-speed warning only
    bValid      : BOOL;         // 结果有效回执 [-] / Result validity receipt
    uErrorId    : UDINT;        // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fK : REAL := 0.0;           // 合成力臂 k = a + b [m] / Combined lever arm [m]
END_VAR
// 段 0：全路径出口安全缺省（不回灌入参）/ Safe defaults, inputs never echoed back
fVelFL := 0.0;                  // 左前轮速缺省零 / Front-left default zero
fVelFR := 0.0;                  // 右前轮速缺省零 / Front-right default zero
fVelRL := 0.0;                  // 左后轮速缺省零 / Rear-left default zero
fVelRR := 0.0;                  // 右后轮速缺省零 / Rear-right default zero
fOmegaTotal := 0.0;             // 回算角速度缺省零 / Recomposed yaw default zero
bOverSpeed := FALSE;            // 超速告警预清 / Over-speed preset clear
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_MecanumWheelInverseCalc := 0.0;   // 返回值缺省零（镜像左前轮速）/ Return default zero
// 段 1：非有限闸（六入参全枚举）/ Non-finite gate over all six inputs
IF (fVx <> fVx) OR (fVy <> fVy) OR (fOmega <> fOmega) OR (fRadius <> fRadius)
   OR (fHalfLen <> fHalfLen) OR (fHalfWid <> fHalfWid)
   OR (ABS(fVx) >= 3.0E38) OR (ABS(fVy) >= 3.0E38) OR (ABS(fOmega) >= 3.0E38)
   OR (ABS(fRadius) >= 3.0E38) OR (ABS(fHalfLen) >= 3.0E38) OR (ABS(fHalfWid) >= 3.0E38) THEN
    uErrorId := 16#0002_9201;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（半径下界 + 力臂为正，防除零）/ Domain gate, R4 divide-by-zero guard
fK := fHalfLen + fHalfWid;      // 合成力臂 / Combined lever arm
IF (fRadius < 1.0E-3) OR (fK <= 1.0E-6) THEN
    uErrorId := 16#0002_9201;   // 半径近零或力臂非正（几何不可解）/ Domain violation
    RETURN;
END_IF
// 段 3：主计算（四轮逆解，ωk 为旋转切向分量）/ Main computation
fVelFL := fVx - fVy - fOmega * fK;                                  // 左前轮 / Front-left wheel
fVelFR := fVx + fVy + fOmega * fK;                                  // 右前轮 / Front-right wheel
fVelRL := fVx + fVy - fOmega * fK;                                  // 左后轮 / Rear-left wheel
fVelRR := fVx - fVy + fOmega * fK;                                  // 右后轮 / Rear-right wheel
fOmegaTotal := (fVelFR + fVelRL - fVelFL - fVelRR) / (4.0 * fK);    // 四轮回算角速度自检 / Recomposed yaw
// 段 4：出口闸（非有限复核 + 超速告警）/ Outlet gate
IF (fVelFL <> fVelFL) OR (fVelFR <> fVelFR) OR (fVelRL <> fVelRL) OR (fVelRR <> fVelRR)
   OR (fOmegaTotal <> fOmegaTotal) OR (ABS(fOmegaTotal) >= 3.0E38) THEN
    fVelFL := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    fVelFR := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    fVelRL := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    fVelRR := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    fOmegaTotal := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9201;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
IF (ABS(fVelFL) > 3.0) OR (ABS(fVelFR) > 3.0) OR (ABS(fVelRL) > 3.0) OR (ABS(fVelRR) > 3.0) THEN
    bOverSpeed := TRUE;         // 超速告警，仅标记不否决 / Over-speed warning, no veto
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_MecanumWheelInverseCalc := fVelFL;    // 返回值镜像左前轮速 / Return mirrors front-left
END_FUNCTION
