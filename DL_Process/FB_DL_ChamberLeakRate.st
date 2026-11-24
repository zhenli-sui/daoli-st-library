(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChamberLeakRate
 * 所属子库 (Sublibrary) : DL_Process
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / R_TRIG / ABS / MAX，零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 腔体压升法检漏公开工艺语义（行业池），道莅
 *                         clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 腔体升压率检漏件（通用压升法）。三态顺控：
 *                         稳压 → 测量 → 判定。压升率 Q = (P2 − P1)·V / tWin，
 *                         测量窗起止压强由调用方外部注入。合格判定带相对
 *                         浮点余量（1E-6 相对量），不做严格小于比较。
 * 职责边界 (Boundary)   : 与库内 EscHeLeakCheck 分工——He 背冷三段法为氦质谱
 *                         专用工艺件，本件为通用压升法单窗判定件，
 *                         二者不合并、不互替。
 * 状态机   (States)     : eIdle 待机 / eStabilize 稳压 / eMeasure 测量窗 /
 *                         eJudge 判定（单拍）/ eFault 故障锁定（CASE 带
 *                         ELSE 兜底）。
 * 码位     (Codes)      : 16#0005_0099 信息级：参数非法早退、反向压差判合格
 *                                      提示（不置 bError）
 *                         16#0005_009A 故障级：测量窗中断（测量中撤启动）
 *                         16#0005_009B 故障级：状态非法（ELSE 兜底，锁存）
 *                         16#0005_009C~009D 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 tWin 不大于零或 V 不大于零参数非法早退（信息级）；
 *                         2 P2 < P1（反向/温降）判合格记信息码（保守侧
 *                           不误杀合格腔体）；
 *                         3 非有限全拦（x<>x 自反判加幅值界）；
 *                         4 除法分母 tWin 换算秒后强制判零；
 *                         5 故障锁存可达解除路径：重新启动沿重新受理；
 *                         6 TON/R_TRIG 实例每拍无条件刷新。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 11）
 *                         2026-11-18 v1.0.1 R31 终审修复：三处信息级码改
 *                         bInfoOne 单拍暂存，消除段 6 ELSE 同拍抹除
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_LeakTestState（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LeakTestState :
(
    eIdle      := 0,    // 待机：未启动或已判定回位 / Idle, not started or judged
    eStabilize := 10,   // 稳压相：压力稳定等待 / Stabilize, pressure settling
    eMeasure   := 20,   // 测量相：升压测量窗计时 / Measure, leak window timing
    eJudge     := 30,   // 判定相：单拍完成判定回待机 / Judge, one-scan verdict then idle
    eFault     := 99    // 故障：测量窗中断或状态非法 / Fault, window interrupted or illegal state
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ChamberLeakRate
 * 调用约定: 每个扫描周期无条件调用一次；测量窗起止压强由调用方在窗口起止
 *           时刻经引脚注入（fP1 为窗起压强，fP2 为窗止压强）。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ChamberLeakRate
VAR_INPUT
    bStart   : BOOL := FALSE;         // 启动沿（含故障态重试受理）/ Start edge, also retries from fault
    fP1      : REAL := 0.0;           // 测量窗起压强 [帕] / Window start pressure [Pa]
    fP2      : REAL := 0.0;           // 测量窗止压强 [帕] / Window end pressure [Pa]
    fV       : REAL := 1.0;           // 腔体容积 [立方米] / Chamber volume [m3]
    tWin     : TIME := T#60S;         // 测量窗时长 [毫秒] / Measurement window duration [ms]
    tStab    : TIME := T#10S;         // 稳压相时长 [毫秒]（可增引脚）/ Stabilize duration [ms], added pin
    fLeakLim : REAL := 5.0;           // 泄漏率限值 [帕立方米每秒] / Leak rate limit [Pa m3 per s]
END_VAR
VAR_OUTPUT
    fLeakRate : REAL;                 // 压升率（泄漏率）[帕立方米每秒] / Pressure rise rate [Pa m3 per s]
    bPass     : BOOL;                 // 合格标志 / Pass verdict flag
    eState    : E_DL_LeakTestState;   // 顺控当前状态 / Current sequence state
    bError    : BOOL;                 // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId  : UDINT;                // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    rTrigStart : R_TRIG;              // 启动沿检测，每拍无条件刷新 / Start edge detector, refreshed every scan
    tonPhase   : TON;                 // 相计时定时器，每拍无条件刷新 / Phase timer, refreshed every scan
    bStepRst   : BOOL;                // 相切换拍单拍断计时输入 / One-scan timer break on phase change
    tPhaseEff  : TIME;                // 本相生效计时目标 [毫秒] / Effective phase timing target [ms]
    eStatePrev : E_DL_LeakTestState;  // 上一拍状态快照 / Previous state snapshot
    bInOk      : BOOL;                // 测量输入有效性 / Measurement input validity
    bParaOk    : BOOL;                // 参数有效性 / Parameter validity
    fWinSec    : REAL;                // 测量窗秒值 [秒] / Window seconds [s]
    fRise      : REAL;                // 窗内压升 [帕] / Pressure rise over window [Pa]
    fSlack     : REAL;                // 判定浮点余量 [帕立方米每秒] / Verdict float slack [Pa m3 per s]
    uCodeLatch : UDINT;               // 故障级锁存码 / Latched fault code
    bInfoBack  : BOOL;                // 反向压差信息标志 / Reverse pressure info flag
    bInfoOne   : BOOL;                // 信息级单拍待发标志（防同拍抹除，R28 终审）/ One-scan info pending flag
    bInit      : BOOL := TRUE;        // 首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_CLR_FIN  : REAL := 1.0E30;     // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_CLR_REL  : REAL := 1.0E-6;     // 判定相对浮点余量系数 / Verdict relative slack factor
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigStart(CLK := bStart);                            // 启动沿检测 / Start edge detection
tPhaseEff := tStab;                                   // 默认稳压时长 / Default stabilize duration
IF eState = eMeasure THEN
    tPhaseEff := tWin;                                // 测量相改用窗时长 / Measure phase uses window duration
END_IF
tonPhase(IN := ((eState = eStabilize) OR (eState = eMeasure)) AND (NOT bStepRst),
         PT := tPhaseEff);                            // 相计时按相取目标 / Phase timing with per-phase target

// ---- 段 2｜相切换检测（供计时器按相断输入）--------------------------------------
bStepRst := (eState <> eStatePrev) OR bInit;          // 相变化即断输入 / Phase change breaks timing input
eStatePrev := eState;                                 // 快照留痕 / Snapshot previous state
bInit := FALSE;                                       // 清首扫标志 / Clear first-scan flag

// ---- 段 3｜输入与参数有效性预判（测量相判定前复验，R42 相转换复验语义）----------
bInOk   := (fP1 = fP1) AND (fP2 = fP2) AND (ABS(fP1) < DL_CLR_FIN) AND (ABS(fP2) < DL_CLR_FIN); // 压强对有限 / Pressure pair finite
fWinSec := TIME_TO_REAL(tWin) / 1000.0;               // 窗时换算秒 [秒] / Window converted to seconds
bParaOk := (fWinSec > 0.0) AND (fV > 0.0) AND (fV = fV) AND (fV < DL_CLR_FIN); // 窗时/容积合法 / Window and volume legal

// ---- 段 4｜状态机（CASE 带 ELSE 兜底锁故障）--------------------------------------
CASE eState OF
    eIdle:
        bPass := FALSE;                               // 待机清合格标志 / Idle clears verdict
        IF rTrigStart.Q AND bParaOk THEN
            eState := eStabilize;                     // 参数合法沿进稳压 / Legal parameters, to stabilize
        ELSIF rTrigStart.Q AND (NOT bParaOk) THEN
            bInfoOne := TRUE;                         // 信息级：参数非法早退（暂存防同拍抹除）/ Info: illegal parameters, staged
        END_IF
    eStabilize:
        IF rTrigStart.Q AND (NOT bParaOk) THEN
            eState := eIdle;                          // 参数中途失配退回 / Parameters lost mid-run
            bInfoOne := TRUE;                         // 信息级：参数非法早退（暂存）/ Info: illegal parameters, staged
        ELSIF tonPhase.Q THEN
            eState := eMeasure;                       // 稳压满进测量窗 / Stabilize elapsed, to measure
            bStepRst := TRUE;                         // 单拍重载计时器入参 / One-scan timer input reload
        END_IF
    eMeasure:
        IF NOT bStart THEN
            eState := eFault;                         // 测量中撤启动即窗中断 / Start drop mid-window is interruption
            uCodeLatch := 16#0005_009A;               // 码位：测量窗中断 / Code: window interrupted
        ELSIF tonPhase.Q THEN
            eState := eJudge;                         // 窗满进判定 / Window elapsed, to judge
        END_IF
    eJudge:
        bInOk := (fP1 = fP1) AND (fP2 = fP2) AND (ABS(fP1) < DL_CLR_FIN) AND (ABS(fP2) < DL_CLR_FIN); // 判定拍复验（R42）/ Recheck at verdict scan
        bInfoBack := FALSE;                           // 反向信息先清 / Clear reverse info
        IF bInOk AND bParaOk THEN
            fRise := fP2 - fP1;                       // 窗内压升 [帕] / Pressure rise [Pa]
            fLeakRate := fRise * fV / fWinSec;        // 压升率，分母已验正 / Rise rate, denominator verified
            IF fRise < 0.0 THEN
                bInfoBack := TRUE;                     // 反向压差（温降）信息 / Reverse rise (cooling) info
                bPass := TRUE;                         // 保守侧判合格不误杀 / Conservative pass verdict
            ELSE
                fSlack := DL_CLR_REL * MAX(ABS(fLeakLim), 1.0); // 相对余量 / Relative slack
                bPass := fLeakRate <= (fLeakLim + fSlack); // 带余量判定不做严格小于 / Slack verdict, no strict less
            END_IF
        ELSE
            fLeakRate := 0.0;                         // 异常路径确定值 / Deterministic fallback
            bPass := FALSE;                           // 异常判不合格 / Fail on invalid data
            bInfoOne := TRUE;                         // 信息级：判定拍数据非法（暂存）/ Info: illegal data at verdict, staged
        END_IF
        eState := eIdle;                              // 判定毕回待机 / Verdict done, back to idle
    eFault:
        bPass := FALSE;                               // 故障态清合格 / Fault clears verdict
        fLeakRate := 0.0;                             // 故障态清输出 / Fault clears output
        IF rTrigStart.Q AND bParaOk THEN
            eState := eStabilize;                     // 可达解除路径：重启沿重试 / Reachable release: restart edge
            uCodeLatch := 16#0000_0000;               // 清锁存码 / Clear latched code
        END_IF
    ELSE
        eState := eFault;                             // 非法状态兜底 / Illegal state fallback
        uCodeLatch := 16#0005_009B;                   // 码位：状态非法 / Code: illegal state
END_CASE

// ---- 段 5｜错误码装配：故障锁存回放优先，信息级居次 ------------------------------
IF eState = eFault THEN
    bError   := TRUE;                                 // 故障标志配对（R45）/ Fault flag paired
    uErrorId := uCodeLatch;                           // 故障码锁存回放 / Latched fault code replayed
ELSIF bInfoBack THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0005_0099;                         // 信息级：反向压差判合格 / Info: reverse rise passed
ELSIF bInfoOne THEN
    bError   := FALSE;                                // 信息级不置故障 / Info never sets fault
    uErrorId := 16#0005_0099;                         // 信息级：参数/数据非法单拍回放 / Info: illegal param or data, one-scan
    bInfoOne := FALSE;                                // 发完即清 / Clear after emit
ELSE
    bError   := FALSE;                                // 无错清标志 / Clear fault flag
    uErrorId := 16#0000_0000;                         // 无码 / No code
END_IF
END_FUNCTION_BLOCK
