(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ModulePottingVac
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 灌胶真空脱泡四相顺控：抽真空 → 保持 → 破空 → 泄压。
 *                         每相一个**专用** TON，PT 语义各自成对写死，绝不共用一个实例改 PT：
 *                           eEvac   抽真空：tonEvacTo  PT = tEvac    （到真空位 bVacReached 即过相）
 *                           eHold   保持  ：tonHoldTo  PT = tHold    （纯定时过相，无外部条件）
 *                           eBreak  破空  ：tonBreakTo PT = tBreak   （到常压位 bBreakDone 即过相）
 *                           eRelief 泄压  ：tonReliefTo PT = tRelief （纯定时过相，完成后回 eIdle）
 *                         每相的"过相条件"= 定时到 ∧ 该相到位信号（有到位信号的两相）；定时到但
 *                         到位信号没来 = 该相超时 → eFault（归因按相区分：eVacTimeout /
 *                         eBreakTimeout）。保持相与泄压相无到位信号，定时到即过相。
 *                         **eFault 可迁出**：bReset 上升沿 → 回 eIdle 并清 _eFaultFrom；同时 eFault
 *                         记录"从哪一相跌进故障"（_eFaultFrom），供 HMI 指明卡在哪一步。
 *                         bStop 在任一相立即可用 → 回 eIdle（中止，bAborted 单拍脉冲），中途中止
 *                         不记故障（操作员主动停机不是故障）。
 * 接口     (Interface)  : 输入 bStart 启动沿、bStop 中止、bVacReached 真空到位、bBreakDone 破空
 *                         到位、四相时间 tEvac / tHold / tBreak / tRelief、bReset 故障复位；
 *                         输出 bEvacActive / bHoldActive / bBreakActive / bReliefActive 四相指示、
 *                         bBusy 顺控进行中、bComplete 完成单拍、bAborted 中止单拍、ePhase 当前相、
 *                         eFaultFrom 跌入故障的相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做四相时序编排，不驱动真空泵/破空阀/
 *                         泄压阀线圈**。阀/泵动作由 IO 映射层与执行件（`I_DL_Cylinder` 族或
 *                         阀门件）负责；本件出相指示位，由上层映射到实际输出。
 *                         ② 组态闸：任一相时间 <= T#0S → 故障锁存（零时长会让相瞬间过相，
 *                         工艺上等于跳过该相，是危险默认）。
 *                         ③ 四枚专用超时 TON（tonEvacTo / tonHoldTo / tonBreakTo / tonReliefTo）
 *                         在段 0 **无条件周期调用**，IN 由"当前相"表达式派生：进相即计时、出相即
 *                         复位，因此不存在跨相累积（R228A：专用超时 TON 命名豁免 + IN 表达式派生）；
 *                         PT 各绑一个专用时间引脚，绝不复用实例改 PT。
 *                         ④ eFault 迁出链：bReset 上升沿 → eIdle（清 _eFaultFrom 与 _eCause）；
 *                         bStop 亦可在故障相把相序拉回 eIdle（停机优先于故障保持），两条路径
 *                         都在段 3 显式写出（R228B 可迁出）。
 *                         ⑤ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 *                         ⑥ **到位信号沿锁存语义（v1.0.1 修订）**：bVacReached / bBreakDone 允许
 *                         为短脉冲型（如压力开关瞬时动作）——两路各设 R_TRIG（段 0 无条件刷新）
 *                         + 锁存量 _bVacSeen / _bBreakSeen，进相首拍清锁存、捕获到位沿后置位；
 *                         过相判据读锁存量（tonEvacTo.Q AND _bVacSeen），脉冲先于超时 TON 到 Q
 *                         消失不再误报超时；持续到位信号行为不变（契约兼容）；迁出链（复位沿 /
 *                         bStop）同时清两锁存量，防跨循环残留。
 * 分工声明 (Scope)      : 与 `FB_DL_PressureDecayTest` 一类气密测试件分工——那件判"密封性"
 *                         （压降速率），本件只管"四相走完没走完、有没有卡相"；不共用判据。
 * 来源标签 (Source Tag) : ROADMAP B 类 / T2-8（灌胶真空脱泡四相顺控，自研 clean-room）
 * 解除式   (Release)    : bReset 上升沿 ∨ bStop（停机优先）→ 回 eIdle 并清故障记录。
 *                         自证可满足：两个外部信号均为操作员级动作，不受任何锁存量门控；
 *                         不存在"必须先到某相才能复位"的隐含前置。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 相别 + ENUM 成因 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 时间域几何闸 + 无浮点比较 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ 四 TON/两沿段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 4 · 序号 19）
 *                         2026-11-20  v1.0.1  R47 终审轻项返修：到位脉冲先于超时 TON 到 Q 消失
 *                         导致过相判据恒假误报超时；增到位沿 R_TRIG 锁存 _bVacSeen/_bBreakSeen，
 *                         过相判据改读锁存量，迁出链清锁存；引脚契约零变更，V1~V3 向量保持。
 *==============================================================================*)

