(*
 * FC_DL_PouringTimeCalc | C2 | DL_Process
 * 功能：浇注时间估算（浇注重量平方根经验式）与上下限钳位       单位：重量 [kg]、系数 [s/√kg]、时间 [s]
 * 工况边界：经验式 t = k×√G，k 取 1.8 s/√kg（灰铸铁中小件典型值）；仅适用于重力浇注且浇口未更换的场合；重量须 >0、系数须 >0 且有限；超出 [min,max] 时钳位并置 xClamped（判据取自未钳位原值，R24）
 * 代数值回代：G=50 kg、k=1.8 → t=1.8×7.071=12.73 s，落在 [4,30] → xClamped=FALSE（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_PouringTimeCalc : BOOL
VAR_INPUT
    rPourWeightKg : REAL := 50.0;     // 浇注重量（含浇冒口）| pouring weight including gating and risers [kg]
    rCoeff        : REAL := 1.8;      // 经验系数 | empirical coefficient [s/√kg]
    rMinS         : REAL := 4.0;      // 允许最短浇注时间 | minimum pouring time [s]
    rMaxS         : REAL := 30.0;     // 允许最长浇注时间 | maximum pouring time [s]
END_VAR
VAR_OUTPUT
    rPourTimeS : REAL;                // 浇注时间设定 | pouring time setpoint [s]
    rRawTimeS  : REAL;                // 未钳位的原始计算值 | raw time before clamping [s]
    xClamped   : BOOL;                // 已打限幅（信息级）| clamped against the limits, informational
    xValid     : BOOL;                // 输出有效 | outputs valid
END_VAR
VAR
    xFinG  : BOOL;                    // 重量有限性 | weight is finite
    xFinK  : BOOL;                    // 系数有限性 | coefficient is finite
    xFinLo : BOOL;                    // 下限有限性 | lower limit is finite
    xFinHi : BOOL;                    // 上限有限性 | upper limit is finite
END_VAR
VAR CONSTANT
    DL_PTC_EPS : REAL := 1.0E-6;      // 浮点比较容差 | floating comparison tolerance [s]
END_VAR

// 段1｜非有限闸（R19）
xFinG := (rPourWeightKg = rPourWeightKg) AND ((rPourWeightKg - rPourWeightKg) = 0.0);
xFinK := (rCoeff = rCoeff) AND ((rCoeff - rCoeff) = 0.0);
xFinLo := (rMinS = rMinS) AND ((rMinS - rMinS) = 0.0);
xFinHi := (rMaxS = rMaxS) AND ((rMaxS - rMaxS) = 0.0);
IF (NOT xFinG) OR (NOT xFinK) OR (NOT xFinLo) OR (NOT xFinHi) THEN
    rPourTimeS := 4.0;                // 安全值：取下限（快速浇注侧不可取，取允许最短）| safe value, the shortest permitted time
    rRawTimeS := 4.0;
    xClamped := TRUE;
    xValid := FALSE;
    FC_DL_PouringTimeCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：重量与系数须为正（√G 的定义域），限幅区间须有效
IF (rPourWeightKg <= 0.0) OR (rCoeff <= 0.0) OR (rMaxS <= rMinS) THEN
    rPourTimeS := rMinS;              // 安全值：取下限 | safe value, the lower limit
    rRawTimeS := rMinS;
    xClamped := TRUE;
    xValid := FALSE;
    FC_DL_PouringTimeCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：t = k×√G
rRawTimeS := rCoeff * SQRT(rPourWeightKg);

// 段4｜限幅与打限标志（判据取自未钳位原值，R24）
xClamped := (rRawTimeS > (rMaxS + DL_PTC_EPS)) OR (rRawTimeS < (rMinS - DL_PTC_EPS));
rPourTimeS := LIMIT(rMinS, rRawTimeS, rMaxS);

// 段5｜出口
xValid := TRUE;
FC_DL_PouringTimeCalc := TRUE;
END_FUNCTION
