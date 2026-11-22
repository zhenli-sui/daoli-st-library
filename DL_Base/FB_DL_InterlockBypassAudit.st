(*==============================================================================
 * 组件名称 (Component)  : FB_DL_InterlockBypassAudit
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : t2-8-isa182（ISA-182 旁路管理方法论，clean-room 编写）
 * 功能描述 (Function)   : 联锁旁路全生命周期审计：申请沿进入旁路态并启动时限窗，
 *                         时限到期自动恢复并置信息级码；人工解除沿即时恢复。
 *                         申请沿 / 解除沿 / 超时到期三类事件写入 8 条深度环形台账，
 *                         台账带全局序号与旁路计数（饱和不回绕）。
 *                         旁路期间目标联锁位仍照常计算，仅放行判定被旁路——
 *                         放行判定归调用方按 bBypassActive 组合，本件不替代联锁本体。
 * 分工互引 (Boundary)   : 联锁本体的条件求值与首因锁存归 FB_DL_InterlockMatrix；
 *                         安全门的旁路申请登记归 FB_DL_SafetyDoorAuditBank；
 *                         本件只负责旁路时限与事件台账审计，三者互不替代。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 时限窗 tBypassWindow <= T#0S 视为组态非法：置故障级码并拒绝进入旁路态，
 *      已在旁路态的不受影响（组态变更不追溯已生效旁路），故障锁存经复位沿清除。
 *   2) 同拍「申请沿 + 解除沿」：解除优先（安全侧）——旁路不进入、不记申请事件。
 *   3) 旁路态不锁存联锁故障：本件是审计器不是联锁本体，故障锁存语义归联锁件。
 *   4) 台账为 8 条环形，写满后覆盖最旧条目并置信息级提示；写指针回卷由模运算
 *      等价的显式 IF 归零实现，不做越界写。
 *   5) 旁路计数为 USINT 饱和计数：255 + 1 停在 255 不回绕；计数顶格本身可由
 *      uBypassCount = 255 直接观测，故不另设码位（R90 反证成立，不加码）。
 * 故障码表 (Error codes) :
 *   16#0001_03EE [故障级] 时限窗组态非法（<= T#0S），拒绝进入旁路态
 *                 反证：该场景仅可由「申请沿被拒 + 状态停 eIdle」观测，但拒因
 *                 （时限非法还是使能关闭）不可区分，现有输出组合无法唯一还原。
 *   16#0001_04B1 [信息级] 时限到期自动恢复（旁路被时限收割）
 *                 反证：到期恢复与人工解除对外都表现为退出旁路态，唯一差异
 *                 是台账事件种类，无码时 HMI 无法区分两类恢复事件。
 *                 回落路径（v1.0.1 · L1）：下一轮旁路申请被受理时归零——
 *                 该事件码只描述「上一轮的收割事实」，新一轮开始即不再是当下事件。
 *   16#0001_04B2 [信息级] 台账环形已回卷（最旧条目被覆盖，审计完整性降级）
 *                 反证：回卷后 nLedgerCount 恒为 8，与「恰好写满未回卷」的
 *                 输出组合完全相同，不可由现有输出观测。
 *                 回落路径（v1.0.1 · L1）：一次性事件码（bWrapCoded 单次置位），
 *                 复位沿清除；回卷状态本身由 bLedgerWrapped 常驻表达（状态与
 *                 事件分离：码承载事件，位承载状态）。
 *   非法状态拦截复用全库惯用码 16#0001_0005（不新占号）。
 * 码位总账 (Code ledger) : 16#0001_03EE 用 ｜ 16#0001_04B1 用 / 16#0001_04B2 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 标准库 ｜ R4 ✓ 时间窗判零 / 计数饱和 / 指针无涉
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 三态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 一沿三实例主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 1 · 目标 1）
 *   2026-11-22  v1.0.1  R69 点修①：迁相（组态故障打断 / 非法态兜底）补 bBypassOn := FALSE，
 *                       防新组态首旁路立即到期；点修⑤：信息码 04B1 随新一轮旁路受理回落、
 *                       04B2 改一次性事件码并由复位沿回落（回卷状态仍由 bLedgerWrapped 常驻）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_BypassState（归属 DL_Base，与 FB_DL_InterlockBypassAudit 同文件）
 * 含义: 旁路审计主状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_BypassState :
