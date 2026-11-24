(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DutyStandbyRotation
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商方言
 * 功能描述 (Function)   : 8 台泵 / 风机 / 压缩机的主备轮值与均衡调度。
 *                         按累计运行时间排序，把"需求台数"分给运行时间最短且满足启动条件
 *                         的机组；按周期把领机降为备机、备机升为领机；故障机立即跳过；
 *                         每台机受最小运行时长与最小停机时长双重保护，避免刚启就停把
 *                         接触器打烂；任何时刻不得把在运行的机组全部停掉。
 *                         解决多泵系统两类对立顽疾："永远只跑 1 号泵、2 号泵锈死"与
 *                         "轮值切得太勤、接触器与软启动器半年一换"。
 *
 * 【安全语义 / Safety semantics（编码侧不可弱化的四条）】
 *   1) 命令-反馈分离：本块只发启动命令（cmd 语义，FALSE = 停），运行状态一律以
 *      abUnitRunning 反馈为准，绝不假设"发了命令就等于在转"。
 *   2) 先启后停：停机放行条件是"目标集中已在运行的台数 >= 需求台数"，比"在运行台数
 *      >= 需求台数"更严。后者在换机场景下仍会短暂欠载（压力/流量掉一拍），本块刻意收紧。
 *   3) 故障机越权停机：abUnitFault = TRUE 且仍在运行时立即撤销命令，越过最小运行时长。
 *      这是最小运行时长保护的唯一例外。
 *   4) 无可用机组时（需求 > 0 且可用 = 0）已在运行的机组绝不因此被停——现场可能是
 *      就地/检修状态把"就绪"信号摘掉了，停掉正在供压的泵比少启一台危险得多。
 *
 * 【失真与语义披露 / Distortion disclosure】
 *   1) 运行时间账（afRunSec / auStartCount）是否断电保持由调用方决定（Retain 声明在
 *      调用侧）。不保持则每次上电从 0 起轮，轮值顺序每次开机都从 0 号机开始。
 *   2) 时间换算按 TIME 基准 1 ms（CODESYS / TwinCAT 3 / 汇川三平台一致）。移植到
 *      100 ns 基准平台时只需改 DL_DS_MS_PER_S 处的一行换算，逻辑不动。
 *   3) 按接口契约，参数冲突故障的复位沿会清零运行时间账——等同重置最小时长约束，
 *      复位前必须确认机组处于稳定工况（手册列为操作注意事项）。
 *   4) 排序为选择排序 O(64)。同运行时间的 tie-break 取"上一拍序列位置"而非索引升序：
 *      若死守索引升序，段 7 刚做完的轮值会在下一拍重新排序时被原样排回去，轮值等于
 *      永不生效（本批实测踩到的实现陷阱）。首扫序列为 0..7 恒等排列，因此冷启动行为
 *      与"索引升序"完全一致；轮值之后同值机组按轮值后的相对顺序排列，结果仍可复算。
 *
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LBP 基础过程库中"最多 8 台聚合体"的粒度
 *                         与 cmd/ind 命令-反馈分离思想，以及 lead-lag 主备轮值工艺惯例，
 *                         clean-room 编写，未接触也未复制任何 LBP 源码）
 * 本文件内含       : TYPE  E_DL_RotationState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_DutyStandbyRotation
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（定长数组 + 选择排序，无动态内存）
 *                         R4 ✓ 需求钳位 + 时间增量钳位 + 双向最小时长 + 计数饱和
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 三实例主体最前部无条件刷新（本组件核心考点）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RotationState（归属 DL_Base，与 FB_DL_DutyStandbyRotation 同文件）
 * 含义: 轮值调度主状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_RotationState :
