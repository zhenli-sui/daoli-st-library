(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BatchPhaseBase
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 批次工艺 · 相状态机底座
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / TON）
 * 功能描述 (Function)   : ISA-88 批次相（Phase）的标准状态机底座：提供相状态迁移、
 *                         相内步骤推进、暂停与恢复、停止与中止四类命令的语义裁决，
 *                         以及相净运行时间累计。具体工艺动作不在本件内实现，由调用方
 *                         按「步骤执行请求」外置实现，完成或失败再回送反馈。
 * 分层声明 (Layering)   : ① 本件不实现任何工艺动作（投料、升温、搅拌、清洗的开阀与
 *                         设定值下发都在调用方），也不定义配方与流程结构（配方、程序、
 *                         单元编排属上层，另立件）；
 *                         ② 本件不驱动任何设备，不读写工艺参数，只裁决状态与命令；
 *                         ③ 步骤动作外置带来一个必须遵守的约定：收到步骤执行请求后，
 *                         调用方要自行记住「当前步已启动」，再用完成或失败反馈应答。
 * 语义要点 (Semantics)  :
 *   ① 命令优先级严格为 中止 高于 停止 高于 暂停 高于 恢复 高于 启动；同拍多命令时高
 *      优先者胜，低优先者直接丢弃且**不排队**——排队会让操作员的「停止」在几拍之后
 *      突然生效，属高危行为。
 *   ② 暂停只在步骤边界生效：暂停请求先登记，等当前步骤的完成反馈被消费、或步骤请求
 *      尚未发出时才真正进入暂停。**绝不在动作执行中途切断**，这是相语义的核心，也是
 *      现场「暂停后物料半投」事故的根因。
 *   ③ 恢复不重头：恢复时步骤号保持不变，重新发当前步骤的执行请求，从该步继续。
 *   ④ 已终止态（完成、已停、已中止）不接受启动与中止命令，只接受复位。
 *   ⑤ 掉使能时冻结状态与全部输出、不清零——批次报表需要看到最后相状态。
 * 计时口径 (Elapsed)    : 相运行累计时间只在执行相累加，暂停相与其余相不计入，故该值
 *                         即「相净运行时间」，MES 用它算相耗时与产能。
 * 开源溯源 (Origin)     : 来源标签 isa88-batch。原创实现（参考 ISA-88 与 IEC 61512 公开的
 *                         相状态模型：空闲、执行、收尾、完成、暂停请求、已暂停、恢复中、
 *                         停止中、已停、中止中、已中止的状态集合，以及「暂停在步骤边界
 *                         生效」「恢复不重头」两条语义）。ISA-88 为公开规范而非代码，
 *                         无代码复制问题；成员编号、状态机实现、超时策略、单拍请求语义、
 *                         计时口径与全部码位 100% 本库独立设计，clean-room 实现。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG / TON
 * 故障码表 (Error codes):
 *   16#0005_0104【信息级】相内步骤数越界已钳到 1 至 32
 *   16#0005_0105【信息级】同拍多命令，低优先命令已丢弃（不排队）
 *   16#0005_0106【信息级】从暂停恢复，步骤号不重置
 *   16#0005_0107【信息级】单步或暂停超时监控被关闭（参数为 0）
 *   16#0005_0203【故障级】单步超时，相中止（锁存）
 *   16#0005_0204【故障级】步骤失败反馈，相中止（锁存，与完成反馈同拍时失败优先）
 *   16#0005_0205【故障级】暂停超时，相中止（锁存）
 *   16#0005_0206【故障级】非法状态兜底（锁存，直接进已中止，不回空闲）
 * 码位占用 (Slot)       : 信息级 0104 / 0105 / 0106 / 0107；故障级 0203 / 0204 / 0205 / 0206。
 *                         全部落在 R12 本件分配块内，无跨块借用、无段外哨兵值。
 * 拍序纪律 (Cycle order) :
 *   ① eState     ：段 7 状态机（唯一位移点），段 8 复位分支是唯一回空闲点
 *   ② nStep      ：进入执行相置 1、步骤推进加 1、复位清零，三处互斥
 *   ③ bStepAcked ：消费一次完成反馈即置位，反馈电平落下即清零（R34 状态量生命周期）
 *   ④ uErrorId   ：段 9 单一优先级链，全拍只写一次
 * 验收向量 (Acceptance) :
 *   V1 三步走完：步骤数 3，启动后每拍给一次完成反馈 → 依次执行 1、2、3 步，
 *      第三步完成进收尾，收尾完成进完成相，完成标志为真
 *   V2 步骤边界暂停：第 2 步执行中给暂停 → 先进暂停请求相，该步完成反馈到达后才进
 *      已暂停，此时不再发步骤请求；恢复后回执行相且步骤号仍为 2
 *   V3 中止与复位：已暂停时给中止 → 中止相发出中止动作单拍 → 已中止；复位回空闲、
 *      步骤号归零、完成标志清零
 *   V4 单步超时：单步超时 2 秒、步骤数 1、启动后不给完成反馈 → 2 秒后进中止、
 *      故障位置位、码 0203
 *   V5 失败优先：完成反馈与失败反馈同拍 → 进中止、码 0204
 * 偏离留档 (Deviation)  :
 *   ① 规格内部变量清单列有循环守卫量，本件无循环（步骤数固定上限、无数组遍历），
 *      故不声明，避免声明不用的死变量。
 *   ② 新增「步骤完成反馈」的上升沿实例（规格清单未列）。理由：若只靠电平消费，完成
 *      反馈常高时新步骤的完成永远等不到下降沿，会把相卡死在执行相（R34 只置不销）。
 *      上升沿实例与电平标志双保险，仍保留步骤已消费标志。
 *   ③ 规格写「恢复时把步骤已消费标志置真」，照写会把恢复后本步的完成反馈永久屏蔽，
 *      故按语义改为置假（恢复后重新等待本步的完成反馈），并写进头注释。
 *   ④ 停止请求在步骤边界生效后，收尾完成由调用方再给一次完成反馈；若收尾无反馈，
 *      单步超时会把相带进中止（宁停不悬）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（R12 · 泳道 C · 批次相状态底座）
 *   2026-11-15  v1.0.1  终审修复两处：
 *                       ① 单步超时被实现成「相内累计超时」——监控定时器的输入在执行、收尾、
 *                       停止三相间持续为真，步骤推进时从不断输入，ET 跨步累加；3 步各 30 s、
 *                       超时 60 s 的合规批次会在第 3 步被误判 0203 中止。改为步骤边界断输入
 *                       一拍（bStepWatchBreak），超时按步重计时。
 *                       ② bStart 引脚注释原写「空闲与已终止态受理」，与实现（仅空闲受理、
 *                       终止态须先复位）不符，按实现更正注释
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_BatchPhaseState（相状态，归属本功能块并同文件发布）
 *       Phase state enumeration following the published ISA-88 phase model
 *       编号约定：0 起跳、步长 10，已中止取 99 保证排序末位
 *-----------------------------------------------------------------------------*)