(
    eIdle     := 0,    // 未旁路：联锁照常生效 / No bypass, interlock fully effective
    eBypassed := 10,   // 旁路生效中：时限窗计时 / Bypass active, time window running
    eFault    := 99    // 组态故障：时限窗非法，拒绝一切新旁路 / Config fault, window illegal
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_BypassEventKind（归属 DL_Base，与 FB_DL_InterlockBypassAudit 同文件）
 * 含义: 台账事件种类，三类全生命周期事件一一对应。
 *----------------------------------------------------------------------------*)
TYPE E_DL_BypassEventKind :
(
    eNone   := 0,    // 无事件（台账空槽哨兵）/ No event, empty ledger slot sentinel
    eApply  := 1,    // 申请沿：进入旁路态 / Apply edge: bypass entered
    eReleaseByCmd     := 2,  // 解除沿：人工解除 / Release edge: manual release
    eReleaseByTimeout := 3   // 超时到期：自动恢复 / Timeout expiry: auto restore
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_InterlockBypassAudit
 * 调用约定: 每个扫描周期无条件调用一次；申请沿与解除沿均为单拍沿语义。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多机组并行实例化。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_InterlockBypassAudit
VAR_INPUT
    bBypassReq     : BOOL;                    // 旁路申请，上升沿生效 / Bypass request, rising edge
    bBypassRelease : BOOL;                    // 旁路解除，上升沿生效 / Bypass release, rising edge
    uInterlockId   : UINT  := 0;              // 目标联锁号 [号]，随事件入台账 / Target interlock id, logged per event
    uSourceId      : UINT  := 0;              // 申请源标识 [号]，随事件入台账 / Request source id, logged per event
    tBypassWindow  : TIME  := T#30S;          // 旁路时限窗 [s]，<= T#0S 组态非法 / Bypass window [s], <= 0 illegal
    bEnable        : BOOL  := TRUE;           // 审计使能，FALSE 时冻结不受理新申请 / Audit enable, FALSE freezes new requests
    bReset         : BOOL;                    // 上升沿：清除组态故障锁存 / Rising edge: clear config fault latch
END_VAR
VAR_OUTPUT
    bBypassActive  : BOOL;                   // 旁路生效中（供调用方放行判定组合）/ Bypass active for the caller gating
    uBypassCount   : USINT;                  // 累计旁路次数 [次]，255 饱和 / Total bypass count, saturates at 255
    nLedgerCount   : INT;                    // 台账有效条数 [条]，0..8 / Valid ledger entries, 0..8
    bLedgerWrapped : BOOL;                   // 台账已回卷覆盖（信息级）/ Ledger wrapped, oldest overwritten
    eLastEvent     : E_DL_BypassEventKind;   // 最近一次事件种类 / Kind of the most recent event
    uLastEventSeq  : UDINT;                  // 最近事件全局序号 [号] / Global sequence of the last event
    uLastTarget    : UINT;                   // 最近事件目标联锁号 [号] / Target id of the last event
    uLastSource    : UINT;                   // 最近事件申请源标识 [号] / Source id of the last event
    aLedgerKind    : ARRAY[0..7] OF E_DL_BypassEventKind; // 台账事件种类环形副本 / Ledger kind ring copy
    auLedgerTarget : ARRAY[0..7] OF UINT;    // 台账目标联锁号环形副本 / Ledger target ring copy
    auLedgerSource : ARRAY[0..7] OF UINT;    // 台账申请源标识环形副本 / Ledger source ring copy
    bError         : BOOL;                   // 故障标志（组态类锁存）/ Fault flag, configuration class latched
    uErrorId       : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = none
    eState         : E_DL_BypassState;       // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReq      : R_TRIG;                 // 申请沿检测实例 / Request edge detector
    fbTrigRel      : R_TRIG;                 // 解除沿检测实例 / Release edge detector
    fbTrigReset    : R_TRIG;                 // 复位沿检测实例 / Reset edge detector
    tonWindow      : TON;                    // 旁路时限窗计时实例 / Bypass window timer
    eStateInt      : E_DL_BypassState;       // 主状态机内部当前态 / Internal state machine state
    bWindowInvalid : BOOL;                   // 本拍时限窗组态非法 / Window config illegal this scan
    bConfigLatch   : BOOL;                   // 组态故障锁存（复位沿清除）/ Config fault latch, cleared by reset edge
    bBypassOn      : BOOL;                   // 旁路窗计时进行中（TON 的 IN 派生量）/ Window timing active, drives TON.IN
    aeKindInt      : ARRAY[0..7] OF E_DL_BypassEventKind; // 台账事件种类（内部）/ Ledger kind ring, internal
    auiTargetInt   : ARRAY[0..7] OF UINT;    // 台账目标联锁号（内部）/ Ledger target ring, internal
    auiSourceInt   : ARRAY[0..7] OF UINT;    // 台账申请源标识（内部）/ Ledger source ring, internal
    nWriteIdx      : INT;                    // 台账写指针 [0..7] / Ledger write pointer
    uEventTotal    : UDINT;                  // 累计事件总数 [件]，环形深度之外的真值 / Total events ever, truth beyond ring depth
    uSeqCounter    : UDINT;                  // 全局序号计数器 [号]，饱和 / Global sequence counter, saturating
    uCntInt        : USINT;                  // 旁路计数内部副本（饱和）/ Internal bypass counter, saturating
    uTargetInt     : UINT;                   // 最近事件目标号内部副本 / Internal copy of last target id
    uSourceInt     : UINT;                   // 最近事件源号内部副本 / Internal copy of last source id
    eLastEventInt  : E_DL_BypassEventKind;   // 最近事件种类内部副本 / Internal copy of last event kind
    uLastSeqInt    : UDINT;                  // 最近事件序号内部副本 / Internal copy of last event sequence
    bErrorInt      : BOOL;                   // 本拍故障置位累加（出口归并）/ Fault set accumulator of this scan
    bWrapCoded     : BOOL;                   // 回卷事件码已发标志（防每拍重发，复位沿撤销）/ Wrap event already coded, cleared by reset
    bFirstScan     : BOOL := TRUE;           // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_BYP_RING_DEPTH : INT   := 8;            // 台账环形深度 [条]，与数组维度一致 / Ledger ring depth, matches arrays
    DL_BYP_CNT_MAX    : USINT := 255;          // 旁路计数饱和值 [次] / Bypass counter saturation
    DL_BYP_SEQ_MAX    : UDINT := 16#FFFF_FFFE; // 序号计数饱和值 [号] / Sequence counter saturation
    DL_BYP_IDX_NONE   : INT   := 0;            // 空槽哨兵：0 号槽事件种类 eNone / Empty slot via kind sentinel
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：三沿 + 一计时，全部位于主体最前部
 *      Unconditional refresh zone: three edges and one timer at the very top
 *      TON 的 IN 用内部派生量 bBypassOn（旁路态驻留标志），禁挂外部引脚原值
 *-----------------------------------------------------------------------------*)
