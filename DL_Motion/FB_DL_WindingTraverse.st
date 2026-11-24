(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WindingTraverse
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 卷绕工艺 · 排线轴指令
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅标准 TON / R_TRIG 与算术
 * 功能描述 (Function)   : 卷绕工位的「卷径递推加横动排线」双职责块。两个职责
 *                         同属一个物理工艺对象（同一根排线轴、同一个卷径），
 *                         故不拆成两个必须共享状态的块，而是按结构分成两个子段：
 *                         ① 卷径递推：层厚积分法，直径等于卷芯加两倍厚度乘圈数，
 *                            圈数由线速度与当前周长积分得到；
 *                         ② 横动排线：行程由排线宽度决定，节距由每圈节距决定，
 *                            端点换向带停留（dwell），输出目标位置与方向。
 * 与既有件边界 (Boundary): FC_DL_CoilDiameterCalc 是瞬时几何反算（纯函数、无
 *                         状态）；本块是递推加执行（有状态、出排线目标）。两者
 *                         互为校验：可把反算结果经注入卷径引脚送进来比对，
 *                         但代码零调用（泳道内禁止跨层调用）。本块不内联任何轴
 *                         逻辑，轴执行由上层注入的轴实例负责。
 * 双数据源仲裁 (Arbitration): 注入卷径与内部递推的优先级由 bUseInjectedDia 明确
 *                         给出，且内部递推在任何情况下都继续累积，切回内部递推
 *                         时不会出现卷径跳变。这不是模式枚举，而是单一布尔数据
 *                         源选择，语义单一，不构成多职责巨无霸块。
 * 设计要点 (Key notes)  : ① 圈增量每拍只积分一次，排线位移只从该增量派生，禁止
 *                           两处各积一次（否则排线节距会被放大一倍）；
 *                         ② 卷径与排线位移全部有 MAX 守卫，分母绝不为 0；
 *                         ③ 变化率先算再更新历史值，次序颠倒会得到恒 0；
 *                         ④ 停止优先于一切运行态：bStop 在状态机之前判，保证
 *                           任何运行态都能停；
 *                         ⑤ 排线轴到位超时用「拍数计数」而非时间累加：固定任务
 *                           周期下二者等价，但拍数计数无需时间类型转换，跨平台
 *                           无歧义；
 *                         ⑥ 只有唯一主状态机枚举，内外共用同一个变量，禁止再设
 *                           第二套状态机。
 * 开源溯源 (Origin)     : lgf-technology / s7-motion。参考 LGF（Libre Graphical
 *                         Framework）公开函数库「Technology」分类中卷绕与排线
 *                         类函数的功能分类与参数域（卷径、厚度、线速度、节距
 *                         四组参数形态），以及 S7-1500 Motion Control 公开手册
 *                         中「工艺对象输出目标位置与方向」的接口形态。只借分类
 *                         与参数域，状态机与递推算法 100% 自有 clean-room，
 *                         不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / R_TRIG
 * 故障码表 (Error codes):
 *   16#0004_01B0【信息级】卷径、厚度、线速度或任务周期越界被钳位
 *   16#0004_01B1【信息级】排线宽度或每圈节距越界被钳位
 *   16#0004_01B2【信息级】注入卷径越界，回落内部递推
 *   16#0004_01B3【信息级】排线轴未就绪，拒绝启动（不锁故障）
 *   16#0004_02C0【故障级】参数非有限值
 *   16#0004_02C1【故障级】非法状态兜底
 *   16#0004_02C2【故障级】排线轴到位超时（方向非零且长期不到位）
 *   16#0004_02C3【故障级】卷径递推不收敛（已达上限仍持续增圈）
 * 验收向量 (Acceptance) :
 *   V1 递推：卷芯 0.1 米、厚度 0.1 毫米、线速度 10 米每分、周期 0.01 秒推
 *      100 拍 → 圈数约 0.53、卷径约 0.1001 米
 *   V2 注入仲裁：注入 0.5 米 → 输出 0.5 米，内部递推仍增长，切回无跳变
 *   V3 排线到端：行程 0.2 米、节距 5 毫米每圈 → 到端时置端位标志、转停留态、
 *      目标位置不越界
 *   V4 停留后换向：停留 100 毫秒 → 方向取反、端位标志清零、回卷绕态
 *   V5 轴未就绪：给启动沿 → 不进入卷绕态、置 01B3、不锁故障
 *   V6 停止优先：停留态给停止 → 立即转停止并回待机、方向清零
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 全部除法分母有 MAX 守卫、
 *                         浮点判零用容差、非有限值筛查 ｜ R5 全变量中英双语
 *                         同行注释 ｜ R6 ENUM 加 CASE 加 ELSE 兜底
 *                         R7 TON 与两个 R_TRIG 全部在 CASE 之外无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · ROADMAP 未注册项补齐）
 *   2026-11-15  v1.0.1  R10 终审修复四处（机检全过、逐拍推演暴露）：
 *                       R-FIX-1【致命】待机态每拍把方向内部量清 0 且卷绕态不再
 *                       赋值方向，启动后方向恒 0 → 排线位移恒 0、永不走位，并在
 *                       卷绕与停留两态间无位移抖动；改为启动时置正向、待机时清 0；
 *                       R-FIX-2【严重】A 端判据未判方向，启动首拍位置为 0 即命中
 *                       「到达 A 端」→ 误进停留并换向；两个端位判据均加方向条件；
 *                       R-FIX-3【中等】轴到位判据的分母为可变入参且在参数非法时
 *                       为 0（0/0 得非数），补 MAX 守卫；
 *                       R-FIX-4【中等】仲裁卷径首拍未预置（保持 0），首拍卷径
 *                       输出 0 米、变化率出现负十米每秒级假跳变，复位拍同理；
 *                       首扫与复位路径均预置为卷芯。
 * 规格偏离登记 (Deviations):
 *   D1 每圈节距引脚沿用规格书原名 nPitchPerRev 而类型为 LREAL，与「n 表示有
 *      符号整数」的命名红线冲突（实为浮点物理量）。因规格书与对外引脚契约
 *      同源，改名为 fPitchPerRev 属破坏性变更，本轮按「契约优先」保留原名，
 *      登记待下一 MAJOR 统一整改，不在 PATCH 版内改名。
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_WindState（唯一主状态机，内外共用同一变量，禁止再设第二套）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_WindState :
(
    eIdle     := 0,     // 待机：未启动或已停止 / Idle, not started or stopped
    eWinding  := 10,    // 卷绕：卷径递推与排线推进 / Winding, diameter recursion and traverse advance
    eDwelling := 20,    // 端点停留：换向前等待 / Endpoint dwell before reversing
    eStopping := 30,    // 停止收尾 / Stopping
    eFault    := 99     // 故障锁定：仅复位沿可退 / Fault latched, only a reset edge leaves
);
END_TYPE

FUNCTION_BLOCK FB_DL_WindingTraverse
VAR_INPUT
    bEnable           : BOOL := TRUE;      // 使能 [-] / Enable
    bStart            : BOOL;              // 启动卷绕，上升沿 [-] / Start winding on a rising edge
    bStop             : BOOL;              // 停止，电平有效，优先于一切运行态 [-] / Stop, level active, outranks every running state
    bReset            : BOOL;              // 复位故障与卷径计数，上升沿 [-] / Reset the fault and the diameter recursion
    bUseInjectedDia   : BOOL := FALSE;     // TRUE 采用注入卷径，FALSE 采用内部递推 [-] / TRUE selects the injected diameter
    fDiaInjected      : LREAL := 0.0;      // 注入卷径，域 0.01 到 3.0 [米] / Injected diameter, 0.01 to 3.0 m
    fCoreDia          : LREAL := 0.100;    // 卷芯直径，域 0.01 到 1.0 [米] / Core diameter, 0.01 to 1.0 m
    fThickness        : LREAL := 0.0001;   // 材料厚度，域 1 微米到 10 毫米 [米] / Material thickness
    fLineSpeed        : LREAL := 0.0;      // 材料线速度，域 0 到 3000 [米每分] / Line speed, 0 to 3000 metres per minute
    fTaskCycle        : LREAL := 0.01;     // 任务周期，域 1 毫秒到 1 秒 [s] / Task cycle time
    fWebWidth         : LREAL := 0.5;      // 卷材宽度，域 0.01 到 5.0 [米] / Web width, 0.01 to 5.0 m
    fTraverseWidth    : LREAL := 0.5;      // 排线行程，域 0.01 到 5.0 [米] / Traverse stroke, 0.01 to 5.0 m
    nPitchPerRev      : LREAL := 1.0;      // 每圈排线节距，域 0.1 到 50 [毫米每圈] / Pitch per revolution, 0.1 to 50 mm per turn
    fTraverseSpeedMax : LREAL := 0.5;      // 排线轴最大速度，域 0.01 到 5.0 [米每秒] / Traverse axis maximum speed
    tDwellEnd         : TIME := T#100MS;   // 端点停留时间，域 0 到 2 秒 [毫秒] / Endpoint dwell time, 0 to 2 s
    bAxisReady        : BOOL;              // 排线轴就绪反馈 [-] / Traverse axis ready feedback
    fAxisPos          : LREAL;             // 排线轴当前位置反馈 [米] / Traverse axis actual position
    bAxisInPos        : BOOL;              // 排线轴到位反馈 [-] / Traverse axis in-position feedback
END_VAR
VAR_OUTPUT
    fDia          : LREAL;                 // 当前卷径（仲裁后）[米] / Current diameter after arbitration
    fDiaRate      : LREAL;                 // 卷径变化率，正值为收卷增大 [米每秒] / Diameter rate, positive when winding up
    nRevolutions  : LREAL;                 // 累计圈数（含小数）[圈] / Accumulated revolutions including the fraction
    fTargetPos    : LREAL;                 // 排线轴目标位置，域 0 到行程 [米] / Traverse target position
    nDir          : INT;                   // 排线方向，正 1 或 负 1，0 为停止 [方向] / Traverse direction, plus one, minus one or zero
    bAtEndA       : BOOL;                  // 已到 A 端（行程零点）[-] / TRUE at end A
    bAtEndB       : BOOL;                  // 已到 B 端（行程末端）[-] / TRUE at end B
    eState        : E_DL_WindState;        // 当前状态，对外直接可观测 [-] / Current state, observable from outside
    bRunning      : BOOL;                  // 卷绕运行中（含停留）[-] / TRUE while winding or dwelling
    bError        : BOOL;                  // 故障锁存 [-] / Fault latch
    uErrorId      : UDINT;                 // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    fbTrigStart   : R_TRIG;                // 启动沿检测，CASE 之外无条件刷新 [-] / Rising edge detector for the start input
    fbTrigReset   : R_TRIG;                // 复位沿检测，CASE 之外无条件刷新 [-] / Rising edge detector for the reset input
    fbDwell       : TON;                   // 端点停留计时，CASE 之外无条件刷新 [-] / Endpoint dwell timer
    bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）[-] / First-scan flag
    _eState       : E_DL_WindState := E_DL_WindState.eIdle;  // 内部状态机（对内经本变量，对外经 eState 镜像）[-] / Internal state machine
    fDiaInt       : LREAL := 0.0;          // 内部递推卷径 [米] / Internal recursive diameter
    fRevAcc       : LREAL := 0.0;          // 累计圈数 [圈] / Accumulated revolutions
    fRevDelta     : LREAL := 0.0;          // 本拍圈增量，排线位移的唯一来源 [圈] / Revolutions gained this cycle
    fTravPos      : LREAL := 0.0;          // 排线轴内部位置，域 0 到行程 [米] / Internal traverse position
    nDirInt       : INT := 1;              // 内部方向，正 1 或 负 1，0 为停止 [方向] / Internal direction
    fPrevDia      : LREAL := 0.0;          // 上拍卷径，变化率用 [米] / Previous diameter used by the rate
    bEndAInt      : BOOL;                  // A 端标志内部量 [-] / Internal end A flag
    bEndBInt      : BOOL;                  // B 端标志内部量 [-] / Internal end B flag
    bDwellActive  : BOOL;                  // 停留计时使能 [-] / Dwell timing enable
    bDwellIn      : BOOL;                  // 停留定时器输入条件，先算后调 [-] / Dwell timer input condition
    tDwellUse     : TIME := T#100MS;       // 生效停留时间（已钳位）[毫秒] / Effective dwell time after clamping
    fCoreUse      : LREAL;                 // 生效卷芯直径 [米] / Effective core diameter
    fThickUse     : LREAL;                 // 生效材料厚度 [米] / Effective thickness
    fLineUse      : LREAL;                 // 生效线速度 [米每分] / Effective line speed
    fDtUse        : LREAL;                 // 生效任务周期 [s] / Effective task cycle
    fTravUse      : LREAL;                 // 生效排线行程 [米] / Effective traverse stroke
    fPitchUse     : LREAL;                 // 生效每圈节距 [毫米每圈] / Effective pitch per revolution
    fSpeedUse     : LREAL;                 // 生效排线速度上限 [米每秒] / Effective traverse speed limit
    fDiaArb       : LREAL;                 // 仲裁后的卷径 [米] / Diameter after arbitration
    bParamOk      : BOOL;                  // 参数全部有限且域合法 [-] / TRUE when every parameter is finite and legal
    nAxisWait     : DINT;                  // 排线轴连续未到位拍数 [拍] / Consecutive cycles without in-position
    fAxisWaitMax  : LREAL;                 // 允许的最大未到位拍数 [拍] / Allowed cycle budget before a timeout
END_VAR
VAR CONSTANT
    DL_PI         : LREAL := 3.141592653589793;  // 圆周率 [-] / Pi
    DL_DIA_MIN    : LREAL := 0.01;               // 卷径下限 [米] / Diameter lower bound
    DL_DIA_MAX    : LREAL := 3.0;                // 卷径上限 [米] / Diameter upper bound
    DL_CORE_MIN   : LREAL := 0.01;               // 卷芯直径下限 [米] / Core diameter lower bound
    DL_CORE_MAX   : LREAL := 1.0;                // 卷芯直径上限 [米] / Core diameter upper bound
    DL_THICK_MIN  : LREAL := 1.0E-6;             // 厚度下限，1 微米 [米] / Thickness lower bound
    DL_THICK_MAX  : LREAL := 0.01;               // 厚度上限，10 毫米 [米] / Thickness upper bound
    DL_LINE_MAX   : LREAL := 3000.0;             // 线速度上限 [米每分] / Line speed upper bound
    DL_CYCLE_MIN  : LREAL := 0.001;              // 任务周期下限 [s] / Task cycle lower bound
    DL_CYCLE_MAX  : LREAL := 1.0;                // 任务周期上限 [s] / Task cycle upper bound
    DL_TRAV_MIN   : LREAL := 0.01;               // 排线行程下限 [米] / Traverse stroke lower bound
    DL_TRAV_MAX   : LREAL := 5.0;                // 排线行程上限 [米] / Traverse stroke upper bound
    DL_WEB_MIN    : LREAL := 0.01;               // 卷材宽度下限 [米] / Web width lower bound
    DL_WEB_MAX    : LREAL := 5.0;                // 卷材宽度上限 [米] / Web width upper bound
    DL_PITCH_MIN  : LREAL := 0.1;                // 节距下限 [毫米每圈] / Pitch lower bound
    DL_PITCH_MAX  : LREAL := 50.0;               // 节距上限 [毫米每圈] / Pitch upper bound
    DL_SPEED_MIN  : LREAL := 0.01;               // 排线速度下限 [米每秒] / Traverse speed lower bound
    DL_SPEED_MAX  : LREAL := 5.0;                // 排线速度上限 [米每秒] / Traverse speed upper bound
    DL_MM2M       : LREAL := 0.001;              // 毫米转米系数 [米每毫米] / Millimetres to metres
    DL_SEC_PER_MIN: LREAL := 60.0;               // 分钟转秒 [s每分] / Seconds per minute
    DL_DWELL_MAX  : TIME  := T#2S;               // 端点停留上限 [毫秒] / Dwell upper bound
    DL_FLOAT_EPS  : LREAL := 1.0E-9;             // 浮点容差 [-] / Float tolerance
    DL_BIG        : LREAL := 1.0E300;            // 非有限值兜底门限 [-] / Magnitude guard
    DL_WAIT_MIN   : LREAL := 2.0;                // 未到位拍数下限，防分母过小 [拍] / Minimum cycle budget
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测与停留计时（R7 红线：全部在 CASE 之外无条件刷新）
 *      Edge detection and dwell timing, all refreshed outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStart);
