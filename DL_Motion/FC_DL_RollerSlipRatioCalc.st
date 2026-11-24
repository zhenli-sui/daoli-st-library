(*
  ============================================================
  组件名 : FC_DL_RollerSlipRatioCalc
  分类   : DL_Motion
  功能   : 辊筒打滑率计算，由输送带速与辊面线速求相对打滑比例并给出打滑报警
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      打滑率 = (辊面线速 - 带速) / 辊面线速 * 100，限幅 -100~100。
      正值表示带速低于辊面速度即打滑，负值表示带速快于辊面速度即被拖动。
      打滑率绝对值超过 5% 置打滑报警；辊面线速为零时打滑率无定义，判无效。
  ============================================================
*)
FUNCTION FC_DL_RollerSlipRatioCalc : BOOL
VAR_INPUT
    bEnable    : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr       : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rBeltMpm   : REAL; // 输送带实际线速度 [m/min] / actual belt speed [metre per minute]
    rRollerMpm : REAL; // 辊筒表面线速度 [m/min] / roller surface speed [metre per minute]
END_VAR
VAR_OUTPUT
    rSlipPct   : REAL; // 打滑率，限幅 -100~100 [%] / slip ratio clamped between minus 100 and 100 [percent]
    bSlipAlarm : BOOL; // 打滑报警：TRUE 表示打滑率绝对值超过 5% / slip alarm, TRUE when the absolute slip ratio exceeds 5 percent
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38;   // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12;  // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT      : REAL := 100.0;    // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_SLIP_HI  : REAL := 100.0;    // 打滑率限幅上限 [%] / upper clamp of the slip ratio [percent]
    DL_SLIP_LO  : REAL := -100.0;   // 打滑率限幅下限 [%] / lower clamp of the slip ratio [percent]
    DL_ALARM_PCT : REAL := 5.0;     // 打滑报警门限 [%] / slip alarm threshold [percent]
    DL_SPEED_MAX : REAL := 10000.0; // 线速度合理上限 [m/min] / sanity upper bound of the line speed [metre per minute]
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rRaw   : REAL := 0.0;   // 限幅前打滑率 [%] / raw slip ratio before clamping [percent]
    _rAbs   : REAL := 0.0;   // 打滑率绝对值 [%] / absolute slip ratio [percent]
END_VAR

    // 段 1｜出口预置
    rSlipPct := 0.0;
    bSlipAlarm := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rBeltMpm = rBeltMpm) AND (ABS(rBeltMpm) <= DL_R_MAX) AND (rRollerMpm = rRollerMpm) AND (ABS(rRollerMpm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：辊面线速严格为正，带速非负，两者均不超过合理上限
    IF (ABS(rRollerMpm) <= DL_EPS) OR (rRollerMpm < 0.0) OR (rRollerMpm > DL_SPEED_MAX) THEN
        RETURN;
    END_IF;
    IF (rBeltMpm < 0.0) OR (rBeltMpm > DL_SPEED_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜打滑率原值
    _rRaw := (rRollerMpm - rBeltMpm) / rRollerMpm * DL_PCT;
    // 段 6｜限幅
    IF _rRaw < DL_SLIP_LO THEN
        rSlipPct := DL_SLIP_LO;
    ELSIF _rRaw > DL_SLIP_HI THEN
        rSlipPct := DL_SLIP_HI;
    ELSE
        rSlipPct := _rRaw;
    END_IF;
    // 段 7｜报警判定
    _rAbs := ABS(rSlipPct);
    IF _rAbs > DL_ALARM_PCT THEN
        bSlipAlarm := TRUE;
    ELSE
        bSlipAlarm := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_RollerSlipRatioCalc := bValid;
END_FUNCTION
