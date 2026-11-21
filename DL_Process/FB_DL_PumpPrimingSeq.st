(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PumpPrimingSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 离心泵引水/自吸排气七态顺控：
 *                           eFill    开灌液阀：等 bFillValveFb 反馈，tFill 反馈超时 →
 *                                    eFault eCause=eFbFill；
 *                           eVent    开排气阀：等 bVentValveFb 反馈，tVent 反馈超时 →
 *                                    eFault eCause=eFbVent；
 *                           eConfirm 压力确认：fPrOutKpa >= fPrPrimeKpa → eDone（引水
 *                                    成功），tConfirm 窗内未达 → nRetries+1 回 eFill，
 *                                    nRetries > nRetryMax → eFault eCause=eNoPrime；
 *                           eRunning 主运态（本件只出态不接管泵启停）；eDone 引水确认
 *                                    完成，eRunning 下 bStop 正常停机 → eDone（引水序
 *                                    完成待复位），再 bStop/bReset → eIdle。
 *                         阀反馈超时各自 TON 段 0 刷新、分码 eFbFill/eFbVent（R190）。
 * 接口     (Interface)  : 输入 bStart/bStop/bReset、fPrOutKpa 泵出口压力（kPa）、
 *                         fPrPrimeKpa 引水成功判据（kPa）、bFillValveFb/bVentValveFb
 *                         阀反馈、tFill/tVent/tConfirm 各相窗、nRetryMax 重试上限；
 *                         输出 ePhase 七态、nRetries 重试计数、相指示 BOOL 组、bDone、
 *                         eCause、bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只管引水时序，不接管泵本体启停与
 *                         保护**（保护归 `FB_DL_PumpDryRunGuard` 族、主备切换归
 *                         `FB_DL_PumpChangeoverSeq`，三分域各管一段）。
 *                         ② 七态 CASE + ELSE 兜底 eFault（R6）；阀反馈/确认 TON 段 0
 *                         无条件刷新，IN 由当前相与反馈电平派生，无外部沿清零。
 *                         ③ 成因分码唯一（R190）：eFbFill / eFbVent / eNoPrime /
 *                         eNoData（压力非有限）/ eCfgIllegal。
 *                         ④ 组态闸：fPrPrimeKpa<=0、任一相时间 <= T#0S → 锁存 eFault
 *                         eCfgIllegal；**nRetryMax=0 为合法组态**（一次不过即故障）。
 *                         ⑤ 压力非有限 → eFault eNoData（R245）。
 *                         ⑥ bStop 在 eFault/eFill/eVent/eConfirm 中止回 eIdle；bStop 在
 *                         eRunning/eDone → eDone（正常停机完成态）；bReset 上升沿全清
 *                         nRetries（R311）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_PumpChangeoverSeq` 分工：引水启动 ≠ 主备切换；与
 *                         `FB_DL_PumpDryRunGuard`/`FB_DL_PumpDryRunProtect` 分工：引水
 *                         时序 ≠ 干转保护。
 * 来源标签 (Source Tag) : T2-2 ◐（LBP 工艺分层只借引水启动序分类事实，时序实现自研）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 七态 + UDINT 计数 +
 *                         BOOL 组 + ENUM 成因；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 压力判据 >= 比较 + 非有限分码 + 组态闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 七态 CASE 含 ELSE ｜ R7 ✓ 三 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 4 · 序号 20）
 *                         验收向量：灌液阀反馈超时 → eFbFill；确认失败重试递增回 eFill；
 *                         nRetries > nRetryMax → eNoPrime；压力达标 → eDone → eRunning。
 *==============================================================================*)

TYPE E_DL_PpsPhase :
(
    eIdle    := 0,    // 待机 / Idle
    eFill    := 10,   // 灌液相 / Filling phase
    eVent    := 20,   // 排气相 / Venting phase
    eConfirm := 30,   // 压力确认相 / Pressure confirmation phase
    eRunning := 40,   // 主运态（只出态不接管泵启停）/ Main-run state
    eDone    := 50,   // 引水序完成（正常停机驻留）/ Priming sequence done
    eFault   := 90    // 故障（等复位）/ Fault, awaiting reset
);
END_TYPE

TYPE E_DL_PpsCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eNoData     := 2,   // 压力非有限 / Non-finite pressure
    eFbFill     := 3,   // 灌液阀反馈超时（R190 独立成因）/ Fill valve feedback timeout
    eFbVent     := 4,   // 排气阀反馈超时（R190 独立成因）/ Vent valve feedback timeout
    eNoPrime    := 5    // 重试耗尽未引水成功 / Retry budget exhausted, no prime
);
END_TYPE

FUNCTION_BLOCK FB_DL_PumpPrimingSeq
VAR_INPUT
    bStart       : BOOL := FALSE;   // 启动沿（eIdle 入灌液相） [-] / Start edge
    bStop        : BOOL := FALSE;   // 中止/停机（运行相回 eDone，其余回 eIdle） [-] / Stop
    bReset       : BOOL := FALSE;   // 复位，上升沿清全部锁存含 nRetries（R311） [-] / Reset, clears all latches
    fPrOutKpa    : LREAL := 0.0;    // 泵出口压力实测 [kPa] / Pump outlet pressure [kPa]
    fPrPrimeKpa  : LREAL := 150.0;  // 引水成功判据压力，域 > 0 [kPa] / Prime success pressure [kPa]
    bFillValveFb : BOOL := FALSE;   // 灌液阀开启反馈 [-] / Fill valve feedback
    bVentValveFb : BOOL := FALSE;   // 排气阀开启反馈 [-] / Vent valve feedback
    tFill        : TIME := T#10S;   // 灌液阀反馈超时窗，域 > T#0S [ms] / Fill feedback timeout [ms]
    tVent        : TIME := T#10S;   // 排气阀反馈超时窗，域 > T#0S [ms] / Vent feedback timeout [ms]
    tConfirm     : TIME := T#30S;   // 压力确认窗，域 > T#0S [ms] / Pressure confirm window [ms]
    nRetryMax    : UDINT := 3;      // 重试上限（=0 合法：一次不过即故障） [次] / Retry ceiling, 0 legal
END_VAR
VAR_OUTPUT
    ePhase      : E_DL_PpsPhase;    // 当前相出口 [-] / Present phase outlet
    nRetries    : UDINT;            // 引水重试计数出口 [次] / Retry count outlet
    bFillActive : BOOL;             // 灌液相指示（兼灌液阀命令参考） [-] / Fill phase indicator
    bVentActive : BOOL;             // 排气相指示（兼排气阀命令参考） [-] / Vent phase indicator
    bConfirmActive: BOOL;           // 压力确认相指示 [-] / Confirm phase indicator
    bRunning    : BOOL;             // 主运态指示 [-] / Main-run indicator
    bDone       : BOOL;             // 引水序完成指示 [-] / Priming done indicator
    eCause      : E_DL_PpsCause;    // 成因出口（锁存回放，R189） / Cause outlet, latched
    bError      : BOOL;             // 故障标志 [-] / Error flag
END_VAR
VAR
    _eState : E_DL_PpsPhase := E_DL_PpsPhase.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause : E_DL_PpsCause := E_DL_PpsCause.eNone;   // 成因锁存量 / Latched cause
    _bFault : BOOL;              // 故障锁存位（解除沿 = bReset 上升沿） / Latched fault bit
    _nRetry : UDINT := 0;        // 重试计数锁存量（bReset/bStop 全清） / Retry count latch
    _bNonFin: BOOL;              // 压力非有限当拍量 [-] / Non-finite pressure this scan
    _bCfgBad: BOOL;              // 组态非法当拍量 [-] / Illegal configuration this scan
    tonFbFill  : TON;            // 灌液阀反馈超时定时器，段 0 无条件调用 / Fill feedback timeout timer
    tonFbVent  : TON;            // 排气阀反馈超时定时器，段 0 无条件调用 / Vent feedback timeout timer
    tonConfirm : TON;            // 压力确认窗定时器，段 0 无条件调用 / Pressure confirm timer
    rtStart    : R_TRIG;         // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset    : R_TRIG;         // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_PPS_ZERO  : LREAL := 0.0;     // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_PPS_UDMAX : UDINT := 4294967295;   // UDINT 上限（重试计数饱和点） [次] / UDINT ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 三 TON 两沿无条件周期刷新 —— *)
_bNonFin := (fPrOutKpa <> fPrOutKpa) OR ((fPrOutKpa - fPrOutKpa) <> DL_PPS_ZERO);   // 压力非有限（R245） / Non-finite pressure
_bCfgBad := (fPrPrimeKpa <= 0.0) OR (tFill <= T#0S) OR (tVent <= T#0S)
         OR (tConfirm <= T#0S);                         // 组态域闸（nRetryMax=0 合法不过闸） / Configuration gate
rtStart(CLK := bStart);                                 // 启动沿，每拍必调 / Start edge, every scan
rtReset(CLK := bReset);                                 // 复位沿，每拍必调 / Reset edge, every scan
tonFbFill(IN := (_eState = E_DL_PpsPhase.eFill) AND (NOT bFillValveFb), PT := tFill);    // 灌液反馈超时（反馈到即自复位） / Fill feedback timeout
tonFbVent(IN := (_eState = E_DL_PpsPhase.eVent) AND (NOT bVentValveFb), PT := tVent);    // 排气反馈超时 / Vent feedback timeout
tonConfirm(IN := (_eState = E_DL_PpsPhase.eConfirm), PT := tConfirm);   // 压力确认窗 / Pressure confirm window

(* —— 段 1：单拍量预清零（_eState/_eCause/_bFault/_nRetry 锁存量不入清单，R107） —— *)
bFillActive := FALSE;                                   // 灌液相指示预清 / Fill indicator preset
bVentActive := FALSE;                                   // 排气相指示预清 / Vent indicator preset
bConfirmActive := FALSE;                                // 确认相指示预清 / Confirm indicator preset
bRunning := FALSE;                                      // 主运指示预清 / Running preset
bDone := FALSE;                                         // 完成指示预清 / Done preset
bError := FALSE;                                        // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸入故障 —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;                                    // 锁存 / Latch
    _eCause := E_DL_PpsCause.eCfgIllegal;               // 归因：组态非法 / Cause: illegal config
    _eState := E_DL_PpsPhase.eFault;                    // 入故障相 / Enter fault
END_IF

(* —— 段 3：迁出链（bStop 分域语义 + bReset 全清 R311） —— *)
IF bStop AND (_eState <> E_DL_PpsPhase.eIdle) THEN
    IF (_eState = E_DL_PpsPhase.eRunning) OR (_eState = E_DL_PpsPhase.eDone) THEN
        _eState := E_DL_PpsPhase.eDone;                 // 运行/完成相停机 → eDone（正常停机完成态，头注释⑥） / Stop in run: to done
    ELSE
        IF _eState = E_DL_PpsPhase.eFault THEN
            _bFault := FALSE;                           // 停机优先清故障 / Stop wins over fault
            _eCause := E_DL_PpsCause.eNone;             // 清成因 / Clear cause
        END_IF
        _nRetry := 0;                                   // 中止全清重试计数（R311 同族） / Clear retries on abort
        _eState := E_DL_PpsPhase.eIdle;                 // 其余相中止回 eIdle / Abort to idle
    END_IF
END_IF
IF rtReset.Q THEN
    _bFault := FALSE;                                   // 清故障锁存（R311） / Clear fault latch
    _eCause := E_DL_PpsCause.eNone;                     // 清成因 / Clear cause
    _nRetry := 0;                                       // 复位沿全清重试计数（规格⑥） / Clear retries on reset edge
    _eState := E_DL_PpsPhase.eIdle;                     // 回待机 / Back to idle
END_IF

(* —— 段 4：七态顺控（只在无故障时推进；压力非有限 → eFault eNoData） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND (NOT bStop) THEN
    IF _bNonFin AND (_eState <> E_DL_PpsPhase.eIdle) AND (_eState <> E_DL_PpsPhase.eDone) THEN
        _bFault := TRUE;                                // 运行相压力非有限：故障锁存（规格⑤） / Non-finite in running phase
        _eCause := E_DL_PpsCause.eNoData;               // 归因分码：无有效数据 / Cause: no data
        _eState := E_DL_PpsPhase.eFault;                // 入故障相 / Enter fault
    ELSE
        CASE _eState OF

        E_DL_PpsPhase.eIdle:
            IF rtStart.Q THEN
                _nRetry := 0;                           // 新启动清重试计数 / Clear retries on new start
                _eState := E_DL_PpsPhase.eFill;         // 入灌液相 / Enter fill
            END_IF

        E_DL_PpsPhase.eFill:
            IF bFillValveFb THEN
                _eState := E_DL_PpsPhase.eVent;         // 灌液阀反馈到：进排气相 / Fill feedback: enter vent
            ELSIF tonFbFill.Q THEN
                _eCause := E_DL_PpsCause.eFbFill;       // 灌液反馈超时（R190 独立成因） / Fill feedback timeout
                _bFault := TRUE;                        // 锁存 / Latch
                _eState := E_DL_PpsPhase.eFault;        // 入故障相 / Enter fault
            END_IF

        E_DL_PpsPhase.eVent:
            IF bVentValveFb THEN
                _eState := E_DL_PpsPhase.eConfirm;      // 排气阀反馈到：进压力确认相 / Vent feedback: enter confirm
            ELSIF tonFbVent.Q THEN
                _eCause := E_DL_PpsCause.eFbVent;       // 排气反馈超时（R190 独立成因） / Vent feedback timeout
                _bFault := TRUE;                        // 锁存 / Latch
                _eState := E_DL_PpsPhase.eFault;        // 入故障相 / Enter fault
            END_IF

        E_DL_PpsPhase.eConfirm:
            IF fPrOutKpa >= fPrPrimeKpa THEN
                _eState := E_DL_PpsPhase.eRunning;      // 压力达标：转主运态（>= 判据禁浮点 =） / Pressure reached: to running
            ELSIF tonConfirm.Q THEN
                IF _nRetry < DL_PPS_UDMAX THEN
                    _nRetry := _nRetry + 1;             // 确认失败重试递增（饱和不回绕） / Increment retry, saturating
                END_IF
                IF _nRetry > nRetryMax THEN
                    _eCause := E_DL_PpsCause.eNoPrime;  // 重试耗尽（nRetryMax=0 时首轮即故障，合法） / Retry budget exhausted
                    _bFault := TRUE;                    // 锁存 / Latch
                    _eState := E_DL_PpsPhase.eFault;    // 入故障相 / Enter fault
                ELSE
                    _eState := E_DL_PpsPhase.eFill;     // 未耗尽：回灌液相重试 / Retry from fill
                END_IF
            END_IF

        E_DL_PpsPhase.eRunning:
            ;                                           // 主运驻留：本件只出态不接管泵启停（头注释①） / Held, pump control out of scope

        E_DL_PpsPhase.eDone:
            ;                                           // 完成驻留：由 bStop/bReset 迁出 / Held, exits via stop or reset

        E_DL_PpsPhase.eFault:
            ;                                           // 故障驻留：由迁出链处理 / Held by exit chain

        ELSE
            _eCause := E_DL_PpsCause.eCfgIllegal;       // 非法相位兜底归因 / Illegal phase cause
            _bFault := TRUE;                            // 锁存 / Latch
            _eState := E_DL_PpsPhase.eFault;            // 强拉故障相 / Force fault

        END_CASE
    END_IF
END_IF

(* —— 段 8：出口单点映射（相指示与相别同源，R191） —— *)
bFillActive := (_eState = E_DL_PpsPhase.eFill);         // 灌液相指示 / Fill indicator
bVentActive := (_eState = E_DL_PpsPhase.eVent);         // 排气相指示 / Vent indicator
bConfirmActive := (_eState = E_DL_PpsPhase.eConfirm);   // 确认相指示 / Confirm indicator
bRunning := (_eState = E_DL_PpsPhase.eRunning);         // 主运指示 / Running indicator
bDone := (_eState = E_DL_PpsPhase.eDone);               // 完成指示 / Done indicator
ePhase := _eState;                                      // 当前相出口 / Present phase outlet
nRetries := _nRetry;                                    // 重试计数出口 / Retry count outlet
eCause := _eCause;                                      // 成因出口 / Cause outlet
bError := _bFault OR _bCfgBad;                          // 故障标志 = 锁存或组态非法 / Error flag

END_FUNCTION_BLOCK
