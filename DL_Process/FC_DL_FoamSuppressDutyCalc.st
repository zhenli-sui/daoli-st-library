(*
  ============================================================
  组件名 : FC_DL_FoamSuppressDutyCalc
  分类   : DL_Process
  功能   : 抑泡剂投加占空比计算，按液位抬高、灌装速率与基准投加量合成占空比并限幅
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      占空比 = 基准投加量 * (1 + 液位/100) * 灌装速率 / 100，结果限幅到 0~100。
      液位越高泡沫越易生成，故以液位对基准投加量做上浮修正；限幅保证输出可直接驱动 PWM。
  ============================================================
*)
FUNCTION FC_DL_FoamSuppressDutyCalc : BOOL
VAR_INPUT
    bEnable    : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr       : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rLevelPct  : REAL; // 当前液位百分比 [%] / current liquid level [percent]
    rFillRate  : REAL; // 灌装体积速率 [L/min] / filling volumetric rate [litre per minute]
    rDoseBase  : REAL; // 基准投加量 [mL/L] / base dosing quantity [millilitre per litre]
END_VAR
VAR_OUTPUT
    rDutyPct     : REAL; // 抑泡投加占空比，限幅 0~100 [%] / foam suppression duty cycle clamped to 0 to 100 [percent]
    rDoseRawPct  : REAL; // 限幅前的原始占空比 [%] / raw duty cycle before clamping [percent]
    bClamped     : BOOL; // 限幅生效：TRUE 表示输出被截断 / clamping active, TRUE means the output was truncated
    bValid       : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX  : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS    : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_PCT    : REAL := 100.0;   // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_DUTY_HI : REAL := 100.0;  // 占空比上限 [%] / duty cycle upper limit [percent]
    DL_DUTY_LO : REAL := 0.0;    // 占空比下限 [%] / duty cycle lower limit [percent]
    DL_LEVEL_HI : REAL := 100.0; // 液位允许上限 [%] / permitted upper bound of the level [percent]
END_VAR
VAR
    _bFin : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rLvl : REAL := 0.0;   // 液位修正系数 [无量纲] / level correction factor [dimensionless]
END_VAR

    // 段 1｜出口预置
    rDutyPct := 0.0;
    rDoseRawPct := 0.0;
    bClamped := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rLevelPct = rLevelPct) AND (ABS(rLevelPct) <= DL_R_MAX) AND (rFillRate = rFillRate) AND (ABS(rFillRate) <= DL_R_MAX) AND (rDoseBase = rDoseBase) AND (ABS(rDoseBase) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：液位 0~100，速率与投加量不得为负
    IF (rLevelPct < DL_DUTY_LO) OR (rLevelPct > DL_LEVEL_HI) THEN
        RETURN;
    END_IF;
    IF (rFillRate < DL_DUTY_LO) OR (rDoseBase < DL_DUTY_LO) THEN
        RETURN;
    END_IF;
    // 段 5｜主体合成：液位越高修正系数越大
    _rLvl := 1.0 + rLevelPct / DL_PCT;
    rDoseRawPct := rDoseBase * _rLvl * rFillRate / DL_PCT;
    // 段 6｜限幅并记录截断标志
    IF rDoseRawPct > DL_DUTY_HI THEN
        rDutyPct := DL_DUTY_HI;
        bClamped := TRUE;
    ELSIF rDoseRawPct < DL_DUTY_LO THEN
        rDutyPct := DL_DUTY_LO;
        bClamped := TRUE;
    ELSE
        rDutyPct := rDoseRawPct;
        bClamped := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_FoamSuppressDutyCalc := bValid;
END_FUNCTION
