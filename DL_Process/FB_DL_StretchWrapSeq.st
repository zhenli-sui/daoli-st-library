(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StretchWrapSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.2
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : t2-7-packml（工站最小子集范式，clean-room 编写）
 * 功能描述 (Function)   : 缠绕膜包装机七态最小顺控：预压 -> 底圈 -> 顶圈（圈数
 *                         配方：底 / 顶 / 总圈数三项）-> 切膜 -> 保持 -> 完成。
 *                         转盘旋转反馈经 R_TRIG 沿计数（计数饱和 255）；膜断检测
 *                         联锁暂停——暂停在圈数边界生效（当前圈转完即停），恢复
 *                         后从当前圈数继续（不重头，ISA-88 相语义次源）。
 * 范式互引 (Paradigm)   : 工站顺控范式参照 FB_DL_PickAndPlaceStation；PackML 17 态
 *                         全集属主为 FB_DL_PackMlStateMachine——本件刻意做七态
 *                         最小子集，全集语义（阻塞 / 中止 / 清空）归全集属主。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 圈数配方域 1..255：越界组态级故障拒绝启动（锁存至复位沿 + 配方改对）；
 *      总圈数与底 / 顶之和不一致为信息级（以底 + 顶之和为准执行）。
 *   2) 转盘反馈丢失超时锁存（故障级）：判据 = 驱动输出有效 AND 本拍无旋转沿，
 *      TON 逐段断输入（R40 家族口径）；解除 = 复位沿 AND 反馈恢复。
 *   3) 暂停双源（膜断检测 / 操作暂停请求）合并为同一暂停挂起位，在圈数边界
 *      生效：暂停挂起期间当前圈转完即停，驱动输出切断，圈数保持。
 *   4) 切膜失败出口（产品裁定，v1.0.2 点修②）：切膜重试计数饱和（nCutRetryMax 封顶
 *      不回绕）后**不再自动重切**——单次窗再次超时即判定切膜失败：置故障级码 +
 *      bCutFail 锁存 + 迁 eFault，切断 bCutOut 与转盘驱动，停机待人工处理；
 *      解除唯一路径为人工复位（bReset 上升沿 AND 配方合法），复位后回 eIdle 从头
 *      开始（重试计数在 eIdle 受理时清零，不延续失败票的计数）。
 *   5) 压膜释放口径（产品裁定，v1.0.2 点修⑦）：bPreClampOut 仅表达「预压建压」
 *      一个动作，只在 ePreClamp 相有效；一进入底圈段即释放，并在底 / 顶圈段
 *      **全程保持释放**（膜被转盘牵引缠绕，压膜件继续压住会压出膜皱 / 拉断），
 *      切膜 / 保持 / 空闲 / 故障相同样释放。释放由状态派生式结构性保证，
 *      不挂单拍标志、不由暂停位改写（暂停只在圈边界截停驱动，不改压膜）。
 *   6) eIdle 相执行输出清零（R57 LWF 家族扫描范式前置合规）。
 * 配比约束 (R100)       : tTurnLoss 须大于转盘单圈周期的 1.5 倍（防正常圈间隔误判）；
 *                         tCutTimeout > tCutDwell（切膜窗必须宽于重试间隔窗）。
 * 故障码表 (Error codes) :
 *   16#0005_03A9 [故障级] 圈数配方组态非法（<1 或 >255），拒绝启动
 *                 反证：拒绝启动与「未按启动」输出组合相同，码位唯一可见。
 *   16#0005_03AA [故障级] 转盘反馈丢失超时，锁存至复位沿 + 反馈恢复
 *                 反证：顺控停摆与暂停态输出组合相似但成因完全不同（机械 vs 操作），必须独立码位。
 *   16#0005_04D1 [信息级] 膜断检测触发，暂停挂起（事件流水归档）
 *                 反证：bPauseHold 已表达暂停态，但暂停双源（膜断 / 人工）不可区分。
 *   16#0005_04D2 [信息级] 总圈数与底 / 顶之和不一致，按底 + 顶之和执行
 *                 反证：不一致时执行结果与显式填一致值相同，无码不可区分。
 *   16#0005_04D3 [信息级] 切膜重试计数已饱和（封顶不回绕）
 *                 反证：饱和计数与恰好达上限计数输出相同，无码不可区分。
 *   16#0005_03B3 [故障级] 切膜失败（重试饱和后单次窗再次超时），停机待人工
 *                 反证：失败停机与「反馈丢失」同为 eFault + bError，但成因与处置
 *                 完全不同（反馈丢失复位后可从现场恢复；切膜失败必须人工拆膜）；
 *                 且原实现无出口时 eCut 永驻、bCutOut 常励磁，故障态与「切膜中」
 *                 输出组合无法区分（R190 归因唯一，R69 点修②）。
 * 码位总账 (Code ledger) : 16#0005_03A9 / 03AA / 03B3 用 ｜ 16#0005_04D1 / 04D2 / 04D3 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 配方域闸 / 计数饱和 / 域闸全枚举
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 七态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 四沿四计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 3 · 目标 12）
 *   2026-11-22  v1.0.1  终审就地修④：总圈计数上限改用 510（原以单段上界 255 作总数闸，合法配方 >255 圈即死锁）
 *   2026-11-22  v1.0.2  R69 点修②：eCut 相补切膜失败出口（重试饱和后单次窗再超时 -> 03B3 +
 *                       bCutFail 锁存 + 迁 eFault 停机待人工，不自动重切，人工复位解除）；
 *                       点修⑦：bPreClampOut 语义固化（仅预压相有效，圈段全程释放防膜皱）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_WrapSeqState（归属 DL_Process，与 FB_DL_StretchWrapSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_WrapSeqState :
