(*
 * FC_DL_TrolleyAccelProfileCalc | C1 | DL_Motion
 * 功能：小车单段行程的梯形/三角形速度规划（加速时间、匀速时间、峰值速度）       单位：距离 [m]、速度 [m/s]、加速度 [m/s²]、时间 [s]
 * 工况边界：rDistM/rVmaxMps/rAccMps2 三者须 >0 且有限，否则 xValid=FALSE 且出口取 0；不处理 S 曲线加加速限幅，仅给出等效梯形；xReachable 表示输入自洽（正距离可达）
 * 代数值回代：d=10 m、v=2 m/s、a=0.5 m/s² → v²/a=8 <10 → 梯形，tAcc=4 s、dAcc=4 m、tCruise=(10-8)/2=1 s（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_TrolleyAccelProfileCalc : BOOL
VAR_INPUT
    rDistM    : REAL;                // 单段行程距离 | single move distance [m]
    rVmaxMps  : REAL;                // 最大速度限幅 | maximum speed limit [m/s]
    rAccMps2  : REAL;                // 加减速度 | acceleration and deceleration [m/s²]
END_VAR
VAR_OUTPUT
    rTAccS     : REAL;               // 单侧加速时间 | acceleration time per side [s]
    rTCruiseS  : REAL;               // 匀速段时间（三角形时为 0）| cruise time, zero for a triangular profile [s]
    rVPeakMps  : REAL;               // 峰值速度（三角形时低于 Vmax）| peak speed, below Vmax for a triangular profile [m/s]
    xTriangular: BOOL;               // 是否三角形（未达 Vmax）| TRUE when the profile is triangular
    xReachable : BOOL;               // 输入自洽且行程可达 | inputs are consistent and the move is reachable
    xValid     : BOOL;               // 输出有效 | outputs valid
END_VAR
VAR
    xFinDist : BOOL;                 // 距离有限性 | distance is finite
    xFinVmax : BOOL;                 // 速度有限性 | speed limit is finite
    xFinAcc  : BOOL;                 // 加速度有限性 | acceleration is finite
    rDistAccM : REAL;                // 加速段行程（单侧）| distance covered while accelerating on one side [m]
    rDistCritM: REAL;                // 达到 Vmax 所需总行程（加+减）| total distance needed to reach Vmax [m]
END_VAR

// 段1｜非有限闸（R19）
xFinDist := (rDistM = rDistM) AND ((rDistM - rDistM) = 0.0);
xFinVmax := (rVmaxMps = rVmaxMps) AND ((rVmaxMps - rVmaxMps) = 0.0);
xFinAcc := (rAccMps2 = rAccMps2) AND ((rAccMps2 - rAccMps2) = 0.0);
IF (NOT xFinDist) OR (NOT xFinVmax) OR (NOT xFinAcc) THEN
    rTAccS := 0.0;                   // 安全值：时间 0 | safe value, zero time
    rTCruiseS := 0.0;
    rVPeakMps := 0.0;                // 安全值：速度 0，下游不得起步 | safe value, no motion allowed
    xTriangular := FALSE;
    xReachable := FALSE;
    xValid := FALSE;
    FC_DL_TrolleyAccelProfileCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：三个输入必须为正（加速度入分母，先判后用）
IF (rDistM <= 0.0) OR (rVmaxMps <= 0.0) OR (rAccMps2 <= 0.0) THEN
    rTAccS := 0.0;
    rTCruiseS := 0.0;
    rVPeakMps := 0.0;
    xTriangular := FALSE;
    xReachable := FALSE;
    xValid := FALSE;
    FC_DL_TrolleyAccelProfileCalc := FALSE;
    RETURN;
END_IF

// 段3｜判型：2*(v²/(2a)) > d 即全程来不及升到 Vmax，走三角形
rDistAccM := (rVmaxMps * rVmaxMps) / (2.0 * rAccMps2);   // 单侧加速行程 | one-side acceleration distance [m]
rDistCritM := 2.0 * rDistAccM;                            // 加+减总行程 | acceleration plus deceleration distance [m]
IF rDistCritM > rDistM THEN
    xTriangular := TRUE;                                  // 三角形：峰值速度取 SQRT(a*d) | triangular, peak speed is SQRT(a*d)
    rVPeakMps := SQRT(rAccMps2 * rDistM);
    rTAccS := rVPeakMps / rAccMps2;                       // 分母已由段2保证 >0 | denominator proven positive in segment 2
    rTCruiseS := 0.0;                                     // 无匀速段 | no cruise segment
ELSE
    xTriangular := FALSE;                                 // 梯形：峰值速度等于 Vmax | trapezoidal, peak speed equals Vmax
    rVPeakMps := rVmaxMps;
    rTAccS := rVmaxMps / rAccMps2;                        // 单侧加速时间 | acceleration time per side [s]
    rTCruiseS := (rDistM - rDistCritM) / rVmaxMps;        // 匀速段行程除以 Vmax | cruise distance divided by Vmax [s]
END_IF

// 段4｜出口：行程可达 = 输入有效（本函数只做运动学自洽性判定）
xReachable := TRUE;
xValid := TRUE;
FC_DL_TrolleyAccelProfileCalc := TRUE;
END_FUNCTION
