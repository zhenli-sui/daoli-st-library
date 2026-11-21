//==============================================================================
// 功能块：FB_DL_CoilFrostWindow ｜ 中文名称：盘管结霜窗口判定与除霜请求
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：结霜双判据窗——盘管表面温度同时满足「冻结判据」（表面温度
//           <= 结霜阈值）与「露点判据」（表面温度 <= 露点 - 裕度，有凝
//           才有霜）持续 tFrostDwell → 结霜窗确认，锁存除霜请求；除霜
//           完成判据 = 表面温度 > 结霜阈值 + 回差 fThawHystK（退出回差，
//           阈值附近抖动防频动，R23 教训同理）。露点由 Magnus-Tetens
//           内联解算（Device 不得调用 DL_Algo，见依赖纪律）。
// 开源溯源 (Origin)：道莅原创实现（参考换热盘管结霜判据与除霜控制工程惯例 分类与参数域）
// 单位表：温度[摄氏度] / 露点[摄氏度] / 裕度与回差[开] / 时间[ms]
// 错误码表：16#0003_018A 信息级（结霜窗确认、除霜请求锁存建立，不置
//           bError）/ 16#0003_018B 信息级（除霜完成回差退出，请求解除，
//           不置 bError）/ 16#0003_0360 故障级（组态非法：阈值/裕度/
//           回差域、时间窗 <= 0 或任一输入非有限，置 bError）/
//           16#0003_0361 故障级（传感器交叉校验失败：解算露点 > 干球
//           + 1 开，物理不可能，判湿度/温度通道异常，安全侧锁存除霜
//           请求，置 bError——该场景不可由 0360 的组态类判据观测，
//           属运行数据独立域）/ 16#0003_0362 故障级兜底（状态机落 ELSE，
//           置 bError）
// 状态机：E_DL_CoilFrostState（五态：eIdle=0 / eMonitor=10 / eFrost=20 /
//           eDefrost=30 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 0362
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 湿度域外钳
//           1~100 照算（Magnus 对数域下限保证）；③ 驻留窗未满判据消失
//           → 自动回监视态（防瞬时低温误锁存）；④ 除霜请求锁存后仅
//           回差退出或 bReset 解除；⑤ 未使能输出冻结零并 bValid :=
//           FALSE（除霜请求不在未使能态保持——使能即监视语义）；⑥
//           安全侧 = 交叉校验失败时锁存除霜请求（宁多除一次，不漏霜）。
// 依赖纪律：Device 不得调用 DL_Algo——Magnus-Tetens 露点解算在本件内联
//           实现，常量口径（17.62/243.12/611.2）与 FC_DL_AirDensity
//           族一致性由本件头注释承担验证责任，改动任一侧须复核另一侧。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §727）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_CoilFrostState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 结霜监视相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_CoilFrostState :
(
    eIdle    := 0,   // 空闲：未使能 / Idle, not enabled
    eMonitor := 10,  // 监视：判据计窗中 / Monitor, criteria window counting
    eFrost   := 20,  // 霜窗：双判据持续驻留已确认 / Frost, dual-criteria dwell confirmed
    eDefrost := 30,  // 除霜：请求锁存保持，等回差退出 / Defrost, request latched, awaiting the hysteresis exit
    eFault   := 99   // 故障：组态非法/交叉校验/非法状态 / Fault, config, cross-check or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoilFrostWindow
VAR_INPUT
    bEnable         : BOOL;                 // 监视使能 [—] / Monitoring enable
    bReset          : BOOL;                 // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    fAirTempC       : LREAL;                // 空气干球温度 [摄氏度] / Air dry-bulb temperature [degC]
    fRhPct          : LREAL;                // 空气相对湿度 [百分数]，域外钳 1..100 照算 / Air relative humidity [percent], clamped 1..100
    fCoilSurfTempC  : LREAL;                // 盘管表面温度 [摄氏度] / Coil surface temperature [degC]
    fFrostThreshC   : LREAL := 0.0;         // 结霜阈值 [摄氏度]，表面低于此判冻结 / Frost threshold [degC], freezing below
    fDpMarginK      : LREAL := 1.0;         // 露点裕度 [开]，表面低于露点减此值判凝露 / Dew-point margin [K]
    fThawHystK      : LREAL := 2.0;         // 除霜退出回差 [开]，须 > 0 且 < 裕度 + 10 / Thaw hysteresis [K], exit band width
    tFrostDwell     : TIME  := T#60S;       // 双判据驻留窗 [ms]，须 > 0 / Dual-criteria dwell window [ms]
END_VAR
VAR_OUTPUT
    fDewPointC      : LREAL;                // 解算露点 [摄氏度]（诊断出口） / Solved dew point [degC], diagnostics outlet
    bFrostWindow    : BOOL;                 // 结霜窗判定中 [—]（霜窗态电平） / Frost-window active level
    bDefrostReq     : BOOL;                 // 除霜请求 [—]（锁存保持） / Defrost request, latched
    eState          : E_DL_CoilFrostState;  // 相位出口 [—] / Phase outlet
    eErr            : UDINT;                // 错误码，0 = 无错，码位 16#0003_018A 起信息级、16#0003_0360 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                 // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                 // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDwell     : TON;                      // 双判据驻留计时（每拍无条件刷新）[ms] / Dwell timer, refreshed unconditionally
    _eState     : E_DL_CoilFrostState := E_DL_CoilFrostState.eIdle; // 当前相位 / Current phase
    _bCfgBad    : BOOL;                     // 组态非法锁存 / Illegal config latch
    _bCrossBad  : BOOL;                     // 交叉校验失败锁存 / Cross-check fault latch
    _bInfoFrost : BOOL;                     // 霜窗信息当拍标志 / Frost-window info flag of this scan
    _bInfoDone  : BOOL;                     // 除霜完成信息当拍标志 / Defrost-done info flag of this scan
    _bDefrostL  : BOOL;                     // 除霜请求锁存 / Defrost request latch
    _fRhUse     : LREAL;                    // 生效湿度（已钳位）[百分数] / Effective humidity, clamped
    _fGamma     : LREAL;                    // 露点解算中间量 ln(RH/100) [无量纲] / Dew-point intermediate ln(RH/100)
    _fDpCalc    : LREAL;                    // 解算露点 [摄氏度] / Solved dew point [degC]
    _bIllegal   : BOOL;                     // 非法状态标志 / Illegal state flag
    _bInit      : BOOL := FALSE;            // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_CFW_MAGNUS_A : LREAL := 17.62;       // Magnus 系数 A [无量纲]，与 FC_DL_AirDensity 同口径 / Magnus coefficient A, aligned with FC_DL_AirDensity
    DL_CFW_MAGNUS_B : LREAL := 243.12;      // Magnus 系数 B [摄氏度]，同口径 / Magnus coefficient B, aligned
    DL_CFW_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_CFW_EPS      : LREAL := 1.0E-6;      // 浮点判零容差 [混合] / Float zero tolerance
    DL_CFW_RH_MIN   : LREAL := 1.0;         // 湿度钳位下限 [百分数]（对数域保证） / Humidity clamp floor [percent]
    DL_CFW_RH_MAX   : LREAL := 100.0;       // 湿度钳位上限 [百分数] / Humidity clamp ceiling [percent]
    DL_CFW_CROSS_K  : LREAL := 1.0;         // 交叉校验容差 [开]（露点 > 干球 + 此值判异常） / Cross-check tolerance [K]
    DL_CFW_ZERO     : LREAL := 0.0;         // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出安全侧清零，单拍标志预清零
 *      Outputs cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fDewPointC   := DL_CFW_ZERO;             // 露点出口先清 / Dew point cleared first
bFrostWindow := FALSE;                   // 霜窗电平先清 / Frost level cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoFrost := FALSE;                    // 霜窗信息预清零 / Frost info pre-cleared
_bInfoDone  := FALSE;                    // 完成信息预清零 / Done info pre-cleared
_bIllegal   := FALSE;                    // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState    := E_DL_CoilFrostState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad   := FALSE;                 // 组态锁存清零 / Config latch cleared
    _bCrossBad := FALSE;                 // 交叉锁存清零 / Cross latch cleared
    _bDefrostL := FALSE;                 // 请求锁存清零 / Request latch cleared
    _bInit     := TRUE;                  // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 阈值/裕度/回差/时间窗域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fAirTempC <> fAirTempC) OR (ABS(fAirTempC) > DL_CFW_INF)
   OR (fRhPct <> fRhPct) OR (ABS(fRhPct) > DL_CFW_INF)
   OR (fCoilSurfTempC <> fCoilSurfTempC) OR (ABS(fCoilSurfTempC) > DL_CFW_INF)
   OR (fFrostThreshC <> fFrostThreshC) OR (ABS(fFrostThreshC) > DL_CFW_INF)
   OR (fDpMarginK <> fDpMarginK) OR (ABS(fDpMarginK) > DL_CFW_INF)
   OR (fThawHystK <> fThawHystK) OR (ABS(fThawHystK) > DL_CFW_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fThawHystK <= DL_CFW_EPS) OR (tFrostDwell <= T#0MS)
   OR (fDpMarginK < DL_CFW_ZERO)) THEN
    _bCfgBad := TRUE;                    // 回差/时间窗/裕度域非法锁存 / Hysteresis, window and margin domains latched
END_IF
IF bReset THEN
    _bCfgBad   := FALSE;                 // 复位清组态锁存 / Reset clears the config latch
    _bCrossBad := FALSE;                 // 复位清交叉锁存 / Reset clears the cross latch
    _bDefrostL := FALSE;                 // 复位清请求锁存 / Reset clears the request latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜湿度钳位与露点内联解算（Device 泳道零外部依赖）
 *      Humidity clamp and the inline dew-point solve
 *-----------------------------------------------------------------------------*)
