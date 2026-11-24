(*
  ============================================================
  组件名 : FC_DL_CompressorDutyCycleCalc
  分类   : DL_Process
  功能   : 压缩机加载占空比与卸载能耗占比计算，用于评估空压站运行经济性
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      加载占空比 = 加载时间 / 统计窗口 * 100。
      卸载能耗占比 = 卸载功率*卸载时间 / (加载功率*加载时间 + 卸载功率*卸载时间) * 100。
      能耗分母为零表示窗口内既无加载也无卸载，占空比无法归一，判无效。
      加载时间加卸载时间超过统计窗口时数据自相矛盾，判无效而不是强行归一。
  ============================================================
*)
FUNCTION FC_DL_CompressorDutyCycleCalc : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rLoadTime_s  : REAL; // 窗口内加载运行时间 [s] / loaded running time inside the window [second]
    rUnloadTime_s : REAL; // 窗口内卸载运行时间 [s] / unloaded running time inside the window [second]
    rIdleKw      : REAL; // 卸载空转功率 [kW] / unloaded idle power [kilowatt]
    rLoadKw      : REAL; // 加载运行功率 [kW] / loaded running power [kilowatt]
    rDur_s       : REAL; // 统计窗口总时长 [s] / total duration of the statistic window [second]
END_VAR
VAR_OUTPUT
    rDutyPct       : REAL; // 加载占空比，限幅 0~100 [%] / loading duty cycle clamped to 0 to 100 [percent]
    rIdleEnergyPct : REAL; // 卸载能耗占窗口总能耗比例，限幅 0~100 [%] / unloaded energy share of the window total clamped to 0 to 100 [percent]
    rTotalKwh      : REAL; // 窗口内折算总电量 [kWh] / equivalent total energy inside the window [kilowatt hour]
    bValid         : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT     : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_S_PER_H : REAL := 3600.0;  // 每小时秒数 [s/h] / seconds per hour [second per hour]
    DL_TOL_S   : REAL := 0.001;   // 时间窗超限判定容差 [s] / tolerance for the window overrun check [second]
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rLoadKwh : REAL := 0.0;  // 加载段电量 [kWh] / energy of the loaded segment [kilowatt hour]
    _rIdleKwh : REAL := 0.0;  // 卸载段电量 [kWh] / energy of the unloaded segment [kilowatt hour]
    _rDen     : REAL := 0.0;  // 能耗占比分母 [kWh] / denominator of the energy share [kilowatt hour]
END_VAR

    // 段 1｜出口预置
    rDutyPct := 0.0;
    rIdleEnergyPct := 0.0;
    rTotalKwh := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rLoadTime_s = rLoadTime_s) AND (ABS(rLoadTime_s) <= DL_R_MAX) AND (rUnloadTime_s = rUnloadTime_s) AND (ABS(rUnloadTime_s) <= DL_R_MAX) AND (rIdleKw = rIdleKw) AND (ABS(rIdleKw) <= DL_R_MAX) AND (rLoadKw = rLoadKw) AND (ABS(rLoadKw) <= DL_R_MAX) AND (rDur_s = rDur_s) AND (ABS(rDur_s) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：统计窗口严格为正，时间与功率不得为负
    IF (ABS(rDur_s) <= DL_EPS) OR (rDur_s < DL_ZERO) THEN
        RETURN;
    END_IF;
    IF (rLoadTime_s < DL_ZERO) OR (rUnloadTime_s < DL_ZERO) OR (rIdleKw < DL_ZERO) OR (rLoadKw < DL_ZERO) THEN
        RETURN;
    END_IF;
    // 段 5｜加载加卸载不得超过窗口，超出部分属数据矛盾
    IF (rLoadTime_s + rUnloadTime_s) > (rDur_s + DL_TOL_S) THEN
        RETURN;
    END_IF;
    // 段 6｜加载占空比与限幅
    rDutyPct := rLoadTime_s / rDur_s * DL_PCT;
    IF rDutyPct < DL_ZERO THEN
        rDutyPct := DL_ZERO;
    END_IF;
    IF rDutyPct > DL_PCT THEN
        rDutyPct := DL_PCT;
    END_IF;
    // 段 7｜两段电量与总电量
    _rLoadKwh := rLoadKw * rLoadTime_s / DL_S_PER_H;
    _rIdleKwh := rIdleKw * rUnloadTime_s / DL_S_PER_H;
    rTotalKwh := _rLoadKwh + _rIdleKwh;
    // 段 8｜能耗占比分母闸
    _rDen := _rLoadKwh + _rIdleKwh;
    IF _rDen <= DL_EPS THEN
        RETURN;
    END_IF;
    rIdleEnergyPct := _rIdleKwh / _rDen * DL_PCT;
    IF rIdleEnergyPct < DL_ZERO THEN
        rIdleEnergyPct := DL_ZERO;
    END_IF;
    IF rIdleEnergyPct > DL_PCT THEN
        rIdleEnergyPct := DL_PCT;
    END_IF;
    bValid := TRUE;
    FC_DL_CompressorDutyCycleCalc := bValid;
END_FUNCTION
