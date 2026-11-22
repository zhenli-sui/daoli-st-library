(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PneumaticCylinder
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）与本库 DL_Base
 *                         的 FB_DL_SignalDebounce，零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_Cylinder）
 * 功能简述 (Function)   : 标准双电控（双线圈）气缸控制功能块。含磁开信号双通道
 *                         消抖、伸出/缩回超时自检、双传感器位置冲突锁存、
 *                         双线圈互斥出口断言、联锁失电保位、行程计数；
 *                         状态机采用 ENUM + CASE + ELSE 兜底。
 * 接口实现 (Implements) : I_DL_Cylinder（属性 eState/bExtended/bRetracted/
 *                         bFault/uErrorId，方法 CmdExtend/CmdRetract/
 *                         CmdStop/CmdReset，全部在本文件尾部落地）
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R5 S-4：工业气动气缸
 *                         FB 设计指南 / 双电控 5/2 阀 + 磁性开关 + 行程计数
 *                         接线语义 / 双线圈禁止同时得电互锁惯例，公开教学
 *                         文章，仅借鉴通用工程语义；状态机、故障码、互斥
 *                         断言按本库红线独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防越界/互斥断言 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 六个定时器/边缘实例主体最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1 本块为纯事件型状态机，无积分/滤波类首扫初始化
 *                         逻辑（消抖由 FB_DL_SignalDebounce 内部自理），
 *                         首扫跟踪范式不适用，无内部初始化标志。
 *                         0.7 故障码段位 16#0003_xxxx：0003_0201 非法状态/
 *                         0003_0202 伸出超时/0003_0203 缩回超时/0003_0204
 *                         双传感器冲突，全部【故障级】R15 锁存仅复位可清；
 *                         本块无信息级码，bFault 派生式天然排除信息级（0.2）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R5 轮 · DL_Device 开库）
 *   2026-11-15  v1.0.1  R11 修复：变量名勘误，段 2 行程计数赋值目标
 *                       _uCycleCount → uCycleCount（原写下划线前缀但未在
 *                       VAR 区声明，且同名输出 uCycleCount 全文零写入，
 *                       判定为前缀笔误而非缺声明；三平台编译阻断已消除）。
 *                       R11 fix: name erratum, _uCycleCount -> uCycleCount
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PneumaticCylinder IMPLEMENTS I_DL_Cylinder
VAR_INPUT
    bCmdExtend    : BOOL;         // 伸出指令（Extend command），上升沿生效 / Extend command, rising edge effective
    bCmdRetract   : BOOL;         // 缩回指令（Retract command），上升沿生效 / Retract command, rising edge effective
    bSnsExtended  : BOOL;         // 伸出到位磁性开关（Extended reed switch），TRUE=到位 / Extended reed switch, TRUE = in position
    bSnsRetracted : BOOL;         // 缩回到位磁性开关（Retracted reed switch），TRUE=到位 / Retracted reed switch, TRUE = in position
    bInterlock    : BOOL;         // 允许动作联锁（Motion interlock），TRUE=允许动作，默认 FALSE 双线圈保持断开 / Motion interlock, TRUE = motion allowed, default FALSE holds coils off
    tTimeoutExt   : TIME := T#2S; // 伸出到位超时（Extend timeout），T#0S=禁用自检 / Extend timeout, T#0S disables the check
    tTimeoutRet   : TIME := T#2S; // 缩回到位超时（Retract timeout），T#0S=禁用自检 / Retract timeout, T#0S disables the check
    tDebounce     : TIME := T#20MS; // 磁开防抖窗口（Sensor debounce），T#0S=直通 / Sensor debounce window, T#0S = pass-through
    bReset        : BOOL;         // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
END_VAR

VAR_OUTPUT
    bSolenoidExt  : BOOL;         // 伸出线圈输出（Extend solenoid coil），TRUE=得电 / Extend solenoid coil, TRUE = energized
    bSolenoidRet  : BOOL;         // 缩回线圈输出（Retract solenoid coil），TRUE=得电 / Retract solenoid coil, TRUE = energized
    eState        : E_DL_CylinderState; // 当前状态机状态（Current state），映射接口同名属性 / Current state, mirrors interface property
    bExtended     : BOOL;         // 伸出到位磁开反馈（Extended reed feedback），消抖后 / Extended reed feedback, debounced
    bRetracted    : BOOL;         // 缩回到位磁开反馈（Retracted reed feedback），消抖后 / Retracted reed feedback, debounced
    bMoving       : BOOL;         // 运动中指示（Moving indicator），TRUE=伸出或缩回动作中 / Moving indicator, TRUE while extending or retracting
    bFault        : BOOL;         // 故障锁存中（Fault latched），TRUE=需复位 / Fault latched, TRUE requires reset
    uErrorId      : UDINT;        // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx
    uCycleCount   : UDINT;        // 行程计数（Stroke count），缩回到位上升沿 +1 / Stroke count, incremented on retracted-position rising edge
END_VAR

VAR
    _eState       : E_DL_CylinderState := E_DL_CylinderState.eIdle; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bFaultLatch  : BOOL;         // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt  : UDINT;        // 内部故障码寄存（Internal error register），随锁存写入 / Internal error register written on latch
    _bPendExtend  : BOOL;         // 方法伸出请求锁存（Method extend request），由 CmdExtend 置位 / Method extend request set by CmdExtend
    _bPendRetract : BOOL;         // 方法缩回请求锁存（Method retract request），由 CmdRetract 置位 / Method retract request set by CmdRetract
    _bPendStop    : BOOL;         // 方法停止请求锁存（Method stop request），由 CmdStop 置位 / Method stop request set by CmdStop
    _bPendReset   : BOOL;         // 方法复位请求锁存（Method reset request），由 CmdReset 置位 / Method reset request set by CmdReset
    _bExtFilt     : BOOL;         // 消抖后伸出磁开（Debounced extended reed）/ Debounced extended reed signal
    _bRetFilt     : BOOL;         // 消抖后缩回磁开（Debounced retracted reed）/ Debounced retracted reed signal
    _bExtToEn     : BOOL;         // 伸出超时自检使能（Extend timeout check enable），超时参数大于零时有效 / Extend timeout enable, active when timeout parameter above zero
    _bRetToEn     : BOOL;         // 缩回超时自检使能（Retract timeout check enable），超时参数大于零时有效 / Retract timeout enable, active when timeout parameter above zero
    _fbDebExt     : FB_DL_SignalDebounce; // 伸出磁开消抖实例（Extended reed debounce），通道一 / Extended reed debounce instance, channel 1
    _fbDebRet     : FB_DL_SignalDebounce; // 缩回磁开消抖实例（Retracted reed debounce），通道二 / Retracted reed debounce instance, channel 2
    _fbTrigExt    : R_TRIG;       // 引脚伸出指令上升沿（Pin extend command edge）/ Pin extend command rising edge
    _fbTrigRet    : R_TRIG;       // 引脚缩回指令上升沿（Pin retract command edge）/ Pin retract command rising edge
    _fbTrigReset  : R_TRIG;       // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTrigStroke : R_TRIG;       // 缩回到位计数上升沿（Stroke count edge）/ Stroke count rising edge on retracted feedback
    _fbTonExtTo   : TON;          // 伸出到位超时定时器（Extend timeout timer）/ Extend timeout timer instance
    _fbTonRetTo   : TON;          // 缩回到位超时定时器（Retract timeout timer）/ Retract timeout timer instance
END_VAR

METHOD CmdExtend : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    CmdExtend     := FALSE;   // 故障态拒绝（Rejected in fault state）
    _bPendRetract := FALSE;   // 清反向残留请求（Clear stale reverse request）
ELSE
    _bPendExtend  := TRUE;    // 登记伸出请求（Register extend request）
    _bPendRetract := FALSE;   // 互斥注销反向请求（Cancel opposite request）
    CmdExtend     := TRUE;    // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdRetract —— 缩回指令（单发）。故障锁存态一律拒绝并返回 FALSE。
 *      Method CmdRetract - retract command (one-shot), rejected with FALSE in fault state.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdRetract : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    CmdRetract   := FALSE;    // 故障态拒绝（Rejected in fault state）
    _bPendExtend := FALSE;    // 清反向残留请求（Clear stale reverse request）
ELSE
    _bPendRetract := TRUE;    // 登记缩回请求（Register retract request）
    _bPendExtend  := FALSE;   // 互斥注销反向请求（Cancel opposite request）
    CmdRetract    := TRUE;    // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 双线圈全断、保持当前位置。故障锁存态拒绝返回 FALSE。
 *      Method CmdStop - both coils off and hold position, rejected with FALSE in fault state.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdStop : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    CmdStop := FALSE;         // 故障态拒绝（Rejected in fault state）
ELSE
    _bPendExtend  := FALSE;   // 注销全部动作请求（Cancel all motion requests）
    _bPendRetract := FALSE;
    _bPendStop    := TRUE;    // 登记停止请求，主体状态机消化（Register stop request, consumed by body）
    CmdStop       := TRUE;    // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障，返回是否可复位（存在锁存故障时为 TRUE）。
 *      Method CmdReset - reset fault, returns TRUE only when a latch exists.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    _bPendReset := TRUE;      // 登记复位请求，主体状态机消化（Register reset request, consumed by body）
    CmdReset    := TRUE;      // 可复位（Resettable）
ELSE
    CmdReset    := FALSE;     // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前状态机状态只读视图。
 *      Property eState (GET) - read-only view of the current state machine state.
 *------------------------------------------------------------------------------*)
    END_METHOD

