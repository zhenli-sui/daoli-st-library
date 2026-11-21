(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PollTempBank
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 工艺采集 · 温控器轮询采集行
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG）
 * 功能描述 (Function)   : 一条温控器采集行——对最多 8 台温控器轮询采集过程值与设定值，
 *                         做工程量换算、有效域判定、滑动均值、偏差与最差通道定位，
 *                         输出通道质量掩码与在线台数，连续失败通道自动摘除并自动恢复。
 * 分层声明 (Layering)   : ① 调度归既有轮询主站件（本件内嵌其一个实例，只注入站表与
 *                         节拍参数，不重写调度、重试与超时逻辑）；② 滤波归既有滑动均值件
 *                         （本件为八个通道各持一个实例，只给样本与采样允许）；
 *                         ③ 本件只做「行级编排加通道质量」，不做温控闭环——设定值下发、
 *                         自整定、超温切断属温控器内部或工艺层职责，本件只读不写。
 * 传输层说明 (Transport) : 内嵌的调度实例以库内基类形态声明，其帧收发为抽象桩。生产部署
 *                         时必须由具备真实串口或网口收发的派生块替换该声明，否则调度层会
 *                         锁「传输层未实现」故障、全部通道因轮询不成功而逐台摘除。这一
 *                         失败是**可观测的显式失败**（质量掩码全置位、在线台数为零），
 *                         不会静默给出假温度，故不在本件内把它翻译成故障码。
 * 保持策略 (Hold)       : 坏通道的温度保持上次有效值并在质量掩码里标记，**绝不**用零或
 *                         上限值填充——零摄氏度在锂电烘箱、冷库等场景是合法工况值，用零
 *                         填充会掩盖真实故障（与既有温度扫描件同一纪律）。
 * 摘除与恢复 (Drop)     : 连续失败达到阈值即摘除并置信息码；摘除后仍继续轮询该通道，
 *                         连续两拍有效即自动恢复。若不继续轮询，被摘除的通道永远拿不到
 *                         有效数据、也就永远无法恢复，这是摘除策略必须配对的另一半。
 * 职责边界 (Scope)      : 不做写设定值（只采集）、不做地址表编辑器的校验（站表按默认值
 *                         填充，机型差异由调用方改表）、不做历史归档与报警分级。
 * 开源溯源 (Origin)     : 来源标签 roadmap-p0 加 t1-4。原创实现（参考 ROADMAP §13.6 P0
 *                         条目「温控器轮询采集行（复用轮询主站与滑动均值）」的需求定义，
 *                         以及 CODESYS Forge ModbusFB 族「调度与传输分层」的组织方式）。
 *                         仅借组织方式与参数域，编排逻辑、通道质量掩码、摘除与恢复策略、
 *                         枚举、状态机与全部码位 100% 本库独立设计，clean-room 实现，
 *                         不复制任何示例代码与注释。
 * 依赖     (Depends)    : ST_DL_PollItem 与 FB_DL_ModbusPollMaster（DL_Process 既有件，
 *                         本件只引用不声明）；FB_DL_MovingAverage（DL_MathData 既有件）；
 *                         Standard.library: R_TRIG
 * 故障码表 (Error codes):
 *   16#0005_0108【信息级】台数、窗口长度或摘除阈值越界已钳位
 *   16#0005_0109【信息级】通道连续失败达到阈值已摘除（仍继续轮询以便自动恢复）
 *   16#0005_010A【信息级】滤波窗口为 1，均值等于瞬时值（无滤波能力）
 *   16#0005_0207【故障级】换算比例非正，量纲错且含零乘隐患（锁存）
 *   16#0005_0208【故障级】有效温度域为空，任何读数都会被判无效（锁存）
 *   16#0005_0209【故障级】非法状态兜底（锁存，终端安全态）
 * 码位占用 (Slot)       : 信息级 0108 / 0109 / 010A；故障级 0207 / 0208 / 0209。
 *                         全部落在 R12 本件分配块内，无跨块借用、无段外哨兵值。
 * 拍序纪律 (Cycle order) :
 *   ① ePhase        ：段 7 状态机（唯一位移点），段 8 复位分支是唯一回退点
 *   ② 三个生效参数   ：段 4 单点钳位，后续所有数组访问与循环上限都取这三个生效值
 *   ③ 质量掩码       ：段 6 装配后整值写出，与本拍在线台数、最差通道同拍一致
 *   ④ uErrorId       ：段 9 单一优先级链，全拍只写一次
 * 验收向量 (Acceptance) :
 *   V1 单台正常：台数 1、过程值 253、设定值 250、比例 0.1 → 温度 25.3、设定 25.0、
 *      偏差 0.3、质量掩码为零、在线 1 台
 *   V2 超域：第 2 台过程值 3200（换算 320.0 高于上限 200）→ 该通道无效、温度保持、
 *      质量掩码位 1 置位、连续失败计数 1
 *   V3 摘除：第 3 台连续三拍轮询失败、阈值为 3 → 第 3 拍摘除、质量掩码位 2 置位、
 *      在线台数减 1、码 0109
 *   V4 最差通道：两通道偏差分别负 3.5 与正 4.2 → 最差通道号为 4、最差偏差正 4.2
 *   V5 量纲错：比例为 0 → 故障位置位、码 0207、各通道温度保持
 * 偏离留档 (Deviation)  :
 *   ① 规格第 3.18 节正文提到「评估相」，但 §2.1 的枚举只有三成员。本件按枚举实现，
 *      把逐通道评估并入轮询相的固定段完成，不新增枚举成员，避免枚举与码表、文档三处
 *      不一致。
 *   ② 规格要求「内嵌调度实例」，但库内调度基类的传输层为抽象桩，无法在本文件内以派生块
 *      替换其声明。本件保留基类实例并在头注释写明部署要求，把「传输层未就绪」表现为
 *      质量掩码全坏这一可观测结果，而不是伪造成功。
 *   ③ 参数钳位放在状态机之前的固定段（而非待机相），理由：台数决定站表填充与循环上限，
 *      必须每拍先于任何数组访问生效，否则上电首拍会用未钳位值访问数组。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（R12 · 泳道 C · 温控器轮询采集行 P0 件）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_TempBankPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block
 *-----------------------------------------------------------------------------*)
