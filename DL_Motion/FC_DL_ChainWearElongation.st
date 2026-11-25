(*
  ============================================================
  组件名 : FC_DL_ChainWearElongation
  分类   : DL_Motion
  功能   : 链条磨损伸长率计算，由公称节距与实测节距求伸长百分比并给出更换到期判定
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      伸长率 = (实测节距 - 公称节距) / 公称节距 * 100。
      实测节距必须为多节平均后的值，节数少于 3 节时平均值不具代表性，判无效。
      伸长率超过 2.0% 判更换到期；实测小于公称（新链或测量误差）时伸长率为负，判定位保持 FALSE。
  ============================================================
*)
FUNCTION FC_DL_ChainWearElongation : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rPitchNom_mm : REAL; // 公称节距 [mm] / nominal chain pitch [millimetre]
    rPitchAct_mm : REAL; // 实测节距，取多节平均 [mm] / measured pitch averaged over several links [millimetre]
    iLinkCnt     : INT;  // 参与平均的链节数量 [节] / number of links used in the average [link]
END_VAR
VAR_OUTPUT
    rElongPct   : REAL; // 链条磨损伸长率 [%] / chain wear elongation [percent]
    rPitchDelta_mm : REAL; // 实测与公称的节距差 [mm] / pitch difference between the measured and nominal value [millimetre]
    bReplaceDue : BOOL; // 更换到期：TRUE 表示伸长率超过 2.0% / replacement due, TRUE when the elongation exceeds 2.0 percent
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT      : REAL := 100.0;  // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_ELONG_MAX : REAL := 2.0;   // 更换到期伸长率门限 [%] / elongation threshold for the replacement [percent]
    DL_LINK_MIN : INT := 3;       // 平均所需最少链节数 [节] / minimum link count required by the average [link]
    DL_LINK_MAX : INT := 200;     // 链节数量合理上限 [节] / sanity upper bound of the link count [link]
    DL_PITCH_MAX : REAL := 1000.0; // 节距合理上限 [mm] / sanity upper bound of the pitch [millimetre]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
END_VAR

    // 段 1｜出口预置
    rElongPct := 0.0;
    rPitchDelta_mm := 0.0;
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
    _bFin := (rPitchNom_mm = rPitchNom_mm) AND (ABS(rPitchNom_mm) <= DL_R_MAX) AND (rPitchAct_mm = rPitchAct_mm) AND (ABS(rPitchAct_mm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：公称节距严格为正且合理，实测节距非负且合理，链节数 3~200
    IF (ABS(rPitchNom_mm) <= DL_EPS) OR (rPitchNom_mm < 0.0) OR (rPitchNom_mm > DL_PITCH_MAX) THEN
        RETURN;
    END_IF;
    IF (rPitchAct_mm < 0.0) OR (rPitchAct_mm > DL_PITCH_MAX) THEN
        RETURN;
    END_IF;
    IF (iLinkCnt < DL_LINK_MIN) OR (iLinkCnt > DL_LINK_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜节距差与伸长率
    rPitchDelta_mm := rPitchAct_mm - rPitchNom_mm;
    rElongPct := rPitchDelta_mm / rPitchNom_mm * DL_PCT;
    // 段 6｜更换到期判定：仅正向伸长计入磨损
    IF rElongPct > DL_ELONG_MAX THEN
        bReplaceDue := TRUE;
    ELSE
        bReplaceDue := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_ChainWearElongation := bValid;
END_FUNCTION
