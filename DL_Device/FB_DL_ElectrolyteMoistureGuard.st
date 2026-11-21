//==============================================================================
// 功能块：FB_DL_ElectrolyteMoistureGuard ｜ 中文名称：注液间露点/湿度联锁（首因锁定）
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：电解液注液间环境联锁——露点 > 露点上限 或 相对湿度 > 湿度
//           上限，任一越限持续 tDebounce → 禁止注液（bDosingPermit :=
//           FALSE），并按「首因锁定」原则记录首个触发的判据通道（bFirstCauseDp
//           / bFirstCauseRh，锁存至 bReset，中途恢复不抹除首因——归因
//           证据链不得被后续波动重写，R81 还原方向不饱和同理）。接近
//           限值预警带内给信息级提示，供提前干预。露点由 Magnus-Tetens
//           内联解算（Device 不得调用 DL_Algo，见依赖纪律）。
// 开源溯源 (Origin)：道莅原创实现（参考锂电注液间露点联锁工程惯例（电芯制程湿度管控） 分类与参数域）
// 单位表：温度[摄氏度] / 露点[摄氏度] / 相对湿度[百分数] / 预警带[开] / 时间[ms]
// 错误码表：16#0003_018C 信息级（联锁恢复放行：阻塞判据消失回放行，
//           不置 bError）/ 16#0003_018D 信息级（接近限值预警带：露点
//           落入 [上限 - 预警带, 上限]，不置 bError）/ 16#0003_0363 故障级
//           （组态非法：上限/带宽域、去抖窗 <= 0 或任一输入非有限，
//           置 bError）/ 16#0003_0364 故障级（传感器交叉校验失败：解算
//           露点 > 干球 + 1 开，物理不可能，判温湿度通道异常，安全侧
//           禁止放行，置 bError——该场景不可由 0363 的组态类判据观测，
//           属运行数据独立域）/ 16#0003_0365 故障级兜底（状态机落 ELSE，
//           置 bError）
// 状态机：E_DL_MoistGuardState（四态：eIdle=0 / ePermit=10 / eBlock=20 /
//           eFault=99），CASE 含 ELSE 兜底，ELSE 置 0365 并撤放行
// 边界行为：① 组态非法 → 故障态锁存（放行安全侧 FALSE），bReset 复位；
//           ② 湿度域外钳 1~100 照算（Magnus 对数域下限保证）；③ 越限
//           消抖未满期判据消失 → 不进阻塞（防瞬时噪声断链）；④ 首因
//           锁存只在 bReset 清除，恢复放行不抹首因（归因证据链）；
//           ⑤ 未使能放行输出 FALSE 且 bValid := FALSE；⑥ 安全侧 =
//           故障/交叉失败路径放行恒 FALSE（禁止注液为安全侧）。
// 依赖纪律：Device 不得调用 DL_Algo——Magnus-Tetens 露点解算在本件内联
//           实现，常量口径（17.62/243.12）与 FC_DL_AirDensity 族一致性
//           由本件头注释承担验证责任，改动任一侧须复核另一侧。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §693）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_MoistGuardState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 环境联锁相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_MoistGuardState :
(
    eIdle   := 0,   // 空闲：未使能 / Idle, not enabled
    ePermit := 10,  // 放行：判据全部满足 / Permit, all criteria satisfied
    eBlock  := 20,  // 阻塞：越限去抖确认，禁止注液 / Block, violation debounced, dosing forbidden
    eFault  := 99   // 故障：组态非法/交叉校验/非法状态 / Fault, config, cross-check or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrolyteMoistureGuard
VAR_INPUT
    bEnable      : BOOL;                    // 联锁使能 [—] / Interlock enable
    bReset       : BOOL;                    // 故障复位 [—]，上升沿清首因/组态锁存 / Fault reset, rising edge clears latches
    bDosingReq   : BOOL;                    // 注液请求 [—]（联锁仅门控，不接管请求） / Dosing request, gated only
    fRoomTempC   : LREAL;                   // 注液间干球温度 [摄氏度] / Room dry-bulb temperature [degC]
    fRhPct       : LREAL;                   // 注液间相对湿度 [百分数]，域外钳 1..100 照算 / Room relative humidity [percent], clamped 1..100
    fDpLimitC    : LREAL := -40.0;          // 露点联锁上限 [摄氏度]，高于此越限 / Dew-point interlock limit [degC]
    fRhLimitPct  : LREAL := 10.0;           // 湿度联锁上限 [百分数]，高于此越限，按工艺卡组态 / Humidity interlock limit [percent]
    fWarnBandK   : LREAL := 2.0;            // 接近限值预警带宽 [开]，须 >= 0 / Warning band width [K]
    tDebounce    : TIME  := T#5S;           // 越限去抖窗 [ms]，须 > 0 / Violation debounce window [ms]
END_VAR
VAR_OUTPUT
    bDosingPermit  : BOOL;                  // 注液放行 [—]（联锁门控输出） / Dosing permit, gated output
    fDewPointC     : LREAL;                 // 解算露点 [摄氏度]（诊断出口） / Solved dew point [degC], diagnostics outlet
    bFirstCauseDp  : BOOL;                  // 首因锁存：露点通道 [—]（bReset 才清除） / First-cause latch, dew-point channel
    bFirstCauseRh  : BOOL;                  // 首因锁存：湿度通道 [—]（bReset 才清除） / First-cause latch, humidity channel
    eGuardState    : E_DL_MoistGuardState;  // 联锁相位 [—] / Interlock phase
    eErr           : UDINT;                 // 错误码，0 = 无错，码位 16#0003_018C 起信息级、16#0003_0363 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbDebounce : TON;                       // 越限去抖计时（每拍无条件刷新）[ms] / Violation debounce timer, refreshed unconditionally
    _eState    : E_DL_MoistGuardState := E_DL_MoistGuardState.eIdle; // 当前相位 / Current phase
    _bCfgBad   : BOOL;                      // 组态非法锁存 / Illegal config latch
    _bCrossBad : BOOL;                      // 交叉校验失败锁存 / Cross-check fault latch
    _bInfoRel  : BOOL;                      // 恢复放行信息当拍标志 / Recovery info flag of this scan
    _bInfoWarn : BOOL;                      // 预警带信息当拍标志 / Warning-band info flag of this scan
    _fRhUse    : LREAL;                     // 生效湿度（已钳位）[百分数] / Effective humidity, clamped
    _fGamma    : LREAL;                     // 露点解算中间量 ln(RH/100) [无量纲] / Dew-point intermediate
    _fDpCalc   : LREAL;                     // 解算露点 [摄氏度] / Solved dew point [degC]
    _bViolate  : BOOL;                      // 越限电平（去抖窗条件） / Violation level, debounce condition
    _bIllegal  : BOOL;                      // 非法状态标志 / Illegal state flag
    _bInit     : BOOL := FALSE;             // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_EMG_MAGNUS_A : LREAL := 17.62;       // Magnus 系数 A [无量纲]，与 FC_DL_AirDensity 同口径 / Magnus coefficient A, aligned
    DL_EMG_MAGNUS_B : LREAL := 243.12;      // Magnus 系数 B [摄氏度]，同口径 / Magnus coefficient B, aligned
    DL_EMG_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_EMG_EPS      : LREAL := 1.0E-6;      // 浮点判零容差 [混合] / Float zero tolerance
    DL_EMG_RH_MIN   : LREAL := 1.0;         // 湿度钳位下限 [百分数] / Humidity clamp floor [percent]
    DL_EMG_RH_MAX   : LREAL := 100.0;       // 湿度钳位上限 [百分数] / Humidity clamp ceiling [percent]
    DL_EMG_CROSS_K  : LREAL := 1.0;         // 交叉校验容差 [开] / Cross-check tolerance [K]
    DL_EMG_ZERO     : LREAL := 0.0;         // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：放行先断（安全侧），单拍标志预清零
 *      Permit cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bDosingPermit := FALSE;                  // 放行先断（安全侧） / Permit cleared first
fDewPointC    := DL_EMG_ZERO;            // 露点出口先清 / Dew point cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoRel  := FALSE;                     // 恢复信息预清零 / Recovery info pre-cleared
_bInfoWarn := FALSE;                     // 预警信息预清零 / Warn info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState    := E_DL_MoistGuardState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad   := FALSE;                 // 组态锁存清零 / Config latch cleared
    _bCrossBad := FALSE;                 // 交叉锁存清零 / Cross latch cleared
    _bInit     := TRUE;                  // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 上限/带宽/去抖窗域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fRoomTempC <> fRoomTempC) OR (ABS(fRoomTempC) > DL_EMG_INF)
   OR (fRhPct <> fRhPct) OR (ABS(fRhPct) > DL_EMG_INF)
   OR (fDpLimitC <> fDpLimitC) OR (ABS(fDpLimitC) > DL_EMG_INF)
   OR (fRhLimitPct <> fRhLimitPct) OR (ABS(fRhLimitPct) > DL_EMG_INF)
   OR (fWarnBandK <> fWarnBandK) OR (ABS(fWarnBandK) > DL_EMG_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fRhLimitPct <= DL_EMG_EPS) OR (fRhLimitPct > 100.0)
   OR (fWarnBandK < DL_EMG_ZERO) OR (tDebounce <= T#0MS)) THEN
    _bCfgBad := TRUE;                    // 上限/带宽/去抖窗域非法锁存 / Limit, band and window domains latched
END_IF
IF bReset THEN
    _bCfgBad   := FALSE;                 // 复位清组态锁存 / Reset clears the config latch
    _bCrossBad := FALSE;                 // 复位清交叉锁存 / Reset clears the cross latch
    bFirstCauseDp := FALSE;              // 复位清首因锁存（露点） / Reset clears the dew-point first cause
    bFirstCauseRh := FALSE;              // 复位清首因锁存（湿度） / Reset clears the humidity first cause
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜湿度钳位与露点内联解算（Device 泳道零外部依赖）
 *      Humidity clamp and the inline dew-point solve
 *-----------------------------------------------------------------------------*)
_fRhUse := MIN(MAX(fRhPct, DL_EMG_RH_MIN), DL_EMG_RH_MAX); // 湿度双侧钳位 / Two-sided humidity clamp
_fGamma := LN(_fRhUse / 100.0);          // 中间量 ln(RH/100) [无量纲]，恒 <= 0 / Intermediate, always <= 0
_fDpCalc := DL_EMG_MAGNUS_B * _fGamma / (DL_EMG_MAGNUS_A - _fGamma); // Magnus 露点反解 [摄氏度]，分母恒 > 17 / Magnus dew-point solve
fDewPointC := _fDpCalc;                  // 露点诊断出口 / Dew-point diagnostics outlet

(*------------------------------------------------------------------------------
 * 段 5｜传感器交叉校验：露点 > 干球 + 容差 → 物理不可能，安全侧禁止放行
 *      Sensor cross-check, safe side blocks the permit
 *-----------------------------------------------------------------------------*)
IF (NOT _bCfgBad) AND (_fDpCalc > (fRoomTempC + DL_EMG_CROSS_K)) THEN
    _bCrossBad := TRUE;                  // 交叉校验失败锁存 / Cross-check failure latched
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜越限电平与去抖计时无条件刷新（R40：CASE 之外每拍必调）
 *      Violation level and debounce timer refreshed unconditionally
 *-----------------------------------------------------------------------------*)