TYPE E_DL_TempBankPhase :
(
    eIdle    := 0,   // 待机：未使能或参数闸门未过，输出保持 / Idle, disabled or the gate has not passed
    ePolling := 10,  // 轮询：调度实例推进轮询，同时做逐通道换算与质量判定 / Polling with per-channel evaluation
    eFault   := 99   // 故障：量纲错、有效域为空或非法状态，需复位退出 / Fault, needs a reset to leave
);
END_TYPE

FUNCTION_BLOCK FB_DL_PollTempBank
VAR_INPUT
    bEnable        : BOOL;                              // 使能，FALSE 时暂停轮询并保持输出 [-] / Enable, polling paused and outputs held while FALSE
    bReset         : BOOL;                              // 复位故障与摘除状态，上升沿有效 [-] / Rising edge clears the fault and the drop state
    nDeviceCount   : INT := 4;                          // 温控器台数 [台]，有效域 1 到 8 / Device count, one to eight
    anSlaveAddr    : ARRAY[1..8] OF USINT;              // 各台从站地址 [1 到 247] / Slave address per device
    auPvRaw        : ARRAY[1..8] OF INT;                // 各台过程值原始寄存器，由传输层写入 [原始码] / Raw process values written by the transport
    auSvRaw        : ARRAY[1..8] OF INT;                // 各台设定值原始寄存器 [原始码] / Raw setpoints
    abPollOk       : ARRAY[1..8] OF BOOL;               // 各台本次轮询成功标志 [-] / Per-device poll success flags
    fScaleGain     : REAL := 0.1;                       // 原始码到温度的比例 [摄氏度每码]，域大于 0 / Raw to temperature gain, must exceed zero
    fScaleOffset   : REAL := 0.0;                       // 零点偏移 [摄氏度] / Zero offset in degrees Celsius
    fRangeMin      : REAL := -50.0;                     // 有效温度下限 [摄氏度] / Valid temperature lower bound
    fRangeMax      : REAL := 200.0;                     // 有效温度上限 [摄氏度] / Valid temperature upper bound
    nFilterLen     : INT := 8;                          // 滑动均值窗口长度 [拍]，有效域 1 到 32 / Moving average window, one to thirty-two
    nDropAfterFails: INT := 3;                          // 连续失败多少次摘除通道 [次]，有效域 1 到 10 / Failures before dropping a channel
