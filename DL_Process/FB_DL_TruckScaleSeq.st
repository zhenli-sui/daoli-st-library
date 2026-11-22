(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TruckScaleSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.2
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library + DL_ 库内既有件，零厂商方言
 * 来源标签 (Source)     : self-std
 * 功能描述 (Function)   : 车辆过磅称重流程七态顺控：空载等待 -> 车辆上磅（到位
 *                         开关）-> 稳定窗（称重稳定判据，委托 FB_DL_SignalStatistics
 *                         统计内核，峰峰值 < 容差判稳）-> 读数锁存（皮重 / 毛重
 *                         配对）-> 下磅 -> 台账推进（8 条定长环形，写指针饱和）。
 *                         超时未稳定置码重测；防作弊窗（读数期间磅台扰动检测）；
 *                         毛重 < 皮重（亏吨）显式码不静默取负净重。
 * 委托清单 (Delegation) : FB_DL_SignalStatistics（DL_MathData，稳态窗口径次源，
 *                         实例化组合调用——峰峰值 fRange 即稳定判据核）
 * 配比约束 (R100)       : tStableTimeout 必须大于统计窗填满耗时（nStableSamples ×
 *                         任务周期），否则未满窗即被超时重测，稳定判据永不达成。
 * 遗留假设三句声明 (R95): ①代理值：稳定窗以「样本数 nStableSamples × 任务周期」
 *                         代理时间窗 tStableWin；②覆盖范围：任务周期已知且恒定的
 *                         调用场合；③覆盖不到的区间：任务周期漂移 / 变长场合由
 *                         tStableTimeout 超时重测兜底，最坏表现是判稳变慢而非误判。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 读数未锁存前下磅（bOnScale 在稳定 / 锁存相消失）-> 流程作废 + 台账不写入
 *      （信息级），统计窗清零重来。
 *   2) 防作弊窗：稳定相内磅台到位信号闪断视为扰动（车未完全上磅 / 人为干预），
 *      置信息级并回稳定相重测，杜绝在扰动读数上锁存。
 *   3) 毛重 < 皮重（亏吨）为显式信息级：净重置 0 出台账，绝不静默取负
 *      （负净重会污染库存对账，R81 还原方向不饱和口径同理）。
 *   4) 皮 / 毛配对以「皮重槽与毛重槽均已锁存」为准，不做车号强校验（车号仅入
 *      台账留痕）；配对完成后双槽清零迎接下一车。
 *   5) 称重值非有限属**运行时信号失效**，不是组态错误：自 v1.0.2 起拆为独立信号闸——
 *      本拍只判 NaN / Inf 并置信息级 16#0005_04DD，统计与判据一律使用上一次有效值
 *      快照（fWeightHold），不锁存、不置 bError、不迁 eFault；失效持续由稳定超时
 *      重测（04D9）兜底。判定拍与消费拍强制错开一拍（本拍判定 -> 下拍消费
 *      bWeightBad），杜绝同拍把脏值锁进皮毛槽。
 *   6) 组态闸（bCfgBad）自 v1.0.2 起只含**静态组态量**（容差 / 超时窗 / 窗样本数），
 *      运行时信号不得进入组态锁存路径（避免一拍 NaN 让磅房永久锁死，R152）。
 * 故障码表 (Error codes) :
 *   16#0005_03B2 [故障级] 稳定窗组态非法（容差 <= 0 / 超时 <= 0 / 窗样本数越域）
 *                 反证：回退后流程照常，码位是组态错误唯一可见出口。
 *   16#0005_04D6 [信息级] 未锁存先下磅，流程作废台账不写入
 *                 反证：作废后回空闲与「正常完成」输出组合不同但作废原因（司机
 *                 误操作 / 磅台故障）不可区分，码位承载事件事实。
 *   16#0005_04D7 [信息级] 亏吨（毛重 < 皮重），净重置 0 出台账
 *                 反证：净重 0 与「空车皮重恰好等于毛重」组合相同，码位区分
 *                 正常零载与亏吨异常。
 *   16#0005_04D8 [信息级] 读数期磅台扰动（防作弊窗触发），重测
 *                 反证：重测与「正常重来」输出组合相同，码位是防作弊事实唯一出口。
 *   16#0005_04D9 [信息级] 超时未稳定，清窗重测
 *                 反证：重测与防作弊重测输出组合相似（均回稳定相），码位区分
 *                 「称量不稳」与「磅台扰动」两种成因（R190）。
 *   16#0005_04DD [信息级] 称重信号非有限（NaN / Inf），保持上次有效值不锁存
 *                 反证：保持时 fWeightHold 不变，与「称重值恰好稳定不变」的输出组合
 *                 完全相同；无码则信号断线被误读为「读数极稳」而照常判稳锁存，
 *                 该误判在现有输出上不可观测（R90 反证成立，R69 点修④）。
 * 码位总账 (Code ledger) : 16#0005_03B2 用 ｜ 16#0005_04D6 / 04D7 / 04D8 / 04D9 / 04DD 用
 * 依赖     (Depends)    : FB_DL_SignalStatistics
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 + 库内委托件
 *                         R4 ✓ 域闸全枚举 / 计数饱和 / 浮点容差比较（fRange < 容差直比）
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 七态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 二沿二计时 + 统计委托件每拍无条件调用
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 3 · 目标 15）
 *   2026-11-22  v1.0.1  终审就地修①②③：组态锁存解除路径可达化 + 超时重测清窗单拍化 + 皮毛槽镜像输出复核
 *   2026-11-22  v1.0.2  R69 点修④：称重信号非有限（NaN）自组态闸拆出为独立信号闸——判定与
 *                       消费分两拍（本拍判 NaN 只置标志与信息码，下一拍才作用于判稳与挂起），
 *                       失效期保持上次有效值、不锁存、不置 bError
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ScaleSeqState（归属 DL_Process，与 FB_DL_TruckScaleSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ScaleSeqState :
(
    eIdle      := 0,    // 空载等待：无车在磅 / Idle, no truck on scale
    eOnScale   := 10,   // 车辆上磅确认：到位保持 / Truck on scale, arrival confirmed
    eStabilize := 20,   // 稳定窗：统计判稳 / Stabilising, statistics window
    eLatch     := 30,   // 读数锁存：皮 / 毛配对 / Latching, tare-gross pairing
    eOffScale  := 40,   // 下磅：等车辆离开 / Off scale, waiting for departure
    eDone      := 50,   // 台账推进完成拍 / Ledger advanced, one-shot
    eFault     := 99    // 组态锁存：流程拒绝 / Config latched, flow refused
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_TruckScaleSeq
 * 调用约定: 每个扫描周期无条件调用一次；bOnScale / bTareMode 为电平引脚。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TruckScaleSeq
VAR_INPUT
    fWeight       : REAL;                // 磅台称重值 [kg] / Scale weight [kg]
    bOnScale      : BOOL;                // 磅台到位开关（车辆在磅）/ Truck-on-scale limit switch
    bTareMode     : BOOL;                // 本次称量模式：TRUE = 皮重 / TRUE tare, FALSE gross
    uTruckId      : UINT;                // 车号 [号]，仅入台账留痕 / Truck id, ledger only
    nStableSamples: INT  := 32;          // 稳定统计窗样本数 [个]，域 2..64 / Stability window samples
    fStableTolKg  : REAL := 50.0;        // 稳定判据峰峰值容差 [kg] / Stability peak-to-peak tolerance [kg]
    tStableTimeout: TIME := T#30S;       // 稳定超时窗 [s]，须宽于窗填满耗时 / Stability timeout [s]
    bEnable       : BOOL := TRUE;        // 使能 / Enable
    bReset        : BOOL;                // 上升沿：清组态锁存与台账计数 / Rising edge: clear latches
END_VAR
VAR_OUTPUT
    eState       : E_DL_ScaleSeqState;   // 当前状态（供 HMI 诊断）/ Current state
    fTareLatched : REAL;                 // 当前皮重槽 [kg]，0 = 未锁存 / Current tare slot, 0 = unset
    fGrossLatched: REAL;                 // 当前毛重槽 [kg]，0 = 未锁存 / Current gross slot, 0 = unset
    fNetLast     : REAL;                 // 最近一票净重 [kg] / Last net weight [kg]
    nLedgerCount : INT;                  // 台账有效票数 [票]，0..8 / Ledger entry count
    bLedgerFull  : BOOL;                 // 台账已满回卷（最旧被覆盖）/ Ledger full, oldest overwritten
    bJudgeSuspended : BOOL;              // 稳定判据挂起（窗未满 / 称重值无效）/ Judge suspended
    bError       : BOOL;                 // 故障标志（组态锁存）/ Fault flag
    uErrorId     : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = none
END_VAR
VAR
    fbTrigReset  : R_TRIG;               // 复位沿检测实例 / Reset edge detector
    fbTrigOn     : R_TRIG;               // 上磅沿检测实例 / On-scale edge detector
    tonStableTo  : TON;                  // 稳定超时计时实例 / Stability timeout timer
    fbStat       : FB_DL_SignalStatistics; // 统计委托实例 / Statistics delegate
    eStateInt    : E_DL_ScaleSeqState;   // 主状态机内部当前态 / Internal state machine state
    auiTruck     : ARRAY[0..7] OF UINT;  // 台账车号环形 [号] / Ledger truck id ring
    afTareRing   : ARRAY[0..7] OF REAL;  // 台账皮重环形 [kg] / Ledger tare ring [kg]
    afGrossRing  : ARRAY[0..7] OF REAL;  // 台账毛重环形 [kg] / Ledger gross ring [kg]
    afNetRing    : ARRAY[0..7] OF REAL;  // 台账净重环形 [kg] / Ledger net ring [kg]
    nLedgerWrite : INT;                  // 台账写指针 [0..7] / Ledger write pointer
    uLedgerTotal : UDINT;                // 台账累计票数 [票]（回卷判据）/ Ledger total ever
    fTareInt     : REAL;                 // 皮重槽内部副本 [kg] / Internal tare slot
    fGrossInt    : REAL;                 // 毛重槽内部副本 [kg] / Internal gross slot
    fWeightSnap  : REAL;                 // 锁存读数快照 [kg] / Latched weight snapshot
    fWeightHold  : REAL;                 // 上次有效称重值快照 [kg]（信号失效期供统计）/ Last valid weight snapshot [kg]
    bWeightBadT  : BOOL;                 // 本拍称重信号非有限（NaN / Inf）/ Weight non-finite this scan
    bWeightBad   : BOOL;                 // 滞后一拍的信号失效标志（消费用）/ Delayed signal-invalid flag for consumption
    nWinEff      : INT;                  // 钳位后窗样本数 [个] / Clamped window samples
    fTolEff      : REAL;                 // 钳位后容差 [kg] / Clamped tolerance
    bStatClear   : BOOL;                 // 统计窗清零脉冲（单拍）/ Statistics clear pulse
    bCfgBad      : BOOL;                 // 本拍组态非法 / Config illegal this scan
    bCfgLatch    : BOOL;                 // 组态故障锁存 / Config fault latch
    bErrorInt    : BOOL;                 // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bToutPulse   : BOOL;                 // 超时清窗单拍已发标志（防每拍清窗死循环）/ Timeout clear issued flag
    bFirstScan   : BOOL := TRUE;         // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_TS_WIN_MIN  : INT  := 2;      // 窗样本数下限 [个]（统计件域）/ Window floor
    DL_TS_WIN_MAX  : INT  := 64;     // 窗样本数上限 [个]（统计件域）/ Window ceiling
    DL_TS_LEDGER   : INT  := 8;      // 台账深度 [票] / Ledger depth
    DL_TS_FIN_LIM  : REAL := 1.0E30; // REAL 有限幅值判界 / REAL finiteness bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：二沿一计时 + 统计委托件每拍调用
 *      Unconditional refresh: two edges, one timer, the stats delegate every scan
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigOn(CLK := bOnScale);
tonStableTo(IN := (eStateInt = E_DL_ScaleSeqState.eStabilize), PT := tStableTimeout);

fbStat(fIn := fWeightHold, bSample := TRUE, nWindow := nWinEff, bClear := bStatClear);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：台账与配对槽显式落零
 *      First-scan init: ledger and pairing slots cleared explicitly
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt    := E_DL_ScaleSeqState.eIdle;
    fTareInt     := 0.0;
    fGrossInt    := 0.0;
    fWeightSnap  := 0.0;
    fWeightHold  := 0.0;                 // 保持槽首扫落零 [kg] / Hold slot cleared on first scan
    bWeightBad   := FALSE;               // 滞后失效标志首扫落假 / Delayed invalid flag cleared
    nLedgerWrite := 0;
    uLedgerTotal := 0;
    bFirstScan   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照 / 台账
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt  := FALSE;
bStatClear := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）+ 两级回退（R117）
 *      Config gate with two-level fallback
 *      解除路径（R152 自证）：复位沿 AND 组态改对
 *      R69 点修④：组态闸只含静态组态量；称重信号非有限一律不进本闸（见段 4b）
 *-----------------------------------------------------------------------------*)
