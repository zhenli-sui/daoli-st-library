(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AsrsSlotAllocSeq
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.1 ｜ 2026-11-24
 * 码位     (Code Segment): 16#0005_2140（DL_Process 段内 21xx 子带，继 2100 顺排）
 * 复杂度   (Complexity) : C4
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG），零厂商私有库
 * 开源溯源 (Provenance) : menes97/ayran-mini-fabrika / FB_Asrs / MIT /
 *                         借鉴点：货位分配「请求—应答」的 ack_seq / res_seq 序号同步与冲突回退语义
 *                         （未复制任何实现行，按 IEC 61131-3 重写为六相状态机 + 序号单点写入）
 * 功能描述 (Function)   : 立库货位分配与取放握手。上位下发分配请求（iReqSlot + diReqSeq），本件先做
 *                         合法性校验（入库目标必须空闲、且不能被其他任务锁闭），再进入握手相把请求
 *                         序号下发为 diOutSeq，等待对端 diAckSeq 回齐同一序号；回齐即放行（bGrant
 *                         单拍）并锁存实际分配货位。冲突（货位非空 / 应答超时）走 eRetry 净额回退，
 *                         最多 3 轮，耗尽转故障级 34。
 *                         **序号三律**：① 下发序号 _diOutSeq 全件唯一写入点（eValidate 通过相、
 *                         eRetry 回退清零点、复位点），禁止两处同拍写；② 序号超前（diAckSeq >
 *                         diOutSeq）判故障级 35——对端序号快于本端只能是对端残留或双主机，
 *                         任何「等待其自愈」的写法都是把错配隐藏成超时；③ 序号比较一律直比
 *                         `>` / `=`，不做减法防溢出假设（DINT 全值域可比，减法反而引入回绕）。
 *                         **bAllocReq 取上升沿**：电平保持不重复触发（R79 教训），重复分配必须
 *                         由上位撤请求再起，避免同一请求被连发当成多次分配。
 *                         **bEnable = FALSE 语义（R191 二选一，本件选「降级为安全值 + 置标志」）**：
 *                         放行撤销、下发序号清零、相位回 eIdle；已完成的 iAllocSlot 保留（事实不撤回）。
 * 接口     (Interface)  : 输入 bEnable / bReset（上升沿）/ bAllocReq（上升沿有效）/ iReqSlot /
 *                         diReqSeq / diAckSeq / bStoreMode / bSlotFree / bSlotLocked / tAckTimeout；
 *                         输出 eState（E_DL_AsrsSlotAllocSeq_State）/ bBusy / bDone（放行同拍单拍）/
 *                         bError / iErrCode / diOutSeq / bGrant（单拍）/ iAllocSlot / iConflictCnt。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eValidate：bEnable 且 rtAlloc.Q（请求上升沿）；拍 N 进入 / 本拍行为：冲突计数与
 *      信息码归零，拒绝一切放行 / 拍 N+1 转出至 eValidate。
 *   ② eValidate → eHandshake：目标货位合法（出库，或入库且空闲），且未被锁闭；拍 N 进入 /
 *      本拍行为：下发序号 _diOutSeq := diReqSeq（全件唯一写入点之一）/ 拍 N+1 转出至 eHandshake。
 *   ③ eValidate → eRetry：入库且目标货位非空；拍 N 进入 / 本拍行为：冲突计数 +1、信息级 31 /
 *      拍 N+1 转出至 eRetry。
 *   ④ eValidate → eFault：目标货位被锁闭（故障级 32）。段 7 段尾迁移闸统一迁相。
 *   ⑤ eHandshake → eCommit：diAckSeq = diOutSeq 且无锁存（本拍合法事件优先，R275）；拍 N 进入 /
 *      本拍行为：拒绝超时判定（事件已消化）/ 拍 N+1 转出至 eCommit。
 *   ⑥ eHandshake → eRetry：tonAck.Q（应答超时）；拍 N 进入 / 本拍行为：冲突计数 +1、信息级 33 /
 *      拍 N+1 转出至 eRetry。
 *   ⑦ eHandshake → eFault：diAckSeq > diOutSeq（序号超前，故障级 35）。
 *   ⑧ eRetry → eValidate：冲突计数 < 3；拍 N 进入 / 本拍行为：下发序号清零、拒绝放行 /
 *      拍 N+1 转出至 eValidate。
 *   ⑨ eRetry → eFault：冲突计数 ≥ 3（重试耗尽，故障级 34）。
 *   ⑩ eCommit → eIdle：单拍放行；拍 N 进入 / 本拍行为：bGrant 与 bDone 置单拍、iAllocSlot 锁存
 *      请求货位、拒绝重复放行 / 拍 N+1 转出至 eIdle。
 *   ⑪ eFault → eIdle：bReset 上升沿；拍 N 进入 / 本拍行为：清锁存、错误码、下发序号、冲突计数 /
 *      拍 N+1 转出至 eIdle。出口穷举、不滞留故障态。
 *   ⑫ ELSE（非法枚举值）→ eFault，码 99（R6 兜底）。
 * 边界     (Boundary)   : ① 一个 TON 与两个 R_TRIG 全部在 CASE 外无条件调用（R7）；tonAck 的 IN 含
 *                            NOT .Q 自复位项（R188），禁靠外部沿清零。
 *                         ② 序号超前判据只在 eHandshake 相内生效：eIdle 相 _diOutSeq 为 0 而
 *                            diAckSeq 可能仍为上一轮的非零值，若在空闲相判超前会误报（域证明）。
 *                         ③ eValidate 为零驻留判定相：每个分支都在本拍定相（放行 / 回退 / 故障），
 *                            不存在等待，故无需超时兜底；eCommit 为单拍放行相，同样零驻留。
 *                            eHandshake 是唯一的等待收敛相，由 tonAck（PT := _tAck）兜底（R448）。
 *                         ④ 时间参数两级回退（FB32-3）：tAckTimeout 越域（< 50ms 或 > 1h）回默认常量
 *                            T#5S，默认常量本身在有效域内，故无需二级钳定；回退不置故障（不新增码位）。
 *                         ⑤ DINT 序号比较全用 `>` / `=` 直比，不做加法/减法（无溢出路径，R4 无除法）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件按派单指定使用小整数码。信息级（永不置 bError，随新请求起点重算）：
 *                         31 = 货位非空（入库目标已被占用，转回退）；反证：该场景无任何输出位变化
 *                              （bGrant 仍假、iAllocSlot 不变），仅凭输出组合不可能观测到进过 eValidate。
 *                         33 = 应答超时（对端未回齐序号，转回退）；反证：与 31 的输出组合完全同形，
 *                              两者唯一差别是成因，必须独立成码。
 *                         故障级（置 bError，锁存至 bReset 沿）：
 *                         32 = 目标货位被锁闭；反证：被锁闭时 bSlotFree 可能仍为真，与「正常放行前
 *                              拍」输出同形，只能靠码区分。
 *                         34 = 重试耗尽（冲突计数达 3）；反证：耗尽拍与普通回退拍输出全同
 *                              （iConflictCnt 已为 3 是唯一差别），且必须能被 bError 过滤上送。
 *                         35 = 序号超前（diAckSeq > diOutSeq）；反证：该场景本拍无超时、无冲突计数
 *                              变化，与「静默等待」完全同形，不报码即永久沉默。
 *                         36 = 请求序号非法（diReqSeq <= 0，未初始化禁参与握手，v1.0.1 新增）；
 *                              反证：diReqSeq=0 时 diAckSeq 初值同为 0，握手判据 (diAckSeq=_diOutSeq)
 *                              立即成立 → 零握手直接放行，输出与「正常放行拍」完全同形，只能靠码区分。
 *                              契约：diAckSeq 必须为发布后新值；提前应答或复用序号将走 33→34 耗尽（fail-closed）。
 *                         99 = 非法状态枚举值（ELSE 兜底）。
 * 分工声明 (Scope)      : 货位号有效性（1..库位总数）与货位台账维护归上游货位管理器；堆垛机行走
 *                         与取放机构归 DL_Motion 轴类件；出库货位选择策略（先进先出 / 就近）归
 *                         上层调度算法件。本件只做**一次分配事务的校验—握手—放行**时序。
 * 归属     (Ownership)  : E_DL_AsrsSlotAllocSeq_State 归属本文件（全库唯一定义，R264）。
 * 命名偏离 (Naming Ex.) : 本件按派单原文保留 i 前缀表示 INT（iReqSlot / iErrCode / iAllocSlot /
 *                         iConflictCnt），di 前缀表示 DINT（diReqSeq / diAckSeq / diOutSeq）；
 *                         与规范 1.2 节 n 前缀存在登记偏离，接口契约优先不改名。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         （TON / R_TRIG）｜ R4 ✓ 无除法、无浮点、无 ABS(x-x) 判据（本件无浮点入参）
 *                         R5 ✓ 逐行同行中英双语注释 ｜ R6 ✓ 六态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ TON / R_TRIG 全在 CASE 外无条件调用 ｜ R8 ✓ 无 METHOD（全内联）
 *                         R10 ✓ 无构造式转换 ｜ R11 ✓ 声明全分号结尾 ｜ R12 ✓ ENUM 成员用 :=
 *                         R14 ✓ 无 PROPERTY ｜ R16 ✓ 不引用任何外部 FB/FC。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R81-B 首版
 *                          2026-11-24  v1.0.1  R81-C 补 diReqSeq<=0 闸(码36)+发布时 ack 快照，消零握手假放行（闸席 FAIL(LOGIC) 修法）
 * 验收向量 (Acceptance) :
 *   V1 入库正常：bStoreMode=TRUE、bSlotFree=TRUE、bSlotLocked=FALSE、iReqSlot=42、diReqSeq=7、
 *      diAckSeq 由 0 变 7 → eState 走 eIdle→eValidate→eHandshake→eCommit→eIdle；diOutSeq=7、
 *      bGrant 单拍为 TRUE、iAllocSlot=42、bDone 单拍为 TRUE、iErrCode=0、bError=FALSE。
 *   V2 货位非空：bStoreMode=TRUE、bSlotFree=FALSE 恒真 → 每轮 iConflictCnt+1、iErrCode=31；
 *      第 3 轮后 eState=eFault、iErrCode=34、bError=TRUE、bGrant=FALSE。
 *   V3 应答超时：diAckSeq 恒 0、tAckTimeout=T#1S → 每轮 tonAck 超时 iConflictCnt+1、iErrCode=33；
 *      第 3 轮后 eState=eFault、iErrCode=34、bError=TRUE。
 *   V4 序号超前：diReqSeq=5、diAckSeq=9 → eState=eHandshake 首拍即 eState=eFault、iErrCode=35、
 *      bError=TRUE；bReset 上升沿 → eState=eIdle、bError=FALSE、iErrCode=0、diOutSeq=0。
 *   V5 货位锁闭：bSlotLocked=TRUE → eState=eFault、iErrCode=32、bError=TRUE；bReset 上升沿可退出。
 *   V6 撤使能：eHandshake 中 bEnable=FALSE → eState=eIdle、diOutSeq=0、bGrant=FALSE、bError=FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AsrsSlotAllocSeq_State（货位分配事务相位；eFault 为安全相）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AsrsSlotAllocSeq_State :
(
    eIdle      := 0,    // 空闲：等分配请求上升沿 / Idle: waiting for the allocation request rising edge
    eValidate  := 10,   // 校验相：货位空闲与锁闭判定，零驻留 / Validate: slot-free and lock checks, no dwell
    eHandshake := 20,   // 握手相：下发序号并等对端回齐 / Handshake: publish the sequence and wait for the acknowledgement
    eCommit    := 30,   // 放行相：单拍输出 bGrant 并锁存货位 / Commit: one-scan grant and slot latching
    eRetry     := 40,   // 回退相：净额回退或耗尽转故障，零驻留 / Retry: net rollback or exhaustion to fault, no dwell
    eFault     := 90    // 故障安全相：锁存成因，放行撤销 / Fault safe phase: latched cause, grant withdrawn
);
END_TYPE

FUNCTION_BLOCK FB_DL_AsrsSlotAllocSeq
VAR_INPUT
    bEnable      : BOOL := FALSE;       // 使能：FALSE 撤销放行并回空闲 / Enable, FALSE withdraws the grant and returns to idle
    bReset       : BOOL := FALSE;       // 复位（上升沿，清锁存/下发序号/冲突计数）/ Reset rising edge clearing latch, output sequence and conflict count
    bAllocReq    : BOOL := FALSE;       // 分配请求（上升沿有效，电平保持不重复触发）/ Allocation request, rising edge only
    iReqSlot     : INT := 0;            // 请求货位号，有效性由上游货位管理器保证 [货位] / Requested slot number, validity guaranteed upstream
    diReqSeq     : DINT := 0;           // 请求序号（本端事务号）[序号] / Request sequence number of this transaction
    diAckSeq     : DINT := 0;           // 对端已确认序号（回齐即握手成功）[序号] / Acknowledged sequence number from the counterpart
    bStoreMode   : BOOL := TRUE;        // 作业模式：TRUE = 入库，FALSE = 出库 / Mode, TRUE for storing, FALSE for retrieving
    bSlotFree    : BOOL := FALSE;       // 目标货位空闲（入库判据）/ Target slot is free, used in store mode
    bSlotLocked  : BOOL := FALSE;       // 目标货位被其他任务锁闭（任何模式均致命）/ Target slot locked by another task, fatal in both modes
    tAckTimeout  : TIME := T#5S;        // 应答超时，有效域 50ms..1h，越域回默认 [s] / Acknowledgement timeout, out of domain falls back to the default
END_VAR
VAR_OUTPUT
    eState       : E_DL_AsrsSlotAllocSeq_State;   // 当前相位出口（段 8 单点映射）/ Current phase outlet mapped once at segment 8
    bBusy        : BOOL;                // 事务进行中（校验/握手/回退/放行）/ Transaction in progress
    bDone        : BOOL;                // 放行完成单拍脉冲 / One-scan completion pulse
    bError       : BOOL;                // 故障锁存标志 / Fault latch flag
    iErrCode     : INT := 0;            // 错误码（故障期锁存回放，非故障期为当前信息码）/ Error code, latched code in fault and the info code otherwise
    diOutSeq     : DINT := 0;           // 下发序号（对端应回齐此值）/ Published sequence number the counterpart must acknowledge
    bGrant       : BOOL;                // 放行单拍脉冲（仅 eCommit 一拍）/ One-scan grant pulse emitted only in eCommit
    iAllocSlot   : INT := 0;            // 实际分配货位（放行拍锁存，撤使能不清）/ Actually allocated slot, latched on grant and kept on disable
    iConflictCnt : INT := 0;            // 冲突累计次数，达 3 判耗尽 [次] / Conflict counter, exhaustion at three
END_VAR
VAR
    _eState      : E_DL_AsrsSlotAllocSeq_State := E_DL_AsrsSlotAllocSeq_State.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch : BOOL := FALSE;       // 故障锁存位（仅 bReset 上升沿清除）/ Fault latch bit, cleared only by the bReset rising edge
    _iErrLatch   : INT := 0;            // 锁存故障码（故障期唯一回放源，FB33-1）/ Latched fault code, the only replay source during fault
    _iInfoCode   : INT := 0;            // 信息级码（31/33，永不置 bError，新请求起点重算）/ Info-level code, never raises bError, recomputed at each new request
    _iErrTmp     : INT := 0;            // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq   : BOOL := FALSE;       // 当拍故障请求标志（段 7 统一锁存）/ Fault request of this scan latched at segment 7
    _diOutSeq    : DINT := 0;           // 下发序号内部量（全件唯一写入点集合）/ Internal published sequence with its single-write point set
    _diAckPublish : DINT := 0;         // 下发时刻的 ack 快照，用于拦截陈旧 ack 二次放行（v1.0.1）/ Ack snapshot at publish time, blocks stale-ack re-grant
    _bGrantPulse : BOOL := FALSE;       // 放行内部单拍位（段 1 预置，段 8 映射）/ Internal one-scan grant bit preset at segment 1
    _bDonePulse  : BOOL := FALSE;       // 完成内部单拍位（段 1 预置，段 8 映射）/ Internal one-scan done bit preset at segment 1
    _iAllocSlot  : INT := 0;            // 内部实际货位（放行拍锁存）/ Internal allocated slot latched on the grant scan
    _iConflictCnt : INT := 0;           // 内部冲突计数 [次] / Internal conflict counter
    _tAck        : TIME := T#5S;        // 应答超时钳定值（两级回退结果）[s] / Clamped acknowledgement timeout after the two-level fallback
    rtReset      : R_TRIG;              // bReset 边沿实例（段 3 无条件调用，R18）/ bReset edge instance called unconditionally
    rtAlloc      : R_TRIG;              // bAllocReq 边沿实例（段 3 无条件调用，防电平重复触发）/ bAllocReq edge instance preventing level retriggering
    tonAck       : TON;                 // 应答超时计时器（段 3 无条件调用）/ Acknowledgement timeout timer called unconditionally
END_VAR
VAR CONSTANT
    DL_ASA_RETRY_MAX : INT := 3;                 // 冲突回退上限，达此判耗尽 [次] / Conflict retry limit, exhaustion at this count
    DL_ASA_CNT_ZERO  : INT := 0;                 // 计数零基准 [-] / Zero base for counters
    DL_ASA_ONE       : INT := 1;                 // 整数一（计数步进）[1] / Integer one used for stepping
    DL_ASA_T_MIN     : TIME := T#50MS;           // 应答超时下限 [s] / Acknowledgement timeout lower bound
    DL_ASA_T_MAX     : TIME := T#1H;             // 应答超时上限 [s] / Acknowledgement timeout upper bound
    DL_ASA_ACK_DEF   : TIME := T#5S;             // 应答超时默认回退值（本身在有效域内）[s] / Default fallback timeout, already inside the valid domain
END_VAR

(* —— 段 1：中间量预置（只清单拍标志与扫描量，不清序号 / 冲突计数 / 锁存，FB32-1） —— *)
_iErrTmp     := 0;                        // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq   := FALSE;                    // 当拍故障请求复位 / Scan fault request reset
_bGrantPulse := FALSE;                    // 放行单拍位预置（单拍路径唯一预置点，FB51-8）/ Grant pulse preset, the single preset point
_bDonePulse  := FALSE;                    // 完成单拍位预置（单拍路径唯一预置点，FB51-8）/ Done pulse preset, the single preset point

(* —— 段 2：时间参数两级回退（越域回默认常量，默认常量在域内故无需二级钳定，FB32-3） —— *)
IF (tAckTimeout < DL_ASA_T_MIN) OR (tAckTimeout > DL_ASA_T_MAX) THEN
    _tAck := DL_ASA_ACK_DEF;              // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tAck := tAckTimeout;                 // 域内：原值采用 / Inside the domain: take the value as given
END_IF

(* —— 段 3：边沿与定时器（CASE 外无条件调用，R7；IN 含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                   // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
rtAlloc(CLK := bAllocReq);                // 分配请求边沿无条件刷新（防电平重复触发，R79）/ Allocation request edge refreshed unconditionally
tonAck(IN := (_eState = E_DL_AsrsSlotAllocSeq_State.eHandshake) AND (NOT tonAck.Q) AND (NOT _bFaultLatch),
       PT := _tAck);                      // 应答超时计时（仅握手相，自复位后逐轮回退再起）/ Acknowledgement timeout running only in the handshake phase

(* —— 段 4：状态机主体（唯一相位写入点；故障只置请求，锁存与迁相由段 7 执行，R21） —— *)
CASE _eState OF
    E_DL_AsrsSlotAllocSeq_State.eIdle :
        (* 迁移①：请求上升沿且使能 → 校验相；拍 N 进入 / 本拍行为：冲突计数与信息码归零 / 拍 N+1 转出 *)
        IF bEnable AND rtAlloc.Q THEN
            _iConflictCnt := DL_ASA_CNT_ZERO;                         // 新请求起点：冲突计数归零 / New request: conflict counter cleared
            _iInfoCode    := 0;                                       // 新请求起点：信息码归零 / New request: info code cleared
            _eState       := E_DL_AsrsSlotAllocSeq_State.eValidate;   // 进校验相 / Move to validate
        END_IF

    E_DL_AsrsSlotAllocSeq_State.eValidate :
        (* 零驻留判定相：三个分支都在本拍定相，无等待故无超时兜底需求（边界③） *)
        IF diReqSeq <= 0 THEN
            _iErrTmp   := 36;                                     // 故障级：请求序号非法（0/负=未初始化，禁参与握手）/ Fault: illegal request sequence
            _bFaultReq := TRUE;                                   // 请求段 7 锁存 / Request the latch at segment 7
        ELSIF bSlotLocked THEN
            _iErrTmp   := 32;                                     // 故障级：目标货位被锁闭 / Fault: target slot locked
            _bFaultReq := TRUE;                                   // 请求段 7 锁存 / Request the latch at segment 7
        ELSIF bStoreMode AND (NOT bSlotFree) THEN
            _iConflictCnt := _iConflictCnt + DL_ASA_ONE;           // 入库目标非空：冲突净额 +1 / Store target occupied: one net conflict
            _iInfoCode    := 31;                                   // 信息级：货位非空（不置 bError）/ Info: slot not free, bError stays false
            _eState       := E_DL_AsrsSlotAllocSeq_State.eRetry;   // 迁移③：转回退 / Move to retry
        ELSE
            _diOutSeq := diReqSeq;                                 // 下发序号写入点①：请求序号下发（唯一写入点集合）/ Write point one: publish the request sequence
            _diAckPublish := diAckSeq;                             // v1.0.1：记录发布时刻 ack 快照 / v1.0.1: snapshot ack at publish time
            _eState   := E_DL_AsrsSlotAllocSeq_State.eHandshake;   // 迁移②：进握手相 / Move to handshake
        END_IF

    E_DL_AsrsSlotAllocSeq_State.eHandshake :
        (* 同拍竞态处理：本拍合法事件（序号回齐）优先于超时迁移（R275），超时判定列最后 *)
        IF (diAckSeq = _diOutSeq) AND (diAckSeq <> _diAckPublish) AND (NOT _bFaultLatch) THEN
            (* v1.0.1 修法：同序号陈旧 ack 不得二次放行（fail-closed）/ v1.0.1: a stale equal ack must not re-grant *)
            _eState := E_DL_AsrsSlotAllocSeq_State.eCommit;         // 迁移⑤：回齐且无锁存，进放行相（R274 全量复检）/ Acknowledged, move to commit
        ELSIF diAckSeq > _diOutSeq THEN
            _iErrTmp   := 35;                                       // 故障级：序号超前（对端快于本端）/ Fault: sequence ahead of the published value
            _bFaultReq := TRUE;                                     // 请求段 7 锁存 / Request the latch at segment 7
        ELSIF tonAck.Q THEN
            _iConflictCnt := _iConflictCnt + DL_ASA_ONE;            // 应答超时：冲突净额 +1 / Acknowledgement timeout: one net conflict
            _iInfoCode    := 33;                                    // 信息级：应答超时（不置 bError）/ Info: acknowledgement timeout, bError stays false
            _eState       := E_DL_AsrsSlotAllocSeq_State.eRetry;    // 迁移⑥：转回退 / Move to retry
        END_IF

    E_DL_AsrsSlotAllocSeq_State.eRetry :
        (* 拍 N 进入（冲突发生）/ 本拍行为：耗尽判或净额回退并清下发序号 / 拍 N+1 转出（R80 三段式） *)
        IF _iConflictCnt >= DL_ASA_RETRY_MAX THEN
            _iErrTmp   := 34;                                       // 故障级：重试耗尽 / Fault: retries exhausted
            _bFaultReq := TRUE;                                     // 请求段 7 锁存 / Request the latch at segment 7
        ELSE
            _diOutSeq := 0;                                         // 下发序号写入点②：回退清零点（单赋值，禁两处同拍写）/ Write point two: rollback clearing
            _eState   := E_DL_AsrsSlotAllocSeq_State.eValidate;     // 迁移⑧：回校验相 / Back to validate
        END_IF

    E_DL_AsrsSlotAllocSeq_State.eCommit :
        (* 迁移⑩：放行单拍；拍 N 进入 / 本拍行为：bGrant 与 bDone 各置一次、货位锁存、拒绝重复放行 / 拍 N+1 转出至 eIdle *)
        IF NOT _bFaultLatch THEN
            _iAllocSlot  := iReqSlot;                               // 实际分配货位锁存 / Allocated slot latched
            _bGrantPulse := TRUE;                                   // 放行内部单拍置位（段 8 映射）/ Internal grant pulse raised and mapped at segment 8
            _bDonePulse  := TRUE;                                   // 完成内部单拍置位（段 8 映射）/ Internal done pulse raised and mapped at segment 8
            _eState      := E_DL_AsrsSlotAllocSeq_State.eIdle;      // 迁移⑩：回空闲相 / Back to idle
        END_IF

    E_DL_AsrsSlotAllocSeq_State.eFault :
        (* 迁移⑪：复位沿出口（唯一出口，穷举可达）/ 拍 N 进入 / 本拍行为：清锁存与序号，放行由段 8 归假 / 拍 N+1 转出至 eIdle *)
        IF rtReset.Q THEN
            _bFaultLatch  := FALSE;                                 // 清故障锁存 / Clear the fault latch
            _iErrLatch    := 0;                                     // 清锁存故障码 / Clear the latched fault code
            _iInfoCode    := 0;                                     // 清信息码 / Clear the info code
            _diOutSeq     := 0;                                     // 下发序号写入点③：复位清零点 / Write point three: reset clearing
            _iConflictCnt := DL_ASA_CNT_ZERO;                       // 冲突计数清零 / Conflict counter cleared
            _eState       := E_DL_AsrsSlotAllocSeq_State.eIdle;     // 回空闲相，不滞留故障态 / Back to idle, never parked in fault
        END_IF

ELSE
    (* 迁移⑫：非法枚举兜底（R6） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                    // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                  // 置故障锁存（码位赋值 3 行内配对，R45）/ Latch the fault within three lines
    END_IF
END_CASE

(* —— 段 7：当拍故障请求锁存 + 段尾故障迁移闸 + 撤使能降级（R191 已声明为降级+置标志） —— *)
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                  // 锁存当拍首因 / Latch the first cause of this scan
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_AsrsSlotAllocSeq_State.eFault) THEN
    _eState := E_DL_AsrsSlotAllocSeq_State.eFault;   // 锁存即迁相（段尾统一执行，FB50-1④）/ Latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_AsrsSlotAllocSeq_State.eIdle) THEN
    _diOutSeq    := 0;                         // 撤使能：撤销下发序号（握手作废）/ Disable: published sequence withdrawn
    _bGrantPulse := FALSE;                     // 撤使能：放行撤销 / Disable: grant withdrawn
    _eState      := E_DL_AsrsSlotAllocSeq_State.eIdle;   // 撤使能：回空闲相 / Disable: back to idle
END_IF

(* —— 段 8：统一出口（单点映射，禁在 CASE 后无条件清零 CASE 内赋值标识符，FB33-1） —— *)
eState       := _eState;                       // 相位映射 / Phase mapping
bBusy        := (_eState = E_DL_AsrsSlotAllocSeq_State.eValidate)
                OR (_eState = E_DL_AsrsSlotAllocSeq_State.eHandshake)
                OR (_eState = E_DL_AsrsSlotAllocSeq_State.eRetry)
                OR (_eState = E_DL_AsrsSlotAllocSeq_State.eCommit);   // 事务进行中 / Transaction in progress
bGrant       := _bGrantPulse AND (NOT _bFaultLatch);   // 放行输出（故障期强制撤销）/ Grant output forced off during fault
bDone        := _bDonePulse AND (NOT _bFaultLatch);    // 完成输出（故障期强制撤销）/ Done output forced off during fault
bError       := _bFaultLatch;                  // 故障标志取锁存位 / Fault flag taken from the latch
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                    // 故障期回放锁存码（FB33-1）/ Replay the latched code during fault
ELSE
    iErrCode := _iInfoCode;                    // 非故障期输出信息码（31/33 永不置 bError，R101）/ Info code outside fault, never raising bError
END_IF
diOutSeq     := _diOutSeq;                     // 下发序号映射 / Published sequence mapping
iAllocSlot   := _iAllocSlot;                   // 实际货位映射（撤使能保留事实，不撤回）/ Allocated slot mapping, kept on disable
iConflictCnt := _iConflictCnt;                 // 冲突计数映射 / Conflict counter mapping
END_FUNCTION_BLOCK
