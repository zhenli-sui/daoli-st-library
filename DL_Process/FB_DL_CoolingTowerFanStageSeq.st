(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CoolingTowerFanStageSeq
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-24
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / LIMIT / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 冷却塔风机分级投切与主备轮换：按 nStageCmd（0..4 台）逐台启动 / 逐台停机，
 *                         级间强制间隔 tStageGap，每台启动后 tSpinUpTol 内未见运行反馈则该台
 *                         置 aFanFault 并跳过（站级不锁存，降级继续）；累计运行时长 tRunAccum
 *                         达 nLeadRotateHours 且台数稳定时做**先进后出**主用轮换（先确认新主用
 *                         起来，再停旧主用，避免瞬时欠风量）；命令 0 台 → 逐台全停。
 *                         输出 aFanRun / aFanFault 为**内部数组的状态映射**（段 5 单点出口），
 *                         迁移与出口分离，禁止在出口数组上直接做状态记忆。
 *                         **bStart = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         全部 aFanRun 落 FALSE 并回 eIdle（冷却塔风机不得冻结保持）。
 * 接口     (Interface)  : 输入 bEnable / bStart / bReset（上升沿）/ nStageCmd / tStageGap /
 *                         tSpinUpTol / nLeadRotateHours / nFanCnt / bFanFb[1..4]；
 *                         输出 aFanRun[1..4] / aFanFault[1..4] / nActiveCnt / nLeadIdx /
 *                         eState（E_DL_CtfPhase）/ eCause（E_DL_CtfCause）/ bError / bValid /
 *                         tRunAccum。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eStartup：bEnable 且 bStart 且组态闸通过且 nStageCmd ≥ 1 且无锁存；
 *      拍 N 进入（启动）/ 本拍行为：清 aFanRun / aFanFault / 台数 / 时长、主用置 1 /
 *      拍 N+1 转出至 eStartup。
 *   ② eStartup / eStageUp → 本相内逐台启动：每 tonGap.Q 单拍启动一台（间隔 tStageGap 节拍）；
 *      拍 N 进入（间隔节拍）/ 本拍行为：置 _aFanRun[idx] 与 _nPendFan / 拍 N+1 等反馈。
 *   ③ eStartup / eStageUp → eRunning：nActiveCnt ≥ nStageCmd；拍 N 进入 / 本拍行为：
 *      发信息级 eStageStable / 拍 N+1 转出至 eRunning。
 *   ④ eRunning → eStageUp：nStageCmd 增大导致 nActiveCnt < nStageCmd（拍 N 判出 / 拍 N+1 转出）。
 *   ⑤ eRunning → eStageDown：nStageCmd 减小导致 nActiveCnt > nStageCmd。
 *   ⑥ eRunning → eRotate：tRunAccum ≥ nLeadRotateHours×3600s 且 nActiveCnt = nStageCmd ≥ 1
 *      且无挂起启动（_nPendFan = 0）；本拍行为：选下一台可用风机先启动（先进）/ 拍 N+1 转出至 eRotate。
 *   ⑦ eRotate → eRunning：新主用反馈确认 → nLeadIdx := 新台、旧主用停机（后出）、
 *      tRunAccum 清零；或 tonSpin.Q（新台启动超时）→ 该台置 aFanFault、tRunAccum 清零、
 *      信息级 eFanStartTimeout，仍回 eRunning（主用不变，降级不锁存）。
 *   ⑧ eStageDown → eRunning：nActiveCnt ≤ nStageCmd；每 tonGap.Q 单拍停一台（先停非主用，
 *      取最大下标；仅剩主用时才停主用并把主用转移到仍运行的最小下标）。
 *   ⑨ eStartup / eStageUp → eFault：命令台数不可达（_nPickIdx = 0 而 nActiveCnt < nStageCmd），
 *      锁存 eStageUnreachable（段尾迁移闸，R21）。
 *   ⑩ 任一运行相 → eFault：所有已命令风机持续无反馈达 tSpinUpTol（tonNoFb.Q），
 *      锁存 eAllFansNoFeedback。
 *   ⑪ eFault → eIdle：bReset 上升沿（R_TRIG 判 .Q）且 bEnable = FALSE（可达性自证 R152：
 *      两引脚外部恒可达，R19 穷举出口）；拍 N 进入 / 本拍行为：清锁存与成因 / 拍 N+1 转出 eIdle。
 *   ⑫ ELSE（非法枚举值）→ eFault，成因 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 三个 TON（tonGap / tonSpin / tonNoFb）与 tonRun、R_TRIG 一律在 CASE 外
 *                            无条件调用（R7）；tonGap / tonSpin / tonNoFb 的 IN 均含 NOT .Q 自复位项
 *                            （R188），不依赖外部沿清零；tonGap.Q 为**单拍节拍**（自复位后仅驻留
 *                            一扫描），故每拍最多投切一台，天然限速。
 *                         ② 级间节拍自进入投切相起算（首台亦等 tStageGap），工程上留出启动冲击间隔；
 *                            若需首台立即启动，请在外部把 tStageGap 设为较小值。
 *                         ③ 数组下标安全：_nFanClamp := LIMIT(1, nFanCnt, 4)，全部 FOR 与下标访问
 *                            只用定长 1..4 与 _nFanClamp，结构性无越界（R17 定长数组）。
 *                         ④ 台数累计 run 时长用 DINT 秒累加（_diRunSec，每 1s 节拍 +1），避免 TIME
 *                            加法与乘法跨型溢出；阈值 _diRotNeed := INT_TO_DINT(h)×3600（DINT 域内）。
 *                         ⑤ 无除法、无浮点比较，故无除零与容差问题（R4）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_CtfPhase / E_DL_CtfCause 归属本文件（全库唯一属主，R264）。
 *                         信息级（0..9）永不置 bError；故障级（10 起）赋值处一律与 _bFaultLatch
 *                         三行成对（R45），故障锁存后回放至 bReset 沿（FB33-1）。
 * 分工声明 (Scope)      : 单台风机电机保护 / 变频器故障字归 DL_Device 侧驱动件；冷却塔出水温度
 *                         PID 归 FB_DL_CoolingTowerReset / 温度回路件；本件只做**台数分级投切时序
 *                         与主备轮换**，不做温度闭环。风机反馈缺失的台级降级在此件完成，
 *                         不向上层抛故障（仅不可达 / 全无反馈才锁存）。
 * 归属     (Ownership)  : E_DL_CtfPhase / E_DL_CtfCause 归属本文件（全库唯一定义，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 无除零/无浮点比较 +
 *                         整数域闸 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ 七态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 全部 TON/R_TRIG 在 CASE 外 ｜ R8/R9 N/A（无 METHOD）｜ R10 ✓ 无构造式
 *                         转换（INT_TO_DINT / DINT_TO_TIME）｜ R14 ✓ 无 PROPERTY ｜ R15 ✓ 无保留字
 *                         撞名（aDuty 类多字母数组名）｜ R17 ✓ 定长 ARRAY[1..4] ｜ R18 ✓ bReset 用
 *                         R_TRIG 判 .Q ｜ R19 ✓ eFault 出口 = bReset 沿 + 撤使能 ｜ R20 ✓ 启动等
 *                         反馈相带 tonSpin 超时 ｜ R21 ✓ 锁存与迁相分离（段尾迁移闸）。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R79-B 首版
 * 验收向量 (Acceptance) :
 *   V1 nFanCnt=3、nStageCmd=2、tStageGap=T#10S、tSpinUpTol=T#15S、bFanFb 全 TRUE：
 *      bEnable=bStart=TRUE → eStartup；第 1 个 tGap 节拍 aFanRun[1]=TRUE、nActiveCnt=1；
 *      第 2 个节拍 aFanRun[2]=TRUE、nActiveCnt=2 → eRunning、nLeadIdx=1、bValid=TRUE。
 *   V2 续 V1，nStageCmd 由 2 改 0 → eStageDown，每节拍停一台（先停非主用，最大下标优先）：
 *      先停 aFanRun[2] 再停 aFanRun[1]，nActiveCnt=0、全部 aFanRun=FALSE。
 *   V3 续 V1，nStageCmd=1 且 aFanRun[1]=TRUE 而 bFanFb[1] 始终 FALSE → tSpinUpTol 后
 *      aFanFault[1]=TRUE、aFanRun[1]=FALSE、eCause=eFanStartTimeout（信息级，bError=FALSE）、
 *      随后启动第 2 台，bError 保持 FALSE（单台降级不锁存）。
 *   V4 nFanCnt=5（越界）→ eState=eFault、eCause=eBadConfig、bError=TRUE、aFanRun 全 FALSE；
 *      bReset 上升沿且 bEnable=FALSE → 回 eIdle、bError=FALSE。
 *   V5 nLeadRotateHours=1 且台数稳定于 2 台（3# 备用）：tRunAccum 达 T#1H 后 → eRotate，
 *      先启动 aFanRun[3]（先进），确认后 nLeadIdx=3 且 aFanRun[1] 停（后出），tRunAccum 清零。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CtfPhase（冷却塔风机分级投切相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CtfPhase :
(
    eIdle     := 0,    // 空闲：未启动，全部风机停 / Idle: not started, all fans off
    eStartup  := 10,   // 启动相：从 0 台逐台升到命令台数 / Startup: ramp fan count up to the command
    eRunning  := 20,   // 运行相：台数已达命令值，监视与轮换判 / Running: count reached, monitor and rotation check
    eStageUp  := 30,   // 加台相：命令台数增大，逐台补启动 / Stage up: command increased, add fans one by one
    eStageDown := 40,  // 减台相：命令台数减小，逐台停机 / Stage down: command decreased, stop fans one by one
    eRotate   := 50,   // 轮换相：主用先进后出换台 / Rotate: lead change with start-before-stop
    eFault    := 90    // 故障安全相：锁存成因，风机全停 / Fault safe phase: latched cause, all fans off
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CtfCause（成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CtfCause :
(
    eNone           := 0,   // 信息级：无事件 / Info: no event
    eStageStable    := 1,   // 信息级：台数与命令一致 / Info: active count matches the command
    eFanUp          := 2,   // 信息级：一台已启动并确认 / Info: one fan started and confirmed
    eFanDown        := 3,   // 信息级：一台已停机 / Info: one fan stopped
    eFanStartTimeout := 4,  // 信息级：单台启动超时，该台置 aFanFault 并跳过 / Info: one fan spin-up timeout, marked faulty and skipped
    eRotateDone     := 5,   // 信息级：主用轮换完成 / Info: lead rotation completed
    eRotateSkip     := 6,   // 信息级：无可轮换风机，本次轮换取消 / Info: no rotatable fan, rotation cancelled
    eAllFansNoFeedback := 10, // 故障级：已命令风机全部无反馈 / Fault: all commanded fans report no feedback
    eStageUnreachable  := 11, // 故障级：无可用风机可达命令台数 / Fault: fan count unreachable with the available fans
    eBadConfig      := 12,  // 故障级：台数/命令/时间参数越域 / Fault: count, command or time parameter out of domain
    eIllegalState   := 13   // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoolingTowerFanStageSeq
VAR_INPUT
    bEnable          : BOOL := FALSE;              // 使能：FALSE 撤全部启动命令并回 eIdle / Enable, FALSE withdraws all fan commands
    bStart           : BOOL := FALSE;              // 启动（电平）：FALSE 动作全撤 / Start level, FALSE withdraws every command
    bReset           : BOOL := FALSE;              // 复位（上升沿，需同时 bEnable=FALSE）/ Reset rising edge, requires bEnable FALSE
    nStageCmd        : INT := 0;                   // 目标风机台数，有效域 0..nFanCnt [台] / Target fan count, valid domain 0..nFanCnt
    tStageGap         : TIME := T#10S;             // 级间投切间隔，域 ≥ 100ms [s] / Inter-stage gap, domain >= 100ms
    tSpinUpTol        : TIME := T#15S;             // 单台启动确认超时，域 ≥ 100ms [s] / Spin-up confirmation timeout, domain >= 100ms
    nLeadRotateHours  : INT := 0;                  // 主备轮换小时数，0 = 不轮换，域 0..1000 [h] / Lead rotation hours, 0 disables it
    nFanCnt           : INT := 2;                  // 装机风机台数，有效域 1..4 [台] / Installed fan count, valid domain 1..4
    bFanFb            : ARRAY[1..4] OF BOOL;       // 各风机运行反馈（TRUE = 在转）[#] / Per-fan running feedback, TRUE means spinning
END_VAR
VAR_OUTPUT
    aFanRun          : ARRAY[1..4] OF BOOL;        // 各风机启动命令（内部状态映射，段 5 单点出口）[#] / Per-fan run command mapped at the tail
    aFanFault        : ARRAY[1..4] OF BOOL;        // 各风机故障标记（启动超时置位，eIdle 清除）[#] / Per-fan fault flag, set on spin-up timeout
    nActiveCnt       : INT := 0;                   // 当前在运行风机台数 [台] / Number of running fans
    nLeadIdx         : INT := 0;                   // 当前主用风机下标（1 起，0 = 无）[#] / Current lead fan index, 0 means none
    eState           : E_DL_CtfPhase;              // 状态出口（段尾单点映射）[-] / State outlet mapped at the tail
    eCause           : E_DL_CtfCause;              // 成因码出口（故障期锁存回放）[-] / Cause code outlet
    bError           : BOOL;                       // 故障锁存标志 [-] / Fault latch flag
    bValid           : BOOL;                       // 时序有效回执（投切/运行相且无锁存）[-] / Sequence validity receipt
    tRunAccum        : TIME := T#0S;               // 本轮累计运行时长（供主备轮换）[s] / Accumulated run time of this round
END_VAR
VAR
    _eState          : E_DL_CtfPhase := E_DL_CtfPhase.eIdle;  // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch     : BOOL := FALSE;                          // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch     : E_DL_CtfCause := E_DL_CtfCause.eNone;    // 锁存成因码（FB33-1 锁存回放）[-] / Latched cause code
    _eCauseTmp       : E_DL_CtfCause := E_DL_CtfCause.eNone;    // 本拍首因中间量（段 5 用）[-] / First cause of this scan
    _bCfgOk          : BOOL := TRUE;                           // 组态域闸通过标志 [-] / Configuration gate flag
    _bResetPulse     : BOOL := FALSE;                          // bReset 上升沿快照（R18）[-] / bReset rising-edge snapshot
    _nFanClamp       : INT := 1;                               // 装机台数钳位值 1..4 [台] / Clamped installed fan count
    _nPendFan        : INT := 0;                               // 挂起待确认的启动风机下标，0 = 无 [台] / Pending fan index awaiting confirmation
    _nOldLead        : INT := 0;                               // 轮换中旧主用下标（先进后出用）[#] / Old lead index during rotation
    _nPickIdx        : INT := 0;                               // 本拍选中的风机下标，0 = 未选中 [台] / Fan index picked in this scan
    _nIdx            : INT := 1;                               // 遍历下标（FOR 专用）[台] / Loop index for FOR statements
    _aFanRun         : ARRAY[1..4] OF BOOL;                    // 内部启动命令状态数组 [#] / Internal run-command state array
    _aFanFault       : ARRAY[1..4] OF BOOL;                    // 内部风机故障状态数组 [#] / Internal fan-fault state array
    _bAnyRun         : BOOL := FALSE;                          // 存在已命令风机标志 [-] / At least one fan commanded
    _bAnyFb          : BOOL := FALSE;                          // 存在已命令且有反馈风机标志 [-] / At least one commanded fan reports feedback
    _diRunSec        : DINT := 0;                              // 运行时长秒累加（DINT 防跨型溢出）[s] / Accumulated run seconds in DINT
    _diRotNeed       : DINT := 0;                              // 轮换阈值秒数 = 小时 × 3600，0 = 不轮换 [s] / Rotation threshold in seconds
    rtReset          : R_TRIG;                                 // bReset 边沿实例（段 2 无条件调用，R18）/ bReset edge instance called unconditionally
    tonGap           : TON;                                    // 级间节拍定时器（段 2 无条件调用）/ Inter-stage tick timer called unconditionally
    tonSpin          : TON;                                    // 单台启动确认超时（段 2 无条件调用）/ Spin-up confirmation timeout called unconditionally
    tonNoFb          : TON;                                    // 全无反馈持续判（段 2 无条件调用）/ All-fans-no-feedback persistence timer
    tonRun           : TON;                                    // 运行时长 1s 累加节拍（段 2 无条件调用）/ One-second accumulation tick timer
END_VAR
VAR CONSTANT
    DL_CTF_ZERO          : INT := 0;               // 整数零基准 [-] / Integer zero base
    DL_CTF_ONE           : INT := 1;               // 整数一起始（下标与计数）[#] / Integer one base
    DL_CTF_FAN_MAX       : INT := 4;               // 风机台数上限（数组定长）[台] / Upper bound of fans, fixed array size
    DL_CTF_ROT_MAX       : INT := 1000;            // 轮换小时数上限 [h] / Upper bound of rotation hours
    DL_CTF_GAP_MIN       : TIME := T#100MS;        // 级间间隔下限 [s] / Lower bound of the inter-stage gap
    DL_CTF_TOL_MIN       : TIME := T#100MS;        // 启动确认超时下限 [s] / Lower bound of the spin-up timeout
    DL_CTF_ONESC         : TIME := T#1S;           // 一秒累加节拍 [s] / One-second accumulation tick
    DL_CTF_SEC_PER_HOUR  : DINT := 3600;           // 每小时秒数 [s/h] / Seconds per hour
    DL_CTF_ROT_ZERO      : DINT := 0;              // DINT 零基准（轮换阈值比较）[-] / DINT zero base
END_VAR

(* —— 段 1：当拍中间量预置（不清锁存 / 数组状态 / 时长累加器，FB32-1） —— *)
_bCfgOk    := TRUE;                                    // 组态闸标志复位 / Configuration gate flag reset
_eCauseTmp := E_DL_CtfCause.eNone;                      // 当拍首因复位 / Scan cause reset
_nPickIdx  := DL_CTF_ZERO;                             // 选中下标复位 / Picked index reset
_bAnyRun   := FALSE;                                   // 已命令标志复位 / Commanded flag reset
_bAnyFb    := FALSE;                                   // 有反馈标志复位 / Feedback flag reset

(* —— 段 2：入参钳位与阈值换算（整数跨型只用标准转换，R10） —— *)
_nFanClamp := LIMIT(DL_CTF_ONE, nFanCnt, DL_CTF_FAN_MAX);                 // 台数钳位 1..4，保证下标安全 / Clamp the fan count for safe indexing
_diRotNeed := INT_TO_DINT(nLeadRotateHours) * DL_CTF_SEC_PER_HOUR;        // 轮换阈值秒数（DINT 域内不溢出）/ Rotation threshold in seconds

(* —— 段 3：组态域闸（台数 / 命令 / 时间参数，R4） —— *)
IF (nFanCnt < DL_CTF_ONE) OR (nFanCnt > DL_CTF_FAN_MAX) THEN
    _bCfgOk    := FALSE;                               // 装机台数越域 / Installed fan count out of domain
    _eCauseTmp := E_DL_CtfCause.eBadConfig;            // 故障级：组态非法 / Fault: bad configuration
ELSIF (nStageCmd < DL_CTF_ZERO) OR (nStageCmd > DL_CTF_FAN_MAX) THEN
    _bCfgOk    := FALSE;                               // 命令台数越域 / Commanded fan count out of domain
    _eCauseTmp := E_DL_CtfCause.eBadConfig;            // 故障级：组态非法 / Fault: bad configuration
ELSIF nStageCmd > nFanCnt THEN
    _bCfgOk    := FALSE;                               // 命令台数超过装机台数 / Command exceeds the installed fan count
    _eCauseTmp := E_DL_CtfCause.eBadConfig;            // 故障级：组态非法 / Fault: bad configuration
ELSIF tStageGap < DL_CTF_GAP_MIN THEN
    _bCfgOk    := FALSE;                               // 级间间隔过小 / Inter-stage gap too small
    _eCauseTmp := E_DL_CtfCause.eBadConfig;            // 故障级：组态非法 / Fault: bad configuration
ELSIF tSpinUpTol < DL_CTF_TOL_MIN THEN
    _bCfgOk    := FALSE;                               // 启动确认超时过小 / Spin-up timeout too small
    _eCauseTmp := E_DL_CtfCause.eBadConfig;            // 故障级：组态非法 / Fault: bad configuration
ELSIF (nLeadRotateHours < DL_CTF_ZERO) OR (nLeadRotateHours > DL_CTF_ROT_MAX) THEN
    _bCfgOk    := FALSE;                               // 轮换小时数越域 / Rotation hours out of domain
    _eCauseTmp := E_DL_CtfCause.eBadConfig;            // 故障级：组态非法 / Fault: bad configuration
END_IF

(* —— 段 4：边沿与定时器（CASE 外无条件调用，R7；IN 均含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                                // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
_bResetPulse := rtReset.Q;                             // 边沿快照 / Edge snapshot
tonGap(IN := ((_eState = E_DL_CtfPhase.eStartup) OR (_eState = E_DL_CtfPhase.eStageUp)
              OR (_eState = E_DL_CtfPhase.eStageDown) OR (_eState = E_DL_CtfPhase.eRotate))
             AND (NOT tonGap.Q) AND (NOT _bFaultLatch),
       PT := tStageGap);                               // 投切相内周期性单拍节拍 / Periodic single-scan tick inside the staging phases
tonSpin(IN := (_nPendFan > DL_CTF_ZERO) AND (NOT tonSpin.Q) AND (NOT _bFaultLatch),
        PT := tSpinUpTol);                             // 挂起风机启动确认超时 / Spin-up timeout of the pending fan
tonRun(IN := (_eState = E_DL_CtfPhase.eRunning) AND (nActiveCnt >= DL_CTF_ONE)
       AND (NOT tonRun.Q) AND (NOT _bFaultLatch),
       PT := DL_CTF_ONESC);                            // 运行相且至少一台在转时 1s 累加（0 台不计时）/ One-second tick only while running with at least one fan
IF tonRun.Q THEN
    _diRunSec := _diRunSec + 1;                        // 运行时长 1s 累加 / Accumulate one second of run time
END_IF
(* 全无反馈判据：已命令风机中无一返回反馈（用上一拍数组状态，一拍延迟已在头注声明） *)
FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
    IF _aFanRun[_nIdx] THEN
        _bAnyRun := TRUE;                              // 存在已命令风机 / At least one fan commanded
        IF bFanFb[_nIdx] THEN
            _bAnyFb := TRUE;                           // 该台有反馈 / This fan reports feedback
        END_IF
    END_IF
END_FOR
tonNoFb(IN := _bAnyRun AND (NOT _bAnyFb) AND (NOT tonNoFb.Q) AND (NOT _bFaultLatch),
        PT := tSpinUpTol);                             // 全无反馈持续判（超时锁存故障）/ Persistence check for the total feedback loss

(* —— 段 5：状态机主体（唯一相位写入点；故障只在分支内置锁存，迁相由段 7 统一执行） —— *)
CASE _eState OF
    E_DL_CtfPhase.eIdle :
        FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
            _aFanRun[_nIdx]   := FALSE;                // 空闲：启动命令全撤 / Idle: all run commands withdrawn
            _aFanFault[_nIdx] := FALSE;                // 空闲：台级故障标志清除 / Idle: per-fan fault flags cleared
        END_FOR
        nActiveCnt := DL_CTF_ZERO;                     // 台数清零 / Active count zeroed
        _nPendFan  := DL_CTF_ZERO;                     // 挂起启动清除 / Pending start cleared
        IF bEnable AND bStart AND _bCfgOk AND (nStageCmd > DL_CTF_ZERO) AND (NOT _bFaultLatch) THEN
            nLeadIdx        := DL_CTF_ONE;             // 主用默认第 1 台 / Lead defaults to fan one
            _diRunSec       := DL_CTF_ROT_ZERO;        // 运行时长清零 / Run seconds cleared
            _nOldLead       := DL_CTF_ZERO;            // 旧主用清零 / Old lead cleared
            eCause          := E_DL_CtfCause.eNone;    // 信息级：无事件 / Info: no event
            _eState         := E_DL_CtfPhase.eStartup; // 迁移①：进入启动相 / Move to startup
        END_IF

    E_DL_CtfPhase.eStartup :
        IF (NOT bEnable) OR (NOT bStart) THEN
            FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
                _aFanRun[_nIdx] := FALSE;              // 失能：启动命令全撤 / Disabled: withdraw all commands
            END_FOR
            nActiveCnt := DL_CTF_ZERO;                 // 台数清零 / Active count zeroed
            _nPendFan  := DL_CTF_ZERO;                 // 挂起启动清除 / Pending start cleared
            eCause     := E_DL_CtfCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_CtfPhase.eIdle;         // 回空闲相 / Back to idle
        ELSIF nActiveCnt >= nStageCmd THEN
            eCause  := E_DL_CtfCause.eStageStable;     // 迁移③：台数已达命令值 / Count reached: stable
            _eState := E_DL_CtfPhase.eRunning;         // 进入运行相 / Move to running
        ELSIF _nPendFan > DL_CTF_ZERO THEN
            IF bFanFb[_nPendFan] THEN
                _nPendFan := DL_CTF_ZERO;              // 反馈到位：清挂起 / Feedback seen: clear the pending fan
                eCause    := E_DL_CtfCause.eFanUp;     // 信息级：一台已确认 / Info: one fan confirmed
            ELSIF tonSpin.Q THEN
                _aFanRun[_nPendFan]   := FALSE;        // 启动超时：撤该台命令 / Spin-up timeout: withdraw this command
                _aFanFault[_nPendFan] := TRUE;         // 该台置故障并跳过 / Mark this fan faulty and skip it
                nActiveCnt := nActiveCnt - DL_CTF_ONE; // 台数回退（该台未起）/ Roll the count back
                _nPendFan  := DL_CTF_ZERO;             // 清挂起 / Clear the pending fan
                eCause     := E_DL_CtfCause.eFanStartTimeout; // 信息级：单台超时降级 / Info: per-fan timeout degrade
            END_IF
        ELSIF tonGap.Q THEN
            _nPickIdx := DL_CTF_ZERO;                  // 选台前复位 / Reset the pick index
            FOR _nIdx := 1 TO _nFanClamp DO
                IF (_nPickIdx = DL_CTF_ZERO) AND (NOT _aFanRun[_nIdx]) AND (NOT _aFanFault[_nIdx]) THEN
                    _nPickIdx := _nIdx;                // 取最小可启动下标（未运行且无故障）/ Lowest startable index
                END_IF
            END_FOR
            IF _nPickIdx > DL_CTF_ZERO THEN
                _aFanRun[_nPickIdx] := TRUE;           // 迁移②：发该台启动命令 / Issue the start command
                nActiveCnt := nActiveCnt + DL_CTF_ONE; // 台数 +1 / Increment the count
                _nPendFan  := _nPickIdx;               // 挂起等反馈 / Pending confirmation
                IF nActiveCnt = DL_CTF_ONE THEN
                    nLeadIdx := _nPickIdx;             // 首台即主用 / The first fan becomes the lead
                END_IF
            ELSE
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_CtfCause.eStageUnreachable; // 故障级：台数不可达 / Fault: count unreachable
                    _bFaultLatch := TRUE;              // 置故障锁存（迁相由段 7 执行，R21）/ Latch the fault, phase moved at the tail
                END_IF
            END_IF
        END_IF

    E_DL_CtfPhase.eStageUp :
        IF (NOT bEnable) OR (NOT bStart) THEN
            FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
                _aFanRun[_nIdx] := FALSE;              // 失能：启动命令全撤 / Disabled: withdraw all commands
            END_FOR
            nActiveCnt := DL_CTF_ZERO;                 // 台数清零 / Active count zeroed
            _nPendFan  := DL_CTF_ZERO;                 // 挂起启动清除 / Pending start cleared
            eCause     := E_DL_CtfCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_CtfPhase.eIdle;         // 回空闲相 / Back to idle
        ELSIF nActiveCnt >= nStageCmd THEN
            eCause  := E_DL_CtfCause.eStageStable;     // 台数已达命令值 / Count reached: stable
            _eState := E_DL_CtfPhase.eRunning;         // 回运行相 / Back to running
        ELSIF _nPendFan > DL_CTF_ZERO THEN
            IF bFanFb[_nPendFan] THEN
                _nPendFan := DL_CTF_ZERO;              // 反馈到位：清挂起 / Feedback seen: clear the pending fan
                eCause    := E_DL_CtfCause.eFanUp;     // 信息级：一台已确认 / Info: one fan confirmed
            ELSIF tonSpin.Q THEN
                _aFanRun[_nPendFan]   := FALSE;        // 启动超时：撤该台命令 / Spin-up timeout: withdraw this command
                _aFanFault[_nPendFan] := TRUE;         // 该台置故障并跳过 / Mark this fan faulty and skip it
                nActiveCnt := nActiveCnt - DL_CTF_ONE; // 台数回退 / Roll the count back
                _nPendFan  := DL_CTF_ZERO;             // 清挂起 / Clear the pending fan
                eCause     := E_DL_CtfCause.eFanStartTimeout; // 信息级：单台超时降级 / Info: per-fan timeout degrade
            END_IF
        ELSIF tonGap.Q THEN
            _nPickIdx := DL_CTF_ZERO;                  // 选台前复位 / Reset the pick index
            FOR _nIdx := 1 TO _nFanClamp DO
                IF (_nPickIdx = DL_CTF_ZERO) AND (NOT _aFanRun[_nIdx]) AND (NOT _aFanFault[_nIdx]) THEN
                    _nPickIdx := _nIdx;                // 取最小可启动下标 / Lowest startable index
                END_IF
            END_FOR
            IF _nPickIdx > DL_CTF_ZERO THEN
                _aFanRun[_nPickIdx] := TRUE;           // 迁移②：发该台启动命令 / Issue the start command
                nActiveCnt := nActiveCnt + DL_CTF_ONE; // 台数 +1 / Increment the count
                _nPendFan  := _nPickIdx;               // 挂起等反馈 / Pending confirmation
            ELSE
                IF NOT _bFaultLatch THEN
                    _eCauseLatch := E_DL_CtfCause.eStageUnreachable; // 故障级：台数不可达 / Fault: count unreachable
                    _bFaultLatch := TRUE;              // 置故障锁存（迁相由段 7 执行，R21）/ Latch the fault, phase moved at the tail
                END_IF
            END_IF
        END_IF

    E_DL_CtfPhase.eRunning :
        IF (NOT bEnable) OR (NOT bStart) THEN
            FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
                _aFanRun[_nIdx] := FALSE;              // 失能：启动命令全撤 / Disabled: withdraw all commands
            END_FOR
            nActiveCnt := DL_CTF_ZERO;                 // 台数清零 / Active count zeroed
            _nPendFan  := DL_CTF_ZERO;                 // 挂起启动清除 / Pending start cleared
            eCause     := E_DL_CtfCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_CtfPhase.eIdle;         // 回空闲相 / Back to idle
        ELSIF nActiveCnt < nStageCmd THEN
            eCause  := E_DL_CtfCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_CtfPhase.eStageUp;         // 迁移④：命令增大 → 加台相 / Command increased: stage up
        ELSIF nActiveCnt > nStageCmd THEN
            eCause  := E_DL_CtfCause.eNone;            // 信息级：无事件 / Info: no event
            _eState := E_DL_CtfPhase.eStageDown;       // 迁移⑤：命令减小 → 减台相 / Command decreased: stage down
        ELSIF (_diRotNeed > DL_CTF_ROT_ZERO) AND (_diRunSec >= _diRotNeed)
              AND (nActiveCnt = nStageCmd) AND (nActiveCnt >= DL_CTF_ONE) AND (_nPendFan = DL_CTF_ZERO) THEN
            _nPickIdx := DL_CTF_ZERO;                  // 候选新主用下标复位 / Candidate index reset
            FOR _nIdx := 1 TO _nFanClamp DO
                IF (_nPickIdx = DL_CTF_ZERO) AND (NOT _aFanRun[_nIdx]) AND (NOT _aFanFault[_nIdx])
                   AND (_nIdx <> nLeadIdx) THEN
                    _nPickIdx := _nIdx;                // 取下一个可用备台（最小下标）/ Next available standby fan
                END_IF
            END_FOR
            IF _nPickIdx > DL_CTF_ZERO THEN
                _nOldLead            := nLeadIdx;      // 记录旧主用 / Record the old lead
                _aFanRun[_nPickIdx]  := TRUE;          // 迁移⑥：先进 —— 先启动新主用 / Start the new lead first
                nActiveCnt           := nActiveCnt + DL_CTF_ONE; // 过渡期多一台（瞬时加台，不欠风量）/ Temporary extra fan
                _nPendFan            := _nPickIdx;     // 挂起等确认 / Pending confirmation
                eCause               := E_DL_CtfCause.eNone; // 信息级：无事件 / Info: no event
                _eState              := E_DL_CtfPhase.eRotate; // 进入轮换相 / Move to rotation
            ELSE
                _diRunSec := DL_CTF_ROT_ZERO;          // 无备台：时长清零避免每拍重试 / No standby: clear the counter
                eCause    := E_DL_CtfCause.eRotateSkip; // 信息级：轮换取消 / Info: rotation cancelled
            END_IF
        ELSE
            eCause := E_DL_CtfCause.eStageStable;      // 信息级：台数稳定 / Info: count stable
        END_IF

    E_DL_CtfPhase.eStageDown :
        IF (NOT bEnable) OR (NOT bStart) THEN
            FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
                _aFanRun[_nIdx] := FALSE;              // 失能：启动命令全撤 / Disabled: withdraw all commands
            END_FOR
            nActiveCnt := DL_CTF_ZERO;                 // 台数清零 / Active count zeroed
            _nPendFan  := DL_CTF_ZERO;                 // 挂起启动清除 / Pending start cleared
            eCause     := E_DL_CtfCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_CtfPhase.eIdle;         // 回空闲相 / Back to idle
        ELSIF nActiveCnt <= nStageCmd THEN
            eCause  := E_DL_CtfCause.eStageStable;     // 台数已降至命令值 / Count reduced to the command
            _eState := E_DL_CtfPhase.eRunning;         // 回运行相 / Back to running
        ELSIF tonGap.Q THEN
            _nPickIdx := DL_CTF_ZERO;                  // 停机候选复位 / Stop candidate reset
            FOR _nIdx := 1 TO _nFanClamp DO
                IF _aFanRun[_nIdx] AND (_nIdx <> nLeadIdx) THEN
                    _nPickIdx := _nIdx;                // 先停非主用（取最大下标，后投先停）/ Stop non-lead first, highest index
                END_IF
            END_FOR
            IF _nPickIdx = DL_CTF_ZERO THEN
                _nPickIdx := nLeadIdx;                 // 仅剩主用时才停主用 / Only the lead remains: stop it as well
            END_IF
            IF (_nPickIdx >= DL_CTF_ONE) AND (_nPickIdx <= DL_CTF_FAN_MAX) AND _aFanRun[_nPickIdx] THEN
                _aFanRun[_nPickIdx] := FALSE;          // 迁移⑧：停该台 / Stop this fan
                nActiveCnt := nActiveCnt - DL_CTF_ONE; // 台数 -1 / Decrement the count
                eCause     := E_DL_CtfCause.eFanDown;  // 信息级：一台已停 / Info: one fan stopped
                IF _nPickIdx = nLeadIdx THEN
                    nLeadIdx := DL_CTF_ZERO;           // 主用被停：先清主用 / Lead stopped: clear it first
                    FOR _nIdx := 1 TO _nFanClamp DO
                        IF (nLeadIdx = DL_CTF_ZERO) AND _aFanRun[_nIdx] THEN
                            nLeadIdx := _nIdx;         // 主用转移到仍运行的最小下标 / Move the lead to the lowest running fan
                        END_IF
                    END_FOR
                END_IF
            END_IF
        END_IF

    E_DL_CtfPhase.eRotate :
        IF (NOT bEnable) OR (NOT bStart) THEN
            FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
                _aFanRun[_nIdx] := FALSE;              // 失能：启动命令全撤 / Disabled: withdraw all commands
            END_FOR
            nActiveCnt := DL_CTF_ZERO;                 // 台数清零 / Active count zeroed
            _nPendFan  := DL_CTF_ZERO;                 // 挂起启动清除 / Pending start cleared
            _nOldLead  := DL_CTF_ZERO;                 // 旧主用清零 / Old lead cleared
            eCause     := E_DL_CtfCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_CtfPhase.eIdle;         // 回空闲相 / Back to idle
        ELSIF _nPendFan > DL_CTF_ZERO THEN
            IF bFanFb[_nPendFan] THEN
                nLeadIdx             := _nPendFan;     // 迁移⑦：新主用确认，交接 / New lead confirmed: hand over
                IF (_nOldLead >= DL_CTF_ONE) AND (_nOldLead <= DL_CTF_FAN_MAX) THEN
                    _aFanRun[_nOldLead] := FALSE;      // 后出：再停旧主用 / Stop the old lead afterwards
                    nActiveCnt := nActiveCnt - DL_CTF_ONE; // 过渡多出的一台回退 / Roll back the temporary extra fan
                END_IF
                _nPendFan := DL_CTF_ZERO;              // 清挂起 / Clear the pending fan
                _nOldLead := DL_CTF_ZERO;              // 清旧主用 / Clear the old lead
                _diRunSec := DL_CTF_ROT_ZERO;          // 轮换完成，时长重新累计 / Rotation done: restart the run counter
                eCause    := E_DL_CtfCause.eRotateDone; // 信息级：轮换完成 / Info: rotation completed
                _eState   := E_DL_CtfPhase.eRunning;   // 回运行相 / Back to running
            ELSIF tonSpin.Q THEN
                _aFanRun[_nPendFan]   := FALSE;        // 新主用启动超时：撤命令 / New lead spin-up timeout: withdraw
                _aFanFault[_nPendFan] := TRUE;         // 该台置故障 / Mark this fan faulty
                nActiveCnt := nActiveCnt - DL_CTF_ONE; // 过渡台数回退 / Roll back the temporary fan
                _nPendFan  := DL_CTF_ZERO;             // 清挂起 / Clear the pending fan
                _nOldLead  := DL_CTF_ZERO;             // 清旧主用（主用不变）/ Clear the old lead, keep the lead
                _diRunSec  := DL_CTF_ROT_ZERO;         // 时长清零避免每拍重试 / Clear the counter to avoid retry storms
                eCause     := E_DL_CtfCause.eFanStartTimeout; // 信息级：降级不锁存 / Info: degrade without latching
                _eState    := E_DL_CtfPhase.eRunning;  // 回运行相 / Back to running
            END_IF
        END_IF

    E_DL_CtfPhase.eFault :
        FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
            _aFanRun[_nIdx] := FALSE;                  // 故障相：启动命令全撤（安全侧）/ Fault phase: all commands withdrawn
        END_FOR
        nActiveCnt := DL_CTF_ZERO;                     // 台数清零 / Active count zeroed
        _nPendFan  := DL_CTF_ZERO;                     // 挂起启动清除 / Pending start cleared
        IF _bResetPulse AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                     // 迁移⑪：清故障锁存 / Clear the fault latch
            _eCauseLatch := E_DL_CtfCause.eNone;       // 清锁存成因 / Clear the latched cause
            eCause       := E_DL_CtfCause.eNone;       // 出口同步归零 / Outlet follows
            _diRunSec    := DL_CTF_ROT_ZERO;           // 时长清零 / Run seconds cleared
            nLeadIdx     := DL_CTF_ONE;                // 主用回默认 / Lead back to default
            _eState      := E_DL_CtfPhase.eIdle;       // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑫：非法枚举兜底（R6） *)
    IF NOT _bFaultLatch THEN
        _eCauseLatch := E_DL_CtfCause.eIllegalState;   // 故障级：非法状态 / Fault: illegal state
        _bFaultLatch := TRUE;                          // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 6：全无反馈持续判与组态闸的锁存（锁存与迁相分离，R21） —— *)
IF tonNoFb.Q AND (NOT _bFaultLatch) THEN
    _eCauseLatch := E_DL_CtfCause.eAllFansNoFeedback;  // 故障级：全无反馈 / Fault: total feedback loss
    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
END_IF
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _eCauseLatch := _eCauseTmp;                        // 锁存首因（组态闸）/ Latch the configuration cause
    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
END_IF

(* —— 段 7：段尾故障迁移闸 + 故障相动作全撤（FB50-1④） —— *)
IF _bFaultLatch AND (_eState <> E_DL_CtfPhase.eFault) THEN
    _eState := E_DL_CtfPhase.eFault;                   // 锁存即迁相 / Latch forces the fault phase
END_IF
IF _eState = E_DL_CtfPhase.eFault THEN
    FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
        _aFanRun[_nIdx] := FALSE;                      // 故障相动作全撤（含同拍迁入）/ All commands withdrawn in fault
    END_FOR
    nActiveCnt := DL_CTF_ZERO;                         // 台数清零 / Active count zeroed
    _nPendFan  := DL_CTF_ZERO;                         // 挂起启动清除 / Pending start cleared
END_IF

(* —— 段 8：统一出口（状态映射 + 数组单点出口 + 锁存回放） —— *)
eState := _eState;                                     // 相位映射 / Phase mapping
FOR _nIdx := 1 TO DL_CTF_FAN_MAX DO
    aFanRun[_nIdx]   := _aFanRun[_nIdx];               // 启动命令映射 / Run command mapping
    aFanFault[_nIdx] := _aFanFault[_nIdx];             // 台级故障映射 / Per-fan fault mapping
END_FOR
tRunAccum := DINT_TO_TIME(_diRunSec);                  // 时长秒 → TIME（显式标准转换）/ Seconds to TIME via the standard converter
bError := _bFaultLatch;                                // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                            // 故障期回放锁存码（FB33-1）/ Replay the latched code
END_IF
bValid := ((_eState = E_DL_CtfPhase.eRunning) OR (_eState = E_DL_CtfPhase.eStartup)
           OR (_eState = E_DL_CtfPhase.eStageUp) OR (_eState = E_DL_CtfPhase.eStageDown)
           OR (_eState = E_DL_CtfPhase.eRotate)) AND (NOT _bFaultLatch);   // 投切/运行相且无锁存时有效
END_FUNCTION_BLOCK
