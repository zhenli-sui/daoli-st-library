(*
  ============================================================
  组件名 : FC_DL_VacuumPadForceCalc
  分类   : DL_Device
  功能   : 真空吸盘吸附力计算，由吸盘直径与真空度求理论吸附力并按安全系数折算可用力
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      吸附力 F = (pi/4) * (直径/1000)^2 * (真空度*1000)，直径先由 mm 折 m，真空度由 kPa 折 Pa，结果单位 N。
      可用力 = 理论力 / 安全系数；安全系数工程常用 1.5~3，低于 1.0 视为参数错误。
      面积同时以 mm2 输出，便于与样本册的吸盘规格直接对照。
  ============================================================
*)
FUNCTION FC_DL_VacuumPadForceCalc : BOOL
VAR_INPUT
    bEnable  : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr     : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rDia_mm  : REAL; // 吸盘有效直径 [mm] / effective pad diameter [millimetre]
    rVacKpa  : REAL; // 工作真空度 [kPa] / working vacuum level [kilopascal]
    rSafety  : REAL; // 安全系数，常用 1.5~3 [无量纲] / safety factor, typically 1.5 to 3 [dimensionless]
END_VAR
VAR_OUTPUT
    rArea_mm2 : REAL; // 吸盘有效面积 [mm2] / effective pad area [square millimetre]
    rForceN   : REAL; // 理论吸附力 [N] / theoretical holding force [newton]
    rUsableN  : REAL; // 除以安全系数后的可用吸附力 [N] / usable holding force after the safety factor [newton]
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_PI      : REAL := 3.14159265; // 圆周率 [无量纲] / circular constant [dimensionless]
    DL_R_MAX   : REAL := 3.0E38;     // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12;    // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_MM_TO_M : REAL := 1000.0;     // 毫米折米系数 [mm/m] / millimetre to metre factor [millimetre per metre]
    DL_KPA_TO_PA : REAL := 1000.0;   // 千帕折帕系数 [Pa/kPa] / kilopascal to pascal factor [pascal per kilopascal]
    DL_QUARTER : REAL := 0.25;       // 四分之一，用于 pi/4 折算 [无量纲] / one quarter used for the pi over four term [dimensionless]
    DL_SAFE_MIN : REAL := 1.0;       // 安全系数下界 [无量纲] / lower bound of the safety factor [dimensionless]
    DL_SAFE_MAX : REAL := 10.0;      // 安全系数上界 [无量纲] / upper bound of the safety factor [dimensionless]
    DL_VAC_MAX : REAL := 101.3;      // 真空度物理上限，标准大气压 [kPa] / physical upper bound of the vacuum level, standard atmosphere [kilopascal]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rDia  : REAL := 0.0;   // 吸盘直径折算米 [m] / pad diameter in metre [metre]
    _rArea : REAL := 0.0;   // 吸盘有效面积 [m2] / effective pad area [square metre]
    _rPress : REAL := 0.0;  // 压差折算帕 [Pa] / differential pressure in pascal [pascal]
END_VAR

    // 段 1｜出口预置
    rArea_mm2 := 0.0;
    rForceN := 0.0;
    rUsableN := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rDia_mm = rDia_mm) AND (ABS(rDia_mm) <= DL_R_MAX) AND (rVacKpa = rVacKpa) AND (ABS(rVacKpa) <= DL_R_MAX) AND (rSafety = rSafety) AND (ABS(rSafety) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：直径严格为正且不超过 1 m，真空度为正且不超过大气压，安全系数在合理区间
    IF (ABS(rDia_mm) <= DL_EPS) OR (rDia_mm < 0.0) OR (rDia_mm > DL_MM_TO_M) THEN
        RETURN;
    END_IF;
    IF (ABS(rVacKpa) <= DL_EPS) OR (rVacKpa < 0.0) OR (rVacKpa > DL_VAC_MAX) THEN
        RETURN;
    END_IF;
    IF (rSafety < DL_SAFE_MIN) OR (rSafety > DL_SAFE_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜面积换算
    _rDia := rDia_mm / DL_MM_TO_M;
    _rArea := DL_PI * DL_QUARTER * _rDia * _rDia;
    rArea_mm2 := DL_PI * (rDia_mm * 0.5) * (rDia_mm * 0.5);
    // 段 6｜理论吸附力：面积乘压差
    _rPress := rVacKpa * DL_KPA_TO_PA;
    rForceN := _rArea * _rPress;
    // 段 7｜安全系数除前闸后再算可用力
    IF ABS(rSafety) <= DL_EPS THEN
        RETURN;
    END_IF;
    rUsableN := rForceN / rSafety;
    bValid := TRUE;
    FC_DL_VacuumPadForceCalc := bValid;
END_FUNCTION
