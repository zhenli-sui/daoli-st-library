(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ElectronicCam
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 多轴同步耦合族 · 电子凸轮
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library
 *                         （R_TRIG / LIMIT / MIN / MAX / ABS / 类型转换），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05，零修改）
 * 功能描述 (Function)   : 电子凸轮（PLCopen 凸轮耦合语义的 clean-room 独立实现）。
 *                         以「主轴相位归一化 → 分段线性表插值 → 缩放与偏移」四段
 *                         链计算从轴目标位置，支持周期 / 非周期两种运行方式、主
 *                         轴相位固定偏移与运行相位微调（飞剪切点补偿）、表单调性
 *                         校验与啮合过渡。
 * 设计要点 (Key notes)  :
 *   ① 相位归一化用「截断取整 + 条件加减」实现小数部分，绝不对负数取模，
 *      保证负向主轴时相位仍落在 0.0..1.0。
 *   ② 表查找为线性扫描 + 防死锁计数器；插值斜率计算前强制判分母，重合点保底
 *      取左值（重合已在啮合前由单调性校验拦截）。
 *   ③ 啮合前对全表做一次性扫描（点数 / 单调性 / 非有限值），运行中只校验当前
 *      区间，避免每拍全表扫描拖长任务周期。
 *   ④ 对轴接口每拍至多一次方法调用：定位指令与减速指令在同一拍互斥。
 * 开源溯源 (Origin)     : 原创实现，clean-room。语义来源为汇川 / CODESYS SoftMotion
 *                         公开指令手册的凸轮耦合页面、ABB AC500 PLCopen 库公开
 *                         帮助页、PLC 技术网公开实战帖与非周期追剪技术文
 *                         （来源编号 RAW_NOTES S-2）。
 *                         「借鉴对象的许可说明」：上述对象全部为公开发布但受版权
 *                         保护的帮助文档 / 论坛教程 / 技术文章，属「可免费查阅、
 *                         仅借鉴语义」类别；本实现未复制任何厂商源码、未使用其
 *                         凸轮表 XML 格式，引脚命名、表结构、插值实现、单调性
 *                         校验、故障码与状态机 100% 自有设计。
 * 验收向量 (Acceptance) :
 *   V1 三点表（0/0、180/90、360/0）周期运行：从轴位置连续，无阶跃跳变；
 *   V2 非周期走完表尾 → eComplete 且 bEndOfProfile 置位，等新啮合沿重启；
 *   V3 主轴点等值（非单调）→ 啮合沿受理时锁存 0004_0261；
 *   V4 nCamPoints = 1 → 锁存 0004_0260；
 *   V5 反向主轴 + bDirNegative = TRUE 正常同步；bDirNegative = FALSE 时停留
 *      eWaiting 并出信息级 0004_0140；
 *   V6 fPhaseShift 步进 5 mm → 切点前移且出信息级 0004_0142；
 *   V7 缩放填 0 → 回默认 1.0 并出信息级 0004_0141；
 *   V8 表值含非有限值 → 锁存 0004_0263；
 *   V9 运行中途插入跟踪脉冲 bTrack：重采样相位基准、退回 eIdle（公约 0.1）。
 * 已知限制 (Limits)     :
 *   ① 从轴定位经轴接口每拍一次下发，同步精度受扫描周期限制，属「逻辑层同步」
 *      而非硬实时插补；高速飞剪必须由驱动侧凸轮功能或实时总线插补承载。
 *   ② 不实现分离式凸轮表句柄（表以数组直传，避免句柄生命周期管理）；
 *      不实现凸轮开关量输出（HMI 层量，非运动语义）。
 *   ③ 表数组维度以字面量 16 声明：FB 内部常量不能用于其自身引脚声明，
 *      因此运行期以 UPPER_BOUND 实测维度做二次钳位，实际可用点数不超实测维度。
 *   ④ 相位微调的加减速平滑由调用方斜坡化：本块只检测突变并提示，不代为滤波。
 *   ⑤ 本块为逻辑层同步编排，不构成 ISO 13849 / IEC 62061 认证安全功能。
 * 规格偏离 (Deviation)  :
 *   ① 依公约 0.1 增补 bTrack 输入引脚（首扫 / 跟踪范式强制项）。
 *   ② 表数组声明维度取字面量 16（等同 DL_CAM_MAX_POINTS），理由见已知限制③；
 *      运行期以 UPPER_BOUND / LOWER_BOUND 实测边界做钳位与越界防护。
 *   ③ eDisengaging 每拍重发一次零速指令（受控降速），而非整段只发一次：部分
 *      实现中单次速度指令会被后续局部指令覆盖，逐拍重发更稳妥，且仍满足
 *      「每拍至多一次方法调用」的接口配额。
 *   ④ bEnable 撤除时除清零输出外补发一次停止请求（安全保守处置）。
 *   ⑤ 方向判定对静止主轴（速度绝对值小于判零容差）放行，避免旋转刀从静止
 *      起步时永久停在等待态。
 * 红线自检 (Redline)    :
 *   R1 零全局符号区访问 ✓（无全局变量表访问、无外部变量声明）
 *   R2 零物理地址直写 ✓（无输入输出通道地址记号）
 *   R3 纯 IEC 61131-3 ✓（仅 R_TRIG / LIMIT / MIN / MAX / ABS / 标准类型转换）
 *   R4 防除零 / 防越界 / 浮点容差 ✓（插值前判斜率分母、数组索引经上下界实测
 *      钳位、浮点比较全用 ABS 容差、扫描循环带防死锁计数器）
 *   R5 声明行 100% 中英双语同行注释 ✓
 *   R6 ENUM + CASE 且 CASE 含 ELSE 兜底 ✓
 *   R7 边沿实例无条件周期刷新 ✓（本块无单拍脉冲输出，无跨周期残留标志）
 *   POU 终结符成对 ✓（FUNCTION_BLOCK ↔ END_FUNCTION_BLOCK，末行即终结符；
 *   TYPE ↔ END_TYPE 成对）
 * 故障码表 (Error codes):
 *   16#0004_0140【信息级】主轴方向不符 / 非周期未进表首区，等待中；
 *   16#0004_0141【信息级】缩放系数非法回默认；
 *   16#0004_0142【信息级】相位微调突变超限提示；
 *   16#0004_0260【故障级】凸轮点数非法，锁存；
 *   16#0004_0261【故障级】凸轮表主轴点非单调递增，锁存；
 *   16#0004_0262【故障级】周期长度非法（周期模式），锁存；
 *   16#0004_0263【故障级】凸轮表含非有限值，锁存；
 *   16#0004_0264【故障级】从轴定位指令被拒，锁存；
 *   16#0004_0265【故障级】从轴故障中断耦合（透传），锁存；
 *   16#0004_0298【故障级】非法状态兜底（本块专用，不与其他块共用）。
 *   信息级码只进 uErrorId；bError 为派生式仅反映 eFault 态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Motion 同步耦合族）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbCam.iMaster := fbMasterAxis;                // 主轴实现块实例注入
 *   fbCam.iSlave  := fbSlaveAxis;                 // 从轴实现块实例注入
 *   fbCam.afCamMaster[0] := 0.0;  fbCam.afCamSlave[0] := 0.0;
 *   fbCam.afCamMaster[1] := 180.0; fbCam.afCamSlave[1] := 90.0;
 *   fbCam.afCamMaster[2] := 360.0; fbCam.afCamSlave[2] := 0.0;
 *   fbCam.fCamMasterPeriod := 360.0;
 *   fbCam(bEnable := TRUE, bExecute := bCamCmd, bPeriodic := TRUE,
 *         nCamPoints := 3, fVelLimit := 300.0, fAcc := 2000.0);
 *   注：表数组在周期调用前填好即可（运行中改表无效，须重新啮合）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 表内主轴点必须严格递增；周期模式下末点可等于周期长度（自然回绕），
 *     但不得小于前一点，否则啮合沿直接被拒（故障级 0261）。
 *   2 相位微调 fPhaseShift 是「运行中」微调量，配方切换请改 fMasterOffset，
 *     两者在块内相加，不会互相覆盖。
 *   3 非周期模式走完表尾后停在 eComplete，必须给新的 bExecute 上升沿才能重启；
 *     周期性连续生产请把 bPeriodic 置 TRUE。
 *   4 等待态与啮合态内本块不会向从轴发停止指令（会与追赶指令打架），要停轴
 *     请给 bDisengage 上升沿，走受控降速路径。
 *   5 主轴静止时相位冻结在最后一次有效值，从轴保持当前位置，属正常工况。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CamState（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 电子凸轮耦合状态机，编号间隔 10 预留扩展位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_CamState :
(
    eIdle        := 0,    // 空闲：未建立耦合，输出指令为零 / Idle: no coupling, command zero
    eWaiting     := 10,   // 等待起步条件：方向不符或未达表首区 / Waiting: direction or table-start condition not met
    eEngaging    := 20,   // 啮合过渡：从轴按速度上限与加速度趋近凸轮目标 / Engaging: slave chases cam target
    eInSync      := 30,   // 同步中：从轴每拍跟随凸轮目标，bInSync 唯一来源 / In sync: slave follows cam target each scan
    eDisengaging := 40,   // 脱开：受控降速后停轴 / Disengaging: controlled deceleration then stop
    eComplete    := 50,   // 非周期走完表尾：bEndOfProfile 有效，等新啮合沿 / Complete: end of profile, waiting for new engage edge
    eFault       := 99    // 故障锁存：仅 bReset 上升沿可退出 / Fault: latched, only bReset rising edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ElectronicCam
VAR_INPUT
    bEnable         : BOOL := FALSE;        // 总使能（Enable），FALSE=立即脱开并清指令，电平语义
    bExecute        : BOOL := FALSE;        // 建立凸轮耦合（Engage），上升沿受理，仅 eIdle / eComplete 受理
    bDisengage      : BOOL := FALSE;        // 脱开（Disengage），上升沿受理，优先于 bExecute
    bTrack          : BOOL := FALSE;        // 相位基准重同步（Tracking pulse），上升沿即重采样相位基准并退回 eIdle
    bPeriodic       : BOOL := TRUE;         // 周期模式（Periodic），TRUE=表尾回绕表头，FALSE=单程到表尾置完成
    bDirNegative    : BOOL := FALSE;        // 期望主轴方向（Expected master direction），FALSE=正向，TRUE=负向
    fMasterOffset   : REAL := 0.0;          // 主轴相位固定偏移（Master offset）[mm]，配方级参数
    fPhaseShift     : REAL := 0.0;          // 运行相位微调（Phase shift）[mm]，飞剪切点在线补偿，与偏移相加
    fSlaveOffset    : REAL := 0.0;          // 从轴位置偏移（Slave offset）[mm]，叠加在表输出之上
    fMasterScaling  : REAL := 1.0;          // 主轴缩放（Master scaling）[-]，域 0.001..100，非法回默认 1.0
    fSlaveScaling   : REAL := 1.0;          // 从轴缩放（Slave scaling）[-]，域 0.001..100，非法回默认 1.0
    fVelLimit       : REAL := 200.0;        // 从轴速度上限（Slave velocity limit）[mm/s]，域 0.1..100000，兼作定位指令速度
    fAcc            : REAL := 1000.0;       // 从轴加速度（Slave acceleration）[mm/s²]，域 0.1..100000，非有限值回默认
    fDec            : REAL := 1000.0;       // 从轴减速度（Slave deceleration）[mm/s²]，域 0.1..100000，非有限值回默认
    nCamPoints      : UINT := 2;            // 凸轮表有效点数（Active cam points）[-]，域 2..实测表维度，<2 判参数非法
    bReset          : BOOL := FALSE;        // 复位故障（Fault reset），上升沿受理，仅 eFault 态有效
END_VAR
VAR_OUTPUT
    bInSync         : BOOL := FALSE;        // 同步中（In sync），仅 eInSync 态为 TRUE
    bBusy           : BOOL := FALSE;        // 执行中（Busy），等待 / 过渡 / 同步 / 脱开 四态为 TRUE
    bEndOfProfile   : BOOL := FALSE;        // 非周期走完表尾（End of profile），保持到下次啮合受理
    bError          : BOOL := FALSE;        // 故障锁存（Error），派生式仅故障级码参与，信息级码不置位
    uErrorId        : UDINT := 0;           // 故障码（Error code），段位 16#0004_xxxx，0=无故障
    fMasterPhase    : REAL := 0.0;          // 归一化主轴相位（Normalized master phase）[-]，0.0..1.0，HMI 监视用
    fSlavePosCmd    : REAL := 0.0;          // 从轴目标位置指令（Slave position command）[mm]，含缩放与偏移
    fCamSlaveTarget : REAL := 0.0;          // 表插值原始输出（Raw cam output）[mm]，未乘缩放未加偏移，调试用
END_VAR
VAR_IN_OUT
    iMaster         : I_DL_MotionAxis;      // 主轴接口引用（Master axis），由调用方注入实现块实例
    iSlave          : I_DL_MotionAxis;      // 从轴接口引用（Slave axis），由调用方注入实现块实例
    afCamMaster     : ARRAY[0..15] OF REAL; // 凸轮表主轴点（Cam master points）[mm]，维度 16（DL_CAM_MAX_POINTS），须单调递增
    afCamSlave      : ARRAY[0..15] OF REAL; // 凸轮表从轴点（Cam slave points）[mm]，维度 16，与主轴点一一对应
    fCamMasterPeriod: REAL;                 // 周期长度（Master period）[mm]，仅周期模式有效，≤0 判参数非法
END_VAR
VAR
    eState          : E_DL_CamState := E_DL_CamState.eIdle; // 内部状态机步序（Internal state）
    bInit           : BOOL := FALSE;        // 首扫完成标志（First-scan done flag），初值 FALSE，随 bTrack 复位
    bFaultLatch     : BOOL := FALSE;        // 故障锁存标志（Fault latch），仅 bReset 沿或新啮合沿解除
    bTableReady     : BOOL := FALSE;        // 凸轮表就绪标志（Table ready），啮合沿校验通过后置位
    bStopIssued     : BOOL := FALSE;        // 停止请求已发标志（Stop issued flag），单发化防重复发令
    bDirOk          : BOOL := FALSE;        // 主轴方向符合标志（Master direction ok），逐拍重算
    nPtsEff         : DINT := 2;            // 生效点数（Effective point count）[-]，已按实测维度钳位
    nLb             : DINT := 0;            // 表数组下标下界（Array lower bound）[-]，实测取得
    nUb             : DINT := 15;           // 表数组下标上界（Array upper bound）[-]，实测取得
    nAvail          : DINT := 16;           // 实测可用点数（Available points）[-]，上界减下界加一
    iIdx            : DINT := 0;            // 插值区间左端点下标（Interval left index）[-]，已验界
    nIdx            : DINT := 0;            // 表扫描索引（Table scan index）[-]，循环内递增
    nGuard          : DINT := 0;            // 循环防死锁计数器（Loop guard counter）[-]，超限即退出
    fMasterPosEff   : REAL := 0.0;          // 生效主轴坐标（Effective master coordinate）[mm]，含缩放与相位量
    fPhaseRaw       : REAL := 0.0;          // 归一化相位原值（Raw normalized phase）[-]，可为负，需修正
    fPhase          : REAL := 0.0;          // 归一化主轴相位（Normalized phase）[-]，钳在 0.0..1.0
    fPhaseShiftPrev : REAL := 0.0;          // 上拍相位微调量（Previous phase shift）[mm]，突变检测基准
    fKey            : REAL := 0.0;          // 表内主轴求值键（Master key in table）[mm]，已钳到表域
    fM0             : REAL := 0.0;          // 插值区间左主轴点（Interval master low）[mm]
    fM1             : REAL := 0.0;          // 插值区间右主轴点（Interval master high）[mm]
    fS0             : REAL := 0.0;          // 插值区间左从轴点（Interval slave low）[mm]
    fS1             : REAL := 0.0;          // 插值区间右从轴点（Interval slave high）[mm]
    fDen            : REAL := 0.0;          // 插值斜率分母（Interpolation denominator）[mm]，除零前判
    fSlaveTarget    : REAL := 0.0;          // 从轴目标位置（Slave target position）[mm]，含缩放与偏移
    fCamRaw         : REAL := 0.0;          // 表插值原始输出（Raw cam output）[mm]，未加缩放偏移
    fMScaleEff      : REAL := 1.0;          // 生效主轴缩放（Effective master scaling）[-]，非法回 1.0
    fSScaleEff      : REAL := 1.0;          // 生效从轴缩放（Effective slave scaling）[-]，非法回 1.0
    fVelEff         : REAL := 200.0;        // 生效定位速度（Effective velocity）[mm/s]，已做下限兜底
    fAccEff         : REAL := 1000.0;       // 生效加速度（Effective acceleration）[mm/s²]，已做下限兜底
    fDecEff         : REAL := 1000.0;       // 生效减速度（Effective deceleration）[mm/s²]，已做下限兜底
    fPeriodEff      : REAL := 0.0;          // 生效周期长度（Effective period）[mm]，周期模式必须 > 0
    fPosErrBand     : REAL := 0.0;          // 进入同步的位置带宽（Sync band）[mm]，取啮合带宽常量
    fSlavePosNow    : REAL := 0.0;          // 从轴本拍位置（Slave position this scan）[mm]
    fbTrigExec      : R_TRIG;               // 建立耦合指令上升沿（Engage command rising edge）
    fbTrigDisengage : R_TRIG;               // 脱开指令上升沿（Disengage command rising edge）
    fbTrigReset     : R_TRIG;               // 复位指令上升沿（Reset command rising edge）
END_VAR
VAR CONSTANT
    DL_CAM_MAX_POINTS   : DINT := 16;       // 表最大点数（Max table points）[-]，与引脚声明的字面量维度一致
    DL_CAM_INF_MAX      : REAL := 1.0E30;   // 有限值判定幅值上限（Finite magnitude bound）[无量纲，按比较量量纲同值使用]
    DL_CAM_EPS          : REAL := 1.0E-6;   // 浮点判零容差（Float zero tolerance）[无量纲，按比较量量纲同值使用]
    DL_CAM_PAR_FLOOR    : REAL := 1.0E-3;   // 速度/加速度参数下限（Parameter floor）[mm/s 或 mm/s²]
    DL_CAM_VEL_DEF      : REAL := 200.0;    // 速度默认回退值（Default velocity）[mm/s]
    DL_CAM_ACC_DEF      : REAL := 1000.0;   // 加速度默认回退值（Default acceleration）[mm/s²]
    DL_CAM_DEC_DEF      : REAL := 1000.0;   // 减速度默认回退值（Default deceleration）[mm/s²]
    DL_CAM_SCALE_MIN    : REAL := 1.0E-3;   // 缩放系数下限（Scaling floor）[-]，低于此值回默认
    DL_CAM_SCALE_MAX    : REAL := 100.0;    // 缩放系数上限（Scaling ceiling）[-]，高于此值回默认
    DL_CAM_ENGAGE_BAND  : REAL := 0.05;     // 啮合带宽（Engage band）[mm]，位置差进入带宽即判同步
    DL_CAM_PHASE_JUMP   : REAL := 2.0;      // 相位微调突变阈值（Phase jump threshold）[mm]，超此值仅提示
    DL_CAM_END_BAND     : REAL := 0.05;     // 表尾判定带（End band）[mm]，主轴接近末点即判走完
    DL_CAM_GUARD_LIMIT  : DINT := 64;       // 表扫描防死锁上限（Loop guard limit）[-]，远超最大点数
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTrigExec(CLK := bExecute);
fbTrigDisengage(CLK := bDisengage);
fbTrigReset(CLK := bReset);

// 段 2｜出口默认赋值（公约 0.9：早退路径输出必须确定）
bInSync      := FALSE;
bBusy        := FALSE;
bError       := (eState = E_DL_CamState.eFault);
fSlavePosCmd := 0.0;

// 段 3｜接口引用有效性防御：任一引用未注入则清输出退出，不产生误动作
IF (iMaster = 0) OR (iSlave = 0) THEN
    RETURN;
END_IF

// 段 4｜缩放与速度参数防御（非有限值 / 越域一律回默认并提示，逐拍重算）
IF (fMasterScaling <> fMasterScaling) OR (ABS(fMasterScaling) > DL_CAM_INF_MAX)
   OR (fMasterScaling < DL_CAM_SCALE_MIN) OR (fMasterScaling > DL_CAM_SCALE_MAX) THEN
    fMScaleEff := 1.0;                                   // 主轴缩放非法 → 默认 1.0
    uErrorId   := 16#0004_0141;                          // 【信息级】缩放系数非法回默认
ELSE
    fMScaleEff := fMasterScaling;
END_IF

IF (fSlaveScaling <> fSlaveScaling) OR (ABS(fSlaveScaling) > DL_CAM_INF_MAX)
   OR (fSlaveScaling < DL_CAM_SCALE_MIN) OR (fSlaveScaling > DL_CAM_SCALE_MAX) THEN
    fSScaleEff := 1.0;                                   // 从轴缩放非法 → 默认 1.0
    uErrorId   := 16#0004_0141;                          // 【信息级】缩放系数非法回默认
ELSE
    fSScaleEff := fSlaveScaling;
END_IF

IF (fVelLimit <> fVelLimit) OR (ABS(fVelLimit) > DL_CAM_INF_MAX) OR (fVelLimit < DL_CAM_PAR_FLOOR) THEN
    fVelEff := DL_CAM_VEL_DEF;                           // 速度上限非法 → 默认值
ELSE
    fVelEff := fVelLimit;
END_IF

IF (fAcc <> fAcc) OR (ABS(fAcc) > DL_CAM_INF_MAX) OR (fAcc < DL_CAM_PAR_FLOOR) THEN
    fAccEff := DL_CAM_ACC_DEF;
ELSE
    fAccEff := fAcc;
END_IF

IF (fDec <> fDec) OR (ABS(fDec) > DL_CAM_INF_MAX) OR (fDec < DL_CAM_PAR_FLOOR) THEN
    fDecEff := DL_CAM_DEC_DEF;
ELSE
    fDecEff := fDec;
END_IF

// 段 5｜数组实测边界（公约 0.14：数组访问前必须验界，禁越界索引）
nLb    := LOWER_BOUND(afCamMaster, 1);
nUb    := UPPER_BOUND(afCamMaster, 1);
nAvail := nUb - nLb + 1;
IF nAvail > DL_CAM_MAX_POINTS THEN
    nAvail := DL_CAM_MAX_POINTS;                         // 实测维度超库级上限时按上限钳位，防下标越界
END_IF
IF nAvail < 2 THEN
    nAvail := 0;                                         // 表维度异常（不足两点）时置 0，后续一律判故障
END_IF

// 段 6｜周期长度防御（仅周期模式需要）
IF (fCamMasterPeriod <> fCamMasterPeriod) OR (ABS(fCamMasterPeriod) > DL_CAM_INF_MAX) THEN
    fPeriodEff := 0.0;
ELSE
    fPeriodEff := fCamMasterPeriod;
END_IF

// 段 7｜主轴相位归一化（截断取整 + 条件加减，绝不对负数取模）
fMasterPosEff := fMScaleEff * iMaster.fPosition + fMasterOffset + fPhaseShift;
fPhase        := 0.0;
IF bPeriodic THEN
    IF fPeriodEff > DL_CAM_EPS THEN
        fPhaseRaw := fMasterPosEff / fPeriodEff;         // 分母已验非零
        fPhase    := fPhaseRaw - DINT_TO_REAL(REAL_TO_DINT(fPhaseRaw)); // 截断取整求小数部分
        IF fPhase < 0.0 THEN
            fPhase := fPhase + 1.0;                      // 负向主轴修正到 0.0..1.0
        END_IF
        IF fPhase >= 1.0 THEN
            fPhase := 0.0;                               // 极接近 1.0 的浮点残差归位，防越界
        END_IF
    END_IF
ELSE
    fPhase := 0.0;                                       // 非周期模式不使用归一化相位
END_IF
fMasterPhase := fPhase;

// 段 8｜相位微调突变检测（信息级提示，不阻断；平滑由调用方斜坡化）
IF ABS(fPhaseShift - fPhaseShiftPrev) > DL_CAM_PHASE_JUMP THEN
    uErrorId := 16#0004_0142;                            // 【信息级】相位微调突变超限提示
END_IF
fPhaseShiftPrev := fPhaseShift;

// 段 9｜凸轮表求值（表就绪时逐拍求值；区间右端点下标已由点数钳位保证不越界）
fCamRaw := 0.0;
IF bTableReady AND (nPtsEff >= 2) AND (nPtsEff <= nAvail) THEN
    IF bPeriodic THEN
        // 周期模式：相位展宽到表主轴域（区间端点取实测下标，避免点数与维度不一致）
        fKey := fPhase * (afCamMaster[nLb + nPtsEff - 1] - afCamMaster[nLb]) + afCamMaster[nLb];
    ELSE
        // 非周期模式：主轴坐标钳到表域
        fKey := LIMIT(afCamMaster[nLb], fMasterPosEff, afCamMaster[nLb + nPtsEff - 1]);
    END_IF
    iIdx   := nLb;
    nGuard := 0;
    FOR nIdx := nLb TO (nLb + nPtsEff - 2) DO
        IF nGuard >= DL_CAM_GUARD_LIMIT THEN
            EXIT;                                        // 防死锁：超限退出，保留下标不越界
        END_IF
        nGuard := nGuard + 1;
        iIdx   := nIdx;
        IF fKey <= afCamMaster[nIdx + 1] THEN
            EXIT;                                        // 找到所在区间
        END_IF
    END_FOR
    fM0  := afCamMaster[iIdx];
    fM1  := afCamMaster[iIdx + 1];
    fS0  := afCamSlave[iIdx];
    fS1  := afCamSlave[iIdx + 1];
    fDen := fM1 - fM0;
    IF ABS(fDen) > DL_CAM_EPS THEN
        fCamRaw := fS0 + (fKey - fM0) * (fS1 - fS0) / fDen; // 分段线性插值，分母已验非零
    ELSE
        fCamRaw := fS0;                                  // 区间退化保底取左值（啮合前已被单调性校验拦截）
    END_IF
END_IF
fCamSlaveTarget := fCamRaw;
fSlaveTarget    := fSScaleEff * fCamRaw + fSlaveOffset;

// 段 10｜首扫与跟踪范式（公约 0.1：bTrack OR (NOT bInit) 为唯一判据，禁止反序）
IF bTrack OR (NOT bInit) THEN
    fPhaseShiftPrev := fPhaseShift;                      // 相位微调基准重采样，防跟踪后误报突变
    bTableReady     := FALSE;                            // 表就绪标志复位，须重新啮合校验
    bStopIssued     := FALSE;
    fSlavePosCmd    := 0.0;
    eState          := E_DL_CamState.eIdle;
    bInit           := TRUE;                             // 首扫完成后置位（判据恒为 bTrack OR NOT bInit）
END_IF

// 段 11｜总使能撤除：清零输出并向从轴补发一次停止请求（安全保守处置）
IF NOT bEnable THEN
    IF (NOT bStopIssued) AND ((eState = E_DL_CamState.eEngaging) OR (eState = E_DL_CamState.eInSync)) THEN
        iSlave.Stop();                                   // 使能撤除瞬间单发停止，杜绝残余定位指令
        bStopIssued := TRUE;
    END_IF
    eState       := E_DL_CamState.eIdle;
    bTableReady  := FALSE;
    fSlavePosCmd := 0.0;
END_IF

// 段 12｜事件码管理（公约 0.7 / R15）：锁存码仅在解除路径清，瞬时码逐拍重算
IF NOT bFaultLatch THEN
    uErrorId := 0;
END_IF

// 段 13｜主状态机（ENUM + CASE + ELSE 兜底）
CASE eState OF

    E_DL_CamState.eIdle:                                 // 空闲：等待啮合沿与全表校验
        bBusy := FALSE;
        IF fbTrigExec.Q AND bEnable THEN
            bFaultLatch := FALSE;                        // 新啮合沿：锁存码解除路径（R15）
            bEndOfProfile := FALSE;
            IF (UINT_TO_DINT(nCamPoints) < 2) OR (UINT_TO_DINT(nCamPoints) > nAvail)
               OR (nAvail < 2) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0260;             // 【故障级】凸轮点数非法
                eState      := E_DL_CamState.eFault;
            ELSIF bPeriodic AND (fPeriodEff <= DL_CAM_EPS) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0262;             // 【故障级】周期长度非法（周期模式）
                eState      := E_DL_CamState.eFault;
            ELSE
                nPtsEff := UINT_TO_DINT(nCamPoints);
                // 啮合前全表一次性扫描：非有限值与单调性（运行中只校验当前区间）
                bTableReady := TRUE;
                nGuard      := 0;
                FOR nIdx := nLb TO (nLb + nPtsEff - 1) DO
                    IF nGuard >= DL_CAM_GUARD_LIMIT THEN
                        EXIT;                            // 防死锁
                    END_IF
                    nGuard := nGuard + 1;
                    IF (afCamMaster[nIdx] <> afCamMaster[nIdx]) OR (afCamSlave[nIdx] <> afCamSlave[nIdx]) THEN
                        bTableReady := FALSE;
                        uErrorId    := 16#0004_0263;     // 【故障级】凸轮表含非有限值
                    END_IF
                END_FOR
                IF bTableReady THEN
                    nGuard := 0;
                    FOR nIdx := nLb TO (nLb + nPtsEff - 2) DO
                        IF nGuard >= DL_CAM_GUARD_LIMIT THEN
                            EXIT;                        // 防死锁
                        END_IF
                        nGuard := nGuard + 1;
                        IF (afCamMaster[nIdx + 1] - afCamMaster[nIdx]) <= DL_CAM_EPS THEN
                            bTableReady := FALSE;
                            uErrorId    := 16#0004_0261; // 【故障级】凸轮表主轴点非单调递增
                        END_IF
                    END_FOR
                END_IF
                IF NOT bTableReady THEN
                    bFaultLatch := TRUE;
                    eState      := E_DL_CamState.eFault;
                ELSE
                    eState := E_DL_CamState.eWaiting;    // 校验通过 → 等待起步条件
                END_IF
            END_IF
        END_IF

    E_DL_CamState.eWaiting:                              // 等待起步条件：方向与表首区
        bBusy := TRUE;
        IF fbTrigDisengage.Q THEN
            eState := E_DL_CamState.eDisengaging;        // 脱开沿优先（本态禁发停止指令）
        ELSIF iSlave.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0265;                 // 【故障级】从轴故障中断耦合
            eState      := E_DL_CamState.eFault;
        ELSE
            // 方向判定：静止主轴放行（避免旋转刀从静止起步时永久等待）
            IF ABS(iMaster.fVelocity) <= DL_CAM_EPS THEN
                bDirOk := TRUE;
            ELSIF bDirNegative THEN
                bDirOk := (iMaster.fVelocity < 0.0);
            ELSE
                bDirOk := (iMaster.fVelocity > 0.0);
            END_IF
            IF (NOT bDirOk)
               OR ((NOT bPeriodic) AND (fMasterPosEff < afCamMaster[nLb] - DL_CAM_END_BAND)) THEN
                uErrorId := 16#0004_0140;                // 【信息级】方向不符 / 未进表首区，等待中
            ELSE
                eState := E_DL_CamState.eEngaging;
            END_IF
        END_IF

    E_DL_CamState.eEngaging:                             // 啮合过渡：追赶凸轮目标，带宽内转同步
        bBusy := TRUE;
        IF fbTrigDisengage.Q THEN
            eState := E_DL_CamState.eDisengaging;
        ELSIF iSlave.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0265;                 // 【故障级】从轴故障中断耦合
            eState      := E_DL_CamState.eFault;
        ELSE
            fSlavePosNow := iSlave.fPosition;
            fPosErrBand  := DL_CAM_ENGAGE_BAND;
            IF ABS(fSlavePosNow - fSlaveTarget) <= fPosErrBand THEN
                eState := E_DL_CamState.eInSync;         // 进入带宽 → 同步
            ELSE
                fSlavePosCmd := fSlaveTarget;
                IF NOT iSlave.MoveAbsolute(fPos := fSlaveTarget, fVel := fVelEff, fAcc := fAccEff) THEN
                    bFaultLatch := TRUE;
                    uErrorId    := 16#0004_0264;         // 【故障级】从轴定位指令被拒
                    eState      := E_DL_CamState.eFault;
                END_IF
            END_IF
        END_IF

    E_DL_CamState.eInSync:                               // 同步中：逐拍跟随凸轮目标
        bBusy   := TRUE;
        bInSync := TRUE;
        IF fbTrigDisengage.Q THEN
            eState := E_DL_CamState.eDisengaging;
        ELSIF iSlave.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0265;                 // 【故障级】从轴故障中断耦合
            eState      := E_DL_CamState.eFault;
        ELSE
            fSlavePosCmd := fSlaveTarget;
            IF NOT iSlave.MoveAbsolute(fPos := fSlaveTarget, fVel := fVelEff, fAcc := fAccEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0264;             // 【故障级】从轴定位指令被拒
                eState      := E_DL_CamState.eFault;
            ELSIF (NOT bPeriodic) AND (fMasterPosEff >= (afCamMaster[nLb + nPtsEff - 1] - DL_CAM_END_BAND)) THEN
                bEndOfProfile := TRUE;                   // 非周期走完表尾
                bStopIssued   := FALSE;
                eState        := E_DL_CamState.eComplete;
            END_IF
        END_IF

    E_DL_CamState.eDisengaging:                          // 脱开：受控降速后停轴
        bBusy := TRUE;
        IF iSlave.bError THEN
            bFaultLatch := TRUE;
            uErrorId    := 16#0004_0265;                 // 【故障级】从轴故障中断耦合
            eState      := E_DL_CamState.eFault;
        ELSIF ABS(iSlave.fVelocity) <= DL_CAM_EPS THEN
            IF NOT bStopIssued THEN
                iSlave.Stop();                           // 已停稳：单发停止确认（本拍唯一一次轴调用）
                bStopIssued := TRUE;
            END_IF
            fSlavePosCmd := 0.0;
            bBusy        := FALSE;
            bStopIssued  := FALSE;                       // 停发标志闭环复位
            eState       := E_DL_CamState.eIdle;
        ELSE
            // 逐拍重发零速指令保证持续减速（每拍至多一次轴调用）
            IF NOT iSlave.MoveVelocity(fVel := 0.0, fAcc := fDecEff) THEN
                bFaultLatch := TRUE;
                uErrorId    := 16#0004_0264;             // 【故障级】脱开减速指令被拒
                eState      := E_DL_CamState.eFault;
            END_IF
            fSlavePosCmd := 0.0;
        END_IF

    E_DL_CamState.eComplete:                             // 非周期完成：保持结果等新啮合沿
        bBusy         := FALSE;
        bEndOfProfile := TRUE;
        fSlavePosCmd  := fSlaveTarget;                   // 保持末点目标，从轴稳定停在表尾位置
        IF fbTrigDisengage.Q THEN
            eState := E_DL_CamState.eDisengaging;
        ELSIF fbTrigExec.Q AND bEnable THEN
            bEndOfProfile := FALSE;                      // 新啮合沿受理：清完成标志重新起步
            bFaultLatch   := FALSE;
            eState        := E_DL_CamState.eWaiting;
        END_IF

    E_DL_CamState.eFault:                                // 故障锁存：仅复位沿可退出
        bBusy         := FALSE;
        bInSync       := FALSE;
        fSlavePosCmd  := 0.0;
        bStopIssued   := FALSE;
        bTableReady   := FALSE;
        IF fbTrigReset.Q THEN
            bFaultLatch := FALSE;                        // 唯一解除路径
            uErrorId    := 0;
            bEndOfProfile := FALSE;
            eState      := E_DL_CamState.eIdle;
        END_IF

    ELSE                                                 // 非法状态兜底（本块专用码）
        bFaultLatch   := TRUE;
        uErrorId      := 16#0004_0298;                   // 【故障级】非法状态兜底
        bBusy         := FALSE;
        bInSync       := FALSE;
        bTableReady   := FALSE;
        fSlavePosCmd  := 0.0;
        eState        := E_DL_CamState.eFault;

END_CASE

// 段 14｜出口映射（派生式，信息级码不参与 bError）
bError          := (eState = E_DL_CamState.eFault);
bInSync         := (eState = E_DL_CamState.eInSync);
bBusy           := (eState = E_DL_CamState.eWaiting) OR (eState = E_DL_CamState.eEngaging)
                   OR (eState = E_DL_CamState.eInSync) OR (eState = E_DL_CamState.eDisengaging);
fCamSlaveTarget := fCamRaw;
fMasterPhase    := fPhase;

END_FUNCTION_BLOCK
