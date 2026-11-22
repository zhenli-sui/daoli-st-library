(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SingleSolenoidCyl
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG）与 DL_Base
 *                         的 FB_DL_SignalDebounce，零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_Cylinder）
 * 功能简述 (Function)   : 单电控（单线圈）弹簧复位气缸驱动。得电伸出、失电
 *                         弹簧缩回；无传感器纯时间模式 + 可选磁开关反馈
 *                         双重校验模式；联锁中途撤除线圈失电弹簧复位；
 *                         出口断言保证故障/空闲稳态线圈必断；行程计数；
 *                         状态机复用既有 E_DL_CylinderState（禁止重定义），
 *                         ENUM + CASE + ELSE 兜底。
 * 接口实现 (Implements) : I_DL_Cylinder。接口 OUT 列同名成员（eState/
 *                         bExtended/bRetracted/bFault/uErrorId）按 R22 以
 *                         只读 PROPERTY GET 承载（内部镜像同源，非接口
 *                         成员 bSolenoidExt/bMoving/uCycleCount 保留
 *                         VAR_OUTPUT）；方法 CmdExtend/CmdRetract/CmdStop/
 *                         CmdReset 全部在本文件尾部落地。
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R6 S-1：单电控弹簧
 *                         复位气缸的纯时间定位 + 磁开校验双模式、单线圈
 *                         失电即缩回的保位语义等行业公知工程惯例，公开教学
 *                         资料，仅借鉴通用工程语义；状态机、故障码按本库
 *                         红线独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防越界/出口断言 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 九个定时器/边缘/消抖实例主体最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1/R23 本块为纯事件型状态机（BOOL 指令/反馈 +
 *                         TIME 参数，无积分/滤波类连续量同步语义），免首扫，
 *                         无内部初始化标志。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0220
 *                         伸出到位超时 / 0003_0221 反馈校验失败 / 0003_0222
 *                         非法状态，全部 R15 锁存仅复位可清；本块无信息级
 *                         码，bFault 派生式天然排除信息级（0.2）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 2 条：
 *                         ① 规格中 0003_0221 释义"时间到位但磁开超窗未确认"
 *                           与 0003_0220（伸出到位超时）在伸出方向同窗重叠；
 *                           本实现将 0221 明确用于缩回方向的磁开校验超窗
 *                           （弹簧复位时间到位后磁开仍未确认），两码位各自
 *                           可测、语义不冲突。
 *                         ② bCmdExtend 规格标注"上升沿生效"，因单线圈物理
 *                           语义为"得电即伸出、失电即缩回"（电平跟随），
 *                           本实现按 电平 OR 上升沿 双通道受理，电平语义
 *                           自然涵盖边沿语义，不会产生指令保持而线圈断开
 *                           的悬挂态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *   2026-11-15  v1.0.1  R11 修复：变量名勘误，段 2 行程计数赋值目标
 *                       _uCycleCount → uCycleCount（原写下划线前缀但未在
 *                       VAR 区声明，且同名输出 uCycleCount 全文零写入，
 *                       判定为前缀笔误而非缺声明；三平台编译阻断已消除）。
 *                       R11 fix: name erratum, _uCycleCount -> uCycleCount
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SingleSolenoidCyl IMPLEMENTS I_DL_Cylinder
VAR_INPUT
    bCmdExtend      : BOOL;           // 伸出指令（Extend command），电平 OR 上升沿双通道受理；失电即弹簧缩回 / Extend command, level or edge accepted, coil drop means spring return
    bSnsExtended    : BOOL;           // 可选伸出到位磁性开关（Optional extended reed switch），TRUE=到位；未接时恒 FALSE / Optional extended reed switch, TRUE = in position, FALSE if not wired
    bSnsRetracted   : BOOL;           // 可选缩回到位磁性开关（Optional retracted reed switch），TRUE=到位 / Optional retracted reed switch, TRUE = in position
    bUseSensorCheck : BOOL;           // 反馈校验使能（Sensor check enable），TRUE=时间+磁开双重校验；FALSE=纯时间模式 / Sensor check enable, TRUE = time + reed dual check, FALSE = pure time mode
    bInterlock      : BOOL;           // 允许动作联锁（Motion interlock），TRUE=允许伸出，默认 FALSE 线圈保持断开 / Motion interlock, TRUE = extend allowed, default FALSE holds coil off
    tStrokeTimeExt  : TIME := T#1S;   // 伸出行程时间（Extend stroke time），纯时间模式据此判定到位 / Extend stroke time, basis of position judgment in pure time mode
    tStrokeTimeRet  : TIME := T#1S;   // 弹簧缩回行程时间（Spring return stroke time），纯时间模式据此判定到位 / Spring return stroke time, basis in pure time mode
    tTimeoutExt     : TIME := T#3S;   // 伸出到位超时（Extend timeout），双重校验模式下磁开确认窗口，T#0S=禁用自检 / Extend timeout for reed confirmation window in dual-check mode, T#0S disables
    tDebounce       : TIME := T#20MS; // 磁开防抖窗口（Sensor debounce），T#0S=直通 / Reed switch debounce window, T#0S = pass-through
    bReset          : BOOL;           // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
END_VAR

VAR_OUTPUT
    bSolenoidExt  : BOOL;             // 伸出线圈输出（Extend solenoid coil），得电伸出 / 失电弹簧缩回 / Extend solenoid coil, energized to extend, de-energized for spring return
    bMoving       : BOOL;             // 运动中指示（Moving indicator），伸出或缩回动作中 / Moving indicator, while extending or retracting
    uCycleCount   : UDINT;            // 行程计数（Stroke count），缩回判定沿 +1 / Stroke count, incremented on retracted-state edge
END_VAR

VAR
    _eState          : E_DL_CylinderState := E_DL_CylinderState.eIdle; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bFaultLatch     : BOOL;           // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt     : UDINT;          // 内部故障码寄存（Internal error register），随锁存写入 / Internal error register written on latch
    _bMethExtLatch   : BOOL;           // 方法伸出保持锁存（Method extend hold latch），由 CmdExtend 置位 / Method extend hold latch set by CmdExtend
    _bMethRetLatch   : BOOL;           // 方法缩回保持锁存（Method retract hold latch），由 CmdRetract/CmdStop 置位 / Method retract hold latch set by CmdRetract or CmdStop
    _bPendStop       : BOOL;           // 方法停止请求（Method stop request），由 CmdStop 置位 / Method stop request set by CmdStop
    _bPendReset      : BOOL;           // 方法复位请求（Method reset request），由 CmdReset 置位 / Method reset request set by CmdReset
    _bExtFilt        : BOOL;           // 消抖后伸出磁开（Debounced extended reed）/ Debounced extended reed signal
    _bRetFilt        : BOOL;           // 消抖后缩回磁开（Debounced retracted reed）/ Debounced retracted reed signal
    _bToEn           : BOOL;           // 磁开确认窗口使能（Confirmation window enable），超时参数大于零时有效 / Confirmation window enable, active when timeout above zero
    _bInStrokeExt    : BOOL;           // 伸出态判定中间量（Extending-state test intermediate），喂定时器实例 / Extending-state test intermediate feeding timer instances
    _bInStrokeRet    : BOOL;           // 缩回态判定中间量（Retracting-state test intermediate），喂定时器实例 / Retracting-state test intermediate feeding timer instances
    _bInExtTo        : BOOL;           // 伸出磁开超时窗计时条件（Ext. reed timeout timing condition）/ Timing condition of extend reed timeout window
    _bInRetFbWin     : BOOL;           // 缩回磁开校验窗计时条件（Ret. reed check window condition），行程时间计满后启动 / Retract reed check window condition, starts after stroke time elapsed
    _bInRetractedSt  : BOOL;           // 已缩回态判定中间量（Retracted-state test intermediate），喂计数边缘实例 / Retracted-state test intermediate feeding count edge instance
    _fbDebExt        : FB_DL_SignalDebounce; // 伸出磁开消抖实例（Extended reed debounce），通道一 / Extended reed debounce instance, channel 1
    _fbDebRet        : FB_DL_SignalDebounce; // 缩回磁开消抖实例（Retracted reed debounce），通道二 / Retracted reed debounce instance, channel 2
    _fbTrigExt       : R_TRIG;         // 引脚伸出指令上升沿（Pin extend command edge）/ Pin extend command rising edge
    _fbTrigReset     : R_TRIG;         // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTrigRetState  : R_TRIG;         // 进入已缩回态计数上升沿（Retracted-state count edge）/ Rising edge on entering retracted state for stroke counting
    _fbTonStrokeExt  : TON;            // 伸出行程时间定时器（Extend stroke time timer）/ Extend stroke time timer instance
    _fbTonStrokeRet  : TON;            // 弹簧缩回行程时间定时器（Spring return stroke time timer）/ Spring return stroke time timer instance
    _fbTonExtTo      : TON;            // 伸出磁开确认超时定时器（Extend reed confirmation timeout timer）/ Extend reed confirmation timeout timer instance
    _fbTonRetFb      : TON;            // 缩回磁开校验窗定时器（Retract reed check window timer）/ Retract reed check window timer instance
END_VAR

METHOD CmdExtend : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    CmdExtend       := FALSE;   // 故障态拒绝（Rejected in fault state）
    _bMethRetLatch  := FALSE;   // 清反向残留锁存（Clear stale reverse latch）
ELSE
    _bMethExtLatch  := TRUE;    // 登记伸出保持锁存（Register extend hold latch）
    _bMethRetLatch  := FALSE;   // 互斥注销缩回锁存（Cancel opposite retract latch）
    CmdExtend       := TRUE;    // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdRetract —— 缩回指令（单线圈释放线圈，弹簧复位）。故障态拒绝。
 *      Method CmdRetract - release coil for spring return, rejected in fault.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdRetract : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    CmdRetract      := FALSE;   // 故障态拒绝（Rejected in fault state）
    _bMethExtLatch  := FALSE;   // 清反向残留锁存（Clear stale reverse latch）
ELSE
    _bMethRetLatch  := TRUE;    // 登记缩回锁存（Register retract latch）
    _bMethExtLatch  := FALSE;   // 互斥注销伸出锁存（Cancel opposite extend latch）
    CmdRetract      := TRUE;    // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 线圈释放、弹簧复位至缩回位（单线圈安全侧）。
 *      Method CmdStop - release coil, spring returns to retracted (safe side).
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdStop : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_CylinderState.eFault) THEN
    CmdStop         := FALSE;   // 故障态拒绝（Rejected in fault state）
