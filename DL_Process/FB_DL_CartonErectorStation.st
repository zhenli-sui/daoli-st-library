//==============================================================================
// 功能块：FB_DL_CartonErectorStation ｜ 中文名称：开箱（Carton Erector）工站模板
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：开箱工站七态九步骨架——七态 = 就绪/送箱坯/开箱/折底/插底/
//           封压/推出（外加 eIdle/eFault 两态不入工作态计数），九步 =
//           步进引擎步号 0..8（吸箱坯下降/吸持/提升/撑箱开箱/折前底翼/
//           折后底翼/插底翼锁底/压底整形/推出），步完成由本件按反馈与
//           驻留判据装配，步超时由 FB_DL_StepSequencer 统一监控（DL_Base
//           组合调用，接口引脚契约与 FB_DL_ElectrolyteDosingSeq 同口径）。
//           步号-相位映射表：0/1/2 → eFeeding（送坯三步）、3 → eOpening、
//           4/5/6 → eFolding、7 → eSealing、8 → eEjecting、bDone → eDone。
// 开源溯源 (Origin)：道莅原创实现（参考 ISA-88 相-步骤语义与开箱成型机工程惯例 分类与参数域）
// 单位表：计数[次] / 时间[ms] / 阀输出[—]
// 错误码表：16#0005_01F4 信息级（成型完成放行：eDone 相进入，不置
//           bError）/ 16#0005_01F5 信息级（开箱到位提示：撑箱步完成，
//           关键节点可观测，不置 bError）/ 16#0005_0333 故障级（组态
//           非法：步超时表为 0 或箱坯 absent 且强行启动，置 bError）/
//           16#0005_0334 故障级（步超时：步进引擎判超时，锁存，置
//           bError——该场景不可由 0333 的组态类判据观测，属执行机构
//           独立域）/ 16#0005_0335 故障级兜底（状态机落 ELSE 或非法
//           状态，置 bError 并全输出断）
// 状态机：E_DL_CartonPhase（九态：eIdle=0 / eReady=10 / eFeeding=20 /
//           eOpening=30 / eFolding=40 / eSealing=50 / eEjecting=60 /
//           eDone=70 / eFault=99；工作态七态 = eReady..eDone），CASE
//           含 ELSE 兜底，ELSE 置 0335 并全输出断
// 边界行为：① 组态非法（任一步超时为 0）→ 故障态锁存，bReset 复位；
//           ② bAbort → 两段化照 §4 修复件样板：真空/输出立即断，推出
//           缸保持不动，等运行条件消失回空闲；③ 步完成判据：反馈优先
//           （bXxxFb），无反馈步用驻留时间兜底；④ eDone 等启动撤销回
//           空闲（同拍重启防抖，R39 范式）；⑤ 未启动/故障全输出断
//           （真空、缸、推出全撤）；⑥ 安全侧 = abort 拍不得出现关阀
//           输出置位以外的任何缸动作（机检断言：abort 拍仅真空断）。
// 依赖纪律：Process → Level 0 组合调用合法——步进引擎组合调用
//           FB_DL_StepSequencer（DL_Base，接口已核实），全库单调用点
//           （每拍恰好调用一次，防双调用边沿竞态）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P0 §652）
//           v1.0.1 2026-11-17 R24 终审修复（R106 第一档，契约不变）：原
//           fbSeq.bReset 恒 FALSE，而步进引擎 bError 为锁存型
//          （eState = eFault，仅 bReset 上升沿清除），步超时后工站故障
//           恢复条件 NOT fbSeq.bError 永不满足 → 故障恢复死锁；修复为
//           仅在工站 eFault 相透传 bReset，非故障相禁透传（防运行中误清
//           步进器致相位-步号失配）。引脚契约、码位、枚举不变。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_CartonPhase（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 开箱工站相位，与步进器步号映射（0/1/2→eFeeding、3→eOpening、
 *       4/5/6→eFolding、7→eSealing、8→eEjecting）。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_CartonPhase :
