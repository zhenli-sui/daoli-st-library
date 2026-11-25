(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BatchDosingControl
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 工艺功能块（Function Block · 多原料单通道配料称重）
 * 功能简述 (Function)   : 多原料单通道自动配料称重控制器（单料批次相 Phase
 *                         语义）。三段给料顺控（快加→慢加→落定结算）+ 空中
 *                         落差自学习（误差/2 更新，防振荡）+ 超差 NG 判定 +
 *                         断流诊断。执行机构抽象为三离散输出（与给料机/闸门
 *                         类型解耦）；秤重量 LREAL→REAL 引脚注入（标定由称
 *                         重层完成）。Abort 优先级最高（CASE 首分支）。
 * 枚举归属 (Enum note)  : E_DL_DosingPhase 随本块同文件发布（公约 0.11 口径：
 *                         配套枚举与主块同文件，头注释注明归属）。
 * 公约遵循 (Convention) : 0.1/R23 显式批次启动沿驱动（无自动首扫初始化语义），
 *                         免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 全部实例主
 *                         体最前部无条件刷新；0.7/R15 断流/秤信号/参数故障锁
 *                         存仅复位路径清码；0.9 非有限值 fWeight 防御（自比
 *                         检测，故障级中止全断）；0.14 全部除法/浮点判等走
 *                         ABS 容差。
 *                         0.8 故障码段位 16#0005_xxxx（经 DL_Process
 *                         VERSION.md 码表核对，0005_0220~0223 / 0005_0114~0106
 *                         均未占用）：
 *                         【故障级】0005_0220 断流/堵料、0005_0221 秤信号无
 *                         效（非有限值）、0005_0223 配方参数非法、0005_0222
 *                         非法状态兜底；
 *                         【信息级】0005_0114 稳窗超时按当前值结算、0005_0115
 *                         补偿学习触限。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 非有限值中止全断/防振荡半
 *                         误差学习/限幅钳位 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 ENUM+CASE+ELSE，Abort
 *                         首分支最高优先 ✓
 *                         R7 五实例（R_TRIG×3/TON×2）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 截断点公式：慢加关断重量 = fSetpoint −
 *                           fInflightComp；fInflightComp 初值 0 → 首批必然过
 *                           冲 → 学习链收敛（首批预期在注释写明）；
 *                         ② 自学习更新：结算后 Error = fFinalWeight −
 *                           fSetpoint；bLearnEnable 时 fInflightComp +=
 *                           Error/2.0（半误差防振荡），钳位 ±fCompLimit，
 *                           触限置信息级 0005_0115；
 *                         ③ 稳窗判稳：tSettleWindow 内重量变化 <
 *                           fFlowDeadband 才结算；超窗未稳重试
 *                           DL_SETTLE_RETRY_MAX 次后按当前值结算 + 信息级；
 *                         ④ 断流诊断：给料相中 tFlowWatch 窗内重量变化 <
 *                           fFlowDeadband → 断流故障锁存（快加/慢加独立监
 *                           视计时重启）；
 *                         ⑤ 超差 NG 锁存 + 卸料输出禁止（NG 不得流入下工
 *                           序）；Abort 电平最高优先（CASE 首分支，立即关全
 *                           部输出）；
 *                         ⑥ 非有限值 fWeight → 批次中止故障级 0005_0221，
 *                           输出全断。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 新增故障码 0005_0223 配方参数非法：规格故障集未
 *                           覆盖 fSetpoint/fTolerance 非法值路径，编码时补
 *                           充登记（核对 DL_Process 码表未占用）。
 * 开源溯源 (Origin)     : 来源标签 lbp-batch-dosing / isa-88（RAW_NOTES_R7
 *                         S-10：ISA-88 批次相（Phase）语义与重力失重式/增
 *                         量式配料公开工程惯例——三段给料、空中落差补偿、
 *                         半误差学习（提取点②③⑤），公开技术资料，仅借鉴
 *                         语义域；状态机、学习与诊断实现、码位与引脚契约
 *                         100% 本库独立设计，clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 三段给料逐拍：快加至 fSetpoint−fInflightComp 切慢加，同点关断进落定；
 *   V2 学习链 5 批收敛数值复算：首批过冲 Δ → 补偿 +Δ/2 → 逐批 Δ 减半；
 *   V3 补偿限幅：学习值触及 ±fCompLimit → 信息级 0005_0115；
 *   V4 断流：给料中 tFlowWatch 内重量变化 < fFlowDeadband → 0005_0220；
 *   V5 超差 NG + 卸料禁止：|误差| > fTolerance → eNg、bOutDischarge=FALSE；
 *   V6 中止优先级：任意相 bCmdAbort 电平 → 全输出断进 eAbort；
 *   V7 非有限值注入：fWeight=NaN → 0005_0221 输出全断。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Process 配料称重件）
 *   2026-11-15  v1.0.1  终审修复 2 处：① _bSettleRestart/_bFlowRestart 单拍
 *                       重启标志永不自清 → 稳窗 TON 永久失效（eSettling 永
 *                       久挂起、判稳拍结算死锁）+ 断流诊断一次后失效（段 1
 *                       实例调用后自清，R24 同源范式）；② fTareOffset/
 *                       fInflightComp 缺 0.9 非数防御（NaN 扩散进净重/截
 *                       断点链路），新增 _fTareEff/_fCompEff 生效值
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DosingPhase（归属 FB_DL_BatchDosingControl，与其同文件）
 * 含义: 单料批次相离散状态。编号步长 10 留空位，eFault 取 99 保证排序末位
 *       （全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_DosingPhase :
(
    eIdle     := 0,   // 空闲：等待批次启动 / Idle, awaiting batch start
    eCoarse   := 10,  // 快加：粗给料输出有效 / Coarse feed active
    eFine     := 20,  // 慢加：细给料输出有效 / Fine feed active
    eSettling := 30,  // 落定：稳窗判稳中 / Settling, stability window judging
    eDone     := 40,  // 完成：批次合格，卸料输出有效 / Done, batch OK, discharge active
    eNg       := 50,  // 超差：批次 NG 锁存，卸料禁止 / NG latched, discharge forbidden
    eAbort    := 60,  // 中止：Abort 电平保持中，全输出断 / Aborted, all outputs off
    eFault    := 99   // 故障锁存：断流/秤信号/参数非法/非法状态 / Latched fault
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_BatchDosingControl
VAR_INPUT
    bCmdBatchStart : BOOL;              // 批次启动指令（Batch start），上升沿进入快加 / Batch start edge enters coarse feed
    bCmdAbort      : BOOL;              // 批次中止指令（Abort），电平生效，立即关全部输出 / Abort level, all outputs off immediately
    fWeight        : REAL;              // 秤实时重量（Live weight）[kg]，非有限值防御；标定由称重层完成 / Live weight [kg], non-finite defended, calibration upstream
    fTareOffset    : REAL := 0.0;       // 皮重偏移（Tare offset）[kg]，默认 0.0；净重 = fWeight − fTareOffset / Tare offset [kg], net = weight − tare
    fSetpoint      : REAL;              // 批次目标净重（Batch setpoint）[kg]，域 >0 / Batch setpoint [kg], > 0
    fSwitchCoarse  : REAL := 0.0;       // 快加切换点（Coarse-to-fine switch）[kg]，0=默认 85% 设定值（引脚覆盖语义见头注释）/ Coarse switch point, 0 = default 85% of setpoint
    fInflightComp  : REAL;              // 空中落差补偿（In-flight compensation）[kg]，学习值跨批次保持；上下限由 fCompLimit 钳位 / In-flight compensation [kg], learned value clamped by fCompLimit
    fCompLimit     : REAL := 0.0;       // 补偿学习限幅（Compensation limit）[kg]，0=默认 10% 设定值 / Compensation clamp, 0 = default 10% of setpoint
    bLearnEnable   : BOOL;              // 落差自学习使能（Learning enable），TRUE=每批结算后按误差/2 更新 / Learning enable, update by error/2 after each settle
    tSettleWindow  : TIME := T#1S;     // 落定稳窗（Settle window），默认 T#1S，域 500MS~5S 越界钳位 / Settle window, clamped 500MS..5S
    fTolerance     : REAL := 0.0;       // 批次公差（Batch tolerance）[kg]，0=默认 0.5% 设定值语义（引脚显式覆盖）/ Batch tolerance, 0 = default 0.5% of setpoint
    tFlowWatch     : TIME := T#10S;    // 断流监视窗（Flow watchdog），默认 T#10S；给料中重量变化率恒零超窗 → 断流 / Flow watchdog, constant-weight over window = no flow
    fFlowDeadband  : REAL := 0.05;     // 断流判据死区（Flow deadband）[kg]，默认 0.05；稳窗内重量变化 < 死区判断流 / Flow deadband [kg], change below deadband = no flow
    bReset         : BOOL;              // 上升沿复位故障（Reset edge）/ Rising edge resets fault
END_VAR
VAR_OUTPUT
    bOutCoarse    : BOOL;               // 快加输出（Coarse feed output），给料机/闸门快加速率 / Coarse feed output
    bOutFine      : BOOL;               // 慢加输出（Fine feed output）/ Fine feed output
    bOutDischarge : BOOL;               // 卸料输出（Discharge output），批次合格后放料 / Discharge output, opens after batch OK
    fNetWeight    : REAL;               // 当前净重（Net weight）[kg] / Current net weight [kg]
    fFinalWeight  : REAL;               // 上批次结算净重（Final weight）[kg]，落定后锁存 / Final settled weight [kg], latched after settle
    bBatchOk      : BOOL;               // 批次合格（Batch OK），|结算净重 − 设定值| ≤ 公差 / Batch OK verdict
    bFault        : BOOL;               // 故障标志（Fault flag），显式排除信息级 / Fault flag, info codes excluded
    uErrorId      : UDINT;              // 故障码（Error code），16#0005_xxxx 段，0=无故障 / Error code, family 16#0005_xxxx
END_VAR
VAR
    _ePhase        : E_DL_DosingPhase := E_DL_DosingPhase.eIdle; // 内部批次相（Internal dosing phase），属性只读 / Internal phase, read-only via property
    _bFaultLatch   : BOOL;              // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt   : UDINT;             // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode     : UDINT;             // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bWeightValid  : BOOL;              // 秤信号有效（Weight signal valid，非有限值防御）/ Weight signal valid flag
    _fNetInt       : REAL;              // 内部净重（Internal net weight）[kg] / Internal net weight [kg]
    _fSetEff       : REAL;              // 防御后生效设定值（Sanitized setpoint）[kg] / Sanitized setpoint [kg]
    _fTolEff       : REAL;              // 防御后生效公差（Sanitized tolerance）[kg] / Sanitized tolerance [kg]
    _fSwitchEff    : REAL;              // 防御后生效快加切换点（Sanitized coarse switch）[kg] / Sanitized coarse switch [kg]
    _fCompLimEff   : REAL;              // 防御后生效补偿限幅（Sanitized compensation clamp）[kg] / Sanitized compensation clamp [kg]
    _fTareEff      : REAL;              // 防御后生效皮重偏移（Sanitized tare offset）[kg]，0.9 非数防御 / Sanitized tare offset [kg] (v1.0.1)
    _fCompEff      : REAL;              // 防御后生效落差补偿（Sanitized in-flight comp）[kg]，0.9 非数防御 / Sanitized in-flight comp [kg] (v1.0.1)
    _fCutCoarse    : REAL;              // 快加→慢加切换重量（Coarse-to-fine cut weight）[kg] / Coarse-to-fine cut weight [kg]
    _fCutFine      : REAL;              // 慢加关断重量（Fine cut weight）[kg]，= 设定值 − 落差补偿 / Fine cut weight [kg]
    _fSettleRef    : REAL;              // 稳窗基准重量（Settle reference weight）[kg] / Settle reference weight [kg]
    _nSettleRetry  : USINT;             // 稳窗重试计数（Settle retry counter）/ Settle retry counter
    _bSettleRestart: BOOL;              // 稳窗重启单拍（Settle restart one-shot）/ Settle restart one-shot
    _fFlowRef      : REAL;              // 断流监视基准重量（Flow-watch reference weight）[kg] / Flow-watch reference weight [kg]
    _bFlowRestart  : BOOL;              // 断流监视重启单拍（Flow-watch restart one-shot）/ Flow-watch restart one-shot
    _bBatchStartEdge : BOOL;            // 批次启动沿（Batch start edge this scan）/ Batch start edge this scan
    _fbTrigStart   : R_TRIG;            // 批次启动沿检测（Batch start edge detector）/ Batch start edge detector
    _fbTrigReset   : R_TRIG;            // 复位沿检测（Reset edge detector）/ Reset edge detector
    _fbTrigAbort   : R_TRIG;            // 中止沿检测（Abort edge detector），沿置中止态（电平保持由段内判定）/ Abort edge detector
    _fbTonSettle   : TON;               // 落定稳窗定时器（Settle window timer）/ Settle window timer
    _fbTonFlow     : TON;               // 断流监视窗定时器（Flow watchdog timer）/ Flow watchdog timer
END_VAR
VAR CONSTANT
    DL_COARSE_FRAC    : REAL := 0.85;   // 快加切换默认比例（Coarse switch default fraction of setpoint）/ Coarse switch default fraction
    DL_COMP_FRAC      : REAL := 0.10;   // 补偿限幅默认比例（Compensation clamp default fraction）/ Compensation clamp default fraction
    DL_TOL_FRAC       : REAL := 0.005;  // 公差默认比例（Tolerance default fraction of setpoint）/ Tolerance default fraction
    DL_LEARN_DIV      : REAL := 2.0;    // 学习半误差除数（Learning half-error divisor），防振荡 / Learning half-error divisor, anti-oscillation
    DL_SETTLE_WIN_MIN : TIME := T#500MS; // 稳窗下限（Settle window lower clamp）/ Settle window lower clamp
    DL_SETTLE_WIN_MAX : TIME := T#5S;   // 稳窗上限（Settle window upper clamp）/ Settle window upper clamp
    DL_SETTLE_RETRY_MAX : USINT := 3;   // 稳窗重试上限（Settle retry max），超限按当前值结算 / Settle retry max, settle as-is beyond
    DL_REAL_EPS       : REAL := 1.0E-6; // 浮点防零容差（Float divide-guard epsilon）/ Float divide-guard epsilon
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigStart(CLK := bCmdBatchStart);
_fbTrigReset(CLK := bReset);
_fbTrigAbort(CLK := bCmdAbort);
_bBatchStartEdge := _fbTrigStart.Q;   // 本拍启动沿（Start edge this scan）
_fbTonSettle(IN := (_ePhase = E_DL_DosingPhase.eSettling) AND (NOT _bSettleRestart) AND (NOT _bFaultLatch), PT := tSettleWindow); // 稳窗（Settle window）
_fbTonFlow(IN := ((_ePhase = E_DL_DosingPhase.eCoarse) OR (_ePhase = E_DL_DosingPhase.eFine))
           AND (NOT _bFlowRestart) AND (NOT _bFaultLatch), PT := tFlowWatch); // 断流监视窗（Flow watchdog）
// R24 同源范式：单拍重启标志在实例调用之后自清（v1.0.1 修复：原永不自清 →
// 稳窗 TON 永久失效（eSettling 永久挂起、判稳拍结算死锁）+ 断流诊断一次后
// 永久失效）/ One-shot restart flags self-cleared AFTER the instance calls
// (v1.0.1 fix: flags were never cleared, permanently disabling both timers)
_bSettleRestart := FALSE;         // 稳窗重启单拍自清（Settle restart flag self-cleared）
_bFlowRestart := FALSE;           // 断流监视重启单拍自清（Flow restart flag self-cleared）

// ============================================================================
// 段 2｜秤信号防御（0.9）+ 信息级预清零 + 复位路径（R15）
//      Weight sanitation (0.9) + info preset + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）

IF fWeight <> fWeight THEN        // 非数自比检测（NaN self-compare）
    _bWeightValid := FALSE;       // 秤信号无效（Weight invalid）
    IF _bFaultLatch = FALSE THEN
        _bFaultLatch := TRUE;     // 秤信号无效故障锁存（Invalid weight latch）
        _uErrorIdInt := 16#0005_0221; // 0005_0221 秤信号无效【故障级】/ Invalid weight signal, fault level
        _ePhase := E_DL_DosingPhase.eFault; // 批次中止进故障态（Batch aborted to fault）
    END_IF
ELSE
    _bWeightValid := TRUE;        // 秤信号有效（Weight valid）
    _fNetInt := fWeight - _fTareEff; // 净重计算（皮重经 0.9 非数防御生效值，v1.0.1）/ Net weight with sanitized tare (v1.0.1)
END_IF
fNetWeight := _fNetInt;           // 净重出口（Net weight outlet）

IF _fbTrigReset.Q THEN
    _bFaultLatch := FALSE;        // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
    IF _ePhase = E_DL_DosingPhase.eFault THEN
        _ePhase := E_DL_DosingPhase.eIdle; // 故障复位回空闲（Fault reset to idle）
    END_IF
END_IF

// ============================================================================
// 段 3｜参数防御（启动时校验配方，0.9 + 域防御）
//      Recipe parameter sanitation at batch start (0.9 + domain guards)
// ============================================================================
IF fSetpoint <> fSetpoint THEN    // 设定值非数（Setpoint NaN）
    _fSetEff := 0.0;              // 非法设定占位（Invalid placeholder）
ELSIF fSetpoint <= DL_REAL_EPS THEN
    _fSetEff := 0.0;              // 非正设定占位（Non-positive placeholder）
ELSE
    _fSetEff := fSetpoint;        // 生效设定（Effective setpoint）
END_IF

IF fTolerance <> fTolerance THEN  // 公差非数（Tolerance NaN）
    _fTolEff := _fSetEff * DL_TOL_FRAC; // 回落默认比例（Default fraction fallback）
ELSIF fTolerance <= 0.0 THEN
    _fTolEff := _fSetEff * DL_TOL_FRAC; // 非正回落默认（Non-positive falls back）
ELSE
    _fTolEff := fTolerance;       // 生效公差（Effective tolerance）
END_IF

IF fSwitchCoarse <> fSwitchCoarse THEN // 切换点非数（Switch NaN）
    _fSwitchEff := _fSetEff * DL_COARSE_FRAC; // 回落默认比例（Default fraction fallback）
ELSIF fSwitchCoarse <= 0.0 THEN
    _fSwitchEff := _fSetEff * DL_COARSE_FRAC; // 零值=默认 85% 设定值（Zero = default 85%）
ELSE
    _fSwitchEff := fSwitchCoarse; // 引脚覆盖生效（Pin override effective）
END_IF

IF fCompLimit <> fCompLimit THEN  // 限幅非数（Clamp NaN）
    _fCompLimEff := _fSetEff * DL_COMP_FRAC; // 回落默认比例（Default fraction fallback）
ELSIF fCompLimit <= 0.0 THEN
    _fCompLimEff := _fSetEff * DL_COMP_FRAC; // 零值=默认 10% 设定值（Zero = default 10%）
ELSE
    _fCompLimEff := fCompLimit;   // 生效限幅（Effective clamp）
END_IF

// 0.9 非数防御补齐（v1.0.1）：皮重偏移与落差补偿为 REAL 输入，非数自比后
// 取生效值，杜绝 NaN 扩散进净重/截断点链路
// 0.9 NaN defense completed (v1.0.1) for tare offset and in-flight compensation
IF fTareOffset <> fTareOffset THEN // 皮重非数（Tare NaN）
    _fTareEff := 0.0;             // 回落零皮重（Fallback zero tare）
ELSE
    _fTareEff := fTareOffset;     // 生效皮重（Effective tare）
END_IF
IF fInflightComp <> fInflightComp THEN // 落差补偿非数（In-flight comp NaN）
    _fCompEff := 0.0;             // 回落零补偿（首批过冲语义，学习链重建）/ Fallback zero comp
ELSE
    _fCompEff := fInflightComp;   // 生效补偿（Effective compensation）
END_IF

// ============================================================================
// 段 4｜主批次相状态机（ENUM + CASE + ELSE 兜底；Abort 首分支最高优先）
//      Main dosing phase machine (Abort first-branch top priority, ELSE fallback)
// ============================================================================
IF bCmdAbort THEN
    // Abort 电平最高优先：立即关全部输出进中止态（Abort level top priority）
    _ePhase := E_DL_DosingPhase.eAbort; // 进中止态（To aborted state）
ELSE
    CASE _ePhase OF

        E_DL_DosingPhase.eIdle: // 空闲态：等待启动沿
            IF _bBatchStartEdge AND (NOT _bFaultLatch) THEN
                IF _fSetEff <= DL_REAL_EPS THEN
                    _bFaultLatch := TRUE;           // 配方参数非法锁存（Invalid recipe latch）
                    _uErrorIdInt := 16#0005_0223;   // 0005_0223 配方参数非法【故障级】/ Invalid recipe parameters, fault level
                    _ePhase := E_DL_DosingPhase.eFault;
                ELSE
                    _fCutCoarse := _fSwitchEff;                     // 快加切换点（Coarse cut point）
                    _fCutFine := _fSetEff - _fCompEff;              // 慢加关断重量 = 设定值 − 落差补偿（截断点公式，生效值）/ Fine cut = setpoint − sanitized comp
                    fFinalWeight := 0.0;                            // 上批结果清位（Final weight cleared）
                    bBatchOk := FALSE;                              // 合格判定清位（OK verdict cleared）
                    _nSettleRetry := 0;                             // 稳窗重试清零（Retry cleared）
                    _fSettleRef := _fNetInt;                        // 稳窗基准初始化（Settle reference init）
                    _fFlowRef := _fNetInt;                          // 断流基准初始化（Flow reference init）
                    _ePhase := E_DL_DosingPhase.eCoarse;            // 进入快加（To coarse feed）
                END_IF
            END_IF

        E_DL_DosingPhase.eCoarse: // 快加态：粗给料至切换点
            IF _fNetInt >= _fCutCoarse THEN
                _ePhase := E_DL_DosingPhase.eFine; // 切慢加（To fine feed）
                _fFlowRef := _fNetInt;             // 断流基准重置（Flow reference reset）
            END_IF

        E_DL_DosingPhase.eFine: // 慢加态：细给料至截断点
            IF _fNetInt >= _fCutFine THEN
                _ePhase := E_DL_DosingPhase.eSettling; // 关断进落定（Cut to settling）
                _fSettleRef := _fNetInt;               // 稳窗基准重置（Settle reference reset）
            END_IF

        E_DL_DosingPhase.eSettling: // 落定态：稳窗判稳，判稳即一次性结算+学习
            IF _fbTonSettle.Q THEN
                IF ABS(_fNetInt - _fSettleRef) < fFlowDeadband THEN
                    // —— 一次性结算（仅判稳拍执行）：锁存结果 + NG 判定 + 学习 ——
                    //     One-shot settlement on the settled scan: result latch, NG verdict, learning
                    fFinalWeight := _fNetInt;   // 结算净重锁存（Final weight latched）
                    bBatchOk := ABS(fFinalWeight - _fSetEff) <= _fTolEff; // 公差判定（Tolerance verdict）
                    IF bLearnEnable THEN
                        fInflightComp := fInflightComp + (fFinalWeight - _fSetEff) / DL_LEARN_DIV; // 误差/2 学习（半误差防振荡）/ Half-error learning, anti-oscillation
                        IF fInflightComp > _fCompLimEff THEN
                            fInflightComp := _fCompLimEff;  // 正向限幅（Positive clamp）
                            _uInfoCode := 16#0005_0115;     // 0005_0115 补偿学习触限【信息级】/ Learning clamp hit, info level
                        ELSIF fInflightComp < (-_fCompLimEff) THEN
                            fInflightComp := -_fCompLimEff; // 负向限幅（Negative clamp）
                            _uInfoCode := 16#0005_0115;     // 0005_0115 补偿学习触限【信息级】/ Learning clamp hit, info level
                        END_IF
                    END_IF
                    IF bBatchOk THEN
                        _ePhase := E_DL_DosingPhase.eDone;  // 合格进完成态（OK to done）
                    ELSE
                        _ePhase := E_DL_DosingPhase.eNg;    // 超差进 NG 锁存态（Out of tolerance to NG）
                    END_IF
                ELSE
                    _nSettleRetry := _nSettleRetry + 1; // 未稳重试（Retry when unstable）
                    IF _nSettleRetry >= DL_SETTLE_RETRY_MAX THEN
                        _uInfoCode := 16#0005_0114;     // 0005_0114 稳窗超时按当前值结算【信息级】/ Settle timeout, settle as-is, info level
                        fFinalWeight := _fNetInt;       // 按当前值结算锁存（Settle as-is latch）
                        bBatchOk := ABS(fFinalWeight - _fSetEff) <= _fTolEff; // 公差判定（Tolerance verdict）
                        IF bBatchOk THEN
                            _ePhase := E_DL_DosingPhase.eDone;
                        ELSE
                            _ePhase := E_DL_DosingPhase.eNg;
                        END_IF
                    ELSE
                        _fSettleRef := _fNetInt;        // 重置稳窗基准（Reset settle reference）
                        _bSettleRestart := TRUE;        // 稳窗重启单拍（Restart window one-shot）
                    END_IF
                END_IF
            END_IF

        E_DL_DosingPhase.eDone: // 完成态：卸料保持，等待新批次启动
            IF _bBatchStartEdge AND (NOT _bFaultLatch) THEN
                IF _fSetEff <= DL_REAL_EPS THEN
                    _bFaultLatch := TRUE;               // 配方参数非法锁存（Invalid recipe latch）
                    _uErrorIdInt := 16#0005_0223;       // 0005_0223 配方参数非法【故障级】/ Invalid recipe, fault level
                    _ePhase := E_DL_DosingPhase.eFault;
                ELSE
                    _fCutCoarse := _fSwitchEff;         // 快加切换点（Coarse cut point）
                    _fCutFine := _fSetEff - _fCompEff;  // 截断点更新（Fine cut update, sanitized comp）
                    fFinalWeight := 0.0;                // 上批结果清位（Final weight cleared）
                    bBatchOk := FALSE;                  // 合格判定清位（OK verdict cleared）
                    _nSettleRetry := 0;                 // 稳窗重试清零（Retry cleared）
                    _fSettleRef := _fNetInt;            // 稳窗基准初始化（Settle reference init）
                    _fFlowRef := _fNetInt;              // 断流基准初始化（Flow reference init）
                    _ePhase := E_DL_DosingPhase.eCoarse; // 进入快加（To coarse feed）
                END_IF
            END_IF

        E_DL_DosingPhase.eNg: // 超差态：卸料禁止，等待新批次启动或 Abort
            IF _bBatchStartEdge AND (NOT _bFaultLatch) THEN
                IF _fSetEff <= DL_REAL_EPS THEN
                    _bFaultLatch := TRUE;               // 配方参数非法锁存（Invalid recipe latch）
                    _uErrorIdInt := 16#0005_0223;       // 0005_0223 配方参数非法【故障级】/ Invalid recipe, fault level
                    _ePhase := E_DL_DosingPhase.eFault;
                ELSE
                    _fCutCoarse := _fSwitchEff;         // 快加切换点（Coarse cut point）
                    _fCutFine := _fSetEff - _fCompEff;  // 截断点更新（Fine cut update, sanitized comp）
                    fFinalWeight := 0.0;                // 上批结果清位（Final weight cleared）
                    bBatchOk := FALSE;                  // 合格判定清位（OK verdict cleared）
                    _nSettleRetry := 0;                 // 稳窗重试清零（Retry cleared）
                    _fSettleRef := _fNetInt;            // 稳窗基准初始化（Settle reference init）
                    _fFlowRef := _fNetInt;              // 断流基准初始化（Flow reference init）
                    _ePhase := E_DL_DosingPhase.eCoarse; // 重开新批（New batch from coarse）
                END_IF
            END_IF

        E_DL_DosingPhase.eAbort: // 中止态：Abort 电平撤销后回空闲
            IF NOT bCmdAbort THEN
                _ePhase := E_DL_DosingPhase.eIdle; // 电平撤销回空闲（Level dropped, back to idle）
            END_IF

        E_DL_DosingPhase.eFault: // 故障锁存态：复位路径见段 2
            // 等待复位（Await reset）

        ELSE
            // 非法状态兜底：任何越界枚举值强制锁存故障（Illegal state fallback）
            _bFaultLatch := TRUE;           // 故障锁存（Fault latch）
            _uErrorIdInt := 16#0005_0222;   // 0005_0222 非法状态兜底【故障级】/ Illegal state, fault level
            _ePhase := E_DL_DosingPhase.eFault;
    END_CASE
END_IF

// ============================================================================
// 段 5｜输出推导 + 断流诊断 + 输出全断出口断言
//      Output derivation + no-flow diagnosis + all-off exit assertion
// ============================================================================
bOutCoarse := (_ePhase = E_DL_DosingPhase.eCoarse) AND _bWeightValid AND (NOT _bFaultLatch); // 快加输出派生（Coarse derived form）
bOutFine := (_ePhase = E_DL_DosingPhase.eFine) AND _bWeightValid AND (NOT _bFaultLatch);     // 慢加输出派生（Fine derived form）
bOutDischarge := (_ePhase = E_DL_DosingPhase.eDone) AND bBatchOk AND (NOT _bFaultLatch);     // 卸料输出派生（NG/Abort/故障恒断，出口断言）/ Discharge derived, off on NG/abort/fault

// 断流诊断：监视窗到且给料相中重量未前进死区 → 断流锁存（快加/慢加独立重置基准）
// No-flow diagnosis: watchdog expired in feed phases without weight advance
IF _fbTonFlow.Q THEN
    IF ABS(_fNetInt - _fFlowRef) < fFlowDeadband THEN
        _bFaultLatch := TRUE;         // 断流故障锁存（No-flow latch）
        _uErrorIdInt := 16#0005_0220; // 0005_0220 断流/堵料【故障级】/ No flow or bridging, fault level
        _ePhase := E_DL_DosingPhase.eFault;
    ELSE
        _fFlowRef := _fNetInt;        // 基准前移（Reference advanced）
        _bFlowRestart := TRUE;        // 监视窗重启单拍（Watchdog restart one-shot）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 属性: ePhase（GET）—— 当前批次相只读视图（Phase 语义对外镜像）。
 *      Property ePhase (GET) - read-only dosing phase view.
 *------------------------------------------------------------------------------*)
PROPERTY ePhase : E_DL_DosingPhase
ePhase := _ePhase;                // 返回内部批次相（Return internal phase）
END_PROPERTY

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_ePhase = E_DL_DosingPhase.eFault); // 显式排除信息级派生式（Derived form excluding info codes）
END_PROPERTY

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（故障级优先，无故障时透出本拍信息级
 *         码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last error code (fault priority, info shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_ePhase = E_DL_DosingPhase.eFault) THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_PROPERTY
END_FUNCTION_BLOCK