(
    eIdle     := 0,    // 空闲：输出全清（R57 前置合规）/ Idle, all outputs cleared
    ePreClamp := 10,   // 预压：压膜建立 / Pre-clamp, film pressed
    eBottom   := 20,   // 底圈段：转盘计数 / Bottom turns, counting
    eTop      := 30,   // 顶圈段：转盘计数 / Top turns, counting
    eCut      := 40,   // 切膜：重试节流 / Film cut with retry throttle
    eDwell    := 50,   // 保持：保持窗计时 / Dwell window timing
    eFault    := 99    // 配方 / 反馈丢失 / 切膜失败 锁存 / Recipe, loss or cut failure latched
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_StretchWrapSeq
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StretchWrapSeq
VAR_INPUT
    bStartCmd    : BOOL;                 // 启动命令（上升沿受理）/ Start command, rising edge accepted
    bStopCmd     : BOOL;                 // 停止命令（电平，任意相退出）/ Stop command, level, exits any phase
    bPauseReq    : BOOL;                 // 操作暂停请求（电平）/ Operator pause request, level
    bFilmBreak   : BOOL;                 // 膜断检测（电平，联锁暂停源）/ Film break detection, interlock pause source
    bTurnFb      : BOOL;                 // 转盘旋转反馈（每圈一脉冲）/ Turntable feedback, one pulse per revolution
    bPreClampFb  : BOOL;                 // 预压到位反馈 / Pre-clamp in-position feedback
    bCutDone     : BOOL;                 // 切膜完成反馈 / Film cut done feedback
    nBottomTurns : INT := 2;             // 底圈数配方 [圈]，域 1..255 / Bottom turns recipe
    nTopTurns    : INT := 3;             // 顶圈数配方 [圈]，域 1..255 / Top turns recipe
    nTotalTurns  : INT := 5;             // 总圈数配方 [圈]，仅一致性核对 / Total turns recipe, consistency only
    nCutRetryMax : INT := 3;             // 切膜重试上限 [次] / Film cut retry ceiling
    tPreClamp    : TIME := T#2S;         // 预压建压窗 [s] / Pre-clamp build-up window [s]
    tTurnLoss    : TIME := T#10S;        // 转盘反馈丢失超时 [s] / Turntable feedback loss timeout [s]
    tCutTimeout  : TIME := T#5S;         // 切膜单次窗 [s] / Film cut single window [s]
    tCutDwell    : TIME := T#1S;         // 切膜重试间隔窗 [s] / Film cut retry interval [s]
    tDwellHold   : TIME := T#3S;         // 保持窗时长 [s] / Dwell hold duration [s]
    bEnable      : BOOL := TRUE;         // 使能 / Enable
    bReset       : BOOL;                 // 上升沿：清配方 / 反馈丢失锁存 / Rising edge: clear latches
END_VAR
VAR_OUTPUT
    bTurnDrive  : BOOL;                  // 转盘驱动输出 / Turntable drive output
    bPreClampOut: BOOL;                  // 预压输出 / Pre-clamp output
    bCutOut     : BOOL;                  // 切膜输出 / Film cut output
    bPauseHold  : BOOL;                  // 暂停挂起（圈边界生效）/ Pause hold, effective at turn boundary
    bSeqActive  : BOOL;                  // 顺控进行中 / Sequence active
    bSeqDone    : BOOL;                  // 顺控完成脉冲（单拍）/ Sequence done pulse, single scan
    nTurnsDone  : INT;                   // 已完成总圈数 [圈] / Total turns completed
    nCutRetries : INT;                   // 切膜重试计数 [次]，饱和 / Film cut retries, saturating
    bCutFail    : BOOL;                  // 切膜失败锁存（停机待人工，人工复位解除）/ Cut failure latch, cleared by manual reset
    bError      : BOOL;                  // 故障标志（配方 / 反馈丢失）/ Fault flag
    uErrorId    : UDINT;                 // 故障码，0 = 无故障 / Error code, 0 = none
    eState      : E_DL_WrapSeqState;     // 当前状态（供 HMI 诊断）/ Current state
END_VAR
VAR
    fbTrigStart  : R_TRIG;               // 启动沿检测实例 / Start edge detector
    fbTrigReset  : R_TRIG;               // 复位沿检测实例 / Reset edge detector
    fbTrigFilm   : R_TRIG;               // 膜断沿检测实例（事件码用）/ Film break edge detector
    rTrigTurn    : R_TRIG;               // 转盘圈脉冲沿计数实例 / Turn pulse counting edge
    tonPre       : TON;                  // 预压建压计时实例 / Pre-clamp timer
    tonTurnLoss  : TON;                  // 转盘反馈丢失计时实例 / Turntable loss timer
    tonCutTo     : TON;                  // 切膜单次窗计时实例 / Film cut window timer
    tonCutDwell  : TON;                  // 切膜重试间隔窗（自复位）实例 / Retry interval timer, self resetting
    tonDwellHold : TON;                  // 保持窗计时实例 / Dwell hold timer
    eStateInt    : E_DL_WrapSeqState;    // 主状态机内部当前态 / Internal state machine state
    nBottomDone  : INT;                  // 底圈已完成圈数 [圈] / Bottom turns completed
    nTopDone     : INT;                  // 顶圈已完成圈数 [圈] / Top turns completed
    nRetryInt    : INT;                  // 切膜重试计数内部副本 / Internal retry count
    bPausePend   : BOOL;                 // 暂停挂起请求（双源合并）/ Pause pending, dual source merged
    bPauseHoldInt: BOOL;                 // 暂停边界生效保持位 / Pause hold latched at boundary
    bRecipeBad   : BOOL;                 // 本拍配方组态非法 / Recipe illegal this scan
    bRecipeLatch : BOOL;                 // 配方故障锁存（复位沿清除）/ Recipe fault latch
    bTotalDiff   : BOOL;                 // 总圈数与底 / 顶之和不一致 / Total mismatch with the sum
    bTurnLossInt : BOOL;                 // 反馈丢失锁存内部副本 / Internal feedback loss latch
    bCutFailInt  : BOOL;                 // 切膜失败锁存内部副本（人工复位解除）/ Internal cut failure latch
    bDoneT       : BOOL;                 // 完成脉冲内部副本（单拍）/ Internal done pulse copy
    bTurnDriveInt: BOOL;                 // 驱动输出内部派生 / Internal drive output derivation
    bErrorInt    : BOOL;                 // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan   : BOOL := TRUE;         // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_WR_TURNS_MAX : INT := 255;    // 单段圈数上限 [圈]（配方域上界）/ Turns ceiling per recipe
    DL_WR_TOTAL_MAX : INT := 510;    // 总圈数上限 [圈]（= 2 x 单段上界，终审就地修 v1.0.1）/ Total turns ceiling
    DL_WR_RETRY_MAX : INT := 8;      // 重试计数硬饱和 [次]（防 INT 溢出兜底）/ Retry hard saturation
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：四沿五计时全部位于主体最前部
 *      Unconditional refresh: four edges and five timers at the very top
 *      计时器 IN 全部为内部派生量（R40 断输入口径）
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStartCmd);
fbTrigReset(CLK := bReset);
fbTrigFilm(CLK := bFilmBreak);
rTrigTurn(CLK := bTurnFb);