bCfgBad := (fStableTolKg <= 0.0) OR (fStableTolKg <> fStableTolKg)
           OR (tStableTimeout <= T#0S)
           OR (nStableSamples < DL_TS_WIN_MIN) OR (nStableSamples > DL_TS_WIN_MAX);

IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF

IF (fStableTolKg <= 0.0) OR (fStableTolKg <> fStableTolKg) THEN
    fTolEff := 50.0;                 // 回退默认容差 / Fallback default tolerance
ELSE
    fTolEff := fStableTolKg;         // 合法直通 / Valid pass-through
END_IF

IF (nStableSamples < DL_TS_WIN_MIN) OR (nStableSamples > DL_TS_WIN_MAX) THEN
    nWinEff := 32;                   // 回退默认窗长 / Fallback default window
ELSE
    nWinEff := nStableSamples;       // 合法直通 / Valid pass-through
END_IF

IF bCfgLatch THEN
    uErrorId  := 16#0005_03B2;       // 故障级：稳定窗组态非法 / Fault: config illegal
    bErrorInt := TRUE;
END_IF

(* 终审就地修 v1.0.1（R68①②）：解除路径（R152 自证可达）——复位沿 AND 组态非法
 * 条件消失即清锁存。原实现把组态锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 不迁相（只回 eIdle 驻留），eFault 相不可达 -> 锁存永不可解，磅房流程一次性
 * 永久死锁至 PLC 重启（终审两式①）。 *)
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;              // 锁存解除 / Latch cleared
    uErrorId  := 16#0000_0000;       // 码位随解除归零 / Code cleared with the latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4b｜信号闸（R69 点修④）：非有限只判不锁，判定拍与消费拍强制错开一拍
 *      Signal gate: non-finite is judged here and consumed one scan later
 *      拍 N：本拍判 bWeightBadT（NaN 自反 + Inf 差自减 + 幅值兜底），失效即置信息码
 *            04DD，**不写** fWeightHold、不锁存、不迁相；
 *      拍 N+1：bWeightBad 才被统计判据与 bJudgeSuspended 消费（错开一拍，防同拍
 *            把脏值锁进皮毛槽 / 判稳窗）。
 *-----------------------------------------------------------------------------*)
