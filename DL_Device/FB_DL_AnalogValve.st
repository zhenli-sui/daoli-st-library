(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AnalogValve
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_ProportionalValve）
 * 功能简述 (Function)   : 模拟量比例阀指令整形与诊断功能块（不含阀位闭环，
 *                         闭环由驱动器/上层 PID 完成，本块职责单一）。
 *                         透传+补偿链：设定钳位 [0,100] → 零点死区补偿
 *                         （防阀芯微抖）→ 限幅域映射 → 阀位指令输出；
 *                         偏差报警延时确认（瞬时型每拍重算，恢复自动清）；
 *                         非有限值反馈锁存保持末次有效值；限幅域对调
 *                         自修复；状态机 E_DL_ValveState + CASE + ELSE
 *                         兜底。
 * 接口实现 (Implements) : I_DL_ProportionalValve。接口 OUT 列同名成员
 *                         （eState/fPosCmd/fPosFeedback/bDeviationAlarm/
 *                         bFault/uErrorId）按 R22 以只读 PROPERTY GET
 *                         承载（内部镜像同源；fPosFeedback 为 IN 引脚与
 *                         接口属性双形式暴露，沿用库级既有先例），非接口
 *                         成员 fPosOutput 保留 VAR_OUTPUT；方法
 *                         SetPosition/CmdStop/CmdReset 全部在本文件尾部
 *                         落地。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1：比例阀指令整形链（钳位-死区
 *                         补偿-限幅域映射）、偏差延时报警、限幅域端点组态
 *                         等行业公知工程惯例，公开教学资料，仅借鉴通用
 *                         工程语义；状态机、整形链实现、故障码按本库红线
 *                         独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防除零/防越界/非有限值
 *                         防御/浮点容差比较 ✓｜R5 全变量中英双语同行注释 ✓
 *                         R6 ENUM+CASE+ELSE ✓｜R7 两个定时器/边缘实例主体
 *                         最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1/R23 本块为逐拍组合整形链（设定→钳位→死区→
 *                         映射，全部由实时输入重算自校正），无积分/滤波类
 *                         需要首扫初始化的连续量驻留状态，免首扫（无
 *                         bInit 标志）；时间基准按公约 0.5 采用 TON 延时
 *                         引脚（偏差确认），无采样周期类连续量语义。
 *                         0.6 限幅域对调自修复：fOutMin > fOutMax 时对调
 *                         + 置信息级码 + 继续计算不中断。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0260
 *                         阀位反馈信号无效 / 0003_0261 非法状态，R15 锁存
 *                         仅复位可清；【信息级】0003_0108 设定值钳位 /
 *                         0003_0109 输出限幅域对调自修复 / 0003_0112 偏差
 *                         报警激活（瞬时型每拍重算，0.15；不进 bFault）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 信息级码：规格原分配 0003_0105/0106，经与子库
 *                           VERSION.md 故障码表核对，R5 已占用 0102~0104
 *                           （AnalogTransmitter），且 0106/0107 已由本轮
 *                           变频器块顺延占用（0105 经终审裁定空置：重启抑
 *                           制拒绝统一沿用 DolMotor 既有语义码位 0208），
 *                           依公约 0.7 冲突顺延：设定值钳位 → 0108、限幅
 *                           域对调 → 0109；偏差报警激活为新码位，顺延分配
 *                           0112。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *   2026-11-15  v1.0.1  终审修复【工程语义级】限幅域对调穿透：原实现对调时
 *                       直读原始引脚（fOutMin/fOutMax），混合非数组态下
 *                       （如下端非数+上端负值）会把未防御的 NaN 带回生效
 *                       域并经映射链输出 NaN 阀位指令且不带故障码。修法：
 *                       对调改为经中间变量交换已防御的生效值。引脚契约
 *                       零变更。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AnalogValve IMPLEMENTS I_DL_ProportionalValve
VAR_INPUT
    fPosSetpoint     : REAL;            // 阀位设定（Position setpoint）[%]，0..100，越界钳位信息级 / Position setpoint [%], clamped with info code
    fPosFeedback     : REAL;            // 阀位反馈（Position feedback）[%]，0..100，来自阀位变送器；非有限值防御 / Position feedback [%] from transmitter, non-finite defended
    fZeroDeadband    : REAL := 0.5;     // 零点死区补偿（Zero deadband compensation）[%]，输出小于此值钳为 0 防阀芯微抖 / Zero deadband [%], output below clamped to zero
    fDeviationLimit  : REAL := 5.0;     // 偏差报警门限（Deviation limit）[%]，默认 5.0 / Deviation alarm limit [%], default 5.0
    tDeviationDelay  : TIME := T#10S;   // 偏差报警确认延时（Deviation delay），防动态调节过程误报 / Deviation confirmation delay against dynamic transients
    fOutMin          : REAL := 0.0;     // 输出限幅域下端点（Output span low endpoint）[%]，对调自修复 / Output span low endpoint, swap self-repair
    fOutMax          : REAL := 100.0;   // 输出限幅域上端点（Output span high endpoint）[%]，对调自修复 / Output span high endpoint, swap self-repair
    bEnable          : BOOL;            // 调节使能（Modulating enable），FALSE 时输出冻结保持 / Modulating enable, FALSE freezes output hold
    bReset           : BOOL;            // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
END_VAR

VAR_OUTPUT
    fPosOutput : REAL;                  // 阀位指令输出（Position output）[%]，死区补偿+限幅域映射后，量纲=限幅域（R20）/ Shaped position output [%], span of limit domain
END_VAR

VAR
    _eState        : E_DL_ValveState := E_DL_ValveState.eIdle; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bFaultLatch   : BOOL;              // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt   : UDINT;             // 故障级码内部寄存（Internal fault-code register） / Internal fault-level code register
    _uInfoCode     : UDINT;             // 本拍信息级码（Info code this cycle），瞬时型每拍重算（0.15）/ Transient info code recomputed each cycle
    _bHoldLatch    : BOOL;              // 输出冻结锁存（Output freeze latch），CmdStop 置位 / Output freeze latch set by CmdStop
    _bPendReset    : BOOL;              // 方法复位请求（Method reset request），由 CmdReset 置位 / Method reset request set by CmdReset
    _bClampOccur   : BOOL;              // 本拍设定值钳位发生（Setpoint clamp occurred this cycle）/ Setpoint clamp occurred flag
    _fPosMethVal   : REAL;              // 方法阀位设定值（Method position value）[%] / Position value set via method
    _bPosMethAct   : BOOL;              // 方法阀位设定激活（Method position active），激活后覆盖引脚 / Method position active, overrides pin
    _fPosFbHold    : REAL := 0.0;       // 末次有效阀位反馈（Last valid position feedback）[%]，保持载体 / Last valid feedback hold carrier
    _fPosCmdEff    : REAL := 0.0;       // 钳位+死区后生效阀位指令（Effective command after clamp and deadband）[%] / Effective command [%]
    _fPosOutHold   : REAL := 0.0;       // 输出保持载体（Output hold carrier）[%]，冻结/故障态保持 / Output hold carrier [%]
    _fOutMinEff    : REAL := 0.0;       // 对调修复后限幅域下端（Repaired span low endpoint）[%] / Repaired span low endpoint
    _fOutMaxEff    : REAL := 100.0;     // 对调修复后限幅域上端（Repaired span high endpoint）[%] / Repaired span high endpoint
    _fZeroDbEff    : REAL := 0.5;       // 防御后死区（Sanitized deadband）[%]，非数/负值钳零 / Sanitized deadband, NaN or negative clamped to zero
    _fDevLimEff    : REAL := 5.0;       // 防御后偏差门限（Sanitized deviation limit）[%] / Sanitized deviation limit
    _bSpanSwap     : BOOL;              // 本拍限幅域对调修复（Span swap repair this cycle）/ Span swap repair occurred flag
    _fSpanTmp      : REAL;              // 对调交换中间变量（Swap temp carrier）[%]，生效域已防御值 / Swap temp for sanitized span values
    _bSpanDegenerate : BOOL;            // 限幅域跨度退化（Degenerate span），近零或非有限 / Span degenerate on near-zero or NaN
    _bFbValid      : BOOL;              // 本拍反馈有效性（Feedback validity this cycle），非有限值为 FALSE / FALSE when feedback non-finite
    _bDevRaw       : BOOL;              // 偏差越限原始判据（Raw deviation-exceed test）/ Raw deviation exceed flag
    _bDeviationAct : BOOL;              // 偏差报警激活中（Deviation alarm active），延时确认后 / Deviation alarm active after confirmation delay
    _fbTrigReset   : R_TRIG;            // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTonDev      : TON;               // 偏差报警确认延时定时器（Deviation confirmation timer）/ Deviation confirmation timer
END_VAR

METHOD SetPosition : BOOL
VAR_INPUT
    fPos : REAL; // 阀位设定值（Position value）[%]，域 0..100 / Position value [%], range 0..100
END_VAR
IF _bFaultLatch OR (_eState = E_DL_ValveState.eFault) THEN
    SetPosition := FALSE;     // 故障态拒绝（Rejected in fault state）
ELSIF (fPos <> fPos) OR (fPos < 0.0) OR (fPos > 100.0) THEN
    SetPosition := FALSE;     // 非数或越域拒绝（Rejected on NaN or out of range）
ELSE
    _fPosMethVal := fPos;     // 登记方法设定值（Register method position value）
    _bPosMethAct := TRUE;     // 激活方法设定通道（Activate method source channel）
    _bHoldLatch  := FALSE;    // 设定即解除输出冻结（Set releases output freeze）
    SetPosition := TRUE;      // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 冻结输出保持当前阀位，直至下次设定或使能撤除。
 *      Method CmdStop - freeze output until next set or enable drop.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdStop : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_ValveState.eFault) THEN
    CmdStop := FALSE;         // 故障态拒绝（Rejected in fault state）
