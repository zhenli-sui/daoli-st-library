(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AndonCallSystem
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 人员响应工艺功能块（Function Block · 安灯呼叫系统）
 * 作者     (Author)     : Daoli Library
 * 日期     (Date)       : 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 功能简介 (Function)   : 车间安灯（Andon）四级呼叫系统：缺料 / 品质 / 设备 /
 *                         维修四路呼叫源，按固定优先级（维修 > 设备 > 品质 > 缺料）
 *                         做多源同拍仲裁；呼叫生命周期为「呼叫（未应答）→ 已应答
 *                         （未解除）→ 解除」三段，未应答超阈值可升级上报；应答
 *                         时长做最近值与滚动均值统计；班次清零只清统计台账，不动
 *                         激活呼叫。
 * 职责边界 (Scope)      : ① 只做「人员响应域」的状态与统计，不驱动物理灯柱：
 *                         灯色/闪频输出由既有 FB_DL_SignalTower 承载（本块仅出
 *                         级别与状态，可与之配套组合，且不依赖其实现）；
 *                         ② 与设备级状态机（如既有 FB_DL_PackMlStateMachine 的
 *                         17 态）正交：安灯描述「谁该来、来了没有」，不做设备
 *                         启停编排；③ 不做消息推送与网络上报（升级位仅作本地
 *                         输出，推送由上层 MES 接口块按位取用）。
 * 开源溯源 (Origin)     : 来源标签 andon / omac（PackML / OMAC 人员响应域开族）。
 *                         仅参考 ISA-TR88.00.02 公开规范与 OMAC 包装机工作组公开
 *                         建模惯例中「安灯四级分类（缺料/品质/设备/维修）、应答-
 *                         解除生命周期、升级上报、班次统计」的功能分类与状态域；
 *                         本块的枚举编号（数值即仲裁权重）、状态机、滚动均值算法、
 *                         引脚契约与故障码位 100% 本库独立设计，clean-room 实现，
 *                         未复制任何来源的代码行，不构成衍生作品。
 * 公约遵循 (Convention) : 0.1/R19 首扫范式（IF (NOT _bInit)）；0.2/R21 bError 显式
 *                         排除信息级码；0.5/R7 定时器与三个边沿实例主体最前部无
 *                         条件刷新；0.6/R14 计时器语义变化断输入一拍（呼叫换级时
 *                         重置升级计时）；0.7/R15 故障级锁存仅重建路径清码；
 *                         0.9 出口默认值先赋；0.14 除法防零；0.16 阈值全常量化。
 * 红线自检 (Redline)    : 全局隔离 ✓（零全局变量表引用、零外部变量声明、零物理
 *                         地址字面记号）｜命名合规 ✓（b/n/u/f/t/a/st/e/fb/i 前缀
 *                         全覆盖）｜注释完整 ✓（声明行 100% 中英双语同行注释）｜
 *                         OOP 封装 ✓（状态全私有，仅引脚与只读输出）｜周期安全 ✓
 *                         （TON / R_TRIG 均无条件刷新）｜防御编程 ✓（算术防溢出、
 *                         均值防除零、ENUM + CASE + ELSE 兜底）｜可移植性 ✓（纯
 *                         IEC 61131-3）｜终结符成对 ✓
 * 设计要点 (Key notes)  : ① 仲裁不依赖枚举数值排序：显式 IF 链按「维修 > 设备 >
 *                         品质 > 缺料」取值，枚举数值仅作对外权重标识，防止后续
 *                         插入新级别时数值序与业务序脱钩（可维护性优先）。
 *                         ② 抢占语义：eCalled / eAcked 期间更高优先级呼叫到来即
 *                         重锁，且升级计时与升级位一并重建（旧呼叫的升级计时不再
 *                         有效）；未应答即被抢占的呼叫不计入应答笔数（它不是一次
 *                         响应），只在信息级码上留痕，避免均值被「没人来」的呼叫
 *                         污染。
 *                         ③ 应答时长来源：以长周期 TON 的 ET 作为「呼叫存活时长」
 *                         计量（PT 取 24 h 上限，正常呼叫远达不到，ET 即真实
 *                         时长），避免引入累计时钟引脚；换级/新呼叫时断输入一拍
 *                         使 ET 从零重计（公约 0.6）。
 *                         ④ 滚动均值：tAckAvg += (tAckLast − tAckAvg) / 笔数。
 *                         采用增量式而非「总和 / 笔数」，避免长班次累计和溢出；
 *                         差值用 DINT 有符号运算，避免无符号下溢。
 *                         ⑤ 班次清零语义写死：只清 tAckLast / tAckAvg / uAckCount，
 *                         不清激活呼叫与升级位（现场交接班时呼叫仍需有人响应）。
 * 偏离留档 (Deviation)  : ① 规格 VAR 段 bFirstScan 改名 _bInit（公约 0.1）；
 *                         ② 规格 VAR 段 fbEscTimer 与内部计时基准拆为两支 TON
 *                         （升级计时 + 存活计时），理由见设计要点③：单个 TON 在
 *                         tEscalate = 0（不升级）时 ET 不再累加，无法同时承担
 *                         应答时长计量。
 * 故障码表 (Error codes) :
 *                         16#0005_01A0【信息级】未应答即解除（应答统计不计入）
 *                         16#0005_01A1【信息级】多源呼叫同拍或高优先级抢占重锁
 *                         16#0005_02A0【故障级】激活呼叫级别非法（内部一致性破坏）
 *                         16#0005_02A1【故障级】非法状态兜底（枚举越界）
 * 验收向量 (Acceptance) :
 *   V1 仲裁：缺料 + 设备同拍 → 激活级别为设备（优先级 2 胜 4），信息级 01A1；
 *   V2 应答统计：呼叫 30 s 后应答 → tAckLast = 30 s、uAckCount = 1、tAckAvg
 *      = 30 s；再来一次 10 s 应答 → tAckAvg = 20 s（增量均值复算）；
 *   V3 升级：tEscalate = 120 s、未应答 120 s → bEscalate 保持型置位；应答后
 *      立即复位；
 *   V4 抢占：品质呼叫 60 s 未应答，维修呼叫到来 → 级别切维修、升级计时从零
 *      重计、bEscalate 复位，uAckCount 不变（未应答不计笔数）；
 *   V5 班次清零：bShiftReset 上升沿 → tAckLast / tAckAvg / uAckCount 归零，
 *      激活呼叫与升级位保持；
 *   V6 未应答解除：eCalled 期间 bClear 上升沿 → 回 eIdle、bCallActive FALSE、
 *      信息级 01A0、uAckCount 不变。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 09 · DL_Process 安灯呼叫件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   VAR fbAndon : FB_DL_AndonCallSystem; END_VAR
 *   fbAndon(bCallMat := bBtnMaterial, bCallQual := bBtnQuality,
 *           bCallDev := bBtnDevice, bCallMaint := bBtnMaintenance,
 *           bAcknowledge := bBtnAck, bClear := bBtnClear,
 *           bShiftReset := bShiftStartPulse, tEscalate := T#120S);
 *   灯柱联动：把 fbAndon.eActiveCall 映射为灯色（维修红常亮 / 设备红闪 /
 *            品质黄 / 缺料蓝），fbAndon.bEscalate 映射为蜂鸣升级。
 *   注意：bAcknowledge / bClear / bShiftReset 均为上升沿生效，长按不会重复计数。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 呼叫位是电平输入：按钮按下保持即持续呼叫，松开且呼叫未应答时呼叫仍
 *     保持（激活呼叫在状态机内锁存），不会因松手而消失——这是安灯的基本语义。
 *   2 应答后必须显式解除（bClear）才会回 eIdle：现场常见「应答了但没消灯」，
 *     属正常设计（提醒问题尚未处理完），若需自动消灯请在上层按工艺判定解除。
 *   3 升级位不改变状态机：它只是「催一下」的上报信号，不额外占用呼叫级别。
 *   4 班次清零不清激活呼叫：交接班时若仍有未处理呼叫，新班次统计从零开始但
 *     呼叫继续升级，这是有意设计。
 *   5 应答时长按「呼叫发起到按键应答」计量，不含问题实际处理时间；需要处理
 *     时长请另用维修工单系统统计。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AndonLevel（归属 FB_DL_AndonCallSystem，随本文件发布）
 * 含义: 呼叫级别。数值即对外公布的仲裁权重（小者优先），状态机内部仍用显式
 *       IF 链仲裁（见设计要点①），数值仅供 HMI 排序与上位系统对照。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_AndonLevel :
(
    eNone     := 0,     // 无呼叫（No call），空闲基准值 / Baseline value when no call is pending
    eMaterial := 4,     // 缺料呼叫（Material call），最低优先级 4 / Lowest priority, weight four
    eQuality  := 3,     // 品质呼叫（Quality call），优先级 3 / Priority weight three
    eDevice   := 2,     // 设备呼叫（Device call），优先级 2 / Priority weight two
    eMaint    := 1      // 维修呼叫（Maintenance call），最高优先级 1 / Highest priority, weight one
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AndonState（归属 FB_DL_AndonCallSystem，随本文件发布）
 * 含义: 呼叫生命周期离散状态。数值步长 10 留空位，故障态 99 排序末位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_AndonState :
(
    eIdle   := 0,      // 无呼叫：等待任一呼叫源（No call, waiting for a source）
    eCalled := 10,     // 已呼叫待应答：升级计时进行中（Called, waiting for acknowledgement）
    eAcked  := 20,     // 已应答待解除：应答已记账，等待问题处理完解除（Acknowledged, waiting for the clear）
    eFault  := 99      // 内部异常：仅班次清零沿可退（Internal fault, left only by the shift reset edge）
) UINT;
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_AndonCallSystem
 * 调用约定: 每个扫描周期无条件调用一次；三个事件输入均为上升沿生效。
 * 无状态泄漏: 全部状态驻留于实例私有成员，多工位各一实例，可并行。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AndonCallSystem
VAR_INPUT
    bCallMat     : BOOL;                // 缺料呼叫（Material call），优先级 4（最低） / Priority four, the lowest
    bCallQual    : BOOL;                // 品质呼叫（Quality call），优先级 3 / Priority three
    bCallDev     : BOOL;                // 设备呼叫（Device call），优先级 2 / Priority two
    bCallMaint   : BOOL;                // 维修呼叫（Maintenance call），优先级 1（最高） / Priority one, the highest
    bAcknowledge : BOOL;                // 呼叫应答（Acknowledge），上升沿对当前激活呼叫应答 / Rising edge acknowledges the active call
    bClear       : BOOL;                // 呼叫解除（Clear call），上升沿清除当前激活呼叫 / Rising edge clears the active call
    bShiftReset  : BOOL;                // 班次清零（Shift reset），上升沿清统计台账，不清激活呼叫 / Rising edge clears the statistics only
    tEscalate    : TIME := T#120S;      // 升级上报阈值（Escalation threshold）[ms]，0 = 不升级 / Zero disables escalation
END_VAR
VAR_OUTPUT
    eActiveCall  : E_DL_AndonLevel;     // 当前激活呼叫级别（Active call level），eNone = 无 / None when idle
    bCallActive  : BOOL;                // 有未应答激活呼叫（Unacknowledged call pending）/ An unacknowledged call is pending
    bAcked       : BOOL;                // 已应答未解除（Acknowledged and not yet cleared）/ Acknowledged but not yet cleared
    bEscalate    : BOOL;                // 升级上报（Escalation raised），保持型直到应答或解除 / Held until acknowledgement or clear
    tAckLast     : TIME := T#0MS;       // 最近一次应答耗时（Last acknowledgement time）[ms] / Time from call to acknowledgement [ms]
    tAckAvg      : TIME := T#0MS;       // 平均应答耗时（Average acknowledgement time）[ms]，滚动均值 / Rolling average acknowledgement time [ms]
    uAckCount    : UDINT := 0;          // 累计应答笔数（Acknowledgement count）[笔] / Number of acknowledgements
    uErrorId     : UDINT;               // 故障码（Error code），0 = 无故障，段位 16#0005_xxxx / Error code, zero means no error
END_VAR
VAR
    _eState      : E_DL_AndonState := E_DL_AndonState.eIdle; // 呼叫主状态机（Call state machine）/ Call state machine
    _bInit       : BOOL;                // 首扫完成标志（First-scan done flag），初值 FALSE / First-scan done flag, initial FALSE
    _eActive     : E_DL_AndonLevel := E_DL_AndonLevel.eNone; // 锁存的激活级别（Latched active level）/ Latched active level
    _eHighest    : E_DL_AndonLevel;     // 本拍最高优先级呼叫（Highest call level this scan）/ Highest call level in this scan
    _uCallBits   : UINT;                // 本拍呼叫源个数（Call source count this scan）[路]，0~4 / Number of active call sources, zero to four
    _tEscEff     : TIME := T#120S;      // 生效升级阈值（Effective escalation threshold）[ms] / Effective escalation threshold [ms]
    _bEscBreak   : BOOL;                // 升级计时断输入一拍（Escalation timer break），换级重置用 / One-scan break used to restart the timer
    _bEscFeed    : BOOL;                // 升级计时器输入（Escalation timer input），先算后喂 / Computed first and then fed
    _bAgeBreak   : BOOL;                // 存活计时断输入一拍（Age timer break），新呼叫重置用 / One-scan break used to restart the age timer
    _bAgeFeed    : BOOL;                // 存活计时器输入（Age timer input），先算后喂 / Computed first and then fed
    _nDeltaMs    : DINT;                // 应答耗时差值（Deviation of the sample）[ms]，有符号 / Signed deviation of the last sample [ms]
    _nStepMs     : DINT;                // 均值增量（Mean increment）[ms]，有符号 / Signed increment of the rolling mean [ms]
    _bFaultLatch : BOOL;                // 故障锁存（Fault latch），仅班次清零沿清除 / Fault latch, cleared by the shift reset edge
    _uErrInt     : UDINT;               // 故障级码寄存（Fault-level code register），锁存型 / Latched fault-level code register
    _uInfoCode   : UDINT;               // 本拍信息级码（Info code this scan），每拍重算 / Info code recomputed every scan
    _fbEscTimer  : TON;                 // 升级计时定时器（Escalation timer），主周期无条件刷新 / Refreshed unconditionally every scan
    _fbAgeTimer  : TON;                 // 呼叫存活计时定时器（Call age timer），ET 即呼叫时长 / Its elapsed time is the call age
    _fbTrigAck   : R_TRIG;              // 应答上升沿（Acknowledge rising edge）/ Acknowledge rising edge detector
    _fbTrigClear : R_TRIG;              // 解除上升沿（Clear rising edge）/ Clear rising edge detector
    _fbTrigShift : R_TRIG;              // 班次清零上升沿（Shift reset rising edge）/ Shift reset rising edge detector
END_VAR
VAR CONSTANT
    DL_AGE_LIMIT   : TIME := T#24H;     // 存活计时上限（Age timer ceiling）[ms]，正常呼叫远达不到 / Ceiling never reached by a normal call
END_VAR

// ============================================================================
// 段 1｜输出确定性默认值先赋（公约 0.9）
//      Deterministic defaults assigned before any early exit
// ============================================================================
bCallActive := FALSE;                  // 未应答呼叫标志预清零（Pending call flag pre-cleared）
bAcked      := FALSE;                  // 已应答标志预清零（Acknowledged flag pre-cleared）
bEscalate   := FALSE;                  // 升级标志预清零（Escalation flag pre-cleared）
_uInfoCode  := 0;                      // 信息级码每拍重算（Info code recomputed every scan）
_uCallBits  := 0;                      // 呼叫源计数预清零（Call source count pre-cleared）

// ============================================================================
// 段 2｜首扫初始化（R19 范式）
//      First-scan initialization following the single legal R19 predicate
// ============================================================================
IF NOT _bInit THEN
    _bInit       := TRUE;              // 置首扫完成（First-scan done）
    _eState      := E_DL_AndonState.eIdle; // 状态复位为空闲（State reset to idle）
    _eActive     := E_DL_AndonLevel.eNone; // 激活级别置无（Active level set to none）
    tAckLast     := T#0MS;             // 最近应答耗时清零（Last acknowledgement cleared）
    tAckAvg      := T#0MS;             // 平均应答耗时清零（Average acknowledgement cleared）
    uAckCount    := 0;                 // 应答笔数清零（Acknowledgement count cleared）
    _bFaultLatch := FALSE;             // 故障锁存清零（Fault latch cleared）
    _uErrInt     := 16#0000_0000;      // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜定时器与边沿实例无条件周期刷新（公约 0.5 / 0.6）
//      Unconditional refresh of the timers and the three edge instances
// ============================================================================
_fbTrigAck(CLK := bAcknowledge);       // 应答沿（Acknowledge edge）
_fbTrigClear(CLK := bClear);           // 解除沿（Clear edge）
_fbTrigShift(CLK := bShiftReset);      // 班次清零沿（Shift reset edge）

IF tEscalate = T#0MS THEN
    _tEscEff := T#0MS;                 // 阈值 0 = 不升级（Zero threshold disables escalation）
ELSE
    _tEscEff := tEscalate;             // 合法阈值直通（Valid threshold passed through）
END_IF

_bAgeFeed := ((_eState = E_DL_AndonState.eCalled) OR (_eState = E_DL_AndonState.eAcked)) AND (NOT _bAgeBreak); // 存活计时输入（Age timer input）
_fbAgeTimer(IN := _bAgeFeed, PT := DL_AGE_LIMIT); // 呼叫存活计时，ET 即呼叫时长（Age timing, elapsed time is the call age）
_bAgeBreak := FALSE;                   // 断输入脉冲在实例调用后自清（Break pulse self-cleared after the call）

_bEscFeed := (_eState = E_DL_AndonState.eCalled) AND (_tEscEff > T#0MS) AND (NOT _bEscBreak); // 升级计时输入（Escalation timer input）
_fbEscTimer(IN := _bEscFeed, PT := _tEscEff); // 升级计时（Escalation timing）
_bEscBreak := FALSE;                   // 断输入脉冲自清（Break pulse self-cleared）

// ============================================================================
// 段 4｜多源仲裁（显式优先级链，不依赖枚举数值序；同拍多源置信息级）
//      Source arbitration with an explicit priority chain
// ============================================================================
_eHighest := E_DL_AndonLevel.eNone;    // 默认无呼叫（Default to no call）
IF bCallMaint THEN
    _eHighest := E_DL_AndonLevel.eMaint; // 维修最高优先级（Maintenance has the highest priority）
    _uCallBits := _uCallBits + 1;      // 呼叫源计数累加（Source count incremented）
END_IF
IF bCallDev THEN
    IF _eHighest = E_DL_AndonLevel.eNone THEN
        _eHighest := E_DL_AndonLevel.eDevice; // 设备次高优先级（Device is the second priority）
    END_IF
    _uCallBits := _uCallBits + 1;      // 呼叫源计数累加（Source count incremented）
END_IF
IF bCallQual THEN
    IF _eHighest = E_DL_AndonLevel.eNone THEN
        _eHighest := E_DL_AndonLevel.eQuality; // 品质再次（Quality is the third priority）
    END_IF
    _uCallBits := _uCallBits + 1;      // 呼叫源计数累加（Source count incremented）
END_IF
IF bCallMat THEN
    IF _eHighest = E_DL_AndonLevel.eNone THEN
        _eHighest := E_DL_AndonLevel.eMaterial; // 缺料最低（Material is the lowest priority）
    END_IF
    _uCallBits := _uCallBits + 1;      // 呼叫源计数累加（Source count incremented）
END_IF

IF _uCallBits > 1 THEN
    _uInfoCode := 16#0005_01A1;        // 0005_01A1 多源呼叫同拍，按固定优先级仲裁【信息级】（Multiple sources arbitrated, info level）
END_IF

// ============================================================================
// 段 5｜班次清零（只清统计台账，不清激活呼叫；R15 顺带解除故障锁存）
//      Shift reset clears the statistics only, never the active call
// ============================================================================
IF _fbTrigShift.Q THEN
    tAckLast     := T#0MS;             // 最近应答耗时清零（Last acknowledgement cleared）
    tAckAvg      := T#0MS;             // 平均应答耗时清零（Average acknowledgement cleared）
    uAckCount    := 0;                 // 应答笔数清零（Acknowledgement count cleared）
    _bFaultLatch := FALSE;             // 班次清零同时解除内部故障锁存（The shift edge also releases the fault latch）
    _uErrInt     := 16#0000_0000;      // 故障码清零（Fault code cleared）
    IF _eState = E_DL_AndonState.eFault THEN
        _eState := E_DL_AndonState.eIdle; // 故障态经班次清零退回空闲（Fault state returns to idle）
    END_IF
END_IF

// ============================================================================
// 段 6｜内部一致性校验（激活呼叫存在但级别为无 → 内部异常）
//      Internal consistency check, an active call without a level is illegal
// ============================================================================
IF ((_eState = E_DL_AndonState.eCalled) OR (_eState = E_DL_AndonState.eAcked)) AND
   (_eActive = E_DL_AndonLevel.eNone) THEN
    _bFaultLatch := TRUE;              // 一致性破坏锁故障（Consistency break latches a fault）
    _uErrInt     := 16#0005_02A0;      // 0005_02A0 激活呼叫级别非法【故障级】（Illegal active call level, fault level）
    _eState      := E_DL_AndonState.eFault;
END_IF

// ============================================================================
// 段 7｜主状态机（ENUM + CASE + ELSE 兜底；抢占重锁 + 应答统计 + 升级）
//      Main state machine with preemption, statistics and escalation
// ============================================================================
CASE _eState OF

    E_DL_AndonState.eIdle: // 无呼叫：任一呼叫源即起呼（Idle, any source raises a call）
        IF _eHighest <> E_DL_AndonLevel.eNone THEN
            _eActive   := _eHighest;   // 锁存最高优先级级别（Latch the highest level）
            _bAgeBreak := TRUE;        // 存活计时从零重计（Age timer restarted）
            _bEscBreak := TRUE;        // 升级计时从零重计（Escalation timer restarted）
            _eState    := E_DL_AndonState.eCalled; // 进已呼叫态（Enter the called state）
        END_IF

    E_DL_AndonState.eCalled: // 已呼叫待应答（Called, waiting for acknowledgement）
        IF (_eHighest <> E_DL_AndonLevel.eNone) AND (_eHighest = E_DL_AndonLevel.eMaint) AND
           (_eActive <> E_DL_AndonLevel.eMaint) THEN
            _eActive   := E_DL_AndonLevel.eMaint; // 维修呼叫抢占一切（Maintenance preempts everything）
            _bAgeBreak := TRUE;        // 存活计时重计（Age timer restarted）
            _bEscBreak := TRUE;        // 升级计时重计，升级位随之重建（Escalation restarted, the raise bit is rebuilt）
            _uInfoCode := 16#0005_01A1; // 0005_01A1 高优先级抢占重锁【信息级】（Preemption re-lock, info level）
        ELSIF (_eHighest = E_DL_AndonLevel.eDevice) AND
              ((_eActive = E_DL_AndonLevel.eQuality) OR (_eActive = E_DL_AndonLevel.eMaterial)) THEN
            _eActive   := E_DL_AndonLevel.eDevice; // 设备抢占品质与缺料（Device preempts quality and material）
            _bAgeBreak := TRUE;        // 存活计时重计（Age timer restarted）
            _bEscBreak := TRUE;        // 升级计时重计（Escalation restarted）
            _uInfoCode := 16#0005_01A1; // 0005_01A1 高优先级抢占重锁【信息级】（Preemption re-lock, info level）
        ELSIF (_eHighest = E_DL_AndonLevel.eQuality) AND (_eActive = E_DL_AndonLevel.eMaterial) THEN
            _eActive   := E_DL_AndonLevel.eQuality; // 品质抢占缺料（Quality preempts material）
            _bAgeBreak := TRUE;        // 存活计时重计（Age timer restarted）
            _bEscBreak := TRUE;        // 升级计时重计（Escalation restarted）
            _uInfoCode := 16#0005_01A1; // 0005_01A1 高优先级抢占重锁【信息级】（Preemption re-lock, info level）
        END_IF

        IF _fbTrigAck.Q THEN
            tAckLast   := _fbAgeTimer.ET; // 应答耗时 = 呼叫存活时长（Acknowledgement time equals the call age）
            uAckCount  := uAckCount + 1;  // 应答笔数累加（Acknowledgement count incremented）
            IF uAckCount <= 1 THEN
                tAckAvg := tAckLast;      // 首笔均值等于样本（The first sample seeds the mean）
            ELSE
                _nDeltaMs := TIME_TO_DINT(tAckLast) - TIME_TO_DINT(tAckAvg); // 有符号差值，避免无符号下溢（Signed deviation avoids underflow）
                _nStepMs  := _nDeltaMs / UDINT_TO_DINT(uAckCount);           // 增量 = 差值 / 笔数（Increment is the deviation over the count）
                tAckAvg   := tAckAvg + DINT_TO_TIME(_nStepMs);               // 增量式滚动均值（Incremental rolling mean）
            END_IF
            _eState    := E_DL_AndonState.eAcked; // 进已应答态（Enter the acknowledged state）
        ELSIF _fbTrigClear.Q THEN
            _uInfoCode := 16#0005_01A0; // 0005_01A0 未应答即解除，不计应答笔数【信息级】（Cleared without an acknowledgement, info level）
            _eActive   := E_DL_AndonLevel.eNone; // 级别归无（Level cleared）
            _bAgeBreak := TRUE;        // 存活计时复位（Age timer reset）
            _bEscBreak := TRUE;        // 升级计时复位（Escalation timer reset）
            _eState    := E_DL_AndonState.eIdle; // 回空闲（Back to idle）
        END_IF

    E_DL_AndonState.eAcked: // 已应答待解除（Acknowledged, waiting for the clear）
        IF _fbTrigClear.Q THEN
            _eActive   := E_DL_AndonLevel.eNone; // 级别归无（Level cleared）
            _bAgeBreak := TRUE;        // 存活计时复位（Age timer reset）
            _bEscBreak := TRUE;        // 升级计时复位（Escalation timer reset）
            _eState    := E_DL_AndonState.eIdle; // 回空闲（Back to idle）
        ELSIF ((_eHighest = E_DL_AndonLevel.eMaint) AND (_eActive <> E_DL_AndonLevel.eMaint)) OR
              ((_eHighest = E_DL_AndonLevel.eDevice) AND
               ((_eActive = E_DL_AndonLevel.eQuality) OR (_eActive = E_DL_AndonLevel.eMaterial))) OR
              ((_eHighest = E_DL_AndonLevel.eQuality) AND (_eActive = E_DL_AndonLevel.eMaterial)) THEN
            _eActive   := _eHighest;   // 仅更高优先级重起呼叫，同级不重复触发（Only a strictly higher level re-raises）
            _bAgeBreak := TRUE;        // 新呼叫存活计时从零（New call age restarted）
            _bEscBreak := TRUE;        // 新呼叫升级计时从零（New call escalation restarted）
            _uInfoCode := 16#0005_01A1; // 0005_01A1 已应答期间更高优先级抢占【信息级】（Preemption while acknowledged, info level）
            _eState    := E_DL_AndonState.eCalled; // 回到待应答（Back to the called state）
        END_IF

    E_DL_AndonState.eFault: // 内部异常：仅班次清零沿可退（Fault, left only by the shift edge）
        _eActive := E_DL_AndonLevel.eNone; // 级别归无，输出安全（Level cleared for a safe output）
        _bEscBreak := TRUE;            // 升级计时复位（Escalation timer reset）
        _bAgeBreak := TRUE;            // 存活计时复位（Age timer reset）

    ELSE
        _bFaultLatch := TRUE;          // 非法状态兜底锁存（Illegal state latched）
        _uErrInt     := 16#0005_02A1;  // 0005_02A1 非法状态兜底【故障级】（Illegal state fallback, fault level）
        _eState      := E_DL_AndonState.eFault; // 进故障态（Enter the fault state）
END_CASE

// ============================================================================
// 段 8｜出口映射（级别、标志派生、升级判据、故障级码优先透出）
//      Outlet mapping with fault-level codes taking priority over info codes
// ============================================================================
eActiveCall := _eActive;               // 激活级别出口（Active level outlet）
bCallActive := (_eState = E_DL_AndonState.eCalled); // 未应答呼叫派生（Pending call derived form）
bAcked      := (_eState = E_DL_AndonState.eAcked);  // 已应答派生（Acknowledged derived form）
bEscalate   := (_eState = E_DL_AndonState.eCalled) AND (_tEscEff > T#0MS) AND _fbEscTimer.Q; // 升级保持型派生（Escalation derived and held）

uErrorId := _uInfoCode;                // 信息级码先透出（Info code exposed first）
IF _bFaultLatch OR (_eState = E_DL_AndonState.eFault) THEN
    uErrorId := _uErrInt;              // 故障级码优先（Fault-level code has priority）
END_IF
END_FUNCTION_BLOCK