_bViolate := (_fDpCalc > fDpLimitC) OR (_fRhUse > fRhLimitPct); // 双判据任一越限 / Either criterion violated
fbDebounce(IN := (_eState = E_DL_MoistGuardState.ePermit) AND _bViolate,
           PT := tDebounce);             // 越限去抖窗（放行态起算） / Violation debounce window, from the permit phase

(*------------------------------------------------------------------------------
 * 段 7｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR _bCfgBad OR _bCrossBad THEN
    _eState := E_DL_MoistGuardState.eFault; // 未使能或异常转故障态（放行 FALSE） / Not enabled or anomaly, fault, permit FALSE
ELSE
CASE _eState OF

    E_DL_MoistGuardState.eIdle:            // 空闲：使能进放行态
        IF bEnable THEN
            _eState := E_DL_MoistGuardState.ePermit; // 进放行 / To permit
        END_IF

    E_DL_MoistGuardState.ePermit:          // 放行：越限去抖满进阻塞；预警带提示
        IF NOT bEnable THEN
            _eState := E_DL_MoistGuardState.eFault; // 使能撤销转故障 / Enable dropped, fault
        ELSIF fbDebounce.Q THEN
            IF _fDpCalc > fDpLimitC THEN
                bFirstCauseDp := TRUE;     // 首因锁定：露点通道（bReset 才清） / First cause, dew-point channel
            END_IF
            IF _fRhUse > fRhLimitPct THEN
                bFirstCauseRh := TRUE;     // 首因锁定：湿度通道（bReset 才清） / First cause, humidity channel
            END_IF
            _eState := E_DL_MoistGuardState.eBlock; // 进阻塞 / To block
        ELSIF _fDpCalc >= (fDpLimitC - fWarnBandK) THEN
            _bInfoWarn := TRUE;            // 接近限值预警带（信息级） / Warning-band notice, info
        END_IF

    E_DL_MoistGuardState.eBlock:           // 阻塞：越限判据全部消失回放行（首因保持）
        IF NOT bEnable THEN
            _eState := E_DL_MoistGuardState.eFault; // 使能撤销转故障 / Enable dropped, fault
        ELSIF (NOT _bViolate) AND (NOT fbDebounce.Q) THEN
            _bInfoRel := TRUE;             // 联锁恢复放行（信息级，拍 N 进入） / Recovery, permit restored, info
            _eState := E_DL_MoistGuardState.ePermit; // 回放行 / Back to permit
        END_IF

    E_DL_MoistGuardState.eFault:           // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) AND (NOT _bCrossBad) THEN
            _eState := E_DL_MoistGuardState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_MoistGuardState.eFault; // 回故障态（放行 FALSE） / Back to fault, permit FALSE
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0003_0365;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCrossBad THEN
    eErr   := 16#0003_0364;                // 故障级：传感器交叉校验失败 / Fault: sensor cross-check failed
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0003_0363;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoWarn THEN
    eErr := 16#0003_018D;                  // 信息级：接近限值预警带 / Info: warning band
ELSIF _bInfoRel THEN
    eErr := 16#0003_018C;                  // 信息级：联锁恢复放行 / Info: interlock recovery
END_IF

bDosingPermit := (NOT bError) AND (_eState = E_DL_MoistGuardState.ePermit); // 放行挂状态量（R99） / Permit bound to the state
bValid := (NOT bError) AND bEnable AND (_eState <> E_DL_MoistGuardState.eIdle); // 空闲/故障/未使能输出不可用 / Outputs unusable in idle, fault or disabled
eGuardState := _eState;                  // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