ELSE
    _bHoldLatch := TRUE;      // 登记冻结锁存，主体状态机消化（Register freeze latch, consumed by body）
    CmdStop := TRUE;          // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障，返回是否可复位（存在锁存故障时为 TRUE）。
 *      Method CmdReset - reset fault, returns TRUE only when a latch exists.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_ValveState.eFault) THEN
    _bPendReset := TRUE;      // 登记复位请求，主体状态机消化（Register reset request, consumed by body）
    CmdReset := TRUE;         // 可复位（Resettable）
ELSE
    CmdReset := FALSE;        // 无故障可复位（Nothing to reset）
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
_fbTrigReset(CLK := bReset);
_bDevRaw := (_eState = E_DL_ValveState.eModulating) AND (ABS(_fPosCmdEff - _fPosFbHold) > _fDevLimEff); // 偏差原始判据（Raw deviation test）
_fbTonDev(IN := _bDevRaw, PT := tDeviationDelay); // 延时确认防动态调节误报（Delay confirmation against dynamics）

// ============================================================================
// 段 2｜参数防御（0.8：非数自比检测，默认值先赋）+ 0.6 限幅域对调自修复
//      Parameter sanitation (0.8 NaN self-compare) + 0.6 span swap repair
// ============================================================================
_uInfoCode := 0;                      // 本拍信息级码先归零，事件段重算（Info code preset zero, recomputed in event chain）
_bClampOccur := FALSE;                // 钳位标志复位（Clamp flag reset）
_fZeroDbEff := fZeroDeadband;         // 死区镜像（Deadband mirror）
IF _fZeroDbEff <> _fZeroDbEff THEN    // 非数自比检测（NaN self-compare test）
    _fZeroDbEff := 0.0;               // 非数死区钳零禁用补偿（NaN deadband clamped to zero, compensation disabled）
