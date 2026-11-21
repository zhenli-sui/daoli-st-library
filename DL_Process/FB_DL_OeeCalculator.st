(*==============================================================================
 * 组件名称 (Component)  : FB_DL_OeeCalculator
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺统计功能块（Function Block · OEE 班次统计引擎）
 * 功能简述 (Function)   : 设备综合效率（OEE）班次级统计引擎。OEE = 时间开动
 *                         率 × 性能开动率 × 合格品率（oee.com / ISO 22400-2
 *                         公开口径）。停机时间经 PackML 根因位语义分账（计划
 *                         停机 vs 计划外停机），与 FB_DL_PackMlStateMachine
 *                         17 态衔接（根因位引脚注入，不引组件实例）。时间累
 *                         计为扫描周期累加式，周期基准经 tCycleTime 引脚注
 *                         入（调用方可用既有 FB_DL_CycleTimeMeasure 语义供
 *                         给，禁读 CPU 钟）。
 * 公约遵循 (Convention) : 0.1/R23 显式班次启停驱动（累计由 bShiftStart 显式
 *                         清零启动、bShiftEnd 冻结），无自动首扫初始化语义，
 *                         免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 边沿实例主
 *                         体最前部无条件刷新；0.7/R15 故障级锁存仅复位路径清
 *                         码；0.9 REAL/LREAL 输入先做非数自比检测再比较；0.14
 *                         全部除法带 ABS(分母) > 1E-6 防零分支并置码。
 *                         0.8 故障码段位 16#0005_xxxx（经 DL_Process
 *                         VERSION.md 码表核对，0005_0200 / 0005_0110~0102 均
 *                         未占用）：
 *                         【故障级】0005_0200 理想节拍非法；
 *                         【信息级】0005_0110 双停机根因同真（分账歧义）、
 *                         0005_0111 性能率超 100 封顶（负损失提示）、
 *                         0005_0112 零计划时间。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 三因子除零防御/非有限值防
 *                         御/浮点容差 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R7 三个边沿实例主体
 *                         最前部无条件刷新 ✓｜R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 时间分账优先级：bUnplannedDown 优先于 bPlannedDown
 *                           （同真置信级 0005_0110，分账入计划外——保守侧）；
 *                         ② tPlannedTime = 计划生产时间（不含计划停机）；
 *                           tDownTime = 计划+计划外停机累计；tRunTime =
 *                           bMachineRunning 且非停机期间累计；
 *                         ③ 三因子防御：PlannedTime=0 → 全因子 0 + 信息级；
 *                           RunTime=0 → Availability/Performance 0、Quality
 *                           100；TotalCount=0 → Quality 100；
 *                         ④ Performance = (理想节拍 × 总数) / 运行秒数 × 100，
 *                           >100 封顶并置信息级 0005_0111（负损失提示：节拍
 *                           偏短或计数异常）；
 *                         ⑤ 根因细分：bHeldByMachine/bSuspendedByLine 仅在
 *                           bUnplannedDown 期间按上升沿计数（nUnplannedByHold
 *                           / nUnplannedBySuspend）。
 * 开源溯源 (Origin)     : 来源标签 packml-oee（RAW_NOTES_R7 S-8：oee.com 与
 *                         ISO 22400-2 公开口径——三因子定义、计划/计划外停
 *                         机分账、根因位语义，公开标准资料，仅借鉴口径；实
 *                         现、防御与码位 100% 本库独立设计，clean-room 未复
 *                         制源码）。
 * 验收向量 (Acceptance) :
 *   V1 oee.com 标准算例等价缩放复算：班次 420min、运行 373min、节拍 1.2s、
 *      总数 14154、不合格 421 → 三因子与 OEE 逐项对表（含时延项换算）；
 *   V2 零产量：TotalCount=0 → Quality=100；
 *   V3 双停机歧义：bPlannedDown+bUnplannedDown 同真 → 信息级 0005_0110，分
 *      账入计划外；
 *   V4 性能封顶：理想节拍偏短 → Performance 封顶 100 + 0005_0111；
 *   V5 班次启停冻结：bShiftStart 清零启动；bShiftEnd 冻结三因子输出。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Process OEE 统计件）
 *   2026-11-15  v1.0.1  终审修复 2 处：① nGoodCount 派生无下溢防御（拒绝脉
 *                       冲多于完工脉冲时 UDINT 无符号下溢），补钳零分支；
 *                       ② tShiftLength 声明未参与计算（注释级勘误：标注本
 *                       轮预留语义）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_OeeCalculator
VAR_INPUT
    bMachineRunning  : BOOL;            // 设备运行中（Machine running），TRUE=运行时间累加 / Machine running, run time accumulates
    bPlannedDown     : BOOL;            // 计划停机中（Planned downtime，换型/休息/保养），TRUE=计划停机累加 / Planned downtime (changeover, break, maintenance)
    bUnplannedDown   : BOOL;            // 计划外停机中（Unplanned downtime，故障/缺料），TRUE=计划外停机累加；与 bPlannedDown 同真 → 信息级（分账歧义）/ Unplanned downtime, dual-true raises ambiguity info
    bHeldByMachine   : BOOL;            // 设备侧保持根因位（Held by machine root cause，PackML Held 语义），参与计划外停机细分 / Machine-side hold root-cause bit
    bSuspendedByLine : BOOL;            // 产线侧暂停根因位（Suspended by line root cause，PackML Suspended 语义）/ Line-side suspend root-cause bit
    bPartFinished    : BOOL;            // 完工计数脉冲（Part finished pulse），R_TRIG 上升沿 +1 总数 / Part finished pulse, total +1 on edge
    bPartRejected    : BOOL;            // 不合格计数脉冲（Part rejected pulse），上升沿 +1 不合格数 / Part rejected pulse, reject +1 on edge
    fIdealCycleTime  : REAL := 10.0;    // 理想节拍（Ideal cycle time）[s]，域 >0，默认 10.0 / Ideal cycle time [s], > 0
    tShiftLength     : TIME := T#8H;    // 班次总时长（Shift length），默认 T#8H；本轮预留引脚（时间分账采用
                                        // 状态累加式，未参与计算；后续轮次用于班次自动截止/计划时间上限校验）
                                        // Shift length, reserved this round, not used in accounting (v1.0.1 note)
    tCycleTime       : TIME := T#10MS;  // 扫描周期基准（Cycle time base），累计基准，由调用方注入（FB_DL_CycleTimeMeasure 语义）；非数/非正值回落常量 / Scan cycle base injected by caller, non-finite falls back to constant
    bShiftStart      : BOOL;            // 班次开始指令（Shift start），上升沿清零全部累计并启动统计 / Shift start edge clears and arms the statistics
    bShiftEnd        : BOOL;            // 班次结束指令（Shift end），上升沿冻结三因子输出 / Shift end edge freezes the factor outputs
    bReset           : BOOL;            // 上升沿复位故障（Reset edge）/ Rising edge resets fault
END_VAR
VAR_OUTPUT
    fAvailability : REAL;               // 时间开动率（Availability）[%]，0~100 / Availability [%]
    fPerformance  : REAL;               // 性能开动率（Performance）[%]，0~100，封顶 100 / Performance [%], capped at 100
    fQuality      : REAL;               // 合格品率（Quality）[%]，0~100，零产量取 100 / Quality [%], 100 when zero output
    fOee          : REAL;               // 设备综合效率（OEE）[%]，三因子连乘 / OEE [%], product of three factors
    nTotalCount   : UDINT;              // 总数（Total count）/ Total part count
    nGoodCount    : UDINT;              // 合格数（Good count）/ Good part count
    nRejectCount  : UDINT;              // 不合格数（Reject count）/ Rejected part count
    tPlannedTime  : TIME;               // 计划生产时间累计（Planned production time，不含计划停机）/ Planned production time, planned downtime excluded
    tRunTime      : TIME;               // 运行时间累计（Run time）/ Run time accumulated
    tDownTime     : TIME;               // 停机时间累计（Down time，计划+计划外）/ Down time accumulated (planned + unplanned)
    nUnplannedByHold   : UDINT;         // 计划外停机中机内保持次数（Unplanned holds）/ Unplanned hold occurrences
    nUnplannedBySuspend: UDINT;         // 计划外停机中产线挂起次数（Unplanned suspends）/ Unplanned suspend occurrences
    bFault        : BOOL;               // 故障标志（Fault flag），显式排除信息级 / Fault flag, info codes excluded
    uErrorId      : UDINT;              // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, family 16#0005_xxxx
END_VAR
VAR
    _bFaultLatch    : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt    : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode      : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bShiftActive   : BOOL;             // 班次统计激活（Shift statistics armed）/ Shift statistics armed
    _bShiftFrozen   : BOOL;             // 班次冻结（Shift frozen by bShiftEnd）/ Shift frozen
    _fCycleEff      : REAL := 10.0;     // 防御后生效理想节拍（Sanitized ideal cycle time）[s] / Sanitized ideal cycle time [s]
    _tCycleBase     : TIME := T#10MS;   // 防御后生效周期基准（Sanitized cycle base）/ Sanitized cycle base
    _tPlannedInt    : TIME;             // 内部计划生产时间累计（Internal planned time）/ Internal planned time
    _tRunInt        : TIME;             // 内部运行时间累计（Internal run time）/ Internal run time
    _tDownInt       : TIME;             // 内部停机时间累计（Internal down time）/ Internal down time
    _fAvailInt      : REAL;             // 内部时间开动率（Internal availability）[%] / Internal availability [%]
    _fPerfInt       : REAL;             // 内部性能开动率（Internal performance）[%] / Internal performance [%]
    _fQualInt       : REAL;             // 内部合格品率（Internal quality）[%] / Internal quality [%]
    _fRunSec        : REAL;             // 运行时间秒数（Run time in seconds），TIME 显式换算 / Run time seconds, explicit conversion
    _fPlannedSec    : REAL;             // 计划时间秒数（Planned time in seconds）/ Planned time seconds
    _bPerfCapped    : BOOL;             // 本拍性能封顶发生（Performance capped this scan）/ Performance capped this scan
    _fbTrigFinished : R_TRIG;           // 完工脉冲沿（Part finished edge）/ Part finished edge detector
    _fbTrigRejected : R_TRIG;           // 不合格脉冲沿（Part rejected edge）/ Part rejected edge detector
    _fbTrigStart    : R_TRIG;           // 班次开始沿（Shift start edge）/ Shift start edge detector
    _fbTrigEnd      : R_TRIG;           // 班次结束沿（Shift end edge）/ Shift end edge detector
    _fbTrigReset    : R_TRIG;           // 复位沿（Reset edge）/ Reset edge detector
    _fbTrigHold     : R_TRIG;           // 机内保持根因沿（Hold root-cause edge）/ Hold root-cause edge detector
    _fbTrigSuspend  : R_TRIG;           // 产线挂起根因沿（Suspend root-cause edge）/ Suspend root-cause edge detector
END_VAR
VAR CONSTANT
    DL_REAL_EPS        : REAL := 1.0E-6; // 浮点防零容差（Float divide-guard epsilon）/ Float divide-guard epsilon
    DL_CYCLE_FALLBACK  : TIME := T#10MS; // 周期基准回落常量（Cycle base fallback）/ Cycle base fallback
    DL_CO_FACTOR       : REAL := 10000.0; // 三因子连乘归一系数（Three-factor product normalization）/ Product normalization factor
END_VAR

// ============================================================================
// 段 1｜边沿实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all edge instances (R7/0.5)
// ============================================================================
_fbTrigFinished(CLK := bPartFinished);
_fbTrigRejected(CLK := bPartRejected);
_fbTrigStart(CLK := bShiftStart);
_fbTrigEnd(CLK := bShiftEnd);
_fbTrigReset(CLK := bReset);
_fbTrigHold(CLK := bHeldByMachine AND bUnplannedDown);        // 根因沿仅计划外期间有效（Root-cause edge only during unplanned down）
_fbTrigSuspend(CLK := bSuspendedByLine AND bUnplannedDown);  // 根因沿仅计划外期间有效（Root-cause edge only during unplanned down）

// ============================================================================
// 段 2｜信息级预清零 + 复位路径 + 参数防御（0.9：非数自比，默认值先行）
//      Info preset + reset path + parameter sanitation (0.9)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）

IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;        // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
END_IF

IF fIdealCycleTime <> fIdealCycleTime THEN // 理想节拍非数自比（Ideal cycle NaN self-compare）
    _bFaultLatch := TRUE;         // 参数非法锁存（Invalid parameter latch）
    _uErrorIdInt := 16#0005_0200; // 0005_0200 理想节拍非法【故障级】/ Invalid ideal cycle time, fault level
ELSIF fIdealCycleTime <= DL_REAL_EPS THEN
    _bFaultLatch := TRUE;         // 节拍非正锁存（Non-positive cycle latch）
    _uErrorIdInt := 16#0005_0200; // 0005_0200 理想节拍非法【故障级】/ Invalid ideal cycle time, fault level
ELSE
    _fCycleEff := fIdealCycleTime; // 生效节拍镜像（Effective cycle mirror）
END_IF

IF tCycleTime <> tCycleTime THEN  // 周期基准非数自比（Cycle base NaN self-compare）
    _tCycleBase := DL_CYCLE_FALLBACK; // 回落常量基准（Fallback constant base）
ELSIF tCycleTime <= T#0S THEN
    _tCycleBase := DL_CYCLE_FALLBACK; // 非正基准回落（Non-positive base falls back）
ELSE
    _tCycleBase := tCycleTime;    // 生效基准镜像（Effective base mirror）
END_IF

// ============================================================================
// 段 3｜班次启停与计数（R15：故障锁存期间累计冻结）
//      Shift start/end and counting (accumulation frozen while latched)
// ============================================================================
IF _fbTrigStart.Q AND (NOT _bFaultLatch) THEN
    _bShiftActive := TRUE;        // 班次激活（Shift armed）
    _bShiftFrozen := FALSE;       // 解除冻结（Unfreeze）
    nTotalCount := 0;             // 总数清零（Total cleared）
    nGoodCount := 0;              // 合格数清零（Good cleared）
    nRejectCount := 0;            // 不合格数清零（Reject cleared）
    nUnplannedByHold := 0;        // 保持次数清零（Hold count cleared）
    nUnplannedBySuspend := 0;     // 挂起次数清零（Suspend count cleared）
    _tPlannedInt := T#0S;         // 计划时间清零（Planned time cleared）
    _tRunInt := T#0S;             // 运行时间清零（Run time cleared）
    _tDownInt := T#0S;            // 停机时间清零（Down time cleared）
END_IF
IF _fbTrigEnd.Q THEN
    _bShiftFrozen := TRUE;        // 班次结束冻结（Shift frozen）
END_IF

IF _bShiftActive AND (NOT _bShiftFrozen) AND (NOT _bFaultLatch) THEN
    IF _fbTrigFinished.Q THEN
        nTotalCount := nTotalCount + 1;   // 完工总数累加（Total increment）
    END_IF
    IF _fbTrigRejected.Q THEN
        nRejectCount := nRejectCount + 1; // 不合格数累加（Reject increment）
    END_IF
    IF _fbTrigHold.Q THEN
        nUnplannedByHold := nUnplannedByHold + 1; // 机内保持计数（Hold count）
    END_IF
    IF _fbTrigSuspend.Q THEN
        nUnplannedBySuspend := nUnplannedBySuspend + 1; // 产线挂起计数（Suspend count）
    END_IF
    IF nTotalCount >= nRejectCount THEN
        nGoodCount := nTotalCount - nRejectCount; // 合格数派生（Good derived）
    ELSE
        nGoodCount := 0;              // 不合格超总数防御：UDINT 下溢钳零（v1.0.1：拒绝脉冲
                                      // 多于完工脉冲时防无符号下溢）/ Underflow guard (v1.0.1)
    END_IF

    // —— 时间分账（优先级：计划外 > 计划 > 运行）——
    //     Time accounting (priority: unplanned > planned > running)
    IF bPlannedDown AND bUnplannedDown THEN
        _uInfoCode := 16#0005_0110;   // 0005_0110 双停机根因同真【信息级】/ Dual downtime root causes, info level
    END_IF
    IF bUnplannedDown THEN
        _tDownInt := _tDownInt + _tCycleBase; // 计划外停机分账（Unplanned down accounting, conservative side on ambiguity）
    ELSIF bPlannedDown THEN
        _tDownInt := _tDownInt + _tCycleBase; // 计划停机分账（Planned down accounting）
    ELSE
        _tPlannedInt := _tPlannedInt + _tCycleBase; // 计划生产时间累计（Planned production accumulates）
        IF bMachineRunning THEN
            _tRunInt := _tRunInt + _tCycleBase;     // 运行时间累计（Run time accumulates）
        END_IF
    END_IF
END_IF

// ============================================================================
// 段 4｜三因子计算（0.14：全部除法带防零分支并置码）
//      Three-factor computation (all divisions guarded with error codes)
// ============================================================================
_fAvailInt := 0.0;                // 出口默认值先赋（Default outlets first）
_fPerfInt := 0.0;
_fQualInt := 0.0;
_fPlannedSec := TIME_TO_REAL(_tPlannedInt) / 1000.0; // TIME→REAL 毫秒换算秒（ms to seconds）
_fRunSec := TIME_TO_REAL(_tRunInt) / 1000.0;         // 运行秒数（Run seconds）

IF NOT _bShiftActive THEN
    _uInfoCode := 16#0005_0112;   // 0005_0112 零计划时间（班次未激活）【信息级】/ Zero planned time (shift not armed), info level
ELSIF ABS(_fPlannedSec) > DL_REAL_EPS THEN
    _fAvailInt := (_fRunSec / _fPlannedSec) * 100.0; // 时间开动率（Availability, divisor proven non-zero）
    IF ABS(_fRunSec) > DL_REAL_EPS THEN
        _fPerfInt := (_fCycleEff * UDINT_TO_REAL(nTotalCount) / _fRunSec) * 100.0; // 性能开动率（Performance, divisor proven non-zero）
    ELSE
        _fPerfInt := 0.0;         // 零运行时间性能取 0（Zero run time: performance 0）
    END_IF
    IF nTotalCount > 0 THEN
        _fQualInt := (UDINT_TO_REAL(nGoodCount) / UDINT_TO_REAL(nTotalCount)) * 100.0; // 合格品率（Quality, divisor proven non-zero）
    ELSE
        _fQualInt := 100.0;       // 零产量合格率取 100（Zero output: quality 100）
    END_IF
ELSE
    _uInfoCode := 16#0005_0112;   // 0005_0112 零计划时间【信息级】/ Zero planned time, info level
END_IF

_bPerfCapped := _fPerfInt > 100.0; // 封顶判定（Cap verdict）
IF _bPerfCapped THEN
    _fPerfInt := 100.0;           // 性能封顶（Performance capped）
    _uInfoCode := 16#0005_0111;   // 0005_0111 性能率超 100 封顶【信息级】（负损失提示：节拍偏短或计数异常）/ Performance capped, info level
END_IF
IF _fAvailInt > 100.0 THEN
    _fAvailInt := 100.0;          // 开动率封顶（Availability capped）
END_IF
IF _fQualInt > 100.0 THEN
    _fQualInt := 100.0;           // 合格率封顶（Quality capped）
END_IF

IF NOT _bShiftFrozen THEN
    fAvailability := _fAvailInt;  // 开动率出口（冻结期不写保持上次值）/ Availability outlet (held when frozen)
    fPerformance  := _fPerfInt;   // 性能出口（Performance outlet）
    fQuality      := _fQualInt;   // 合格率出口（Quality outlet）
    fOee := (_fAvailInt * _fPerfInt * _fQualInt) / DL_CO_FACTOR; // 三因子连乘（Three-factor product）
END_IF
tPlannedTime := _tPlannedInt;     // 计划时间出口（Planned time outlet）
tRunTime := _tRunInt;             // 运行时间出口（Run time outlet）
tDownTime := _tDownInt;           // 停机时间出口（Down time outlet）

// ============================================================================
// 段 5｜bFault/uErrorId 出口（R21：bFault 显式排除信息级）
//      Outlets: bFault excludes info codes (R21)
// ============================================================================
bFault := _bFaultLatch;           // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
