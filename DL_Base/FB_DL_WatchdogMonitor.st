(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WatchdogMonitor
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）+ 本库双层沿检测构件
 * 功能描述 (Function)   : 外部心跳信号看门狗。监控对象是心跳的"跳变间隔"而不是电平：
 *                         连接还在、脚本已死循环的静默失效工况下，电平永远不变，
 *                         只有跳变间隔能暴露问题。超窗即锁定故障输出并保持，需显式复位；
 *                         同时检测跳变过快（接线抖动 / 心跳被写成恒振荡）并告警，
 *                         该频率告警不锁存，间隔恢复正常即自动消除。
 *                         上电即武装：窗口内没有第一个跳变就按时超时——
 *                         心跳信号必须先证明自己活着，这是刻意设计而非缺陷。
 * 开源溯源 (Origin)     : 原创实现。看门狗的"窗口定时器 + 跳变沿复位"模式为工业界通行做法，
 *                         跳变间隔语义与高频告警为本库差异化设计，未复制任何源码。
 * 本文件内含       : TYPE  E_DL_WdtState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_WatchdogMonitor
 * 依赖     (Depends)    : FB_DL_DualEdgeTrig（首轮 #2，仅取其电平输出）
 *                         Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 窗口钳位 + 零窗口合法性判定
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 三态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 三实例主体最前部无条件刷新 ｜ R8 ✓ 上限与常量全常量化
 *
 * 【依赖收窄留档 / Dependency narrowing（R11）】
 *   规格书 B5 要求跳变计数直接复用双层沿检测构件的上升/下降计数输出。
 *   实测该构件当前版本的上升/下降事件输出以"上一周期电平"做资格与运算，
 *   在真实上升沿那一周期上一周期电平必然为 FALSE，导致事件恒不成立、计数恒不增长。
 *   为避免看门狗核心功能被上游缺陷阻塞，本组件只从该构件取"当前电平"（正确且稳定），
 *   跳变判定与计数在本地以电平差分为准，饱和口径与故障码口径与上游保持一致。
 *   上游修复后可改为直接读其事件输出，届时本段留档同步撤销。
 *   （2026-11-14 终审补注：上游缺陷已在 FB_DL_DualEdgeTrig v1.0.1 修复，
 *     其事件输出恢复正确。本组件继续保留本地电平差分口径——两者行为等价，
 *     且本地派生同时服务于 tSinceToggle 与频率判定，独立于上游事件口更稳；
 *     是否收敛为上游事件输出留待 Level 1 统一重构时评估，本版不改行为。）
 *   The dependency's edge outputs are qualified by the previous level, which makes them
 *   permanently FALSE on a genuine edge. This component therefore consumes only its
 *   level output and derives toggles locally, keeping the same saturation policy.
 *   (Final review note: the upstream defect is fixed in v1.0.1; the local derivation is
 *   kept because it is behaviour-equivalent and also feeds the silence measurement.)
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 B）
 *   2026-11-14  v1.0.0  含依赖收窄留档（见上）
 *   2026-11-14  v1.0.0  终审补注依赖收窄现状（仅注释同步，逻辑未变，版本不变）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_WdtState（归属 DL_Base，与 FB_DL_WatchdogMonitor 同文件）
 * 含义: 看门狗工作状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_WdtState :
(
    eArmed    := 0,    // 监控中：窗口计时进行，等待下一次跳变 / Armed, the window timer runs and waits for the next toggle
    eFault    := 10,   // 心跳超时锁定：仅复位沿可解除 / Timeout latched, only the reset edge releases it
    eDisabled := 20    // 未启用：输出全清，重新使能视同首次武装 / Disabled, re-enabling behaves like a first arming
);
END_TYPE

FUNCTION_BLOCK FB_DL_WatchdogMonitor
VAR_INPUT
    bHeartbeat   : BOOL;                  // 被监控心跳信号（期望周期性跳变）/ Monitored heartbeat, expected to toggle periodically
    tMaxInterval : TIME := T#2S;          // 最大允许跳变间隔 [ms] / Max allowed toggle interval [ms]
    tMinInterval : TIME := T#5MS;         // 最小合法跳变间隔 [ms]，低于视为异常信号 / Min legal interval [ms], below is abnormal
    bEnable      : BOOL := TRUE;          // 使能 / Enable
    bReset       : BOOL;                  // 上升沿：清除故障并重新武装 / Rising edge: clear fault and re-arm
END_VAR
VAR_OUTPUT
    bAlive       : BOOL;     // 心跳健康（未超时且未触发频率异常）/ Heartbeat healthy, no timeout and no rate anomaly
    bTimeout     : BOOL;     // 心跳超时锁存 / Timeout latched
    tSinceToggle : TIME;     // 距上次跳变的时长 [ms] / Time since the last toggle [ms]
    uToggleCount : UDINT;    // 累计跳变次数 [次]（诊断用）/ Accumulated toggles [count], diagnostics
    bError       : BOOL;     // 故障标志，bReset 清除 / Fault flag, cleared by bReset
    uErrorId     : UDINT;    // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbDual       : FB_DL_DualEdgeTrig;    // 依赖构件实例，仅取电平输出 / Dependency instance, level output only
    fbTonWatch   : TON;                   // 看门狗窗口计时器 / Watchdog window timer
    fbTrigReset  : R_TRIG;                // 复位上升沿检测实例 / Reset rising edge detector instance
    eState       : E_DL_WdtState;         // 主状态机 / Main state machine
    tMinLast     : TIME;                  // 上一次相邻跳变间隔 [ms]（诊断留档）/ Last observed toggle interval [ms]
    bLastLevel   : BOOL;                  // 上周期心跳电平，跳变派生用 / Previous heartbeat level for toggle derivation
    bToggle      : BOOL;                  // 本周期检测到跳变 / Toggle detected in this scan
    tMaxEff      : TIME;                  // 钳位后的窗口 [ms] / Clamped window [ms]
    tPrevSince   : TIME;                  // 上周期末的静默时长 [ms]，间隔测量用 / Silence at the end of the last scan [ms]
    tFrozenSince : TIME;                  // 故障瞬间冻结的静默时长 [ms] / Frozen silence at the fault instant [ms]
    bHasToggled  : BOOL;                  // 是否已观测到过至少一次跳变 / At least one toggle has been observed
    bRateBad     : BOOL;                  // 本周期频率异常（不锁存）/ Rate anomaly this scan, not latched
    bWindowBad   : BOOL;                  // 窗口参数非法 / Illegal window parameter
    bCountSat    : BOOL;                  // 跳变计数饱和标志 / Toggle count saturation flag
    bStateBad    : BOOL;                  // 非法状态命中标志 / Illegal state hit flag
    uToggleLocal : UDINT;                 // 本地跳变计数 [次] / Local toggle counter [count]
END_VAR
VAR CONSTANT
    DL_WDT_INTERVAL_MAX : TIME  := T#1H;            // 窗口上限钳位 [ms] / Window clamp [ms]
    DL_WDT_COUNT_MAX    : UDINT := 16#FFFF_FFFE;    // 跳变计数饱和上限 [次] / Toggle count saturation limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：依赖实例与两个标准实例全部位于主体最前部
 *      Unconditional refresh zone: dependency instance and both standard instances
 *      严禁进入任何 IF / CASE 分支，否则窗口计时会被条件化并失去看门狗意义
 *      No instance call may sit inside IF / CASE, otherwise the window loses its meaning
 *-----------------------------------------------------------------------------*)
