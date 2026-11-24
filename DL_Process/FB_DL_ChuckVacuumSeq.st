(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ChuckVacuumSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 卡盘真空吸附 / 释放顺控（四段：吸附 → 到位确认 → 加工互锁 → 破空释放）。
 *                         每相一枚**专用** TON，PT 各绑一个时间引脚，绝不共用实例改 PT：
 *                           eVacOn   吸附  ：tonVacTo  PT = tVacTo   （到位 bVacOk 即过相）
 *                           eConfirm 确认  ：tonConfTo PT = tConfirm （纯定时确认窗，窗内真空须保持）
 *                           eClamp   加工  ：无计时器，等 bProcessDone（外部加工完成）
 *                           eVent    释放  ：tonVentTo PT = tVentTo  （到位 bVentOk 即回待机）
 *                         到位判据：吸附相"定时到但未到位" → eVacTimeout；释放相"定时到但未破空" →
 *                         eVentTimeout；确认窗内真空掉落 → eVacLost（真空夹持不可中断）。
 *                         **加工互锁先于顺控**：加工进行中（bProcessActive）拒绝释放请求
 *                         （bReleaseReq），只置 bReleaseBlocked 单拍，不改变相（互锁优先级最高）。
 *                         验收向量：
 *                           ① 启动 → bVacValve 开；bVacOk 到 → eConfirm；tConfirm 到 → eClamp
 *                           ② eClamp 且 bProcessActive 时按释放请求 → 拒绝（bReleaseBlocked 单拍）
 *                           ③ bProcessDone 到 → eVent：bVacValve 关、bVentValve 开；bVentOk 到 → eIdle
 *                           ④ eVacOn 超时未到位 → eVacTimeout 锁存；eConfirm 窗内真空掉 → eVacLost 锁存
 * 接口     (Interface)  : 入 bStart 启动沿、bVacOk 真空到位、bVentOk 破空到位、bProcessDone 加工完成、
 *                         bProcessActive 加工进行中（互锁源）、bReleaseReq 释放请求、bStop 中止、
 *                         tVacTo 吸附超时、tConfirm 确认窗、tVentTo 破空超时、bReset 复位沿；
 *                         出 bVacValve 真空阀位、bVentValve 破空阀位、bClamped 夹持中、
 *                         bBusy 顺控进行中、bDone 完成脉冲（单拍）、bAborted 中止脉冲（单拍）、
 *                         bReleaseBlocked 释放被互锁拒绝（单拍）、ePhase 当前相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出阀位与夹持指示，不驱动真空发生器/
 *                         电磁阀线圈、不判晶圆是否在位**（属 IO 映射层与在位检测件）；
 *                         ② **组态闸**：三个时间 ≤ T#0S → 锁存 eCfgIllegal；**互锁一致性闸**：
 *                         bProcessActive 为真而本件处于释放相 → 锁存 eInterlockViolation（防止外部
 *                         互锁源与顺控相位脱节）；
 *                         ③ **一相一 TON**：三枚专用 TON 在段 0 无条件调用，IN 由"当前相"表达式派生，
 *                         进相计时、出相复位，无跨相累积（R228A/R275）；
 *                         ④ **相驻留失守**：eConfirm 相真空掉落 → 立即落故障（驻留条件失守，R163）；
 *                         ⑤ **eFault 可迁出**：bReset 上升沿 → eIdle；bStop 亦可在非故障相回 eIdle，
 *                         但 eClamp 相中止需先破空，故中止统一走 eVent 相（安全侧）；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"卡盘吸附/释放四段时序与加工互锁"。不接管：真空度模拟量判读
 *                         （属模拟量件）、吸盘环真空（属 FB_DL_VacCupRingCtrl）、
 *                         腔体抽真空（属 FB_DL_ChamberPumpDownSeq）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（卡盘真空序，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 组态闸 + 相超时 + 互锁一致性闸 + 驻留失守 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ 三 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 3 · 序号 13）
 *==============================================================================*)

