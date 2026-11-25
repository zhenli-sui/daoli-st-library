(*
 * FC_DL_UpsLoadRateCalc | C1 | DL_Device
 * 功能：UPS 负载率、N+1 冗余下的最大允许负载率与过载判定       单位：功率 [kW]、负载率 [%]、台数 [台]
 * 工况边界：模块均分假设（各模块容量相同、均流良好）；额定功率须 >0、模块数须 ≥1、冗余台数须满足 0 ≤ nRedundant < nModules；不含电池放电与效率修正
 * 代数值回代：rated=400 kW、nModules=4、nRedundant=1 → maxPct=3/4×100=75 %、允许 300 kW；load=320 kW → 320>300 → xOverload=TRUE、负载率 80 %（与 spec 回代行一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_UpsLoadRateCalc : BOOL
VAR_INPUT
    rLoadKw     : REAL := 320.0;     // 实际负载功率 | actual load power [kW]
    rRatedKw    : REAL := 400.0;     // UPS 额定功率（全模块）| UPS rated power, all modules [kW]
    nModules    : INT := 4;          // 模块总数 | total module count [台]
    nRedundant  : INT := 1;          // 冗余模块数 | redundant module count [台]
END_VAR
VAR_OUTPUT
    rLoadRatePct     : REAL;         // 负载率 | load rate [%]
    rMaxPermittedPct : REAL;         // 冗余约束下的最大允许负载率 | maximum permitted load rate under the redundancy constraint [%]
    rMaxPermittedKw  : REAL;         // 冗余约束下的最大允许负载功率 | maximum permitted load power [kW]
    xOverload        : BOOL;         // 过载（超过冗余允许值）| overload beyond the redundancy allowance
    xRedundancyOk    : BOOL;         // 冗余成立（去冗余后仍有 ≥1 台可用）| redundancy valid, at least one module remains
    xValid           : BOOL;         // 输出有效 | outputs valid
END_VAR
VAR
    xFinLoad : BOOL;                 // 负载功率有限性 | load power is finite
    xFinRated: BOOL;                 // 额定功率有限性 | rated power is finite
    nUsable  : INT;                  // 允许带载的模块数（去冗余）| usable modules after removing the redundancy [台]
    rModules : REAL;                 // 模块数实数形式 | module count as a real number [台]
END_VAR
VAR CONSTANT
    DL_ULR_PCT : REAL := 100.0;      // 百分数换算系数 | percentage factor [%]
    DL_ULR_MIN : REAL := 1.0E-9;     // 额定功率下限（防零除）| rated power lower bound [kW]
END_VAR

// 段1｜非有限闸（R19）
xFinLoad := (rLoadKw = rLoadKw) AND ((rLoadKw - rLoadKw) = 0.0);
xFinRated := (rRatedKw = rRatedKw) AND ((rRatedKw - rRatedKw) = 0.0);
IF (NOT xFinLoad) OR (NOT xFinRated) THEN
    rLoadRatePct := 0.0;             // 安全值：负载率 0 | safe value, zero load rate
    rMaxPermittedPct := 0.0;
    rMaxPermittedKw := 0.0;
    xOverload := TRUE;               // 安全值：判过载，禁止新增负载 | safe value, flagged as overload
    xRedundancyOk := FALSE;
    xValid := FALSE;
    FC_DL_UpsLoadRateCalc := FALSE;
    RETURN;
END_IF

// 段2｜域闸：额定功率入分母须 >0，模块数与冗余数须自洽
IF (rRatedKw <= DL_ULR_MIN) OR (nModules < 1) OR (nRedundant < 0) OR (nRedundant >= nModules) THEN
    rLoadRatePct := 0.0;
    rMaxPermittedPct := 0.0;
    rMaxPermittedKw := 0.0;
    xOverload := TRUE;
    xRedundancyOk := FALSE;
    xValid := FALSE;
    FC_DL_UpsLoadRateCalc := FALSE;
    RETURN;
END_IF

// 段3｜算法：maxPct = (n−nRed)/n×100；负载率 = load/rated×100
nUsable := nModules - nRedundant;
rModules := INT_TO_REAL(nModules);
rMaxPermittedPct := INT_TO_REAL(nUsable) / rModules * DL_ULR_PCT;
rMaxPermittedKw := rRatedKw * INT_TO_REAL(nUsable) / rModules;
rLoadRatePct := rLoadKw / rRatedKw * DL_ULR_PCT;

// 段4｜判定：过载与冗余度（判据同源于原始功率与台数）
xOverload := rLoadKw > rMaxPermittedKw;
xRedundancyOk := nUsable >= 1;
xValid := TRUE;
FC_DL_UpsLoadRateCalc := TRUE;
END_FUNCTION
