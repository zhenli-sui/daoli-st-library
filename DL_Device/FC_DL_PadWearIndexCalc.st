(*
  ============================================================
  组件名 : FC_DL_PadWearIndexCalc
  分类   : DL_Device
  功能   : 吸盘磨损指数计算，综合泄漏增长率与直径磨耗量加权后给出更换到期判定
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      泄漏增长率 = (当前泄漏 - 新品泄漏) / 新品泄漏 * 100，新品泄漏低于 0.001 L/min 视为无基准判无效。
      磨损指数 = 0.7 * 泄漏增长率 + 0.3 * 直径磨耗 * 10，限幅 0~100。
      指数超过 70 判更换到期；负的泄漏增长（密封变好）按 0 截断，指数只反映劣化方向。
  ============================================================
*)
FUNCTION FC_DL_PadWearIndexCalc : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rLeakNew    : REAL; // 新品基准泄漏量 [L/min] / leak rate of a new pad [litre per minute]
    rLeakNow    : REAL; // 当前实测泄漏量 [L/min] / currently measured leak rate [litre per minute]
    rDiaWear_mm : REAL; // 吸盘直径磨耗量 [mm] / diameter wear of the pad [millimetre]
END_VAR
VAR_OUTPUT
    rLeakPct  : REAL; // 泄漏增长率 [%] / leak growth rate [percent]
    rWearIdx  : REAL; // 综合磨损指数，限幅 0~100 [无量纲] / combined wear index clamped to 0 to 100 [dimensionless]
    bReplaceDue : BOOL; // 更换到期：TRUE 表示指数超过 70 / replacement due, TRUE when the index exceeds 70
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX     : REAL := 3.0E38;  // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS       : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_LEAK_MIN  : REAL := 0.001;   // 新品泄漏基准的可信下界 [L/min] / credible lower bound of the new pad leak reference [litre per minute]
    DL_PCT       : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_W_LEAK    : REAL := 0.7;     // 泄漏项权重 [无量纲] / weight of the leak term [dimensionless]
    DL_W_DIA     : REAL := 0.3;     // 直径磨耗项权重 [无量纲] / weight of the diameter wear term [dimensionless]
    DL_DIA_GAIN  : REAL := 10.0;    // 直径磨耗放大倍数 [无量纲] / amplification of the diameter wear term [dimensionless]
    DL_IDX_HI    : REAL := 100.0;   // 指数限幅上限 [无量纲] / upper clamp of the index [dimensionless]
    DL_IDX_LO    : REAL := 0.0;     // 指数限幅下限 [无量纲] / lower clamp of the index [dimensionless]
    DL_DUE_IDX   : REAL := 70.0;    // 更换到期门限 [无量纲] / replacement due threshold [dimensionless]
    DL_DIA_MAX   : REAL := 200.0;   // 直径磨耗合理上限 [mm] / sanity upper bound of the diameter wear [millimetre]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rRaw : REAL := 0.0;   // 限幅前磨损指数 [无量纲] / raw wear index before clamping [dimensionless]
END_VAR

    // 段 1｜出口预置
    rLeakPct := 0.0;
    rWearIdx := 0.0;
    bReplaceDue := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rLeakNew = rLeakNew) AND (ABS(rLeakNew) <= DL_R_MAX) AND (rLeakNow = rLeakNow) AND (ABS(rLeakNow) <= DL_R_MAX) AND (rDiaWear_mm = rDiaWear_mm) AND (ABS(rDiaWear_mm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：新品泄漏必须高于可信下界，当前泄漏与磨耗不得为负
    IF (ABS(rLeakNew) <= DL_EPS) OR (rLeakNew < DL_LEAK_MIN) THEN
        RETURN;
    END_IF;
    IF (rLeakNow < 0.0) OR (rDiaWear_mm < 0.0) OR (rDiaWear_mm > DL_DIA_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜泄漏增长率
    rLeakPct := (rLeakNow - rLeakNew) / rLeakNew * DL_PCT;
    IF rLeakPct < DL_IDX_LO THEN
        rLeakPct := DL_IDX_LO;
    END_IF;
    // 段 6｜加权合成与限幅
    _rRaw := DL_W_LEAK * rLeakPct + DL_W_DIA * rDiaWear_mm * DL_DIA_GAIN;
    IF _rRaw < DL_IDX_LO THEN
        rWearIdx := DL_IDX_LO;
    ELSIF _rRaw > DL_IDX_HI THEN
        rWearIdx := DL_IDX_HI;
    ELSE
        rWearIdx := _rRaw;
    END_IF;
    // 段 7｜更换到期判定用限幅前的真实指数判断方向
    IF _rRaw > DL_DUE_IDX THEN
        bReplaceDue := TRUE;
    ELSE
        bReplaceDue := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_PadWearIndexCalc := bValid;
END_FUNCTION