TYPE E_DL_BatchPhaseState :
(
    eIdle       := 0,   // 空闲：等待启动，输出全复位 / Idle, waiting for the start command
    eRunning    := 10,  // 执行：按步骤号推进相内步骤 / Running, stepping through the phase
    eCompleting := 20,  // 收尾：最后一步已完成，等待收尾动作反馈 / Completing, waiting for the clean-up feedback
    eComplete   := 30,  // 完成：正常完成，保持到复位 / Complete, held until reset
    eHolding    := 40,  // 暂停请求：已受理，等步骤边界 / Holding, the hold request is accepted and pending a boundary
    eHeld       := 50,  // 已暂停：不再推进、不发步骤请求 / Held, no step request is issued
    eRestarting := 60,  // 恢复中：重发当前步骤请求，不重头 / Restarting, the current step is re-requested
    eStopping   := 70,  // 停止中：当前步骤收尾 / Stopping, the current step is being wrapped up
    eStopped    := 80,  // 已停：保持到复位 / Stopped, held until reset
    eAborting   := 90,  // 中止中：发出中止动作单拍 / Aborting, a one-scan abort request is issued
    eAborted    := 99   // 已中止：保持到复位 / Aborted, held until reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchPhaseBase
VAR_INPUT
    bEnable      : BOOL;                           // 使能，FALSE 时冻结状态与输出且不清零 [-] / Enable, freezes the phase without clearing it
    bStart       : BOOL;                           // 启动相，上升沿有效，仅空闲态受理（已终止态须先复位）[-] / Rising edge starts the phase in idle only, terminal states need a reset first
    bHold        : BOOL;                           // 请求暂停，上升沿有效，在步骤边界生效 [-] / Rising edge requests a hold at a step boundary
    bRestart     : BOOL;                           // 从已暂停恢复，上升沿有效，继续当前步骤 [-] / Rising edge resumes the current step
    bStop        : BOOL;                           // 请求停止，上升沿有效，在当前步骤完成后停 [-] / Rising edge requests a controlled stop
    bAbort       : BOOL;                           // 请求中止，上升沿有效，立即跳出步骤 [-] / Rising edge aborts immediately
    bReset       : BOOL;                           // 复位，上升沿有效，从已终止态回空闲 [-] / Rising edge returns the phase to idle
    bStepDone    : BOOL;                           // 步骤完成反馈（相内动作成功）[-] / Step completion feedback
    bStepFail    : BOOL;                           // 步骤失败反馈（相内动作失败）[-] / Step failure feedback
    nStepCount   : INT := 1;                       // 相内步骤数 [步]，有效域 1 到 32 / Steps in the phase, one to thirty-two
    tStepTimeout : TIME := T#60S;                  // 单步超时 [毫秒]，0 表示不监控 / Per-step timeout, zero disables the watchdog
    tHoldTimeout : TIME := T#600S;                 // 暂停超时 [毫秒]，0 表示不监控 / Hold timeout, zero disables the watchdog
END_VAR
VAR_OUTPUT
    ePhase       : E_DL_BatchPhaseState;           // 相状态，对外唯一状态出口 [-] / Phase state, the single state outlet
    nStepNo      : INT;                            // 当前步骤号，1 起，0 表示未进入 [步] / Current step number, zero before the first step
    bPhaseActive : BOOL;                           // 相处于活动族（执行、暂停族、收尾、停止、中止中）[-] / Phase is active
    bPhaseComplete : BOOL;                         // 相正常完成（完成相保持）[-] / Phase completed normally
    bRequestStep : BOOL;                           // 单拍：请执行当前步的动作 [-] / One-scan request to execute the current step
    bRequestAbort: BOOL;                           // 单拍：请执行中止动作 [-] / One-scan request to run the abort action
    uPhaseElapsed: UDINT;                          // 相净运行累计时间（不含暂停）[秒] / Accumulated running seconds excluding held time
    bError       : BOOL;                           // 故障级锁存，仅 0203 至 0206 置位 [-] / Latched fault, only fault level codes set it
    uErrorId     : UDINT;                          // 事件码，0 表示无事件 [代码] / Event code, zero means none
END_VAR
VAR
    fbTrigStart  : R_TRIG;                         // 启动沿检测，主周期无条件刷新 [-] / Start edge detector, refreshed unconditionally
    fbTrigHold   : R_TRIG;                         // 暂停沿检测，主周期无条件刷新 [-] / Hold edge detector, refreshed unconditionally
    fbTrigRestart: R_TRIG;                         // 恢复沿检测，主周期无条件刷新 [-] / Restart edge detector, refreshed unconditionally
    fbTrigStop   : R_TRIG;                         // 停止沿检测，主周期无条件刷新 [-] / Stop edge detector, refreshed unconditionally
    fbTrigAbort  : R_TRIG;                         // 中止沿检测，主周期无条件刷新 [-] / Abort edge detector, refreshed unconditionally
    fbTrigReset  : R_TRIG;                         // 复位沿检测，主周期无条件刷新 [-] / Reset edge detector, refreshed unconditionally
    fbTrigStepDone : R_TRIG;                       // 步骤完成上升沿，防电平常高时漏推进 [-] / Step completion rising edge
    fbStepWatch  : TON;                            // 单步超时监控，主周期无条件刷新 / Per-step watchdog, refreshed unconditionally
    fbHoldWatch  : TON;                            // 暂停超时监控，主周期无条件刷新 / Hold watchdog, refreshed unconditionally
    fbSecBase    : TON;                            // 一秒基准定时器，到点自复位 / One second base timer, self restarting
    bStepWatchBreak : BOOL;                        // 单步超时断输入一拍（步骤边界重计时）[-] / One-scan break of the step watchdog at a step boundary
    eState       : E_DL_BatchPhaseState := E_DL_BatchPhaseState.eIdle; // 内部相状态，对外经 ePhase 输出 [-] / Internal state exported as ePhase
    bInit        : BOOL := FALSE;                  // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    bFaultLatch  : BOOL;                           // 故障锁存，仅复位分支清除 [-] / Fault latch, cleared by the reset path only
    uErrInt      : UDINT;                          // 故障级码寄存，锁存型 [代码] / Latched fault level code register
    uInfoCode    : UDINT;                          // 本拍信息级码，每拍重算 [代码] / Info level code recomputed every scan
    nStep        : INT;                            // 当前步骤号 [步]，0 表示未进入 / Current step number, zero before the first step
    nStepUse     : INT := 1;                       // 生效步骤数 [步]，钳位后 / Effective step count after clamping
    bStepIssued  : BOOL;                           // 本步执行请求已发出 [-] / Step request issued flag
    bStepAcked   : BOOL;                           // 本步完成反馈已被消费（防一步多次完成）[-] / Step completion consumed flag
    bHoldArmed   : BOOL;                           // 暂停请求已登记、待步骤边界生效 [-] / Hold armed, pending a step boundary
    bStopArmed   : BOOL;                           // 停止请求已登记 [-] / Stop armed
    bCmdStart    : BOOL;                           // 本拍生效的启动命令 [-] / Effective start command of this scan
    bCmdHold     : BOOL;                           // 本拍生效的暂停命令 [-] / Effective hold command of this scan
    bCmdRestart  : BOOL;                           // 本拍生效的恢复命令 [-] / Effective restart command of this scan
    bCmdStop     : BOOL;                           // 本拍生效的停止命令 [-] / Effective stop command of this scan
    bCmdAbort    : BOOL;                           // 本拍生效的中止命令 [-] / Effective abort command of this scan
    bCmdReset    : BOOL;                           // 本拍生效的复位命令 [-] / Effective reset command of this scan
    bCmdDropped  : BOOL;                           // 本拍存在被丢弃的低优先命令 [-] / A low priority command was dropped this scan
    bStepMon     : BOOL;                           // 单步超时监控启用 [-] / Step watchdog enabled
    bHoldMon     : BOOL;                           // 暂停超时监控启用 [-] / Hold watchdog enabled
    tStepUse     : TIME := T#60S;                  // 生效单步超时 [毫秒] / Effective step timeout
    tHoldUse     : TIME := T#600S;                 // 生效暂停超时 [毫秒] / Effective hold timeout
    bStepTo      : BOOL;                           // 单步超时到点 [-] / Step timeout reached
    bHoldTo      : BOOL;                           // 暂停超时到点 [-] / Hold timeout reached
    bSecTick     : BOOL;                           // 一秒脉冲 [-] / One second tick
    bSecDone     : BOOL;                           // 秒基准定时器到点电平，用于自复位 [-] / Second base elapsed level used for the self restart
    uElapsed     : UDINT;                          // 相净运行秒累计 [秒] / Accumulated running seconds
END_VAR
VAR CONSTANT
    DL_STEP_MAX  : INT := 32;                      // 步骤数上限 [步] / Step count limit
    DL_STEP_MIN  : INT := 1;                       // 步骤数下限 [步] / Step count lower bound
    DL_SEC_MS    : TIME := T#1S;                   // 一秒基准 [毫秒] / One second base
    DL_TIME_ZERO : TIME := T#0S;                   // 时间零值基准 [毫秒] / Time zero reference
    DL_TIME_MIN  : TIME := T#1MS;                  // 时间参数最小正值 [毫秒] / Minimum positive time
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出确定性默认值（单拍标志每拍预清零，R25 第一律）
 *      Deterministic defaults first, one-scan flags pre-cleared every scan
 *-----------------------------------------------------------------------------*)
