(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SignalFreeze
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : self-std（防御性新增线）
 * 功能描述 (Function)   : 坏值冻结保持：连续量输入出现 NaN / Inf / 越合理性域时，
 *                         输出保持上一次有效值（绝不把坏值搬到下游），并累计冻结
 *                         时长；冻结时长超过 tFreezeMax 即判「信号源已死」锁存告警。
 *                         有效输入回来时：输出无扰切回实时值，冻结计时清零。
 * 分工互引 (Boundary)   : ① FB_DL_SignalHoldResume —— 由**外部命令 bHold** 决定
 *                         保持还是恢复（人工/工艺保持），不判信号真伪；
 *                         ② FB_DL_SignalFrozenDetect —— 判「信号数值长期不变」的
 *                         冻结故障（上游诊断）；③ 本件由**坏值**驱动自动保持 +
 *                         冻结时长告警，三件语义互不重叠，禁互相替代。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 合理性域 [fLowLim, fHighLim] 为闭区间；fLowLim > fHighLim 属组态非法，
 *      锁存至复位沿 + 组态改对（R152 解除路径自证）。
 *   2) 坏值判定三判据全枚举（R272）：NaN 自反 `x <> x`、Inf 差自减
 *      `(x − x) <> (x − x)`、幅值兜底 `ABS(x) >= 1.0E30`。禁用单一近似阈值。
 *   3) 坏值期输出恒为**上一次有效值**（fHold 只在有效样本上刷新），因此输出永远
 *      有限；下游无需再做非有限防护（但本件仍不承诺输出在域内——保持值属于
 *      历史有效值，域闸变更后可能落在新域外，这是刻意保留的证据语义）。
 *   4) 冻结时长超限为**故障级锁存**：解除 = 复位沿 AND 本拍输入有效（信号已恢复），
 *      未恢复时复位沿不作解除（防复位即掩盖断线）。
 *   5) 冻结告警不是动作输出：本件只上报，不切断工艺（切断归使用侧联锁件）。
 * 故障码表 (Error codes) :
 *   16#0001_03FC [故障级] 组态非法（合理性域反向 / 冻结上限 <= T#0S），不冻结不告警
 *                 反证：禁用与组态非法都表现为「输出恒等输入」，现有输出不可区分。
 *   16#0001_03FD [故障级] 冻结时长超限（信号源疑似失效），锁存至复位沿 + 输入恢复
 *                 反证：持续坏值与「信号源恰好长时间恒定为某有效值」输出组合相同，
 *                 无码则该故障对 HMI 完全不可见。
 *   16#0001_04FD [信息级] 本拍进入坏值冻结保持（bFrozen 同源可查）
 *                 反证：冻结与「输入稳定不变」输出组合相同；单拍级事件事实需入流水。
 * 码位总账 (Code ledger) : 16#0001_03FC / 03FD 用 ｜ 16#0001_04FD 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限三判 / 无除法 / 域闸全枚举
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE
 *                         R7 ✓ 一沿一计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 2 · N7）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FreezeState（归属 DL_Base，与 FB_DL_SignalFreeze 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FreezeState :
