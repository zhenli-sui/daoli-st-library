(*
  ============================================================
  组件名 : FC_DL_LaneDiverterAngleCalc
  分类   : DL_Motion
  功能   : 道岔转角计算，由包件宽度与道间距求最小偏转角并折算通过时间与速度许可
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      最小转角 = ATAN(包件宽度 / 道间距)，ATAN 以弧度返回，再除以 0.0174533 折算为度。
      通过时间 = (包件长度/1000) / (线速度/60)，即长度折米后除以速度折 m/s。
      线速度不超过 60 m/min 判速度许可；速度为 0 时通过时间无定义，判无效。
  ============================================================
*)
FUNCTION FC_DL_LaneDiverterAngleCalc : BOOL
VAR_INPUT
    bEnable    : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr       : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rPkgW_mm   : REAL; // 包件宽度，垂直于输送方向 [mm] / package width perpendicular to the conveying direction [millimetre]
    rPkgL_mm   : REAL; // 包件长度，沿输送方向 [mm] / package length along the conveying direction [millimetre]
    rLaneGap_mm : REAL; // 相邻道中心间距 [mm] / centre distance between adjacent lanes [millimetre]
    rSpeedMpm  : REAL; // 输送线速度 [m/min] / conveyor line speed [metre per minute]
END_VAR
VAR_OUTPUT
    rAngleRad : REAL; // 最小偏转角 [rad] / minimum divert angle [radian]
    rAngleDeg : REAL; // 最小偏转角 [度] / minimum divert angle [degree]
    rCrossTime_s : REAL; // 包件通过道岔所需时间 [s] / time for the package to cross the diverter [second]
    bSpeedOk  : BOOL; // 速度许可：TRUE 表示线速度不超过 60 m/min / speed permitted, TRUE when the line speed is within 60 metres per minute
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX     : REAL := 3.0E38;   // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS       : REAL := 1.0E-12;  // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_RAD_TO_DEG : REAL := 0.0174533; // 弧度转度系数 [度/rad] / radian to degree factor [degree per radian]
    DL_MM_TO_M   : REAL := 1000.0;   // 毫米折米系数 [mm/m] / millimetre to metre factor [millimetre per metre]
    DL_MIN_PER_S : REAL := 60.0;     // 每分钟秒数 [s/min] / seconds per minute [second per minute]
    DL_SPEED_OK  : REAL := 60.0;     // 允许的最高线速度 [m/min] / permitted maximum line speed [metre per minute]
    DL_SPEED_MAX : REAL := 600.0;    // 线速度合理上限 [m/min] / sanity upper bound of the line speed [metre per minute]
    DL_GAP_MIN   : REAL := 1.0;      // 道间距合理下限 [mm] / sanity lower bound of the lane gap [millimetre]
    DL_GAP_MAX   : REAL := 10000.0;  // 道间距合理上限 [mm] / sanity upper bound of the lane gap [millimetre]
    DL_SIZE_MAX  : REAL := 5000.0;   // 包件尺寸合理上限 [mm] / sanity upper bound of the package dimension [millimetre]
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rLenM   : REAL := 0.0;   // 包件长度折算米 [m] / package length in metre [metre]
    _rSpdMs  : REAL := 0.0;   // 线速度折算米每秒 [m/s] / line speed in metre per second [metre per second]
END_VAR

    // 段 1｜出口预置
    rAngleRad := 0.0;
    rAngleDeg := 0.0;
    rCrossTime_s := 0.0;
    bSpeedOk := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rPkgW_mm = rPkgW_mm) AND (ABS(rPkgW_mm) <= DL_R_MAX) AND (rPkgL_mm = rPkgL_mm) AND (ABS(rPkgL_mm) <= DL_R_MAX) AND (rLaneGap_mm = rLaneGap_mm) AND (ABS(rLaneGap_mm) <= DL_R_MAX) AND (rSpeedMpm = rSpeedMpm) AND (ABS(rSpeedMpm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：包件尺寸非负且合理，道间距在合理区间，速度严格为正且合理
    IF (rPkgW_mm < 0.0) OR (rPkgW_mm > DL_SIZE_MAX) OR (rPkgL_mm < 0.0) OR (rPkgL_mm > DL_SIZE_MAX) THEN
        RETURN;
    END_IF;
    IF (rLaneGap_mm < DL_GAP_MIN) OR (rLaneGap_mm > DL_GAP_MAX) THEN
        RETURN;
    END_IF;
    IF (ABS(rSpeedMpm) <= DL_EPS) OR (rSpeedMpm < 0.0) OR (rSpeedMpm > DL_SPEED_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜最小转角
    rAngleRad := ATAN(rPkgW_mm / rLaneGap_mm);
    rAngleDeg := rAngleRad / DL_RAD_TO_DEG;
    // 段 6｜通过时间：长度折米、速度折米每秒
    _rLenM := rPkgL_mm / DL_MM_TO_M;
    _rSpdMs := rSpeedMpm / DL_MIN_PER_S;
    IF ABS(_rSpdMs) <= DL_EPS THEN
        RETURN;
    END_IF;
    rCrossTime_s := _rLenM / _rSpdMs;
    // 段 7｜速度许可
    IF rSpeedMpm <= DL_SPEED_OK THEN
        bSpeedOk := TRUE;
    ELSE
        bSpeedOk := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_LaneDiverterAngleCalc := bValid;
END_FUNCTION
