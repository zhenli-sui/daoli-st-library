(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CameraHealthWatch
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : t1-5-tcopen（视觉设备健康看门狗语义，clean-room 编写）
 * 功能描述 (Function)   : 视觉相机设备健康看门狗，三判据独立确认窗：
 *                         ① 触发结果超时：触发发出后 tTrigTimeout 内无结果返回，
 *                            连续 nTimeoutTrips 次超时 -> eCheckFunction；
 *                         ② 心跳丢失：tHeartbeatWin 周期窗内无任何结果返回 ->
 *                            eCheckFunction（下一次结果返回即恢复）；
 *                         ③ NG 率滑动窗趋势：nNgWindow 环形窗内 NG 率超
 *                            fNgRateLimit 且 tNgConfirm 确认窗满 -> eMaintenanceReq。
 *                         样本数不足 nNgMinSamples 时 NG 判据挂起不发布
 *                         （挂起同步挂起确认计时器，R307）。
 * 统计语义次源 (Stats)  : NG 率滑动窗沿用 FB_DL_SignalStatistics 的环形窗统计语义
 *                         （次源参照，不实例化——该件为 REAL 值统计器，位样本
 *                         环形由本件自建，语义对齐不复制实现）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 三判据各带独立确认窗（R13 三分类范式）：超时窗 = tTrigTimeout，心跳窗 =
 *      tHeartbeatWin，NG 确认窗 = tNgConfirm，互不复用。
 *   2) 同拍竞态（R275）：结果返回沿与超时 / 心跳到期同拍时，结果沿优先消化
 *      （IF / ELSIF 结构性优先），超时不计入 streak。
 *   3) NG 率分母（有效样本数）为 0 或低于下限时判据挂起：不发布、不计码、
 *      确认计时器不计时（挂起同步挂起累计载体 R307）。
 *   4) 使能撤销不置故障：只复位统计（streak / NG 窗 / 确认器），健康回 eUnknown。
 *   5) 组态非法两级回退（R117）：非法参数钳回默认常量，看门狗继续服务并置
 *      故障级码（组态错误必须可见，但监视不停摆）。
 * 配比约束 (Timing ratios) : tHeartbeatWin > tTrigTimeout（心跳窗必须宽于触发窗，
 *      否则每次触发超时都会连带心跳判据，双判据互相污染）。
 * 故障码表 (Error codes) :
 *   16#0003_0504 [故障级] 组态非法（窗长 / 样本数 / NG 率限域 / 配比），已两级回退
 *                 反证：回退后看门狗继续服务，eHealth 与合法组态时组合相同，
 *                 码位是组态错误唯一可见出口。
 *   16#0003_0402 [信息级] 触发超时连续 nTimeoutTrips 次达成（eCheckFunction 依据一）
 *                 反证：eHealth 为分级状态不承载成因；三类成因必须码位互异（R190）。
 *   16#0003_0403 [信息级] 心跳丢失确认（eCheckFunction 依据二）
 *                 反证：心跳丢失与触发超时对 eHealth 的影响同为 eCheckFunction，组合不可区分。
 *   16#0003_0404 [信息级] NG 率趋势确认（eMaintenanceReq 依据）
 *                 反证：NG 趋势的分级与 eCheckFunction 级两成因不同档，码位仍需独立承载。
 * 码位总账 (Code ledger) : 16#0003_0504 用 ｜ 16#0003_0402 / 0403 / 0404 用
 * 依赖     (Depends)    : TYPE E_DL_Ne107Status（属主 I_DL_DeviceHealth.st，只引用）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 域闸全枚举 / 两级回退 / 计数饱和
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 三态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 三沿三计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 2 · 目标 7）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（复位沿 + 组态改对即清锁存，原 eFault 相不可达）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CamHealthState（归属 DL_Device，与 FB_DL_CameraHealthWatch 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CamHealthState :
(
    eIdle  := 0,    // 未使能：统计复位，健康 eUnknown / Disabled, stats reset, eUnknown
    eWatch := 10,   // 监视中：三判据并行评估 / Watching, three criteria evaluated
    eFault := 99    // 组态故障：两级回退后继续监视 / Config fault, service continues after fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CameraHealthWatch
 * 调用约定: 每个扫描周期无条件调用一次；结果引脚为单拍事件语义。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CameraHealthWatch
VAR_INPUT
    bTriggerOut     : BOOL;                 // 触发发出（上升沿登记未决）/ Trigger issued, rising edge arms outstanding
    bResultOk       : BOOL;                 // 本拍结果返回且 OK（单拍事件）/ Result returned OK this scan, single shot
    bResultNg       : BOOL;                 // 本拍结果返回且 NG（单拍事件）/ Result returned NG this scan, single shot
    tTrigTimeout    : TIME := T#5S;         // 触发结果超时窗 [s] / Trigger result timeout window [s]
    tHeartbeatWin   : TIME := T#30S;        // 心跳窗 [s]，须 > tTrigTimeout / Heartbeat window [s], must exceed trigger window
    tNgConfirm      : TIME := T#60S;        // NG 率确认窗 [s] / NG rate confirmation window [s]
    nTimeoutTrips   : INT  := 3;            // 连续超时次数阈值 [次] / Consecutive timeout trip threshold
    fNgRateLimit    : REAL := 0.2;          // NG 率上限 [1]，域 0..1 / NG rate ceiling, 0..1
    nNgMinSamples   : INT  := 5;            // NG 判据最小样本数 [个] / NG criterion minimum samples
    nNgWindow       : INT  := 32;           // NG 滑动窗长 [个]，域 2..64 / NG sliding window length
    bEnable         : BOOL := TRUE;         // 使能 / Enable
    bReset          : BOOL;                 // 上升沿：清组态故障锁存与统计 / Rising edge: clear config latch and stats
END_VAR
VAR_OUTPUT
    eHealth         : E_DL_Ne107Status;     // NE107 健康出口 / NE107 health verdict
    nTimeoutStreak  : INT;                  // 当前连续超时次数 [次] / Current consecutive timeout count
    bHeartbeatLost  : BOOL;                 // 心跳丢失（保持至下次结果）/ Heartbeat lost, held until next result
    fNgRate         : REAL;                 // 当前 NG 率 [1]，样本不足时为 -1.0 哨兵 / Current NG rate, -1.0 sentinel
    bNgSuspended    : BOOL;                 // NG 判据挂起（样本不足）/ NG criterion suspended, too few samples
    bError          : BOOL;                 // 故障标志（组态类锁存）/ Fault flag, configuration class
    uErrorId        : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = none
    eState          : E_DL_CamHealthState;  // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigTrig      : R_TRIG;               // 触发沿检测实例 / Trigger edge detector
    fbTrigResult    : R_TRIG;               // 结果返回沿检测实例 / Result edge detector
    fbTrigReset     : R_TRIG;               // 复位沿检测实例 / Reset edge detector
    tonTrig         : TON;                  // 触发超时计时实例 / Trigger timeout timer
    tonHb           : TON;                  // 心跳窗计时实例 / Heartbeat window timer
    tonNg           : TON;                  // NG 确认窗计时实例 / NG confirmation timer
    eStateInt       : E_DL_CamHealthState;  // 主状态机内部当前态 / Internal state machine state
    bTrigOutPrev    : BOOL;                 // TON 调用时刻的未决快照（同拍竞态判据）/ Outstanding snapshot at TON call time
    bResultAny      : BOOL;                 // 本拍有结果返回 / Any result this scan
    bTrigOutstanding: BOOL;                 // 触发未决（发出后未见结果）/ Trigger outstanding, no result yet
    bHbRun          : BOOL;                 // 心跳窗计时进行中 / Heartbeat window running
    bNgExceeds      : BOOL;                 // NG 率超限（挂起时强制 FALSE，驱动确认器）/ NG rate exceeds, drives the confirmer
    bNgConfirmed    : BOOL;                 // NG 判据已确认（保持型）/ NG criterion confirmed, level held
    abNgWin         : ARRAY[0..63] OF BOOL; // NG 样本环形窗（TRUE = NG）/ NG sample ring, TRUE = NG
    nNgWrite        : INT;                  // NG 窗写指针 [0..63] / NG ring write pointer
    nNgFill         : INT;                  // NG 窗有效样本数 [个] / NG ring valid samples
    nNgCount        : INT;                  // NG 窗内 NG 样本数 [个] / NG samples in ring
    nStreakInt      : INT;                  // 连续超时计数内部副本 / Internal timeout streak
    fNgRateInt      : REAL;                 // NG 率内部副本 [1] / Internal NG rate
    fNgLimEff       : REAL;                 // 钳位后 NG 率限 [1] / Clamped NG rate limit
    nWinEff         : INT;                  // 钳位后窗长 [个] / Clamped window length
    nMinEff         : INT;                  // 钳位后最小样本数 [个] / Clamped minimum samples
    nTripsEff       : INT;                  // 钳位后超时次数阈值 [次] / Clamped trip threshold
    bCfgBad         : BOOL;                 // 本拍组态非法 / Config illegal this scan
    bCfgLatch       : BOOL;                 // 组态故障锁存（复位沿清除）/ Config fault latch, cleared by reset edge
    bErrorInt       : BOOL;                 // 本拍故障置位累加（出口归并）/ Fault set accumulator of this scan
    bFirstScan      : BOOL := TRUE;         // 上电首扫标志 / First-scan flag
    nIdx            : INT;                  // 遍历索引 / Loop index
END_VAR
VAR CONSTANT
    DL_CH_WIN_MIN    : INT  := 2;     // NG 窗长下限 [个] / NG window floor
    DL_CH_WIN_MAX    : INT  := 64;    // NG 窗长上限 [个]，与数组维度一致 / NG window ceiling
    DL_CH_STREAK_MAX : INT  := 255;   // 超时计数饱和值 [次] / Timeout streak saturation
    DL_CH_RATE_NONE  : REAL := -1.0;  // NG 率不可发布哨兵 [1] / NG rate unpublishable sentinel
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：三沿三计时全部位于主体最前部
 *      Unconditional refresh: three edges and three timers at the very top
 *      TON 的 IN 全部为内部派生量（R40 家族口径），禁挂外部引脚原值
 *-----------------------------------------------------------------------------*)
