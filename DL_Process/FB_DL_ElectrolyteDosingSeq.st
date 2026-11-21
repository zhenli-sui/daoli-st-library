//==============================================================================
// 功能块：FB_DL_ElectrolyteDosingSeq ｜ 中文名称：电解液定量注液顺控（复杂度 H）
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：电解液定量注液节拍链——抽液 → 称重核对 → 粗注 → 细注 →
//           静置 → 完成，粗/细切换点按目标量占比驱动，秤读数全程监视
//           （回退判秤异常），中止走两段化（断输出使能 → 惰转窗 → 关阀）。
// 开源溯源 (Origin)：道莅原创实现（参考 ISA-88 相-步骤语义与注液机工程惯例 分类与参数域）
// 单位表：m[g] / 占比[倍] / 时间[ms] / 计数[次]
// 错误码表：16#0005_01E2 信息级（粗细切换点已达，不置 bError）/
//           16#0005_01E3 预留禁用（不得挪用）/ 16#0005_0318 故障级（目标
//           注液量 <= 0 或切换占比域外或确认窗组态越界（tSettleTime 为 0
//           或大于步 1 超时、xCoastAbort 时 tCoastTime <= 0），组态非法，
//           置 bError）/ 16#0005_0319
//           故障级（称重回退判秤异常，暂停顺控保持输出，置 bError）/
//           16#0005_031A 故障级兜底（状态机落 ELSE 或步超时，R90 复用，
//           置 bError 并全输出断）
// 状态机：E_DL_ElyteDosingPhase（八态：eIdle=0 / eVacuumDraw=10 /
//           eWeighCheck=20 / eCoarseFill=30 / eFineFill=40 / eSettle=50 /
//           eDone=60 / eFault=99）。【命名留档】派单枚举名 E_DL_DosingPhase
//           已被 FB_DL_BatchDosingControl 占用且成员不兼容，按 R70 唯一
//           属主纪律改用 E_DL_ElyteDosingPhase，全库唯一定义。中止两段化
//           不占相位（八态契约锁定），由 _uAbortStage 内部标志驱动。
// 边界行为：① fTargetMassG <= 0 或切换占比域外或确认窗/惰转窗组态越界
//           （tSettleTime 为 0 或 > 步 1 超时 DL_DOS_TO_WEIGH——否则步 1
//           稳定窗结构性超时；xCoastAbort 时 tCoastTime <= 0——否则中止段
//           A 永不收口）→ 故障 0318；② 称重回退
//           （fScaleMassG 比上拍小超容差，注液执行期）→ 故障 0319，暂停
//           顺控保持输出，bReset 清锁存；③ bAbort 两段化照 §4 修复件样板：
//           泵输出使能立即断、注液阀保持不动 → 惰转窗满 → 关阀，禁单拍
//           先停后关，机检断言：abort 拍不得出现关阀输出置位；④ 八态
//           CASE 每态显式 + ELSE 兜底 → 031A + 全输出断；⑤ 步超时（步进
//           器判超时）→ 031A 复用（R90，无专用码位）；⑥ 非有限秤读数归入
//           秤异常（0319 复用，R90）。
// 依赖纪律：Process → Level 0 组合调用合法——步进引擎组合调用
//           FB_DL_StepSequencer（DL_Base，接口已核实：bStart/abStepDone/
//           auStepTimeout/bAbort/bReset → nCurrentStep/bRunning/bDone/
//           bError/nFaultStep），步号映射表见下方注释；全库单调用点（每拍
 *           恰好调用一次，防双调用边沿竞态）；防除零/防回绕/R79 防御齐备。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 锂电 P1 §409 + ISA-88 相语义次源）
