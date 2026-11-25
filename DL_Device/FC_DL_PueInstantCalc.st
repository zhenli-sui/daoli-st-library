(*
 * FC_DL_PueInstantCalc | C1 | DL_Device
 * 功能：瞬时 PUE 与 IT 负载占比       单位：功率 [kW]、PUE [1]、占比 [%]
 * 工况边界：仅适用于整机房口径（总功率含制冷、输配与照明，不小于 IT 功率）；IT 功率须 >0（入分母），否则判 9621；总功率小于 IT 功率说明计量口径错误，置 xValid=FALSE 但保留数值供诊断
 * 代数值回代：IT=500 kW、Total=700 kW → PUE=1.40、IT 占比 71.43 %（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_PueInstantCalc : BOOL
VAR_INPUT
    rItKw    : REAL := 500.0;        // IT 设备功率 | IT equipment power [kW]
    rTotalKw : REAL := 700.0;        // 机房总功率 | total facility power [kW]
END_VAR
VAR_OUTPUT
    rPue      : REAL;                // 瞬时 PUE | instantaneous PUE [1]
    rItSharePct : REAL;              // IT 负载占比 | IT load share [%]
    xValid    : BOOL;                // 输出有效 | outputs valid
    nFaultCode: INT;                 // 0=无 / 9621=IT 功率非法 / 9622=总功率小于 IT 功率 | 0 none, 9621 illegal IT power, 9622 total below IT
END_VAR
VAR
    xFinIt : BOOL;                   // IT 功率有限性 | IT power is finite
    xFinTot: BOOL;                   // 总功率有限性 | total power is finite
END_VAR
VAR CONSTANT
    DL_PUE_PCT   : REAL := 100.0;    // 百分数换算系数 | percentage factor [%]
    DL_PUE_ITMIN : REAL := 1.0E-9;   // IT 功率下限（防零除）| IT power lower bound guarding the division [kW]
END_VAR

// 段1｜非有限闸（R19）
xFinIt := (rItKw = rItKw) AND ((rItKw - rItKw) = 0.0);
xFinTot := (rTotalKw = rTotalKw) AND ((rTotalKw - rTotalKw) = 0.0);
IF (NOT xFinIt) OR (NOT xFinTot) THEN
    rPue := 0.0;                     // 安全值：PUE 0（下游按无效丢弃）| safe value, downstream discards it
    rItSharePct := 0.0;
    xValid := FALSE;
    nFaultCode := 9621;
    FC_DL_PueInstantCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：IT 功率入分母必须 >0，总功率不得为负
IF (rItKw <= DL_PUE_ITMIN) OR (rTotalKw < 0.0) THEN
    rPue := 0.0;
    rItSharePct := 0.0;
    xValid := FALSE;
    nFaultCode := 9621;
    FC_DL_PueInstantCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：PUE = 总功率/IT 功率；IT 占比同源
rPue := rTotalKw / rItKw;
rItSharePct := rItKw / rTotalKw * DL_PUE_PCT;

// 段4｜口径校验：总功率必须不小于 IT 功率（判据与出口同源于原始值）
IF rTotalKw < rItKw THEN
    xValid := FALSE;
    nFaultCode := 9622;              // 计量口径错误：数值保留供诊断，标志置无效 | metering inconsistency, value kept for diagnostics
    FC_DL_PueInstantCalc := FALSE;
    RETURN;
END_IF

// 段5｜出口
nFaultCode := 0;
xValid := TRUE;
FC_DL_PueInstantCalc := TRUE;
END_FUNCTION