END_VAR
VAR_OUTPUT
    afTempC        : ARRAY[1..8] OF REAL;               // 各台温度 [摄氏度]，坏通道保持上次有效值 / Temperature per device, bad channels hold the last value
    afSetpointC    : ARRAY[1..8] OF REAL;               // 各台设定值 [摄氏度] / Setpoint per device
    afDeviation    : ARRAY[1..8] OF REAL;               // 各台偏差，过程值减设定值 [摄氏度] / Deviation, process minus setpoint
    afTempAvg      : ARRAY[1..8] OF REAL;               // 各台滑动均值 [摄氏度] / Per-device moving average
    auCommFailCnt  : ARRAY[1..8] OF UINT;               // 各台连续失败次数，饱和到上限 [次] / Consecutive failure counter per device, saturated
    uQualityMask   : WORD;                              // 通道坏质量掩码，位 n 减一 对应第 n 台 [位串] / Bad channel mask, bit n minus one is device n
    nOnlineCount   : INT;                               // 在线台数 [台] / Online device count
    nWorstIdx      : INT;                               // 偏差绝对值最大的在线通道号，0 表示无 [通道号] / Channel with the largest absolute deviation
    fWorstDev      : REAL;                              // 该通道的有符号偏差值 [摄氏度] / Signed deviation of that channel
    bError         : BOOL;                              // 故障级锁存，仅 0207 至 0209 置位 [-] / Latched fault, only fault level codes set it
    uErrorId       : UDINT;                             // 事件码，0 表示无事件 [代码] / Event code, zero means none
    eState         : E_DL_TempBankPhase;                // 主状态机当前相位 [-] / Current phase of the main state machine
END_VAR
VAR_IN_OUT
    aPollTable     : ARRAY[0..15] OF ST_DL_PollItem;    // 轮询站表，由内嵌调度实例持有并更新统计 [-] / Poll table owned by the embedded scheduler
END_VAR
VAR
    fbPoll         : FB_DL_ModbusPollMaster;            // 内嵌轮询调度实例，主周期无条件调用 / Embedded poll scheduler, called unconditionally
    afbAvg         : ARRAY[1..8] OF FB_DL_MovingAverage; // 逐通道滑动均值实例，主周期无条件全量调用 / Per-channel moving average instances
    fbTrigReset    : R_TRIG;                            // 复位沿检测，主周期无条件刷新 [-] / Reset edge detector, refreshed unconditionally
    ePhase         : E_DL_TempBankPhase := E_DL_TempBankPhase.eIdle; // 内部相位，对外经 eState 输出 [-] / Internal phase exported as eState
    bInit          : BOOL := FALSE;                     // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    bFaultLatch    : BOOL;                              // 故障锁存，仅复位分支清除 [-] / Fault latch, cleared by the reset path only
    uErrInt        : UDINT;                             // 故障级码寄存，锁存型 [代码] / Latched fault level code register
    uInfoCode      : UDINT;                             // 本拍信息级码，每拍重算 [代码] / Info level code recomputed every scan
    nDevUse        : INT := 1;                          // 生效台数，钳位后 [台] / Effective device count after clamping
    nFilterUse     : INT := 1;                          // 生效窗口长度，钳位后 [拍] / Effective window length after clamping
    nDropUse       : INT := 1;                          // 生效摘除阈值，钳位后 [次] / Effective drop threshold after clamping
    fGainUse       : REAL := 1.0;                       // 生效换算比例 [摄氏度每码] / Effective gain
    bEval          : BOOL;                              // 本拍执行通道评估 [-] / Evaluation enabled flag of this scan
    bDropEvent     : BOOL;                              // 本拍有通道被摘除 [-] / A channel was dropped this scan
    fVal           : REAL;                              // 单通道温度 [摄氏度] / Single channel temperature
    fSp            : REAL;                              // 单通道设定值 [摄氏度] / Single channel setpoint
    fDevAbs        : REAL;                              // 偏差绝对值 [摄氏度] / Absolute deviation
    fWorstTmp      : REAL;                              // 最差偏差绝对值暂存 [摄氏度] / Worst absolute deviation temporary
    uQBuild        : WORD;                              // 质量掩码装配 [位串] / Quality mask under assembly
    nOnline        : INT;                               // 在线计数 [台] / Online counter
    nWorst         : INT;                               // 最差通道号 [通道号] / Worst channel number
    abOkTmp        : ARRAY[1..8] OF BOOL;               // 各通道本拍有效标志 [-] / Per-channel validity of this scan
    abDropped      : ARRAY[1..8] OF BOOL;               // 通道已摘除标志 [-] / Channel dropped flags
    anRecover      : ARRAY[1..8] OF INT;                // 摘除后连续有效拍数 [拍] / Consecutive valid scans after a drop
    bValFin        : BOOL;                              // 换算值有限标志 [-] / Finite converted value flag
    nGuard         : DINT;                              // 循环守卫计数 [次]，上限常量化 / Loop guard counter with a constant bound
    i              : INT;                               // 通道索引 [1..8] / Channel loop index
    k              : INT;                               // 站表索引 [0..15] / Poll table loop index