//           v1.0.1 2026-11-17 R23 终审修复：段 3 补组态一致性闸——tSettleTime
//           > 步 1 超时 T#5S 时稳定窗结构性超时（必报 031A 假故障）、
//           tCoastTime <= 0 时中止段 A 永不收口，均归入 0318 锁存，契约不变。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_ElyteDosingPhase（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 注液顺控相位，与步进器步号一一映射（见步号映射表）。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_ElyteDosingPhase :
(
    eIdle       := 0,   // 空闲：等启动 / Idle, awaiting start
    eVacuumDraw := 10,  // 抽液：泵送电解液至计量腔（步 0） / Vacuum draw, pumping electrolyte, step 0
    eWeighCheck := 20,  // 称重核对：秤读数稳定窗（步 1） / Weigh check, scale stability window, step 1
    eCoarseFill := 30,  // 粗注：注液阀开，至粗细切换点（步 2） / Coarse fill to the switch point, step 2
    eFineFill   := 40,  // 细注：注液阀开，至目标量（步 3） / Fine fill to the target mass, step 3
    eSettle     := 50,  // 静置：浸润计时与终值复核（步 4） / Settling, soak window and final check, step 4
    eDone       := 60,  // 完成：放行，等启动撤销（步 5） / Done, released, step 5
    eFault      := 99   // 故障：组态/秤异常/步超时/非法状态 / Fault, config, scale, timeout or illegal state
);
END_TYPE

(*------------------------------------------------------------------------------
 * 步号映射表（步进器步号 → 相位枚举）：
 *   0 → eVacuumDraw ｜ 1 → eWeighCheck ｜ 2 → eCoarseFill ｜ 3 → eFineFill
 *   4 → eSettle ｜ 5 → eDone（步进器 bDone）｜ -1 → eIdle
 * 语义假设（头注释留档）：电子秤位于注液目标侧，注液过程中读数单调
 *   递增；已注量 = 读数 − 启动基线；抽液侧无秤反馈，以固定时长判完成。
 *-----------------------------------------------------------------------------*)
FUNCTION_BLOCK FB_DL_ElectrolyteDosingSeq
VAR_INPUT
    bStart        : BOOL;                   // 启动请求 [—]，上升沿生效 / Start request, rising edge
    bAbort        : BOOL;                   // 中止请求 [—]，任意拍生效 / Abort request, effective on any scan
    bReset        : BOOL;                   // 故障复位 [—]，上升沿清秤异常锁存 / Fault reset, rising edge clears the scale latch
    fTargetMassG  : LREAL;                  // 目标注液量 [克]，须 > 0 / Target dosing mass [g], must be > 0
    fCoarseFineKg : LREAL := 0.95;          // 粗/细切换点占目标比 [倍]，有效域 0..1 / Coarse-to-fine switch ratio [ratio], 0..1
    fScaleMassG   : LREAL;                  // 电子秤实时读数 [克]，注液目标侧质量 / Scale reading [g], target-side mass
    tSettleTime   : TIME  := T#2S;          // 静置浸润计时 [ms]，兼作称重稳定窗 / Soak time [ms], also the weigh stability window
    xCoastAbort   : BOOL  := TRUE;          // TRUE = 中止走惰转两段化（推荐）/ FALSE = 单拍中止（不推荐：残压回流风险） / Coast-stop abort sequencing enabled
    tCoastTime    : TIME  := T#2S;          // 泵惰转时间 [ms]：断使能到关阀的物理时序分隔窗 / Pump coast-down time [ms]
END_VAR
VAR_OUTPUT
    ePhase        : E_DL_ElyteDosingPhase;  // 注液相位 [—] / Dosing phase
    fDosedMassG   : LREAL;                  // 已注量 [克] = 读数 − 基线 / Dosed mass [g] = reading minus baseline
    bDosingOut    : BOOL;                   // 注液阀输出 [—] / Dosing valve output
    bPumpOut      : BOOL;                   // 泵输出 [—] / Pump output
    eErr          : UDINT;                  // 错误码，0 = 无错 / Error code, 0 = no error
    bError        : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbSeq         : FB_DL_StepSequencer;    // 步进引擎（Level 0 组合调用，单调用点） / Step engine, Level 0 composition, single call site
    fbDraw        : TON;                    // 抽液计时（步 0 完成判据），段 6 无条件刷新 [ms] / Draw timer, step 0 done criterion
    fbStable      : TON;                    // 称重稳定窗（步 1 完成判据），段 6 无条件刷新 [ms] / Weigh stability window, step 1 done criterion
    fbSettle      : TON;                    // 静置计时（步 4 完成判据），段 6 无条件刷新 [ms] / Settle timer, step 4 done criterion
    fbCoast       : TON;                    // 泵惰转计时（中止第一段），段 6 无条件刷新 [ms] / Pump coast timer, abort stage A
    _abStepDone   : ARRAY[0..15] OF BOOL;   // 步完成信号（本件按判据维护） / Step-done levels, maintained by this FB
    _auStepTimeout: ARRAY[0..15] OF TIME;   // 每步超时 [ms]，0 = 不监控 / Per-step timeout [ms], zero = not monitored
    _ePhase       : E_DL_ElyteDosingPhase := E_DL_ElyteDosingPhase.eIdle; // 当前相位 / Current phase
    _fBaseMassG   : LREAL;                  // 注液基线质量 [克]，启动拍锁定 / Baseline mass [g], locked at start
    _fScalePrevG  : LREAL;                  // 上拍秤读数快照 [克] / Previous-scan scale snapshot [g]
    _uAbortStage  : UINT;                   // 中止段号 [—]，0 = 无 / 1 = 惰转 / 2 = 已关阀 / Abort stage, zero none, one coast, two closed
    _bSeqStart    : BOOL;                   // 步进器启动沿请求（单调用点输入） / Sequencer start edge request
    _bStartPrev   : BOOL;                   // 启动命令上拍电平快照 / Previous-scan level of the start command
    _bInit        : BOOL := FALSE;          // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bParamBad    : BOOL;                   // 参数非法锁存 / Illegal parameter latch
    _bScaleErr    : BOOL;                   // 秤异常锁存（bReset 清除） / Scale fault latch, cleared by bReset
    _bIllegal     : BOOL;                   // 非法状态标志 / Illegal state flag
    _bInfoCoarse  : BOOL;                   // 粗细切换信息当拍标志 / Coarse switch info flag of this scan