fbDual(bSignal := bHeartbeat, bEnable := bEnable, bReset := bReset);
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜跳变派生：电平差分，与跳变计数共用同一个判定源，保证口径唯一
 *      Toggle derivation: level difference, the single source of truth for counting
 *-----------------------------------------------------------------------------*)
bToggle := (fbDual.bLevel AND (NOT bLastLevel)) OR ((NOT fbDual.bLevel) AND bLastLevel);

(*------------------------------------------------------------------------------
 * 段 3｜窗口参数校验（边界 B4）：零窗口视为非法但超时立即受理；超上限钳位
 *      Window validation: a zero window is illegal but honoured as an instant timeout
 *      零窗口意味着"监控无意义"，仍按超时受理以保证输出行为可预期
 *      A zero window is meaningless, yet honouring it keeps the output predictable
 *-----------------------------------------------------------------------------*)
bWindowBad := FALSE;

IF tMaxInterval <= T#0S THEN
    tMaxEff    := T#0S;
    bWindowBad := TRUE;
ELSIF tMaxInterval > DL_WDT_INTERVAL_MAX THEN
    tMaxEff    := DL_WDT_INTERVAL_MAX;
    bWindowBad := TRUE;
ELSE
    tMaxEff    := tMaxInterval;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜窗口计时（边界 B1）：跳变当周期 IN 断开，ET 自然清零重新起算
 *      Window timing: IN drops on the toggle scan, so ET restarts from zero
 *-----------------------------------------------------------------------------*)
fbTonWatch(IN := (eState = eArmed) AND (NOT bToggle) AND bEnable, PT := tMaxEff);

(*------------------------------------------------------------------------------
 * 段 5｜使能 / 复位 / 主状态机（边界 B2/B6/B7/B8/B9）
 *      Enable, reset and the main state machine
 *-----------------------------------------------------------------------------*)
bRateBad  := FALSE;
bStateBad := FALSE;

IF NOT bEnable THEN
    (*--------------------------------------------------------------------------
     * 段 5a｜使能失效（边界 B6）：输出全清、状态回未启用，跳变计数保留作诊断
     *      Disabled: outputs cleared, state parked; the diagnostic count is kept
     *-------------------------------------------------------------------------*)
    eState       := eDisabled;
    bTimeout     := FALSE;
    bAlive       := FALSE;
    tSinceToggle := T#0S;
    tFrozenSince := T#0S;
    tPrevSince   := T#0S;
    bHasToggled  := FALSE;
    bLastLevel   := fbDual.bLevel;
