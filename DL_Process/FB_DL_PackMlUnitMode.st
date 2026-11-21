(*
  ==================================================================
  组件名 Component  : FB_DL_PackMlUnitMode
  分类   Category   : DL_Process
  版本   Version    : 1.0.1
  功能   Purpose    : PackML UnitMode 与 PMODE（PackML 状态模型）管理与命令过滤。
                      维护单元模式（生产 / 维护 / 手动 / 换型 / 清洗）与 PackML 状态
                      子集（空闲 / 启动 / 执行 / 保持 / 暂停 / 停止 / 中止 / 清除 /
                      复位 / 完成），按「当前状态 × 当前模式」两张闸对命令做过滤：
                      合法命令被受理并驱动状态迁移，非法命令被拒绝并给出拒绝原因；
                      模式切换仅在空闲 / 停止 / 完成三态允许。
  溯源   Origin     : PackML 状态与 UnitMode 组织为 OMAC PackML 公开标准语义；本件为
                      clean-room 实现，仅借鉴来源分类与参数域组织（来源标签
                      t2-7-packml 的 PackML 状态组织），未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / 枚举比较，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做模式与状态管理及命令过滤，不执行任何设备动作（属主边界）；
                      二 中止（Abort）与停止（Stop）在全部模式下恒受理（安全侧优先）；
                      三 过渡态（启动 / 保持 / 暂停 / 停止 / 中止 / 清除 / 复位）由外部
                         完成信号 bTransDone 推进，并有过渡超时保护；
                      四 模式切换只在 eIdle / eStopped / eComplete 三态允许，其余态拒绝并留因；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      eState / eMode 为锁存状态，只在合法迁移或合法模式切换时改变；
                      bCmdAccepted 为单拍脉冲（内部位置位、统一出口映射后撤销）；
                      eReject 每次拒绝独立留痕，nRejectCnt 饱和累计；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 4 · 序号 19）
    2026-11-20  v1.0.1  R56 返修（7.5）：段 4 模式受理前补 eModeReq 枚举五选一合法性
                        校验，非法请求改记 eModeBlocked 不采纳（消除一拍非法模式窗口）；
                        段 9 / 段 10 头注释段号回正（原误标 segment 10 / 11）。
  ==================================================================
*)

TYPE E_DL_PmlState :
(
    eIdle        := 0,   // 空闲：允许启动与模式切换 / idle, start and mode change allowed
    eStarting    := 10,  // 启动过渡 / starting transition
    eExecute     := 20,  // 执行 / execute
    eCompleting  := 30,  // 完成过渡 / completing transition
    eComplete    := 40,  // 已完成：允许复位与模式切换 / complete, reset and mode change allowed
    eHolding     := 50,  // 保持过渡 / holding transition
    eHeld        := 60,  // 已保持 / held
    eUnholding   := 70,  // 解除保持过渡 / unholding transition
    eSuspending  := 80,  // 暂停过渡 / suspending transition
    eSuspended   := 90,  // 已暂停 / suspended
    eUnsuspending:= 100, // 解除暂停过渡 / unsuspending transition
    eStopping    := 110, // 停止过渡 / stopping transition
    eStopped     := 120, // 已停止：允许复位与模式切换 / stopped, reset and mode change allowed
    eClearing    := 130, // 清除过渡 / clearing transition
    eAborting    := 140, // 中止过渡 / aborting transition
    eAborted     := 150  // 已中止：只能经清除与复位恢复 / aborted, only clear and reset recover it
);
END_TYPE

TYPE E_DL_UnitMode :
(
    eProduction  := 0,   // 生产模式：全命令集 / production mode with the full command set
    eMaintenance := 10,  // 维护模式：禁暂停 / maintenance mode without suspend
    eManual      := 20,  // 手动模式：禁启动与保持 / manual mode without start and hold
    eChangeover  := 30,  // 换型模式：禁暂停与完成 / changeover mode without suspend and complete
    eCleaning    := 40   // 清洗模式：仅启动 / cleaning mode with start only
);
END_TYPE

