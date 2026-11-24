(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PulseGenerator
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），时间-实数换算用
 *                         IEC 标准 TIME_TO_REAL / REAL_TO_TIME 转换族（毫秒语义）
 * 功能描述 (Function)   : 周期与占空比运行时可调的方波发生器，支持相位复位与禁用重启。
 *                         用 ENUM 相位状态机（高相位 / 低相位）+ 单个 TON 实现，
 *                         不引入任何平台时刻函数，行为与扫描周期严格耦合、可预期。
 *                         占空比 0 与 1 分别退化为恒低与恒高（显式分支输出，不靠相位机碰运气）；
 *                         周期设下限防止脉冲窄到下游边沿检测丢沿；
 *                         越界参数钳位后继续运行并告警，绝不停机。
 * 开源溯源 (Origin)     : 原创实现。方波 / 占空比调制为公开经典需求；
 *                         本库刻意放弃"记录时刻再比较"的实现路线，
 *                         改用标准定时器 + 相位状态机，未复制任何源码。
 * 本文件内含       : TYPE  E_DL_PulsePhase（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_PulseGenerator
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3（时间换算走标准转换族）｜ R4 ✓ 容差判等 + 周期钳位 + 进度钳位
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 两实例主体最前部无条件刷新 ｜ R8 ✓ 上下限与容差全常量化
 *
 * 【周期下限的存在理由 / Why the lower period bound exists（边界 B3）】
 *   脉宽低于两个任务周期时，下游边沿检测在扫描采样的离散化下必然丢沿，
 *   表现为"下游偶尔少计一次"。故下限设为 2ms，低于下限一律钳位并告警。
 *
 * 【平台收窄预案 / Platform narrowing contingency（边界 B5，R11）】
 *   时间-实数换算使用 IEC 标准转换族；若目标平台实测不支持该转换族，
 *   按规格书 P4 预案收窄：删去 fProgress 引脚并以整型毫秒中间量实现时长拆分，
 *   届时须在头注释追加收窄依据与影响说明。当前版本未启用收窄。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 B）
 *   2026-11-14  v1.0.1  修复换相后相位定时器不清零缺陷：标准定时器仅在本体输入为
 *                       FALSE 时清已计时，换相时只改预设值不会清零，低相位带着
 *                       高相位残值起算——占空比 0.5 时低相位塌缩为一个扫描周期，
 *                       占空比 0.3 时周期由 1000ms 变成 700ms。改为换相后追加一拍
 *                       断开输入（断拍屏蔽标志延后一拍提交），相位时长恢复设计值。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PulsePhase（归属 DL_Base，与 FB_DL_PulseGenerator 同文件）
 * 含义: 方波相位状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_PulsePhase :
(
    eInit  := 0,     // 上电/未使能首态：输出低，等待使能 / Power-up or disabled, output low and waits for enable
    eHigh  := 10,    // 高电平相位：持续 tHighTime / High phase lasting tHighTime
    eLow   := 20,    // 低电平相位：持续 tLowTime / Low phase lasting tLowTime
    eFault := 99     // 故障锁定：输出强制低 / Fault latched, output forced low
);
END_TYPE

FUNCTION_BLOCK FB_DL_PulseGenerator
VAR_INPUT
    bEnable     : BOOL := TRUE;       // 使能，FALSE 时输出 FALSE 并复位相位 / Enable, FALSE forces the output low and resets the phase
    tPeriod     : TIME := T#1S;       // 周期 [ms]，合法域为下限至上限 / Period [ms], valid range between the bounds
    fDutyCycle  : REAL := 0.5;        // 占空比 [0..1]，0 = 恒低，1 = 恒高 / Duty ratio [0..1], 0 = always low, 1 = always high
    bPhaseReset : BOOL;               // 上升沿：相位回高电平起点 / Rising edge: restart at the high phase
END_VAR
VAR_OUTPUT
    bPulseOut   : BOOL;     // 方波输出 / Square-wave output
    fProgress   : REAL;     // 当前周期进度 [0..1] / Cycle progress [0..1]
    bError      : BOOL;     // 故障/告警标志 / Fault or warning flag
    uErrorId    : UDINT;    // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbTonPhase  : TON;                // 相位计时器 / Phase timer
    fbTrigReset : R_TRIG;             // 相位复位沿检测实例 / Phase reset edge detector instance
    ePhase      : E_DL_PulsePhase;    // 相位状态机 / Phase state machine
    tHighTime   : TIME;               // 高电平持续 [ms] / High duration [ms]
    tLowTime    : TIME;               // 低电平持续 [ms] / Low duration [ms]
    tPeriodEff  : TIME;               // 钳位后周期 [ms] / Clamped period [ms]
    tPhasePt    : TIME;               // 当前相位定时器预设 [ms] / Preset of the current phase [ms]
    fDutyEff    : REAL;               // 钳位后占空比 [0..1] / Clamped duty [0..1]
    fPeriodMs   : REAL;               // 周期毫秒实数 [ms] / Period in milliseconds [ms]
    fHighMs     : REAL;               // 高相位毫秒实数 [ms] / High phase in milliseconds [ms]
    bParamBad   : BOOL;               // 参数钳位告警 / Parameter clamp warning
    bStateBad   : BOOL;               // 非法状态命中 / Illegal state hit
    bPhaseSwitched : BOOL;            // 本周期发生相位切换 / A phase switch happened this scan
    bRestartMask   : BOOL;            // 下一周期断开相位定时器一扫描（ET 归零）/ Drop the timer input for one scan
END_VAR
VAR CONSTANT
    DL_PULSE_PERIOD_MIN : TIME  := T#2MS;     // 周期下限 [ms]，至少两个任务周期可辨 / Min period [ms]
    DL_PULSE_PERIOD_MAX : TIME  := T#12H;     // 周期上限 [ms] / Max period [ms]
    DL_FLOAT_EPS        : REAL  := 1.0E-6;    // 浮点判零容差 / Float zero tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：复位沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: the reset edge instance runs at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bPhaseReset);

(*------------------------------------------------------------------------------
 * 段 2｜占空比钳位（边界 B2）：越界钳位后继续运行并告警，与 0/1 的比较用容差
 *      Duty clamping: out-of-range values clamp and warn, comparisons use a tolerance
 *-----------------------------------------------------------------------------*)
bParamBad := FALSE;

IF fDutyCycle < 0.0 THEN
    fDutyEff  := 0.0;
    bParamBad := TRUE;
ELSIF fDutyCycle > 1.0 THEN
    fDutyEff  := 1.0;
    bParamBad := TRUE;
ELSE
    fDutyEff  := fDutyCycle;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜周期钳位（边界 B3）：下限防丢沿、上限防时间量溢出，两端都告警
 *      Period clamping: the lower bound prevents missed edges downstream
 *-----------------------------------------------------------------------------*)