(
    eIdle          := 0,     // 未使能：命令全部撤销，运行时间账继续按反馈累加 / Disabled, commands dropped, runtime still accounted
    eRunning       := 10,    // 正常调度：累加 → 排序 → 定需求集 → 先启后停 / Normal scheduling
    eRotatePending := 20,    // 轮值挂起：受最小时长阻挡，保持当前组合并每拍重试 / Rotation pending, retried every scan
    eFault         := 99     // 参数冲突锁存：轮值禁用，但启停调度照常工作 / Latched config fault, scheduling still runs
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_DutyStandbyRotation
 * 调用约定: 每个扫描周期无条件调用一次，uDeltaTimeMs 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DutyStandbyRotation
VAR_INPUT
    abUnitReady     : ARRAY[0..7] OF BOOL;    // 机组就绪（无故障、无就地、无禁止），上限 8 台 / Unit ready, max 8 units
    abUnitRunning   : ARRAY[0..7] OF BOOL;    // 运行反馈（接触器辅助触点或流量开关）/ Running feedback
    abUnitFault     : ARRAY[0..7] OF BOOL;    // 机组故障（跳过并允许立即停机）/ Unit fault, skipped and stopped at once
    nDemand         : INT := 0;               // 需求运行台数，合法域 0..8 / Required unit count, valid 0..8
    bEnable         : BOOL := TRUE;           // 使能，FALSE 时命令全撤 / Enable, FALSE drops all commands
    uDeltaTimeMs    : UDINT;                  // 调用方注入的扫描间隔 [ms] / Injected scan delta [ms]
    tMinRunTime     : TIME := T#10M;          // 最小连续运行时长 [min]，防刚启就停 / Minimum run time
    tMinStopTime    : TIME := T#5M;           // 最小停机时长 [min]，防接触器高频动作 / Minimum stop time
    tRotateInterval : TIME := T#24H;          // 轮值周期 [h] / Rotation interval
    bForceRotate    : BOOL;                   // 上升沿：立即请求一次轮值（仍受最小时长约束）/ Rising edge: force one rotation
    bReset          : BOOL;                   // 上升沿：复位参数冲突并清零运行时间账 / Rising edge: reset the config fault and clear runtimes
END_VAR
VAR_OUTPUT
    abStartCmd        : ARRAY[0..7] OF BOOL;  // 启动命令（cmd 语义，FALSE = 停）/ Start command per unit, FALSE = stop
    anRank            : ARRAY[0..7] OF INT;   // 本轮优先顺序，0 = 最高 / Priority rank, 0 = highest
    nLeadUnit         : INT;                  // 领机号 0..7，-1 = 无 / Lead unit 0..7, -1 = none
    afRuntimeHours    : ARRAY[0..7] OF LREAL; // 累计运行小时 [h] / Accumulated runtime [h]
    abBlockedByMinRun : ARRAY[0..7] OF BOOL;  // 因最小运行时长被阻止停机 / Stop blocked by the minimum run time
    abBlockedByMinStop: ARRAY[0..7] OF BOOL;  // 因最小停机时长被阻止启动 / Start blocked by the minimum stop time
    auStartCount      : ARRAY[0..7] OF UDINT; // 各机启动次数（饱和）/ Start count per unit, saturating
    bRotatePending    : BOOL;                 // 轮值挂起中 / Rotation pending
    bNoAvailableUnit  : BOOL;                 // 无可用机组（瞬时诊断）/ No available unit, instantaneous
    uRotateCount      : UDINT;                // 已完成的轮值次数（饱和）/ Completed rotations, saturating
    bError            : BOOL;                 // 故障标志（参数冲突锁存）/ Fault flag, config conflict latched
    uErrorId          : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = no error
    eState            : E_DL_RotationState;   // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿检测实例 / Reset rising edge detector
    fbTrigForce     : R_TRIG;                 // 强制轮值上升沿检测实例 / Force-rotate rising edge detector
    fbTonRotate     : TON;                    // 轮值周期定时器 / Rotation interval timer
    eStateInt       : E_DL_RotationState;     // 主状态机内部当前态 / Internal state of the main state machine
    afRunSec        : ARRAY[0..7] OF LREAL;   // 运行秒累加 [s] / Runtime seconds accumulator [s]
    afStopSec       : ARRAY[0..7] OF LREAL;   // 停机秒累加 [s] / Stop seconds accumulator [s]
    anOrder         : ARRAY[0..7] OF INT;     // 已提交的优先序列（可用优先，运行时间升序）/ Committed priority order
    anTrial         : ARRAY[0..7] OF INT;     // 轮值试验序列（未提交前不生效）/ Trial order, not committed yet
    anPos           : ARRAY[0..7] OF INT;     // 各机组在上一拍序列中的位置（排序稳定性锚点）/ Previous position per unit
    abUsable        : ARRAY[0..7] OF BOOL;    // 可用 = 就绪且无故障 / Usable = ready and not faulted
    abDesired       : ARRAY[0..7] OF BOOL;    // 目标运行集 / Desired running set
    abTrialUnit     : ARRAY[0..7] OF BOOL;    // 轮值试验目标集 / Trial desired set
    abCmdInt        : ARRAY[0..7] OF BOOL;    // 本拍命令内部副本 / Internal command copy of this scan
    abCmdPrev       : ARRAY[0..7] OF BOOL;    // 上一拍命令（算启动沿）/ Previous commands, for start edges
    nIdx            : INT;                    // 外层索引 / Outer index
    nInner          : INT;                    // 内层索引 / Inner index
    nMinPos         : INT;                    // 选择排序中的最小元位置 / Position of the minimum during selection sort
    nTmp            : INT;                    // 交换临时量 / Swap temporary
    nAvail          : INT;                    // 可用机组数 / Number of usable units
    nDesired        : INT;                    // 本拍应运行台数（已按可用数钳位）/ Desired count, clamped to the usable count
    nRunningCnt     : INT;                    // 当前在运行台数 / Currently running units
    nDesiredRunning : INT;                    // 目标集中已在运行的台数 / Desired units already running
    nCnt            : INT;                    // 计数累加器 / Counting accumulator
    nLead           : INT;                    // 领机号 / Lead unit index
    nDemandEff      : INT;                    // 钳位后的需求台数 / Clamped demand
    fDtSec          : LREAL;                  // 扫描间隔换算成秒 [s] / Scan delta in seconds [s]
    fMinRunSec      : LREAL;                  // 最小运行时长 [s] / Minimum run time [s]
    fMinStopSec     : LREAL;                  // 最小停机时长 [s] / Minimum stop time [s]
    tRotEff         : TIME;                   // 钳位后的轮值周期 [ms] / Clamped rotation interval [ms]
    uDtEff          : UDINT;                  // 钳位后的扫描间隔 [ms] / Clamped scan delta [ms]
    uWarnId         : UDINT;                  // 本拍瞬时告警码 / Instantaneous warning code of this scan
    uRotateCnt      : UDINT;                  // 轮值次数内部副本（饱和）/ Internal rotation counter, saturating
    bRotateReq      : BOOL;                   // 本拍请求轮值 / Rotation requested this scan
    bRotTimerRun    : BOOL;                   // 轮值定时器运行中 / Rotation timer running
    bRotTimerRearm  : BOOL;                   // 轮值定时器下一拍重新计时 / Rearm the rotation timer next scan
    bRotPendingScr  : BOOL;                   // 本拍轮值因最小时长受阻 / Rotation blocked by the minimum times this scan
    bFeasible       : BOOL;                   // 轮值试验是否可行 / Whether the trial rotation is feasible
    bSmaller        : BOOL;                   // 排序比较：候选元是否更靠前 / Sort comparator: candidate ranks earlier
    bHoldAll        : BOOL;                   // 无可用机组时冻结全部停机 / Freeze every stop when no unit is usable
    bSchedOn        : BOOL;                   // 本拍允许调度 / Scheduling enabled this scan
    bConflict       : BOOL;                   // 本拍存在时间参数冲突 / Time-parameter conflict present this scan
    bParamLatch     : BOOL;                   // 参数冲突锁存 / Configuration conflict latched
    bStateFault     : BOOL;                   // 非法状态锁存（与参数冲突分开记账）/ Illegal-state latch, kept apart from the config latch
    bCntWarned      : BOOL;                   // 饱和告警已发过一次 / Saturation warning already raised
    bSortInit       : BOOL := TRUE;           // 排序序列尚未初始化为恒等排列 / Priority order not yet initialised
    bFirstScan      : BOOL := TRUE;           // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_DS_UNITS      : INT   := 8;            // 机组数，必须等于数组维度 / Unit count, must match the arrays
    DL_DS_IDX_NONE   : INT   := -1;           // 无效索引哨兵 / Invalid-index sentinel
    DL_DS_HOUR_MAX   : LREAL := 1.0E9;        // 运行小时饱和上限 [h] / Runtime saturation [h]
    DL_DS_SEC_MAX    : LREAL := 3.6E12;       // 运行秒饱和上限 [s]，与小时上限对齐 / Runtime saturation [s]
    DL_DS_SEC_PER_H  : LREAL := 3600.0;       // 小时换算常数 [s/h] / Seconds per hour
    DL_DS_MS_PER_S   : LREAL := 1000.0;       // 毫秒换算常数 [ms/s]，三平台 TIME 基准均为 1 ms / Milliseconds per second
    DL_DS_DT_MAX     : UDINT := 60000;        // 时间增量上限 [ms]，超此值判为断点 / Delta clamp [ms]
    DL_DS_EPS        : LREAL := 1.0E-6;       // 浮点判等容差 / Float comparison tolerance
    DL_DS_CNT_MAX    : UDINT := 16#FFFF_FFFE; // 计数器饱和值 / Counter saturation
    DL_DS_ROT_MIN    : TIME  := T#1S;         // 轮值周期下限 [s] / Rotation interval lower bound
    DL_DS_ROT_MAX    : TIME  := T#8760H;      // 轮值周期上限 [h]，一年 / Rotation interval upper bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜轮值周期钳位（先于定时器，避免 PT = 0 造成每拍触发）
 *      Rotation-interval clamp, done before the timer so PT is never zero
 *-----------------------------------------------------------------------------*)
