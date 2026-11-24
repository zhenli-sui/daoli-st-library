(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WindingTensionCtrl
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 卷绕工艺族 · 锥度张力闭环
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（R_TRIG / LIMIT /
 *                         MIN / MAX / ABS / 标准类型转换）
 * 功能描述 (Function)   : 卷绕张力给定合成器。基准张力 = 目标张力 乘 锥度系数（随
 *                         机组直径由 1.0 平滑衰减到 1-K），摆辊位置误差经纯比例
 *                         修正环折算成张力修正量，两层相加后限幅输出，可直接送
 *                         比例阀或伺服转矩限幅入口。卷径可由线速度与角速度反算，
 *                         也可由外部注入。
 * 与既有件边界 (Boundary): FB_DL_WindingTraverse 做排线横动与卷径递推，不含张力
 *                         闭环；FC_DL_CoilDiameterCalc 只做单点几何反算（无状态、
 *                         无记忆）；本件是张力控制层，把二者的能力按需组装。本件
 *                         的相位枚举是工艺相位（闭环 / 开环降级），不是轴状态，轴
 *                         状态机仍归 I_DL_MotionAxis 的 PLCopen 语义，两者严禁合并。
 * 设计要点 (Key notes)  :
 *   ① 降级必须显式：摆辊反馈丢失时进 eOpenLoop 并上报 02D0，只输出锥度基准张力，
 *      不静默沿用上次闭环输出，也不静默把自己当闭环继续算；
 *   ② 修正加在基准上而非串接：摆辊失反馈时仍有锥度张力可用，失反馈不丢张力；
 *   ③ 锥度分母双重校验：满卷直径减卷芯直径小于容差即判退化，系数置 1.0 并上报
 *      01C1，绝不做出除以零的动作；系数再钳到 [1-K, 1.0]，K 自身先钳到 [0, 1]；
 *   ④ 卷径无效沿用上次有效值：转速低于门限时几何反算不可信（编码器低频量化），
 *      沿用上次有效值并累计连续无效次数，超限才升级为 02D1 锁存；
 *   ⑤ 无扰投切：开环恢复闭环时先给 PID 两拍跟踪（跟踪值 0，跟踪窗内过程值同步
 *      取基准以保偏差为零），跟踪结束积分残量为零，比例作用全量恢复；
 *      杜绝投切瞬间张力跳变；
 *   ⑥ 纯比例修正环：PID 实例积分与微分时间均给零，卷径时变工况下不会被积分饱和
 *      拖住。
 * 开源溯源 (Origin)     : 参考 lgf-technology、s7-motion 公开手册与 PLCopen 运动
 *                         控制规范中卷绕张力控制的功能分类与参数域（张力设定、锥度
 *                         系数、摆辊修正、卷径来源四段入口形态），只借分类、参数域
 *                         与命名组织，clean-room 实现，不构成衍生作品。引脚命名、
 *                         枚举、状态跃迁、故障码与合成公式 100% 自有。
 * 依赖     (Depends)    : DL_Algo 已入库件 FB_DL_PidController（拍级 PID，输出域
 *                         经 rOutMin / rOutMax 取 −1~+1 归一化）、
 *                         FC_DL_CoilDiameterCalc（几何反算，入口米制、出口米制，
 *                         本件负责毫米与米换算）。层次合法：Motion 依赖 Algo。
 * 状态迁移 (Transitions):
 *   eIdle      -- bEnable 且 bRun 且摆辊反馈有效 -----------> eClosedLoop（bInControl）
 *   eIdle      -- bEnable 且 bRun 且摆辊反馈无效 -----------> eOpenLoop（02D0 显式降级）
 *   eClosedLoop-- 摆辊反馈丢失 -----------------------------> eOpenLoop（02D0）
 *   eOpenLoop  -- 摆辊反馈连续 3 拍在物理域内 ---------------> eClosedLoop（跟踪投切）
 *   eClosedLoop-- 卷径连续无效次数超限 ---------------------> eFault（02D1 锁存）
 *   eOpenLoop  -- 卷径连续无效次数超限 ---------------------> eFault（02D1 锁存）
 *   任何运行态 -- NOT bEnable 或 NOT bRun ------------------> eIdle（输出 0，PID 复位）
 *   eFault     -- bReset 上升沿 ----------------------------> eIdle
 *   非法枚举值 -- CASE ELSE 兜底 ---------------------------> eFault（复用 02D1）
 * 码位表 (Error codes)  :
 *   16#0004_01C0【信息级】卷径无效（无有效反算或注入非法），已沿用上次有效值；
 *   16#0004_01C1【信息级】锥度系数分母退化或系数超界，已钳位；
 *   16#0004_01C2【信息级】张力输出限幅生效，输出被钳到张力域边界；
 *   16#0004_02D0【故障级】摆辊反馈丢失（非有限值或超机械行程），降级开环；
 *   16#0004_02D1【故障级】卷径连续无效超限（几何法已不可信），锁存待复位。
 *   信息级码只进 uErrorId，不置 bError；02D0 虽为故障级但只降级不停机（bError
 *   置位以提示上游），02D1 进 eFault 锁存。
 * 验收向量 (Acceptance):
 *   V1 锥度：K 0.5、卷芯 200 mm、满卷 1000 mm、实际 800 mm → 系数 0.625；
 *   V2 基准张力：同上且设定 100 N → 基准 62.5 N；
 *   V3 摆辊修正：误差 +2.0 mm、增益 0.5（归一化）、修正满量程 1.0 N → 修正 +1.0 N，
 *      输出 63.5 N；
 *   V4 满卷：实际 1000 mm、设定 100 N → 系数 0.5，基准 50.0 N；
 *   V5 卷径反算：线速 120 米每分、转速 60 转每分、直连 → 卷径约 636.6 mm；
 *   V6 卷径无效：转速 0 → 沿用上次有效卷径，码 01C0，bError 为 FALSE；
 *   V7 反馈丢失：摆辊位置 9999.0 mm → 输出等于基准（不加修正），码 02D0，
 *      bError 为 TRUE，bInControl 为 FALSE。
 * 已知限制 (Limits)     : ① 卷径反算用直连传动比 1.0（机械传动比应由卷径件入口
 *                         承载，本件不重复定义）；② 张力闭环是归一化纯比例修正，
 *                         不做卷径前馈，加减速段的动态偏差仍需现场调 fPidKp；
 *                         ③ 本件不构成安全功能，断带与超张力保护必须由硬件与
 *                         认证安全回路承担。
 * 规格偏离 (Deviation)  : ① 规格伪码把 fPidKp 原样送 PID，同时要求「摆辊正误差得
 *                         正修正」，二者符号相反；本实现送 −ABS(fPidKp)，依托 PID
 *                         件已文档化的「负增益即反作用」特性，令正误差得正修正，
 *                         与验收向量 V3 一致；② 规格成员名 nInvalidDiaCnt 定义类型
 *                         为 UDINT，与「无符号量 u 前缀」红线冲突，改名
 *                         uInvalidDiaCnt（语义不变）；③ 规格未规定故障态张力输出，
 *                         本实现取 0.0 安全值；④ 规格未覆盖「使能瞬间反馈已丢失」
 *                         路径，本实现显式进 eOpenLoop 并带 02D0，不得静默入闭环。
 * 红线自检 (Redline)    : R1 零全局变量表 / 零外部变量声明 / 零物理地址 ✓
 *                         R2 零占位符 ✓ ｜ R3 纯 IEC 61131-3 ✓
 *                         R4 防除零（锥度分母、转速门限）、防越界（卷径钳位）、
 *                         浮点容差（系数域与限幅判定）✓
 *                         R5 声明行 100% 中英双语同行注释 ✓
 *                         R6 ENUM + CASE 且 ELSE 兜底，四态各自有标签 ✓
 *                         R7 R_TRIG 与 PID 实例均在主体无条件刷新 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 11 · DL_Motion 卷绕张力族开族件）
 *   2026-11-15  v1.0.1  R11 总监终审修复：跟踪拍只置位不递减（bTrack 恒真致修正恒零、
 *                       闭环退化为开环），补 eClosedLoop 逐拍递减；跟踪窗内过程值改取
 *                       基准，消除 PID 反算积分残量（原跟踪结束 fInt 恒等于负比例项，
 *                       V3 修正 +1.0 N 不可达）；02D1 判据由大于改为大于等于，与饱和
 *                       计数上限自洽（原判据在计数封顶时永假，锁存永不触发）
 *   2026-11-15  v1.0.1  R11 director final review fix: the tracking counter now decrements
 *                       every closed-loop scan, the process value follows the reference
 *                       inside the tracking window to keep the back-calculated integral at
 *                       zero, and the 02D1 test uses greater-or-equal against the
 *                       saturating counter so the latch can actually engage
 *============================================================================*)
