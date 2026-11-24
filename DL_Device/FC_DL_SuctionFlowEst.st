(*
  ============================================================
  组件名 : FC_DL_SuctionFlowEst
  分类   : DL_Device
  功能   : 真空抽吸流量估算，按喷嘴直径真空度与流量系数求可达到的抽吸体积流量
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      孔口流量式 Q = Cd * (pi/4) * (直径/1000)^2 * SQRT(2*压差/密度)，压差由 kPa 折 Pa，密度取 1.2 kg/m3。
      Q 的自然单位为 m3/s，乘以 60000/1000 即乘 60 后得到 L/min。
      该式为不可压缩孔口近似，仅在压比不进入临界区时可用，属工程估算而非精确标定。
  ============================================================
*)
FUNCTION FC_DL_SuctionFlowEst : BOOL
VAR_INPUT
    bEnable  : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr     : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rDia_mm  : REAL; // 抽吸喷嘴等效直径 [mm] / equivalent nozzle diameter [millimetre]
    rVacKpa  : REAL; // 工作真空度 [kPa] / working vacuum level [kilopascal]
    rCd      : REAL; // 流量系数，常用 0.6~0.85 [无量纲] / discharge coefficient, typically 0.6 to 0.85 [dimensionless]
END_VAR
VAR_OUTPUT
    rVel_ms   : REAL; // 孔口等效流速 [m/s] / equivalent orifice velocity [metre per second]
    rFlowLpm  : REAL; // 折算抽吸流量 [L/min] / equivalent suction flow [litre per minute]
    rFlowNm3h : REAL; // 折算标准状态流量 [Nm3/h] / equivalent normal flow [normal cubic metre per hour]
    bValid    : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_PI       : REAL := 3.14159265; // 圆周率 [无量纲] / circular constant [dimensionless]
    DL_R_MAX    : REAL := 3.0E38;     // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12;    // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_MM_TO_M  : REAL := 1000.0;     // 毫米折米系数 [mm/m] / millimetre to metre factor [millimetre per metre]
    DL_KPA_TO_PA : REAL := 1000.0;    // 千帕折帕系数 [Pa/kPa] / kilopascal to pascal factor [pascal per kilopascal]
    DL_RHO      : REAL := 1.2;        // 空气密度 [kg/m3] / air density [kilogram per cubic metre]
    DL_QUARTER  : REAL := 0.25;       // 四分之一，用于 pi/4 折算 [无量纲] / one quarter used for the pi over four term [dimensionless]
    DL_M3S_TO_LPM : REAL := 60000.0;  // 立方米每秒折升每分系数（含 1/1000 体积换算）[无量纲] / cubic metre per second to litre per minute factor [dimensionless]
    DL_M3S_TO_NM3H : REAL := 3600.0;  // 立方米每秒折立方米每小时系数 [无量纲] / cubic metre per second to cubic metre per hour factor [dimensionless]
    DL_CD_MIN   : REAL := 0.1;        // 流量系数可信下界 [无量纲] / credible lower bound of the discharge coefficient [dimensionless]
    DL_CD_MAX   : REAL := 1.0;        // 流量系数物理上界 [无量纲] / physical upper bound of the discharge coefficient [dimensionless]
    DL_VAC_MAX  : REAL := 101.3;      // 真空度物理上限，标准大气压 [kPa] / physical upper bound of the vacuum level, standard atmosphere [kilopascal]
    DL_DIA_MAX  : REAL := 1000.0;     // 喷嘴直径合理上限 [mm] / sanity upper bound of the nozzle diameter [millimetre]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rDia  : REAL := 0.0;   // 喷嘴直径折算米 [m] / nozzle diameter in metre [metre]
    _rArea : REAL := 0.0;   // 喷嘴过流面积 [m2] / nozzle flow area [square metre]
    _rPress : REAL := 0.0;  // 压差折算帕 [Pa] / differential pressure in pascal [pascal]
    _rTerm : REAL := 0.0;   // 流速根号内被开方数 [m2/s2] / radicand of the velocity square root [square metre per square second]
    _rQm3s : REAL := 0.0;   // 体积流量 [m3/s] / volumetric flow [cubic metre per second]
END_VAR

    // 段 1｜出口预置
    rVel_ms := 0.0;
    rFlowLpm := 0.0;
    rFlowNm3h := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rDia_mm = rDia_mm) AND (ABS(rDia_mm) <= DL_R_MAX) AND (rVacKpa = rVacKpa) AND (ABS(rVacKpa) <= DL_R_MAX) AND (rCd = rCd) AND (ABS(rCd) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸
    IF (ABS(rDia_mm) <= DL_EPS) OR (rDia_mm < 0.0) OR (rDia_mm > DL_DIA_MAX) THEN
        RETURN;
    END_IF;
    IF (ABS(rVacKpa) <= DL_EPS) OR (rVacKpa < 0.0) OR (rVacKpa > DL_VAC_MAX) THEN
        RETURN;
    END_IF;
    IF (rCd < DL_CD_MIN) OR (rCd > DL_CD_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜面积与压差
    _rDia := rDia_mm / DL_MM_TO_M;
    _rArea := DL_PI * DL_QUARTER * _rDia * _rDia;
    _rPress := rVacKpa * DL_KPA_TO_PA;
    // 段 6｜开方前必须确认被开方数非负，密度分母已按常数保证为正
    _rTerm := 2.0 * _rPress / DL_RHO;
    IF _rTerm < 0.0 THEN
        RETURN;
    END_IF;
    rVel_ms := SQRT(_rTerm);
    // 段 7｜体积流量与单位折算
    _rQm3s := rCd * _rArea * rVel_ms;
    rFlowLpm := _rQm3s * DL_M3S_TO_LPM;
    rFlowNm3h := _rQm3s * DL_M3S_TO_NM3H;
    bValid := TRUE;
    FC_DL_SuctionFlowEst := bValid;
END_FUNCTION
