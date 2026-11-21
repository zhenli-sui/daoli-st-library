(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FormationChannelQueue
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 化成柜通道排队与优先级抢占调度。申请（通道号+
 *                         优先级 0 高..3 低）入队；调度相取队列中最高优先级
 *                         （数值最小，同级先入先出）派发；运行中更高级申请到
 *                         来即抢占（当前通道回队头，bPreempt 单拍）；被派通道
 *                         bChanFault 电平即故障摘除（不回队，bEvict 单拍）；
 *                         bChanDone 沿正常收口计数。与 MotionCmdQueue/FifoBuffer
 *                         （通用队列）分工：本件是资源排队 + 优先级抢占 + 故障
 *                         摘除的调度语义。
 * 来源标签 (Origin)     : ROADMAP §16.1 R11 池（L694），自研 clean-room
 * 边界语义 (Boundary)   : ① 队满申请沿：bQueueFull 指示该拍拒收（申请丢弃，
 *                         头注释明示不缓存）；
 *                         ② 摘除/收口/抢占后的队列搬移用单向前移复制，游标
 *                         0..8 结构性有界；
 *                         ③ 优先级域闸 0..3 / 通道号域闸 1..99 越域 → 组态故障；
 *                         ④ 抢占只回队不重派，防同拍振荡。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 派发保持（运行通道不中断，
 *                         由调用方决定停机）；eFault 相 → 派发撤销 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 越界（游标有界）/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 队空申请（5,1）→ 立即派发 nDispatch=5；
 *                         V2 运行中申请（7,0）→ bPreempt 单拍，5 回队头，
 *                         7 抢占派发；
 *                         V3 运行通道故障电平 → bEvict 单拍不回队，自动派
 *                         队内次高优先级。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 1 · 序号 3）
 *==============================================================================*)
