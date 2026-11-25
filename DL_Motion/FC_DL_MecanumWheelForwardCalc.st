// FC_DL_MecanumWheelForwardCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Motion，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 麦克纳姆轮正运动学 k = a + b：vx = (vFL+vFR+vRL+vRR)/4，
        vy = (−vFL+vFR+vRL−vRR)/4，ω = (−vFL+vFR−vRL+vRR)/(4k)；k 为唯一分母。
  邻件/码位: 与 FC_DL_MecanumWheelInverseCalc 构成正/逆一对（轮→底盘侧，供轮速实测校核）；
             16#0002_9202 = 域外或非有限拒收。
*)
FUNCTION FC_DL_MecanumWheelForwardCalc : REAL
VAR_INPUT
    fVelFL   : REAL := 0.0;     // 左前轮线速度 [m/s] / Front-left speed [m/s]
    fVelFR   : REAL := 0.0;     // 右前轮线速度 [m/s] / Front-right speed [m/s]
    fVelRL   : REAL := 0.0;     // 左后轮线速度 [m/s] / Rear-left speed [m/s]
    fVelRR   : REAL := 0.0;     // 右后轮线速度 [m/s] / Rear-right speed [m/s]
    fHalfLen : REAL := 0.3;     // 半轴距 a [m]，纵向半跨 / Half wheelbase [m]
    fHalfWid : REAL := 0.25;    // 半轮距 b [m]，横向半跨 / Half track [m]
END_VAR
VAR_OUTPUT
    fVx      : REAL;            // 车体纵向速度 [m/s]，前正 / Longitudinal velocity [m/s]
    fVy      : REAL;            // 车体横向速度 [m/s]，左正 / Lateral velocity [m/s]
    fOmega   : REAL;            // 车体自转角速度 [rad/s] / Body yaw rate [rad/s]
    bValid   : BOOL;            // 结果有效回执 [-] / Result validity receipt
    uErrorId : UDINT;           // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fK : REAL := 0.0;           // 合成力臂 k = a + b [m] / Combined lever arm [m]
END_VAR
// 段 0：全路径出口安全缺省（三出口一律缺省）/ Safe defaults on all outlets
fVx := 0.0;                     // 纵向速度缺省零 / Longitudinal default zero
fVy := 0.0;                     // 横向速度缺省零 / Lateral default zero
fOmega := 0.0;                  // 角速度缺省零 / Yaw rate default zero
bValid := FALSE;                // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;            // 事件码预清 / Event code preset clear
FC_DL_MecanumWheelForwardCalc := 0.0;   // 返回值缺省零（镜像纵向速度）/ Return default zero
// 段 1：非有限闸（四轮速 + 两几何量全枚举）/ Non-finite gate over all inputs
IF (fVelFL <> fVelFL) OR (fVelFR <> fVelFR) OR (fVelRL <> fVelRL) OR (fVelRR <> fVelRR)
   OR (fHalfLen <> fHalfLen) OR (fHalfWid <> fHalfWid)
   OR (ABS(fVelFL) >= 3.0E38) OR (ABS(fVelFR) >= 3.0E38) OR (ABS(fVelRL) >= 3.0E38)
   OR (ABS(fVelRR) >= 3.0E38) OR (ABS(fHalfLen) >= 3.0E38) OR (ABS(fHalfWid) >= 3.0E38) THEN
    uErrorId := 16#0002_9202;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（k 为正，ω 分母非零）/ Domain gate, R4 divide-by-zero guard
fK := fHalfLen + fHalfWid;      // 合成力臂 / Combined lever arm
IF fK <= 1.0E-6 THEN
    uErrorId := 16#0002_9202;   // 力臂非正，转向不可解 / Non-positive arm, yaw unsolvable
    RETURN;
END_IF
// 段 3：主计算（四轮线性组合）/ Main computation
fVx := (fVelFL + fVelFR + fVelRL + fVelRR) / 4.0;                   // 纵向速度均值 / Longitudinal mean
fVy := (-fVelFL + fVelFR + fVelRL - fVelRR) / 4.0;                  // 横向带符号组合 / Lateral signed sum
fOmega := (-fVelFL + fVelFR - fVelRL + fVelRR) / (4.0 * fK);        // 角速度除以力臂 / Yaw over arm
// 段 4：出口闸（三输出各做非有限复核）/ Outlet gate
IF (fVx <> fVx) OR (fVy <> fVy) OR (fOmega <> fOmega)
   OR (ABS(fVx) >= 3.0E38) OR (ABS(fVy) >= 3.0E38) OR (ABS(fOmega) >= 3.0E38) THEN
    fVx := 0.0;                 // 复核失败回缺省 / Fallback on recheck failure
    fVy := 0.0;                 // 复核失败回缺省 / Fallback on recheck failure
    fOmega := 0.0;              // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9202;   // 出口非有限拒收 / Output non-finite reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_MecanumWheelForwardCalc := fVx;   // 返回值镜像纵向速度 / Return mirrors longitudinal speed
END_FUNCTION