END_VAR
VAR CONSTANT
    DL_DEV_MAX     : INT := 8;                          // 温控器台数上限 [台] / Device count limit
    DL_FILT_MAX    : INT := 32;                         // 滤波窗口上限 [拍] / Window length limit
    DL_DROP_MAX    : INT := 10;                         // 摘除阈值上限 [次] / Drop threshold limit
    DL_TABLE_MAX   : INT := 16;                         // 站表长度 [项] / Poll table length
    DL_FAIL_MAX    : UINT := 9999;                      // 连续失败计数饱和值 [次] / Failure counter saturation
    DL_MASK_ONE    : WORD := 16#0001;                   // 单通道基准位 [位串] / Single channel base bit
    DL_MASK_NONE   : WORD := 16#0000;                   // 全零掩码基准 [位串] / All zero mask reference
    DL_GAIN_MIN    : REAL := 1.0E-6;                    // 比例最小正值 [摄氏度每码] / Minimum positive gain
    DL_GAIN_SAFE   : REAL := 1.0;                       // 比例非法时的兜底值 [摄氏度每码] / Safe gain used when the input is illegal
    DL_TEMP_MAX    : REAL := 1.0E6;                     // 温度量级上限，超出视为非有限 [摄氏度] / Temperature magnitude bound
    DL_GUARD_MAX   : DINT := 64;                        // 循环守卫上限 [次] / Loop guard bound
    DL_RECOVER_NEED: INT := 2;                          // 自动恢复所需的连续有效拍数 [拍] / Valid scans required for an automatic recovery
    DL_FUNC_READ   : USINT := 3;                        // 读保持寄存器功能码 [功能码] / Read holding registers function code
    DL_REG_QTY     : UINT := 2;                         // 每站连续读两个寄存器，过程值与设定值 [个] / Two registers per station
    DL_REG_START   : UINT := 0;                         // 站表起始地址 [寄存器地址] / Station start address
    DL_RESP_TO     : TIME := T#500MS;                   // 单事务响应超时 [毫秒] / Per-transaction response timeout
    DL_POLL_GAP    : TIME := T#50MS;                    // 相邻事务最小间隔 [毫秒] / Minimum poll interval
    DL_RETRY_MAX   : UINT := 2;                         // 超时重试上限 [次] / Retry limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出确定性默认值（单拍与评估缓冲每拍预清零，R25 第一律）
 *      Deterministic defaults first, evaluation buffers pre-cleared every scan
 *-----------------------------------------------------------------------------*)