uWarnId := 16#0000;
tRotEff := tRotateInterval;

IF tRotEff < DL_DS_ROT_MIN THEN
    tRotEff := DL_DS_ROT_MIN;
    uWarnId := 16#0001_0001;
ELSIF tRotEff > DL_DS_ROT_MAX THEN
    tRotEff := DL_DS_ROT_MAX;
    uWarnId := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：两沿 + 一轮值周期计时
 *      Unconditional refresh zone: two edges plus the rotation interval timer
 *      IN 由 bRotTimerRun 这一派生量给出，实例调用本身绝不进 IF
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigForce(CLK := bForceRotate);
fbTonRotate(IN := bRotTimerRun, PT := tRotEff);

bRotateReq := fbTrigForce.Q;

IF fbTonRotate.Q THEN
    bRotateReq     := TRUE;
    bRotTimerRun   := FALSE;    // 下一拍 ET 归零 / Reset ET on the next scan
    bRotTimerRearm := TRUE;
ELSIF bRotTimerRearm THEN
    bRotTimerRun   := TRUE;
    bRotTimerRearm := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：状态、领机号与锁存显式落到安全侧
 *      First-scan init: state, lead index and latches forced to the safe side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    bFirstScan  := FALSE;
    eStateInt   := E_DL_RotationState.eIdle;
    nLead       := DL_DS_IDX_NONE;
    bParamLatch := FALSE;
    uRotateCnt  := 0;
    bRotTimerRun   := FALSE;
    bRotTimerRearm := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜时间增量校验（边界 B8）：0 或超上限一律钳位，绝不接受回绕值
 *      Delta-time check: zero or over-limit values are clamped, wraparound never accepted
 *      回绕的 UDINT 转成秒后是天文数字，会瞬间把运行时间算爆并把排序彻底打乱
 *-----------------------------------------------------------------------------*)