(
    eIdle     := 0,   // 空闲：等启动 / Idle, awaiting start
    eReady    := 10,  // 就绪：箱坯在位确认窗（步 0 吸箱坯下降） / Ready, blank presence window, step 0
    eFeeding  := 20,  // 送箱坯：吸持提升（步 1/2） / Feeding, vacuum and lift, steps 1 and 2
    eOpening  := 30,  // 开箱：撑箱开箱（步 3） / Opening, case spreader, step 3
    eFolding  := 40,  // 折底：折前后底翼与插底锁底（步 4/5/6） / Folding, bottom flaps and tuck, steps 4 to 6
    eSealing  := 50,  // 封压：压底整形（步 7） / Sealing, bottom press, step 7
    eEjecting := 60,  // 推出：成品推出（步 8） / Ejecting, product push-out, step 8
    eDone     := 70,  // 完成：放行，等启动撤销 / Done, released, awaiting start drop
    eFault    := 99   // 故障：组态/步超时/非法状态 / Fault, config, step timeout or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_CartonErectorStation
VAR_INPUT
    bStart       : BOOL;                    // 启动请求 [—]，上升沿生效 / Start request, rising edge
    bAbort       : BOOL;                    // 中止请求 [—]，任意拍生效 / Abort request, effective on any scan
    bReset       : BOOL;                    // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    bBlankPresent: BOOL;                    // 箱坯在位 [—] / Carton blank present
    bVacuumFb    : BOOL;                    // 吸持真空反馈 [—] / Vacuum feedback
    bLiftFb      : BOOL;                    // 提升到位反馈 [—] / Lift-in-position feedback
    bOpenFb      : BOOL;                    // 开箱到位反馈 [—] / Spreader-in-position feedback
    bFoldFb      : BOOL;                    // 折翼到位反馈 [—] / Flap-in-position feedback
    bTuckFb      : BOOL;                    // 插底到位反馈 [—] / Tuck-in-position feedback
    bPressFb     : BOOL;                    // 压底到位反馈 [—] / Press-in-position feedback
    bEjectFb     : BOOL;                    // 推出到位反馈 [—] / Eject-in-position feedback
    tDwell       : TIME  := T#200MS;        // 无反馈步驻留兜底 [ms]，须 > 0 / Dwell fallback for feedback-less steps [ms]
END_VAR
VAR_OUTPUT
    ePhase       : E_DL_CartonPhase;        // 工站相位 [—] / Station phase
    bVacuumOn    : BOOL;                    // 吸持真空输出 [—] / Vacuum output
    bFeedOut     : BOOL;                    // 送箱坯下降输出 [—] / Blank-feed output
    bOpenOut     : BOOL;                    // 开箱缸输出 [—] / Spreader output
    bFoldOut     : BOOL;                    // 折翼缸输出 [—] / Flap cylinder output
    bTuckOut     : BOOL;                    // 插底缸输出 [—] / Tuck cylinder output
    bPressOut    : BOOL;                    // 压底缸输出 [—] / Press cylinder output
    bEjectOut    : BOOL;                    // 推出缸输出 [—] / Eject cylinder output
    eErr         : UDINT;                   // 错误码，0 = 无错，码位 16#0005_01F4 起信息级、16#0005_0333 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError       : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid       : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbSeq        : FB_DL_StepSequencer;     // 步进引擎（Level 0 组合调用，单调用点） / Step engine, Level 0 composition, single call site
    fbDwellT     : TON;                     // 无反馈步驻留兜底计时（每拍无条件刷新）[ms] / Dwell fallback timer, refreshed unconditionally
    fbStart      : R_TRIG;                  // 启动沿检测（待机/故障分支同样无条件刷新） / Start edge detector, refreshed unconditionally
    _ePhase      : E_DL_CartonPhase := E_DL_CartonPhase.eIdle; // 当前相位 / Current phase
    _abStepDone  : ARRAY[0..15] OF BOOL;    // 步完成信号（本件按判据维护） / Step-done levels, maintained by this FB
    _auStepTimeout: ARRAY[0..15] OF TIME;   // 每步超时 [ms]，0 = 不监控 / Per-step timeout [ms], zero = not monitored
    _bSeqStart   : BOOL;                    // 步进器启动沿请求（单调用点输入） / Sequencer start edge request
    _bCfgBad     : BOOL;                    // 组态非法锁存 / Illegal config latch
    _bAbortStage : UINT;                    // 中止段号 [—]，0 = 无 / 1 = 输出已断 / Abort stage, zero none, one outputs cut
    _bInfoOpen   : BOOL;                    // 开箱到位信息当拍标志 / Opening info flag of this scan
    _bInfoDone   : BOOL;                    // 完成信息当拍标志 / Done info flag of this scan
    _bIllegal    : BOOL;                    // 非法状态标志 / Illegal state flag
    _bInit       : BOOL := FALSE;           // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_CES_TO_FEED : TIME := T#3S;          // 步 0 吸箱坯超时 [ms] / Step 0 timeout [ms]
    DL_CES_TO_VAC  : TIME := T#2S;          // 步 1 吸持超时 [ms] / Step 1 timeout [ms]
    DL_CES_TO_LIFT : TIME := T#3S;          // 步 2 提升超时 [ms] / Step 2 timeout [ms]
    DL_CES_TO_OPEN : TIME := T#4S;          // 步 3 开箱超时 [ms] / Step 3 timeout [ms]
    DL_CES_TO_FOLD : TIME := T#3S;          // 步 4 折前底翼超时 [ms] / Step 4 timeout [ms]
    DL_CES_TO_FOLD2: TIME := T#3S;          // 步 5 折后底翼超时 [ms] / Step 5 timeout [ms]
    DL_CES_TO_TUCK : TIME := T#3S;          // 步 6 插底超时 [ms] / Step 6 timeout [ms]
    DL_CES_TO_PRESS: TIME := T#2S;          // 步 7 压底超时 [ms] / Step 7 timeout [ms]
    DL_CES_TO_EJCT : TIME := T#4S;          // 步 8 推出超时 [ms] / Step 8 timeout [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：全输出先断（安全侧），单拍标志预清零
 *      All outputs cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bVacuumOn := FALSE;                      // 真空输出先清（安全侧） / Vacuum cleared first
bFeedOut  := FALSE;                      // 送坯输出先清 / Feed output cleared first
bOpenOut  := FALSE;                      // 开箱输出先清 / Spreader cleared first
bFoldOut  := FALSE;                      // 折翼输出先清 / Flap cleared first
bTuckOut  := FALSE;                      // 插底输出先清 / Tuck cleared first
bPressOut := FALSE;                      // 压底输出先清 / Press cleared first
bEjectOut := FALSE;                      // 推出输出先清 / Eject cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoOpen := FALSE;                     // 开箱信息预清零 / Opening info pre-cleared
_bInfoDone := FALSE;                     // 完成信息预清零 / Done info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared
_bSeqStart := FALSE;                     // 步进器启动沿请求预清零 / Sequencer start request pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：步超时表一次装配
 *      First-scan initialisation, the timeout table assembled once
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _ePhase := E_DL_CartonPhase.eIdle;   // 相位空闲起步 / Phase starts idle
    _auStepTimeout[0] := DL_CES_TO_FEED; // 步 0 超时 / Step 0 timeout
    _auStepTimeout[1] := DL_CES_TO_VAC;  // 步 1 超时 / Step 1 timeout
    _auStepTimeout[2] := DL_CES_TO_LIFT; // 步 2 超时 / Step 2 timeout
    _auStepTimeout[3] := DL_CES_TO_OPEN; // 步 3 超时 / Step 3 timeout
    _auStepTimeout[4] := DL_CES_TO_FOLD; // 步 4 超时 / Step 4 timeout
    _auStepTimeout[5] := DL_CES_TO_FOLD2; // 步 5 超时 / Step 5 timeout
    _auStepTimeout[6] := DL_CES_TO_TUCK; // 步 6 超时 / Step 6 timeout
    _auStepTimeout[7] := DL_CES_TO_PRESS; // 步 7 超时 / Step 7 timeout
    _auStepTimeout[8] := DL_CES_TO_EJCT; // 步 8 超时 / Step 8 timeout
    _auStepTimeout[9] := T#0MS;          // 步 9 及以后不监控 / Steps 9 and beyond not monitored
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    _bAbortStage := 0;                   // 中止段号从零起步 / Abort stage starts at zero
    _bInit := TRUE;                      // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态闸 + 沿检测 + 驻留计时无条件刷新（R40：CASE 之外每拍必调）
 *      Config gate plus unconditional refresh per R40
 *-----------------------------------------------------------------------------*)