_fRhUse := MIN(MAX(fRhPct, DL_CFW_RH_MIN), DL_CFW_RH_MAX); // 湿度双侧钳位（对数域下限保证） / Two-sided humidity clamp
_fGamma := LN(_fRhUse / 100.0);          // 中间量 ln(RH/100) [无量纲]，恒 <= 0 / Intermediate, always <= 0
_fDpCalc := DL_CFW_MAGNUS_B * _fGamma / (DL_CFW_MAGNUS_A - _fGamma); // Magnus 露点反解 [摄氏度]，分母恒 > 17 / Magnus dew-point solve, denominator always > 17
fDewPointC := _fDpCalc;                  // 露点诊断出口 / Dew-point diagnostics outlet

(*------------------------------------------------------------------------------
 * 段 5｜传感器交叉校验：露点 > 干球 + 容差 → 物理不可能，判通道异常
 *      Sensor cross-check: dew point above the dry bulb is impossible
 *-----------------------------------------------------------------------------*)
IF (NOT _bCfgBad) AND (_fDpCalc > (fAirTempC + DL_CFW_CROSS_K)) THEN
    _bCrossBad := TRUE;                  // 交叉校验失败锁存（安全侧锁存请求） / Cross-check failure latched, request latched on the safe side
    _bDefrostL := TRUE;                  // 安全侧：宁多除一次，不漏霜 / Safe side: defrost rather than miss frost
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜驻留计时无条件刷新（R40：CASE 之外每拍必调）
 *      Dwell timer refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbDwell(IN := (_eState = E_DL_CoilFrostState.eMonitor)
             AND (fCoilSurfTempC <= fFrostThreshC)
             AND (fCoilSurfTempC <= (_fDpCalc - fDpMarginK)),
        PT := tFrostDwell);              // 双判据驻留窗 / Dual-criteria dwell window