bWeightBadT := (fWeight <> fWeight)
               OR ((fWeight - fWeight) <> (fWeight - fWeight))
               OR (ABS(fWeight) >= DL_TS_FIN_LIM);
IF bWeightBadT THEN
    uErrorId := 16#0005_04DD;        // 信息级：信号非有限，保持上次有效值 / Info: non-finite, holding last valid
ELSE
    fWeightHold := fWeight;          // 有效样本刷新保持槽 [kg] / Refresh the hold slot with a valid sample
END_IF
(* 消费侧滞后镜像 bWeightBad 在主体末行统一刷新（见段 7 之后），保证「本拍判定、
 * 下拍消费」两拍分离，CASE 与判稳判据读到的永远是上一拍结论。 *)
(* The mirror bWeightBad is refreshed on the last body line, so every consumer reads the previous verdict *)

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *      同拍竞态（R275）：锁存相先消化本拍锁存，再消化下磅沿
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_ScaleSeqState.eIdle:
        IF bCfgLatch OR (NOT bEnable) THEN
            (* 组态 / 失能驻留：流程拒绝（降级语义已声明）/ Flow refused, declared *)
        ELSIF fbTrigOn.Q THEN
            bStatClear := TRUE;      // 新车进窗先清统计 / Clear stats for the new truck
            eStateInt  := E_DL_ScaleSeqState.eOnScale;
        END_IF

    E_DL_ScaleSeqState.eOnScale:
        IF NOT bOnScale THEN
            (* 读数未锁存前下磅：流程作废 + 台账不写入（信息级 0405） *)
            (* Departure before any latch: flow voided, ledger untouched *)
            bStatClear := TRUE;
            uErrorId   := 16#0005_04D6;   // 信息级：未锁存先下磅 / Info: departed unlatched
            eStateInt  := E_DL_ScaleSeqState.eIdle;
        ELSE
            eStateInt := E_DL_ScaleSeqState.eStabilize;   // 到位保持确认，进稳定窗 / Confirmed, to stabilise
        END_IF

    E_DL_ScaleSeqState.eStabilize:
        IF (NOT bOnScale) AND (NOT fbTrigOn.Q) THEN
            (* 防作弊窗：稳定相内到位信号消失 = 扰动（车未完全上磅 / 人为干预） *)
            (* Anti-cheat: on-scale dropped during stabilising is a disturbance *)
            bStatClear := TRUE;      // 清窗重测 / Clear and re-measure
            uErrorId   := 16#0005_04D8;   // 信息级：磅台扰动 / Info: disturbance
            eStateInt  := E_DL_ScaleSeqState.eIdle;   // 作废回空闲（未锁存不写台账）/ Voided
        ELSIF (fbStat.nCount >= nWinEff) AND (fbStat.fRange < fTolEff) THEN
            eStateInt := E_DL_ScaleSeqState.eLatch;   // 窗满且峰峰值达标 / Full window, range OK
        END_IF

    E_DL_ScaleSeqState.eLatch:
        IF (fWeight <> fWeight) OR ((fWeight - fWeight) <> (fWeight - fWeight))
           OR (ABS(fWeight) >= DL_TS_FIN_LIM) OR bWeightBad THEN
            (* 称重值非有限：拒绝锁存（保持槽不写），回稳定相由超时兜底 *)
            (* Non-finite weight: latch refused, back to stabilise *)
            bStatClear := TRUE;
            eStateInt  := E_DL_ScaleSeqState.eStabilize;
        ELSE
            fWeightSnap := fWeight;  // 读数锁存 / Latch the reading
            IF bTareMode THEN
                fTareInt := fWeightSnap;      // 皮重入槽 / Tare into slot
            ELSE
                fGrossInt := fWeightSnap;     // 毛重入槽 / Gross into slot
            END_IF
            IF (fTareInt > 0.0) AND (fGrossInt > 0.0) THEN
                WriteLedger();       // 皮毛双槽齐 -> 台账（私有方法）/ Pair complete, ledger write
            END_IF
            eStateInt := E_DL_ScaleSeqState.eOffScale;
        END_IF

    E_DL_ScaleSeqState.eOffScale:
        IF NOT bOnScale THEN
            eStateInt := E_DL_ScaleSeqState.eDone;   // 车辆离开 / Truck departed
        END_IF

    E_DL_ScaleSeqState.eDone:
        eStateInt := E_DL_ScaleSeqState.eIdle;       // 单拍完成相：下一拍回空闲 / One-shot, back to idle

    E_DL_ScaleSeqState.eFault:
        IF fbTrigReset.Q AND (NOT bCfgBad) THEN
            bCfgLatch := FALSE;      // 解除路径自证可达（R152）/ Clear path reachable
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_ScaleSeqState.eIdle;
        END_IF

    ELSE
        eStateInt := E_DL_ScaleSeqState.eFault;
        uErrorId  := 16#0005_03B2;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜超时未稳定消化：清窗重测（信息级），与防作弊重测成因码位互异（R190）
 *      Stability timeout: clear and re-measure, cause code distinct from 0407
 *-----------------------------------------------------------------------------*)