(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   // fbTensionPid 与 stStat 均由调用方持有，跨周期传入
 *   fbTension(bEnable := bLineRun, bReset := bFaultReset, bRun := bWinding,
 *             fTensionSet := fTensionRecipe, fDancerPos := fDancerFeedback,
 *             fDancerRef := 0.0, fAxisSpeedRpm := fWinderRpm,
 *             fLineSpeed := fLineSpeedAct, fCoreDia := 200.0,
 *             fDiaMax := 1000.0, bUseInjectedDia := FALSE,
 *             fTaperK := 0.50, fPidKp := 0.5, fTrimSpan := 5.0,
 *             fTensionMin := 0.0, fTensionMax := 300.0);
 *   fValveCmd := fbTension.fTensionOut;
 *   注：fbTensionPid 只允许本块调用，外部不要再对该实例赋值引脚，否则归一化
 *       输出域会被覆盖，修正量会放大一百倍。
 *----------------------------------------------------------------------------*)
(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 fTaperK 给 0 表示无锥度（全程恒张力），给 1 表示满卷张力降到零，后者在
 *     实际工艺中通常不可用，建议上限取 0.7。
 *   2 摆辊反馈量程必须与 fDancerRef 同一基准：本块用绝对值 500 mm 判机械不可能
 *     值，若机械行程超过 500 mm，请把 DL_DANCER_LIMIT 调大后重新入库。
 *   3 卷径连续无效 50 次即锁存 02D1：停机不转时卷径无效属正常（信息级 01C0），
 *     只要 bRun 撤除就不会累计，现场不要把停机误判为故障。
 *   4 开环降级期间张力只随卷径变化，摆辊会漂到机械限位，现场必须给摆辊限位
 *     开关并把其信号接入上位联锁，本块不做摆辊位置保护。
 *   5 张力上下限写反时本块自动对调，但不会报警，调试期请核对 fTensionMin 与
 *     fTensionMax 的实际取值。
 *----------------------------------------------------------------------------*)
