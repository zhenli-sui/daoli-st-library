(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GuardLockDoor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备功能块（Function Block，实现 I_DL_SafetyDoor）
 * 功能简述 (Function)   : 带电磁锁扣安全门联锁控制器。时序骨架（ISO 14119
 *                         公开语义 clean-room）：请求解锁 → 停机请求输出 →
 *                         静止确认（零速反馈或 run-down 计时器二选一）→ 解
 *                         锁输出 → 开门审计 → 关门再锁定确认窗 → 复位后才
 *                         允许重启（禁止自动重启）；防篡改冲突诊断、解锁电
 *                         磁铁出口断言式硬约束。
 * 定位声明 (Positioning): 公约 0.13——本块为标准 PLC 逻辑编排与诊断镜像层，
 *                         不构成 ISO 13849 / IEC 62061 认证安全功能，安全回
 *                         路由认证安全控制器/安全 PLC 承载；硬限位与安全门
 *                         开关的最终防线在认证安全回路。
 * 接口实现 (Implements) : I_DL_SafetyDoor。接口属性同名成员（eState/bClosed/
 *                         bLocked/bUnlockPermitted/bOpened/bFault/uErrorId）
 *                         按 R22 以只读 PROPERTY GET 承载（内部镜像同源），
 *                         非接口成员 bUnlockCoil/bStopRequest/uOpenCount 保
 *                         留 VAR_OUTPUT；方法 CmdRequestUnlock/CmdRelock/
 *                         CmdReset/CmdAuditClear 在本文件尾部落地。
 * 公约遵循 (Convention) : 0.1/R23 事件型时序状态机（指令沿 + 反馈电平驱动），
 *                         免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 全部实例主
 *                         体最前部无条件刷新；0.7/R15 故障级锁存仅复位路径
 *                         清码。
 *                         0.8 故障码段位 16#0003_xxxx（经 DL_Device
 *                         VERSION.md 码表核对：规格建议 0003_0260/0261/0262
 *                         已被 FB_DL_AnalogValve 占用、0003_0105 终审空置，
 *                         依公约冲突顺延）：
 *                         【故障级】0003_0290 静止确认超时（解锁链未达成）、
 *                         0003_0291 门锁不合理组合（防篡改冲突）、0003_0292
 *                         再锁定超时、0003_0293 非法状态兜底；
 *                         【信息级】0003_0121 run-down 计时器模式提示（非零
 *                         速实测，解锁时序期间每拍提示）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 时序超窗防御/出口断言 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 五实例（R_TRIG×2/TON×3）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 解锁链硬约束（出口断言式）：bUnlockCoil 置位前
 *                           提 = （bStandstill 或 tRunDown 计满）AND
 *                           bDoorClosed AND bLockEngaged；三条件不满足时解
 *                           锁输出恒断；
 *                         ② 防篡改冲突：门开（bDoorClosed=FALSE）+ 锁闭反
 *                           馈（bLockEngaged=TRUE）同时为真 → 故障锁存（全
 *                           局监视，任意态生效）；
 *                         ③ 关门再锁定：关门沿 → 锁闭反馈确认窗（常量
 *                           DL_RELOCK_WINDOW）内未闭 → 故障；
 *                         ④ 重启抑制：开门事件后必须 bReset 且门锁全确认才
 *                           回 eIdle，无任何自动重启路径；
 *                         ⑤ tRunDown 按实测最差停机时间整定，制动维护后必
 *                           须重测（引脚注释与手册口径）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 码位顺延：规格建议 0003_0260/0261/0262 与既有
 *                           FB_DL_AnalogValve 冲突、0003_0105 空置，依公约
 *                           0.8 顺延为 0003_0290/0291/0292/0293 与
 *                           0003_0121（核对结果优先于建议值）。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / safety-interlock
 *                         （RAW_NOTES_R7 S-4：ISO 14119 电磁锁扣门联锁公开
 *                         语义——解锁时序骨架、run-down 计时、防篡改诊断，
 *                         公开标准资料，仅借鉴语义域；状态机、出口断言、码
 *                         位与引脚契约 100% 本库独立设计，clean-room 未复
 *                         制源码）。
 * 验收向量 (Acceptance) :
 *   V1 解锁全链（零速模式）：请求 → eStopRequested → bStandstill=TRUE →
 *      eStandstillConfirmed → eUnlocked → 开门 → eOpened 审计+1；
 *   V2 run-down 模式计时链：bUseStandstillFb=FALSE → tRunDown 计满 → 解锁，
 *      期间信息级 0003_0121；
 *   V3 静止确认超时：eStopRequested 超 DL_UNLOCK_TIMEOUT → 故障 0003_0290；
 *   V4 防篡改冲突注入：门开+锁闭反馈同真 → 故障 0003_0291（任意态生效）；
 *   V5 开门审计与再锁定：关门沿 → DL_RELOCK_WINDOW 内锁闭确认 → eLocked；
 *      超窗 → 0003_0292；
 *   V6 复位后重启抑制：再锁定完成 + bReset 沿 → eIdle；无 bReset 时解锁请
 *      求被拒（bUnlockPermitted=FALSE）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 安全门族实现件）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_GuardLockDoor IMPLEMENTS I_DL_SafetyDoor
VAR_INPUT
    bCmdUnlock       : BOOL;            // 解锁请求指令（Unlock request），上升沿发起解锁时序 / Unlock request edge starts the sequence
    bCmdRelock       : BOOL;            // 重新闭锁指令（Relock command），电平生效 / Relock command, level effective
    bReset           : BOOL;            // 上升沿复位故障与重启抑制（Reset edge clears fault and restart inhibit）/ Reset edge
    bDoorClosed      : BOOL;            // 门关闭反馈（Door closed feedback），TRUE=门已关；NC 语义由接线层保证 / Door closed, NC semantics by wiring layer
    bLockEngaged     : BOOL;            // 锁闭反馈（Lock engaged feedback），TRUE=机械锁扣已闭 / Lock engaged, TRUE = mechanical lock closed
    bStandstill      : BOOL;            // 静止确认反馈（Standstill feedback，可选零速信号），TRUE=危险运动已停止 / Standstill feedback, TRUE = hazardous motion stopped
    bUseStandstillFb : BOOL;            // 静止反馈使能（Standstill feedback enable），TRUE=用 bStandstill 判静止；FALSE=用 run-down 计时器 / TRUE = zero-speed mode, FALSE = run-down timer mode
    tRunDown         : TIME := T#5S;    // 停机走完计时（Run-down time），默认 T#5S；按实测最差停机时间整定，制动维护后重测 / Run-down time, tune to measured worst-case stopping time, re-measure after brake maintenance
END_VAR
VAR_OUTPUT
    bUnlockCoil : BOOL;                 // 解锁电磁铁输出（Unlock solenoid coil），断电解锁方向（失电=保持锁定，弹簧锁语义）/ Unlock coil, de-energize-to-unlock (spring-lock semantics)
    bStopRequest: BOOL;                 // 停机请求输出（Stop request），解锁时序中置位直到静止确认 / Stop request active during the unlock sequence until standstill confirmed
    uOpenCount  : UDINT;                // 开门次数审计（Open audit count），CmdAuditClear 清零 / Open audit count, cleared by CmdAuditClear
END_VAR
VAR
    _eState         : E_DL_SafetyDoorState := E_DL_SafetyDoorState.eIdle; // 内部时序状态（Internal sequence state），属性只读 / Internal state, read-only via property
    _bFaultLatch    : BOOL;            // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt    : UDINT;           // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode      : UDINT;           // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bRestartInhibit: BOOL;            // 重启抑制标志（Restart inhibit），开门事件置位、复位沿清除 / Restart inhibit, set on open event, cleared by reset
    _bRelockCheck   : BOOL;            // 再锁定确认窗计时中（Relock confirm window running）/ Relock confirm window running
    _bPendUnlock    : BOOL;            // 方法解锁请求（Method unlock request）/ Method unlock request
    _bPendRelock    : BOOL;            // 方法再闭锁请求（Method relock request）/ Method relock request
    _bPendReset     : BOOL;            // 方法复位请求（Method reset request）/ Method reset request
    _bPendAuditClr  : BOOL;            // 方法审计清除请求（Method audit-clear request）/ Method audit-clear request
    _bUnlockReq     : BOOL;            // 合成解锁请求（Merged unlock request），引脚沿 OR 方法 / Merged unlock request
    _bStandstillOk  : BOOL;            // 静止确认达成（Standstill achieved），零速反馈或计时器二选一 / Standstill achieved by either source
    _fbTrigUnlock   : R_TRIG;          // 解锁请求沿（Unlock request edge）/ Unlock request edge detector
    _fbTrigReset    : R_TRIG;          // 复位沿（Reset edge）/ Reset edge detector
    _fbTonRunDown   : TON;             // run-down 计时器（Run-down timer），计时器模式判静止 / Run-down timer for timer-mode standstill
    _fbTonUnlockTo  : TON;             // 解锁链超时监视（Unlock-chain timeout monitor）/ Unlock-chain timeout monitor
    _fbTonRelockWin : TON;             // 再锁定确认窗（Relock confirm window）/ Relock confirm window
END_VAR
VAR CONSTANT
    DL_RELOCK_WINDOW  : TIME := T#2S;   // 再锁定确认窗（Relock confirm window），窗内未闭锁即故障 / Relock confirm window, no engagement in window = fault
    DL_UNLOCK_TIMEOUT : TIME := T#30S;  // 解锁链总超时（Unlock-chain timeout），静止确认未达即故障 / Unlock-chain timeout for standstill confirmation
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigUnlock(CLK := bCmdUnlock);
_fbTrigReset(CLK := bReset);
_fbTonRunDown(IN := (_eState = E_DL_SafetyDoorState.eStopRequested) AND (NOT bUseStandstillFb), PT := tRunDown); // run-down 计时（Run-down timing）
_fbTonUnlockTo(IN := (_eState = E_DL_SafetyDoorState.eStopRequested), PT := DL_UNLOCK_TIMEOUT);   // 解锁链超时监视（Unlock-chain timeout）
_fbTonRelockWin(IN := _bRelockCheck, PT := DL_RELOCK_WINDOW);                                     // 再锁定确认窗（Relock window）
_bUnlockReq := _fbTrigUnlock.Q OR _bPendUnlock;   // 合成解锁请求（Merged unlock request）

// ============================================================================
// 段 2｜信息级码预清零 + 复位路径（R15：锁存型故障只在解除路径清码）
//      Info code preset + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）

IF _fbTrigReset.Q OR _bPendReset THEN
    _bPendReset := FALSE;         // 消费方法复位请求（Consume method reset）
    // 故障解除前提：防篡改冲突源已消失（门锁状态自洽）
    IF NOT ((NOT bDoorClosed) AND bLockEngaged) THEN
        _bFaultLatch := FALSE;    // 故障锁存解除（Fault latch released）
        _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
        _bRelockCheck := FALSE;   // 确认窗计时取消（Confirm window cancelled）
        IF _eState = E_DL_SafetyDoorState.eFault THEN
            IF bDoorClosed AND bLockEngaged THEN
                _eState := E_DL_SafetyDoorState.eLocked; // 门锁全确认回闭锁态（重启抑制仍保持）/ Back to locked, inhibit retained
            ELSE
                _eState := E_DL_SafetyDoorState.eIdle;   // 否则回待机（Otherwise back to idle）
            END_IF
        END_IF
    END_IF
END_IF

// ============================================================================
// 段 3｜故障全局监视（优先级最高）
//      Global fault monitors (highest priority)
// ============================================================================
IF (NOT bDoorClosed) AND bLockEngaged THEN
    _bFaultLatch := TRUE;         // 门开+锁闭反馈同真：物理不可能组合，防篡改冲突锁存（Tamper conflict latch）
    _uErrorIdInt := 16#0003_0291; // 0003_0291 门锁不合理组合（防篡改冲突）【故障级】/ Impossible door-lock combination, fault level
    _eState := E_DL_SafetyDoorState.eFault;
ELSIF _fbTonUnlockTo.Q AND (_eState = E_DL_SafetyDoorState.eStopRequested) THEN
    _bFaultLatch := TRUE;         // 静止确认超时锁存（Standstill timeout latch）
    _uErrorIdInt := 16#0003_0290; // 0003_0290 静止确认超时（解锁链未达成）【故障级】/ Standstill confirmation timeout, fault level
    _eState := E_DL_SafetyDoorState.eFault;
ELSIF _fbTonRelockWin.Q AND _bRelockCheck THEN
    _bFaultLatch := TRUE;         // 再锁定超时锁存（Relock timeout latch）
    _uErrorIdInt := 16#0003_0292; // 0003_0292 再锁定超时【故障级】/ Relock timeout, fault level
    _eState := E_DL_SafetyDoorState.eFault;
    _bRelockCheck := FALSE;       // 确认窗计时终止（Confirm window terminated）
END_IF

// ============================================================================
// 段 4｜核心时序状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core sequence state machine (ENUM + CASE with ELSE fallback)
// ============================================================================
IF NOT _bFaultLatch THEN
    CASE _eState OF

        E_DL_SafetyDoorState.eIdle: // 待机态：门锁全确认，可受理解锁
            IF _bRestartInhibit THEN
                IF _fbTrigReset.Q THEN
                    _bRestartInhibit := FALSE;  // 复位沿解除重启抑制（Reset edge releases restart inhibit）
                END_IF
            ELSIF _bUnlockReq AND bDoorClosed AND bLockEngaged THEN
                _bPendUnlock := FALSE;          // 消费方法解锁请求（Consume method unlock）
                _eState := E_DL_SafetyDoorState.eStopRequested; // 进入解锁时序（Enter unlock sequence）
            ELSIF _bUnlockReq THEN
                _bPendUnlock := FALSE;          // 门锁未全确认的请求就地拒绝（Request rejected when door/lock not confirmed）
            END_IF

        E_DL_SafetyDoorState.eLocked: // 已闭锁态：再锁定确认中或重启抑制保持
            IF _bRelockCheck THEN
                IF bLockEngaged THEN
                    _bRelockCheck := FALSE;     // 窗内锁闭确认达成（Engagement confirmed inside window）
                END_IF                          // 超窗由段 3 全局监视接管（Window overrun handled by stage 3）
            ELSE
                IF _bRestartInhibit THEN
                    IF _fbTrigReset.Q THEN
                        _bRestartInhibit := FALSE; // 复位沿解除重启抑制（Reset edge releases inhibit）
                        _eState := E_DL_SafetyDoorState.eIdle; // 回待机（Back to idle）
                    END_IF
                ELSE
                    _eState := E_DL_SafetyDoorState.eIdle; // 无抑制直接回待机（No inhibit, back to idle）
                END_IF
            END_IF

        E_DL_SafetyDoorState.eStopRequested: // 已请求停机：等静止确认
            IF NOT bUseStandstillFb THEN
                _uInfoCode := 16#0003_0121;  // 0003_0121 run-down 计时器模式提示【信息级】（非零速实测）/ Run-down timer mode hint, info level
            END_IF
            IF bUseStandstillFb THEN
                _bStandstillOk := bStandstill; // 零速反馈模式（Zero-speed feedback mode）
            ELSE
                _bStandstillOk := _fbTonRunDown.Q; // run-down 计时模式（Run-down timer mode）
            END_IF
            IF _bStandstillOk THEN
                _eState := E_DL_SafetyDoorState.eStandstillConfirmed; // 静止确认达成（To standstill confirmed）
            END_IF

        E_DL_SafetyDoorState.eStandstillConfirmed: // 静止已确认：单拍过渡进解锁
            _eState := E_DL_SafetyDoorState.eUnlocked; // 进入解锁输出态（To unlocked state）

        E_DL_SafetyDoorState.eUnlocked: // 已解锁态：等待开门
            IF NOT bDoorClosed THEN
                uOpenCount := uOpenCount + 1;   // 开门审计累加（Open audit increment）
                _bRestartInhibit := TRUE;       // 开门事件置重启抑制（Open event arms restart inhibit）
                _eState := E_DL_SafetyDoorState.eOpened; // 转门开态（To opened state）
            END_IF

        E_DL_SafetyDoorState.eOpened: // 门已开启：等关门再锁定
            IF _bPendRelock OR bCmdRelock THEN
                _bPendRelock := FALSE;          // 消费方法再闭锁请求（Consume method relock）
            END_IF
            IF bDoorClosed THEN
                _bRelockCheck := TRUE;          // 关门沿启动再锁定确认窗（Door closed starts relock window）
                _eState := E_DL_SafetyDoorState.eLocked; // 转闭锁态（To locked state）
            END_IF

        E_DL_SafetyDoorState.eFault: // 故障锁存态：复位路径见段 2
            // 等待复位（Await reset）

        ELSE
            // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;           // 故障锁存（Fault latch）
            _uErrorIdInt := 16#0003_0293;   // 0003_0293 非法状态兜底【故障级】/ Illegal state, fault level
            _eState := E_DL_SafetyDoorState.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 5｜输出推导 + 解锁电磁铁出口断言式硬约束
//      Output derivation + exit-assertion hard constraint of the unlock coil
// ============================================================================
// 解锁链硬约束：三条件不满足时解锁输出恒断（出口断言式写法）
// Hard constraint: the coil stays off unless all three conditions hold
IF _bStandstillOk AND bDoorClosed AND bLockEngaged AND (_eState = E_DL_SafetyDoorState.eUnlocked) AND (NOT _bFaultLatch) THEN
    bUnlockCoil := TRUE;              // 解锁电磁铁输出有效（Coil energized）
ELSE
    bUnlockCoil := FALSE;             // 出口断言恒断（Assertion: coil off）
END_IF
bStopRequest := (_eState = E_DL_SafetyDoorState.eStopRequested)
            OR (_eState = E_DL_SafetyDoorState.eStandstillConfirmed)
            OR (_eState = E_DL_SafetyDoorState.eUnlocked); // 停机请求随时序派生（Stop request follows the sequence）
IF _bFaultLatch THEN
    bStopRequest := FALSE;            // 故障态停机请求断（出口断言）/ Stop request forced off in fault (assertion)
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdRequestUnlock —— 请求解锁：发起停机请求并进入解锁时序。
 *      Method CmdRequestUnlock - starts the unlock sequence via stop request.
 *------------------------------------------------------------------------------*)
