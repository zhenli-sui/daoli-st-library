(*
  ============================================================
  组件名 : FC_DL_VacuumGenDutyCalc
  分类   : DL_Device
  功能   : 真空发生器占空比计算，按单周期通电时长求占空比并折算压缩空气耗量
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      占空比 = 通电时长 / 循环周期 * 100，限幅 0~100。
      平均耗气量 = 额定耗气量 * 占空比 / 100，单位 L/min。
      通电时长超过循环周期属参数矛盾，判无效；周期为零则无法归一，同样判无效。
  ============================================================
*)
FUNCTION FC_DL_VacuumGenDutyCalc : BOOL
VAR_INPUT
    bEnable    : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr       : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rOnTime_s  : REAL; // 单周期内真空发生器通电时长 [s] / generator energised time within one cycle [second]
    rCycle_s   : REAL; // 循环周期总时长 [s] / total cycle duration [second]
    rAirCons   : REAL; // 通电状态下的额定耗气量 [L/min] / rated air consumption while energised [litre per minute]
END_VAR
VAR_OUTPUT
    rDutyPct   : REAL; // 真空发生器占空比，限幅 0~100 [%] / generator duty cycle clamped to 0 to 100 [percent]
    rAirUseLpm : REAL; // 折算平均耗气量 [L/min] / equivalent average air consumption [litre per minute]
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_TOL_S   : REAL := 0.001;   // 时长比较容差 [s] / tolerance of the duration comparison [second]
    DL_CYC_MAX : REAL := 86400.0; // 循环周期合理上限，一天 [s] / sanity upper bound of the cycle duration, one day [second]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置
    rDutyPct := 0.0;
    rAirUseLpm := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rOnTime_s = rOnTime_s) AND (ABS(rOnTime_s) <= DL_R_MAX) AND (rCycle_s = rCycle_s) AND (ABS(rCycle_s) <= DL_R_MAX) AND (rAirCons = rAirCons) AND (ABS(rAirCons) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：周期严格为正且不超过一天，通电时长与耗气量非负
    IF (ABS(rCycle_s) <= DL_EPS) OR (rCycle_s < DL_ZERO) OR (rCycle_s > DL_CYC_MAX) THEN
        RETURN;
    END_IF;
    IF (rOnTime_s < DL_ZERO) OR (rAirCons < DL_ZERO) THEN
        RETURN;
    END_IF;
    // 段 5｜通电时长不得越过周期
    IF rOnTime_s > (rCycle_s + DL_TOL_S) THEN
        RETURN;
    END_IF;
    // 段 6｜占空比与限幅
    rDutyPct := rOnTime_s / rCycle_s * DL_PCT;
    IF rDutyPct < DL_ZERO THEN
        rDutyPct := DL_ZERO;
    END_IF;
    IF rDutyPct > DL_PCT THEN
        rDutyPct := DL_PCT;
    END_IF;
    // 段 7｜平均耗气量
    rAirUseLpm := rAirCons * rDutyPct / DL_PCT;
    bValid := TRUE;
    FC_DL_VacuumGenDutyCalc := bValid;
END_FUNCTION
