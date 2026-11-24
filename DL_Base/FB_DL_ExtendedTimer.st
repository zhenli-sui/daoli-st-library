(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ExtendedTimer
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / F_TRIG），零厂商方言
 * 功能描述 (Function)   : 四模式工业定时器，一个实例覆盖通电延时 / 断电延时 / 单脉冲 /
 *                         保持型累加四种现场时序需求，消除"同一延时逻辑在项目里
 *                         散落四种实现、改造时漏改某处"的维护风险。
 *                         保持型累加模式补足标准库空白：输入断开时进度保留，
 *                         只有显式复位才清零，累加采用相位定时器差值累加而非直读已计时值。
 *                         运行中切换模式立即作废当前计时（操作语义，不产生故障码）。
 * 开源溯源 (Origin)     : 原创实现。四模式语义依据 IEC 61131-3 标准 TON/TOF/TP 定义，
 *                         保持型累加模式参照 AB / Omron 生态的 RTO 行为定义；
 *                         全部代码为本库独立重构，未复制任何厂商或开源库源码。
 * 本文件内含       : TYPE  E_DL_TimerMode（配套枚举，归属 DL_Base）
 *                    TYPE  E_DL_ExtTimerState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_ExtendedTimer
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG / F_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 预设钳位 + 剩余时间负值钳位 + 差分累加防倒退
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 三实例主体最前部无条件刷新（本组件核心考点）
 *                         R8 ✓ 预设上限、零值判据全常量化
 *
 * 【四模式输出语义表 / Four-mode output semantics（边界 B2，手册原样收录）】
 *   通电延时：输入 TRUE 满 PT 后输出 TRUE；输入 FALSE 立即输出 FALSE 且已计时清零。
 *   断电延时：输入 TRUE 期间输出 TRUE；输入变 FALSE 后输出保持 TRUE 并计时，
 *             满 PT 才复位为 FALSE；输入提前恢复 TRUE 则计时作废。
 *   单脉冲  ：输入上升沿触发，输出 TRUE 持续 PT 时长；期间输入变 FALSE 不中断；
 *             新上升沿重触发并从零重新计时。
 *   保持型  ：输入 TRUE 时累加计时，输入 FALSE 时进度保留不清零；
 *             累计达 PT 后输出 TRUE 且不再受输入影响，仅复位可清零。
 *
 * 【模式切换即计时作废 / Mode switch voids the timing（边界 B4）】
 *   运行中改写模式会立即中止当前计时、清零累加并回到待机态，
 *   这是操作语义而不是故障，因此不产生任何故障码（手册须写明）。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 B）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TimerMode（归属 DL_Base，与 FB_DL_ExtendedTimer 同文件）
 * 含义: 定时器工作模式。数值与现场惯用编号一致，便于 HMI 配方直接映射。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TimerMode :
(
    eTon := 0,    // 通电延时：输入保持 TRUE 满 PT 后输出 TRUE / On-delay, output TRUE after PT of TRUE input
    eTof := 1,    // 断电延时：输入变 FALSE 后延时 PT 再复位输出 / Off-delay, output drops PT after the input falls
    eTp  := 2,    // 单脉冲：上升沿触发 PT 时长脉冲，可重触发 / Pulse, retriggerable on each rising edge
    eRto := 3     // 保持型累加：输入 TRUE 累加，断开保持进度，仅复位清零 / Retentive on-delay, reset only
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ExtTimerState（归属 DL_Base，与 FB_DL_ExtendedTimer 同文件）
 * 含义: 定时器主状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ExtTimerState :
(
    eIdle   := 0,     // 待机：输出为当前模式的待机值 / Idle, output at the mode rest value
    eTiming := 10,    // 计时进行中 / Timing in progress
    eDone   := 20,    // 完成：输出保持 / Done, output held
    eFault  := 99     // 故障锁定：需复位清除 / Fault latched, cleared by reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_ExtendedTimer
VAR_INPUT
    bIn      : BOOL;                        // 输入信号（电平语义）/ Input signal, level semantics
    eMode    : E_DL_TimerMode := eTon;      // 工作模式 / Operating mode
    tPreset  : TIME := T#10S;               // 预设时间 [ms]，合法域 0 至上限 / Preset time [ms], valid range up to the clamp
    bReset   : BOOL;                        // 上升沿：清零累加与故障 / Rising edge: clear the accumulation and the fault
END_VAR
VAR_OUTPUT
    bQ         : BOOL;    // 输出，语义随模式（见头注释语义表）/ Output, semantics per mode, see the header table
    bTiming    : BOOL;    // 计时进行中标志 / Timing in progress flag
    tElapsed   : TIME;    // 当前模式已计时 [ms]，保持型为累计值 / Elapsed time [ms], accumulated in retentive mode
    tRemaining : TIME;    // 距完成剩余 [ms]，完成或待机为 0 / Remaining time [ms], zero when done or idle
    uErrorId   : UDINT;   // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbTrigRise  : R_TRIG;                 // 输入上升沿检测实例 / Input rising edge detector instance
    fbTrigFall  : F_TRIG;                 // 输入下降沿检测实例 / Input falling edge detector instance
    fbTrigReset : R_TRIG;                 // 复位上升沿检测实例 / Reset rising edge detector instance
    fbTonPhase  : TON;                    // 相位计时器，四模式共用 / Phase timer shared by all four modes
    eState      : E_DL_ExtTimerState;     // 主状态机 / Main state machine
    tAccum      : TIME;                   // 保持型累计时间 [ms] / Retentive accumulated time [ms]
    eLastMode   : E_DL_TimerMode;         // 上周期模式，用于变更检测 / Previous mode for change detection
    tPresetEff  : TIME;                   // 钳位后的预设时间 [ms] / Clamped preset time [ms]
    tTonPt      : TIME;                   // 相位定时器当前预设 [ms] / Current preset of the phase timer [ms]
    tEtPrev     : TIME;                   // 上周期相位定时器已计时 [ms]，差分累加用 / Previous ET for delta accumulation [ms]
    tDelta      : TIME;                   // 本周期已计时增量 [ms] / ET increment of this scan [ms]
    bTonIn      : BOOL;                   // 相位定时器输入（先推导后喂入）/ Phase timer input, derived first then fed
    bModeBad    : BOOL;                   // 模式枚举越界标志 / Mode enum out-of-domain flag
    bPresetBad  : BOOL;                   // 预设时间越界标志 / Preset out-of-range flag
    bPresetZero : BOOL;                   // 预设为零标志（立即完成）/ Zero preset flag, complete immediately
    bRtoDone    : BOOL;                   // 保持型累加已达标（锁存）/ Retentive accumulation reached the preset, latched
    bTofArmed   : BOOL;                   // 断电延时的延时阶段已建立 / Off-delay hold phase armed
    bTpRun      : BOOL;                   // 单脉冲进行中 / Single pulse running
    bHoldOn     : BOOL;                   // 本周期强制定时器停计（复位/换模式/故障）/ Force the timer off this scan
END_VAR
VAR CONSTANT
    DL_TIMER_PRESET_MAX : TIME := T#12H;  // 预设时间上限钳位 [h] / Preset clamp [h]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7 / 边界 B1）：三个实例严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone: no instance call inside IF / CASE
 *      IN 与 PT 均由"状态 + 输入"先行推导成普通量，实例调用本身保持无条件
 *      IN and PT are derived into plain values first, the calls stay unconditional
 *-----------------------------------------------------------------------------*)
fbTrigRise(CLK  := bIn);
fbTrigFall(CLK  := bIn);
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜预设钳位（边界 B3）：超上限钳到上限并告警，但计时继续不中断
 *      Preset clamping: clamp and warn, but keep timing without interruption
 *-----------------------------------------------------------------------------*)
bPresetBad := FALSE;

IF tPreset > DL_TIMER_PRESET_MAX THEN
    tPresetEff := DL_TIMER_PRESET_MAX;
    bPresetBad := TRUE;
ELSIF tPreset < T#0S THEN
    tPresetEff := T#0S;
    bPresetBad := TRUE;
ELSE
    tPresetEff := tPreset;
END_IF

bPresetZero := (tPresetEff <= T#0S);

(*------------------------------------------------------------------------------
 * 段 3｜模式合法性（边界 B7）：枚举被强制写入域外值时直接进故障态
 *      Mode validity: an out-of-domain enum drives the state machine to fault
 *-----------------------------------------------------------------------------*)
bModeBad := NOT ((eMode = eTon) OR (eMode = eTof) OR (eMode = eTp) OR (eMode = eRto));

(*------------------------------------------------------------------------------
 * 段 4｜运行中模式切换（边界 B4）：立即中止计时、清零累加，不产生故障码
 *      Mode switch while running: abort the timing and clear the accumulation, no error
 *      本周期强制定时器停计，让相位定时器在下一周期从零重新起算
 *      The timer is forced off this scan so it restarts from zero next scan
 *-----------------------------------------------------------------------------*)
bHoldOn := FALSE;

IF eMode <> eLastMode THEN
    eLastMode := eMode;
    eState    := eIdle;
    tAccum    := T#0S;
    tEtPrev   := T#0S;
    bRtoDone  := FALSE;
    bTofArmed := FALSE;
    bTpRun    := FALSE;
    bHoldOn   := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜相位定时器输入推导（边界 B2）：先算成 BOOL，再喂给实例
 *      Phase timer input derivation: compute the BOOL first, then feed the instance
 *      四种模式对"何时计时"的要求完全不同，统一收敛到一个推导段便于审阅
 *      All four modes converge here so the timing condition is reviewed in one place
 *-----------------------------------------------------------------------------*)
bTonIn := FALSE;
tTonPt := tPresetEff;

IF bModeBad THEN
    bTonIn := FALSE;
ELSIF eMode = eTon THEN
    (* 通电延时：输入为 TRUE 即计时 *)
    (* On-delay: time while the input is TRUE *)
    bTonIn := bIn;
ELSIF eMode = eTof THEN
    (* 断电延时：输入为 FALSE 即计时（输入 TRUE 时 ET 被清零） *)
    (* Off-delay: time while the input is FALSE, a TRUE input clears ET *)
    bTonIn := NOT bIn;
ELSIF eMode = eTp THEN
    (* 单脉冲：上升沿当周期强制停计一拍，使 ET 清零后重新计时（可重触发） *)
    (* Pulse: the rising scan forces one off-scan so ET restarts from zero *)
    bTonIn := bTpRun AND (NOT fbTrigRise.Q);
ELSE
    (* 保持型：输入 TRUE 且未达标时计时 *)
    (* Retentive: time while the input is TRUE and the preset is not yet reached *)
    bTonIn := bIn AND (NOT bRtoDone);
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜相位定时器无条件刷新（红线 R7）：全组件唯一一次调用
 *      Single unconditional call of the phase timer
 *      复位 / 换模式 / 故障 / 禁用当周期统一断开 IN，ET 由标准语义自动清零
 *      Reset, mode switch and fault all drop IN so the standard semantics clear ET
 *-----------------------------------------------------------------------------*)
