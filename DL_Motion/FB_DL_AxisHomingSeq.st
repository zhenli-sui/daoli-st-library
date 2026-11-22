(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisHomingSeq
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 轴回零序列状态机 · 工艺上层件
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（TON / R_TRIG /
 *                         F_TRIG / MIN / MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05）
 * 功能描述 (Function)   : 标准工业回零序列状态机。经轴接口引用驱动轴体，全部
 *                         序列动作由 MoveVelocity / Stop 组合出，本块绝不出任何
 *                         自有速度输出。四模式：限位开关回零 / 原点开关回零 /
 *                         Z 相脉冲精定位 / 扭矩堵转回零。慢速逼近-回退-再逼近-
 *                         标定时序。被动回零（外力移动轴监听参考事件）本轮不
 *                         实现，留矩阵扩产。
 * 设计要点 (Key notes)  : ① 双护栏：总超时（TON 自实现周期累积）+ 行程超限
 *                           （起点-当前位置绝对差 > fMaxTravel）；
 *                         ② 启动门禁：轴不在待机态 / 参数非法 / 可观测矛盾
 *                           （原点开关或所选限位启动时已压住）→ 拒绝并置
 *                           信息级 0004_0106；信号缺失类不可观测项（Z 相通道
 *                           无效、堵转阈值未组态）由调用方保证（头注释声明）；
 *                         ③ 标定职责边界：eCalibrate 仅完成受控停车与序列收口，
 *                           坐标系写入与轴回原标志置位由调用方联动 bDone 完成，
 *                           本块不直接写轴内部态（接口无位置写入域）；
 *                         ④ bTrack 中途插入 → 序列中止受控停车回空闲（R19）；
 *                         ⑤ R14：超时定时器 PT 变更显式断输入一拍使已计时归零。
 * 规格偏离留档 (R11)    : 规格引脚表未列回零方向，但四模式时序均需逼近方向
 *                         语义，补充 bDirNeg : BOOL 输入（TRUE=朝负方向回零）；
 *                         fMaxTravel 为规格正文明确的新增引脚（默认 1.0E6）。
 * 开源溯源 (Origin)     : 原创实现（参考 PLCopen Part 1-6 回零方式分类与西门子
 *                         Motion Control 对象语义，clean-room）。仅提取公开的
 *                         回零方式分类（限位/原点开关/Z 相/扭矩堵转）与
 *                         逼近-回退-再逼近-标定公开语义；实现与命名 100% 自有，
 *                         未参考任何厂商源码行。
 * 验收向量 (Acceptance) :
 *   V1 限位开关回零全链：逼近→限位上升沿→反向回退→限位下降沿→爬行再逼近→
 *      限位上升沿→标定→完成；V2 原点开关回零全链（逼近-回退-再逼近逐拍）；
 *   V3 Z 相精定位：爬行单向→Z 相上升沿→标定→完成；V4 堵转回零：爬行→
 *      堵转信号→标定→完成；V5 总超时 → 故障码 0004_0210；V6 行程超限 →
 *      0004_0211；V7 启动门禁（轴非待机/原点开关已压住）→ 信息级 0004_0106
 *      拒绝；V8 运行中途 bTrack → 受控停车回空闲（R19 必测）。
 * 故障码表 (Error codes):
 *   16#0004_0106【信息级】启动门禁/参数门禁拒绝（与 FB_DL_AxisRelativeMove
 *   同码同义，共用留档）；16#0004_0210【故障级】回零总超时；
 *   16#0004_0211【故障级】行程超限；16#0004_0212【故障级】中止/轴故障；
 *   16#0004_0213【故障级】序列指令被拒或非法状态兜底。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 06 · DL_Motion 回零/运动族）
 *   2026-11-15  v1.0.1  终审修复【严重】终态死锁：原实现 eDone/eAborted/
 *                       eFault 三态在 CASE 内无任何迁出路径，启动上升沿被
 *                       吞——首次回零完成后（或中止/故障后）永远无法再次
 *                       回零，仅 bTrack 可逃逸（R6 状态机跃迁完整性检查项
 *                       复现）。修法：新增段 5.5 终态重启借道逻辑——三终
 *                       态收到启动沿即回 eIdle，使同拍 eIdle 门禁分支受理
 *                       该沿（不吞沿、不要求双击）。引脚契约零变更。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbHome.iAxis := fbAxis;                       // 接口依赖注入
 *   fbHome(eMode := E_DL_HomingMode.eHomeSwitch,  // 周期调用
 *          bCmdStart := bStartHome, bDirNeg := TRUE,
 *          fHomingVel := 50.0, fCreepVel := 2.0, fAcc := 1000.0,
 *          fHomePosition := 0.0, tHomingTimeout := T#60S,
 *          bLimPos := swLimP, bLimNeg := swLimN, bHomeSw := swHome);
 *   IF fbHome.bDone THEN … 上层联动：写入轴坐标系 fHomePosition 并置轴回原标志（示例省略）
 *   注意：本块只驱动序列，坐标系建立由调用方在 bDone 后执行。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 启动时原点开关/所选限位已压住属可观测矛盾，本块拒绝启动（信息级
 *     0004_0106）；Z 相通道无效、堵转阈值未组态等不可观测项由调用方保证。
 *   2 eDone 态 bDone 保持 TRUE，回零完成后轴接口回原标志由上层联动；本块
 *     不重复标定，直到下一次 bCmdStart 上升沿。
 *   3 fHomePosition 在本块内不参与运算，作为标定值暂存引脚供上层读取写入
 *     轴坐标系（接口无位置写入域，职责边界见设计要点③）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HomingMode（归属 DL_Motion，与 FB_DL_AxisHomingSeq 同文件）
 * 含义: 回零方式选择。模式是组合矩阵而非厂商魔法数：本库仅取四种高频方式，
 *       取值不用任何厂商模式数值，其余方式留扩产。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_HomingMode :
(
    eLimitSwitch := 1,   // 限位开关回零（Limit switch homing），以近端限位为参考
    eHomeSwitch  := 2,   // 原点开关回零（Home switch homing），独立原点开关
    eZeroPulse   := 3,   // Z 相脉冲精定位（Encoder zero pulse homing）
    eTorqueBlock := 4    // 扭矩堵转回零（Torque block homing），堵转阈值到达即原点
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HomingStep（归属 DL_Motion，与 FB_DL_AxisHomingSeq 同文件）
 * 含义: 回零序列步。编号显式、间隔 10 预留扩展位，eFault 末位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_HomingStep :
(
    eIdle       := 0,    // 空闲：等待启动指令 / Idle: waiting for start command
    eApproach   := 10,   // 快速逼近（Z 相/堵转模式为爬行逼近）/ Fast approach (creep for zero-pulse/torque modes)
    eRetreat    := 20,   // 反向回退（限位模式全速回退/原点开关模式停车后爬行脱离）/ Reverse retreat
    eReapproach := 30,   // 爬行再逼近（Creep re-approach toward reference）
    eCalibrate  := 40,   // 标定原点（Calibrate home position），收口转受控停车
    eStopping   := 50,   // 受控停车等待停稳（Controlled stop, waiting standstill）
    eDone       := 60,   // 回零完成（Homing done），bDone 保持
    eAborted    := 70,   // 已中止（Aborted by command），受控停车后进入
    eFault      := 99    // 故障（Fault），仅重新启动可退出本块故障态
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_AxisHomingSeq
VAR_INPUT
    eMode               : E_DL_HomingMode := E_DL_HomingMode.eHomeSwitch; // 回零模式（Homing mode），见 E_DL_HomingMode
    bCmdStart           : BOOL := FALSE;      // 回零启动（Homing start），上升沿生效
    bCmdAbort           : BOOL := FALSE;      // 回零中止（Homing abort），电平生效，触发受控停车
    bDirNeg             : BOOL := FALSE;      // 回零方向（Homing direction），TRUE=朝负方向逼近（规格外补充引脚，见头注 R11 留档）
    fHomingVel          : REAL := 50.0;       // 快速逼近速度（Homing approach velocity）[mm/s]，正值，默认 50.0
    fCreepVel           : REAL := 2.0;        // 爬行再逼近速度（Creep velocity）[mm/s]，正值，默认 2.0
    fAcc                : REAL := 1000.0;     // 回零加减速（Homing acceleration）[mm/s²]，正值，默认 1000.0
    fHomePosition       : REAL := 0.0;        // 标定原点位置值（Home position value）[mm]，暂存引脚，标定后由上层写入轴坐标系
    fMaxTravel          : REAL := 1.0E6;      // 行程护栏上限（Max travel guard）[mm]，|当前位置-起点| 超限即故障，默认 1.0E6
    tHomingTimeout      : TIME := T#60S;      // 回零总超时（Homing timeout），默认 T#60S，0=禁用
    bLimPos             : BOOL := FALSE;      // 正限位开关（Positive limit switch），TRUE=已压住
    bLimNeg             : BOOL := FALSE;      // 负限位开关（Negative limit switch），TRUE=已压住
    bHomeSw             : BOOL := FALSE;      // 原点开关（Home switch），TRUE=已压住
    bZeroPulse          : BOOL := FALSE;      // Z 相脉冲（Encoder zero pulse），捕获上升沿
    bTorqueLimitReached : BOOL := FALSE;      // 堵转阈值到达（Torque limit reached），由驱动层注入（接口无扭矩域，外部注入声明 R11 留档）
    bTrack              : BOOL := FALSE;      // 跟踪重同步（Track resync），TRUE 时中止序列回空闲（R19）
END_VAR
VAR_IN_OUT
    iAxis               : I_DL_MotionAxis;    // 轴接口引用（Axis reference），由上层注入实现块实例
END_VAR
VAR_OUTPUT
    bBusy               : BOOL := FALSE;      // 回零进行中（Homing busy）
    bDone               : BOOL := FALSE;      // 回零完成（Homing done），完成态保持至下次启动
    eStep               : E_DL_HomingStep := E_DL_HomingStep.eIdle; // 当前序列步（Current homing step），HMI 显示用
    uErrorId            : UDINT := 0;         // 末次事件码（Last error code），段位 16#0004_xxxx
END_VAR
VAR
    bInit               : BOOL := FALSE;      // 首扫标志（First-scan flag，R19 范式配套）
    bParamOk            : BOOL := FALSE;      // 参数门禁通过标志（Parameter gate pass flag），启动前逐拍重算
    bTmoEn              : BOOL := FALSE;      // 超时护栏使能（Timeout guard enable），tHomingTimeout > 0 时为 TRUE
    bTmoBreak           : BOOL := FALSE;      // 超时参数变更断拍标志（Timeout PT break flag，R14：变更后断输入一拍归零计时）
    tTmoLastRaw         : TIME := T#0S;       // 上一拍超时参数快照（Last timeout parameter snapshot，R14 配套）
    bAbortPend          : BOOL := FALSE;      // 中止挂起标志（Abort pending），受控停车完成后转已中止态
    bCmdSent            : BOOL := FALSE;      // 本步速度指令已发标志（Velocity command sent per step），换步自动复位
    bStopIssued         : BOOL := FALSE;      // 本步停止指令已发标志（Stop command sent per step），换步自动复位
    fDir                : REAL := 1.0;        // 回零方向系数（Direction factor），+1=正向 / -1=负向
    fVelHomEff          : REAL := 50.0;       // 生效快速逼近速度（Effective homing velocity）[mm/s]，恒正
    fVelCrpEff          : REAL := 2.0;        // 生效爬行速度（Effective creep velocity）[mm/s]，恒正
    fAccEff             : REAL := 1000.0;     // 生效加减速（Effective acceleration）[mm/s²]，防除零下限兜底
    fMaxTravelEff       : REAL := 1.0E6;      // 生效行程护栏（Effective travel guard）[mm]，非有限值兜底
    fVelApp             : REAL := 0.0;        // 逼近步带符号速度（Approach velocity signed）[mm/s]
    fVelRet             : REAL := 0.0;        // 限位回退步带符号速度（Limit retreat velocity signed）[mm/s]
    fVelCrpRev          : REAL := 0.0;        // 反向爬行带符号速度（Reverse creep velocity signed）[mm/s]
    fVelCrpFwd          : REAL := 0.0;        // 正向爬行带符号速度（Forward creep velocity signed）[mm/s]
    fStartPos           : REAL := 0.0;        // 启动时记录的起点位置（Start position snapshot）[mm]
    bLimWatch           : BOOL := FALSE;      // 当前模式监听的限位电平（Watched limit level），按 bDirNeg 选择
    eStepPrev           : E_DL_HomingStep := E_DL_HomingStep.eIdle; // 上一拍序列步（Previous step），换步复位步内标志
    rtrigStart          : R_TRIG;             // 启动指令上升沿（Rising edge of homing start）
    rtrigLimPos         : R_TRIG;             // 正限位上升沿（Rising edge of positive limit）
    rtrigLimNeg         : R_TRIG;             // 负限位上升沿（Rising edge of negative limit）
    rtrigHomeSw         : R_TRIG;             // 原点开关上升沿（Rising edge of home switch）
    rtrigZero           : R_TRIG;             // Z 相脉冲上升沿（Rising edge of zero pulse）
    rtrigTorque         : R_TRIG;             // 堵转信号上升沿（Rising edge of torque limit signal）
    ftrigLimPos         : F_TRIG;             // 正限位下降沿（Falling edge of positive limit）
    ftrigLimNeg         : F_TRIG;             // 负限位下降沿（Falling edge of negative limit）
    ftrigHomeSw         : F_TRIG;             // 原点开关下降沿（Falling edge of home switch）
    tonHome             : TON;                // 回零总超时定时器（Homing timeout timer）
END_VAR
VAR CONSTANT
    DL_HOM_INF_MAX      : REAL := 1.0E30;     // 有限值判定幅值上限（Finite-value magnitude bound）[mm]
    DL_HOM_EPS          : REAL := 1.0E-6;     // 浮点判零容差（Float zero tolerance）[mm]
    DL_HOM_VEL_FLOOR    : REAL := 1.0E-3;     // 速度/加速度参数下限（Velocity and acceleration floor）[mm/s 或 mm/s²]
END_VAR

METHOD IssueVel : BOOL
VAR_INPUT
    fV : REAL;                                   // 带符号速度指令（Signed velocity command）[mm/s]
END_VAR
IssueVel := iAxis.MoveVelocity(fV, fAccEff);     // 转发轴接口，受理结果即返回值
    END_METHOD

// 段 1｜沿检测与定时器无条件周期刷新（R7 红线，严禁置于分支内；实例入参先算成变量再喂实例）
rtrigStart(CLK := bCmdStart);
rtrigLimPos(CLK := bLimPos);      rtrigLimNeg(CLK := bLimNeg);
rtrigHomeSw(CLK := bHomeSw);
rtrigZero(CLK := bZeroPulse);     rtrigTorque(CLK := bTorqueLimitReached);
ftrigLimPos(CLK := bLimPos);      ftrigLimNeg(CLK := bLimNeg);
ftrigHomeSw(CLK := bHomeSw);
// R14：tHomingTimeout 语义参数变更时显式断输入一拍，使已计时归零
IF tHomingTimeout <> tTmoLastRaw THEN bTmoBreak := TRUE;  tTmoLastRaw := tHomingTimeout; END_IF
tonHome(IN := bBusy AND (NOT bTmoBreak), PT := tHomingTimeout);  // 回零总超时定时器（无条件刷新，R7）
bTmoBreak := FALSE;                              // 断拍标志本拍消费后复位

// 段 2｜接口引用有效性防御：未注入轴引用则直接退出（不产生误动作）
IF iAxis = 0 THEN
    bBusy := FALSE;
    RETURN;
END_IF

// 段 3｜R19 首扫/跟踪同步：判据唯一合法范式 IF bTrack OR (NOT bInit)
IF bTrack OR (NOT bInit) THEN
    IF bInit AND bBusy THEN
        iAxis.Stop();                            // 中途插入跟踪脉冲 → 受控停车
    END_IF
    eStep   := E_DL_HomingStep.eIdle;            // 中止序列回空闲（R19）
    bBusy   := FALSE;
    bAbortPend := FALSE;
    bCmdSent := FALSE;
    bStopIssued := FALSE;
    bInit   := TRUE;
END_IF

// 段 4｜参数防御与方向解析（公约 0.6/0.8）：非法参数仅封锁启动（信息级 0004_0106），不影响运行中扫描
fDir := 1.0;                                     // 方向系数默认正向 [1]
IF bDirNeg THEN fDir := -1.0; END_IF
bLimWatch := bLimPos;                            // 正向回零监听正限位
IF bDirNeg THEN bLimWatch := bLimNeg; END_IF     // 负向回零监听负限位
bParamOk := TRUE;
IF (fHomingVel <> fHomingVel) OR (fCreepVel <> fCreepVel) OR (fAcc <> fAcc)
   OR (fHomingVel <= DL_HOM_VEL_FLOOR) OR (fCreepVel <= DL_HOM_VEL_FLOOR)
   OR (fAcc <= DL_HOM_VEL_FLOOR)
   OR (fHomingVel > DL_HOM_INF_MAX) OR (fCreepVel > DL_HOM_INF_MAX)
   OR (fAcc > DL_HOM_INF_MAX) THEN
    bParamOk  := FALSE;                          // 速度/加速度非法或非有限值：拒绝启动
    fVelHomEff := 50.0;  fVelCrpEff := 2.0;  fAccEff := 1000.0;  // 安全兜底值，防运行中被改坏
ELSE
    fVelHomEff := fHomingVel;                    // 合法快速逼近速度直通 [mm/s]
    fVelCrpEff := fCreepVel;                     // 合法爬行速度直通 [mm/s]
    fAccEff    := fAcc;                          // 合法加减速直通 [mm/s²]
END_IF
IF (fMaxTravel <> fMaxTravel) OR (fMaxTravel <= DL_HOM_EPS) OR (fMaxTravel > DL_HOM_INF_MAX) THEN
    fMaxTravelEff := 1.0E6;                      // 行程护栏非法兜底 [mm]
    uErrorId := 16#0004_0106;                    // 信息级：参数兜底修复提示
ELSE
    fMaxTravelEff := fMaxTravel;                 // 合法行程护栏直通 [mm]
END_IF
bTmoEn := (tHomingTimeout > T#0MS);              // 超时 0=禁用护栏
fVelApp    := fDir * fVelCrpEff;                 // 逼近步默认爬行（Z 相/堵转模式）[mm/s]
IF (eMode = E_DL_HomingMode.eLimitSwitch) OR (eMode = E_DL_HomingMode.eHomeSwitch) THEN
    fVelApp := fDir * fVelHomEff;                // 限位/原点开关模式为快速逼近 [mm/s]
END_IF
fVelRet    := -fDir * fVelHomEff;                // 限位模式回退：全速反向 [mm/s]
fVelCrpRev := -fDir * fVelCrpEff;                // 原点开关模式反向爬行脱离 [mm/s]
fVelCrpFwd := fDir * fVelCrpEff;                 // 原点开关模式正向爬行再逼近 [mm/s]

// 段 5｜运行中全局护栏：轴故障 > 中止 > 超时 > 行程超限（优先级从高到低）
IF bBusy THEN
    IF iAxis.bError THEN
        eStep := E_DL_HomingStep.eFault;         // 轴故障：轴已自锁故障态，本块随之收口
        uErrorId := 16#0004_0212;
        bBusy := FALSE;
    ELSIF bCmdAbort THEN
        iAxis.Stop();                            // 中止：受控停车，停稳后转已中止态
        bAbortPend := TRUE;
        eStep := E_DL_HomingStep.eStopping;
    ELSIF bTmoEn AND tonHome.Q THEN
        iAxis.Stop();                            // 总超时：受控停车并锁存故障
        eStep := E_DL_HomingStep.eFault;
        uErrorId := 16#0004_0210;
        bBusy := FALSE;
    ELSIF ABS(iAxis.fPosition - fStartPos) > fMaxTravelEff THEN
        iAxis.Stop();                            // 行程超限：受控停车并锁存故障
        eStep := E_DL_HomingStep.eFault;
        uErrorId := 16#0004_0211;
        bBusy := FALSE;
    END_IF
END_IF

// 段 5.5｜终态重启借道（终审修复：eDone/eAborted/eFault 原为死态，启动沿被吞）：
//      三个终态收到启动上升沿 → 借道 eIdle，使下段 CASE 的 eIdle 门禁分支
//      同拍受理本次启动沿（边沿当拍仍有效，不吞沿、不双击）
IF rtrigStart.Q AND ((eStep = E_DL_HomingStep.eDone)
                  OR (eStep = E_DL_HomingStep.eAborted)
                  OR (eStep = E_DL_HomingStep.eFault)) THEN
    eStep := E_DL_HomingStep.eIdle;              // 终态重启：借道空闲态门禁（Restart from terminal state via idle gate）
END_IF

// 段 5.6｜换步检测：步号变化即复位步内指令标志（速度指令/停止指令各发一次）
IF eStep <> eStepPrev THEN
    bCmdSent := FALSE;
    bStopIssued := FALSE;
    eStepPrev := eStep;
END_IF

// 段 6｜回零序列状态机（ENUM + CASE + ELSE 兜底）
CASE eStep OF

    E_DL_HomingStep.eIdle:                       // 空闲态：等待启动门禁
        bBusy := FALSE;
        IF rtrigStart.Q THEN
            IF NOT bParamOk THEN
                uErrorId := 16#0004_0106;        // 参数门禁拒绝（信息级）
            ELSIF iAxis.eState <> E_DL_AxisState.eStandstill THEN
                uErrorId := 16#0004_0106;        // 轴不在待机态，拒绝启动（信息级）
            ELSIF (eMode = E_DL_HomingMode.eLimitSwitch) AND bLimWatch THEN
                uErrorId := 16#0004_0106;        // 可观测矛盾：启动时限位已压住
            ELSIF (eMode = E_DL_HomingMode.eHomeSwitch) AND bHomeSw THEN
                uErrorId := 16#0004_0106;        // 可观测矛盾：启动时原点开关已压住
            ELSE
                fStartPos := iAxis.fPosition;    // 记录行程护栏起点 [mm]
                bAbortPend := FALSE;
                bDone := FALSE;
                eStep := E_DL_HomingStep.eApproach;
            END_IF
        END_IF

    E_DL_HomingStep.eApproach:                   // 逼近态：按模式速度运行，监听参考事件
        bBusy := TRUE;
        IF NOT bCmdSent THEN
            IF IssueVel(fVelApp) THEN
                bCmdSent := TRUE;                // 速度指令受理，本步不再重发
            ELSE
                uErrorId := 16#0004_0213;        // 序列指令被轴拒绝（故障级）
                eStep := E_DL_HomingStep.eFault;
                bBusy := FALSE;
            END_IF
        ELSE
            CASE eMode OF
                E_DL_HomingMode.eLimitSwitch:    // 限位模式：监听所选限位上升沿
                    IF bDirNeg THEN
                        IF rtrigLimNeg.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eRetreat; END_IF
                    ELSE
                        IF rtrigLimPos.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eRetreat; END_IF
                    END_IF
                E_DL_HomingMode.eHomeSwitch:     // 原点开关模式：监听原点开关上升沿
                    IF rtrigHomeSw.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eRetreat; END_IF
                E_DL_HomingMode.eZeroPulse:      // Z 相模式：监听 Z 相上升沿
                    IF rtrigZero.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eCalibrate; END_IF
                E_DL_HomingMode.eTorqueBlock:    // 堵转模式：监听堵转信号上升沿
                    IF rtrigTorque.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eCalibrate; END_IF
                ELSE
                    uErrorId := 16#0004_0213;    // 非法模式兜底（故障级）
                    eStep := E_DL_HomingStep.eFault;
                    bBusy := FALSE;
            END_CASE
        END_IF

    E_DL_HomingStep.eRetreat:                    // 回退态：限位模式全速反向 / 原点开关模式停车后爬行脱离
        bBusy := TRUE;
        CASE eMode OF
            E_DL_HomingMode.eLimitSwitch:        // 限位模式：反向全速回退，监听限位下降沿确认脱离
                IF NOT bCmdSent THEN
                    IF IssueVel(fVelRet) THEN
                        bCmdSent := TRUE;
                    ELSE
                        uErrorId := 16#0004_0213;
                        eStep := E_DL_HomingStep.eFault;
                        bBusy := FALSE;
                    END_IF
                ELSIF bDirNeg THEN
                    IF ftrigLimNeg.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eReapproach; END_IF
                ELSE
                    IF ftrigLimPos.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eReapproach; END_IF
                END_IF
            E_DL_HomingMode.eHomeSwitch:         // 原点开关模式：先受控停车，停稳后反向爬行脱离
                IF NOT bStopIssued THEN
                    iAxis.Stop();                // 减速停（逼近沿触发）
                    bStopIssued := TRUE;
                ELSIF iAxis.eState = E_DL_AxisState.eStandstill THEN
                    IF NOT bCmdSent THEN
                        IF IssueVel(fVelCrpRev) THEN
                            bCmdSent := TRUE;
                        ELSE
                            uErrorId := 16#0004_0213;
                            eStep := E_DL_HomingStep.eFault;
                            bBusy := FALSE;
                        END_IF
                    ELSIF ftrigHomeSw.Q THEN     // 确认脱离原点开关（下降沿）
                        bCmdSent := FALSE;
                        eStep := E_DL_HomingStep.eReapproach;
                    END_IF
                END_IF
            ELSE
                uErrorId := 16#0004_0213;        // Z 相/堵转模式不应进入回退态：非法兜底
                eStep := E_DL_HomingStep.eFault;
                bBusy := FALSE;
        END_CASE

    E_DL_HomingStep.eReapproach:                 // 爬行再逼近态：监听参考事件二次触发
        bBusy := TRUE;
        IF NOT bCmdSent THEN
            IF IssueVel(fVelCrpFwd) THEN
                bCmdSent := TRUE;
            ELSE
                uErrorId := 16#0004_0213;
                eStep := E_DL_HomingStep.eFault;
                bBusy := FALSE;
            END_IF
        ELSE
            CASE eMode OF
                E_DL_HomingMode.eLimitSwitch:    // 限位模式：监听限位上升沿
                    IF bDirNeg THEN
                        IF rtrigLimNeg.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eCalibrate; END_IF
                    ELSE
                        IF rtrigLimPos.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eCalibrate; END_IF
                    END_IF
                E_DL_HomingMode.eHomeSwitch:     // 原点开关模式：监听原点开关上升沿
                    IF rtrigHomeSw.Q THEN bCmdSent := FALSE;  eStep := E_DL_HomingStep.eCalibrate; END_IF
                ELSE
                    uErrorId := 16#0004_0213;    // Z 相/堵转模式不应进入再逼近态：非法兜底
                    eStep := E_DL_HomingStep.eFault;
                    bBusy := FALSE;
            END_CASE
        END_IF

    E_DL_HomingStep.eCalibrate:                  // 标定态：本块仅收口（坐标系写入由上层联动 bDone）
        bBusy := TRUE;
        eStep := E_DL_HomingStep.eStopping;      // 转受控停车，停车指令由停车态统一发出

    E_DL_HomingStep.eStopping:                   // 受控停车态：等待轴停稳后收口
        bBusy := TRUE;
        IF NOT bStopIssued THEN
            iAxis.Stop();                        // 受控停车指令（MC_Stop 语义）
            bStopIssued := TRUE;
        ELSIF iAxis.eState = E_DL_AxisState.eStandstill THEN
            IF bAbortPend THEN
                eStep := E_DL_HomingStep.eAborted;  // 中止收口
                uErrorId := 16#0004_0212;
                bBusy := FALSE;
            ELSE
                eStep := E_DL_HomingStep.eDone;     // 正常标定收口
            END_IF
        END_IF

    E_DL_HomingStep.eDone:                       // 完成态：bDone 保持，启动沿经段 5.5 借道空闲态门禁重新回零
        bBusy := FALSE;
        bDone := TRUE;

    E_DL_HomingStep.eAborted:                    // 已中止态：启动沿经段 5.5 借道空闲态门禁重新回零
        bBusy := FALSE;

    E_DL_HomingStep.eFault:                      // 故障态：码已锁存，启动沿经段 5.5 借道空闲态门禁重试
        bBusy := FALSE;

    ELSE
        // 非法状态兜底（故障级）
        uErrorId := 16#0004_0213;
        eStep := E_DL_HomingStep.eFault;
        bBusy := FALSE;

END_CASE

// 段 7｜忙状态出口聚合（R20：量纲=布尔派生式，与序列步语义一致）
bBusy := (eStep = E_DL_HomingStep.eApproach) OR (eStep = E_DL_HomingStep.eRetreat)
      OR (eStep = E_DL_HomingStep.eReapproach) OR (eStep = E_DL_HomingStep.eCalibrate)
      OR (eStep = E_DL_HomingStep.eStopping);

(*-----------------------------------------------------------------------------
 * 方法实现（METHOD）：速度指令派发子过程，非阻塞，直接转发轴接口受理结果。
 *-----------------------------------------------------------------------------*)

END_FUNCTION_BLOCK
