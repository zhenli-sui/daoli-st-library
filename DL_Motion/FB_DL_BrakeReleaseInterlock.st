(*
    FB_DL_BrakeReleaseInterlock —— 伺服抱闸释放互锁
    ------------------------------------------------------------------
    分类      : DL_Motion / AxisSafety
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : clean-room 自有实现；仅借鉴「先确认力矩再放闸」的公开工程常识语义，
                未复制任何闭源厂商源码，码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R76 冲刺批 C3 · #1）
    ------------------------------------------------------------------
    功能说明  : 伺服抱闸「释放侧互锁」唯一时序属主件：伺服使能建立 → 力矩到达确认
                （fTorque < fReleaseTh 持续 tTorqueQual）→ 发抱闸释放输出 →
                闸位反馈确认（bBrakeReleased）→ 就绪（bReady）。
                边界：只产出抱闸释放命令与就绪标志，不发运动指令、不直控伺服使能；
                与 FB_DL_AxisBrakeSeq（上/断电两条全序）差异化：本件聚焦
                「释放互锁单序 + 运行中失使能即时回闸」。
    序列      : eIdle --bServoEnabled--> eTorqueQual --fbTorqueQual.Q--> eReleasing
                --bBrakeReleased--> eReady；
                eReady --bServoEnabled丢失--> eClosing（立即撤输出重上闸）
                --反馈闭合或 tCloseWait--> eIdle；
                eReleasing --tReleaseTimeout--> eFault（撤输出回退，弹簧闸抱死为安全侧）；
                任意态 --参数/采样非法--> eFault。
    错误码    : 16#0005_1D00 力矩确认超时（tTorqueQual 内未持续低于阈值）——故障级，撤输出回退
                16#0005_1D01 抱闸释放反馈超 tReleaseTimeout——故障级，撤输出回退
                16#0005_1D02 就绪态伺服使能丢失，已立即重新上闸——信息级，eClosing 期间持续发布
                16#0005_1D03 时序中途使能丢失，回退重新上闸——信息级，eClosing 期间持续发布
                16#0005_1D04 力矩采样非有限（NaN 用 f<>f、±Inf 用 (f-f)<>(f-f)）——故障级
                16#0005_1D05 参数非法（阈值非正 / 任一时间为零）——故障级
                16#0005_1D06 就绪态释放反馈意外跌落（抱闸非受控闭合）——故障级
                16#0005_1D07 CASE 落 ELSE 兜底——故障级
    码位总账  : 16#0005_1D00..1D07 全部定义并使用，无空悬码位
    状态机    : E_DL_BrakeRelState（eIdle / eTorqueQual / eReleasing / eReady / eClosing
                / eFault），CASE 含 ELSE 兜底：落 ELSE 置 16#0005_1D07、撤输出回 eFault。
                故障码锁存至复位沿：bReset 上升沿且 bServoEnabled=FALSE 时方可复位
                （带使能复位会立即重新放闸，禁止）；信息级码不置 bError、随相发布。
    定时器    : 三只 TON + 一只 R_TRIG 在本体段 1 无条件周期刷新（R7），绝不放入 CASE/IF；
                相转出靠状态条件失配自然断输入，无跨相复用实例。
    防御口径  : 浮点比较一律阈值/容差，禁 =/<>；本件无除法运算；非有限判定按
                NaN f<>f、±Inf (f-f)<>(f-f) 双判，不近似阈值。
    修订记录  : 2026-11-23 v1.0.0 首次入库（R76 冲刺批 C3 · #1）
*)
TYPE E_DL_BrakeRelState :
(
    eIdle       := 0,   // 待机，释放命令失电，等伺服使能建立 / idle, release command off, waiting for the servo enable
    eTorqueQual := 10,  // 力矩确认中，fTorque 持续低于阈值计时 / torque qualifying, timing while torque stays under threshold
    eReleasing  := 20,  // 已发释放命令，等闸位反馈确认 / release command asserted, waiting for brake feedback
    eReady      := 30,  // 释放互锁就绪，抱闸已开且使能在 / interlock ready, brake open and enable present
    eClosing    := 40,  // 回闸中，命令已撤，等反馈闭合或时间兜底 / re-closing, command off, waiting for closed feedback or the fallback time
    eFault      := 50   // 故障，撤输出回退，故障码锁存至复位沿 / fault, outputs rolled back, code latched until reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_BrakeReleaseInterlock
VAR_INPUT
    bServoEnabled    : BOOL;              // 伺服使能状态，TRUE = 使能已建立 / servo enable status, TRUE = enable established
    fTorque          : REAL;              // 伺服当前力矩 [Nm]，参与确认判定 / servo torque [Nm], used by the qualification test
    fReleaseTh       : REAL := 5.0;       // 力矩确认阈值 [Nm]，必须大于 0 / torque qualification threshold [Nm], must exceed zero
    tTorqueQual      : TIME := T#300MS;   // 力矩确认持续时间 [ms]，必须大于 0 / torque qualification dwell [ms], must exceed zero
    bBrakeReleased   : BOOL;              // 抱闸释放到位反馈，TRUE = 已完全释放 / brake released feedback, TRUE = fully released
    tReleaseTimeout  : TIME := T#3S;      // 释放反馈超时 [ms]，必须大于 0 / release feedback timeout [ms], must exceed zero
    tCloseWait       : TIME := T#500MS;   // 回闸兜底等待 [ms]，反馈闭合可提前退出 / re-close fallback wait [ms], closed feedback exits earlier
    bReset           : BOOL;              // 故障复位请求，上升沿生效且须无使能 / fault reset request, edge-active and requires no enable
END_VAR
VAR_OUTPUT
    bBrakeReleaseCmd : BOOL;              // 抱闸释放命令输出，仅 eReleasing/eReady 置位 / brake release command, asserted in eReleasing/eReady only
    bReady           : BOOL;              // 释放互锁就绪标志 / release interlock ready flag
    eState           : E_DL_BrakeRelState; // 当前状态镜像输出 / current state mirror output
    nErrCode         : UDINT;             // 错误码，0 = 无错；信息级随相发布、故障级锁存回放 / error code, 0 = none; info codes published per phase, fault codes latched
    bError           : BOOL;              // 故障级标志，仅故障级码置位 / fault-class flag, raised only by fault-class codes
    bValid           : BOOL;              // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    fbTorqueQual     : TON;               // 力矩确认定时器，仅 eTorqueQual 使用 / torque qualification timer, eTorqueQual only
    fbReleaseTo      : TON;               // 释放反馈超时定时器，仅 eReleasing 使用 / release feedback timeout timer, eReleasing only
    fbCloseWait      : TON;               // 回闸兜底定时器，仅 eClosing 使用 / re-close fallback timer, eClosing only
    rtReset          : R_TRIG;            // 复位上升沿检测 / reset rising-edge detector
    _eState          : E_DL_BrakeRelState; // 当前状态 / current state
    _uErrLatch       : UDINT;             // 故障码锁存副本，故障态每拍回放 / latched fault code republished inside the fault state
    _bGateOk         : BOOL;              // 参数与采样门禁结果 / parameter and sample gate result
    _bLostInReady    : BOOL;              // TRUE = 就绪态丢使能（1D02），FALSE = 中途丢（1D03）/ TRUE = enable lost in eReady (1D02), FALSE = lost mid-sequence (1D03)
END_VAR
VAR CONSTANT
    DL_BRI_ZERO : REAL := 0.0;            // 零值常量，避免裸字面量 [Nm] / zero constant avoiding a bare literal [Nm]
    DL_BRI_T_ZERO : TIME := T#0S;         // 零时间常量，参数门禁用 / zero time constant for the parameter gate
END_VAR

// 段 1｜定时器与边缘检测无条件周期刷新（R7：严禁放入 IF / CASE，实例无跨相复用）
// segment 1, timers and edge detectors refreshed unconditionally, never inside IF/CASE, no cross-phase reuse
fbTorqueQual(IN := (_eState = E_DL_BrakeRelState.eTorqueQual) AND _bGateOk, PT := tTorqueQual);
fbReleaseTo(IN := (_eState = E_DL_BrakeRelState.eReleasing), PT := tReleaseTimeout);
fbCloseWait(IN := (_eState = E_DL_BrakeRelState.eClosing), PT := tCloseWait);
rtReset(CLK := bReset);

// 段 2｜输出与错误状态预置；故障态从锁存副本回放（故障码锁存至复位沿，不被预置冲掉）
// segment 2, preset outputs and error status; the fault state replays from the latch so the preset cannot erase it
bReady := FALSE;                          // 预置未就绪 / preset not ready
nErrCode := 0;                            // 预置无错误码 / preset no error code
bError := FALSE;                          // 预置无故障标志 / preset no fault flag
bValid := TRUE;                           // 预置输出可用 / preset outputs valid
IF _eState = E_DL_BrakeRelState.eFault THEN
    nErrCode := _uErrLatch;               // 重发布锁存故障码，HMI 不会看到码位闪断 / republish the latched fault code
    bError := TRUE;                       // 故障态恒置故障标志 / fault flag stays raised in the fault state
    bValid := FALSE;                      // 故障态输出不可信 / outputs not valid in the fault state
END_IF

// 段 3｜参数与采样门禁：非法即锁存故障并转 eFault，不进状态机（已在故障态则不覆盖原锁存码）
// segment 3, parameter and sample gate; any violation latches a fault and jumps to eFault, an existing latch is not overwritten
_bGateOk := (fReleaseTh > DL_BRI_ZERO) AND (tTorqueQual > DL_BRI_T_ZERO)
        AND (tReleaseTimeout > DL_BRI_T_ZERO) AND (tCloseWait > DL_BRI_T_ZERO);
IF (fTorque <> fTorque) OR ((fTorque - fTorque) <> (fTorque - fTorque)) THEN
    _bGateOk := FALSE;                    // 力矩采样 NaN 或 ±Inf，非有限判定 / torque sample NaN or infinite
END_IF
IF (NOT _bGateOk) AND (_eState <> E_DL_BrakeRelState.eFault) THEN
    IF (fTorque <> fTorque) OR ((fTorque - fTorque) <> (fTorque - fTorque)) THEN
        _uErrLatch := 16#0005_1D04;       // 锁存采样非有限码 / latch the non-finite sample code
        nErrCode := 16#0005_1D04;         // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
    ELSE
        _uErrLatch := 16#0005_1D05;       // 锁存参数非法码 / latch the illegal parameter code
        nErrCode := 16#0005_1D05;         // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
    END_IF
    _eState := E_DL_BrakeRelState.eFault; // 直接转故障，本拍 CASE 按 eFault 分派 / jump to fault, CASE dispatches on eFault this scan
END_IF

// 段 4｜主状态机：CASE + ELSE 兜底；每个相注明 拍 N 进入 / 本拍行为 / 拍 N+1 转出
// segment 4, main state machine, CASE with ELSE fallback; each phase notes entry, per-scan behaviour and exits
CASE _eState OF
E_DL_BrakeRelState.eIdle:
    // 拍 N 进入：复位后或回闸完成；本拍行为：全失电等待；拍 N+1 转出：使能建立 → eTorqueQual
    // entered after reset or re-close; idle with outputs off; exits to eTorqueQual when the enable appears
    IF bServoEnabled THEN
        _bLostInReady := FALSE;           // 新序默认按中途丢失口径 / new sequence defaults to the mid-sequence class
        _eState := E_DL_BrakeRelState.eTorqueQual; // 进力矩确认相，下一拍计时启动 / enter torque qualification, timing starts next scan
    END_IF

E_DL_BrakeRelState.eTorqueQual:
    // 拍 N 进入：使能建立；本拍行为：力矩低于阈值则 fbTorqueQual 计时；拍 N+1 转出三路：
    // 计时到 → eReleasing；使能丢失 → eClosing（1D03）；门禁非法 → eFault（段 3 已转）
    // entered on enable; timer runs while torque is under threshold; exits to eReleasing on Q,
    // to eClosing on enable loss (1D03), or to eFault via the segment-3 gate
    IF NOT bServoEnabled THEN
        _bLostInReady := FALSE;           // 中途丢失，eClosing 发布 1D03 / lost mid-sequence, eClosing publishes 1D03
        _eState := E_DL_BrakeRelState.eClosing; // 回闸相，输出映射本拍即撤命令 / re-close phase, command drops this scan
    ELSIF fbTorqueQual.Q THEN
        _eState := E_DL_BrakeRelState.eReleasing; // 力矩确认通过，发释放命令 / torque qualified, assert the release command
    END_IF

E_DL_BrakeRelState.eReleasing:
    // 拍 N 进入：力矩确认通过；本拍行为：命令保持、等反馈；拍 N+1 转出三路：
    // 反馈到位 → eReady；超时 → eFault（1D01）；使能丢失 → eClosing（1D03）
    // entered after torque qualification; command held awaiting feedback; exits to eReady on feedback,
    // to eFault on timeout (1D01), or to eClosing on enable loss (1D03)
    IF NOT bServoEnabled THEN
        _bLostInReady := FALSE;           // 中途丢失，eClosing 发布 1D03 / lost mid-sequence, eClosing publishes 1D03
        _eState := E_DL_BrakeRelState.eClosing; // 立即回闸，先于一切确认 / re-close at once, before any acknowledgement
    ELSIF bBrakeReleased THEN
        _eState := E_DL_BrakeRelState.eReady;   // 反馈确认，互锁放行 / feedback confirmed, interlock passes
    ELSIF fbReleaseTo.Q THEN
        _uErrLatch := 16#0005_1D01;       // 锁存反馈超时码 / latch the feedback timeout code
        nErrCode := 16#0005_1D01;         // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_BrakeRelState.eFault;   // 撤输出回退，弹簧闸抱死为安全侧 / roll back, spring brake engagement is the safe side
    END_IF

E_DL_BrakeRelState.eReady:
    // 拍 N 进入：释放反馈确认；本拍行为：命令保持、就绪置位（输出映射段）；拍 N+1 转出两路：
    // 使能丢失 → eClosing（1D02，立即重新上闸）；反馈意外跌落 → eFault（1D06）
    // entered on release feedback; command held and ready asserted; exits to eClosing on enable loss (1D02),
    // or to eFault when the feedback drops unexpectedly (1D06)
    IF NOT bBrakeReleased THEN
        _uErrLatch := 16#0005_1D06;       // 锁存反馈意外跌落码 / latch the unexpected feedback drop code
        nErrCode := 16#0005_1D06;         // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_BrakeRelState.eFault;   // 非受控闭合必须停机检查 / uncontrolled engagement demands a stop
    ELSIF NOT bServoEnabled THEN
        _bLostInReady := TRUE;            // 就绪态丢失，eClosing 发布 1D02 / lost in ready, eClosing publishes 1D02
        _eState := E_DL_BrakeRelState.eClosing; // 立即重新上闸 / re-apply the brake at once
    END_IF

E_DL_BrakeRelState.eClosing:
    // 拍 N 进入：任一相使能丢失；本拍行为：命令已撤、按丢失口径发布信息码、等闭合确认；
    // 拍 N+1 转出：反馈闭合或 tCloseWait 兜底到 → eIdle
    // entered on enable loss from any phase; command off, info code published per class, awaiting closure;
    // exits to eIdle on closed feedback or the tCloseWait fallback
    IF _bLostInReady THEN
        nErrCode := 16#0005_1D02;         // 信息级：就绪态丢使能已回闸，不置 bError / info class, no fault flag
    ELSE
        nErrCode := 16#0005_1D03;         // 信息级：时序中途丢使能已回闸 / info class for the mid-sequence loss
    END_IF
    IF (NOT bBrakeReleased) OR fbCloseWait.Q THEN
        _eState := E_DL_BrakeRelState.eIdle;    // 闸已确认闭合（或时间兜底）回待机 / brake confirmed closed, back to idle
    END_IF

E_DL_BrakeRelState.eFault:
    // 拍 N 进入：任一故障级路径；本拍行为：命令保持撤销、锁存码回放；拍 N+1 转出：
    // bReset 上升沿且无使能 → eIdle（带使能复位禁止，防止立即重新放闸）
    // entered from any fault path; command stays off and the latch replays; exits to eIdle only on
    // a reset edge with no servo enable, so the brake cannot release again immediately
    IF rtReset.Q AND (NOT bServoEnabled) THEN
        _uErrLatch := 0;                  // 清锁存码 / clear the latched code
        _eState := E_DL_BrakeRelState.eIdle;    // 回待机，等下一次使能建立 / back to idle for the next enable
    END_IF

ELSE
    // 非法状态拦截：任何未定义枚举值一律锁存兜底码并转故障（R6）
    // illegal-state interception, any undefined enum value latches the fallback code and goes to fault
    _uErrLatch := 16#0005_1D07;           // 锁存兜底码 / latch the fallback code
    nErrCode := 16#0005_1D07;             // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_BrakeRelState.eFault;
END_CASE

// 段 5｜输出映射：命令只在 eReleasing/eReady 保持，其余相（含故障）一律撤销
// segment 5, output map; the command is held only in eReleasing/eReady and dropped everywhere else including fault
bBrakeReleaseCmd := (_eState = E_DL_BrakeRelState.eReleasing)
                OR (_eState = E_DL_BrakeRelState.eReady); // 释放命令按相映射 / release command mapped by phase
bReady := (_eState = E_DL_BrakeRelState.eReady);          // 就绪仅在确认相 / ready only in the confirmed phase
eState := _eState;                                        // 状态镜像输出 / state mirror output

END_FUNCTION_BLOCK
