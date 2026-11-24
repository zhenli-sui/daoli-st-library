(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StarDeltaMotor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，无接口实现）
 * 功能简述 (Function)   : 星三角降压启动电机控制（三接触器）。星形降压启动
 *                         （起动力矩约三分之一）→ 星角切换死区互锁（星线圈
 *                         分断后方允许角线圈吸合）→ 三角形全压运行；三路
 *                         接触器指令-反馈校验窗（拒动保护）、运行失反馈
 *                         脱扣、热继过载锁存、重启抑制冷却（沿用
 *                         FB_DL_DolMotor 参数范式）；星角输出互斥出口
 *                         断言 + 反馈互锁冲突监视；状态机复用既有
 *                         E_DL_MotorState（禁止重定义），ENUM + CASE + ELSE
 *                         兜底。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1 + S-5：星三角降压启动时序、
 *                         星角切换死区时间互锁、三接触器反馈校验等行业
 *                         公知工程惯例，公开教学资料，仅借鉴通用工程语义；
 *                         状态机、死区互锁实现、故障码按本库红线独立设计，
 *                         clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防越界/互斥断言 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE ✓
 *                         R7 七个定时器/边缘实例主体最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1/R23 本块为纯事件型状态机（BOOL 指令/反馈 +
 *                         TIME 参数，无积分/滤波类连续量同步语义），免首扫，
 *                         无内部初始化标志。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0240
 *                         主接触器拒动 / 0003_0241 星接触器拒动 / 0003_0242
 *                         星接触器分断失败（角拒动码位承接，见偏离③）/
 *                         0003_0243 星角互斥冲突 / 0003_0244 运行失反馈
 *                         脱扣 / 0003_0245 过载锁存 / 0003_0246 星角转换
 *                         失败（角接触器窗内未吸合），全部 R15 锁存仅复位
 *                         可清；【信息级】0003_0208 重启抑制期启动拒绝
 *                         （沿用 FB_DL_DolMotor 既有同义码位，终审裁定统
 *                         一双电机族口径；仅写 uErrorId，不进 bFault，0.2
 *                         公约）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 3 条：
 *                         ① 信息级码：规格原分配 0003_0102，经与子库
 *                           VERSION.md 故障码表核对，R5 已占用 0102~0104
 *                           （AnalogTransmitter）；且重启抑制拒绝语义在
 *                           FB_DL_DolMotor 已有信息级码位 0003_0208——
 *                           终审裁定同库同语义不设双码，本块改用 0208
 *                           （0105 空置不分配），与规格原意"沿用 DolMotor
 *                           口径"完全一致。
 *                         ② 规格中 0003_0242（角接触器拒动）与 0003_0246
 *                           （星角转换失败）对"死区满后角接触器窗内未吸合"
 *                           同事件重叠；本实现将 0246 用于规格明示的角接触
 *                           器窗内未吸合，0242 承接转换窗口内星接触器反馈
 *                           未按时分断（星粘连/拒分）的互锁异常，两码位
 *                           各自可测。
 *                         ③ 重启抑制冷却计时采用 TON（本库 Standard.library
 *                           既有范式，DolMotor 同口径），无 CPU 钟依赖。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *   2026-11-15  v1.0.1  终审修复【逻辑级】重启抑制信息级码双码归一：原分配
 *                       0003_0105 与 FB_DL_DolMotor 既有同义码 0003_0208
 *                       重复（同库同语义双码会致 HMI 报警分组重复映射），
 *                       改用 0208 统一口径。引脚契约零变更。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StarDeltaMotor
VAR_INPUT
    bCmdStart        : BOOL;            // 启动指令（Start command），上升沿生效 / Start command, rising edge effective
    bCmdStop         : BOOL;            // 停止指令（Stop command），电平生效 / Stop command, level effective
    bFbMain          : BOOL;            // 主接触器反馈（Main contactor feedback），TRUE=吸合 / Main contactor feedback, TRUE = picked up
    bFbStar          : BOOL;            // 星形接触器反馈（Star contactor feedback），TRUE=吸合 / Star contactor feedback, TRUE = picked up
    bFbDelta         : BOOL;            // 三角形接触器反馈（Delta contactor feedback），TRUE=吸合 / Delta contactor feedback, TRUE = picked up
    bThermalOverload : BOOL;            // 热继电器过载信号（Thermal overload trip），TRUE=过载 / Thermal overload trip, TRUE = overloaded
    bPermitStart     : BOOL;            // 启动允许联锁（Start permit），TRUE=允许 / Start permit interlock, TRUE = start allowed
    tStarTime        : TIME := T#5S;    // 星形运行时间（Star run time），按负载实测加速时间整定 / Star run time, tune per measured load acceleration
    tDeadTime        : TIME := T#100MS; // 星角转换死区时间（Transition dead time），域 50~200MS，星分断后角方可吸合 / Transition dead time 50..200 ms, star must drop before delta picks up
    tFbWindow        : TIME := T#500MS; // 指令-反馈校验窗口（Feedback check window），T#0S=免校验 / Feedback check window, T#0S disables the check
    tRestartInhibit  : TIME := T#60S;   // 重启抑制冷却时间（Restart inhibit），停机后冷却期内拒绝启动 / Restart inhibit cooling time after stop
    bReset           : BOOL;            // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
END_VAR

VAR_OUTPUT
    bMainContactor   : BOOL;            // 主接触器线圈输出（Main contactor coil），星形与运行期全程吸合 / Main contactor coil, closed through star and run phases
    bStarContactor   : BOOL;            // 星形接触器线圈输出（Star contactor coil），仅星形降压段吸合 / Star contactor coil, closed only in star phase
    bDeltaContactor  : BOOL;            // 三角形接触器线圈输出（Delta contactor coil），死区满后吸合 / Delta contactor coil, closed after dead time
    eState           : E_DL_MotorState; // 当前状态机状态（Current state），复用既有枚举 / Current state, reuses existing enum
    bRunning         : BOOL;            // 运行反馈（Running feedback），角接触器吸合确认 / Running feedback, confirmed by delta contactor
    bFault           : BOOL;            // 故障锁存中（Fault latched），TRUE=需复位（含过载脱扣）/ Fault latched, TRUE requires reset (incl. overload trip)
    uErrorId         : UDINT;           // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, 0 = none, family 16#0003_xxxx
    bRestartInhibit  : BOOL;            // 重启抑制激活中（Restart inhibit active），TRUE=冷却期拒绝启动 / Restart inhibit active, TRUE = starts refused
    bStarPhase       : BOOL;            // 星形阶段指示（Star phase active），调试/HMI 用 / Star phase indicator for debug and HMI
    uStartCount      : UDINT;           // 累计启动次数（Start count），每次受理启动 +1 / Total start count, incremented per accepted start
END_VAR

VAR
    _eState           : E_DL_MotorState := E_DL_MotorState.eIdle; // 内部状态机步序（Internal state step）/ Internal state step
    _bFaultLatch      : BOOL;           // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt      : UDINT;          // 内部故障码寄存（Internal error register），故障级与信息级共用 / Internal error register, fault and info codes share it
    _bDeadZone        : BOOL;           // 星角转换死区子相位（Star-delta dead-zone sub-phase），星形态内二段 / Dead-zone sub-phase inside starting state
    _bDeltaCmd        : BOOL;           // 角接触器指令已发出（Delta command issued），转换校验窗运行中 / Delta command issued, check window running
    _bCooling         : BOOL;           // 冷却计时进行中（Cooling timing active）/ Cooling timer run request flag
    _bRestartInhAct   : BOOL;           // 重启抑制激活内部寄存（Internal restart inhibit register）/ Internal restart inhibit register
    _bFbWinEn         : BOOL;           // 反馈校验窗使能（Feedback window enable），窗口参数大于零有效 / Feedback window enable, active when window above zero
    _bInFbWin         : BOOL;           // 主/星反馈窗计时条件（Main/star window timing condition）/ Timing condition of main and star window
    _bInStarTime      : BOOL;           // 星形运行计时条件（Star run timing condition）/ Timing condition of star run timer
    _bInDeadTime      : BOOL;           // 死区计时条件（Dead time timing condition）/ Timing condition of dead time timer
    _bInDeltaWin      : BOOL;           // 角反馈窗计时条件（Delta window timing condition）/ Timing condition of delta window
    _bInRunningSt     : BOOL;           // 运行态判定中间量（Running-state test intermediate） / Running-state test intermediate
    _fbTrigStart      : R_TRIG;         // 引脚启动指令上升沿（Pin start command edge）/ Pin start command rising edge
    _fbTrigReset      : R_TRIG;         // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTonFbWin       : TON;            // 主/星接触器反馈校验窗定时器（Main and star feedback window timer）/ Main and star feedback window timer
    _fbTonStarTime    : TON;            // 星形运行时间定时器（Star run time timer）/ Star run time timer
    _fbTonDeadTime    : TON;            // 星角转换死区定时器（Transition dead time timer）/ Transition dead time timer
    _fbTonDeltaWin    : TON;            // 角接触器反馈校验窗定时器（Delta feedback window timer）/ Delta feedback window timer
    _fbTonRestartInh  : TON;            // 重启抑制冷却定时器（Restart inhibit cooling timer）/ Restart inhibit cooling timer
END_VAR

// ============================================================================
// 段 1｜定时器与边缘检测实例无条件周期刷新（R7：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all timer and edge instances (R7)
// ============================================================================
_fbTrigStart(CLK := bCmdStart);
_fbTrigReset(CLK := bReset);
_bFbWinEn := (tFbWindow > T#0S);      // 窗口为零 = 免校验（Zero window = check disabled）
_bInFbWin := (_eState = E_DL_MotorState.eStarting) AND (NOT _bDeadZone) AND _bFbWinEn; // 启动段主/星校验窗（Starting phase main and star window）
_bInStarTime := (_eState = E_DL_MotorState.eStarting) AND (NOT _bDeadZone); // 星形段计时（Star phase timing）
_bInDeadTime := (_eState = E_DL_MotorState.eStarting) AND _bDeadZone AND (NOT _bDeltaCmd); // 死区段计时（Dead-zone timing）
_bInDeltaWin := (_eState = E_DL_MotorState.eStarting) AND _bDeadZone AND _bDeltaCmd AND (NOT bFbDelta) AND _bFbWinEn; // 角校验窗（Delta check window）
_fbTonFbWin(IN := _bInFbWin, PT := tFbWindow);
_fbTonStarTime(IN := _bInStarTime, PT := tStarTime);
_fbTonDeadTime(IN := _bInDeadTime, PT := tDeadTime);
_fbTonDeltaWin(IN := _bInDeltaWin, PT := tFbWindow);
_fbTonRestartInh(IN := _bCooling, PT := tRestartInhibit);

// 冷却到期：解除抑制（Cooling expired: release inhibit）
IF _fbTonRestartInh.Q THEN
    _bCooling       := FALSE;         // 结束冷却计时（Stop cooling timing）
    _bRestartInhAct := FALSE;         // 解除抑制（Release inhibit）
ELSE
    _bRestartInhAct := _bCooling;     // 冷却期间抑制有效（Inhibit active during cooling）
END_IF
_bInRunningSt := (_eState = E_DL_MotorState.eRunning); // 运行态判定（Running-state test）

// ============================================================================
// 段 2｜星角反馈互锁冲突全局监视（优先级最高）：双反馈同真物理不可能
//      Star-delta feedback conflict monitor (highest priority): both
//      feedbacks ON is physically impossible
// ============================================================================
IF bFbStar AND bFbDelta THEN
    _bFaultLatch := TRUE;             // 反馈冲突锁存（Feedback conflict latch）
    _uErrorIdInt := 16#0003_0243;     // 0003_0243 星角互斥冲突【故障级】/ Star-delta exclusivity conflict, fault level
    _eState      := E_DL_MotorState.eFault; // 强制故障态（Force fault state）
END_IF

// ============================================================================
// 段 3｜过载全局监视：启动/运行态过载立即锁存脱扣
//      Global overload monitor: trip immediately in starting/running states
// ============================================================================
IF bThermalOverload AND ((_eState = E_DL_MotorState.eStarting) OR _bInRunningSt) THEN
    _bFaultLatch := TRUE;             // 过载锁存（Overload latched）
    _uErrorIdInt := 16#0003_0245;     // 0003_0245 热继电器过载脱扣【故障级】/ Thermal overload trip, fault level
    _eState      := E_DL_MotorState.eTripOverload; // 强制脱扣态（Force trip state）
END_IF

// ============================================================================
// 段 4｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
CASE _eState OF

    E_DL_MotorState.eIdle: // 空闲停机态：三线圈全断，评估启动请求
        IF _fbTrigStart.Q THEN
            IF bThermalOverload THEN
                // 过载未复位：静默拒绝（Overload present: silent refusal）
            ELSIF NOT bPermitStart THEN
                // 联锁未满足：静默拒绝（Permit absent: silent refusal）
            ELSIF _bRestartInhAct THEN
                _uErrorIdInt := 16#0003_0208; // 0003_0208 重启抑制期内启动被拒【信息级】（沿用 DolMotor 既有同义码位，终审裁定）/ Start refused during restart inhibit, info level (DolMotor shared code, audit ruling)
            ELSE
                _bDeadZone   := FALSE;   // 复位转换子相位（Reset transition sub-phase）
                _bDeltaCmd   := FALSE;   // 复位角指令标志（Reset delta command flag）
                uStartCount  := uStartCount + 1; // 累计启动 +1（Total starts +1）
                _eState      := E_DL_MotorState.eStarting;
            END_IF
        END_IF

    E_DL_MotorState.eStarting: // 启动校验态：星形降压段 → 死区段 → 角校验段
        IF bCmdStop THEN
            _eState := E_DL_MotorState.eStopping; // 停止指令：三线圈全断（Stop: all coils off）
        ELSIF (NOT _bDeadZone) AND (NOT bFbMain) AND _bFbWinEn AND _fbTonFbWin.Q THEN
            _bFaultLatch := TRUE;                 // 主接触器拒动锁存（Main refusal latch）
            _uErrorIdInt := 16#0003_0240;         // 0003_0240 主接触器拒动（窗内未吸合）【故障级】/ Main contactor refused, fault level
            _eState      := E_DL_MotorState.eFault;
        ELSIF (NOT _bDeadZone) AND (NOT bFbStar) AND _bFbWinEn AND _fbTonFbWin.Q THEN
            _bFaultLatch := TRUE;                 // 星接触器拒动锁存（Star refusal latch）
            _uErrorIdInt := 16#0003_0241;         // 0003_0241 星接触器拒动（窗内未吸合）【故障级】/ Star contactor refused, fault level
            _eState      := E_DL_MotorState.eFault;
        ELSIF (NOT _bDeadZone) AND _fbTonStarTime.Q THEN
            _bDeadZone := TRUE;                   // 星形时间计满，星线圈分断，进入死区（Star time elapsed, star coil drops, dead zone entered）
        ELSIF _bDeadZone AND (NOT _bDeltaCmd) AND _fbTonDeadTime.Q THEN
            IF bFbStar THEN
                _bFaultLatch := TRUE;             // 星接触器分断失败锁存（Star drop-out failure latch）
                _uErrorIdInt := 16#0003_0242;     // 0003_0242 星接触器分断失败（死区满仍吸合）【故障级】/ Star contactor failed to drop, fault level
                _eState      := E_DL_MotorState.eFault;
            ELSE
                _bDeltaCmd := TRUE;               // 死区满且星已分断，发出角指令（Dead time done, star dropped, delta commanded）
            END_IF
        ELSIF _bDeadZone AND _bDeltaCmd AND bFbDelta AND (NOT bFbStar) THEN
            _eState := E_DL_MotorState.eRunning;  // 角吸合确认，转全压运行（Delta picked up, to full-voltage running）
        ELSIF _bDeadZone AND _bDeltaCmd AND (NOT bFbDelta) AND _bFbWinEn AND _fbTonDeltaWin.Q THEN
            _bFaultLatch := TRUE;                 // 星角转换失败锁存（Transition failure latch）
            _uErrorIdInt := 16#0003_0246;         // 0003_0246 星角转换失败（角接触器窗内未吸合）【故障级】/ Star-delta transition failed, fault level
            _eState      := E_DL_MotorState.eFault;
        END_IF

    E_DL_MotorState.eRunning: // 全压运行态：主+角吸合确认
        IF bCmdStop THEN
            _eState := E_DL_MotorState.eStopping; // 停止指令（Stop command）
        ELSIF (NOT bFbDelta) OR (NOT bFbMain) THEN
            _bFaultLatch := TRUE;                 // 失反馈脱扣锁存（Feedback loss latch）
            _uErrorIdInt := 16#0003_0244;         // 0003_0244 运行中反馈意外断开【故障级】/ Contactor feedback dropped while running, fault level
            _eState      := E_DL_MotorState.eFault;
        END_IF

    E_DL_MotorState.eStopping: // 停机过渡态：三线圈已断，等反馈全部分断
        IF (NOT bFbMain) AND (NOT bFbStar) AND (NOT bFbDelta) THEN
            _bDeadZone := FALSE;                  // 复位转换子相位（Reset transition sub-phase）
            _bDeltaCmd := FALSE;                  // 复位角指令标志（Reset delta command flag）
            _bCooling  := TRUE;                   // 启动重启抑制冷却（Start restart-inhibit cooling）
            _eState    := E_DL_MotorState.eIdle;  // 回空闲（Back to idle）
        END_IF
        // 反馈触点粘连时保持本态等待分断，直至上层干预（Welded contacts hold this state until intervention）

    E_DL_MotorState.eTripOverload: // 过载脱扣锁存态：仅复位且过载消失后可清
        IF _fbTrigReset.Q AND (NOT bThermalOverload) THEN
            _bFaultLatch := FALSE;                // 解除锁存（Release latch）
            _uErrorIdInt := 0;                    // 故障码清零（Error code cleared）
            _bDeadZone   := FALSE;                // 复位转换子相位（Reset transition sub-phase）
            _bDeltaCmd   := FALSE;                // 复位角指令标志（Reset delta command flag）
            _bCooling    := TRUE;                 // 脱扣复位后同样进入冷却（Cooling also after trip reset）
            _eState      := E_DL_MotorState.eIdle; // 回空闲（Back to idle）
        END_IF

    E_DL_MotorState.eFault: // 故障锁存态：仅复位可退出
        IF _fbTrigReset.Q THEN
            _bFaultLatch := FALSE;                // 解除锁存（Release latch）
            _uErrorIdInt := 0;                    // 故障码清零（Error code cleared）
            _bDeadZone   := FALSE;                // 复位转换子相位（Reset transition sub-phase）
            _bDeltaCmd   := FALSE;                // 复位角指令标志（Reset delta command flag）
            _bCooling    := TRUE;                 // 故障复位后进入冷却（Cooling also after fault reset）
            _eState      := E_DL_MotorState.eIdle; // 回空闲（Back to idle）
        END_IF

    ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
        _bFaultLatch := TRUE;                     // 故障锁存（Fault latched）
        _uErrorIdInt := 16#0003_0201;             // 0003_0201 非法状态【故障级】（沿用库级既有码）/ Illegal state, fault level
        _eState      := E_DL_MotorState.eFault;
END_CASE

// ============================================================================
// 段 5｜线圈输出推导 + 星角互斥出口断言（硬约束：星/角输出恒不可同真）
//      Coil output derivation + star-delta exclusivity exit assertion
// ============================================================================
bMainContactor  := (_eState = E_DL_MotorState.eStarting) OR (_eState = E_DL_MotorState.eRunning); // 启动段与运行段主接触器吸合（Main closed in starting and running）
bStarContactor  := (_eState = E_DL_MotorState.eStarting) AND (NOT _bDeadZone); // 仅星形降压段吸合（Closed only in star phase）
bDeltaContactor := (_eState = E_DL_MotorState.eRunning);       // 仅全压运行段吸合（Closed only in full-voltage run）
IF bStarContactor AND bDeltaContactor THEN
    bStarContactor  := FALSE;                        // 断言对调：异常同真时双断保安全（Assertion fallback: cut both on impossible condition）
    bDeltaContactor := FALSE;
    _bFaultLatch    := TRUE;                         // 出口冲突锁存（Exit conflict latch）
    _uErrorIdInt    := 16#0003_0243;                 // 0003_0243 星角互斥冲突【故障级】/ Star-delta exclusivity conflict, fault level
    _eState         := E_DL_MotorState.eFault;
END_IF

// ============================================================================
// 段 6｜状态引脚映射（bFault 为显式派生式，排除信息级码——0.2 公约）
//      Status pin mapping (bFault explicit derived form, info codes excluded)
// ============================================================================
eState          := _eState;                        // 状态映射（State mapping）
bRunning        := (_eState = E_DL_MotorState.eRunning) AND bFbDelta; // 运行 = 状态且角接触器确认（Running = state AND delta confirmed）
bFault          := _bFaultLatch OR (_eState = E_DL_MotorState.eFault) OR (_eState = E_DL_MotorState.eTripOverload); // 故障派生（Fault derived）
uErrorId        := _uErrorIdInt;                   // 故障码映射（Error code mapping）
bRestartInhibit := _bRestartInhAct;                // 重启抑制映射（Restart inhibit mapping）
bStarPhase      := (_eState = E_DL_MotorState.eStarting) AND (NOT _bDeadZone); // 星形阶段指示（Star phase indicator）
END_FUNCTION_BLOCK