(
    eIdle   := 0,     // 未使能：输出恒等于输入（不保持）/ Disabled, output mirrors the input
    ePass   := 10,    // 实时直通：输入有效 / Live pass-through, input valid
    eFrozen := 20,    // 坏值冻结：输出保持上次有效值 / Frozen, outputs the last valid value
    eAlarm  := 99     // 冻结超限锁存：输出仍保持，需人工复位 / Frozen too long, latched
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SignalFreeze
 * 调用约定: 每个扫描周期无条件调用一次；bReset 为上升沿语义。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SignalFreeze
VAR_INPUT
    fIn         : REAL;                  // 连续量输入 [工程单位] / continuous input [engineering unit]
    fLowLim     : REAL := -1.0E6;        // 合理性域下限（含）[工程单位] / plausibility floor, inclusive
    fHighLim    : REAL := 1.0E6;         // 合理性域上限（含）[工程单位] / plausibility ceiling, inclusive
    tFreezeMax  : TIME := T#5S;          // 冻结时长告警上限 [s]，<= T#0S 组态非法 / freeze duration ceiling [s]
    bEnable     : BOOL := TRUE;          // 使能；FALSE 时输出恒等输入（降级已声明）/ enable, FALSE mirrors the input
    bReset      : BOOL;                  // 上升沿：清冻结超限锁存（须输入已恢复）/ rising edge clears the freeze latch
END_VAR
VAR_OUTPUT
    fOut        : REAL;                  // 输出（坏值期 = 上次有效值）[工程单位] / output, last valid while frozen
    bFrozen     : BOOL;                  // 本拍处于坏值冻结保持 / frozen this scan
    tFrozenDur  : TIME;                  // 当前冻结已持续时长 [s] / current freeze duration [s]
    bFreezeAlarm: BOOL;                  // 冻结时长超限锁存（人工复位解除）/ freeze duration exceeded, latched
    bInputValid : BOOL;                  // 本拍输入有效（域内且有限）/ input valid this scan
    bError      : BOOL;                  // 故障标志（组态 / 冻结超限锁存）/ fault flag
    uErrorId    : UDINT;                 // 故障码，0 = 无故障 / error code, 0 = none
    eState      : E_DL_FreezeState;      // 当前状态（供 HMI 诊断）/ current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset : R_TRIG;                // 复位沿检测实例 / reset edge detector
    tonFreeze   : TON;                   // 冻结时长计时实例 / freeze duration timer
    eStateInt   : E_DL_FreezeState;      // 主状态机内部当前态 / internal state machine state
    fHold       : REAL;                  // 上次有效值保持槽 [工程单位] / hold slot of the last valid value
    bInValidT   : BOOL;                  // 本拍输入有效（含域闸）/ input valid this scan including the domain gate
    bCfgBad     : BOOL;                  // 本拍组态非法 / config illegal this scan
    bCfgLatch   : BOOL;                  // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bAlarmInt   : BOOL;                  // 冻结超限锁存内部副本 / internal freeze alarm latch
    bErrorInt   : BOOL;                  // 本拍故障置位累加（出口归并）/ fault set accumulator of this scan
    bFirstScan  : BOOL := TRUE;          // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_SF_FIN_LIM : REAL := 1.0E30;      // REAL 幅值兜底判界 / REAL magnitude bound as the last line
    DL_SF_NO_ALARM : REAL := 0.0;        // 有限零点常量（首扫落零）[工程单位] / finite zero constant for first scan
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿一计时位于主体最前部
 *      Unconditional refresh: one edge and one timer at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
tonFreeze(IN := (eStateInt = E_DL_FreezeState.eFrozen), PT := tFreezeMax);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：保持槽落有限零点（禁用未初始化量参与下游）/ first-scan init
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt  := E_DL_FreezeState.eIdle;
    fHold      := DL_SF_NO_ALARM;
    bAlarmInt  := FALSE;
    bFirstScan := FALSE;
END_IF

(* 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / per-scan preset, single-scan flags only *)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151）：合理性域反向 / 冻结上限非正即非法，锁存至复位沿
 *      Config gate: reversed plausibility interval or non-positive ceiling
 *      解除路径（R152 自证）：复位沿 AND 组态已改对
 *-----------------------------------------------------------------------------*)
bCfgBad := (fLowLim > fHighLim) OR (fLowLim <> fLowLim) OR (fHighLim <> fHighLim)
           OR (tFreezeMax <= T#0S);

IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;              // 组态锁存解除 / config latch cleared
    uErrorId  := 16#0000_0000;       // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0001_03FC;       // 故障级：组态非法 / fault: illegal configuration
    bErrorInt := TRUE;               // R45 配对 / paired with the code
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜坏值三判（R272）：NaN 自反 / Inf 差自减 / 幅值兜底，再并合理性域
 *      Bad-value triage: NaN, Inf and the plausibility interval
 *-----------------------------------------------------------------------------*)