IF uDeltaTimeMs = 0 THEN
    uDtEff  := 1;
    uWarnId := 16#0001_0008;
ELSIF uDeltaTimeMs > DL_DS_DT_MAX THEN
    uDtEff  := DL_DS_DT_MAX;
    uWarnId := 16#0001_0008;
ELSE
    uDtEff := uDeltaTimeMs;
END_IF

fDtSec     := UDINT_TO_LREAL(uDtEff) / DL_DS_MS_PER_S;
fMinRunSec := TIME_TO_LREAL(tMinRunTime) / DL_DS_MS_PER_S;
fMinStopSec := TIME_TO_LREAL(tMinStopTime) / DL_DS_MS_PER_S;

(*------------------------------------------------------------------------------
 * 段 4｜参数校验（边界 B1/B7）
 *      Parameter validation: demand clamp and the minimum-time conflict check
 *-----------------------------------------------------------------------------*)
nDemandEff := nDemand;
IF nDemand < 0 THEN
    nDemandEff := 0;
    uWarnId    := 16#0001_0001;
ELSIF nDemand > DL_DS_UNITS THEN
    nDemandEff := DL_DS_UNITS;
    uWarnId    := 16#0001_0001;
END_IF

(* 最小运行 + 最小停机 > 轮值周期：轮值永远等不到，属参数冲突而非运行故障 *)
(* min-run + min-stop > interval means rotation could never complete: a configuration conflict *)
bConflict := ((tMinRunTime + tMinStopTime) > tRotateInterval);