uInfoCode  := 16#0000_0000;                     // 信息级码每拍重算（Info code recomputed every scan）
nGuard     := 0;                                // 循环守卫清零（Loop guard cleared）
bDropEvent := FALSE;                            // 摘除事件标志预清零（Drop event flag pre-cleared）
bEval      := bEnable AND (ePhase = E_DL_TempBankPhase.ePolling); // 评估使能取上一拍相位（Evaluation enabled from the previous phase）
FOR i := 1 TO DL_DEV_MAX DO
    abOkTmp[i] := FALSE;                        // 本拍有效标志预清零，未轮询时不采样（No sampling while the phase is not polling）
END_FOR

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（红线：实例在 CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据取非）
 *      First-scan initialisation following the single legal pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR i := 1 TO DL_DEV_MAX DO
        afTempC[i]       := 0.0;                // 温度出口清零（Temperature outlet cleared）
        afSetpointC[i]   := 0.0;                // 设定值出口清零（Setpoint outlet cleared）
        afDeviation[i]   := 0.0;                // 偏差出口清零（Deviation outlet cleared）
        afTempAvg[i]     := 0.0;                // 均值出口清零（Average outlet cleared）
        auCommFailCnt[i] := 0;                  // 连续失败计数清零（Failure counter cleared）
        abDropped[i]     := FALSE;              // 摘除标志清零（Drop flag cleared）
        anRecover[i]     := 0;                  // 恢复计数清零（Recovery counter cleared）
    END_FOR
    uQualityMask := DL_MASK_NONE;               // 质量掩码清零（Quality mask cleared）
    nOnlineCount := 0;                          // 在线台数清零（Online count cleared）
    nWorstIdx    := 0;                          // 最差通道清零（Worst channel cleared）
    fWorstDev    := 0.0;                        // 最差偏差清零（Worst deviation cleared）
    nDevUse      := 1;                          // 生效台数取下限（Effective device count at the lower bound）
    nFilterUse   := 1;                          // 生效窗口取下限（Effective window at the lower bound）
    nDropUse     := 1;                          // 生效阈值取下限（Effective threshold at the lower bound）
    fGainUse     := DL_GAIN_SAFE;               // 生效比例取兜底值（Effective gain set to the safe value）
    bFaultLatch  := FALSE;                      // 故障锁存清零（Fault latch cleared）
    uErrInt      := 16#0000_0000;               // 故障码清零（Fault code cleared）
    ePhase       := E_DL_TempBankPhase.eIdle;   // 相位复位为待机（Phase reset to idle）
    bInit        := TRUE;                       // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜参数钳位（先于任何数组访问与循环上限；越界只钳位并置信息码）
 *      Parameter clamping before any array access or loop bound
 *-----------------------------------------------------------------------------*)
IF nDeviceCount < 1 THEN
    nDevUse   := 1;                             // 台数下限钳位（Clamped to the lower bound）
    uInfoCode := 16#0005_0108;                  // 0108 台数越界已钳位（Device count clamped）
ELSIF nDeviceCount > DL_DEV_MAX THEN
    nDevUse   := DL_DEV_MAX;                    // 台数上限钳位（Clamped to the upper bound）
    uInfoCode := 16#0005_0108;                  // 0108 台数越界已钳位（Device count clamped）
ELSE
    nDevUse   := nDeviceCount;                  // 合法台数直通（Valid device count passed through）
END_IF

IF nFilterLen < 1 THEN
    nFilterUse := 1;                            // 窗口下限钳位（Clamped to the lower bound）
    uInfoCode  := 16#0005_0108;                 // 0108 窗口越界已钳位（Window clamped）
ELSIF nFilterLen > DL_FILT_MAX THEN
    nFilterUse := DL_FILT_MAX;                  // 窗口上限钳位（Clamped to the upper bound）
    uInfoCode  := 16#0005_0108;                 // 0108 窗口越界已钳位（Window clamped）
ELSE
    nFilterUse := nFilterLen;                   // 合法窗口直通（Valid window passed through）
END_IF
IF nFilterUse = 1 THEN
    uInfoCode := 16#0005_010A;                  // 010A 窗口为 1，无滤波能力（Window of one gives no filtering）
END_IF

IF nDropAfterFails < 1 THEN
    nDropUse  := 1;                             // 阈值下限钳位（Clamped to the lower bound）
    uInfoCode := 16#0005_0108;                  // 0108 阈值越界已钳位（Threshold clamped）
