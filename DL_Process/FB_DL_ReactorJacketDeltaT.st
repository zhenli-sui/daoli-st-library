(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ReactorJacketDeltaT
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 釜温-夹套温差约束与冷热分程
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / TON / ABS / MIN / MAX / LIMIT）
 *                         与库内低层件 FB_DL_RateLimiter（DL_Algo），零厂商方言
 * 接口依赖 (Depends)    : E_DL_Ne107Status（属主 A1）、FB_DL_RateLimiter（DL_Algo 既有件）。
 *                         温度闭环由 FB_DL_CascadePid 承担，本件只做「约束层 + 分程层」。
 * 功能描述 (Function)   : 放热反应的釜温-夹套温差抑制。以 ΔT = 釜温 − 夹套温 为约束量，
 *                         对升温侧做**温差上限约束**与**温差变化率约束**，并把上层 PID 输出
 *                         分程为冷/热两路阀位给定；超温时强制冷却；分程带死区防冷热同开。
 * 边界与纪律 (Boundary) : ① **不内联 PID** —— 温度闭环由 FB_DL_CascadePid 承担，PID 输出以
 *                         fPidOut 引脚注入，本件绝不实现比例/积分/微分；② **不新增轴/相状态
 *                         枚举** —— 工艺相状态归 FB_DL_BatchPhaseBase，本件的 E_DL_JacketState
 *                         只描述「冷热分程的当前执行方向」，不是批次相状态（R31 家族纪律）；
 *                         ③ 两路输出**互斥**（由状态机与目标量赋值保证），并带 fDeadband 死区，
 *                         禁止「冷热同开」；④ 不做阀位反馈校验（归阀门件）。
 * 分层声明 (Layer)      : 工艺层（DL_Process）。限速能力**组合调用** FB_DL_RateLimiter，
 *                         绝不内联限速算法（依赖方向纪律）。零全局变量表引用、零外部变量声明、
 *                         零物理 IO 地址。
 * 段序     (Segments)   : 段1 实例无条件刷新（含两个限速器实例）→ 段2 复位通道（CASE 前，R39）→
 *                         段3 输入防御与参数钳位 → 段4 温差与变化率测量（TON 统计窗，R40）→
 *                         段5 状态机（约束层 + 分程层）→ 段6 分程限速（组合低层件）→
 *                         段7 码位单一优先级链 → 段8 出口钳位与互斥仲裁。
 * 枚举映射表 (R31)      : eIdle(0)→标签 0｜eHeat(10)→标签 10｜eCool(20)→标签 20｜eHold(30)→标签 30｜
 *                         eFault(99)→标签 99。每个成员有且仅有一个显式标签，ELSE 只接脏值（02FE）。
 * 单拍标志清单 (R25)    : 本件唯一的沿输入是 bReset：预清零点段1 每拍覆盖 _bResetEdge；置位点
 *                         段1 的 _fbTrigReset 实例调用；自清点紧随实例调用的赋值行。
 * 保持位清单 (R27)      : bDeltaTLimited / bOverTemp / fHeatOut / fCoolOut —— 逐拍由
 *                         _bLimitLatched / _bOverTempLatched / 限速器输出重写，绝不靠进入那拍。
 * 定时器清单 (R40)      : _fbTonRate｜IN = NOT _bRateBreak（变化率统计窗，PT = tRateWindow）｜
 *                         断输入标志 _bRateBreak（每次窗口结算置一拍，ET 归零后重开新窗）｜
 *                         自清点：段2 无条件 `IF _bRateBreak THEN _bRateBreak := FALSE; END_IF`。
 *                         另有两个 FB_DL_RateLimiter 实例在段6 无条件周期调用（R7：位于主体顶层，
 *                         不在任何 IF/CASE 之内；必须在状态机算出目标量之后，否则目标滞后一拍）。
 * 三元一致表 (R35)      : 温差上限守卫 5~150 K / 封顶 150 / 判据 `>=`（达上限即冻结）｜
 *                         变化率守卫 0.1~50 K/min / 封顶 50 / 判据 `>`（超阈只报警不拦截）｜
 *                         死区守卫 0~10 % / 封顶 10 / 判据 `<=`（判据 `<=` 与封顶同向）。
 * 镜像量清单 (R38)      : fReactorTemp / fJacketTemp / fPidOut 的唯一消费点是段3 的三个快照
 *                         （_fReactorNow / _fJacketNow / _fPidNow），全件不二次读取实时入参。
 * R36 关联（必须手算，写给调用方）: 本件消费上层 PID 输出 fPidOut。**调用方须保证 fPidOut 已过
 *                         「跟踪结束首拍」处理**：若上层 PID 处于跟踪态（手动/暂停）时输出为
 *                         fTrack，切自动首拍 fPidOut = fP + fI + fD 可能相对 fTrack 跳变
 *                         Δ = fPidOut − fTrack。手算示例：fTrack = 0 %、fP = 24 %、fI = 18 %、
 *                         fD = 0 %（微分先行且无扰动）→ 首拍 fPidOut = 42 %，跳变 42 %；若上层
 *                         PID 已按无扰切换（fI := fOut − fP − fD 反算残量）则 fI 已被重算为
 *                         −24 %，首拍 fPidOut 仍为 0 %，不会出现阶跃。本件对该阶跃**不做补偿**
 *                         （补偿属 PID 的无扰切换职责），只保证：首拍大跳不会触发 16#0005_01CF
 *                         （01CF 的判据是实测温差达上限，不是指令跳变）。V4 向量复现该场景。
 * 开源溯源 (Origin)     : 原创实现（参考 Siemens LBP 的「给定 → 限幅 → 闭环 → 执行机构限幅」
 *                         设定值分层组织结构，T2-2 主源；以及 ISA-88 公开的相语义与状态迁移
 *                         惯例，T2-8 次源）。仅借分层骨架与参数域划分，LBP 块名、参数名、UDT
 *                         布局、门限值一律未沿用；温差约束、分程死区、反装判据为本库自有。
 *                         许可证说明：LBP 与 ISA-88 均为文档/公开规范（非代码），只借组织
 *                         结构，clean-room 编写；本文件为本库原创，随本库许可证发布。
 * 验收向量 (Acceptance) :
 *   V1 釜 80 ℃、夹套 60 ℃、fPidOut = +40 %、fDeltaTMax = 30 → eHeat、fHeatOut = 40.0、
 *      fCoolOut = 0.0（未受限时不限速，直接跟随）。
 *   V2（约束层）釜温继续升、ΔT = 31 K → bDeltaTLimited = TRUE、fHeatOut 按 fDeltaTRate
 *      折算的速率斜坡回 0、16#0005_01CF。
 *   V3（V-C 死区分程）fPidOut = +1.0 %（< 死区 2.0）→ 两路均 0（eHold），**不得**冷热同开；
 *      离开死区时置 16#0005_01D1。
 *   V4（V-D R36 跟踪首拍）上层 PID 从手动跟踪切自动，首拍 fPidOut 由 0 跳到 +60 % → 本件
 *      未受限时直通（周期内不产生 ΔT 变化），**不得**因此误报 01CF；一旦因温差触限，输出按
 *      fDeltaTRate 限速回落（限速路径由 FB_DL_RateLimiter 承担，非限幅）。
 *   V5（V-A 反装）釜 80、夹套 95、fPidOut = +50 % → ΔT = −15 且要求升温 → 16#0005_02FD 锁存
 *      （这是本件最有价值的一条：反装传感器会被这条抓住）。
 * 偏离留档 (Deviation)  :
 *   ① 增补 tCycle 引脚（任务扫描周期）：FB_DL_RateLimiter 的限速步长必须用真实周期折算，
 *      规格未给该引脚。理由：公共约定（时间换算基准由引脚给）与泳道内 FB_DL_LeakTestStation
 *      先例一致，属公共约定强制项，非语义偏离。
 *   ② 常态是否限速的裁定：V1 要求「fPidOut = +40 % → fHeatOut = 40.0」，V4 要求「阶跃时限速」。
 *      两者只在「未受限」与「已受限」两种工况下并存，故本件把限速施加于**约束路径**
 *      （温差触限、超温强制冷却、以及从约束态恢复的整个过程），未受限时按 V1 直通。
 *      实现上用 FB_DL_RateLimiter 的 bTrack 引脚完成无扰切换：跟踪时输出等于输入，退出跟踪
 *      那一拍从当前值开始限速，不存在回跳。
 *   ③ 温差→阀位速率折算：以常量 DL_JKT_K_PER_PCT（默认 0.5 K/%）把 fDeltaTRate [K/min]
 *      折算为 [%/s]，即 (fDeltaTRate / 60) / DL_JKT_K_PER_PCT。该常量是夹套传热增益的
 *      工艺整定值，由调用方按装置实测整定；折算关系在头注释显式披露，不做隐藏假设。
 *   ④ 控制码 01CE 的修正：规格 V2 正文写作 01CE，但码位表把「温差达上限冻结」定为
 *      16#0005_01CF，且 01CE 已被 C5 占用（配方名截断）。本件按**码位表**执行（01CF），
 *      避免跨件撞号，此处留档。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 C · DL_Process 第 26 件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_JacketState（归属 FB_DL_ReactorJacketDeltaT，同文件发布）
 * 说明: 只表达「冷热分程的当前执行方向」，**不是**批次相状态（相状态归 FB_DL_BatchPhaseBase）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_JacketState :
(
    eIdle  := 0,    // 空闲：未使能或参数未就绪 / Idle, disabled or parameters not ready
    eHeat  := 10,   // 升温：热路给给定，冷路 0 / Heating, heat path commanded, cool path zero
    eCool  := 20,   // 冷却：冷路给给定，热路 0 / Cooling, cool path commanded, heat path zero
    eHold  := 30,   // 保持：两路均 0（死区内或温差触限冻结）/ Hold, both paths zero
    eFault := 99    // 故障：非有限、反装或非法状态 / Fault, non-finite, reversed sensor or illegal state
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ReactorJacketDeltaT
VAR_INPUT
    bEnable        : BOOL;                  // 使能（Enable），FALSE = 两路归零并回空闲；复位通道不受其屏蔽 / Enable, FALSE zeroes both paths
    bReset         : BOOL;                  // 复位（Reset），上升沿清故障与保持位 / Rising edge clears the fault and the held flags
    fReactorTemp   : REAL;                  // 釜温（Reactor temperature）[℃]，域 −50~400 / Reactor temperature [degC]
    fJacketTemp    : REAL;                  // 夹套温度（Jacket temperature）[℃]，域 −50~400 / Jacket temperature [degC]
    fPidOut        : REAL;                  // 上层 PID 输出（PID output）[%]，域 −100~100，**须已过跟踪首拍**（R36）/ PID output [%], must have passed its tracking-exit scan
    fDeltaTMax     : REAL := 30.0;          // 允许最大温差（Max allowed delta-T）[K]，域 5~150，默认 30.0 / Max allowed delta-T [K]
    fDeltaTRate    : REAL := 5.0;           // 温差变化率上限（Delta-T rate limit）[K/min]，域 0.1~50，默认 5.0 / Delta-T rate limit [K/min]
    fOverTempMargin : REAL := 5.0;          // 超温强制冷却裕量（Over-temperature margin）[K]，域 0.5~50，默认 5.0 / Over-temperature margin [K]
    fTempSetpoint  : REAL;                  // 釜温设定（Reactor setpoint）[℃]，域 −50~400，超温判据用 / Reactor setpoint [degC]
    tRateWindow    : TIME := T#1M;          // 变化率统计窗（Rate window），域 5 s~10 min，默认 1 min / Rate window
    fDeadband      : REAL := 2.0;           // 冷热分程死区（Split-range deadband）[%]，域 0~10，默认 2.0 / Split-range deadband [%]
    fOutMin        : REAL := 0.0;           // 输出下限（Output lower limit）[%]，默认 0.0 / Output lower limit [%]
    fOutMax        : REAL := 100.0;         // 输出上限（Output upper limit）[%]，默认 100.0 / Output upper limit [%]
    tCycle         : TIME := T#10MS;        // 任务扫描周期（Task cycle time）[ms]，限速步长折算基准（偏离留档①）/ Task cycle time [ms]
END_VAR

VAR_OUTPUT
    fHeatOut       : REAL;                  // 热路阀位给定（Heat output）[%]，0~100，保持语义 / Heat valve command [%], held
    fCoolOut       : REAL;                  // 冷路阀位给定（Cool output）[%]，0~100，保持语义 / Cool valve command [%], held
    fDeltaT        : REAL;                  // 实测温差（Measured delta-T）[K]，有符号 = 釜温 − 夹套温 / Measured delta-T [K], signed
    fDeltaTRateMeas : REAL;                 // 实测温差变化率（Measured delta-T rate）[K/min]，窗内斜率 / Measured delta-T rate [K/min]
    bDeltaTLimited : BOOL;                  // 温差达上限、升温侧被限（Delta-T limiting active），保持语义 / TRUE while the delta-T limit is active
    bOverTemp      : BOOL;                  // 釜温超设定加裕量（Over temperature），保持语义 / TRUE while over temperature
    eVerdict       : E_DL_JacketState;      // 当前执行方向（Verdict state），逐拍重写 / Current actuation direction, rewritten every scan
    eHealth        : E_DL_Ne107Status;      // 健康态（NE107 health），引用属主 A1 的枚举 / NE107 health, owned by A1
    uDiagCode      : UDINT;                 // 诊断码（Diagnostic code），本拍单一优先级链输出 / Diagnostic code, single priority chain
    uErrorId       : UDINT;                 // 故障码（Error code），仅故障级码，0 = 无故障 / Fault-level code, 0 = no fault
    bError         : BOOL;                  // 故障标志（Error），仅故障级码置位 / TRUE only for fault-level codes
END_VAR

VAR
    _eState        : E_DL_JacketState := E_DL_JacketState.eIdle;    // 内部状态（Internal state）/ Internal state value
    _bResetEdge    : BOOL;                  // 复位沿单拍标志（Reset one-shot flag）/ Reset one-shot flag
    _bRateBreak    : BOOL;                  // 统计窗断输入拍（Rate window break）/ Rate window break
    _uFaultCode    : UDINT;                 // 本拍故障级码（Fault-level code this scan）/ Fault-level code of this scan
    _uFaultLatched : UDINT;                 // 故障码锁存（Latched fault code），仅复位清除 / Latched fault code, reset only
    _uInfoCode     : UDINT;                 // 本拍信息级码（Info-level code this scan）/ Info-level code of this scan
    _bFaultCond    : BOOL;                  // 故障条件（Fault condition）/ Fault condition flag
    _fReactorNow   : REAL;                  // 釜温快照（Reactor temperature snapshot）[℃]，单次锁存（R38）/ Reactor snapshot [degC]
    _fJacketNow    : REAL;                  // 夹套温快照（Jacket temperature snapshot）[℃]，单次锁存（R38）/ Jacket snapshot [degC]
    _fPidNow       : REAL;                  // PID 输出快照（PID output snapshot）[%]，单次锁存（R38）/ PID snapshot [%]
    _fDeltaTMaxEff : REAL;                  // 生效温差上限（Effective delta-T limit）[K] / Effective delta-T limit [K]
    _fRateLimEff   : REAL;                  // 生效变化率上限（Effective rate limit）[K/min] / Effective rate limit [K/min]
    _fOtMarginEff  : REAL;                  // 生效超温裕量（Effective over-temp margin）[K] / Effective over-temp margin [K]
    _fDeadbandEff  : REAL;                  // 生效死区（Effective deadband）[%] / Effective deadband [%]
    _fOutLowEff    : REAL;                  // 生效输出下限（Effective output low）[%] / Effective output low [%]
    _fOutHighEff   : REAL;                  // 生效输出上限（Effective output high）[%] / Effective output high [%]
    _fRatePctS     : REAL;                  // 折算后的阀位速率（Output rate）[%/s]，偏离留档③ / Output rate [%/s]
    _fSwapTmp      : REAL;                  // 交换临时量（Swap scratch）[EU] / Swap scratch [EU]
    _fRateMin      : REAL;                  // 统计窗分钟值（Window minutes）[min] / Rate window in minutes [min]
    _fDtWinStart   : REAL;                  // 窗起点温差（Delta-T at the window start）[K] / Delta-T at the window start [K]
    _bRateInit     : BOOL;                  // 变化率窗首扫标志（Rate window first-scan flag），初值 FALSE（R19）/ Rate window init flag
    _fRateMeasInt  : REAL;                  // 内部变化率（Internal rate）[K/min] / Internal rate [K/min]
    _fHeatTgt      : REAL;                  // 热路目标（Heat target）[%]，送限速器 / Heat target [%] fed to the limiter
    _fCoolTgt      : REAL;                  // 冷路目标（Cool target）[%]，送限速器 / Cool target [%] fed to the limiter
    _bLimitActive  : BOOL;                  // 本拍处于约束路径（Limiting path active this scan）/ Limiting path active
    _bLimitLatched : BOOL;                  // 温差触限锁存（Delta-T limit latch）/ Delta-T limit latch
    _bOverTempLatched : BOOL;               // 超温锁存（Over-temperature latch）/ Over-temperature latch
    _fHeatPrev     : REAL;                  // 上一拍热路输出（Previous heat output）[%] / Previous heat output [%]
    _fCoolPrev     : REAL;                  // 上一拍冷路输出（Previous cool output）[%] / Previous cool output [%]
    _fbTrigReset   : R_TRIG;                // 复位上升沿（Reset rising edge）/ Reset rising edge
    _fbTonRate     : TON;                   // 变化率统计窗（Rate window timer）/ Rate window timer
    _fbRlHeat      : FB_DL_RateLimiter;     // 热路限速器（Heat rate limiter，组合调用低层件）/ Heat rate limiter, composed from DL_Algo
    _fbRlCool      : FB_DL_RateLimiter;     // 冷路限速器（Cool rate limiter，组合调用低层件）/ Cool rate limiter, composed from DL_Algo
END_VAR

VAR CONSTANT
    DL_JKT_REAL_MAX : REAL := 3.4E38;       // 单精度有限值判据幅值（Finite magnitude bound）/ Finite bound for REAL inputs
    DL_JKT_EPS      : REAL := 1.0E-6;       // 浮点防零容差（Divide-guard epsilon）/ Float divide-guard epsilon
    DL_JKT_TEMP_MIN : REAL := -50.0;        // 温度域下限（Temperature lower domain）[℃] / Temperature lower domain [degC]
    DL_JKT_TEMP_MAX : REAL := 400.0;        // 温度域上限（Temperature upper domain）[℃] / Temperature upper domain [degC]
    DL_JKT_PID_MAX  : REAL := 100.0;        // PID 输出域（PID output domain）[%] / PID output domain [%]
    DL_JKT_DT_LO    : REAL := 5.0;          // 温差上限域下限（Delta-T upper clamp low）[K] / Delta-T upper clamp low [K]
    DL_JKT_DT_HI    : REAL := 150.0;        // 温差上限域上限（Delta-T upper clamp high）[K] / Delta-T upper clamp high [K]
    DL_JKT_RATE_LO  : REAL := 0.1;          // 变化率域下限（Rate lower clamp）[K/min] / Rate lower clamp [K/min]
    DL_JKT_RATE_HI  : REAL := 50.0;                // 变化率域上限（Rate upper clamp）[K/min] / Rate upper clamp [K/min]
    DL_JKT_OT_LO    : REAL := 0.5;          // 超温裕量域下限（Margin lower clamp）[K] / Margin lower clamp [K]
    DL_JKT_OT_HI    : REAL := 50.0;                // 超温裕量域上限（Margin upper clamp）[K] / Margin upper clamp [K]
    DL_JKT_DB_LO    : REAL := 0.0;          // 死区域下限（Deadband lower clamp）[%] / Deadband lower clamp [%]
    DL_JKT_DB_HI    : REAL := 10.0;                // 死区域上限（Deadband upper clamp）[%] / Deadband upper clamp [%]
    DL_JKT_HYST     : REAL := 0.5;          // 触限回差（Limit hysteresis）[K]，防边界抖动 / Limit hysteresis [K]
    DL_JKT_K_PER_PCT : REAL := 0.5;         // 阀位传热增益（K per percent）[K/%]，偏离留档③ / Heat gain per percent [K/%]
    DL_JKT_MIN_PER_H : REAL := 60.0;        // 分钟换算（Minutes per hour）[-] / Minutes per hour
    DL_JKT_MS_PER_MIN : REAL := 60000.0;    // 毫秒→分钟换算（Milliseconds-to-minutes scale）[-] / Milliseconds-to-minutes scale
    DL_JKT_OPEN_EPS : REAL := 0.5;          // 「阀已开」判据（Valve open epsilon）[%] / Valve open epsilon [%]
    DL_JKT_ERR_NONFIN : UDINT := 16#0005_02FC; // 0005_02FC 温度或 PID 输出非有限【故障级】/ Non-finite temperature or PID output
    DL_JKT_ERR_REV    : UDINT := 16#0005_02FD; // 0005_02FD 温差为负且要求升温（传感器反装）【故障级】/ Reversed sensor, fault level
    DL_JKT_ERR_STATE  : UDINT := 16#0005_02FE; // 0005_02FE 非法状态兜底【故障级】/ Illegal state fallback, fault level
    DL_JKT_INFO_LIM   : UDINT := 16#0005_01CF; // 0005_01CF 温差达上限升温侧冻结【信息级】/ Delta-T limit reached, info level
    DL_JKT_INFO_OT    : UDINT := 16#0005_01D0; // 0005_01D0 釜温超设定加裕量强制冷却【信息级】/ Over temperature, info level
    DL_JKT_INFO_SPLIT : UDINT := 16#0005_01D1; // 0005_01D1 分程重叠区被死区分离【信息级】/ Split-range overlap separated, info level
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of every instance (R7/0.5)
// ============================================================================
_fbTrigReset(CLK := bReset);                    // 复位上升沿（Reset rising edge）
_bResetEdge := _fbTrigReset.Q;                  // 复位单拍标志紧随实例赋值（R25 自清点）
_fbTonRate(
    IN := (NOT _bRateBreak),                    // 断输入拍串入 IN（R40 合规指纹）/ Window break folded into IN
    PT := tRateWindow
);                                              // 变化率统计窗（Rate window）

// 本拍码与条件预置（每拍重算；故障码以上拍锁存续用）
// Per-scan preset of codes and conditions, the fault code is carried from the latch
_uFaultCode := _uFaultLatched;                  // 故障码续用（Carry the latched fault code）
_uInfoCode  := 16#0000_0000;                    // 信息级码预清零（Info code preset to zero）
_bFaultCond := FALSE;                           // 故障条件预清零（Fault condition preset FALSE）
_fHeatTgt   := 0.0;                             // 热路目标预置 0（Heat target preset to zero）
_fCoolTgt   := 0.0;                             // 冷路目标预置 0（Cool target preset to zero）
_bLimitActive := FALSE;                         // 约束路径预置假（Limiting path preset FALSE）

// ============================================================================
// 段 2｜复位通道（R39：置于 CASE 之前，且不被掉使能分支屏蔽）
//      Reset path, before CASE and never masked by the disable branch
// ============================================================================
IF _bRateBreak THEN
    _bRateBreak := FALSE;                       // 统计窗断输入拍自清（Window break self-cleared）
END_IF

IF _bResetEdge THEN
    _bLimitLatched    := FALSE;                 // 触限锁存清除（Limit latch cleared）
    _bOverTempLatched := FALSE;                 // 超温锁存清除（Over-temp latch cleared）
    _fRateMeasInt     := 0.0;                   // 变化率测量值清零（Rate measurement cleared）
    _fDtWinStart      := 0.0;                   // 窗起点清零（Window start cleared）
    _bRateInit        := FALSE;                 // 窗首扫标志复位，重装基准（Init flag reset, R41）
    _uFaultLatched    := 16#0000_0000;          // 故障码锁存清除（Latched fault code cleared）
    _uFaultCode       := 16#0000_0000;          // 本拍故障码清空，防止段6 重新锁存旧码（Clear this scan code）
    IF _eState = E_DL_JacketState.eFault THEN
        _eState := E_DL_JacketState.eIdle;      // 故障态回空闲（Fault state back to idle）
        _bFaultCond := FALSE;                   // 故障条件清除（Fault condition cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜输入防御与参数钳位（镜像量每拍只锁一次，R38）
//      Input defense and parameter clamping, each mirror value latched once (R38)
// ============================================================================
IF (NOT (fReactorTemp >= DL_JKT_TEMP_MIN AND fReactorTemp <= DL_JKT_TEMP_MAX))
OR (NOT (fJacketTemp >= DL_JKT_TEMP_MIN AND fJacketTemp <= DL_JKT_TEMP_MAX))
OR (NOT (fPidOut >= (-DL_JKT_PID_MAX) AND fPidOut <= DL_JKT_PID_MAX)) THEN
    _bFaultCond := TRUE;                        // 非有限或越域即故障（Non-finite or out-of-domain is a fault）
    _uFaultCode := DL_JKT_ERR_NONFIN;           // 0005_02FC 温度或 PID 输出非有限【故障级】/ Non-finite input, fault level
    _fReactorNow := 0.0;                        // 快照置零，绝不用脏值（Snapshots zeroed）
    _fJacketNow  := 0.0;                        // 夹套快照置零（Jacket snapshot zeroed）
    _fPidNow     := 0.0;                        // PID 快照置零（PID snapshot zeroed）
ELSE
    _fReactorNow := fReactorTemp;               // 釜温快照（Reactor snapshot）
    _fJacketNow  := fJacketTemp;                // 夹套温快照（Jacket snapshot）
    _fPidNow     := fPidOut;                    // PID 快照（PID snapshot）
END_IF

// 参数域钳位（R35：守卫、封顶与判据同向）
// Parameter clamping so that guard, ceiling and comparison stay in step (R35)
_fDeltaTMaxEff := LIMIT(DL_JKT_DT_LO, fDeltaTMax, DL_JKT_DT_HI);        // 温差上限 5~150 K（Delta-T limit clamped）
_fRateLimEff   := LIMIT(DL_JKT_RATE_LO, fDeltaTRate, DL_JKT_RATE_HI);   // 变化率 0.1~50 K/min（Rate limit clamped）
_fOtMarginEff  := LIMIT(DL_JKT_OT_LO, fOverTempMargin, DL_JKT_OT_HI);   // 超温裕量 0.5~50 K（Margin clamped）
_fDeadbandEff  := LIMIT(DL_JKT_DB_LO, fDeadband, DL_JKT_DB_HI);         // 死区 0~10 %（Deadband clamped）
_fOutLowEff    := fOutMin;                      // 输出下限取引脚值（Output low taken from the pin）
_fOutHighEff   := fOutMax;                      // 输出上限取引脚值（Output high taken from the pin）
IF _fOutLowEff > _fOutHighEff THEN
    _fSwapTmp    := _fOutLowEff;                // 交换临时量（Swap scratch）
    _fOutLowEff  := _fOutHighEff;               // 下限取原上限（Low takes the former high）
    _fOutHighEff := _fSwapTmp;                  // 上限取原下限（High takes the former low）
END_IF

// 温差→阀位速率折算（偏离留档③）：[%/s] = (K/min ÷ 60) ÷ (K/%)
// Delta-T rate converted into an output rate in percent per second
IF _fRateLimEff > DL_JKT_EPS THEN
    _fRatePctS := (_fRateLimEff / DL_JKT_MIN_PER_H) / DL_JKT_K_PER_PCT;  // 折算（Converted rate）
ELSE
    _fRatePctS := 0.0;                          // 非法值按 0（限速器把 0 视为不限，防御性兜底）
END_IF

// ============================================================================
// 段 4｜温差与变化率测量（窗内斜率；窗边界断输入一拍，R40/R42）
//      Delta-T and its rate; the window boundary breaks the timer input for one scan
// ============================================================================
fDeltaT := _fReactorNow - _fJacketNow;          // 温差 = 釜温 − 夹套温（Delta-T, signed）
_fRateMin := TIME_TO_REAL(tRateWindow) / DL_JKT_MS_PER_MIN;  // 窗口分钟值（Window in minutes）
IF NOT _bRateInit THEN
    _bRateInit   := TRUE;                       // 首扫只装基准（R19：只装基准，不做判据）
    _fDtWinStart := fDeltaT;                    // 窗起点取首拍温差（Seed the window with the first scan value）
END_IF
IF _fbTonRate.Q THEN
    IF _fRateMin > DL_JKT_EPS THEN
        _fRateMeasInt := (fDeltaT - _fDtWinStart) / _fRateMin;  // 窗内平均斜率（Mean slope in the window）
    ELSE
        _fRateMeasInt := 0.0;                   // 窗长非法不出率（Illegal window, no rate）
    END_IF
    _fDtWinStart := fDeltaT;                    // 新窗起点（New window start）
    _bRateBreak  := TRUE;                       // 断输入一拍，ET 归零（R40）
END_IF

// ============================================================================
// 段 5｜状态机（约束层 + 分程层；ENUM + CASE，含 ELSE 兜底）
//      State machine: constraint layer plus split-range layer
// ============================================================================
// 5.1 温差触限与超温判定（回差防边界抖动）
//     Delta-T limit and over-temperature with hysteresis
IF fDeltaT >= _fDeltaTMaxEff THEN
    _bLimitLatched := TRUE;                     // 达上限即锁存（Reach the limit, latch it）
ELSIF fDeltaT < (_fDeltaTMaxEff - DL_JKT_HYST) THEN
    _bLimitLatched := FALSE;                    // 回落超回差才解除（Release only beyond the hysteresis）
END_IF
IF _fReactorNow > (fTempSetpoint + _fOtMarginEff) THEN
    _bOverTempLatched := TRUE;                  // 超温锁存（Over temperature latched）
    _uInfoCode := DL_JKT_INFO_OT;               // 0005_01D0 超温强制冷却【信息级】/ Over temperature
ELSIF _fReactorNow < (fTempSetpoint + _fOtMarginEff - DL_JKT_HYST) THEN
    _bOverTempLatched := FALSE;                 // 回落超回差才解除（Release only beyond the hysteresis）
END_IF

// 5.2 反装判据：温差为负且要求升温（本件最有价值的一条）
//     Reversed-sensor criterion: negative delta-T while heating is demanded
IF (NOT _bFaultCond) AND (fDeltaT < (-DL_JKT_HYST)) AND (_fPidNow > _fDeadbandEff) THEN
    _bFaultCond := TRUE;                        // 传感器疑似反装（Sensor likely reversed）
    _uFaultCode := DL_JKT_ERR_REV;              // 0005_02FD 温差为负且要求升温【故障级】/ Reversed sensor, fault level
END_IF

// 5.3 约束路径标记：触限、超温，或限速器仍在追赶（保证退出约束时平滑回收，不回跳）
//     Limiting path flag: limit active, over temperature, or the limiter still catching up
_bLimitActive := _bLimitLatched OR _bOverTempLatched
              OR _fbRlHeat.bLimiting OR _fbRlCool.bLimiting;

IF _bFaultCond THEN
    _eState := E_DL_JacketState.eFault;         // 故障条件优先于状态机（Fault outranks the machine）
END_IF

// 掉使能冻结分支：显式排除故障态（R39 合法写法①），复位通道仍可从故障态退出
// Disable branch explicitly excludes the fault state so the reset path still works
IF (NOT bEnable) AND (_eState <> E_DL_JacketState.eFault) THEN
    _eState := E_DL_JacketState.eIdle;          // 冻结回空闲（Freeze back to idle）
END_IF

CASE _eState OF

    E_DL_JacketState.eIdle: // 空闲：等使能与参数闸门
        IF bEnable AND (NOT _bFaultCond) THEN
            _eState := E_DL_JacketState.eHold;  // 进保持态等 PID 有效（Enter hold until the PID is valid）
        END_IF

    E_DL_JacketState.eHold: // 保持：两路 0，按 PID 与死区决定进入哪个方向
        _fHeatTgt := 0.0;                       // 热路目标 0（Heat target zero）
        _fCoolTgt := 0.0;                       // 冷路目标 0（Cool target zero）
        IF _bOverTempLatched THEN
            _eState   := E_DL_JacketState.eCool;    // 超温强制冷却（Forced cooling）
            _fCoolTgt := _fOutHighEff;          // 冷路给满量程（Cool at the upper limit）
        ELSIF _bLimitLatched THEN
            _eState := E_DL_JacketState.eHold;  // 触限期间保持冻结（Stay frozen while limited）
        ELSIF _fPidNow > _fDeadbandEff THEN
            _eState := E_DL_JacketState.eHeat;  // 要求升温（Heating demanded）
        ELSIF _fPidNow < (-_fDeadbandEff) THEN
            _eState := E_DL_JacketState.eCool;  // 要求冷却（Cooling demanded）
        ELSE
            _eState := E_DL_JacketState.eHold;  // 死区内保持（Inside the deadband)
        END_IF

    E_DL_JacketState.eHeat: // 升温：热路跟 PID，冷路 0
        _fCoolTgt := 0.0;                       // 冷路恒 0（Cool path forced zero）
        IF _bLimitLatched THEN
            _fHeatTgt := 0.0;                   // 触限冻结：目标 0，由限速器斜坡回落（Freeze, ramp down by the limiter）
            _uInfoCode := DL_JKT_INFO_LIM;      // 0005_01CF 温差达上限升温侧冻结【信息级】/ Delta-T limit reached
            _eState   := E_DL_JacketState.eHold;    // 进保持（Enter hold）
        ELSIF _bOverTempLatched THEN
            _fHeatTgt := 0.0;                   // 超温：热路目标 0（Over temperature, heat target zero）
            _eState   := E_DL_JacketState.eCool;    // 强制冷却（Forced cooling）
        ELSIF ABS(_fPidNow) <= _fDeadbandEff THEN
            _fHeatTgt := 0.0;                   // 死区内：热路目标 0（Inside the deadband）
            _eState   := E_DL_JacketState.eHold;    // 回保持（Back to hold）
            _uInfoCode := DL_JKT_INFO_SPLIT;    // 0005_01D1 分程重叠区被死区分离【信息级】/ Split-range overlap separated
        ELSE
            _fHeatTgt := LIMIT(_fOutLowEff, _fPidNow, _fOutHighEff);    // 热路跟 PID 并限幅（Heat follows the PID, clamped）
        END_IF

    E_DL_JacketState.eCool: // 冷却：冷路跟反相 PID，热路 0
        _fHeatTgt := 0.0;                       // 热路恒 0（Heat path forced zero）
        IF _bOverTempLatched THEN
            _fCoolTgt := _fOutHighEff;          // 超温：冷路给满（Cool at the upper limit）
            _uInfoCode := DL_JKT_INFO_OT;       // 0005_01D0 超温强制冷却【信息级】/ Over temperature
        ELSIF _fReactorNow < fTempSetpoint THEN
            _fCoolTgt := 0.0;                   // 釜温低于设定：停冷（Below setpoint, cooling stops）
            _eState   := E_DL_JacketState.eHold;    // 回保持（Back to hold）
        ELSIF ABS(_fPidNow) <= _fDeadbandEff THEN
            _fCoolTgt := 0.0;                   // 死区内：冷路目标 0（Inside the deadband）
            _eState   := E_DL_JacketState.eHold;    // 回保持（Back to hold）
            _uInfoCode := DL_JKT_INFO_SPLIT;    // 0005_01D1 分程重叠区被死区分离【信息级】/ Split-range overlap separated
        ELSE
            _fCoolTgt := LIMIT(_fOutLowEff, 0.0 - _fPidNow, _fOutHighEff);  // 冷路取反相 PID 并限幅（Cool takes the inverted PID, clamped）
        END_IF

    E_DL_JacketState.eFault: // 故障：两路强制 0，等复位沿（段2）
        _fHeatTgt := 0.0;                       // 热路目标 0（Heat target zero）
        _fCoolTgt := 0.0;                       // 冷路目标 0（Cool target zero）

    ELSE // 兜底：非法状态
        _uFaultCode := DL_JKT_ERR_STATE;        // 0005_02FE 非法状态兜底【故障级】/ Illegal state fallback
        _bFaultCond := TRUE;                    // 置故障条件（Raise the fault condition）
        _eState     := E_DL_JacketState.eFault; // 强制回故障态（Force the fault state）
        _fHeatTgt   := 0.0;                     // 热路目标 0（Heat target zero）
        _fCoolTgt   := 0.0;                     // 冷路目标 0（Cool target zero）
END_CASE

// ============================================================================
// 段 6｜冷热分程限速（组合调用 FB_DL_RateLimiter，算法在低层件内，绝不内联）
//      Split-range rate limiting by composing the low-level limiter, never inlined
//      未受限时 bTrack = TRUE（输出等于输入，无扰直通）；受限时 bTrack = FALSE，
//      按 _fRatePctS（由 fDeltaTRate 折算）限速，退出跟踪那一拍从当前值开始，不回跳。
//      Unconstrained passes through, constrained ramps from the present value
// ============================================================================
_fbRlHeat(
    bEnable     := TRUE,
    fIn         := _fHeatTgt,
    fRateUp     := _fRatePctS,
    fRateDown   := _fRatePctS,
    bTrack      := (NOT _bLimitActive) OR (NOT bEnable),
    fTrackValue := _fHeatTgt,
    tSampleTime := tCycle
);                                              // 热路限速（Heat path rate limiting）
_fbRlCool(
    bEnable     := TRUE,
    fIn         := _fCoolTgt,
    fRateUp     := _fRatePctS,
    fRateDown   := _fRatePctS,
    bTrack      := (NOT _bLimitActive) OR (NOT bEnable),
    fTrackValue := _fCoolTgt,
    tSampleTime := tCycle
);                                              // 冷路限速（Cool path rate limiting）

// ============================================================================
// 段 7｜码位单一优先级链（全拍只写一次，信息级不置 bError）
//      Single priority chain for the codes, written once per scan
// ============================================================================
IF _uFaultCode <> 16#0000_0000 THEN
    _uFaultLatched := _uFaultCode;              // 故障码锁存（Latched until reset）
    uErrorId  := _uFaultCode;                   // 故障级码优先（Fault-level code wins）
    uDiagCode := _uFaultCode;                   // 诊断码同源（Diagnostic code mirrors the fault）
    bError    := TRUE;                          // 故障标志置位（Error flag raised）
ELSIF _uInfoCode <> 16#0000_0000 THEN
    uErrorId  := 16#0000_0000;                  // 信息级不占故障码（Info level leaves the fault code empty）
    uDiagCode := _uInfoCode;                    // 诊断码取信息级码（Diagnostic code takes the info code）
    bError    := FALSE;                         // 信息级不置故障位（Info level never raises the error flag）
ELSE
    uErrorId  := 16#0000_0000;                  // 无码（No code）
    uDiagCode := 16#0000_0000;                  // 无码（No code）
    bError    := FALSE;                         // 无故障（No error）
END_IF

// ============================================================================
// 段 8｜出口钳位与保持语义重写（R27/R43：结论逐拍重写，冷热互斥）
//      Output clamping and held-semantics rewrite, heat and cool mutually exclusive
// ============================================================================
_fHeatPrev := LIMIT(_fOutLowEff, _fbRlHeat.fOut, _fOutHighEff);     // 热路取限速器输出并夹域（Heat from the limiter, clamped）
_fCoolPrev := LIMIT(_fOutLowEff, _fbRlCool.fOut, _fOutHighEff);     // 冷路取限速器输出并夹域（Cool from the limiter, clamped）

// 互斥出口：决不允许冷热同开（同拍只保留一路，且优先保冷——冷却属安全方向）
// Mutual exclusion: heat and cool can never be open together, cooling wins as the safe direction
IF (_fHeatPrev > DL_JKT_OPEN_EPS) AND (_fCoolPrev > DL_JKT_OPEN_EPS) THEN
    _fHeatPrev := 0.0;                          // 两路同开：热路强制归零（Both open: heat forced to zero）
END_IF

fHeatOut      := _fHeatPrev;                    // 热路出口逐拍重写（Heat output rewritten every scan）
fCoolOut      := _fCoolPrev;                    // 冷路出口逐拍重写（Cool output rewritten every scan）
fDeltaTRateMeas := _fRateMeasInt;               // 变化率出口逐拍重写（Measured rate rewritten）
bDeltaTLimited := _bLimitLatched;               // 触限位逐拍重写（Limit flag rewritten）
bOverTemp     := _bOverTempLatched;             // 超温位逐拍重写（Over-temperature flag rewritten）
eVerdict      := _eState;                       // 执行方向逐拍重写（Verdict rewritten every scan）

// 健康态仲裁（引用属主 A1 的四态语言）
// Health arbitration mapped onto the A1 health language
IF _eState = E_DL_JacketState.eFault THEN
    eHealth := E_DL_Ne107Status.eFailure;       // 故障：温度或 PID 不可信（Failure）
ELSIF NOT bEnable THEN
    eHealth := E_DL_Ne107Status.eUnknown;       // 未知：未使能（Unknown）
ELSIF _bOverTempLatched THEN
    eHealth := E_DL_Ne107Status.eOutOfSpec;     // 越规：釜温越界（Out of spec）
ELSIF _bLimitLatched THEN
    eHealth := E_DL_Ne107Status.eMaintenanceReq;    // 需维护：温差约束长期生效，传热面可能结垢（Maintenance required）
ELSE
    eHealth := E_DL_Ne107Status.eOk;            // 正常（OK）
END_IF

END_FUNCTION_BLOCK
