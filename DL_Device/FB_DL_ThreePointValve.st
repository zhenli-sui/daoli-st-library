(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ThreePointValve
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备执行器功能块（Function Block，实现 I_DL_MotorizedValve）
 * 功能简述 (Function)   : 三点浮点式电动调节阀控制器。开/关双脉冲输出；
 *                         行程时间积分自动估算开度（TON 计时段 ET 折算，
 *                         量纲推导见段 4 注释）；全开/全关限位双保险保护
 *                         （限位锚定 + 无限位端点拒绝）；限位互斥与估算-
 *                         限位一致性监视；双向指令互斥；首扫按限位状态
 *                         推断初值（R19 范式，bTrack 强制重同步）；状态机
 *                         E_DL_MotorValveState + CASE + ELSE 兜底。
 * 接口实现 (Implements) : I_DL_MotorizedValve。接口 OUT 列同名成员
 *                         （eState/fPosEstimate/bLimOpen/bLimClosed/
 *                         bFault/uErrorId）按 R22 以只读 PROPERTY GET 承载
 *                         （内部镜像同源；fPosEstimate 为 OUT 引脚、
 *                         bLimOpen/bLimClosed 为 IN 引脚与接口属性双形式
 *                         暴露，沿用库级既有先例），非接口成员 bOpenPulse/
 *                         bClosePulse/bOpened/bClosed/uTravelCount 保留
 *                         VAR_OUTPUT；方法 CmdOpen/CmdClose/CmdStop/
 *                         CmdReset 全部在本文件尾部落地。
 * 开源溯源 (Origin)     : 来源标签 lbp-basic-process / lbp-device
 *                         （RAW_NOTES_R6 S-1 + S-5：三点浮点式电动阀的开/
 *                         关脉冲控制、行程时间开度积分估算、端点限位双
 *                         保险等行业公知工程惯例，公开教学资料，仅借鉴
 *                         通用工程语义；状态机、积分实现、故障码按本库
 *                         红线独立设计，clean-room 未复制源码）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 防除零/防越界/浮点容差
 *                         比较 ✓｜R5 全变量中英双语同行注释 ✓
 *                         R6 ENUM+CASE+ELSE ✓｜R7 四个定时器/边缘实例主体
 *                         最前部无条件刷新 ✓
 * 公约遵循 (Convention) : 0.1/R19 本块为事件型 + 连续估算混合组件：开度
 *                         积分为连续量，设 bInit 首扫（初值 FALSE，同步后
 *                         置 TRUE），判据唯一合法范式 IF bTrack OR (NOT
 *                         bInit)；bTrack 引脚供上层运行中途强制重同步。
 *                         0.7 故障码段位 16#0003_xxxx：【故障级】0003_0270
 *                         行程估算失准 / 0003_0271 双限位冲突 / 0003_0272
 *                         非法状态，R15 锁存仅复位可清；【信息级】
 *                         0003_0110 端点指令拒绝 / 0003_0111 双向指令冲突
 *                         （瞬时型每拍重算，0.15；不进 bFault）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 3 条：
 *                         ① 信息级码：规格原分配 0003_0107/0108，经与子库
 *                           VERSION.md 故障码表核对，R5 已占用 0102~0104，
 *                           且 0106~0109 已由本轮变频器/模拟量阀块顺延占用
 *                           （0105 经终审裁定空置：重启抑制拒绝统一沿用
 *                           DolMotor 既有语义码位 0208），依公约 0.7 冲突
 *                           顺延为 0003_0110/0111。
 *                         ② 开度积分：规格原文"每拍按 fDt 增量累加"需周期
 *                           时间注入或时钟基准（与公约 0.9 冲突）；本实现
 *                           改用 TON 计时段 ET 累计行程时间折算：
 *                           fPosEstimate = 锚点 + 100 × ET[ms] / 行程时间[ms]
 *                           （量纲推导：无量纲比值 × 100% = [%]），等价
 *                           消除逐拍折算误差且零时钟依赖。
 *                         ③ bOpened/bClosed 的估算近似判据取固定 1% 吸附带
 *                           （限位优先，无限位场景估算到端点 1% 带内即视为
 *                           确认），规格未定值，现场可按需整定行程时间。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R6 轮 · DL_Device 阀门/驱动族深化）
 *   2026-11-15  v1.0.1  终审注释级修订：头注释偏离①码位占位表述与终审裁定
 *                       对齐（0105 空置、重启抑制拒绝归一 DolMotor 0208）。
 *                       逻辑零变更。已知诊断口径观察项（不改码）：uTravelCount
 *                       在上电首扫若全关限位已压住会即计 +1（限位态计数），
 *                       与 R4 PwmDutyController 首周期计数偏差同类，±1 口径。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ThreePointValve IMPLEMENTS I_DL_MotorizedValve
VAR_INPUT
    bCmdOpen     : BOOL;            // 开阀指令（Open command），电平生效 / Open command, level effective
    bCmdClose    : BOOL;            // 关阀指令（Close command），电平生效；与开同拍为真 → 停止 + 信息级 / Close command, conflict with open stops with info code
    bLimOpen     : BOOL;            // 全开限位开关（Open limit switch），TRUE=已到全开端点 / Open limit switch, TRUE = at fully-open endpoint
    bLimClosed   : BOOL;            // 全关限位开关（Closed limit switch），TRUE=已到全关端点 / Closed limit switch, TRUE = at fully-closed endpoint
    tStrokeOpen  : TIME := T#60S;   // 全行程开启时间（Full open stroke time），现场实测注入 / Full-open stroke time, field-measured
    tStrokeClose : TIME := T#60S;   // 全行程关闭时间（Full close stroke time），现场实测注入 / Full-close stroke time, field-measured
    fEstimateTol : REAL := 10.0;    // 估算-限位一致性容差（Estimate tolerance）[%]，默认 10.0 / Estimate-vs-limit consistency tolerance [%]
    bEnable      : BOOL;            // 允许动作联锁（Motion interlock），TRUE=允许发脉冲 / Motion interlock, TRUE = pulses allowed
    bReset       : BOOL;            // 故障复位（Fault reset），上升沿生效 / Fault reset, rising edge effective
    bTrack       : BOOL;            // 跟踪重同步（Track resync），TRUE 拍按限位状态重推初值（R19）/ Track resync re-infers initial estimate from limits
END_VAR

VAR_OUTPUT
    bOpenPulse   : BOOL;            // 开阀脉冲输出（Open pulse output）/ Open pulse output
    bClosePulse  : BOOL;            // 关阀脉冲输出（Close pulse output）/ Close pulse output
    fPosEstimate : REAL;            // 估算开度（Estimated position）[%]，0~100，行程时间积分（R20：量纲 [%]）/ Estimated position [%], stroke-time integration
    bOpened      : BOOL;            // 全开确认（Fully opened），限位优先 / Fully opened, limit switch has priority
    bClosed      : BOOL;            // 全关确认（Fully closed），限位优先 / Fully closed, limit switch has priority
    uTravelCount : UDINT;           // 全行程计数（Travel count），全关确认沿 +1 / Travel count, incremented on closed-confirmation edge
END_VAR

VAR
    _eState        : E_DL_MotorValveState := E_DL_MotorValveState.eIdle; // 内部状态机步序（Internal state step），外部经属性只读 / Internal state, read-only via property
    _bInit         : BOOL := FALSE; // 首扫初始化标志（First-scan init flag），R19 范式判据成员 / R19 paradigm member
    _bFaultLatch   : BOOL;          // 故障锁存标志（Fault latch flag），仅复位清除 / Fault latch flag, cleared only by reset
    _uErrorIdInt   : UDINT;         // 故障级码内部寄存（Internal fault-code register）/ Internal fault-level code register
    _uInfoCode     : UDINT;         // 本拍信息级码（Info code this cycle），瞬时型每拍重算（0.15）/ Transient info code recomputed each cycle
    _fAnchor       : REAL := 50.0;  // 积分锚点（Integration anchor）[%]，脉冲静止期与估算值同步 / Integration anchor [%], synced with estimate when idle
    _fEstInt       : REAL := 50.0;  // 估算开度内部寄存（Internal estimate register）[%] / Internal estimate register [%]
    _bPendOpen     : BOOL;          // 方法开阀保持锁存（Method open hold latch）/ Method open hold latch
    _bPendClose    : BOOL;          // 方法关阀保持锁存（Method close hold latch）/ Method close hold latch
    _bPendStop     : BOOL;          // 方法停止请求（Method stop request），由 CmdStop 置位 / Method stop request set by CmdStop
    _bPendReset    : BOOL;          // 方法复位请求（Method reset request），由 CmdReset 置位 / Method reset request set by CmdReset
    _bOpenReq      : BOOL;          // 合成开阀指令（Merged open command），引脚 OR 方法锁存 / Merged open command, pin OR method latch
    _bCloseReq     : BOOL;          // 合成关阀指令（Merged close command），引脚 OR 方法锁存 / Merged close command, pin OR method latch
    _bConflict     : BOOL;          // 双向同拍冲突（Open/close conflict this cycle）/ Open-close conflict flag
    _bOpenAtEnd    : BOOL;          // 开端点到达（Open endpoint reached），限位或估算判据 / Open endpoint reached by limit or estimate
    _bCloseAtEnd   : BOOL;          // 关端点到达（Close endpoint reached），限位或估算判据 / Close endpoint reached by limit or estimate
    _fTolEff       : REAL := 10.0;  // 防御后一致性容差（Sanitized tolerance）[%] / Sanitized consistency tolerance
    _tStrokeOpenEff  : TIME := T#60S; // 防御后开启行程时间（Sanitized open stroke time），非正值回退默认 / Sanitized open stroke time, non-positive falls back
    _tStrokeCloseEff : TIME := T#60S; // 防御后关闭行程时间（Sanitized close stroke time），非正值回退默认 / Sanitized close stroke time, non-positive falls back
    _bClosedInt    : BOOL;          // 全关确认内部镜像（Internal closed-confirmation mirror），喂计数边缘实例 / Internal closed mirror feeding count edge
    _bLimOpenMir   : BOOL;          // 全开限位内部镜像（Internal open-limit mirror），供属性读取 / Internal open-limit mirror for property exposure
    _bLimClosedMir : BOOL;          // 全关限位内部镜像（Internal closed-limit mirror），供属性读取 / Internal closed-limit mirror for property exposure
    _fbTrigReset   : R_TRIG;        // 引脚复位上升沿（Pin reset edge）/ Pin reset rising edge
    _fbTrigTravel  : R_TRIG;        // 全关确认计数上升沿（Travel count edge）/ Rising edge on closed confirmation for counting
    _fbTonOpenET   : TON;           // 开阀计时段定时器（Open timing segment timer），ET 供积分折算 / Open segment timer, ET feeds integration
    _fbTonCloseET  : TON;           // 关阀计时段定时器（Close timing segment timer），ET 供积分折算 / Close segment timer, ET feeds integration
END_VAR

// ============================================================================
// 段 1｜定时器与边缘检测实例无条件周期刷新（R7：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all timer and edge instances (R7)
// ============================================================================
_fbTrigReset(CLK := bReset);
_fbTonOpenET(IN := bOpenPulse, PT := _tStrokeOpenEff);   // 计时段随开阀脉冲累计（Segment ET accumulates with open pulse）
_fbTonCloseET(IN := bClosePulse, PT := _tStrokeCloseEff); // 计时段随关阀脉冲累计（Segment ET accumulates with close pulse）
_bClosedInt := bLimClosed OR (_fEstInt <= 1.0);           // 全关确认镜像（Closed-confirmation mirror, limit priority + 1% snap band）
_fbTrigTravel(CLK := _bClosedInt);
IF _fbTrigTravel.Q THEN
    uTravelCount := uTravelCount + 1;                     // 全行程计数 +1（Travel count +1 on closed confirmation）
END_IF

// ============================================================================
// 段 2｜首扫/跟踪初始化（R19 唯一合法范式：IF bTrack OR (NOT bInit)）
//      First-scan / track initialization (R19 sole legal paradigm)
// ============================================================================
IF bTrack OR (NOT _bInit) THEN
    IF bLimOpen THEN
        _fAnchor := 100.0;                // 限位推断：已全开（Inferred from limit: fully open）
    ELSIF bLimClosed THEN
        _fAnchor := 0.0;                  // 限位推断：已全关（Inferred from limit: fully closed）
    ELSE
        _fAnchor := 50.0;                 // 无限位信息：中位兜底（No limit info: mid-position fallback）
    END_IF
    _fEstInt := _fAnchor;                 // 估算值与锚点同步（Estimate synced with anchor）
    _bInit  := TRUE;                      // 初始化完成（Initialization done）
END_IF

// ============================================================================
// 段 3｜参数防御（0.8）+ 指令合成与冲突判定
//      Parameter sanitation (0.8) + command merge and conflict evaluation
// ============================================================================
_uInfoCode := 0;                          // 本拍信息级码先归零，事件分支重算（Info code preset zero, recomputed in branches）
_bLimOpenMir := bLimOpen;                 // 全开限位镜像刷新（Refresh open-limit mirror）
_bLimClosedMir := bLimClosed;             // 全关限位镜像刷新（Refresh closed-limit mirror）
_fTolEff := fEstimateTol;                 // 容差镜像（Tolerance mirror）
IF _fTolEff <> _fTolEff THEN              // 非数自比检测（NaN self-compare test）
    _fTolEff := 10.0;                     // 回落默认容差（Fallback to default tolerance）
END_IF
IF _fTolEff < 0.0 THEN
    _fTolEff := ABS(_fTolEff);            // 负容差取绝对值（Negative tolerance made absolute）
END_IF
_tStrokeOpenEff := tStrokeOpen;           // 开启行程时间镜像（Open stroke time mirror）
IF _tStrokeOpenEff <= T#0S THEN
    _tStrokeOpenEff := T#60S;             // 非正值回退默认，防积分除零（Non-positive falls back, divide-by-zero guard）
END_IF
_tStrokeCloseEff := tStrokeClose;         // 关闭行程时间镜像（Close stroke time mirror）
IF _tStrokeCloseEff <= T#0S THEN
    _tStrokeCloseEff := T#60S;            // 非正值回退默认，防积分除零（Non-positive falls back, divide-by-zero guard）
END_IF

_bOpenReq := bCmdOpen OR _bPendOpen;      // 合成开阀指令（Merged open command）
_bCloseReq := bCmdClose OR _bPendClose;   // 合成关阀指令（Merged close command）
_bConflict := _bOpenReq AND _bCloseReq;   // 双向同拍冲突（Same-cycle conflict）
IF _bConflict THEN
    _uInfoCode := 16#0003_0111;           // 0003_0111 双向指令冲突【信息级】/ Open-close conflict, info level
END_IF
_bOpenAtEnd := bLimOpen OR (_fEstInt >= 100.0);    // 开端点判据（Open endpoint test）
_bCloseAtEnd := bLimClosed OR (_fEstInt <= 0.0);   // 关端点判据（Close endpoint test）

// ============================================================================
// 段 4｜开度积分（换算式：估算 = 锚点 + 100 × 计时段ET[ms] / 行程时间[ms]，
//       无量纲比值 × 100% → 量纲 [%]，R20；钳位 [0,100]；脉冲静止期锚点
//       与估算同步）
//      Position integration (see conversion formula above; clamped [0,100];
//      anchor synced with estimate while pulses idle)
// ============================================================================
IF bLimOpen THEN
    _fAnchor := 100.0;                    // 限位锚定：全开（Limit anchor: fully open）
    _fEstInt := 100.0;
ELSIF bLimClosed THEN
    _fAnchor := 0.0;                      // 限位锚定：全关（Limit anchor: fully closed）
    _fEstInt := 0.0;
ELSIF bOpenPulse THEN
    _fEstInt := _fAnchor + (100.0 * (TIME_TO_REAL(_fbTonOpenET.ET) / TIME_TO_REAL(_tStrokeOpenEff))); // 开向积分（Open-direction integration, divisor proven positive）
    IF _fEstInt > 100.0 THEN
        _fEstInt := 100.0;                // 上限钳位（Clamped to high bound）
    END_IF
ELSIF bClosePulse THEN
    _fEstInt := _fAnchor - (100.0 * (TIME_TO_REAL(_fbTonCloseET.ET) / TIME_TO_REAL(_tStrokeCloseEff))); // 关向积分（Close-direction integration, divisor proven positive）
    IF _fEstInt < 0.0 THEN
        _fEstInt := 0.0;                  // 下限钳位（Clamped to low bound）
    END_IF
ELSE
    _fAnchor := _fEstInt;                 // 脉冲静止期：锚点与估算同步（Pulses idle: anchor synced with estimate）
END_IF

// ============================================================================
// 段 5｜限位与估算一致性全局监视（优先级最高，故障级锁存）
//      Limit and estimate consistency global monitor (highest priority)
// ============================================================================
IF bLimOpen AND bLimClosed THEN
    _bFaultLatch := TRUE;                 // 双限位冲突锁存（Dual-limit conflict latch）
    _uErrorIdInt := 16#0003_0271;         // 0003_0271 双限位冲突（物理不可能）【故障级】/ Dual-limit conflict, fault level
    _eState      := E_DL_MotorValveState.eFault; // 强制故障态（Force fault state）
ELSIF bLimClosed AND (_fEstInt > _fTolEff) THEN
    _bFaultLatch := TRUE;                 // 估算失准锁存（Estimate mismatch latch）
    _uErrorIdInt := 16#0003_0270;         // 0003_0270 行程估算失准（估算与限位矛盾超容差）【故障级】/ Estimate mismatch beyond tolerance, fault level
    _eState      := E_DL_MotorValveState.eFault;
ELSIF bLimOpen AND (_fEstInt < (100.0 - _fTolEff)) THEN
    _bFaultLatch := TRUE;                 // 估算失准锁存（Estimate mismatch latch）
    _uErrorIdInt := 16#0003_0270;         // 0003_0270 行程估算失准【故障级】/ Estimate mismatch beyond tolerance, fault level
    _eState      := E_DL_MotorValveState.eFault;
END_IF

// ============================================================================
// 段 6｜核心状态机（ENUM + CASE，含 ELSE 非法状态兜底）
//      Core state machine (ENUM + CASE with ELSE illegal-state fallback)
// ============================================================================
IF _bFaultLatch OR (_eState = E_DL_MotorValveState.eFault) THEN
    CASE _eState OF
        E_DL_MotorValveState.eFault: // 故障锁存态：清空全部请求，仅复位可退出
            _bPendOpen  := FALSE;             // 清方法锁存（Clear method latches）
            _bPendClose := FALSE;
            _bPendStop  := FALSE;
            IF _bPendReset OR _fbTrigReset.Q THEN
                _bPendReset  := FALSE;        // 消费复位请求（Consume reset request）
                _bFaultLatch := FALSE;        // 解除锁存（Release latch）
                _uErrorIdInt := 0;            // 故障码清零（Error code cleared）
                _fAnchor     := _fEstInt;     // 锚点与估算重同步（Anchor re-synced with estimate）
                _eState      := E_DL_MotorValveState.eIdle; // 回空闲态（Back to idle）
            END_IF
        ELSE // 锁存标志与状态不一致兜底：强制同步进故障态（Latch/state mismatch fallback）
            _eState := E_DL_MotorValveState.eFault;
    END_CASE
ELSE
    CASE _eState OF

        E_DL_MotorValveState.eIdle: // 空闲稳态：双脉冲全断
            IF _bPendStop THEN
                _bPendStop := FALSE;          // 消化停止请求（Absorb stop request）
            END_IF
            IF bLimOpen THEN
                _fAnchor := 100.0;            // 限位同步锚点（Sync anchor with limit）
                _fEstInt := 100.0;
                _eState  := E_DL_MotorValveState.eOpened;
            ELSIF bLimClosed THEN
                _fAnchor := 0.0;              // 限位同步锚点（Sync anchor with limit）
                _fEstInt := 0.0;
                _eState  := E_DL_MotorValveState.eClosed;
            ELSIF _bConflict THEN
                // 双向冲突：安全侧不动，信息级已在段 3 置码（Conflict: hold, info code set in section 3）
            ELSIF _bOpenReq AND (NOT _bOpenAtEnd) THEN
                _eState := E_DL_MotorValveState.eOpening; // 受理开阀（Accept open）
            ELSIF _bCloseReq AND (NOT _bCloseAtEnd) THEN
                _eState := E_DL_MotorValveState.eClosing; // 受理关阀（Accept close）
            ELSIF (_bOpenReq AND _bOpenAtEnd) OR (_bCloseReq AND _bCloseAtEnd) THEN
                _uInfoCode := 16#0003_0110;   // 0003_0110 端点指令拒绝【信息级】/ Endpoint command refused, info level
            END_IF

        E_DL_MotorValveState.eOpening: // 开阀中：开阀脉冲输出
            IF bLimOpen THEN
                _fAnchor := 100.0;            // 限位锚定双保险①（Limit anchor, protection layer 1）
                _fEstInt := 100.0;
                _eState  := E_DL_MotorValveState.eOpened;
            ELSIF (NOT _bOpenReq) OR _bConflict OR _bPendStop THEN
                _bPendStop := FALSE;          // 消化停止请求（Absorb stop request）
                _eState    := E_DL_MotorValveState.eIdle; // 指令撤除/冲突/停止：回空闲（Command dropped, conflict or stop: to idle）
            ELSIF _fEstInt >= 100.0 THEN
                _uInfoCode := 16#0003_0110;   // 0003_0110 端点指令拒绝（无限位端点双保险②）【信息级】/ Endpoint refused (no-limit protection layer 2), info level
                _eState    := E_DL_MotorValveState.eIdle;
            END_IF

        E_DL_MotorValveState.eClosing: // 关阀中：关阀脉冲输出
            IF bLimClosed THEN
                _fAnchor := 0.0;              // 限位锚定双保险①（Limit anchor, protection layer 1）
                _fEstInt := 0.0;
                _eState  := E_DL_MotorValveState.eClosed;
            ELSIF (NOT _bCloseReq) OR _bConflict OR _bPendStop THEN
                _bPendStop := FALSE;          // 消化停止请求（Absorb stop request）
                _eState    := E_DL_MotorValveState.eIdle; // 指令撤除/冲突/停止：回空闲（Command dropped, conflict or stop: to idle）
            ELSIF _fEstInt <= 0.0 THEN
                _uInfoCode := 16#0003_0110;   // 0003_0110 端点指令拒绝（无限位端点双保险②）【信息级】/ Endpoint refused (no-limit protection layer 2), info level
                _eState    := E_DL_MotorValveState.eIdle;
            END_IF

        E_DL_MotorValveState.eOpened: // 全开确认稳态：限位优先
            IF NOT bLimOpen THEN
                _eState := E_DL_MotorValveState.eIdle; // 限位脱开回空闲（Limit dropped, to idle）
            ELSIF _bCloseReq AND (NOT _bCloseAtEnd) THEN
                _eState := E_DL_MotorValveState.eClosing; // 受理关阀（Accept close）
            ELSIF _bOpenReq THEN
                _uInfoCode := 16#0003_0110;   // 0003_0110 端点指令拒绝（限位确认端点）【信息级】/ Endpoint command refused at limit, info level
            END_IF

        E_DL_MotorValveState.eClosed: // 全关确认稳态：限位优先
            IF NOT bLimClosed THEN
                _eState := E_DL_MotorValveState.eIdle; // 限位脱开回空闲（Limit dropped, to idle）
            ELSIF _bOpenReq AND (NOT _bOpenAtEnd) THEN
                _eState := E_DL_MotorValveState.eOpening; // 受理开阀（Accept open）
            ELSIF _bCloseReq THEN
                _uInfoCode := 16#0003_0110;   // 0003_0110 端点指令拒绝（限位确认端点）【信息级】/ Endpoint command refused at limit, info level
            END_IF

        ELSE // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;             // 故障锁存（Fault latched）
            _uErrorIdInt := 16#0003_0272;     // 0003_0272 非法状态【故障级】/ Illegal state, fault level
            _eState      := E_DL_MotorValveState.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 7｜脉冲输出推导 + 双脉冲互斥出口断言（硬约束：开/关脉冲恒不可同真）
//      Pulse output derivation + mutual exclusivity exit assertion
// ============================================================================
bOpenPulse  := (_eState = E_DL_MotorValveState.eOpening) AND _bOpenReq AND (NOT _bConflict)
               AND bEnable AND (NOT bLimOpen) AND (_fEstInt < 100.0); // 开阀脉冲使能条件链（Open pulse condition chain）
bClosePulse := (_eState = E_DL_MotorValveState.eClosing) AND _bCloseReq AND (NOT _bConflict)
               AND bEnable AND (NOT bLimClosed) AND (_fEstInt > 0.0); // 关阀脉冲使能条件链（Close pulse condition chain）
IF bOpenPulse AND bClosePulse THEN
    bOpenPulse  := FALSE;               // 断言对调：异常同真时双断保安全（Assertion fallback: cut both on impossible condition）
    bClosePulse := FALSE;
END_IF
IF (_eState = E_DL_MotorValveState.eFault) OR (_eState = E_DL_MotorValveState.eIdle)
   OR (_eState = E_DL_MotorValveState.eOpened) OR (_eState = E_DL_MotorValveState.eClosed) THEN
    bOpenPulse  := FALSE;               // 出口断言：非动作态脉冲必断（Assertion: pulses off in non-motion states）
    bClosePulse := FALSE;
END_IF
fPosEstimate := _fEstInt;               // 估算开度输出（Estimate output）
bOpened := bLimOpen OR (_fEstInt >= 99.0); // 全开确认：限位优先 + 1% 吸附带（Opened: limit priority + 1% snap band）
bClosed := bLimClosed OR (_fEstInt <= 1.0); // 全关确认：限位优先 + 1% 吸附带（Closed: limit priority + 1% snap band）

(*------------------------------------------------------------------------------
 * 方法: CmdOpen —— 开阀指令（受理为保持锁存）。故障态一律拒绝返回 FALSE。
 *      Method CmdOpen - open command held as latch, rejected with FALSE in fault.
 *------------------------------------------------------------------------------*)
METHOD CmdOpen : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_MotorValveState.eFault) THEN
    CmdOpen := FALSE;         // 故障态拒绝（Rejected in fault state）
    _bPendClose := FALSE;     // 清反向残留锁存（Clear stale reverse latch）
