(*
 * FC_DL_CraneCycleTimeEstimate | C2 | DL_Algo
 * 功能：单箱作业循环时间估算（起升 / 小车 / 大车三轴 + 固定辅助时间）       单位：距离 [m]、速度 [m/s]、加速度 [m/s²]、时间 [s]
 * 工况边界：各轴速度与加速度须 >0 且有限；某轴距离 ≤0 视为该轴不动作，时间计 0；含加速与减速的对称梯形近似，不含防摇等待与人工对箱时间（由 rFixedS 覆盖）
 * 代数值回代：起升 20 m/1.2+1.2/0.5=19.07 s；小车 30/2.5+2.5/0.5=17.0 s；大车 0 s；总=19.07+17.0+0+25=61.07 s（spec 记 19.1/17.0/0/61.1 s，一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_CraneCycleTimeEstimate : BOOL
VAR_INPUT
    rHoistDistM   : REAL := 20.0;    // 起升行程 | hoist travel [m]
    rTrolleyDistM : REAL := 30.0;    // 小车行程 | trolley travel [m]
    rGantryDistM  : REAL := 0.0;     // 大车行程（单箱作业常为 0）| gantry travel, usually zero per box [m]
    rVHoist       : REAL := 1.2;     // 起升额定速度 | hoist rated speed [m/s]
    rVTrolley     : REAL := 2.5;     // 小车额定速度 | trolley rated speed [m/s]
    rVGantry      : REAL := 3.0;     // 大车额定速度 | gantry rated speed [m/s]
    rAcc          : REAL := 0.5;     // 统一加减速度 | common acceleration and deceleration [m/s²]
    rFixedS       : REAL := 25.0;    // 固定辅助时间（对箱、开闭锁等）| fixed handling time [s]
END_VAR
VAR_OUTPUT
    rHoistS   : REAL;                // 起升轴时间 | hoist axis time [s]
    rTrolleyS : REAL;                // 小车轴时间 | trolley axis time [s]
    rGantryS  : REAL;                // 大车轴时间 | gantry axis time [s]
    rCycleS   : REAL;                // 循环总时间 | total cycle time [s]
    xValid    : BOOL;                // 输出有效 | outputs valid
END_VAR
VAR
    xFinH     : BOOL;                // 起升行程有限性 | hoist travel is finite
    xFinT     : BOOL;                // 小行程有限性 | trolley travel is finite
    xFinG     : BOOL;                // 大车行程有限性 | gantry travel is finite
    xFinVh    : BOOL;                // 起升速度有限性 | hoist speed is finite
    xFinVt    : BOOL;                // 小车速度有限性 | trolley speed is finite
    xFinVg    : BOOL;                // 大车速度有限性 | gantry speed is finite
    xFinA     : BOOL;                // 加速度有限性 | acceleration is finite
    xFinFixed : BOOL;                // 固定时间有限性 | fixed time is finite
    rCritH    : REAL;                // 起升达到额定速度所需行程 | travel needed to reach the hoist rated speed [m]
    rCritT    : REAL;                // 小车达到额定速度所需行程 | travel needed to reach the trolley rated speed [m]
    rCritG    : REAL;                // 大车达到额定速度所需行程 | travel needed to reach the gantry rated speed [m]
END_VAR

// 段1｜非有限闸（R19）
xFinH := (rHoistDistM = rHoistDistM) AND ((rHoistDistM - rHoistDistM) = 0.0);
xFinT := (rTrolleyDistM = rTrolleyDistM) AND ((rTrolleyDistM - rTrolleyDistM) = 0.0);
xFinG := (rGantryDistM = rGantryDistM) AND ((rGantryDistM - rGantryDistM) = 0.0);
xFinVh := (rVHoist = rVHoist) AND ((rVHoist - rVHoist) = 0.0);
xFinVt := (rVTrolley = rVTrolley) AND ((rVTrolley - rVTrolley) = 0.0);
xFinVg := (rVGantry = rVGantry) AND ((rVGantry - rVGantry) = 0.0);
xFinA := (rAcc = rAcc) AND ((rAcc - rAcc) = 0.0);
xFinFixed := (rFixedS = rFixedS) AND ((rFixedS - rFixedS) = 0.0);
IF (NOT xFinH) OR (NOT xFinT) OR (NOT xFinG) OR (NOT xFinVh) OR (NOT xFinVt)
   OR (NOT xFinVg) OR (NOT xFinA) OR (NOT xFinFixed) THEN
    rHoistS := 0.0;                  // 安全值：时间全 0 | safe value, all zero
    rTrolleyS := 0.0;
    rGantryS := 0.0;
    rCycleS := 0.0;
    xValid := FALSE;
    FC_DL_CraneCycleTimeEstimate := FALSE;
    RETURN;
END_IF

// 段2｜域闸：速度与加速度必须为正（速度在分母）；固定时间不得为负
IF (rVHoist <= 0.0) OR (rVTrolley <= 0.0) OR (rVGantry <= 0.0)
   OR (rAcc <= 0.0) OR (rFixedS < 0.0) THEN
    rHoistS := 0.0;
    rTrolleyS := 0.0;
    rGantryS := 0.0;
    rCycleS := 0.0;
    xValid := FALSE;
    FC_DL_CraneCycleTimeEstimate := FALSE;
    RETURN;
END_IF

// 段3｜起升轴：d ≥ v²/a 走梯形 t=d/v+v/a，否则三角形 t=2·SQRT(d/a)
rCritH := (rVHoist * rVHoist) / rAcc;
IF rHoistDistM <= 0.0 THEN
    rHoistS := 0.0;                                          // 该轴不动作 | axis not moving
ELSIF rHoistDistM >= rCritH THEN
    rHoistS := rHoistDistM / rVHoist + rVHoist / rAcc;
ELSE
    rHoistS := 2.0 * SQRT(rHoistDistM / rAcc);
END_IF

// 段4｜小车轴
rCritT := (rVTrolley * rVTrolley) / rAcc;
IF rTrolleyDistM <= 0.0 THEN
    rTrolleyS := 0.0;
ELSIF rTrolleyDistM >= rCritT THEN
    rTrolleyS := rTrolleyDistM / rVTrolley + rVTrolley / rAcc;
ELSE
    rTrolleyS := 2.0 * SQRT(rTrolleyDistM / rAcc);
END_IF

// 段5｜大车轴
rCritG := (rVGantry * rVGantry) / rAcc;
IF rGantryDistM <= 0.0 THEN
    rGantryS := 0.0;
ELSIF rGantryDistM >= rCritG THEN
    rGantryS := rGantryDistM / rVGantry + rVGantry / rAcc;
ELSE
    rGantryS := 2.0 * SQRT(rGantryDistM / rAcc);
END_IF

// 段6｜总时间与出口
rCycleS := rHoistS + rTrolleyS + rGantryS + rFixedS;
xValid := TRUE;
FC_DL_CraneCycleTimeEstimate := TRUE;
END_FUNCTION