bRequestStep  := FALSE;                         // 步骤请求单拍预清零（Step request pulse pre-cleared）
bRequestAbort := FALSE;                         // 中止请求单拍预清零（Abort request pulse pre-cleared）
uInfoCode     := 16#0000_0000;                  // 信息级码每拍重算（Info code recomputed every scan）
bCmdDropped   := FALSE;                         // 丢弃标记预清零（Dropped flag pre-cleared）
bSecTick      := FALSE;                         // 秒脉冲预清零（Second tick pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（红线：实例在 CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStart);
fbTrigHold(CLK := bHold);
fbTrigRestart(CLK := bRestart);
fbTrigStop(CLK := bStop);
fbTrigAbort(CLK := bAbort);
fbTrigReset(CLK := bReset);
fbTrigStepDone(CLK := bStepDone);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据取非）
 *      First-scan initialisation following the single legal pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    nStep         := 0;                         // 步骤号清零（Step number cleared）
    nStepUse      := DL_STEP_MIN;               // 生效步骤数取下限（Effective step count at the lower bound）
    bStepIssued   := FALSE;                     // 请求已发出标志清零（Request issued flag cleared）
    bStepAcked    := FALSE;                     // 完成已消费标志清零（Completion consumed flag cleared）
    bHoldArmed    := FALSE;                     // 暂停登记清零（Hold armed cleared）
    bStopArmed    := FALSE;                     // 停止登记清零（Stop armed cleared）
    uElapsed      := 0;                         // 运行秒累计清零（Elapsed seconds cleared）
    bFaultLatch   := FALSE;                     // 故障锁存清零（Fault latch cleared）
    uErrInt       := 16#0000_0000;              // 故障码清零（Fault code cleared）
    eState        := E_DL_BatchPhaseState.eIdle; // 相状态复位为空闲（Phase state reset to idle）
    ePhase        := E_DL_BatchPhaseState.eIdle; // 状态出口复位（State outlet reset）
    nStepNo       := 0;                         // 步骤号出口清零（Step outlet cleared）
    uPhaseElapsed := 0;                         // 累计时间出口清零（Elapsed outlet cleared）
    bError        := FALSE;                     // 故障位出口清零（Fault outlet cleared）
    bInit         := TRUE;                      // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜参数钳位（步骤数越界属组态，钳位加信息码，不停机）
 *      Parameter clamping with an informational code only
 *-----------------------------------------------------------------------------*)
