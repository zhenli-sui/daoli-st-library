(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisRelativeMove
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 单轴相对定位与链式步进封装 · 工艺上层件
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（R_TRIG / MIN /
 *                         MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05）
 * 功能描述 (Function)   : 单轴相对定位（MC_MoveRelative 语义）与连续累加步进
 *                         控制封装。经轴接口引用驱动轴体：上升沿发起
 *                         MoveRelative，轮询轴状态回待机判步完成；链式模式下
 *                         到位后自动连续执行下一步，步间距即 fDistance，上层
 *                         运行中递增 nChainTarget 即实现无上限累加步进。
 * 设计要点 (Key notes)  : ① 启动门禁：仅在轴待机态发起；fVel/fAcc 非正值或
 *                           非有限值 → 拒绝启动并置信息级 0004_0106（与
 *                           FB_DL_AxisHomingSeq 同码同义：参数门禁拒绝，共用
 *                           留档）；
 *                         ② 指令被轴拒绝（返回 FALSE）→ 0004_0220 故障级
 *                           锁存；bAbort 或轴故障 → 受控 Stop + 0004_0221
 *                           故障级锁存；两锁存码仅新执行沿解除（R15：锁存型
 *                           故障只在解除路径清码）；
 *                         ③ 链式步进：步完成后隔一拍自动再发（轴待机确认后
 *                           消费），bDone 每步置位保持至下一步启动；
 *                         ④ 本块为事件型 + 轮询状态组件，免首扫（R23），无
 *                           连续量同步语义，不设初始化跟踪逻辑。
 * 开源溯源 (Origin)     : 原创实现（参考 PLCopen Part 1-6 MC_MoveRelative 公开
 *                         语义与西门子 Motion Control 对象语义，clean-room）。
 *                         仅提取公开指令动词与参数域；实现与命名 100% 自有，
 *                         未参考任何厂商源码行。
 * 验收向量 (Acceptance) :
 *   V1 单步链：执行沿→MoveRelative 受理→轮询回待机→bDone+计数+1；
 *   V2 链式 3 步：bChainMode+target=3 → 连续 3 步逐拍推进，bChainDone 置位；
 *   V3 目标递增累加：运行中 nChainTarget 3→5 → 链不中断续跑第 4、5 步；
 *   V4 指令被拒：轴非待机态受理失败 → 0004_0220 锁存，新执行沿解除；
 *   V5 中止：运行中 bAbort → 受控 Stop + 0004_0221；
 *   V6 状态门禁：轴故障态执行沿 → 拒绝并置信息级 0004_0106，轴状态不变。
 * 故障码表 (Error codes):
 *   16#0004_0106【信息级】启动门禁/参数门禁拒绝（与 FB_DL_AxisHomingSeq 同码
 *   同义，共用留档）；16#0004_0220【故障级】定位指令被轴拒绝（锁存）；
 *   16#0004_0221【故障级】中止/轴故障中断（锁存）；16#0004_0201【故障级】
 *   非法状态兜底（沿用族码，与 FB_DL_SingleAxis 同码同义，复用留档）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 06 · DL_Motion 回零/运动族）
 *   2026-11-15  v1.0.1  R11 修复：枚举成员分隔符笔误，eMoving 行误写单冒号 `:`（枚举成员赋值须用 `:=`），三平台编译阻断已消除，数值与语义不变。
 *                       R11 fix: enum member separator erratum, `:` -> `:=` on one member.
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbRel.iAxis := fbAxis;                        // 接口依赖注入
 *   fbRel(bCmdExecute := bDoStep, fDistance := 25.0, // 周期调用
 *         fVel := 100.0, fAcc := 1000.0,
 *         bChainMode := TRUE, nChainTarget := 10);
 *   连续累加步进：运行中每检测到一件料即 nChainTarget := nChainTarget + 1，
 *   链式机制自动续跑，无需停止重启链。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 本块仅在轴待机态发起定位，轴受控停止中/故障态一律拒绝；中止后轴自行
 *     减速回待机，无需上层等待即可发新执行沿。
 *   2 uStepsDone 在每次执行沿清零重新计数；跨链累计请上层自行汇总。
 *   3 bAbort 电平生效：运行中置 TRUE 立即受控停车并锁存 0004_0221，撤除
 *     不自动恢复运行；重新执行需新的 bCmdExecute 上升沿。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RelStep（归属 DL_Motion，与 FB_DL_AxisRelativeMove 同文件）
 * 含义: 相对定位内部步进枚举（本块私有配套，外部仅作诊断参考）。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_RelStep :
(
    eIdle   := 0,    // 空闲：等待执行沿 / Idle: waiting for execute edge
    eMoving := 10    // 定位进行中：轮询轴状态回待机 / Moving: polling axis back to standstill
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_AxisRelativeMove
VAR_INPUT
    bCmdExecute   : BOOL := FALSE;      // 执行指令（Execute command），上升沿生效
    fDistance     : REAL := 0.0;        // 相对位移（Relative distance）[mm]，带符号，负值=负向
    fVel          : REAL := 100.0;      // 运行速度（Run velocity）[mm/s]，正值，默认 100.0
    fAcc          : REAL := 1000.0;     // 加减速度（Acceleration）[mm/s²]，正值，默认 1000.0
    bChainMode    : BOOL := FALSE;      // 链式步进模式（Chain mode），TRUE=到位后自动连续执行下一步
    nChainTarget  : UDINT := 1;         // 链式目标步数（Chain target steps），0=按 1 步处理；运行中递增即累加步进
    bAbort        : BOOL := FALSE;      // 中止（Abort），电平生效 → 轴受控停止
END_VAR
VAR_IN_OUT
    iAxis         : I_DL_MotionAxis;    // 轴接口引用（Axis reference），由上层注入实现块实例
END_VAR
VAR_OUTPUT
    bBusy         : BOOL := FALSE;      // 定位进行中（Move busy）
    bDone         : BOOL := FALSE;      // 单步完成（Step done），每步置位保持至下一步启动
    bChainDone    : BOOL := FALSE;      // 链式目标完成（Chain target reached）
    uStepsDone    : UDINT := 0;         // 本次链累计完成步数（Steps done），执行沿清零
    uErrorId      : UDINT := 0;         // 末次事件码（Last error code），段位 16#0004_xxxx
END_VAR
VAR
    eStep         : E_DL_RelStep := E_DL_RelStep.eIdle; // 内部步进状态（Internal step state）
    bFaultLatch   : BOOL := FALSE;      // 故障锁存标志（Fault latch），0004_0220/0221 锁存载体
    bParamOk      : BOOL := FALSE;      // 参数门禁通过标志（Parameter gate pass flag），逐拍重算
    bWaitNext     : BOOL := FALSE;      // 链式步间一拍间隔标志（Inter-step one-scan wait flag）
    bAbortDone    : BOOL := FALSE;      // 中止停止指令已发标志（Abort stop issued flag），单发化
    uChainTgt     : UDINT := 1;         // 生效链式目标（Effective chain target），下限钳位 1
    fVelEff       : REAL := 100.0;      // 生效运行速度（Effective velocity）[mm/s]，防除零兜底
    fAccEff       : REAL := 1000.0;     // 生效加减速度（Effective acceleration）[mm/s²]，防除零兜底
    rtrigExec     : R_TRIG;             // 执行指令上升沿（Rising edge of execute command）
END_VAR
VAR CONSTANT
    DL_REL_INF_MAX   : REAL := 1.0E30;  // 有限值判定幅值上限（Finite-value magnitude bound）[mm 或 mm/s]
    DL_REL_EPS       : REAL := 1.0E-6;  // 浮点判零容差（Float zero tolerance）
    DL_REL_PAR_FLOOR : REAL := 1.0E-3;  // 速度/加速度参数下限（Velocity and acceleration floor）[mm/s 或 mm/s²]
END_VAR

METHOD IssueMove : BOOL
VAR_INPUT
END_VAR
IssueMove := iAxis.MoveRelative(fDistance, fVelEff, fAccEff);  // 转发轴接口，受理结果即返回值
    END_METHOD

// 段 1｜沿检测无条件周期刷新（R7 红线，严禁置于分支内）
rtrigExec(CLK := bCmdExecute);

// 段 2｜接口引用有效性防御：未注入轴引用则清输出退出（不产生误动作）
IF iAxis = 0 THEN
    bBusy := FALSE;
    RETURN;
END_IF

// 段 3｜参数门禁逐拍重算（公约 0.8）：非法仅封锁启动，运行中不中断
bParamOk := (fDistance = fDistance) AND (fVel = fVel) AND (fAcc = fAcc)
        AND (ABS(fDistance) <= DL_REL_INF_MAX) AND (fVel <= DL_REL_INF_MAX)
        AND (fAcc <= DL_REL_INF_MAX)
        AND (fVel > DL_REL_PAR_FLOOR) AND (fAcc > DL_REL_PAR_FLOOR);
fVelEff := MAX(fVel, DL_REL_PAR_FLOOR);          // 生效速度下限兜底 [mm/s]，防除零
fAccEff := MAX(fAcc, DL_REL_PAR_FLOOR);          // 生效加速度下限兜底 [mm/s²]，防除零

// 段 4｜事件码管理（R15）：瞬时码逐拍重算，锁存码仅在解除路径（新执行沿）清
IF NOT bFaultLatch THEN
    uErrorId := 0;
END_IF

// 段 5｜定位状态机（ENUM + CASE + ELSE 兜底）
CASE eStep OF

    E_DL_RelStep.eIdle:                          // 空闲态：等待执行沿与门禁
        bBusy := FALSE;
        IF rtrigExec.Q THEN
            bFaultLatch := FALSE;                // 新执行沿：锁存码解除路径（R15）
            IF NOT bParamOk THEN
                uErrorId := 16#0004_0106;        // 参数门禁拒绝（信息级）
            ELSIF iAxis.eState <> E_DL_AxisState.eStandstill THEN
                uErrorId := 16#0004_0106;        // 轴非待机态，拒绝发起（信息级）
            ELSE
                uChainTgt := 1;                  // 非链式恒为单步目标 [步]
                IF bChainMode THEN uChainTgt := MAX(nChainTarget, 1); END_IF  // 链式目标下限钳位 1
                uStepsDone := 0;                 // 本次链计数清零
                bDone := FALSE;
                bChainDone := FALSE;
                bWaitNext := FALSE;
                bAbortDone := FALSE;
                IF IssueMove() THEN
                    eStep := E_DL_RelStep.eMoving;
                    bBusy := TRUE;
                ELSE
                    bFaultLatch := TRUE;         // 指令被轴拒绝：故障级锁存
                    uErrorId := 16#0004_0220;
                END_IF
            END_IF
        END_IF

    E_DL_RelStep.eMoving:                        // 定位态：轮询轴状态，链式自动续步
        bBusy := TRUE;
        IF bAbort OR iAxis.bError THEN
            IF NOT bAbortDone THEN
                iAxis.Stop();                    // 中止/轴故障：受控停车单发
                bAbortDone := TRUE;
            END_IF
            bFaultLatch := TRUE;                 // 故障级锁存（R15：仅新执行沿解除）
            uErrorId := 16#0004_0221;
            bBusy := FALSE;
            eStep := E_DL_RelStep.eIdle;
        ELSIF bWaitNext THEN
            bWaitNext := FALSE;                  // 链式步间隔拍：下一拍自动再发（连续累加步进语义）
            IF NOT IssueMove() THEN
                bFaultLatch := TRUE;             // 续步指令被拒：故障级锁存
                uErrorId := 16#0004_0220;
                bBusy := FALSE;
                eStep := E_DL_RelStep.eIdle;
            END_IF
        ELSIF iAxis.eState = E_DL_AxisState.eStandstill THEN
            bDone := TRUE;                       // 单步完成：置位保持至下一步启动
            uStepsDone := uStepsDone + 1;        // 步计数递增 [步]
            IF bChainMode AND (uStepsDone < uChainTgt) THEN
                bWaitNext := TRUE;               // 链未达目标：下一拍续步
            ELSE
                IF bChainMode THEN
                    bChainDone := TRUE;          // 链式目标完成
                END_IF
                bBusy := FALSE;
                eStep := E_DL_RelStep.eIdle;
            END_IF
        END_IF

    ELSE
        // 非法状态兜底（故障级，沿用族码 0004_0201，复用留档）
        uErrorId := 16#0004_0201;
        bFaultLatch := TRUE;
        bBusy := FALSE;
        eStep := E_DL_RelStep.eIdle;

END_CASE

(*-----------------------------------------------------------------------------
 * 方法实现（METHOD）：相对定位指令派发子过程，非阻塞，直接转发轴接口受理
 * 结果；步间距取当前 fDistance 输入值，链式运行中改位移即改步距。
 *-----------------------------------------------------------------------------*)

END_FUNCTION_BLOCK