METHOD CmdRequestUnlock : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_SafetyDoorState.eFault) OR (NOT bDoorClosed) THEN
    CmdRequestUnlock := FALSE;    // 故障态/门开态拒绝（Rejected in fault or door-open）
ELSE
    _bPendUnlock := TRUE;         // 登记解锁请求，主体状态机消化（Register unlock, consumed by body）
    CmdRequestUnlock := TRUE;     // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdRelock —— 重新闭锁指令：门开态下关门后受理。
 *      Method CmdRelock - relock, accepted on door close in opened state.
 *------------------------------------------------------------------------------*)
METHOD CmdRelock : BOOL
VAR_INPUT
END_VAR
IF (_eState = E_DL_SafetyDoorState.eOpened) AND bDoorClosed THEN
    _bPendRelock := TRUE;         // 登记再闭锁请求（Register relock request）
    CmdRelock := TRUE;            // 受理成功（Accepted）
ELSE
    CmdRelock := FALSE;           // 非门开态/门未关拒绝（Rejected outside opened-with-closed-door）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障：仅故障态受理（接口方法拒绝语义红线）。
 *      Method CmdReset - reset, accepted only in fault state.
 *------------------------------------------------------------------------------*)
METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_SafetyDoorState.eFault) THEN
    _bPendReset := TRUE;          // 登记复位请求（Register reset request）
    CmdReset := TRUE;             // 可复位（Resettable）
