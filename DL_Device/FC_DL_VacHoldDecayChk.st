(*
  ============================================================
  组件名 : FC_DL_VacHoldDecayChk
  分类   : DL_Device
  功能   : 真空保持衰减校验，按保持时段内的真空度跌落求衰减率并给出泄漏报警
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      衰减率 = (起始真空度 - 当前真空度) / 保持时长，单位 kPa/s。
      当前真空度高于起始值属测量异常或补抽工况，衰减率按 0 处理并置 bSuspect 提示，不判泄漏。
      衰减率严格大于允许限值才置泄漏报警，等于限值视为边界可控。
  ============================================================
*)
FUNCTION FC_DL_VacHoldDecayChk : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时校验 / Enable: TRUE to check
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rVacStart_kpa : REAL; // 保持时段起始真空度 [kPa] / vacuum level at the start of the hold phase [kilopascal]
    rVacNow_kpa : REAL; // 当前实测真空度 [kPa] / current measured vacuum level [kilopascal]
    rHoldTime_s : REAL; // 保持时段已持续时长 [s] / elapsed hold phase duration [second]
    rDecayLim   : REAL; // 允许的最大衰减率 [kPa/s] / permitted maximum decay rate [kilopascal per second]
END_VAR
VAR_OUTPUT
    rDecayRate : REAL; // 实测真空衰减率，负值按 0 处理 [kPa/s] / measured vacuum decay rate, negative clamped to zero [kilopascal per second]
    rDropKpa   : REAL; // 时段内真空度跌落量 [kPa] / vacuum drop within the hold phase [kilopascal]
    bLeakAlarm : BOOL; // 泄漏报警：TRUE 表示衰减率超过限值 / leak alarm, TRUE when the decay rate exceeds the limit
    bSuspect   : BOOL; // 数据可疑：TRUE 表示当前真空度高于起始值 / suspect data, TRUE when the current vacuum is above the start value
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_VAC_MAX : REAL := 101.3;   // 真空度物理上限，标准大气压 [kPa] / physical upper bound of the vacuum level, standard atmosphere [kilopascal]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置：报警位保守置 FALSE，可疑位先置 FALSE
    rDecayRate := 0.0;
    rDropKpa := 0.0;
    bLeakAlarm := FALSE;
    bSuspect := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rVacStart_kpa = rVacStart_kpa) AND (ABS(rVacStart_kpa) <= DL_R_MAX) AND (rVacNow_kpa = rVacNow_kpa) AND (ABS(rVacNow_kpa) <= DL_R_MAX) AND (rHoldTime_s = rHoldTime_s) AND (ABS(rHoldTime_s) <= DL_R_MAX) AND (rDecayLim = rDecayLim) AND (ABS(rDecayLim) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：保持时长严格为正，真空度与限值不得为负
    IF (ABS(rHoldTime_s) <= DL_EPS) OR (rHoldTime_s < DL_ZERO) THEN
        RETURN;
    END_IF;
    IF (rVacStart_kpa < DL_ZERO) OR (rVacNow_kpa < DL_ZERO) OR (rDecayLim < DL_ZERO) THEN
        RETURN;
    END_IF;
    IF (rVacStart_kpa > DL_VAC_MAX) OR (rVacNow_kpa > DL_VAC_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜跌落量与衰减率
    rDropKpa := rVacStart_kpa - rVacNow_kpa;
    IF rDropKpa < DL_ZERO THEN
        bSuspect := TRUE;
        rDropKpa := DL_ZERO;
        rDecayRate := DL_ZERO;
    ELSE
        bSuspect := FALSE;
        rDecayRate := rDropKpa / rHoldTime_s;
    END_IF;
    // 段 6｜泄漏报警
    IF rDecayRate > rDecayLim THEN
        bLeakAlarm := TRUE;
    ELSE
        bLeakAlarm := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_VacHoldDecayChk := bValid;
END_FUNCTION