fbStart(CLK := bStart);                  // 启动沿检测 / Start edge detection
fbDwellT(IN := (_ePhase = E_DL_CartonPhase.eReady), PT := tDwell); // 步 0 吸箱坯下降驻留窗（进相即起算） / Step 0 feed-down dwell window, restarts on phase entry
IF (tDwell <= T#0MS) OR (_auStepTimeout[0] <= T#0MS)
   OR (_auStepTimeout[3] <= T#0MS) OR (_auStepTimeout[8] <= T#0MS) THEN
    _bCfgBad := TRUE;                    // 步超时表/驻留窗非法锁存（关键步抽查） / Timeout table and dwell domains latched, key steps sampled
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜中止入口（输出立即断，机构位置保持）与复位
 *      Abort entry, outputs cut immediately, mechanisms held
 *-----------------------------------------------------------------------------*)
IF bAbort AND (_bAbortStage = 0)
   AND (_ePhase <> E_DL_CartonPhase.eIdle) AND (_ePhase <> E_DL_CartonPhase.eFault) THEN
    _bAbortStage := 1;                   // 进中止段（输出断、位置保持） / Enter abort stage, outputs cut, positions held
END_IF
IF _bAbortStage = 1 THEN
    IF (NOT bStart) THEN
        _bAbortStage := 0;               // 启动撤销回空闲 / Start dropped, back to idle
        _ePhase := E_DL_CartonPhase.eIdle; // 相位回空闲 / Phase back to idle
    END_IF
END_IF
IF bReset THEN
    _bCfgBad := FALSE;                   // 复位清组态锁存 / Reset clears the config latch
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜步进器单调用点与步完成判据装配（每拍恰好一次）
 *      Single sequencer call site and step-done assembly
 *-----------------------------------------------------------------------------*)