(* 终审就地修 v1.0.1（R68③）：超时重测单拍化。TON.Q 在 IN 保持期间恒真，原实现
 * 每拍 bStatClear := TRUE，统计窗被扫描周期级反复清零 -> 窗永不填满、判稳永不
 * 达成（超时同源挂死）。改为「一次超时只清一次窗」，重测窗得以重新累计。
 * Timeout clear is now a one-shot: an expired timer no longer wipes the window every scan. *)
IF tonStableTo.Q AND (eStateInt = E_DL_ScaleSeqState.eStabilize) AND (NOT bToutPulse) THEN
    bStatClear := TRUE;              // 清窗重测（单拍）/ Clear and re-measure, once
    uErrorId   := 16#0005_04D9;      // 信息级：超时重测 / Info: timeout re-measure
    bToutPulse := TRUE;              // 单拍标志置位 / Mark the one-shot as issued
END_IF
IF eStateInt <> E_DL_ScaleSeqState.eStabilize THEN
    bToutPulse := FALSE;             // 离开稳定相即撤销（下次进相可再清一次）/ Re-armed on phase exit
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（范式 P-05）：台账口径与挂起标志派生
 *      Single output exit: ledger derived values and the suspension flag
 *-----------------------------------------------------------------------------*)
IF uLedgerTotal > UDINT#8 THEN
    bLedgerFull := TRUE;             // 回卷覆盖（最旧被覆盖）/ Ring wrapped