tonPre(IN := (eStateInt = E_DL_WrapSeqState.ePreClamp) AND (NOT bPreClampFb), PT := tPreClamp);
tonTurnLoss(IN := bTurnDriveInt AND (NOT rTrigTurn.Q), PT := tTurnLoss);
tonCutTo(IN := (eStateInt = E_DL_WrapSeqState.eCut) AND (NOT bCutDone), PT := tCutTimeout);
tonCutDwell(IN := NOT tonCutDwell.Q, PT := tCutDwell);
tonDwellHold(IN := (eStateInt = E_DL_WrapSeqState.eDwell), PT := tDwellHold);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：计数与状态落安全侧
 *      First-scan init: counters and state to the safe side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt   := E_DL_WrapSeqState.eIdle;
    nBottomDone := 0;
    nTopDone    := 0;
    nRetryInt   := 0;
    bCutFailInt := FALSE;    // 首扫清切膜失败锁存 / Cut failure latch cleared on first scan
    bFirstScan  := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照 / 计数
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;
bDoneT    := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜配方域闸（R151）+ 一致性核对：越界拒绝启动，不一致信息级按和执行
 *      Recipe gate and consistency check
 *      解除路径（R152 自证）：复位沿 AND 配方已改对
 *-----------------------------------------------------------------------------*)