_bSeqStart := fbStart.Q AND (_ePhase = E_DL_CartonPhase.eIdle)
              AND (NOT _bCfgBad) AND bBlankPresent; // 启动沿（空闲且组态合法且箱坯在位） / Start edge in idle with legal config and blank present
IF (_ePhase <> E_DL_CartonPhase.eIdle) AND (_ePhase <> E_DL_CartonPhase.eFault)
   AND (_bAbortStage = 0) THEN
    _abStepDone[0] := fbDwellT.Q;        // 步 0 完成：吸箱坯下降驻留窗满 / Step 0 done, feed-down dwell elapsed
    _abStepDone[1] := bVacuumFb;         // 步 1 完成：真空反馈 / Step 1 done, vacuum feedback
    _abStepDone[2] := bLiftFb;           // 步 2 完成：提升到位反馈 / Step 2 done, lift feedback
    _abStepDone[3] := bOpenFb;           // 步 3 完成：开箱到位反馈 / Step 3 done, spreader feedback
    _abStepDone[4] := bFoldFb;           // 步 4 完成：折翼到位反馈 / Step 4 done, flap feedback
    _abStepDone[5] := bFoldFb;           // 步 5 完成：折后底翼共用折翼反馈 / Step 5 done, flap feedback shared
    _abStepDone[6] := bTuckFb;           // 步 6 完成：插底到位反馈 / Step 6 done, tuck feedback
    _abStepDone[7] := bPressFb;          // 步 7 完成：压底到位反馈 / Step 7 done, press feedback
    _abStepDone[8] := bEjectFb;          // 步 8 完成：推出到位反馈 / Step 8 done, eject feedback
    IF _abStepDone[3] AND (_ePhase = E_DL_CartonPhase.eOpening) THEN
        _bInfoOpen := TRUE;              // 开箱到位（信息级，关键节点） / Opening reached, info
    END_IF
END_IF

