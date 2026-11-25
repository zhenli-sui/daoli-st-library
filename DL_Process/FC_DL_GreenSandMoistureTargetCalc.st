(*
 * FC_DL_GreenSandMoistureTargetCalc | C2 | DL_Process
 * 功能：由紧实率反算湿型砂水分目标（线性经验式）       单位：紧实率 [%]、水分 [%]、系数 [%/%、1]
 * 工况边界：经验式 w = a + b×CB，a=1.2 %、b=0.04 %/%（spec 采纳值，回代 38 → 2.72 %，落在湿型砂 2.5~3.5 % 合理区间）；紧实率按物理域钳位 [20,60] %，越界置信息位且判据取自未钳位原值；系数 b 须 >0
 * 代数值回代：CB=38 %、a=1.2、b=0.04 → w=1.2+0.04×38=2.72 %（与 spec 采纳回代值一致）
 * 系数修正说明：spec 初版给 a=0.55 / b=0.0525，回代 38 得 2.545 % 偏离湿型砂常规区间，spec 已明确改用 a=1.2 / b=0.04，本件按采纳值实现
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_GreenSandMoistureTargetCalc : BOOL
VAR_INPUT
    rCompactabilityPct : REAL := 38.0;  // 紧实率 | compactability [%]
    rA                 : REAL := 1.2;   // 经验式截距 | empirical intercept [%]
    rB                 : REAL := 0.04;  // 经验式斜率 | empirical slope [%/%]
END_VAR
VAR_OUTPUT
    rTargetMoisturePct : REAL;          // 目标水分 | target moisture [%]
    rCbUsed            : REAL;          // 实际参与计算的紧实率（已钳位）| compactability actually used, clamped [%]
    xClamped           : BOOL;          // 紧实率越界被钳位（信息级）| compactability clamped, informational
    xValid             : BOOL;          // 输出有效 | outputs valid
END_VAR
VAR
    xFinCb : BOOL;                      // 紧实率有限性 | compactability is finite
    xFinA  : BOOL;                      // 截距有限性 | intercept is finite
    xFinB  : BOOL;                      // 斜率有限性 | slope is finite
END_VAR
VAR CONSTANT
    DL_GSM_CB_LO : REAL := 20.0;        // 紧实率物理下限 | compactability lower bound [%]
    DL_GSM_CB_HI : REAL := 60.0;        // 紧实率物理上限 | compactability upper bound [%]
END_VAR

// 段1｜非有限闸（R19）
xFinCb := (rCompactabilityPct = rCompactabilityPct) AND ((rCompactabilityPct - rCompactabilityPct) = 0.0);
xFinA := (rA = rA) AND ((rA - rA) = 0.0);
xFinB := (rB = rB) AND ((rB - rB) = 0.0);
IF (NOT xFinCb) OR (NOT xFinA) OR (NOT xFinB) THEN
    rTargetMoisturePct := 0.0;          // 安全值：目标水分 0 | safe value, zero target
    rCbUsed := 0.0;
    xClamped := FALSE;
    xValid := FALSE;
    FC_DL_GreenSandMoistureTargetCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：斜率必须为正（经验式单调增，否则反算无意义）
IF rB <= 0.0 THEN
    rTargetMoisturePct := 0.0;
    rCbUsed := 0.0;
    xClamped := FALSE;
    xValid := FALSE;
    FC_DL_GreenSandMoistureTargetCalc := FALSE;
    RETURN;
END_IF

// 段3｜域钳位：越界标志取自未钳位原值（R24）
IF rCompactabilityPct < DL_GSM_CB_LO THEN
    xClamped := TRUE;
    rCbUsed := DL_GSM_CB_LO;
ELSIF rCompactabilityPct > DL_GSM_CB_HI THEN
    xClamped := TRUE;
    rCbUsed := DL_GSM_CB_HI;
ELSE
    xClamped := FALSE;
    rCbUsed := rCompactabilityPct;
END_IF

// 段4｜算法：w = a + b×CB
rTargetMoisturePct := rA + rB * rCbUsed;
xValid := TRUE;
FC_DL_GreenSandMoistureTargetCalc := TRUE;
END_FUNCTION
