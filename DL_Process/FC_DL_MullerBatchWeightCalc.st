(*
 * FC_DL_MullerBatchWeightCalc | C2 | DL_Process
 * 功能：混砂机单批配比（批量、新砂、膨润土、水、旧砂）       单位：质量 [kg]、比例 [%]、充填系数 [1]
 * 工况边界：单批料量 = 容量×充填系数，充填系数须在 (0,1]；各比例均按「批量」为基数（与 spec 回代一致，水计入批内），三者之和须 ≤100 %，否则判 9712；容量须 >0 且有限
 * 代数值回代：cap=2000 kg、fill=0.75 → batch=1500 kg；新砂 10 %→150 kg；膨润土 1.2 %→18 kg；水 2.8 %→42 kg；旧砂=1500−150−18−42=1290 kg（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_MullerBatchWeightCalc : BOOL
VAR_INPUT
    rCapacityKg    : REAL := 2000.0;  // 混砂机额定容量 | muller rated capacity [kg]
    rFillFactor    : REAL := 0.75;    // 充填系数 | fill factor [1]
    rNewSandPct    : REAL := 10.0;    // 新砂比例 | new sand ratio [%]
    rBentonitePct  : REAL := 1.2;     // 膨润土比例 | bentonite ratio [%]
    rWaterPct      : REAL := 2.8;     // 水比例 | water ratio [%]
END_VAR
VAR_OUTPUT
    rBatchKg      : REAL;             // 单批料量 | batch weight [kg]
    rNewSandKg    : REAL;             // 新砂加入量 | new sand weight [kg]
    rBentoniteKg  : REAL;             // 膨润土加入量 | bentonite weight [kg]
    rWaterKg      : REAL;             // 水加入量 | water weight [kg]
    rReturnSandKg : REAL;             // 旧砂（回用砂）量 | return sand weight [kg]
    rSumPct       : REAL;             // 三辅料比例之和 | sum of the three additive ratios [%]
    xValid        : BOOL;             // 输出有效 | outputs valid
    nFaultCode    : INT;              // 0=无 / 9712=容量或比例非法 | 0 none, 9712 illegal capacity or ratio
END_VAR
VAR
    xFinCap  : BOOL;                  // 容量有限性 | capacity is finite
    xFinFill : BOOL;                  // 充填系数有限性 | fill factor is finite
    xFinNew  : BOOL;                  // 新砂比例有限性 | new sand ratio is finite
    xFinBent : BOOL;                  // 膨润土比例有限性 | bentonite ratio is finite
    xFinWtr  : BOOL;                  // 水比例有限性 | water ratio is finite
END_VAR
VAR CONSTANT
    DL_MBW_PCT : REAL := 100.0;       // 百分数换算系数 | percentage factor [%]
    DL_MBW_EPS : REAL := 1.0E-6;      // 浮点比较容差 | floating comparison tolerance [%]
END_VAR

// 段1｜非有限闸（R19）
xFinCap := (rCapacityKg = rCapacityKg) AND ((rCapacityKg - rCapacityKg) = 0.0);
xFinFill := (rFillFactor = rFillFactor) AND ((rFillFactor - rFillFactor) = 0.0);
xFinNew := (rNewSandPct = rNewSandPct) AND ((rNewSandPct - rNewSandPct) = 0.0);
xFinBent := (rBentonitePct = rBentonitePct) AND ((rBentonitePct - rBentonitePct) = 0.0);
xFinWtr := (rWaterPct = rWaterPct) AND ((rWaterPct - rWaterPct) = 0.0);
IF (NOT xFinCap) OR (NOT xFinFill) OR (NOT xFinNew) OR (NOT xFinBent) OR (NOT xFinWtr) THEN
    rBatchKg := 0.0;                  // 安全值：全部 0（不配料）| safe value, no batching
    rNewSandKg := 0.0;
    rBentoniteKg := 0.0;
    rWaterKg := 0.0;
    rReturnSandKg := 0.0;
    rSumPct := 0.0;
    xValid := FALSE;
    nFaultCode := 9712;
    FC_DL_MullerBatchWeightCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：容量 >0、充填系数 (0,1]、各比例非负且之和 ≤100 %
rSumPct := rNewSandPct + rBentonitePct + rWaterPct;
IF (rCapacityKg <= 0.0) OR (rFillFactor <= 0.0) OR (rFillFactor > 1.0)
   OR (rNewSandPct < 0.0) OR (rBentonitePct < 0.0) OR (rWaterPct < 0.0)
   OR (rSumPct > (DL_MBW_PCT + DL_MBW_EPS)) THEN
    rBatchKg := 0.0;
    rNewSandKg := 0.0;
    rBentoniteKg := 0.0;
    rWaterKg := 0.0;
    rReturnSandKg := 0.0;
    xValid := FALSE;
    nFaultCode := 9712;
    FC_DL_MullerBatchWeightCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：batch = cap×fill；各辅料按批量比例；旧砂 = 批量 − 三辅料
rBatchKg := rCapacityKg * rFillFactor;
rNewSandKg := rBatchKg * rNewSandPct / DL_MBW_PCT;
rBentoniteKg := rBatchKg * rBentonitePct / DL_MBW_PCT;
rWaterKg := rBatchKg * rWaterPct / DL_MBW_PCT;
rReturnSandKg := rBatchKg - rNewSandKg - rBentoniteKg - rWaterKg;
IF rReturnSandKg < 0.0 THEN
    rReturnSandKg := 0.0;             // 保险钳位（段2的比例和约束已排除）| defensive clamp already excluded by segment 2
END_IF

// 段4｜出口
nFaultCode := 0;
xValid := TRUE;
FC_DL_MullerBatchWeightCalc := TRUE;
END_FUNCTION