TYPE E_DL_CvsPhase :
(
    eIdle   := 0,    // 待机相（阀位全关） / Idle, valves closed
    eVacOn  := 10,   // 吸附相（抽真空等到位） / Vacuum-on, waiting for vacuum
    eConfirm:= 20,   // 确认相（真空保持确认窗） / Confirmation window
    eClamp  := 30,   // 加工相（夹持中，等加工完成） / Clamped, waiting for process completion
    eVent   := 40,   // 释放相（破空等到位） / Venting, waiting for atmosphere
    eFault  := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_CvsCause :
(
    eNone            := 0,   // 无异常 / No anomaly
    eCfgIllegal      := 1,   // 组态非法（时间非正） / Illegal configuration
    eVacTimeout      := 2,   // 吸附超时未到位 / Vacuum timeout
    eVentTimeout     := 3,   // 破空超时未到位 / Vent timeout
    eVacLost         := 4,   // 确认窗内真空掉（驻留失守） / Vacuum lost inside the confirmation window
    eInterlockViolation:= 5, // 互锁相位矛盾（加工中处于释放相） / Interlock contradiction
    ePhaseBad        := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChuckVacuumSeq
VAR_INPUT
    bStart         : BOOL := FALSE;   // 启动沿，进入吸附相 [-] / Start edge, enters vacuum-on
    bVacOk         : BOOL := FALSE;   // 真空到位信号 [-] / Vacuum reached
    bVentOk        : BOOL := FALSE;   // 破空到位信号 [-] / Atmosphere reached
    bProcessDone   : BOOL := FALSE;   // 加工完成信号 [-] / Process finished
    bProcessActive : BOOL := FALSE;   // 加工进行中（互锁源，TRUE 时禁释放） [-] / Process active, release inhibited
    bReleaseReq    : BOOL := FALSE;   // 释放请求 [-] / Release request
    bStop          : BOOL := FALSE;   // 中止（安全侧：先进破空再回待机） [-] / Abort, vents first
    tVacTo         : TIME := T#10S;   // 吸附超时，域 > T#0S [ms] / Vacuum timeout
    tConfirm       : TIME := T#2S;    // 真空保持确认窗，域 > T#0S [ms] / Vacuum-hold confirmation window
    tVentTo        : TIME := T#10S;   // 破空超时，域 > T#0S [ms] / Vent timeout
    bReset         : BOOL := FALSE;   // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    bVacValve   : BOOL := FALSE;                          // 真空阀位 [-] / Vacuum valve position
    bVentValve  : BOOL := FALSE;                          // 破空阀位 [-] / Vent valve position
    bClamped    : BOOL := FALSE;                          // 夹持中（真空建立且确认过） [-] / Clamped
    bBusy       : BOOL := FALSE;                          // 顺控进行中 [-] / Sequence busy
    bDone       : BOOL := FALSE;                          // 完成脉冲（单拍） [-] / Completion pulse, single scan
    bAborted    : BOOL := FALSE;                          // 中止脉冲（单拍） [-] / Abort pulse, single scan
    bReleaseBlocked : BOOL := FALSE;                      // 释放被互锁拒绝（单拍） [-] / Release blocked by the interlock
    ePhase      : E_DL_CvsPhase := E_DL_CvsPhase.eIdle;   // 当前相出口 [-] / Present phase outlet
    eCause      : E_DL_CvsCause := E_DL_CvsCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL := FALSE;                          // 故障标志 [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_CvsPhase := E_DL_CvsPhase.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_CvsCause := E_DL_CvsCause.eNone;    // 成因锁存量 / Latched cause
    _bFault    : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bDone     : BOOL := FALSE;                           // 完成脉冲内部位（单拍） / Internal completion pulse
    _bAborted  : BOOL := FALSE;                           // 中止脉冲内部位（单拍） / Internal abort pulse
    _bRelBlock : BOOL := FALSE;                           // 释放被拒内部位（单拍） / Internal release-blocked flag
    _bCfgBad   : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _bBusyPrev : BOOL := FALSE;                           // 上拍忙碌快照 / Busy snapshot of the previous scan
    tonVacTo   : TON;                                     // 吸附相专用超时，段 0 无条件调用 / Vacuum dedicated timeout
    tonConfTo  : TON;                                     // 确认相专用窗，段 0 无条件调用 / Confirmation dedicated window
    tonVentTo  : TON;                                     // 释放相专用超时，段 0 无条件调用 / Vent dedicated timeout
    rtStart    : R_TRIG;                                  // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset    : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_CVS_MS   : INT := 0;               // 占位性零值常量（保持常量区非空，非事件码） [-] / Zero constant, not an event code
END_VAR

(* —— 段 0：组态闸 + 三枚专用 TON 与两沿无条件周期刷新（R228A/R275） —— *)
_bCfgBad := (tVacTo <= T#0S) OR (tConfirm <= T#0S) OR (tVentTo <= T#0S);                    // 三时间须为正 / All three times positive
rtStart(CLK := bStart);                                                                      // 启动沿 / Start edge
rtReset(CLK := bReset);                                                                      // 复位沿 / Reset edge
tonVacTo(IN := (_eState = E_DL_CvsPhase.eVacOn), PT := tVacTo);                               // 吸附相专用超时 / Vacuum timeout
tonConfTo(IN := (_eState = E_DL_CvsPhase.eConfirm), PT := tConfirm);                          // 确认相专用窗 / Confirmation window
tonVentTo(IN := (_eState = E_DL_CvsPhase.eVent), PT := tVentTo);                              // 释放相专用超时 / Vent timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bBusyPrev 不入清单，R107） —— *)
_bDone     := FALSE;                                                                          // 完成脉冲预清 / Completion pulse preset
_bAborted  := FALSE;                                                                          // 中止脉冲预清 / Abort pulse preset
_bRelBlock := FALSE;                                                                          // 释放被拒预清 / Release-blocked preset
bError     := FALSE;                                                                          // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（时间非正即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_CvsCause.eCfgIllegal;                                                    // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                                          // 锁存 / Latch
    _eState := E_DL_CvsPhase.eFault;                                                          // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿 → 待机相；解除式恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                                          // 清故障锁存 / Clear fault latch
    _eCause := E_DL_CvsCause.eNone;                                                            // 清成因 / Clear cause
    _eState := E_DL_CvsPhase.eIdle;                                                            // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（顺控 + 互锁；互锁判定先于顺控推进） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_CvsPhase.eIdle:
        IF rtStart.Q THEN
            _eState := E_DL_CvsPhase.eVacOn;                                                   // 启动沿进吸附相 / Enter vacuum-on
        END_IF

    E_DL_CvsPhase.eVacOn:
        IF bVacOk THEN
            _eState := E_DL_CvsPhase.eConfirm;                                                 // 到位：进确认相 / Vacuum reached, enter confirmation
        ELSIF tonVacTo.Q THEN
            _eCause := E_DL_CvsCause.eVacTimeout;                                              // 归因：吸附超时 / Cause: vacuum timeout
            _bFault := TRUE;                                                                   // 锁存 / Latch
            _eState := E_DL_CvsPhase.eFault;                                                   // 入故障相 / Enter fault phase
        ELSIF bStop THEN
            _bAborted := TRUE;                                                                 // 中止脉冲 / Abort pulse
            _eState := E_DL_CvsPhase.eVent;                                                     // 中止先进破空（安全侧） / Abort vents first
        END_IF

    E_DL_CvsPhase.eConfirm:
        IF NOT bVacOk THEN
            _eCause := E_DL_CvsCause.eVacLost;                                                 // 驻留失守：确认窗内真空掉 / Vacuum lost, residency breach
            _bFault := TRUE;                                                                   // 锁存 / Latch
            _eState := E_DL_CvsPhase.eFault;                                                   // 入故障相 / Enter fault phase
        ELSIF tonConfTo.Q THEN
            _eState := E_DL_CvsPhase.eClamp;                                                    // 确认窗满：进加工相 / Confirmed, enter the clamp phase
        END_IF

    E_DL_CvsPhase.eClamp:
        IF bReleaseReq AND bProcessActive THEN
            _bRelBlock := TRUE;                                                                // 加工中拒释放（互锁先于顺控） / Release blocked while processing
        ELSIF (bReleaseReq AND bProcessDone) OR bStop THEN
            _bAborted := bStop AND (NOT bProcessDone);                                          // 中止（无完成）置中止脉冲 / Abort pulse only on stop
            _eState := E_DL_CvsPhase.eVent;                                                     // 进破空相 / Enter venting
        END_IF

    E_DL_CvsPhase.eVent:
        IF bVentOk THEN
            _eState := E_DL_CvsPhase.eIdle;                                                     // 破空到位：回待机相 / Atmosphere reached, back to idle
        ELSIF tonVentTo.Q THEN
            _eCause := E_DL_CvsCause.eVentTimeout;                                              // 归因：破空超时 / Cause: vent timeout
            _bFault := TRUE;                                                                   // 锁存 / Latch
            _eState := E_DL_CvsPhase.eFault;                                                   // 入故障相 / Enter fault phase
        END_IF

    E_DL_CvsPhase.eFault:
        ;                                                                                      // 故障相：仅等复位沿 / Wait for the reset edge only

    ELSE
        _eCause := E_DL_CvsCause.ePhaseBad;                                                    // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                                                       // 锁存 / Latch
        _eState := E_DL_CvsPhase.eFault;                                                       // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 5：互锁一致性闸（加工中却处于释放/待机相 → 相位与外部互锁源脱节） —— *)
IF bProcessActive AND ((_eState = E_DL_CvsPhase.eVent) OR (_eState = E_DL_CvsPhase.eIdle)) THEN
    _eCause := E_DL_CvsCause.eInterlockViolation;                                              // 归因：互锁相位矛盾 / Cause: interlock contradiction
    _bFault := TRUE;                                                                            // 锁存 / Latch
    _eState := E_DL_CvsPhase.eFault;                                                            // 入故障相 / Enter fault phase
END_IF

(* —— 段 6：完成脉冲（忙碌 → 待机且无中止无故障；两段式单拍） —— *)
IF _bBusyPrev AND (_eState = E_DL_CvsPhase.eIdle) AND (NOT _bAborted) AND (NOT _bFault) THEN
    _bDone := TRUE;                                                                             // 完成脉冲 / Completion pulse
END_IF
_bBusyPrev := (_eState <> E_DL_CvsPhase.eIdle) AND (_eState <> E_DL_CvsPhase.eFault);           // 忙碌快照（本拍末） / Busy snapshot at body end

(* —— 段 7：出口单点映射（阀位与相/夹持同源，R191） —— *)
bVacValve  := ((_eState = E_DL_CvsPhase.eVacOn) OR (_eState = E_DL_CvsPhase.eConfirm) OR (_eState = E_DL_CvsPhase.eClamp))
              AND (NOT _bFault);                                                                // 吸附/确认/加工相保持真空（故障相切断） / Vacuum held in three phases only
bVentValve := (_eState = E_DL_CvsPhase.eVent);                                                  // 破空阀仅在释放相 / Vent valve only in the vent phase
bClamped   := (_eState = E_DL_CvsPhase.eClamp);                                                 // 夹持指示 / Clamped indicator
bBusy      := (_eState <> E_DL_CvsPhase.eIdle) AND (_eState <> E_DL_CvsPhase.eFault);           // 忙碌 / Busy
bDone      := _bDone;                                                                           // 完成脉冲出口 / Completion pulse outlet
bAborted   := _bAborted;                                                                        // 中止脉冲出口 / Abort pulse outlet
bReleaseBlocked := _bRelBlock;                                                                  // 释放被拒出口 / Release-blocked outlet
ePhase     := _eState;                                                                          // 相出口 / Phase outlet
eCause     := _eCause;                                                                          // 成因出口 / Cause outlet
bError     := _bFault;                                                                          // 故障标志 / Error flag

END_FUNCTION_BLOCK