END_VAR
VAR CONSTANT
    DL_DOS_TOL_G   : LREAL := 0.5;          // 秤稳定/回退容差 [克] / Scale stability and regression tolerance [g]
    DL_DOS_DRAW_T  : TIME  := T#5S;         // 抽液固定时长 [ms]，抽液无秤反馈侧判据的工程缺省 / Fixed draw duration [ms]
    DL_DOS_TO_DRAW : TIME  := T#8S;         // 步 0 超时 [ms] / Step 0 timeout [ms]
    DL_DOS_TO_WEIGH: TIME  := T#5S;         // 步 1 超时 [ms] / Step 1 timeout [ms]
    DL_DOS_TO_COARSE: TIME := T#60S;        // 步 2 超时 [ms] / Step 2 timeout [ms]
    DL_DOS_TO_FINE : TIME  := T#120S;       // 步 3 超时 [ms] / Step 3 timeout [ms]
    DL_DOS_TO_SETTLE: TIME := T#10S;        // 步 4 超时 [ms] / Step 4 timeout [ms]
    DL_DOS_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：双输出先全断（安全侧），单拍标志预清零
 *      Both outputs cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bDosingOut  := FALSE;                       // 注液阀输出先清（安全侧） / Dosing output cleared first
bPumpOut    := FALSE;                       // 泵输出先清（安全侧） / Pump output cleared first
fDosedMassG := 0.0;                         // 已注量每拍重算 / Dosed mass recomputed
eErr        := 16#0000_0000;                // 错误码每拍重算 / Error code recomputed
bError      := FALSE;                       // 故障标志每拍重算 / Fault flag recomputed
bValid      := FALSE;                       // 可用标志每拍重算 / Usable flag recomputed
_bIllegal   := FALSE;                       // 非法状态标志预清零 / Illegal flag pre-cleared
_bInfoCoarse := FALSE;                     // 粗细切换信息预清零 / Coarse info pre-cleared
_bSeqStart  := FALSE;                       // 步进器启动沿请求预清零 / Sequencer start request pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化：步超时表一次装配
 *      First-scan initialisation, the timeout table assembled once
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _ePhase := E_DL_ElyteDosingPhase.eIdle; // 相位空闲起步 / Phase starts idle
    _auStepTimeout[0] := DL_DOS_TO_DRAW;    // 步 0 抽液超时 / Step 0 draw timeout
    _auStepTimeout[1] := DL_DOS_TO_WEIGH;   // 步 1 称重超时 / Step 1 weigh timeout
    _auStepTimeout[2] := DL_DOS_TO_COARSE;  // 步 2 粗注超时 / Step 2 coarse timeout
    _auStepTimeout[3] := DL_DOS_TO_FINE;    // 步 3 细注超时 / Step 3 fine timeout
    _auStepTimeout[4] := DL_DOS_TO_SETTLE;  // 步 4 静置超时 / Step 4 settle timeout
    _auStepTimeout[5] := T#0MS;             // 步 5 完成态不监控 / Step 5 not monitored
    _fScalePrevG := 0.0;                    // 秤快照从零起步 / Scale snapshot starts at zero
    _uAbortStage := 0;                      // 中止段号从零起步 / Abort stage starts at zero
    _bInit := TRUE;                         // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数与输入防御闸（R79 双侧幅值判 + 占比域闸）
 *      Parameter and input defense gates
 *-----------------------------------------------------------------------------*)
