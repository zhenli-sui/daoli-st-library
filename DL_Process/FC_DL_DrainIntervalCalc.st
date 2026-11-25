(*
  ============================================================
  组件名 : FC_DL_DrainIntervalCalc
  分类   : DL_Process
  功能   : 自动排水间隔计算，由冷凝析水率与允许最大积水求排水周期并给出即时排水请求
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      排水间隔 = 允许最大积水 / 析水率 * 60，单位 min。
      间隔小于 10 min 表示积水速度已超出常规排放节奏，置 bDrainNow 请求连续排放。
      单次排水量仅用于校核排放能力是否覆盖间隔内的积水，不参与间隔公式。
  ============================================================
*)
FUNCTION FC_DL_DrainIntervalCalc : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rCondRate    : REAL; // 冷凝析水率 [L/h] / condensate generation rate [litre per hour]
    rDrainVol_L  : REAL; // 单次排水动作排放量 [L] / volume released by one drain action [litre]
    rMaxHold_L   : REAL; // 允许的最大积水量 [L] / maximum permitted accumulated water [litre]
END_VAR
VAR_OUTPUT
    rInterval_min : REAL; // 建议排水间隔 [min] / recommended drain interval [minute]
    rWaterPerInt_L : REAL; // 单个间隔内积水总量 [L] / accumulated water within one interval [litre]
    bDrainNow   : BOOL; // 即时排水请求：TRUE 表示间隔小于 10 min / immediate drain request, TRUE when the interval is below 10 minutes
    bCapOk      : BOOL; // 排放能力充足：TRUE 表示单次排放量不小于间隔内积水量 / capacity adequate, TRUE when one drain covers the water of one interval
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_MIN_PER_H : REAL := 60.0;  // 每小时分钟数 [min/h] / minutes per hour [minute per hour]
    DL_NOW_MIN  : REAL := 10.0;   // 即时排水间隔门限 [min] / threshold of the immediate drain interval [minute]
    DL_TOL_L    : REAL := 1.0E-6; // 排放能力比较容差 [L] / tolerance of the drain capacity comparison [litre]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置
    rInterval_min := 0.0;
    rWaterPerInt_L := 0.0;
    bDrainNow := FALSE;
    bCapOk := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rCondRate = rCondRate) AND (ABS(rCondRate) <= DL_R_MAX) AND (rDrainVol_L = rDrainVol_L) AND (ABS(rDrainVol_L) <= DL_R_MAX) AND (rMaxHold_L = rMaxHold_L) AND (ABS(rMaxHold_L) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：析水率严格为正，积水量与单次排放量不得为负
    IF (ABS(rCondRate) <= DL_EPS) OR (rCondRate < 0.0) THEN
        RETURN;
    END_IF;
    IF (rMaxHold_L < 0.0) OR (rDrainVol_L < 0.0) THEN
        RETURN;
    END_IF;
    // 段 5｜排水间隔
    rInterval_min := rMaxHold_L / rCondRate * DL_MIN_PER_H;
    // 段 6｜间隔内积水量
    rWaterPerInt_L := rCondRate * rInterval_min / DL_MIN_PER_H;
    // 段 7｜排放能力校核：单次排放量须覆盖一个间隔的积水
    IF rDrainVol_L >= (rWaterPerInt_L - DL_TOL_L) THEN
        bCapOk := TRUE;
    ELSE
        bCapOk := FALSE;
    END_IF;
    // 段 8｜即时排水请求
    IF rInterval_min < DL_NOW_MIN THEN
        bDrainNow := TRUE;
    ELSE
        bDrainNow := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_DrainIntervalCalc := bValid;
END_FUNCTION
