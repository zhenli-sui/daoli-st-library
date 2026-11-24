(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisVelocityMove
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 单轴速度模式与动态变速封装 · 工艺上层件
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（R_TRIG /
 *                         F_TRIG / MIN / MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05）
 * 功能描述 (Function)   : 单轴速度模式（MC_MoveVelocity 语义）与动态变速控制
 *                         封装。经轴接口引用驱动轴体：指令电平生效，TRUE=运行
 *                         / FALSE=受控停止；运行中变更 fVelocity 即为改速请求
 *                         （轴接口连续运动改速语义，改速而非重启），bDynamicRetarget
 *                         使能时自动重发；速度上限独立钳位，越限置信息级。
 * 设计要点 (Key notes)  : ① 指令上升沿门禁：轴待机态受理运行、连续运动态受理
 *                           改速；其余态请求不被受理 → 信息级 0004_0107；
 *                         ② 动态改速：连续运动中 |fVelocity − 上次已发值| 超
 *                           容差即重发 MoveVelocity（改速语义），指令被拒 →
 *                           0004_0230 故障级锁存；
 *                         ③ 下降沿 → 轴受控停止（MC_Stop 语义）；
 *                         ④ 参数门禁（fAcc 非正值/非有限值）→ 信息级 0004_0106
 *                           （与 FB_DL_AxisHomingSeq/FB_DL_AxisRelativeMove
 *                           同码同义：参数门禁拒绝，共用留档）；
 *                         ⑤ 本块为事件型 + 轮询状态组件，免首扫（R23）。
 * 开源溯源 (Origin)     : 原创实现（参考 PLCopen Part 1-6 MC_MoveVelocity 公开
 *                         语义与西门子 Motion Control 对象语义，clean-room）。
 *                         仅提取公开指令动词、参数域与改速语义；实现与命名
 *                         100% 自有，未参考任何厂商源码行。
 * 验收向量 (Acceptance) :
 *   V1 启动-停止链：bCmdStart 上升沿→轴进连续运动；下降沿→受控停止；
 *   V2 运行中改速：fVelocity 50→-30（含反向）→ 自动重发改速，轴不重启；
 *   V3 改速被拒：轴受控停止中发改速请求 → 信息级 0004_0107，轴不受扰；
 *   V4 速度钳位：|fVelocity|=5000 > fVelMax=1000 → 钳位至 1000 + 信息级；
 *   V5 轴故障中断：运行中轴故障反馈 → 0004_0230 锁存，bBusy 退出。
 * 故障码表 (Error codes):
 *   16#0004_0106【信息级】参数门禁拒绝（三块同码同义，共用留档）；
 *   16#0004_0107【信息级】改速请求不被受理/速度钳位提示（规格外补充子义，
 *   R11 留档）；16#0004_0230【故障级】指令被拒/轴故障中断（锁存）；
 *   16#0004_0201【故障级】非法状态兜底（沿用族码，与 FB_DL_SingleAxis 同码
 *   同义，复用留档）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 06 · DL_Motion 回零/运动族）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbVel.iAxis := fbAxis;                        // 接口依赖注入
 *   fbVel(bCmdStart := bRunSwitch, fVelocity := fSetVel, // 周期调用
 *         fAcc := 2000.0, bDynamicRetarget := TRUE, fVelMax := 1000.0);
 *   电平语义：bRunSwitch 断开即受控减速停车，无需上层编排停止时序；
 *   改速只需改 fVelocity 输入值，块自动差值比较后重发改速指令。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 bCmdStart 电平语义：FALSE 即停车并退出速度模式，不要用脉冲；
 *     需要脉冲语义的工位在上层自锁存。
 *   2 改速容差为固定值（0.001 mm/s），HMI 微调速度时每次变化都会重发；
 *     高频改速场景请在上层做死区滤波，避免指令流量放大。
 *   3 轴限位停车后 bCmdStart 仍为 TRUE 时本块会自动重新发起（电平需求
 *     语义）；不希望自动重启的工位在限位联动层断开 bCmdStart。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VelStep（归属 DL_Motion，与 FB_DL_AxisVelocityMove 同文件）
 * 含义: 速度模式内部步进枚举（本块私有配套，外部仅作诊断参考）。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_VelStep :
(
    eIdle    := 0,    // 空闲：等待启动沿 / Idle: waiting for start edge
    eRunning := 10    // 运行：轮询轴状态并处理动态改速 / Running: polling axis and retargeting
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_AxisVelocityMove
VAR_INPUT
    bCmdStart        : BOOL := FALSE;   // 速度运行指令（Velocity start command），电平生效：TRUE=运行 / FALSE=受控停止
    fVelocity        : REAL := 0.0;     // 目标速度（Target velocity）[mm/s]，带符号，负值=负向；运行中变更即为改速请求
    fAcc             : REAL := 1000.0;  // 加减速度（Acceleration）[mm/s²]，正值，默认 1000.0
    bDynamicRetarget : BOOL := FALSE;   // 动态改速使能（Dynamic retarget），TRUE=连续运动中速度变化自动改速
    fVelMax          : REAL := 1000.0;  // 速度上限（Velocity limit）[mm/s]，|fVelocity| 超限钳位并置信息级
END_VAR
VAR_IN_OUT
    iAxis            : I_DL_MotionAxis; // 轴接口引用（Axis reference），由上层注入实现块实例
END_VAR
VAR_OUTPUT
    bBusy            : BOOL := FALSE;   // 速度模式激活（Velocity mode active）
    bActive          : BOOL := FALSE;   // 轴处于连续运动态（Axis in continuous motion），轮询派生
    uErrorId         : UDINT := 0;      // 末次事件码（Last error code），段位 16#0004_xxxx
END_VAR
VAR
    eStep            : E_DL_VelStep := E_DL_VelStep.eIdle; // 内部步进状态（Internal step state）
    bFaultLatch      : BOOL := FALSE;   // 故障锁存标志（Fault latch），0004_0230 锁存载体
    bParamOk         : BOOL := FALSE;   // 参数门禁通过标志（Parameter gate pass flag），逐拍重算
    fVelEff          : REAL := 0.0;     // 本拍钳位后的目标速度（Clamped target velocity）[mm/s]
    fVelSent         : REAL := 0.0;     // 上次已发轴指令速度（Last issued velocity）[mm/s]，改速差值比较基准
    fVelLim          : REAL := 1000.0;  // 生效速度上限（Effective velocity limit）[mm/s]，非有限值兜底
    fAccEff          : REAL := 1000.0;  // 生效加减速度（Effective acceleration）[mm/s²]，防除零兜底
    rtrigStart       : R_TRIG;          // 启动指令上升沿（Rising edge of start command）
    ftrigStart       : F_TRIG;          // 启动指令下降沿（Falling edge of start command）
END_VAR
VAR CONSTANT
    DL_VEL_INF_MAX   : REAL := 1.0E30;  // 有限值判定幅值上限（Finite-value magnitude bound）[mm/s 或 mm/s²]
    DL_VEL_EPS       : REAL := 1.0E-6;  // 浮点判零容差（Float zero tolerance）
    DL_VEL_TGT_TOL   : REAL := 1.0E-3;  // 改速差值容差（Retarget delta tolerance）[mm/s]，超过才重发改速
    DL_VEL_PAR_FLOOR : REAL := 1.0E-3;  // 加速度参数下限（Acceleration floor）[mm/s²]
END_VAR

// 段 1｜沿检测无条件周期刷新（R7 红线，严禁置于分支内）
rtrigStart(CLK := bCmdStart);
ftrigStart(CLK := bCmdStart);

// 段 2｜接口引用有效性防御：未注入轴引用则清输出退出（不产生误动作）
IF iAxis = 0 THEN
    bBusy := FALSE;
    bActive := FALSE;
    RETURN;
END_IF

// 段 3｜参数门禁逐拍重算（公约 0.8）：非法仅封锁启动（信息级 0004_0106），运行中不中断
bParamOk := (fAcc = fAcc) AND (fAcc <= DL_VEL_INF_MAX) AND (fAcc > DL_VEL_PAR_FLOOR);
IF (fVelMax = fVelMax) AND (fVelMax > DL_VEL_PAR_FLOOR) AND (fVelMax <= DL_VEL_INF_MAX) THEN
    fVelLim := fVelMax;                          // 合法速度上限直通 [mm/s]
ELSE
    fVelLim := 1000.0;                           // 非法上限兜底 [mm/s]
    uErrorId := 16#0004_0106;                    // 信息级：参数兜底修复提示
END_IF
fAccEff := MAX(fAcc, DL_VEL_PAR_FLOOR);          // 生效加速度下限兜底 [mm/s²]，防除零

// 段 4｜事件码管理（R15）：瞬时码逐拍重算，锁存码仅在新启动沿解除
IF NOT bFaultLatch THEN
    uErrorId := 0;
END_IF

// 段 5｜下降沿受控停车（电平语义：FALSE=停止；全局处理，任何态均生效）
IF ftrigStart.Q THEN
    iAxis.Stop();                                // 受控减速停车（MC_Stop 语义）
    bBusy := FALSE;
    IF eStep = E_DL_VelStep.eRunning THEN
        eStep := E_DL_VelStep.eIdle;             // 退出速度模式，等待下次启动沿
    END_IF
END_IF

// 段 6｜运行中轴故障中断（优先于状态机，锁存 R15）
IF (eStep = E_DL_VelStep.eRunning) AND iAxis.bError THEN
    bFaultLatch := TRUE;                         // 故障级锁存，仅新启动沿解除
    uErrorId := 16#0004_0230;
    bBusy := FALSE;
    eStep := E_DL_VelStep.eIdle;
END_IF

// 段 7｜速度模式状态机（ENUM + CASE + ELSE 兜底）
CASE eStep OF

    E_DL_VelStep.eIdle:                          // 空闲态：等待启动沿与门禁
        bBusy := FALSE;
        IF rtrigStart.Q THEN
            bFaultLatch := FALSE;                // 新启动沿：锁存码解除路径（R15）
            IF NOT bParamOk THEN
                uErrorId := 16#0004_0106;        // 参数门禁拒绝（信息级）
            ELSIF (iAxis.eState <> E_DL_AxisState.eStandstill)
              AND (iAxis.eState <> E_DL_AxisState.eContinuousMotion) THEN
                uErrorId := 16#0004_0107;        // 非受理态（停止中/故障态）：请求不被受理（信息级）
            ELSE
                fVelEff := fVelocity;            // 目标速度初值 [mm/s]
                IF fVelEff > fVelLim THEN
                    fVelEff := fVelLim;          // 正向超限钳位 [mm/s]
                    uErrorId := 16#0004_0107;    // 信息级：速度钳位提示
                ELSIF fVelEff < -fVelLim THEN
                    fVelEff := -fVelLim;         // 负向超限钳位 [mm/s]
                    uErrorId := 16#0004_0107;    // 信息级：速度钳位提示
                END_IF
                IF (fVelEff <> fVelEff) OR (ABS(fVelEff) > DL_VEL_INF_MAX) THEN
                    fVelEff := 0.0;              // 非有限速度防御归零（0=原地保持，安全侧）
                    uErrorId := 16#0004_0106;    // 信息级：参数门禁拒绝
                END_IF
                IF iAxis.MoveVelocity(fVelEff, fAccEff) THEN
                    fVelSent := fVelEff;         // 记录已发速度，作为改速差值基准 [mm/s]
                    eStep := E_DL_VelStep.eRunning;
                    bBusy := TRUE;
                ELSE
                    bFaultLatch := TRUE;         // 指令被轴拒绝：故障级锁存
                    uErrorId := 16#0004_0230;
                END_IF
            END_IF
        END_IF

    E_DL_VelStep.eRunning:                       // 运行态：电平需求语义 + 动态改速
        bBusy := TRUE;
        IF bCmdStart THEN
            fVelEff := fVelocity;                // 目标速度初值 [mm/s]
            IF fVelEff > fVelLim THEN
                fVelEff := fVelLim;              // 正向超限钳位 [mm/s]
                uErrorId := 16#0004_0107;        // 信息级：速度钳位提示
            ELSIF fVelEff < -fVelLim THEN
                fVelEff := -fVelLim;             // 负向超限钳位 [mm/s]
                uErrorId := 16#0004_0107;        // 信息级：速度钳位提示
            END_IF
            IF (fVelEff <> fVelEff) OR (ABS(fVelEff) > DL_VEL_INF_MAX) THEN
                fVelEff := 0.0;                  // 非有限速度防御归零（安全侧：请求停车速度）
                uErrorId := 16#0004_0106;        // 信息级：参数门禁拒绝
            END_IF
            IF iAxis.eState = E_DL_AxisState.eStandstill THEN
                // 轴已回待机（如限位自动停车）而需求电平仍为真：按电平需求重新发起
                IF iAxis.MoveVelocity(fVelEff, fAccEff) THEN
                    fVelSent := fVelEff;
                ELSE
                    bFaultLatch := TRUE;         // 重发被拒：故障级锁存
                    uErrorId := 16#0004_0230;
                    bBusy := FALSE;
                    eStep := E_DL_VelStep.eIdle;
                END_IF
            ELSIF bDynamicRetarget AND (ABS(fVelEff - fVelSent) > DL_VEL_TGT_TOL) THEN
                // 动态改速：连续运动中差值超容差 → 重发改速（改速而非重启，接口契约语义）
                IF iAxis.eState = E_DL_AxisState.eContinuousMotion THEN
                    IF iAxis.MoveVelocity(fVelEff, fAccEff) THEN
                        fVelSent := fVelEff;     // 更新已发速度基准 [mm/s]
                    ELSE
                        bFaultLatch := TRUE;     // 改速指令被拒：故障级锁存
                        uErrorId := 16#0004_0230;
                        bBusy := FALSE;
                        eStep := E_DL_VelStep.eIdle;
                    END_IF
                ELSE
                    uErrorId := 16#0004_0107;    // 改速请求在非受理态被拒（信息级，瞬态）
                END_IF
            END_IF
        END_IF

    ELSE
        // 非法状态兜底（故障级，沿用族码 0004_0201，复用留档）
        uErrorId := 16#0004_0201;
        bFaultLatch := TRUE;
        bBusy := FALSE;
        eStep := E_DL_VelStep.eIdle;

END_CASE

// 段 8｜状态出口派生（R21：bActive 为轴状态轮询派生式，逐拍重算）
bActive := (iAxis.eState = E_DL_AxisState.eContinuousMotion);
END_FUNCTION_BLOCK
