(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ClockDriftMonitor
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / SUB / TIME_TO_REAL），
 *                         SUB(DT,DT)->TIME 为 IEC 61131-3 标准函数表语义，零厂商方言
 * 来源标签 (Source)     : self-std
 * 功能描述 (Function)   : 本地 RTC 对外部标准钟的漂移率监视：每个采样窗分别求两钟
 *                         相对上一窗基线的时间增量，差值即窗内漂移量 [ms]，折算为
 *                         漂移率 [ms/h]（LREAL 承载防溢出），经 5 样本滑动窗中位滤波
 *                         后与漂移率上限比较产生告警；累计漂移超同步阈值置「需校钟」。
 *                         钟回拨（任一钟相对上窗基线负跳）单列「校钟事件」：只置事件
 *                         不计漂移、不置告警，并就地重立基线。
 *                         本件只监视不写钟——写钟归系统层，本件零输出侧钟操作。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 两钟均以 DT 引脚注入（零全局耦合）；DT 零值（DT#1970-01-01-00:00:00）视为
 *      未初始化，按故障级锁存，两钟各自独立码位（归因唯一 R190）。
 *   2) 窗增量以 TIME 承载：两钟相邻窗基线间隔超过 IEC TIME 正域上限（约 24.8 天，
 *      有符号口径）时增量回绕为巨值——以 3.0E9 ms（约 34.7 天）界作回绕哨兵，
 *      触发按「校钟事件」处理并重立基线，绝不把回绕值折算成漂移率。
 *   3) 首窗只立基线不发布漂移（无前窗可比），基线窗与运行窗状态分离。
 *   4) 漂移率与累计漂移的正负号语义：正 = 本地钟慢于外部标准钟（本地增量不足），
 *      负 = 本地钟快；告警与需校钟判据均取绝对值。
 *   5) SUB(DT,DT) 与 DT 比较（<）均为 IEC 61131-3 标准函数/运算语义。
 *      交付门槛：须在 CODESYS / TwinCAT / InoProShop 三平台各编译验证一次（R64）。
 * 故障码表 (Error codes) :
 *   16#0001_03EF [故障级] 外部标准钟无效（DT 零值未初始化），锁存至复位沿
 *                 反证：该场景下漂移率恒不发布（fDriftRateMsH 保持末值）、
 *                 状态 eFault——但 eFault 无法区分是哪只钟无效，需独立码位。
 *   16#0001_03F0 [故障级] 本地 RTC 无效（DT 零值未初始化），锁存至复位沿
 *                 反证：本地钟失效与外部钟失效对 eState / 漂移不发布等输出的影响组合完全一致，不可区分。
 *   16#0001_03F1 [故障级] 采样窗组态非法（<= T#0S），拒绝采样，锁存至复位沿
 *                 反证：窗非法时无窗脉冲（bWindowTick 恒 FALSE）与「使能关闭」
 *                 输出组合相同，无码不可区分。
 *   16#0001_04B3 [信息级] 中位滤波后漂移率超限（告警确认）
 *                 反证：bDriftAlarm 已是保持型位，但超限方向（快/慢）不可由
 *                 布尔位观测，码位承载「已确认超限」事实供 HMI 记录。
 *   16#0001_04B4 [信息级] 钟回拨 / 窗增量回绕，已按校钟事件重立基线
 *                 反证：回拨拍 bSyncEvent 为单拍脉冲，事件落账后即消失，
 *                 无码则历史回拨次数不可考。
 *   16#0001_04B5 [信息级] 累计漂移超同步阈值（需校钟确认）
 *                 反证：bNeedSync 为保持型位，码位用于事件流水归档，与告警码
 *                 分开承载两类不同事实（率超限 vs 累计超限）。
 *   非法状态拦截复用全库惯用码 16#0001_0005（不新占号）。
 * 码位总账 (Code ledger) : 16#0001_03EF / 03F0 / 03F1 用 ｜ 16#0001_04B3 / 04B4 / 04B5 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG / SUB / TIME_TO_REAL
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3（SUB/TIME_TO_REAL 均标准语义）
 *                         R4 ✓ 窗判零 / 折算分母 eps 闸 / 非有限双判（自反 + 差自减）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 二沿一计时主体最前部无条件刷新；窗 TON 自复位（IN 串自身 Q 取反）
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 1 · 目标 2）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（复位沿 + 三类非法源消失即清锁存，原 eFault 相不可达）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ClockDriftState（归属 DL_Base，与 FB_DL_ClockDriftMonitor 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ClockDriftState :
(
    eIdle     := 0,    // 未使能：全部告警与累计量冻结 / Disabled, alerts and accumulators frozen
    eBaseline := 10,   // 等待首窗基线：只存钟不发布 / Awaiting first window baseline, no publish
    eRun      := 20,   // 采样运行：每窗发布漂移率 / Running, drift rate published per window
    eFault    := 99    // 组态 / 钟源无效锁存 / Config or clock source latched invalid
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ClockDriftMonitor
 * 调用约定: 每个扫描周期无条件调用一次；两钟 DT 引脚须每拍刷新注入。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ClockDriftMonitor
VAR_INPUT
    dtExtStd         : DT;                     // 外部标准钟快照 [UTC]，零值 = 未初始化 / External standard clock, zero = uninitialized
    dtLocRtc         : DT;                     // 本地 RTC 快照 [本地]，零值 = 未初始化 / Local RTC snapshot, zero = uninitialized
    tSampleWin       : TIME  := T#30M;         // 采样窗时长 [min]，<= T#0S 组态非法 / Sampling window [min], <= 0 illegal
    fRateLimitMsH    : LREAL := 100.0;         // 漂移率告警上限 [ms/h] / Drift rate alarm limit [ms per hour]
    fSyncThresholdMs : LREAL := 5000.0;        // 累计漂移需校钟阈值 [ms] / Cumulative drift sync threshold [ms]
    bEnable          : BOOL  := TRUE;          // 监视使能 / Monitor enable
    bAckSync         : BOOL;                   // 上升沿：校钟完成确认，清累计漂移 / Rising edge: sync done, clears cumulative drift
    bReset           : BOOL;                   // 上升沿：清除钟源 / 组态故障锁存 / Rising edge: clears source and config latches
END_VAR
VAR_OUTPUT
    fDriftRateMsH : LREAL;                   // 中位滤波后漂移率 [ms/h] / Median filtered drift rate [ms per hour]
    fDriftRawMsH  : LREAL;                   // 本窗原始漂移率 [ms/h]，诊断 / Raw drift rate of the last window
    fCumDriftMs   : LREAL;                   // 累计漂移 [ms]，正 = 本地慢 / Cumulative drift [ms], positive = local slow
    bDriftAlarm   : BOOL;                    // 漂移率超限告警（保持型）/ Drift rate over limit alarm, level held
    bNeedSync     : BOOL;                    // 需校钟（累计超阈值，保持型）/ Sync required, level held
    bSyncEvent    : BOOL;                    // 校钟事件脉冲（回拨 / 回绕，单拍）/ Sync event pulse, single scan
    bWindowTick   : BOOL;                    // 采样窗脉冲（单拍，诊断）/ Window tick pulse, single scan, diagnostics
    bError        : BOOL;                    // 故障标志（钟源 / 组态锁存）/ Fault flag, source or config latched
    uErrorId      : UDINT;                   // 故障码，0 = 无故障 / Error code, 0 = none
    eState        : E_DL_ClockDriftState;    // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigAck     : R_TRIG;                  // 校钟确认沿检测实例 / Sync acknowledge edge detector
    fbTrigReset   : R_TRIG;                  // 复位沿检测实例 / Reset edge detector
    tonWin        : TON;                     // 采样窗计时（自复位）实例 / Sampling window timer, self resetting
    eStateInt     : E_DL_ClockDriftState;    // 主状态机内部当前态 / Internal state machine state
    dtExtPrev     : DT;                      // 上窗外部标准钟基线 / Previous window external baseline
    dtLocPrev     : DT;                      // 上窗本地钟基线 / Previous window local baseline
    tDeltaExt     : TIME;                    // 本窗外部钟增量 [ms] / External clock delta this window [ms]
    tDeltaLoc     : TIME;                    // 本窗本地钟增量 [ms] / Local clock delta this window [ms]
    fMsExt        : LREAL;                   // 外部钟增量实数化 [ms] / External delta as LREAL [ms]
    fMsLoc        : LREAL;                   // 本地钟增量实数化 [ms] / Local delta as LREAL [ms]
    fDriftMs      : LREAL;                   // 本窗漂移量 [ms] / Drift amount this window [ms]
    fWinHours     : LREAL;                   // 窗长折算小时 [h] / Window length in hours [h]
    fRateRaw      : LREAL;                   // 原始漂移率中间量 [ms/h] / Raw drift rate intermediate
    afRateRing    : ARRAY[0..4] OF LREAL;    // 漂移率滑动窗 [ms/h]，5 样本 / Drift rate sliding window, 5 samples
    afRateSort    : ARRAY[0..4] OF LREAL;    // 中位排序暂存区 / Median sort scratch
    nRingWrite    : INT;                     // 滑动窗写指针 [0..4] / Sliding window write pointer
    nRingFill     : INT;                     // 滑动窗已填样本数 [个] / Filled sample count
    nI            : INT;                     // 排序外层索引 / Sort outer index
    nJ            : INT;                     // 排序内层索引 / Sort inner index
    fKey          : LREAL;                   // 插入排序当前键值 / Insertion sort key
    fCumInt       : LREAL;                   // 累计漂移内部副本 [ms] / Internal cumulative drift [ms]
    bExtInvalid   : BOOL;                    // 本拍外部钟无效 / External clock invalid this scan
    bLocInvalid   : BOOL;                    // 本拍本地钟无效 / Local clock invalid this scan
    bWinInvalid   : BOOL;                    // 本拍采样窗组态非法 / Window config illegal this scan
    bFaultLatch   : BOOL;                    // 故障锁存（复位沿清除）/ Fault latch, cleared by reset edge
    bErrorInt     : BOOL;                    // 本拍故障置位累加（出口归并）/ Fault set accumulator of this scan
    bFirstScan    : BOOL := TRUE;            // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_CD_RING_CAP  : INT   := 5;            // 中位滤波窗容量 [个] / Median window capacity
    DL_CD_MEDIAN_MID: INT   := 2;            // 5 样本中位下标 / Median index of 5 samples
    DL_CD_WRAP_MS   : LREAL := 3.0E9;        // 窗增量回绕哨兵 [ms]，约 34.7 天 / Window delta wrap sentinel [ms]
    DL_CD_HOUR_MS   : LREAL := 3600000.0;    // 小时毫秒换算常数 [ms/h] / Hours to milliseconds factor
    DL_CD_EPS       : LREAL := 1.0E-9;       // 窗长折算判零容差 [h] / Window length zero tolerance [h]
    DL_CD_CUM_MAX   : LREAL := 1.0E12;       // 累计漂移饱和上限 [ms] / Cumulative drift saturation [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：二沿 + 窗计时（IN 串 bEnable AND NOT 自身 Q，自复位 R188）
 *      Unconditional refresh: two edges plus the self resetting window timer
 *-----------------------------------------------------------------------------*)
