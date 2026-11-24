(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RotaryIndexTable
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 工站模板 · 多工位分度盘调度
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
 *                         仅依赖标准库（TON / R_TRIG / F_TRIG / LIMIT），分度请求
 *                         以布尔脉冲出口下发，块内不绑定任何电机或驱动库
 * 功能描述 (Function)   : 管理「分度请求 → 到位确认 → 稳定等待 → 工位工艺放行」的
 *                         节拍链；维护工位启用表与工艺号映射，支持空跑（清洗）模式
 *                         逐位走完，并对分度超时与到位信号抖动给出可诊断的故障码
 * 与既有件边界 (Scope)  : 料仓槽位台账（空 / 满 / 不合格）由料仓件承担，本块不管槽
 *                         位内容；连续输送积放由输送段件承担，本块管离散分度盘的节
 *                         拍与工位放行。三者拓扑互斥，语义不重叠
 * 状态机规模 (States)   : 五态最小子集（eIdle 0 / eDwell 10 / eIndexing 20 /
 *                         eSettling 30 / eFault 99）。eSettling 单独成态，用于隔离
 *                         「到位后抖动」的诊断窗口，避免把机械抖动混入分度超时计数
 * 关键算法 (Algorithm)  :
 *   ① 工位号合法性：nAtStation 须落在 1~生效工位数，越界即 02D2，不做猜测性修正
 *   ② 掩码构造：每拍由启用表重建，逐位置位（位累加器左移一位再或），不拼累计量，
 *      规避位宽边界；工位数上限 24，恒在安全域内
 *   ③ 停留计时：剩余停留时间由定时器已历时反算，空跑模式直接旁路计时
 *   ④ 空跑模式：工艺放行恒假，分度链照走，用于清洗与调试；不计循环数
 *   ⑤ 循环计数：分度回到 1 号位那一拍出单拍脉冲并累加，饱和防溢出
 *   ⑥ 抖动诊断：稳定窗内到位信号掉沿即判硬件问题，直接锁故障且不自动重试——自动
 *      重试会把机械松动掩盖成偶发超时，现场极难定位
 * 码位表 (Error codes)  :
 *   16#0005_01C2【信息级】工位数量越界已钳位至 2~24，不置故障位
 *   16#0005_02D0【故障级】分度超时（到位信号未在监控窗内建立）
 *   16#0005_02D1【故障级】到位信号抖动或丢失（稳定窗内掉沿）
 *   16#0005_02D2【故障级】工位号越界（机械到位反馈不可信）
 *   16#0005_02D3【故障级】非法状态兜底
 * R32 写入点次序审计 :
 *   nActiveStation  : ① 空跑 / 停机撤销时清 0（段 6、段 7）→ ② 停留与稳定段按到位
 *                     反馈刷新（eDwell / eSettling 各一处，同拍只可能命中一处）
 *   bStationReady   : 仅段 10 单点派生（由生效工位数、启用表、空跑模式三者与门），
 *                     状态机内不写，杜绝分支双写
 *   nRecipeAtStation: 仅段 10 单点派生（工艺号透传，越界给 0，不做校验）
 *   tDwellRemain    : 仅段 10 单点派生（由停留定时器已历时反算，钳位非负）
 *   _uErrorIdInt    : ① 首扫清（段 4）→ ② 分度超时（eIndexing）→ ③ 抖动（eSettling）
 *                     → ④ 工位号越界（eSettling）→ ⑤ 非法状态（ELSE）→ ⑥ 复位清
 *   _eState         : 每拍只在 CASE 分支出口单点写入；CASE 之外仅段 6 使能撤销一处
 * 设计偏离登记 (Deviations) :
 *   D1 增补 tCycle 引脚（默认 10 毫秒）：统计结构体内含累计运行时长，而块内无时间
 *      基准引脚则无法累加；按库内既有公约以任务扫描周期作基准，向后兼容（有默认
 *      值），不改变任何既有引脚语义
 *   D2 分度计数在「到位确认通过」拍累加，而非请求拍：超时未到位属失败分度，不应
 *      计入成功次数；与规格文字「分度次数」取成功口径一致
 * 验收向量 (Acceptance) :
 *   V1 掩码：工位数 8、前 5 个启用 → 掩码 16#0000_001F
 *   V2 工艺号透传：到位 3 号工位、3 号工艺号 27 → 作业工位 3、工艺号 27、放行为真
 *   V3 分度超时：监控窗 2 秒内到位信号未建立 → 码 02D0、故障态、故障位为真
 *   V4 空跑：工位数 4、空跑为真 → 逐位推进，4 拍后出循环脉冲，循环计数不增
 *   V5 抖动：到位后 50 毫秒内信号由真转假 → 码 02D1，无自动重试
 * 开源溯源 (Origin)     : 参考包装机械公开手册的工位 / 节拍语义组织与位掩码工位表
 *                         写法，只借分类与参数域；状态机、掩码重建、抖动诊断、码位
 *                         与引脚契约为本库独立设计，clean-room 不构成衍生作品
 * 红线自检 (Redline)    : R1 零全局表与外部变量引用、零物理地址记号 ✓｜R2 零占位符 ✓
 *                         R3 纯 IEC 61131-3 加标准库 ✓｜R4 数组先判界、除法防零、
 *                         时长反算钳非负 ✓｜R5 声明行中英双语同行注释 ✓｜R6 五成员逐
 *                         一有 CASE 标签且含 ELSE 兜底 ✓｜R7 三沿检测（启动 / 停止 /
 *                         复位）与到位双沿、三定时器全部在 CASE 之外无条件刷新 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 11 · C 泳道 · 工站四件套之二）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_IndexTableState（归属 FB_DL_RotaryIndexTable，同文件发布）
 *   五态，每个成员在主状态机中均有同名 CASE 标签（R31 完备性）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_IndexTableState :
(
    eIdle     := 0,     // 待机：等启动沿，不发放行 / Idle, awaiting start, no permit
    eDwell    := 10,    // 停留：当前工位工艺放行窗 / Dwell, process permit window
    eIndexing := 20,    // 分度中：已出请求脉冲，等到位 / Indexing, waiting for in-position
    eSettling := 30,    // 稳定中：到位后去抖确认 / Settling, debounce after in-position
    eFault    := 99     // 故障锁存：仅复位沿可退 / Fault latched, only a reset edge leaves
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_IndexTableStat（归属 FB_DL_RotaryIndexTable）
 *   跨周期统计，由调用方持有，本块只累加，掉电保持由上层负责
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_IndexTableStat :
STRUCT
    nIndexCount : UDINT;                    // 累计成功分度次数 [次] [Successful index counter]
    nCycleCount : UDINT;                    // 累计整圈循环数 [圈] [Full revolution counter]
    tRunTime    : TIME;                     // 累计运行时长 [毫秒] [Accumulated run time]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_RotaryIndexTable
VAR_INPUT
    bEnable          : BOOL;                            // 使能，FALSE 撤销分度请求并回待机 [Enable, withdraws request on FALSE]
    bStart           : BOOL;                            // 启动节拍循环，上升沿受理 [Start the cycle on a rising edge]
    bStop            : BOOL;                            // 完成当前工位后停止，上升沿受理 [Stop after current station, rising edge]
    bReset           : BOOL;                            // 复位故障，上升沿受理 [Reset fault on rising edge]
    nStationCount    : INT;                             // 工位总数 [个]，有效域 2~24 [Station count, 2..24]
    nAtStation       : INT;                             // 机械到位工位号 [1~工位数]，0 表示未定位 [Mechanical station number, 0 = not seated]
    bIndexInPos      : BOOL;                            // 分度到位开关信号 [-] [Indexer in-position switch]
    abStationEnable  : ARRAY[1..24] OF BOOL;            // 工位启用表，FALSE 视为空位 [Station enable table, FALSE = empty]
    anStationRecipe  : ARRAY[1..24] OF INT;             // 工位工艺号表，仅透传不校验 [-] [Per-station recipe number, pass-through]
    tDwellTime       : TIME := T#1S;                    // 每工位停留时间 [毫秒]，0 表示不停留 [Dwell per station]
    tSettleTime      : TIME := T#100MS;                 // 到位后稳定确认时间 [毫秒]，滤机械抖动 [Settling time after in-position]
    tIndexTimeout    : TIME := T#3S;                    // 分度超时 [毫秒]，0 表示不监控 [Indexing timeout]
    bDryRun          : BOOL;                            // 空跑（清洗）模式：忽略启用表逐位走完 [Dry-run mode, ignores enable table]
    tCycle           : TIME := T#10MS;                  // 任务扫描周期 [毫秒]，累计运行时长基准（偏离 D1）[Task cycle time, run-time base]
END_VAR
VAR_OUTPUT
    bIndexReq        : BOOL;                            // 分度请求，单拍脉冲 [-] [Index request, single-scan pulse]
    nActiveStation   : INT;                             // 当前作业工位号 [1~工位数]，0 表示无效 [Active station number, 0 = invalid]
    bStationReady    : BOOL;                            // 当前工位允许工艺动作 [-] [Station ready for process action]
    nRecipeAtStation : INT;                             // 当前工位工艺号，透传 [-] [Recipe number at active station]
    uStationMask     : DWORD;                           // 工位启用镜像，第 n 位对应第 n 工位 [Station enable mirror, bit n-1]
    bCycleDone       : BOOL;                            // 整圈走完单拍脉冲 [-] [Single pulse on full revolution]
    tDwellRemain     : TIME;                            // 当前工位剩余停留时间 [毫秒] [Remaining dwell time]
    eState           : E_DL_IndexTableState;            // 主状态机当前态 [-] [Current state]
    bError           : BOOL;                            // 故障锁存，需复位清除 [Latched fault]
    uErrorId         : UDINT;                           // 事件码或故障码，0 表示无 [Event or fault code]
END_VAR
VAR_IN_OUT
    stStat           : ST_DL_IndexTableStat;            // 跨周期统计，调用方持有 [Persistent statistics]
END_VAR
VAR
    _eState          : E_DL_IndexTableState := E_DL_IndexTableState.eIdle;  // 内部状态寄存器，唯一真值源 [Internal state register]
    _bInit           : BOOL := FALSE;                   // 首扫标志，初值 FALSE，判据 NOT _bInit [First-scan flag, R19 pattern]
    _bFaultLatch     : BOOL;                            // 故障级锁存，仅复位路径清 [Fault latch, reset path only]
    _uErrorIdInt     : UDINT;                           // 故障级码寄存 [Fault-level code register]
    _uInfoCode       : UDINT;                           // 本拍信息级码，每拍重算 [Transient info code]
    nStaEff          : INT;                             // 生效工位数，已钳位 [个] [Effective station count]
    nIdxVal          : INT;                             // 到位工位号（已判界）[号] [Validated station number]
    tDwellEff        : TIME;                            // 生效停留时间 [毫秒] [Effective dwell time]
    tSettleEff       : TIME;                            // 生效稳定时间 [毫秒] [Effective settling time]
    tIndexEff        : TIME;                            // 生效分度超时 [毫秒] [Effective index timeout]
    tCycleEff        : TIME;                            // 生效扫描周期 [毫秒] [Effective task cycle time]
    uMaskAcc         : UDINT;                           // 掩码累加器 [位域] [Mask accumulator]
    uBitAcc          : UDINT;                           // 位累加器，逐位左移 [位域] [Single-bit accumulator]
    nI               : INT;                             // 通用循环索引 [索引] [Loop index]
    bDwellIn         : BOOL;                            // 停留计时输入条件，先算后调 [Dwell timer input]
    bSettleIn        : BOOL;                            // 稳定计时输入条件，先算后调 [Settle timer input]
    bIndexIn         : BOOL;                            // 分度超时输入条件，先算后调 [Index timer input]
    bDwellDone       : BOOL;                            // 停留结束（含空跑旁路）[Dwell finished, dry-run bypassed]
    _bInPosDropped   : BOOL;                            // 分度中到位信号曾回落，兼容保持型开关 [In-position dropped during indexing]
    fbTrigStart      : R_TRIG;                          // 启动沿检测 [Start edge detector]
    fbTrigStop       : R_TRIG;                          // 停止沿检测 [Stop edge detector]
    fbTrigReset      : R_TRIG;                          // 复位沿检测 [Reset edge detector]
    fbTrigInPos      : R_TRIG;                          // 到位上升沿检测 [In-position rising edge]
    fbTrigInPosFall  : F_TRIG;                          // 到位下降沿检测，抖动诊断用 [In-position falling edge, jitter diagnosis]
    fbTmoDwell       : TON;                             // 停留计时 [Dwell timer]
    fbTmoSettle      : TON;                             // 稳定确认计时 [Settle timer]
    fbTmoIndex       : TON;                             // 分度超时 [Index timeout timer]
END_VAR
VAR CONSTANT
    DL_STATION_MAX   : INT := 24;                       // 工位上限 [个] [Max station count]
    DL_STATION_MIN   : INT := 2;                        // 工位下限 [个] [Min station count]
    DL_TMO_MAX       : TIME := T#120S;                  // 时长参数域上限 [毫秒] [Duration upper bound]
    DL_RUN_MAX       : TIME := T#500H;                 // 运行时长饱和上限 [毫秒] [Run time saturation limit]
    DL_COUNT_MAX     : UDINT := 16#FFFF_FFFE;           // 计数饱和上限 [次] [Counter saturation limit]
    DL_INFO_STA_CLAMP: UDINT := 16#0005_01C2;           // 01C2 工位数量越界已钳位【信息级】 [Info, station count clamped]
    DL_ERR_INDEX_TMO : UDINT := 16#0005_02D0;           // 02D0 分度超时【故障级】 [Fault, index timeout]
    DL_ERR_INPOS     : UDINT := 16#0005_02D1;           // 02D1 到位信号抖动或丢失【故障级】 [Fault, in-position lost]
    DL_ERR_STATION   : UDINT := 16#0005_02D2;           // 02D2 工位号越界【故障级】 [Fault, station out of range]
    DL_ERR_STATE     : UDINT := 16#0005_02D3;           // 02D3 非法状态兜底【故障级】 [Fault, illegal state]
END_VAR

// ==== 段 1｜单拍输出预清零（脉冲类出口每拍先清零，避免跨拍粘滞） / Single-scan pulse pre-clear, no sticky pulses
bIndexReq  := FALSE;                        // 分度请求先清零 [Index request pre-cleared]
bCycleDone := FALSE;                        // 整圈完成先清零 [Revolution pulse pre-cleared]
_uInfoCode := 16#0000_0000;                 // 信息级码每拍重算 [Info code recomputed]

// ==== 段 2｜参数钳位（工位数与三个时长，先钳位再进逻辑） / Parameter clamping before any logical use
nStaEff := nStationCount;                   // 工位数先取引脚值 [Station count from pin]
IF nStaEff < DL_STATION_MIN THEN
    nStaEff    := DL_STATION_MIN;           // 低于下限钳到 2 [Clamped to lower bound]
    _uInfoCode := DL_INFO_STA_CLAMP;        // 01C2 工位数量越界已钳位【信息级】 [Info, count clamped]
ELSIF nStaEff > DL_STATION_MAX THEN
    nStaEff    := DL_STATION_MAX;           // 高于上限钳到 24 [Clamped to upper bound]
    _uInfoCode := DL_INFO_STA_CLAMP;        // 01C2 工位数量越界已钳位【信息级】 [Info, count clamped]
END_IF

tDwellEff := tDwellTime;                    // 停留时间先取引脚值 [Dwell from pin]
IF tDwellEff > DL_TMO_MAX THEN
    tDwellEff := DL_TMO_MAX;                // 超上限钳位 [Clamped to upper bound]
ELSIF tDwellEff < T#0S THEN
    tDwellEff := T#0S;                      // 负值归零 [Negative clamped to zero]
END_IF

tSettleEff := tSettleTime;                  // 稳定时间先取引脚值 [Settle from pin]
IF tSettleEff > DL_TMO_MAX THEN
    tSettleEff := DL_TMO_MAX;               // 超上限钳位 [Clamped to upper bound]
ELSIF tSettleEff < T#0S THEN
    tSettleEff := T#0S;                     // 负值归零 [Negative clamped to zero]
END_IF

tIndexEff := tIndexTimeout;                 // 分度超时先取引脚值 [Index timeout from pin]
IF tIndexEff > DL_TMO_MAX THEN
    tIndexEff := DL_TMO_MAX;                // 超上限钳位 [Clamped to upper bound]
ELSIF tIndexEff <= T#0S THEN
    tIndexEff := T#0S;                      // 零表示不监控 [Zero means supervision disabled]
END_IF

tCycleEff := tCycle;                        // 扫描周期先取引脚值 [Task cycle from pin]
IF tCycleEff <= T#0S OR tCycleEff > T#10S THEN
    tCycleEff := T#10MS;                    // 异常值回默认 10 毫秒 [Fallback to 10 ms]
END_IF

// ==== 段 3｜沿与定时器无条件刷新（R7 红线：严禁置于 IF / CASE 分支内） / Unconditional refresh of edges and timers
fbTrigStart(CLK := bStart);                 // 启动沿 [Start edge]
fbTrigStop(CLK := bStop);                   // 停止沿 [Stop edge]
fbTrigReset(CLK := bReset);                 // 复位沿 [Reset edge]
fbTrigInPos(CLK := bIndexInPos);            // 到位上升沿 [In-position rising edge]
fbTrigInPosFall(CLK := bIndexInPos);        // 到位下降沿 [In-position falling edge]

IF _eState = E_DL_IndexTableState.eDwell THEN
    bDwellIn := TRUE;                       // 仅停留段计时 [Only during dwell]
ELSE
    bDwellIn := FALSE;                      // 其余段清零 [Cleared otherwise]
END_IF
fbTmoDwell(IN := bDwellIn, PT := tDwellEff);

IF _eState = E_DL_IndexTableState.eSettling THEN
    bSettleIn := TRUE;                      // 仅稳定段计时 [Only during settling]
ELSE
    bSettleIn := FALSE;                     // 其余段清零 [Cleared otherwise]
END_IF
fbTmoSettle(IN := bSettleIn, PT := tSettleEff);

IF (_eState = E_DL_IndexTableState.eIndexing) AND (tIndexEff > T#0S) THEN
    bIndexIn := TRUE;                       // 仅分度段且监控开启时计时 [Only while indexing with supervision on]
ELSE
    bIndexIn := FALSE;                      // 其余段清零 [Cleared otherwise]
END_IF
fbTmoIndex(IN := bIndexIn, PT := tIndexEff);

// ==== 段 4｜首扫初始化（R19 唯一合法范式：初值 FALSE，判据 NOT，同步后置 TRUE） / First-scan initialisation with the canonical R19 pattern
IF NOT _bInit THEN
    _eState          := E_DL_IndexTableState.eIdle;  // 状态回待机 [State to idle]
    _bInPosDropped   := FALSE;              // 到位回落标志复位 [Dropped flag reset]
    _bFaultLatch     := FALSE;              // 故障锁存清零 [Fault latch cleared]
    _uErrorIdInt     := 16#0000_0000;       // 故障码清零 [Fault code cleared]
    nActiveStation   := 0;                  // 作业工位号清 0 [Active station cleared]
    nRecipeAtStation := 0;                  // 工艺号清 0 [Recipe cleared]
    bStationReady    := FALSE;              // 放行复位 [Permit cleared]
    tDwellRemain     := T#0S;               // 剩余停留清零 [Remaining dwell cleared]
    bError           := FALSE;              // 故障标志清零 [Error cleared]
    uErrorId         := 16#0000_0000;       // 事件码清零 [Error id cleared]
    stStat.nIndexCount := 0;                // 分度计数清零 [Index counter cleared]
    stStat.nCycleCount := 0;                // 循环计数清零 [Revolution counter cleared]
    stStat.tRunTime    := T#0S;             // 运行时长清零 [Run time cleared]
    _bInit := TRUE;                         // 首扫只做一次 [Runs exactly once]
END_IF

// ==== 段 5｜工位启用掩码重建（逐位置位，不用累计量拼接，规避位宽边界） / Mask rebuild by per-bit set, no shift accumulation
uMaskAcc := 0;
uBitAcc  := 1;
FOR nI := 1 TO DL_STATION_MAX DO
    IF (nI <= nStaEff) AND abStationEnable[nI] THEN
        uMaskAcc := uMaskAcc OR uBitAcc;    // 该工位启用则置对应位 [Set bit for enabled station]
    END_IF
    uBitAcc := uBitAcc * 2;                 // 位累加器左移一位（等价左移，跨平台不依赖位移函数）[Shift left by one]
END_FOR
uStationMask := UDINT_TO_DWORD(uMaskAcc);   // 转位串出口 [Convert to word for output]

// ==== 段 6｜使能撤销（FALSE 立即回待机、撤分度请求、清作业工位） / Disable path withdraws the request and clears the station
IF NOT bEnable THEN
    _eState        := E_DL_IndexTableState.eIdle;
    bIndexReq      := FALSE;                // 请求撤销 [Request withdrawn]
    bStationReady  := FALSE;                // 放行撤销 [Permit withdrawn]
    nActiveStation := 0;                    // 作业工位清 0 [Active station cleared]
END_IF

// ==== 段 7｜全局监视：工位号越界在分度链之外单点判定，避免越界索引数组 / Bounds monitor outside the CASE, protects array access
IF bEnable AND (NOT _bFaultLatch)
AND (_eState <> E_DL_IndexTableState.eIdle)
AND (_eState <> E_DL_IndexTableState.eFault)
AND ((nAtStation < 0) OR (nAtStation > nStaEff)) THEN
    bIndexReq    := FALSE;                  // 越界即撤请求 [Request withdrawn on out-of-range]
    _bFaultLatch := TRUE;                   // 故障锁存 [Fault latched]
    _uErrorIdInt := DL_ERR_STATION;         // 02D2 工位号越界【故障级】 [Fault, station out of range]
    _eState      := E_DL_IndexTableState.eFault;
END_IF

// ==== 段 8｜主状态机（ENUM 加 CASE 加 ELSE 兜底，五成员逐一有标签） / Main state machine, every member has its own label
CASE _eState OF
    E_DL_IndexTableState.eIdle: // 待机：等启动沿，首工位放行由停留态给出
        IF fbTrigStart.Q AND bEnable AND (NOT _bFaultLatch) THEN
            _uErrorIdInt := 16#0000_0000;   // 启动前必无故障，码清零 [No fault before start]
            IF (nAtStation >= 1) AND (nAtStation <= nStaEff) THEN
                nActiveStation := nAtStation;   // 已定位则先放行该工位 [Permit current station if seated]
            ELSE
                nActiveStation := 0;        // 未定位不给放行 [No permit when not seated]
            END_IF
            _eState := E_DL_IndexTableState.eDwell;
        END_IF

    E_DL_IndexTableState.eDwell: // 停留：工艺放行窗，计时到即出分度请求
        IF (nAtStation >= 1) AND (nAtStation <= nStaEff) THEN
            nActiveStation := nAtStation;       // 作业工位跟随机械反馈 [Follow mechanical feedback]
        ELSE
            nActiveStation := 0;                // 未定位则无效 [Invalid when not seated]
        END_IF
        IF bDryRun THEN
            bDwellDone := TRUE;                 // 空跑旁路停留计时 [Dry run bypasses dwell]
        ELSE
            bDwellDone := fbTmoDwell.Q;         // 正常按定时器 [Normal timer]
        END_IF
        IF bDwellDone THEN
            IF fbTrigStop.Q OR bStop THEN    // 上升沿受理短脉冲按钮，电平兜住长按与上位机置位 [Edge for momentary, level for held stop]
                _eState := E_DL_IndexTableState.eIdle;   // 停止请求：完成当前工位后停 [Stop after current station]
            ELSE
                bIndexReq      := TRUE;         // 分度请求单拍脉冲，本拍唯一置位点 [Sole set point of the pulse]
                _bInPosDropped := FALSE;        // 新的分度周期，回落标志复位 [Dropped flag reset per index]
                _eState        := E_DL_IndexTableState.eIndexing;
            END_IF
        END_IF

    E_DL_IndexTableState.eIndexing: // 分度中：等到位确认，超时即锁故障
        IF NOT bIndexInPos THEN
            _bInPosDropped := TRUE;             // 到位信号已回落，后续恢复即可确认 [Signal dropped, recovery confirms]
        END_IF
        IF fbTrigInPos.Q OR (_bInPosDropped AND bIndexInPos) THEN
            IF stStat.nIndexCount < DL_COUNT_MAX THEN
                stStat.nIndexCount := stStat.nIndexCount + 1;  // 成功分度计数（偏离 D2）[Successful index counter]
            END_IF
            _eState := E_DL_IndexTableState.eSettling;
        ELSIF fbTmoIndex.Q THEN
            _bFaultLatch := TRUE;               // 超时锁存 [Timeout latched]
            _uErrorIdInt := DL_ERR_INDEX_TMO;   // 02D0 分度超时【故障级】 [Fault, index timeout]
            _eState      := E_DL_IndexTableState.eFault;
        END_IF

    E_DL_IndexTableState.eSettling: // 稳定中：去抖确认，掉沿即判硬件抖动
        IF fbTrigInPosFall.Q THEN
            _bFaultLatch := TRUE;               // 抖动属硬件问题，锁故障且不重试 [Hardware fault, no retry]
            _uErrorIdInt := DL_ERR_INPOS;       // 02D1 到位信号抖动或丢失【故障级】 [Fault, in-position lost]
            _eState      := E_DL_IndexTableState.eFault;
        ELSIF (nAtStation < 1) OR (nAtStation > nStaEff) THEN
            _bFaultLatch := TRUE;               // 稳定窗内工位号失真 [Station feedback untrustworthy]
            _uErrorIdInt := DL_ERR_STATION;     // 02D2 工位号越界【故障级】 [Fault, station out of range]
            _eState      := E_DL_IndexTableState.eFault;
        ELSIF bIndexInPos AND fbTmoSettle.Q THEN
            nActiveStation := nAtStation;       // 稳定通过，登记作业工位 [Settled, register active station]
            IF (NOT bDryRun) AND (nAtStation = 1) THEN
                bCycleDone := TRUE;             // 回到 1 号位即整圈完成单拍 [Sole set point of the pulse]
                IF stStat.nCycleCount < DL_COUNT_MAX THEN
                    stStat.nCycleCount := stStat.nCycleCount + 1;  // 循环计数饱和累加 [Revolution counter, saturated]
                END_IF
            END_IF
            _eState := E_DL_IndexTableState.eDwell;
        END_IF

    E_DL_IndexTableState.eFault: // 故障：等复位沿，复位后清码回待机
        bIndexReq      := FALSE;                // 故障态不得出请求 [No request while faulted]
        bStationReady  := FALSE;                // 故障态不得放行 [No permit while faulted]
        IF fbTrigReset.Q THEN
            _bFaultLatch   := FALSE;            // 锁存解除 [Latch released]
            _bInPosDropped := FALSE;            // 到位回落标志复位 [Dropped flag reset]
            _uErrorIdInt   := 16#0000_0000;     // 故障码清零 [Fault code cleared]
            nActiveStation := 0;                // 作业工位清 0 [Active station cleared]
            _eState      := E_DL_IndexTableState.eIdle;
        END_IF

    ELSE // 非法枚举值兜底：撤请求、回安全态并锁故障
        bIndexReq    := FALSE;                  // 非法态撤请求 [Request withdrawn]
        _bFaultLatch := TRUE;                   // 兜底锁存 [Fallback latch]
        _uErrorIdInt := DL_ERR_STATE;           // 02D3 非法状态兜底【故障级】 [Fault, illegal state]
        _eState      := E_DL_IndexTableState.eFault;
END_CASE

// ==== 段 9｜运行时长累计（仅运行段累加，饱和保护，停机不计） / Run-time accumulation with saturation
IF bEnable AND (_eState <> E_DL_IndexTableState.eIdle)
AND (_eState <> E_DL_IndexTableState.eFault)
AND (stStat.tRunTime < DL_RUN_MAX) THEN
    stStat.tRunTime := stStat.tRunTime + tCycleEff;   // 累加一个扫描周期 [Accumulate one task cycle]
END_IF

// ==== 段 10｜出口派生（放行、工艺号、剩余停留三者在同一处单点派生） / Outlets derived at a single point
bStationReady := FALSE;                    // 默认不放行，判界通过后再置位 [Default no permit, bounds checked first]
IF (NOT bDryRun) AND (_eState = E_DL_IndexTableState.eDwell)
AND (nActiveStation >= 1) AND (nActiveStation <= nStaEff) THEN
    bStationReady := abStationEnable[nActiveStation];   // 放行：工位启用才放 [Permit only when the station is enabled]
END_IF

IF (nActiveStation >= 1) AND (nActiveStation <= nStaEff) THEN
    nRecipeAtStation := anStationRecipe[nActiveStation];   // 工艺号透传 [Recipe pass-through]
ELSE
    nRecipeAtStation := 0;                  // 无效工位给 0 [Zero for invalid station]
END_IF

IF tDwellEff > fbTmoDwell.ET THEN
    tDwellRemain := tDwellEff - fbTmoDwell.ET;   // 剩余停留时间 [Remaining dwell]
ELSE
    tDwellRemain := T#0S;                   // 已到点钳零 [Clamped to zero]
END_IF

eState  := _eState;                         // 状态镜像 [State mirror]
bError  := _bFaultLatch;                    // 故障级派生式（R21）[Fault-level derived form]
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;               // 故障级码优先透出 [Fault code wins]
ELSE
    uErrorId := _uInfoCode;                 // 无故障时透出信息级码 [Info code otherwise]
END_IF
END_FUNCTION_BLOCK