END_IF
IF _fZeroDbEff < 0.0 THEN
    _fZeroDbEff := 0.0;               // 负死区钳零（Negative deadband clamped to zero）
END_IF
_fDevLimEff := fDeviationLimit;       // 偏差门限镜像（Deviation limit mirror）
IF _fDevLimEff <> _fDevLimEff THEN    // 非数自比检测（NaN self-compare test）
    _fDevLimEff := 5.0;               // 回落默认门限（Fallback to default limit）
END_IF
IF _fDevLimEff < 0.0 THEN
    _fDevLimEff := ABS(_fDevLimEff);  // 负门限取绝对值保持报警有效（Negative limit made absolute, alarm stays valid）
END_IF

_fOutMinEff := fOutMin;               // 限幅域下端镜像（Span low mirror）
_fOutMaxEff := fOutMax;               // 限幅域上端镜像（Span high mirror）
IF _fOutMinEff <> _fOutMinEff THEN    // 非数自比检测（NaN self-compare test）
    _fOutMinEff := 0.0;               // 回落下端默认（Fallback to default low）
END_IF
IF _fOutMaxEff <> _fOutMaxEff THEN    // 非数自比检测（NaN self-compare test）
    _fOutMaxEff := 100.0;             // 回落上端默认（Fallback to default high）