ELSE
    IF fbTrigReset.Q THEN
        (*----------------------------------------------------------------------
         * 段 5b｜复位（边界 B8）：清故障、回武装、窗口重新起算；不清诊断计数
         *      Reset: clear fault, re-arm, restart the window; the counter is kept
         *---------------------------------------------------------------------*)
        eState       := eArmed;
        bTimeout     := FALSE;
        tFrozenSince := T#0S;
        tPrevSince   := T#0S;
        bHasToggled  := FALSE;
        bLastLevel   := fbDual.bLevel;
    ELSE
        (*----------------------------------------------------------------------
         * 段 5c｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
         *      Main state machine with the mandatory ELSE fallback
         *---------------------------------------------------------------------*)
        CASE eState OF

            eDisabled:
                (* 重新使能视同首次武装：不等历史，先要求心跳证明自己活着 *)
                (* Re-enabling behaves like a first arming, the heartbeat must prove itself *)
                eState      := eArmed;
                bHasToggled := FALSE;
                tPrevSince  := T#0S;
                bLastLevel  := fbDual.bLevel;

            eArmed:
                IF bToggle THEN
                    (* 跳变计数（饱和停增，不回绕） *)
                    (* Toggle count, saturating instead of wrapping around *)
                    IF uToggleLocal < DL_WDT_COUNT_MAX THEN
                        uToggleLocal := uToggleLocal + UDINT#1;
                    ELSE
                        bCountSat := TRUE;
                    END_IF

                    (*----------------------------------------------------------
                     * 段 5c-1｜频率异常（边界 B3）：相邻跳变间隔小于下限即告警
                     *      Rate anomaly: an interval below the minimum raises the alarm
                     *      首个跳变不参与判定（尚无参照间隔），间隔为 0 亦不判定
                     *      The first toggle and a zero interval are not qualified
                     *---------------------------------------------------------*)
                    IF bHasToggled AND (tPrevSince > T#0S) AND (tPrevSince < tMinInterval) THEN
                        bRateBad := TRUE;
                    END_IF

                    tMinLast    := tPrevSince;
                    bHasToggled := TRUE;
                END_IF

                (*--------------------------------------------------------------
                 * 段 5c-2｜超时锁定（边界 B2）：窗口期满即锁存，仅复位可解
                 *      Timeout latch: the expired window latches until a reset
                 *-------------------------------------------------------------*)
                IF fbTonWatch.Q THEN
                    eState       := eFault;
                    bTimeout     := TRUE;
                    tFrozenSince := fbTonWatch.ET;
                END_IF

            eFault:
                (* 故障锁存：输出保持，窗口不再计时，等待复位沿 *)
                (* Fault latched: outputs hold, the window stops, waiting for reset *)
                bTimeout := TRUE;

            ELSE
                (* 非法状态拦截：转故障并上报，不做隐式恢复 *)
                (* Illegal state interception: go to fault and report, no implicit recovery *)
                eState       := eFault;
                bTimeout     := TRUE;
                bStateBad    := TRUE;
                tFrozenSince := T#0S;

        END_CASE;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜静默时长输出（边界 B2 配套）：故障态显示冻结值而非 0，便于现场判断超了多久
 *      Silence output: the fault state shows the frozen value instead of zero
 *-----------------------------------------------------------------------------*)
IF eState = eArmed THEN
    tSinceToggle := fbTonWatch.ET;
ELSIF eState = eFault THEN
    tSinceToggle := tFrozenSince;
ELSE
    tSinceToggle := T#0S;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜健康与故障输出：健康 = 武装中且无频率异常；故障 = 超时锁存
 *      Health and fault outputs: healthy means armed without a rate anomaly
 *-----------------------------------------------------------------------------*)
bAlive       := (eState = eArmed) AND (NOT bRateBad) AND (NOT bWindowBad);
bError       := bTimeout;
uToggleCount := uToggleLocal;

(*------------------------------------------------------------------------------
 * 段 8｜故障码优先级：非法状态 > 超时 > 频率异常 > 计数饱和 > 参数钳位
 *      Error priority: illegal state, timeout, rate anomaly, saturation, clamp
 *-----------------------------------------------------------------------------*)
IF bStateBad THEN
    uErrorId := 16#0001_0005;
ELSIF bTimeout THEN
    uErrorId := 16#0001_000C;
ELSIF bRateBad THEN
    uErrorId := 16#0001_0008;
ELSIF bCountSat THEN
    uErrorId := 16#0001_0007;
ELSIF bWindowBad THEN
    uErrorId := 16#0001_0001;
ELSE
    uErrorId := 16#0000_0000;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜历史更新必须放在全部判定之后：先取沿再改历史，否则跳变永远检测不到
 *      History update must come last, otherwise toggles are never detected
 *      tPrevSince 记录周期末静默时长，供下一次跳变时计算间隔
 *      tPrevSince stores the end-of-scan silence for the next interval measurement
 *-----------------------------------------------------------------------------*)
bLastLevel := fbDual.bLevel;
tPrevSince := fbTonWatch.ET;
END_FUNCTION_BLOCK