END_IF
IF UDINT_TO_DINT(uLedgerTotal) < DINT#8 THEN
    nLedgerCount := DINT_TO_INT(UDINT_TO_DINT(uLedgerTotal));
ELSE
    nLedgerCount := 8;               // 深度即上限 [票] / Depth is the cap
END_IF

fTareLatched  := fTareInt;           // 皮重槽镜像输出（0 = 未锁存）/ Mirror tare slot out
fGrossLatched := fGrossInt;          // 毛重槽镜像输出（0 = 未锁存）/ Mirror gross slot out

bJudgeSuspended := (fbStat.nCount < nWinEff) OR bWeightBad
                   OR (eStateInt <> E_DL_ScaleSeqState.eStabilize);

bError := bErrorInt OR (eStateInt = E_DL_ScaleSeqState.eFault);
eState := eStateInt;
bWeightBad := bWeightBadT;           // 主体末行刷新滞后镜像（判定 -> 消费相隔一拍）/ Last line, one-scan delayed mirror
END_FUNCTION_BLOCK

(*------------------------------------------------------------------------------
 * 私有方法: WriteLedger —— 皮 / 毛配对台账唯一写入点（环形 + 写指针饱和）
 *      Private method: the single ledger write, ring with saturating pointer
 *      调用约定: 仅在 eLatch 相皮毛双槽齐拍调用一次；亏吨显式码在此落账
 *----------------------------------------------------------------------------*)
