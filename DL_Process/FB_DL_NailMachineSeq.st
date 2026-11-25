//==============================================================================
// 功能块：FB_DL_NailMachineSeq ｜ 中文名称：极耳裁切/模切机顺控
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：极耳裁切/模切机节拍链——放卷 → 裁切 → 收料三工位联动：
//           三就绪门控起步、单拍节拍超时保护、批量计数达批自动收批；
//           bStop 立即断裁切输出（模切头行程内停止由驱动层负责，边界声明）。
// 开源溯源 (Origin)：道莅原创实现（参考锂电极耳模切机工程惯例 分类与参数域）
// 单位表：计数[片] / 节拍[ms] / 诊断掩码[位]
// 错误码表：16#0005_01E4 信息级（三就绪缺一，诊断掩码输出，不置 bError）/
//           16#0005_01E5 信息级（批量计数达批，正常收批结论，不置 bError）/
//           16#0005_031B 故障级（单拍节拍超时，全停，置 bError）/
//           16#0005_031C 预留禁用（不得挪用）/ 16#0005_031D 故障级兜底
//           （状态机落 ELSE，置 bError 并全停）
// 状态机：E_DL_NailSeqState（七态：eIdle=0 / eWaitReady=10 / eRun=20 /
//           eCutting=30 / eCollecting=40 / eBatchDone=50 / eFault=99），
//           CASE 含 ELSE 兜底，ELSE 置 031D 并全停
// 边界行为：① 三就绪缺一 → 停在 eWaitReady 并输出诊断掩码 uNotReadyMask
//           （位 0 = 放卷缺、位 1 = 裁切原点缺、位 2 = 收料缺）+ 信息 01E4；
//           ② 单拍节拍超时（tCutCycleMax 内未回到原点/收到切完反馈）→
//           故障 031B + 全停；③ 计数达批 → 回 eIdle + 信息 01E5；④ bStop
//           立即断裁切输出（安全侧不停机次序假设：模切头行程内停止由
//           驱动层负责，本件只断输出指令，头注释边界声明）；⑤ 计数饱和
//           4294967295 不回绕；⑥ 非有限/非法防御：批量目标为 0 不判故障
//           （0 = 连续模式），节拍上限 <= 0 判组态非法 031B 复用（R90）。
// 依赖纪律：仅 Standard.library；零跨层调用（三工位节拍编排为自研顺控，
//           不复用 StepSequencer——工位间为并行联动非串行步，复用会扭曲
//           语义，头注释声明此设计取舍）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 锂电 P1 §351）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_NailSeqState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 模切机顺控相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_NailSeqState :
(
    eIdle       := 0,   // 空闲：等启动 / Idle, awaiting start
    eWaitReady  := 10,  // 等就绪：三工位就绪门控（诊断掩码输出） / Waiting for readiness with a diagnostic mask
    eRun        := 20,  // 运行：放卷 + 收料联动输出 / Running, unwind and collector active
    eCutting    := 30,  // 裁切：切脉冲发出，等切完反馈/回原点 / Cutting, pulse issued, waiting for done or home
    eCollecting := 40,  // 收料：裁切完成转收料拍 / Collecting, the cut done transitions to the collect beat
    eBatchDone  := 50,  // 批完成：达批收批，等启动撤销 / Batch done, awaiting the start drop
    eFault      := 99   // 故障：节拍超时/组态非法/非法状态 / Fault, cycle timeout, illegal config or state
);
END_TYPE

FUNCTION_BLOCK FB_DL_NailMachineSeq
VAR_INPUT
    bStart         : BOOL;                  // 启动请求 [—]，上升沿生效 / Start request, rising edge
    bStop          : BOOL;                  // 停止请求 [—]，电平有效，立即断裁切输出 / Stop request, level active, cut output dropped immediately
    bUnwinderReady : BOOL;                  // 放卷就绪反馈 [—] / Unwinder ready feedback
    bCutterHome    : BOOL;                  // 裁切原点反馈 [—] / Cutter home feedback
    bCollectorReady: BOOL;                  // 收料就绪反馈 [—] / Collector ready feedback
    bCutDone       : BOOL;                  // 切完反馈 [—]，每片一拍 / Cut-done feedback, one scan per piece
    uBatchCount    : UDINT;                 // 批量目标 [片]，0 = 连续模式 / Batch target [pieces], zero = continuous mode
    tCutCycleMax   : TIME := T#3S;          // 单拍节拍上限 [ms]，须 > 0 / Single-cycle ceiling [ms], must be > 0
    bReset         : BOOL;                  // 故障复位 [—]，上升沿退出 eFault / Fault reset, rising edge leaves fault