fbTrigReq(CLK := bBypassReq);
fbTrigRel(CLK := bBypassRelease);
fbTrigReset(CLK := bReset);
tonWindow(IN := bBypassOn, PT := tBypassWindow);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫（FB50-2①）：台账槽位显式落哨兵，不依赖默认零的巧合
 *      First-scan init: ledger slots forced to sentinels explicitly
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    FOR nWriteIdx := 0 TO (DL_BYP_RING_DEPTH - 1) DO
        aeKindInt[nWriteIdx] := E_DL_BypassEventKind.eNone;   // 空槽哨兵 / Empty slot sentinel
    END_FOR
    nWriteIdx   := 0;
    uEventTotal := 0;
    uSeqCounter := 0;
    uCntInt     := 0;
    bWrapCoded  := FALSE;   // 回卷事件码首扫未发 / Wrap event not yet coded
    eStateInt   := E_DL_BypassState.eIdle;
    bFirstScan  := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1：只准含单拍标志，禁入快照 / 累计 / 锁存量）
 *      Per-scan preset: single-scan flags only, no snapshots or latches
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151）：时限窗 <= T#0S 即非法；非法即锁存，复位沿 + 组态恢复可解除
 *      Config gate: window <= 0 is illegal; latched, cleared by reset edge with valid config
 *      解除路径自证：bReset 上升沿 AND 组态已改对（R152 可达性）
 *-----------------------------------------------------------------------------*)