IF (fTargetMassG <> fTargetMassG) OR (ABS(fTargetMassG) > DL_DOS_INF) OR (fTargetMassG <= 0.0) THEN
    _bParamBad := TRUE;                     // 目标量非法锁存 / Illegal target latched
END_IF
IF (fScaleMassG <> fScaleMassG) OR (ABS(fScaleMassG) > DL_DOS_INF) THEN
    _bScaleErr := TRUE;                     // 秤读数非有限归入秤异常（0319 复用，R90） / Non-finite scale folded into the scale fault
END_IF
IF (fCoarseFineKg < 0.0) OR (fCoarseFineKg > 1.0) THEN
    _bParamBad := TRUE;                     // 切换占比域外锁存 / Switch ratio out of range latched
END_IF
IF (tSettleTime <= T#0MS) OR (tSettleTime > DL_DOS_TO_WEIGH) THEN
    _bParamBad := TRUE;                     // 确认窗组态越界：为 0 或大于步 1 超时（结构性超时）锁存 / Confirm window out of range, latched
END_IF
IF xCoastAbort AND (tCoastTime <= T#0MS) THEN
    _bParamBad := TRUE;                     // 惰转窗组态越界：两段化中止永不收口锁存 / Coast window out of range, latched
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜称重回退检测（注液执行期）：比上拍小超容差 → 0319 锁存
 *      Scale regression detection during the dosing execution phases
 *-----------------------------------------------------------------------------*)
IF (_ePhase = E_DL_ElyteDosingPhase.eCoarseFill)
   OR (_ePhase = E_DL_ElyteDosingPhase.eFineFill)
   OR (_ePhase = E_DL_ElyteDosingPhase.eSettle) THEN
    IF fScaleMassG < (_fScalePrevG - DL_DOS_TOL_G) THEN
        _bScaleErr := TRUE;                 // 称重回退锁存（暂停顺控保持输出） / Scale regression latched, sequencing paused
    END_IF
END_IF
_fScalePrevG := fScaleMassG;                // 快照推进 / Snapshot advanced

(*------------------------------------------------------------------------------
 * 段 5｜中止入口（任意拍生效；中止族态内不重复触发）与复位
 *      Abort entry, effective on any scan, not re-triggered in the family
 *-----------------------------------------------------------------------------*)
IF bAbort AND (_uAbortStage = 0)
   AND (_ePhase = E_DL_ElyteDosingPhase.eVacuumDraw
        OR _ePhase = E_DL_ElyteDosingPhase.eWeighCheck
        OR _ePhase = E_DL_ElyteDosingPhase.eCoarseFill
        OR _ePhase = E_DL_ElyteDosingPhase.eFineFill
        OR _ePhase = E_DL_ElyteDosingPhase.eSettle) THEN
    _uAbortStage := 1;                      // 进中止段 A（惰转） / Enter abort stage A, coast
END_IF
IF _uAbortStage >= 1 THEN
    IF (NOT bStart) AND (_uAbortStage = 2) THEN
        _uAbortStage := 0;                  // 关阀已完成且启动撤销，回空闲 / Close done and start dropped, back to idle
        _ePhase      := E_DL_ElyteDosingPhase.eIdle; // 相位回空闲 / Phase back to idle
    END_IF
END_IF
IF bReset THEN
    _bScaleErr := FALSE;                    // 复位清秤异常锁存 / Reset clears the scale latch
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜四只计时无条件刷新（R40：CASE 之外每拍必调，各司其职不复用）
 *      Four timers refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbDraw(IN := (_ePhase = E_DL_ElyteDosingPhase.eVacuumDraw) AND (_uAbortStage = 0),
       PT := DL_DOS_DRAW_T);               // 抽液计时 / Draw timer
fbStable(IN := (_ePhase = E_DL_ElyteDosingPhase.eWeighCheck) AND (_uAbortStage = 0)
              AND (ABS(fScaleMassG - _fBaseMassG) < DL_DOS_TOL_G), PT := tSettleTime); // 称重稳定窗 / Weigh stability window
fbSettle(IN := (_ePhase = E_DL_ElyteDosingPhase.eSettle) AND (_uAbortStage = 0), PT := tSettleTime); // 静置计时 / Settle timer
fbCoast(IN := (_uAbortStage = 1), PT := tCoastTime); // 中止惰转计时（段 A） / Abort coast timer, stage A

(*------------------------------------------------------------------------------
 * 段 7｜步进器单调用点（每拍恰好一次）与步完成判据装配
 *      Single sequencer call site and the step-done criteria assembly
 *-----------------------------------------------------------------------------*)
_bSeqStart := bStart AND (NOT _bStartPrev) AND (_ePhase = E_DL_ElyteDosingPhase.eIdle)
              AND (NOT _bParamBad) AND (NOT _bScaleErr); // 启动沿（空闲且组态合法） / Start edge in idle with a legal configuration
_bStartPrev := bStart;                      // 电平快照推进 / Level snapshot advanced

IF (_ePhase <> E_DL_ElyteDosingPhase.eIdle) AND (_ePhase <> E_DL_ElyteDosingPhase.eFault)
   AND (_uAbortStage = 0) THEN
    _abStepDone[0] := fbDraw.Q;             // 步 0 完成：抽液计时满 / Step 0 done, draw elapsed
    _abStepDone[1] := fbStable.Q;           // 步 1 完成：秤读数稳定窗满 / Step 1 done, stability window elapsed
    _abStepDone[2] := (fScaleMassG - _fBaseMassG) >= (fTargetMassG * fCoarseFineKg); // 步 2 完成：达粗细切换点 / Step 2 done, switch point reached
    _abStepDone[3] := (fScaleMassG - _fBaseMassG) >= fTargetMassG; // 步 3 完成：达目标量 / Step 3 done, target reached
    _abStepDone[4] := fbSettle.Q;           // 步 4 完成：静置计时满 / Step 4 done, settle elapsed
    _abStepDone[5] := TRUE;                 // 步 5 完成态恒成 / Step 5 always done
    IF _abStepDone[2] AND (_ePhase = E_DL_ElyteDosingPhase.eCoarseFill) THEN
        _bInfoCoarse := TRUE;               // 粗细切换点已达（信息级） / Switch point reached, info
    END_IF
END_IF

fbSeq(bStart := _bSeqStart, abStepDone := _abStepDone, auStepTimeout := _auStepTimeout,
      bHold := FALSE, bSingleStep := FALSE, bAdvance := FALSE,
      bAbort := (_uAbortStage >= 1), bReset := FALSE); // 步进器唯一调用点 / The only sequencer call site

IF _uAbortStage = 1 THEN
    IF fbCoast.Q THEN
        _uAbortStage := 2;                  // 惰转窗满，进中止段 B（关阀） / Coast elapsed, abort stage B, close
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜相位机（只做迁移与步进对账；输出在段 9 按相置位）
 *      Phase machine, transitions and step reconciliation only
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF

    E_DL_ElyteDosingPhase.eIdle:           // 空闲：启动沿锁定基线进抽液
        IF _bSeqStart THEN
            _fBaseMassG := fScaleMassG;     // 基线锁定 / Baseline locked
            _ePhase     := E_DL_ElyteDosingPhase.eVacuumDraw; // 进抽液相 / To the draw phase
        END_IF

    E_DL_ElyteDosingPhase.eVacuumDraw:     // 抽液：步进器推进到步 1 即转称重
        IF fbSeq.bError THEN
            _ePhase := E_DL_ElyteDosingPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 1) THEN
            _ePhase := E_DL_ElyteDosingPhase.eWeighCheck; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_ElyteDosingPhase.eWeighCheck:     // 称重核对：步进器推进到步 2 即转粗注
        IF fbSeq.bError THEN
            _ePhase := E_DL_ElyteDosingPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 2) THEN
            _ePhase := E_DL_ElyteDosingPhase.eCoarseFill; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_ElyteDosingPhase.eCoarseFill:     // 粗注：步进器推进到步 3 即转细注
        IF fbSeq.bError THEN
            _ePhase := E_DL_ElyteDosingPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 3) THEN
            _ePhase := E_DL_ElyteDosingPhase.eFineFill; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_ElyteDosingPhase.eFineFill:       // 细注：步进器推进到步 4 即转静置
        IF fbSeq.bError THEN
            _ePhase := E_DL_ElyteDosingPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 4) THEN
            _ePhase := E_DL_ElyteDosingPhase.eSettle; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_ElyteDosingPhase.eSettle:         // 静置：步进器推进到步 5 即完成
        IF fbSeq.bError THEN
            _ePhase := E_DL_ElyteDosingPhase.eFault; // 步超时，故障 / Step timeout, fault
        ELSIF (fbSeq.nCurrentStep = 5) THEN
            _ePhase := E_DL_ElyteDosingPhase.eDone; // 步进器已推进 / The sequencer advanced
        END_IF

    E_DL_ElyteDosingPhase.eDone:           // 完成：等启动撤销回空闲
        IF NOT bStart THEN
            _ePhase := E_DL_ElyteDosingPhase.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_ElyteDosingPhase.eFault:          // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bParamBad) AND (NOT _bScaleErr) THEN
            _ePhase := E_DL_ElyteDosingPhase.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _ePhase   := E_DL_ElyteDosingPhase.eFault; // 回故障态（段 9 全断） / Back to fault, all outputs off
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜输出置位（次序即安全：泵先于阀；中止段 A 泵断使能、阀保持不动，
 *       机检断言：abort 拍不得出现关阀输出置位——段 A 阀输出 = 保持量）
 *      Output assignment, pump precedes the valve, abort stage A holds the valve
 *-----------------------------------------------------------------------------*)