fbTrigReset(CLK := bReset);

IF bDwellActive THEN
    bDwellIn := TRUE;
ELSE
    bDwellIn := FALSE;
END_IF

(* 停留时间先钳位到合法区间，再无条件调用实例，禁止把调用写进 IF 分支 *)
tDwellUse := tDwellEnd;
IF tDwellUse > DL_DWELL_MAX THEN
    tDwellUse := DL_DWELL_MAX;
ELSIF tDwellUse < T#0S THEN
    tDwellUse := T#0S;
END_IF
fbDwell(IN := bDwellIn, PT := tDwellUse);

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    _eState      := E_DL_WindState.eIdle;
    fDiaInt      := fCoreDia;
    fRevAcc      := 0.0;
    fRevDelta    := 0.0;
    fTravPos     := 0.0;
    nDirInt      := 1;
    fPrevDia     := fCoreDia;
    bEndAInt     := TRUE;
    bEndBInt     := FALSE;
    bDwellActive := FALSE;
    nAxisWait    := 0;
    fDiaArb      := fCoreDia;                // 仲裁卷径预置为卷芯，防首拍变化率出现假跳变
    bError       := FALSE;
    uErrorId     := 16#0000_0000;
    bInit        := TRUE;                    // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数域校验与钳位（每拍，信息级）；任一非有限值 → 故障级
 *      Parameter validation and clamping; non-finite values escalate to a fault
 *-----------------------------------------------------------------------------*)