fbTonPhase(IN := bTonIn AND (NOT bHoldOn) AND (NOT fbTrigReset.Q) AND (NOT bModeBad) AND (eState <> eFault),
           PT := tTonPt);

(*------------------------------------------------------------------------------
 * 段 7｜保持型差分累加（边界 B5）：把 ET 的增量并入累计，禁止直读 ET 当累计值
 *      Retentive delta accumulation: fold the ET increment into the accumulator
 *      ET 在输入断开时会被标准定时器清零，若直读 ET 当累计值，进度当场丢失
 *      ET is cleared when the input drops, reading it directly would lose the progress
 *      增量为负说明定时器刚被清零，忽略即可，累计值因此只增不减
 *      A negative delta means the timer just reset, ignoring it keeps the total monotonic
 *-----------------------------------------------------------------------------*)
IF (eMode = eRto) AND (NOT bModeBad) AND (NOT bRtoDone) THEN
    tDelta := fbTonPhase.ET - tEtPrev;
    IF tDelta > T#0S THEN
        tAccum := tAccum + tDelta;
        IF tAccum >= tPresetEff THEN
            tAccum   := tPresetEff;
            bRtoDone := TRUE;
        END_IF
    END_IF
END_IF

tEtPrev := fbTonPhase.ET;

(*------------------------------------------------------------------------------
 * 段 8｜复位语义（边界 B6）：保持型唯一清零路径，同时清故障与全部模式标志
 *      Reset: the only clearing path of the retentive accumulator
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    eState    := eIdle;
    tAccum    := T#0S;
    tEtPrev   := T#0S;
    bRtoDone  := FALSE;
    bTofArmed := FALSE;
    bTpRun    := FALSE;
    bPresetBad := FALSE;
    uErrorId  := 16#0000_0000;
ELSE

    (*--------------------------------------------------------------------------
     * 段 9｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
     *      Main state machine with the mandatory ELSE fallback
     *-------------------------------------------------------------------------*)
    IF bModeBad THEN
        eState := eFault;
    ELSE
        CASE eState OF

            eIdle:
                (* 待机态：按模式等待各自的启动事件 *)
                (* Idle: wait for the mode-specific start event *)
                IF eMode = eTon THEN
                    (* 预设为零时立即完成，不占一个扫描周期的启动延迟 *)
                    (* A zero preset completes immediately, no start-up scan delay *)
                    IF bIn AND bPresetZero THEN
                        eState := eDone;
                    ELSIF bIn THEN
                        eState := eTiming;
                    END_IF
                ELSIF eMode = eTof THEN
                    IF bIn THEN
                        bTofArmed := TRUE;
                        eState    := eDone;
                    END_IF
                ELSIF eMode = eTp THEN
                    IF fbTrigRise.Q THEN
                        bTpRun := TRUE;
                        eState := eTiming;
                    END_IF
                ELSE
                    (* 保持型：已达标或输入到来均可启动；进度保留在 tAccum *)
                    (* Retentive: resume from the retained accumulation *)
                    IF bRtoDone THEN
                        eState := eDone;
                    ELSIF bIn AND bPresetZero THEN
                        bRtoDone := TRUE;
                        eState   := eDone;
                    ELSIF bIn THEN
                        eState := eTiming;
                    END_IF
                END_IF

            eTiming:
                IF eMode = eTon THEN
                    (* 输入掉电立即回待机，输出与已计时一并清零（语义表第一行） *)
                    (* Input falling returns to idle and clears the elapsed time *)
                    IF NOT bIn THEN
                        eState := eIdle;
                    ELSIF fbTonPhase.Q THEN
                        eState := eDone;
                    END_IF
                ELSIF eMode = eTof THEN
                    (* 输入恢复：延时作废回完成态；延时到期：回待机 *)
                    (* Input recovered voids the delay, expiry returns to idle *)
                    IF bIn THEN
                        eState := eDone;
                    ELSIF fbTonPhase.Q THEN
                        bTofArmed := FALSE;
                        eState    := eIdle;
                    END_IF
                ELSIF eMode = eTp THEN
                    (* 脉冲期满：结束脉冲；期间输入变化不打断，新上升沿由段 5 重触发 *)
                    (* Pulse expiry ends the pulse, a new rising edge retriggers via stage 5 *)
                    IF fbTonPhase.Q THEN
                        bTpRun := FALSE;
                        eState := eDone;
                    END_IF
                ELSE
                    (* 保持型：达标锁存；输入断开回待机但累计值保留 *)
                    (* Retentive: latch on done, an input drop keeps the accumulation *)
                    IF bRtoDone THEN
                        eState := eDone;
                    ELSIF NOT bIn THEN
                        eState := eIdle;
                    END_IF
                END_IF

            eDone:
                IF eMode = eTon THEN
                    IF NOT bIn THEN
                        eState := eIdle;
                    END_IF
                ELSIF eMode = eTof THEN
                    (* 输入断开即进入延时阶段 *)
                    (* An input drop starts the off-delay phase *)
                    IF NOT bIn THEN
                        eState := eTiming;
                    END_IF
                ELSIF eMode = eTp THEN
                    (* 脉冲结束后等待下一次上升沿 *)
                    (* Wait for the next rising edge after the pulse finished *)
                    IF fbTrigRise.Q THEN
                        bTpRun := TRUE;
                        eState := eTiming;
                    END_IF
                ELSE
                    (* 保持型：达标后锁存，仅段 8 的复位可解除 *)
                    (* Retentive: latched after done, only the reset in stage 8 clears it *)
                    eState := eDone;
                END_IF

            eFault:
                (* 故障锁存：输出由段 10 强制 FALSE，等待复位 *)
                (* Fault latched: stage 10 forces the output FALSE until reset *)
                eState := eFault;

            ELSE
                (* 非法状态拦截：转故障并上报，不做隐式恢复 *)
                (* Illegal state interception: go to fault and report, no implicit recovery *)
                eState := eFault;

        END_CASE;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜输出单一出口（边界 B8 / P-05）：三个输出只在此处统一赋值一次
 *      Single output outlet: the three outputs are written exactly once here
 *      分支内部只改状态与标志，不直接写输出，避免同一输出在多处赋值产生竞态
 *      Branches only change state and flags, never the outputs, to avoid races
 *-----------------------------------------------------------------------------*)
