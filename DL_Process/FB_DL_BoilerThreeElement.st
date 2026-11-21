//==============================================================================
// 功能块：FB_DL_BoilerThreeElement ｜ 中文名称：锅炉三冲量给水控制（复杂度 H）
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：锅炉三冲量给水——汽包水位主回路（组合调用 FB_DL_PidController）
//           + 蒸汽流量前馈① + 给水流量反馈②，合成给水流量给定 [t/h]；
//           手/自无扰切换（跟踪）；蒸汽/给水流量比持续偏离判泄漏疑似。
// 开源溯源 (Origin)：道莅原创实现（参考锅炉三冲量给水控制工程惯例 分类与参数域）
// 单位表：水位[%] / 流量[t/h] / 增益[（t/h）/（t/h）] / 给定满量程[t/h] /
//         PID 参数[s] / 确认窗[ms] / 比偏阈[倍]
// 错误码表：16#0005_01EC 信息级（给水/蒸汽流量比持续超偏，泄漏疑似，
//           R13 三分类诊断范式，不置 bError）/ 16#0005_01ED 预留禁用
//           （不得挪用）/ 16#0005_0327 故障级（任一流量/水位非有限，保持
//           末次有效给定，切手动会扰动汽包，与 R22 CrossLimitSelect 同侧
//           策略，置 bError）/ 16#0005_0328 预留禁用（不得挪用）/
//           16#0005_0329 故障级兜底（置 bError）
// 状态机：N/A（手/自切换 + 前馈合成 + 比偏判窗为电平逻辑，无相位状态机）
// 边界行为：① 任一流量/水位非有限 → 保持末次有效给定 + 故障 0327（不
//           静默归零——切手动会扰动汽包）；② bAutoMode 下降沿 → 无扰切
//           手动（给定冻结为当前值）；③ 手动→自动无扰切换（PID 跟踪
//           注入当前给定）；④ 流量比超偏持续确认窗 → 信息 01EC；
//           ⑤ 给定下限钳 0（不倒转）；⑥ 非有限前馈增益 → 0327 复用。
// 依赖纪律：Process → Level 0/1 组合调用合法——水位主回路组合调用
//           FB_DL_PidController（DL_Algo，接口已核实：bEnable/bManual/
//           fSetpoint/fActual/fKp/tTi/tTd/rOutMin/rOutMax/bTrack/fTrackValue/
//           fOut），头注释依赖清单声明；蒸汽前馈律在本件内联（单乘法
//           合成属编排语义，非算法复制）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP P1 §322）
//==============================================================================

FUNCTION_BLOCK FB_DL_BoilerThreeElement
VAR_INPUT
    fDrumLevelPct  : LREAL;                 // 汽包水位实测 [百分数] / Drum level [percent]
    fSteamFlowTh   : LREAL;                 // 蒸汽流量 [吨/小时]，前馈① / Steam flow [t/h], feedforward 1
    fFeedFlowTh    : LREAL;                 // 给水流量 [吨/小时]，反馈② / Feedwater flow [t/h], feedback 2
    fLevelSpPct    : LREAL := 50.0;         // 水位设定 [百分数] / Level setpoint [percent]
    fFwdGainSteam  : LREAL := 1.0;          // 蒸汽前馈增益 [（吨/小时）/（吨/小时）] / Steam feedforward gain
    fLevelKp       : LREAL := 2.0;          // 水位主回比例增益 [1] / Level loop proportional gain
    tLevelTi       : TIME  := T#30S;        // 水位主回积分时间 [s]，T#0S = 纯 PD / Level loop integral time [s]
    tLevelTd       : TIME  := T#0S;         // 水位主回微分时间 [s]，T#0S = 关闭 / Level loop derivative time [s]
    bAutoMode      : BOOL;                  // 自动模式请求 [—] / Auto mode request
    bReset         : BOOL;                  // 故障复位 [—] / Fault reset