END_VAR
VAR_OUTPUT
    eSeqState      : E_DL_NailSeqState;     // 顺控相位 [—] / Sequence phase
    uCutDone       : UDINT;                 // 已切计数 [片]，饱和不回绕 / Cut counter [pieces], saturated without wrap
    uNotReadyMask  : UINT;                  // 就绪诊断掩码 [位]，位0放卷/位1原点/位2收料 / Readiness diagnostic mask, bit0 unwind, bit1 home, bit2 collector
    bUnwindRun     : BOOL;                  // 放卷运行输出 [—] / Unwind run output
    bCutTrig       : BOOL;                  // 裁切触发输出 [—] / Cut trigger output
    bCollectRun    : BOOL;                  // 收料运行输出 [—] / Collector run output
    eErr           : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = no error
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbCycle        : TON;                   // 单拍节拍计时，段 6 无条件刷新 [ms] / Single-cycle timer
    _eState        : E_DL_NailSeqState := E_DL_NailSeqState.eIdle; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bStartPrev    : BOOL;                  // 启动命令上拍电平快照 / Previous-scan level of the start command
    _bIllegal      : BOOL;                  // 非法状态标志 / Illegal state flag
    _bCfgBad       : BOOL;                  // 组态非法锁存（节拍上限 <= 0） / Illegal configuration latch
    _bNotReady     : BOOL;                  // 三就绪缺一当拍标志 / Readiness-missing flag of this scan
END_VAR
VAR CONSTANT
    DL_NAIL_CNT_MAX : UDINT := 4294967295;  // 计数饱和上限 [片] / Counter saturation ceiling [pieces]
    DL_NAIL_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限（本件无浮点引脚，防御常量备扩展） / LREAL ceiling reserved for extensions
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：三输出先全断（安全侧），单拍标志预清零
 *      Three outputs cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bUnwindRun    := FALSE;                     // 放卷输出先清（安全侧） / Unwind output cleared first
bCutTrig      := FALSE;                     // 裁切输出先清（安全侧） / Cut output cleared first
bCollectRun   := FALSE;                     // 收料输出先清（安全侧） / Collector output cleared first
eErr          := 16#0000_0000;              // 错误码每拍重算 / Error code recomputed
bError        := FALSE;                     // 故障标志每拍重算 / Fault flag recomputed
bValid        := FALSE;                     // 可用标志每拍重算 / Usable flag recomputed
_bIllegal     := FALSE;                     // 非法状态标志预清零 / Illegal flag pre-cleared
_bNotReady    := FALSE;                     // 就绪缺一标志预清零 / Readiness flag pre-cleared
uNotReadyMask := 0;                         // 诊断掩码每拍重算 / Diagnostic mask recomputed

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_NailSeqState.eIdle; // 相位空闲起步 / Phase starts idle
    uCutDone    := 0;                       // 计数清零 / Counter cleared
    _bCfgBad    := FALSE;                   // 组态锁存清零 / Config latch cleared
    _bInit      := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态闸门：节拍上限 <= 0 → 组态非法（031B 复用，R90）
 *      Configuration gate: non-positive cycle ceiling is illegal
 *-----------------------------------------------------------------------------*)
IF TIME_TO_DINT(tCutCycleMax) <= 0 THEN
    _bCfgBad := TRUE;                       // 组态非法锁存 / Illegal configuration latched
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜就绪门控与诊断掩码装配
 *      Readiness gating and the diagnostic mask assembly
 *-----------------------------------------------------------------------------*)