ELSE
    CmdReset := FALSE;            // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdAuditClear —— 清除开门审计记录：故障态拒绝。
 *      Method CmdAuditClear - clears the open audit count, rejected in fault.
 *------------------------------------------------------------------------------*)
METHOD CmdAuditClear : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_SafetyDoorState.eFault) THEN
    CmdAuditClear := FALSE;       // 故障态拒绝（Rejected in fault）
ELSE
    uOpenCount := 0;              // 审计记录清零（Audit count cleared）
    CmdAuditClear := TRUE;        // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前解锁时序状态只读视图。
 *      Property eState (GET) - read-only sequence state view.
 *------------------------------------------------------------------------------*)
PROPERTY eState : E_DL_SafetyDoorState
eState := _eState;                // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: bClosed（GET）—— 门已关闭反馈镜像。
 *      Property bClosed (GET) - door-closed feedback mirror.
 *------------------------------------------------------------------------------*)
PROPERTY bClosed : BOOL
bClosed := bDoorClosed;           // 反馈镜像（Feedback mirror）

(*------------------------------------------------------------------------------
 * 属性: bLocked（GET）—— 锁已闭锁反馈镜像。
 *      Property bLocked (GET) - lock-engaged feedback mirror.
 *------------------------------------------------------------------------------*)