bParamOk := TRUE;

IF (fCoreDia <> fCoreDia) OR (fThickness <> fThickness) OR (fLineSpeed <> fLineSpeed)
   OR (fTaskCycle <> fTaskCycle) OR (fTraverseWidth <> fTraverseWidth)
   OR (nPitchPerRev <> nPitchPerRev) OR (fTraverseSpeedMax <> fTraverseSpeedMax)
   OR (fDiaInjected <> fDiaInjected) OR (fWebWidth <> fWebWidth) THEN
    bParamOk := FALSE;
ELSE
    fCoreUse := fCoreDia;
    IF fCoreUse < DL_CORE_MIN THEN
        fCoreUse := DL_CORE_MIN;
        uErrorId := 16#0004_01B0;
    ELSIF fCoreUse > DL_CORE_MAX THEN
        fCoreUse := DL_CORE_MAX;
        uErrorId := 16#0004_01B0;
    END_IF

    fThickUse := fThickness;
    IF fThickUse < DL_THICK_MIN THEN
        fThickUse := DL_THICK_MIN;
        uErrorId  := 16#0004_01B0;
    ELSIF fThickUse > DL_THICK_MAX THEN
        fThickUse := DL_THICK_MAX;
        uErrorId  := 16#0004_01B0;
    END_IF

    fLineUse := fLineSpeed;
    IF fLineUse < 0.0 THEN
        fLineUse := 0.0;
        uErrorId := 16#0004_01B0;
    ELSIF fLineUse > DL_LINE_MAX THEN
        fLineUse := DL_LINE_MAX;
        uErrorId := 16#0004_01B0;
    END_IF

    fDtUse := fTaskCycle;
    IF fDtUse < DL_CYCLE_MIN THEN
        fDtUse  := DL_CYCLE_MIN;
        uErrorId := 16#0004_01B0;
    ELSIF fDtUse > DL_CYCLE_MAX THEN
        fDtUse  := DL_CYCLE_MAX;
        uErrorId := 16#0004_01B0;
    END_IF

    fTravUse := fTraverseWidth;
    IF fTravUse < DL_TRAV_MIN THEN
        fTravUse := DL_TRAV_MIN;
        uErrorId := 16#0004_01B1;
    ELSIF fTravUse > DL_TRAV_MAX THEN
        fTravUse := DL_TRAV_MAX;
        uErrorId := 16#0004_01B1;
    END_IF

    fPitchUse := nPitchPerRev;
    IF fPitchUse < DL_PITCH_MIN THEN
        fPitchUse := DL_PITCH_MIN;
        uErrorId  := 16#0004_01B1;
    ELSIF fPitchUse > DL_PITCH_MAX THEN
        fPitchUse := DL_PITCH_MAX;
        uErrorId  := 16#0004_01B1;
    END_IF

    fSpeedUse := fTraverseSpeedMax;
    IF fSpeedUse < DL_SPEED_MIN THEN
        fSpeedUse := DL_SPEED_MIN;
        uErrorId  := 16#0004_01B1;
    ELSIF fSpeedUse > DL_SPEED_MAX THEN
        fSpeedUse := DL_SPEED_MAX;
        uErrorId  := 16#0004_01B1;
    END_IF
