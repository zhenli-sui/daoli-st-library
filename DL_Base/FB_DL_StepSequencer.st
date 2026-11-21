(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StepSequencer
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 功能描述 (Function)   : 通用顺控步引擎（顺序功能图的 ST 基类形态）。
 *                         只管理"当前步号、步内计时、步超时、推进、暂停、单步、故障锁存"，
 *                         动作不写死在块内：调用方按当前步号执行动作，并按步号回报完成信号。
 *                         因此本块可作为上百个工站的共用基类，而不是某个工站的专用代码。
 *                         每步可配独立超时，超时锁定故障并记录故障步号，便于现场定位；
 *                         步完成信号为电平语义，换步后第一个周期屏蔽完成判定，
 *                         从结构上杜绝"旧步残留完成位导致连环跳步"的不稳定转换。
 * 开源溯源 (Origin)     : 原创实现。步状态机与步超时监控为顺序功能图最佳实践的公开共识；
 *                         通用步引擎的职责切分（动作外置）为本库差异化设计，未复制任何源码。
 * 本文件内含       : TYPE  E_DL_SeqState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_StepSequencer
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 步号双检 + 超时钳位 + 非法状态兜底
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 五个实例主体最前部无条件刷新（本组件核心考点）
 *                         R8 ✓ 步数与超时上限全常量化
 *
 * 【完成信号电平语义 / Level-semantic step-done signals（决策 D-R2-09，边界 B12）】
 *   调用方在当前步的条件满足时把对应位保持 TRUE，顺控器在推进瞬间屏蔽该位一个周期。
 *   调用方必须在新步开始后撤销旧步的完成位：本块只屏蔽一个周期，
 *   若旧位长期保持 TRUE 且新步恰好也读该索引，仍会被判成立。
 *   Callers must drop the previous step's done bit once the step has advanced.
 *
 * 【暂停语义 / Hold semantics（决策 D-R2-10，边界 B5）】
 *   暂停期间步计时冻结（定时器输入断开，已计时清零），恢复后**重新计时**而不是续算。
 *   "暂停续算"需要差分补偿，会让定时器语义复杂化；代价是本块明确披露"暂停不算超时"。
 *
 * 【单步调试 / Single-step commissioning（边界 B6）】
 *   单步模式下每步完成即进入暂停态，等待推进沿才真正换步，供维护工程师逐段验证。
 *
 * 【断电保持 / Retain（边界 B12）】
 *   是否将实例声明为断电保持由调用方按工艺决定：保持可续跑，不保持则复位到空闲。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 D）
 *   2026-11-14  v1.0.1  修复故障码不锁存缺陷：原实现在每周期开头无条件清零 uErrorId，
 *                       而故障态分支不再重写故障码，导致进入故障后的下一个扫描周期
 *                       bError 仍为 TRUE、uErrorId 却读回 0，现场与 HMI 丢失根因。
 *                       改为故障锁存期间保留进入故障时的故障码，仅复位沿清零。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SeqState（归属 DL_Base，与 FB_DL_StepSequencer 同文件）
 * 含义: 顺控引擎主状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SeqState :
(
    eIdle  := 0,     // 空闲待机：步号无效，等待启动沿 / Idle, no active step, waiting for the start edge
    eRun   := 10,    // 运行中：执行当前步动作并监控完成与超时 / Running, executing the current step
    eHold  := 20,    // 暂停：单步调试等待推进沿 / Held, single-step mode waiting for the advance edge
    eDone  := 30,    // 全部步完成：步号保持末步 / All steps done, the step index holds the last step
    eFault := 99     // 故障锁定：步超时或非法状态，仅复位沿可解除 / Fault latched, only the reset edge clears it
);
END_TYPE

FUNCTION_BLOCK FB_DL_StepSequencer
VAR_INPUT
    bStart        : BOOL;                       // 上升沿：从 0 号步启动 / Rising edge: start from step 0
    abStepDone    : ARRAY[0..15] OF BOOL;       // 步完成信号（电平，调用方按当前步维护）/ Step-done levels, caller-maintained
    auStepTimeout : ARRAY[0..15] OF TIME;       // 每步超时 [ms]，0 = 该步不监控 / Per-step timeout [ms], 0 = not monitored
    bHold         : BOOL := FALSE;              // TRUE = 暂停：冻结推进与超时计时 / TRUE = hold advancing and the timeout
    bSingleStep   : BOOL := FALSE;              // TRUE = 单步调试模式 / Single-step commissioning mode
    bAdvance      : BOOL;                       // 单步模式下上升沿推进一步 / Rising edge: advance one step in single-step mode
    bAbort        : BOOL;                       // 上升沿：中止回空闲，不设故障码 / Rising edge: abort to idle without an error
    bReset        : BOOL;                       // 上升沿：清除故障回空闲 / Rising edge: clear the fault and return to idle
END_VAR
VAR_OUTPUT
    nCurrentStep  : INT;     // 当前步号 0..15，-1 = 未运行 / Current step 0..15, -1 = inactive
    bRunning      : BOOL;    // 运行状态标志 / Running flag
    bDone         : BOOL;    // 全部步完成 / All steps done
    bError        : BOOL;    // 故障标志，bReset 清除 / Fault flag, cleared by bReset
    nFaultStep    : INT;     // 超时故障发生步号，-1 = 无 / Fault step index, -1 = none
    tStepElapsed  : TIME;    // 当前步已运行时间 [ms] / Elapsed time in the current step [ms]
    uErrorId      : UDINT;   // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    eState        : E_DL_SeqState;   // 主状态机 / Main state machine
    fbTonStep     : TON;             // 步计时器 / Step timer
    fbTrigStart   : R_TRIG;          // 启动沿检测实例 / Start edge detector instance
    fbTrigAbort   : R_TRIG;          // 中止沿检测实例 / Abort edge detector instance
    fbTrigReset   : R_TRIG;          // 复位沿检测实例 / Reset edge detector instance
    fbTrigAdvance : R_TRIG;          // 单步推进沿检测实例 / Advance edge detector instance
    nStep         : INT;             // 内部步号 / Internal step index
    tEffTimeout   : TIME;            // 当前步生效超时（已钳位）[ms] / Clamped effective timeout of the current step [ms]
    bTimeoutArmed : BOOL;            // 当前步是否启用超时监控 / Timeout monitoring armed for the current step
    bJustAdvanced : BOOL;            // 换步后首周期屏蔽标志（按下一拍提交）/ First-scan-after-advance mask, committed one scan later
    bMaskNext     : BOOL;            // 下一周期屏蔽请求 / Mask request for the next scan
    bDoAdvance    : BOOL;            // 本周期请求推进 / Advance requested this scan
    bArmStep      : BOOL;            // 本周期请求装载步超时 / Step timeout load requested this scan
    bSkipSm       : BOOL;            // 本周期跳过状态机（复位 / 中止已处理）/ Skip the state machine this scan
    bFirstScan    : BOOL := TRUE;    // 上电首扫初始化标志 / First-scan initialisation flag
END_VAR
VAR CONSTANT
    DL_SEQ_MAX_STEPS : INT  := 16;      // 步数上限 [步]，与数组维度一致 / Step count, must match the arrays
    DL_SEQ_IDX_NONE  : INT  := -1;      // 无效步号哨兵 / Sentinel for no step
    DL_SEQ_TOUT_MAX  : TIME := T#12H;   // 单步超时上限钳位 [ms] / Per-step timeout clamp [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7 / 边界 B1）：四沿 + 一步计时，全部位于主体最前部
 *      Unconditional refresh zone: four edge instances plus the step timer
 *      IN 由"状态 + 暂停 + 超时启用 + 换步屏蔽"先行推导成 BOOL，实例调用本身无条件
 *      IN is derived into a BOOL first, the instance call itself stays unconditional
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK   := bStart);
fbTrigAbort(CLK   := bAbort);
fbTrigReset(CLK   := bReset);
fbTrigAdvance(CLK := bAdvance);