IF nStepCount < DL_STEP_MIN THEN
    nStepUse  := DL_STEP_MIN;                   // 步骤数下限钳位（Clamped to the lower bound）
    uInfoCode := 16#0005_0104;                  // 0104 步骤数越界已钳位（Step count clamped）
ELSIF nStepCount > DL_STEP_MAX THEN
    nStepUse  := DL_STEP_MAX;                   // 步骤数上限钳位（Clamped to the upper bound）
    uInfoCode := 16#0005_0104;                  // 0104 步骤数越界已钳位（Step count clamped）
ELSE
    nStepUse  := nStepCount;                    // 合法步骤数直通（Valid step count passed through）
END_IF

IF tStepTimeout <= DL_TIME_ZERO THEN
    tStepUse  := DL_TIME_MIN;                   // 零表示关闭监控，定时器仍给安全预置值（Zero disables, the timer keeps a safe preset）
    bStepMon  := FALSE;                         // 单步监控关闭（Step watchdog disabled）
    uInfoCode := 16#0005_0107;                  // 0107 单步超时监控关闭（Step watchdog disabled）
ELSE
    tStepUse  := tStepTimeout;                  // 合法超时直通（Valid timeout passed through）
    bStepMon  := TRUE;                          // 单步监控启用（Step watchdog enabled）
