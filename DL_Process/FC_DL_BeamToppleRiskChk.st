(*
  ============================================================
  组件名 : FC_DL_BeamToppleRiskChk
  分类   : DL_Process
  功能   : 横梁倾覆风险校核，按重心偏心放大力矩后折算横梁承载利用率并给出风险位
  复杂度 : C1
  版本   : 1.0.1
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      偏心系数 = 1 + |重心偏移|/横梁深度（v1.0.1 取绝对值：负偏移同样放大倾覆风险，
      修正原带符号实现导致负偏移时利用率被低估、风险漏报的缺陷），偏心为零时系数为 1。
      |重心偏移| > 梁深/2 视为不可信组态，直接置 bValid=FALSE 返回。
      有效载荷 = 载荷 * 偏心系数；利用率超过 85% 即判倾覆风险。
      利用率不做 100% 上限截断，超过 100% 的信息对诊断有价值，由调用侧自行显示。
  ============================================================
*)
FUNCTION FC_DL_BeamToppleRiskChk : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时校核 / Enable: TRUE to check
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rLoadKg      : REAL; // 实际载荷质量 [kg] / actual load mass [kg]
    rBeamCapKg   : REAL; // 横梁额定承载质量 [kg] / rated load capacity of the beam [kg]
    rCgOffset_mm : REAL; // 载荷重心相对横梁中心的偏移 [mm] / load centre of gravity offset from the beam centre [mm]
    rBeamDepth_mm : REAL; // 横梁截面深度 [mm] / beam section depth [mm]
END_VAR
VAR_OUTPUT
    rEccFactor : REAL; // 偏心放大系数 [无量纲] / eccentricity amplification factor [dimensionless]
    rEffLoadKg : REAL; // 折算有效载荷质量 [kg] / equivalent effective load mass [kg]
    rUtilPct   : REAL; // 承载利用率 [%] / utilisation of the rated capacity [percent]
    bRisk      : BOOL; // 倾覆风险：TRUE 表示利用率超过门限 / topple risk, TRUE when utilisation exceeds the limit
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_RISK_PCT : REAL := 85.0;   // 倾覆风险门限 [%] / topple risk threshold [percent]
    DL_PCT      : REAL := 100.0;  // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置
    rEccFactor := 1.0;
    rEffLoadKg := 0.0;
    rUtilPct := 0.0;
    bRisk := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rLoadKg = rLoadKg) AND (ABS(rLoadKg) <= DL_R_MAX) AND (rBeamCapKg = rBeamCapKg) AND (ABS(rBeamCapKg) <= DL_R_MAX) AND (rCgOffset_mm = rCgOffset_mm) AND (ABS(rCgOffset_mm) <= DL_R_MAX) AND (rBeamDepth_mm = rBeamDepth_mm) AND (ABS(rBeamDepth_mm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：承载与横梁深度必须为正，载荷不得为负
    IF (ABS(rBeamCapKg) <= DL_EPS) OR (ABS(rBeamDepth_mm) <= DL_EPS) THEN
        RETURN;
    END_IF;
    IF (rBeamCapKg < 0.0) OR (rLoadKg < 0.0) OR (rBeamDepth_mm < 0.0) THEN
        RETURN;
    END_IF;
    // 段 4b｜偏心量域闸：|偏移| 超过梁深一半即视为不可信组态，直接置无效退出（R81 闸席 FAIL(LOGIC) 修法）
    IF ABS(rCgOffset_mm) > (rBeamDepth_mm * 0.5) THEN
        RETURN;
    END_IF;
    // 段 5｜偏心放大系数：取偏移绝对值，负偏移（重心偏向另一侧）同样放大倾覆风险 / use absolute offset
    rEccFactor := 1.0 + ABS(rCgOffset_mm) / rBeamDepth_mm;
    // 段 6｜有效载荷与利用率
    rEffLoadKg := rLoadKg * rEccFactor;
    rUtilPct := rEffLoadKg / rBeamCapKg * DL_PCT;
    // 段 7｜风险位：严格大于门限才置位，等于门限视为可控
    IF rUtilPct > DL_RISK_PCT THEN
        bRisk := TRUE;
    ELSE
        bRisk := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_BeamToppleRiskChk := bValid;
END_FUNCTION