fbTonStep(IN := (eState = eRun) AND (NOT bHold) AND bTimeoutArmed AND (NOT bJustAdvanced),
          PT := tEffTimeout);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫初始化：步号与故障步号必须显式置为无效哨兵，不能依赖默认零
 *      First-scan init: step indices must be set to the sentinel, never left at zero
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    bFirstScan := FALSE;
    eState     := eIdle;
    nStep      := DL_SEQ_IDX_NONE;
    nFaultStep := DL_SEQ_IDX_NONE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜故障码清零口径（v1.0.1 修正）：故障锁存期间必须保留进入故障时的故障码
 *      Error-code policy: while the fault is latched the entry code must survive
 *      故障码是"锁存事实"而非"本周期瞬时量"：若每周期无条件清零，
 *      进入故障后的下一拍就会读回 0，HMI 与现场工程师同时丢失根因
 *      A fault code is a latched fact; an unconditional clear would erase it one scan later
 *-----------------------------------------------------------------------------*)
IF eState <> eFault THEN
    uErrorId := 16#0000_0000;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜复位与中止（边界 B7/B9）：复位仅在故障态有效，中止在非故障态有效
 *      Reset works only in fault, abort works everywhere except fault
 *      两者都清空步号与计时，中止刻意不设故障码——操作员主动中止不是故障
 *      Abort raises no error because a deliberate operator stop is not a fault
 *-----------------------------------------------------------------------------*)