END_IF

IF NOT bParamOk THEN
    _eState  := E_DL_WindState.eFault;
    uErrorId := 16#0004_02C0;
    bError   := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜停止优先（状态机之前判）：任何运行态都能停
 *      Stop priority evaluated before the state machine
 *-----------------------------------------------------------------------------*)
IF bStop AND ((_eState = E_DL_WindState.eWinding) OR (_eState = E_DL_WindState.eDwelling)) THEN
    _eState := E_DL_WindState.eStopping;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（ENUM 加 CASE，含 ELSE 兜底）
 *      Main state machine with an ELSE fallback branch
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_WindState.eIdle:
        IF fbTrigStart.Q AND bEnable THEN
            IF NOT bAxisReady THEN
                uErrorId := 16#0004_01B3;    // 轴未就绪：拒绝启动，不锁故障
            ELSE
                nDirInt := 1;                // 启动方向固定为正向（零点 → 行程末端）
                _eState := E_DL_WindState.eWinding;
            END_IF
        ELSE
            nDirInt := 0;                    // 待机时方向输出 0，便于 HMI 显示已停止
        END_IF

    E_DL_WindState.eWinding:
        (* 5.1 圈增量：每拍只积分一次，排线位移只从本增量派生 *)
        fRevDelta := (fLineUse / DL_SEC_PER_MIN)
                     / (DL_PI * MAX(fDiaInt, DL_DIA_MIN))
                     * fDtUse;
        fRevAcc := fRevAcc + fRevDelta;

        (* 5.2 卷径递推（内部值始终更新，保证切回递推时无跳变） *)
        fDiaInt := LIMIT(DL_DIA_MIN, fCoreUse + 2.0 * fThickUse * fRevAcc, DL_DIA_MAX);

        (* 5.3 卷径仲裁：注入值有效则只改输出，内部累积继续 *)
        IF bUseInjectedDia THEN
            IF (fDiaInjected >= DL_DIA_MIN) AND (fDiaInjected <= DL_DIA_MAX) THEN
                fDiaArb := fDiaInjected;
            ELSE
                fDiaArb  := fDiaInt;
                uErrorId := 16#0004_01B2;    // 注入值越界，回落递推
            END_IF
        ELSE
            fDiaArb := fDiaInt;
        END_IF

        (* 5.4 排线推进：位移等于圈增量乘节距（毫米每圈先转米每圈） *)
        fTravPos := fTravPos + INT_TO_LREAL(nDirInt) * fRevDelta * fPitchUse * DL_MM2M;

        IF (nDirInt > 0) AND (fTravPos >= fTravUse) THEN
            fTravPos     := fTravUse;         // 端点钳位，绝不越界
            bEndBInt     := TRUE;
            bDwellActive := TRUE;
            _eState      := E_DL_WindState.eDwelling;
        ELSIF (nDirInt < 0) AND (fTravPos <= 0.0) THEN
            fTravPos     := 0.0;
            bEndAInt     := TRUE;
            bDwellActive := TRUE;
            _eState      := E_DL_WindState.eDwelling;
        END_IF

        (* 5.5 卷径不收敛监视：已达上限仍持续增圈说明厚度或圈数算错 *)
        IF (fDiaInt >= DL_DIA_MAX) AND (fRevDelta > DL_FLOAT_EPS) THEN
            uErrorId := 16#0004_02C3;
            bError   := TRUE;
            _eState  := E_DL_WindState.eFault;
        END_IF

    E_DL_WindState.eDwelling:
        (* 停留：位置保持，等停留计时到即换向；端位标志清零需每拍重写 *)
        IF fbDwell.Q THEN
            nDirInt      := -nDirInt;
            bEndAInt     := FALSE;
            bEndBInt     := FALSE;
            bDwellActive := FALSE;
            _eState      := E_DL_WindState.eWinding;
        END_IF

    E_DL_WindState.eStopping:
        nDirInt      := 0;
        bDwellActive := FALSE;
        bEndAInt     := FALSE;
        bEndBInt     := FALSE;
        nAxisWait    := 0;
        _eState      := E_DL_WindState.eIdle;

    E_DL_WindState.eFault:
        nDirInt      := 0;
        bDwellActive := FALSE;
        IF fbTrigReset.Q AND bParamOk THEN
            bError    := FALSE;
            uErrorId  := 16#0000_0000;
            fRevAcc   := 0.0;
            fDiaInt   := fCoreUse;
            fDiaArb   := fCoreUse;           // 仲裁卷径同步回卷芯，防复位拍变化率假跳变
            fPrevDia  := fCoreUse;
            fTravPos  := 0.0;
            nDirInt   := 1;
            nAxisWait := 0;
            _eState   := E_DL_WindState.eIdle;
        END_IF

    ELSE
        (* 非法枚举值兜底 *)
        _eState  := E_DL_WindState.eFault;
        uErrorId := 16#0004_02C1;
        bError   := TRUE;
        nDirInt  := 0;
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜排线轴到位超时监视（拍数口径，跨平台无歧义）
 *      Traverse in-position timeout measured in cycles, portable by construction
 *      允许拍数 = 两倍行程除以最大速度再除以任务周期（走完一个来回的预算），
 *      行程与速度与周期均已钳位，分母不小于 0.01，不会除零
 *-----------------------------------------------------------------------------*)
