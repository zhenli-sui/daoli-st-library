// FC_DL_PotlineBusbarShuntCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 母线并联支路分流：分流比 = R_other/(R_branch + R_other)，支路电流 = 总电流 × 分流比；
        两电阻同为 µΩ 量纲，比值无量纲故不换算。用于母线搭接电阻劣化诊断。
  邻件/码位: 与 FC_DL_PotlineCellVoltageBudgetCalc 层次不同（槽外母线分流 vs 槽内压降）；
             16#0002_9218 = 非有限、总电流非正或任一电阻非正拒收。
*)
FUNCTION FC_DL_PotlineBusbarShuntCalc : REAL
VAR_INPUT
    fTotalCurrent : REAL := 400.0;  // 总电流 [kA]，域 > 0 / Total current [kA]
    fBranchRes    : REAL := 10.0;   // 本支路电阻 [µΩ]，域 > 0 / Branch resistance [uOhm]
    fOtherRes     : REAL := 12.0;   // 其余并联等效电阻 [µΩ]，域 > 0 / Other resistance [uOhm]
END_VAR
VAR_OUTPUT
    fBranchCurrent : REAL;          // 本支路电流 [kA] / Branch current [kA]
    fShuntRatio    : REAL;          // 分流比 [-] / Shunt ratio [-]
    bValid         : BOOL;          // 结果有效回执 [-] / Result validity receipt
    uErrorId       : UDINT;         // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    fResSum : REAL := 0.0;          // 电阻和 [µΩ] / Resistance sum [uOhm]
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fBranchCurrent := 0.0;              // 支路电流缺省零 / Branch current default zero
fShuntRatio := 0.0;                 // 分流比缺省零 / Shunt ratio default zero
bValid := FALSE;                    // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                // 事件码预清 / Event code preset clear
FC_DL_PotlineBusbarShuntCalc := 0.0;        // 返回值缺省零（镜像支路电流）/ Return default zero
// 段 1：非有限闸（三入参全枚举）/ Non-finite gate over all inputs
IF (fTotalCurrent <> fTotalCurrent) OR (fBranchRes <> fBranchRes) OR (fOtherRes <> fOtherRes)
   OR (ABS(fTotalCurrent) >= 3.0E38) OR (ABS(fBranchRes) >= 3.0E38) OR (ABS(fOtherRes) >= 3.0E38) THEN
    uErrorId := 16#0002_9218;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（总电流为正 + 两电阻为正，分母非零，R4）/ Domain gate
IF fTotalCurrent <= 1.0E-6 THEN
    uErrorId := 16#0002_9218;   // 总电流非正 / Non-positive total current
    RETURN;
END_IF
IF (fBranchRes <= 0.0) OR (fOtherRes <= 0.0) THEN
    uErrorId := 16#0002_9218;   // 支路或并联电阻非正 / Non-positive resistance
    RETURN;
END_IF
// 段 3：主计算（分流比 → 支路电流）/ Main computation
fResSum := fBranchRes + fOtherRes;                              // 电阻和 / Resistance sum
fShuntRatio := fOtherRes / fResSum;                             // 分流比 / Shunt ratio
fBranchCurrent := fTotalCurrent * fShuntRatio;                   // 支路电流 / Branch current
// 段 4：出口闸（非有限复核 + 分流比区间复核）/ Outlet gate
IF (fBranchCurrent <> fBranchCurrent) OR (fShuntRatio <> fShuntRatio)
   OR (ABS(fBranchCurrent) >= 3.0E38) OR (ABS(fShuntRatio) >= 3.0E38)
   OR (fShuntRatio <= 0.0) OR (fShuntRatio >= 1.0) THEN
    fBranchCurrent := 0.0;      // 复核失败回缺省 / Fallback on recheck failure
    fShuntRatio := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9218;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_PotlineBusbarShuntCalc := fBranchCurrent;     // 返回值镜像支路电流 / Return mirrors current
END_FUNCTION