bWindowInvalid := (tBypassWindow <= T#0S);

IF bWindowInvalid THEN
    bConfigLatch := TRUE;
END_IF

IF bConfigLatch THEN
    uErrorId  := 16#0001_03EE;   // 故障级：时限窗组态非法 / Fault: window config illegal
    bErrorInt := TRUE;           // R45 配对：故障码 3 行内置位 / Paired with the fault code
    eStateInt := E_DL_BypassState.eFault;
    (* R69 点修①（迁相补清）：故障打断旁路时同步撤窗计时量。原实现只迁相不清
     * bBypassOn，TON.IN 常真 -> 时限窗在故障期照走并在修复后率先到期，
     * 新组态首旁路一进 eBypassed 即被 tonWindow.Q 收割（04B1 误报、旁路退化）。 *)
    (* Phase migration also drops the window timing quantity, so the window cannot expire during the fault *)
    bBypassOn := FALSE;          // 迁相即断计时：TON.IN 归假 / Timing quantity dropped on migration
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *      使能冻结语义：空闲相受理判据内串 bEnable，失能即拒绝新申请（不另设覆盖段，
 *      避免「禁用覆盖吃掉沿」类 R39 失真）；已生效旁路的时限窗照走（审计不中断）。
 *      同拍竞态（R275）：eBypassed 相内先消化解除沿，再消化超时迁移
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_BypassState.eIdle:
        (* 同拍「申请 + 解除」：解除优先（安全侧），申请沿作废不记台账 *)
        (* Same-scan request plus release: release wins on the safe side *)
        IF bEnable AND (NOT bConfigLatch) AND fbTrigReq.Q AND (NOT fbTrigRel.Q) THEN
            uErrorId     := 16#0000_0000;   // 信息码回落（R69 点修⑤）：上一轮收割 / 回卷事件不再属当下
                                            // Info codes fall back as a new bypass cycle starts
            bBypassOn    := TRUE;
            uTargetInt   := uInterlockId;
            uSourceInt   := uSourceId;
            WriteLedger(eKind := E_DL_BypassEventKind.eApply);
            eStateInt    := E_DL_BypassState.eBypassed;
        END_IF
        (* 空闲相收到解除沿：无旁路对象，事件不入台账（无中生有即伪造证据） *)
        (* Release edge while idle: nothing to release, not logged *)

    E_DL_BypassState.eBypassed:
        IF fbTrigRel.Q THEN
            (* 本拍解除沿优先于超时迁移（R275）：人工解除即时生效 *)
            (* Release edge outranks the timeout transition in the same scan *)
            bBypassOn  := FALSE;
            uTargetInt := uInterlockId;
            uSourceInt := uSourceId;
            WriteLedger(eKind := E_DL_BypassEventKind.eReleaseByCmd);
            eStateInt  := E_DL_BypassState.eIdle;
        ELSIF tonWindow.Q THEN
            (* 时限到期自动恢复：信息级码（信息级允许每拍重算，本拍一次性落账） *)
            (* Window expired: auto restore, info-level code *)
            bBypassOn  := FALSE;
            uErrorId   := 16#0001_04B1;
            uTargetInt := uInterlockId;
            uSourceInt := uSourceId;
            WriteLedger(eKind := E_DL_BypassEventKind.eReleaseByTimeout);
            eStateInt  := E_DL_BypassState.eIdle;
        END_IF

    E_DL_BypassState.eFault:
        (* 解除路径（R152 自证可达）：复位沿 AND 组态已改对（bWindowInvalid 已消） *)
        (* Clear path: reset edge AND the config is fixed, provably reachable *)
        IF fbTrigReset.Q AND (NOT bWindowInvalid) THEN
            bConfigLatch := FALSE;
            uErrorId     := 16#0000_0000;
            eStateInt    := E_DL_BypassState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：不做隐式恢复，直接锁存上报（全库惯用码 0001_0005） *)
        (* Illegal state interception: latch and report, no implicit recovery *)
        eStateInt := E_DL_BypassState.eFault;
        uErrorId  := 16#0001_0005;
        bErrorInt := TRUE;
        bBypassOn := FALSE;      // 迁相补清（R69 点修①）：非法态兜底同样断窗计时 / Same migration clearance

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜输出单一出口（范式 P-05）：旁路位只由状态派生一次
 *      Single output exit: the bypass bit derives from the state exactly once
 *      eFault / eIdle 相旁路位必为 FALSE：故障态不携带旁路放行（安全侧）
 *-----------------------------------------------------------------------------*)
