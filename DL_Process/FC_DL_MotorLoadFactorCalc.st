(*
  ============================================================
  组件名 : FC_DL_MotorLoadFactorCalc
  分类   : DL_Process
  功能   : 电机负载率计算，由实测有功功率与功率因数求视在功率并折算负载率与过载位
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      视在功率 = 有功功率 / 功率因数，功率因数不高于 0.1 视为测量不可信，直接判无效。
      负载率 = 有功 / 额定有功 * 100，限幅 0~150；超过 100% 置过载位。
      限幅上限取 150% 而非 100%，是为了在过载时保留可区分的幅值信息。
  ============================================================
*)
FUNCTION FC_DL_MotorLoadFactorCalc : BOOL
VAR_INPUT
    bEnable   : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr      : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rP_kw     : REAL; // 实测有功功率 [kW] / measured active power [kilowatt]
    rPnom_kw  : REAL; // 电机额定有功功率 [kW] / rated active power of the motor [kilowatt]
    rCosPhi   : REAL; // 实测功率因数 [无量纲] / measured power factor [dimensionless]
END_VAR
VAR_OUTPUT
    rApparentKva : REAL; // 视在功率 [kVA] / apparent power [kilovolt ampere]
    rLoadPct     : REAL; // 负载率，限幅 0~150 [%] / load factor clamped to 0 to 150 [percent]
    bOverload    : BOOL; // 过载：TRUE 表示负载率超过 100% / overload, TRUE when the load factor exceeds 100 percent
    bValid       : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX     : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS       : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PF_MIN    : REAL := 0.1;    // 功率因数可信下界 [无量纲] / credible lower bound of the power factor [dimensionless]
    DL_PF_MAX    : REAL := 1.0;    // 功率因数物理上界 [无量纲] / physical upper bound of the power factor [dimensionless]
    DL_PCT       : REAL := 100.0;  // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_LOAD_HI   : REAL := 150.0;  // 负载率限幅上限 [%] / upper clamp of the load factor [percent]
    DL_LOAD_LO   : REAL := 0.0;    // 负载率限幅下限 [%] / lower clamp of the load factor [percent]
    DL_OVL_PCT   : REAL := 100.0;  // 过载门限 [%] / overload threshold [percent]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rRaw  : REAL := 0.0;   // 限幅前负载率 [%] / raw load factor before clamping [percent]
END_VAR

    // 段 1｜出口预置
    rApparentKva := 0.0;
    rLoadPct := 0.0;
    bOverload := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rP_kw = rP_kw) AND (ABS(rP_kw) <= DL_R_MAX) AND (rPnom_kw = rPnom_kw) AND (ABS(rPnom_kw) <= DL_R_MAX) AND (rCosPhi = rCosPhi) AND (ABS(rCosPhi) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：额定功率严格为正，有功功率非负，功率因数在可信区间
    IF (ABS(rPnom_kw) <= DL_EPS) OR (rPnom_kw < 0.0) THEN
        RETURN;
    END_IF;
    IF rP_kw < 0.0 THEN
        RETURN;
    END_IF;
    IF (rCosPhi <= DL_PF_MIN) OR (rCosPhi > DL_PF_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜视在功率
    rApparentKva := rP_kw / rCosPhi;
    // 段 6｜负载率与限幅
    _rRaw := rP_kw / rPnom_kw * DL_PCT;
    IF _rRaw < DL_LOAD_LO THEN
        rLoadPct := DL_LOAD_LO;
    ELSIF _rRaw > DL_LOAD_HI THEN
        rLoadPct := DL_LOAD_HI;
    ELSE
        rLoadPct := _rRaw;
    END_IF;
    // 段 7｜过载位用限幅前的真实值判定，避免限幅把过载信息吃掉
    IF _rRaw > DL_OVL_PCT THEN
        bOverload := TRUE;
    ELSE
        bOverload := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_MotorLoadFactorCalc := bValid;
END_FUNCTION