END_IF

IF tHoldTimeout <= DL_TIME_ZERO THEN
    tHoldUse  := DL_TIME_MIN;                   // 零表示关闭监控（Zero disables the watchdog）
    bHoldMon  := FALSE;                         // 暂停监控关闭（Hold watchdog disabled）
    uInfoCode := 16#0005_0107;                  // 0107 暂停超时监控关闭（Hold watchdog disabled）
ELSE
    tHoldUse  := tHoldTimeout;                  // 合法超时直通（Valid timeout passed through）
    bHoldMon  := TRUE;                          // 暂停监控启用（Hold watchdog enabled）
END_IF
IF nStep < 0 THEN
    nStep := 0;                                 // 步骤号负值防御，正常流程不可达（Defensive clamp, unreachable normally）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜命令优先级裁决（中止 高于 停止 高于 暂停 高于 恢复 高于 启动；不排队）
 *      Command arbitration by a strict priority order, dropped commands are not queued
 *-----------------------------------------------------------------------------*)
bCmdAbort   := fbTrigAbort.Q;                   // 最高优先：中止（Highest priority, abort）
bCmdStop    := fbTrigStop.Q AND (NOT bCmdAbort); // 次优先：停止（Next, stop）
bCmdHold    := fbTrigHold.Q AND (NOT bCmdAbort) AND (NOT bCmdStop); // 次优先：暂停（Next, hold）
bCmdRestart := fbTrigRestart.Q AND (NOT bCmdAbort) AND (NOT bCmdStop) AND (NOT bCmdHold); // 次优先：恢复（Next, restart）
bCmdStart   := fbTrigStart.Q AND (NOT bCmdAbort) AND (NOT bCmdStop) AND (NOT bCmdHold) AND (NOT bCmdRestart); // 最低优先：启动（Lowest, start）
bCmdReset   := fbTrigReset.Q;                   // 复位独立通道，不参与优先级（Reset is an independent channel）

IF (bCmdAbort AND (fbTrigStop.Q OR fbTrigHold.Q OR fbTrigRestart.Q OR fbTrigStart.Q)) OR
   (bCmdStop AND (fbTrigHold.Q OR fbTrigRestart.Q OR fbTrigStart.Q)) OR
   (bCmdHold AND (fbTrigRestart.Q OR fbTrigStart.Q)) OR
   (bCmdRestart AND fbTrigStart.Q) THEN
    bCmdDropped := TRUE;                        // 同拍多命令：标记丢弃提示（Concurrent commands, mark the drop）
END_IF
IF bCmdDropped THEN
    uInfoCode := 16#0005_0105;                  // 0105 低优先命令已丢弃（Low priority command dropped）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜定时器无条件刷新（入口条件取当前相状态；掉使能时冻结计时）
 *      Timers refreshed unconditionally, gated by enable and by the phase state
 *-----------------------------------------------------------------------------*)
fbStepWatch(IN := bEnable AND bStepMon AND (NOT bStepWatchBreak) AND
                 ((eState = E_DL_BatchPhaseState.eRunning) OR
                  (eState = E_DL_BatchPhaseState.eCompleting) OR
                  (eState = E_DL_BatchPhaseState.eStopping)),
            PT := tStepUse);
bStepTo := fbStepWatch.Q;                       // 超时判定在实例调用后取用（Verdict read after the call）
bStepWatchBreak := FALSE;                       // 断输入脉冲在实例调用后自清（Break pulse self-cleared after the call）

fbHoldWatch(IN := bEnable AND bHoldMon AND (eState = E_DL_BatchPhaseState.eHeld), PT := tHoldUse);
bHoldTo := fbHoldWatch.Q;                       // 超时判定在实例调用后取用（Verdict read after the call）