ELSIF nDropAfterFails > DL_DROP_MAX THEN
    nDropUse  := DL_DROP_MAX;                   // 阈值上限钳位（Clamped to the upper bound）
    uInfoCode := 16#0005_0108;                  // 0108 阈值越界已钳位（Threshold clamped）
ELSE
    nDropUse  := nDropAfterFails;               // 合法阈值直通（Valid threshold passed through）
END_IF

IF fScaleGain <= DL_GAIN_MIN THEN
    fGainUse := DL_GAIN_SAFE;                   // 量纲错：兜底比例避免零乘（Safe gain avoids a zero product）
    IF NOT bFaultLatch THEN
        bFaultLatch := TRUE;                    // 锁故障，保留首出码（Latch the fault keeping the first code）
        uErrInt     := 16#0005_0207;            // 0207 换算比例非正（Non-positive gain）
    END_IF
ELSE
    fGainUse := fScaleGain;                     // 合法比例直通（Valid gain passed through）
END_IF

IF fRangeMin >= fRangeMax THEN
    IF NOT bFaultLatch THEN
        bFaultLatch := TRUE;                    // 有效域为空：锁故障（Empty valid range, latch the fault）
        uErrInt     := 16#0005_0208;            // 0208 有效域为空（Empty valid range）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜站表默认值填充与调度实例调用（实例每拍无条件调用，使能经引脚注入）
 *      Poll table defaults and the embedded scheduler, called every scan
 *-----------------------------------------------------------------------------*)
FOR k := 0 TO (DL_TABLE_MAX - 1) DO
    nGuard := nGuard + 1;                       // 守卫递增（Guard incremented）
    IF nGuard > DL_GUARD_MAX THEN
        EXIT;                                   // 守卫到顶即退出（Bail out at the guard bound）
    END_IF
    IF k < DL_DEV_MAX THEN
        IF (k + 1) <= nDevUse THEN
            aPollTable[k].uSlaveAddr := anSlaveAddr[k + 1]; // 从站地址取引脚（Slave address from the pin）
            aPollTable[k].uFuncCode  := DL_FUNC_READ;       // 读保持寄存器（Read holding registers）
            aPollTable[k].uStartAddr := DL_REG_START;       // 起始地址零（Start address zero）
            aPollTable[k].uQuantity  := DL_REG_QTY;         // 连续两寄存器：过程值与设定值（Two registers, process and setpoint）
            aPollTable[k].bSkip      := FALSE;              // 启用本站（Station enabled）
        ELSE
            aPollTable[k].bSkip := TRUE;                    // 超出台数：跳过（Beyond the device count, skip）
        END_IF
    ELSE
        aPollTable[k].bSkip := TRUE;                        // 站表多余项一律跳过（Extra table entries are skipped）
    END_IF
END_FOR

fbPoll(bEnable       := bEnable AND (ePhase = E_DL_TempBankPhase.ePolling),
       uStationCount := INT_TO_UINT(nDevUse),
       tRespTimeout  := DL_RESP_TO,
       uMaxRetry     := DL_RETRY_MAX,
       tPollInterval := DL_POLL_GAP,
       aPollTable    := aPollTable);            // 调度实例无条件调用，绝不做条件包裹（Never wrapped in a conditional）

(*------------------------------------------------------------------------------
 * 段 6｜逐通道评估（换算、三道有效性闸、失败计数与摘除、恢复、偏差与最差通道）
 *      Per-channel evaluation with the three validity gates and the drop policy
 *-----------------------------------------------------------------------------*)