END_VAR
VAR_OUTPUT
    fFeedSpTh      : LREAL;                 // 给水流量给定 [吨/小时] = PID 主回路 + 双前馈 / Feedwater setpoint [t/h] = PID plus feedforwards
    bAuto          : BOOL;                  // 实际自动态 [—] / Actual auto state
    eErr           : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = no error
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbLevelPid     : FB_DL_PidController;   // 水位主回 PID（Level 0 组合调用） / Level loop PID, Level 0 composition
    fbRatioWin     : TON;                   // 流量比偏确认窗，段 6 无条件刷新 [ms] / Ratio-deviation confirm window
    _fFeedSpHeld   : LREAL;                 // 末次有效给定保持量 [吨/小时] / Held last valid setpoint [t/h]
    _fPidTrackPct  : LREAL;                 // 跟踪/手动值（PID % 域换算） [%] / Track and manual value in the PID percent domain
    _bAutoPrev     : BOOL;                  // 自动请求上拍电平快照 / Previous-scan auto request snapshot
    _bTrackNow     : BOOL;                  // 无扰投切跟踪当拍标志 / Bumpless track flag of this scan
    _bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bFiniteBad    : BOOL;                  // 非有限锁存 / Non-finite latch
    _bRatioSuspect : BOOL;                  // 比偏疑似当拍标志 / Ratio-suspect flag of this scan
    _bIllegal      : BOOL;                  // 非法状态标志 / Illegal state flag
END_VAR
VAR CONSTANT
    DL_BLR_SPAN_TH  : LREAL := 100.0;       // 给水给定满量程 [吨/小时]，PID 输出 [%] → [t/h] 映射基准 / Feedwater setpoint span [t/h], PID percent mapping base
    DL_BLR_RATIO_DEV: LREAL := 2.0;         // 给水/蒸汽比偏阈 [倍] / Feed-to-steam ratio deviation bound [ratio]
    DL_BLR_RATIO_WIN: TIME  := T#10S;       // 比偏确认窗 [ms] / Ratio-deviation confirm window [ms]
    DL_BLR_FLOW_MIN : LREAL := 1.0;         // 比偏判据流量下限 [吨/小时]，防小流量假比 / Ratio floor [t/h], guards a false ratio at low flows
    DL_BLR_INF      : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_BLR_EPS      : LREAL := 1.0E-6;      // 浮点判零容差 / Float zero tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：给定保持量起步为零，单拍标志预清零
 *      Held setpoint starts at zero, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fFeedSpTh := 0.0;                           // 给定预置零（异常路径由保持量覆盖） / Setpoint preset zero, held value overrides on anomaly
bAuto     := FALSE;                         // 自动态预置 FALSE / Auto preset FALSE
eErr      := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError    := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid    := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bTrackNow  := FALSE;                       // 跟踪标志预清零 / Track flag pre-cleared
_bRatioSuspect := FALSE;                    // 比偏标志预清零 / Ratio flag pre-cleared
_bIllegal   := FALSE;                       // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化与手/自沿检测
 *      First-scan initialisation and the auto-edge detection
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _fFeedSpHeld := 0.0;                    // 保持量清零 / Held value cleared
    _bFiniteBad  := FALSE;                  // 非有限锁存清零 / Non-finite latch cleared
    _bInit       := TRUE;                   // 首扫只做一次 / The first scan runs once
END_IF
IF (NOT bAutoMode) AND _bAutoPrev THEN
    _bTrackNow := FALSE;                    // 下降沿：无扰切手动（给定冻结，PID bManual 承担） / Falling edge, bumpless to manual, the setpoint freezes
END_IF
IF bAutoMode AND (NOT _bAutoPrev) THEN
    _bTrackNow := TRUE;                     // 上升沿：无扰投切（PID 跟踪注入当前给定） / Rising edge, bumpless track injection
END_IF
_bAutoPrev := bAutoMode;                    // 电平快照推进 / Snapshot advanced

(*------------------------------------------------------------------------------
 * 段 3｜输入防御闸（任一流量/水位/增益非有限 → 0327，保持末值）
 *      Input defense gate, last held setpoint kept on anomaly
 *-----------------------------------------------------------------------------*)
IF (fDrumLevelPct <> fDrumLevelPct) OR (ABS(fDrumLevelPct) > DL_BLR_INF)
   OR (fSteamFlowTh <> fSteamFlowTh) OR (ABS(fSteamFlowTh) > DL_BLR_INF)
   OR (fFeedFlowTh <> fFeedFlowTh) OR (ABS(fFeedFlowTh) > DL_BLR_INF)
   OR (fLevelSpPct <> fLevelSpPct) OR (ABS(fLevelSpPct) > DL_BLR_INF)
   OR (fFwdGainSteam <> fFwdGainSteam) OR (ABS(fFwdGainSteam) > DL_BLR_INF) THEN
    _bFiniteBad := TRUE;                    // 非有限锁存 / Non-finite latched
END_IF
IF bReset THEN
    _bFiniteBad := FALSE;                   // 复位清非有限锁存 / Reset clears the latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜PID 主回路组合调用（无条件周期刷新，R40：每拍必调）
 *      PID composition called unconditionally every scan per R40
 *-----------------------------------------------------------------------------*)
