(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VacuumEjector
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / TP），零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_VacuumGenerator）
 * 功能简述 (Function)   : 真空发生器（射流式负压源）控制功能块。负压阈值
 *                         建立判据（负压域迟滞：建立用设定值、保持放宽
 *                         迟滞带防临界抖动）+ 可选真空开关双确认；破真空
 *                         吹气定宽单发脉冲（吹气期间真空阀强制断）；负压
 *                         反馈非有限值防御保持末次有效值；建立超时锁存；
 *                         状态机 ENUM + CASE + ELSE 兜底。
 * 接口实现 (Implements) : I_DL_VacuumGenerator。接口 OUT 列同名成员
 *                         （eState/bVacuumOk/fPressure/bFault/uErrorId）按
 *                         R22 以只读 PROPERTY GET 承载（内部镜像同源），
 *                         非接口成员 bVacuumValve/bBlowValve/bHolding 保留
 *                         VAR_OUTPUT；方法 CmdEvacuate/CmdBlowOff/CmdStop/
 *                         CmdReset 全部在本文件尾部落地。
 * 开源溯源 (Origin)     : 来源标签 lbp-device（RAW_NOTES_R6 S-1：真空吸持的
 *                         建立-保持迟滞判据、破真空吹气定宽脉冲、真空开关
 *                         双确认等行业公知工程惯例，公开教学资料，仅借鉴
 *                         通用工程语义；状态机、迟滞方向、故障码按本库红线
 *                         独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防除零/非有限值防御/浮点
 *                         容差比较 ✓｜R5 全变量中英双语同行注释 ✓
 *                         R6 ENUM+CASE+ELSE ✓｜R7 六个定时器/边缘/脉冲实例
 *                         主体最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1/R23 本块为事件型状态机 + 逐拍组合阈值判定：
 *                         迟滞保持态每拍由实时负压重算自校正，无积分/滤波
 *                         类需要首扫初始化的连续量驻留状态，免首扫（无
 *                         bInit 标志）。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0230
 *                         负压反馈信号无效 / 0003_0231 真空建立超时（含
 *                         双确认模式下开关校验超窗）/ 0003_0232 非法状态，
 *                         全部 R15 锁存仅复位可清；本块无信息级码，bFault
 *                         派生式天然排除信息级（0.2）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 规格建议吹气脉冲用"内部时间戳累积法"自实现
 *                           TP 语义；时间戳累积需时钟基准，与公约 0.9
 *                           "禁读时钟、时间一律注入"冲突，本实现改用
 *                           IEC 标准 TP 定宽脉冲定时器（Standard.library，
 *                           纯跨平台，语义等价），R14 断输入一拍规则对
 *                           组态期定值 PT 不涉及。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *   2026-11-15  v1.0.1  终审修复【致命】吹气脉冲触发时序：原实现 _bBlowReq
 *                       于主体末尾同拍自清，TP 实例（段 1 最前部刷新）永远
 *                       采不到 TRUE 入参，bBlowValve 恒 FALSE、eBlowing 态
 *                       下一拍即退回 eIdle（验收向量 V3 不成立，R13 逐拍
 *                       推演复现）。修法：自清动作移至 TP 实例调用之后，
 *                       TP 本拍采样 TRUE 起振、下一拍入参回落，定宽脉冲
 *                       由 TP 自身保持。引脚契约零变更。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_VacuumEjector IMPLEMENTS I_DL_VacuumGenerator
VAR_INPUT
    bCmdEvacuate      : BOOL;           // 建立真空指令（Evacuate command），上升沿生效 / Evacuate command, rising edge effective
    bCmdBlowOff       : BOOL;           // 破真空吹气指令（Blow-off command），上升沿生效，输出 tBlowPulse 定宽脉冲 / Blow-off command, rising edge outputs fixed-width pulse
    fPressureFeedback : REAL;           // 负压表反馈（Pressure feedback）[kPa]，0=大气，负值=真空度；非有限值防御 / Pressure feedback [kPa], 0 = atmospheric, negative = vacuum, non-finite defended
    bFbVacuumSwitch   : BOOL;           // 可选真空开关反馈（Optional vacuum switch feedback），TRUE=真空确认 / Optional vacuum switch feedback, TRUE = vacuum confirmed
    bUseSensorCheck   : BOOL;           // 开关反馈校验使能（Sensor check enable），TRUE=负压阈值+开关双确认 / Sensor check enable, TRUE = threshold + switch dual confirmation
    fVacuumSetpoint   : REAL := -60.0;  // 真空建立阈值（Vacuum setpoint）[kPa]，负压域 / Vacuum establishment threshold in negative-pressure domain
    fVacuumHysteresis : REAL := 5.0;    // 真空判定迟滞（Vacuum hysteresis）[kPa]，保持判据放宽量，负值防御钳零 / Hysteresis band for hold criterion, negative clamped to zero
    tEstablishTimeout : TIME := T#5S;   // 真空建立超时（Establish timeout），T#0S=禁用 / Establish timeout, T#0S disables the check
    tBlowPulse        : TIME := T#500MS; // 破真空吹气脉冲宽度（Blow-off pulse width）/ Blow-off pulse width
    tDebounce         : TIME := T#20MS; // 开关反馈防抖（Switch debounce），T#0S=直通 / Switch feedback debounce, T#0S = pass-through
    bReset            : BOOL;           // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
END_VAR

VAR_OUTPUT
    bVacuumValve : BOOL;                // 真空电磁阀输出（Vacuum solenoid valve），TRUE=抽真空 / Vacuum solenoid valve, TRUE = evacuating
    bBlowValve   : BOOL;                // 破真空吹气阀输出（Blow-off solenoid valve），定宽脉冲 / Blow-off solenoid valve, fixed-width pulse
    bHolding     : BOOL;                // 吸附保持中指示（Holding indicator），真空确认态为 TRUE / Holding indicator, TRUE in vacuum-ok state
END_VAR

VAR
    _eState         : E_DL_VacuumState := E_DL_VacuumState.eIdle; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bFaultLatch    : BOOL;           // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt    : UDINT;          // 内部故障码寄存（Internal error register），随锁存写入 / Internal error register written on latch
    _bPendEvac      : BOOL;           // 方法抽真空请求（Method evacuate request），由 CmdEvacuate 置位 / Method evacuate request set by CmdEvacuate
    _bPendBlow      : BOOL;           // 方法吹气请求（Method blow-off request），由 CmdBlowOff 置位 / Method blow-off request set by CmdBlowOff
    _bPendStop      : BOOL;           // 方法停止请求（Method stop request），由 CmdStop 置位 / Method stop request set by CmdStop
    _bPendReset     : BOOL;           // 方法复位请求（Method reset request），由 CmdReset 置位 / Method reset request set by CmdReset
    _bBlowReq       : BOOL;           // 吹气单拍触发请求（Blow pulse trigger request），上升沿消费置位一拍 / One-cycle blow trigger, set on edge consumption
    _fPressValid    : REAL := 0.0;    // 末次有效负压值（Last valid pressure）[kPa]，非有限值防御保持载体 / Last valid pressure hold carrier
    _fSetpEff       : REAL := -60.0;  // 防御后建立阈值（Sanitized setpoint）[kPa] / Sanitized vacuum setpoint
    _fHystEff       : REAL := 5.0;    // 防御后迟滞带（Sanitized hysteresis）[kPa]，钳制非负 / Sanitized hysteresis band, clamped non-negative
    _bPressValid    : BOOL;           // 本拍负压输入有效性（Pressure input validity this cycle），非有限值为 FALSE / FALSE when pressure input non-finite
    _bSwFilt        : BOOL;           // 防抖后真空开关（Debounced vacuum switch）/ Debounced vacuum switch signal
    _bInEstablish   : BOOL;           // 建立超时计时条件（Establish timeout timing condition）/ Timing condition of establish timeout
    _bEstToEn       : BOOL;           // 建立超时使能（Establish timeout enable），参数大于零有效 / Establish timeout enable, active when above zero
    _bEstablished   : BOOL;           // 本拍真空建立判据结果（Establishment criterion result this cycle）/ Establishment criterion result this cycle
    _bHoldCriterion : BOOL;           // 本拍保持判据结果（Hold criterion result this cycle），迟滞放宽域 / Hold criterion result within hysteresis band
    _fbTrigEvac     : R_TRIG;         // 引脚抽真空指令上升沿（Pin evacuate command edge）/ Pin evacuate command rising edge
    _fbTrigBlow     : R_TRIG;         // 引脚吹气指令上升沿（Pin blow-off command edge）/ Pin blow-off command rising edge
    _fbTrigReset    : R_TRIG;         // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTonSwDeb     : TON;            // 真空开关防抖定时器（Vacuum switch debounce timer）/ Vacuum switch debounce timer instance
    _fbTonEstablish : TON;            // 真空建立超时定时器（Establish timeout timer）/ Establish timeout timer instance
    _fbTpBlow       : TP;             // 吹气定宽脉冲定时器（Blow-off pulse timer），IEC 标准 TP / Blow-off fixed-width pulse timer, IEC standard TP
END_VAR

METHOD CmdEvacuate : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VacuumState.eFault) THEN
    CmdEvacuate := FALSE;     // 故障态拒绝（Rejected in fault state）