fbTrigAck(CLK := bAckSync);
fbTrigReset(CLK := bReset);
tonWin(IN := bEnable AND (NOT tonWin.Q), PT := tSampleWin);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：基线钟显式落零哨兵（与零值 = 未初始化闸共用判据，不误发故障）
 *      First-scan init: baselines forced to the zero sentinel, sharing the gate
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    dtExtPrev  := dtExtStd;
    dtLocPrev  := dtLocRtc;
    eStateInt  := E_DL_ClockDriftState.eBaseline;
    nRingWrite := 0;
    nRingFill  := 0;
    fCumInt    := 0.0;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍位统一预置，禁入锁存 / 快照 / 累计量
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt   := FALSE;
bSyncEvent  := FALSE;
bWindowTick := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 / R190 归因唯一）：两钟零值各自独立码位 + 窗判零
 *      Config gate: each clock gets its own code, plus the window zero gate
 *      DT 与 DT#1970-01-01-00:00:00 精确相等比较（离散类型直比合法，非浮点）
 *-----------------------------------------------------------------------------*)
bExtInvalid := (dtExtStd = DT#1970-01-01-00:00:00);
bLocInvalid := (dtLocRtc = DT#1970-01-01-00:00:00);
bWinInvalid := (tSampleWin <= T#0S);

IF bExtInvalid OR bLocInvalid OR bWinInvalid THEN
    bFaultLatch := TRUE;
END_IF

(* 终审就地修 v1.0.1（R68）：解除路径（R152 自证可达）——复位沿 AND 组态非法条件
 * 全部消失即清锁存。原实现把锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 并不迁相至 eFault（只回 eIdle / 驻留），eFault 相不可达 -> 锁存永不可解，
 * 组件保护/监视功能一次性永久失效直至 PLC 重启（终审两式①）。
 * Clear path made provably reachable: reset edge with the illegal config gone. *)
IF fbTrigReset.Q AND (NOT bExtInvalid) AND (NOT bLocInvalid) AND (NOT bWinInvalid) THEN
    bFaultLatch := FALSE;         // 锁存解除 / Latch cleared
    uErrorId    := 16#0000_0000;  // 码位随解除归零 / Code cleared with the latch
END_IF

IF bExtInvalid THEN
    uErrorId  := 16#0001_03EF;    // 故障级：外部标准钟无效 / Fault: external clock invalid
    bErrorInt := TRUE;
ELSIF bLocInvalid THEN
    uErrorId  := 16#0001_03F0;    // 故障级：本地 RTC 无效 / Fault: local RTC invalid
    bErrorInt := TRUE;
ELSIF bWinInvalid THEN
    uErrorId  := 16#0001_03F1;    // 故障级：采样窗组态非法 / Fault: window config illegal
    bErrorInt := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜校钟确认沿：清累计漂移（作用域声明：只清累计量，不清基线与告警）
 *      Sync acknowledge edge: clears the cumulative drift only
 *-----------------------------------------------------------------------------*)
IF fbTrigAck.Q THEN
    fCumInt := 0.0;               // 累计漂移归零（作用域：仅累计量）/ Clear cumulative only
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_ClockDriftState.eIdle:
        IF bEnable AND (NOT bFaultLatch) THEN
            dtExtPrev := dtExtStd;     // 重入先立新基线 / New baseline on re-entry
            dtLocPrev := dtLocRtc;
            eStateInt := E_DL_ClockDriftState.eBaseline;
        END_IF

    E_DL_ClockDriftState.eBaseline:
        (* eWait 类相退出条件 >= 2 条（R98）：窗脉冲沿 + 进相前置消失（失能 / 故障） *)
        IF bFaultLatch OR (NOT bEnable) THEN
            eStateInt := E_DL_ClockDriftState.eIdle;
        ELSIF tonWin.Q THEN
            dtExtPrev := dtExtStd;     // 首窗只立基线不发布 / First window stores baseline only
            dtLocPrev := dtLocRtc;
            eStateInt := E_DL_ClockDriftState.eRun;
        END_IF

    E_DL_ClockDriftState.eRun:
        IF bFaultLatch OR (NOT bEnable) THEN
            eStateInt := E_DL_ClockDriftState.eIdle;
        ELSIF tonWin.Q THEN
            bWindowTick := TRUE;       // 窗脉冲（诊断）/ Window tick for diagnostics
            IF (dtLocRtc < dtLocPrev) OR (dtExtStd < dtExtPrev) THEN
                (* 回拨（差值负跳）：只置校钟事件不计漂移不置告警，就地重立基线 *)
                (* Rollback: sync event only, no drift, no alarm, re-baseline *)
                bSyncEvent := TRUE;
                uErrorId   := 16#0001_04B4;
                dtExtPrev  := dtExtStd;
                dtLocPrev  := dtLocRtc;
            ELSE
                tDeltaExt := SUB(dtExtStd, dtExtPrev);   // 外部钟窗增量 / External window delta
                tDeltaLoc := SUB(dtLocRtc, dtLocPrev);   // 本地钟窗增量 / Local window delta
                fMsExt := TIME_TO_LREAL(tDeltaExt);
                fMsLoc := TIME_TO_LREAL(tDeltaLoc);
                IF (fMsExt >= DL_CD_WRAP_MS) OR (fMsLoc >= DL_CD_WRAP_MS) THEN
                    (* 窗增量回绕哨兵触发：按校钟事件处理，绝不折算漂移率 *)
                    (* Wrap sentinel hit: treated as a sync event, never scaled *)
                    bSyncEvent := TRUE;
                    uErrorId   := 16#0001_04B4;
                ELSE
                    fDriftMs  := fMsExt - fMsLoc;        // 窗内漂移量 [ms] / Window drift [ms]
                    fWinHours := TIME_TO_LREAL(tSampleWin) / DL_CD_HOUR_MS;
                    IF fWinHours > DL_CD_EPS THEN
                        fRateRaw := fDriftMs / fWinHours;  // 折算漂移率 [ms/h]，分母已闸 / Rate, guarded denominator
                        IF (fRateRaw <> fRateRaw) OR ((fRateRaw - fRateRaw) <> (fRateRaw - fRateRaw)) THEN
                            (* 非有限兜底三件套（R258）：冻结发布 + 故障码 + bError + 不发布 *)
                            fRateRaw  := 0.0;
                            uErrorId  := 16#0001_0005;
                            bErrorInt := TRUE;
                        ELSE
                            fDriftRawMsH := fRateRaw;
                            fDriftRateMsH := MedianOfRing(fRateRaw);  // 中位滤波委托 / Median via private method
                            IF ABS(fDriftRateMsH) > fRateLimitMsH THEN
                                bDriftAlarm := TRUE;           // 告警置位（保持型）/ Level alarm set
                                uErrorId    := 16#0001_04B3;   // 信息级：率超限确认 / Info: rate confirmed
                            ELSIF ABS(fDriftRateMsH) <= fRateLimitMsH THEN
                                bDriftAlarm := FALSE;          // 回落清除（与阈值同点，无回差）/ Clear on recovery
                            END_IF
                            IF ABS(fCumInt) < DL_CD_CUM_MAX THEN
                                fCumInt := fCumInt + fDriftMs; // 累计推进（饱和守卫）/ Accumulate, guarded
                            END_IF
                            IF ABS(fCumInt) > fSyncThresholdMs THEN
                                bNeedSync := TRUE;             // 需校钟置位 / Sync required set
                                uErrorId  := 16#0001_04B5;     // 信息级：累计超限确认 / Info: cumulative confirmed
                            ELSE
                                bNeedSync := FALSE;            // 确认沿已归零后回落清除 / Clear after ack
                            END_IF
                        END_IF
                    END_IF
                END_IF
                dtExtPrev := dtExtStd;     // 窗尾统一刷新基线 / Baselines refreshed at window tail
                dtLocPrev := dtLocRtc;
            END_IF
        END_IF

    E_DL_ClockDriftState.eFault:
        (* 解除路径（R152 自证可达）：复位沿 AND 三类非法源全部消失 *)
        IF fbTrigReset.Q AND (NOT bExtInvalid) AND (NOT bLocInvalid) AND (NOT bWinInvalid) THEN
            bFaultLatch := FALSE;
            bDriftAlarm := FALSE;
            bNeedSync   := FALSE;
            uErrorId    := 16#0000_0000;
            eStateInt   := E_DL_ClockDriftState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：不做隐式恢复，直接锁存上报 *)
        eStateInt := E_DL_ClockDriftState.eFault;
        uErrorId  := 16#0001_0005;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
fCumDriftMs := fCumInt;
bError := bErrorInt OR (eStateInt = E_DL_ClockDriftState.eFault);
eState := eStateInt;
END_FUNCTION_BLOCK

(*------------------------------------------------------------------------------
 * 私有方法: MedianOfRing —— 滑动窗写入 + 插入排序取中位（5 样本固定容量，无死循环风险）
 *      Private method: ring write plus insertion sort median over 5 fixed slots
 *      调用约定: 仅在 eRun 相窗脉冲拍调用；两层循环边界均为常量，开闭词配对
 *----------------------------------------------------------------------------*)
METHOD MedianOfRing : LREAL
VAR_INPUT
    fNew : LREAL;    // 本窗新样本 [ms/h] / New sample of this window [ms per hour]
END_VAR

afRateRing[nRingWrite] := fNew;                       // 新样本入环 / New sample into the ring
nRingWrite := nRingWrite + 1;
IF nRingWrite >= DL_CD_RING_CAP THEN
    nRingWrite := 0;                                  // 显式回卷 / Explicit wrap
END_IF
IF nRingFill < DL_CD_RING_CAP THEN
    nRingFill := nRingFill + 1;                       // 填充计数推进 / Fill count up
END_IF

IF nRingFill < 3 THEN
    MedianOfRing := fNew;    // 样本不足 3 个：中位未定义，直通新样本（R307 挂起语义）/ Fewer than 3 samples: pass through
    RETURN;
END_IF

FOR nI := 0 TO (nRingFill - 1) DO                     // 复制有效区到排序暂存 / Copy valid span
    afRateSort[nI] := afRateRing[nI];
END_FOR

FOR nI := 1 TO (nRingFill - 1) DO                     // 插入排序（升序）/ Insertion sort ascending
    fKey := afRateSort[nI];
    nJ  := nI - 1;
    WHILE (nJ >= 0) AND (afRateSort[nJ] > fKey) DO    // 内层右移 / Inner shift right
        afRateSort[nJ + 1] := afRateSort[nJ];
        nJ := nJ - 1;
    END_WHILE
    afRateSort[nJ + 1] := fKey;
END_FOR

MedianOfRing := afRateSort[DL_CD_MEDIAN_MID];         // 5 样本中位 = 排序后第 2 位 / Median of five

END_METHOD