IF bEval THEN
    nOnline     := 0;                           // 在线计数清零（Online counter cleared）
    nWorst      := 0;                           // 最差通道清零（Worst channel cleared）
    fWorstTmp   := 0.0;                         // 最差偏差暂存清零（Worst deviation temporary cleared）
    uQBuild     := DL_MASK_NONE;                // 质量掩码装配清零（Quality mask cleared）
    FOR i := 1 TO DL_DEV_MAX DO
        nGuard := nGuard + 1;                   // 守卫递增（Guard incremented）
        IF nGuard > DL_GUARD_MAX THEN
            EXIT;                               // 守卫到顶即退出（Bail out at the guard bound）
        END_IF
        IF i <= nDevUse THEN
            fVal    := (INT_TO_REAL(auPvRaw[i]) * fGainUse) + fScaleOffset; // 过程值换算（Process value conversion）
            fSp     := (INT_TO_REAL(auSvRaw[i]) * fGainUse) + fScaleOffset; // 设定值换算（Setpoint conversion）
            bValFin := NOT ((fVal <> fVal) OR (ABS(fVal) > DL_TEMP_MAX));   // 有限性判定（Finiteness test）
            abOkTmp[i] := abPollOk[i] AND bValFin AND (fVal >= fRangeMin) AND (fVal <= fRangeMax); // 三道闸（Three gates）
            IF abOkTmp[i] THEN
                auCommFailCnt[i] := 0;          // 有效拍清零连续失败（Clear the failure counter）
                afTempC[i]       := fVal;       // 有效才刷新温度（Refresh the temperature only when valid）
                afSetpointC[i]   := fSp;        // 有效才刷新设定值（Refresh the setpoint only when valid）
                IF abDropped[i] THEN
                    IF anRecover[i] < DL_RECOVER_NEED THEN
                        anRecover[i] := anRecover[i] + 1; // 恢复计数累加（Recovery counter incremented）
                    END_IF
                    IF anRecover[i] >= DL_RECOVER_NEED THEN
                        abDropped[i] := FALSE;  // 连续有效达阈值：自动恢复（Automatic recovery）
                        anRecover[i] := 0;      // 恢复计数清零（Recovery counter cleared）
                    END_IF
                END_IF
            ELSE
                IF auCommFailCnt[i] < DL_FAIL_MAX THEN
                    auCommFailCnt[i] := auCommFailCnt[i] + 1; // 连续失败累加，饱和到上限（Failure counter incremented and saturated）
                END_IF
                anRecover[i] := 0;              // 失败即清恢复计数（Recovery counter cleared on a failure）
                IF (NOT abDropped[i]) AND (auCommFailCnt[i] >= INT_TO_UINT(nDropUse)) THEN
                    abDropped[i] := TRUE;       // 达阈值：摘除通道（Drop the channel）
                    bDropEvent   := TRUE;       // 标记待置信息码 0109（Flag the informational code 0109）
                END_IF
            END_IF
            IF abDropped[i] OR (NOT abOkTmp[i]) THEN
                uQBuild := uQBuild OR SHL(DL_MASK_ONE, i - 1); // 坏通道进位（Bad channel bit set）
            ELSE
                nOnline := nOnline + 1;         // 在线台数累加（Online count incremented）
            END_IF
            afDeviation[i] := afTempC[i] - afSetpointC[i]; // 偏差由保持后的温度算出（Deviation from the held temperature）
            IF (NOT abDropped[i]) AND abOkTmp[i] THEN
                fDevAbs := ABS(afDeviation[i]);  // 只让在线通道参与最差判定（Only online channels compete）
                IF fDevAbs > fWorstTmp THEN
                    fWorstTmp := fDevAbs;        // 严格大于才替换，并列取小号（Strictly greater, ties keep the lower index）
                    nWorst    := i;              // 记录最差通道号（Record the worst channel）
                END_IF
            END_IF
        ELSE
            abOkTmp[i]     := FALSE;            // 超出台数：本拍无效（Beyond the device count, invalid）
            afDeviation[i] := 0.0;              // 超出台数：偏差清零（Deviation cleared）
        END_IF
    END_FOR
    uQualityMask := uQBuild;                    // 质量掩码整值写出（Quality mask published as a whole）
    nOnlineCount := nOnline;                    // 在线台数写出（Online count published）
    nWorstIdx    := nWorst;                     // 最差通道写出（Worst channel published）
    IF nWorst > 0 THEN
        fWorstDev := afDeviation[nWorst];       // 最差通道的有符号偏差（Signed deviation of that channel）
    ELSE
        fWorstDev := 0.0;                       // 无在线通道时为零（Zero when no channel is online）
    END_IF
    IF bDropEvent THEN
        uInfoCode := 16#0005_0109;              // 0109 通道已摘除（A channel was dropped）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜滑动均值实例全量调用（红线：实例每拍无条件调用，采样经允许位控制）
 *      Moving average instances called for every channel, sampling gated by a flag
 *-----------------------------------------------------------------------------*)
