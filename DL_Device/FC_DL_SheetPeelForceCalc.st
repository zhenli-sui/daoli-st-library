(*
  ============================================================
  组件名 : FC_DL_SheetPeelForceCalc
  分类   : DL_Device
  功能   : 片材剥离力计算，由接触面积粘附强度与静电电压求剥离力并按剥离角折减
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      粘附分量 = 接触面积(m2) * 粘附强度(Pa)，面积由 mm2 乘 1e-6，强度由 kPa 乘 1000。
      静电分量 = 静电电压(kV) * 0.05，系数为工程经验折算，单位 N/kV。
      剥离角修正系数 = (1 + COS(角度)) / 2，归一到 0 度时为 1、90 度为 0.5、180 度为 0，便于跨机型比较。
      剥离力超过 50 N 判需要外部辅助剥离。
  ============================================================
*)
FUNCTION FC_DL_SheetPeelForceCalc : BOOL
VAR_INPUT
    bEnable       : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr          : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rArea_mm2     : REAL; // 片材与承载面接触面积 [mm2] / contact area between sheet and support [square millimetre]
    rAdhesion_kpa : REAL; // 单位面积粘附强度 [kPa] / adhesion strength per unit area [kilopascal]
    rStaticKv     : REAL; // 片材静电电位 [kV] / electrostatic potential of the sheet [kilovolt]
    rPeelAngleDeg : REAL; // 剥离角度，0 度表示垂直拉起 [度] / peel angle, zero means lifting perpendicular [degree]
END_VAR
VAR_OUTPUT
    rAdhesionN : REAL; // 粘附力分量 [N] / adhesion force component [newton]
    rStaticN   : REAL; // 静电力分量 [N] / electrostatic force component [newton]
    rAngleFactor : REAL; // 剥离角折减系数，0~1 [无量纲] / peel angle reduction factor from 0 to 1 [dimensionless]
    rPeelN     : REAL; // 综合剥离力 [N] / resultant peel force [newton]
    bNeedAssist : BOOL; // 需要辅助：TRUE 表示剥离力超过 50 N / assistance required, TRUE when the peel force exceeds 50 newton
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX     : REAL := 3.0E38;     // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS       : REAL := 1.0E-12;    // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_MM2_TO_M2 : REAL := 1.0E-6;     // 平方毫米折平方米系数 [m2/mm2] / square millimetre to square metre factor [square metre per square millimetre]
    DL_KPA_TO_PA : REAL := 1000.0;     // 千帕折帕系数 [Pa/kPa] / kilopascal to pascal factor [pascal per kilopascal]
    DL_KV_TO_N   : REAL := 0.05;       // 每千伏静电折算力 [N/kV] / electrostatic force per kilovolt [newton per kilovolt]
    DL_DEG_TO_RAD : REAL := 0.0174533; // 度转弧度系数 [rad/度] / degree to radian factor [radian per degree]
    DL_HALF      : REAL := 0.5;        // 二分之一，用于角度系数归一 [无量纲] / one half used to normalise the angle factor [dimensionless]
    DL_ONE       : REAL := 1.0;        // 单位常量 [无量纲] / unity constant [dimensionless]
    DL_ASSIST_N  : REAL := 50.0;       // 辅助剥离门限 [N] / assistance threshold [newton]
    DL_ANGLE_MAX : REAL := 180.0;      // 剥离角允许上限 [度] / permitted upper bound of the peel angle [degree]
    DL_STAT_MAX  : REAL := 1000.0;     // 静电电位合理上限 [kV] / sanity upper bound of the electrostatic potential [kilovolt]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rRad  : REAL := 0.0;   // 剥离角折算弧度 [rad] / peel angle in radian [radian]
END_VAR

    // 段 1｜出口预置
    rAdhesionN := 0.0;
    rStaticN := 0.0;
    rAngleFactor := 0.0;
    rPeelN := 0.0;
    bNeedAssist := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rArea_mm2 = rArea_mm2) AND (ABS(rArea_mm2) <= DL_R_MAX) AND (rAdhesion_kpa = rAdhesion_kpa) AND (ABS(rAdhesion_kpa) <= DL_R_MAX) AND (rStaticKv = rStaticKv) AND (ABS(rStaticKv) <= DL_R_MAX) AND (rPeelAngleDeg = rPeelAngleDeg) AND (ABS(rPeelAngleDeg) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：面积非负、粘附强度非负、静电位非负且合理、角度 0~180
    IF (rArea_mm2 < 0.0) OR (rAdhesion_kpa < 0.0) OR (rStaticKv < 0.0) OR (rStaticKv > DL_STAT_MAX) THEN
        RETURN;
    END_IF;
    IF (rPeelAngleDeg < 0.0) OR (rPeelAngleDeg > DL_ANGLE_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜两个力分量
    rAdhesionN := rArea_mm2 * DL_MM2_TO_M2 * rAdhesion_kpa * DL_KPA_TO_PA;
    rStaticN := rStaticKv * DL_KV_TO_N;
    // 段 6｜角度折减系数
    _rRad := rPeelAngleDeg * DL_DEG_TO_RAD;
    rAngleFactor := (DL_ONE + COS(_rRad)) * DL_HALF;
    IF rAngleFactor < 0.0 THEN
        rAngleFactor := 0.0;
    END_IF;
    IF rAngleFactor > DL_ONE THEN
        rAngleFactor := DL_ONE;
    END_IF;
    // 段 7｜综合剥离力
    rPeelN := (rAdhesionN + rStaticN) * rAngleFactor;
    // 段 8｜辅助判定
    IF rPeelN > DL_ASSIST_N THEN
        bNeedAssist := TRUE;
    ELSE
        bNeedAssist := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_SheetPeelForceCalc := bValid;
END_FUNCTION