IF ABS(fFwdGainSteam) > DL_BLR_EPS THEN
    _fPidTrackPct := ((_fFeedSpHeld - fFwdGainSteam * fSteamFlowTh) / DL_BLR_SPAN_TH) * 100.0; // 当前给定反算 PID % 域跟踪值 / Current setpoint back-computed to the PID percent domain
ELSE
    _fPidTrackPct := (_fFeedSpHeld / DL_BLR_SPAN_TH) * 100.0; // 前馈增益为零：按纯主回换算 / Zero gain, pure loop conversion
END_IF
IF _fPidTrackPct < 0.0 THEN
    _fPidTrackPct := 0.0;                   // 跟踪值下限钳 0 / Track value lower clamp
ELSIF _fPidTrackPct > 100.0 THEN
    _fPidTrackPct := 100.0;                 // 跟踪值上限钳 100 / Track value ceiling clamp
END_IF
fbLevelPid(bEnable      := bAutoMode AND (NOT _bFiniteBad),
           bManual      := (NOT bAutoMode) OR _bFiniteBad,
           fManualValue := _fPidTrackPct,
           fSetpoint    := fLevelSpPct,
           fActual      := fDrumLevelPct,
           fKp          := fLevelKp,
           tTi          := tLevelTi,
           tTd          := tLevelTd,
           fDeadband    := 0.0,
           bIncremental := FALSE,
           rOutMin      := 0.0,
           rOutMax      := 100.0,
           bTrack       := _bTrackNow,
           fTrackValue  := _fPidTrackPct,
           bReset       := FALSE);         // 水位主回 PID / Level loop PID
IF _bTrackNow THEN
    _bTrackNow := FALSE;                    // 跟踪只注一拍（无扰投切窗口收敛） / Track injected for one scan only
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜三冲量合成：给定 = PID 主回路换算 + 蒸汽前馈（内联合成）
 *      Three-element synthesis, feedforward inlined
 *-----------------------------------------------------------------------------*)
IF (NOT _bFiniteBad) THEN
    fFeedSpTh := (fbLevelPid.fOut / 100.0) * DL_BLR_SPAN_TH + fFwdGainSteam * fSteamFlowTh; // 三冲量给定 [吨/小时] / Three-element setpoint [t/h]
    IF fFeedSpTh < 0.0 THEN
        fFeedSpTh := 0.0;                   // 给定下限钳 0（不倒转） / Lower clamp, no reverse
    END_IF
    _fFeedSpHeld := fFeedSpTh;              // 末次有效给定保持量推进 / Held setpoint advanced
ELSE
    fFeedSpTh := _fFeedSpHeld;              // 异常路径：保持末次有效给定（0327 口径） / Anomaly, last held setpoint kept
END_IF
bAuto := bAutoMode AND (NOT _bFiniteBad);   // 实际自动态出口 / Actual auto outlet

(*------------------------------------------------------------------------------
 * 段 6｜流量比偏确认窗无条件刷新（R40：CASE 之外每拍必调）
 *      Ratio-deviation window refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
IF (ABS(fSteamFlowTh) > DL_BLR_FLOW_MIN) AND (ABS(fFeedFlowTh) > DL_BLR_FLOW_MIN) THEN
    IF (fFeedFlowTh > fSteamFlowTh * DL_BLR_RATIO_DEV)
       OR (fSteamFlowTh > fFeedFlowTh * DL_BLR_RATIO_DEV) THEN
        _bRatioSuspect := TRUE;             // 双侧直比（禁 ABS 单侧，R19 整数纪律同源） / Two-sided direct comparison
    END_IF
END_IF
fbRatioWin(IN := bAutoMode AND (NOT _bFiniteBad) AND _bRatioSuspect, PT := DL_BLR_RATIO_WIN); // 比偏确认窗 / Ratio-deviation window

(*------------------------------------------------------------------------------
 * 段 7｜码位出口
 *      Code outlet
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_0329;                 // 故障级：兜底 / Fault: fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bFiniteBad THEN
    eErr   := 16#0005_0327;                 // 故障级：非有限输入保持末值 / Fault: non-finite input, held setpoint
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
ELSIF fbRatioWin.Q THEN
    eErr := 16#0005_01EC;                   // 信息级：流量比超偏，泄漏疑似 / Info: ratio deviation, leak suspected
    bValid := TRUE;                         // 输出可用 / Outputs usable
ELSE
    bValid := bAutoMode;                    // 自动态输出可用；手动态给定由调用方使用 / Usable in auto, the manual setpoint is for the caller
END_IF
END_FUNCTION_BLOCK
