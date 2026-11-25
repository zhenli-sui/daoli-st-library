(*
  ============================================================
  组件名 : FC_DL_BottleNeckLevelMargin
  分类   : DL_Process
  功能   : 瓶口液位余量计算，由瓶高瓶颈高与含泡沫液位求瓶口剩余空间并给出溢泡风险
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      余量 = 瓶高 - 瓶颈段高 - (液位 + 泡沫高)。
      瓶颈段高表示瓶口以下不可被液体占据的结构高度，必须先扣除。
      余量小于 5 mm 判溢泡风险；余量为负表示液体已侵入瓶颈段，风险必然成立。
  ============================================================
*)
FUNCTION FC_DL_BottleNeckLevelMargin : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rBottleH_mm : REAL; // 瓶身总高 [mm] / total bottle height [millimetre]
    rLevel_mm   : REAL; // 当前液位高度，自瓶底起算 [mm] / current liquid level from the bottle bottom [millimetre]
    rNeckH_mm   : REAL; // 瓶颈段结构高度 [mm] / structural height of the neck section [millimetre]
    rFoamH_mm   : REAL; // 液面泡沫层高度 [mm] / foam layer height above the liquid surface [millimetre]
END_VAR
VAR_OUTPUT
    rFillTop_mm : REAL; // 含泡沫的液面顶部高度 [mm] / top height of the liquid including foam [millimetre]
    rMargin_mm  : REAL; // 瓶口剩余余量，负值表示侵入瓶颈 [mm] / remaining margin to the bottle mouth, negative means neck intrusion [millimetre]
    bOverflowRisk : BOOL; // 溢泡风险：TRUE 表示余量小于 5 mm / overflow risk, TRUE when the margin is below 5 millimetre
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX   : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_ZERO    : REAL := 0.0;     // 零值常量 [无量纲] / zero constant [dimensionless]
    DL_RISK_MM : REAL := 5.0;     // 溢泡风险余量门限 [mm] / overflow risk margin threshold [millimetre]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rAvail : REAL := 0.0;  // 扣除瓶颈后的可用灌注高度 [mm] / usable filling height after removing the neck [millimetre]
END_VAR

    // 段 1｜出口预置
    rFillTop_mm := 0.0;
    rMargin_mm := 0.0;
    bOverflowRisk := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rBottleH_mm = rBottleH_mm) AND (ABS(rBottleH_mm) <= DL_R_MAX) AND (rLevel_mm = rLevel_mm) AND (ABS(rLevel_mm) <= DL_R_MAX) AND (rNeckH_mm = rNeckH_mm) AND (ABS(rNeckH_mm) <= DL_R_MAX) AND (rFoamH_mm = rFoamH_mm) AND (ABS(rFoamH_mm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：瓶高严格为正，其余高度不得为负
    IF rBottleH_mm <= DL_ZERO THEN
        RETURN;
    END_IF;
    IF (rLevel_mm < DL_ZERO) OR (rNeckH_mm < DL_ZERO) OR (rFoamH_mm < DL_ZERO) THEN
        RETURN;
    END_IF;
    // 段 5｜瓶颈段不得吞掉整个瓶高
    IF rNeckH_mm >= rBottleH_mm THEN
        RETURN;
    END_IF;
    // 段 6｜含泡沫的液面顶部与余量
    rFillTop_mm := rLevel_mm + rFoamH_mm;
    _rAvail := rBottleH_mm - rNeckH_mm;
    rMargin_mm := _rAvail - rFillTop_mm;
    // 段 7｜风险位
    IF rMargin_mm < DL_RISK_MM THEN
        bOverflowRisk := TRUE;
    ELSE
        bOverflowRisk := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_BottleNeckLevelMargin := bValid;
END_FUNCTION