fbTrigTrig(CLK := bTriggerOut);
fbTrigResult(CLK := bResultOk OR bResultNg);
fbTrigReset(CLK := bReset);

tonTrig(IN := bTrigOutstanding, PT := tTrigTimeout);
tonHb(IN := bHbRun, PT := tHeartbeatWin);
tonNg(IN := bNgExceeds, PT := tNgConfirm);

(* 未决快照：取 TON 判定所依据的那一拍状态，供同拍竞态判据（R275） *)
(* Outstanding snapshot taken at TON call time for the same-scan race *)
bTrigOutPrev := bTrigOutstanding;

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：计数与环形窗显式清零，健康落 eUnknown
 *      First-scan init: counters and ring cleared, health to eUnknown
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt := E_DL_CamHealthState.eIdle;
    eHealth   := E_DL_Ne107Status.eUnknown;
    FOR nIdx := 0 TO 63 DO
        abNgWin[nIdx] := FALSE;    // 环形窗显式清零 / Ring cleared explicitly
    END_FOR
    nNgWrite   := 0;
    nNgFill    := 0;
    nNgCount   := 0;
    nStreakInt := 0;
    fNgRateInt := DL_CH_RATE_NONE;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）+ 两级回退（R117）：非法钳回默认常量继续服务
 *      Config gate with two-level fallback: clamp to defaults, keep serving
 *      解除路径（R152 自证）：复位沿 AND 组态已改对
 *-----------------------------------------------------------------------------*)
