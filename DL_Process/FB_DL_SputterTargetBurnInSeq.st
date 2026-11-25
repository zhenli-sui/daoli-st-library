//==============================================================================
// 功能块：FB_DL_SputterTargetBurnInSeq ｜ 中文名称：溅射靶预烧与功率爬坡序（复杂度 C4）
// 所属子库：DL_Process ｜ 版本 VERSION: v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：新靶装机后的预烧处理——真空达标 → 通 Ar 稳气 → 功率按斜率爬升 → 预烧到规定
//           能量 → 按斜率降功率 → 关快门 → 关气 → 完成。全程统计打火次数，超限立即把功率
//           指令压到 0 并锁存 xArcTrip；中止与打火停机一律走三段关断序（降功率 → 关快门
//           → 关气），禁单拍全断（会污染靶面）。
// 开源溯源 (Origin)：道莅原创实现（参考 SEMI F47 与磁控溅射靶预烧工艺惯例 分类与参数
//           域，许可证=MIT，借鉴点=「按斜率爬升 + 累计能量达量停烧 + 打火计数联锁」的
//           预烧序）
// 单位表：气压[Pa] / 功率[kW] / 能量[kWh] / 斜率[kW/s] / 打火[次] / 时间[ms]
// 能量离散积分（本件核心积分，换算写清）：
//   fEnergyKWh = Σ (P[kW] × Δt[s]) ÷ 3600 [s/h]；由 W 折算 kW 的 ÷1000 已含在入口量纲
//   上（若上层以 W 给功率，须先 ÷1000 再进本件），Δt 取 DL_SPT_DT_S 假定 10 ms 周期。
// 错误码表（Process 段 0005，故障窗口 3F11~3F19，信息窗口 3F91）：
//   16#0005_3F11 故障级：组态非法（设定压/容差/设定功率/斜率/能量 <= 0 或打火上限 = 0）
//   16#0005_3F12 故障级：实时量入口非有限（腔压 / 功率 NaN 或 Inf）或幅值超上限，拒算
//   16#0005_3F13 故障级：真空未达标超时（tRampTimeout 内气压未进入设定带）
//   16#0005_3F14 故障级：稳气超时（tRampTimeout 内气压未在带内稳住 tGasStabTime）
//   16#0005_3F15 故障级：功率爬坡超时（tRampTimeout 内未爬到设定功率）
//   16#0005_3F16 故障级：预烧超时（tBurnTimeout 内累计能量未达 fBurnEnergyKWh）
//   16#0005_3F17 故障级：打火超限（累计打火 > nArcLimit，功率立即压 0 并锁存 xArcTrip）
//   16#0005_3F18 故障级：关断序超时（降功率/关快门/关气任一段超 tRampTimeout）
//   16#0005_3F19 故障级兜底：状态机落 ELSE 非法态，全输出断
//   16#0005_3F91 信息级：预烧完成（进入 eDone 拍，不置 bError）
//           故障级码全部锁存回放（R187），唯一清除路径 = bReset 上升沿（含打火锁存）。
// 状态机：E_DL_SputterBurnState（八态：eIdle=0 / eVacCheck=10 / eGasStab=20 / eRampUp=30 /
//           eBurnIn=40 / eRampDown=50 / eDone=60 / eFault=99）。三段关断序不占相位，由
//           内部段号 _uDownStage 驱动（0 降功率 / 1 关快门 / 2 关气）。
// 边界行为：① 真空或气压未进带绝不加功率（eRampUp 入口以 _bVacOk 为唯一前提）；② 打火
//           超限属最高优先级：段 5 在功率生成处先判 _bArcTrip 并压 0，不等状态机；③ 三段
//           关断序每段之间留物理动作时间（DL_SPT_SHUTTER_T / DL_SPT_GAS_T），禁单拍全断；
//           ④ 中止与打火停机共用同一关断序，关断后落 eFault 或 eDone 由 _bArcTrip 决定；
//           ⑤ 八态 CASE 每态显式 + ELSE 兜底 → 3F19 全断。
// 语义假设：① nArcCount 为打火探测器累计计数，本件按增量累加并对上游复位做单调化处理；
//           ② 快门开 = xShutterCmd TRUE 表示靶面暴露给基片，预烧期按工艺允许开快门（挡板
//           由上层另控）；③ 腔压判据用绝对偏差带，不含符号方向。
// 依赖纪律：仅 Standard.library（TON / R_TRIG）；零 GVL、零 VAR_EXTERNAL、零物理地址。
// 修订历史：v1.0.0 2026-11-25 R88 首版（无人值守批次 · 复杂件 C4 · 序号 4）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_SputterBurnState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 预烧相位，与段 8 状态机、段 9 输出置位一一对应。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SputterBurnState :
(
    eIdle     := 0,  // 空闲：等启动沿 / Idle, awaiting the start edge
    eVacCheck := 10, // 真空核对：腔压进入设定带 / Vacuum check against the pressure band
    eGasStab  := 20, // 稳气：通 Ar 并在带内稳住规定时间 / Argon stabilisation inside the band
    eRampUp   := 30, // 功率爬坡：按斜率爬到设定功率 / Power ramp up to the setpoint
    eBurnIn   := 40, // 预烧：累计能量到量前持续 / Burn-in until the energy target is met
    eRampDown := 50, // 降功率与三段关断 / Power ramp down and the three-stage shutdown
    eDone     := 60, // 完成：预烧结束 / Done, burn-in finished
    eFault    := 99  // 故障：组态/超时/打火/非法态 / Fault, configuration, timeout, arcing or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_SputterTargetBurnInSeq
VAR_INPUT
    xEnable       : BOOL;   // 使能，FALSE 期间按中止处理（走三段关断） [—] / Enable, a drop aborts into the shutdown
    xStart        : BOOL;   // 启动请求，上升沿生效 [—] / Start request, rising edge effective
    xAbort        : BOOL;   // 中止请求，任意拍生效（走三段关断） [—] / Abort request, moves into the shutdown
    xReset        : BOOL;   // 故障复位，上升沿清全部锁存（含打火锁存） [—] / Fault reset, clears all latches
    fChamberPressPa : LREAL; // 腔体实际气压 [Pa] / Actual chamber pressure [Pa]
    fPressSetPa   : LREAL;  // 工艺设定气压 [Pa]，须 > 0 / Process pressure setpoint [Pa]
    fPressTolPa   : LREAL;  // 气压允许偏差 [Pa]，须 > 0 / Allowed pressure tolerance [Pa]
    fPowerKW      : LREAL;  // 实际输出功率 [kW] / Actual delivered power [kW]
    fPowerSetKW   : LREAL;  // 预烧设定功率 [kW]，须 > 0 / Burn-in power setpoint [kW]
    fRampKWperS   : LREAL;  // 功率爬坡/降坡斜率 [kW/s]，须 > 0 / Power ramp rate [kW/s]
    fBurnEnergyKWh: LREAL;  // 预烧目标能量 [kWh]，须 > 0 / Burn-in energy target [kWh]
    nArcCount     : UDINT;  // 打火探测器累计计数 [次] / Arc detector accumulated count
    nArcLimit     : UDINT;  // 打火累计上限 [次]，须 > 0 / Accumulated arc ceiling
    tGasStabTime  : TIME;   // 稳气时长 [ms] / Gas stabilisation time [ms]
    tRampTimeout  : TIME;   // 真空/稳气/爬坡/关断超时 [ms] / Vacuum, gas, ramp and shutdown timeout [ms]
    tBurnTimeout  : TIME;   // 预烧最长允许时间 [ms] / Maximum burn-in time [ms]
END_VAR
VAR_OUTPUT
    fPowerCmdKW     : LREAL;  // 功率指令出口 [kW]，0 = 断功率 / Power command outlet [kW], 0 = off
    xArValveCmd     : BOOL;   // 氩气进气阀命令 [—] / Argon inlet valve command
    xShutterCmd     : BOOL;   // 快门命令（TRUE = 开） [—] / Shutter command, TRUE = open
    bRunning        : BOOL;   // 预烧进行中（非空闲非完成非故障） [—] / Burn-in active
    bDone           : BOOL;   // 预烧完成相电平 [—] / Burn-in done, level in the done phase
    bError          : BOOL;   // 故障级标志，仅故障级码置位 [—] / Fault-class flag, fault-level codes only
    nErrCode        : UDINT;  // 错误码，0 = 无错 [—] / Error code, 0 = none
    fEnergyKWh      : LREAL;  // 累计预烧能量 [kWh] / Accumulated burn-in energy [kWh]
    nArcTotal       : UDINT;  // 累计打火次数 [次] / Accumulated arc count
    xArcTrip        : BOOL;   // 打火超限锁存（bReset 清） [—] / Arc trip latch, cleared by bReset
END_VAR
VAR
    _eState         : E_DL_SputterBurnState := E_DL_SputterBurnState.eIdle; // 当前相位 [—] / Current phase
    _bInit          : BOOL := FALSE;  // 首扫标志，取非判定 [—] / First-scan flag, tested negated
    _fPowerCmd      : LREAL;          // 功率指令斜率限幅后的保持量 [kW] / Held command after rate limiting [kW]
    _fEnergyKWh     : LREAL;          // 内部累计能量 [kWh] / Internal accumulated energy [kWh]
    _nArcTotal      : UDINT;          // 内部累计打火次数 [次] / Internal accumulated arc count
    _nArcPrev       : UDINT;          // 上拍打火计数快照 [次] / Previous-scan arc count snapshot
    _bCfgBad        : BOOL;           // 组态非法锁存 / Illegal configuration latch
    _bCfgOk         : BOOL;           // 本拍组态合法（派生量不锁存） [—] / Configuration legal this scan
    _bSigBad        : BOOL;           // 实时量非有限锁存 / Non-finite process value latch
    _bVacOk         : BOOL;           // 气压在设定带内（派生量） [—] / Pressure inside the setpoint band
    _bArcTrip       : BOOL;           // 打火超限锁存 / Arc trip latch
    _bVacTmo        : BOOL;           // 真空超时锁存 / Vacuum timeout latch
    _bGasTmo        : BOOL;           // 稳气超时锁存 / Gas stabilisation timeout latch
    _bRampTmo       : BOOL;           // 爬坡超时锁存 / Ramp timeout latch
    _bBurnTmo       : BOOL;           // 预烧超时锁存 / Burn-in timeout latch
    _bDownTmo       : BOOL;           // 关断序超时锁存 / Shutdown timeout latch
    _bIllegal       : BOOL;           // 非法状态标志 / Illegal state flag
    _bInfoDone      : BOOL;           // 预烧完成信息当拍标志 / Burn-in done info flag of this scan
    _bAbortReq      : BOOL;           // 中止请求合成（xAbort 或失能） [—] / Combined abort request
    _uDownStage     : UINT;           // 关断段号 0=降功率 1=关快门 2=关气 / Shutdown stage 0 power 1 shutter 2 gas
    rtStart         : R_TRIG;         // 启动沿，段 7 无条件刷新 [—] / Start edge, refreshed in segment 7
    rtReset         : R_TRIG;         // 复位沿，段 7 无条件刷新 [—] / Reset edge, refreshed in segment 7
    tonVac          : TON;            // 真空核对超时 [ms] / Vacuum check timeout [ms]
    tonGas          : TON;            // 稳气计时（仅在带内累计） [ms] / Gas stabilisation timer inside the band
    tonGasMax       : TON;            // 稳气最长允许时间 [ms] / Maximum stabilisation time [ms]
    tonRamp         : TON;            // 功率爬坡超时 [ms] / Ramp timeout [ms]
    tonBurn         : TON;            // 预烧最长允许时间 [ms] / Maximum burn-in time [ms]
    tonShutter      : TON;            // 关快门动作让位 [ms] / Shutter travel dwell [ms]
    tonGasClose     : TON;            // 关气动作让位 [ms] / Gas closing dwell [ms]
    tonDownMax      : TON;            // 关断序总超时 [ms] / Total shutdown timeout [ms]
END_VAR
VAR CONSTANT
    DL_EPS           : LREAL := 1.0E-9;      // 浮点容差零点，兼作除法分母下限 / Float epsilon, also the divisor floor
    DL_SPT_DT_S      : LREAL := 0.01;        // 爬坡与积分的假定任务周期 [s]（10 ms） / Assumed task period [s]
    DL_SPT_SEC_PER_H : LREAL := 3600.0;      // 秒折算小时 [s/h]，能量积分用 / Seconds per hour for the energy integral
    DL_SPT_POW_EPS   : LREAL := 0.05;        // 功率到位容差 [kW] / Power arrival tolerance [kW]
    DL_SPT_POWER_MAX : LREAL := 500.0;       // 功率反馈合法幅值上限 [kW] / Legal power ceiling [kW]
    DL_SPT_PRESS_MAX : LREAL := 100000.0;    // 气压反馈合法幅值上限 [Pa] / Legal pressure ceiling [Pa]
    DL_SPT_SHUTTER_T : TIME  := T#800MS;     // 关快门动作让位 [ms] / Shutter travel dwell [ms]
    DL_SPT_GAS_T     : TIME  := T#500MS;     // 关气动作让位 [ms] / Gas closing dwell [ms]
END_VAR
(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：全部输出先落安全侧，单拍标志预清零
 *      All outputs preset to the safe side, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fPowerCmdKW := 0.0;                         // 功率指令先归零（安全侧） / Power command zeroed first
xArValveCmd := FALSE; xShutterCmd := FALSE; // 氩气与快门命令先断 / Argon and shutter commands cleared
bRunning := FALSE;  bDone := FALSE;         // 运行与完成标志每拍重算 / Running and done flags recomputed
bError := FALSE;    nErrCode := 16#0000_0000; // 故障标志与错误码每拍重算 / Fault flag and code recomputed
_bIllegal := FALSE; _bInfoDone := FALSE;    // 非法态与完成信息预清零 / Illegal and done-info flags pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：相位、指令保持量、能量、打火累计与关断段号复位
 *      First-scan initialisation of phase, command, energy, arc count and stage
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_SputterBurnState.eIdle; // 相位从空闲起步 / Phase starts idle
    _fPowerCmd := 0.0;  _fEnergyKWh := 0.0;     // 指令与能量从零起步 / Command and energy start at zero
    _nArcTotal := 0;    _nArcPrev  := 0;  _uDownStage := 0; // 打火累计/快照/关断段号从零起步 / Arc, snapshot and stage zero
    _bInit := TRUE;                             // 首扫只做一次 / The first scan runs once
END_IF
(*------------------------------------------------------------------------------
 * 段 3｜实时量入口非有限闸 + 组态闸 + 气压带判据
 *      Non-finite inlet gate, configuration gates and the pressure band criterion
 *-----------------------------------------------------------------------------*)
IF NOT (fChamberPressPa > -1.0E30 AND fChamberPressPa < 1.0E30) THEN _bSigBad := TRUE; END_IF  // 腔压非有限 → 3F12 / Non-finite pressure, 3F12
IF ABS(fChamberPressPa) > DL_SPT_PRESS_MAX THEN _bSigBad := TRUE; END_IF                     // 腔压幅值超上限 → 3F12 / Beyond the ceiling, 3F12
IF NOT (fPowerKW > -1.0E30 AND fPowerKW < 1.0E30) THEN _bSigBad := TRUE; END_IF               // 功率非有限 → 3F12 / Non-finite power, 3F12
IF ABS(fPowerKW) > DL_SPT_POWER_MAX THEN _bSigBad := TRUE; END_IF                             // 功率幅值超上限 → 3F12 / Beyond the ceiling, 3F12
IF NOT (fPressSetPa > -1.0E30 AND fPressSetPa < 1.0E30) THEN _bCfgBad := TRUE; END_IF         // 设定压非有限 → 3F11 / Non-finite setpoint pressure, 3F11
IF NOT (fPowerSetKW > -1.0E30 AND fPowerSetKW < 1.0E30) THEN _bCfgBad := TRUE; END_IF         // 设定功率非有限 → 3F11 / Non-finite setpoint power, 3F11
IF NOT (fRampKWperS > -1.0E30 AND fRampKWperS < 1.0E30) THEN _bCfgBad := TRUE; END_IF         // 斜率非有限 → 3F11 / Non-finite ramp, 3F11
IF NOT (fBurnEnergyKWh > -1.0E30 AND fBurnEnergyKWh < 1.0E30) THEN _bCfgBad := TRUE; END_IF    // 目标能量非有限 → 3F11 / Non-finite energy, 3F11
IF (fPressSetPa <= DL_EPS) OR (fPressTolPa <= DL_EPS) OR (fPowerSetKW <= DL_EPS)
   OR (fRampKWperS <= DL_EPS) OR (fBurnEnergyKWh <= DL_EPS) THEN _bCfgBad := TRUE; END_IF // 五者须为正 → 3F11 / All five must be positive
IF nArcLimit = 0 THEN _bCfgBad := TRUE; END_IF                          // 打火上限为 0 即永久跳闸 → 3F11 / Zero arc limit, 3F11
IF (tGasStabTime <= T#0MS) OR (tRampTimeout <= T#0MS) OR (tBurnTimeout <= T#0MS) THEN _bCfgBad := TRUE; END_IF // 时间量须为正 → 3F11
_bCfgOk := NOT _bCfgBad;                    // 本拍组态合法派生量 / Configuration-legal derived flag of this scan
_bVacOk := ABS(fChamberPressPa - fPressSetPa) <= fPressTolPa; // 气压带判据 [Pa] / Pressure band criterion [Pa]

(*------------------------------------------------------------------------------
 * 段 4｜打火累计（增量单调化）与超限锁存
 *      Arc accumulation with monotonic handling of an upstream counter reset
 *-----------------------------------------------------------------------------*)
IF nArcCount >= _nArcPrev THEN _nArcTotal := _nArcTotal + (nArcCount - _nArcPrev); // 增量累加 / Increment accumulated
ELSE _nArcTotal := _nArcTotal + nArcCount; END_IF                                  // 上游复位按新窗累加 / Upstream reset, new window
_nArcPrev := nArcCount;                     // 计数快照推进 / Count snapshot advanced
IF (_nArcTotal > nArcLimit) THEN
    _bArcTrip := TRUE;                      // 打火超限锁存 → 3F17 / Arc ceiling exceeded, 3F17
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜功率指令生成（打火优先压 0）+ 斜率限幅 + 能量离散积分
 *      Power command generation, arc-first zeroing, rate limiting and energy integral
 *-----------------------------------------------------------------------------*)
IF _bArcTrip THEN
    _fPowerCmd := 0.0;                      // 打火超限：功率立即压 0（不等状态机） / Arc trip, power forced to zero
ELSIF (_eState = E_DL_SputterBurnState.eRampUp) OR (_eState = E_DL_SputterBurnState.eBurnIn) THEN
    IF fPowerSetKW > _fPowerCmd THEN
        _fPowerCmd := _fPowerCmd + fRampKWperS * DL_SPT_DT_S;       // 升坡 [kW] / Ramp up [kW]
        IF _fPowerCmd > fPowerSetKW THEN _fPowerCmd := fPowerSetKW; END_IF // 上钳设定值 / Clamp at setpoint
    ELSIF fPowerSetKW < _fPowerCmd THEN
        _fPowerCmd := _fPowerCmd - fRampKWperS * DL_SPT_DT_S;       // 降坡 [kW] / Ramp down [kW]
        IF _fPowerCmd < fPowerSetKW THEN _fPowerCmd := fPowerSetKW; END_IF // 下钳设定值 / Clamp at setpoint
    END_IF
ELSIF _eState = E_DL_SputterBurnState.eRampDown THEN
    _fPowerCmd := _fPowerCmd - fRampKWperS * DL_SPT_DT_S;           // 关断序段 0：降功率 [kW] / Shutdown stage 0, ramp down
    IF _fPowerCmd < 0.0 THEN _fPowerCmd := 0.0; END_IF              // 下钳 0 / Lower clamp at zero
ELSE
    _fPowerCmd := 0.0;                      // 其余相指令归零 / Zeroed in all other phases
END_IF
IF (_eState = E_DL_SputterBurnState.eBurnIn) AND (DL_SPT_SEC_PER_H > DL_EPS) THEN
    _fEnergyKWh := _fEnergyKWh + (_fPowerCmd * DL_SPT_DT_S) / DL_SPT_SEC_PER_H; // 能量积分 [kWh] / Energy integral [kWh]
END_IF
fPowerCmdKW := _fPowerCmd; fEnergyKWh := _fEnergyKWh; // 功率指令与能量出口 [kW]/[kWh] / Power and energy outlets
nArcTotal := _nArcTotal;    xArcTrip := _bArcTrip;    // 累计打火与打火锁存出口 / Arc count and arc trip outlets

(*------------------------------------------------------------------------------
 * 段 6｜中止入口（任意运行相 → 三段关断序）与复位
 *      Abort entry into the three-stage shutdown plus the reset edge
 *-----------------------------------------------------------------------------*)
_bAbortReq := xAbort OR (NOT xEnable);      // 中止请求合成：显式中止或失能 / Combined abort: explicit abort or enable loss
IF _bAbortReq AND (_eState <> E_DL_SputterBurnState.eIdle) AND (_eState <> E_DL_SputterBurnState.eRampDown)
   AND (_eState <> E_DL_SputterBurnState.eDone) AND (_eState <> E_DL_SputterBurnState.eFault) THEN
    _uDownStage := 0;                       // 关断序从段 0（降功率）起 / Shutdown starts at stage 0
    _eState     := E_DL_SputterBurnState.eRampDown; // 进关断相 / To the shutdown phase
END_IF
IF rtReset.Q THEN
    _bCfgBad := FALSE;  _bSigBad := FALSE;  _bArcTrip := FALSE; // 复位清组态/入口/打火锁存 / Clears configuration, inlet and arc latches
    _bVacTmo := FALSE;  _bGasTmo := FALSE;  _bRampTmo := FALSE; // 复位清真空/稳气/爬坡锁存 / Clears vacuum, gas and ramp latches
    _bBurnTmo := FALSE; _bDownTmo := FALSE;                     // 复位清预烧/关断锁存 / Clears burn-in and shutdown latches
END_IF
(*------------------------------------------------------------------------------
 * 段 7｜定时器与边沿无条件周期刷新（R7：CASE 之外每拍必调，各司其职不复用）
 *      Timers and edges refreshed unconditionally every scan, outside the CASE
 *-----------------------------------------------------------------------------*)
rtStart(CLK := xStart); rtReset(CLK := xReset); // 启动沿与复位沿无条件刷新 / Start and reset edges refreshed
tonVac(IN := (_eState = E_DL_SputterBurnState.eVacCheck), PT := tRampTimeout);                     // 真空核对超时 / Vacuum timeout
tonGas(IN := (_eState = E_DL_SputterBurnState.eGasStab) AND _bVacOk, PT := tGasStabTime);          // 带内稳气计时 / In-band gas timer
tonGasMax(IN := (_eState = E_DL_SputterBurnState.eGasStab), PT := tRampTimeout);                   // 稳气最长允许 / Maximum stabilisation
tonRamp(IN := (_eState = E_DL_SputterBurnState.eRampUp), PT := tRampTimeout);                      // 爬坡超时 / Ramp timeout
tonBurn(IN := (_eState = E_DL_SputterBurnState.eBurnIn), PT := tBurnTimeout);                      // 预烧超时 / Burn-in timeout
tonShutter(IN := (_eState = E_DL_SputterBurnState.eRampDown) AND (_uDownStage = 1), PT := DL_SPT_SHUTTER_T); // 关快门让位 / Shutter dwell
tonGasClose(IN := (_eState = E_DL_SputterBurnState.eRampDown) AND (_uDownStage = 2), PT := DL_SPT_GAS_T);    // 关气让位 / Gas dwell
tonDownMax(IN := (_eState = E_DL_SputterBurnState.eRampDown), PT := tRampTimeout);                  // 关断序总超时 / Shutdown timeout

(*------------------------------------------------------------------------------
 * 段 8｜状态机（含三段关断序；打火停机与中止共用关断序）
 *      Phase machine with the three-stage shutdown shared by abort and arc trip
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_SputterBurnState.eIdle:            // 空闲：启动沿 + 组态合法 + 入口可用才进真空核对 / Idle, legal start edge only
        IF rtStart.Q AND _bCfgOk AND (NOT _bSigBad) AND (NOT _bArcTrip) AND (NOT _bAbortReq) THEN
            _fEnergyKWh := 0.0; _nArcTotal := 0; _nArcPrev := nArcCount; // 新靶计数与能量清零 / New target, counters reset
            _uDownStage := 0;               // 关断段号复位 / Shutdown stage reset
            _eState := E_DL_SputterBurnState.eVacCheck; // 进真空核对相 / To the vacuum check
        END_IF
    E_DL_SputterBurnState.eVacCheck:        // 真空核对：气压进带即稳气，超时落故障 / Into the band or time out
        IF _bVacOk THEN _eState := E_DL_SputterBurnState.eGasStab; // 进带，进稳气相 / In band, to stabilisation
        ELSIF tonVac.Q THEN _bVacTmo := TRUE; _eState := E_DL_SputterBurnState.eFault; // 真空超时 → 3F13 / Vacuum timeout, 3F13
        END_IF
    E_DL_SputterBurnState.eGasStab:         // 稳气：带内累计满即爬坡；离带重置；总时超落故障 / In-band accumulation
        IF tonGasMax.Q THEN _bGasTmo := TRUE; _eState := E_DL_SputterBurnState.eFault; // 稳气超时 → 3F14 / Gas timeout, 3F14
        ELSIF tonGas.Q THEN _eState := E_DL_SputterBurnState.eRampUp; // 稳气完成，进爬坡相 / Stabilised, to ramp up
        END_IF
    E_DL_SputterBurnState.eRampUp:          // 爬坡：气压须仍在带内，到设定功率即预烧 / Ramp with the band still proven
        IF NOT _bVacOk THEN _bGasTmo := TRUE; _eState := E_DL_SputterBurnState.eFault; // 爬坡期气压离带 → 3F14 / Band lost, 3F14
        ELSIF _bArcTrip THEN _uDownStage := 0; _eState := E_DL_SputterBurnState.eRampDown; // 打火停机走关断序 / Arc trip, shutdown
        ELSIF ABS(_fPowerCmd - fPowerSetKW) <= DL_SPT_POW_EPS THEN _eState := E_DL_SputterBurnState.eBurnIn; // 到功率，进预烧
        ELSIF tonRamp.Q THEN _bRampTmo := TRUE; _eState := E_DL_SputterBurnState.eFault; // 爬坡超时 → 3F15 / Ramp timeout, 3F15
        END_IF
    E_DL_SputterBurnState.eBurnIn:          // 预烧：能量到量进关断，打火超限立即关断，超时落故障 / Energy or arc or timeout
        IF _bArcTrip THEN _uDownStage := 0; _eState := E_DL_SputterBurnState.eRampDown; // 打火停机走关断序 / Arc trip, shutdown
        ELSIF _fEnergyKWh >= fBurnEnergyKWh THEN _uDownStage := 0; _eState := E_DL_SputterBurnState.eRampDown; // 能量到量，降功率
        ELSIF tonBurn.Q THEN _bBurnTmo := TRUE; _eState := E_DL_SputterBurnState.eFault; // 预烧超时 → 3F16 / Burn-in timeout, 3F16
        END_IF
    E_DL_SputterBurnState.eRampDown:        // 三段关断：0 降功率 → 1 关快门 → 2 关气 → 完成/故障
        IF tonDownMax.Q AND (_uDownStage < 2) THEN _bDownTmo := TRUE; _eState := E_DL_SputterBurnState.eFault; // 关断超时 → 3F18
        ELSIF (_uDownStage = 0) AND (_fPowerCmd <= DL_SPT_POW_EPS) THEN _uDownStage := 1; // 功率到 0，关快门 / Power zero, shutter off
        ELSIF (_uDownStage = 1) AND tonShutter.Q THEN _uDownStage := 2;                   // 快门让位，关气 / Shutter dwelled, gas off
        ELSIF (_uDownStage = 2) AND tonGasClose.Q THEN
            IF _bArcTrip THEN _eState := E_DL_SputterBurnState.eFault;                    // 打火停机落故障 / Arc trip, fault
            ELSE _bInfoDone := TRUE; _eState := E_DL_SputterBurnState.eDone; END_IF         // 正常完成 / Normal completion
        END_IF
    E_DL_SputterBurnState.eDone:            // 完成：启动撤销才回空闲 / Done, back to idle once start drops
        IF NOT xStart THEN _eState := E_DL_SputterBurnState.eIdle; END_IF
    E_DL_SputterBurnState.eFault:           // 故障：复位沿且组态合法且入口可用才回空闲 / Fault, reset edge only
        IF rtReset.Q AND _bCfgOk AND (NOT _bSigBad) THEN _eState := E_DL_SputterBurnState.eIdle; END_IF
    ELSE                                    // 非法状态兜底（R6：CASE 必带 ELSE）/ Illegal-state fallback
        _bIllegal := TRUE; _eState := E_DL_SputterBurnState.eFault; // 非法态 → 3F19，落故障 / Illegal state, 3F19
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜输出置位（三段关断序：功率→快门→气；打火锁存期严禁再进气或开快门）
 *      Output assignment, the three-stage order, no gas or shutter while tripped
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_SputterBurnState.eGasStab:         // 稳气相：只开氩气 / Stabilisation, argon only
        xArValveCmd := TRUE;
    E_DL_SputterBurnState.eRampUp:          // 爬坡相：氩气 + 快门开 / Ramp up with argon and the shutter open
        xArValveCmd := TRUE; xShutterCmd := TRUE;
    E_DL_SputterBurnState.eBurnIn:          // 预烧相：氩气 + 快门开 / Burn-in with argon and the shutter open
        xArValveCmd := TRUE; xShutterCmd := TRUE;
    E_DL_SputterBurnState.eRampDown:        // 关断相：按段号逐级断开 / Shutdown, staged
        xArValveCmd := (_uDownStage < 2);   // 段 2 才关气 / Gas closes at stage 2
        xShutterCmd := (_uDownStage < 1);   // 段 1 才关快门 / Shutter closes at stage 1
    E_DL_SputterBurnState.eDone:            // 完成相：完成电平，两阀全关 / Done, done level and both closed
        bDone := TRUE;
    ELSE                                    // 其余相（空闲/核对/故障）全断 / Other phases, all off
        xArValveCmd := FALSE; xShutterCmd := FALSE;
END_CASE
bRunning := (_eState <> E_DL_SputterBurnState.eIdle) AND (_eState <> E_DL_SputterBurnState.eDone)
            AND (_eState <> E_DL_SputterBurnState.eFault); // 运行标志 / Running flag

(*------------------------------------------------------------------------------
 * 段 10｜错误码映射（锁存回放，R187：故障相不按当下输入重推断）
 *      Error-code map, latched replay
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN nErrCode := 16#0005_3F19; bError := TRUE;        // 故障级兜底：非法态 / Fault, illegal state fallback
ELSIF _bCfgBad THEN nErrCode := 16#0005_3F11; bError := TRUE;      // 故障级：组态非法 / Fault, illegal configuration
ELSIF _bSigBad THEN nErrCode := 16#0005_3F12; bError := TRUE;      // 故障级：入口非有限 / Fault, non-finite inlet
ELSIF _bArcTrip THEN nErrCode := 16#0005_3F17; bError := TRUE;     // 故障级：打火超限 / Fault, arc trip
ELSIF _bVacTmo THEN nErrCode := 16#0005_3F13; bError := TRUE;      // 故障级：真空超时 / Fault, vacuum timeout
ELSIF _bGasTmo THEN nErrCode := 16#0005_3F14; bError := TRUE;      // 故障级：稳气超时或离带 / Fault, gas timeout or band loss
ELSIF _bRampTmo THEN nErrCode := 16#0005_3F15; bError := TRUE;     // 故障级：爬坡超时 / Fault, ramp timeout
ELSIF _bBurnTmo THEN nErrCode := 16#0005_3F16; bError := TRUE;     // 故障级：预烧超时 / Fault, burn-in timeout
ELSIF _bDownTmo THEN nErrCode := 16#0005_3F18; bError := TRUE;     // 故障级：关断序超时 / Fault, shutdown timeout
ELSIF _bInfoDone THEN nErrCode := 16#0005_3F91;                    // 信息级：预烧完成 / Info, burn-in done
END_IF
END_FUNCTION_BLOCK