bBypassActive  := (eStateInt = E_DL_BypassState.eBypassed);
uBypassCount   := uCntInt;
bLedgerWrapped := (uEventTotal > UDINT#8);
(* 04B2 一次性事件码（R69 点修⑤）：回卷首次发生才发一次，禁每拍重发（信息级可每拍
 * 重算但事件码重发会淹没后续事件码）。回落：复位沿 AND 无组态锁存即归零。 *)
(* Wrap event code is one-shot; it falls back on a reset edge without a config latch *)
IF bLedgerWrapped AND (NOT bWrapCoded) THEN
    uErrorId   := 16#0001_04B2;    // 信息级：台账回卷覆盖 / Info: ledger wrapped
    bWrapCoded := TRUE;            // 一次性标记 / One-shot marker
END_IF
IF fbTrigReset.Q AND (NOT bConfigLatch) THEN
    uErrorId   := 16#0000_0000;    // 信息码随复位沿回落 / Info codes fall back on reset
    bWrapCoded := FALSE;           // 回卷事件码重新武装（再次回卷才重发）/ Re-armed for a later wrap
END_IF
IF UDINT_TO_DINT(uEventTotal) < DINT#8 THEN
    nLedgerCount := DINT_TO_INT(UDINT_TO_DINT(uEventTotal));
ELSE
    nLedgerCount := 8;           // 环形深度即上限 [条] / Ring depth is the cap
END_IF
eLastEvent   := eLastEventInt;
uLastEventSeq := uLastSeqInt;
uLastTarget  := uTargetInt;
uLastSource  := uSourceInt;

FOR nWriteIdx := 0 TO (DL_BYP_RING_DEPTH - 1) DO
    aLedgerKind[nWriteIdx] := aeKindInt[nWriteIdx];     // 台账副本直出 / Ledger copy out
    auLedgerTarget[nWriteIdx] := auiTargetInt[nWriteIdx];
    auLedgerSource[nWriteIdx] := auiSourceInt[nWriteIdx];
END_FOR

bError := bErrorInt OR (eStateInt = E_DL_BypassState.eFault);
eState := eStateInt;
END_FUNCTION_BLOCK

(*------------------------------------------------------------------------------
 * 私有方法: WriteLedger —— 台账环形写入唯一入口（写指针 / 序号 / 计数三记账）
 *      Private method: the single ledger write entry, books pointer, seq and count
 *      调用约定: 仅在本件主体 CASE 内调用；无阻塞、无跨周期状态驻留之外副作用
 *----------------------------------------------------------------------------*)
METHOD WriteLedger
VAR_INPUT
    eKind : E_DL_BypassEventKind;   // 待写事件种类 / Event kind to be written
END_VAR
VAR
    nSlot : INT;                    // 本次写入槽位 [0..7] / Slot index of this write
END_VAR

nSlot := nWriteIdx;                                 // 取当前写指针 / Take the current pointer
aeKindInt[nSlot] := eKind;                          // 事件种类入账 / Kind into the ledger
auiTargetInt[nSlot] := uTargetInt;                  // 目标联锁号入账 / Target id into the ledger
auiSourceInt[nSlot] := uSourceInt;                  // 申请源标识入账 / Source id into the ledger

IF uSeqCounter < DL_BYP_SEQ_MAX THEN
    uSeqCounter := uSeqCounter + 1;                 // 序号推进（饱和）/ Advance sequence, saturating
END_IF
uLastSeqInt   := uSeqCounter;                       // 最近事件序号留影 / Snapshot last sequence
eLastEventInt := eKind;                             // 最近事件种类留影 / Snapshot last kind

IF uCntInt < DL_BYP_CNT_MAX THEN
    uCntInt := uCntInt + 1;                         // 旁路计数推进（255 饱和不回绕）/ Count up, saturating
END_IF

uEventTotal := uEventTotal + 1;                     // 累计事件推进（回卷判据）/ Total events up

nWriteIdx := nWriteIdx + 1;                         // 写指针推进 / Advance the write pointer
IF nWriteIdx >= DL_BYP_RING_DEPTH THEN
    nWriteIdx := 0;                                 // 显式回卷（禁 MOD 方言，IF 等价实现）/ Explicit wrap, IF form
END_IF

END_METHOD