METHOD WriteLedger
VAR
    fNet : REAL;                     // 本票净重 [kg] / Net weight of this ticket
END_VAR

IF fGrossInt >= fTareInt THEN
    fNet := fGrossInt - fTareInt;    // 正常净重 / Normal net
ELSE
    fNet := 0.0;                     // 亏吨：净重置 0 不出负值（R81 口径）/ Tare exceeds gross: zero
    uErrorId := 16#0005_04D7;        // 信息级：亏吨 / Info: negative net
END_IF

auiTruck[nLedgerWrite]   := uTruckId;      // 车号入账 / Truck id into ledger
afTareRing[nLedgerWrite] := fTareInt;      // 皮重入账 / Tare into ledger
afGrossRing[nLedgerWrite] := fGrossInt;    // 毛重入账 / Gross into ledger
afNetRing[nLedgerWrite]  := fNet;          // 净重入账 / Net into ledger

fNetLast    := fNet;               // 最近净重出口留影 / Snapshot last net
fTareInt    := 0.0;                // 配对槽清零迎下一车 / Pair slots cleared
fGrossInt   := 0.0;

uLedgerTotal := uLedgerTotal + 1;  // 累计票数推进（回卷判据）/ Total tickets up
nLedgerWrite := nLedgerWrite + 1;  // 写指针推进 / Pointer up
IF nLedgerWrite >= DL_TS_LEDGER THEN
    nLedgerWrite := 0;              // 显式回卷 / Explicit wrap
END_IF

END_METHOD
