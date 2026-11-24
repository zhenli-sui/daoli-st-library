(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ModbusPollMaster
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 通信调度功能块（Function Block · 轮询主站调度抽象层）
 * 作者     (Author)     : Daoli Library
 * 日期     (Date)       : 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（TON / F_TRIG），零厂商方言
 * 功能简介 (Function)   : 多从站轮询主站调度器（Modbus RTU 轮询节拍抽象层）。
 *                         按站表顺序轮询、单事务响应超时重试、成功/异常双计数器
 *                         台账、空表与全跳过保护、站表禁用跳过的自动回绕。本块
 *                         只做「调度」：决定「此刻该问哪个站、问什么地址区、失败
 *                         重试几次、超时怎么记账」，帧的构造、CRC 校验、字节收发、
 *                         串口/TCP 底层时序全部交由传输层实现。
 * 分层声明 (Layering)   : ① 本块不绑定任何具体串口库、不引用任何厂商驱动块；
 *                         ② 传输层经两个抽象方法 SendFrame / RecvFrame 由集成者
 *                         实现（推荐做法：EXTENDS 本块并覆盖 DoTransaction 作为
 *                         统一入口，在覆盖体内调用自家收发库，再复用本块的记账
 *                         与重试；亦可只覆盖 SendFrame / RecvFrame 两个帧级原语）；
 *                         ③ 基类默认实现为「抽象桩」：返回 FALSE 并锁故障码
 *                         0005_0290（传输层未实现），这是抽象层的合法形态，不是
 *                         漏填——未注入传输层时块不会静默假成功；
 *                         ④ 调度层零触碰帧内容：不解析功能码、不读写应答字节、
 *                         不做 CRC 运算。CRC-16/Modbus 的公开算法定义在本库已有
 *                         实现（见 DL_MathData 子库既有 CRC 计算函数），本块仅在
 *                         此注释说明「可作校验实现」，不 import、不调用、不内联。
 * 职责边界 (Scope)      : ① 不做站内数据解包与工程量换算（由上层按站表项自行
 *                         读取应答缓冲后处理）；② 不做主备链路切换与总线诊断
 *                         （后续轮次另立组件）；③ 不做写单寄存器/写多寄存器的
 *                         流程编排（功能码仅作透传字段，调度节拍与读写无关）。
 * 开源溯源 (Origin)     : 来源标签 codesys-forge-modbus（T1-4 开族续挖）。仅参考
 *                         CODESYS Forge 免费库 ModbusFB 公开文档页中「主站轮询 /
 *                         站表组织 / 超时重试 / 轮询间隔」的功能分类与参数域惯例，
 *                         以及「帧构造与校验归传输层」的分层语义；所据页面未显
 *                         式声明许可条款，故按最严口径处置：只借组织分类与参数
 *                         范围，零代码行复制。本块的枚举编号、状态机、站表结构、
 *                         台账口径与故障码位 100% 本库独立设计，clean-room 实现。
 * 公约遵循 (Convention) : 0.1/R19 首扫范式（IF (NOT _bInit)）；0.2/R21 bError 显式
 *                         排除信息级码；0.5/R7 定时器与边沿实例主体最前部无条件
 *                         刷新；0.6/R14 定时器语义参数变化断输入一拍；0.7/R15 故障
 *                         级锁存仅重建路径清码；0.9 出口默认值先赋；0.14 WHILE 带
 *                         防死锁计数器 + 数组访问先判上下界；0.16 阈值全常量化。
 * 红线自检 (Redline)    : 全局隔离 ✓（零全局变量表引用、零外部变量声明、零物理
 *                         地址字面记号）｜命名合规 ✓（b/n/u/f/t/a/st/e/fb/i 前缀
 *                         全覆盖）｜注释完整 ✓（声明行 100% 中英双语同行注释）｜
 *                         OOP 封装 ✓（内部状态全私有，传输层经抽象方法注入）｜
 *                         周期安全 ✓（TON / F_TRIG 实例无条件刷新，方法无跨周期
 *                         驻留）｜防御编程 ✓（索引判界、循环防死锁、重试上限、
 *                         ENUM + CASE + ELSE 兜底）｜可移植性 ✓（纯 IEC 61131-3）｜
 *                         终结符成对 ✓
 * 设计要点 (Key notes)  : ① 事务生命周期：eRequest 发起（一次性调用抽象方法）→
 *                         eWaitResp 轮询结果（ePending 等待、eDone 成功、
 *                         eTimeout/eFailed 失败）→ eSttUpdate 记账 → eNextStn。
 *                         传输层可为异步（返回 FALSE 且 eResult = ePending 表示
 *                         尚未收完），调度层的响应超时定时器是它的兜底下限。
 *                         ② 不因单站失败中断轮询：重试耗尽只累加该站异常计数并
 *                         继续下一站（台账留证，避免一站坏总线导致全线停摆）；
 *                         只有「传输层未实现」与「站表索引越界」才锁全局故障。
 *                         ③ 轮询间隔由 TON 闸门实现（eSttUpdate 后重新计时），
 *                         事务结束到下一次发起至少间隔 tPollInterval，防止从站
 *                         换向静默期被打断（RTU 帧间静默的工程近似）。
 *                         ④ 站表回绕：每次事务结束把索引 +1，寻找下一站时从当前
 *                         索引起最多检查 uStationCount 站（超过即回绕），全部
 *                         跳过则置信息级码并按间隔节流空转，不锁故障。
 *                         ⑤ 计数口径：uStatOk / uStatErr 累计在调用方持有的站表
 *                         项内（跨班不清零），本块自身不保存历史，重启即从站表
 *                         现值继续，便于 HMI 做长期台账。
 * 偏离留档 (Deviation)  : ① 规格建议故障码 0005_0290~0293 中 0293 未使用（站数
 *                         非法按钳位 + 信息级处置，不锁故障；理由：站数是可在线
 *                         修改的组态量，钳位比停机更符合现场），实际使用
 *                         0005_0290~0292 三条；
 *                         ② 传输层抽象未采用独立 INTERFACE 文件（理由：本库公约
 *                         0.18「一文件一 POU」，接口件须独立成 .st 且本泳道不
 *                         允许新增第 6 个文件；改为块内抽象方法三件套，语义等价：
 *                         基类桩返回 FALSE + 锁码，派生块覆盖实现）；
 *                         ③ 规格 VAR 段 bFirstScan 改名 _bInit（公约 0.1 统一命名）。
 * 故障码表 (Error codes) :
 *                         16#0005_0190【信息级】站数越界已钳位到 1 至 16
 *                         16#0005_0191【信息级】站表全部跳过，本轮无事务（按间隔节流）
 *                         16#0005_0192【信息级】单站重试耗尽，异常台账已累加
 *                         16#0005_0193【信息级】超时/间隔参数非法已兜底
 *                         16#0005_0290【故障级】传输层未实现（抽象方法桩未被覆盖）
 *                         16#0005_0291【故障级】站表索引越界（越界保护触发）
 *                         16#0005_0292【故障级】非法状态兜底（枚举越界）
 * 验收向量 (Acceptance) :
 *   V1 单站成功：站数 1、从站 1 功能码 3 → eRequest 发起一次，eWaitResp 得
 *      eDone → uStatOk +1、bDone 单拍、回到 eNextStn；
 *   V2 超时重试：传输层持续回 ePending → 响应超时定时器到期后 uActiveRetry
 *      逐次 +1，达 uMaxRetry 后该站 uStatErr +1 且轮询继续下一站（不锁故障）；
 *   V3 站表跳过：站 0 的 bSkip = TRUE → 首个事务直接落在站 1（索引回绕正确）；
 *      全部站跳过 → 信息级 0191，块按 tPollInterval 节流空转，bBusy FALSE；
 *   V4 抽象桩：未覆盖 DoTransaction / SendFrame / RecvFrame → 首次发起即锁
 *      0005_0290 并停轮询，bError TRUE（杜绝静默假成功）；
 *   V5 间隔节流：tPollInterval = 100 ms、任务 10 ms → 相邻两事务发起间隔
 *      不少于 100 ms（TON 闸门计时）；
 *   V6 禁用重建：bEnable 下降沿 → 队伍暂停且保持现场（站索引/计数不清零），
 *      再次使能从原索引继续，不重复打扰刚问过的站。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 09 · DL_Process Modbus 轮询调度件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 集成示例 (Integration guide)：
 *   1 定义派生块 FB_MyRtuMaster EXTENDS FB_DL_ModbusPollMaster，覆盖
 *     DoTransaction（VAR_IN_OUT stItem : ST_DL_PollItem），在覆盖体内调用自家
 *     串口收发块完成「组帧 + 发送 + 收帧 + CRC 校验」，并把结果写回本块事务
 *     上下文（成功回 eDone，超时回 eTimeout，异常码回 uExceptionCode）。
 *   2 上层每周期调用派生块实例，注入站表数组与调度参数：
 *      aPollTable[0].uSlaveAddr := 1; aPollTable[0].uFuncCode := 3;
 *      aPollTable[0].uStartAddr := 0; aPollTable[0].uQuantity := 16;
 *      fbPoll(uStationCount := 4, tRespTimeout := T#500MS, uMaxRetry := 3,
 *             tPollInterval := T#100MS, aPollTable := aPollTable);
 *   3 读台账：aPollTable[i].uStatOk / uStatErr 由本块维护，HMI 直接读结构体。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 站表项的功能码只是透传字段，本块不校验其合法性；上位填 0 或非法功能码
 *     时，从站会回异常码，表现为该站 uStatErr 持续上升，请查站表而不是本块。
 *   2 响应超时必须大于最慢从站的最长应答时间；填得过小会造成「其实成功但被
 *     判超时」的重复点名，从站可能因此回异常码（上一次未收完）。
 *   3 uMaxRetry = 0 表示不重试，一次失败即记账进下一站，适合「宁漏不拖」的
 *     快速巡检场景。
 *   4 站表全部 bSkip 时本块按间隔空转且 bBusy 恒 FALSE，这是正常状态，不是
 *     死机；检修期整线隔离时常被误判为故障。
 *   5 本块不做总线抢占仲裁：同一物理链路上不要挂两个本块实例，否则帧会交错。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PollState（归属 FB_DL_ModbusPollMaster，随本文件发布）
 * 含义: 轮询调度离散状态。数值步长 10 留空位，故障态 99 保证排序末位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_PollState :
(
    eIdle      := 0,     // 空闲：未使能或故障重建后待启动 / Idle: disabled or waiting for a rebuild
    eNextStn   := 10,    // 选下一站：按站表回绕寻找未跳过站，并受轮询间隔闸门约束 / Select next station with wrap and interval gating
    eRequest   := 20,    // 发起事务：一次性调用抽象方法 DoTransaction / Issue one transaction by calling DoTransaction
    eWaitResp  := 30,    // 等待应答：轮询传输层结果与响应超时定时器 / Wait for the transport result and the response timeout
    eSttUpdate := 40,    // 记账：成功/异常计数累加并产生单拍完成脉冲 / Accounting with a one-scan done pulse
    eFault     := 99     // 故障锁存：仅使能下降沿重建可退 / Fault latched, left only by the disable-edge rebuild
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MbTxnResult（归属 FB_DL_ModbusPollMaster，随本文件发布）
 * 含义: 单事务结果，由传输层回填。调度层只据此推进状态，不解析帧内容。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_MbTxnResult :
(
    ePending := 0,       // 传输中：尚未收完应答（异步传输层的等待态） / In progress, response not yet complete
    eDone    := 10,      // 事务成功：应答完整且通过传输层校验 / Success, a complete and validated response
    eTimeout := 20,      // 传输超时：传输层自身判超时 / Timeout reported by the transport layer
    eFailed  := 30       // 传输失败：校验错、异常码或链路错误 / Failure such as a check error, an exception or a link error
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_PollItem（归属 FB_DL_ModbusPollMaster，随本文件发布）
 * 用途: 站表项。由调用方持有并注入（VAR_IN_OUT 数组），本块只读写统计字段。
 * 说明: uFuncCode / uStartAddr / uQuantity 均为透传字段，本块不解析、不改写。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_PollItem :
STRUCT
    uSlaveAddr : USINT := 1;      // 从站地址（Slave address）[1~247]，0 与 248 以上为保留地址 / Reserved above 247 and at zero
    uFuncCode  : USINT := 3;      // 功能码（Function code），本块仅透传不解析 / Passed through, never parsed by this block
    uStartAddr : UINT := 0;       // 起始地址（Start address），寄存器区偏移，本块仅透传 / Register offset, passed through only
    uQuantity  : UINT := 1;       // 数量（Quantity），寄存器个数或线圈个数，本块仅透传 / Register or coil count, passed through only
    uStatOk    : UDINT := 0;      // 成功计数（Success counter）[次]，跨班累计由调用方清零 / Accumulated until the caller clears it
    uStatErr   : UDINT := 0;      // 异常计数（Error counter）[次]，重试耗尽即累加 / Incremented when the retries are exhausted
    bSkip      : BOOL := FALSE;   // 本站跳过（Skip this station），TRUE 时轮询回绕绕过本站 / TRUE makes the scan wrap past this station
END_STRUCT
END_TYPE

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_ModbusTxn（归属 FB_DL_ModbusPollMaster，随本文件发布）
 * 用途: 单事务上下文。调度层装填请求字段，传输层回填结果字段，双方以此交接。
 * 说明: 应答缓冲容量 256 字节为 Modbus RTU 最大帧长度（地址 + 功能码 + 数据 +
 *       CRC 的上限），调度层只保存不解读。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_ModbusTxn :
STRUCT
    uSlaveAddr     : USINT := 1;                        // 从站地址（Slave address）[1~247] / Slave address in the range one to 247
    uFuncCode      : USINT := 3;                        // 功能码（Function code），透传 / Passed-through function code
    uStartAddr     : UINT := 0;                         // 起始地址（Start address），透传 / Passed-through start address
    uQuantity      : UINT := 1;                         // 数量（Quantity），透传 / Passed-through quantity
    eResult        : E_DL_MbTxnResult := E_DL_MbTxnResult.ePending; // 事务结果（Transaction result），传输层回填 / Filled in by the transport layer
    uExceptionCode : USINT := 0;                        // 异常码（Exception code）[1~255]，0 = 无异常，传输层回填 / Zero means no exception
    uRxLen         : UINT := 0;                         // 应答字节数（Response length）[字节]，传输层回填 / Response length in bytes
    auRxFrame      : ARRAY[0..255] OF BYTE;             // 应答帧原始字节（Raw response frame）[字节]，容量 256，调度层不解读 / Raw bytes, never parsed here
    bAbort         : BOOL := FALSE;                     // 中止请求（Abort request），重试或切站时由调度层置位 / Set by the scheduler on retries
END_STRUCT
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ModbusPollMaster
 * 调用约定: 每个扫描周期无条件调用一次；站表与参数全部经引脚注入。
 * 抽象层形态: DoTransaction / SendFrame / RecvFrame 三个默认实现均为抽象桩
 *             （返回 FALSE 并锁 0005_0290），由派生块覆盖后落地真实传输。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ModbusPollMaster
VAR_INPUT
    bEnable       : BOOL;               // 调度使能（Scheduler enable），FALSE 时队列暂停并保持现场 / FALSE pauses the queue and keeps the context
    uStationCount : UINT := 4;          // 轮询站数（Station count）[站]，域 1~16，越界钳位 / Clamped to the range one to sixteen
    tRespTimeout  : TIME := T#500MS;    // 单事务响应超时（Response timeout）[ms]，域 >= 1 ms / At least one millisecond
    uMaxRetry     : UINT := 3;          // 超时重试上限（Retry limit）[次]，0 = 不重试 / Zero means no retry
    tPollInterval : TIME := T#100MS;    // 相邻事务最小间隔（Minimum poll interval）[ms]，0 = 不节流 / Zero disables the interval gate
END_VAR
VAR_OUTPUT
    bBusy          : BOOL;              // 有事务执行中（Transaction in progress）/ A transaction is running
    uActiveStation : UINT;              // 当前轮询站索引（Active station index）[索引 0~15] / Active station index in the range zero to fifteen
    uActiveRetry   : UINT;              // 当前站累计重试数（Active retry count）[次]，切站清零 / Cleared when the station advances
    bDone          : BOOL;              // 单站事务完成（Station transaction done），单拍脉冲（R25）/ One-scan pulse per station completion
    bError         : BOOL;              // 故障保持型（Fault latched），显式排除信息级码 / Latched fault flag, info codes excluded
    uErrorId       : UDINT;             // 故障码（Error code），0 = 无故障，段位 16#0005_xxxx / Error code, zero means no error
END_VAR
VAR_IN_OUT
    aPollTable    : ARRAY[0..DL_MB_MAX_STN-1] OF ST_DL_PollItem; // 轮询站表（Poll table），调用方持有 / Caller-owned poll table
END_VAR
VAR
    _eState       : E_DL_PollState := E_DL_PollState.eIdle; // 主状态机状态（Main state machine state）/ Main state machine state
    _bInit        : BOOL;               // 首扫完成标志（First-scan done flag），初值 FALSE / First-scan done flag, initial FALSE
    _uStnIdx      : UINT;               // 当前站索引（Current station index）[索引]，域 0~15 / Station index in the range zero to fifteen
    _uRetryCnt    : UINT;               // 重试计数（Retry counter）[次] / Retry counter
    _uStnCntEff   : UINT := 4;          // 生效站数（Effective station count）[站]，钳位后 / Effective station count after clamping
    _uStnTried    : UINT;               // 已检查站数（Stations examined）[站]，回绕寻找用 / Stations examined during the wrap search
    _uGuard       : UINT;               // 循环防死锁计数（Loop guard counter）[次]，上限 16 / Loop guard bounded by sixteen
    _bStationFound : BOOL;              // 找到可轮询站（Usable station found）/ A usable station was found
    _tRespEff     : TIME := T#500MS;    // 生效响应超时（Effective response timeout）[ms] / Effective response timeout [ms]
    _tGapEff      : TIME := T#100MS;    // 生效轮询间隔（Effective poll interval）[ms] / Effective poll interval [ms]
    _bGapActive   : BOOL;               // 间隔闸门激活（Interval gate armed），TRUE 时须等定时器到期 / The gate holds until the timer elapses
    _bGapBreak    : BOOL;               // 间隔定时器断输入一拍（Interval timer break），重新计时用（公约 0.6）/ One-scan break used to restart the timer
    _bGapFeed     : BOOL;               // 间隔定时器输入（Interval timer input），先算后喂（公约 0.5）/ Computed first and then fed to the timer
    _bRespBreak   : BOOL;               // 超时定时器断输入一拍（Timeout timer break），发起事务后重计时 / One-scan break after a request is issued
    _bRespFeed    : BOOL;               // 超时定时器输入（Timeout timer input），先算后喂（公约 0.5）/ Computed first and then fed to the timer
    _stTxn        : ST_DL_ModbusTxn;    // 事务上下文（Transaction context），与传输层交接 / Transaction context shared with the transport
    _bTxnOk       : BOOL;               // 本次事务成功（Transaction succeeded）/ Transaction succeeded flag
    _bTxnStub     : BOOL;               // 抽象方法桩未覆盖（Stub not overridden），TRUE 即锁故障 / TRUE when the abstract stub is still in place
    _bFaultLatch  : BOOL;               // 故障锁存（Fault latch），仅重建路径清除 / Fault latch, cleared only through the rebuild path
    _uErrInt      : UDINT;              // 故障级码寄存（Fault-level code register），锁存型 / Latched fault-level code register
    _uInfoCode    : UDINT;              // 本拍信息级码（Info code this scan），每拍重算 / Info code recomputed every scan
    _fbPollTick   : TON;                // 轮询间隔定时器（Poll interval timer），主周期无条件刷新 / Refreshed unconditionally every scan
    _fbRespWatch  : TON;                // 响应超时定时器（Response watchdog timer），主周期无条件刷新 / Refreshed unconditionally every scan
    _fbTrigDisable : F_TRIG;            // 使能下降沿（Enable falling edge），故障重建触发 / Triggers the disable-edge rebuild
END_VAR
VAR CONSTANT
    DL_MB_MAX_STN  : UINT := 16;        // 最大站数（Maximum station count）[站]，同时为站表长度 / Maximum station count, also the table length
    DL_MB_FRAME_MAX : UINT := 256;      // 最大帧长（Maximum frame length）[字节]，Modbus RTU 上限 / Modbus RTU frame limit
    DL_MAX_LOOP    : UINT := 16;        // 循环防死锁上限（Loop guard bound）[次]，等于站数上限 / Loop guard bound equal to the station limit
    DL_TIME_MIN    : TIME := T#1MS;     // 时间参数下限（Lower time bound）[ms]，兜底用 / Lower bound used when a time input is illegal
    DL_STN_MIN     : UINT := 1;         // 站数下限（Lower station bound）[站] / Lower bound of the station count
END_VAR

METHOD DoTransaction : BOOL
VAR_IN_OUT
    stItem : ST_DL_PollItem;           // 站表项（Poll item），只读意图，统计字段由主体维护 / Read-only intent, statistics maintained by the body
END_VAR
_stTxn.uSlaveAddr     := stItem.uSlaveAddr; // 装填从站地址（Fill the slave address）
_stTxn.uFuncCode      := stItem.uFuncCode;  // 装填功能码（Fill the function code）
_stTxn.uStartAddr     := stItem.uStartAddr; // 装填起始地址（Fill the start address）
_stTxn.uQuantity      := stItem.uQuantity;  // 装填数量（Fill the quantity）
_stTxn.eResult        := E_DL_MbTxnResult.ePending; // 结果置等待态（Result set to pending）
_stTxn.uExceptionCode := 0;                 // 异常码清零（Exception code cleared）
_stTxn.uRxLen         := 0;                 // 应答长度清零（Response length cleared）
IF SendFrame(stTxn := _stTxn) THEN
    IF RecvFrame(stTxn := _stTxn) THEN
        _stTxn.eResult := E_DL_MbTxnResult.eDone; // 收帧完成即置成功（A complete response marks success）
    END_IF
ELSIF NOT _bTxnStub THEN
    _stTxn.eResult := E_DL_MbTxnResult.eFailed; // 发送失败且非桩未覆盖（Send failure, not the stub case）
END_IF
DoTransaction := (_stTxn.eResult = E_DL_MbTxnResult.eDone); // 仅成功返回 TRUE（TRUE only on success）

(*------------------------------------------------------------------------------
 * 方法: SendFrame —— 帧级发送原语（抽象桩）。派生块覆盖后在体内完成组帧与发送。
 *      Method SendFrame - frame level transmit primitive, an abstract stub here.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD SendFrame : BOOL
VAR_IN_OUT
    stTxn : ST_DL_ModbusTxn;           // 事务上下文（Transaction context），承载请求字段与中止标志 / Carries the request fields and the abort flag
END_VAR
IF stTxn.bAbort THEN
    stTxn.eResult := E_DL_MbTxnResult.eFailed; // 已请求中止则不再发送（Aborted transactions are not transmitted）
    SendFrame     := FALSE;            // 未发送（Not transmitted）
ELSE
    _bTxnStub := TRUE;                 // 标记抽象桩未被覆盖（Mark the stub as not overridden）
    SendFrame := FALSE;                // 桩一律返回 FALSE（The stub always returns FALSE）
END_IF

(*------------------------------------------------------------------------------
 * 方法: RecvFrame —— 帧级接收原语（抽象桩）。派生块覆盖后在体内完成收帧与校验。
 *      Method RecvFrame - frame level receive primitive, an abstract stub here.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD RecvFrame : BOOL
VAR_IN_OUT
    stTxn : ST_DL_ModbusTxn;           // 事务上下文（Transaction context），承载结果字段回填 / Carries the result fields to be filled in
END_VAR
IF stTxn.bAbort THEN
    stTxn.eResult := E_DL_MbTxnResult.eFailed; // 已请求中止则不收帧（Aborted transactions are not received）
    RecvFrame     := FALSE;            // 未接收（Not received）
ELSE
    _bTxnStub := TRUE;                 // 标记抽象桩未被覆盖（Mark the stub as not overridden）
    RecvFrame := FALSE;                // 桩一律返回 FALSE（The stub always returns FALSE）
END_IF
    END_METHOD

// ============================================================================
// 段 1｜输出确定性默认值先赋（公约 0.9；R25 第一律：单拍标志每拍预清零）
//      Deterministic defaults first, one-scan flags pre-cleared every scan
// ============================================================================
bDone      := FALSE;                   // 完成脉冲预清零，仅 eSttUpdate 拍置位（Done pulse pre-cleared, set only in the update state）
bBusy      := FALSE;                   // 忙碌标志预清零（Busy flag pre-cleared）
_uInfoCode := 0;                       // 信息级码每拍重算（Info code recomputed every scan）

// ============================================================================
// 段 2｜首扫初始化（R19 范式）
//      First-scan initialization following the single legal R19 predicate
// ============================================================================
IF NOT _bInit THEN
    _bInit        := TRUE;             // 置首扫完成（First-scan done）
    _eState       := E_DL_PollState.eIdle; // 状态复位为空闲（State reset to idle）
    _uStnIdx      := 0;                // 站索引清零（Station index cleared）
    _uRetryCnt    := 0;                // 重试计数清零（Retry counter cleared）
    _bGapActive   := FALSE;            // 间隔闸门关闭（Interval gate disarmed）
    _stTxn.bAbort := FALSE;            // 事务中止标志清零（Transaction abort cleared）
    _bFaultLatch  := FALSE;            // 故障锁存清零（Fault latch cleared）
    _uErrInt      := 16#0000_0000;     // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜定时器与边沿实例无条件周期刷新（公约 0.5 / 0.6：入参先算后喂）
//      Unconditional refresh of timers and the edge instance
// ============================================================================
_fbTrigDisable(CLK := bEnable);        // 使能下降沿检测（Enable falling edge detection）

_bGapFeed := _bGapActive AND (NOT _bGapBreak); // 间隔定时器输入（Interval timer input）
_fbPollTick(IN := _bGapFeed, PT := _tGapEff);  // 间隔计时（Interval timing）
_bGapBreak := FALSE;                   // 断输入脉冲在实例调用后自清（Break pulse self-cleared after the call）

IF _fbPollTick.Q THEN
    _bGapActive := FALSE;              // 间隔已满，解除闸门（Gate released once the interval elapsed）
END_IF

_bRespFeed := (_eState = E_DL_PollState.eWaitResp) AND (NOT _bRespBreak); // 超时定时器输入（Timeout timer input）
_fbRespWatch(IN := _bRespFeed, PT := _tRespEff); // 响应超时计时（Response timeout timing）
_bRespBreak := FALSE;                  // 断输入脉冲自清（Break pulse self-cleared）

// ============================================================================
// 段 4｜参数钳位（站数 1~16、超时与间隔 >= 1 ms；越界只钳位并置信息级）
//      Parameter clamping, out-of-range values are clamped with info codes
// ============================================================================
IF uStationCount < DL_STN_MIN THEN
    _uStnCntEff := DL_STN_MIN;         // 站数下限钳位（Clamped to the lower bound）
    _uInfoCode  := 16#0005_0190;       // 0005_0190 站数越界已钳位【信息级】（Station count clamped, info level）
ELSIF uStationCount > DL_MB_MAX_STN THEN
    _uStnCntEff := DL_MB_MAX_STN;      // 站数上限钳位（Clamped to the upper bound）
    _uInfoCode  := 16#0005_0190;       // 0005_0190 站数越界已钳位【信息级】（Station count clamped, info level）
ELSE
    _uStnCntEff := uStationCount;      // 合法站数直通（Valid station count passed through）
END_IF

IF tRespTimeout < DL_TIME_MIN THEN
    _tRespEff  := DL_TIME_MIN;         // 超时下限兜底（Timeout falls back to the lower bound）
    _uInfoCode := 16#0005_0193;        // 0005_0193 超时/间隔参数非法已兜底【信息级】（Time parameter clamped, info level）
ELSE
    _tRespEff := tRespTimeout;         // 合法超时直通（Valid timeout passed through）
END_IF

IF tPollInterval = T#0MS THEN
    _tGapEff   := T#0MS;               // 间隔 0 = 不节流，定时器立即到期（Zero interval disables the gate, the timer expires at once）
    _uInfoCode := 16#0005_0193;        // 0005_0193 间隔参数为 0 已按不节流处置【信息级】（Zero interval treated as no gating, info level）
ELSE
    _tGapEff := tPollInterval;         // 合法间隔直通（Valid interval passed through）
END_IF

// ============================================================================
// 段 5｜站索引越界保护（防御性：正常流程不可达，纯兜底）
//      Station index guard, unreachable in the normal flow
// ============================================================================
IF _uStnIdx > DL_MB_MAX_STN THEN
    _bFaultLatch := TRUE;              // 索引越界锁故障（Out-of-range index latches a fault）
    _uErrInt     := 16#0005_0291;      // 0005_0291 站表索引越界【故障级】（Station index out of range, fault level）
    _uStnIdx     := 0;                 // 索引强制回零自愈（Index forced back to zero）
ELSIF _uStnIdx = DL_MB_MAX_STN THEN
    _uStnIdx := 0;                     // 恰在上界即回绕，属正常（Wrapping at the bound is the normal path）
END_IF

// ============================================================================
// 段 6｜主状态机（ENUM + CASE + ELSE 兜底；故障重建走使能下降沿）
//      Main state machine with mandatory ELSE fallback and a disable-edge rebuild
// ============================================================================
CASE _eState OF

    E_DL_PollState.eIdle: // 空闲：等使能（Idle, waiting for enable）
        IF _fbTrigDisable.Q THEN
            _bFaultLatch := FALSE;     // 下降沿重建：清故障锁存（Rebuild clears the fault latch）
            _uErrInt     := 16#0000_0000; // 故障码清零（Fault code cleared）
            _uRetryCnt   := 0;         // 重试计数清零（Retry counter cleared）
        END_IF
        IF bEnable AND (NOT _bFaultLatch) THEN
            _bGapActive := FALSE;      // 起动首事务不节流（The first transaction is not gated）
            _uRetryCnt  := 0;          // 重试计数清零（Retry counter cleared）
            _eState     := E_DL_PollState.eNextStn; // 进选站态（Enter the station selection state）
        END_IF

    E_DL_PollState.eNextStn: // 选下一站：回绕寻找 + 间隔闸门（Select next station with wrap and gating）
        IF (NOT bEnable) OR _bFaultLatch THEN
            _eState := E_DL_PollState.eIdle; // 使能撤销或故障即回空闲（Disabled or faulty returns to idle）
        ELSIF (NOT _bGapActive) OR _fbPollTick.Q THEN
            _bStationFound := FALSE;   // 站发现标志预清零（Station found flag pre-cleared）
            _uStnTried     := 0;       // 已检查站数清零（Stations examined cleared）
            _uGuard        := 0;       // 循环守卫清零（Loop guard cleared）
            WHILE (_uStnTried < _uStnCntEff) AND (_uGuard < DL_MAX_LOOP) AND (NOT _bStationFound) DO
                _uGuard    := _uGuard + 1;      // 循环守卫递增，防死锁（Guard incremented to prevent a dead loop）
                _uStnTried := _uStnTried + 1;   // 已检查站数递增（Stations examined incremented）
                IF _uStnIdx >= _uStnCntEff THEN
                    _uStnIdx := 0;              // 回绕到首站（Wrap back to the first station）
                END_IF
                IF NOT aPollTable[_uStnIdx].bSkip THEN
                    _bStationFound := TRUE;     // 找到可用站（Usable station found）
                ELSE
                    _uStnIdx := _uStnIdx + 1;   // 跳过本站，索引后移（Skip this station and advance）
                END_IF
            END_WHILE
            IF _bStationFound THEN
                _uRetryCnt  := 0;              // 新站重试计数清零（Retry counter cleared for the new station）
                _bRespBreak := TRUE;           // 超时定时器下拍从零开始（Timeout timer restarts next scan）
                _eState     := E_DL_PollState.eRequest; // 进发起态（Enter the request state）
            ELSE
                _uInfoCode  := 16#0005_0191;   // 0005_0191 站表全部跳过【信息级】（All stations skipped, info level）
                _bGapActive := TRUE;           // 按间隔节流空转（Idle pacing through the interval gate）
                _bGapBreak  := TRUE;           // 间隔定时器重新计时（Interval timer restarted）
            END_IF
        END_IF

    E_DL_PollState.eRequest: // 发起事务：一次性调用抽象方法（Issue one transaction）
        _stTxn.uSlaveAddr     := aPollTable[_uStnIdx].uSlaveAddr; // 透传从站地址（Pass the slave address through）
        _stTxn.uFuncCode      := aPollTable[_uStnIdx].uFuncCode;  // 透传功能码（Pass the function code through）
        _stTxn.uStartAddr     := aPollTable[_uStnIdx].uStartAddr; // 透传起始地址（Pass the start address through）
        _stTxn.uQuantity      := aPollTable[_uStnIdx].uQuantity;  // 透传数量（Pass the quantity through）
        _stTxn.eResult        := E_DL_MbTxnResult.ePending;       // 结果置等待态（Result set to pending）
        _stTxn.uExceptionCode := 0;                               // 异常码清零（Exception code cleared）
        _stTxn.uRxLen         := 0;                               // 应答长度清零（Response length cleared）
        _stTxn.bAbort         := FALSE;                           // 中止标志清零（Abort cleared）
        _bTxnStub             := FALSE;                           // 桩标志预清零（Stub flag pre-cleared）
        _bTxnOk               := DoTransaction(stItem := aPollTable[_uStnIdx]); // 抽象方法调用，每拍至多一次（At most one call per scan）
        _bRespBreak           := TRUE;                            // 超时定时器下拍从零开始（Timeout timer restarts next scan）
        IF _bTxnStub THEN
            _bFaultLatch := TRUE;        // 传输层未实现即锁故障（A missing transport latches a fault）
            _uErrInt     := 16#0005_0290; // 0005_0290 传输层未实现【故障级】（Transport not implemented, fault level）
            _eState      := E_DL_PollState.eFault;
        ELSE
            _eState := E_DL_PollState.eWaitResp; // 进等待应答态（Enter the waiting state）
        END_IF

    E_DL_PollState.eWaitResp: // 等待应答：结果枚举与超时定时器双判（Wait on the result and the watchdog）
        IF (_stTxn.eResult = E_DL_MbTxnResult.eDone) AND (_stTxn.uRxLen <= DL_MB_FRAME_MAX) THEN
            _bTxnOk := TRUE;             // 事务成功且帧长在容量内（Success with a length inside the buffer capacity）
            _eState := E_DL_PollState.eSttUpdate; // 进记账态（Enter the accounting state）
        ELSIF _stTxn.uRxLen > DL_MB_FRAME_MAX THEN
            _stTxn.bAbort := TRUE;       // 帧长越界即中止（Abort on an over-long frame）
            _bTxnOk := FALSE;            // 帧长越界判失败，不再重试（Over-long frame fails without a retry）
            _eState := E_DL_PollState.eSttUpdate; // 进记账态（Enter the accounting state）
        ELSIF (_stTxn.eResult = E_DL_MbTxnResult.eTimeout) OR
              (_stTxn.eResult = E_DL_MbTxnResult.eFailed) OR _fbRespWatch.Q THEN
            _stTxn.bAbort := TRUE;       // 通知传输层中止本事务（Ask the transport to abort）
            IF _uRetryCnt < uMaxRetry THEN
                _uRetryCnt := _uRetryCnt + 1;   // 重试计数累加（Retry counter incremented）
                _eState    := E_DL_PollState.eRequest; // 重新发起（Reissue the transaction）
            ELSE
                _bTxnOk := FALSE;        // 重试耗尽判失败（Retries exhausted, marked as failed）
                _eState := E_DL_PollState.eSttUpdate; // 进记账态（Enter the accounting state）
            END_IF
        END_IF

    E_DL_PollState.eSttUpdate: // 记账：台账累加 + 单拍完成脉冲 + 推进站索引（Accounting and advance）
        IF _bTxnOk THEN
            aPollTable[_uStnIdx].uStatOk := aPollTable[_uStnIdx].uStatOk + 1; // 成功计数累加（Success counter incremented）
        ELSE
            aPollTable[_uStnIdx].uStatErr := aPollTable[_uStnIdx].uStatErr + 1; // 异常计数累加（Error counter incremented）
            _uInfoCode := 16#0005_0192; // 0005_0192 单站重试耗尽【信息级】（Station retries exhausted, info level）
        END_IF
        bDone       := TRUE;           // 单站完成单拍脉冲，本拍不再清除（One-scan done pulse, never cleared in the same scan）
        _uRetryCnt  := 0;              // 切站重试计数清零（Retry counter cleared on the station change）
        IF (_uStnIdx + 1) >= _uStnCntEff THEN
            _uStnIdx := 0;             // 到表尾即回绕首站（Wrap to the first station at the table end）
        ELSE
            _uStnIdx := _uStnIdx + 1;  // 索引后移到下一站（Advance to the next station）
        END_IF
        _bGapActive := TRUE;           // 启用间隔闸门（Arm the interval gate）
        _bGapBreak  := TRUE;           // 间隔定时器重新计时（Interval timer restarted）
        _eState     := E_DL_PollState.eNextStn; // 回选站态（Back to the selection state）

    E_DL_PollState.eFault: // 故障锁存：停轮询，保持现场（Fault latched, polling stopped）
        IF _fbTrigDisable.Q THEN
            _bFaultLatch := FALSE;     // 使能下降沿重建（Rebuild on the enable falling edge）
            _uErrInt     := 16#0000_0000; // 故障码清零（Fault code cleared）
            _uRetryCnt   := 0;         // 重试计数清零（Retry counter cleared）
            _eState      := E_DL_PollState.eIdle; // 回空闲（Back to idle）
        END_IF

    ELSE
        _bFaultLatch := TRUE;          // 非法状态兜底锁存（Illegal state latched）
        _uErrInt     := 16#0005_0292;  // 0005_0292 非法状态兜底【故障级】（Illegal state fallback, fault level）
        _eState      := E_DL_PollState.eFault; // 进故障态（Enter the fault state）
END_CASE

// ============================================================================
// 段 7｜出口映射（忙碌派生、活动站索引、重试数、故障级码优先透出）
//      Outlet mapping with fault-level codes taking priority over info codes
// ============================================================================
bBusy          := (_eState = E_DL_PollState.eRequest) OR (_eState = E_DL_PollState.eWaitResp); // 忙碌派生（Busy derived form）
uActiveStation := _uStnIdx;            // 活动站索引出口（Active station index outlet）
uActiveRetry   := _uRetryCnt;          // 活动重试数出口（Active retry count outlet）
bError         := _bFaultLatch OR (_eState = E_DL_PollState.eFault); // 故障派生，显式排除信息级（Fault derived, info codes excluded）
IF bError THEN
    uErrorId := _uErrInt;              // 故障级码优先（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;            // 无故障透出本拍信息级码（Transient info code exposed）
END_IF

(*------------------------------------------------------------------------------
 * 方法: DoTransaction —— 抽象入口：装填上下文、调用帧级原语、返回成功与否。
 *      Method DoTransaction - abstract entry assembling the context and calling
 *      the frame level primitives. Derived blocks override this method.
 *------------------------------------------------------------------------------*)


END_FUNCTION_BLOCK
