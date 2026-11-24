(*
  ============================================================
  组件名 : FC_DL_TrackingOffsetChk
  分类   : DL_Motion
  功能   : 跟踪偏移校验，由编码器累计脉冲折算实际位移并与基准距离比较给出漂移报警
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      实际距离 = 累计脉冲数 / 每米脉冲数；偏移 = 实际距离 - 基准距离。
      偏移绝对值超过容差置漂移报警；每米脉冲为零时无法折算，判无效。
      脉冲数允许为负，表示编码器反向计数，此时实际距离为负，属正常工况不作拦截。
  ============================================================
*)
FUNCTION FC_DL_TrackingOffsetChk : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时校验 / Enable: TRUE to check
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rEncoderCnt : REAL; // 编码器累计脉冲数，带符号 [脉冲] / accumulated encoder counts with sign [count]
    rPulsePerM  : REAL; // 每米对应的脉冲数 [脉冲/m] / encoder counts per metre [count per metre]
    rRefM       : REAL; // 基准跟踪距离 [m] / reference tracking distance [metre]
    rTolM       : REAL; // 允许的偏移容差 [m] / permitted offset tolerance [metre]
END_VAR
VAR_OUTPUT
    rActM      : REAL; // 由脉冲折算的实际距离 [m] / actual distance derived from the counts [metre]
    rOffsetM   : REAL; // 实际距离相对基准的偏移 [m] / offset of the actual distance from the reference [metre]
    bDriftAlarm : BOOL; // 漂移报警：TRUE 表示偏移绝对值超过容差 / drift alarm, TRUE when the absolute offset exceeds the tolerance
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38;   // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12;  // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PULSE_MAX : REAL := 1.0E9;   // 每米脉冲合理上限 [脉冲/m] / sanity upper bound of the counts per metre [count per metre]
    DL_DIST_MAX : REAL := 100000.0; // 距离合理上限 [m] / sanity upper bound of the distance [metre]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rAbs  : REAL := 0.0;   // 偏移绝对值 [m] / absolute offset [metre]
END_VAR

    // 段 1｜出口预置
    rActM := 0.0;
    rOffsetM := 0.0;
    bDriftAlarm := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rEncoderCnt = rEncoderCnt) AND (ABS(rEncoderCnt) <= DL_R_MAX) AND (rPulsePerM = rPulsePerM) AND (ABS(rPulsePerM) <= DL_R_MAX) AND (rRefM = rRefM) AND (ABS(rRefM) <= DL_R_MAX) AND (rTolM = rTolM) AND (ABS(rTolM) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：每米脉冲严格为正且合理，基准距离与容差非负
    IF (ABS(rPulsePerM) <= DL_EPS) OR (rPulsePerM < 0.0) OR (rPulsePerM > DL_PULSE_MAX) THEN
        RETURN;
    END_IF;
    IF (rRefM < 0.0) OR (rRefM > DL_DIST_MAX) OR (rTolM < 0.0) OR (rTolM > DL_DIST_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜实际距离与偏移
    rActM := rEncoderCnt / rPulsePerM;
    rOffsetM := rActM - rRefM;
    // 段 6｜漂移报警
    _rAbs := ABS(rOffsetM);
    IF _rAbs > rTolM THEN
        bDriftAlarm := TRUE;
    ELSE
        bDriftAlarm := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_TrackingOffsetChk := bValid;
END_FUNCTION
