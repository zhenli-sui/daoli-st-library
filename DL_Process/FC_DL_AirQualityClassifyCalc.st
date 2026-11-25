(*
  ============================================================
  组件名 : FC_DL_AirQualityClassifyCalc
  分类   : DL_Process
  功能   : 压缩空气质量等级判定，按 ISO 8573-1 分别评定露点含油与颗粒等级并取最严者
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      露点分级：<=-40 为 1 级，<=-20 为 2 级，<=+3 为 3 级，其余为 4 级。
      含油分级：<=0.01 为 1 级，<=0.1 为 2 级，<=1 为 3 级，其余为 4 级。
      颗粒等级由调用侧直接给出 1~4，本组件只做合法性校验。
      总等级取三者最大值（数字越大越差）；总等级 <=2 判定为合格。
  ============================================================
*)
FUNCTION FC_DL_AirQualityClassifyCalc : BOOL
VAR_INPUT
    bEnable       : BOOL; // 使能：TRUE 时判定 / Enable: TRUE to classify
    bErr          : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rDewPointC    : REAL; // 压力露点 [摄氏度] / pressure dew point [degree Celsius]
    rOil_mgm3     : REAL; // 含油量 [mg/m3] / oil content [milligram per cubic metre]
    iParticleClass : INT; // 颗粒等级 1~4 [级] / particle class from 1 to 4 [class]
END_VAR
VAR_OUTPUT
    iDewClass     : INT;  // 露点等级 1~4 [级] / dew point class from 1 to 4 [class]
    iOilClass     : INT;  // 含油等级 1~4 [级] / oil class from 1 to 4 [class]
    iQualityClass : INT;  // 综合等级取三者最大值 [级] / overall class taken as the maximum of the three [class]
    bPass         : BOOL; // 合格：TRUE 表示综合等级不差于 2 级 / pass, TRUE when the overall class is 2 or better
    bValid        : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX      : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS        : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_DEW_1      : REAL := -40.0;  // 1 级露点上限 [摄氏度] / upper bound of the class one dew point [degree Celsius]
    DL_DEW_2      : REAL := -20.0;  // 2 级露点上限 [摄氏度] / upper bound of the class two dew point [degree Celsius]
    DL_DEW_3      : REAL := 3.0;    // 3 级露点上限 [摄氏度] / upper bound of the class three dew point [degree Celsius]
    DL_OIL_1      : REAL := 0.01;   // 1 级含油上限 [mg/m3] / upper bound of the class one oil content [milligram per cubic metre]
    DL_OIL_2      : REAL := 0.1;    // 2 级含油上限 [mg/m3] / upper bound of the class two oil content [milligram per cubic metre]
    DL_OIL_3      : REAL := 1.0;    // 3 级含油上限 [mg/m3] / upper bound of the class three oil content [milligram per cubic metre]
    DL_CLS_MIN    : INT := 1;       // 等级下界 [级] / lower bound of a class [class]
    DL_CLS_MAX    : INT := 4;       // 等级上界 [级] / upper bound of a class [class]
    DL_PASS_MAX   : INT := 2;       // 合格允许的最差等级 [级] / worst class still accepted as a pass [class]
    DL_DEW_MIN    : REAL := -100.0; // 露点合理下界 [摄氏度] / sanity lower bound of the dew point [degree Celsius]
    DL_DEW_MAX    : REAL := 100.0;  // 露点合理上界 [摄氏度] / sanity upper bound of the dew point [degree Celsius]
    DL_OIL_MAX    : REAL := 100.0;  // 含油合理上界 [mg/m3] / sanity upper bound of the oil content [milligram per cubic metre]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置：等级先置最差 4 级，任何提前返回都不会误报合格
    iDewClass := DL_CLS_MAX;
    iOilClass := DL_CLS_MAX;
    iQualityClass := DL_CLS_MAX;
    bPass := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rDewPointC = rDewPointC) AND (ABS(rDewPointC) <= DL_R_MAX) AND (rOil_mgm3 = rOil_mgm3) AND (ABS(rOil_mgm3) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：露点与含油落在合理区间，颗粒等级 1~4
    IF (rDewPointC < DL_DEW_MIN) OR (rDewPointC > DL_DEW_MAX) THEN
        RETURN;
    END_IF;
    IF (rOil_mgm3 < 0.0) OR (rOil_mgm3 > DL_OIL_MAX) THEN
        RETURN;
    END_IF;
    IF (iParticleClass < DL_CLS_MIN) OR (iParticleClass > DL_CLS_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜露点分级
    IF rDewPointC <= DL_DEW_1 THEN
        iDewClass := 1;
    ELSIF rDewPointC <= DL_DEW_2 THEN
        iDewClass := 2;
    ELSIF rDewPointC <= DL_DEW_3 THEN
        iDewClass := 3;
    ELSE
        iDewClass := 4;
    END_IF;
    // 段 6｜含油分级
    IF rOil_mgm3 <= DL_OIL_1 THEN
        iOilClass := 1;
    ELSIF rOil_mgm3 <= DL_OIL_2 THEN
        iOilClass := 2;
    ELSIF rOil_mgm3 <= DL_OIL_3 THEN
        iOilClass := 3;
    ELSE
        iOilClass := 4;
    END_IF;
    // 段 7｜综合等级取最严
    iQualityClass := iDewClass;
    IF iOilClass > iQualityClass THEN
        iQualityClass := iOilClass;
    END_IF;
    IF iParticleClass > iQualityClass THEN
        iQualityClass := iParticleClass;
    END_IF;
    // 段 8｜合格判定
    IF iQualityClass <= DL_PASS_MAX THEN
        bPass := TRUE;
    ELSE
        bPass := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_AirQualityClassifyCalc := bValid;
END_FUNCTION