PROPERTY bLocked : BOOL
bLocked := bLockEngaged;          // 反馈镜像（Feedback mirror）

(*------------------------------------------------------------------------------
 * 属性: bUnlockPermitted（GET）—— 允许解锁：无故障、无重启抑制且门锁全确认。
 *      Property bUnlockPermitted (GET) - unlock permitted derivation.
 *------------------------------------------------------------------------------*)
PROPERTY bUnlockPermitted : BOOL
bUnlockPermitted := (NOT _bFaultLatch) AND (NOT _bRestartInhibit)
                AND bDoorClosed AND bLockEngaged
                AND ((_eState = E_DL_SafetyDoorState.eIdle) OR (_eState = E_DL_SafetyDoorState.eLocked)); // 多条件派生式（Multi-condition derived form）

(*------------------------------------------------------------------------------
 * 属性: bOpened（GET）—— 门开启诊断镜像。
 *      Property bOpened (GET) - door-open diagnostic mirror.
 *------------------------------------------------------------------------------*)
PROPERTY bOpened : BOOL
bOpened := NOT bDoorClosed;       // 门开镜像（Door-open mirror）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_SafetyDoorState.eFault); // 显式排除信息级派生式（Derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（故障级优先，无故障时透出本拍信息级
 *         码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last error code (fault priority, info shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_SafetyDoorState.eFault) THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