IF (nDirInt <> 0) AND (NOT bAxisInPos) THEN
    nAxisWait := nAxisWait + 1;
ELSE
    nAxisWait := 0;
END_IF

fAxisWaitMax := (2.0 * fTravUse / MAX(fSpeedUse, DL_SPEED_MIN)) / MAX(fDtUse, DL_CYCLE_MIN);
IF fAxisWaitMax < DL_WAIT_MIN THEN
    fAxisWaitMax := DL_WAIT_MIN;
END_IF

IF INT_TO_LREAL(nAxisWait) > fAxisWaitMax THEN
    uErrorId  := 16#0004_02C2;
    bError    := TRUE;
    _eState   := E_DL_WindState.eFault;
    nAxisWait := 0;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜变化率先算再更新历史值（次序写死），输出每拍重写（R27）
 *      Diameter rate before the history refresh, outputs rewritten every cycle
 *-----------------------------------------------------------------------------*)
fDiaRate := (fDiaArb - fPrevDia) / MAX(fDtUse, DL_CYCLE_MIN);
fPrevDia := fDiaArb;

fDia         := fDiaArb;
nRevolutions := fRevAcc;
fTargetPos   := fTravPos;
nDir         := nDirInt;
bAtEndA      := bEndAInt;
bAtEndB      := bEndBInt;
eState       := _eState;

IF (_eState = E_DL_WindState.eWinding) OR (_eState = E_DL_WindState.eDwelling) THEN
    bRunning := TRUE;
ELSE
    bRunning := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 现场提示：
 *   1 fAxisPos 只作监视与诊断参考，本块的目标位置由内部递推给出，避免轴反馈
 *     抖动反向污染节距计算；若现场需要闭环纠偏，请在上层用 fAxisPos 与
 *     fTargetPos 的偏差做补偿，不要把反馈直接接回本块的递推链路；
 *   2 注入卷径越界时会自动回落内部递推，此时 fDia 会跳变，HMI 应同时显示
 *     注入有效标志与事件码，避免误判为卷径突变。
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
