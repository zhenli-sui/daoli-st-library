(*
  ============================================================
  组件名 : FC_DL_RinseWaterVolumeCalc
  分类   : DL_Process
  功能   : 冲洗水量计算，由管径管长求管容并按冲洗次数与残留系数折算总耗水量
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      管容 = pi * (内径/2000)^2 * 管长 * 1000，内径由 mm 先折 m 再折 L，单位链不可省略。
      总水量 = 管容 * 冲洗次数 * (1 + 残留系数)；残留系数限定 0~1。
  ============================================================
*)
FUNCTION FC_DL_RinseWaterVolumeCalc : BOOL
VAR_INPUT
    bEnable       : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr          : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rPipeLen_m    : REAL; // 管道长度 [m] / pipe length [metre]
    rPipeDia_mm   : REAL; // 管道内径 [mm] / pipe inner diameter [millimetre]
    iRinseCount   : INT;  // 冲洗次数 [次] / number of rinse cycles [time]
    rResidFactor  : REAL; // 残留附加系数 [无量纲] / residual surcharge factor [dimensionless]
END_VAR
VAR_OUTPUT
    rPipeVol_L  : REAL; // 单管容积 [L] / single pipe volume [litre]
    rTotalVol_L : REAL; // 全次数冲洗总水量 [L] / total rinse water volume over all cycles [litre]
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_PI      : REAL := 3.14159265; // 圆周率 [无量纲] / circular constant [dimensionless]
    DL_R_MAX   : REAL := 3.0E38;     // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS     : REAL := 1.0E-12;    // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_MM_TO_M : REAL := 2000.0;     // 直径毫米折半径米的除数 [无量纲] / divisor converting diameter in mm into radius in m [dimensionless]
    DL_M3_TO_L : REAL := 1000.0;     // 立方米折升系数 [L/m3] / cubic metre to litre factor [litre per cubic metre]
    DL_ONE     : REAL := 1.0;        // 单位常量 [无量纲] / unity constant [dimensionless]
    DL_MAX_RINSE : INT := 100;       // 冲洗次数上限 [次] / upper bound of the rinse count [time]
END_VAR
VAR
    _bFin  : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rRad  : REAL := 0.0;   // 管道内半径 [m] / pipe inner radius [metre]
    _rArea : REAL := 0.0;   // 管道过流截面积 [m2] / pipe flow cross section area [square metre]
    _rCnt  : REAL := 0.0;   // 冲洗次数折算实数 [次] / rinse count cast to real [time]
END_VAR

    // 段 1｜出口预置
    rPipeVol_L := 0.0;
    rTotalVol_L := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rPipeLen_m = rPipeLen_m) AND (ABS(rPipeLen_m) <= DL_R_MAX) AND (rPipeDia_mm = rPipeDia_mm) AND (ABS(rPipeDia_mm) <= DL_R_MAX) AND (rResidFactor = rResidFactor) AND (ABS(rResidFactor) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：管长非负、管径严格为正、冲洗次数 1~100、残留系数 0~1
    IF (rPipeLen_m < 0.0) OR (ABS(rPipeDia_mm) <= DL_EPS) OR (rPipeDia_mm < 0.0) THEN
        RETURN;
    END_IF;
    IF (iRinseCount < 1) OR (iRinseCount > DL_MAX_RINSE) THEN
        RETURN;
    END_IF;
    IF (rResidFactor < 0.0) OR (rResidFactor > DL_ONE) THEN
        RETURN;
    END_IF;
    // 段 5｜截面积与单管容积
    _rRad := rPipeDia_mm / DL_MM_TO_M;
    _rArea := DL_PI * _rRad * _rRad;
    rPipeVol_L := _rArea * rPipeLen_m * DL_M3_TO_L;
    // 段 6｜总水量
    _rCnt := INT_TO_REAL(iRinseCount);
    rTotalVol_L := rPipeVol_L * _rCnt * (DL_ONE + rResidFactor);
    bValid := TRUE;
    FC_DL_RinseWaterVolumeCalc := bValid;
END_FUNCTION