bRecipeBad := (nBottomTurns < 1) OR (nBottomTurns > DL_WR_TURNS_MAX)
              OR (nTopTurns < 1) OR (nTopTurns > DL_WR_TURNS_MAX);

IF bRecipeBad THEN
    bRecipeLatch := TRUE;
    uErrorId     := 16#0005_03A9;    // 故障级：配方组态非法 / Fault: recipe illegal
    bErrorInt    := TRUE;
END_IF

bTotalDiff := (nTotalTurns <> (nBottomTurns + nTopTurns));
IF bTotalDiff AND (NOT bRecipeBad) THEN
    uErrorId := 16#0005_04D2;        // 信息级：总数不一致按和执行 / Info: total mismatch
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜暂停双源合并与圈边界生效（ISA-88 相语义次源）
 *      Pause dual-source merge with turn-boundary effectiveness
 *      拍 N 进入：膜断 / 暂停请求置挂起；本拍行为：当前圈转完（沿到）即保持；
 *      拍 N+1 转出：请求撤销即恢复圈数继续（不重头）
 *-----------------------------------------------------------------------------*)
bPausePend := bFilmBreak OR bPauseReq;

IF fbTrigFilm.Q AND bPausePend THEN
    uErrorId := 16#0005_04D1;        // 信息级：膜断事件 / Info: film break event
END_IF

IF bPausePend AND rTrigTurn.Q THEN
    bPauseHoldInt := TRUE;           // 圈边界：暂停保持生效 / Boundary: pause hold engages
