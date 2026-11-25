(*
  ============================================================
  组件名 : FC_DL_SipResidueVolumeEst
  分类   : DL_Process
  功能   : SIP 灭菌残留量估算，按主管坡度排空残量与盲管滞留量折算残留升数与占比
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      主管理论容 = pi * (内径/2000)^2 * 管长 * 1000 [L]。
      坡度排空残留 = 主管理论容 * SIN(坡度) * 0.5，系数 0.5 表示理想排空后仍滞留一半的坡度积液。
      盲管容 = pi * (内径/2000)^2 * 盲管总长 * 1000，按 15% 滞留计。
      残留占比 = 总残留 / 主管理论容 * 100，主管理论容非正时判无效。
  ============================================================
*)
FUNCTION FC_DL_SipResidueVolumeEst : BOOL
VAR_INPUT
    bEnable     : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr        : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rPipeLen_m  : REAL; // 主管长度 [m] / main pipe length [metre]
    rPipeDia_mm : REAL; // 管道内径 [mm] / pipe inner diameter [millimetre]
    rSlopeDeg   : REAL; // 主管安装坡度 [度] / installation slope of the main pipe [degree]
    rBlindLen_m : REAL; // 盲管总长度 [m] / total length of blind branches [metre]
END_VAR
VAR_OUTPUT
    rMainVol_L  : REAL; // 主管理论容积 [L] / theoretical main pipe volume [litre]
    rBlindVol_L : REAL; // 盲管理论容积 [L] / theoretical blind branch volume [litre]
    rResidueL   : REAL; // 估算残留总量 [L] / estimated total residue volume [litre]
    rResiduePct : REAL; // 残留占主管容积百分比 [%] / residue percentage over the main pipe volume [percent]
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_PI        : REAL := 3.14159265; // 圆周率 [无量纲] / circular constant [dimensionless]
    DL_R_MAX     : REAL := 3.0E38;     // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS       : REAL := 1.0E-12;    // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_MM_TO_M   : REAL := 2000.0;     // 直径毫米折半径米的除数 [无量纲] / divisor converting diameter in mm into radius in m [dimensionless]
    DL_M3_TO_L   : REAL := 1000.0;     // 立方米折升系数 [L/m3] / cubic metre to litre factor [litre per cubic metre]
    DL_DEG_TO_RAD : REAL := 0.0174533; // 度转弧度系数 [rad/度] / degree to radian factor [radian per degree]
    DL_SLOPE_K   : REAL := 0.5;        // 坡度排空滞留系数 [无量纲] / slope drainage retention factor [dimensionless]
    DL_BLIND_K   : REAL := 0.15;       // 盲管滞留系数 [无量纲] / blind branch retention factor [dimensionless]
    DL_PCT       : REAL := 100.0;      // 百分数换算系数 [无量纲] / percentage scaling factor [dimensionless]
    DL_SLOPE_MAX : REAL := 90.0;       // 坡度允许上限 [度] / permitted upper bound of the slope [degree]
END_VAR
VAR
    _bFin   : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rRad   : REAL := 0.0;   // 管道内半径 [m] / pipe inner radius [metre]
    _rArea  : REAL := 0.0;   // 管道过流截面积 [m2] / pipe flow cross section area [square metre]
    _rResM  : REAL := 0.0;   // 主管坡度排空残留 [L] / slope drainage residue of the main pipe [litre]
    _rResB  : REAL := 0.0;   // 盲管滞留残留 [L] / retained residue in blind branches [litre]
    _rSin   : REAL := 0.0;   // 坡度的正弦值 [无量纲] / sine of the slope angle [dimensionless]
END_VAR

    // 段 1｜出口预置
    rMainVol_L := 0.0;
    rBlindVol_L := 0.0;
    rResidueL := 0.0;
    rResiduePct := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rPipeLen_m = rPipeLen_m) AND (ABS(rPipeLen_m) <= DL_R_MAX) AND (rPipeDia_mm = rPipeDia_mm) AND (ABS(rPipeDia_mm) <= DL_R_MAX) AND (rSlopeDeg = rSlopeDeg) AND (ABS(rSlopeDeg) <= DL_R_MAX) AND (rBlindLen_m = rBlindLen_m) AND (ABS(rBlindLen_m) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸
    IF (rPipeLen_m < 0.0) OR (rBlindLen_m < 0.0) OR (ABS(rPipeDia_mm) <= DL_EPS) OR (rPipeDia_mm < 0.0) THEN
        RETURN;
    END_IF;
    IF (rSlopeDeg < 0.0) OR (rSlopeDeg > DL_SLOPE_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜截面积
    _rRad := rPipeDia_mm / DL_MM_TO_M;
    _rArea := DL_PI * _rRad * _rRad;
    // 段 6｜主管理与盲管容积
    rMainVol_L := _rArea * rPipeLen_m * DL_M3_TO_L;
    rBlindVol_L := _rArea * rBlindLen_m * DL_M3_TO_L;
    // 段 7｜主管理论容非正闸，同时保护后续占比除法
    IF ABS(rMainVol_L) <= DL_EPS THEN
        RETURN;
    END_IF;
    // 段 8｜残留量
    _rSin := SIN(rSlopeDeg * DL_DEG_TO_RAD);
    _rResM := rMainVol_L * _rSin * DL_SLOPE_K;
    _rResB := rBlindVol_L * DL_BLIND_K;
    rResidueL := _rResM + _rResB;
    // 段 9｜残留占比
    rResiduePct := rResidueL / rMainVol_L * DL_PCT;
    bValid := TRUE;
    FC_DL_SipResidueVolumeEst := bValid;
END_FUNCTION
