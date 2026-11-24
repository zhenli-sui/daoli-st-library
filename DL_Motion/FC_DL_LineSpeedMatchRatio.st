(*
  ============================================================
  组件名 : FC_DL_LineSpeedMatchRatio
  分类   : DL_Motion
  功能   : 主从线速匹配校验，由主从线速求实际速比并与设定速比比较给出偏差与匹配位
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      实际速比 = 从线速度 / 主线速度；偏差 = (实际速比 - 设定速比) / 设定速比 * 100。
      偏差绝对值不超过 2% 判匹配；主线静止时速比无定义，直接判无效而不是输出零速比。
  ============================================================
*)
FUNCTION FC_DL_LineSpeedMatchRatio : BOOL
VAR_INPUT
    bEnable    : BOOL; // 使能：TRUE 时校验 / Enable: TRUE to check
    bErr       : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rMasterMpm : REAL; // 主线线速度 [m/min] / master line speed [metre per minute]
    rSlaveMpm  : REAL; // 从线线速度 [m/min] / slave line speed [metre per minute]
    rRatioSet  : REAL; // 设定速比，从线相对主线 [无量纲] / set speed ratio of slave over master [dimensionless]
END_VAR
VAR_OUTPUT
    rRatioAct : REAL; // 实际速比 [无量纲] / actual speed ratio [dimensionless]
    rDevPct   : REAL; // 速比相对偏差 [%] / relative speed ratio deviation [percent]
    bMatch    : BOOL; // 匹配：TRUE 表示偏差绝对值不超过 2% / matched, TRUE when the absolute deviation is within 2 percent
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_TOL_PCT : REAL := 2.0;     // 速比匹配允许偏差 [%] / permitted ratio deviation for a match [percent]
    DL_RATIO_MAX : REAL := 100.0; // 速比合理上限 [无量纲] / sanity upper bound of the speed ratio [dimensionless]
    DL_SPEED_MAX : REAL := 10000.0; // 线速度合理上限 [m/min] / sanity upper bound of the line speed [metre per minute]
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rAbsDev : REAL := 0.0;  // 偏差绝对值 [%] / absolute deviation [percent]
END_VAR

    // 段 1｜出口预置
    rRatioAct := 0.0;
    rDevPct := 0.0;
    bMatch := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rMasterMpm = rMasterMpm) AND (ABS(rMasterMpm) <= DL_R_MAX) AND (rSlaveMpm = rSlaveMpm) AND (ABS(rSlaveMpm) <= DL_R_MAX) AND (rRatioSet = rRatioSet) AND (ABS(rRatioSet) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：主线速度严格为正，从线速度非负，设定速比严格为正
    IF (ABS(rMasterMpm) <= DL_EPS) OR (rMasterMpm < 0.0) OR (rMasterMpm > DL_SPEED_MAX) THEN
        RETURN;
    END_IF;
    IF (rSlaveMpm < 0.0) OR (rSlaveMpm > DL_SPEED_MAX) THEN
        RETURN;
    END_IF;
    IF (ABS(rRatioSet) <= DL_EPS) OR (rRatioSet < 0.0) OR (rRatioSet > DL_RATIO_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜实际速比
    rRatioAct := rSlaveMpm / rMasterMpm;
    // 段 6｜相对偏差
    rDevPct := (rRatioAct - rRatioSet) / rRatioSet * DL_PCT;
    // 段 7｜匹配判定
    _rAbsDev := ABS(rDevPct);
    IF _rAbsDev <= DL_TOL_PCT THEN
        bMatch := TRUE;
    ELSE
        bMatch := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_LineSpeedMatchRatio := bValid;
END_FUNCTION