bSkipSm    := FALSE;
bDoAdvance := FALSE;
bArmStep   := FALSE;

IF fbTrigReset.Q AND (eState = eFault) THEN
    eState        := eIdle;
    nStep         := DL_SEQ_IDX_NONE;
    nFaultStep    := DL_SEQ_IDX_NONE;
    tEffTimeout   := T#0S;
    bTimeoutArmed := FALSE;
    uErrorId      := 16#0000_0000;   // 故障码唯一清除路径 / The only path that clears the fault code
    bMaskNext     := TRUE;
    bSkipSm       := TRUE;
END_IF

IF fbTrigAbort.Q AND (eState <> eFault) THEN
    eState        := eIdle;
    nStep         := DL_SEQ_IDX_NONE;
    tEffTimeout   := T#0S;
    bTimeoutArmed := FALSE;
    bMaskNext     := TRUE;
    bSkipSm       := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6 / 边界 B10）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
IF NOT bSkipSm THEN

    CASE eState OF

        eIdle:
            (* 启动沿：从 0 号步开始，并装载该步超时 *)
            (* Start edge: begin at step 0 and load its timeout *)
            IF fbTrigStart.Q THEN
                nStep         := 0;
                bArmStep      := TRUE;
                bMaskNext     := TRUE;
                eState        := eRun;
            END_IF

        eRun:
            (*------------------------------------------------------------------
             * 段 5a｜超时优先（边界 B4）：先判超时再判完成，避免"超时同时完成"时漏报
             *      Timeout first: a timeout wins over a simultaneous completion
             *-----------------------------------------------------------------*)
            IF fbTonStep.Q THEN
                eState     := eFault;
                nFaultStep := nStep;
                uErrorId   := 16#0001_000B;
            ELSIF (NOT bHold) AND (NOT bJustAdvanced) THEN

                (*--------------------------------------------------------------
                 * 段 5b｜完成判定（边界 B2/B11）：只采当前步，且换步首周期不采
                 *      Completion: only the current step, never in the first scan after a switch
                 *-------------------------------------------------------------*)
                IF (nStep >= 0) AND (nStep < DL_SEQ_MAX_STEPS) THEN
                    IF abStepDone[nStep] THEN
                        IF bSingleStep THEN
                            (* 单步模式：完成即暂停，等推进沿再换步 *)
                            (* Single-step: hold after completion until the advance edge *)
                            eState := eHold;
                        ELSE
                            bDoAdvance := TRUE;
                        END_IF
                    END_IF
                END_IF

            END_IF

        eHold:
            (* 单步推进：真正的换步在段 6 统一执行，此处只发请求 *)
            (* Advance request only, the actual switch happens in stage 6 *)
            IF fbTrigAdvance.Q THEN
                bDoAdvance := TRUE;
            END_IF

        eDone:
            (* 全部完成：启动沿可直接重新开始一轮 *)
            (* All done: a start edge begins a new cycle *)
            IF fbTrigStart.Q THEN
                nStep         := 0;
                bArmStep      := TRUE;
                bMaskNext     := TRUE;
                eState        := eRun;
            END_IF

        eFault:
            (* 故障锁存：保持步号便于现场定位，停用超时监控避免二次触发 *)
            (* Fault latched: the step index is kept for diagnosis, the timer is disarmed *)
            bTimeoutArmed := FALSE;

        ELSE
            (* 非法状态拦截：转故障并上报，不做隐式恢复 *)
            (* Illegal state interception: go to fault and report, no implicit recovery *)
            eState     := eFault;
            nFaultStep := nStep;
            uErrorId   := 16#0001_0005;

    END_CASE;