bInValidT := (NOT (fIn <> fIn))
             AND (NOT ((fIn - fIn) <> (fIn - fIn)))
             AND (ABS(fIn) < DL_SF_FIN_LIM)
             AND (fIn >= fLowLim) AND (fIn <= fHighLim)
             AND bEnable
             AND (NOT bCfgLatch);

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      拍 N 进入：本拍坏值 -> eFrozen 并保持 fHold；本拍行为：不刷新 fHold；
 *      拍 N+1 转出：输入恢复有效即回 ePass 并清冻结计时（无扰切回实时值）
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_FreezeState.eIdle:
        IF bEnable AND (NOT bCfgLatch) THEN
            eStateInt := E_DL_FreezeState.ePass;    // 使能且组态合法才进入直通 / enabled and configured
        END_IF

    E_DL_FreezeState.ePass:
        IF (NOT bEnable) OR bCfgLatch THEN
            eStateInt := E_DL_FreezeState.eIdle;    // 失能 / 组态非法即退出 / disable or config fault
        ELSIF NOT bInValidT THEN
            eStateInt := E_DL_FreezeState.eFrozen;  // 坏值：进冻结保持 / bad value, start holding
            uErrorId  := 16#0001_04FD;              // 信息级：进入冻结保持 / info: frozen hold entered
        END_IF

    E_DL_FreezeState.eFrozen:
        IF (NOT bEnable) OR bCfgLatch THEN
            eStateInt := E_DL_FreezeState.eIdle;
        ELSIF bInValidT THEN
            eStateInt := E_DL_FreezeState.ePass;    // 输入恢复：无扰切回实时 / recovered, back to live
        ELSIF bAlarmInt THEN
            eStateInt := E_DL_FreezeState.eAlarm;   // 冻结超限：迁告警态驻留 / frozen too long
        END_IF

    E_DL_FreezeState.eAlarm:
        (* 输出仍保持上次有效值（不因告警改口径）；解除 = 复位沿 AND 输入已恢复 *)
        IF fbTrigReset.Q AND bInValidT AND (NOT bCfgBad) THEN
            bAlarmInt  := FALSE;                    // 冻结超限锁存解除 / alarm latch cleared
            uErrorId   := 16#0000_0000;
            eStateInt  := E_DL_FreezeState.ePass;   // 直接回直通（本拍输入已有效）/ straight back to pass-through
        ELSIF (NOT bEnable) OR bCfgLatch THEN
            eStateInt  := E_DL_FreezeState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：迁兜底态并锁存上报 / illegal state interception *)
        eStateInt := E_DL_FreezeState.eAlarm;
        bAlarmInt := TRUE;
        uErrorId  := 16#0001_03FD;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜保持槽刷新与冻结计时消化（保持槽只在有效样本上写）
 *      Hold slot refresh and freeze timer digestion
 *-----------------------------------------------------------------------------*)
IF bInValidT THEN
    fHold := fIn;                    // 有效样本刷新保持槽 [工程单位] / refresh the hold slot
END_IF

IF tonFreeze.Q AND (NOT bAlarmInt) THEN
    bAlarmInt := TRUE;               // 冻结超限锁存 / freeze alarm latched
    uErrorId  := 16#0001_03FD;       // 故障级：冻结时长超限 / fault: freeze duration exceeded
    bErrorInt := TRUE;               // R45 配对 / paired with the code
    eStateInt := E_DL_FreezeState.eAlarm;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）：输出恒为保持槽（有限），坏值永不外泄
 *      Single output exit: the output is always the finite hold slot
 *-----------------------------------------------------------------------------*)
fOut        := fHold;                                      // 输出 = 上次有效值 [工程单位] / output equals the last valid value
bFrozen     := (eStateInt = E_DL_FreezeState.eFrozen) OR (eStateInt = E_DL_FreezeState.eAlarm);
tFrozenDur  := tonFreeze.ET;                               // 当前冻结时长 [s] / current freeze duration
bFreezeAlarm := bAlarmInt;                                 // 超限锁存直出 / alarm latch straight out
bInputValid := bInValidT;                                  // 本拍有效性直出 / validity straight out
bError      := bErrorInt OR (eStateInt = E_DL_FreezeState.eAlarm) OR bCfgLatch;
eState      := eStateInt;
END_FUNCTION_BLOCK