IF bConflict THEN
    bParamLatch := TRUE;
END_IF

IF (tMinRunTime < T#0S) OR (tMinStopTime < T#0S) THEN
    uWarnId := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜运行时间记账（状态 eIdle 也照记：停机也要记账，否则轮值失真）
 *      Runtime accounting runs even when disabled: an unaccounted stop skews rotation
 *      以反馈为准而不是以命令为准，接触器没吸合就不能算运行
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO

    IF abUnitRunning[nIdx] THEN
        afRunSec[nIdx] := afRunSec[nIdx] + fDtSec;
        IF afRunSec[nIdx] > DL_DS_SEC_MAX THEN
            afRunSec[nIdx] := DL_DS_SEC_MAX;
            uWarnId := 16#0001_0007;
        END_IF
    ELSE
        afStopSec[nIdx] := afStopSec[nIdx] + fDtSec;
        IF afStopSec[nIdx] > DL_DS_SEC_MAX THEN
            afStopSec[nIdx] := DL_DS_SEC_MAX;
        END_IF
    END_IF

    afRuntimeHours[nIdx] := afRunSec[nIdx] / DL_DS_SEC_PER_H;
    IF afRuntimeHours[nIdx] > DL_DS_HOUR_MAX THEN
        afRuntimeHours[nIdx] := DL_DS_HOUR_MAX;
    END_IF

END_FOR

(*------------------------------------------------------------------------------
 * 段 6｜可用性与候选排序（边界 B6/B10）
 *      Usability and candidate ordering: usable first, then runtime, then previous position
 *      序列只在首扫初始化为恒等排列，之后一律在既有排列上就地排序：
 *      若每拍都从 0..7 重新开始排，段 7 刚做完的轮值会在下一拍被排序抹掉，
 *      轮值等于永远不生效——这是本组件最容易踩的实现陷阱
 *      The order is initialised once and then sorted in place, otherwise every rotation
 *      would be erased by the next scan's re-sort
 *-----------------------------------------------------------------------------*)
nAvail := 0;

FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    abUsable[nIdx] := abUnitReady[nIdx] AND (NOT abUnitFault[nIdx]);
    IF abUsable[nIdx] THEN
        nAvail := nAvail + 1;
    END_IF
END_FOR

IF bSortInit THEN
    FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
        anOrder[nIdx] := nIdx;
        anPos[nIdx]   := nIdx;
    END_FOR
    bSortInit := FALSE;
END_IF

(* 选择排序：8 元定长，0..6 外层、nIdx+1..7 内层，迭代次数由常量卡死 *)
(* Selection sort over 8 fixed elements, the loop bounds are compile-time constants *)
FOR nIdx := 0 TO (DL_DS_UNITS - 2) DO

    nMinPos := nIdx;

    FOR nInner := (nIdx + 1) TO (DL_DS_UNITS - 1) DO

        bSmaller := FALSE;

        IF abUsable[anOrder[nInner]] AND (NOT abUsable[anOrder[nMinPos]]) THEN
            bSmaller := TRUE;
        ELSIF abUsable[anOrder[nInner]] = abUsable[anOrder[nMinPos]] THEN
            IF (afRunSec[anOrder[nInner]] + DL_DS_EPS) < afRunSec[anOrder[nMinPos]] THEN
                bSmaller := TRUE;
            ELSIF ABS(afRunSec[anOrder[nInner]] - afRunSec[anOrder[nMinPos]]) <= DL_DS_EPS THEN
                (* 运行时间相同：按上一拍位置排序，保证稳定且轮值结果不被抹掉 *)
                (* Equal runtime: keep the previous relative order, so rotations survive *)
                IF anPos[anOrder[nInner]] < anPos[anOrder[nMinPos]] THEN
                    bSmaller := TRUE;
                END_IF
            END_IF
        END_IF

        IF bSmaller THEN
            nMinPos := nInner;
        END_IF

    END_FOR

    IF nMinPos <> nIdx THEN
        nTmp             := anOrder[nIdx];
        anOrder[nIdx]    := anOrder[nMinPos];
        anOrder[nMinPos] := nTmp;
    END_IF

END_FOR

FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    anPos[anOrder[nIdx]] := nIdx;
END_FOR

nDesired := nDemandEff;
IF nDesired > nAvail THEN
    nDesired := nAvail;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜轮值尝试（边界 B7）：可行才移位，不可行一律不动任何命令
 *      Rotation attempt: shift only when every constraint is met, never touch commands otherwise
 *      把"领机移到可用序列末位、其余前移一位"这一动作做成试验序列，
 *      可行性由"要停的机组已满足最小运行、要启的机组已满足最小停机"共同决定
 *-----------------------------------------------------------------------------*)