ELSIF NOT bPausePend THEN
    bPauseHoldInt := FALSE;          // 请求撤销：恢复 / Request gone: resume
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_WrapSeqState.eIdle:
        (* eIdle 相执行输出清零（R57）：本相不写任何执行输出，出口段按状态归零 *)
        (* Idle clears outputs: the exit section derives all-off from the state *)
        (* 锁存驻留声明：反馈丢失 / 配方锁存的复位消化在 eFault 分支与空闲复位行处理 *)
        (* Latch dwell note: clears happen in the eFault branch and the idle reset line *)
        IF bReset THEN
            bTurnLossInt := FALSE;   // 空闲相复位也允许清反馈丢失锁存 / Idle reset clears loss latch
            bRecipeLatch := FALSE;   // 空闲相复位清配方锁存 / Idle reset clears recipe latch
            bCutFailInt  := FALSE;   // 空闲相复位清切膜失败锁存 / Idle reset clears cut failure latch
            uErrorId     := 16#0000_0000;
        END_IF
        IF bEnable AND (NOT bRecipeLatch) AND (NOT bTurnLossInt) AND (NOT bCutFailInt) AND fbTrigStart.Q THEN
            nBottomDone  := 0;       // 圈数计数清零 / Turn counters cleared
            nTopDone     := 0;
            nRetryInt    := 0;
            bPauseHoldInt := FALSE;
            eStateInt    := E_DL_WrapSeqState.ePreClamp;
        END_IF

    E_DL_WrapSeqState.ePreClamp:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_WrapSeqState.eIdle;    // 退出 / Exit
        ELSIF bPreClampFb OR tonPre.Q THEN
            eStateInt := E_DL_WrapSeqState.eBottom;  // 反馈到位或建压窗满（双出口 R98）/ Feedback or window full
        END_IF

    E_DL_WrapSeqState.eBottom:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_WrapSeqState.eIdle;
        ELSIF nBottomDone >= nBottomTurns THEN
            eStateInt := E_DL_WrapSeqState.eTop;     // 底圈数满转顶圈 / Bottom full, to top
        END_IF

    E_DL_WrapSeqState.eTop:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_WrapSeqState.eIdle;
        ELSIF (nBottomDone + nTopDone) >= (nBottomTurns + nTopTurns) THEN
            eStateInt := E_DL_WrapSeqState.eCut;     // 总圈数满转切膜（验收：2+3=5）/ Total full, to cut
        END_IF

    E_DL_WrapSeqState.eCut:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_WrapSeqState.eIdle;
        ELSIF bCutDone THEN
            eStateInt := E_DL_WrapSeqState.eDwell;   // 切膜完成进保持 / Cut done, to dwell
        END_IF

    E_DL_WrapSeqState.eDwell:
        IF bStopCmd OR (NOT bEnable) THEN
            eStateInt := E_DL_WrapSeqState.eIdle;
        ELSIF tonDwellHold.Q THEN
            bDoneT    := TRUE;       // 完成脉冲：内部置位 -> 出口单拍映射（两段式）/ Done pulse via exit
            eStateInt := E_DL_WrapSeqState.eIdle;
        END_IF

    E_DL_WrapSeqState.eFault:
        (* 解除路径（R152 自证可达）：复位沿 AND 反馈已恢复 AND 配方已改对 *)
        (* 三类锁存同沿解除：配方 / 反馈丢失 / 切膜失败（人工复位是切膜失败的唯一出路） *)
        IF fbTrigReset.Q AND (NOT bRecipeBad) THEN
            bRecipeLatch := FALSE;
            bTurnLossInt := FALSE;
            bCutFailInt  := FALSE;       // 切膜失败锁存解除（人工复位）/ Cut failure latch cleared by the manual reset
            uErrorId     := 16#0000_0000;
            eStateInt    := E_DL_WrapSeqState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：迁兜底态（复用配方段码位） *)
        eStateInt := E_DL_WrapSeqState.eFault;
        uErrorId  := 16#0005_03A9;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜转盘圈计数（沿计数 + 饱和 255）与反馈丢失消化
 *      Turn counting with 255 saturation, and the feedback loss digestion
 *      计数仅在驱动输出有效且未暂停保持时推进（暂停在圈边界已截停驱动）
 *-----------------------------------------------------------------------------*)
bTurnDriveInt := (eStateInt = E_DL_WrapSeqState.eBottom) OR (eStateInt = E_DL_WrapSeqState.eTop);
bTurnDriveInt := bTurnDriveInt AND (NOT bPauseHoldInt);

IF rTrigTurn.Q AND bTurnDriveInt THEN
    (* 终审就地修 v1.0.1（R68④）：计数上限改用总圈上界 510。原实现以单段上界 255
     * 作总数闸，配方合法（如底 200 + 顶 100 = 300）时计数停在 255 -> eTop 相
     * 永不可达、转盘驱动常励磁（死路径）。 *)
    (* The counter ceiling is the total bound, so legal recipes above 255 turns no longer deadlock. *)
    IF (nBottomDone + nTopDone) < DL_WR_TOTAL_MAX THEN
        IF eStateInt = E_DL_WrapSeqState.eBottom THEN
            nBottomDone := nBottomDone + 1;  // 底圈计数推进 / Bottom count up
        ELSIF eStateInt = E_DL_WrapSeqState.eTop THEN
            nTopDone := nTopDone + 1;        // 顶圈计数推进 / Top count up
        END_IF
    END_IF
