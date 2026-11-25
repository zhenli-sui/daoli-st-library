(*
  ============================================================
  组件名 : FC_DL_IdleRunRatioCalc
  分类   : DL_Process
  功能   : 空转率与浪费电量计算，由总运行时间与加载时间求空转占比及折算电耗
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      空转时间 = 总运行时间 - 加载时间；空转率 = 空转时间 / 总运行时间 * 100。
      浪费电量 = 空转功率 * 空转时间 / 3600，单位 kWh。
      加载时间超过总运行时间属数据矛盾，本组件判无效，不做负数截断掩盖问题。
  ============================================================
*)
FUNCTION FC_DL_IdleRunRatioCalc : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rRunTime_s  : REAL; // 总运行时间 [s] / total running time [second]
    rLoadTime_s : REAL; // 加载运行时间 [s] / loaded running time [second]
    rIdleKw     : REAL; // 空转状态功率 [kW] / idle state power [kilowatt]
END_VAR
VAR_OUTPUT
    rIdleTime_s : REAL; // 空转时间 [s] / idle time [second]
    rIdlePct    : REAL; // 空转率，限幅 0~100 [%] / idle ratio clamped to 0 to 100 [percent]
    rWastedKwh  : REAL; // 空转浪费电量 [kWh] / energy wasted while idling [kilowatt hour]
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_S_PER_H : REAL := 3600.0;  // 每小时秒数 [s/h] / seconds per hour [second per hour]
    DL_TOL_S   : REAL := 0.001;   // 时间比较容差 [s] / tolerance of the time comparison [second]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置
    rIdleTime_s := 0.0;
    rIdlePct := 0.0;
    rWastedKwh := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rRunTime_s = rRunTime_s) AND (ABS(rRunTime_s) <= DL_R_MAX) AND (rLoadTime_s = rLoadTime_s) AND (ABS(rLoadTime_s) <= DL_R_MAX) AND (rIdleKw = rIdleKw) AND (ABS(rIdleKw) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：总运行时间严格为正，加载时间与空转功率不得为负
    IF (ABS(rRunTime_s) <= DL_EPS) OR (rRunTime_s < DL_ZERO) THEN
        RETURN;
    END_IF;
    IF (rLoadTime_s < DL_ZERO) OR (rIdleKw < DL_ZERO) THEN
        RETURN;
    END_IF;
    // 段 5｜加载时间不得越过总运行时间
    IF rLoadTime_s > (rRunTime_s + DL_TOL_S) THEN
        RETURN;
    END_IF;
    // 段 6｜空转时间
    rIdleTime_s := rRunTime_s - rLoadTime_s;
    IF rIdleTime_s < DL_ZERO THEN
        rIdleTime_s := DL_ZERO;
    END_IF;
    // 段 7｜空转率与浪费电量
    rIdlePct := rIdleTime_s / rRunTime_s * DL_PCT;
    IF rIdlePct < DL_ZERO THEN
        rIdlePct := DL_ZERO;
    END_IF;
    IF rIdlePct > DL_PCT THEN
        rIdlePct := DL_PCT;
    END_IF;
    rWastedKwh := rIdleKw * rIdleTime_s / DL_S_PER_H;
    bValid := TRUE;
    FC_DL_IdleRunRatioCalc := bValid;
END_FUNCTION
