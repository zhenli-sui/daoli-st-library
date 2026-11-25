(*
  ============================================================
  组件名 : FC_DL_ConductivityDilutionCalc
  分类   : DL_Process
  功能   : 电导率稀释比计算，由母液与水的本底电导求目标浓度所需的稀释倍数与配水占比
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      稀释比 = (母液电导 - 水本底电导) / (目标电导 - 水本底电导)。
      目标电导不高于水本底时分母非正，物理上无法靠兑水达到，直接判无效。
      配水占比 = (1 - 1/稀释比) * 100，稀释比非正时同样判无效。
  ============================================================
*)
FUNCTION FC_DL_ConductivityDilutionCalc : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rCondFeed    : REAL; // 母液电导率 [uS/cm] / feed solution conductivity [micro siemens per centimetre]
    rCondTarget  : REAL; // 目标电导率 [uS/cm] / target conductivity [micro siemens per centimetre]
    rCondWater   : REAL; // 稀释水本底电导率 [uS/cm] / background conductivity of the dilution water [micro siemens per centimetre]
END_VAR
VAR_OUTPUT
    rDilutionRatio : REAL; // 稀释倍数，母液体积的多少倍 [无量纲] / dilution ratio in multiples of the feed volume [dimensionless]
    rWaterPct      : REAL; // 配水中水所占体积百分比 [%] / volumetric percentage of water in the mixture [percent]
    bValid         : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS   : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ONE   : REAL := 1.0;     // 单位常量 [无量纲] / unity constant [dimensionless]
    DL_PCT   : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_RATIO_MAX : REAL := 10000.0; // 稀释比合理上限，超限视为配比不可实现 [无量纲] / sanity upper bound of the dilution ratio [dimensionless]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rNum  : REAL := 0.0;   // 稀释比分子 [uS/cm] / numerator of the dilution ratio [micro siemens per centimetre]
    _rDen  : REAL := 0.0;   // 稀释比分母 [uS/cm] / denominator of the dilution ratio [micro siemens per centimetre]
END_VAR

    // 段 1｜出口预置
    rDilutionRatio := 0.0;
    rWaterPct := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rCondFeed = rCondFeed) AND (ABS(rCondFeed) <= DL_R_MAX) AND (rCondTarget = rCondTarget) AND (ABS(rCondTarget) <= DL_R_MAX) AND (rCondWater = rCondWater) AND (ABS(rCondWater) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：三者均不得为负，母液必须高于水本底
    IF (rCondFeed < 0.0) OR (rCondTarget < 0.0) OR (rCondWater < 0.0) THEN
        RETURN;
    END_IF;
    // 段 5｜分子分母组装
    _rNum := rCondFeed - rCondWater;
    _rDen := rCondTarget - rCondWater;
    // 段 6｜分母非正闸：兑水无法把电导降到水本底以下
    IF _rDen <= DL_EPS THEN
        RETURN;
    END_IF;
    // 段 7｜分子非正闸：母液不高于水本底时无稀释意义
    IF _rNum <= DL_EPS THEN
        RETURN;
    END_IF;
    rDilutionRatio := _rNum / _rDen;
    // 段 8｜稀释比合理区间闸，防止配比不可实现
    IF (rDilutionRatio < DL_ONE) OR (rDilutionRatio > DL_RATIO_MAX) THEN
        RETURN;
    END_IF;
    // 段 9｜配水占比
    rWaterPct := (DL_ONE - DL_ONE / rDilutionRatio) * DL_PCT;
    IF rWaterPct < 0.0 THEN
        rWaterPct := 0.0;
    END_IF;
    IF rWaterPct > DL_PCT THEN
        rWaterPct := DL_PCT;
    END_IF;
    bValid := TRUE;
    FC_DL_ConductivityDilutionCalc := bValid;
END_FUNCTION