fbSecBase(IN := bEnable AND (NOT bSecDone), PT := DL_SEC_MS);
bSecTick := fbSecBase.Q;                        // 秒脉冲在实例调用后取用（Tick read after the call）
bSecDone := fbSecBase.Q;                        // 到点电平在实例调用后更新，供下拍自复位（Elapsed level refreshed after the call）

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（枚举每个成员均有标签，末尾 ELSE 兜底到已中止）
 *      Main state machine, one label per member plus a trailing ELSE fallback
 *      掉使能时整体冻结：状态、步骤号与单拍请求都不变（A disabled phase is frozen）
 *-----------------------------------------------------------------------------*)
IF bEnable THEN
    CASE eState OF

        E_DL_BatchPhaseState.eIdle: // 空闲：等启动，输出全复位
            nStep        := 0;              // 步骤号归零（Step number cleared）
            bStepIssued  := FALSE;          // 请求标志清零（Request flag cleared）
            bStepAcked   := FALSE;          // 完成消费标志清零（Completion flag cleared）
            bHoldArmed   := FALSE;          // 暂停登记清零（Hold armed cleared）
            bStopArmed   := FALSE;          // 停止登记清零（Stop armed cleared）
            IF bCmdStart THEN
                nStep       := 1;           // 从第一步开始（Start from the first step）
                bStepIssued := FALSE;       // 请求待下拍发出（The request is issued on the next scan）
                eState      := E_DL_BatchPhaseState.eRunning; // 进执行相（Enter the running phase）
            END_IF

        E_DL_BatchPhaseState.eRunning: // 执行：推进步骤，处理四类命令
            IF bCmdAbort THEN
                bHoldArmed := FALSE;        // 中止优先：清暂停登记（Abort wins, clear the hold armed flag）
                bStopArmed := FALSE;        // 清停止登记（Clear the stop armed flag）
                eState     := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
            ELSIF bStepFail THEN
                IF NOT bFaultLatch THEN
                    bFaultLatch := TRUE;    // 步骤失败：锁故障（Step failure, latch the fault）
                    uErrInt     := 16#0005_0204; // 0204 步骤失败（Step failure）
                END_IF
                eState := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
            ELSIF bCmdHold THEN
                bHoldArmed := TRUE;         // 受理暂停，寄存器置位（The hold request is accepted）
                IF NOT bStepIssued THEN
                    eState := E_DL_BatchPhaseState.eHeld;    // 本步尚未开始：直接暂停（The step has not started, hold at once）
                ELSE
                    eState := E_DL_BatchPhaseState.eHolding; // 本步进行中：等步骤边界（Wait for the step boundary）
                END_IF
            ELSE
                IF bCmdStop THEN
                    bStopArmed := TRUE;     // 登记停止，在步骤边界生效（Arm the stop at the boundary）
                END_IF
                IF fbTrigStepDone.Q AND (NOT bStepAcked) THEN
                    bStepAcked  := TRUE;    // 消费本次完成（Consume the completion）
                    bStepIssued := FALSE;   // 下一步的请求待重新发出（The next step needs a new request）
                    bStepWatchBreak := TRUE; // 步骤边界：单步超时断输入一拍，按步重计时（Restart the step watchdog at the boundary）
                    IF bStopArmed THEN
                        eState := E_DL_BatchPhaseState.eStopping; // 边界已到：进停止相（Boundary reached, stop）
                    ELSIF nStep >= nStepUse THEN
                        eState := E_DL_BatchPhaseState.eCompleting; // 步骤耗尽：进收尾相（Steps exhausted, complete）
                    ELSE
                        nStep := nStep + 1; // 推进到下一步（Advance to the next step）
                    END_IF
                ELSIF bStepTo THEN
                    IF NOT bFaultLatch THEN
                        bFaultLatch := TRUE; // 单步超时：锁故障（Step timeout, latch the fault）
                        uErrInt     := 16#0005_0203; // 0203 单步超时（Step timeout）
                    END_IF
                    eState := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
                ELSE
                    IF bStepDone THEN
                        bStepAcked := TRUE;  // 反馈仍高：保持已消费（Feedback still high, keep the consumed flag）
                    ELSE
                        bStepAcked := FALSE; // 反馈落下：允许下一次消费（Feedback dropped, allow the next consumption）
                    END_IF
                    IF NOT bStepIssued THEN
                        bRequestStep := TRUE; // 单拍步骤请求（One-scan step request）
                        bStepIssued  := TRUE; // 置请求已发（Mark the request as issued）
                    END_IF
                END_IF
            END_IF

        E_DL_BatchPhaseState.eCompleting: // 收尾：等收尾动作反馈，不占步骤号
            IF bCmdAbort THEN
                eState := E_DL_BatchPhaseState.eAborting; // 中止优先（Abort wins）
            ELSIF bStepFail THEN
                IF NOT bFaultLatch THEN
                    bFaultLatch := TRUE;    // 收尾失败：锁故障（Clean-up failure, latch the fault）
                    uErrInt     := 16#0005_0204; // 0204 步骤失败（Step failure）
                END_IF
                eState := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
            ELSIF fbTrigStepDone.Q AND (NOT bStepAcked) THEN
                bStepAcked := TRUE;         // 收尾完成（Clean-up finished）
                eState     := E_DL_BatchPhaseState.eComplete; // 进完成相（Enter the complete phase）
            ELSIF bStepTo THEN
                IF NOT bFaultLatch THEN
                    bFaultLatch := TRUE;    // 收尾超时：锁故障（Clean-up timeout, latch the fault）
                    uErrInt     := 16#0005_0203; // 0203 单步超时（Step timeout）
                END_IF
                eState := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
            ELSE
                IF bStepDone THEN
                    bStepAcked := TRUE;     // 反馈仍高：保持已消费（Feedback still high）
                ELSE
                    bStepAcked := FALSE;    // 反馈落下：允许下一次消费（Feedback dropped）
                END_IF
            END_IF

        E_DL_BatchPhaseState.eComplete: // 完成：保持到复位，已终止态不受理启动与中止
            bStepIssued := FALSE;           // 终止态不保留步骤请求标志（No step request lingers in a terminal state）

        E_DL_BatchPhaseState.eHolding: // 暂停请求：仅在步骤边界真正暂停
            IF bCmdAbort THEN
                eState := E_DL_BatchPhaseState.eAborting; // 中止优先（Abort wins）
            ELSIF bCmdStop THEN
                bStopArmed := TRUE;         // 停止优先于暂停（Stop outranks hold）
                eState     := E_DL_BatchPhaseState.eStopping; // 进停止相（Enter the stopping phase）
            ELSIF bHoldArmed AND (NOT bStepIssued) THEN
                eState := E_DL_BatchPhaseState.eHeld; // 步骤尚未开始：可安全暂停（The step has not started, safe to hold）
            ELSIF fbTrigStepDone.Q AND (NOT bStepAcked) THEN
                bStepAcked  := TRUE;        // 当前步完成反馈到达：边界已到（The boundary has arrived）
                bStepIssued := FALSE;       // 清请求标志（Clear the issued flag）
                eState      := E_DL_BatchPhaseState.eHeld; // 进已暂停相（Enter the held phase）
            ELSE
                IF bStepDone THEN
                    bStepAcked := TRUE;     // 反馈仍高：保持已消费（Feedback still high）
                ELSE
                    bStepAcked := FALSE;    // 反馈落下：允许下一次消费（Feedback dropped）
                END_IF
            END_IF

        E_DL_BatchPhaseState.eHeld: // 已暂停：不推进、不发请求
            IF bCmdAbort THEN
                eState := E_DL_BatchPhaseState.eAborting; // 中止优先（Abort wins）
            ELSIF bCmdStop THEN
                bStopArmed := TRUE;         // 登记停止（Arm the stop）
                eState     := E_DL_BatchPhaseState.eStopping; // 进停止相（Enter the stopping phase）
            ELSIF bCmdRestart THEN
                bStepIssued := FALSE;       // 恢复：请求待重发（Restart, the request is reissued）
                bStepAcked  := FALSE;       // 恢复：重新等待本步完成反馈（Restart, wait for a fresh completion）
                eState      := E_DL_BatchPhaseState.eRestarting; // 进恢复相（Enter the restarting phase）
            ELSIF bHoldTo THEN
                IF NOT bFaultLatch THEN
                    bFaultLatch := TRUE;    // 暂停超时：锁故障（Hold timeout, latch the fault）
                    uErrInt     := 16#0005_0205; // 0205 暂停超时（Hold timeout）
                END_IF
                eState := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
            ELSE
                bHoldArmed := TRUE;         // 保持登记，等待恢复或停止（Keep the hold armed）
            END_IF

        E_DL_BatchPhaseState.eRestarting: // 恢复中：重发当前步请求，不重头
            bRequestStep := TRUE;           // 重发当前步请求（Reissue the current step request）
            bStepIssued  := TRUE;           // 置请求已发（Mark the request as issued）
            bStepAcked   := FALSE;          // 重新等待本步完成（Wait for a fresh completion）
            uInfoCode    := 16#0005_0106;   // 0106 从暂停恢复，步骤号不重置（Restarted from hold, the step number is kept）
            eState       := E_DL_BatchPhaseState.eRunning; // 回执行相（Back to running）

        E_DL_BatchPhaseState.eStopping: // 停止中：等收尾反馈
            IF bCmdAbort THEN
                eState := E_DL_BatchPhaseState.eAborting; // 中止优先（Abort wins）
            ELSIF fbTrigStepDone.Q AND (NOT bStepAcked) THEN
                bStepAcked := TRUE;         // 收尾完成（Wrap-up finished）
                eState     := E_DL_BatchPhaseState.eStopped; // 进已停相（Enter the stopped phase）
            ELSIF bStepTo THEN
                IF NOT bFaultLatch THEN
                    bFaultLatch := TRUE;    // 收尾超时：锁故障（Wrap-up timeout, latch the fault）
                    uErrInt     := 16#0005_0203; // 0203 单步超时（Step timeout）
                END_IF
                eState := E_DL_BatchPhaseState.eAborting; // 进中止相（Enter the aborting phase）
            ELSE
                IF bStepDone THEN
                    bStepAcked := TRUE;     // 反馈仍高：保持已消费（Feedback still high）
                ELSE
                    bStepAcked := FALSE;    // 反馈落下：允许下一次消费（Feedback dropped）
                END_IF
            END_IF

        E_DL_BatchPhaseState.eStopped: // 已停：保持到复位，已终止态不受理启动与中止
            bStepIssued := FALSE;           // 终止态不保留步骤请求标志（No step request lingers in a terminal state）

        E_DL_BatchPhaseState.eAborting: // 中止中：发出中止动作单拍后立即进已中止
            bRequestAbort := TRUE;          // 单拍中止动作请求（One-scan abort action request）
            bHoldArmed    := FALSE;         // 清暂停登记（Clear the hold armed flag）
            bStopArmed    := FALSE;         // 清停止登记（Clear the stop armed flag）
            eState        := E_DL_BatchPhaseState.eAborted; // 进已中止相（Enter the aborted phase）

        E_DL_BatchPhaseState.eAborted: // 已中止：保持到复位，步骤号保留供报表追溯
            bStepIssued := FALSE;           // 终止态不保留步骤请求标志（No step request lingers in a terminal state）

        ELSE
            bFaultLatch := TRUE;            // 非法状态兜底锁存（Illegal state latched）
            uErrInt     := 16#0005_0206;    // 0206 非法状态兜底（Illegal state fallback code）
            eState      := E_DL_BatchPhaseState.eAborted; // 直接进已中止，不回空闲（Go straight to aborted）
    END_CASE

    (* 秒脉冲累加：只在执行相计时，暂停与收尾不计入相净运行时间 *)
    IF bSecTick AND (eState = E_DL_BatchPhaseState.eRunning) THEN
        uElapsed := uElapsed + 1;           // 相净运行秒累加（Accumulate a running second）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜复位（仅已终止态受理；清步骤号、完成标志与故障锁存）
 *      Reset is accepted from the terminal states only
 *-----------------------------------------------------------------------------*)