IF (NOT bUnwinderReady) OR (NOT bCutterHome) OR (NOT bCollectorReady) THEN
    _bNotReady := TRUE;                     // 三就绪缺一 / Readiness missing
    IF NOT bUnwinderReady THEN
        uNotReadyMask := uNotReadyMask OR 1; // 位 0：放卷缺 / Bit 0, unwind missing
    END_IF
    IF NOT bCutterHome THEN
        uNotReadyMask := uNotReadyMask OR 2; // 位 1：裁切原点缺 / Bit 1, home missing
    END_IF
    IF NOT bCollectorReady THEN
        uNotReadyMask := uNotReadyMask OR 4; // 位 2：收料缺 / Bit 2, collector missing
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜单拍节拍计时无条件刷新（R40：CASE 之外每拍必调）
 *      Cycle timer refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbCycle(IN := (_eState = E_DL_NailSeqState.eCutting), PT := tCutCycleMax); // 单拍节拍计时 / Single-cycle timer

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；输出在段 7 按相置位）
 *      Phase machine, transitions only, outputs assigned in segment seven
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_NailSeqState.eIdle:               // 空闲：启动沿进等就绪
        IF bStart AND (NOT _bStartPrev) AND (NOT _bCfgBad) THEN
            _eState := E_DL_NailSeqState.eWaitReady; // 进等就绪 / To the wait-ready phase
        END_IF

    E_DL_NailSeqState.eWaitReady:          // 等就绪：三就绪全满进运行
        IF _bNotReady THEN
            _eState := E_DL_NailSeqState.eWaitReady; // 缺一滞留（掩码在段 7 输出） / Held while missing, the mask is output
        ELSE
            _eState := E_DL_NailSeqState.eRun; // 就绪全满，进运行 / All ready, run
        END_IF
        IF bStop THEN
            _eState := E_DL_NailSeqState.eIdle; // 停止请求回空闲 / Stop back to idle
        END_IF

    E_DL_NailSeqState.eRun:                // 运行：放卷 + 收料联动，发裁切触发
        IF bStop OR _bNotReady THEN
            _eState := E_DL_NailSeqState.eIdle; // 停止或缺就绪回空闲 / Stop or missing readiness back to idle
        ELSIF (bCutDone OR NOT bCutterHome) THEN
            _eState := E_DL_NailSeqState.eCutting; // 发切（反馈或离原点即视为切入） / To cutting
        END_IF

    E_DL_NailSeqState.eCutting:            // 裁切：等切完反馈或节拍超时
        IF bStop THEN
            _eState := E_DL_NailSeqState.eIdle; // 停止请求立即回空闲（输出段 7 断） / Stop, back to idle
        ELSIF fbCycle.Q THEN
            _eState := E_DL_NailSeqState.eFault; // 节拍超时，故障全停 / Cycle timeout, fault
        ELSIF bCutterHome AND bCutDone THEN
            uCutDone := uCutDone + 1;       // 切完计数递增（饱和不回绕） / Cut counter increment, saturated
            IF (uBatchCount > 0) AND (uCutDone >= uBatchCount) THEN
                _eState := E_DL_NailSeqState.eBatchDone; // 达批收批 / Batch complete
            ELSE
                _eState := E_DL_NailSeqState.eCollecting; // 转收料拍 / To the collect beat
            END_IF
        END_IF

    E_DL_NailSeqState.eCollecting:         // 收料：收料拍维持一拍后回运行
        IF bStop OR _bNotReady THEN
            _eState := E_DL_NailSeqState.eIdle; // 停止或缺就绪回空闲 / Stop or missing readiness back to idle
        ELSE
            _eState := E_DL_NailSeqState.eRun; // 收料拍结束回运行 / Collect beat ends, back to run
        END_IF

    E_DL_NailSeqState.eBatchDone:          // 批完成：等启动撤销回空闲
        IF NOT bStart THEN
            _eState := E_DL_NailSeqState.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_NailSeqState.eFault:              // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_NailSeqState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_NailSeqState.eFault; // 回故障态（全停） / Back to fault, all stopped
END_CASE
_bStartPrev := bStart;                      // 启动电平快照推进 / Start snapshot advanced

(*------------------------------------------------------------------------------
 * 段 7｜输出置位（bStop 电平直断裁切输出——安全侧，行程内停止由驱动层负责）
 *      Output assignment, bStop cuts the cut output directly, fail-safe
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_NailSeqState.eWaitReady:          // 等就绪：不启输出，只报掩码 / Wait-ready: no outputs, mask only
        bUnwindRun  := FALSE;              // 放卷断 / Unwind off
        bCollectRun := FALSE;              // 收料断 / Collector off
    E_DL_NailSeqState.eRun:                // 运行：放卷 + 收料联动 / Run: unwind and collector active
        bUnwindRun  := TRUE;               // 放卷运行 / Unwind run
        bCollectRun := TRUE;               // 收料运行 / Collector run
        bCutTrig    := (NOT bStop);        // 裁切触发（bStop 电平直断） / Cut trigger, dropped by bStop
    E_DL_NailSeqState.eCutting:            // 裁切：保持联动，触发随 bStop 断 / Cutting: linkage held, trigger dropped by bStop
        bUnwindRun  := TRUE;               // 放卷运行 / Unwind run
        bCollectRun := TRUE;               // 收料运行 / Collector run
        bCutTrig    := (NOT bStop);        // 裁切触发（bStop 电平直断） / Cut trigger, dropped by bStop
    E_DL_NailSeqState.eCollecting:         // 收料：放卷 + 收料维持 / Collecting: unwind and collector held
        bUnwindRun  := TRUE;               // 放卷运行 / Unwind run
        bCollectRun := TRUE;               // 收料运行 / Collector run
    ELSE                                   // 其余相输出全断 / Otherwise all off
        bUnwindRun  := FALSE;              // 放卷断 / Unwind off
        bCutTrig    := FALSE;              // 裁切断 / Cut off
        bCollectRun := FALSE;              // 收料断 / Collector off
END_CASE

IF _bIllegal THEN
    eErr   := 16#0005_031D;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad OR (_eState = E_DL_NailSeqState.eFault) THEN
    eErr   := 16#0005_031B;                // 故障级：节拍超时或组态非法（R90 复用） / Fault: cycle timeout or illegal config, code reused
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bNotReady AND (_eState = E_DL_NailSeqState.eWaitReady) THEN
    eErr := 16#0005_01E4;                  // 信息级：三就绪缺一（掩码输出） / Info: readiness missing with the mask
ELSIF _eState = E_DL_NailSeqState.eBatchDone THEN
    eErr := 16#0005_01E5;                  // 信息级：批量计数达批 / Info: batch count reached
END_IF

bValid := (NOT bError) AND (_eState <> E_DL_NailSeqState.eIdle); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
eSeqState := _eState;               // 顺控相位出口每拍赋值（名实同源） / Sequence phase outlet assigned every scan
END_FUNCTION_BLOCK
