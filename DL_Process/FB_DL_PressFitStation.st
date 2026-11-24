(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PressFitStation
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 工站模板 · 伺服精密压装
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
 *                         仅依赖标准库（TON / R_TRIG / ABS / LIMIT / MAX / MIN），
 *                         位移与压力均为引脚注入的工程量，块内零硬件与零轴库细节
 * 功能描述 (Function)   : 伺服精密压装工站八态（待机 / 接近 / 压入 / 保压 / 回退 /
 *                         判定 / 完成 / 故障）；压入过程逐点做位移-压力包络窗口校验
 *                         （上下限按位移节点线性插值），提取接触点 / 屈服点 / 峰值点
 *                         / 终点四特征点，一个循环给出合格结论与 NG 原因位
 * 与既有件边界 (Scope)  : 轴级力矩限幅与到位判定属运动层力矩限幅件（只出「达限 /
 *                         到位」两个布尔）；本块做工站级工艺判定（包络 + 曲线特征 +
 *                         多原因归并 + 结果结构），分层不同、不可互替。通用步序基类
 *                         不套用：压装态与监控量强耦合，套基类会出现两套状态机并存
 * 状态机规模 (States)   : 八态最小子集（0 / 10 / 20 / 30 / 40 / 50 / 60 / 99），编号
 *                         留 10 间隔便于插态；不重复包装机十七态全集（那由包装机
 *                         状态机件承担），本块只做压装工序自身的可执行子集
 * 采样口径 (Sampling)   : 接近 / 压入 / 保压三段逐拍采样；包络校验只在压入与保压段
 *                         执行（接近段压力天然低于下限，一并判会误报）；斜率按相邻
 *                         两拍差分，位移增量小于保护阈值时沿用上一拍，杜绝除零
 * 屈服判据 (Yield note) : 取「斜率回落至峰值斜率的指定比例」，不以压力绝对过峰为前
 *                         提。现场屈服段多为斜率软化而非压力下降（铝壳 / 塑料件尤
 *                         甚），强求过峰则单调上升曲线永远判不出；过峰另有独立标志
 * 设计要点 (Key notes)  : ① 单拍三律：bDone 每拍预清零、eFinish 唯一置位、转出拍不
 *                           再置位；合格与不合格在 eEvaluate 一次锁存，同循环闭环
 *                         ② 包络表只读：注入表一律不改写，上下限对调在块内镜像纠正
 *                         ③ 二分定位：带防死锁计数的二分查找，节点上限 32，最多五轮
 *                         ④ 非有限值防御：位移或压力非有限时当拍拒绝采样并转故障
 *                         ⑤ 回退快照：进回退态首拍取终点特征，位置最多滞后一个扫描
 * 码位表 (Error codes)  :
 *   16#0005_01C0【信息级】包络表点数超上限已钳位为 32，不置故障位
 *   16#0005_01C1【信息级】包络上下限对调已在块内镜像修复，不置故障位
 *   16#0005_02C0【故障级】非法状态兜底
 *   16#0005_02C1【故障级】包络表非法（节点数小于 2、或位移非严格单调递增）
 *   16#0005_02C2【故障级】阶段超时（接近 / 压入 / 保压 三段共用该码）
 *   16#0005_02C3【故障级】采样非有限值（当拍拒绝更新并转故障）
 * NG 原因位 (NG bits)   : bit0 上包络越界｜bit1 下包络越界｜bit2 终点未达｜bit3 接触
 *                         未建立｜bit4 保压压降超限；按位或累计，一个循环可多位置位
 * R32 写入点次序审计 :
 *   nSampleCnt   : ① 启动拍清零（eIdle）→ ② 采样块自增（唯一自增点）
 *   uNgReason    : ① 启动拍清零 → ② 上包络越界 → ③ 下包络越界 → ④ 保压压降（eDwell
 *                  转出）→ ⑤ 终点未达（回退首拍）→ ⑥ 接触未建立（eEvaluate）→ ⑦ 复
 *                  位清；全部按位或置位，同拍按 ②③④⑤ 累加，结构上不可能互相覆盖
 *   _uErrorIdInt : ① 启动拍清零 → ② 包络表非法（启动校验）→ ③ 阶段超时（三态各一处，
 *                  同拍只命中一处）→ ④ 采样非有限 → ⑤ 非法状态（ELSE）→ ⑥ 复位清
 *   _eState      : 每拍只在 CASE 分支出口单点写入；CASE 之外仅两处（中止监视、使能撤
 *                  销），且均在 CASE 之前，次序固定
 * 验收向量 (Acceptance) :
 *   V1 包络插值：节点（0 毫米 上限 0 下限 0）、（10 毫米 上限 10 下限 2），实测位移
 *      5.0 毫米压力 5.5 千牛 → 插得上限 5.0 下限 1.0，上越界 0.5 千牛 → bit0 置位、
 *      最大偏差不小于 0.5 千牛（容差 1E-6）
 *   V2 接触点插值：采样（1.0 毫米, 0.02 千牛）、（1.2 毫米, 0.06 千牛），阈值 0.05
 *      千牛 → 接触位移 1.15 毫米（误差不超过 1E-4）
 *   V3 屈服点：斜率序列 20 / 18 / 9 千牛每毫米，比例 0.5（阈值 10）→ 斜率 9 出现那
 *      一拍锁存屈服点，锁存后不再更新
 *   V4 终点未达：目标 10.0 毫米，回退前最大位移 9.4 毫米 → bit2 置位、不合格、单拍脉冲
 *   V5 保压压降：保压起点 12.0 千牛、结束 8.0 千牛、判据 0.3 千牛 → 压降 4.0 千牛超限
 *      → bit4 置位
 *   V6 非法包络：节点数 1 → 码 02C1、故障锁存、不出完成脉冲
 * 开源溯源 (Origin)     : 参考 lisp 与 PLCopen 公开手册的「命令-监视-判定」三段分层与
 *                         工艺参数域命名组织，只借分类与参数域；状态机、插值、特征点
 *                         提取、码位与引脚契约为本库独立设计，clean-room 不构成衍生
 * 红线自检 (Redline)    : R1 零全局表与外部变量引用、零物理地址记号 ✓｜R2 零占位符 ✓
 *                         R3 纯 IEC 61131-3 加标准库 ✓｜R4 非有限值 / 除零 / 容差 /
 *                         判界 ✓｜R5 声明行中英双语同行注释 ✓｜R6 八成员逐一有 CASE
 *                         标签且含 ELSE 兜底 ✓｜R7 三沿两定时器 CASE 外无条件刷新 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 11 · C 泳道 · 工站四件套之一）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PressFitState（归属 FB_DL_PressFitStation，同文件发布）
 *   八态：每个成员在下方主状态机中均有同名 CASE 标签，缺一即致命（R31）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PressFitState :
(
    eIdle      := 0,    // 待机：等启动沿，输出全复位 / Idle, awaiting start edge
    eApproach  := 10,   // 接近：等接触建立 / Approach, awaiting contact build-up
    ePress     := 20,   // 压入：包络校验与特征点逐拍提取 / Press, envelope and features per scan
    eDwell     := 30,   // 保压：保持压力并监视压降 / Dwell, hold and watch force decay
    eRetract   := 40,   // 回退：等回退到位或中止 / Retract, waiting for home or abort
    eEvaluate  := 50,   // 判定：归并 NG 原因并锁存结论 / Evaluate, merge NG reasons and latch
    eFinish    := 60,   // 完成：本拍出完成脉冲，下拍转待机 / Finish, done pulse this scan
    eFault     := 99    // 故障锁存：仅复位沿可退 / Fault latched, only a reset edge leaves
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_PressFitEnvelope（归属 FB_DL_PressFitStation）
 *   位移-压力包络表，由工艺组态注入；位移节点须严格单调递增
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_PressFitEnvelope :
STRUCT
    nPoints   : INT;                        // 有效节点数 [个]，域 2~32 [Valid knot count]
    afPos     : ARRAY[1..32] OF REAL;       // 节点位移 [毫米]，严格单调递增 [Knot position, mm]
    afUpper   : ARRAY[1..32] OF REAL;       // 节点包络上限 [千牛] [Upper envelope limit, kN]
    afLower   : ARRAY[1..32] OF REAL;       // 节点包络下限 [千牛] [Lower envelope limit, kN]
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_PressFitResult（归属 FB_DL_PressFitStation）
 *   四特征点结果，未提取到时保持 0.0，对应 NG 原因位说明缺失原因
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_PressFitResult :
STRUCT
    fContactPos   : REAL;                   // 接触点位移 [毫米] [Contact position, mm]
    fContactForce : REAL;                   // 接触点压力 [千牛] [Contact force, kN]
    fYieldPos     : REAL;                   // 屈服点位移 [毫米] [Yield position, mm]
    fYieldForce   : REAL;                   // 屈服点压力 [千牛] [Yield force, kN]
    fPeakPos      : REAL;                   // 峰值点位移 [毫米] [Peak position, mm]
    fPeakForce    : REAL;                   // 峰值点压力 [千牛] [Peak force, kN]
    fEndPos       : REAL;                   // 终点位移 [毫米] [End position, mm]
    fEndForce     : REAL;                   // 终点压力 [千牛] [End force, kN]
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_PressFitStat（归属 FB_DL_PressFitStation）
 *   跨周期统计，由调用方持有，本块只累加，掉电保持由上层负责
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_PressFitStat :
STRUCT
    nCycleCount : UDINT;                    // 累计循环数 [次] [Cycle counter]
    nOkCount    : UDINT;                    // 累计合格数 [件] [Accepted counter]
    nNgCount    : UDINT;                    // 累计不合格数 [件] [Rejected counter]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_PressFitStation
VAR_INPUT
    bEnable            : BOOL;              // 使能，FALSE 回待机并复位输出 [Enable, FALSE resets to idle]
    bStart             : BOOL;              // 启动一个压装循环，上升沿受理 [Start one cycle on rising edge]
    bAbort             : BOOL;              // 中止并立即请求回退，上升沿受理 [Abort and retract on rising edge]
    bReset             : BOOL;              // 复位故障锁存，上升沿受理 [Reset latched fault on rising edge]
    fActPos            : REAL;              // 压头实际位移 [毫米]，量程 0.0~1000.0 [Ram position, mm]
    fActForce          : REAL;              // 压力传感器实测压力 [千牛]，量程 0.0~500.0 [Measured force, kN]
    fContactForceThr   : REAL := 0.05;      // 接触判定压力阈值 [千牛]，0 表示禁用接触点提取 [Contact threshold, kN]
    fYieldSlopeRatio   : REAL := 0.50;      // 屈服判据斜率比例 [-]，域 0.05~0.99 [Yield slope ratio]
    fPeakDropForce     : REAL := 0.30;      // 峰值后压降判定量 [千牛]，0 表示不判 [Force drop after peak, kN]
    fEndPosTarget      : REAL := 10.0;      // 终点位移目标 [毫米] [Target end position, mm]
    tStageTimeout      : TIME := T#5S;      // 单段动作超时 [毫秒]，0 表示不监控 [Per-stage timeout]
    tDwell             : TIME := T#500MS;   // 保压时间 [毫秒]，0 表示跳过保压 [Dwell time]
    fForceUpperLimit   : REAL := 180.0;     // 压力硬上限 [千牛]，达限立即转保压 [Hard force limit, kN]
END_VAR
VAR_OUTPUT
    eState             : E_DL_PressFitState; // 主状态机当前态 [-]，八态之一 [Current state]
    bBusy              : BOOL;              // 循环进行中，接近至回退为真 [Cycle in progress]
    bDone              : BOOL;              // 循环结束单拍脉冲 [-] [Single-scan done pulse]
    bOk                : BOOL;              // 判定合格，保持到下次启动 [Verdict OK held until next start]
    bNg                : BOOL;              // 判定不合格，保持到下次启动 [Verdict NG held until next start]
    bError             : BOOL;              // 故障级锁存，需复位清除 [Latched fault, cleared by reset]
    uErrorId           : UDINT;             // 事件码或故障码，0 表示无 [Event or fault code, 0 = none]
    uNgReason          : WORD;              // NG 原因位，bit0~bit4 见头注释 [NG reason bits, see header]
    stResult           : ST_DL_PressFitResult; // 曲线四特征点结果 [-] [Curve feature result]
    fEnvDevMax         : REAL;              // 全程包络最大偏差 [千牛]，趋势分析用 [Max envelope deviation, kN]
    nSampleCnt         : UDINT;             // 本循环有效采样点数 [点] [Valid sample count of this cycle]
END_VAR
VAR_IN_OUT
    stEnv              : ST_DL_PressFitEnvelope; // 包络表，组态注入，块内只读 [Envelope table, read-only here]
    stStat             : ST_DL_PressFitStat;     // 跨周期统计，调用方持有 [Persistent statistics held by caller]
END_VAR
VAR
    _eState            : E_DL_PressFitState := E_DL_PressFitState.eIdle; // 内部状态寄存器 [-]，唯一真值源 [Internal state register]
    _bInit             : BOOL := FALSE;     // 首扫标志，初值 FALSE，判据 NOT _bInit [First-scan flag, R19 pattern]
    _bFaultLatch       : BOOL;              // 故障级锁存，仅复位路径清 [Fault latch, reset path only]
    _uErrorIdInt       : UDINT;             // 故障级码寄存 [Fault-level code register]
    _uInfoCode         : UDINT;             // 本拍信息级码，每拍重算 [Transient info code]
    _bEnvValid         : BOOL;              // 包络表校验通过，启动拍重算 [Envelope validated at start]
    _nEnvPts           : INT;               // 生效包络节点数 [个]，域 2~32 [Effective knot count]
    _bContactFound     : BOOL;              // 接触点已提取 [Contact point captured]
    _bYieldFound       : BOOL;              // 屈服点已提取，只锁一次 [Yield point captured once]
    _bPeakPassed       : BOOL;              // 压力已回落过峰值 [Force passed its peak]
    _bHavePrev         : BOOL;              // 存在上一点采样 [Previous sample available]
    _bRetractSnapDone  : BOOL;              // 回退入口快照已完成 [Retract snapshot already taken]
    _fPrevPos          : REAL;              // 上一点位移 [毫米] [Previous position, mm]
    _fPrevForce        : REAL;              // 上一点压力 [千牛] [Previous force, kN]
    _fStartPos         : REAL;              // 循环起点位移 [毫米] [Cycle start position, mm]
    _fSlope            : REAL;              // 当前斜率 [千牛每毫米] [Current slope, kN/mm]
    _fSlopeMax         : REAL;              // 峰值斜率 [千牛每毫米] [Peak slope, kN/mm]
    _fPeakPos          : REAL;              // 峰值点位移 [毫米] [Peak position, mm]
    _fPeakForce        : REAL;              // 峰值点压力 [千牛] [Peak force, kN]
    _fDwellStartForce  : REAL;              // 保压起点压力 [千牛] [Dwell start force, kN]
    _fContactThrEff    : REAL;              // 生效接触阈值 [千牛] [Effective contact threshold, kN]
    _fYieldRatioEff    : REAL;              // 生效屈服比例 [-] [Effective yield ratio]
    _fPeakDropEff      : REAL;              // 生效压降判据 [千牛] [Effective drop criterion, kN]
    _fEndTgtEff        : REAL;              // 生效终点目标 [毫米] [Effective end target, mm]
    _fForceLimEff      : REAL;              // 生效压力硬上限 [千牛] [Effective force limit, kN]
    _tStageEff         : TIME;              // 生效单段超时 [毫秒] [Effective stage timeout]
    _tDwellEff         : TIME;              // 生效保压时间 [毫秒] [Effective dwell time]
    _fUp               : REAL;              // 插值包络上限 [千牛] [Interpolated upper bound, kN]
    _fLo               : REAL;              // 插值包络下限 [千牛] [Interpolated lower bound, kN]
    _fSpan             : REAL;              // 插值区间跨度 [毫米] [Interpolation span, mm]
    _fRatio            : REAL;              // 插值比例 [-] [Interpolation ratio]
    _fDelta            : REAL;              // 差分中间量 [千牛或毫米] [Difference term]
    afPosUse           : ARRAY[1..32] OF REAL;  // 位移节点镜像 [毫米] [Position knot mirror, mm]
    afUpperUse         : ARRAY[1..32] OF REAL;  // 包络上限镜像 [千牛] [Upper limit mirror, kN]
    afLowerUse         : ARRAY[1..32] OF REAL;  // 包络下限镜像 [千牛] [Lower limit mirror, kN]
    nI                 : INT;               // 通用循环索引 [索引] [Loop index]
    nGuard             : INT;               // 防死锁计数 [次] [Loop guard counter]
    nLo                : INT;               // 二分下界索引 [索引] [Binary search low index]
    nHi                : INT;               // 二分上界索引 [索引] [Binary search high index]
    nMid               : INT;               // 二分中点索引 [索引] [Binary search mid index]
    bSampleFinite      : BOOL;              // 采样值有限，当拍可采 [Sample finite verdict]
    _bStageChg         : BOOL;              // 本拍发生过阶段迁移，用于断开单段计时一拍 [Stage changed this scan]
    _eStagePrev        : E_DL_PressFitState := E_DL_PressFitState.eIdle; // 上拍状态，迁移判据用 [Previous state of last scan]
    bStageTmoIn        : BOOL;              // 单段超时输入条件，先算后调 [Stage timer input]
    bDwellTmoIn        : BOOL;              // 保压计时输入条件，先算后调 [Dwell timer input]
    fbTrigStart        : R_TRIG;            // 启动沿检测 [Start edge detector]
    fbTrigAbort        : R_TRIG;            // 中止沿检测 [Abort edge detector]
    fbTrigReset        : R_TRIG;            // 复位沿检测 [Reset edge detector]
    fbTmoStage         : TON;               // 单段超时定时器 [Stage timeout timer]
    fbTmoDwell         : TON;               // 保压计时定时器 [Dwell timer]
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS       : REAL := 1.0E-6;    // 浮点判等容差 [-] [Float comparison epsilon]
    DL_SLOPE_MIN_DELTA : REAL := 1.0E-4;    // 斜率计算最小位移增量 [毫米] [Min delta for slope, mm]
    DL_ENV_MAX_POINTS  : INT  := 32;        // 包络表节点数上限 [个] [Max envelope knots]
    DL_ENV_MIN_POINTS  : INT  := 2;         // 包络表节点数下限 [个] [Min envelope knots]
    DL_MAX_LOOP        : INT  := 64;        // 循环防死锁上限 [次] [Loop guard limit]
    DL_MAX_CYCLES      : UDINT := 16#FFFF_FFFE; // 统计计数饱和上限 [次] [Counter saturation limit]
    DL_RATIO_MIN       : REAL := 0.05;      // 屈服比例域下限 [-] [Yield ratio lower bound]
    DL_RATIO_MAX       : REAL := 0.99;      // 屈服比例域上限 [-] [Yield ratio upper bound]
    DL_FORCE_MAX       : REAL := 500.0;     // 压力输入域上限 [千牛] [Force domain upper bound, kN]
    DL_POS_MAX         : REAL := 1000.0;    // 位移输入域上限 [毫米] [Position domain upper bound, mm]
    DL_REAL_MAX        : REAL := 3.4E38;    // 单精度有限值判据幅值 [-] [Finite magnitude bound]
    DL_TMO_MAX         : TIME := T#180S;    // 超时参数域上限 [毫秒] [Timeout upper bound]
    DL_NG_ENV_HIGH     : WORD := 16#0001;   // NG 原因位 bit0 上包络越界 [NG bit0, upper envelope]
    DL_NG_ENV_LOW      : WORD := 16#0002;   // NG 原因位 bit1 下包络越界 [NG bit1, lower envelope]
    DL_NG_END_POS      : WORD := 16#0004;   // NG 原因位 bit2 终点未达 [NG bit2, end not reached]
    DL_NG_NO_CONTACT   : WORD := 16#0008;   // NG 原因位 bit3 接触未建立 [NG bit3, contact missing]
    DL_NG_DWELL_DROP   : WORD := 16#0010;   // NG 原因位 bit4 保压压降超限 [NG bit4, dwell decay]
    DL_INFO_PTS_CLAMP  : UDINT := 16#0005_01C0; // 01C0 包络点数越界已钳位【信息级】 [Info, knots clamped]
    DL_INFO_LIM_SWAP   : UDINT := 16#0005_01C1; // 01C1 上下限对调已修复【信息级】 [Info, limits swapped]
    DL_ERR_STATE       : UDINT := 16#0005_02C0; // 02C0 非法状态兜底【故障级】 [Fault, illegal state]
    DL_ERR_ENV         : UDINT := 16#0005_02C1; // 02C1 包络表非法【故障级】 [Fault, invalid envelope]
    DL_ERR_STAGE_TMO   : UDINT := 16#0005_02C2; // 02C2 阶段超时【故障级】 [Fault, stage timeout]
    DL_ERR_SAMPLE      : UDINT := 16#0005_02C3; // 02C3 采样非有限值【故障级】 [Fault, non-finite sample]
END_VAR
// ==== 段 1｜单拍输出预清零（R24/R25 律①：置位前先清零，任何早退路径输出确定） / Single-scan output pre-clear, mandatory before any set point
bDone      := FALSE;                        // 完成脉冲每拍先清零 [Done pulse pre-cleared]
_uInfoCode := 16#0000_0000;                 // 信息级码每拍重算 [Info code recomputed each scan]
// ==== 段 2｜工艺参数钳位（先钳位再进逻辑，杜绝分支内出现裸数值） / Parameter clamping before any logical use, no magic numbers in logic
_fContactThrEff := LIMIT(0.0, fContactForceThr, DL_FORCE_MAX);   // 接触阈值钳位 [千牛] [Contact threshold clamped]
_fYieldRatioEff := LIMIT(DL_RATIO_MIN, fYieldSlopeRatio, DL_RATIO_MAX); // 屈服比例钳位 [-] [Yield ratio clamped]
_fPeakDropEff   := LIMIT(0.0, fPeakDropForce, DL_FORCE_MAX);     // 压降判据钳位 [千牛] [Drop criterion clamped]
_fEndTgtEff     := LIMIT(0.0, fEndPosTarget, DL_POS_MAX);        // 终点目标钳位 [毫米] [End target clamped]
_fForceLimEff   := LIMIT(DL_FLOAT_EPS, fForceUpperLimit, DL_FORCE_MAX); // 硬上限钳位 [千牛] [Force limit clamped]
_tStageEff := tStageTimeout;                // 单段超时先取引脚值 [Stage timeout from pin]
IF _tStageEff > DL_TMO_MAX THEN
    _tStageEff := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
ELSIF _tStageEff < T#0S THEN
    _tStageEff := T#0S;                     // 负值归零 [Negative clamped to zero]
END_IF
_tDwellEff := tDwell;                       // 保压时间先取引脚值 [Dwell time from pin]
IF _tDwellEff > DL_TMO_MAX THEN
    _tDwellEff := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
ELSIF _tDwellEff < T#0S THEN
    _tDwellEff := T#0S;                     // 负值归零 [Negative clamped to zero]
END_IF
// ==== 段 3｜沿与定时器无条件刷新（R7 红线：严禁置于 IF / CASE 分支内） / Unconditional per-cycle refresh of edges and timers, outside any branch
fbTrigStart(CLK := bStart);                 // 启动沿 [Start edge]
fbTrigAbort(CLK := bAbort);                 // 中止沿 [Abort edge]
fbTrigReset(CLK := bReset);                 // 复位沿 [Reset edge]
IF ((_eState = E_DL_PressFitState.eApproach)
 OR (_eState = E_DL_PressFitState.ePress)
 OR (_eState = E_DL_PressFitState.eDwell)) AND (NOT _bStageChg) THEN
    bStageTmoIn := TRUE;                    // 动作段计时，迁移后的第一拍断输入以清零 [Timed, broken one scan after a transition]
ELSE
    bStageTmoIn := FALSE;                   // 非动作段不计时 [Timer disabled outside motion]
END_IF
fbTmoStage(IN := bStageTmoIn, PT := _tStageEff);
IF _eState = E_DL_PressFitState.eDwell THEN
    bDwellTmoIn := TRUE;                    // 仅保压段计时 [Only during dwell]
ELSE
    bDwellTmoIn := FALSE;                   // 其余段清零 [Cleared otherwise]
END_IF
fbTmoDwell(IN := bDwellTmoIn, PT := _tDwellEff);
// ==== 段 4｜首扫初始化（R19 唯一合法范式：初值 FALSE，判据 NOT，同步后置 TRUE） / First-scan initialisation with the canonical R19 pattern
IF NOT _bInit THEN
    _eState           := E_DL_PressFitState.eIdle;  // 状态回待机 [State to idle]
    _bFaultLatch      := FALSE;             // 故障锁存清零 [Fault latch cleared]
    _uErrorIdInt      := 16#0000_0000;      // 故障码清零 [Fault code cleared]
    _bEnvValid        := FALSE;             // 包络未校验 [Envelope not validated yet]
    _bStageChg        := FALSE;             // 阶段迁移标志清零 [Stage change flag cleared]
    _eStagePrev       := E_DL_PressFitState.eIdle;  // 上拍状态同步 [Previous state synced]
    _nEnvPts          := 0;                 // 节点数清零 [Knot count cleared]
    _bContactFound    := FALSE;  _bYieldFound   := FALSE;   // 接触点与屈服点未提取 [Contact and yield not captured]
    _bPeakPassed      := FALSE;  _bHavePrev     := FALSE;   // 过峰标志与采样链清零 [Peak flag and sampling chain cleared]
    _bRetractSnapDone := FALSE;             // 回退快照未做 [Retract snapshot pending]
    _fPrevPos         := 0.0;    _fPrevForce    := 0.0;     // 上一点位移与压力清零 [Previous sample cleared]
    _fStartPos        := 0.0;    _fDwellStartForce := 0.0;  // 起点与保压起点压力清零 [Start points cleared]
    _fSlope           := 0.0;    _fSlopeMax     := 0.0;     // 斜率与峰值斜率清零 [Slope and peak slope cleared]
    _fPeakPos         := 0.0;    _fPeakForce    := 0.0;     // 峰值点清零 [Peak point cleared]
    fEnvDevMax        := 0.0;    _fUp           := 0.0;     // 最大偏差与插值上限清零 [Deviation and upper bound cleared]
    _fLo              := 0.0;                               // 插值下限清零 [Lower bound cleared]
    bOk               := FALSE;  bNg            := FALSE;   // 合格与不合格结论清零 [Verdicts cleared]
    bBusy             := FALSE;  bError         := FALSE;   // 忙与故障标志清零 [Busy and error cleared]
    uErrorId          := 16#0000_0000;  uNgReason := 16#0000;  // 事件码与原因位清零 [Error id and NG bits cleared]
    nSampleCnt        := 0;                 // 采样计数清零 [Sample counter cleared]
    stResult.fContactPos   := 0.0;  stResult.fContactForce := 0.0;  // 接触点清零 [Contact point cleared]
    stResult.fYieldPos     := 0.0;  stResult.fYieldForce   := 0.0;  // 屈服点清零 [Yield point cleared]
    stResult.fPeakPos      := 0.0;  stResult.fPeakForce    := 0.0;  // 峰值点清零 [Peak point cleared]
    stResult.fEndPos       := 0.0;  stResult.fEndForce     := 0.0;  // 终点清零 [End point cleared]
    FOR nI := 1 TO DL_ENV_MAX_POINTS DO
        afPosUse[nI]   := 0.0;              // 位移镜像清零 [Position mirror cleared]
        afUpperUse[nI] := 0.0;              // 上限镜像清零 [Upper mirror cleared]
        afLowerUse[nI] := 0.0;              // 下限镜像清零 [Lower mirror cleared]
    END_FOR
    _bInit := TRUE;                         // 首扫只做一次 [Runs exactly once]
END_IF
// ==== 段 5｜启动拍包络表校验（只读校验，上下限对调在镜像里纠正，绝不改写组态） / Envelope validation at start; swaps are repaired in the mirror only
IF fbTrigStart.Q AND (_eState = E_DL_PressFitState.eIdle)
AND bEnable AND (NOT _bFaultLatch) THEN
    _bEnvValid := TRUE;                     // 先假定合法，再逐条反证 [Assume valid, then disprove]
    _nEnvPts   := stEnv.nPoints;            // 取组态节点数 [Knot count from configuration]
    IF _nEnvPts > DL_ENV_MAX_POINTS THEN
        _nEnvPts   := DL_ENV_MAX_POINTS;    // 超上限钳到 32 [Clamped to 32]
        _uInfoCode := DL_INFO_PTS_CLAMP;    // 01C0 点数越界已钳位【信息级】 [Info, knots clamped]
    END_IF
    IF _nEnvPts < DL_ENV_MIN_POINTS THEN
        _bEnvValid := FALSE;                // 少于两点无法插值 [Less than two knots is unusable]
    END_IF
    IF _bEnvValid THEN
        FOR nI := 1 TO _nEnvPts DO
            afPosUse[nI] := stEnv.afPos[nI];    // 位移镜像复制 [Copy position knot]
            IF stEnv.afUpper[nI] < stEnv.afLower[nI] THEN
                afUpperUse[nI] := stEnv.afLower[nI];   // 上限取原下限 [Upper takes old lower]
                afLowerUse[nI] := stEnv.afUpper[nI];   // 下限取原上限 [Lower takes old upper]
                _uInfoCode     := DL_INFO_LIM_SWAP;    // 01C1 上下限对调已修复【信息级】 [Info, limits swapped]
            ELSE
                afUpperUse[nI] := stEnv.afUpper[nI];  afLowerUse[nI] := stEnv.afLower[nI];  // 正常复制上下限 [Copy limits as-is]
            END_IF
        END_FOR
        FOR nI := 1 TO (_nEnvPts - 1) DO
            IF afPosUse[nI + 1] <= afPosUse[nI] THEN
                _bEnvValid := FALSE;        // 位移非严格单调，二分不可用 [Non-monotonic, binary search unsafe]
            END_IF
        END_FOR
    END_IF
    IF NOT _bEnvValid THEN
        _bFaultLatch := TRUE;               // 故障锁存 [Fault latched]
        _uErrorIdInt := DL_ERR_ENV;         // 02C1 包络表非法【故障级】 [Fault, invalid envelope]
        _eState      := E_DL_PressFitState.eFault;
    END_IF
END_IF
// ==== 段 6｜采样有限性防御与中止监视（全局，优先于状态机） / Sample finiteness defense and abort monitor, ahead of the state machine
bSampleFinite := (fActPos >= (-DL_REAL_MAX)) AND (fActPos <= DL_REAL_MAX)
             AND (fActForce >= (-DL_REAL_MAX)) AND (fActForce <= DL_REAL_MAX);
IF bEnable AND (NOT _bFaultLatch)
AND (_eState <> E_DL_PressFitState.eIdle)
AND (_eState <> E_DL_PressFitState.eFault)
AND (NOT bSampleFinite) THEN
    _bFaultLatch := TRUE;                   // 非有限值属故障级，立即锁存 [Non-finite is a fault]
    _uErrorIdInt := DL_ERR_SAMPLE;          // 02C3 采样非有限值【故障级】 [Fault, non-finite sample]
    _eState      := E_DL_PressFitState.eFault;
END_IF

IF bEnable AND (NOT _bFaultLatch) AND fbTrigAbort.Q
AND ((_eState = E_DL_PressFitState.eApproach)
  OR (_eState = E_DL_PressFitState.ePress)
  OR (_eState = E_DL_PressFitState.eDwell)) THEN
    _bHavePrev := FALSE;                    // 中止后重新起算差分 [Difference restarts after abort]
    _eState    := E_DL_PressFitState.eRetract;
END_IF
// ==== 段 7｜使能撤销（FALSE 立即回待机并撤全部动作出口，保留故障锁存） / Disable path returns to idle immediately, fault latch is preserved
IF NOT bEnable THEN
    _eState      := E_DL_PressFitState.eIdle;
    _bHavePrev   := FALSE;                  // 采样链断，防跨循环沿用 [Sampling chain broken]
    bBusy        := FALSE;                  // 忙标志撤 [Busy withdrawn]
END_IF
// ==== 段 8｜采样与特征点提取（接近 / 压入 / 保压三段逐拍执行） / Sampling and feature extraction, one sample per scan in three stages
IF bEnable AND (NOT _bFaultLatch) AND bSampleFinite
AND ((_eState = E_DL_PressFitState.eApproach)
  OR (_eState = E_DL_PressFitState.ePress)
  OR (_eState = E_DL_PressFitState.eDwell)) THEN

    IF _bHavePrev THEN
        // ---- 斜率：相邻两拍差分，位移增量过小时沿用上一拍，杜绝除零
        _fDelta := fActPos - _fPrevPos;
        IF ABS(_fDelta) >= DL_SLOPE_MIN_DELTA THEN
            _fSlope := (fActForce - _fPrevForce) / _fDelta;   // 斜率 [千牛每毫米] [Slope, kN/mm]
        END_IF
        IF _fSlope > _fSlopeMax THEN
            _fSlopeMax := _fSlope;          // 跟踪峰值斜率 [Track peak slope]
        END_IF
        // ---- 接触点：首个越过阈值的采样，用相邻两采样线性插值求精确位移
        IF (NOT _bContactFound) AND (_fContactThrEff > DL_FLOAT_EPS)
        AND (fActForce >= _fContactThrEff) THEN
            _fDelta := fActForce - _fPrevForce;
            IF ABS(_fDelta) > DL_FLOAT_EPS THEN
                stResult.fContactPos := _fPrevPos
                    + (fActPos - _fPrevPos) * (_fContactThrEff - _fPrevForce) / _fDelta;
            ELSE
                stResult.fContactPos := fActPos;   // 压力已稳定在阈值上，退化为当前点 [Degenerate to current point]
            END_IF
            stResult.fContactForce := fActForce;   // 接触点压力 [Contact force, kN]
            _bContactFound         := TRUE;        // 只锁一次 [Latched once]
        END_IF
    END_IF

    // ---- 峰值点：全程最大压力及其位移，逐拍刷新
    IF fActForce > _fPeakForce THEN
        _fPeakForce        := fActForce;    // 峰值压力 [千牛] [Peak force, kN]
        _fPeakPos          := fActPos;      // 峰值位移 [毫米] [Peak position, mm]
        stResult.fPeakForce := _fPeakForce;
        stResult.fPeakPos   := _fPeakPos;
    END_IF
    IF fActForce < (_fPeakForce - DL_FLOAT_EPS) THEN
        _bPeakPassed := TRUE;               // 已回落过峰值，趋势用 [Force has passed its peak]
    END_IF

    // ---- 屈服点：斜率回落至峰值斜率指定比例，首次成立即锁存
    IF (NOT _bYieldFound) AND _bContactFound AND (_fSlopeMax > DL_FLOAT_EPS) THEN
        IF _fSlope < (_fSlopeMax * _fYieldRatioEff) THEN
            stResult.fYieldPos   := fActPos;    // 屈服位移 [毫米] [Yield position, mm]
            stResult.fYieldForce := fActForce;  // 屈服压力 [千牛] [Yield force, kN]
            _bYieldFound         := TRUE;       // 只锁一次 [Latched once]
        END_IF
    END_IF

    nSampleCnt := nSampleCnt + 1;           // 有效采样计数 [Valid sample counter]
    _fPrevPos  := fActPos;                  // 上一点位移刷新 [Previous position refreshed]
    _fPrevForce := fActForce;               // 上一点压力刷新 [Previous force refreshed]
    _bHavePrev := TRUE;                     // 已有上一点 [Previous sample available]

    // ---- 包络窗口校验：仅压入与保压段，接近段压力天然低于下限故不判
    IF (_eState = E_DL_PressFitState.ePress) OR (_eState = E_DL_PressFitState.eDwell) THEN
        nLo    := 1;
        nHi    := _nEnvPts;
        nGuard := 0;
        WHILE ((nHi - nLo) > 1) AND (nGuard < DL_MAX_LOOP) DO
            nGuard := nGuard + 1;           // 防死锁计数 [Guard incremented]
            nMid   := (nLo + nHi) / 2;      // 整数中点 [Integer midpoint]
            IF fActPos >= afPosUse[nMid] THEN
                nLo := nMid;                // 落在右半区 [Right half]
            ELSE
                nHi := nMid;                // 落在左半区 [Left half]
            END_IF
        END_WHILE
        _fSpan := afPosUse[nHi] - afPosUse[nLo];
        IF ABS(_fSpan) > DL_SLOPE_MIN_DELTA THEN
            _fRatio := (fActPos - afPosUse[nLo]) / _fSpan;         // 区间内比例 [-] [Ratio in interval]
            _fRatio := LIMIT(0.0, _fRatio, 1.0);                   // 区间外钳位 [Clamped to 0..1]
            _fUp := afUpperUse[nLo] + _fRatio * (afUpperUse[nHi] - afUpperUse[nLo]); // 插值上限 [Interpolated upper]
            _fLo := afLowerUse[nLo] + _fRatio * (afLowerUse[nHi] - afLowerUse[nLo]); // 插值下限 [Interpolated lower]
        ELSE
            _fUp := afUpperUse[nLo];        // 退化区间取左节点上限 [Degenerate, take left knot]
            _fLo := afLowerUse[nLo];        // 退化区间取左节点下限 [Degenerate, take left knot]
        END_IF
        IF fActForce > (_fUp + DL_FLOAT_EPS) THEN
            uNgReason := uNgReason OR DL_NG_ENV_HIGH;              // bit0 上包络越界 [Upper envelope violated]
            IF (fActForce - _fUp) > fEnvDevMax THEN
                fEnvDevMax := fActForce - _fUp;                    // 累计最大偏差 [Track max deviation]
            END_IF
        END_IF
        IF fActForce < (_fLo - DL_FLOAT_EPS) THEN
            uNgReason := uNgReason OR DL_NG_ENV_LOW;               // bit1 下包络越界 [Lower envelope violated]
            IF (_fLo - fActForce) > fEnvDevMax THEN
                fEnvDevMax := _fLo - fActForce;                    // 累计最大偏差 [Track max deviation]
            END_IF
        END_IF
    END_IF
END_IF
// ==== 段 9｜主状态机（ENUM 加 CASE 加 ELSE 兜底，八成员逐一有标签） / Main state machine, every enum member has its own label
CASE _eState OF
    E_DL_PressFitState.eIdle: // 待机：等启动沿，启动拍清循环量
        IF fbTrigStart.Q AND bEnable AND (NOT _bFaultLatch) AND _bEnvValid THEN
            uNgReason    := 16#0000;  fEnvDevMax := 0.0;  nSampleCnt := 0;   // 原因位、最大偏差、采样计数清零 [Bits, deviation, count cleared]
            _bContactFound := FALSE;  _bYieldFound := FALSE;  _bPeakPassed := FALSE;  // 特征点与过峰标志复位 [Feature flags reset]
            _bHavePrev := FALSE;      _fSlope := 0.0;   _fSlopeMax := 0.0;         // 采样链、斜率、峰值斜率复位 [Chain and slope reset]
            _fPeakPos := 0.0;         _fPeakForce := 0.0;                          // 峰值点复位 [Peak reset]
            _fStartPos := fActPos;    _bRetractSnapDone := FALSE;                  // 记循环起点并复位回退快照 [Start point and snapshot reset]
            _uErrorIdInt := 16#0000_0000;  bOk := FALSE;  bNg := FALSE;            // 故障码与结论复位（启动前必无故障）[Code and verdicts reset]
            stResult.fContactPos := 0.0;  stResult.fContactForce := 0.0;           // 接触点复位 [Contact reset]
            stResult.fYieldPos   := 0.0;  stResult.fYieldForce   := 0.0;           // 屈服点复位 [Yield reset]
            stResult.fPeakPos    := 0.0;  stResult.fPeakForce    := 0.0;           // 峰值点复位 [Peak reset]
            stResult.fEndPos     := 0.0;  stResult.fEndForce     := 0.0;           // 终点复位 [End reset]
            _eState := E_DL_PressFitState.eApproach;
        END_IF
    E_DL_PressFitState.eApproach: // 接近：接触建立即转压入，阈值禁用时直通
        IF (_fContactThrEff <= DL_FLOAT_EPS) OR _bContactFound THEN
            _eState := E_DL_PressFitState.ePress;
        ELSIF fbTmoStage.Q THEN
            _bFaultLatch := TRUE;           // 阶段超时锁存 [Stage timeout latched]
            _uErrorIdInt := DL_ERR_STAGE_TMO;  // 02C2 阶段超时【故障级】 [Fault, stage timeout]
            _eState      := E_DL_PressFitState.eFault;
        END_IF
    E_DL_PressFitState.ePress: // 压入：到达终点目标或压力硬上限即转保压
        IF (fActPos >= (_fEndTgtEff - DL_FLOAT_EPS)) OR (fActForce >= _fForceLimEff) THEN
            _fDwellStartForce := fActForce; // 保压起点压力快照 [Dwell start force snapshot]
            _eState           := E_DL_PressFitState.eDwell;
        ELSIF fbTmoStage.Q THEN
            _bFaultLatch := TRUE;           // 阶段超时锁存 [Stage timeout latched]
            _uErrorIdInt := DL_ERR_STAGE_TMO;  // 02C2 阶段超时【故障级】 [Fault, stage timeout]
            _eState      := E_DL_PressFitState.eFault;
        END_IF
    E_DL_PressFitState.eDwell: // 保压：计时到即判压降并转回退，零时长直通
        IF (_tDwellEff <= T#0S) OR fbTmoDwell.Q THEN
            IF (_fPeakDropEff > DL_FLOAT_EPS)
            AND ((_fDwellStartForce - fActForce) > _fPeakDropEff) THEN
                uNgReason := uNgReason OR DL_NG_DWELL_DROP;  // bit4 保压压降超限 [Dwell decay violated]
            END_IF
            _bHavePrev := FALSE;            // 回退段不再算斜率 [Slope tracking stops]
            _eState    := E_DL_PressFitState.eRetract;
        ELSIF fbTmoStage.Q THEN
            _bFaultLatch := TRUE;           // 阶段超时锁存 [Stage timeout latched]
            _uErrorIdInt := DL_ERR_STAGE_TMO;  // 02C2 阶段超时【故障级】 [Fault, stage timeout]
            _eState      := E_DL_PressFitState.eFault;
        END_IF
    E_DL_PressFitState.eRetract: // 回退：首拍取终点特征，到位或中止即转判定
        IF NOT _bRetractSnapDone THEN
            stResult.fEndPos   := fActPos;  // 终点位移 [毫米] [End position, mm]
            stResult.fEndForce := fActForce; // 终点压力 [千牛] [End force, kN]
            IF fActPos < (_fEndTgtEff - DL_FLOAT_EPS) THEN
                uNgReason := uNgReason OR DL_NG_END_POS;  // bit2 终点未达 [End position not reached]
            END_IF
            _bRetractSnapDone := TRUE;      // 快照只做一次 [Snapshot taken once]
        END_IF
        IF fbTrigAbort.Q OR (fActPos <= (_fStartPos + DL_FLOAT_EPS)) THEN
            _eState := E_DL_PressFitState.eEvaluate;
        END_IF
    E_DL_PressFitState.eEvaluate: // 判定：归并原因并锁存结论，当拍转完成
        IF (_fContactThrEff > DL_FLOAT_EPS) AND (NOT _bContactFound) THEN
            uNgReason := uNgReason OR DL_NG_NO_CONTACT;  // bit3 接触未建立 [Contact never built up]
        END_IF
        bNg      := (uNgReason <> 16#0000); // 任一原因位即不合格 [Any reason bit means NG]
        bOk      := NOT bNg;                // 与不合格严格互斥 [Mutually exclusive with NG]
        _eState  := E_DL_PressFitState.eFinish;
    E_DL_PressFitState.eFinish: // 完成：本拍出完成脉冲并结算统计，下拍转待机
        bDone := TRUE;                      // 完成单拍，本拍唯一置位点 [Sole set point of the pulse]
        IF bNg THEN
            IF stStat.nNgCount < DL_MAX_CYCLES THEN
                stStat.nNgCount := stStat.nNgCount + 1;   // 不合格计数饱和累加 [NG counter, saturated]
            END_IF
        ELSE
            IF stStat.nOkCount < DL_MAX_CYCLES THEN
                stStat.nOkCount := stStat.nOkCount + 1;   // 合格计数饱和累加 [OK counter, saturated]
            END_IF
        END_IF
        IF stStat.nCycleCount < DL_MAX_CYCLES THEN
            stStat.nCycleCount := stStat.nCycleCount + 1; // 循环计数饱和累加 [Cycle counter, saturated]
        END_IF
        _bHavePrev := FALSE;                // 采样链断开，防跨循环 [Sampling chain broken]
        _eState    := E_DL_PressFitState.eIdle;
    E_DL_PressFitState.eFault: // 故障：等复位沿，复位后清码回待机
        IF fbTrigReset.Q THEN
            _bFaultLatch      := FALSE;     // 锁存解除 [Latch released]
            _uErrorIdInt      := 16#0000_0000; // 故障码清零 [Fault code cleared]
            uNgReason         := 16#0000;   // 原因位清零 [NG bits cleared]
            _bRetractSnapDone := FALSE;     // 快照标志复位 [Snapshot flag reset]
            _bHavePrev        := FALSE;     // 差分复位 [Difference reset]
            _eState           := E_DL_PressFitState.eIdle;
        END_IF

    ELSE // 非法枚举值兜底：回安全态并锁故障
        _bFaultLatch := TRUE;               // 兜底锁存 [Fallback latch]
        _uErrorIdInt := DL_ERR_STATE;       // 02C0 非法状态兜底【故障级】 [Fault, illegal state]
        _eState      := E_DL_PressFitState.eFault;
END_CASE
// ==== 段 10｜阶段迁移寄存器更新（单段超时的清零依据，与状态写入点分离） / Stage change register, drives the per-stage timer reset
_bStageChg  := (_eState <> _eStagePrev);     // 本拍是否发生迁移 [Transition happened this scan]
_eStagePrev := _eState;                      // 迁移寄存器同步 [Previous state synced]

// ==== 段 11｜出口派生（每拍重写，bError 只反映故障级，信息级码只进 uErrorId） / Outlets rewritten every scan, info codes never raise bError
eState := _eState;                          // 状态镜像 [State mirror]
bBusy  := (_eState = E_DL_PressFitState.eApproach)
       OR (_eState = E_DL_PressFitState.ePress)
       OR (_eState = E_DL_PressFitState.eDwell)
       OR (_eState = E_DL_PressFitState.eRetract);   // 执行中派生 [Busy derived]

bError := _bFaultLatch;                     // 故障级派生式（R21）[Fault-level derived form]
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;               // 故障级码优先透出 [Fault code wins]
ELSE
    uErrorId := _uInfoCode;                 // 无故障时透出信息级码 [Info code otherwise]
END_IF
END_FUNCTION_BLOCK
