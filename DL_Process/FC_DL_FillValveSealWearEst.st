(*
  ============================================================
  组件名 : FC_DL_FillValveSealWearEst
  分类   : DL_Process
  功能   : 灌装阀密封磨损估算，按循环数乘温度加速因子求等效循环并折算磨损百分比
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      温度加速因子 = 1 + MAX(0, 实测温度 - 基准温度) * 0.03，低于基准温度时不加速。
      等效循环 = DWORD_TO_REAL(循环数) * 温度加速因子，磨损 = 等效/额定 * 100，限幅 0~100。
      DWORD 规模较大，转 REAL 时尾数精度约 24 位，对磨损百分比的分辨率影响可忽略，本组件按此口径实现。
  ============================================================
*)
FUNCTION FC_DL_FillValveSealWearEst : BOOL
VAR_INPUT
    bEnable      : BOOL;  // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL;  // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    dwCycleCnt   : DWORD; // 阀累计动作循环数 [次] / accumulated valve actuation cycles [time]
    rTempC       : REAL;  // 实际工作温度 [摄氏度] / actual working temperature [degree Celsius]
    rTempRefC    : REAL;  // 额定基准温度 [摄氏度] / rated reference temperature [degree Celsius]
    dwRatedCycle : DWORD; // 密封件额定寿命循环数 [次] / rated life cycles of the seal [time]
END_VAR
VAR_OUTPUT
    rTempFactor : REAL; // 温度加速因子 [无量纲] / temperature acceleration factor [dimensionless]
    rEquivCyc   : REAL; // 温度折算后的等效循环数 [次] / equivalent cycle count after temperature weighting [time]
    rWearPct    : REAL; // 密封磨损百分比，限幅 0~100 [%] / seal wear percentage clamped to 0 to 100 [percent]
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ONE      : REAL := 1.0;     // 单位常量 [无量纲] / unity constant [dimensionless]
    DL_ZERO     : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_PCT      : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_TEMP_K   : REAL := 0.03;    // 每摄氏度加速增量 [1/摄氏度] / acceleration increment per degree Celsius [per degree Celsius]
    DL_TEMP_MIN : REAL := -50.0;   // 允许温度下界 [摄氏度] / permitted lower bound of the temperature [degree Celsius]
    DL_TEMP_MAX : REAL := 200.0;   // 允许温度上界 [摄氏度] / permitted upper bound of the temperature [degree Celsius]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rOver : REAL := 0.0;   // 高于基准温度的超温量，负值归零 [摄氏度] / excess over the reference temperature, negative clamped to zero [degree Celsius]
    _rRated : REAL := 0.0;  // 额定循环数折算实数 [次] / rated cycle count cast to real [time]
END_VAR

    // 段 1｜出口预置：因子先置于 1，避免下游误用零
    rTempFactor := DL_ONE;
    rEquivCyc := 0.0;
    rWearPct := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸：温度参与换算，必须有限
    _bFin := (rTempC = rTempC) AND (ABS(rTempC) <= DL_R_MAX) AND (rTempRefC = rTempRefC) AND (ABS(rTempRefC) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：温度落在工程区间
    IF (rTempC < DL_TEMP_MIN) OR (rTempC > DL_TEMP_MAX) THEN
        RETURN;
    END_IF;
    IF (rTempRefC < DL_TEMP_MIN) OR (rTempRefC > DL_TEMP_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜额定寿命非零闸：额定为零时磨损无定义
    _rRated := DWORD_TO_REAL(dwRatedCycle);
    IF _rRated <= DL_EPS THEN
        RETURN;
    END_IF;
    // 段 6｜温度加速因子：仅超温部分计入加速
    _rOver := rTempC - rTempRefC;
    IF _rOver < DL_ZERO THEN
        _rOver := DL_ZERO;
    END_IF;
    rTempFactor := DL_ONE + _rOver * DL_TEMP_K;
    // 段 7｜等效循环
    rEquivCyc := DWORD_TO_REAL(dwCycleCnt) * rTempFactor;
    // 段 8｜磨损百分比与限幅
    rWearPct := rEquivCyc / _rRated * DL_PCT;
    IF rWearPct < DL_ZERO THEN
        rWearPct := DL_ZERO;
    END_IF;
    IF rWearPct > DL_PCT THEN
        rWearPct := DL_PCT;
    END_IF;
    bValid := TRUE;
    FC_DL_FillValveSealWearEst := bValid;
END_FUNCTION