IF tPeriod < DL_PULSE_PERIOD_MIN THEN
    tPeriodEff := DL_PULSE_PERIOD_MIN;
    bParamBad  := TRUE;
ELSIF tPeriod > DL_PULSE_PERIOD_MAX THEN
    tPeriodEff := DL_PULSE_PERIOD_MAX;
    bParamBad  := TRUE;
ELSE
    tPeriodEff := tPeriod;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜时长拆分（边界 B5/B9）：高相位时长由周期 × 占空比得出，低相位取差值
 *      Duration split: high = period x duty, low is the remainder
 *      先钳位高相位不超过整周期，杜绝换算误差造成的负重
 *      The high phase is clamped to the period so rounding can never go negative
 *-----------------------------------------------------------------------------*)
fPeriodMs := TIME_TO_REAL(tPeriodEff);
fHighMs   := fPeriodMs * fDutyEff;

IF fHighMs < 0.0 THEN
    fHighMs := 0.0;
ELSIF fHighMs > fPeriodMs THEN
    fHighMs := fPeriodMs;
END_IF

tHighTime := REAL_TO_TIME(fHighMs);
tLowTime  := tPeriodEff - tHighTime;

(*------------------------------------------------------------------------------
 * 段 5｜相位定时器刷新（边界 B1）：PT 由当前相位决定，IN 在复位与换相周期断开
 *      Phase timer refresh: PT follows the current phase, IN drops on reset and on a switch
 *      复位当周期 IN 为 FALSE 使 ET 立即清零，实现"从高相位起点重新起算"
 *      A FALSE IN on the reset scan clears ET so the high phase restarts from zero
 *      换相后必须再断一拍：标准定时器只在 IN 为 FALSE 时清 ET，
 *      仅改 PT 不会清零，ET 会带着上一相位的残值继续累加，
 *      低相位因此被缩短为一个扫描周期（v1.0.1 修复的正是此缺陷）
 *      A PT change never clears ET; without one off-scan the low phase collapses
 *-----------------------------------------------------------------------------*)
IF ePhase = eLow THEN
    tPhasePt := tLowTime;
ELSE
    tPhasePt := tHighTime;
END_IF

fbTonPhase(IN  := ((ePhase = eHigh) OR (ePhase = eLow)) AND bEnable
                  AND (NOT fbTrigReset.Q) AND (NOT bRestartMask),
           PT  := tPhasePt);