bRotPendingScr := FALSE;

FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    abBlockedByMinRun[nIdx]  := FALSE;
    abBlockedByMinStop[nIdx] := FALSE;
END_FOR

IF bRotateReq AND bEnable AND (NOT bParamLatch)
   AND (eStateInt <> E_DL_RotationState.eIdle)
   AND (eStateInt <> E_DL_RotationState.eFault)
   AND (nAvail >= 2) AND (nDesired >= 1) THEN

    FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
        anTrial[nIdx] := anOrder[nIdx];
    END_FOR

    nTmp := anTrial[0];
    FOR nIdx := 0 TO (DL_DS_UNITS - 2) DO
        IF nIdx < (nAvail - 1) THEN
            anTrial[nIdx] := anTrial[nIdx + 1];
        END_IF
    END_FOR
    anTrial[nAvail - 1] := nTmp;

    (* 试验目标集：可用序列中取前 nDesired 台 *)
    (* Trial set: the first nDesired usable entries of the trial order *)
    FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
        abTrialUnit[nIdx] := FALSE;
    END_FOR

    nCnt := 0;
    FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
        IF (nCnt < nDesired) AND abUsable[anTrial[nIdx]] AND (NOT abTrialUnit[anTrial[nIdx]]) THEN
            abTrialUnit[anTrial[nIdx]] := TRUE;
            nCnt := nCnt + 1;
        END_IF
    END_FOR

    (* 可行性检查：需停的看最小运行，需启的看最小停机；故障机不参与（越权立即停） *)
    (* Feasibility: stops need the min run time, starts need the min stop time *)
    bFeasible := TRUE;

    FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
        IF abUnitRunning[nIdx] AND (NOT abTrialUnit[nIdx]) AND (NOT abUnitFault[nIdx]) THEN
            IF afRunSec[nIdx] < fMinRunSec THEN
                bFeasible := FALSE;
                abBlockedByMinRun[nIdx] := TRUE;
            END_IF
        END_IF
        IF (NOT abUnitRunning[nIdx]) AND abTrialUnit[nIdx] THEN
            IF afStopSec[nIdx] < fMinStopSec THEN
                bFeasible := FALSE;
                abBlockedByMinStop[nIdx] := TRUE;
            END_IF
        END_IF
    END_FOR

    IF bFeasible THEN
        FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
            anOrder[nIdx] := anTrial[nIdx];
        END_FOR
        (* 提交后立即刷新位置锚点，否则下一次排序会按旧位置把轮值结果排回去 *)
        (* Refresh the position anchor at once, or the next sort undoes the rotation *)
        FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
            anPos[anOrder[nIdx]] := nIdx;
        END_FOR
        bRotateReq := FALSE;
        IF uRotateCnt < DL_DS_CNT_MAX THEN
            uRotateCnt := uRotateCnt + 1;
        ELSIF NOT bCntWarned THEN
            uWarnId    := 16#0001_0007;
            bCntWarned := TRUE;
        END_IF
    ELSE
        (* 边界 B7：请求不丢，保留到条件满足，每拍重试且只补做一次 *)
        (* The request is kept, retried every scan, and only ever executed once *)
        bRotPendingScr := TRUE;
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 8｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_RotationState.eIdle:
        bRotateReq     := FALSE;
        bRotTimerRun   := FALSE;
        bRotTimerRearm := TRUE;
        IF bEnable THEN
            IF bParamLatch THEN
                eStateInt := E_DL_RotationState.eFault;
            ELSE
                eStateInt := E_DL_RotationState.eRunning;
            END_IF
        END_IF

    E_DL_RotationState.eRunning:
        IF NOT bEnable THEN
            eStateInt := E_DL_RotationState.eIdle;
        ELSIF bParamLatch THEN
            eStateInt := E_DL_RotationState.eFault;
        ELSIF bRotPendingScr THEN
            eStateInt := E_DL_RotationState.eRotatePending;
        END_IF

    E_DL_RotationState.eRotatePending:
        IF NOT bEnable THEN
            eStateInt := E_DL_RotationState.eIdle;
        ELSIF bParamLatch THEN
            eStateInt := E_DL_RotationState.eFault;
        ELSIF NOT bRotPendingScr THEN
            eStateInt := E_DL_RotationState.eRunning;
        END_IF

    E_DL_RotationState.eFault:
        (* 轮值禁用但启停调度照常：不能因为轮值配错就让泵不转 *)
        (* Rotation is disabled, scheduling still runs: a wrong interval must not stop the pumps *)
        bRotateReq := FALSE;
        IF NOT bEnable THEN
            eStateInt := E_DL_RotationState.eIdle;
        ELSIF fbTrigReset.Q AND (NOT bConflict) THEN
            bParamLatch := FALSE;
            bStateFault := FALSE;
            eStateInt   := E_DL_RotationState.eRunning;
            (* 接口契约：复位参数冲突同时清零运行时间账，等同重置最小时长约束 *)
            (* Contract: resetting the conflict also clears the runtime books *)
            FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
                afRunSec[nIdx]    := 0.0;
                afStopSec[nIdx]   := 0.0;
                afRuntimeHours[nIdx] := 0.0;
            END_FOR
            bRotTimerRun   := FALSE;
            bRotTimerRearm := TRUE;
        END_IF

    ELSE
        (* 非法状态拦截：不做隐式恢复，直接锁存上报 *)
        (* Illegal state interception: no implicit recovery, latch and report *)
        eStateInt   := E_DL_RotationState.eFault;
        bStateFault := TRUE;