CASE _ePhase OF
    E_DL_ElyteDosingPhase.eVacuumDraw:     // 抽液：泵运行 / Draw: pump runs
        bPumpOut := (_uAbortStage = 0);    // 中止段 A 泵使能立即断 / Pump enable cut immediately in abort stage A
    E_DL_ElyteDosingPhase.eCoarseFill:     // 粗注：阀开 / Coarse: valve open
        bDosingOut := (_uAbortStage = 0) OR (_uAbortStage = 1); // 段 A 阀保持，段 B 关阀 / Valve held in stage A, closed in stage B
    E_DL_ElyteDosingPhase.eFineFill:       // 细注：阀开 / Fine: valve open
        bDosingOut := (_uAbortStage = 0) OR (_uAbortStage = 1); // 段 A 阀保持，段 B 关阀 / Valve held in stage A, closed in stage B
    ELSE                                   // 其余相输出全断 / Otherwise all off
        bDosingOut := FALSE;               // 注液阀断 / Dosing off
        bPumpOut   := FALSE;               // 泵断 / Pump off
END_CASE
IF (NOT xCoastAbort) AND (_uAbortStage >= 1) THEN
    bDosingOut := FALSE;                   // 兼容路径：单拍中止（不推荐，残压回流风险） / Legacy single-scan abort, not recommended
    bPumpOut   := FALSE;                   // 泵同拍断 / Pump off the same scan
END_IF

fDosedMassG := fScaleMassG - _fBaseMassG;   // 已注量出口 [克] / Dosed mass outlet [g]
IF fDosedMassG < 0.0 THEN
    fDosedMassG := 0.0;                     // 负增量钳 0（换批/去皮期） / Negative delta clamped to zero
END_IF
ePhase := _ePhase;                          // 相位出口 / Phase outlet

IF _bIllegal THEN
    eErr   := 16#0005_031A;                 // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bParamBad THEN
    eErr   := 16#0005_0318;                 // 故障级：目标量或占比非法 / Fault: illegal target or ratio
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bScaleErr THEN
    eErr   := 16#0005_0319;                 // 故障级：称重回退判秤异常 / Fault: scale regression
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF fbSeq.bError THEN
    eErr   := 16#0005_031A;                 // 故障级：步超时复用兜底码（R90） / Fault: step timeout, code reused per R90
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
ELSIF _bInfoCoarse THEN
    eErr := 16#0005_01E2;                   // 信息级：粗细切换点已达 / Info: switch point reached
END_IF

bValid := (NOT bError) AND (_ePhase <> E_DL_ElyteDosingPhase.eIdle); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
END_FUNCTION_BLOCK