TYPE E_DL_FcqState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eDispatch := 10,                         (* 有通道运行（队列可继续接纳） / Dispatching *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_FcqCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：优先级/通道号越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FormationChannelQueue
VAR_INPUT
    bReq       : BOOL := FALSE;              (* 申请电平（上升沿入队）[-] / Request level, edge enqueues *)
    nChanId    : INT := 0;                   (* 申请通道号，域 1..99 [-] / Channel id *)
    nPrio      : INT := 3;                   (* 申请优先级 0 高..3 低，域 0..3 [-] / Priority *)
    bChanDone  : BOOL := FALSE;              (* 运行通道完成沿 [-] / Dispatched channel done edge *)
    bChanFault : BOOL := FALSE;              (* 运行通道故障电平（摘除不回队）[-] / Dispatched channel fault *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nDispatchId : INT;                       (* 派发通道号（0 = 无派发）[-] / Dispatched channel id *)
    bDispatchValid : BOOL;                   (* 派发有效指示 [-] / Dispatch valid *)
    nQueueDepth : INT;                       (* 当前队列深度 [条] / Queue depth *)
    bQueueFull  : BOOL;                      (* 队满指示（该拍申请拒收）[-] / Queue full *)
    bPreempt    : BOOL;                      (* 抢占单拍位 [-] / Preempt pulse *)
    bEvict      : BOOL;                      (* 故障摘除单拍位 [-] / Evict pulse *)
    nDoneCnt    : UDINT;                     (* 正常收口累计 [次] / Done count *)
    eState      : E_DL_FcqState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_FcqCause;             (* 故障成因出口 / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_FcqState := E_DL_FcqState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_FcqCause := E_DL_FcqCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReq     : R_TRIG;                     (* 申请沿实例，段 0 无条件调用 / Request edge *)
    rtDone    : R_TRIG;                     (* 完成沿实例，段 0 无条件调用 / Done edge *)
    rtReset   : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge *)
    _anId     : ARRAY[1..8] OF INT;         (* 队列通道号槽 [—] / Queue id slots *)
    _anPrio   : ARRAY[1..8] OF INT;         (* 队列优先级槽 [-] / Queue priority slots *)
    _nDepth   : INT;                        (* 队列深度锁存 [条] / Depth latch *)
    _nDispId  : INT;                        (* 派发通道号锁存 [-] / Dispatch id latch *)
    _nPrioDispL : INT;                      (* 派发通道优先级锁存（抢占判据用）[-] / Dispatched prio latch *)
    _bDisp    : BOOL;                       (* 派发有效锁存 [-] / Dispatch valid latch *)
    _bPreempt : BOOL;                       (* 抢占单拍量 [-] / Preempt pulse work *)
    _bEvict   : BOOL;                       (* 摘除单拍量 [-] / Evict pulse work *)
    _bFull    : BOOL;                       (* 队满单拍量 [-] / Full pulse work *)
    _nSel     : INT;                        (* 最高优先级选中槽（每趟重算）[-] / Selected slot *)
    _i        : INT;                        (* 搬移游标（每趟重置，R227）[-] / Shift cursor *)
    _nDone    : UDINT;                      (* 收口计数锁存 [次] / Done count latch *)
    _bFault   : BOOL;                       (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                       (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_FCQ_QMAX : INT := 8;                  (* 队列容量 [条] / Queue capacity *)
    DL_FCQ_IDMAX: INT := 99;                 (* 通道号上限 [-] / Channel id max *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
_bCfgBad := (bReq AND ((nChanId < 1) OR (nChanId > DL_FCQ_IDMAX) OR (nPrio < 0) OR (nPrio > 3)));   (* 组态闸：申请沿域闸（R151） / Config gate on request domain *)
rtReq(CLK := bReq);                          (* 申请沿每拍必调 / Request edge every scan *)
rtDone(CLK := bChanDone);                    (* 完成沿每拍必调 / Done edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bPreempt := FALSE;                          (* 抢占脉冲预清，唯一分支置位 / Preempt preset *)
_bEvict := FALSE;                            (* 摘除脉冲预清 / Evict preset *)
_bFull := FALSE;                             (* 队满脉冲预清 / Full preset *)
_nSel := 0;                                  (* 选中槽预清（每趟重算，R285） / Selected slot preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清队列 + 清派发 + 清计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_FcqCause.eNone;          (* 清成因 / Clear cause *)
    _nDepth := 0;                            (* 清队列深度 / Clear depth *)
    _nDispId := 0;                           (* 清派发号 / Clear dispatch id *)
    _nPrioDispL := 0;                        (* 清派发优先级锁存 / Clear prio latch *)
    _bDisp := FALSE;                         (* 清派发有效 / Clear valid *)
    nDispatchId := 0;                        (* 清派发出口 / Clear outlet *)
    _nDone := 0;                             (* 清收口计数 / Clear done count *)
    _eState := E_DL_FcqState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_FcqCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_FcqState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_FcqState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_FcqState.eDispatch;   (* 进入调度 / Enter dispatch *)
        END_IF
    E_DL_FcqState.eDispatch:                 (* 调度相：入队 + 抢占 + 摘除 + 收口 + 派发 / Dispatch *)
        IF NOT bEnable THEN
            _eState := E_DL_FcqState.eIdle;  (* 失能回待机（派发保持，R191 声明） / Back to idle, dispatch held *)
        ELSE
            IF rtReq.Q THEN                  (* 申请沿：入队 / Enqueue on edge *)
                IF _nDepth < DL_FCQ_QMAX THEN
                    _nDepth := _nDepth + 1;  (* 深度 +1 / Depth up *)
                    _anId[_nDepth] := nChanId;       (* 尾插通道号 / Append id *)
                    _anPrio[_nDepth] := nPrio;       (* 尾插优先级 / Append prio *)
                ELSE
                    _bFull := TRUE;          (* 队满拒收单拍（不缓存，边界①） / Full reject *)
                END_IF
            END_IF
            IF _bDisp AND bChanFault THEN    (* 运行通道故障：摘除不回队 / Evict on fault *)
                _bEvict := TRUE;             (* 摘除单拍 / Evict pulse *)
                _bDisp := FALSE;             (* 撤派发 / Drop dispatch *)
            END_IF
            IF _bDisp AND rtDone.Q THEN      (* 正常收口 / Normal done *)
                _nDone := _nDone + 1;        (* 收口计数（UDINT 回绕 ≈ 49 天 @1kHz，工程安全） / Count done *)
                _bDisp := FALSE;             (* 撤派发 / Drop dispatch *)
            END_IF
            IF _bDisp AND rtReq.Q AND (NOT _bFull) AND (nPrio < _nPrioDispL) AND (_nDepth < DL_FCQ_QMAX) THEN
                (* 抢占：更优优先级申请且队列可容纳回队件 / Preempt: better prio + room for requeue *)
                _i := _nDepth;               (* 队列后移游标自尾起（R227） / Shift cursor from tail *)
                WHILE _i >= 1 DO             (* 全队后移一格腾出队头 / Shift back one slot *)
                    _anId[_i + 1] := _anId[_i];   (* 通道号后移 / Shift id *)
                    _anPrio[_i + 1] := _anPrio[_i];   (* 优先级后移 / Shift prio *)
                    _i := _i - 1;            (* 游标递退 / Cursor back *)
                END_WHILE
                _anId[1] := _nDispId;        (* 被抢占通道回队头 / Requeue preempted *)
                _anPrio[1] := 3;             (* 回队降为最低级（防反复抢占振荡，边界④） / Requeue at lowest prio *)
                _nDepth := _nDepth + 1;      (* 深度 +1 / Depth up *)
                _bPreempt := TRUE;           (* 抢占单拍 / Preempt pulse *)
                _bDisp := FALSE;             (* 撤当前派发 / Drop dispatch *)
            END_IF
            IF (NOT _bDisp) AND (_nDepth >= 1) THEN   (* 空派发且有队列：选最高优先级（数值最小，同级先入先出） / Pick best *)
                _nSel := 1;                  (* 先选队头（同级 FIFO 基准） / Seed with head *)
                _i := 2;                     (* 扫描游标重置（R227） / Scan cursor reset *)
                WHILE _i <= _nDepth DO       (* 逐槽找数值最小优先级 / Find min prio *)
                    IF _anPrio[_i] < _anPrio[_nSel] THEN
                        _nSel := _i;         (* 更优槽 / Better slot *)
                    END_IF
                    _i := _i + 1;            (* 游标递进 / Cursor advance *)
                END_WHILE
                _nDispId := _anId[_nSel];    (* 派发选中通道 / Dispatch selected *)
                _nPrioDispL := _anPrio[_nSel];   (* 锁存派发优先级（抢占判据基准） / Latch dispatched prio *)
                _bDisp := TRUE;              (* 置派发有效 / Set valid *)
                _i := _nSel;                 (* 删除搬移游标（R227） / Removal cursor *)
                WHILE _i < _nDepth DO        (* 后件前移补空 / Shift forward *)
                    _anId[_i] := _anId[_i + 1];   (* 通道号前移 / Shift id *)
                    _anPrio[_i] := _anPrio[_i + 1];   (* 优先级前移 / Shift prio *)
                    _i := _i + 1;            (* 游标递进 / Cursor advance *)
                END_WHILE
                _nDepth := _nDepth - 1;      (* 深度 -1 / Depth down *)
            END_IF
        END_IF
    E_DL_FcqState.eFault:                    (* 故障相：撤派发，仅复位沿出 / Fault *)
        _bDisp := FALSE;                     (* 故障相派发撤销（安全侧） / Drop dispatch in fault *)
        _nDispId := 0;                       (* 派发号清零 / Clear id *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_FcqState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_FcqCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nDispatchId := _nDispId;                     (* 派发号出口 / Dispatch id outlet *)
bDispatchValid := _bDisp;                    (* 派发有效出口 / Valid outlet *)
nQueueDepth := _nDepth;                      (* 深度出口 / Depth outlet *)
bQueueFull := _bFull;                        (* 队满脉冲出口 / Full outlet *)
bPreempt := _bPreempt;                       (* 抢占脉冲出口 / Preempt outlet *)
bEvict := _bEvict;                           (* 摘除脉冲出口 / Evict outlet *)
nDoneCnt := _nDone;                          (* 收口计数出口 / Done count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