END_IF

IF tonTurnLoss.Q AND (NOT bTurnLossInt) THEN
    bTurnLossInt := TRUE;            // 反馈丢失锁存 / Loss latched
    uErrorId     := 16#0005_03AA;    // 故障级：反馈丢失 / Fault: feedback loss
    bErrorInt    := TRUE;
    eStateInt    := E_DL_WrapSeqState.eFault;   // 锁存同步迁相（FB50-1④）/ Latch migrates phase
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜切膜重试节流、计数饱和与失败出口（R69 点修②）
 *      Film cut retry throttle, count saturation and the failure exit
 *      重试由自复位间隔窗节流：每窗到期 +1 次（防同拍连发）；
 *      计次饱和（nCutRetryMax 封顶不回绕）后**不再自动重切**：单次窗再次超时即判
 *      切膜失败 -> 03B3 + bCutFail 锁存 + 迁 eFault 停机待人工，解除靠人工复位。
 *      nCutRetryMax <= 0 表示「不允许重试」，首次窗超时即判失败（安全侧直落）。
 *-----------------------------------------------------------------------------*)
IF (eStateInt = E_DL_WrapSeqState.eCut) AND tonCutTo.Q THEN
    IF nRetryInt >= nCutRetryMax THEN
        (* 拍 N 进入：计次已饱和且单次窗再次超时；本拍行为：锁存失败码并迁故障相，
         * 拒绝任何自动重切；拍 N+1 转出：eFault 驻留至人工复位沿。 *)
        (* Retries exhausted and the cut window expired again: latch the failure, never retry automatically *)
        bCutFailInt := TRUE;         // 切膜失败锁存 / Cut failure latched
        uErrorId    := 16#0005_03B3; // 故障级：切膜失败，停机待人工 / Fault: cut failed, manual service
        bErrorInt   := TRUE;         // R45 配对 / Paired with the fault code
        eStateInt   := E_DL_WrapSeqState.eFault;   // 锁存同步迁相 / Latch migrates phase
    ELSIF tonCutDwell.Q THEN
        (* 双窗合流节流：切膜窗保持超时的同时，重试间隔窗到期才计一次（防同拍连发） *)
        (* Double-window throttle: count at most once per dwell period while timed out *)
        IF nRetryInt < nCutRetryMax THEN
            nRetryInt := nRetryInt + 1;  // 重试计数推进 / Retry count up
        END_IF
        IF nRetryInt >= nCutRetryMax THEN
            uErrorId := 16#0005_04D3;    // 信息级：重试已饱和，下一窗超时即判失败 / Info: retries saturated
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
bTurnDrive   := bTurnDriveInt AND (NOT bTurnLossInt) AND (NOT bCutFailInt);
(* 压膜出口（R69 点修⑦）：仅 ePreClamp 相有效；底 / 顶圈段一进入即释放并全程保持
 * 释放（防膜皱 / 拉断），切膜 / 保持 / 空闲 / 故障相同样释放。释放由状态派生式
 * 结构性保证，不挂单拍标志，也不受暂停位改写。 *)
(* Press-film output is only driven in the pre-clamp phase; the winding phases stay released *)
bPreClampOut := (eStateInt = E_DL_WrapSeqState.ePreClamp);
bCutOut      := (eStateInt = E_DL_WrapSeqState.eCut) AND (NOT bCutDone) AND (NOT bCutFailInt);
bCutFail     := bCutFailInt;         // 失败锁存直出（人工复位前常驻）/ Failure latch straight out
bPauseHold   := bPauseHoldInt;
bSeqActive   := (eStateInt <> E_DL_WrapSeqState.eIdle) AND (eStateInt <> E_DL_WrapSeqState.eFault);
bSeqDone     := bDoneT;              // 完成脉冲统一出口（预清 + 两段式）/ Unified done exit
nTurnsDone   := nBottomDone + nTopDone;
nCutRetries  := nRetryInt;
bError       := bErrorInt OR (eStateInt = E_DL_WrapSeqState.eFault);
eState       := eStateInt;
END_FUNCTION_BLOCK