FOR i := 1 TO DL_DEV_MAX DO
    nGuard := nGuard + 1;                       // 守卫递增（Guard incremented）
    IF nGuard > DL_GUARD_MAX THEN
        EXIT;                                   // 守卫到顶即退出（Bail out at the guard bound）
    END_IF
    afbAvg[i](fInput      := afTempC[i],
              nWindowSize := nFilterUse,
              bSample     := bEval AND abOkTmp[i],
              bEnable     := TRUE,
              bReset      := fbTrigReset.Q);    // 复位沿同拍清窗口，避免复位后混旧样本（Reset clears the window）
    afTempAvg[i] := afbAvg[i].fAverage;         // 均值出口（Average outlet）
END_FOR

(*------------------------------------------------------------------------------
 * 段 8｜主状态机（枚举每个成员均有标签，末尾 ELSE 兜底到终端安全态）
 *      Main state machine, one label per member plus a trailing ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF

    E_DL_TempBankPhase.eIdle: // 待机：故障或未使能则停留，否则进入轮询
        IF bFaultLatch THEN
            ePhase := E_DL_TempBankPhase.eFault;   // 参数已锁故障：进故障态（Gate failed, enter the fault state）
        ELSIF bEnable THEN
            ePhase := E_DL_TempBankPhase.ePolling; // 进轮询相（Enter the polling phase）
        END_IF

    E_DL_TempBankPhase.ePolling: // 轮询：评估在固定段完成，本相只负责相位迁移
        IF NOT bEnable THEN
            ePhase := E_DL_TempBankPhase.eIdle;    // 掉使能：回待机，输出保持（Disabled, back to idle with outputs held）
        ELSIF bFaultLatch THEN
            ePhase := E_DL_TempBankPhase.eFault;   // 运行期参数失效：进故障态（A parameter failed at run time）
        END_IF

    E_DL_TempBankPhase.eFault: // 故障：输出保持，等复位沿
        IF fbTrigReset.Q THEN
            ePhase := E_DL_TempBankPhase.eIdle;    // 复位后回待机，重新过闸门（Reset returns to idle and re-runs the gate）
        END_IF

    ELSE
        bFaultLatch := TRUE;                        // 非法状态兜底锁存（Illegal state latched）
        uErrInt     := 16#0005_0209;                // 0209 非法状态兜底（Illegal state fallback code）
        ePhase      := E_DL_TempBankPhase.eFault;   // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜复位（清故障、摘除状态与连续失败计数，温度保持供画面对比）
 *      Reset clears the fault, the drop state and the failure counters
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    bFaultLatch := FALSE;                       // 清故障锁存（Clear the fault latch）
    uErrInt     := 16#0000_0000;                // 清故障码（Clear the fault code）
    FOR i := 1 TO DL_DEV_MAX DO
        abDropped[i]     := FALSE;              // 清摘除标志（Clear the drop flag）
        anRecover[i]     := 0;                  // 清恢复计数（Clear the recovery counter）
        auCommFailCnt[i] := 0;                  // 清连续失败计数（Clear the failure counter）
    END_FOR
    uInfoCode := 16#0000_0000;                  // 复位当拍清信息码（Info code cleared on the reset cycle）
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜出口映射与码位定级（单一优先级链，全拍只写一次 uErrorId）
 *      Outlet mapping with a single priority chain
 *-----------------------------------------------------------------------------*)
eState := ePhase;                               // 相位出口（Phase outlet）
bError := bFaultLatch;                          // 故障位只反映故障级锁存（Fault bit reflects the latch only）
IF bError THEN
    uErrorId := uErrInt;                        // 故障级码优先透出（Fault level code has priority）
ELSE
    uErrorId := uInfoCode;                      // 无故障透出本拍信息级码（Info code exposed otherwise）
END_IF
END_FUNCTION_BLOCK