TYPE E_DL_PmlCmd :
(
    eNone     := 0,      // 无命令 / no command
    eStart    := 10,     // 启动 / start
    eHold     := 20,     // 保持 / hold
    eUnhold   := 30,     // 解除保持 / unhold
    eSuspend  := 40,     // 暂停 / suspend
    eUnsuspend:= 50,     // 解除暂停 / unsuspend
    eStop     := 60,     // 停止 / stop
    eAbort    := 70,     // 中止 / abort
    eClear    := 80,     // 清除 / clear
    eReset    := 90,     // 复位 / reset
    eComplete := 100     // 完成 / complete
);
END_TYPE

TYPE E_DL_PmlReject :
(
    eNone            := 0, // 无拒绝 / no rejection
    eNoCmd           := 10, // 本拍无命令 / no command in this scan
    eIllegalState    := 20, // 该状态不接受此命令 / the current state does not accept this command
    eModeBlocked     := 30, // 当前模式禁止此命令 / the current mode blocks this command
    eModeLocked      := 40, // 当前状态不允许切换模式 / the current state does not allow a mode change
    eTransTimeout    := 50  // 过渡超时（故障级，与 bError 配对）/ transition timeout, a fault paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_PackMlUnitMode
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时不受理命令并回空闲 [-] / enable, no command is accepted when disabled and the state returns to idle
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存并回空闲 [-] / reset rising edge clears the fault latch and returns to idle
    bCmdStrobe   : BOOL := FALSE;            // 命令选通脉冲，上升沿消费 eCmdReq [-] / command strobe, eCmdReq is consumed on the rising edge
    eCmdReq      : E_DL_PmlCmd := E_DL_PmlCmd.eNone;   // 命令请求 [枚举] / requested command [enum]
    bModeStrobe  : BOOL := FALSE;            // 模式切换选通脉冲，上升沿消费 eModeReq [-] / mode change strobe, eModeReq is consumed on the rising edge
    eModeReq     : E_DL_UnitMode := E_DL_UnitMode.eProduction; // 模式请求 [枚举] / requested unit mode [enum]
    bTransDone   : BOOL := FALSE;            // 过渡完成信号（外部动作已完成）[-] / transition done signal from the external action
    tTransTo     : TIME := T#60S;            // 过渡超时 [毫秒]，域 大于零 / transition timeout [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    eState       : E_DL_PmlState := E_DL_PmlState.eIdle;     // PackML 状态出口 [枚举] / PackML state outlet [enum]
    eMode        : E_DL_UnitMode := E_DL_UnitMode.eProduction; // 单元模式出口 [枚举] / unit mode outlet [enum]
    eAccepted    : E_DL_PmlCmd := E_DL_PmlCmd.eNone;         // 最近受理命令 [枚举] / last accepted command [enum]
    eReject      : E_DL_PmlReject := E_DL_PmlReject.eNone;   // 本拍拒绝原因 [枚举] / rejection reason of this scan [enum]
    bCmdAccepted : BOOL := FALSE;            // 命令受理单拍脉冲 [-] / command accepted single-shot pulse
    bModeAllowed : BOOL := FALSE;            // 当前状态是否允许切换模式 [-] / whether the current state allows a mode change
    bTransBusy   : BOOL := FALSE;            // 处于过渡态 [-] / inside a transition state
    uRejectCnt   : UDINT := 0;               // 拒绝计数（饱和到上限）[次] / rejection count, saturated [count]
    eCause       : E_DL_PmlReject := E_DL_PmlReject.eNone;   // 成因出口（复用拒绝枚举，故障级与 bError 配对）/ cause outlet reusing the reject enum, fault grade paired with bError
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStrobe     : R_TRIG;                   // 命令选通沿检测，段 0 无条件刷新 / command strobe edge detector, refreshed unconditionally in segment zero
    rtMode       : R_TRIG;                   // 模式选通沿检测，段 0 无条件刷新 / mode strobe edge detector, refreshed unconditionally in segment zero
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonTrans     : TON;                      // 过渡超时，段 0 无条件刷新 / transition timeout, refreshed unconditionally in segment zero
    _eState      : E_DL_PmlState := E_DL_PmlState.eIdle;     // 内部状态，CASE 唯一写入目标 / internal state, the only CASE write target
    _eMode       : E_DL_UnitMode := E_DL_UnitMode.eProduction; // 内部模式锁存 / internal mode latch
    _eReject     : E_DL_PmlReject := E_DL_PmlReject.eNone;   // 本拍拒绝原因工作值 / rejection reason working value
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bAccInt     : BOOL := FALSE;            // 受理脉冲内部位，统一出口映射 / internal accepted bit, mapped at the unified outlet
    _bAccepted   : BOOL := FALSE;            // 本拍是否受理了命令 [-] / whether a command was accepted this scan
    _bTransBusy  : BOOL := FALSE;            // 过渡态判定 [-] / transition state verdict
    _bModeAllowed: BOOL := FALSE;            // 模式切换许可 [-] / mode change permission
    _bAllowStart : BOOL := FALSE;            // 模式允许启动 [-] / the mode allows start
    _bAllowHold  : BOOL := FALSE;            // 模式允许保持 [-] / the mode allows hold
    _bAllowSusp  : BOOL := FALSE;            // 模式允许暂停 [-] / the mode allows suspend
    _bAllowCompl : BOOL := FALSE;            // 模式允许完成 [-] / the mode allows complete
    _bModeValid  : BOOL := FALSE;            // 模式枚举合法 [-] / the mode enumeration is legal
    _bModeReqOk  : BOOL := FALSE;            // 模式请求枚举五选一合法性 [-] / whether the requested mode is one of the five legal members
    _uReject     : UDINT := 0;               // 拒绝计数工作值 [次] / rejection count working value [count]
END_VAR
VAR CONSTANT
    DL_PML_REJ_MAX : UDINT := 2000000000;    // 拒绝计数饱和上限（常量在 DINT 可表范围内）[次] / rejection count saturation ceiling, the constant fits in DINT
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串过渡态闸 / segment 0, unconditional refresh with the transition gate on IN only
rtStrobe(CLK := bCmdStrobe); // 命令选通沿无条件刷新 / unconditional refresh of the command strobe
rtMode(CLK := bModeStrobe); // 模式选通沿无条件刷新 / unconditional refresh of the mode strobe
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonTrans(IN := _bTransBusy AND (NOT _bFault) AND bEnable, PT := tTransTo); // 过渡超时，仅在过渡态计时 / transition timeout timing only inside a transition state

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_PmlState.eIdle; // 状态从空闲起步 / the state starts at idle
    _eMode := E_DL_UnitMode.eProduction; // 模式从生产起步 / the mode starts at production
    _eReject := E_DL_PmlReject.eNone; // 拒绝原因清零 / clear the rejection reason
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _uReject := 0; // 拒绝计数清零 / clear the rejection count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁状态 / 清脉冲内部位（模式保持，避免复位改工艺模式）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eReject := E_DL_PmlReject.eNone; // 作用域一：清拒绝原因 / scope one, clear the rejection reason
    _eState := E_DL_PmlState.eIdle; // 作用域二：迁回空闲 / scope two, migrate back to idle
    _bAccInt := FALSE; // 作用域二：清受理脉冲内部位 / scope two, clear the internal accepted bit
END_IF

// 段 3｜模式合法性与模式命令白名单（模式闸） / segment 3, mode validity and the per mode command whitelist
_bModeValid := (_eMode = E_DL_UnitMode.eProduction) OR (_eMode = E_DL_UnitMode.eMaintenance) OR (_eMode = E_DL_UnitMode.eManual) OR (_eMode = E_DL_UnitMode.eChangeover) OR (_eMode = E_DL_UnitMode.eCleaning); // 模式枚举五选一 / the mode is one of five
IF NOT _bModeValid THEN // 模式非法 / the mode is illegal
    _eMode := E_DL_UnitMode.eProduction; // 两级回退（R117）：一级回生产模式 / stage one of the two stage fallback, back to production
END_IF
_bAllowStart := (_eMode = E_DL_UnitMode.eProduction) OR (_eMode = E_DL_UnitMode.eMaintenance) OR (_eMode = E_DL_UnitMode.eChangeover) OR (_eMode = E_DL_UnitMode.eCleaning); // 启动白名单：手动模式禁启动 / start whitelist, manual mode forbids start
_bAllowHold := (_eMode = E_DL_UnitMode.eProduction) OR (_eMode = E_DL_UnitMode.eMaintenance) OR (_eMode = E_DL_UnitMode.eChangeover); // 保持白名单：手动与清洗禁保持 / hold whitelist, manual and cleaning forbid hold
_bAllowSusp := (_eMode = E_DL_UnitMode.eProduction); // 暂停白名单：仅生产模式 / suspend whitelist, production only
_bAllowCompl := (_eMode = E_DL_UnitMode.eProduction); // 完成白名单：仅生产模式 / complete whitelist, production only
_bModeAllowed := (_eState = E_DL_PmlState.eIdle) OR (_eState = E_DL_PmlState.eStopped) OR (_eState = E_DL_PmlState.eComplete); // 模式切换许可：空闲 / 停止 / 完成三态 / mode change allowed in idle, stopped and complete only

// 段 4｜模式切换：许可态内受理，非许可态留拒绝原因 / segment 4, mode change acceptance with a rejection trail
_eReject := E_DL_PmlReject.eNone; // 本拍拒绝原因预置空 / preset the rejection reason to none
_bModeReqOk := (eModeReq = E_DL_UnitMode.eProduction) OR (eModeReq = E_DL_UnitMode.eMaintenance) OR (eModeReq = E_DL_UnitMode.eManual) OR (eModeReq = E_DL_UnitMode.eChangeover) OR (eModeReq = E_DL_UnitMode.eCleaning); // 模式请求枚举五选一判式（R56 返修补齐）/ the requested mode is one of five legal members
IF rtMode.Q THEN // 模式选通沿 / mode strobe edge
    IF NOT bEnable THEN // 失能 / disabled
        _eReject := E_DL_PmlReject.eModeLocked; // 拒绝原因：失能不受理 / rejection reason, disabled
    ELSIF NOT _bModeReqOk THEN // 模式请求枚举非法 / the requested mode is illegal
        _eReject := E_DL_PmlReject.eModeBlocked; // 拒绝原因：非法模式请求不采纳（R56 返修补齐，消除一拍非法模式窗口）/ rejection reason, an illegal mode request is not adopted
    ELSIF _bModeAllowed THEN // 许可态 / inside a permitted state
        _eMode := eModeReq; // 采纳请求模式 / adopt the requested mode
    ELSE // 非许可态 / outside a permitted state
        _eReject := E_DL_PmlReject.eModeLocked; // 拒绝原因：状态锁模式 / rejection reason, the state locks the mode
    END_IF
END_IF

// 段 5｜过渡态判定 / segment 5, transition state verdict
_bTransBusy := (_eState = E_DL_PmlState.eStarting) OR (_eState = E_DL_PmlState.eCompleting) OR (_eState = E_DL_PmlState.eHolding) OR (_eState = E_DL_PmlState.eUnholding) OR (_eState = E_DL_PmlState.eSuspending) OR (_eState = E_DL_PmlState.eUnsuspending) OR (_eState = E_DL_PmlState.eStopping) OR (_eState = E_DL_PmlState.eClearing) OR (_eState = E_DL_PmlState.eAborting); // 九个过渡态之一 / one of the nine transition states

// 段 6｜过渡推进：外部完成信号或过渡超时（超时即中止并留故障级原因）/ segment 6, transition advancement by the external signal or by a timeout
IF _bTransBusy THEN // 过渡态内 / inside a transition state
    IF bTransDone THEN // 外部动作完成 / the external action completed
        CASE _eState OF
        E_DL_PmlState.eStarting: // 启动过渡完成 / starting completed
            _eState := E_DL_PmlState.eExecute; // 进执行态 / enter execute
        E_DL_PmlState.eCompleting: // 完成过渡完成 / completing completed
            _eState := E_DL_PmlState.eComplete; // 进已完成态 / enter complete
        E_DL_PmlState.eHolding: // 保持过渡完成 / holding completed
            _eState := E_DL_PmlState.eHeld; // 进已保持态 / enter held
        E_DL_PmlState.eUnholding: // 解除保持过渡完成 / unholding completed
            _eState := E_DL_PmlState.eExecute; // 回执行态 / back to execute
        E_DL_PmlState.eSuspending: // 暂停过渡完成 / suspending completed
            _eState := E_DL_PmlState.eSuspended; // 进已暂停态 / enter suspended
        E_DL_PmlState.eUnsuspending: // 解除暂停过渡完成 / unsuspending completed
            _eState := E_DL_PmlState.eExecute; // 回执行态 / back to execute
        E_DL_PmlState.eStopping: // 停止过渡完成 / stopping completed
            _eState := E_DL_PmlState.eStopped; // 进已停止态 / enter stopped
        E_DL_PmlState.eClearing: // 清除过渡完成 / clearing completed
            _eState := E_DL_PmlState.eIdle; // 回空闲态 / back to idle
        E_DL_PmlState.eAborting: // 中止过渡完成 / aborting completed
            _eState := E_DL_PmlState.eAborted; // 进已中止态 / enter aborted
        ELSE // 非法过渡态兜底（R128）/ illegal transition fallback
            _eState := E_DL_PmlState.eIdle; // 回空闲态 / back to idle
        END_CASE
    ELSIF tonTrans.Q THEN // 过渡超时 / the transition timed out
        _eReject := E_DL_PmlReject.eTransTimeout; // 故障级原因（与 bError 配对，R45）/ fault grade reason paired with bError
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eState := E_DL_PmlState.eAborting; // 强制走中止过渡 / force the aborting transition
    END_IF
END_IF

// 段 7｜命令过滤：状态闸在前、模式闸在后，两闸顺序固定（先判状态可接受性，再判模式白名单）/ segment 7, command filtering with the state gate before the mode gate
_eAccepted := E_DL_PmlCmd.eNone; // 受理命令预置空 / preset the accepted command to none
_bAccepted := FALSE; // 受理标志预置假 / preset the accepted flag to false
IF rtStrobe.Q AND bEnable AND (NOT _bFault) AND (NOT _bTransBusy) THEN // 选通沿、使能、无故障、非过渡态 / strobe while enabled, unfaulted and outside a transition
    IF eCmdReq = E_DL_PmlCmd.eNone THEN // 无命令 / no command
        _eReject := E_DL_PmlReject.eNoCmd; // 拒绝原因：无命令 / rejection reason, no command
    ELSE
        // 段 7.1｜状态闸：按当前状态给出可接受的命令集合 / segment 7.1, the state gate defines the acceptable command set
        CASE _eState OF
        E_DL_PmlState.eIdle: // 空闲态：启动 / 中止 / 复位 / 清除 / 模式许可 / idle state
            IF eCmdReq = E_DL_PmlCmd.eStart THEN // 启动 / start
                IF _bAllowStart THEN // 模式允许 / the mode allows it
                    _eState := E_DL_PmlState.eStarting; // 迁启动过渡 / enter starting
                    _eAccepted := E_DL_PmlCmd.eStart; // 受理启动 / accept start
                    _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
                ELSE
                    _eReject := E_DL_PmlReject.eModeBlocked; // 模式闸拒绝 / blocked by the mode gate
                END_IF
            ELSIF eCmdReq = E_DL_PmlCmd.eAbort THEN // 中止 / abort
                _eState := E_DL_PmlState.eAborting; // 迁中止过渡 / enter aborting
                _eAccepted := E_DL_PmlCmd.eAbort; // 受理中止 / accept abort
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eReset THEN // 复位 / reset
                _eState := E_DL_PmlState.eClearing; // 空闲态的复位等价于清除 / a reset from idle behaves as clearing
                _eAccepted := E_DL_PmlCmd.eReset; // 受理复位 / accept reset
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eClear THEN // 清除 / clear
                _eState := E_DL_PmlState.eClearing; // 迁清除过渡 / enter clearing
                _eAccepted := E_DL_PmlCmd.eClear; // 受理清除 / accept clearing
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        E_DL_PmlState.eExecute: // 执行态：保持 / 暂停 / 停止 / 完成 / 中止 / execute state
            IF eCmdReq = E_DL_PmlCmd.eHold THEN // 保持 / hold
                IF _bAllowHold THEN // 模式允许 / the mode allows it
                    _eState := E_DL_PmlState.eHolding; // 迁保持过渡 / enter holding
                    _eAccepted := E_DL_PmlCmd.eHold; // 受理保持 / accept hold
                    _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
                ELSE
                    _eReject := E_DL_PmlReject.eModeBlocked; // 模式闸拒绝 / blocked by the mode gate
                END_IF
            ELSIF eCmdReq = E_DL_PmlCmd.eSuspend THEN // 暂停 / suspend
                IF _bAllowSusp THEN // 模式允许 / the mode allows it
                    _eState := E_DL_PmlState.eSuspending; // 迁暂停过渡 / enter suspending
                    _eAccepted := E_DL_PmlCmd.eSuspend; // 受理暂停 / accept suspend
                    _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
                ELSE
                    _eReject := E_DL_PmlReject.eModeBlocked; // 模式闸拒绝 / blocked by the mode gate
                END_IF
            ELSIF eCmdReq = E_DL_PmlCmd.eComplete THEN // 完成 / complete
                IF _bAllowCompl THEN // 模式允许 / the mode allows it
                    _eState := E_DL_PmlState.eCompleting; // 迁完成过渡 / enter completing
                    _eAccepted := E_DL_PmlCmd.eComplete; // 受理完成 / accept complete
                    _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
                ELSE
                    _eReject := E_DL_PmlReject.eModeBlocked; // 模式闸拒绝 / blocked by the mode gate
                END_IF
            ELSIF eCmdReq = E_DL_PmlCmd.eStop THEN // 停止（安全侧恒受理）/ stop, always accepted on the safety side
                _eState := E_DL_PmlState.eStopping; // 迁停止过渡 / enter stopping
                _eAccepted := E_DL_PmlCmd.eStop; // 受理停止 / accept stop
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eAbort THEN // 中止（安全侧恒受理）/ abort, always accepted
                _eState := E_DL_PmlState.eAborting; // 迁中止过渡 / enter aborting
                _eAccepted := E_DL_PmlCmd.eAbort; // 受理中止 / accept abort
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        E_DL_PmlState.eHeld: // 已保持态：解除保持 / 停止 / 中止 / held state
            IF eCmdReq = E_DL_PmlCmd.eUnhold THEN // 解除保持 / unhold
                _eState := E_DL_PmlState.eUnholding; // 迁解除保持过渡 / enter unholding
                _eAccepted := E_DL_PmlCmd.eUnhold; // 受理解除保持 / accept unhold
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eStop THEN // 停止 / stop
                _eState := E_DL_PmlState.eStopping; // 迁停止过渡 / enter stopping
                _eAccepted := E_DL_PmlCmd.eStop; // 受理停止 / accept stop
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eAbort THEN // 中止 / abort
                _eState := E_DL_PmlState.eAborting; // 迁中止过渡 / enter aborting
                _eAccepted := E_DL_PmlCmd.eAbort; // 受理中止 / accept abort
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        E_DL_PmlState.eSuspended: // 已暂停态：解除暂停 / 停止 / 中止 / suspended state
            IF eCmdReq = E_DL_PmlCmd.eUnsuspend THEN // 解除暂停 / unsuspend
                _eState := E_DL_PmlState.eUnsuspending; // 迁解除暂停过渡 / enter unsuspending
                _eAccepted := E_DL_PmlCmd.eUnsuspend; // 受理解除暂停 / accept unsuspend
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eStop THEN // 停止 / stop
                _eState := E_DL_PmlState.eStopping; // 迁停止过渡 / enter stopping
                _eAccepted := E_DL_PmlCmd.eStop; // 受理停止 / accept stop
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eAbort THEN // 中止 / abort
                _eState := E_DL_PmlState.eAborting; // 迁中止过渡 / enter aborting
                _eAccepted := E_DL_PmlCmd.eAbort; // 受理中止 / accept abort
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        E_DL_PmlState.eComplete: // 已完成态：复位 / 停止 / 中止 / complete state
            IF (eCmdReq = E_DL_PmlCmd.eReset) OR (eCmdReq = E_DL_PmlCmd.eClear) THEN // 复位或清除 / reset or clear
                _eState := E_DL_PmlState.eClearing; // 迁清除过渡 / enter clearing
                _eAccepted := eCmdReq; // 受理该命令 / accept that command
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eAbort THEN // 中止 / abort
                _eState := E_DL_PmlState.eAborting; // 迁中止过渡 / enter aborting
                _eAccepted := E_DL_PmlCmd.eAbort; // 受理中止 / accept abort
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        E_DL_PmlState.eStopped: // 已停止态：复位 / 清除 / 中止 / stopped state
            IF (eCmdReq = E_DL_PmlCmd.eReset) OR (eCmdReq = E_DL_PmlCmd.eClear) THEN // 复位或清除 / reset or clear
                _eState := E_DL_PmlState.eClearing; // 迁清除过渡 / enter clearing
                _eAccepted := eCmdReq; // 受理该命令 / accept that command
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSIF eCmdReq = E_DL_PmlCmd.eAbort THEN // 中止 / abort
                _eState := E_DL_PmlState.eAborting; // 迁中止过渡 / enter aborting
                _eAccepted := E_DL_PmlCmd.eAbort; // 受理中止 / accept abort
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        E_DL_PmlState.eAborted: // 已中止态：只能清除后复位 / aborted state, clear then reset only
            IF eCmdReq = E_DL_PmlCmd.eClear THEN // 清除 / clear
                _eState := E_DL_PmlState.eClearing; // 迁清除过渡 / enter clearing
                _eAccepted := E_DL_PmlCmd.eClear; // 受理清除 / accept clearing
                _bAccepted := TRUE; // 置受理标志 / raise the accepted flag
            ELSE // 其它命令 / any other command
                _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
            END_IF
        ELSE // 过渡态不接受新命令 / transition states reject new commands
            _eReject := E_DL_PmlReject.eIllegalState; // 状态闸拒绝 / blocked by the state gate
        END_CASE
    END_IF
ELSIF rtStrobe.Q THEN // 有选通但使能 / 故障 / 过渡态不满足 / a strobe arrived under a blocking condition
    _eReject := E_DL_PmlReject.eIllegalState; // 拒绝原因：条件不满足 / rejection reason, the condition is not met
END_IF

// 段 8｜拒绝计数与受理脉冲内部位 / segment 8, rejection counting and the internal accepted bit
IF NOT (_eReject = E_DL_PmlReject.eNone) THEN // 本拍存在拒绝 / a rejection occurred
    IF _uReject < DL_PML_REJ_MAX THEN // 未达饱和上限 / below the ceiling
        _uReject := _uReject + 1; // 拒绝计数递增 / increment the rejection count
    END_IF
END_IF
IF _bAccepted THEN // 本拍受理了命令 / a command was accepted
    _bAccInt := TRUE; // 受理脉冲内部位置位（统一出口映射，R187）/ raise the internal accepted bit, mapped at the unified outlet
END_IF

// 段 9｜失能语义：不受理命令，状态保持但过渡计时停摆（R191 显式声明）/ segment 9, disabled semantics
IF NOT bEnable THEN // 失能 / disabled
    _bAccInt := FALSE; // 撤受理脉冲内部位 / withdraw the internal accepted bit
    _eReject := E_DL_PmlReject.eModeLocked; // 拒绝原因记模式锁（失能态不支持任何命令）/ rejection reason, disabled blocks every command
END_IF

// 段 10｜统一出口 / segment 10, unified outlet
eState := _eState; // 状态出口单点映射 / single-point state outlet mapping
eMode := _eMode; // 模式出口（锁存量）/ mode outlet from the latch
eAccepted := _eAccepted; // 受理命令出口 / accepted command outlet
eReject := _eReject; // 拒绝原因出口 / rejection reason outlet
bCmdAccepted := _bAccInt; // 受理脉冲映射本拍值 / map the accepted pulse for this scan
_bAccInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
bModeAllowed := _bModeAllowed; // 模式切换许可出口 / mode change permission outlet
bTransBusy := _bTransBusy; // 过渡态出口 / transition state outlet
uRejectCnt := _uReject; // 拒绝计数出口 / rejection count outlet
eCause := _eReject; // 成因出口与拒绝原因同源（名实双出口，R191）/ the cause outlet shares the rejection source
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
