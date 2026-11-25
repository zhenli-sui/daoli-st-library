(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AerationBlowerCycle
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-24
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / ABS / LIMIT），零厂商私有库
 * 功能描述 (Function)   : 曝气风机间歇循环 + 溶解氧（DO）带控制：DO < fDoLow → eBlowing
 *                         （先开 1 台；若一个 tBlowOn 窗后 DO 仍低于下限则再增开一台，最多
 *                         nBlowerCnt 台）；DO ≥ fDoHigh 且已满足最短曝气 tBlowOn → eResting（全停）；
 *                         eResting 满足最短停曝 tBlowOff 且 DO < fDoLow → 回 eBlowing。
 *                         **迟滞带**：DO ∈ [fDoLow, fDoHigh) 时保持当前相（禁抖，只在两阈值处置位）。
 *                         **仪表失效判据**：DO 采样非有限 → 故障级 eNonFinite；DO 变化量
 *                         |Δ| < 1.0E-6 持续 tDoTimeout（数值完全冻结）→ 故障级 eDoSensorStuck。
 *                         **风机降级**：运行中某台持续无反馈达 3s → 该台置失效标记并停机，
 *                         由台数调节逻辑自动补开备台（信息级 eBlowerSwap，不锁存）；
 *                         无可补备台而需求 > 0 时 → 故障级 eNoBlowerAvail。
 *                         **bStart = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         全部风机停、eIdle（曝气风机不得冻结保持）。
 * 接口     (Interface)  : 输入 bEnable / bStart / bReset（上升沿）/ fDoPv / fDoLow / fDoHigh /
 *                         tBlowOn / tBlowOff / tDoTimeout / nBlowerCnt / aBlowerFb[1..3]；
 *                         输出 aBlowerRun[1..3] / nBlowerUsed / eState（E_DL_AbcPhase）/
 *                         eCause（E_DL_AbcCause）/ bError / bValid / tCycleElapsed。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eBlowing：bEnable 且 bStart 且组态闸通过且 fDoPv < fDoLow 且无锁存；
 *      拍 N 进入 / 本拍行为：清失效标记、需求台数置 1、_diCycleMs 清零 / 拍 N+1 转出至 eBlowing。
 *   ② eBlowing → eResting：fDoPv ≥ fDoHigh 且 _bMinOnDone（最短曝气已满足，迟滞上沿）；
 *      拍 N 进入 / 本拍行为：全部风机停、需求台数置 0、_bMinOffDone 复位、_diCycleMs 清零 /
 *      拍 N+1 转出至 eResting。
 *   ③ eBlowing → eBlowing（增台）：tonBlowOn.Q 且 fDoPv 仍 < fDoLow 且需求 < nBlowerCnt；
 *      拍 N 进入（一个曝气窗结束）/ 本拍行为：需求台数 +1、信息级 eBlowerAdded /
 *      拍 N+1 转出（仍在本相，台数调节逻辑补开一台）。
 *   ④ eResting → eBlowing：_bMinOffDone 且 fDoPv < fDoLow（迟滞下沿）；拍 N 进入 /
 *      本拍行为：需求台数置 1、_bMinOnDone 复位、_diCycleMs 清零 / 拍 N+1 转出至 eBlowing。
 *   ⑤ eBlowing → eFault：无可补备台而需求台数 > 0（eNoBlowerAvail）；DO 冻结超时
 *      （eDoSensorStuck）；DO 非有限（eNonFinite）。锁存后由段尾迁移闸迁相（R21）。
 *   ⑥ eFault → eIdle：bReset 上升沿（R_TRIG 判 .Q）且 bEnable = FALSE（R19 穷举出口）；
 *      拍 N 进入 / 本拍行为：清锁存与成因、全部风机停 / 拍 N+1 转出至 eIdle。
 *   ⑦ ELSE（非法枚举值）→ eFault，成因 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 五个 TON（tonBlowOn / tonBlowOff / tonDoStuck / tonBlowerFb / tonCycle）
 *                            与 R_TRIG 全在 CASE 外无条件调用（R7）；IN 均含 NOT .Q 自复位项（R188）。
 *                         ② 最短曝气 / 最短停曝是**状态量**（_bMinOnDone / _bMinOffDone，由 tonBlowOn /
 *                            tonBlowOff 首个 Q 置位、换相清零），不是单拍标志 —— 避免「Q 早已过去
 *                            而当拍 DO 尚未到上沿」导致最短时间判据被漏掉（禁挂单拍位，R192 类）。
 *                         ③ tonBlowOn.Q 自复位后周期性再触发，故每个 tBlowOn 窗最多增开一台，
 *                            天然的逐级增台节流；增台上限 nBlowerCnt。
 *                         ④ 台数调节：_nRunCnt（实际运行台数）与 _nWant（需求台数）对齐，单拍最多
 *                            补/停一台；补开取最小可用下标，停机取最大下标（后投先停）。
 *                         ⑤ DO 冻结判据的 Δ 用上一拍快照 _fDoPrev（段尾唯一写入），容差 1.0E-6（R4）。
 *                         ⑥ 数组下标安全：_nClamp := LIMIT(1, nBlowerCnt, 3)，全部 FOR 与下标访问
 *                            只用定长 1..3 与 _nClamp（R17 定长数组）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_AbcPhase / E_DL_AbcCause 归属本文件（全库唯一属主，R264）。
 *                         信息级（0..9）永不置 bError；故障级（10 起）赋值处与 _bFaultLatch 三行
 *                         成对（R45），锁存回放至 bReset 沿（FB33-1）。
 * 分工声明 (Scope)      : DO 闭环（鼓风机变频 / 阀门开度 PID）归 FB_DL_DoControlLoop 类件；
 *                         曝气池工艺模型与DO预测归高级算法件；本件只做**间歇曝气时序 + 台数分级 +
 *                         DO 迟滞带**，不做连续闭环，也不做鼓风机电机保护。
 * 归属     (Ownership)  : E_DL_AbcPhase / E_DL_AbcCause 归属本文件（全库唯一定义，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 无除法 + 容差比较 +
 *                         非有限双判 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ 四态 ENUM + CASE + ELSE
 *                         R7 ✓ 全部 TON/R_TRIG 在 CASE 外 ｜ R8/R9 N/A（无 METHOD）｜ R10 ✓ 无构造式
 *                         转换 ｜ R14 ✓ 无 PROPERTY ｜ R15 ✓ 无保留字撞名（aBlowerRun 多字母数组名）
 *                         R17 ✓ 定长 ARRAY[1..3] ｜ R18 ✓ bReset 用 R_TRIG 判 .Q ｜ R19 ✓ eFault
 *                         出口 = bReset 沿 + 撤使能 ｜ R20 ✓ 等待收敛相带超时 ｜ R21 ✓ 锁存与迁相分离。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R79-B 首版
 * 验收向量 (Acceptance) :
 *   V1 fDoLow=2.0、fDoHigh=4.0、tBlowOn=T#30S、tBlowOff=T#60S、nBlowerCnt=2、aBlowerFb 全 TRUE：
 *      fDoPv=1.5 → eBlowing、nBlowerUsed=1、aBlowerRun[1]=TRUE；fDoPv 升至 4.5 且已过 30s →
 *      eResting、nBlowerUsed=0；tBlowOff 到且 fDoPv=1.0 → 回 eBlowing、nBlowerUsed=1。
 *   V2 fDoPv 恒 1.5、nBlowerCnt=3：首个 tBlowOn 窗后 nBlowerUsed=2（eCause=eBlowerAdded），
 *      第二个窗后 nBlowerUsed=3；此后保持 3 台（不再增，信息级 eAllBlowersBusy）。
 *   V3 fDoLow=4.0、fDoHigh=2.0（阈值倒置）→ eState=eFault、eCause=eBadConfig、bError=TRUE、
 *      全部 aBlowerRun=FALSE；bReset 上升沿且 bEnable=FALSE → 回 eIdle、bError=FALSE。
 *   V4 fDoPv 恒为 2.5（|Δ| = 0）持续 tDoTimeout=T#60S → eState=eFault、
 *      eCause=eDoSensorStuck、bError=TRUE。
 *   V5 nBlowerCnt=2、1# 运行中 aBlowerFb[1] 保持 FALSE 超 3s → 1# 停、nBlowerUsed 仍为 1
 *      （2# 补开）、eCause=eBlowerSwap、bError=FALSE（台级降级不锁存）。
 *   V6 nBlowerCnt=1 且该台失效（无备台）→ eState=eFault、eCause=eNoBlowerAvail、bError=TRUE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AbcPhase（曝气间歇循环相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AbcPhase :
(
    eIdle    := 0,    // 空闲：全部风机停，等启动条件 / Idle: all blowers off, waiting for the start condition
    eBlowing := 10,   // 曝气相：按 DO 逐级开风机 / Blowing: stage blowers up according to the DO
    eResting := 20,   // 停曝相：全部风机停，等最短停曝与 DO 回落 / Resting: all off, waiting for min off time and DO drop
    eFault   := 90    // 故障安全相：锁存成因，全部风机停 / Fault safe phase: latched cause, all blowers off
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AbcCause（成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AbcCause :
(
    eNone            := 0,   // 信息级：无事件 / Info: no event
    eBlowingCode     := 1,   // 信息级：曝气中 / Info: blowing in progress
    eRestingCode     := 2,   // 信息级：停曝中 / Info: resting in progress
    eBlowerAdded     := 3,   // 信息级：低氧未改善，增开一台 / Info: DO still low, one more blower added
    eBlowerSwap      := 4,   // 信息级：台级失效，换备台运行 / Info: one blower failed, standby started instead
    eAllBlowersBusy  := 5,   // 信息级：已达最大台数仍低氧，保持并等工艺 / Info: all blowers running, DO still low
    eBadConfig       := 10,  // 故障级：阈值倒置 / 时间参数越域 / 台数越域 / Fault: inverted thresholds, time or count out of domain
    eNonFinite       := 11,  // 故障级：DO 采样非有限 / Fault: non-finite DO sample
    eDoSensorStuck   := 12,  // 故障级：DO 数值冻结超时（仪表失效）/ Fault: DO frozen beyond the timeout
    eNoBlowerAvail   := 13,  // 故障级：无可补备台而需求台数 > 0 / Fault: demand positive but no blower available
    eIllegalState    := 14   // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_AerationBlowerCycle
VAR_INPUT
    bEnable      : BOOL := FALSE;             // 使能：FALSE 全部风机停并回 eIdle / Enable, FALSE stops all blowers and returns to idle
    bStart       : BOOL := FALSE;             // 启动（电平）：FALSE 全部风机停 / Start level, FALSE stops all blowers
    bReset       : BOOL := FALSE;             // 复位（上升沿，需同时 bEnable=FALSE）/ Reset rising edge, requires bEnable FALSE
    fDoPv        : LREAL := 0.0;              // 溶解氧实测值 [mg/L] / Measured dissolved oxygen
    fDoLow       : LREAL := 2.0;              // DO 下限（低于即需曝气），域 < fDoHigh [mg/L] / DO low limit, domain < fDoHigh
    fDoHigh      : LREAL := 4.0;              // DO 上限（达此可停曝），域 > fDoLow [mg/L] / DO high limit, domain > fDoLow
    tBlowOn      : TIME := T#30S;             // 最短曝气时长 / 增台窗，域 ≥ 100ms [s] / Minimum blow time and staging window
    tBlowOff     : TIME := T#60S;             // 最短停曝时长，域 ≥ 100ms [s] / Minimum rest time
    tDoTimeout   : TIME := T#60S;             // DO 冻结判失效超时，域 100ms..1h [s] / DO frozen-to-fail timeout
    nBlowerCnt   : INT := 2;                  // 装机风机台数，有效域 1..3 [台] / Installed blower count, valid domain 1..3
    aBlowerFb    : ARRAY[1..3] OF BOOL;       // 各风机运行反馈（TRUE = 在转）[#] / Per-blower running feedback
END_VAR
VAR_OUTPUT
    aBlowerRun   : ARRAY[1..3] OF BOOL;       // 各风机启动命令（内部状态映射，段 8 单点出口）[#] / Per-blower run command mapped at the tail
    nBlowerUsed  : INT := 0;                  // 当前运行风机台数 [台] / Number of running blowers
    eState       : E_DL_AbcPhase;             // 状态出口（段尾单点映射）[-] / State outlet mapped at the tail
    eCause       : E_DL_AbcCause;             // 成因码出口（故障期锁存回放）[-] / Cause code outlet
    bError       : BOOL;                      // 故障锁存标志 [-] / Fault latch flag
    bValid       : BOOL;                      // 循环有效回执（曝气/停曝相且无锁存）[-] / Cycle validity receipt
    tCycleElapsed : TIME := T#0S;             // 当前相驻留时长 [s] / Dwell time of the current phase
END_VAR
VAR
    _eState       : E_DL_AbcPhase := E_DL_AbcPhase.eIdle;   // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch  : BOOL := FALSE;                          // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch  : E_DL_AbcCause := E_DL_AbcCause.eNone;    // 锁存成因码（FB33-1 锁存回放）[-] / Latched cause code
    _eCauseTmp    : E_DL_AbcCause := E_DL_AbcCause.eNone;    // 本拍首因中间量（段 7 组态闸用）[-] / First cause of this scan
    _bCfgOk       : BOOL := TRUE;                           // 组态与入参闸通过标志 [-] / Configuration gate flag
    _bResetPulse  : BOOL := FALSE;                          // bReset 上升沿快照（R18）[-] / bReset rising-edge snapshot
    _nClamp       : INT := 1;                               // 装机台数钳位值 1..3 [台] / Clamped installed blower count
    _nIdx         : INT := 1;                               // 遍历下标（FOR 专用）[台] / Loop index for FOR statements
    _nPick        : INT := 0;                               // 本拍选中风机下标，0 = 未选中 [台] / Blower index picked in this scan
    _nWant        : INT := 0;                               // 需求运行台数 [台] / Required number of running blowers
    _nRunCnt      : INT := 0;                               // 实际运行台数（含未确认反馈者）[台] / Actual running blower count
    _nFbSuspect   : INT := 0;                               // 无反馈嫌疑风机下标，0 = 无 [台] / Suspect blower index without feedback
    _aBlowerRun   : ARRAY[1..3] OF BOOL;                    // 内部启动命令状态数组 [#] / Internal run-command state array
    _aBlowerBad   : ARRAY[1..3] OF BOOL;                    // 内部台级失效标记（换备台用，eIdle 清除）[#] / Internal per-blower failure flags
    _bMinOnDone   : BOOL := FALSE;                          // 最短曝气已满足（状态量，非单拍位）[-] / Min blow time satisfied, a state not a pulse
    _bMinOffDone  : BOOL := FALSE;                          // 最短停曝已满足（状态量，非单拍位）[-] / Min rest time satisfied, a state not a pulse
    _fDoPrev      : LREAL := 0.0;                           // 上一拍 DO 快照（冻结判据用，段尾唯一写入）[mg/L] / DO snapshot of the last scan
    _bDoMoving    : BOOL := FALSE;                          // DO 本拍有变化标志 [-] / DO changed in this scan
    _diCycleMs    : DINT := 0;                              // 当前相驻留毫秒累加 [ms] / Accumulated dwell milliseconds
    rtReset       : R_TRIG;                                 // bReset 边沿实例（段 4 无条件调用，R18）/ bReset edge instance called unconditionally
    tonBlowOn     : TON;                                    // 最短曝气 / 增台窗定时器（段 4 无条件调用）/ Min blow and staging window timer
    tonBlowOff    : TON;                                    // 最短停曝定时器（段 4 无条件调用）/ Min rest timer called unconditionally
    tonDoStuck    : TON;                                    // DO 冻结持续判（段 4 无条件调用）/ DO frozen persistence timer
    tonBlowerFb   : TON;                                    // 单台无反馈持续判（段 4 无条件调用）/ Per-blower feedback loss timer
    tonCycle      : TON;                                    // 相驻留时长采样节拍（段 4 无条件调用）/ Dwell-time sampling tick
END_VAR
VAR CONSTANT
    DL_ABC_ZERO      : LREAL := 0.0;             // 浮点零基准 [-] / Float zero base
    DL_ABC_EPS       : LREAL := 1.0E-6;          // DO 变化量容差（冻结判据）[mg/L] / DO change tolerance for the freeze check
    DL_ABC_BLOWER_MAX : INT := 3;                // 风机台数上限（数组定长）[台] / Upper bound of blowers, fixed array size
    DL_ABC_ONE       : INT := 1;                 // 台数起始值 [台] / Count start value
    DL_ABC_FB_WIN    : TIME := T#3S;             // 单台无反馈持续窗 [s] / Per-blower feedback loss window
    DL_ABC_T_MIN     : TIME := T#100MS;          // 时间参数下限 [s] / Lower bound of the time parameters
    DL_ABC_T_MAX     : TIME := T#1H;             // 时间参数上限 [s] / Upper bound of the time parameters
    DL_ABC_DT        : TIME := T#100MS;          // 驻留时长采样节拍 [s] / Dwell-time sampling tick
    DL_ABC_DT_MS     : DINT := 100;              // 采样节拍毫秒数 [ms] / Sampling tick in milliseconds
    DL_ABC_MS_ZERO   : DINT := 0;                // 毫秒零基准 [-] / Millisecond zero base
END_VAR

(* —— 段 1：中间量预置（不清锁存 / 数组状态 / 驻留累加，FB32-1） —— *)
_bCfgOk    := TRUE;                                    // 组态闸标志复位 / Configuration flag reset
_eCauseTmp := E_DL_AbcCause.eNone;                      // 当拍首因复位 / Scan cause reset
_nPick     := 0;                                       // 选中下标复位 / Picked index reset
_bDoMoving := FALSE;                                   // DO 变化标志复位 / DO change flag reset

(* —— 段 2：台数钳位与 DO 变化判据（浮点容差比较，R4） —— *)
_nClamp := LIMIT(DL_ABC_ONE, nBlowerCnt, DL_ABC_BLOWER_MAX);            // 台数钳位 1..3 / Clamp the blower count
IF ABS(fDoPv - _fDoPrev) >= DL_ABC_EPS THEN
    _bDoMoving := TRUE;                                                 // Δ 达容差：DO 在变化 / Delta above tolerance: DO is moving
ELSE
    _bDoMoving := FALSE;                                                // Δ 小于容差：本拍视作冻结 / Delta below tolerance: frozen this scan
END_IF

(* —— 段 3：组态与入参域闸（阈值倒置 / 时间越域 / 台数越域 / 非有限） —— *)
IF (fDoPv <> fDoPv) OR ((fDoPv - fDoPv) <> DL_ABC_ZERO)
    OR (fDoLow <> fDoLow) OR ((fDoLow - fDoLow) <> DL_ABC_ZERO)
    OR (fDoHigh <> fDoHigh) OR ((fDoHigh - fDoHigh) <> DL_ABC_ZERO) THEN
    _bCfgOk    := FALSE;                               // 入参非有限 / Non-finite input
    _eCauseTmp := E_DL_AbcCause.eNonFinite;            // 故障级：非有限入参 / Fault: non-finite input
END_IF
IF _bCfgOk THEN
    IF fDoLow >= fDoHigh THEN
        _bCfgOk    := FALSE;                           // 阈值倒置（或无迟滞带）/ Inverted thresholds, no hysteresis band
        _eCauseTmp := E_DL_AbcCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF (nBlowerCnt < DL_ABC_ONE) OR (nBlowerCnt > DL_ABC_BLOWER_MAX) THEN
        _bCfgOk    := FALSE;                           // 装机台数越域 / Blower count out of domain
        _eCauseTmp := E_DL_AbcCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF (tBlowOn < DL_ABC_T_MIN) OR (tBlowOn > DL_ABC_T_MAX) THEN
        _bCfgOk    := FALSE;                           // 最短曝气越域 / Min blow time out of domain
        _eCauseTmp := E_DL_AbcCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF (tBlowOff < DL_ABC_T_MIN) OR (tBlowOff > DL_ABC_T_MAX) THEN
        _bCfgOk    := FALSE;                           // 最短停曝越域 / Min rest time out of domain
        _eCauseTmp := E_DL_AbcCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    ELSIF (tDoTimeout < DL_ABC_T_MIN) OR (tDoTimeout > DL_ABC_T_MAX) THEN
        _bCfgOk    := FALSE;                           // DO 冻结超时越域 / DO freeze timeout out of domain
        _eCauseTmp := E_DL_AbcCause.eBadConfig;        // 故障级：组态非法 / Fault: bad configuration
    END_IF
END_IF

(* —— 段 4：边沿与定时器（CASE 外无条件调用，R7；IN 均含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                                // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
_bResetPulse := rtReset.Q;                             // 边沿快照 / Edge snapshot
tonBlowOn(IN := (_eState = E_DL_AbcPhase.eBlowing) AND (NOT tonBlowOn.Q) AND (NOT _bFaultLatch),
          PT := tBlowOn);                              // 最短曝气 / 增台窗（自复位后周期性再触发）/ Min blow and staging window
tonBlowOff(IN := (_eState = E_DL_AbcPhase.eResting) AND (NOT tonBlowOff.Q) AND (NOT _bFaultLatch),
           PT := tBlowOff);                            // 最短停曝（自复位后周期性再触发）/ Min rest window
tonCycle(IN := ((_eState = E_DL_AbcPhase.eBlowing) OR (_eState = E_DL_AbcPhase.eResting))
              AND (NOT tonCycle.Q) AND (NOT _bFaultLatch),
         PT := DL_ABC_DT);                             // 相驻留时长采样节拍 / Dwell-time sampling tick
IF tonCycle.Q THEN
    _diCycleMs := _diCycleMs + DL_ABC_DT_MS;           // 驻留毫秒累加 / Accumulate dwell milliseconds
END_IF
(* 无反馈嫌疑台：取最小下标的「已命令但无反馈」风机（用上一拍状态，一拍延迟） *)
_nFbSuspect := 0;                                      // 嫌疑下标复位 / Suspect index reset
FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
    IF (_nFbSuspect = 0) AND _aBlowerRun[_nIdx] AND (NOT aBlowerFb[_nIdx]) THEN
        _nFbSuspect := _nIdx;                          // 记录首个无反馈风机 / Record the first blower without feedback
    END_IF
END_FOR
tonBlowerFb(IN := (_nFbSuspect > 0) AND (NOT tonBlowerFb.Q) AND (NOT _bFaultLatch),
            PT := DL_ABC_FB_WIN);                      // 单台无反馈持续判 / Per-blower feedback loss persistence
tonDoStuck(IN := bEnable AND bStart AND (NOT _bDoMoving)
                AND (NOT tonDoStuck.Q) AND (NOT _bFaultLatch),
           PT := tDoTimeout);                          // DO 冻结持续判（仪表失效）/ DO frozen persistence check

(* —— 段 5：状态机主体（唯一相位写入点；故障只置锁存，迁相由段 7 统一执行） —— *)
CASE _eState OF
    E_DL_AbcPhase.eIdle :
        FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
            _aBlowerRun[_nIdx] := FALSE;               // 空闲：命令全撤 / Idle: commands withdrawn
            _aBlowerBad[_nIdx] := FALSE;               // 空闲：台级失效标记清除 / Idle: failure flags cleared
        END_FOR
        _nWant      := 0;                              // 空闲：需求台数 0 / Idle: demand zero
        _nRunCnt    := 0;                              // 空闲：运行台数 0 / Idle: run count zero
        _bMinOnDone := FALSE;                          // 空闲：最短曝气状态复位 / Idle: min-blow state cleared
        _bMinOffDone := FALSE;                         // 空闲：最短停曝状态复位 / Idle: min-rest state cleared
        _diCycleMs  := DL_ABC_MS_ZERO;                 // 空闲：驻留累计清零 / Idle: dwell accumulator cleared
        IF bEnable AND bStart AND _bCfgOk AND (fDoPv < fDoLow) AND (NOT _bFaultLatch) THEN
            _nWant      := DL_ABC_ONE;                 // 迁移①：先开 1 台 / Start with one blower
            _bMinOnDone := FALSE;                      // 最短曝气状态复位 / Min-blow state cleared
            _bMinOffDone := FALSE;                     // 最短停曝状态复位 / Min-rest state cleared
            _diCycleMs  := DL_ABC_MS_ZERO;             // 驻留累计清零 / Dwell accumulator cleared
            eCause      := E_DL_AbcCause.eBlowingCode; // 信息级：开始曝气 / Info: blowing started
            _eState     := E_DL_AbcPhase.eBlowing;     // 进入曝气相 / Move to blowing
        END_IF

    E_DL_AbcPhase.eBlowing :
        IF (NOT bEnable) OR (NOT bStart) THEN
            FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
                _aBlowerRun[_nIdx] := FALSE;           // 失能：命令全撤 / Disabled: all commands withdrawn
            END_FOR
            _nWant      := 0;                          // 需求台数 0 / Demand zero
            _nRunCnt    := 0;                          // 运行台数 0 / Run count zero
            _diCycleMs  := DL_ABC_MS_ZERO;             // 驻留累计清零 / Dwell accumulator cleared
            eCause      := E_DL_AbcCause.eNone;        // 信息级：无事件 / Info: no event
            _eState     := E_DL_AbcPhase.eIdle;        // 回空闲相 / Back to idle
        ELSE
            (* 最长曝气窗到：置最短曝气满足状态量（非单拍位）/ 低氧未改善则逐级增台 *)
            IF tonBlowOn.Q THEN
                _bMinOnDone := TRUE;                   // 最短曝气已满足（状态量）/ Min blow satisfied as a state
                IF fDoPv < fDoLow THEN
                    IF _nWant < _nClamp THEN
                        _nWant := _nWant + DL_ABC_ONE; // 迁移③：低氧未改善，需求 +1 / DO still low: demand plus one
                        eCause := E_DL_AbcCause.eBlowerAdded;   // 信息级：增开一台 / Info: one blower added
                    ELSE
                        eCause := E_DL_AbcCause.eAllBlowersBusy; // 信息级：已达最大台数 / Info: all blowers already running
                    END_IF
                END_IF
            END_IF
            (* 台级反馈丢失降级：嫌疑台置失效、停机，随后由台数调节补开备台 *)
            IF tonBlowerFb.Q AND (_nFbSuspect > 0) THEN
                IF (_nFbSuspect >= DL_ABC_ONE) AND (_nFbSuspect <= DL_ABC_BLOWER_MAX) THEN
                    _aBlowerBad[_nFbSuspect] := TRUE;  // 该台置失效标记 / Mark this blower as failed
                    IF _aBlowerRun[_nFbSuspect] THEN
                        _aBlowerRun[_nFbSuspect] := FALSE;   // 撤该台命令 / Withdraw this command
                        IF _nRunCnt > 0 THEN
                            _nRunCnt := _nRunCnt - DL_ABC_ONE; // 运行台数回退 / Roll the run count back
                        END_IF
                    END_IF
                    eCause := E_DL_AbcCause.eBlowerSwap;     // 信息级：台级失效换备台 / Info: failed blower swapped out
                END_IF
            END_IF
            (* 台数调节：需求与实际对齐，单拍最多补/停一台 *)
            IF _nRunCnt < _nWant THEN
                _nPick := 0;                           // 补开候选复位 / Candidate reset
                FOR _nIdx := 1 TO _nClamp DO
                    IF (_nPick = 0) AND (NOT _aBlowerRun[_nIdx]) AND (NOT _aBlowerBad[_nIdx]) THEN
                        _nPick := _nIdx;               // 取最小可用下标（未运行且未失效）/ Lowest available blower
                    END_IF
                END_FOR
                IF _nPick > 0 THEN
                    _aBlowerRun[_nPick] := TRUE;       // 补开一台 / Start one blower
                    _nRunCnt := _nRunCnt + DL_ABC_ONE; // 运行台数 +1 / Increment the run count
                ELSE
                    IF NOT _bFaultLatch THEN
                        _eCauseLatch := E_DL_AbcCause.eNoBlowerAvail;   // 故障级：无可补备台 / Fault: no blower available
                        _bFaultLatch := TRUE;                           // 置故障锁存（迁相由段 7，R21）/ Latch the fault
                    END_IF
                END_IF
            ELSIF _nRunCnt > _nWant THEN
                _nPick := 0;                           // 停机候选复位 / Stop candidate reset
                FOR _nIdx := 1 TO _nClamp DO
                    IF _aBlowerRun[_nIdx] THEN
                        _nPick := _nIdx;               // 取最大下标（后投先停）/ Highest index, last started first stopped
                    END_IF
                END_FOR
                IF _nPick > 0 THEN
                    _aBlowerRun[_nPick] := FALSE;      // 停一台 / Stop one blower
                    _nRunCnt := _nRunCnt - DL_ABC_ONE; // 运行台数 -1 / Decrement the run count
                END_IF
            END_IF
            (* 停曝判据：DO 达上沿且最短曝气已满足（迟滞上沿，R4 大小判据） *)
            IF (fDoPv >= fDoHigh) AND _bMinOnDone THEN
                FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
                    _aBlowerRun[_nIdx] := FALSE;       // 迁移②：全部风机停 / All blowers stopped
                END_FOR
                _nWant      := 0;                      // 需求台数 0 / Demand zero
                _nRunCnt    := 0;                      // 运行台数 0 / Run count zero
                _bMinOffDone := FALSE;                 // 最短停曝状态复位 / Min-rest state cleared
                _diCycleMs  := DL_ABC_MS_ZERO;         // 驻留累计清零 / Dwell accumulator cleared
                eCause      := E_DL_AbcCause.eRestingCode;   // 信息级：进入停曝 / Info: resting started
                _eState     := E_DL_AbcPhase.eResting; // 进入停曝相 / Move to resting
            ELSE
                IF eCause = E_DL_AbcCause.eNone THEN
                    eCause := E_DL_AbcCause.eBlowingCode;    // 信息级：曝气中 / Info: blowing in progress
                END_IF
            END_IF
        END_IF

    E_DL_AbcPhase.eResting :
        FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
            _aBlowerRun[_nIdx] := FALSE;               // 停曝相：命令全撤 / Resting: all commands withdrawn
        END_FOR
        _nWant   := 0;                                 // 需求台数 0 / Demand zero
        _nRunCnt := 0;                                 // 运行台数 0 / Run count zero
        IF (NOT bEnable) OR (NOT bStart) THEN
            _diCycleMs := DL_ABC_MS_ZERO;              // 驻留累计清零 / Dwell accumulator cleared
            eCause     := E_DL_AbcCause.eNone;         // 信息级：无事件 / Info: no event
            _eState    := E_DL_AbcPhase.eIdle;         // 回空闲相 / Back to idle
        ELSE
            IF tonBlowOff.Q THEN
                _bMinOffDone := TRUE;                  // 最短停曝已满足（状态量）/ Min rest satisfied as a state
            END_IF
            IF _bMinOffDone AND (fDoPv < fDoLow) THEN
                _nWant      := DL_ABC_ONE;             // 迁移④：下限已触发，先开 1 台 / Low limit reached: start with one
                _bMinOnDone := FALSE;                  // 最短曝气状态复位 / Min-blow state cleared
                _diCycleMs  := DL_ABC_MS_ZERO;         // 驻留累计清零 / Dwell accumulator cleared
                eCause      := E_DL_AbcCause.eBlowingCode;   // 信息级：恢复曝气 / Info: blowing resumed
                _eState     := E_DL_AbcPhase.eBlowing; // 进入曝气相 / Move to blowing
            ELSE
                eCause := E_DL_AbcCause.eRestingCode;  // 信息级：停曝中（迟滞带内保持）/ Info: resting in progress
            END_IF
        END_IF

    E_DL_AbcPhase.eFault :
        FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
            _aBlowerRun[_nIdx] := FALSE;               // 故障相：命令全撤（安全侧）/ Fault phase: all commands withdrawn
        END_FOR
        _nWant     := 0;                               // 需求台数 0 / Demand zero
        _nRunCnt   := 0;                               // 运行台数 0 / Run count zero
        _diCycleMs := DL_ABC_MS_ZERO;                  // 驻留累计清零 / Dwell accumulator cleared
        IF _bResetPulse AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                     // 迁移⑥：清故障锁存 / Clear the fault latch
            _eCauseLatch := E_DL_AbcCause.eNone;       // 清锁存成因 / Clear the latched cause
            eCause       := E_DL_AbcCause.eNone;       // 出口同步归零 / Outlet follows
            _bMinOnDone  := FALSE;                     // 最短曝气状态复位 / Min-blow state cleared
            _bMinOffDone := FALSE;                     // 最短停曝状态复位 / Min-rest state cleared
            _eState      := E_DL_AbcPhase.eIdle;       // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑦：非法枚举兜底（R6） *)
    IF NOT _bFaultLatch THEN
        _eCauseLatch := E_DL_AbcCause.eIllegalState;   // 故障级：非法状态 / Fault: illegal state
        _bFaultLatch := TRUE;                          // 置故障锁存 / Latch the fault
    END_IF
END_CASE

(* —— 段 6：DO 冻结超时（仪表失效）的锁存（锁存与迁相分离，R21） —— *)
IF tonDoStuck.Q AND (NOT _bFaultLatch) THEN
    _eCauseLatch := E_DL_AbcCause.eDoSensorStuck;      // 故障级：DO 数值冻结 / Fault: DO value frozen
    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
END_IF

(* —— 段 7：组态闸失败处理 + 段尾故障迁移闸 + 故障相动作全撤（FB50-1④） —— *)
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _eCauseLatch := _eCauseTmp;                        // 锁存首因（组态闸）/ Latch the configuration cause
    _bFaultLatch := TRUE;                              // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_AbcPhase.eFault) THEN
    _eState := E_DL_AbcPhase.eFault;                   // 锁存即迁相 / Latch forces the fault phase
END_IF
IF _eState = E_DL_AbcPhase.eFault THEN
    FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
        _aBlowerRun[_nIdx] := FALSE;                   // 故障相命令全撤（含同拍迁入）/ All commands withdrawn in fault
    END_FOR
    _nWant   := 0;                                     // 需求台数 0 / Demand zero
    _nRunCnt := 0;                                     // 运行台数 0 / Run count zero
END_IF

(* —— 段 8：统一出口（状态映射 + 台数映射 + 驻留换算 + 锁存回放） —— *)
eState := _eState;                                     // 相位映射 / Phase mapping
FOR _nIdx := 1 TO DL_ABC_BLOWER_MAX DO
    aBlowerRun[_nIdx] := _aBlowerRun[_nIdx];           // 启动命令映射 / Run command mapping
END_FOR
nBlowerUsed   := _nRunCnt;                             // 运行台数出口 / Running count outlet
tCycleElapsed := DINT_TO_TIME(_diCycleMs);             // 驻留毫秒 → TIME（标准转换，R10）/ Dwell milliseconds to TIME
bError := _bFaultLatch;                                // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                            // 故障期回放锁存码（FB33-1）/ Replay the latched code
END_IF
bValid := ((_eState = E_DL_AbcPhase.eBlowing) OR (_eState = E_DL_AbcPhase.eResting))
          AND (NOT _bFaultLatch);                      // 曝气/停曝相且无锁存时有效 / Valid while blowing or resting without a latch
_fDoPrev := fDoPv;                                     // DO 快照更新（唯一写入点，冻结判据用）/ DO snapshot, single write point
END_FUNCTION_BLOCK