bCfgBad := (tTrigTimeout <= T#0S) OR (tHeartbeatWin <= tTrigTimeout)
           OR (tNgConfirm <= T#0S) OR (nTimeoutTrips < 1)
           OR (nNgWindow < DL_CH_WIN_MIN) OR (nNgWindow > DL_CH_WIN_MAX)
           OR (nNgMinSamples < 1) OR (nNgMinSamples > nNgWindow)
           OR (fNgRateLimit < 0.0) OR (fNgRateLimit > 1.0) OR (fNgRateLimit <> fNgRateLimit);

IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF

(* 终审就地修 v1.0.1（R68）：解除路径（R152 自证可达）——复位沿 AND 组态非法条件
 * 全部消失即清锁存。原实现把锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 并不迁相至 eFault（只回 eIdle / 驻留），eFault 相不可达 -> 锁存永不可解，
 * 组件保护/监视功能一次性永久失效直至 PLC 重启（终审两式①）。
 * Clear path made provably reachable: reset edge with the illegal config gone. *)
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;           // 锁存解除 / Latch cleared
    uErrorId  := 16#0000_0000;    // 码位随解除归零 / Code cleared with the latch
END_IF

(* 两级回退取值（非法值钳回默认常量，服务不中断） *)
(* Two-level fallback values, clamped to defaults, service continues *)
IF (fNgRateLimit < 0.0) OR (fNgRateLimit > 1.0) OR (fNgRateLimit <> fNgRateLimit) THEN
    fNgLimEff := 1.0;            // 回退默认：上限 1（判据退化为不触发）/ Fallback: no-trip ceiling
ELSE
    fNgLimEff := fNgRateLimit;   // 合法直通 / Valid pass-through
END_IF

IF (nNgWindow < DL_CH_WIN_MIN) OR (nNgWindow > DL_CH_WIN_MAX) THEN
    nWinEff := 32;               // 回退默认窗长 / Fallback default window
ELSE
    nWinEff := nNgWindow;        // 合法直通 / Valid pass-through
END_IF

IF (nNgMinSamples < 1) OR (nNgMinSamples > nWinEff) THEN
    nMinEff := 5;                // 回退默认最小样本 / Fallback default minimum
ELSE
    nMinEff := nNgMinSamples;    // 合法直通 / Valid pass-through
END_IF

IF nTimeoutTrips < 1 THEN
    nTripsEff := 1;              // 回退：单次超时即计 / Fallback: single trip counts
ELSE
    nTripsEff := nTimeoutTrips;  // 合法直通 / Valid pass-through
END_IF

IF bCfgLatch THEN
    uErrorId  := 16#0003_0504;   // 故障级：组态非法已回退 / Fault: config illegal, fallback applied
    bErrorInt := TRUE;           // R45 配对 / Paired with the fault code
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜NG 率窗口统计（每拍重算）：写指针 / 样本数 / NG 计数 / 率
 *      NG ring statistics recomputed every scan
 *      挂起判据（R307）：有效样本数 < nMinEff 时 bNgExceeds 强制 FALSE（确认器停摆）
 *-----------------------------------------------------------------------------*)
bNgExceeds := FALSE;
fNgRateInt := DL_CH_RATE_NONE;

IF nNgFill >= nMinEff THEN
    fNgRateInt := UDINT_TO_REAL(DINT_TO_UDINT(nNgCount)) / UDINT_TO_REAL(DINT_TO_UDINT(nNgFill));  // 除子已闸 / Guarded denominator
    bNgSuspendedCalc := FALSE;   // 非挂起（占位变量见下方统一赋值）/ Not suspended, unified below
    IF fNgRateInt > fNgLimEff THEN
        bNgExceeds := TRUE;      // 超限（确认器计时窗口）/ Exceeds, confirmer timing
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *      同拍竞态（R275）：结果沿优先于超时 / 心跳到期（IF / ELSIF 结构性优先）
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_CamHealthState.eIdle:
        IF bEnable AND (NOT bCfgLatch) THEN
            eStateInt := E_DL_CamHealthState.eWatch;
            bHbRun    := TRUE;           // 入监视相即立心跳窗（从未返回结果也可判丢失）/ Arm heartbeat on entry
        END_IF

    E_DL_CamHealthState.eWatch:
        IF bCfgLatch OR (NOT bEnable) THEN
            eStateInt := E_DL_CamHealthState.eIdle;
        ELSE
            (* —— ① 结果沿（最高优先）或超时到期，二者同拍时结果胜（R275） —— *)
            (* Result edge outranks the timeout expiry in the same scan *)
            IF fbTrigResult.Q THEN
                bTrigOutstanding := FALSE;
                nStreakInt  := 0;
                bHbRun      := TRUE;
                bHeartbeatLost := FALSE;
                abNgWin[nNgWrite] := bResultNg;    // NG 样本入环 / NG sample into ring
                nNgWrite := nNgWrite + 1;
                IF nNgWrite >= nWinEff THEN
                    nNgWrite := 0;                 // 显式回卷 / Explicit wrap
                END_IF
                IF nNgFill < nWinEff THEN
                    nNgFill := nNgFill + 1;        // 填充推进 / Fill up
                ELSE
                    IF abNgWin[nNgWrite] THEN      // 覆盖前扣减最旧样本的 NG 贡献 / Decrement the oldest
                        nNgCount := nNgCount - 1;
                    END_IF
                END_IF
                IF bResultNg THEN
                    nNgCount := nNgCount + 1;      // NG 计数推进 / NG count up
                END_IF
            ELSIF tonTrig.Q AND bTrigOutPrev THEN
                (* 超时消化：以 TON 判定拍的未决快照为准，不吞新触发沿 *)
                (* Timeout consumed against the snapshot, never eats a new trigger *)
                bTrigOutstanding := FALSE;
                IF nStreakInt < DL_CH_STREAK_MAX THEN
                    nStreakInt := nStreakInt + 1;  // 计数推进（饱和）/ Streak up, saturating
                END_IF
                IF nStreakInt >= nTripsEff THEN
                    uErrorId := 16#0003_0402;      // 信息级：超时三连 / Info: timeout streak
                END_IF
            END_IF

            (* —— ② 触发沿独立消化（与上段并行，不互斥） —— *)
            (* Trigger edge digested independently *)
            IF fbTrigTrig.Q THEN
                bTrigOutstanding := TRUE;
            END_IF

            (* —— ③ 心跳到期：置丢失（结果沿已优先重立心跳窗） —— *)
            (* Heartbeat expiry: lost flag set, result edge re-arms first *)
            IF bHbRun AND tonHb.Q THEN
                bHbRun         := FALSE;
                bHeartbeatLost := TRUE;
                uErrorId       := 16#0003_0403;   // 信息级：心跳丢失 / Info: heartbeat lost
            END_IF

            (* —— ④ NG 确认：超限确认窗满 -> 保持型确认（挂起时 bNgExceeds 已 FALSE） —— *)
            (* NG confirmation: confirmed level when the window fills *)
            IF tonNg.Q THEN
                bNgConfirmed := TRUE;
                uErrorId     := 16#0003_0404;     // 信息级：NG 趋势确认 / Info: NG trend confirmed
            ELSIF NOT bNgExceeds THEN
                bNgConfirmed := FALSE;            // 回落清除 / Clear on recovery
            END_IF
        END_IF

    E_DL_CamHealthState.eFault:
        (* 兜底态：解除路径 = 复位沿 AND 组态已改对（R152） *)
        IF fbTrigReset.Q AND (NOT bCfgBad) THEN
            bCfgLatch := FALSE;
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_CamHealthState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：直接迁入兜底态并复用组态码（不隐式恢复） *)
        eStateInt := E_DL_CamHealthState.eFault;
        uErrorId  := 16#0003_0504;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜使能撤销复位统计（不置故障，规格明示）
 *      Enable withdrawal resets statistics without any fault
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR fbTrigReset.Q THEN
    nStreakInt := 0;             // 超时计数复位 / Streak reset
    nNgFill    := 0;             // 样本数复位 / Sample count reset
    nNgCount   := 0;             // NG 计数复位 / NG count reset
    nNgWrite   := 0;             // 写指针复位 / Write pointer reset
    bNgConfirmed := FALSE;       // NG 确认复位 / NG confirmation reset
    bHeartbeatLost := FALSE;     // 心跳丢失复位 / Heartbeat lost reset
    bTrigOutstanding := FALSE;   // 未决复位 / Outstanding reset
    bHbRun     := FALSE;         // 心跳窗复位 / Heartbeat window reset
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）：健康分级由三判据保持型派生
 *      Single output exit: health derived from the three level-held criteria
 *-----------------------------------------------------------------------------*)
nTimeoutStreak := nStreakInt;
fNgRate := fNgRateInt;
bNgSuspended := (nNgFill < nMinEff);

IF (eStateInt = E_DL_CamHealthState.eIdle) OR (eStateInt = E_DL_CamHealthState.eFault) THEN
    eHealth := E_DL_Ne107Status.eUnknown;        // 未使能 / 故障：未知 / Idle or fault: unknown
ELSIF bNgConfirmed THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq; // NG 趋势确认 / NG trend confirmed
ELSIF (nStreakInt >= nTripsEff) OR bHeartbeatLost THEN
    eHealth := E_DL_Ne107Status.eCheckFunction;  // 超时三连或心跳丢失 / Streak or heartbeat lost
ELSE
    eHealth := E_DL_Ne107Status.eOk;             // 全判据通过 / All criteria pass
END_IF

bError := bErrorInt OR (eStateInt = E_DL_CamHealthState.eFault);
eState := eStateInt;
END_FUNCTION_BLOCK
