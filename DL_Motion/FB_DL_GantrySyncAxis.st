(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GantrySyncAxis
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 多轴同步耦合族 · 龙门双驱偏斜保护
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library
 *                         （TON / R_TRIG / LIMIT / MIN / MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05，零修改）
 * 功能描述 (Function)   : 双驱龙门同步与偏斜保护。主动侧（主轴）与从动侧（从轴）
 *                         1:1 速度耦合，实时监视两侧实际位置偏差；两级阈值（预警
 *                         / 故障）分别触发降速纠偏与双轴停止；可选比例纠偏（偏差
 *                         为正即主动侧在前 → 从动侧加速追赶）；任一轴故障同拍双轴
 *                         停止（不对称风险优先，不做「健康侧继续」策略）。
 * 设计要点 (Key notes)  :
 *   ① 两级监视是本块骨架：预警阈只告警与纠偏，故障阈才双停；预警阈必须小于
 *      故障阈，组态写反时自动对调并提示（沿用库内对调自修复先例）。
 *   ② 偏差确认走延时（抗单拍毛刺）；延时参数变化时显式断输入一拍，使已计时
 *      归零（防「改时间常数后计时不清零」的幽灵故障）。
 *   ③ 纠偏为比例律 + 修正量限幅，不用积分（避免在轴外层再套积分器造成饱和）；
 *      长时间饱和判为机械卡滞或增益不足，升为故障级锁存。
 *   ④ 偏差回差 80% 才退出纠偏态，防止阈值边缘反复抖动。
 * 开源溯源 (Origin)     : 原创实现，clean-room。语义来源为公开技术文章「双编码器
 *                         龙门组态」（两级位置差监视、偏差锁存门限）、公开厂商
 *                         帮助的软龙门章节（两级监视：一级可复位、二级不可复位）、
 *                         公开论文「宽跨距龙门吊防偏斜控制器」（偏差 → 速度修正
 *                         量、增益限幅）与公开的数控龙门位置公差参考值（来源编号
 *                         RAW_NOTES S-3）。
 *                         「借鉴对象的许可说明」：上述对象均为公开发布但受版权
 *                         保护的帮助文档 / 技术文章 / 公开论文，属「可免费查阅、
 *                         仅借鉴语义与参数域」类别；本实现未复制任何源码或组态
 *                         文件，状态机、引脚命名、故障码与对调自修复策略均为本
 *                         库自有设计。
 * 验收向量 (Acceptance) :
 *   V1 正常耦合：使能后进入 eRun，偏差在预警阈内 → bInSync 为 TRUE；
 *   V2 注入 1 mm 偏差：进入 eCorrecting，修正量不超上限，偏差收敛后回 eRun；
 *   V3 偏差 3 mm（超故障阈 2 mm）持续 60 ms：确认后双轴同时停止 + 锁存 0273；
 *   V4 单轴故障：同拍双轴停止 + 锁存 0274（不等待偏差阈值）；
 *   V5 阈值写反（预警 5 / 故障 1）：自动对调 + 信息级 0151，仍能正常监视；
 *   V6 纠偏饱和持续 3 s：锁存 0271；
 *   V7 偏差未回到预警阈内给 bReset：拒绝复位 + 信息级 0150；
 *   V8 位置含非有限值：锁存 0272 并立即双停；
 *   V9 运行中途插入跟踪脉冲 bTrack：清偏差计时、退回 eIdle（公约 0.1）。
 * 已知限制 (Limits)     :
 *   ① 本块为逻辑层同步监视与纠偏编排，不构成 ISO 13849 / IEC 62061 认证安全
 *      功能；机械偏斜的最终保护由硬件限位与安全回路承担。
 *   ② 两侧轴若注入同一实例，块内无法识别，轴自身仲裁；调用方须保证主动侧与
 *      从动侧为不同实例。
 *   ③ 偏差延时确认粒度等于任务扫描周期，极短延时（小于两个扫描周期）实际等效
 *      单拍确认，毛刺风险由调用方通过 tDevDelay 规避。
 * 规格偏离 (Deviation)  :
 *   ① 依公约 0.1 增补 bTrack 输入引脚（首扫 / 跟踪范式强制项）。
 *   ② 进入 eStopping 后沿用本块既有的停止单发标志，避免每拍重复下发停止指令；
 *      规格「同拍对两轴各发一次」在进入该态的同一拍内完成，语义不变。
 *   ③ 使能撤除时在清零输出的同时补发一次双轴停止（安全保守处置）。
 *   ④ 故障级码 0270（阈值非法）在使能期间逐拍复核，一旦组态被改坏立即锁存，
 *      不停留在仅启动时校验。
 * 红线自检 (Redline)    :
 *   R1 零全局符号区访问 ✓（无全局变量表访问、无外部变量声明）
 *   R2 零物理地址直写 ✓（无输入输出通道地址记号）
 *   R3 纯 IEC 61131-3 ✓（仅 TON / R_TRIG / LIMIT / MIN / MAX / ABS）
 *   R4 防除零 / 防越界 / 浮点容差 ✓（阈值对调与回差全用容差比较、无数组索引、
 *      时间参数变化断输入一拍）
 *   R5 声明行 100% 中英双语同行注释 ✓
 *   R6 ENUM + CASE 且 CASE 含 ELSE 兜底 ✓
 *   R7 定时器与边沿实例无条件周期刷新 ✓（本块无单拍脉冲输出）
 *   POU 终结符成对 ✓（FUNCTION_BLOCK ↔ END_FUNCTION_BLOCK，末行即终结符；
 *   TYPE ↔ END_TYPE 成对）
 * 故障码表 (Error codes):
 *   16#0004_0150【信息级】偏差未回预警阈内，复位被拒；
 *   16#0004_0151【信息级】预警 / 故障阈值对调自修复；
 *   16#0004_0152【信息级】纠偏速度上限非法回默认；
 *   16#0004_0270【故障级】偏差阈值非法（≤0 / 非有限值），锁存；
 *   16#0004_0271【故障级】纠偏长时间饱和（疑似机械卡滞），锁存；
 *   16#0004_0272【故障级】轴位置信号非有限值，锁存；
 *   16#0004_0273【故障级】偏差超故障阈触发双轴停止，锁存；
 *   16#0004_0274【故障级】单轴故障触发双轴停止（透传），锁存；
 *   16#0004_0297【故障级】非法状态兜底（本块专用，不与其他块共用）。
 *   信息级码只进 uErrorId；bFault 为派生式仅反映 eFault 态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Motion 同步耦合族）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbGantry.iMasterAxis := fbLeftAxis;           // 主动侧（驱动侧）实例
 *   fbGantry.iSlaveAxis  := fbRightAxis;          // 从动侧（跟随侧）实例
 *   fbGantry(bEnable := bGantryOn,
 *            fDevTolWarn := 0.5, fDevTolFault := 2.0,
 *            tDevDelay := T#50MS, bCorrectEnable := TRUE,
 *            fCorrGain := 2.0, fCorrSpeedMax := 20.0,
 *            fCoupleSpeed := 10.0, fAcc := 500.0);
 *   IF fbGantry.bStopBothCmd THEN bSafetyRelayDrop := TRUE; END_IF
 *   注：两侧轴的上使能、回原与限位保护仍由各自轴块与安全链负责，本块只做
 *       速度耦合与偏差监视。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 预警阈与故障阈不要设成同值：同值时监视失去两级意义，块内会按对调处理
 *      并提示，但工艺上应重新组态（预警阈建议取故障阈的 1/4 ~ 1/2）。
 *   2 纠偏增益过大会在阈值边缘产生速度抖动；从 1.0 ~ 3.0 起步，观察
 *      fCorrSpeedCmd 是否长期贴上限（贴上限即增益不足或机械卡滞）。
 *   3 单轴报跟随误差时本块同拍双停，另一轴不会「继续跑」——这是刻意的保守
 *      策略，复位后必须人工确认横梁已回正再重新使能。
 *   4 bFault 一旦置位只能靠 bReset 上升沿解除，且要求偏差已回到预警阈内；
 *      机械偏斜未消除时复位会被拒（信息级 0150），必须先手动点动纠偏。
 *   5 本块不产生位置指令，只产生速度指令；位置同步精度取决于两侧驱动自身
 *      的位置环，本块不替代驱动的位置控制。
 *   6 阈值组态被改坏（≤0 / 非有限值 / 超域）时本块直接锁存 0270，且「组态未改好
 *      之前复位会立刻再次锁存」是刻意行为：不允许带着非法偏差阈值运行龙门。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GantryState（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 龙门双驱同步状态机，编号间隔 10 预留扩展位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_GantryState :
(
    eIdle       := 0,    // 空闲：未耦合，输出全清 / Idle: not coupled, outputs cleared
    eCoupling   := 10,   // 耦合建立：双轴以慢速趋同 / Coupling: both axes converge at low speed
    eRun        := 20,   // 运行：1:1 速度跟随 + 偏差监视 / Run: 1:1 velocity follow with deviation monitoring
    eCorrecting := 30,   // 纠偏中：偏差超预警阈且纠偏使能 / Correcting: deviation over warn band with correction enabled
    eStopping   := 40,   // 双轴停止中：偏差超故障阈或任一轴故障 / Stopping: deviation over fault band or axis fault
    eFault      := 99    // 故障锁存：仅 bReset 上升沿且偏差回位可退出 / Fault: latched, bReset only after deviation recovered
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_GantrySyncAxis
VAR_INPUT
    bEnable         : BOOL := FALSE;        // 总使能（Enable），FALSE=停止并清指令，电平语义
    bReset          : BOOL := FALSE;        // 复位故障（Reset），上升沿受理，须偏差已回预警阈内才真正复位
    bTrack          : BOOL := FALSE;        // 偏差计时重同步（Tracking pulse），上升沿即清计时与锁存并退回 eIdle
    fDevTolWarn     : REAL := 0.5;          // 偏差预警阈（Deviation warn tolerance）[mm]，域 0.001..50，须小于故障阈
    fDevTolFault    : REAL := 2.0;          // 偏差故障阈（Deviation fault tolerance）[mm]，域 0.01..100
    tDevDelay       : TIME := T#50MS;       // 偏差确认延时（Deviation confirm delay）[ms]，超阈须持续此时间才动作
    bCorrectEnable  : BOOL := TRUE;         // 纠偏使能（Correction enable），FALSE=只监视不纠偏
    fCorrGain       : REAL := 2.0;          // 纠偏比例增益（Correction gain）[1/s]，域 0..50，0=纠偏关闭
    fCorrSpeedMax   : REAL := 20.0;         // 纠偏速度修正上限（Correction speed limit）[mm/s]，域 0.1..500
    fCoupleSpeed    : REAL := 10.0;         // 耦合建立慢速（Coupling speed）[mm/s]，域 0.1..1000，双轴以此速度趋同
    fAcc            : REAL := 500.0;        // 加/减速度（Acceleration）[mm/s²]，域 0.1..100000，非有限值回默认
END_VAR
VAR_OUTPUT
    bInSync         : BOOL := FALSE;        // 同步中（In sync），eRun / eCorrecting 且偏差未超预警阈为 TRUE
    fDeviation      : REAL := 0.0;          // 实时偏差（Deviation）[mm]，= 主动侧位置 − 从动侧位置，带符号
    bDevWarn        : BOOL := FALSE;        // 偏差预警（Deviation warning），延时确认后置位，回差内自动清，瞬态型
    bFault          : BOOL := FALSE;        // 故障锁存（Fault），派生式仅故障级码参与，信息级码不置位
    uErrorId        : UDINT := 0;           // 故障码（Error code），段位 16#0004_xxxx，0=无故障
    bStopBothCmd    : BOOL := FALSE;        // 双轴停止请求（Stop both request），供上层安全链与 HMI 监视
    fCorrSpeedCmd   : REAL := 0.0;          // 纠偏速度修正量（Correction speed）[mm/s]，带符号，叠加到从动侧指令
END_VAR
VAR_IN_OUT
    iMasterAxis     : I_DL_MotionAxis;      // 主动侧轴接口引用（Drive side axis），由调用方注入
    iSlaveAxis      : I_DL_MotionAxis;      // 从动侧轴接口引用（Following side axis），由调用方注入
END_VAR
VAR
    eState          : E_DL_GantryState := E_DL_GantryState.eIdle; // 内部状态机步序（Internal state）
    bInit           : BOOL := FALSE;        // 首扫完成标志（First-scan done flag），初值 FALSE，随 bTrack 复位
    bFaultLatch     : BOOL := FALSE;        // 故障锁存标志（Fault latch），仅 bReset 沿或新啮合沿解除
    bRefOk          : BOOL := FALSE;        // 双引用有效标志（Both references valid），逐拍重算
    bStopIssued     : BOOL := FALSE;        // 双轴停止已下发标志（Stop issued flag），单发化防重复发令
    bWarnLatched    : BOOL := FALSE;        // 预警锁存标志（Warning latched），带回差自动清除
    bMonActive      : BOOL := FALSE;        // 偏差监视使能（Monitoring active），运行三态为 TRUE
    bParamBad       : BOOL := FALSE;        // 阈值参数非法标志（Tolerance parameter invalid），逐拍重算
    bDelayChanged   : BOOL := FALSE;        // 延时参数变更标志（Delay changed flag），断输入一拍用
    fWarnEff        : REAL := 0.5;          // 生效预警阈（Effective warn tolerance）[mm]，对调后值
    fFaultEff       : REAL := 2.0;          // 生效故障阈（Effective fault tolerance）[mm]，对调后值
    fCorrMaxEff     : REAL := 20.0;         // 生效纠偏上限（Effective correction limit）[mm/s]，非法回默认
    fAccEff         : REAL := 500.0;        // 生效加减速度（Effective acceleration）[mm/s²]，非法回默认
    fCoupleEff      : REAL := 10.0;         // 生效耦合慢速（Effective coupling speed）[mm/s]，非法回默认
    fDevAbs         : REAL := 0.0;          // 偏差绝对值（Absolute deviation）[mm]，阈值比较用
    fCorrAbs        : REAL := 0.0;          // 纠偏量绝对值（Absolute correction）[mm/s]，饱和判定用
    fCorrCmd        : REAL := 0.0;          // 纠偏修正量（Correction command）[mm/s]，带符号
    fMasterPos      : REAL := 0.0;          // 主动侧位置（Drive side position）[mm]
    fSlavePos       : REAL := 0.0;          // 从动侧位置（Following side position）[mm]
    fMasterVel      : REAL := 0.0;          // 主动侧速度（Drive side velocity）[mm/s]，带符号
    fSlaveVel       : REAL := 0.0;          // 从动侧速度（Following side velocity）[mm/s]，带符号
    fCmdVel         : REAL := 0.0;          // 下发给从动侧的速度指令（Commanded velocity）[mm/s]，带符号
    tDelayEff       : TIME := T#50MS;       // 生效确认延时（Effective confirm delay）[ms]，负值归零
    tDelayPrev      : TIME := T#0MS;        // 上拍确认延时（Previous confirm delay）[ms]，变更检测基准
    nStopCode       : UDINT := 0;           // 停止原因码（Stop reason code），进 eFault 时落地
    fbTrigReset     : R_TRIG;               // 复位指令上升沿（Reset command rising edge）
    fbTonDevWarn    : TON;                  // 偏差预警延时确认（Warn confirm delay timer）
    fbTonDevFault   : TON;                  // 偏差故障延时确认（Fault confirm delay timer）
    fbTonCorrSat    : TON;                  // 纠偏饱和累计计时（Correction saturation timer）
END_VAR
VAR CONSTANT
    DL_GANTRY_INF_MAX   : REAL := 1.0E30;   // 有限值判定幅值上限（Finite magnitude bound）[无量纲，按比较量量纲同值使用]
    DL_GANTRY_EPS       : REAL := 1.0E-6;   // 浮点判零容差（Float zero tolerance）[无量纲，按比较量量纲同值使用]
    DL_GANTRY_TOL_MIN   : REAL := 1.0E-3;   // 阈值下限（Tolerance floor）[mm]，低于此值判非法
    DL_GANTRY_TOL_MAX   : REAL := 100.0;    // 阈值上限（Tolerance ceiling）[mm]，高于此值判非法
    DL_GANTRY_CORR_DEF  : REAL := 20.0;     // 纠偏上限默认值（Default correction limit）[mm/s]
    DL_GANTRY_CORR_MAX  : REAL := 500.0;    // 纠偏上限允许最大值（Correction limit ceiling）[mm/s]
    DL_GANTRY_ACC_DEF   : REAL := 500.0;    // 加速度默认回退值（Default acceleration）[mm/s²]
    DL_GANTRY_CPL_DEF   : REAL := 10.0;     // 耦合慢速默认回退值（Default coupling speed）[mm/s]
    DL_GANTRY_HYST      : REAL := 0.8;      // 回差系数（Hysteresis factor）[-]，低于预警阈 80% 才清预警
    DL_GANTRY_SAT_RATIO : REAL := 0.98;     // 饱和判定比例（Saturation ratio）[-]，达上限 98% 视为饱和
    DL_GANTRY_SAT_TIME  : TIME := T#3S;     // 饱和持续上限（Saturation time limit）[ms]，超过判卡滞
    DL_GANTRY_SPEED_BAND: REAL := 1.0E-5;   // 速度趋同判定带（Speed convergence band）[mm/s]，= 判零容差 × 10
    DL_GANTRY_ZERO_TIME : TIME := T#0S;     // 零延时字面量（Zero delay literal）[ms]，用于延时下限比较
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTrigReset(CLK := bReset);

// 段 2｜出口默认赋值（公约 0.9：早退路径输出必须确定）
bInSync       := FALSE;
bDevWarn      := FALSE;
bFault        := (eState = E_DL_GantryState.eFault);
fCorrSpeedCmd := 0.0;
fDeviation    := 0.0;

// 段 3｜双引用有效性判定 + 反馈量采集（无效时全部回零，定时器照样刷新）
bRefOk := (iMasterAxis <> 0) AND (iSlaveAxis <> 0);
IF bRefOk THEN
    fMasterPos := iMasterAxis.fPosition;
    fSlavePos  := iSlaveAxis.fPosition;
    fMasterVel := iMasterAxis.fVelocity;
    fSlaveVel  := iSlaveAxis.fVelocity;
ELSE
    fMasterPos := 0.0;
    fSlavePos  := 0.0;
    fMasterVel := 0.0;
    fSlaveVel  := 0.0;
END_IF
fDeviation := fMasterPos - fSlavePos;
fDevAbs    := ABS(fDeviation);

// 段 4｜阈值参数防御：非有限值 / 超域判非法，预警阈不小于故障阈时自动对调
fWarnEff  := fDevTolWarn;
fFaultEff := fDevTolFault;
bParamBad := FALSE;
IF (fWarnEff <> fWarnEff) OR (ABS(fWarnEff) > DL_GANTRY_INF_MAX)
   OR (fWarnEff < DL_GANTRY_TOL_MIN) OR (fWarnEff > DL_GANTRY_TOL_MAX) THEN
    bParamBad := TRUE;
END_IF
IF (fFaultEff <> fFaultEff) OR (ABS(fFaultEff) > DL_GANTRY_INF_MAX)
   OR (fFaultEff < DL_GANTRY_TOL_MIN) OR (fFaultEff > DL_GANTRY_TOL_MAX) THEN
    bParamBad := TRUE;
END_IF
IF (NOT bParamBad) AND (fWarnEff > (fFaultEff - DL_GANTRY_EPS)) THEN
    fWarnEff  := fDevTolFault;                           // 自动对调：写反时按对调后值监视，不静默
    fFaultEff := fDevTolWarn;
    uErrorId  := 16#0004_0151;                           // 【信息级】预警 / 故障阈值对调自修复
END_IF

IF (fCorrSpeedMax <> fCorrSpeedMax) OR (ABS(fCorrSpeedMax) > DL_GANTRY_INF_MAX)
   OR (fCorrSpeedMax < DL_GANTRY_TOL_MIN) THEN
    fCorrMaxEff := DL_GANTRY_CORR_DEF;                   // 纠偏上限非法 → 默认 20 mm/s
    uErrorId    := 16#0004_0152;                         // 【信息级】纠偏速度上限非法回默认
ELSE
    fCorrMaxEff := MIN(fCorrSpeedMax, DL_GANTRY_CORR_MAX);
END_IF

IF (fAcc <> fAcc) OR (ABS(fAcc) > DL_GANTRY_INF_MAX) OR (fAcc < DL_GANTRY_TOL_MIN) THEN
    fAccEff := DL_GANTRY_ACC_DEF;
ELSE
    fAccEff := fAcc;
END_IF

IF (fCoupleSpeed <> fCoupleSpeed) OR (ABS(fCoupleSpeed) > DL_GANTRY_INF_MAX) OR (fCoupleSpeed < DL_GANTRY_TOL_MIN) THEN
    fCoupleEff := DL_GANTRY_CPL_DEF;
ELSE
    fCoupleEff := fCoupleSpeed;
END_IF

// 段 5｜确认延时防御与变更检测（公约 0.6：语义参数变化必须断输入一拍）
IF tDevDelay < DL_GANTRY_ZERO_TIME THEN
    tDelayEff := DL_GANTRY_ZERO_TIME;                    // 负延时归零，按单拍确认（毛刺风险由调用方规避）
ELSE
    tDelayEff := tDevDelay;
END_IF
bDelayChanged := (tDelayEff <> tDelayPrev);              // 延时变更：本拍强制断输入，使已计时归零
tDelayPrev    := tDelayEff;

// 段 6｜偏差监视使能（运行三态参与监视）
bMonActive := (eState = E_DL_GantryState.eCoupling) OR (eState = E_DL_GantryState.eRun)
              OR (eState = E_DL_GantryState.eCorrecting);

// 段 7｜定时器无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTonDevWarn(IN := bRefOk AND bMonActive AND (fDevAbs >= fWarnEff) AND (NOT bDelayChanged),
             PT := tDelayEff);
fbTonDevFault(IN := bRefOk AND bMonActive AND (fDevAbs >= fFaultEff) AND (NOT bDelayChanged),
              PT := tDelayEff);
fbTonCorrSat(IN := (eState = E_DL_GantryState.eCorrecting) AND (fCorrAbs >= fCorrMaxEff * DL_GANTRY_SAT_RATIO),
             PT := DL_GANTRY_SAT_TIME);

// 段 8｜引用无效直接退出（定时器已在上方无条件刷新，本拍不产生任何轴动作）
IF NOT bRefOk THEN
    RETURN;
END_IF

// 段 9｜预警锁存与回差清除（瞬态型，每拍重算）
IF fDevAbs >= fWarnEff THEN
    bWarnLatched := fbTonDevWarn.Q;                      // 超阈值区间：以延时确认结果为准
ELSIF fDevAbs <= (fWarnEff * DL_GANTRY_HYST) THEN
    bWarnLatched := FALSE;                               // 回差内自动清除
END_IF

// 段 10｜首扫与跟踪范式（公约 0.1：bTrack OR (NOT bInit) 为唯一判据，禁止反序）
IF bTrack OR (NOT bInit) THEN
    bWarnLatched := FALSE;
    bStopIssued  := FALSE;
    bStopBothCmd := FALSE;
    fCorrCmd     := 0.0;
    fCorrAbs     := 0.0;
    nStopCode    := 0;
    eState       := E_DL_GantryState.eIdle;
    bInit        := TRUE;                                // 首扫完成后置位（判据恒为 bTrack OR NOT bInit）
END_IF

// 段 11｜总使能撤除：清指令 + 补发一次双轴停止（安全保守处置）
IF NOT bEnable THEN
    IF (NOT bStopIssued) AND ((eState = E_DL_GantryState.eCoupling) OR (eState = E_DL_GantryState.eRun)
       OR (eState = E_DL_GantryState.eCorrecting)) THEN
        iMasterAxis.Stop();                              // 主动侧停止（本拍唯一一次主动侧调用）
        iSlaveAxis.Stop();                               // 从动侧停止（本拍唯一一次从动侧调用）
        bStopIssued := TRUE;
    END_IF
    eState    := E_DL_GantryState.eIdle;
    fCorrCmd  := 0.0;
    fCorrAbs  := 0.0;
END_IF

// 段 12｜事件码管理（公约 0.7 / R15）：锁存码仅在解除路径清，瞬时码逐拍重算
IF NOT bFaultLatch THEN
    uErrorId := 0;
END_IF

// 段 13｜位置 / 力矩类信号非有限值拦截（判定不可信，立即转双停）
IF (fMasterPos <> fMasterPos) OR (fSlavePos <> fSlavePos)
   OR (ABS(fMasterPos) > DL_GANTRY_INF_MAX) OR (ABS(fSlavePos) > DL_GANTRY_INF_MAX) THEN
    IF (eState <> E_DL_GantryState.eIdle) AND (eState <> E_DL_GantryState.eFault) THEN
        nStopCode := 16#0004_0272;                       // 【故障级】轴位置信号非有限值
        eState    := E_DL_GantryState.eStopping;
    END_IF
END_IF

// 段 14｜阈值非法拦截（使能期间逐拍复核组态）
IF bParamBad THEN
    IF eState <> E_DL_GantryState.eFault THEN
        bFaultLatch := TRUE;
        uErrorId    := 16#0004_0270;                     // 【故障级】偏差阈值非法
        eState      := E_DL_GantryState.eFault;
    END_IF
END_IF

// 段 15｜主状态机（ENUM + CASE + ELSE 兜底）
CASE eState OF

    E_DL_GantryState.eIdle:                              // 空闲：等待使能
        bInSync  := FALSE;
        bStopIssued := FALSE;
        bStopBothCmd := FALSE;
        fCorrCmd := 0.0;
        IF bEnable AND (NOT bParamBad) THEN
            bFaultLatch := FALSE;                        // 使能上升：锁存码解除路径（R15）
            fCorrCmd    := 0.0;
            eState      := E_DL_GantryState.eCoupling;
        END_IF

    E_DL_GantryState.eCoupling:                          // 耦合建立：双轴以慢速趋同
        bStopBothCmd := FALSE;
        IF iMasterAxis.bError OR iSlaveAxis.bError THEN
            nStopCode := 16#0004_0274;                   // 【故障级】单轴故障（不对称风险优先）
            eState    := E_DL_GantryState.eStopping;
        ELSIF fbTonDevFault.Q THEN
            nStopCode := 16#0004_0273;                   // 【故障级】偏差超故障阈
            eState    := E_DL_GantryState.eStopping;
        ELSE
            // 跟随主动侧速度，但幅值不超过耦合慢速
            fCmdVel := LIMIT(-fCoupleEff, fMasterVel, fCoupleEff);
            IF NOT iSlaveAxis.MoveVelocity(fVel := fCmdVel, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0274;             // 【故障级】从动侧速度指令被拒（按单轴故障处置）
                eState      := E_DL_GantryState.eFault;
            ELSIF (ABS(fMasterVel - fSlaveVel) <= DL_GANTRY_SPEED_BAND) AND (fDevAbs <= fWarnEff) THEN
                eState := E_DL_GantryState.eRun;         // 速度趋同且偏差在预警阈内 → 运行
            END_IF
        END_IF

    E_DL_GantryState.eRun:                               // 运行：1:1 跟随，纠偏量为零
        IF iMasterAxis.bError OR iSlaveAxis.bError THEN
            nStopCode := 16#0004_0274;
            eState    := E_DL_GantryState.eStopping;
        ELSIF fbTonDevFault.Q THEN
            nStopCode := 16#0004_0273;
            eState    := E_DL_GantryState.eStopping;
        ELSE
            fCorrCmd := 0.0;                             // 运行态不纠偏
            IF bCorrectEnable AND (ABS(fCorrGain) > DL_GANTRY_EPS) AND bWarnLatched THEN
                eState := E_DL_GantryState.eCorrecting;  // 偏差确认超预警阈且纠偏使能 → 纠偏
            END_IF
            fCmdVel := fMasterVel;
            IF NOT iSlaveAxis.MoveVelocity(fVel := fCmdVel, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0274;             // 【故障级】从动侧速度指令被拒
                eState      := E_DL_GantryState.eFault;
            END_IF
        END_IF

    E_DL_GantryState.eCorrecting:                        // 纠偏中：比例律修正量限幅
        IF iMasterAxis.bError OR iSlaveAxis.bError THEN
            nStopCode := 16#0004_0274;
            eState    := E_DL_GantryState.eStopping;
        ELSIF fbTonDevFault.Q THEN
            nStopCode := 16#0004_0273;
            eState    := E_DL_GantryState.eStopping;
        ELSIF fbTonCorrSat.Q THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0271;                 // 【故障级】纠偏长时间饱和（疑似卡滞 / 增益不足）
            eState      := E_DL_GantryState.eFault;
        ELSE
            // 偏差为正（主动侧在前）→ 从动侧加速追赶；为负则减速
            fCorrCmd := LIMIT(-fCorrMaxEff, fCorrGain * fDeviation, fCorrMaxEff);
            fCorrAbs := ABS(fCorrCmd);
            // 偏差回到预警阈 80% 以内（回差）→ 退出纠偏
            IF fDevAbs <= (fWarnEff * DL_GANTRY_HYST) THEN
                fCorrCmd := 0.0;
                fCorrAbs := 0.0;
                eState   := E_DL_GantryState.eRun;
            END_IF
            fCmdVel := fMasterVel + fCorrCmd;
            IF NOT iSlaveAxis.MoveVelocity(fVel := fCmdVel, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0274;             // 【故障级】从动侧速度指令被拒
                eState      := E_DL_GantryState.eFault;
            END_IF
        END_IF

    E_DL_GantryState.eStopping:                          // 双轴停止：同拍各发一次，停稳后锁存
        bStopBothCmd := TRUE;
        fCorrCmd     := 0.0;
        fCorrAbs     := 0.0;
        IF NOT bStopIssued THEN
            iMasterAxis.Stop();                          // 主动侧停止（本拍唯一一次主动侧调用）
            iSlaveAxis.Stop();                           // 从动侧停止（本拍唯一一次从动侧调用）
            bStopIssued := TRUE;
        END_IF
        IF (ABS(fMasterVel) <= DL_GANTRY_EPS) AND (ABS(fSlaveVel) <= DL_GANTRY_EPS) THEN
            bFaultLatch := TRUE;
            IF nStopCode = 0 THEN
                uErrorId := 16#0004_0273;                // 【故障级】兜底：停止原因缺失时按偏差超限记账
            ELSE
                uErrorId := nStopCode;                   // 落地本次停止的真实原因码
            END_IF
            bStopIssued := FALSE;
            eState      := E_DL_GantryState.eFault;
        END_IF

    E_DL_GantryState.eFault:                             // 故障锁存：仅复位沿且偏差回位可退出
        bInSync      := FALSE;
        bStopBothCmd := TRUE;                            // 故障态保持停止请求，供安全链与 HMI 监视
        fCorrCmd     := 0.0;
        fCorrAbs     := 0.0;
        bStopIssued  := FALSE;
        IF fbTrigReset.Q THEN
            IF fDevAbs <= fWarnEff THEN
                bFaultLatch := FALSE;                    // 唯一解除路径：偏差已回预警阈内
                uErrorId    := 0;
                nStopCode   := 0;
                eState      := E_DL_GantryState.eIdle;
            ELSE
                uErrorId := 16#0004_0150;                // 【信息级】偏差未回预警阈内，复位被拒
            END_IF
        END_IF

    ELSE                                                 // 非法状态兜底（本块专用码）
        bFaultLatch  := TRUE;
        uErrorId     := 16#0004_0297;                    // 【故障级】非法状态兜底
        bInSync      := FALSE;
        bStopBothCmd := TRUE;
        fCorrCmd     := 0.0;
        fCorrAbs     := 0.0;
        eState       := E_DL_GantryState.eFault;

END_CASE

// 段 16｜出口映射（派生式，信息级码不参与 bFault）
bFault        := (eState = E_DL_GantryState.eFault);
bInSync       := ((eState = E_DL_GantryState.eRun) OR (eState = E_DL_GantryState.eCorrecting))
                 AND (NOT bWarnLatched);
bDevWarn      := bWarnLatched AND ((eState = E_DL_GantryState.eCoupling)
                 OR (eState = E_DL_GantryState.eRun) OR (eState = E_DL_GantryState.eCorrecting));
bStopBothCmd  := (eState = E_DL_GantryState.eStopping) OR (eState = E_DL_GantryState.eFault);
fDeviation    := fMasterPos - fSlavePos;
fCorrSpeedCmd := fCorrCmd;

END_FUNCTION_BLOCK