(*------------------------------------------------------------------------------
 * 段 7｜相位机（CASE 含 ELSE 兜底；未使能/异常落故障态）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR _bCfgBad OR _bCrossBad THEN
    _eState := E_DL_CoilFrostState.eFault; // 未使能或异常转故障态 / Not enabled or anomaly, fault
ELSE
CASE _eState OF

    E_DL_CoilFrostState.eIdle:             // 空闲：使能进监视
        IF bEnable THEN
            _eState := E_DL_CoilFrostState.eMonitor; // 进监视 / To monitor
        END_IF

    E_DL_CoilFrostState.eMonitor:          // 监视：双判据驻留满进霜窗
        IF NOT bEnable THEN
            _eState := E_DL_CoilFrostState.eFault; // 使能撤销转故障 / Enable dropped, fault
        ELSIF fbDwell.Q THEN
            _bInfoFrost := TRUE;           // 霜窗确认（信息级，拍 N 进入） / Frost window confirmed, info
            _bDefrostL := TRUE;            // 除霜请求锁存建立 / Defrost request latched
            _eState := E_DL_CoilFrostState.eDefrost; // 进除霜态 / To defrost
        END_IF

    E_DL_CoilFrostState.eFrost:            // 霜窗：请求已锁存，转除霜态保持
        _bDefrostL := TRUE;                // 请求保持 / Request held
        _eState := E_DL_CoilFrostState.eDefrost; // 进除霜态 / To defrost

    E_DL_CoilFrostState.eDefrost:          // 除霜：回差退出或复位解除
        IF (NOT bEnable) OR _bCfgBad THEN
            _eState := E_DL_CoilFrostState.eFault; // 异常转故障 / Anomaly, fault
        ELSIF fCoilSurfTempC > (fFrostThreshC + fThawHystK) THEN
            _bInfoDone := TRUE;            // 除霜完成回差退出（信息级） / Thaw hysteresis exit, info
            _bDefrostL := FALSE;           // 请求解除 / Request released
            _eState := E_DL_CoilFrostState.eMonitor; // 回监视 / Back to monitor
        END_IF

    E_DL_CoilFrostState.eFault:            // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) AND (NOT _bCrossBad) THEN
            _eState := E_DL_CoilFrostState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_CoilFrostState.eFault; // 回故障态 / Back to fault
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_0362;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCrossBad THEN
    eErr   := 16#0003_0361;                // 故障级：传感器交叉校验失败 / Fault: sensor cross-check failed
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0003_0360;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoDone THEN
    eErr := 16#0003_018B;                  // 信息级：除霜完成回差退出 / Info: thaw hysteresis exit
ELSIF _bInfoFrost THEN
    eErr := 16#0003_018A;                  // 信息级：结霜窗确认 / Info: frost window confirmed
END_IF

bFrostWindow := (_eState = E_DL_CoilFrostState.eDefrost); // 霜窗电平 = 除霜态（锁存期） / Frost level equals the defrost phase
bDefrostReq  := _bDefrostL;              // 除霜请求出口 = 锁存量（R99） / Defrost request outlet equals the latch
bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_CoilFrostState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