(*------------------------------------------------------------------------------
 * 段 6｜状态机（边界 B6/B7/B8）：禁用回首态，复位回高相位，相位期满互换
 *      State machine: disable parks at init, reset returns to high, expiry swaps
 *-----------------------------------------------------------------------------*)
bStateBad := FALSE;
bPhaseSwitched := FALSE;

IF NOT bEnable THEN
    (* 禁用：回首态并强制输出低；重新使能从高相位起步，不与外设中途相位错位 *)
    (* Disabled: park at init and force the output low; re-enable restarts at high *)
    ePhase := eInit;
ELSIF fbTrigReset.Q THEN
    (* 相位复位：本周期定时器已被清零，下一次调用从高相位重新计时 *)
    (* Phase reset: the timer is already cleared, the next call times the high phase *)
    ePhase := eHigh;
ELSE
    CASE ePhase OF

        eInit:
            (* 首态：使能后从高电平相位起步 *)
            (* Initial state: enter the high phase once enabled *)
            ePhase := eHigh;

        eHigh:
            (* 高相位期满：切换到低相位，并申请下一周期断拍使 ET 归零 *)
            (* High phase expired: switch to low and request one off-scan to clear ET *)
            IF fbTonPhase.Q THEN
                ePhase         := eLow;
                bPhaseSwitched := TRUE;
            END_IF

        eLow:
            (* 低相位期满：回到高相位，同样断拍一拍重新起算 *)
            (* Low phase expired: back to high with the same one-scan restart *)
            IF fbTonPhase.Q THEN
                ePhase         := eHigh;
                bPhaseSwitched := TRUE;
            END_IF

        eFault:
            (* 故障锁存：输出由段 7 强制低，等待禁用或复位 *)
            (* Fault latched: stage 7 forces the output low until disable or reset *)
            ePhase := eFault;

        ELSE
            (* 非法相位拦截：转故障并上报，不做隐式恢复 *)
            (* Illegal phase interception: go to fault and report, no implicit recovery *)
            ePhase    := eFault;
            bStateBad := TRUE;

    END_CASE;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（边界 B4/B8）：恒低/恒高两态显式分支，不依赖相位机碰运气
 *      Single output outlet: degenerate duties take explicit branches
 *      占空比恰为 0 或 1 时若走相位机，会出现"进入高相位当周期即判期满"的毛刺
 *      Routing degenerate duties through the phase machine would create a one-scan glitch
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    bPulseOut := FALSE;
ELSIF ABS(fDutyEff) <= DL_FLOAT_EPS THEN
    bPulseOut := FALSE;
ELSIF ABS(fDutyEff - 1.0) <= DL_FLOAT_EPS THEN
    bPulseOut := TRUE;
ELSIF ePhase = eHigh THEN
    bPulseOut := TRUE;
ELSE
    bPulseOut := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜进度输出（边界 B9）：按相位累计 ET，除零前置判零 + 结果双向钳位
 *      Progress output: ET accumulated per phase, divide guard plus two-sided clamp
 *-----------------------------------------------------------------------------*)
IF fPeriodMs > DL_FLOAT_EPS THEN
    IF ePhase = eHigh THEN
        fProgress := TIME_TO_REAL(fbTonPhase.ET) / fPeriodMs;
    ELSIF ePhase = eLow THEN
        fProgress := (fHighMs + TIME_TO_REAL(fbTonPhase.ET)) / fPeriodMs;
    ELSE
        fProgress := 0.0;
    END_IF
ELSE
    fProgress := 0.0;
END_IF

IF fProgress < 0.0 THEN
    fProgress := 0.0;
ELSIF fProgress > 1.0 THEN
    fProgress := 1.0;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜故障码汇总：非法状态优先，其余为参数钳位告警
 *      Error aggregation: an illegal state outranks the parameter clamp warnings
 *-----------------------------------------------------------------------------*)
IF bStateBad THEN
    uErrorId := 16#0001_0005;
ELSIF bParamBad THEN
    uErrorId := 16#0001_0001;
ELSE
    uErrorId := 16#0000_0000;
END_IF

bError := (uErrorId <> 16#0000_0000);

(*------------------------------------------------------------------------------
 * 段 10｜换相断拍提交：本周期置的切换请求在下一周期生效并自动解除
 *      Switch mask commit: a switch raised this scan drops IN next scan and self-clears
 *      与顺控引擎的换步屏蔽同一范式：请求提交延后一拍，避免同周期自锁
 *      Same idiom as the sequencer's step mask: commit one scan later, never self-locking
 *-----------------------------------------------------------------------------*)
bRestartMask := bPhaseSwitched;
END_FUNCTION_BLOCK
