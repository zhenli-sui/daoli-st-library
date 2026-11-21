(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ElectronicGear
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 多轴同步耦合族 · 电子齿轮
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library
 *                         （R_TRIG / LIMIT / MIN / MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05，
 *                         零修改引用；本块不新增任何接口方法）
 * 功能描述 (Function)   : 电子齿轮耦合（PLCopen 齿轮耦合语义的 clean-room 独立
 *                         实现）。从轴速度指令 = 主轴实际速度 × 传动比 + 相位
 *                         补偿项。传动比以整数分子/分母保存，仅在输出处换算为
 *                         浮点比值，避免浮点比值累积误差；啮合过渡段按 fAcc 限
 *                         斜率平滑建立，脱开段按 fDec 受控降速到零后再向轴发一次
 *                         停止请求。
 * 设计要点 (Key notes)  :
 *   ① 整数比值对：nRatioNum / nRatioDen 全程整数保存，fRatio 仅为显示量；
 *      分数比 3:7 长期运行不产生浮点漂移（验收向量 V2）。
 *   ② 相位补偿为比例式（fPhaseGain × 累计相位误差，钳到 ±fPhaseMax），
 *      不在轴外层再套积分器；fPhaseGain = 0 时补偿恒为 0（功能关闭）。
 *   ③ 指令下发去抖：仅当新指令与上次下发值之差超过重发阈值才向从轴下发，
 *      避免每拍刷指令洪水（接口配额：对轴接口每拍至多一次方法调用）。
 *   ④ 连续更新门控：eInGear 内改传动比，未开放连续更新时拒绝并出信息级码。
 * 开源溯源 (Origin)     : 原创实现，clean-room。语义来源为 PLCopen
 *                         「Function blocks for motion control」公开规范
 *                         （MC_GearIn / MC_GearInPos 引脚表与状态语义）、
 *                         infoPLC 公开镜像的 Part 2 扩展版说明、Beckhoff
 *                         TF5200 编程手册公开帮助页、Unitronics 多轴指令公开
 *                         帮助页（来源编号 RAW_NOTES S-1）。
 *                         「借鉴对象的许可说明」：上述对象均为公开发布但受版权
 *                         保护的规范文档 / 厂商帮助文档，属「可免费查阅、
 *                         可借鉴接口参数域与状态语义、禁止复制代码」类别；本
 *                         实现未复制任何示例代码、源码行或表结构，引脚命名、
 *                         枚举、状态机跃迁、故障码、相位补偿控制律 100% 自有。
 * 验收向量 (Acceptance) :
 *   V1 正常啮合：比值 1:2、主速 100 → 从速指令趋近 200，过渡段每拍增速不超
 *      fAcc × 采样周期；
 *   V2 分数比 3:7 长期运行：fRatio 恒为 0.428571（整数比值不漂移），相位误差
 *      有界不发散；
 *   V3 分母 0：bExecute 沿受理时判参数非法 → 锁存 0004_0250，指令清零不进耦合；
 *   V4 bContinuousUpdate = FALSE 时改比值：沿用旧比值 + 信息级 0004_0131；
 *   V5 相位补偿开（fPhaseGain = 2）注入 1 mm 相位差：补偿量不超 fPhaseMax，
 *      相位误差单调收敛；
 *   V6 脱开：bDisengage 沿 → 受控降速，指令归零后向轴发一次停止请求 → eIdle；
 *   V7 从轴故障：iSlave.bError 置位 → 锁存 0004_0252 并清指令；
 *   V8 主轴静止：主速绝对值小于判零容差 → 相位积累冻结 + 信息级 0004_0130，
 *      不置故障；
 *   V9 运行中途插入跟踪脉冲 bTrack：重采样主从参考位置、相位误差清零、
 *      耦合状态退回 eIdle（公约 0.1 必测向量）。
 * 已知限制 (Limits)     :
 *   ① 主轴与从轴若被注入同一实例，本块无法在块内识别（接口引用不可比较
 *      身份），轴自身仲裁；调用方必须保证主从不指向同一实例。
 *   ② 本库接口无「指令速度」属性，耦合一律取主轴实际速度（等效于按实际值
 *      耦合）；指令值耦合留待接口升版，避免破坏既有 6 个实现块。
 *   ③ 本块为逻辑层同步编排，不构成 ISO 13849 / IEC 62061 认证安全功能；
 *      安全回路、硬限位与机械保护由认证安全控制器与硬件承载。
 *   ④ 同步精度受扫描周期限制，属逻辑层耦合而非硬实时插补。
 * 规格偏离 (Deviation)  :
 *   ① 依公约 0.1（首扫范式）增补 bTrack 输入引脚；依公约 0.10（定时基准由
 *      引脚给）增补 tCycle 输入引脚。二者均为公共约定强制项，非逐组件条款
 *      可覆盖。影响：调用方须接扫描周期常量与跟踪脉冲，其余引脚语义不变。
 *   ② 出口默认赋值置于参数防御之前（依公约 0.9「早退路径输出确定」），与
 *      规格 1.1 节「防御 → 默认」的叙述顺序有调整，语义等价。
 *   ③ bEnable 撤除时除清零输出外，另向从轴补发一次停止请求（安全保守处置：
 *      仅清指令会让从轴保留末次速度指令，现场不可接受）。
 *   ④ 啮合完成判据取「指令与目标之差进入啮合判定带」这一明确口径（带值 0.01 mm/s），
 *      规格原文写「差小于速度上限或绝对值超差小于判零容差十倍」，两种表述在
 *      限速非零时不等价；本实现取固定小带，语义更严（只在真正跟上时才判啮合）。
 * 红线自检 (Redline)    :
 *   R1 零全局符号区访问 ✓（无全局变量表访问、无外部变量声明）
 *   R2 零物理地址直写 ✓（无输入输出通道地址记号）
 *   R3 纯 IEC 61131-3 ✓（仅标准库 R_TRIG / LIMIT / MIN / MAX / ABS / 类型转换）
 *   R4 防除零 / 防越界 / 浮点容差 ✓（比值换算前判分母、浮点比较全用 ABS 容差）
 *   R5 声明行 100% 中英双语同行注释 ✓
 *   R6 ENUM + CASE 且 CASE 含 ELSE 兜底 ✓
 *   R7 边沿实例无条件周期刷新 ✓（R25 单拍闭环：本块无单拍脉冲输出）
 *   POU 终结符成对 ✓（FUNCTION_BLOCK ↔ END_FUNCTION_BLOCK，末行即终结符；
 *   TYPE ↔ END_TYPE 成对）
 * 故障码表 (Error codes):
 *   16#0004_0130【信息级】主轴静止、相位跟踪冻结，不置故障位；
 *   16#0004_0131【信息级】未开放连续更新时改传动比被拒，沿用旧比值；
 *   16#0004_0132【信息级】从轴速度指令被绝对限速钳位；
 *   16#0004_0250【故障级】传动比参数非法（分母为 0 / 分子非正），锁存；
 *   16#0004_0251【故障级】从轴速度指令被轴拒绝，锁存；
 *   16#0004_0252【故障级】从轴故障中断耦合（透传），锁存；
 *   16#0004_0299【故障级】非法状态兜底（本块专用，不与其他块共用）。
 *   信息级码只进 uErrorId，不参与 bError 派生；bError 仅反映 eFault 态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Motion 同步耦合族开族件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbGear.iMaster := fbMasterAxis;              // 主轴实现块实例注入
 *   fbGear.iSlave  := fbSlaveAxis;               // 从轴实现块实例注入
 *   fbGear(bEnable := TRUE, bExecute := bCoupleCmd,   // 周期调用，永远每拍调用
 *          nRatioNum := 1, nRatioDen := 2,
 *          fAcc := 800.0, fDec := 800.0,
 *          fVelLimit := 600.0, fPhaseGain := 1.5,
 *          tCycle := T#10MS);
 *   IF fbGear.bInGear THEN bReady := TRUE; END_IF
 *   注：从轴速度指令经 fSlaveSpeedCmd 出口逐拍刷新，实际下发由本块内部完成
 *       （每拍至多一次速度指令），上层不要再对同一从轴另发运动指令。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 本块是「速度耦合」而非「位置同步」：位置偏差靠相位补偿项收敛，若现场
 *     需要硬位置对齐（GearInPos 语义），请改用电子凸轮块承载。
 *   2 比值引脚为整数：若工艺给的是小数比值（如 0.28），请放大为整数对
 *     （28 : 100），不要直接填浮点近似值，否则长期运行会漂。
 *   3 主轴静止时相位冻结属正常工况（信息级 0130），不要当作故障处理；
 *     主轴重新启动后相位继续累计。
 *   4 从轴被外部强制停止（驱动器使能丢失）时会锁存 0252；必须等从轴恢复且
 *     给 bReset 上升沿后才能重新啮合。
 *   5 bTrack 用于调试与换型：给一个上升沿即重采样参考位置并退回 eIdle，
 *     不会向从轴发停止请求，轴保持当前运动状态（由调用方决定是否先停轴）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GearState（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 电子齿轮耦合状态机，编号间隔 10 预留扩展位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_GearState :
(
    eIdle          := 0,    // 空闲：从轴不受本块控制，速度指令清零 / Idle: slave not controlled, speed command cleared
    eSynchronizing := 10,   // 啮合过渡：从轴速度指令向目标比值速度按加速度斜坡逼近 / Synchronizing: slave speed ramps toward ratio target
    eInGear        := 20,   // 已啮合：主从速度比稳定保持，bInGear 唯一来源 / In gear: ratio held steady, sole source of bInGear
    eDisengaging   := 30,   // 脱开：按脱开减速度受控降速至零 / Disengaging: controlled deceleration to zero
    eFault         := 99    // 故障锁存：仅 bReset 上升沿可退出 / Fault: latched, only bReset rising edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ElectronicGear
VAR_INPUT
    bEnable           : BOOL := FALSE;          // 耦合总使能（Coupling enable），FALSE=脱开并清零输出，电平语义
    bExecute          : BOOL := FALSE;          // 建立耦合指令（Engage command），上升沿受理，eInGear 期间忽略新沿
    bDisengage        : BOOL := FALSE;          // 脱开指令（Disengage command），上升沿受理，优先于 bExecute
    bTrack            : BOOL := FALSE;          // 参考位置重同步（Tracking pulse），上升沿/电平即重采样主从位置并清相位误差
    nRatioNum         : DINT := 1;              // 传动比分子（Gear ratio numerator）[-]，域 1..1000000，≤0 判参数非法
    nRatioDen         : DINT := 1;              // 传动比分母（Gear ratio denominator）[-]，域 1..1000000，=0 防除零故障
    bContinuousUpdate : BOOL := FALSE;          // 运行中改比值使能（Continuous update），FALSE 时啮合内改比值被拒并出信息码
    fAcc              : REAL := 500.0;          // 啮合过渡加速度（Engage acceleration）[mm/s²]，域 0.1..100000，非有限值→默认
    fDec              : REAL := 500.0;          // 脱开减速度（Disengage deceleration）[mm/s²]，域 0.1..100000，非有限值→默认
    fVelLimit         : REAL := 0.0;            // 从轴速度绝对上限（Slave speed limit）[mm/s]，0=不限，负值取绝对值
    fPhaseGain        : REAL := 0.0;            // 相位修正增益（Phase correction gain）[1/s]，0=关闭相位补偿
    fPhaseMax         : REAL := 5.0;            // 相位修正量上限（Phase correction limit）[mm/s]，仅补偿开启时有效
    tCycle            : TIME := T#10MS;         // 任务扫描周期（Task cycle time）[ms]，由调用方按实际任务给，用于加速度限斜率
    bReset            : BOOL := FALSE;          // 复位故障（Fault reset），上升沿受理，仅 eFault 态有效
END_VAR
VAR_OUTPUT
    bInGear           : BOOL := FALSE;          // 已啮合标志（In gear），仅 eInGear 态为 TRUE
    bBusy             : BOOL := FALSE;          // 执行中（Busy），eSynchronizing / eInGear / eDisengaging 为 TRUE
    bActive           : BOOL := FALSE;          // 本块持有从轴控制权（Active），eSynchronizing / eInGear 为 TRUE
    bError            : BOOL := FALSE;          // 故障锁存（Error），派生式仅故障级码参与，信息级码不置位
    uErrorId          : UDINT := 0;             // 故障码（Error code），段位 16#0004_xxxx，0=无故障
    fRatio            : REAL := 0.0;            // 实际生效传动比（Effective ratio）[-]，= 生效分子 / 生效分母
    fSlaveSpeedCmd    : REAL := 0.0;            // 下发给从轴的速度指令（Slave speed command）[mm/s]，带符号，负值=负向
    fPhaseError       : REAL := 0.0;            // 相位累计误差（Accumulated phase error）[mm]，= 累计(主位增量×比值 − 从位增量)
END_VAR
VAR_IN_OUT
    iMaster           : I_DL_MotionAxis;        // 主轴接口引用（Master axis），由调用方注入实现块实例
    iSlave            : I_DL_MotionAxis;        // 从轴接口引用（Slave axis），由调用方注入实现块实例
END_VAR
VAR
    eState            : E_DL_GearState := E_DL_GearState.eIdle; // 内部状态机步序（Internal state）
    bInit             : BOOL := FALSE;          // 首扫完成标志（First-scan done flag），初值 FALSE，随 bTrack 复位重采样
    bFaultLatch       : BOOL := FALSE;          // 故障锁存标志（Fault latch），仅 bReset 沿或新啮合沿解除
    bRatioOk          : BOOL := FALSE;          // 传动比参数合法标志（Ratio parameter valid），逐拍重算
    bStopIssued       : BOOL := FALSE;          // 脱开停止请求已发标志（Stop issued flag），单发化防重复发令
    nNumEff           : DINT := 1;              // 生效传动比分子（Effective numerator）[-]，啮合时锁定
    nDenEff           : DINT := 1;              // 生效传动比分母（Effective denominator）[-]，啮合时锁定且已验非零
    fRatioEff         : REAL := 1.0;            // 生效传动比数值（Effective ratio value）[-]，仅由整数对比值换算
    fAccEff           : REAL := 500.0;          // 生效啮合加速度（Effective acceleration）[mm/s²]，已做默认回退与限幅
    fDecEff           : REAL := 500.0;          // 生效脱开减速度（Effective deceleration）[mm/s²]，已做默认回退与限幅
    fVelLimitEff      : REAL := 0.0;            // 生效速度上限（Effective speed limit）[mm/s]，0=不限
    fPhaseMaxEff      : REAL := 5.0;            // 生效相位补偿上限（Effective phase limit）[mm/s]，≥0
    fDtS              : REAL := 0.01;           // 采样周期秒值（Cycle time in seconds）[s]，由 tCycle 换算并限幅
    fCmdRamp          : REAL := 0.0;            // 斜坡中的速度指令（Ramped speed command）[mm/s]，带符号
    fLastSentCmd      : REAL := 0.0;            // 上次实际下发速度（Last issued speed）[mm/s]，用于重发去抖
    fTargetCmd        : REAL := 0.0;            // 本拍目标速度（Target speed this scan）[mm/s]，含相位补偿与限幅
    fCompTerm         : REAL := 0.0;            // 相位补偿项（Phase compensation term）[mm/s]，已钳到 ±fPhaseMax
    fStepMax          : REAL := 0.0;            // 单拍速度增量上限（Max speed step per scan）[mm/s]，= 加速度 × 采样周期
    fMasterVel        : REAL := 0.0;            // 主轴实际速度（Master actual velocity）[mm/s]，带符号
    fSlaveVel         : REAL := 0.0;            // 从轴实际速度（Slave actual velocity）[mm/s]，带符号
    fMasterPosNow     : REAL := 0.0;            // 主轴本拍位置（Master position this scan）[mm]
    fSlavePosNow      : REAL := 0.0;            // 从轴本拍位置（Slave position this scan）[mm]
    fLastMasterPos    : REAL := 0.0;            // 上拍主轴位置（Previous master position）[mm]，相位增量基准
    fLastSlavePos     : REAL := 0.0;            // 上拍从轴位置（Previous slave position）[mm]，相位增量基准
    fPhaseErrInt      : REAL := 0.0;            // 相位误差累计器（Phase error accumulator）[mm]，内部量
    fNewRatio         : REAL := 1.0;            // 新比值候选值（Candidate ratio value）[-]，除法前已验分母
    fbTrigExec        : R_TRIG;                 // 建立耦合指令上升沿（Engage command rising edge）
    fbTrigDisengage   : R_TRIG;                 // 脱开指令上升沿（Disengage command rising edge）
    fbTrigReset       : R_TRIG;                 // 复位指令上升沿（Reset command rising edge）
END_VAR
VAR CONSTANT
    DL_GEAR_INF_MAX    : REAL := 1.0E30;        // 有限值判定幅值上限（Finite magnitude bound）[无量纲，按各量量纲同值使用]
    DL_GEAR_EPS        : REAL := 1.0E-6;        // 浮点判零容差（Float zero tolerance）[无量纲，按比较量量纲同值使用]
    DL_GEAR_PAR_FLOOR  : REAL := 1.0E-3;        // 加速度/减速度参数下限（Acceleration floor）[mm/s²]，低于此值回默认
    DL_GEAR_ACC_DEF    : REAL := 500.0;         // 加速度默认回退值（Default acceleration）[mm/s²]
    DL_GEAR_DEC_DEF    : REAL := 500.0;         // 减速度默认回退值（Default deceleration）[mm/s²]
    DL_GEAR_ACC_MAX    : REAL := 100000.0;      // 加速度上限（Acceleration upper bound）[mm/s²]，超限钳位
    DL_GEAR_LOCK_BAND  : REAL := 0.01;          // 啮合判定带（In-gear band）[mm/s]，指令与目标差小于此值判啮合
    DL_GEAR_RESEND_EPS : REAL := 0.5;           // 速度指令重发阈值（Resend threshold）[mm/s]，差小于此值不重复下发
    DL_GEAR_DT_MIN     : REAL := 1.0E-4;        // 采样周期下限（Cycle time lower bound）[s]，低于此值按默认
    DL_GEAR_DT_MAX     : REAL := 1.0;           // 采样周期上限（Cycle time upper bound）[s]，高于此值钳位
    DL_GEAR_DT_DEF     : REAL := 0.01;          // 采样周期默认值（Default cycle time）[s]
    DL_GEAR_RATIO_MAX  : DINT := 1000000;       // 传动比分子分母上限（Ratio term upper bound）[-]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTrigExec(CLK := bExecute);
fbTrigDisengage(CLK := bDisengage);
fbTrigReset(CLK := bReset);

// 段 2｜出口默认赋值（公约 0.9：早退路径输出必须确定）
bInGear        := FALSE;
bBusy          := FALSE;
bActive        := FALSE;
bError         := (eState = E_DL_GearState.eFault);
fSlaveSpeedCmd := 0.0;
fRatio         := fRatioEff;

// 段 3｜接口引用有效性防御：任一引用未注入则清输出退出，不产生误动作
IF (iMaster = 0) OR (iSlave = 0) THEN
    RETURN;
END_IF

// 段 4｜采样周期换算与限幅（公约 0.10：定时基准由引脚给，禁读系统时钟）
fDtS := TIME_TO_REAL(tCycle) * 1.0E-3;                       // 毫秒 → 秒（注释：本行换算单位为 s）
IF (fDtS <> fDtS) OR (fDtS <= DL_GEAR_DT_MIN) THEN
    fDtS := DL_GEAR_DT_DEF;                                  // 周期非法回默认 10 ms，防除零与超大单拍步长
ELSIF fDtS > DL_GEAR_DT_MAX THEN
    fDtS := DL_GEAR_DT_MAX;                                  // 周期过大钳位，避免单拍跨越过大
END_IF

// 段 5｜参数防御：非有限值回默认、加速度/减速度非正回默认、限速负值取绝对值
IF (fAcc <> fAcc) OR (ABS(fAcc) > DL_GEAR_INF_MAX) OR (fAcc <= DL_GEAR_PAR_FLOOR) THEN
    fAccEff := DL_GEAR_ACC_DEF;                              // 加速度非法 → 默认值
ELSE
    fAccEff := MIN(fAcc, DL_GEAR_ACC_MAX);                   // 加速度合法 → 上限钳位
END_IF

IF (fDec <> fDec) OR (ABS(fDec) > DL_GEAR_INF_MAX) OR (fDec <= DL_GEAR_PAR_FLOOR) THEN
    fDecEff := DL_GEAR_DEC_DEF;                              // 减速度非法 → 默认值
ELSE
    fDecEff := MIN(fDec, DL_GEAR_ACC_MAX);                   // 减速度合法 → 上限钳位
END_IF

IF (fVelLimit <> fVelLimit) OR (ABS(fVelLimit) > DL_GEAR_INF_MAX) THEN
    fVelLimitEff := 0.0;                                     // 限速非有限值 → 视为不限
ELSE
    fVelLimitEff := ABS(fVelLimit);                          // 限速取绝对值，0=不限
END_IF

IF (fPhaseMax <> fPhaseMax) OR (ABS(fPhaseMax) > DL_GEAR_INF_MAX) THEN
    fPhaseMaxEff := 0.0;                                     // 补偿上限非法 → 关闭补偿
ELSE
    fPhaseMaxEff := ABS(fPhaseMax);                          // 补偿上限取绝对值，0=关闭补偿
END_IF

// 传动比参数合法性：分子必须为正、分母必须为正（分母为 0 防除零，负值无工程意义）
bRatioOk := (nRatioNum > 0) AND (nRatioDen > 0)
            AND (nRatioNum <= DL_GEAR_RATIO_MAX) AND (nRatioDen <= DL_GEAR_RATIO_MAX);

// 段 6｜首扫与跟踪范式（公约 0.1：bTrack OR (NOT bInit) 为唯一判据，禁止反序）
fMasterPosNow := iMaster.fPosition;
fSlavePosNow  := iSlave.fPosition;
fMasterVel    := iMaster.fVelocity;
fSlaveVel     := iSlave.fVelocity;

IF bTrack OR (NOT bInit) THEN
    fLastMasterPos := fMasterPosNow;                         // 主轴参考位置重采样 [mm]
    fLastSlavePos  := fSlavePosNow;                          // 从轴参考位置重采样 [mm]
    fPhaseErrInt   := 0.0;                                   // 相位误差清零 [mm]
    fCmdRamp       := fSlaveVel;                             // 斜坡起点取从轴当前速度，避免指令跳变 [mm/s]
    fLastSentCmd   := fSlaveVel;                             // 下发基准同步，避免首拍误判重发 [mm/s]
    bStopIssued    := FALSE;                                 // 停止单发标志复位
    eState         := E_DL_GearState.eIdle;                  // 跟踪后退回空闲，等待新的啮合沿
    bInit          := TRUE;                                  // 首扫完成后置位（判据恒为 bTrack OR NOT bInit）
END_IF

// 段 7｜总使能撤除：清零输出并向从轴补发一次停止请求（安全保守处置）
IF NOT bEnable THEN
    IF (NOT bStopIssued) AND ((eState = E_DL_GearState.eSynchronizing) OR (eState = E_DL_GearState.eInGear)) THEN
        iSlave.Stop();                                       // 使能撤除瞬间单发一次停止，杜绝残余速度指令
        bStopIssued := TRUE;
    END_IF
    eState       := E_DL_GearState.eIdle;
    fCmdRamp     := 0.0;
    fLastSentCmd := 0.0;
    fPhaseErrInt := 0.0;
    fSlaveSpeedCmd := 0.0;
END_IF

// 段 8｜事件码管理（公约 0.7 / R15）：锁存码仅在解除路径清，瞬时码逐拍重算
IF NOT bFaultLatch THEN
    uErrorId := 0;                                           // 非锁存态每拍重算瞬时码
END_IF

// 段 9｜主状态机（ENUM + CASE + ELSE 兜底）
CASE eState OF

    E_DL_GearState.eIdle:                                    // 空闲：等待啮合沿与参数门禁
        bInGear := FALSE;
        bBusy   := FALSE;
        bActive := FALSE;
        IF fbTrigExec.Q AND bEnable THEN
            bFaultLatch := FALSE;                            // 新啮合沿：锁存码解除路径（R15）
            IF NOT bRatioOk THEN
                bFaultLatch    := TRUE;                      // 传动比非法：故障级锁存
                uErrorId       := 16#0004_0250;              // 【故障级】传动比参数非法
                eState         := E_DL_GearState.eFault;
            ELSE
                nNumEff     := nRatioNum;                    // 锁定分子，运行中不受引脚抖动影响
                nDenEff     := nRatioDen;                    // 锁定分母（已验非零）
                fRatioEff   := DINT_TO_REAL(nNumEff) / DINT_TO_REAL(nDenEff); // 整数对比值换算，唯一除法点且分母已验非零
                fRatio      := fRatioEff;
                fCmdRamp    := fSlaveVel;                    // 过渡斜坡起点 = 从轴当前速度
                fLastSentCmd:= fSlaveVel;
                fPhaseErrInt:= 0.0;                          // 新啮合：相位误差从零起算
                bStopIssued := FALSE;
                eState      := E_DL_GearState.eSynchronizing;
            END_IF
        END_IF

    E_DL_GearState.eSynchronizing:                           // 啮合过渡：按加速度限斜率逼近目标比值速度
        bBusy   := TRUE;
        bActive := TRUE;
        IF fbTrigDisengage.Q THEN
            eState := E_DL_GearState.eDisengaging;           // 脱开沿优先于一切运行逻辑
        ELSIF iSlave.bError THEN
            bFaultLatch := TRUE;                             // 从轴故障透传：故障级锁存
            uErrorId    := 16#0004_0252;                     // 【故障级】从轴故障中断耦合
            fCmdRamp    := 0.0;
            fSlaveSpeedCmd := 0.0;
            eState      := E_DL_GearState.eFault;
        ELSE
            // 相位累计：主轴位移增量 × 比值 − 从轴位移增量（主静止时冻结）
            IF ABS(fMasterVel) > DL_GEAR_EPS THEN
                fPhaseErrInt := fPhaseErrInt + (fMasterPosNow - fLastMasterPos) * fRatioEff
                                - (fSlavePosNow - fLastSlavePos);
            ELSE
                uErrorId := 16#0004_0130;                    // 【信息级】主轴静止、相位跟踪冻结（正常工况）
            END_IF
            // 目标速度 = 主速 × 比值 + 相位补偿项
            fCompTerm := 0.0;
            IF (ABS(fPhaseGain) > DL_GEAR_EPS) AND (fPhaseMaxEff > DL_GEAR_EPS) THEN
                fCompTerm := LIMIT(-fPhaseMaxEff, fPhaseGain * fPhaseErrInt, fPhaseMaxEff); // 补偿量钳到 ±上限
            END_IF
            fTargetCmd := fMasterVel * fRatioEff + fCompTerm;
            // 绝对限速钳位（提示配方比值与限速矛盾，逐拍重算不置故障）
            IF (fVelLimitEff > DL_GEAR_EPS) AND (ABS(fTargetCmd) > fVelLimitEff) THEN
                fTargetCmd := LIMIT(-fVelLimitEff, fTargetCmd, fVelLimitEff);
                uErrorId   := 16#0004_0132;                  // 【信息级】从轴速度指令被限速钳位
            END_IF
            // 加速度限斜率：单拍增量不超 加速度 × 采样周期
            fStepMax  := fAccEff * fDtS;
            fCmdRamp  := fCmdRamp + LIMIT(-fStepMax, fTargetCmd - fCmdRamp, fStepMax);
            fSlaveSpeedCmd := fCmdRamp;
            // 每拍至多一次速度指令下发，且仅在变化超过重发阈值时下发
            IF ABS(fCmdRamp - fLastSentCmd) > DL_GEAR_RESEND_EPS THEN
                IF NOT iSlave.MoveVelocity(fVel := fCmdRamp, fAcc := fAccEff) THEN
                    bFaultLatch := TRUE;                     // 指令被轴拒绝：故障级锁存
                    uErrorId    := 16#0004_0251;             // 【故障级】从轴速度指令被拒
                    fCmdRamp    := 0.0;
                    fSlaveSpeedCmd := 0.0;
                    eState      := E_DL_GearState.eFault;
                ELSE
                    fLastSentCmd := fCmdRamp;
                END_IF
            END_IF
            // 指令进入啮合判定带 → 已啮合
            IF (eState = E_DL_GearState.eSynchronizing) AND (ABS(fCmdRamp - fTargetCmd) <= DL_GEAR_LOCK_BAND) THEN
                eState := E_DL_GearState.eInGear;
            END_IF
        END_IF

    E_DL_GearState.eInGear:                                  // 已啮合：比值稳定保持 + 连续更新门控
        bBusy    := TRUE;
        bActive  := TRUE;
        bInGear  := TRUE;
        IF fbTrigDisengage.Q THEN
            eState := E_DL_GearState.eDisengaging;           // 脱开沿优先
        ELSIF iSlave.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0252;                     // 【故障级】从轴故障中断耦合
            fCmdRamp    := 0.0;
            fSlaveSpeedCmd := 0.0;
            eState      := E_DL_GearState.eFault;
        ELSE
            // 传动比变更门控：未开放连续更新时拒绝，沿用旧比值并出信息码
            IF (nRatioNum <> nNumEff) OR (nRatioDen <> nDenEff) THEN
                IF bContinuousUpdate THEN
                    IF bRatioOk THEN
                        nNumEff   := nRatioNum;
                        nDenEff   := nRatioDen;
                        fRatioEff := DINT_TO_REAL(nNumEff) / DINT_TO_REAL(nDenEff); // 分母已验非零，防除零
                    ELSE
                        bFaultLatch := TRUE;
                        uErrorId    := 16#0004_0250;         // 【故障级】连续更新传入非法比值
                        eState      := E_DL_GearState.eFault;
                    END_IF
                ELSE
                    uErrorId := 16#0004_0131;                // 【信息级】未开放连续更新时改比值被拒
                END_IF
            END_IF
            // 相位累计（同上，主静止冻结）
            IF ABS(fMasterVel) > DL_GEAR_EPS THEN
                fPhaseErrInt := fPhaseErrInt + (fMasterPosNow - fLastMasterPos) * fRatioEff
                                - (fSlavePosNow - fLastSlavePos);
            ELSE
                uErrorId := 16#0004_0130;                    // 【信息级】主轴静止、相位跟踪冻结
            END_IF
            fCompTerm := 0.0;
            IF (ABS(fPhaseGain) > DL_GEAR_EPS) AND (fPhaseMaxEff > DL_GEAR_EPS) THEN
                fCompTerm := LIMIT(-fPhaseMaxEff, fPhaseGain * fPhaseErrInt, fPhaseMaxEff);
            END_IF
            fTargetCmd := fMasterVel * fRatioEff + fCompTerm;
            IF (fVelLimitEff > DL_GEAR_EPS) AND (ABS(fTargetCmd) > fVelLimitEff) THEN
                fTargetCmd := LIMIT(-fVelLimitEff, fTargetCmd, fVelLimitEff);
                uErrorId   := 16#0004_0132;                  // 【信息级】限速钳位
            END_IF
            // 已啮合段仍以加速度限斜率跟随，防止比值阶跃造成冲击
            fStepMax := fAccEff * fDtS;
            fCmdRamp := fCmdRamp + LIMIT(-fStepMax, fTargetCmd - fCmdRamp, fStepMax);
            fSlaveSpeedCmd := fCmdRamp;
            IF ABS(fCmdRamp - fLastSentCmd) > DL_GEAR_RESEND_EPS THEN
                IF NOT iSlave.MoveVelocity(fVel := fCmdRamp, fAcc := fAccEff) THEN
                    bFaultLatch := TRUE;
                    uErrorId    := 16#0004_0251;             // 【故障级】从轴速度指令被拒
                    fCmdRamp    := 0.0;
                    fSlaveSpeedCmd := 0.0;
                    eState      := E_DL_GearState.eFault;
                ELSE
                    fLastSentCmd := fCmdRamp;
                END_IF
            END_IF
        END_IF

    E_DL_GearState.eDisengaging:                             // 脱开：按减速度受控降速至零后单发停止
        bBusy   := TRUE;
        bActive := FALSE;
        IF iSlave.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0252;                     // 【故障级】从轴故障中断耦合
            fCmdRamp    := 0.0;
            fSlaveSpeedCmd := 0.0;
            eState      := E_DL_GearState.eFault;
        ELSE
            fStepMax := fDecEff * fDtS;
            fCmdRamp := fCmdRamp - LIMIT(-fStepMax, fCmdRamp, fStepMax); // 朝零收敛，单拍降幅不超 减速度×周期
            IF ABS(fCmdRamp) <= DL_GEAR_EPS THEN
                fCmdRamp       := 0.0;
                fSlaveSpeedCmd := 0.0;
                iSlave.Stop();                               // 指令归零后发一次停止（本拍唯一一次轴调用，随即退态不复发）
                bBusy       := FALSE;
                eState      := E_DL_GearState.eIdle;
            ELSE
                fSlaveSpeedCmd := fCmdRamp;
                IF ABS(fCmdRamp - fLastSentCmd) > DL_GEAR_RESEND_EPS THEN
                    IF NOT iSlave.MoveVelocity(fVel := fCmdRamp, fAcc := fDecEff) THEN
                        bFaultLatch := TRUE;
                        uErrorId    := 16#0004_0251;         // 【故障级】脱开减速指令被拒
                        fCmdRamp    := 0.0;
                        fSlaveSpeedCmd := 0.0;
                        eState      := E_DL_GearState.eFault;
                    ELSE
                        fLastSentCmd := fCmdRamp;
                    END_IF
                END_IF
            END_IF
        END_IF

    E_DL_GearState.eFault:                                   // 故障锁存：仅复位沿可退出
        bInGear        := FALSE;
        bBusy          := FALSE;
        bActive        := FALSE;
        fCmdRamp       := 0.0;
        fSlaveSpeedCmd := 0.0;
        bStopIssued    := FALSE;
        IF fbTrigReset.Q THEN
            bFaultLatch := FALSE;                            // 唯一解除路径
            uErrorId    := 0;
            eState      := E_DL_GearState.eIdle;
        END_IF

    ELSE                                                     // 非法状态兜底（本块专用码）
        bFaultLatch := TRUE;
        uErrorId    := 16#0004_0299;                         // 【故障级】非法状态兜底
        bInGear     := FALSE;
        bBusy       := FALSE;
        bActive     := FALSE;
        fCmdRamp    := 0.0;
        fSlaveSpeedCmd := 0.0;
        eState      := E_DL_GearState.eFault;

END_CASE

// 段 10｜相位基准推进：无论是否耦合都推进一拍，保证增量口径唯一、重新啮合不产生伪增量
fLastMasterPos := fMasterPosNow;                         // 主轴位置基准推进 [mm]
fLastSlavePos  := fSlavePosNow;                          // 从轴位置基准推进 [mm]

// 段 11｜出口映射（派生式，信息级码不参与 bError）
bError       := (eState = E_DL_GearState.eFault);
bInGear      := (eState = E_DL_GearState.eInGear);
bBusy        := (eState = E_DL_GearState.eSynchronizing) OR (eState = E_DL_GearState.eInGear)
                OR (eState = E_DL_GearState.eDisengaging);
bActive      := (eState = E_DL_GearState.eSynchronizing) OR (eState = E_DL_GearState.eInGear);
fRatio       := fRatioEff;
fPhaseError  := fPhaseErrInt;

END_FUNCTION_BLOCK
