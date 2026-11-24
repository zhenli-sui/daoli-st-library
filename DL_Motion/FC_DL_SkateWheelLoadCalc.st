(*
  ============================================================
  组件名 : FC_DL_SkateWheelLoadCalc
  分类   : DL_Motion
  功能   : 滑板轮载荷分配计算，按重心纵向偏移求前后轴占比并折算前轴单轮载荷
  复杂度 : C2
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      前轴占比 = 0.5 + 重心偏移 / 轴距，限幅 0.1~0.9，防止极端重心把全部载荷压到单轴。
      前轴总载 = 总重 * 前轴占比；前轴轮数按 (轮数+1)/2 取整，奇数轮时前轴多分 1 个轮。
      单轮载荷 = 前轴总载 / 前轴轮数；轮数不足 2 个或轴距为零时判无效。
  ============================================================
*)
FUNCTION FC_DL_SkateWheelLoadCalc : BOOL
VAR_INPUT
    bEnable      : BOOL; // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr         : BOOL; // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    rTotalKg     : REAL; // 滑板与载荷总质量 [kg] / total mass of the skate and the load [kilogram]
    iWheelCnt    : INT;  // 滑板轮总数量 [个] / total number of skate wheels [unit]
    rCgOffset_mm : REAL; // 重心相对几何中心的前向偏移 [mm] / forward offset of the centre of gravity from the geometric centre [millimetre]
    rWheelBase_mm : REAL; // 前后轴距 [mm] / distance between the front and rear axles [millimetre]
END_VAR
VAR_OUTPUT
    rFrontShare : REAL; // 前轴载荷占比，限幅 0.1~0.9 [无量纲] / front axle load share clamped to 0.1 to 0.9 [dimensionless]
    rFrontKg    : REAL; // 前轴总载荷 [kg] / total load on the front axle [kilogram]
    iFrontWheelCnt : INT; // 前轴轮数量 [个] / number of wheels on the front axle [unit]
    rPerWheelKg : REAL; // 前轴单个轮的平均载荷 [kg] / average load of one front wheel [kilogram]
    bValid      : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_R_MAX    : REAL := 3.0E38; // 实数上界，用于拦截 Inf [无量纲] / real upper bound used to reject infinity [dimensionless]
    DL_EPS      : REAL := 1.0E-12; // 除零判定阈值 [无量纲] / division guard threshold [dimensionless]
    DL_HALF     : REAL := 0.5;    // 二分之一，均分基准占比 [无量纲] / one half, the balanced share baseline [dimensionless]
    DL_SHARE_LO : REAL := 0.1;    // 前轴占比下限 [无量纲] / lower clamp of the front share [dimensionless]
    DL_SHARE_HI : REAL := 0.9;    // 前轴占比上限 [无量纲] / upper clamp of the front share [dimensionless]
    DL_WHEEL_MIN : INT := 2;      // 轮数下界 [个] / lower bound of the wheel count [unit]
    DL_WHEEL_MAX : INT := 32;     // 轮数上界 [个] / upper bound of the wheel count [unit]
    DL_BASE_MAX : REAL := 10000.0; // 轴距合理上限 [mm] / sanity upper bound of the wheel base [millimetre]
    DL_MASS_MAX : REAL := 100000.0; // 总质量合理上限 [kg] / sanity upper bound of the total mass [kilogram]
    DL_TWO      : INT := 2;       // 取半数用的除数 [无量纲] / divisor used to obtain half of the wheel count [dimensionless]
    DL_ONE      : INT := 1;       // 奇数轮进位偏置 [个] / carry bias used for an odd wheel count [unit]
END_VAR
VAR
    _bFin    : BOOL := FALSE; // 输入有限性判定结果 / input finiteness verdict
    _rShare  : REAL := 0.0;   // 限幅前前轴占比 [无量纲] / raw front share before clamping [dimensionless]
    _rFrontW : REAL := 0.0;   // 前轴轮数折算实数 [个] / front wheel count cast to real [unit]
END_VAR

    // 段 1｜出口预置：占比先置均分，避免下游误用零
    rFrontShare := DL_HALF;
    rFrontKg := 0.0;
    iFrontWheelCnt := 0;
    rPerWheelKg := 0.0;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜非有限闸
    _bFin := (rTotalKg = rTotalKg) AND (ABS(rTotalKg) <= DL_R_MAX) AND (rCgOffset_mm = rCgOffset_mm) AND (ABS(rCgOffset_mm) <= DL_R_MAX) AND (rWheelBase_mm = rWheelBase_mm) AND (ABS(rWheelBase_mm) <= DL_R_MAX);
    IF NOT _bFin THEN
        RETURN;
    END_IF;
    // 段 4｜域闸：轴距严格为正且合理，总质量非负且合理，轮数 2~32
    IF (ABS(rWheelBase_mm) <= DL_EPS) OR (rWheelBase_mm < 0.0) OR (rWheelBase_mm > DL_BASE_MAX) THEN
        RETURN;
    END_IF;
    IF (rTotalKg < 0.0) OR (rTotalKg > DL_MASS_MAX) THEN
        RETURN;
    END_IF;
    IF (iWheelCnt < DL_WHEEL_MIN) OR (iWheelCnt > DL_WHEEL_MAX) THEN
        RETURN;
    END_IF;
    // 段 5｜前轴占比与限幅
    _rShare := DL_HALF + rCgOffset_mm / rWheelBase_mm;
    IF _rShare < DL_SHARE_LO THEN
        rFrontShare := DL_SHARE_LO;
    ELSIF _rShare > DL_SHARE_HI THEN
        rFrontShare := DL_SHARE_HI;
    ELSE
        rFrontShare := _rShare;
    END_IF;
    // 段 6｜前轴轮数：奇数轮时前轴多分一个
    iFrontWheelCnt := (iWheelCnt + DL_ONE) / DL_TWO;
    IF iFrontWheelCnt < DL_ONE THEN
        iFrontWheelCnt := DL_ONE;
    END_IF;
    // 段 7｜前轴总载与单轮载荷
    rFrontKg := rTotalKg * rFrontShare;
    _rFrontW := INT_TO_REAL(iFrontWheelCnt);
    IF ABS(_rFrontW) <= DL_EPS THEN
        RETURN;
    END_IF;
    rPerWheelKg := rFrontKg / _rFrontW;
    bValid := TRUE;
    FC_DL_SkateWheelLoadCalc := bValid;
END_FUNCTION