TYPE E_DL_MpvPhase :
(
    eIdle   := 0,    // 待机相 / Idle
    eEvac   := 10,   // 抽真空相 / Evacuation
    eHold   := 20,   // 真空保持相 / Vacuum hold
    eBreak  := 30,   // 破空相 / Air break
    eRelief := 40,   // 泄压相 / Pressure relief
    eFault  := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_MpvCause :
(
    eNone         := 0,   // 无异常 / No anomaly
    eCfgIllegal   := 1,   // 组态非法（相时间非正） / Illegal configuration
    eVacTimeout   := 2,   // 抽真空相超时（未到真空位） / Evacuation timed out before reaching vacuum
    eBreakTimeout := 3,   // 破空相超时（未到常压位） / Air break timed out before reaching atmosphere
    ePhaseBad     := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ModulePottingVac
VAR_INPUT
    bStart      : BOOL := FALSE;        // 启动沿，进入抽真空相 [-] / Start edge, enters evacuation
    bStop       : BOOL := FALSE;        // 中止（停机优先，任一相可用） [-] / Abort, honoured in every phase
    bVacReached : BOOL := FALSE;        // 真空到位信号（抽真空相过相条件） [-] / Vacuum reached, evacuation exit condition
    bBreakDone  : BOOL := FALSE;        // 破空到位信号（破空相过相条件） [-] / Atmosphere reached, air-break exit condition
    tEvac       : TIME := T#30S;        // 抽真空相超时，域 > T#0S [ms] / Evacuation timeout, > T#0S [ms]
    tHold       : TIME := T#10S;        // 真空保持时长，域 > T#0S [ms] / Vacuum hold duration, > T#0S [ms]
    tBreak      : TIME := T#10S;        // 破空相超时，域 > T#0S [ms] / Air-break timeout, > T#0S [ms]
    tRelief     : TIME := T#5S;         // 泄压时长，域 > T#0S [ms] / Pressure-relief duration, > T#0S [ms]
    bReset      : BOOL := FALSE;        // 故障复位，上升沿回待机相 [-] / Fault reset, rising edge returns to idle
END_VAR
VAR_OUTPUT
    bEvacActive   : BOOL;               // 抽真空相进行中 [-] / Evacuation phase active
    bHoldActive   : BOOL;               // 真空保持相进行中 [-] / Hold phase active
    bBreakActive  : BOOL;               // 破空相进行中 [-] / Air-break phase active
    bReliefActive : BOOL;               // 泄压相进行中 [-] / Relief phase active
    bBusy         : BOOL;               // 顺控进行中（非待机非故障） [-] / Sequence busy
    bComplete     : BOOL;               // 四相完成，单拍脉冲 [-] / Sequence complete, single-scan pulse
    bAborted      : BOOL;               // 中止，单拍脉冲 [-] / Aborted, single-scan pulse
    ePhase        : E_DL_MpvPhase;      // 当前相出口 [-] / Present phase outlet
    eFaultFrom    : E_DL_MpvPhase;      // 跌入故障时所处的相（诊断用） [-] / Phase that faulted
    eCause        : E_DL_MpvCause;      // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError        : BOOL;               // 故障标志（组态非法或相超时） [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_MpvPhase := E_DL_MpvPhase.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eFaultFrom: E_DL_MpvPhase := E_DL_MpvPhase.eIdle;    // 故障来源相（锁存量） / Faulting phase, latched
    _eCause    : E_DL_MpvCause := E_DL_MpvCause.eNone;    // 成因锁存量 / Latched cause
    tonEvacTo  : TON;           // 抽真空相专用超时，段 0 无条件调用 / Evacuation dedicated timeout
    tonHoldTo  : TON;           // 真空保持相专用时长，段 0 无条件调用 / Hold dedicated duration
    tonBreakTo : TON;           // 破空相专用超时，段 0 无条件调用 / Air-break dedicated timeout
    tonReliefTo: TON;           // 泄压相专用时长，段 0 无条件调用 / Relief dedicated duration
    rtStart    : R_TRIG;        // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset    : R_TRIG;        // 复位沿实例，段 0 无条件调用 / Reset edge instance
    rtVacIn    : R_TRIG;        // 真空到位沿实例，段 0 无条件调用 / Vacuum-reached edge instance
    rtBreakIn  : R_TRIG;        // 破空到位沿实例，段 0 无条件调用 / Break-done edge instance
    _bVacSeen  : BOOL;          // 真空到位沿锁存（进相清、捕获沿置位） / Vacuum-reached edge latch
    _bBreakSeen: BOOL;          // 破空到位沿锁存（进相清、捕获沿置位） / Break-done edge latch
    _bFault    : BOOL;          // 故障锁存位（锁存量） / Latched fault bit
    _bCfgBad   : BOOL;          // 组态非法当拍量 [-] / Illegal configuration this scan
    _bBusyPrev : BOOL;          // 上拍忙碌快照（用于完成脉冲） / Busy snapshot for the completion pulse
END_VAR

(* —— 段 0：组态闸 + 四枚专用 TON 与两枚沿无条件周期刷新 —— *)
_bCfgBad := (tEvac <= T#0S) OR (tHold <= T#0S)                  // 抽真空/保持时长须为正 / Evacuation and hold durations must be positive
         OR (tBreak <= T#0S) OR (tRelief <= T#0S);              // 破空/泄压时长须为正 / Break and relief durations must be positive
rtStart(CLK := bStart);                                          // 启动沿，每拍必调（R228A） / Start edge, every scan
rtReset(CLK := bReset);                                          // 复位沿，每拍必调 / Reset edge, every scan
rtVacIn(CLK := bVacReached);                                     // 真空到位沿，每拍必调 / Vacuum-reached edge, every scan
rtBreakIn(CLK := bBreakDone);                                    // 破空到位沿，每拍必调 / Break-done edge, every scan
tonEvacTo(IN := (_eState = E_DL_MpvPhase.eEvac), PT := tEvac);        // 抽真空相专用超时（进相计时，出相自复位） / Evacuation dedicated timeout
tonHoldTo(IN := (_eState = E_DL_MpvPhase.eHold), PT := tHold);        // 保持相专用时长 / Hold dedicated duration
tonBreakTo(IN := (_eState = E_DL_MpvPhase.eBreak), PT := tBreak);     // 破空相专用超时 / Air-break dedicated timeout
tonReliefTo(IN := (_eState = E_DL_MpvPhase.eRelief), PT := tRelief);  // 泄压相专用时长 / Relief dedicated duration

(* —— 段 1：单拍量预清零（锁存量 _eFaultFrom/_eCause/_bFault/_bBusyPrev 不入清单，R107） —— *)
bEvacActive   := FALSE;     // 抽真空相指示预清 / Evacuation indicator preset
bHoldActive   := FALSE;     // 保持相指示预清 / Hold indicator preset
bBreakActive  := FALSE;     // 破空相指示预清 / Break indicator preset
bReliefActive := FALSE;     // 泄压相指示预清 / Relief indicator preset
bBusy         := FALSE;     // 忙碌指示预清 / Busy preset
bComplete     := FALSE;     // 完成脉冲预清 / Complete pulse preset
bAborted      := FALSE;     // 中止脉冲预清 / Aborted pulse preset
bError        := FALSE;     // 故障标志预清（R45 配对） / Error flag preset

(* —— 段 2：组态闸（相时间非正即故障，记录来源相） —— *)
IF _bCfgBad THEN
    IF _eState <> E_DL_MpvPhase.eFault THEN
        _eFaultFrom := _eState;                         // 记录跌入故障时所在相 / Record the phase that faulted
    END_IF
    _bFault := TRUE;                                    // 锁存 / Latch
    _eCause := E_DL_MpvCause.eCfgIllegal;               // 归因：组态非法 / Cause: illegal configuration
    _eState := E_DL_MpvPhase.eFault;                    // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿 或 bStop 停机优先；两条都显式写出，R228B） —— *)
IF rtReset.Q THEN
    _bFault     := FALSE;                               // 清故障锁存 / Clear the fault latch
    _eCause     := E_DL_MpvCause.eNone;                 // 清成因 / Clear cause
    _eFaultFrom := E_DL_MpvPhase.eIdle;                 // 清来源相 / Clear the faulting phase
    _bVacSeen   := FALSE;                               // 清真空到位锁存（迁出链防残留，R310/R311） / Clear vacuum latch on exit chain
    _bBreakSeen := FALSE;                               // 清破空到位锁存（迁出链防残留，R310/R311） / Clear break latch on exit chain
    _eState     := E_DL_MpvPhase.eIdle;                 // 回待机相（迁出路径 1） / Back to idle, exit path 1
END_IF
IF bStop AND (_eState <> E_DL_MpvPhase.eIdle) THEN
    bAborted := TRUE;                                   // 中止脉冲 / Abort pulse
    IF _eState = E_DL_MpvPhase.eFault THEN
        _bFault := FALSE;                               // 停机优先：故障相也允许被停机清出 / Stop wins, clears even the fault
        _eCause := E_DL_MpvCause.eNone;                 // 清成因 / Clear cause
    END_IF
    _eFaultFrom := E_DL_MpvPhase.eIdle;                 // 清来源相 / Clear the faulting phase
    _bVacSeen   := FALSE;                               // 清真空到位锁存（迁出链防残留） / Clear vacuum latch on exit chain
    _bBreakSeen := FALSE;                               // 清破空到位锁存（迁出链防残留） / Clear break latch on exit chain
    _eState     := E_DL_MpvPhase.eIdle;                 // 回待机相（迁出路径 2） / Back to idle, exit path 2
END_IF

(* —— 段 4：顺控相迁移（只在无故障时推进；每相出口条件显式成对） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND (NOT bStop) THEN
    CASE _eState OF

    E_DL_MpvPhase.eIdle:
        IF rtStart.Q THEN
            _bVacSeen := FALSE;                                 // 进相首拍清到位锁存（防跨循环残留） / Clear vacuum latch on phase entry
            _eState := E_DL_MpvPhase.eEvac;                     // 启动沿入抽真空相 / Start edge enters evacuation
        END_IF

    E_DL_MpvPhase.eEvac:
        IF rtVacIn.Q THEN
            _bVacSeen := TRUE;                                  // 捕获真空到位沿并锁存（脉冲型兼容） / Capture vacuum-reached edge into latch
        END_IF
        IF tonEvacTo.Q AND _bVacSeen THEN
            _eState := E_DL_MpvPhase.eHold;                     // 定时到 ∧ 真空到位锁存：进保持相 / Timer done and vacuum latch set
        ELSIF tonEvacTo.Q AND (NOT _bVacSeen) THEN
            _eFaultFrom := E_DL_MpvPhase.eEvac;                 // 记录故障来源相 / Record the faulting phase
            _bFault := TRUE;                                    // 锁存 / Latch
            _eCause := E_DL_MpvCause.eVacTimeout;               // 归因：抽真空超时 / Cause: evacuation timeout
            _eState := E_DL_MpvPhase.eFault;                    // 入故障相 / Enter fault phase
        END_IF

    E_DL_MpvPhase.eHold:
        IF tonHoldTo.Q THEN
            _bBreakSeen := FALSE;                               // 进破空相首拍清到位锁存（防跨循环残留） / Clear break latch on phase entry
            _eState := E_DL_MpvPhase.eBreak;                    // 保持时长到：进破空相 / Hold done enters air break
        END_IF

    E_DL_MpvPhase.eBreak:
        IF rtBreakIn.Q THEN
            _bBreakSeen := TRUE;                                // 捕获破空到位沿并锁存（脉冲型兼容） / Capture break-done edge into latch
        END_IF
        IF tonBreakTo.Q AND _bBreakSeen THEN
            _eState := E_DL_MpvPhase.eRelief;                   // 定时到 ∧ 破空到位锁存：进泄压相 / Timer done and break latch set
        ELSIF tonBreakTo.Q AND (NOT _bBreakSeen) THEN
            _eFaultFrom := E_DL_MpvPhase.eBreak;                // 记录故障来源相 / Record the faulting phase
            _bFault := TRUE;                                    // 锁存 / Latch
            _eCause := E_DL_MpvCause.eBreakTimeout;             // 归因：破空超时 / Cause: air-break timeout
            _eState := E_DL_MpvPhase.eFault;                    // 入故障相 / Enter fault phase
        END_IF

    E_DL_MpvPhase.eRelief:
        IF tonReliefTo.Q THEN
            _eState := E_DL_MpvPhase.eIdle;                     // 泄压完成：回待机相 / Relief done returns to idle
        END_IF

    E_DL_MpvPhase.eFault:
        ;                                                       // 故障相：由段 3 两条迁出路径处理 / Handled by the two exit paths in stage 3

    ELSE
        _eFaultFrom := _eState;                                 // 记录异常相 / Record the anomalous phase
        _eCause := E_DL_MpvCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                        // 锁存 / Latch
        _eState := E_DL_MpvPhase.eFault;                        // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 5：完成脉冲（由"忙碌→空闲"且无中止无故障的沿派生，单拍） —— *)
IF _bBusyPrev AND (_eState = E_DL_MpvPhase.eIdle) AND (NOT bAborted) AND (NOT _bFault) THEN
    bComplete := TRUE;                                          // 四相走完 / All four phases finished
END_IF
_bBusyPrev := (_eState <> E_DL_MpvPhase.eIdle) AND (_eState <> E_DL_MpvPhase.eFault);   // 忙碌快照（本拍末） / Busy snapshot at body end

(* —— 段 6：出口单点映射（相指示与相别同源，R191） —— *)
bEvacActive   := (_eState = E_DL_MpvPhase.eEvac);               // 抽真空相指示 / Evacuation indicator
bHoldActive   := (_eState = E_DL_MpvPhase.eHold);               // 保持相指示 / Hold indicator
bBreakActive  := (_eState = E_DL_MpvPhase.eBreak);              // 破空相指示 / Break indicator
bReliefActive := (_eState = E_DL_MpvPhase.eRelief);             // 泄压相指示 / Relief indicator
bBusy         := (_eState <> E_DL_MpvPhase.eIdle) AND (_eState <> E_DL_MpvPhase.eFault);   // 忙碌 / Busy
bError        := _bFault OR _bCfgBad;                           // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
ePhase        := _eState;                                       // 当前相出口 / Present phase outlet
eFaultFrom    := _eFaultFrom;                                   // 故障来源相出口 / Faulting phase outlet
eCause        := _eCause;                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