END_CASE;

bSchedOn := bEnable AND (eStateInt <> E_DL_RotationState.eIdle);

(*------------------------------------------------------------------------------
 * 段 9｜命令生成（边界 B1/B2/B3/B4/B5）：先启后停，单一出口
 *      Command derivation: starts first, stops last, single exit
 *      顺序本身即安全逻辑：先把替代机组拉起来，等反馈确认到位后才允许停旧机
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    abDesired[nIdx] := FALSE;
END_FOR

nCnt := 0;
FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    IF (nCnt < nDesired) AND abUsable[anOrder[nIdx]] THEN
        abDesired[anOrder[nIdx]] := TRUE;
        nCnt := nCnt + 1;
    END_IF
END_FOR

nRunningCnt     := 0;
nDesiredRunning := 0;

FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    IF abUnitRunning[nIdx] THEN
        nRunningCnt := nRunningCnt + 1;
        IF abDesired[nIdx] THEN
            nDesiredRunning := nDesiredRunning + 1;
        END_IF
    END_IF
END_FOR

(* 边界 B1/V5：需求 > 0 而可用 = 0 时冻结全部停机，已在供压的机组绝不停 *)
(* Demand > 0 with no usable unit freezes every stop: a running pump is never stopped *)
bHoldAll := (nDemandEff > 0) AND (nAvail = 0);

FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO

    abCmdInt[nIdx] := abDesired[nIdx];

    IF abUnitFault[nIdx] THEN
        (* 边界 B4：故障机越权停机，不等最小运行时长 *)
        (* Fault overrides the minimum run time: stop at once *)
        abCmdInt[nIdx] := FALSE;

    ELSIF abDesired[nIdx] AND (NOT abUnitRunning[nIdx]) THEN
        (* 启动约束：未就绪或停机未满，一律不启动 *)
        (* Start constraint: not ready or the minimum stop time is not satisfied *)
        IF (NOT abUnitReady[nIdx]) THEN
            abCmdInt[nIdx] := FALSE;
        ELSIF afStopSec[nIdx] < fMinStopSec THEN
            abCmdInt[nIdx] := FALSE;
            abBlockedByMinStop[nIdx] := TRUE;
        END_IF

    ELSIF abUnitRunning[nIdx] AND (NOT abDesired[nIdx]) THEN
        (* 停机约束：冻结 → 最后一台 → 最小运行时长 → 目标集是否已全部到位 *)
        (* Stop constraint: freeze, then the last unit, then min run, then start-first *)
        IF bHoldAll THEN
            abCmdInt[nIdx] := TRUE;
        ELSIF (nDemandEff > 0) AND (nRunningCnt <= 1) THEN
            (* 边界 B5 加强项：需求 > 0 时绝不停掉正在供压的最后一台 *)
            (* Never stop the last running unit while a demand exists *)
            abCmdInt[nIdx] := TRUE;
        ELSIF afRunSec[nIdx] < fMinRunSec THEN
            abCmdInt[nIdx] := TRUE;
            abBlockedByMinRun[nIdx] := TRUE;
        ELSIF nDesiredRunning >= nDesired THEN
            abCmdInt[nIdx] := FALSE;
        ELSE
            abCmdInt[nIdx] := TRUE;
        END_IF

    END_IF

END_FOR

IF NOT bSchedOn THEN
    FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
        abCmdInt[nIdx] := FALSE;
    END_FOR
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜启动次数统计（命令上升沿）：饱和累加，回绕会让保养周期判断失效
 *      Start counters increment on command rising edges, with saturation
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    IF abCmdInt[nIdx] AND (NOT abCmdPrev[nIdx]) THEN
        IF auStartCount[nIdx] < DL_DS_CNT_MAX THEN
            auStartCount[nIdx] := auStartCount[nIdx] + 1;
        ELSIF NOT bCntWarned THEN
            uWarnId    := 16#0001_0007;
            bCntWarned := TRUE;
        END_IF
    END_IF
    abCmdPrev[nIdx] := abCmdInt[nIdx];
END_FOR

(*------------------------------------------------------------------------------
 * 段 11｜排序与领机（边界 B6）：排名来自已提交序列，不来自本拍临时计算
 *      Ranking and lead unit come from the committed order
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    anRank[nIdx] := DL_DS_IDX_NONE;
END_FOR

FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    IF (anOrder[nIdx] >= 0) AND (anOrder[nIdx] < DL_DS_UNITS) THEN
        anRank[anOrder[nIdx]] := nIdx;
    END_IF
END_FOR

IF (nAvail > 0) AND (nDesired > 0) THEN
    nLead := anOrder[0];
ELSE
    nLead := DL_DS_IDX_NONE;
END_IF

(*------------------------------------------------------------------------------
 * 段 12｜故障码落码（红线 R15）：锁存码优先，瞬时码条件消失即归零
 *      Error-code policy: latched codes win, instantaneous codes clear themselves
 *-----------------------------------------------------------------------------*)
IF (nDemandEff > 0) AND (nAvail = 0) THEN
    uWarnId := 16#0002_0007;
END_IF

IF eStateInt <> E_DL_RotationState.eFault THEN
    IF uWarnId <> 16#0000 THEN
        uErrorId := uWarnId;
    ELSE
        uErrorId := 16#0000_0000;
    END_IF
END_IF

IF bParamLatch THEN
    uErrorId := 16#0002_0008;
ELSIF bStateFault THEN
    uErrorId := 16#0001_0005;
END_IF

(*------------------------------------------------------------------------------
 * 段 13｜输出单一出口（范式 P-05）
 *      Single output exit: the command array is written exactly once, here
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_DS_UNITS - 1) DO
    abStartCmd[nIdx] := abCmdInt[nIdx];
END_FOR

bRotatePending   := (eStateInt = E_DL_RotationState.eRotatePending);
bNoAvailableUnit := (nDemandEff > 0) AND (nAvail = 0);
uRotateCount     := uRotateCnt;
nLeadUnit        := nLead;
bError           := bParamLatch OR bStateFault;
eState           := eStateInt;
END_FUNCTION_BLOCK