END_IF
_bSpanSwap := FALSE;                  // 对调标志复位（Swap flag reset）
IF _fOutMinEff > _fOutMaxEff THEN     // 参数对自修复判据（Pair swap test）
    _fSpanTmp     := _fOutMinEff;     // 对调经已防御的生效值交换（中间变量，防原始引脚
    _fOutMinEff   := _fOutMaxEff;     // 非有限值穿透——若直读原始引脚，混合非数组态
    _fOutMaxEff   := _fSpanTmp;       // 会把 NaN 带回生效域，终审修复）
    _bSpanSwap := TRUE;               // 登记对调修复，继续计算不中断（Register swap repair, computation continues）
END_IF

// ============================================================================
// 段 3｜阀位反馈有效性全局监视（优先级最高，故障级锁存保持末次有效值）
//      Position feedback validity global monitor (highest priority, latched)
// ============================================================================
_bFbValid := (fPosFeedback = fPosFeedback); // 非数自比检测：等号成立即有效（NaN iff self-compare fails）
IF _bFbValid THEN
    _fPosFbHold := fPosFeedback;      // 更新末次有效反馈（Update last valid feedback）
ELSE
    _bFaultLatch := TRUE;             // 反馈失效锁存（Feedback loss latch）
    _uErrorIdInt := 16#0003_0260;     // 0003_0260 阀位反馈信号无效【故障级】/ Position feedback invalid, fault level
    _eState      := E_DL_ValveState.eFault; // 强制故障态（Force fault state）
END_IF

// ============================================================================
// 段 4｜指令整形链：来源选择 → 钳位 [0,100] → 零点死区补偿
//      Command shaping chain: source select → clamp [0,100] → zero deadband
// ============================================================================
IF _bPosMethAct THEN
    _fPosCmdEff := _fPosMethVal;      // 方法设定覆盖引脚（Method value overrides pin）
ELSE
    _fPosCmdEff := fPosSetpoint;      // 引脚设定（Pin setpoint）
END_IF
IF _fPosCmdEff <> _fPosCmdEff THEN    // 非数自比检测（NaN self-compare test）
    _fPosCmdEff := 0.0;               // 非数设定回零（NaN setpoint falls back to zero）
END_IF
IF _fPosCmdEff < 0.0 THEN
    _fPosCmdEff := 0.0;               // 下限钳位（Clamped to low bound）
    _bClampOccur := TRUE;             // 登记钳位事件（Register clamp event）
END_IF
IF _fPosCmdEff > 100.0 THEN
    _fPosCmdEff := 100.0;             // 上限钳位（Clamped to high bound）
    _bClampOccur := TRUE;             // 登记钳位事件（Register clamp event）
END_IF
IF ABS(_fPosCmdEff) < _fZeroDbEff THEN
    _fPosCmdEff := 0.0;               // 零点死区补偿：近零指令钳为 0 防阀芯微抖（Zero deadband: near-zero command clamped to zero）
END_IF

// ============================================================================
// 段 5｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
IF _bFaultLatch OR (_eState = E_DL_ValveState.eFault) THEN
    CASE _eState OF
        E_DL_ValveState.eFault: // 故障锁存态：输出冻结保持，仅复位可退出
            IF _fbTrigReset.Q OR _bPendReset THEN
                _bPendReset  := FALSE;            // 消费复位请求（Consume reset request）
                _bFaultLatch := FALSE;            // 解除锁存（Release latch）
                _uErrorIdInt := 0;                // 故障码清零（Error code cleared）
                _bHoldLatch  := FALSE;            // 复位同时解除冻结（Freeze released on reset）
                _eState      := E_DL_ValveState.eIdle; // 回空闲态（Back to idle）
            END_IF
        ELSE // 锁存标志与状态不一致兜底：强制同步进故障态（Latch/state mismatch fallback）
            _eState := E_DL_ValveState.eFault;
    END_CASE
ELSE
    CASE _eState OF

        E_DL_ValveState.eIdle: // 空闲稳态：使能撤除或输出冻结
            IF bEnable AND (NOT _bHoldLatch) THEN
                _eState := E_DL_ValveState.eModulating; // 受理调节（Accept modulating）
            END_IF

        E_DL_ValveState.eModulating: // 调节中：指令整形后正常输出
            IF (NOT bEnable) OR _bHoldLatch THEN
                _eState := E_DL_ValveState.eIdle; // 使能撤除或冻结请求：输出冻结（Enable dropped or freeze requested: output frozen）
            END_IF

        ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;                 // 故障锁存（Fault latched）
            _uErrorIdInt := 16#0003_0261;         // 0003_0261 非法状态【故障级】/ Illegal state, fault level
            _eState      := E_DL_ValveState.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 6｜限幅域映射与输出推导（R20：输出量纲=限幅域；冻结/故障态保持）