IF bCmdReset THEN
    IF (eState = E_DL_BatchPhaseState.eComplete) OR (eState = E_DL_BatchPhaseState.eStopped) OR
       (eState = E_DL_BatchPhaseState.eAborted) OR (eState = E_DL_BatchPhaseState.eIdle) THEN
        nStep       := 0;                   // 步骤号归零（Step number cleared）
        bStepIssued := FALSE;               // 请求标志清零（Request flag cleared）
        bStepAcked  := FALSE;               // 完成消费标志清零（Completion flag cleared）
        bHoldArmed  := FALSE;               // 暂停登记清零（Hold armed cleared）
        bStopArmed  := FALSE;               // 停止登记清零（Stop armed cleared）
        bFaultLatch := FALSE;               // 清故障锁存（Clear the fault latch）
        uErrInt     := 16#0000_0000;        // 清故障码（Clear the fault code）
        eState      := E_DL_BatchPhaseState.eIdle; // 回空闲（Back to idle）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜出口映射（状态、步骤号、活动族、完成标志、累计时间与码位定级）
 *      Outlet mapping with a single priority chain for the event code
 *-----------------------------------------------------------------------------*)
ePhase        := eState;                        // 相状态出口（Phase state outlet）
nStepNo       := nStep;                         // 步骤号出口（Step number outlet）
uPhaseElapsed := uElapsed;                      // 净运行时间出口（Elapsed outlet）
bPhaseComplete := (eState = E_DL_BatchPhaseState.eComplete); // 完成标志由状态派生（Derived from the state）
bPhaseActive  := (eState = E_DL_BatchPhaseState.eRunning) OR
                 (eState = E_DL_BatchPhaseState.eCompleting) OR
                 (eState = E_DL_BatchPhaseState.eHolding) OR
                 (eState = E_DL_BatchPhaseState.eHeld) OR
                 (eState = E_DL_BatchPhaseState.eRestarting) OR
                 (eState = E_DL_BatchPhaseState.eStopping) OR
                 (eState = E_DL_BatchPhaseState.eAborting); // 活动族派生（Active family derived）
bError        := bFaultLatch;                   // 故障位只反映故障级锁存（Fault bit reflects the latch only）
IF bError THEN
    uErrorId := uErrInt;                        // 故障级码优先透出（Fault level code has priority）
ELSE
    uErrorId := uInfoCode;                      // 无故障透出本拍信息级码（Info code exposed otherwise）
END_IF
END_FUNCTION_BLOCK