(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TensionPhase（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 张力工艺相位。eOpenLoop 是显式降级态而非故障态，二者不可混用。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_TensionPhase :
(
    eIdle       := 0,   // 空闲：未使能或未运行，张力输出 0，PID 复位 / Idle: disabled or not running, tension output zero, PID reset
    eOpenLoop   := 10,  // 开环降级：摆辊反馈不可用，只出锥度基准张力 / Open loop degraded: dancer feedback unusable, taper base only
    eClosedLoop := 20,  // 闭环运行：基准张力加摆辊比例修正 / Closed loop: base tension plus dancer proportional trim
    eFault      := 99   // 故障锁存：卷径几何法不可信，仅复位沿退出 / Fault latched: diameter geometry untrusted, exits on reset edge only
) UINT;
END_TYPE
(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_WindingStat（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 卷绕统计，由调用方持有并可持久化到配方域。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_WindingStat :
STRUCT
    fTensionAvg     : REAL;   // 张力滑动均值 [N]，一阶指数平均，仅闭环期更新 / Tension running average in newtons, updated in closed loop only
    uInvalidDiaCnt  : UDINT;  // 卷径连续无效次数 [次]，任一有效反算即清零 / Consecutive invalid diameter count, cleared by any valid result
    tRunTime        : TIME;   // 闭环累计运行时长 [ms]，按任务周期累加 / Accumulated closed-loop runtime in milliseconds
END_STRUCT
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_WindingTensionCtrl
 * 调用约定: 每扫描周期无条件调用一次；PID 实例在主体末尾无条件调用。
 * 无状态泄漏: 状态驻留实例私有 VAR 与调用方持有的 stStat / fbTensionPid。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_WindingTensionCtrl
VAR_INPUT
    bEnable          : BOOL := FALSE;        // 总使能 [BOOL]，FALSE 时输出 0 并复位 PID / Master enable, FALSE zeroes the output and resets the PID
    bReset           : BOOL := FALSE;        // 复位 [BOOL]，上升沿复位故障、计数与 PID / Reset, rising edge clears fault, counters and the PID
    bRun             : BOOL := FALSE;        // 卷绕运行中 [BOOL]，FALSE 时张力给定保持 0 / Winding running flag, FALSE holds the tension command at zero
    fTensionSet      : REAL := 0.0;          // 目标张力（满卷前基准）[N]，域 0.0~500.0 / Base tension setpoint in newtons, range zero to five hundred
    fDancerPos       : REAL := 0.0;          // 摆辊实际位置 [mm]，0 为机械中位，绝对值超 500 判失效 / Dancer actual position in millimetres, zero at mechanical centre
    fDancerRef       : REAL := 0.0;          // 摆辊中位基准 [mm]，非有限值按 0 处理 / Dancer centre reference in millimetres, non-finite treated as zero
    fAxisSpeedRpm    : REAL := 0.0;          // 卷轴转速 [转每分]，低于 1.0 视为不可反算 / Winder shaft speed in revolutions per minute, below one is untrusted
    fLineSpeed       : REAL := 0.0;          // 线速度 [米每分]，与卷径件入口同单位 / Line speed in metres per minute, same unit as the diameter function input
    fCoreDia         : REAL := 200.0;        // 卷芯直径 [mm]，域 10.0~3000.0 / Core diameter in millimetres, range ten to three thousand
    fDiaMax          : REAL := 1000.0;       // 满卷直径 [mm]，必须大于卷芯直径，否则锥度退化 / Full roll diameter in millimetres, must exceed the core diameter
    fDiaInjected     : REAL := 0.0;          // 外部注入卷径 [mm]，视觉或上位机来源 / Injected diameter in millimetres from vision or a host system
    bUseInjectedDia  : BOOL := FALSE;        // 卷径来源选择 [BOOL]，TRUE 用注入值，FALSE 由速度比反算 / Diameter source, TRUE uses the injected value
    fThickness       : REAL := 0.10;         // 材料厚度 [mm]，供卷径件层数积分 / Material thickness in millimetres, used by the layer integral
    fTaperK          : REAL := 0.50;         // 锥度系数 [无量纲 0~1]，满卷张力降至 1-K 倍 / Taper coefficient, full roll tension falls to one minus K
    fPidKp           : REAL := 0.5;          // 摆辊修正归一化增益 [每毫米]，输出域 −1~+1，取绝对值后反作用 / Normalised dancer gain per millimetre, absolute value used with reverse action
    fTrimSpan        : REAL := 1.0;          // 修正满量程 [N]，归一化输出乘该值即张力修正 / Trim span in newtons, the normalised output multiplied by this value
    fTensionMin      : REAL := 0.0;          // 张力输出下限 [N]，与上限对调时自动修复 / Tension lower limit in newtons, swapped limits are repaired
    fTensionMax      : REAL := 500.0;        // 张力输出上限 [N]，等于下限时输出被钉死 / Tension upper limit in newtons, an equal limit pins the output
END_VAR
VAR_OUTPUT
    fTensionOut      : REAL := 0.0;          // 张力给定输出 [N]，送比例阀或转矩限幅入口 / Tension command output in newtons for a proportional valve or torque limit
    fDiaAct          : REAL := 0.0;          // 当前生效卷径 [mm]，已钳入物理域 / Effective diameter in millimetres, clamped into the physical range
    fTaperFactor     : REAL := 1.0;          // 实际锥度系数 [无量纲]，域 1-K~1.0 / Effective taper factor, range one minus K to one
    fDancerErr       : REAL := 0.0;          // 摆辊位置误差 [mm]，等于实测减基准 / Dancer position error in millimetres, measured minus reference
    eState           : E_DL_TensionPhase := E_DL_TensionPhase.eIdle; // 主状态机当前态 [枚举] / Current state of the main state machine
    bInControl       : BOOL := FALSE;        // 张力闭环生效 [BOOL]，仅 eClosedLoop 为 TRUE / Closed-loop tension active, TRUE only in the closed-loop state
    bError           : BOOL := FALSE;        // 故障标志 [BOOL]，故障级码或降级态置位，信息级码不置位 / Fault flag, set by fault-level codes or the degraded state
    uErrorId         : UDINT := 0;           // 事件或故障码 [段位 0004_01Cx 与 0004_02Dx]，0 表示无事件 / Event or fault code in the 0004 bands, zero means none
    fDiaLastValid    : REAL := 0.0;          // 最近一次有效卷径 [mm]，0 表示尚无有效值 / Last valid diameter in millimetres, zero means none yet
END_VAR
VAR_IN_OUT
    fbTensionPid     : FB_DL_PidController;  // 摆辊修正环 PID 实例 [FB]，由调用方持有且只允许本块调用 / Dancer trim PID instance held by the caller and driven only by this block
    stStat           : ST_DL_WindingStat;    // 跨周期卷绕统计 [结构体]，由调用方持有 / Persistent winding statistics held by the caller
END_VAR
VAR
    bInit            : BOOL := FALSE;        // 首扫完成标志 [BOOL]，初值 FALSE，判据恒为 NOT bInit / First-scan done flag, initial FALSE, judged by NOT bInit
    bDancerOk        : BOOL := FALSE;        // 摆辊反馈有效判据 [BOOL]，逐拍重算 / Dancer feedback verdict, recomputed every scan
    bDancerLost      : BOOL := FALSE;        // 摆辊反馈丢失标志 [BOOL]，降级原因量 / Dancer feedback lost flag, the explicit degradation reason
    bAvgInit         : BOOL := FALSE;        // 张力均值首样本标志 [BOOL]，避免从 0 起算 / Tension average first-sample flag, avoids averaging from zero
    nRecoverCnt      : INT := 0;             // 反馈恢复连续拍计数 [拍]，满 3 拍回闭环 / Consecutive good-feedback counter, three scans restore closed loop
    nTrackSync       : INT := 0;             // 投切跟踪剩余拍数 [拍]，大于 0 时 PID 跟踪 / Remaining tracking scans, the PID tracks while above zero
    fDancerPosEff    : REAL := 0.0;          // 喂给 PID 的摆辊位置 [mm]，失效时以基准值替代 / Dancer position fed to the PID, replaced by the reference when invalid
    fDancerRefEff    : REAL := 0.0;          // 生效摆辊基准 [mm]，已做非有限值防御 / Effective dancer reference after the non-finite defence
    fPidPvEff        : REAL := 0.0;          // 喂给 PID 的过程值 [mm]，跟踪窗口内以基准替代 / Process value fed to the PID, replaced by the reference inside the tracking window
    fTensionSetEff   : REAL := 0.0;          // 生效目标张力 [N]，已做非有限值防御 / Effective tension setpoint after the non-finite defence
    fTrimSpanEff     : REAL := 1.0;          // 生效修正满量程 [N]，取绝对值 / Effective trim span in newtons, absolute value used
    fPidKpEff        : REAL := 0.0;          // 送入 PID 的增益 [每毫米]，取负值实现反作用 / Gain passed to the PID, negated for reverse action
    fCoreDiaEff      : REAL := 200.0;        // 生效卷芯直径 [mm]，钳入物理域 / Effective core diameter in millimetres, clamped into the physical range
    fDiaMaxEff       : REAL := 1000.0;       // 生效满卷直径 [mm]，钳入物理域 / Effective full-roll diameter in millimetres, clamped into the physical range
    fTaperKEff       : REAL := 0.50;         // 生效锥度系数 [无量纲 0~1]，越界钳位 / Effective taper coefficient, clamped into zero to one
    fTaperLow        : REAL := 0.50;         // 锥度系数下限 [无量纲]，等于 1 减生效锥度 / Taper factor lower bound, equal to one minus the effective coefficient
    fTaperRaw        : REAL := 1.0;          // 未钳位的锥度系数 [无量纲]，用于超界判定 / Unclamped taper factor used for the out-of-range test
    fDiaCalc         : REAL := 0.0;          // 卷径反算结果 [mm]，已做米转毫米 / Diameter result in millimetres after the metre conversion
    fDiaLReal        : LREAL := 0.0;         // 卷径件出口绑定值 [米]，LREAL 精度承接 / Diameter bound from the function output in metres at LREAL precision
    fDiaRet          : LREAL := 0.0;         // 卷径件返回值 [米]，函数返回即滤波后卷径 / Diameter function return value in metres, the filtered diameter
    fBase            : REAL := 0.0;          // 锥度基准张力 [N]，等于设定乘锥度系数 / Taper base tension in newtons, setpoint times the taper factor
    fTrim            : REAL := 0.0;          // 摆辊张力修正 [N]，闭环时等于归一化输出乘满量程 / Dancer trim in newtons, the normalised output times the span
    fRawCmd          : REAL := 0.0;           // 未限幅的张力指令 [N]，限幅前中间量 / Unlimited tension command in newtons before clamping
    fLimLow          : REAL := 0.0;          // 生效张力下限 [N]，已做上下对调修复 / Effective tension lower limit after repair
    fLimHigh         : REAL := 500.0;        // 生效张力上限 [N]，已做上下对调修复 / Effective tension upper limit after repair
    fAvgAlpha        : REAL := 0.0;          // 张力均值一阶权重 [无量纲]，由任务周期与时间常数算出 / First-order weight of the tension average
    uErrInfo         : UDINT := 0;           // 本拍瞬时信息码 [段位 0004_01C0~01C2]，逐拍重算 / Transient info code recomputed every scan
    uErrFault        : UDINT := 0;           // 锁存故障码 [段位 0004_02D1]，仅复位清除 / Latched fault code, cleared by reset only
    fbTrigReset      : R_TRIG;               // 复位上升沿检测实例 / Rising edge detector for the reset flag
    fbTrigRun        : R_TRIG;               // 运行上升沿检测实例 / Rising edge detector for the running flag
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : REAL := 1.0E-6;       // 浮点判等与判零容差 [无量纲，按比较量量纲同值使用] / Float equality and zero tolerance
    DL_INF_MAX       : REAL := 1.0E30;       // 有限值幅值上限 [无量纲，按各量量纲同值使用] / Finite magnitude upper bound
    DL_RPM_MIN       : REAL := 1.0;          // 卷径反算最小转速 [转每分]，低于此值不反算 / Minimum speed for the inverse diameter calculation
    DL_DIA_MIN       : REAL := 10.0;         // 卷径物理下限 [mm] / Diameter physical lower bound in millimetres
    DL_DIA_MAX       : REAL := 3000.0;       // 卷径物理上限 [mm] / Diameter physical upper bound in millimetres
    DL_DANCER_LIMIT  : REAL := 500.0;        // 摆辊机械行程上限 [mm]，绝对值超此判失效 / Dancer mechanical travel bound in millimetres
    DL_TASK_CYCLE    : REAL := 0.010;        // 主任务周期 [s]，供卷径件变化率换算 / Main task cycle in seconds for the diameter rate
    DL_TASK_TIME     : TIME := T#10MS;       // 主任务周期时间量 [ms]，供运行时长累加 / Main task cycle as a time value for runtime accumulation
    DL_FILTER_TAU    : REAL := 0.50;         // 卷径一阶低通时间常数 [s] / Diameter low-pass time constant in seconds
    DL_INVALID_MAX   : UDINT := 50;          // 卷径连续无效次数上限 [次]，超限锁存 02D1 / Consecutive invalid diameter limit before latching
    DL_RECOVER_N     : INT := 3;             // 反馈恢复确认拍数 [拍]，连续满足才回闭环 / Consecutive good scans required to restore the closed loop
    DL_AVG_TAU       : REAL := 1.0;          // 张力均值时间常数 [s]，一阶平均用 / Tension average time constant in seconds
END_VAR
(*------------------------------------------------------------------------------
 * 段 1｜边沿实例无条件周期刷新（红线 R7：严禁置于 IF 或 CASE 分支内）｜Unconditional edge refresh, never placed inside IF or CASE branches
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigRun(CLK := bRun);
(*------------------------------------------------------------------------------
 * 段 2｜瞬时输出与瞬时码预清零（出口只置位，跨拍残留一律在入口清）｜Pre-clear transient outputs and info codes at scan entry
 *-----------------------------------------------------------------------------*)
bInControl := FALSE;                        // 闭环生效标志预清零 [BOOL] / Pre-clear the closed-loop flag
fTrim      := 0.0;                          // 修正量预清零，开环与空闲不得继承上次值 [N] / Pre-clear the trim so open loop never inherits it
uErrInfo   := 0;                            // 瞬时信息码预清零 [码] / Pre-clear the transient info code
(*------------------------------------------------------------------------------
 * 段 3｜参数域修复（引脚可在线改，故逐拍重算；域非法只钳位不锁存）｜Parameter domain repair, clamping only without latching
 *-----------------------------------------------------------------------------*)
IF fTensionMax < fTensionMin THEN
    fLimLow  := fTensionMax;                // 张力域上下对调修复：下限取原上限 [N] / Repaired lower limit takes the original upper
    fLimHigh := fTensionMin;                // 张力域上下对调修复：上限取原下限 [N] / Repaired upper limit takes the original lower
ELSE
    fLimLow  := fTensionMin;                // 合法下限直通 [N] / Valid lower limit passed through
    fLimHigh := fTensionMax;                // 合法上限直通 [N] / Valid upper limit passed through
END_IF

IF (fTensionSet <> fTensionSet) OR (ABS(fTensionSet) > DL_INF_MAX) THEN
    fTensionSetEff := 0.0;                  // 目标张力非有限 → 0，宁可失张力也不给非法值 [N] / Non-finite setpoint falls back to zero
ELSE
    fTensionSetEff := fTensionSet;          // 合法目标张力直通 [N] / Valid setpoint passed through
END_IF

IF (fTrimSpan <> fTrimSpan) OR (ABS(fTrimSpan) > DL_INF_MAX) THEN
    fTrimSpanEff := 0.0;                    // 修正满量程非有限 → 0，等效关闭摆辊修正 [N] / Non-finite trim span disables the dancer trim
ELSE
    fTrimSpanEff := ABS(fTrimSpan);         // 修正满量程取绝对值 [N] / Absolute trim span
END_IF
// 送入 PID 的增益取负实现反作用：摆辊正误差（上偏）对应增张力，与验收向量 V3 一致
IF (fPidKp <> fPidKp) OR (ABS(fPidKp) > DL_INF_MAX) THEN
    fPidKpEff := 0.0;                       // 增益非有限 → 0，等效关闭修正 [每毫米] / Non-finite gain disables the trim
ELSE
    fPidKpEff := -ABS(fPidKp);              // 取绝对值后取负，负增益即 PID 件的反作用语义 [每毫米] / Absolute value negated for reverse action
END_IF

IF (fDancerRef <> fDancerRef) OR (ABS(fDancerRef) > DL_DANCER_LIMIT) THEN
    fDancerRefEff := 0.0;                   // 摆辊基准非法 → 回机械中位 0 [mm] / Illegal reference falls back to the mechanical centre
ELSE
    fDancerRefEff := fDancerRef;            // 合法基准直通 [mm] / Valid reference passed through
END_IF

IF (fCoreDia <> fCoreDia) OR (ABS(fCoreDia) > DL_INF_MAX) THEN
    fCoreDiaEff := DL_DIA_MIN;              // 卷芯直径非法 → 回物理下限 [mm] / Illegal core diameter falls back to the physical lower bound
ELSE
    fCoreDiaEff := LIMIT(DL_DIA_MIN, fCoreDia, DL_DIA_MAX); // 卷芯直径钳入物理域 [mm] / Core diameter clamped into the physical range
END_IF

IF (fDiaMax <> fDiaMax) OR (ABS(fDiaMax) > DL_INF_MAX) THEN
    fDiaMaxEff := DL_DIA_MAX;               // 满卷直径非法 → 回物理上限 [mm] / Illegal full-roll diameter falls back to the physical upper bound
ELSE
    fDiaMaxEff := LIMIT(DL_DIA_MIN, fDiaMax, DL_DIA_MAX);   // 满卷直径钳入物理域 [mm] / Full-roll diameter clamped into the physical range
END_IF
// 锥度系数域校验：非有限或越出 0~1 一律钳位并置信息级 01C1，绝不带非法系数进公式
IF (fTaperK <> fTaperK) OR (ABS(fTaperK) > DL_INF_MAX) THEN
    fTaperKEff := 0.0;                      // 非有限系数按无锥度处理，先判非数再钳位，避免 NaN 穿过 LIMIT [无量纲] / Non-finite coefficient treated as no taper
    IF bEnable AND bRun THEN
        uErrInfo := 16#0004_01C1;           // 【信息级】锥度系数非有限已按无锥度处理 / Info: non-finite taper coefficient replaced
    END_IF
ELSIF (fTaperK < 0.0) OR (fTaperK > 1.0) THEN
    fTaperKEff := LIMIT(0.0, fTaperK, 1.0); // 越界钳到 0~1 双向钳位 [无量纲] / Two-sided clamp into zero to one
    IF bEnable AND bRun THEN
        uErrInfo := 16#0004_01C1;           // 【信息级】锥度系数超界已钳位 / Info: taper coefficient clamped
    END_IF
ELSE
    fTaperKEff := fTaperK;                  // 合法锥度系数直通 [无量纲] / Valid taper coefficient passed through
END_IF
// 张力均值一阶权重：由任务周期与时间常数算出，分母恒正（时间常数有下限保证）
fAvgAlpha := DL_TASK_CYCLE / (DL_AVG_TAU + DL_TASK_CYCLE); // 均值权重 [无量纲] / First-order average weight
(*------------------------------------------------------------------------------
 * 段 4｜首扫装载（R19 唯一合法范式：bInit 初值 FALSE，判据 NOT bInit）｜First-scan load, the only accepted initialisation pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    stStat.fTensionAvg    := 0.0;           // 张力均值清零，等首个闭环样本直取 [N] / Clear the tension average until the first closed-loop sample
    stStat.uInvalidDiaCnt := 0;             // 卷径无效计数清零 [次] / Clear the invalid diameter counter
    stStat.tRunTime       := T#0S;          // 运行时长清零 [ms] / Clear the accumulated runtime
    fDiaLastValid         := 0.0;           // 有效卷径历史清零，0 表示尚无有效值 [mm] / Clear the valid diameter history
    bDancerLost           := FALSE;         // 反馈丢失标志清零 [BOOL] / Clear the feedback lost flag
    nRecoverCnt           := 0;             // 恢复计数清零 [拍] / Clear the recovery counter
    nTrackSync            := 0;             // 投切跟踪计数清零 [拍] / Clear the tracking counter
    bAvgInit              := FALSE;         // 均值首样本标志清零 [BOOL] / Clear the average first-sample flag
    bInit                 := TRUE;          // 首扫完成置位 [BOOL] / First scan completed
END_IF
(*------------------------------------------------------------------------------
 * 段 5｜复位（清故障、计数与降级标志；PID 由复位引脚同步清除；参数域不动）｜Reset clears the latched fault, counters and degradation flags
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    uErrFault             := 0;             // 锁存故障码清零 [码] / Clear the latched fault code
    uErrInfo              := 0;             // 瞬时信息码清零 [码] / Clear the transient info code
    stStat.uInvalidDiaCnt := 0;             // 卷径无效计数清零，允许重新起步 [次] / Clear the invalid diameter counter so production can restart
    bDancerLost           := FALSE;         // 反馈丢失标志清零 [BOOL] / Clear the feedback lost flag
    nRecoverCnt           := 0;             // 恢复计数清零 [拍] / Clear the recovery counter
    nTrackSync            := 0;             // 跟踪计数清零 [拍] / Clear the tracking counter
    eState                := E_DL_TensionPhase.eIdle; // 回空闲，等待使能与运行条件 [枚举] / Back to idle waiting for enable and run
END_IF

IF fbTrigRun.Q THEN
    bAvgInit := FALSE;                      // 新一次卷绕启动：张力均值重新直取首样本，不继承上一卷 [BOOL] / New run restarts the tension average instead of inheriting the last roll
END_IF
(*------------------------------------------------------------------------------
 * 段 6｜摆辊反馈有效性判定（非有限值或超机械行程即判失效，显式标记原因）｜Dancer feedback verdict with an explicit reason flag
 *-----------------------------------------------------------------------------*)
bDancerOk := NOT ((fDancerPos <> fDancerPos) OR (ABS(fDancerPos) > DL_DANCER_LIMIT));
IF bDancerOk THEN
    fDancerPosEff := fDancerPos;            // 有效反馈直通，喂给 PID [mm] / Valid feedback passed through to the PID
ELSE
    fDancerPosEff := fDancerRefEff;         // 失效反馈以基准替代，令 PID 偏差为零且 NaN 不扩散 [mm] / Substitute the reference so the PID error stays zero
END_IF
fDancerErr := fDancerPosEff - fDancerRefEff; // 摆辊位置误差，实测减基准 [mm] / Dancer position error, measured minus reference
(*------------------------------------------------------------------------------
 * 段 7｜卷径获取（注入优先；否则按速度比反算；无效沿用上次有效值并计数）｜Diameter acquisition with reuse-on-invalid and consecutive counting
 *-----------------------------------------------------------------------------*)
IF bEnable AND bRun THEN
    IF bUseInjectedDia THEN
        IF (fDiaInjected <> fDiaInjected) OR (ABS(fDiaInjected) > DL_INF_MAX) THEN
            IF fDiaLastValid > DL_FLOAT_EPS THEN
                fDiaAct := fDiaLastValid;   // 注入值非法 → 沿用上次有效卷径 [mm] / Illegal injection reuses the last valid diameter
            ELSE
                fDiaAct := fCoreDiaEff;     // 无历史有效值 → 以卷芯直径兜底，杜绝零卷径除零 [mm] / Fall back to the core diameter when no history exists
            END_IF
            IF stStat.uInvalidDiaCnt < DL_INVALID_MAX THEN
                stStat.uInvalidDiaCnt := stStat.uInvalidDiaCnt + 1; // 连续无效计数累加，封顶后靠 02D1 锁存 [次] / Saturating invalid counter
            END_IF
            uErrInfo := 16#0004_01C0;       // 【信息级】卷径无效已沿用上次有效值 / Info: invalid diameter, last valid value reused
        ELSE
            fDiaAct := LIMIT(DL_DIA_MIN, fDiaInjected, DL_DIA_MAX); // 注入卷径钳入物理域 [mm] / Injected diameter clamped into the physical range
            IF (fDiaInjected < DL_DIA_MIN) OR (fDiaInjected > DL_DIA_MAX) THEN
                uErrInfo := 16#0004_01C0;   // 【信息级】注入卷径超物理域已钳位 / Info: injected diameter clamped
            END_IF
            fDiaLastValid         := fDiaAct; // 记录有效卷径 [mm] / Record the valid diameter
            stStat.uInvalidDiaCnt := 0;     // 有效值出现即清零连续无效计数 [次] / Reset the consecutive counter on any valid value
        END_IF
    ELSE
        IF (fAxisSpeedRpm <> fAxisSpeedRpm) OR (ABS(fAxisSpeedRpm) > DL_INF_MAX)
           OR (fAxisSpeedRpm < DL_RPM_MIN)
           OR (fLineSpeed <> fLineSpeed) OR (ABS(fLineSpeed) > DL_INF_MAX) THEN
            IF fDiaLastValid > DL_FLOAT_EPS THEN
                fDiaAct := fDiaLastValid;   // 低速或入参非法 → 沿用上次有效卷径 [mm] / Low speed or illegal input reuses the last valid diameter
            ELSE
                fDiaAct := fCoreDiaEff;     // 无历史有效值 → 以卷芯直径兜底 [mm] / Fall back to the core diameter
            END_IF
            IF stStat.uInvalidDiaCnt < DL_INVALID_MAX THEN
                stStat.uInvalidDiaCnt := stStat.uInvalidDiaCnt + 1; // 连续无效计数累加 [次] / Saturating invalid counter
            END_IF
            uErrInfo := 16#0004_01C0;       // 【信息级】卷径无效已沿用上次有效值 / Info: invalid diameter, last valid value reused
        ELSE
            // 按已入库卷径件的真实契约调用：入口为米制与秒制，出口绑定滤波后卷径（米）
            fDiaRet := FC_DL_CoilDiameterCalc(
                fLineSpeed := REAL_TO_LREAL(fLineSpeed),              // 米每分，与本件引脚同单位 / Metres per minute, same unit as this pin
                fShaftRpm  := REAL_TO_LREAL(fAxisSpeedRpm),           // 转每分，与卷轴转速同单位 / Revolutions per minute
                fGearRatio := 1.0,                                    // 直连，机械传动比由卷径件入口承载 / Direct drive, the gear ratio belongs to the function input
                fCoreDia   := REAL_TO_LREAL(fCoreDiaEff) / 1000.0,     // 毫米转米 / Millimetres converted to metres
                fThickness := REAL_TO_LREAL(fThickness) / 1000.0,     // 毫米转米 / Millimetres converted to metres
                fPrevDia   := REAL_TO_LREAL(fDiaLastValid) / 1000.0,  // 毫米转米，0 表示无历史 / Millimetres converted to metres, zero means no history
                fTaskCycle := REAL_TO_LREAL(DL_TASK_CYCLE),           // 任务周期，秒 / Task cycle in seconds
                bFilterEn  := TRUE,                                   // 卷径低通使能 / Diameter low-pass enabled
                fFilterTau := REAL_TO_LREAL(DL_FILTER_TAU),           // 低通时间常数，秒 / Low-pass time constant in seconds
                fDia       => fDiaLReal );                            // 出口绑定：滤波后卷径，米 / Bound output, filtered diameter in metres
            fDiaCalc := LREAL_TO_REAL(fDiaLReal * 1000.0);            // 米转毫米，显式转换，出口绑定优先 / Metres converted to millimetres, the bound output is preferred
            IF (fDiaLReal <> fDiaLReal) AND (fDiaRet = fDiaRet) THEN
                fDiaCalc := LREAL_TO_REAL(fDiaRet * 1000.0);          // 绑定值非法而返回值有效 → 退回返回值，兼容平台绑定差异 / Bound value illegal, fall back to the function return
            END_IF
            IF (fDiaCalc <> fDiaCalc) OR (fDiaCalc <= DL_FLOAT_EPS) THEN
                IF fDiaLastValid > DL_FLOAT_EPS THEN
                    fDiaAct := fDiaLastValid; // 反算结果不可用 → 沿用上次有效卷径 [mm] / Unusable result reuses the last valid diameter
                ELSE
                    fDiaAct := fCoreDiaEff;   // 无历史有效值 → 以卷芯直径兜底 [mm] / Fall back to the core diameter
                END_IF
                IF stStat.uInvalidDiaCnt < DL_INVALID_MAX THEN
                    stStat.uInvalidDiaCnt := stStat.uInvalidDiaCnt + 1; // 连续无效计数累加 [次] / Saturating invalid counter
                END_IF
                uErrInfo := 16#0004_01C0;   // 【信息级】反算结果不可用已沿用上次有效值 / Info: unusable result, last valid value reused
            ELSE
                fDiaAct := LIMIT(DL_DIA_MIN, fDiaCalc, DL_DIA_MAX); // 反算卷径钳入物理域 [mm] / Computed diameter clamped into the physical range
                fDiaLastValid         := fDiaAct; // 记录有效卷径 [mm] / Record the valid diameter
                stStat.uInvalidDiaCnt := 0;       // 有效反算即清零连续无效计数 [次] / Reset the consecutive counter on a valid result
            END_IF
        END_IF
    END_IF
ELSE
    IF fDiaLastValid > DL_FLOAT_EPS THEN
        fDiaAct := fDiaLastValid;           // 非运行态不反算，沿用上次有效卷径 [mm] / Not running, reuse the last valid diameter
    ELSE
        fDiaAct := fCoreDiaEff;             // 非运行且无历史 → 以卷芯直径兜底 [mm] / Not running without history falls back to the core diameter
    END_IF
END_IF

// 卷径输出钳位兜底：任何路径都不得把非法值送出（防御性二次确认）
IF (fDiaAct <> fDiaAct) OR (fDiaAct < DL_DIA_MIN) OR (fDiaAct > DL_DIA_MAX) THEN
    fDiaAct := LIMIT(DL_DIA_MIN, fDiaAct, DL_DIA_MAX); // 卷径域二次钳位 [mm] / Second-stage diameter clamp
    IF fDiaAct <> fDiaAct THEN
        fDiaAct := fCoreDiaEff;             // 仍为非法值 → 回卷芯直径 [mm] / Still illegal, fall back to the core diameter
    END_IF
END_IF
(*------------------------------------------------------------------------------
 * 段 8｜锥度系数（分母双重校验，系数双向钳位，退化或超界置 01C1）｜Taper factor with denominator guard and two-sided clamping
 *-----------------------------------------------------------------------------*)
IF ABS(fDiaMaxEff - fCoreDiaEff) <= DL_FLOAT_EPS THEN
    fTaperFactor := 1.0;                    // 满卷等于卷芯：锥度退化，系数取 1.0 防除零 [无量纲] / Degenerate span, unity factor avoids division by zero
    IF bEnable AND bRun THEN
        uErrInfo := 16#0004_01C1;           // 【信息级】锥度分母退化已改置 1.0 / Info: degenerate taper span replaced by unity
    END_IF
ELSE
    fTaperLow := 1.0 - fTaperKEff;          // 锥度系数下限，等于 1 减锥度 [无量纲] / Taper factor lower bound
    fTaperRaw := 1.0 - fTaperKEff * (fDiaAct - fCoreDiaEff) / (fDiaMaxEff - fCoreDiaEff); // 原始锥度系数 [无量纲] / Raw taper factor
    IF (fTaperRaw > 1.0 + DL_FLOAT_EPS) OR (fTaperRaw < fTaperLow - DL_FLOAT_EPS) THEN
        fTaperFactor := LIMIT(fTaperLow, fTaperRaw, 1.0); // 超界钳到 [1-K, 1] [无量纲] / Clamp into the lower bound and one
        IF bEnable AND bRun THEN
            uErrInfo := 16#0004_01C1;       // 【信息级】锥度系数超界已钳位 / Info: taper factor clamped
        END_IF
    ELSE
        fTaperFactor := fTaperRaw;          // 未超界直通 [无量纲] / Raw factor passed through
    END_IF
END_IF
(*------------------------------------------------------------------------------
 * 段 9｜锥度基准张力（修正项后续加在基准上，失反馈也不丢张力）｜Taper base tension, the trim is added on top later
 *-----------------------------------------------------------------------------*)
fBase := fTensionSetEff * fTaperFactor;     // 基准张力＝目标张力乘锥度系数 [N] / Base tension equals setpoint times taper factor
(*------------------------------------------------------------------------------
 * 段 10｜主状态机（红线 R6：ENUM + CASE + ELSE 兜底，四态各有标签）｜Main state machine with mandatory ELSE fallback and four labelled states
 *-----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_TensionPhase.eIdle:                // 空闲：等使能与运行条件，张力输出在段 12 强制为 0
        IF bEnable AND bRun THEN
            IF bDancerOk THEN
                nTrackSync  := 2;           // 无扰投切：先给 PID 两拍跟踪 [拍] / Two tracking scans for a bumpless transfer
                bDancerLost := FALSE;       // 反馈有效，降级原因清除 [BOOL] / Feedback valid, clear the degradation reason
                eState      := E_DL_TensionPhase.eClosedLoop;
            ELSE
                bDancerLost := TRUE;        // 显式记录降级原因：反馈缺失 [BOOL] / Record the explicit degradation reason
                nRecoverCnt := 0;           // 恢复计数从零开始 [拍] / Recovery counter starts at zero
                eState      := E_DL_TensionPhase.eOpenLoop; // 使能瞬间反馈已失效，直接进降级态 [枚举] / Enter the degraded state directly
            END_IF
        END_IF

    E_DL_TensionPhase.eClosedLoop:          // 闭环运行：基准加摆辊比例修正
        IF nTrackSync > 0 THEN
            nTrackSync := nTrackSync - 1;   // 跟踪拍递减，减到零才放开修正 [拍] / Decrement the tracking counter until the trim is released
        END_IF
        IF (NOT bEnable) OR (NOT bRun) THEN
            nTrackSync := 0;                // 停机撤跟踪 [拍] / Clear the tracking counter on stop
            eState     := E_DL_TensionPhase.eIdle;
        ELSIF stStat.uInvalidDiaCnt >= DL_INVALID_MAX THEN
            uErrFault := 16#0004_02D1;      // 【故障级】卷径连续无效超限，几何法不可信 / Fault: consecutive invalid diameters exceeded the limit
            eState    := E_DL_TensionPhase.eFault;
        ELSIF NOT bDancerOk THEN
            bDancerLost := TRUE;            // 显式降级：反馈丢失 [BOOL] / Explicit degradation on feedback loss
            nRecoverCnt := 0;               // 恢复计数重新开始 [拍] / Recovery counter restarts
            nTrackSync  := 0;               // 撤闭环跟踪 [拍] / Clear the closed-loop tracking counter
            eState      := E_DL_TensionPhase.eOpenLoop;
        END_IF

    E_DL_TensionPhase.eOpenLoop:            // 开环降级：只出锥度基准张力，修正恒为 0
        IF (NOT bEnable) OR (NOT bRun) THEN
            bDancerLost := FALSE;           // 停机清降级原因 [BOOL] / Clear the degradation reason on stop
            nRecoverCnt := 0;               // 恢复计数清零 [拍] / Clear the recovery counter
            eState      := E_DL_TensionPhase.eIdle;
        ELSIF stStat.uInvalidDiaCnt >= DL_INVALID_MAX THEN
            uErrFault := 16#0004_02D1;      // 【故障级】卷径连续无效超限 / Fault: consecutive invalid diameters exceeded the limit
            eState    := E_DL_TensionPhase.eFault;
        ELSIF bDancerOk THEN
            nRecoverCnt := nRecoverCnt + 1; // 连续有效拍数累加 [拍] / Count the consecutive good scans
            IF nRecoverCnt >= DL_RECOVER_N THEN
                nRecoverCnt := 0;           // 恢复确认后计数归零 [拍] / Reset the counter after confirmation
                nTrackSync  := 2;           // 回闭环先跟踪两拍，修正从 0 起爬 [拍] / Track for two scans so the trim starts from zero
                bDancerLost := FALSE;       // 降级原因清除 [BOOL] / Clear the degradation reason
                eState      := E_DL_TensionPhase.eClosedLoop;
            END_IF
        ELSE
            nRecoverCnt := 0;               // 反馈再次失效，恢复计数归零 [拍] / Feedback failed again, reset the counter
        END_IF

    E_DL_TensionPhase.eFault:               // 故障锁存：输出安全值，仅复位沿退出
        bInControl := FALSE;                // 故障态闭环必然未生效 [BOOL] / Closed loop is not active in the fault state
        fTrim      := 0.0;                  // 故障态修正清零 [N] / Clear the trim in the fault state

    ELSE                                    // 非法状态兜底：复用本件最高优先故障码，不另造码
        uErrFault  := 16#0004_02D1;         // 【故障级】非法状态兜底，复用 02D1 / Fault: illegal state fallback reusing 02D1
        eState     := E_DL_TensionPhase.eFault;
        bInControl := FALSE;                // 强制非闭环 [BOOL] / Force the loop inactive
        fTrim      := 0.0;                  // 修正清零 [N] / Clear the trim

END_CASE
(*------------------------------------------------------------------------------
 * 段 11｜摆辊修正环实例无条件调用（FB 实例严禁放在 IF 或 CASE 分支内）｜Unconditional PID call, normalised output, pure proportional action
 *-----------------------------------------------------------------------------*)
// 跟踪窗口内以基准替代过程值：偏差恒为零，PID 反算积分保持零，窗口结束即恢复全量比例作用
// Inside the tracking window the reference replaces the process value: the error stays zero,
// so the back-calculated integral stays zero and full proportional action resumes afterwards
fPidPvEff := fDancerPosEff;
IF nTrackSync > 0 THEN
    fPidPvEff := fDancerRefEff;             // 跟踪拍强制零偏差 [mm] / Force zero error on the tracking scans
END_IF
fbTensionPid(
    bEnable      := (eState = E_DL_TensionPhase.eClosedLoop), // 仅闭环态使能，空闲与降级一律关闭 / Enabled in the closed-loop state only
    bManual      := FALSE,                                    // 恒为自动，禁止手动态污染归一化输出 / Always automatic
    fSetpoint    := fDancerRefEff,                            // 摆辊基准，毫米 / Dancer reference in millimetres
    fActual      := fPidPvEff,                                // 摆辊实测（失效与跟踪窗口内已替代）/ Dancer feedback, substituted when invalid or tracking
    fKp          := fPidKpEff,                                // 负增益实现反作用，每毫米 / Negated gain for reverse action
    tTi          := T#0S,                                     // 纯比例，无积分 / Pure proportional, no integral
    tTd          := T#0S,                                     // 无微分 / No derivative
    fDeadband    := 0.0,                                      // 死区为零，摆辊微偏也要修正 / Zero deadband
    bIncremental := FALSE,                                    // 位置式，输出即归一化修正 / Positional form, the output is the normalised trim
    rOutMin      := -1.0,                                     // 归一化下限 / Normalised lower bound
    rOutMax      := 1.0,                                      // 归一化上限 / Normalised upper bound
    tSampleTime  := DL_TASK_TIME,                             // 任务周期 / Task cycle
    bTrack       := (nTrackSync > 0),                         // 投切跟踪使能 / Transfer tracking enabled
    fTrackValue  := 0.0,                                      // 跟踪值为零修正，无扰投切 / Track at zero trim for a bumpless transfer
    bReset       := fbTrigReset.Q                             // 复位沿同步清 PID 内部历史 / Reset the PID history on the reset edge
);
(*------------------------------------------------------------------------------
 * 段 12｜张力合成与限幅（闭环加修正、开环只出基准、空闲与故障强制 0）｜Tension composition and clamping with explicit per-state behaviour
 *-----------------------------------------------------------------------------*)
IF eState = E_DL_TensionPhase.eClosedLoop THEN
    fTrim := fbTensionPid.fOut * fTrimSpanEff; // 归一化输出乘满量程得张力修正 [N] / Normalised output times the span gives the trim
ELSE
    fTrim := 0.0;                           // 非闭环态修正显式置零，绝不继承上次值 [N] / Explicitly zero the trim outside closed loop
END_IF

fRawCmd := fBase + fTrim;                   // 限幅前的张力指令 [N] / Unlimited tension command
fTensionOut := LIMIT(fLimLow, fRawCmd, fLimHigh); // 张力输出限幅 [N] / Clamped tension output
IF (bEnable AND bRun) AND (ABS(fRawCmd - fTensionOut) > DL_FLOAT_EPS) THEN
    uErrInfo := 16#0004_01C2;               // 【信息级】张力输出限幅生效 / Info: tension output clamped
END_IF

IF (eState = E_DL_TensionPhase.eIdle) OR (eState = E_DL_TensionPhase.eFault) THEN
    fTensionOut := 0.0;                     // 空闲与故障态输出安全零值 [N] / Safe zero output in idle and fault states
END_IF
(*------------------------------------------------------------------------------
 * 段 13｜统计与出口映射（信息级码不置 bError；02D0 降级置位、02D1 锁存进 eFault）｜Statistics and output mapping, info codes never raise the fault flag
 *-----------------------------------------------------------------------------*)
IF eState = E_DL_TensionPhase.eClosedLoop THEN
    IF NOT bAvgInit THEN
        stStat.fTensionAvg := fTensionOut;  // 均值首样本直取，避免从 0 缓慢爬升 [N] / First sample taken over directly, never averaged from zero
        bAvgInit           := TRUE;         // 置均值首样本标志 [BOOL] / Mark the first average sample
    ELSE
        stStat.fTensionAvg := stStat.fTensionAvg + fAvgAlpha * (fTensionOut - stStat.fTensionAvg); // 一阶指数平均 [N] / First-order exponential average
    END_IF
    stStat.tRunTime := stStat.tRunTime + DL_TASK_TIME; // 闭环运行时长按任务周期累加 [ms] / Accumulate the closed-loop runtime
END_IF

bInControl   := (eState = E_DL_TensionPhase.eClosedLoop); // 闭环生效标志由状态派生 [BOOL] / Closed-loop flag derived from the state
bError       := (eState = E_DL_TensionPhase.eFault) OR bDancerLost; // 故障态或显式降级态置位，信息级码不置位 [BOOL] / Fault flag raised by the fault state or the explicit degradation flag
IF eState = E_DL_TensionPhase.eFault THEN
    uErrorId := uErrFault;                  // 故障态上报锁存码，不被信息码覆盖 [码] / Report the latched code while faulted
ELSIF eState = E_DL_TensionPhase.eOpenLoop THEN
    uErrorId := 16#0004_02D0;               // 降级态显式上报反馈丢失原因，不静默降级 [码] / Report the explicit degradation reason
ELSE
    uErrorId := uErrInfo;                   // 运行态上报本拍瞬时信息码 [码] / Report the transient info code while running
END_IF

END_FUNCTION_BLOCK