END_IF

(*------------------------------------------------------------------------------
 * 段 6｜推进执行（边界 B8）：末步完成进完成态并保持末步步号，其余步号加一
 *      Advance: the last step completes the sequence, otherwise the index increments
 *      推进只在此处发生一次，避免多处写步号造成跳步
 *      The index changes in exactly one place, which rules out double-stepping
 *-----------------------------------------------------------------------------*)
IF bDoAdvance THEN

    IF nStep >= (DL_SEQ_MAX_STEPS - 1) THEN
        eState := eDone;
    ELSE
        nStep      := nStep + 1;
        bMaskNext  := TRUE;
        bArmStep   := TRUE;
        eState     := eRun;
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 7｜步超时装载（边界 B3/B11）：进入新步时取该步超时并钳位
 *      Step timeout load: read and clamp the timeout when a step is entered
 *      超时为 0 表示该步不监控，挂死风险由调用方自担（手册明示）
 *      A zero timeout disables monitoring for that step, the caller carries the risk
 *-----------------------------------------------------------------------------*)
IF bArmStep THEN
    IF (nStep >= 0) AND (nStep < DL_SEQ_MAX_STEPS) THEN
        IF auStepTimeout[nStep] > DL_SEQ_TOUT_MAX THEN
            tEffTimeout   := DL_SEQ_TOUT_MAX;
            bTimeoutArmed := TRUE;
            uErrorId      := 16#0001_0001;
        ELSIF auStepTimeout[nStep] <= T#0S THEN
            tEffTimeout   := T#0S;
            bTimeoutArmed := FALSE;
        ELSE
            tEffTimeout   := auStepTimeout[nStep];
            bTimeoutArmed := TRUE;
        END_IF
    ELSE
        tEffTimeout   := T#0S;
        bTimeoutArmed := FALSE;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出刷新（边界 B8）：步号与状态标志集中在此一次赋值
 *      Output refresh: the step index and the status flags are written once here
 *-----------------------------------------------------------------------------*)
nCurrentStep := nStep;
bRunning     := (eState = eRun);
bDone        := (eState = eDone);
bError       := (eState = eFault);
tStepElapsed := fbTonStep.ET;

(*------------------------------------------------------------------------------
 * 段 9｜换步屏蔽标志提交（边界 B2）：本周期置的请求在下一周期生效并自动解除
 *      Mask commit: a request raised this scan takes effect next scan and self-clears
 *      这样换步后的第一个完整周期既不推进也不计时，旧步残留完成位无从生效
 *      The first full scan after a switch neither advances nor times, so stale bits die here
 *-----------------------------------------------------------------------------*)
bJustAdvanced := bMaskNext;
bMaskNext     := FALSE;
END_FUNCTION_BLOCK