fbSeq(bStart := _bSeqStart, abStepDone := _abStepDone, auStepTimeout := _auStepTimeout,
      bHold := FALSE, bSingleStep := FALSE, bAdvance := FALSE,
      bAbort := (_bAbortStage >= 1),
      bReset := bReset AND (_ePhase = E_DL_CartonPhase.eFault)); // 步进器唯一调用点；复位仅故障相透传（步进器 bError 锁存型，v1.0.1 死锁修复；非故障相禁透传防误清） / The only sequencer call site; reset forwarded only in the fault phase, v1.0.1 deadlock fix

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移与步进对账；输出在段 7 按相置位）
 *      Phase machine, transitions and step reconciliation only
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF

    E_DL_CartonPhase.eIdle:                // 空闲：启动沿进就绪
        IF _bSeqStart THEN
            _ePhase := E_DL_CartonPhase.eReady; // 进就绪 / To ready
        END_IF

    E_DL_CartonPhase.eReady:               // 就绪：步进器推进到步 1 即转送箱坯
        IF fbSeq.bError THEN
            _ePhase := E_DL_CartonPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 1) THEN
            _ePhase := E_DL_CartonPhase.eFeeding; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_CartonPhase.eFeeding:             // 送箱坯：步进器推进到步 3 即转开箱
        IF fbSeq.bError THEN
            _ePhase := E_DL_CartonPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 3) THEN
            _ePhase := E_DL_CartonPhase.eOpening; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_CartonPhase.eOpening:             // 开箱：步进器推进到步 4 即转折底
        IF fbSeq.bError THEN
            _ePhase := E_DL_CartonPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 4) THEN
            _ePhase := E_DL_CartonPhase.eFolding; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_CartonPhase.eFolding:             // 折底：步进器推进到步 7 即转封压
        IF fbSeq.bError THEN
            _ePhase := E_DL_CartonPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 7) THEN
            _ePhase := E_DL_CartonPhase.eSealing; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_CartonPhase.eSealing:             // 封压：步进器推进到步 8 即转推出
        IF fbSeq.bError THEN
            _ePhase := E_DL_CartonPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 8) THEN
            _ePhase := E_DL_CartonPhase.eEjecting; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_CartonPhase.eEjecting:            // 推出：步进器 bDone 即完成
        IF fbSeq.bError THEN
            _ePhase := E_DL_CartonPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF fbSeq.bDone THEN
            _bInfoDone := TRUE;            // 成型完成（信息级，拍 N 进入） / Erecting done, info
            _ePhase := E_DL_CartonPhase.eDone; // 本拍转出：进完成 / To done
        END_IF

    E_DL_CartonPhase.eDone:                // 完成：等启动撤销回空闲
        IF NOT bStart THEN
            _ePhase := E_DL_CartonPhase.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_CartonPhase.eFault:               // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) AND (NOT fbSeq.bError) THEN
            _ePhase := E_DL_CartonPhase.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _ePhase   := E_DL_CartonPhase.eFault; // 回故障态（段 7 全断） / Back to fault, all outputs off
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜输出置位（次序即安全：abort 拍仅真空断、缸全部撤，机检断言）
 *      Output assignment, abort scan cuts vacuum and retracts all cylinders
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF
    E_DL_CartonPhase.eReady:               // 就绪：吸箱坯下降 / Ready: blank feed down
        bVacuumOn := (_bAbortStage = 0);   // 中止拍真空断 / Vacuum cut in abort
        bFeedOut  := (_bAbortStage = 0);   // 送坯输出 / Feed output
    E_DL_CartonPhase.eFeeding:             // 送箱坯：真空保持 + 提升 / Feeding: vacuum held, lift
        bVacuumOn := (_bAbortStage = 0);   // 真空保持 / Vacuum held
    E_DL_CartonPhase.eOpening:             // 开箱：撑箱缸 / Opening: spreader
        bVacuumOn := (_bAbortStage = 0);   // 真空保持 / Vacuum held
        bOpenOut  := (_bAbortStage = 0);   // 开箱输出 / Spreader output
    E_DL_CartonPhase.eFolding:             // 折底：折翼 + 插底缸 / Folding: flap and tuck
        bVacuumOn := (_bAbortStage = 0);   // 真空保持 / Vacuum held
        bFoldOut  := (_bAbortStage = 0);   // 折翼输出 / Flap output
        bTuckOut  := (_bAbortStage = 0) AND fbSeq.nCurrentStep >= 6; // 插底输出（步 6 起） / Tuck output from step 6
    E_DL_CartonPhase.eSealing:             // 封压：压底缸 / Sealing: press
        bPressOut := (_bAbortStage = 0);   // 压底输出 / Press output
    E_DL_CartonPhase.eEjecting:            // 推出：推出缸 / Ejecting: eject
        bEjectOut := (_bAbortStage = 0);   // 推出输出 / Eject output
    ELSE                                   // 其余相输出全断 / Otherwise all off
        bVacuumOn := FALSE;                // 真空断 / Vacuum off
        bFeedOut  := FALSE;                // 送坯断 / Feed off
        bOpenOut  := FALSE;                // 开箱断 / Spreader off
        bFoldOut  := FALSE;                // 折翼断 / Flap off
        bTuckOut  := FALSE;                // 插底断 / Tuck off
        bPressOut := FALSE;                // 压底断 / Press off
        bEjectOut := FALSE;                // 推出断 / Eject off
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜码位出口（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_0335;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_0333;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF fbSeq.bError THEN
    eErr   := 16#0005_0334;                // 故障级：步超时 / Fault: step timeout
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoDone THEN
    eErr := 16#0005_01F4;                  // 信息级：成型完成放行 / Info: erecting done
ELSIF _bInfoOpen THEN
    eErr := 16#0005_01F5;                  // 信息级：开箱到位提示 / Info: opening reached
END_IF

bValid := (NOT bError) AND (_ePhase <> E_DL_CartonPhase.eIdle); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
ePhase := _ePhase;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