// ============================================================================
// 段 1｜定时器与边缘检测实例无条件周期刷新（R7：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all timer and edge instances (R7)
// ============================================================================
_fbDebExt(bRawInput := bSnsExtended, tRiseDelay := tDebounce, tFallDelay := tDebounce, bEnable := TRUE, bReset := FALSE);
_fbDebRet(bRawInput := bSnsRetracted, tRiseDelay := tDebounce, tFallDelay := tDebounce, bEnable := TRUE, bReset := FALSE);
_fbTrigExt(CLK := bCmdExtend);
_fbTrigRet(CLK := bCmdRetract);
_fbTrigReset(CLK := bReset);
_bExtFilt := _fbDebExt.bStable;   // 通道一消抖输出（Channel 1 debounced output）
_bRetFilt := _fbDebRet.bStable;   // 通道二消抖输出（Channel 2 debounced output）
_fbTrigStroke(CLK := _bRetFilt);

_bExtToEn := (tTimeoutExt > T#0S); // 超时参数为零 = 自检禁用（Zero timeout = check disabled）
_bRetToEn := (tTimeoutRet > T#0S); // 超时参数为零 = 自检禁用（Zero timeout = check disabled）
_fbTonExtTo(IN := (_eState = E_DL_CylinderState.eExtending) AND _bExtToEn, PT := tTimeoutExt);
_fbTonRetTo(IN := (_eState = E_DL_CylinderState.eRetracting) AND _bRetToEn, PT := tTimeoutRet);

// ============================================================================
// 段 2｜行程计数：缩回到位上升沿 +1（R15 范畴外，非故障量，不锁存）
//      Stroke counting: one increment per retracted-position rising edge
// ============================================================================
IF _fbTrigStroke.Q THEN
    uCycleCount := uCycleCount + 1; // 完整行程 +1（One completed stroke added）
END_IF

// ============================================================================
// 段 3｜位置冲突全局监视：双磁开同时动作物理不可能，立即锁存（优先级最高）
//      Global position-conflict monitor: both reed switches ON is physically
//      impossible, latch immediately (highest priority over the state machine)
// ============================================================================
IF _bExtFilt AND _bRetFilt THEN
    _bFaultLatch := TRUE;                          // 故障锁存（Fault latched）
    _uErrorIdInt := 16#0003_0204;                  // 0003_0204 双传感器同时动作【故障级】/ Both sensors active, fault level
    _eState      := E_DL_CylinderState.eFault;     // 强制进入故障态（Force fault state）
END_IF

// ============================================================================
// 段 4｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
CASE _eState OF

    E_DL_CylinderState.eIdle: // 空闲稳态：双线圈全断，按传感器同步实际位置
        IF _bExtFilt AND (NOT _bRetFilt) THEN
            _eState := E_DL_CylinderState.eExtended;  // 首态同步：实际已伸出（Sync: physically extended）
        ELSIF _bRetFilt AND (NOT _bExtFilt) THEN
            _eState := E_DL_CylinderState.eRetracted; // 首态同步：实际已缩回（Sync: physically retracted）
        ELSIF (_bPendExtend OR _fbTrigExt.Q) AND bInterlock THEN
            _bPendExtend  := FALSE;                    // 消费伸出请求（Consume extend request）
            _eState       := E_DL_CylinderState.eExtending;
        ELSIF (_bPendRetract OR _fbTrigRet.Q) AND bInterlock THEN
            _bPendRetract := FALSE;                    // 消费缩回请求（Consume retract request）
            _eState       := E_DL_CylinderState.eRetracting;
        ELSIF _bPendStop THEN
            _bPendStop := FALSE;                       // 空闲态停止请求直接消化（Stop request absorbed in idle）
        END_IF

    E_DL_CylinderState.eExtending: // 伸出动作中：伸出线圈得电
        IF _bExtFilt AND (NOT _bRetFilt) THEN
            _eState := E_DL_CylinderState.eExtended;   // 到位确认（Reached extended position）
        ELSIF _fbTonExtTo.Q THEN
            _bFaultLatch := TRUE;                      // 超时故障锁存（Timeout fault latch）
            _uErrorIdInt := 16#0003_0202;              // 0003_0202 伸出到位超时【故障级】/ Extend timeout, fault level
            _eState      := E_DL_CylinderState.eFault;
        ELSIF NOT bInterlock THEN
            _eState := E_DL_CylinderState.eIdle;       // 联锁中途撤除：双线圈断、保位、不判故障（Interlock dropped mid-stroke: coils off, hold position, no fault）
        ELSIF _bPendStop THEN
            _bPendStop := FALSE;                       // 停止指令：双线圈全断保位（Stop command: both coils off, hold position）
            _eState    := E_DL_CylinderState.eIdle;
        ELSIF (_bPendRetract OR _fbTrigRet.Q) AND bInterlock THEN
            _bPendRetract := FALSE;                    // 行程中途反向（Mid-stroke reversal to retract）
            _eState       := E_DL_CylinderState.eRetracting;
        END_IF

    E_DL_CylinderState.eExtended: // 已伸出到位稳态
        IF _bPendStop THEN
            _bPendStop := FALSE;                       // 停止请求消化（Stop request absorbed）
            _eState    := E_DL_CylinderState.eIdle;
        ELSIF (_bPendRetract OR _fbTrigRet.Q) AND bInterlock THEN
            _bPendRetract := FALSE;                    // 受理缩回（Accept retract command）
            _eState       := E_DL_CylinderState.eRetracting;
        END_IF

    E_DL_CylinderState.eRetracting: // 缩回动作中：缩回线圈得电
        IF _bRetFilt AND (NOT _bExtFilt) THEN
            _eState := E_DL_CylinderState.eRetracted;  // 到位确认（Reached retracted position）
        ELSIF _fbTonRetTo.Q THEN
            _bFaultLatch := TRUE;                      // 超时故障锁存（Timeout fault latch）
            _uErrorIdInt := 16#0003_0203;              // 0003_0203 缩回到位超时【故障级】/ Retract timeout, fault level
            _eState      := E_DL_CylinderState.eFault;
        ELSIF NOT bInterlock THEN
            _eState := E_DL_CylinderState.eIdle;       // 联锁中途撤除：双线圈断、保位、不判故障（Interlock dropped mid-stroke: coils off, hold position, no fault）
        ELSIF _bPendStop THEN
            _bPendStop := FALSE;                       // 停止指令：双线圈全断保位（Stop command: both coils off, hold position）
            _eState    := E_DL_CylinderState.eIdle;
        ELSIF (_bPendExtend OR _fbTrigExt.Q) AND bInterlock THEN
            _bPendExtend := FALSE;                     // 行程中途反向（Mid-stroke reversal to extend）
            _eState      := E_DL_CylinderState.eExtending;
        END_IF

    E_DL_CylinderState.eRetracted: // 已缩回到位稳态
        IF _bPendStop THEN
            _bPendStop := FALSE;                       // 停止请求消化（Stop request absorbed）
            _eState    := E_DL_CylinderState.eIdle;
        ELSIF (_bPendExtend OR _fbTrigExt.Q) AND bInterlock THEN
            _bPendExtend := FALSE;                     // 受理伸出（Accept extend command）
            _eState      := E_DL_CylinderState.eExtending;
        END_IF

    E_DL_CylinderState.eFault: // 故障锁存态：清空全部请求，仅复位可退出
        _bPendExtend  := FALSE;                        // 清方法请求（Clear method requests）
        _bPendRetract := FALSE;
        _bPendStop    := FALSE;
        IF _bPendReset OR _fbTrigReset.Q THEN
            _bPendReset  := FALSE;                     // 消费复位请求（Consume reset request）
            _bFaultLatch := FALSE;                     // 解除锁存（Release latch）
            _uErrorIdInt := 0;                         // 故障码清零（Error code cleared）
            _eState      := E_DL_CylinderState.eIdle;  // 回空闲态重新同步（Back to idle for re-sync）
        END_IF

    ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
        _bFaultLatch := TRUE;                          // 故障锁存（Fault latched）
        _uErrorIdInt := 16#0003_0201;                  // 0003_0201 非法状态【故障级】/ Illegal state, fault level
        _eState      := E_DL_CylinderState.eFault;
END_CASE

// ============================================================================
// 段 5｜线圈输出推导 + 双线圈互斥出口断言（硬约束：两输出恒不可同真）
//      Coil output derivation + dual-coil exclusivity assertion at exit
// ============================================================================
bSolenoidExt := (_eState = E_DL_CylinderState.eExtending);   // 仅动作态单端置位（Energize only during motion）
bSolenoidRet := (_eState = E_DL_CylinderState.eRetracting);
IF bSolenoidExt AND bSolenoidRet THEN
    bSolenoidExt := FALSE;                                   // 断言对调：异常同真时双断保安全（Assertion fallback: cut both on impossible condition）
    bSolenoidRet := FALSE;
END_IF

// ============================================================================
// 段 6｜状态引脚映射（bFault 为显式派生式，排除信息级码——本块无信息级码）
//      Status pin mapping (bFault explicit derived form, info codes excluded)
// ============================================================================
eState     := _eState;                                       // 状态映射（State mapping）
bExtended  := _bExtFilt;                                     // 伸出反馈映射（Extended feedback mapping）
bRetracted := _bRetFilt;                                     // 缩回反馈映射（Retracted feedback mapping）
bMoving    := (_eState = E_DL_CylinderState.eExtending) OR (_eState = E_DL_CylinderState.eRetracting); // 运动中派生（Moving derived）
bFault     := _bFaultLatch OR (_eState = E_DL_CylinderState.eFault); // 故障派生（Fault derived）
uErrorId   := _uErrorIdInt;                                  // 故障码映射（Error code mapping）

(*------------------------------------------------------------------------------
 * 方法: CmdExtend —— 伸出指令（单发）。故障锁存态一律拒绝并返回 FALSE。
 *      Method CmdExtend - extend command (one-shot), rejected with FALSE in fault state.
 *------------------------------------------------------------------------------*)




PROPERTY eState : E_DL_CylinderState
eState := _eState;            // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: bExtended（GET）—— 伸出到位磁开反馈（消抖后）。
 *      Property bExtended (GET) - debounced extended reed feedback.
 *------------------------------------------------------------------------------*)
PROPERTY bExtended : BOOL
bExtended := _bExtFilt;       // 返回通道一消抖输出（Return channel 1 debounced output）

(*------------------------------------------------------------------------------
 * 属性: bRetracted（GET）—— 缩回到位磁开反馈（消抖后）。
 *      Property bRetracted (GET) - debounced retracted reed feedback.
 *------------------------------------------------------------------------------*)
PROPERTY bRetracted : BOOL
bRetracted := _bRetFilt;      // 返回通道二消抖输出（Return channel 2 debounced output）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info-level codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_CylinderState.eFault); // 显式排除信息级派生式（Explicit derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（0=无故障）。
 *      Property uErrorId (GET) - last error code (0 = none).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
uErrorId := _uErrorIdInt;     // 返回内部故障码寄存（Return internal error register）
END_FUNCTION_BLOCK
