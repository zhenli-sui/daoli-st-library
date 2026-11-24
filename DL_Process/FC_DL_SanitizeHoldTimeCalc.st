(*
  ============================================================
  组件名 : FC_DL_SanitizeHoldTimeCalc
  分类   : DL_Process
  功能   : 消毒保持时间计算，按实际浓度折算浓度比并对温度系数修正后给出保持时间
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      温度系数 = 1 + (温度-20)*0.02，限幅 0.5~2.0，防止极端温度把时间推到无意义区间。
      保持时间 = 基准时间 * (基准浓度/实际浓度) * (1/温度系数)。
      浓度低于基准时比值大于 1，时间自动延长；浓度高于基准时时间缩短，符合消毒动力学方向。
  ============================================================
*)
FUNCTION FC_DL_SanitizeHoldTimeCalc : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rConcPct     : REAL; // 实际消毒液浓度 [%] / actual sanitizer concentration [percent]
    rConcRefPct  : REAL; // 基准消毒液浓度 [%] / reference sanitizer concentration [percent]
    rHoldRef_min : REAL; // 基准浓度下的基准保持时间 [min] / reference hold time at the reference concentration [minute]
    rTempC       : REAL; // 实际消毒液温度 [摄氏度] / actual sanitizer temperature [degree Celsius]
END_VAR
VAR_OUTPUT
    rTempFactor : REAL; // 温度修正系数，限幅 0.5~2.0 [无量纲] / temperature correction factor clamped to 0.5 to 2.0 [dimensionless]
    rConcRatio  : REAL; // 浓度比，基准浓度除以实际浓度 [无量纲] / concentration ratio of reference over actual [dimensionless]
    rHold_min   : REAL; // 修正后的保持时间 [min] / corrected hold time [minute]
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ONE      : REAL := 1.0;    // 单位常量 [无量纲] / unity constant [dimensionless]
    DL_TEMP_REF : REAL := 20.0;   // 温度基准点 [摄氏度] / temperature reference point [degree Celsius]
    DL_TEMP_K   : REAL := 0.02;   // 每摄氏度温度系数增量 [1/摄氏度] / temperature coefficient increment per degree Celsius [per degree Celsius]
    DL_FACT_LO  : REAL := 0.5;    // 温度系数下限 [无量纲] / lower limit of the temperature factor [dimensionless]
    DL_FACT_HI  : REAL := 2.0;    // 温度系数上限 [无量纲] / upper limit of the temperature factor [dimensionless]
    DL_TEMP_MIN : REAL := -50.0;  // 允许温度下界 [摄氏度] / permitted lower bound of the temperature [degree Celsius]
    DL_TEMP_MAX : REAL := 150.0;  // 允许温度上界 [摄氏度] / permitted upper bound of the temperature [degree Celsius]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rInv  : REAL := 0.0;   // 温度系数的倒数，除法前先算后判 [无量纲] / reciprocal of the temperature factor computed before the guard [dimensionless]
END_VAR

    // 段 1｜出口预置：系数先置于 1，避免下游误用零
    rTempFactor := DL_ONE;
    rConcRatio := 0.0;
    rHold_min := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rConcPct = rConcPct) AND (ABS(rConcPct) <= DL_R_MAX) AND (rConcRefPct = rConcRefPct) AND (ABS(rConcRefPct) <= DL_R_MAX) AND (rHoldRef_min = rHoldRef_min) AND (ABS(rHoldRef_min) <= DL_R_MAX) AND (rTempC = rTempC) AND (ABS(rTempC) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：实际浓度严格为正、基准浓度非负、基准时间非负、温度在工程区间
    IF ABS(rConcPct) <= DL_EPS THEN
        RETURN;
    END_IF;
    IF (rConcPct < 0.0) OR (rConcRefPct < 0.0) OR (rHoldRef_min < 0.0) THEN
        RETURN;
    END_IF;
    IF (rTempC < DL_TEMP_MIN) OR (rTempC > DL_TEMP_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜温度系数与限幅
    rTempFactor := DL_ONE + (rTempC - DL_TEMP_REF) * DL_TEMP_K;
    IF rTempFactor > DL_FACT_HI THEN
        rTempFactor := DL_FACT_HI;
    ELSIF rTempFactor < DL_FACT_LO THEN
        rTempFactor := DL_FACT_LO;
    END_IF;
    // 段 6｜浓度比
    rConcRatio := rConcRefPct / rConcPct;
    // 段 7｜温度系数分母闸：先判零再取倒数，顺序不可颠倒
    IF ABS(rTempFactor) <= DL_EPS THEN
        RETURN;
    END_IF;
    _rInv := DL_ONE / rTempFactor;
    rHold_min := rHoldRef_min * rConcRatio * _rInv;
    bValid := TRUE;
    FC_DL_SanitizeHoldTimeCalc := bValid;
END_FUNCTION
