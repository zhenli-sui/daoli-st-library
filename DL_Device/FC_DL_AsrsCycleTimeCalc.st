(*
  DL Factory R83 | FC_DL_AsrsCycleTimeCalc
  功能：按梯形速度曲线分别算堆垛机行走与升降时间，取慢者加货叉时间得单循环。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_AsrsCycleTimeCalc : REAL
VAR_INPUT
    fTravelM   : REAL; // 巷道行走距离 [m] / Aisle travel distance [m]
    fTravelMps : REAL; // 行走最大速度 [m/s] / Travel maximum speed [m/s]
    fTravelAcc : REAL; // 行走加速度 [m/s²] / Travel acceleration [m/s^2]
    fLiftM     : REAL; // 升降行程 [m] / Lift stroke [m]
    fLiftMps   : REAL; // 升降最大速度 [m/s] / Lift maximum speed [m/s]
    fLiftAcc   : REAL; // 升降加速度 [m/s²] / Lift acceleration [m/s^2]
    fForkSec   : REAL; // 货叉单次伸缩时间 [s] / Fork stroke time [s]
END_VAR
VAR_OUTPUT
    fTravelS : REAL; // 行走段耗时 [s] / Travel leg time [s]
    fLiftS   : REAL; // 升降段耗时 [s] / Lift leg time [s]
    fCycleS  : REAL; // 单循环作业时间（两轴取大 + 货叉）[s] / Single cycle time [s]
    xValid   : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fCritTravelM : REAL; // 行走达速临界距离 [m] / Travel distance to reach max speed [m]
    fCritLiftM   : REAL; // 升降达速临界距离 [m] / Lift distance to reach max speed [m]
END_VAR
fTravelS := 0.0; fLiftS := 0.0; fCycleS := 0.0; xValid := FALSE;  // 出口预置（R256）
// 非有限拦截 + 量纲自检 + 速度/加速度零闸（R4/R20/R21）
IF NOT (fTravelM > -1.0E30 AND fTravelM < 1.0E30) OR NOT (fTravelMps > -1.0E30 AND fTravelMps < 1.0E30) OR NOT (fTravelAcc > -1.0E30 AND fTravelAcc < 1.0E30) OR NOT (fLiftM > -1.0E30 AND fLiftM < 1.0E30) OR NOT (fLiftMps > -1.0E30 AND fLiftMps < 1.0E30) OR NOT (fLiftAcc > -1.0E30 AND fLiftAcc < 1.0E30) OR NOT (fForkSec > -1.0E30 AND fForkSec < 1.0E30) OR fTravelM < 0.0 OR fLiftM < 0.0 OR fForkSec < 0.0 OR fTravelMps <= 0.0 OR fLiftMps <= 0.0 OR fTravelAcc <= 0.0 OR fLiftAcc <= 0.0 THEN
    FC_DL_AsrsCycleTimeCalc := -1.0; RETURN;   // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 行走段：临界距离 v²/a，超过则梯形曲线，否则三角曲线（t = 2√(d/a)）
fCritTravelM := (fTravelMps * fTravelMps) / fTravelAcc;   // 临界距离 [m] / Critical distance [m]
IF fTravelM >= fCritTravelM THEN
    fTravelS := fTravelM / fTravelMps + fTravelMps / fTravelAcc; // 梯形：d/v + v/a，量纲 s
ELSE
    fTravelS := 2.0 * SQRT(fTravelM / fTravelAcc);   // 三角：未达速，2√(d/a)，被除数已非负（R4）
END_IF
// 升降段：同一梯形/三角判据，参数完全独立
fCritLiftM := (fLiftMps * fLiftMps) / fLiftAcc;            // 临界距离 [m] / Critical distance [m]
IF fLiftM >= fCritLiftM THEN fLiftS := fLiftM / fLiftMps + fLiftMps / fLiftAcc; ELSE fLiftS := 2.0 * SQRT(fLiftM / fLiftAcc); END_IF  // 升降梯形/三角 [s]
// 单循环：两轴并行取较慢者，再串行加货叉伸缩（s + s = s）
IF fTravelS >= fLiftS THEN
    fCycleS := fTravelS + fForkSec; // 行走为瓶颈 [s] / Travel is the bottleneck
ELSE
    fCycleS := fLiftS + fForkSec;   // 升降为瓶颈 [s] / Lift is the bottleneck
END_IF
xValid := TRUE;                            // 链路有效 / Chain valid
FC_DL_AsrsCycleTimeCalc := fCycleS;        // 返回单循环时间 [s] / Return single cycle time [s]
END_FUNCTION
