(*
    FB_DL_ChillerDoorPurgeSeq —— 冷机检修门吹扫联锁时序
    ------------------------------------------------------------------
    分类      : DL_Process / Interlock
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : clean-room 自有实现；仅借鉴「先吹扫置换、后放行开门」的受限空间
                进入公开安全常识语义，未复制任何闭源厂商源码，码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R76 冲刺批 C3 · #3）
    ------------------------------------------------------------------
    功能说明  : 冷机检修门「吹扫联锁」唯一时序属主件：门关到位确认 → 风压建立确认
                （fAirPress > fPressMin 持续 tPressQual，超 tPressTo 未建立报 1F00）
                → 吹扫倒计时（tPurgeDur）→ 吹扫完成（bDone 单拍脉冲）→ 放行门开允许
                （bDoorPermit）。任一异常（门中途打开 / 风压跌落 / 确认超时）→
                回退安全态（吹扫输出与开门允许同时撤销）并锁存故障，须 bReset 复位；
                bEStop 急停为最高优先，任意态立即回安全态并锁存 1F03。
                边界：只产出吹扫输出与开门允许，不驱动门电机、不判冷剂浓度。
    序列      : eIdle --bDoorClosed--> ePressQual --fbPressQual.Q--> ePurging
                --fbPurge.Q--> eReady（bDoorPermit）--门正常打开--> eIdle；
                ePressQual/ePurging --门中途打开--> eFault（1F02）；
                ePurging --风压跌落--> eFault（1F01）；ePressQual --超时--> eFault（1F00）。
    错误码    : 16#0005_1F00 风压建立确认超时（tPressTo 内未持续达标）——故障级
                16#0005_1F01 吹扫期间风压跌落（低于 fPressMin）——故障级
                16#0005_1F02 门中途打开（风压确认或吹扫中）——故障级
                16#0005_1F03 急停触发——故障级，最高优先，任意态立即安全态
                16#0005_1F04 参数/采样非法（fAirPress 非有限 / 阈值非正 / 时间为零）——故障级
                16#0005_1F05 CASE 落 ELSE 兜底——故障级
    码位总账  : 16#0005_1F00..1F05 全部定义并使用，无空悬码位
    状态机    : E_DL_PurgeState（eIdle / ePressQual / ePurging / eReady / eFault），
                CASE 含 ELSE 兜底：落 ELSE 置 16#0005_1F05、回安全态转 eFault。
                全部故障码锁存至复位沿：bReset 上升沿且 bEStop 已解除方可复位；
                吹扫完成脉冲 bDone 为单拍位：内部 _bDonePulse 置位 → 统一出口
                映射单拍发布（两段式，防同拍抹除）。
    安全优先级: 段 3 急停拦截在参数门禁与状态机之前执行，任意态（含 eFault）急停
                即重锁存 1F03 并保持安全态输出；安全态 = 吹扫输出 OFF + 开门允许 OFF。
    定时器    : 三只 TON + 两只 R_TRIG 在本体段 1 无条件周期刷新（R7），绝不放入
                CASE/IF，实例无跨相复用。
    防御口径  : 浮点比较一律阈值比较（禁 =/<>）；本件无除法运算；非有限判定按
                NaN f<>f、±Inf (f-f)<>(f-f)。
    修订记录  : 2026-11-23 v1.0.0 首次入库（R76 冲刺批 C3 · #3）
*)
TYPE E_DL_PurgeState :
(
    eIdle       := 0,   // 待机，等门关到位，吹扫与放行全撤销 / idle, waiting for the closed door, purge and permit both off
    ePressQual  := 10,  // 风压建立确认中，fAirPress 持续达标计时 / pressure qualifying, timing while air pressure stays above the minimum
    ePurging    := 20,  // 吹扫倒计时中，风压须持续保持 / purging, countdown running while pressure must hold
    eReady      := 30,  // 吹扫完成，开门允许放行 / purge complete, door-open permit granted
    eFault      := 40   // 故障，安全态保持，故障码锁存至复位沿 / fault, safe state held, code latched until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChillerDoorPurgeSeq
VAR_INPUT
    bDoorClosed : BOOL;                  // 门关到位反馈，TRUE = 已关严 / door closed feedback, TRUE = fully closed
    fAirPress   : REAL;                  // 吹扫风压采样 [kPa] / purge air pressure sample [kPa]
    fPressMin   : REAL := 5.0;           // 风压建立阈值 [kPa]，必须大于 0 / pressure qualification threshold [kPa], must exceed zero
    tPressQual  : TIME := T#1S;          // 风压确认持续时间 [ms]，必须大于 0 / pressure qualification dwell [ms], must exceed zero
    tPressTo    : TIME := T#5S;          // 风压建立超时窗 [ms]，须大于 tPressQual / pressure establish timeout [ms], must exceed tPressQual
    tPurgeDur   : TIME := T#30S;         // 吹扫倒计时时长 [ms]，必须大于 0 / purge duration [ms], must exceed zero
    bEStop      : BOOL;                  // 急停输入，TRUE = 急停，最高优先 / emergency stop, TRUE = stopped, highest priority
    bReset      : BOOL;                  // 故障复位请求，上升沿生效且须急停已解除 / fault reset request, edge-active and requires estop cleared
END_VAR
VAR_OUTPUT
    bPurgeCmd   : BOOL;                  // 吹扫风机/风阀输出，仅确认与吹扫相置位 / purge blower or valve output, asserted in the qualify and purge phases only
    bDoorPermit : BOOL;                  // 门开允许，仅吹扫完成相置位 / door-open permit, asserted in the ready phase only
    bDone       : BOOL;                  // 吹扫完成单拍脉冲，发布后自清 / purge-complete one-scan pulse, self-cleared after publishing
    eState      : E_DL_PurgeState;       // 当前状态镜像输出 / current state mirror output
    nErrCode    : UDINT;                 // 错误码，0 = 无错；故障级码全部锁存回放 / error code, 0 = none; all fault-class codes latched and replayed
    bError      : BOOL;                  // 故障级标志，仅故障级码置位 / fault-class flag, raised only by fault-class codes
    bValid      : BOOL;                  // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    fbPressQual : TON;                   // 风压确认定时器，仅 ePressQual 使用 / pressure qualification timer, ePressQual only
    fbPressTo   : TON;                   // 风压建立超时定时器，仅 ePressQual 使用 / pressure establish timeout timer, ePressQual only
    fbPurge     : TON;                   // 吹扫倒计时定时器，仅 ePurging 使用 / purge countdown timer, ePurging only
    rtReset     : R_TRIG;                // 复位上升沿检测 / reset rising-edge detector
    _eState     : E_DL_PurgeState;       // 当前状态 / current state
    _uErrLatch  : UDINT;                 // 故障码锁存副本，故障态每拍回放 / latched fault code republished inside the fault state
    _bDonePulse : BOOL;                  // 完成脉冲源，段 2 发布后立刻自清 / completion pulse source, published then cleared in segment 2
    _bGateOk    : BOOL;                  // 参数与采样门禁结果 / parameter and sample gate result
END_VAR
VAR CONSTANT
    DL_CDP_ZERO : REAL := 0.0;           // 零值常量，避免裸字面量 [kPa] / zero constant avoiding a bare literal [kPa]
    DL_CDP_T_ZERO : TIME := T#0S;        // 零时间常量，参数门禁用 / zero time constant for the parameter gate
END_VAR

// 段 1｜定时器与边缘检测无条件周期刷新（R7：严禁放入 IF / CASE，实例无跨相复用）
// segment 1, timers and edge detectors refreshed unconditionally, never inside IF/CASE, no cross-phase reuse
fbPressQual(IN := (_eState = E_DL_PurgeState.ePressQual) AND (fAirPress > fPressMin) AND _bGateOk, PT := tPressQual);
fbPressTo(IN := (_eState = E_DL_PurgeState.ePressQual), PT := tPressTo);
fbPurge(IN := (_eState = E_DL_PurgeState.ePurging), PT := tPurgeDur);
rtReset(CLK := bReset);

// 段 2｜输出与错误状态预置；故障态从锁存副本回放；完成脉冲统一出口单拍发布（两段式）
// segment 2, preset outputs and error status; the fault state replays from the latch; the done pulse is published one scan via the unified exit
bDone := _bDonePulse;                    // 发布上一拍置的完成脉冲 / publish the pulse latched last scan
_bDonePulse := FALSE;                    // 发布即自清，保证只出现一拍 / clear right after publishing so the pulse lasts one scan
nErrCode := 0;                           // 预置无错误码 / preset no error code
bError := FALSE;                         // 预置无故障标志 / preset no fault flag
bValid := TRUE;                          // 预置输出可用 / preset outputs valid
IF _eState = E_DL_PurgeState.eFault THEN
    nErrCode := _uErrLatch;              // 重发布锁存故障码，HMI 不会看到码位闪断 / republish the latched fault code
    bError := TRUE;                      // 故障态恒置故障标志 / fault flag stays raised in the fault state
    bValid := FALSE;                     // 故障态输出不可信 / outputs not valid in the fault state
END_IF

// 段 3｜急停最高优先拦截 + 参数/采样门禁：急停任意态立即锁存 1F03 回安全态；
//        门禁非法锁存 1F04 转故障；已在故障态不覆盖原锁存码
// segment 3, estop has the highest priority and latches 1F03 from any state including fault;
//        the parameter gate latches 1F04; an existing latch inside the fault state is not overwritten
IF bEStop THEN
    _uErrLatch := 16#0005_1F03;          // 锁存急停码（任意态含 eFault 均可覆盖更新）/ latch the estop code, overridable from any state
    nErrCode := 16#0005_1F03;            // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_PurgeState.eFault;   // 立即回安全态，本拍 CASE 按 eFault 分派 / jump to the safe state, CASE dispatches on eFault
ELSE
    _bGateOk := (fPressMin > DL_CDP_ZERO) AND (tPressQual > DL_CDP_T_ZERO)
            AND (tPressTo > DL_CDP_T_ZERO) AND (tPurgeDur > DL_CDP_T_ZERO)
            AND (tPressTo > tPressQual);
    IF (fAirPress <> fAirPress) OR ((fAirPress - fAirPress) <> (fAirPress - fAirPress)) THEN
        _bGateOk := FALSE;               // 风压采样 NaN 或 ±Inf，非有限判定 / pressure sample NaN or infinite
    END_IF
    IF (NOT _bGateOk) AND (_eState <> E_DL_PurgeState.eFault) THEN
        _uErrLatch := 16#0005_1F04;      // 锁存参数/采样非法码 / latch the illegal parameter or sample code
        nErrCode := 16#0005_1F04;        // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_PurgeState.eFault; // 参数不可信直接转故障 / untrusted parameters jump to fault
    END_IF
END_IF

// 段 4｜主状态机：CASE + ELSE 兜底（R6）；每个相注明 拍 N 进入 / 本拍行为 / 拍 N+1 转出
// segment 4, main state machine, CASE with ELSE fallback; each phase notes entry, per-scan behaviour and exits
CASE _eState OF
E_DL_PurgeState.eIdle:
    // 拍 N 进入：复位后或门正常打开后；本拍行为：全撤销等待；拍 N+1 转出：门关到位 → ePressQual
    // entered after reset or a normal door opening; everything off while waiting; exits to ePressQual on the closed door
    IF bDoorClosed AND _bGateOk THEN
        _eState := E_DL_PurgeState.ePressQual; // 进风压确认相，下一拍计时启动 / enter pressure qualification, timing starts next scan
    END_IF

E_DL_PurgeState.ePressQual:
    // 拍 N 进入：门关到位；本拍行为：风压达标则 fbPressQual 计时；拍 N+1 转出四路：
    // 计时到 → ePurging；门中途打开 → eFault（1F02）；确认超时 → eFault（1F00）；门禁 → eFault（段 3）
    // entered on the closed door; timer runs while pressure holds; exits to ePurging on Q,
    // to eFault on a mid-sequence door opening (1F02) or on the establish timeout (1F00)
    IF NOT bDoorClosed THEN
        _uErrLatch := 16#0005_1F02;      // 锁存门中途打开码 / latch the mid-sequence door opening code
        nErrCode := 16#0005_1F02;        // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_PurgeState.eFault; // 回安全态，吹扫与放行同拍撤销 / safe state, purge and permit drop the same scan
    ELSIF fbPressQual.Q THEN
        _eState := E_DL_PurgeState.ePurging; // 风压确认通过，进吹扫倒计时 / pressure qualified, start the purge countdown
    ELSIF fbPressTo.Q THEN
        _uErrLatch := 16#0005_1F00;      // 锁存风压建立超时码 / latch the pressure establish timeout code
        nErrCode := 16#0005_1F00;        // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_PurgeState.eFault; // 超时回退安全态 / roll back to the safe state on timeout
    END_IF

E_DL_PurgeState.ePurging:
    // 拍 N 进入：风压确认通过；本拍行为：吹扫输出保持、倒计时走、风压须持续达标；
    // 拍 N+1 转出三路：倒计时到 → eReady（置完成脉冲源）；风压跌落 → eFault（1F01）；
    // 门中途打开 → eFault（1F02）
    // entered after qualification; purge output held, countdown running, pressure must hold;
    // exits to eReady with the pulse source on Q, to eFault on pressure drop (1F01) or door opening (1F02)
    IF NOT bDoorClosed THEN
        _uErrLatch := 16#0005_1F02;      // 锁存门中途打开码 / latch the mid-sequence door opening code
        nErrCode := 16#0005_1F02;        // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_PurgeState.eFault; // 回安全态 / return to the safe state
    ELSIF fAirPress < fPressMin THEN
        _uErrLatch := 16#0005_1F01;      // 锁存风压跌落码 / latch the pressure drop code
        nErrCode := 16#0005_1F01;        // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
        bError := TRUE;
        bValid := FALSE;
        _eState := E_DL_PurgeState.eFault; // 风压跌落立即回退 / roll back at once on the pressure drop
    ELSIF fbPurge.Q THEN
        _bDonePulse := TRUE;             // 置完成脉冲源，段 2 统一出口单拍发布 / set the pulse source, published one scan via segment 2
        _eState := E_DL_PurgeState.eReady;   // 吹扫完成，进放行相 / purge complete, enter the ready phase
    END_IF

E_DL_PurgeState.eReady:
    // 拍 N 进入：吹扫倒计时到；本拍行为：开门允许置位（输出映射段）、吹扫输出撤销；
    // 拍 N+1 转出：门正常打开（关反馈消失）→ eIdle，下次关门重新吹扫
    // entered when the countdown elapsed; permit asserted via the output map while the purge output drops;
    // exits to eIdle when the door actually opens, the next closure restarts the purge
    IF NOT bDoorClosed THEN
        _eState := E_DL_PurgeState.eIdle;    // 门已开，正常返回待机 / door opened, normal return to idle
    END_IF

E_DL_PurgeState.eFault:
    // 拍 N 进入：任一故障级路径；本拍行为：安全态保持、锁存码回放；拍 N+1 转出：
    // bReset 上升沿且急停已解除 → eIdle（门关反馈丢失自动回 eIdle 等下次关门）
    // entered from any fault path; safe state held and the latch replays; exits to eIdle only on
    // a reset edge with the estop cleared
    IF rtReset.Q AND (NOT bEStop) THEN
        _uErrLatch := 0;                 // 清锁存码 / clear the latched code
        _eState := E_DL_PurgeState.eIdle;    // 回待机，等下次门关到位 / back to idle for the next closure
    END_IF

ELSE
    // 非法状态拦截：任何未定义枚举值一律锁存兜底码并转故障（R6）
    // illegal-state interception, any undefined enum value latches the fallback code and goes to fault
    _uErrLatch := 16#0005_1F05;          // 锁存兜底码 / latch the fallback code
    nErrCode := 16#0005_1F05;            // 故障级码赋值 3 行内置 bError / fault-class assignment with bError inline
    bError := TRUE;
    bValid := FALSE;
    _eState := E_DL_PurgeState.eFault;
END_CASE

// 段 5｜输出映射：吹扫输出仅确认/吹扫相保持，开门允许仅就绪相置位，其余一律撤销（双保险）
// segment 5, output map; purge output held only in qualify/purge, permit only in ready, everything else dropped as a double cut
bPurgeCmd := (_eState = E_DL_PurgeState.ePressQual)
          OR (_eState = E_DL_PurgeState.ePurging);   // 吹扫输出按相映射 / purge output mapped by phase
bDoorPermit := (_eState = E_DL_PurgeState.eReady);   // 开门允许仅在放行相 / permit only in the ready phase
eState := _eState;                                   // 状态镜像输出 / state mirror output

END_FUNCTION_BLOCK
