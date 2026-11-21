(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DolMotor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_MotorDriver）
 * 功能简述 (Function)   : 直接启动（DOL）电机控制功能块。含指令-反馈校验窗
 *                         （拒动保护）、运行失反馈脱扣、热继电器过载锁存、
 *                         最短运行时间监视、60 分钟桶滑窗每小时启动次数
 *                         限制与停机后重启抑制冷却；状态机采用
 *                         ENUM + CASE + ELSE 兜底。
 * 接口实现 (Implements) : I_DL_MotorDriver（属性 eState/bRunning/bFault/
 *                         uErrorId/bRestartInhibit，方法 CmdStart/CmdStop/
 *                         CmdReset，全部在本文件尾部落地）
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R5 S-4：DOL 电机侧
 *                         接触器反馈校验（指令-反馈 500ms 窗）、热继电器
 *                         过载锁存、防频繁启停（重启抑制冷却时间）等行业
 *                         公知语义，公开教学资料，仅借鉴通用工程语义；
 *                         状态机、小时窗计数算法、故障码按本库红线独立
 *                         设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 数组上下界防御+无死循环 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 定时器/边缘实例主体最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1 本块为纯事件型状态机，无积分/滤波类首扫初始化
 *                         逻辑（分钟桶数组零值初始化由编译器缺省保证），
 *                         首扫跟踪范式不适用，无内部初始化标志。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0205
 *                         接触器拒动 / 0003_0206 失反馈脱扣 / 0003_0209
 *                         过载锁存 / 0003_0201 非法状态（全部 R15 锁存仅
 *                         复位可清）；【信息级】0003_0207 每小时启动次数
 *                         超限拒绝 / 0003_0208 重启抑制期拒绝 / 0003_020A
 *                         最短运行时间不足（仅写 uErrorId，不进 bFault，
 *                         0.2 公约）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R5 轮 · DL_Device 开库）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DolMotor IMPLEMENTS I_DL_MotorDriver
VAR_INPUT
    bCmdStart         : BOOL;           // 启动指令（Start command），上升沿生效 / Start command, rising edge effective
    bCmdStop          : BOOL;           // 停止指令（Stop command），电平生效 / Stop command, level effective
    bFbContactor      : BOOL;           // 接触器辅助触点反馈（Contactor feedback），TRUE=吸合 / Contactor feedback, TRUE = picked up
    bThermalOverload  : BOOL;           // 热继电器过载信号（Thermal overload trip），TRUE=过载 / Thermal overload trip, TRUE = overloaded
    bPermitStart      : BOOL;           // 启动允许联锁（Start permit），TRUE=允许 / Start permit interlock, TRUE = start allowed
    tFbWindow         : TIME := T#500MS; // 指令-反馈校验窗口（Feedback check window），T#0S=免校验 / Feedback check window, T#0S disables the check
    tMinRunTime       : TIME := T#5S;   // 最短运行时间（Min run time），T#0S=免监视 / Minimum run time, T#0S disables the monitor
    tRestartInhibit   : TIME := T#60S;  // 重启抑制冷却时间（Restart inhibit），停机后冷却期内拒绝启动 / Restart inhibit cooling time after stop
    uMaxStartsPerHour : USINT := 6;     // 每小时最大启动次数（Max starts per hour），滑动小时窗上限 / Max starts per sliding hour window
    bReset            : BOOL;           // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
END_VAR

VAR_OUTPUT
    bContactorCmd     : BOOL;           // 接触器线圈输出（Contactor coil command），TRUE=得电 / Contactor coil command, TRUE = energized
    eState            : E_DL_MotorState; // 当前状态机状态（Current state），映射接口同名属性 / Current state, mirrors interface property
    bRunning          : BOOL;           // 运行反馈（Running feedback），运行态且触点吸合确认 / Running feedback, running state confirmed by contactor
    bFault            : BOOL;           // 故障锁存中（Fault latched），TRUE=需复位 / Fault latched, TRUE requires reset
    uErrorId          : UDINT;          // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx
    bRestartInhibit   : BOOL;           // 重启抑制激活中（Restart inhibit active），TRUE=冷却期拒绝启动 / Restart inhibit active, TRUE = starts refused
    uStartCount       : UDINT;          // 累计启动次数（Start count），每次受理启动 +1 / Total start count, incremented per accepted start
END_VAR

VAR
    _eState           : E_DL_MotorState := E_DL_MotorState.eIdle; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bFaultLatch      : BOOL;           // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt      : UDINT;          // 内部故障码寄存（Internal error register），故障级与信息级共用 / Internal error register, fault and info codes share it
    _bCooling         : BOOL;           // 冷却计时进行中（Cooling timing active）/ Cooling timer run request flag
    _bRestartInhibitAct : BOOL;         // 重启抑制激活内部寄存（Internal restart inhibit register）/ Internal restart inhibit register
    _bStopLatch       : BOOL;           // 方法停止锁存（Method stop latch），电平语义至回空闲态消化 / Method stop latch, level semantics until idle
    _bPendStart       : BOOL;           // 方法启动请求（Method start request），由 CmdStart 置位 / Method start request set by CmdStart
    _bPendReset       : BOOL;           // 方法复位请求（Method reset request），由 CmdReset 置位 / Method reset request set by CmdReset
    _bFbWinEn         : BOOL;           // 反馈校验窗使能（Feedback window enable），窗口参数大于零时有效 / Feedback window enable, active when window above zero
    _bMinRunEn        : BOOL;           // 最短运行监视使能（Min run monitor enable），参数大于零时有效 / Min run monitor enable, active when parameter above zero
    _bTickReset       : BOOL;           // 分钟桶定时器单周期复位保持（One-cycle tick timer hold-down）/ One-cycle hold-down to restart minute tick timer
    _aMinuteStarts    : ARRAY[0..59] OF UDINT; // 60 分钟启动次数桶（Sliding 60-minute start buckets），索引 0=当前分钟槽 / Buckets of starts per minute, index 0 = current slot
    _uMinIdx          : UINT;           // 当前分钟桶索引（Current minute bucket index），0..59 循环 / Current minute bucket index, cyclic 0..59
    _uHourCount       : UDINT;          // 滑动小时窗合计启动次数（Sliding hour window start sum）/ Start sum over sliding hour window
    _fbTrigStart      : R_TRIG;         // 引脚启动指令上升沿（Pin start command edge）/ Pin start command rising edge
    _fbTrigReset      : R_TRIG;         // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTrigTick       : R_TRIG;         // 分钟桶滚动触发（Minute bucket roll trigger）/ Minute bucket roll edge trigger
    _fbTonFbWindow    : TON;            // 指令-反馈校验窗定时器（Feedback check window timer）/ Feedback check window timer
    _fbTonMinRun      : TON;            // 最短运行时间定时器（Min run time timer）/ Minimum run time timer
    _fbTonRestartInh  : TON;            // 重启抑制冷却定时器（Restart inhibit cooling timer）/ Restart inhibit cooling timer
    _fbTonHourTick    : TON;            // 分钟桶节拍定时器（Minute tick timer），60 秒滚动 / Minute tick timer, rolls every 60 s
    i                 : UINT;           // 滑窗求和循环索引（Sliding window sum loop index）/ Loop index for window sum
END_VAR

// ============================================================================
// 段 1｜定时器与边缘检测实例无条件周期刷新（R7：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all timer and edge instances (R7)
// ============================================================================
_fbTrigStart(CLK := bCmdStart);
_fbTrigReset(CLK := bReset);
_bFbWinEn := (tFbWindow > T#0S);    // 窗口为零 = 免校验（Zero window = check disabled）
_bMinRunEn := (tMinRunTime > T#0S); // 参数为零 = 免监视（Zero parameter = monitor disabled）
_fbTonFbWindow(IN := (_eState = E_DL_MotorState.eStarting) AND _bFbWinEn, PT := tFbWindow);
_fbTonMinRun(IN := ((_eState = E_DL_MotorState.eStarting) OR (_eState = E_DL_MotorState.eRunning)) AND _bMinRunEn, PT := tMinRunTime);
_fbTonRestartInh(IN := _bCooling, PT := tRestartInhibit);
_fbTonHourTick(IN := NOT _bTickReset, PT := T#60S);
_fbTrigTick(CLK := _fbTonHourTick.Q);

// 冷却到期：解除抑制（Cooling expired: release inhibit）
IF _fbTonRestartInh.Q THEN
    _bCooling           := FALSE;    // 结束冷却计时（Stop cooling timing）
    _bRestartInhibitAct := FALSE;    // 解除抑制（Release inhibit）
ELSE
    _bRestartInhibitAct := _bCooling; // 冷却期间抑制有效（Inhibit active during cooling）
END_IF

// ============================================================================
// 段 2｜滑动小时窗：60 秒滚动分钟桶 + 全窗求和（固定界 FOR，无死循环风险）
//      Sliding hour window: 60 s rolling minute buckets + full window sum
// ============================================================================
IF _fbTrigTick.Q THEN
    _uMinIdx := (_uMinIdx + 1) MOD 60; // 桶索引循环推进（Advance bucket index cyclically）
    IF _uMinIdx <= 59 THEN
        _aMinuteStarts[_uMinIdx] := 0; // 新槽清零，旧数据保留 59 分钟后自然滑出（Clear new slot, old data slides out after 59 min）
    END_IF
    _bTickReset := TRUE;               // 单周期复位节拍定时器（One-cycle reset of tick timer）
END_IF
IF _bTickReset THEN
    _bTickReset := FALSE;              // 下一周期恢复计时（Resume timing next cycle）
END_IF

_uHourCount := 0;                      // 每周期重算滑窗合计（Recompute window sum each cycle）
FOR i := 0 TO 59 DO
    _uHourCount := _uHourCount + _aMinuteStarts[i]; // 累加 60 个分钟桶（Accumulate all 60 buckets）
END_FOR

// ============================================================================
// 段 3｜过载全局监视（优先级最高）：启动/运行态过载立即锁存脱扣
//      Global overload monitor (highest priority): trip immediately in starting/running
// ============================================================================
IF bThermalOverload AND ((_eState = E_DL_MotorState.eStarting) OR (_eState = E_DL_MotorState.eRunning)) THEN
    _bFaultLatch := TRUE;              // 过载锁存（Overload latched）
    _uErrorIdInt := 16#0003_0209;      // 0003_0209 热继电器过载脱扣【故障级】/ Thermal overload trip, fault level
    _eState      := E_DL_MotorState.eTripOverload; // 强制脱扣态（Force trip state）
END_IF

// ============================================================================
// 段 4｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
CASE _eState OF

    E_DL_MotorState.eIdle: // 空闲停机态：消化停止锁存，评估启动请求
        IF _bStopLatch THEN
            _bStopLatch := FALSE;      // 停止锁存到空闲即消化（Stop latch absorbed at idle）
        END_IF
        IF _bPendStart OR _fbTrigStart.Q THEN
            IF bThermalOverload THEN
                _bPendStart := FALSE;  // 过载未复位：静默拒绝（Overload present: silent refusal, trip code already latched in trip state）
            ELSIF NOT bPermitStart THEN
                _bPendStart := FALSE;  // 联锁未满足：静默拒绝（Permit absent: silent refusal）
            ELSIF _bRestartInhibitAct THEN
                _bPendStart := FALSE;  // 消费请求不自动重试（Consume request, no auto retry）
                _uErrorIdInt := 16#0003_0208; // 0003_0208 重启抑制期内启动被拒【信息级】/ Start refused during restart inhibit, info level
            ELSIF _uHourCount >= uMaxStartsPerHour THEN
                _bPendStart := FALSE;  // 消费请求不自动重试（Consume request, no auto retry）
                _uErrorIdInt := 16#0003_0207; // 0003_0207 每小时启动次数超限拒绝【信息级】/ Hourly start limit exceeded, info level
            ELSE
                _bPendStart := FALSE;  // 受理启动（Accept start）
                uStartCount := uStartCount + 1; // 累计启动 +1（Total starts +1）
                IF _uMinIdx <= 59 THEN
                    _aMinuteStarts[_uMinIdx] := _aMinuteStarts[_uMinIdx] + 1; // 当前分钟桶 +1（Current bucket +1）
                END_IF
                _eState := E_DL_MotorState.eStarting;
            END_IF
        END_IF

    E_DL_MotorState.eStarting: // 启动校验态：线圈得电，等待反馈窗内吸合
        IF bFbContactor THEN
            _eState := E_DL_MotorState.eRunning;   // 吸合确认，转运行（Pick-up confirmed, to running）
        ELSIF _fbTonFbWindow.Q THEN
            _bFaultLatch := TRUE;                  // 拒动故障锁存（Refusal fault latch）
            _uErrorIdInt := 16#0003_0205;          // 0003_0205 接触器拒动（窗内未吸合）【故障级】/ Contactor refused to pick up in window, fault level
            _eState      := E_DL_MotorState.eFault;
        ELSIF bCmdStop OR _bStopLatch THEN
            _eState := E_DL_MotorState.eStopping;  // 启动中止：线圈断开，无运行故不计 0003_020A / Aborted start: no run time, 0003_020A not applicable
        END_IF

    E_DL_MotorState.eRunning: // 运行态：反馈吸合确认
        IF bCmdStop OR _bStopLatch THEN
            IF (NOT _fbTonMinRun.Q) AND _bMinRunEn THEN
                _uErrorIdInt := 16#0003_020A;      // 0003_020A 运行不足最短时间即停【信息级】/ Stopped before min run time, info level
            END_IF
            _eState := E_DL_MotorState.eStopping;  // 转停机过渡（To stopping transition）
        ELSIF NOT bFbContactor THEN
            _bFaultLatch := TRUE;                  // 失反馈脱扣锁存（Feedback loss latch）
            _uErrorIdInt := 16#0003_0206;          // 0003_0206 运行中反馈意外断开【故障级】/ Contactor feedback dropped while running, fault level
            _eState      := E_DL_MotorState.eFault;
        END_IF

    E_DL_MotorState.eStopping: // 停机过渡态：线圈已断，等反馈分断
        IF NOT bFbContactor THEN
            _bStopLatch := FALSE;                  // 停止锁存消化（Stop latch absorbed）
            _bCooling   := TRUE;                   // 启动重启抑制冷却（Start restart-inhibit cooling）
            _eState     := E_DL_MotorState.eIdle;  // 回空闲（Back to idle）
        END_IF
        // 反馈触点粘连时保持本态等待分断，直至上层干预（Welded contact holds this state until intervention）

    E_DL_MotorState.eTripOverload: // 过载脱扣锁存态：仅复位且过载消失后可清
        IF (_fbTrigReset.Q OR _bPendReset) AND (NOT bThermalOverload) THEN
            _bPendReset  := FALSE;                 // 消费复位请求（Consume reset request）
            _bFaultLatch := FALSE;                 // 解除锁存（Release latch）
            _uErrorIdInt := 0;                     // 故障码清零（Error code cleared）
            _bCooling    := TRUE;                  // 脱扣复位后同样进入冷却（Cooling also after trip reset）
            _eState      := E_DL_MotorState.eIdle; // 回空闲（Back to idle）
        END_IF

    E_DL_MotorState.eFault: // 故障锁存态：仅复位可退出
        IF _fbTrigReset.Q OR _bPendReset THEN
            _bPendReset  := FALSE;                 // 消费复位请求（Consume reset request）
            _bFaultLatch := FALSE;                 // 解除锁存（Release latch）
            _uErrorIdInt := 0;                     // 故障码清零（Error code cleared）
            _bCooling    := TRUE;                  // 故障复位后进入冷却（Cooling also after fault reset）
            _eState      := E_DL_MotorState.eIdle; // 回空闲（Back to idle）
        END_IF

    ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
        _bFaultLatch := TRUE;                      // 故障锁存（Fault latched）
        _uErrorIdInt := 16#0003_0201;              // 0003_0201 非法状态【故障级】/ Illegal state, fault level
        _eState      := E_DL_MotorState.eFault;
END_CASE

// ============================================================================
// 段 5｜输出映射（bFault 为显式派生式：仅故障级码可达的锁存/状态置位，
//         信息级 0003_0207/0208/020A 天然被排除——0.2 公约）
//      Output mapping (bFault explicit derived form: only fault-level codes
//      can set it, info codes 0003_0207/0208/020A excluded by construction)
// ============================================================================
bContactorCmd   := (_eState = E_DL_MotorState.eStarting) OR (_eState = E_DL_MotorState.eRunning); // 仅启动/运行态得电（Energized only in starting/running）
eState          := _eState;                       // 状态映射（State mapping）
bRunning        := (_eState = E_DL_MotorState.eRunning) AND bFbContactor; // 运行 = 状态且反馈确认（Running = state AND feedback confirmed）
bFault          := _bFaultLatch OR (_eState = E_DL_MotorState.eFault) OR (_eState = E_DL_MotorState.eTripOverload); // 故障派生（Fault derived）
uErrorId        := _uErrorIdInt;                  // 故障码映射（Error code mapping）
bRestartInhibit := _bRestartInhibitAct;           // 重启抑制映射（Restart inhibit mapping）

(*------------------------------------------------------------------------------
 * 方法: CmdStart —— 启动指令（单发）。被抑制（冷却中）或故障态返回 FALSE。
 *      Method CmdStart - start command (one-shot), FALSE when inhibited or faulty.
 *------------------------------------------------------------------------------*)
METHOD CmdStart : BOOL
VAR_INPUT
END_VAR
IF (_eState <> E_DL_MotorState.eIdle) OR _bFaultLatch OR _bRestartInhibitAct THEN
    CmdStart := FALSE;        // 非空闲/故障/冷却期拒绝（Refused: not idle, faulty, or cooling）
ELSE
    _bPendStart := TRUE;      // 登记启动请求，主体状态机评估（Register start request, evaluated by body）
    CmdStart    := TRUE;      // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 无条件安全停止（双线圈全断语义，由主体在运行/启动态消化）。
 *      Method CmdStop - unconditional safe stop, consumed by body in running/starting.
 *------------------------------------------------------------------------------*)
METHOD CmdStop
VAR_INPUT
END_VAR
_bStopLatch := TRUE;          // 登记停止锁存，主体状态机消化（Register stop latch, consumed by body）

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位过载/故障，返回是否可复位（存在锁存故障时为 TRUE）。
 *      Method CmdReset - reset overload/fault, returns TRUE only when latch exists.
 *------------------------------------------------------------------------------*)
METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_MotorState.eFault) OR (_eState = E_DL_MotorState.eTripOverload) THEN
    _bPendReset := TRUE;      // 登记复位请求，主体状态机消化（Register reset request, consumed by body）
    CmdReset    := TRUE;      // 可复位（Resettable）
ELSE
    CmdReset    := FALSE;     // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前状态机状态只读视图。
 *      Property eState (GET) - read-only view of the current state machine state.
 *------------------------------------------------------------------------------*)
PROPERTY eState : E_DL_MotorState
eState := _eState;            // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: bRunning（GET）—— 运行反馈（状态且触点吸合确认）。
 *      Property bRunning (GET) - running feedback (state AND contactor confirmed).
 *------------------------------------------------------------------------------*)
PROPERTY bRunning : BOOL
bRunning := (_eState = E_DL_MotorState.eRunning) AND bFbContactor; // 显式确认式派生（Explicit confirmed derived form）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info-level codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_MotorState.eFault) OR (_eState = E_DL_MotorState.eTripOverload); // 显式排除信息级派生式（Explicit derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（0=无故障）。
 *      Property uErrorId (GET) - last error code (0 = none).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
uErrorId := _uErrorIdInt;     // 返回内部故障码寄存（Return internal error register）

(*------------------------------------------------------------------------------
 * 属性: bRestartInhibit（GET）—— 重启抑制激活指示。
 *      Property bRestartInhibit (GET) - restart inhibit active indicator.
 *------------------------------------------------------------------------------*)
PROPERTY bRestartInhibit : BOOL
bRestartInhibit := _bRestartInhibitAct; // 返回抑制寄存（Return inhibit register）
END_FUNCTION_BLOCK