ELSE
    _bMethExtLatch  := FALSE;   // 注销伸出锁存（Cancel extend latch）
    _bMethRetLatch  := TRUE;    // 登记缩回锁存，主体状态机消化（Register retract latch, consumed by body）
    _bPendStop      := TRUE;    // 登记停止请求（Register stop request）
    CmdStop         := TRUE;    // 受理成功（Accepted）
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
    _bPendReset     := TRUE;    // 登记复位请求，主体状态机消化（Register reset request, consumed by body）
    CmdReset        := TRUE;    // 可复位（Resettable）
ELSE
    CmdReset        := FALSE;   // 无故障可复位（Nothing to reset）
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
_fbTrigReset(CLK := bReset);
_bExtFilt := _fbDebExt.bStable;       // 通道一消抖输出（Channel 1 debounced output）
_bRetFilt := _fbDebRet.bStable;       // 通道二消抖输出（Channel 2 debounced output）
_bInRetractedSt := (_eState = E_DL_CylinderState.eRetracted); // 已缩回态判定（Retracted-state test）
_fbTrigRetState(CLK := _bInRetractedSt);
_bToEn := (tTimeoutExt > T#0S);       // 窗口参数为零 = 自检禁用（Zero window = check disabled）
_bInStrokeExt := (_eState = E_DL_CylinderState.eExtending);   // 伸出态判定（Extending-state test）
_bInStrokeRet := (_eState = E_DL_CylinderState.eRetracting);  // 缩回态判定（Retracting-state test）
_bInExtTo := _bInStrokeExt AND bUseSensorCheck;               // 双重校验模式才计时确认窗（Window timed only in dual-check mode）
_bInRetFbWin := _bInStrokeRet AND bUseSensorCheck AND _fbTonStrokeRet.Q; // 行程时间计满后启动校验窗（Window starts after stroke time elapsed）
_fbTonStrokeExt(IN := _bInStrokeExt, PT := tStrokeTimeExt);
_fbTonStrokeRet(IN := _bInStrokeRet, PT := tStrokeTimeRet);
_fbTonExtTo(IN := _bInExtTo, PT := tTimeoutExt);
_fbTonRetFb(IN := _bInRetFbWin, PT := tTimeoutExt);

// ============================================================================
// 段 2｜行程计数：进入已缩回态上升沿 +1（纯时间模式同样有效，R15 范畴外）
//      Stroke counting: one increment per retracted-state edge, valid in
//      pure time mode too (outside fault-latch scope)
// ============================================================================
IF _fbTrigRetState.Q THEN
    uCycleCount := uCycleCount + 1; // 完整行程 +1（One completed stroke added）
END_IF

// ============================================================================
// 段 3｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
CASE _eState OF

    E_DL_CylinderState.eIdle: // 空闲稳态：线圈必断，按磁开同步实际位置
        IF _bExtFilt AND (NOT _bRetFilt) THEN
            _eState := E_DL_CylinderState.eExtended;   // 首态同步：实际已伸出（Sync: physically extended）
        ELSIF _bRetFilt AND (NOT _bExtFilt) THEN
            _eState := E_DL_CylinderState.eRetracted;  // 首态同步：实际已缩回（Sync: physically retracted）
        ELSIF (bCmdExtend OR _fbTrigExt.Q OR _bMethExtLatch) AND bInterlock AND (NOT _bMethRetLatch) THEN
            _eState := E_DL_CylinderState.eExtending;  // 受理伸出（Accept extend）
        ELSIF _bMethRetLatch OR _bPendStop THEN
            _bMethRetLatch := FALSE;                   // 空闲态消化缩回/停止请求（Absorb retract/stop requests in idle）
            _bPendStop     := FALSE;
        END_IF

    E_DL_CylinderState.eExtending: // 伸出动作中：线圈得电
        IF bUseSensorCheck AND _bExtFilt AND (NOT _bRetFilt) THEN
            _eState := E_DL_CylinderState.eExtended;   // 双重校验：磁开确认到位（Dual check: reed confirms position）
        ELSIF (NOT bUseSensorCheck) AND _fbTonStrokeExt.Q THEN
            _eState := E_DL_CylinderState.eExtended;   // 纯时间模式：行程时间计满判定到位（Pure time: stroke time elapsed）
        ELSIF bUseSensorCheck AND _bToEn AND _fbTonExtTo.Q THEN
            _bFaultLatch := TRUE;                      // 超时故障锁存（Timeout fault latch）
            _uErrorIdInt := 16#0003_0220;              // 0003_0220 伸出到位超时（磁开窗内未确认）【故障级】/ Extend timeout, fault level
            _eState      := E_DL_CylinderState.eFault;
        ELSIF (NOT (bCmdExtend OR _bMethExtLatch)) OR (NOT bInterlock) THEN
            _eState := E_DL_CylinderState.eRetracting; // 指令失电或联锁中途撤除：线圈断、弹簧复位（Command dropped or interlock removed: coil off, spring return）
        ELSIF _bPendStop OR _bMethRetLatch THEN
            _bPendStop     := FALSE;                   // 停止/缩回请求：线圈断弹簧复位（Stop/retract request: coil off, spring return）
            _bMethExtLatch := FALSE;
            _eState        := E_DL_CylinderState.eRetracting;
        END_IF

    E_DL_CylinderState.eExtended: // 已伸出到位稳态：线圈保持得电维持伸出位
        IF (NOT (bCmdExtend OR _bMethExtLatch)) OR (NOT bInterlock) THEN
            _eState := E_DL_CylinderState.eRetracting; // 指令失电或联锁撤除：失电弹簧缩回（Command dropped or interlock removed: spring return）
        ELSIF _bPendStop OR _bMethRetLatch THEN
            _bPendStop     := FALSE;                   // 停止/缩回请求：失电缩回（Stop/retract request: spring return）
            _bMethExtLatch := FALSE;
            _eState        := E_DL_CylinderState.eRetracting;
        END_IF

    E_DL_CylinderState.eRetracting: // 缩回动作中：线圈失电，弹簧复位不可中断
        IF (NOT bUseSensorCheck) AND _fbTonStrokeRet.Q THEN
            _eState := E_DL_CylinderState.eRetracted;  // 纯时间模式：缩回时间计满（Pure time: return stroke time elapsed）
        ELSIF bUseSensorCheck AND _bRetFilt AND (NOT _bExtFilt) THEN
            _eState := E_DL_CylinderState.eRetracted;  // 双重校验：磁开确认到位（Dual check: reed confirms position）
        ELSIF bUseSensorCheck AND _bToEn AND _fbTonRetFb.Q THEN
            _bFaultLatch := TRUE;                      // 反馈校验失败锁存（Feedback check failure latch）
            _uErrorIdInt := 16#0003_0221;              // 0003_0221 反馈校验失败（缩回时间到位但磁开超窗未确认）【故障级】/ Feedback check failure, fault level
            _eState      := E_DL_CylinderState.eFault;
        ELSIF (bCmdExtend OR _bMethExtLatch) AND bInterlock AND (NOT _bMethRetLatch) THEN
            _eState := E_DL_CylinderState.eExtending;  // 缩回途中再伸出（Re-extend during spring return）
        ELSIF _bPendStop THEN
            _bPendStop := FALSE;                       // 消化停止请求，继续缩回至到位（Absorb stop request, spring return continues）
        END_IF

    E_DL_CylinderState.eRetracted: // 已缩回到位稳态：弹簧保持，线圈必断
        IF _bMethRetLatch THEN
            _bMethRetLatch := FALSE;                   // 缩回锁存到位即消化（Retract latch absorbed at retracted position）
        END_IF
        IF (bCmdExtend OR _fbTrigExt.Q OR _bMethExtLatch) AND bInterlock THEN
            _eState := E_DL_CylinderState.eExtending;  // 受理伸出（Accept extend）
        END_IF

    E_DL_CylinderState.eFault: // 故障锁存态：清空全部请求，仅复位可退出
        _bMethExtLatch := FALSE;                       // 清方法锁存（Clear method latches）
        _bMethRetLatch := FALSE;
        _bPendStop     := FALSE;
        IF _bPendReset OR _fbTrigReset.Q THEN
            _bPendReset  := FALSE;                     // 消费复位请求（Consume reset request）
            _bFaultLatch := FALSE;                     // 解除锁存（Release latch）
            _uErrorIdInt := 0;                         // 故障码清零（Error code cleared）
            _eState      := E_DL_CylinderState.eIdle;  // 回空闲态重新同步（Back to idle for re-sync）
        END_IF

    ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
        _bFaultLatch := TRUE;                          // 故障锁存（Fault latched）
        _uErrorIdInt := 16#0003_0222;                  // 0003_0222 非法状态【故障级】/ Illegal state, fault level
        _eState      := E_DL_CylinderState.eFault;
END_CASE

// ============================================================================
// 段 4｜线圈输出推导 + 出口断言（硬约束：故障/空闲稳态线圈必断）
//      Coil output derivation + exit assertion (fault/idle states force coil off)
// ============================================================================
bSolenoidExt := (_eState = E_DL_CylinderState.eExtending) OR (_eState = E_DL_CylinderState.eExtended); // 伸出与保持位得电（Energized in extending and extended hold）
IF (_eState = E_DL_CylinderState.eFault) OR (_eState = E_DL_CylinderState.eIdle) THEN
    bSolenoidExt := FALSE;                             // 出口断言：故障/空闲稳态线圈必断（Assertion: coil forced off in fault/idle）
END_IF
bMoving := (_eState = E_DL_CylinderState.eExtending) OR (_eState = E_DL_CylinderState.eRetracting); // 运动中派生（Moving derived）

(*------------------------------------------------------------------------------
 * 方法: CmdExtend —— 伸出指令（登记保持锁存）。故障态一律拒绝返回 FALSE。
 *      Method CmdExtend - register extend hold latch, rejected with FALSE in fault.
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
