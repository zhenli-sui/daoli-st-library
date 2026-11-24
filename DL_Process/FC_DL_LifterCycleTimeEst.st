(*
  ============================================================
  组件名 : FC_DL_LifterCycleTimeEst
  分类   : DL_Process
  功能   : 提升机单循环节拍估算，由层高与层数求往复升降时间并叠加开关门与货叉时间
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      单循环 = 2*(层高*(层数-1)/提升速度) + 2*开关门时间 + 2*货叉时间，即一取一放完整往复。
      层数要求 >= 2，层数 1 时无层间位移，节拍模型不成立，直接判无效。
      rCap 由 3600/rCycle 折算，rCycle 非正时不做除法，仅保留时间输出并判无效。
  ============================================================
*)
FUNCTION FC_DL_LifterCycleTimeEst : BOOL
VAR_INPUT
    bEnable   : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr      : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rLiftH    : REAL; // 层间高度 [m] / height between two adjacent levels [m]
    iLayers   : INT;  // 货架总层数 [层] / total number of levels [level]
    rVlift    : REAL; // 提升额定速度 [m/s] / rated lifting speed [metre per second]
    rTdoor    : REAL; // 单次开关门时间 [s] / door open close time for one operation [s]
    rTfork    : REAL; // 单次货叉伸缩时间 [s] / fork extend retract time for one operation [s]
END_VAR
VAR_OUTPUT
    rCycle_s  : REAL; // 单循环节拍时间 [s] / single cycle time [s]
    rCap      : REAL; // 折算产能 [件/小时] / equivalent capacity [piece per hour]
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_SEC_H   : REAL := 3600.0;  // 每小时秒数 [s/h] / seconds per hour [second per hour]
    DL_TWO     : REAL := 2.0;     // 往复行程倍数 [无量纲] / round trip multiplier [dimensionless]
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 输入有限性判定汇总 / aggregated finiteness verdict of the inputs
    _rTravel : REAL := 0.0;   // 单程升降时间 [s] / one way travel time [s]
    _rLayers : REAL := 0.0;   // 层数折算实数 [无量纲] / level count cast to real [dimensionless]
END_VAR

    // 段 1｜出口预置
    rCycle_s := 0.0;
    rCap := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rLiftH = rLiftH) AND (ABS(rLiftH) <= DL_R_MAX) AND (rVlift = rVlift) AND (ABS(rVlift) <= DL_R_MAX) AND (rTdoor = rTdoor) AND (ABS(rTdoor) <= DL_R_MAX) AND (rTfork = rTfork) AND (ABS(rTfork) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：速度必须严格为正，层数必须 >= 2，时间与层高不得为负
    IF ABS(rVlift) <= DL_EPS THEN
        RETURN;
    END_IF;
    IF iLayers < 2 THEN
        RETURN;
    END_IF;
    IF (rLiftH < 0.0) OR (rVlift < 0.0) OR (rTdoor < 0.0) OR (rTfork < 0.0) THEN
        RETURN;
    END_IF;
    // 段 5｜单程升降时间：层数减一得到层间跨距个数
    _rLayers := INT_TO_REAL(iLayers);
    _rTravel := rLiftH * (_rLayers - 1.0) / rVlift;
    // 段 6｜单循环时间：升降往复加两次开关门加两次货叉
    rCycle_s := DL_TWO * _rTravel + DL_TWO * rTdoor + DL_TWO * rTfork;
    // 段 7｜产能折算：必须再次确认周期严格为正才允许做除法
    IF rCycle_s > DL_EPS THEN
        rCap := DL_SEC_H / rCycle_s;
    ELSE
        rCap := 0.0;
        bValid := FALSE;
        FC_DL_LifterCycleTimeEst := bValid;
        RETURN;
    END_IF;
    bValid := TRUE;
    FC_DL_LifterCycleTimeEst := bValid;
END_FUNCTION