//      Span mapping and output derivation (output in span domain, hold in
//      frozen/fault states)
// ============================================================================
IF (_eState = E_DL_ValveState.eModulating) THEN
    _bSpanDegenerate := (ABS(_fOutMaxEff - _fOutMinEff) < 1E-9); // 跨度近零判退化（Degenerate on near-zero span）
    IF _bSpanDegenerate THEN
        _fPosOutHold := _fOutMinEff;  // 退化回退域下端（Degenerate fallback to span low）
    ELSE
        _fPosOutHold := _fOutMinEff + (_fPosCmdEff * ((_fOutMaxEff - _fOutMinEff) / 100.0)); // [%]→域线性映射（Linear mapping over span, divisor proven non-zero）
    END_IF
END_IF // 空闲/故障态不更新保持载体，输出自动冻结（Idle/fault skip update, output frozen）
fPosOutput := _fPosOutHold;           // 输出保持载体透出（Expose hold carrier）

// ============================================================================
// 段 7｜偏差报警派生与事件码优先级链（信息级瞬时每拍重算，0.15）
//      Deviation alarm derivation and event-code priority chain
// ============================================================================
_bDeviationAct := _fbTonDev.Q;        // 延时确认后激活（Active after confirmation delay）
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_ValveState.eFault) THEN
    // 故障级码已锁存，信息级不覆盖（Fault-level latched, info not applied）
ELSIF _bDeviationAct THEN
    _uInfoCode := 16#0003_0112;       // 0003_0112 偏差报警激活【信息级】/ Deviation alarm active, info level
ELSIF _bSpanSwap THEN
    _uInfoCode := 16#0003_0109;       // 0003_0109 输出限幅域对调自修复【信息级】/ Span swap repair, info level
ELSIF _bClampOccur THEN
    _uInfoCode := 16#0003_0108;       // 0003_0108 设定值钳位【信息级】/ Setpoint clamped, info level
ELSE
    _uInfoCode := 0;                  // 无事件码清零（No event, code cleared）
END_IF

(*------------------------------------------------------------------------------
 * 方法: SetPosition —— 阀位指令设定 [%]，越界/非有限值拒绝返回 FALSE。
 *      Method SetPosition - position set, out-of-range or NaN returns FALSE.
 *------------------------------------------------------------------------------*)



PROPERTY eState : E_DL_ValveState
eState := _eState;            // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: fPosCmd（GET）—— 当前阀位指令 [%]（钳位+死区后生效值）。
 *      Property fPosCmd (GET) - current position command [%] after shaping.
 *------------------------------------------------------------------------------*)
PROPERTY fPosCmd : REAL
fPosCmd := _fPosCmdEff;       // 返回生效指令镜像（Return effective command mirror）

(*------------------------------------------------------------------------------
 * 属性: fPosFeedback（GET）—— 阀位反馈 [%]，非有限值时保持末次有效值。
 *      Property fPosFeedback (GET) - position feedback [%], holds last valid on non-finite.
 *------------------------------------------------------------------------------*)
PROPERTY fPosFeedback : REAL
fPosFeedback := _fPosFbHold;  // 返回末次有效反馈保持值（Return last valid feedback hold value）

(*------------------------------------------------------------------------------
 * 属性: bDeviationAlarm（GET）—— 偏差报警激活中（瞬时型每拍重算）。
 *      Property bDeviationAlarm (GET) - transient deviation alarm indicator.
 *------------------------------------------------------------------------------*)
PROPERTY bDeviationAlarm : BOOL
bDeviationAlarm := _bDeviationAct; // 返回延时确认后的报警态（Return delayed-confirmed alarm state）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info-level codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_ValveState.eFault); // 显式排除信息级派生式（Explicit derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次事件码（故障级锁存优先；无故障时透出本拍
 *         信息级码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last event code (fault-level priority,
 *      transient info code shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_ValveState.eFault) THEN
    uErrorId := _uErrorIdInt; // 故障级码优先透出（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;   // 无故障时透出本拍信息级码（Transient info code when no fault）
END_IF
END_FUNCTION_BLOCK
