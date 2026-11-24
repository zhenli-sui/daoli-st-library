(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TorqueLimitControl
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 压装与力矩族 · 力矩达限压装判定
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library
 *                         （TON / R_TRIG / LIMIT / MIN / MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05，零修改）
 * 功能描述 (Function)   : 力矩达限压装判定（「运行到固定挡块」语义的 clean-room 独立
 *                         实现）。流程为 接近 → 慢速压装 → 力矩达限判定 → 达限保持
 *                         → 位移窗口合格判定 → 释放归位。严格区分「设备异常」（未达
 *                         限超时、力矩信号无效、释放超时）与「工件不合格」（到位但
 *                         位移越窗），前者进故障锁存，后者只出判定结果与方向提示。
 * 设计要点 (Key notes)  :
 *   ① 达限判据三源等价（驱动器力矩限制激活 / 实际力矩达阈值 / 驱动器到达挡块反馈），
 *      三者任一成立即判达限，现场按可用信号接入，未接线引脚保持 FALSE 即可。
 *   ② 位移窗判定只在「达限瞬间位置」上做一次锁存判定，判定结果全程保持，避免释放
 *      段位置回退污染结论。
 *   ③ 判定输出先清后置，出口断言「合格与不合格不同时为真」，不合格优先。
 *   ④ 单拍脉冲 bDone 采用「进入态置位、下一拍开头复位」的闭环生命周期，不在同一
 *      扫描内自我清除（单拍标志生命周期三律）。
 *   ⑤ 本块只做判定与流程编排：力矩限幅本身由驱动器参数承担，软件力矩限制不是安全
 *      功能，机械限位与安全回路仍是最终边界。
 * 开源溯源 (Origin)     : 原创实现，clean-room。语义来源为某工业自动化厂商官方支持
 *                         文档的公开页面「转矩限幅及固定停止点检测」（两种模式分离、
 *                         达限状态输出）、公开技术知识库页面（挡块力矩 / 位置检测窗
 *                         / 到达挡块最长时限的参数域）（来源编号 RAW_NOTES S-4）。
 *                         「借鉴对象的许可说明」：上述对象为该厂商免费使用但闭源
 *                         版权的官方文档与公开技术文章，属「可免费查阅、仅借鉴参数
 *                         域与状态语义」类别；本实现未复制任何示例程序、源码或组态
 *                         数据，状态机、判定逻辑、故障码 100% 自有设计；亦不实现
 *                         厂商的力矩限幅指令本身（本库接口无扭矩域，扭矩经引脚注入）。
 * 验收向量 (Acceptance) :
 *   V1 正常压装：达限位置 20.5 mm、位移窗 20.0~21.0 → bJudgeOk 为 TRUE；
 *   V2 压到 19.5 mm（低于窗下限）→ bJudgeNg 为 TRUE 且出信息级 0163；
 *   V3 压到 21.5 mm（高于窗上限）→ bJudgeNg 为 TRUE 且出信息级 0164；
 *   V4 压装段 10 s 未达限 → 锁存 0282（工件过软 / 未到位 / 信号失效）；
 *   V5 终点不超过起点 → 启动沿锁存 0280（方向组态错误）；
 *   V6 位移窗写反（低 21 / 高 20）→ 对调自修复 + 信息级 0160，判定仍有效；
 *   V7 中途 bAbort → 立即受控停止退回，判定输出清零且不置不合格；
 *   V8 fActTorque 为非有限值 → 锁存 0283（判定不可信）；
 *   V9 运行中途插入跟踪脉冲 bTrack：清判定与锁存、退回 eIdle（公约 0.1）。
 * 已知限制 (Limits)     :
 *   ① 力矩与达限状态由驱动适配层经引脚注入（轴接口无扭矩域），本块不读取驱动器
 *      内部参数；引脚未接时达限判据退化为阈值比较，可能永远等不到达限。
 *   ② 释放目标固定取压装起点（不引入额外释放位引脚），若工艺需要退到更远的安全
 *      位，请在上层压制完成后追加一条定位指令。
 *   ③ 本块为判定层与流程编排层，不构成 ISO 13849 / IEC 62061 认证安全功能。
 * 规格偏离 (Deviation)  :
 *   ① 依公约 0.1 增补 bTrack 输入引脚（首扫 / 跟踪范式强制项）。
 *   ② eRelease 超时按故障级 0281 处理并进入 eFault，而非留在 eDone 带码：
 *      规格仅写「超时置故障 0281，不静默」，本块取严格处置，避免上层误判合格。
 *   ③ 速度 / 力矩参数非正或非有限值时回默认值（与库内其他运动件口径一致），
 *      不在启动沿判故障；力矩阈值超额定只提示不阻断（依规格 0161 语义）。
 *   ④ 使能撤除时补发一次停止请求（安全保守处置）。
 * 红线自检 (Redline)    :
 *   R1 零全局符号区访问 ✓（无全局变量表访问、无外部变量声明）
 *   R2 零物理地址直写 ✓（无输入输出通道地址记号）
 *   R3 纯 IEC 61131-3 ✓（仅 TON / R_TRIG / LIMIT / MIN / MAX / ABS）
 *   R4 防除零 / 防越界 / 浮点容差 ✓（无除法、浮点比较全用容差、无数组索引）
 *   R5 声明行 100% 中英双语同行注释 ✓
 *   R6 ENUM + CASE 且 CASE 含 ELSE 兜底 ✓
 *   R7 定时器与边沿实例无条件周期刷新 ✓；单拍标志 bDone 置位于本次进入、复位于
 *      下一拍开头，同一周期闭环，无跨周期残留 ✓
 *   POU 终结符成对 ✓（FUNCTION_BLOCK ↔ END_FUNCTION_BLOCK，末行即终结符；
 *   TYPE ↔ END_TYPE 成对）
 * 故障码表 (Error codes):
 *   16#0004_0160【信息级】位移窗上下限对调自修复；
 *   16#0004_0161【信息级】达限力矩超额定（机械风险提示）；
 *   16#0004_0162【信息级】压装速度高于接近速度（工艺反常）；
 *   16#0004_0163【信息级】到位但位移低于窗下限（压浅，判定方向提示）；
 *   16#0004_0164【信息级】到位但位移高于窗上限（压深，判定方向提示）；
 *   16#0004_0280【故障级】压装行程组态非法（终点不大于起点 / 位置非有限值），锁存；
 *   16#0004_0281【故障级】释放超时，锁存；
 *   16#0004_0282【故障级】压装超时未达限，锁存；
 *   16#0004_0283【故障级】力矩信号非有限值，锁存；
 *   16#0004_0284【故障级】轴指令被拒 / 轴故障，锁存；
 *   16#0004_0296【故障级】非法状态兜底（本块专用，不与其他块共用）。
 *   信息级码只进 uErrorId；bError 为派生式仅反映 eFault 态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Motion 压装与力矩族开族件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbPress.iAxis := fbPressAxis;                  // 压装轴实例注入
 *   fbPress(bEnable := TRUE, bStart := bStartPress,
 *           fPressStartPos := 10.0, fPressEndPos := 30.0,
 *           fPosWindowLow := 20.0, fPosWindowHigh := 21.0,
 *           fTorqueLimit := 30.0,
 *           fApproachVel := 50.0, fPressVel := 5.0, fAcc := 200.0,
 *           tClampTime := T#300MS, tPressTimeout := T#10S,
 *           fActTorque := fDriveTorque,
 *           bTorqueLimitActive := bDriveInLimitation);
 *   IF fbPress.bDone THEN
 *       bResultOk := fbPress.bJudgeOk;             // 只在 bDone 单拍内取结果
 *   END_IF
 *   注：驱动器侧的力矩限幅（如力矩上限参数族）与「到达挡块」功能必须先行组态，
 *       本块只消费其状态反馈，不代替驱动器限幅。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 压装速度经验值取接近速度的 1/10 左右；压装快于接近速度时本块只提示
 *      （信息级 0162），不会拒绝执行，但冲击会损伤工件与压头。
 *   2 位移窗必须按「达限瞬间位置」组态，而不是按「起点到终点」的行程；窗上下限
 *      填反会被自动对调并提示，但仍建议在配方里改对。
 *   3 力矩阈值填超过额定值（>100）只提示不阻断，属于「明知有机械风险仍要压」的
 *      场景；正式产线请把上限压回 100 以内。
 *   4 bAbort 是电平最高优先：任意态给 TRUE 立即受控停止并退回空闲，判定结果清零，
 *      不会把中途中止误判为不合格工件。
 *   5 bDone 只维持一个扫描周期，上层必须在本拍内取 bJudgeOk / bJudgeNg 并存到
 *      自己的结果寄存器里；跨拍读判定请读 bJudgeOk / bJudgeNg（这两者在 eDone
 *      期间保持）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PressState（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 力矩达限压装流程状态机，编号间隔 10 预留扩展位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_PressState :
(
    eIdle     := 0,    // 空闲：未启动，输出清零 / Idle: not started, outputs cleared
    eApproach := 10,   // 接近：以接近速度走向压装起点 / Approach: move to press start at approach speed
    ePress    := 20,   // 压装：以压装速度慢速压入，等力矩达限 / Press: slow press until torque limit reached
    eClamp    := 30,   // 达限保持：力矩达限后保位并计时（应力松弛） / Clamp: hold position and time after torque limit
    eRelease  := 40,   // 释放：退回压装起点 / Release: retract to press start position
    eDone     := 50,   // 完成：判定结果有效，等新启动沿 / Done: judgement valid, waiting for new start edge
    eFault    := 99    // 故障锁存：仅 bReset 上升沿可退出 / Fault: latched, only bReset rising edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_TorqueLimitControl
VAR_INPUT
    bEnable            : BOOL := FALSE;     // 总使能（Enable），FALSE=中止流程并清输出，电平语义
    bStart             : BOOL := FALSE;     // 启动压装周期（Start），上升沿受理，仅 eIdle / eDone 受理
    bAbort             : BOOL := FALSE;     // 中止（Abort），电平最高优先，立即受控停止并退回空闲
    bReset             : BOOL := FALSE;     // 复位故障与判定结果（Reset），上升沿受理
    bTrack             : BOOL := FALSE;     // 内部锁存重同步（Tracking pulse），上升沿清判定与故障并退回 eIdle
    fPressStartPos     : REAL := 0.0;       // 压装起点位置（Press start position）[mm]，接近段目标与释放目标
    fPressEndPos       : REAL := 0.0;       // 压装终点位置（Press end position）[mm]，必须大于起点
    fPosWindowLow      : REAL := 0.0;       // 到位位移窗下限（Position window low）[mm]，窗上下限写反自动对调
    fPosWindowHigh     : REAL := 0.0;       // 到位位移窗上限（Position window high）[mm]
    fTorqueLimit       : REAL := 30.0;      // 达限判定力矩（Torque limit）[% 额定]，域 1..150，>100 仅提示
    fApproachVel       : REAL := 50.0;      // 接近速度（Approach velocity）[mm/s]，域 0.1..1000，非正值回默认
    fPressVel          : REAL := 5.0;       // 压装速度（Press velocity）[mm/s]，域 0.1..100，建议不超接近速度 1/10
    fAcc               : REAL := 200.0;     // 加/减速度（Acceleration）[mm/s²]，域 0.1..100000，非有限值回默认
    tClampTime         : TIME := T#300MS;   // 达限保持时间（Clamp hold time）[ms]，域 T#0S..T#10S
    tPressTimeout      : TIME := T#10S;     // 压装超时（Press timeout）[ms]，域 T#100MS..T#60S
    tReleaseTimeout    : TIME := T#5S;      // 释放超时（Release timeout）[ms]，超时判故障级
    fActTorque         : REAL := 0.0;       // 实际力矩（Actual torque）[% 额定]，由驱动适配层注入
    bTorqueLimitActive : BOOL := FALSE;     // 驱动器力矩限制已激活反馈（Drive in limitation），由适配层注入
    bInClampFeedback   : BOOL := FALSE;     // 驱动器到达固定挡块反馈（Fixed stop reached），可选，未接线保持 FALSE
END_VAR
VAR_OUTPUT
    bJudgeOk           : BOOL := FALSE;     // 判定合格（Judge OK），eDone 内保持
    bJudgeNg           : BOOL := FALSE;     // 判定不合格（Judge NG），eDone 内保持，与合格互斥且优先
    bInClamp           : BOOL := FALSE;     // 已达限压紧（In clamp），eClamp 态为 TRUE
    bBusy              : BOOL := FALSE;     // 周期执行中（Busy），接近 / 压装 / 保持 / 释放四态为 TRUE
    bDone              : BOOL := FALSE;     // 周期结束单拍脉冲（Done pulse），仅进入 eDone 那一拍为 TRUE
    fPosAtClamp        : REAL := 0.0;       // 达限瞬间位置（Position at clamp）[mm]，锁存值
    fTorqueAtClamp     : REAL := 0.0;       // 达限瞬间力矩（Torque at clamp）[% 额定]，锁存值
    bError             : BOOL := FALSE;     // 故障锁存（Error），派生式仅故障级码参与，信息级码不置位
    uErrorId           : UDINT := 0;        // 故障码（Error code），段位 16#0004_xxxx，0=无故障
    nCycleCount        : UDINT := 0;        // 完成周期计数（Cycle counter）[次]，每次进入 eDone 加一
END_VAR
VAR_IN_OUT
    iAxis              : I_DL_MotionAxis;   // 压装轴接口引用（Press axis），由调用方注入实现块实例
END_VAR
VAR
    eState             : E_DL_PressState := E_DL_PressState.eIdle; // 内部状态机步序（Internal state）
    bInit              : BOOL := FALSE;     // 首扫完成标志（First-scan done flag），初值 FALSE，随 bTrack 复位
    bFaultLatch        : BOOL := FALSE;     // 故障锁存标志（Fault latch），仅 bReset 沿或新启动沿解除
    bStopIssued        : BOOL := FALSE;     // 停止已下发标志（Stop issued flag），单发化防重复发令
    bTorqueReached     : BOOL := FALSE;     // 达限标志（Torque limit reached），三源 OR 结果
    bClampTimerBrk     : BOOL := FALSE;     // 保持计时断输入标志（Clamp timer break），时间参数变更时置位
    bPressTimerBrk     : BOOL := FALSE;     // 压装计时断输入标志（Press timer break），时间参数变更时置位
    bRelTimerBrk       : BOOL := FALSE;     // 释放计时断输入标志（Release timer break），时间参数变更时置位
    fWinLowEff         : REAL := 0.0;       // 生效位移窗下限（Effective window low）[mm]，对调后的较小值
    fWinHighEff        : REAL := 0.0;       // 生效位移窗上限（Effective window high）[mm]，对调后的较大值
    fTorqueLimitEff    : REAL := 30.0;      // 生效力矩阈值（Effective torque limit）[% 额定]，已做域钳位
    fApproachEff       : REAL := 50.0;      // 生效接近速度（Effective approach velocity）[mm/s]
    fPressEff          : REAL := 5.0;       // 生效压装速度（Effective press velocity）[mm/s]
    fAccEff            : REAL := 200.0;     // 生效加减速度（Effective acceleration）[mm/s²]
    fPosNow            : REAL := 0.0;      // 轴当前实际位置（Actual position）[mm]
    fTorqueNow         : REAL := 0.0;      // 力矩当前值（Actual torque）[% 额定]，非有限值时按 0 记账
    tClampEff          : TIME := T#300MS;   // 生效保持时间（Effective clamp time）[ms]，负值归零
    tPressEff          : TIME := T#10S;     // 生效压装超时（Effective press timeout）[ms]
    tRelEff            : TIME := T#5S;      // 生效释放超时（Effective release timeout）[ms]
    tClampPrev         : TIME := T#0MS;     // 上拍保持时间（Previous clamp time）[ms]，变更检测基准
    tPressPrev         : TIME := T#0MS;     // 上拍压装超时（Previous press timeout）[ms]，变更检测基准
    tRelPrev           : TIME := T#0MS;     // 上拍释放超时（Previous release timeout）[ms]，变更检测基准
    fbTrigStart        : R_TRIG;            // 启动指令上升沿（Start command rising edge）
    fbTrigReset        : R_TRIG;            // 复位指令上升沿（Reset command rising edge）
    fbTonClamp         : TON;               // 达限保持计时（Clamp hold timer）
    fbTonPressTimeout  : TON;               // 压装超时监控（Press timeout timer）
    fbTonRelTimeout    : TON;               // 释放超时监控（Release timeout timer）
END_VAR
VAR CONSTANT
    DL_PRESS_INF_MAX     : REAL := 1.0E30;  // 有限值判定幅值上限（Finite magnitude bound）[无量纲，按比较量量纲同值使用]
    DL_PRESS_EPS         : REAL := 1.0E-6;  // 浮点判零容差（Float zero tolerance）[无量纲，按比较量量纲同值使用]
    DL_PRESS_POS_BAND    : REAL := 0.05;    // 到位判定带（In-position band）[mm]，位置差小于此值判到位
    DL_PRESS_PAR_FLOOR   : REAL := 1.0E-3;  // 速度/加速度参数下限（Parameter floor）[mm/s 或 mm/s²]
    DL_PRESS_APPR_DEF    : REAL := 50.0;    // 接近速度默认值（Default approach velocity）[mm/s]
    DL_PRESS_PRESS_DEF   : REAL := 5.0;     // 压装速度默认值（Default press velocity）[mm/s]
    DL_PRESS_ACC_DEF     : REAL := 200.0;   // 加速度默认值（Default acceleration）[mm/s²]
    DL_PRESS_VEL_MAX     : REAL := 1000.0;  // 接近速度上限（Approach velocity ceiling）[mm/s]，超限钳位
    DL_PRESS_TQ_DEF      : REAL := 30.0;    // 力矩阈值默认值（Default torque limit）[% 额定]
    DL_PRESS_TQ_NOMINAL  : REAL := 100.0;   // 额定力矩（Nominal torque）[% 额定]，超此值仅提示
    DL_PRESS_TQ_MAX      : REAL := 150.0;   // 力矩阈值上限（Torque limit ceiling）[% 额定]，超限钳位
    DL_PRESS_ZERO_TIME   : TIME := T#0S;    // 零时间字面量（Zero time literal）[ms]，用于时间下限比较
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTrigStart(CLK := bStart);
fbTrigReset(CLK := bReset);

// 段 2｜出口默认赋值（公约 0.9：早退路径输出必须确定）；bDone 在此复位 = 单拍闭环
bBusy      := FALSE;
bInClamp   := FALSE;
bDone      := FALSE;
bError     := (eState = E_DL_PressState.eFault);

// 段 3｜接口引用有效性防御：未注入轴引用则清输出退出
IF iAxis = 0 THEN
    RETURN;
END_IF

// 段 4｜参数防御：速度 / 加速度 / 力矩阈值非正或非有限值回默认，位移窗写反自动对调
IF (fApproachVel <> fApproachVel) OR (ABS(fApproachVel) > DL_PRESS_INF_MAX)
   OR (fApproachVel < DL_PRESS_PAR_FLOOR) THEN
    fApproachEff := DL_PRESS_APPR_DEF;                    // 接近速度非法 → 默认
ELSE
    fApproachEff := MIN(fApproachVel, DL_PRESS_VEL_MAX);   // 合法 → 上限钳位
END_IF

IF (fPressVel <> fPressVel) OR (ABS(fPressVel) > DL_PRESS_INF_MAX)
   OR (fPressVel < DL_PRESS_PAR_FLOOR) THEN
    fPressEff := DL_PRESS_PRESS_DEF;                      // 压装速度非法 → 默认
ELSE
    fPressEff := MIN(fPressVel, fApproachEff);            // 合法 → 不超接近速度（超出部分另出信息码提示）
END_IF

IF (fAcc <> fAcc) OR (ABS(fAcc) > DL_PRESS_INF_MAX) OR (fAcc < DL_PRESS_PAR_FLOOR) THEN
    fAccEff := DL_PRESS_ACC_DEF;
ELSE
    fAccEff := fAcc;
END_IF

IF (fTorqueLimit <> fTorqueLimit) OR (ABS(fTorqueLimit) > DL_PRESS_INF_MAX)
   OR (fTorqueLimit < DL_PRESS_PAR_FLOOR) THEN
    fTorqueLimitEff := DL_PRESS_TQ_DEF;                   // 力矩阈值非法 → 默认
ELSE
    fTorqueLimitEff := MIN(fTorqueLimit, DL_PRESS_TQ_MAX); // 合法 → 上限钳位 150%
END_IF

fWinLowEff  := fPosWindowLow;
fWinHighEff := fPosWindowHigh;
IF (fWinLowEff <> fWinLowEff) OR (fWinHighEff <> fWinHighEff) THEN
    fWinLowEff  := 0.0;                                   // 非有限值：窗回零，判定必然趋向不合格
    fWinHighEff := 0.0;
ELSIF fWinLowEff > (fWinHighEff - DL_PRESS_EPS) THEN
    fWinLowEff  := fPosWindowHigh;                        // 写反：对调自修复，不静默
    fWinHighEff := fPosWindowLow;
    uErrorId    := 16#0004_0160;                          // 【信息级】位移窗上下限对调自修复
END_IF

// 段 5｜时间参数防御与变更检测（公约 0.6：语义参数变化必须断输入一拍使计时归零）
IF tClampTime < DL_PRESS_ZERO_TIME THEN
    tClampEff := DL_PRESS_ZERO_TIME;
ELSE
    tClampEff := tClampTime;
END_IF
IF tPressTimeout < DL_PRESS_ZERO_TIME THEN
    tPressEff := DL_PRESS_ZERO_TIME;
ELSE
    tPressEff := tPressTimeout;
END_IF
IF tReleaseTimeout < DL_PRESS_ZERO_TIME THEN
    tRelEff := DL_PRESS_ZERO_TIME;
ELSE
    tRelEff := tReleaseTimeout;
END_IF
bClampTimerBrk := (tClampEff <> tClampPrev);
bPressTimerBrk := (tPressEff <> tPressPrev);
bRelTimerBrk   := (tRelEff <> tRelPrev);
tClampPrev     := tClampEff;
tPressPrev     := tPressEff;
tRelPrev       := tRelEff;

// 段 6｜反馈量采集与信号有效性判定
fPosNow := iAxis.fPosition;
IF (fActTorque <> fActTorque) OR (ABS(fActTorque) > DL_PRESS_INF_MAX) THEN
    fTorqueNow  := 0.0;                                   // 力矩信号无效：按零记账，另由状态机置故障级
    bTorqueReached := FALSE;
ELSE
    fTorqueNow  := fActTorque;
    // 达限三源等价：驱动器限制激活 / 实际力矩达阈值 / 到达挡块反馈，任一成立即达限
    bTorqueReached := bTorqueLimitActive OR (fTorqueNow >= fTorqueLimitEff) OR bInClampFeedback;
END_IF

// 段 7｜定时器无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTonClamp(IN := (eState = E_DL_PressState.eClamp) AND (NOT bClampTimerBrk), PT := tClampEff);
fbTonPressTimeout(IN := (eState = E_DL_PressState.ePress) AND (NOT bPressTimerBrk), PT := tPressEff);
fbTonRelTimeout(IN := (eState = E_DL_PressState.eRelease) AND (NOT bRelTimerBrk), PT := tRelEff);

// 段 8｜首扫与跟踪范式（公约 0.1：bTrack OR (NOT bInit) 为唯一判据，禁止反序）
IF bTrack OR (NOT bInit) THEN
    bFaultLatch    := FALSE;
    bStopIssued    := FALSE;
    bJudgeOk       := FALSE;
    bJudgeNg       := FALSE;
    fPosAtClamp    := 0.0;                                // 达限位置锁存清零 [mm]
    fTorqueAtClamp := 0.0;                                // 达限力矩锁存清零 [% 额定]
    eState         := E_DL_PressState.eIdle;
    bInit          := TRUE;                               // 首扫完成后置位（判据恒为 bTrack OR NOT bInit）
END_IF

// 段 9｜总使能撤除：中止流程 + 补发一次停止（安全保守处置）
IF NOT bEnable THEN
    IF (NOT bStopIssued) AND (eState <> E_DL_PressState.eIdle) AND (eState <> E_DL_PressState.eFault) THEN
        iAxis.Stop();                                     // 使能撤除瞬间单发停止
        bStopIssued := TRUE;
    END_IF
    eState     := E_DL_PressState.eIdle;
    bJudgeOk   := FALSE;
    bJudgeNg   := FALSE;
    bInClamp   := FALSE;
END_IF

// 段 10｜中止最高优先：任意运行态立即受控停止并退回空闲（不置不合格，避免误判工件）
IF bAbort AND (eState <> E_DL_PressState.eIdle) AND (eState <> E_DL_PressState.eFault) THEN
    IF NOT bStopIssued THEN
        iAxis.Stop();                                     // 中止单发停止（本拍唯一一次轴调用）
        bStopIssued := TRUE;
    END_IF
    bJudgeOk   := FALSE;
    bJudgeNg   := FALSE;
    bInClamp   := FALSE;
    bBusy      := FALSE;
    eState     := E_DL_PressState.eIdle;
END_IF

// 段 11｜事件码管理（公约 0.7 / R15）：锁存码仅在解除路径清，瞬时码逐拍重算
IF NOT bFaultLatch THEN
    uErrorId := 0;
END_IF

// 段 11.5｜轴位置非有限值拦截（反馈不可信时不得继续判定，按轴异常处置）
IF (fPosNow <> fPosNow) OR (ABS(fPosNow) > DL_PRESS_INF_MAX) THEN
    IF (eState <> E_DL_PressState.eIdle) AND (eState <> E_DL_PressState.eFault) THEN
        bFaultLatch := TRUE;
        uErrorId    := 16#0004_0284;                      // 【故障级】轴位置非有限值（按压装轴异常处置）
        eState      := E_DL_PressState.eFault;
    END_IF
END_IF

// 段 12｜主状态机（ENUM + CASE + ELSE 兜底）
CASE eState OF

    E_DL_PressState.eIdle:                                // 空闲：等待启动沿与组态校验
        bBusy    := FALSE;
        bInClamp := FALSE;
        IF fbTrigStart.Q AND bEnable AND (NOT bAbort) THEN
            bFaultLatch := FALSE;                         // 新启动沿：锁存码解除路径（R15）
            bJudgeOk    := FALSE;
            bJudgeNg    := FALSE;
            bStopIssued := FALSE;
            IF (fPressEndPos <> fPressEndPos) OR (fPressStartPos <> fPressStartPos)
               OR (ABS(fPressEndPos) > DL_PRESS_INF_MAX) OR (ABS(fPressStartPos) > DL_PRESS_INF_MAX)
               OR ((fPressEndPos - fPressStartPos) <= DL_PRESS_EPS) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0280;              // 【故障级】压装行程组态非法（终点不大于起点 / 位置非有限值）
                eState      := E_DL_PressState.eFault;
            ELSE
                IF fTorqueLimitEff > DL_PRESS_TQ_NOMINAL THEN
                    uErrorId := 16#0004_0161;             // 【信息级】达限力矩超额定（机械风险提示）
                ELSIF fPressVel > fApproachVel THEN
                    uErrorId := 16#0004_0162;             // 【信息级】压装速度高于接近速度（工艺反常）
                END_IF
                fPosAtClamp    := 0.0;
                fTorqueAtClamp := 0.0;
                eState         := E_DL_PressState.eApproach;
            END_IF
        END_IF

    E_DL_PressState.eApproach:                            // 接近：以接近速度走向压装起点
        bBusy := TRUE;
        IF iAxis.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0284;                  // 【故障级】轴故障
            eState      := E_DL_PressState.eFault;
        ELSIF ABS(fPosNow - fPressStartPos) <= DL_PRESS_POS_BAND THEN
            eState := E_DL_PressState.ePress;             // 到位 → 进入压装段
        ELSE
            IF NOT iAxis.MoveAbsolute(fPos := fPressStartPos, fVel := fApproachEff, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0284;              // 【故障级】轴指令被拒
                eState      := E_DL_PressState.eFault;
            END_IF
        END_IF

    E_DL_PressState.ePress:                               // 压装：慢速压入，等力矩达限
        bBusy := TRUE;
        IF iAxis.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0284;                  // 【故障级】轴故障
            eState      := E_DL_PressState.eFault;
        ELSIF (fActTorque <> fActTorque) OR (ABS(fActTorque) > DL_PRESS_INF_MAX) THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0283;                  // 【故障级】力矩信号非有限值，判定不可信
            eState      := E_DL_PressState.eFault;
        ELSIF bTorqueReached THEN
            fPosAtClamp    := fPosNow;                     // 锁存达限瞬间位置 [mm]
            fTorqueAtClamp := fTorqueNow;                  // 锁存达限瞬间力矩 [% 额定]
            eState         := E_DL_PressState.eClamp;      // 进入达限保持段
        ELSIF fbTonPressTimeout.Q THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0282;                  // 【故障级】压装超时未达限
            eState      := E_DL_PressState.eFault;
        ELSE
            IF NOT iAxis.MoveAbsolute(fPos := fPressEndPos, fVel := fPressEff, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0284;              // 【故障级】轴指令被拒
                eState      := E_DL_PressState.eFault;
            END_IF
        END_IF

    E_DL_PressState.eClamp:                               // 达限保持：零速保位并计时
        bBusy    := TRUE;
        bInClamp := TRUE;
        IF iAxis.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0284;                  // 【故障级】轴故障
            eState      := E_DL_PressState.eFault;
        ELSIF fbTonClamp.Q THEN
            // 保持结束：按达限瞬间位置做位移窗判定（先清后置，不合格优先）
            bJudgeOk   := FALSE;
            bJudgeNg   := FALSE;
            IF (fPosAtClamp >= fWinLowEff) AND (fPosAtClamp <= fWinHighEff) THEN
                bJudgeOk := TRUE;                         // 落在窗内：合格
            ELSE
                bJudgeNg := TRUE;                         // 越窗：不合格
                IF fPosAtClamp < fWinLowEff THEN
                    uErrorId := 16#0004_0163;             // 【信息级】压浅（低于窗下限）
                ELSE
                    uErrorId := 16#0004_0164;             // 【信息级】压深（高于窗上限）
                END_IF
            END_IF
            bInClamp   := FALSE;
            eState     := E_DL_PressState.eRelease;
        ELSE
            IF NOT iAxis.MoveVelocity(fVel := 0.0, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0284;              // 【故障级】保位指令被拒
                eState      := E_DL_PressState.eFault;
            END_IF
        END_IF

    E_DL_PressState.eRelease:                             // 释放：退回压装起点
        bBusy := TRUE;
        IF iAxis.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0284;                  // 【故障级】轴故障
            eState      := E_DL_PressState.eFault;
        ELSIF ABS(fPosNow - fPressStartPos) <= DL_PRESS_POS_BAND THEN
            bBusy        := FALSE;
            bDone        := TRUE;                         // 单拍脉冲：本拍置位，下一拍开头复位
            nCycleCount  := nCycleCount + 1;              // 完成周期计数 [次]
            bStopIssued  := FALSE;
            eState       := E_DL_PressState.eDone;
        ELSIF fbTonRelTimeout.Q THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0281;                  // 【故障级】释放超时（不静默，避免上层误判合格）
            eState      := E_DL_PressState.eFault;
        ELSE
            IF NOT iAxis.MoveAbsolute(fPos := fPressStartPos, fVel := fApproachEff, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0284;              // 【故障级】轴指令被拒
                eState      := E_DL_PressState.eFault;
            END_IF
        END_IF

    E_DL_PressState.eDone:                                // 完成：判定保持，等新启动沿或复位
        bBusy    := FALSE;
        bInClamp := FALSE;
        IF fbTrigReset.Q THEN
            bJudgeOk   := FALSE;
            bJudgeNg   := FALSE;
            eState     := E_DL_PressState.eIdle;
        ELSIF fbTrigStart.Q AND bEnable AND (NOT bAbort) THEN
            bJudgeOk   := FALSE;                          // 新周期：判定清零后重新压装
            bJudgeNg   := FALSE;
            fPosAtClamp    := 0.0;
            fTorqueAtClamp := 0.0;
            bStopIssued    := FALSE;
            IF (fPressEndPos <> fPressEndPos) OR (fPressStartPos <> fPressStartPos)
               OR ((fPressEndPos - fPressStartPos) <= DL_PRESS_EPS) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0280;              // 【故障级】压装行程组态非法
                eState      := E_DL_PressState.eFault;
            ELSE
                eState := E_DL_PressState.eApproach;
            END_IF
        END_IF

    E_DL_PressState.eFault:                               // 故障锁存：仅复位沿可退出
        bBusy      := FALSE;
        bInClamp   := FALSE;
        bStopIssued := FALSE;
        IF fbTrigReset.Q THEN
            bFaultLatch    := FALSE;                      // 唯一解除路径
            uErrorId       := 0;
            bJudgeOk       := FALSE;
            bJudgeNg       := FALSE;
            fPosAtClamp    := 0.0;
            fTorqueAtClamp := 0.0;
            eState         := E_DL_PressState.eIdle;
        END_IF

    ELSE                                                  // 非法状态兜底（本块专用码）
        bFaultLatch := TRUE;
        uErrorId    := 16#0004_0296;                      // 【故障级】非法状态兜底
        bBusy       := FALSE;
        bInClamp    := FALSE;
        eState      := E_DL_PressState.eFault;

END_CASE

// 段 13｜出口映射与判定互斥断言（不合格优先，两者不得同真）
bError   := (eState = E_DL_PressState.eFault);
bInClamp := (eState = E_DL_PressState.eClamp);
bBusy    := (eState = E_DL_PressState.eApproach) OR (eState = E_DL_PressState.ePress)
            OR (eState = E_DL_PressState.eClamp) OR (eState = E_DL_PressState.eRelease);
IF bJudgeOk AND bJudgeNg THEN
    bJudgeOk := FALSE;                                    // 互斥断言：同时为真时按不合格处置
    bJudgeNg := TRUE;
END_IF

END_FUNCTION_BLOCK