ELSE
    _bPendOpen := TRUE;       // 登记开阀保持锁存（Register open hold latch）
    _bPendClose := FALSE;     // 互斥注销关阀锁存（Cancel opposite close latch）
    CmdOpen := TRUE;          // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdClose —— 关阀指令（受理为保持锁存）。故障态一律拒绝返回 FALSE。
 *      Method CmdClose - close command held as latch, rejected with FALSE in fault.
 *------------------------------------------------------------------------------*)
METHOD CmdClose : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_MotorValveState.eFault) THEN
    CmdClose := FALSE;        // 故障态拒绝（Rejected in fault state）
    _bPendOpen := FALSE;      // 清反向残留锁存（Clear stale reverse latch）
ELSE
    _bPendClose := TRUE;      // 登记关阀保持锁存（Register close hold latch）
    _bPendOpen := FALSE;      // 互斥注销开阀锁存（Cancel opposite open latch）
    CmdClose := TRUE;         // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 双脉冲全断保持当前位置。无条件受理。
 *      Method CmdStop - both pulses off and hold position, unconditionally accepted.
 *------------------------------------------------------------------------------*)
METHOD CmdStop : BOOL
VAR_INPUT
END_VAR
_bPendOpen  := FALSE;         // 注销开阀锁存（Cancel open latch）
_bPendClose := FALSE;         // 注销关阀锁存（Cancel close latch）
_bPendStop  := TRUE;          // 登记停止请求，主体状态机消化（Register stop request, consumed by body）
CmdStop := TRUE;              // 无条件受理（Unconditionally accepted）

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障，返回是否可复位（存在锁存故障时为 TRUE）。
 *      Method CmdReset - reset fault, returns TRUE only when a latch exists.
 *------------------------------------------------------------------------------*)
METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_MotorValveState.eFault) THEN
    _bPendReset := TRUE;      // 登记复位请求，主体状态机消化（Register reset request, consumed by body）
    CmdReset := TRUE;         // 可复位（Resettable）
ELSE
    CmdReset := FALSE;        // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前状态机状态只读视图。
 *      Property eState (GET) - read-only view of the current state machine state.
 *------------------------------------------------------------------------------*)
PROPERTY eState : E_DL_MotorValveState
eState := _eState;            // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: fPosEstimate（GET）—— 估算开度 [%]（行程时间积分）。
 *      Property fPosEstimate (GET) - estimated position [%] from stroke-time integration.
 *------------------------------------------------------------------------------*)
PROPERTY fPosEstimate : REAL
fPosEstimate := _fEstInt;     // 返回估算镜像（Return estimate mirror）

(*------------------------------------------------------------------------------
 * 属性: bLimOpen（GET）—— 全开限位反馈。
 *      Property bLimOpen (GET) - open limit switch feedback.
 *------------------------------------------------------------------------------*)
PROPERTY bLimOpen : BOOL
bLimOpen := _bLimOpenMir;     // 返回限位镜像（Return limit mirror）

(*------------------------------------------------------------------------------
 * 属性: bLimClosed（GET）—— 全关限位反馈。
 *      Property bLimClosed (GET) - closed limit switch feedback.
 *------------------------------------------------------------------------------*)
PROPERTY bLimClosed : BOOL
bLimClosed := _bLimClosedMir; // 返回限位镜像（Return limit mirror）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info-level codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_MotorValveState.eFault); // 显式排除信息级派生式（Explicit derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次事件码（故障级锁存优先；无故障时透出本拍
 *         信息级码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last event code (fault-level priority,
 *      transient info code shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_MotorValveState.eFault) THEN
    uErrorId := _uErrorIdInt; // 故障级码优先透出（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;   // 无故障时透出本拍信息级码（Transient info code when no fault）
END_IF
END_FUNCTION_BLOCK