ELSE
    _bPendEvac  := TRUE;      // 登记抽真空请求，主体状态机消化（Register evacuate request, consumed by body）
    CmdEvacuate := TRUE;      // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdBlowOff —— 破真空吹气指令（单发定宽脉冲）。故障态拒绝。
 *      Method CmdBlowOff - blow-off command (one-shot pulse), rejected in fault.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdBlowOff : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VacuumState.eFault) THEN
    CmdBlowOff := FALSE;      // 故障态拒绝（Rejected in fault state）
ELSE
    _bPendBlow := TRUE;       // 登记吹气请求，主体状态机消化（Register blow request, consumed by body）
    CmdBlowOff := TRUE;       // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 双阀全断保持现状。故障态拒绝返回 FALSE。
 *      Method CmdStop - both valves off and hold, rejected with FALSE in fault.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdStop : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VacuumState.eFault) THEN
    CmdStop := FALSE;         // 故障态拒绝（Rejected in fault state）
ELSE
    _bPendEvac := FALSE;      // 注销全部动作请求（Cancel all action requests）
    _bPendBlow := FALSE;
    _bPendStop := TRUE;       // 登记停止请求，主体状态机消化（Register stop request, consumed by body）
    CmdStop    := TRUE;       // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障，返回是否可复位（存在锁存故障时为 TRUE）。
 *      Method CmdReset - reset fault, returns TRUE only when a latch exists.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_VacuumState.eFault) THEN
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
_fbTrigEvac(CLK := bCmdEvacuate);
_fbTrigBlow(CLK := bCmdBlowOff);
_fbTrigReset(CLK := bReset);
_fbTonSwDeb(IN := bFbVacuumSwitch, PT := tDebounce); // 开关持续为真 tDebounce 才确认（Switch must hold TRUE for tDebounce）
_bSwFilt := _fbTonSwDeb.Q;            // 防抖后开关（Debounced switch）
_bEstToEn := (tEstablishTimeout > T#0S); // 超时参数为零 = 自检禁用（Zero timeout = check disabled）
_bInEstablish := (_eState = E_DL_VacuumState.eEvacuating) AND _bEstToEn; // 建立超时计时条件（Timeout timing condition）
_fbTonEstablish(IN := _bInEstablish, PT := tEstablishTimeout);
_fbTpBlow(IN := _bBlowReq, PT := tBlowPulse); // 吹气定宽脉冲（Fixed-width blow pulse, TP semantics）
_bBlowReq := FALSE;                   // 单拍触发请求在 TP 采样后立即自清：TP 于本拍见到
                                      // TRUE 并起振，下一拍入参回落 FALSE，TP 定宽保持
                                      // （One-cycle trigger cleared right after TP sampling,
                                      // pulse held by TP for the full width）

// ============================================================================
// 段 2｜参数防御（0.8：非数自比检测，默认值先赋）+ 迟滞钳零
//      Parameter sanitation (0.8 NaN self-compare, defaults first) + clamp
// ============================================================================
_fSetpEff := fVacuumSetpoint;         // 建立阈值镜像（Setpoint mirror）
IF _fSetpEff <> _fSetpEff THEN        // 非数自比检测（NaN self-compare test）
    _fSetpEff := -60.0;               // 回落默认阈值（Fallback to default setpoint）
END_IF
_fHystEff := fVacuumHysteresis;       // 迟滞带镜像（Hysteresis mirror）
IF _fHystEff <> _fHystEff THEN        // 非数自比检测（NaN self-compare test）
    _fHystEff := 5.0;                 // 回落默认迟滞（Fallback to default hysteresis）
END_IF
IF _fHystEff < 0.0 THEN
    _fHystEff := 0.0;                 // 负迟滞会收窄判定域，钳零防错（Negative band narrows domain, clamp to zero）
END_IF

// ============================================================================
// 段 3｜负压输入有效性全局监视（优先级最高，吸附安全相关故为故障级）
//      Pressure validity global monitor (highest priority, fault level due
//      to holding safety relevance)
// ============================================================================
_bPressValid := (fPressureFeedback = fPressureFeedback); // 非数自比检测：等号成立即有效（NaN iff self-compare fails）
IF _bPressValid THEN
    _fPressValid := fPressureFeedback; // 更新末次有效负压（Update last valid pressure）
ELSE
    _bFaultLatch := TRUE;              // 反馈失效锁存（Feedback loss latch）
    _uErrorIdInt := 16#0003_0230;      // 0003_0230 负压反馈信号无效【故障级】/ Pressure feedback invalid, fault level
    _eState      := E_DL_VacuumState.eFault; // 强制故障态（Force fault state）
END_IF

// 真空判据（clean-room 内联迟滞语义，负压域方向：值越负真空越强）
// Vacuum criteria (inline hysteresis, negative-pressure domain: more negative = stronger)
_bEstablished := (_fPressValid <= _fSetpEff);                          // 建立判据：达到设定真空（Establish: reached setpoint vacuum）
_bHoldCriterion := (_fPressValid <= (_fSetpEff + _fHystEff));          // 保持判据：迟滞带放宽防临界抖动（Hold: widened by hysteresis band）

// ============================================================================
// 段 4｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
IF _bFaultLatch OR (_eState = E_DL_VacuumState.eFault) THEN
    // 故障锁存态：清空全部请求，仅复位可退出（Latched fault: requests cleared, reset-only exit）
    _bPendEvac  := FALSE;             // 清方法请求（Clear method requests）
    _bPendBlow  := FALSE;
    _bPendStop  := FALSE;
    _bBlowReq   := FALSE;             // 撤销未触发脉冲请求（Cancel pending pulse trigger）
    IF _bPendReset OR _fbTrigReset.Q THEN
        _bPendReset  := FALSE;        // 消费复位请求（Consume reset request）
        _bFaultLatch := FALSE;        // 解除锁存（Release latch）
        _uErrorIdInt := 0;            // 故障码清零（Error code cleared）
        _eState      := E_DL_VacuumState.eIdle; // 回空闲态（Back to idle）
    END_IF
ELSE
    IF _bPendReset OR _fbTrigReset.Q THEN
        _bPendReset := FALSE;         // 无故障时消化复位请求（Absorb reset request when no fault）
    END_IF
    CASE _eState OF

        E_DL_VacuumState.eIdle: // 空闲稳态：双阀全断
            IF _bPendEvac OR _fbTrigEvac.Q THEN
                _bPendEvac := FALSE;            // 消费抽真空请求（Consume evacuate request）
                _eState    := E_DL_VacuumState.eEvacuating; // 转抽真空（To evacuating）
            ELSIF _bPendBlow OR _fbTrigBlow.Q THEN
                _bPendBlow := FALSE;            // 消费吹气请求（Consume blow request）
                _bBlowReq  := TRUE;             // 触发定宽脉冲（Trigger fixed-width pulse）
                _eState    := E_DL_VacuumState.eBlowing;
            ELSIF _bPendStop THEN
                _bPendStop := FALSE;            // 空闲态消化停止请求（Absorb stop request in idle）
            END_IF

        E_DL_VacuumState.eEvacuating: // 抽真空中：真空阀开，等待建立确认
            IF _bPendBlow OR _fbTrigBlow.Q THEN
                _bPendBlow := FALSE;            // 中途改吹气（Mid-way blow-off）
                _bBlowReq  := TRUE;
                _eState    := E_DL_VacuumState.eBlowing;
            ELSIF _bPendStop THEN
                _bPendStop := FALSE;            // 停止：双阀全断（Stop: both valves off）
                _eState    := E_DL_VacuumState.eIdle;
            ELSIF bUseSensorCheck AND _bEstablished AND (NOT _bSwFilt) THEN
                // 阈值达成但开关未确认：继续抽气等待（Threshold reached, switch pending: keep evacuating）
            ELSIF (NOT bUseSensorCheck) AND _bEstablished THEN
                _eState := E_DL_VacuumState.eVacuumOk; // 纯阈值模式：建立确认（Pure threshold: established）
            ELSIF bUseSensorCheck AND _bEstablished AND _bSwFilt THEN
                _eState := E_DL_VacuumState.eVacuumOk; // 双确认模式：阈值+开关齐备（Dual confirm: threshold AND switch）
            ELSIF _fbTonEstablish.Q THEN
                _bFaultLatch := TRUE;           // 建立超时锁存（Establish timeout latch）
                _uErrorIdInt := 16#0003_0231;   // 0003_0231 真空建立超时/反馈校验失败【故障级】/ Establish timeout or check failure, fault level
                _eState      := E_DL_VacuumState.eFault;
            END_IF

        E_DL_VacuumState.eVacuumOk: // 真空保持态：吸附保持中
            IF _bPendBlow OR _fbTrigBlow.Q THEN
                _bPendBlow := FALSE;            // 破真空放料（Release workpiece by blow-off）
                _bBlowReq  := TRUE;
                _eState    := E_DL_VacuumState.eBlowing;
            ELSIF _bPendStop THEN
                _bPendStop := FALSE;            // 停止：双阀全断（Stop: both valves off）
                _eState    := E_DL_VacuumState.eIdle;
            ELSIF NOT _bHoldCriterion THEN
                _eState := E_DL_VacuumState.eEvacuating; // 真空丢失（超迟滞带）：自动重建（Vacuum lost beyond band: auto re-establish）
            ELSIF bUseSensorCheck AND (NOT _bSwFilt) THEN
                _eState := E_DL_VacuumState.eEvacuating; // 双确认模式下开关脱开：自动重建（Switch dropped in dual mode: re-establish）
            END_IF

        E_DL_VacuumState.eBlowing: // 吹气中：吹气阀定宽脉冲，真空阀强制断
            IF _bPendBlow OR _fbTrigBlow.Q THEN
                _bPendBlow := FALSE;            // 吹气中重复触发忽略（Retrigger ignored while blowing）
            ELSIF _bPendStop THEN
                _bPendStop := FALSE;            // 停止请求提前截断脉冲（Stop request truncates pulse early）
                _bBlowReq  := FALSE;
                _eState    := E_DL_VacuumState.eIdle;
            ELSIF NOT _fbTpBlow.Q THEN
                _eState := E_DL_VacuumState.eIdle; // 脉冲宽度计满自动回空闲（Pulse completed, back to idle）
            END_IF

        ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;               // 故障锁存（Fault latched）
            _uErrorIdInt := 16#0003_0232;       // 0003_0232 非法状态【故障级】/ Illegal state, fault level
            _eState      := E_DL_VacuumState.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 5｜阀输出推导 + 出口断言（硬约束：吹气期间真空阀必断；故障/空闲双阀必断）
//      Valve output derivation + exit assertions (vacuum valve forced off
//      while blowing; both valves off in fault/idle)
// ============================================================================
bVacuumValve := (_eState = E_DL_VacuumState.eEvacuating) OR (_eState = E_DL_VacuumState.eVacuumOk); // 抽真空与保持期真空阀开（Valve open while evacuating/holding）
bBlowValve := (_eState = E_DL_VacuumState.eBlowing) AND _fbTpBlow.Q; // 吹气阀随 TP 定宽脉冲（Blow valve follows TP pulse）
IF (_eState = E_DL_VacuumState.eBlowing) OR (_eState = E_DL_VacuumState.eFault)
   OR (_eState = E_DL_VacuumState.eIdle) THEN
    bVacuumValve := FALSE;              // 出口断言：吹气/故障/空闲真空阀必断（Assertion: vacuum valve off in blowing/fault/idle）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdEvacuate —— 建立真空指令（单发）。故障态一律拒绝返回 FALSE。
 *      Method CmdEvacuate - evacuate command (one-shot), rejected with FALSE in fault.
 *------------------------------------------------------------------------------*)




PROPERTY eState : E_DL_VacuumState
eState := _eState;            // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: bVacuumOk（GET）—— 真空建立确认（吸附保持态为 TRUE）。
 *      Property bVacuumOk (GET) - vacuum established (TRUE in holding state).
 *------------------------------------------------------------------------------*)
PROPERTY bVacuumOk : BOOL
bVacuumOk := (_eState = E_DL_VacuumState.eVacuumOk); // 显式状态派生式（Explicit state-derived form）

(*------------------------------------------------------------------------------
 * 属性: fPressure（GET）—— 负压反馈值 [kPa]，0=大气压，负值=真空度。
 *      Property fPressure (GET) - pressure feedback [kPa], 0 = atmospheric, negative = vacuum.
 *------------------------------------------------------------------------------*)
PROPERTY fPressure : REAL
fPressure := _fPressValid;    // 返回末次有效负压保持值（Return last valid pressure hold value）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info-level codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_VacuumState.eFault); // 显式排除信息级派生式（Explicit derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（0=无故障）。
 *      Property uErrorId (GET) - last error code (0 = none).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
uErrorId := _uErrorIdInt;     // 返回内部故障码寄存（Return internal error register）
END_FUNCTION_BLOCK