CASE eMode OF
    eTon:
        bQ := (eState = eDone);
    eTof:
        (* 输入 TRUE 期间与延时保持期间均输出 TRUE *)
        (* TRUE while the input is TRUE and during the off-delay hold *)
        bQ := (eState = eTiming) OR (eState = eDone);
    eTp:
        bQ := (eState = eTiming);
    eRto:
        bQ := (eState = eDone);
    ELSE
        bQ := FALSE;
END_CASE;

IF eState = eFault THEN
    bQ := FALSE;
END_IF

IF eMode = eRto THEN
    (* 保持型输出累计值：输入断开后进度仍可见，这是该模式的存在意义 *)
    (* The retentive mode reports the accumulation so the progress stays visible *)
    tElapsed := tAccum;
ELSE
    IF (eState = eIdle) OR (eState = eFault) THEN
        tElapsed := T#0S;
    ELSE
        tElapsed := fbTonPhase.ET;
    END_IF
END_IF

(* 剩余时间负值钳位（边界 B9）：换算与时序竞态都可能产生负差，一律钳到零 *)
(* Remaining time clamp: rounding and timing races can go negative, clamp to zero *)
IF tElapsed >= tPresetEff THEN
    tRemaining := T#0S;
ELSE
    tRemaining := tPresetEff - tElapsed;
END_IF

bTiming := (eState = eTiming);

(*------------------------------------------------------------------------------
 * 段 11｜故障码汇总：模式越界 > 非法状态 > 预设钳位
 *      Error aggregation: mode out-of-domain, illegal state, then preset clamp
 *-----------------------------------------------------------------------------*)
IF bModeBad THEN
    uErrorId := 16#0001_000E;
ELSIF eState = eFault THEN
    uErrorId := 16#0001_0005;
ELSIF bPresetBad THEN
    uErrorId := 16#0001_0001;
ELSE
    uErrorId := 16#0000_0000;
END_IF
END_FUNCTION_BLOCK
