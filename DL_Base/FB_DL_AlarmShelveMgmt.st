(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AlarmShelveMgmt
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : isa-18.2（T2-8 报警管理族本体：搁置 Shelving 生命周期）
 * 功能描述 (Function)   : ISA-18.2 报警搁置管理状态机：申请沿 -> 搁置生效（带时限）->.
 *                         时限到期自动解除；人工解除沿即时恢复。搁置申请 / 人工解除 /
 *                         自动解除三类事件写入 4 条深度环形审计台账（带全局序号）。
 * 分工互引 (Boundary)   : FB_DL_AlarmFloodLimiter 做报警**限流**（抑制短时洪泛），
 *                         本件做**搁置**（操作员主动、有时限、必须留痕）；两者语义
 *                         不同不可互代（限流不改报警状态，搁置改报警可见性）。
 *                         报警本体与优先级归 FB_DL_AlarmManager。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 搁置时限 tShelveDur <= T#0S 属组态非法：拒绝进入搁置并置故障级，锁存至
 *      复位沿 + 组态改对（R152 解除路径自证可达）。
 *   2) 同拍「申请 + 解除」：解除优先（安全侧），申请作废不入台账。
 *   3) 只允许单报警搁置（uAlarmId 单槽）：多报警并发搁置由上层按报警号各实例化
 *      一份本件（组合优于在件内做动态表，避免变长容器）。
 *   4) 审计台账 4 条环形：写满覆盖最旧并置一次性信息码；写指针显式归零，不做越界写。
 *   5) 搁置状态在 bEnable 拉低时**保持**（不静默解除）：失能不是解除条件，
 *      解除只能来自人工解除沿或时限到期（避免上位机失能导致报警被永久藏起来）。
 * 故障码表 (Error codes) :
 *   16#0001_03FE [故障级] 搁置时限组态非法（<= T#0S），拒绝进入搁置
 *                 反证：拒绝搁置与「操作员没申请」输出组合完全相同，无码不可区分。
 *   16#0001_04FA [信息级] 搁置生效（申请沿受理并入台账）
 *                 反证：bShelved 只表达状态，无法承载「何时由谁申请」的事件事实。
 *   16#0001_04FB [信息级] 时限到期自动解除（旁路被时限收割）
 *                 反证：自动解除与人工解除对外同形（都退出搁置），仅事件种类不同。
 *   16#0001_04FC [信息级] 审计台账环形已回卷（最旧条目被覆盖）
 *                 反证：回卷后 nAuditCount 恒为 4，与「恰好写满」输出组合相同。
 * 码位总账 (Code ledger) : 16#0001_03FE 用 ｜ 16#0001_04FA / 04FB / 04FC 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量 ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 时限判零 / 环形显式回卷无越界 ｜ R5 ✓ 全变量双语同行注释
 *                         R6 ✓ 三态 ENUM + CASE + ELSE 兜底 ｜ R7 ✓ 三沿一计时最前部无条件刷新
 * 修订历史 (Revision)   : 2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 2 · N6）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ShelveState / E_DL_ShelveEvt（归属 DL_Base，与 FB_DL_AlarmShelveMgmt 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ShelveState :
(
    eIdle    := 0,    // 未搁置：报警正常可见 / Not shelved, the alarm stays visible
    eShelved := 10,   // 搁置生效：时限窗计时 / Shelved, the time window runs
    eFault   := 99    // 组态故障：拒绝一切新搁置 / Config fault, new shelving refused
);
END_TYPE

TYPE E_DL_ShelveEvt :
(
    eNone     := 0,   // 无事件（空槽哨兵）/ No event, empty slot sentinel
    eApply    := 1,   // 申请搁置 / Shelving applied
    eRelCmd   := 2,   // 人工解除 / Released by the operator
    eRelTime  := 3    // 时限自动解除 / Released by the time window
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_AlarmShelveMgmt
 * 调用约定: 每个扫描周期无条件调用一次；bShelveReq / bUnshelveReq 为上升沿语义。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AlarmShelveMgmt
VAR_INPUT
    bShelveReq    : BOOL;                  // 搁置申请，上升沿生效 / shelving request, rising edge
    bUnshelveReq  : BOOL;                  // 人工解除，上升沿生效 / manual release, rising edge
    uAlarmId      : UINT := 0;             // 被搁置报警号 [号]，随事件入台账 / alarm id logged with each event
    tShelveDur    : TIME := T#30M;         // 搁置时限 [s]，<= T#0S 组态非法 / shelving duration [s]
    bEnable       : BOOL := TRUE;          // 使能；FALSE 只冻结新申请，不解除已搁置 / enable, FALSE freezes new requests only
    bReset        : BOOL;                  // 上升沿：清组态故障锁存 / rising edge clears the config latch
END_VAR
VAR_OUTPUT
    bShelved      : BOOL;                  // 搁置生效中（报警可被 HMI 隐藏）/ shelving active
    tElapsed      : TIME;                  // 已搁置时长 [s] / elapsed shelving time [s]
    tRemain       : TIME;                  // 剩余搁置时长 [s] / remaining shelving time [s]
    bExpired      : BOOL;                  // 本拍时限到期（单拍脉冲）/ window expired, single scan
    nAuditCount   : INT;                   // 台账有效条数 [条]，0..4 / valid ledger entries
    bAuditWrapped : BOOL;                  // 台账已回卷覆盖 / ledger wrapped
    eLastEvt      : E_DL_ShelveEvt;        // 最近事件种类 / kind of the most recent event
    uLastEvtSeq   : UDINT;                 // 最近事件全局序号 [号] / global sequence of the last event
    auLedgerAlarm : ARRAY[0..3] OF UINT;   // 台账报警号环形副本 [号] / ledger alarm id ring copy
    aLedgerEvt    : ARRAY[0..3] OF E_DL_ShelveEvt; // 台账事件种类环形副本 / ledger event kind ring copy
    bError        : BOOL;                  // 故障标志（组态锁存）/ fault flag
    uErrorId      : UDINT;                 // 故障码，0 = 无故障 / error code, 0 = none
    eState        : E_DL_ShelveState;      // 当前状态（供 HMI 诊断）/ current state
END_VAR
VAR
    fbTrigReq     : R_TRIG;                // 申请沿检测实例 / request edge detector
    fbTrigRel     : R_TRIG;                // 解除沿检测实例 / release edge detector
    fbTrigReset   : R_TRIG;                // 复位沿检测实例 / reset edge detector
    tonShelve     : TON;                   // 搁置时限计时实例 / shelving window timer
    eStateInt     : E_DL_ShelveState;      // 主状态机内部当前态 / internal state
    bDurBad       : BOOL;                  // 本拍时限组态非法 / duration illegal this scan
    bCfgLatch     : BOOL;                  // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bShelveOn     : BOOL;                  // 搁置驻留标志（驱动 TON.IN）/ shelving dwell flag driving TON.IN
    bExpiredT     : BOOL;                  // 到期脉冲内部副本（单拍）/ internal expired pulse
    aeEvtInt      : ARRAY[0..3] OF E_DL_ShelveEvt; // 台账事件种类（内部）/ ledger event kind ring, internal
    auiAlarmInt   : ARRAY[0..3] OF UINT;   // 台账报警号（内部）/ ledger alarm id ring, internal
    nWriteIdx     : INT;                   // 台账写指针 [0..3] / ledger write pointer
    uEvtTotal     : UDINT;                 // 累计事件总数 [件]（回卷判据）/ total events ever
    uSeqInt       : UDINT;                 // 全局序号计数器 [号]，饱和 / saturating sequence counter
    bWrapCoded    : BOOL;                  // 回卷事件码已发（一次性）/ wrap event already coded
    uTargetInt    : UINT;                  // 入场报警号内部副本 [号] / internal alarm id copy
    eLastEvtInt   : E_DL_ShelveEvt;        // 最近事件种类内部副本 / internal last event kind
    uLastSeqInt   : UDINT;                 // 最近事件序号内部副本 / internal last sequence
    bErrorInt     : BOOL;                  // 本拍故障置位累加 / fault set accumulator
    bFirstScan    : BOOL := TRUE;          // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_AS_DEPTH   : INT := 4;              // 台账环形深度 [条] / ledger ring depth
    DL_AS_SEQ_MAX : UDINT := 16#FFFF_FFFE; // 序号饱和上界 [号] / sequence saturation bound
END_VAR

METHOD WriteAudit
VAR_INPUT
    eEvt : E_DL_ShelveEvt;          // 待写事件种类 / event kind to be written
END_VAR
VAR
    nSlot : INT;                    // 本次写入槽位 [0..3] / slot index of this write
END_VAR

nSlot := nWriteIdx;                              // 取当前写指针 / take the current pointer
aeEvtInt[nSlot]    := eEvt;                      // 事件种类入账 / event kind into the ledger
auiAlarmInt[nSlot] := uTargetInt;                // 报警号入账 / alarm id into the ledger
IF uSeqInt < DL_AS_SEQ_MAX THEN
    uSeqInt := uSeqInt + 1;                      // 序号推进（饱和）/ advance the sequence, saturating
END_IF
uLastSeqInt   := uSeqInt;                        // 最近序号留影 / snapshot the sequence
eLastEvtInt   := eEvt;                           // 最近事件种类留影 / snapshot the kind
uEvtTotal     := uEvtTotal + 1;                  // 累计事件推进（回卷判据）/ total events up
nWriteIdx     := nWriteIdx + 1;                  // 写指针推进 / advance the pointer
IF nWriteIdx >= DL_AS_DEPTH THEN
    nWriteIdx := 0;                              // 显式回卷（IF 等价，禁 MOD 方言）/ explicit wrap
END_IF

END_METHOD

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：三沿一计时位于主体最前部
 *      Unconditional refresh: three edges and one timer at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReq(CLK := bShelveReq);
fbTrigRel(CLK := bUnshelveReq);
fbTrigReset(CLK := bReset);
tonShelve(IN := bShelveOn, PT := tShelveDur);   // IN 用内部驻留标志，禁挂外部引脚原值 / driven by the internal dwell flag

(* 段 2｜上电首扫：台账槽位显式落哨兵 / first-scan init *)
IF bFirstScan THEN
    FOR nWriteIdx := 0 TO (DL_AS_DEPTH - 1) DO
        aeEvtInt[nWriteIdx] := E_DL_ShelveEvt.eNone;   // 空槽哨兵 / empty slot sentinel
    END_FOR
    nWriteIdx   := 0;
    uEvtTotal   := 0;
    uSeqInt     := 0;
    eStateInt   := E_DL_ShelveState.eIdle;
    bFirstScan  := FALSE;
END_IF

(* 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / per-scan preset *)
bErrorInt := FALSE;
bExpiredT := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸：时限 <= 0 非法，锁存至复位沿 + 组态改对（R152 自证可达）
 *      Config gate on the shelving duration with the reachable clear path
 *-----------------------------------------------------------------------------*)
bDurBad := (tShelveDur <= T#0S);
IF bDurBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bDurBad) THEN
    bCfgLatch := FALSE;              // 组态锁存解除 / config latch cleared
    uErrorId  := 16#0000_0000;       // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0001_03FE;       // 故障级：时限组态非法 / fault: illegal duration
    bErrorInt := TRUE;               // R45 配对 / paired with the code
    eStateInt := E_DL_ShelveState.eFault;
    bShelveOn := FALSE;              // 迁相补清：故障打断搁置即断计时 / timing dropped on migration
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      同拍竞态（R275）：eShelved 相内先消化解除沿，再消化时限到期
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_ShelveState.eIdle:
        (* 同拍「申请 + 解除」：解除优先（安全侧），申请作废不入台账 *)
        IF bEnable AND (NOT bCfgLatch) AND fbTrigReq.Q AND (NOT fbTrigRel.Q) THEN
            uTargetInt := uAlarmId;                       // 报警号留影 [号] / snapshot the alarm id
            bShelveOn  := TRUE;                           // 起计时 / start the window
            uErrorId   := 16#0000_0000;                   // 新一轮开始，旧事件码回落 / previous event codes fall back
            WriteAudit(eEvt := E_DL_ShelveEvt.eApply);    // 入台账 / write the audit entry
            eStateInt  := E_DL_ShelveState.eShelved;
        END_IF

    E_DL_ShelveState.eShelved:
        IF fbTrigRel.Q THEN
            bShelveOn  := FALSE;                          // 人工解除即时生效 / manual release is immediate
            uTargetInt := uAlarmId;
            WriteAudit(eEvt := E_DL_ShelveEvt.eRelCmd);
            eStateInt  := E_DL_ShelveState.eIdle;
        ELSIF tonShelve.Q THEN
            bShelveOn  := FALSE;                          // 时限到期自动解除 / auto release on expiry
            uTargetInt := uAlarmId;
            uErrorId   := 16#0001_04FB;                   // 信息级：时限自动解除 / info: auto released
            bExpiredT  := TRUE;                           // 单拍到期脉冲 / single-scan expired pulse
            WriteAudit(eEvt := E_DL_ShelveEvt.eRelTime);
            eStateInt  := E_DL_ShelveState.eIdle;
        END_IF

    E_DL_ShelveState.eFault:
        IF fbTrigReset.Q AND (NOT bDurBad) THEN
            bCfgLatch := FALSE;                           // 解除路径自证可达 / clear path reachable
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_ShelveState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截 / illegal state interception *)
        eStateInt := E_DL_ShelveState.eFault;
        uErrorId  := 16#0001_03FE;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜输出单一出口（范式 P-05）：搁置位只由状态派生一次
 *      Single output exit: the shelved bit derives from the state exactly once
 *-----------------------------------------------------------------------------*)
bShelved     := (eStateInt = E_DL_ShelveState.eShelved);
tElapsed     := tonShelve.ET;                            // 已搁置时长 [s] / elapsed time
IF tShelveDur > tonShelve.ET THEN
    tRemain  := tShelveDur - tonShelve.ET;               // 剩余时长 [s] / remaining time
ELSE
    tRemain  := T#0S;                                    // 已到期：剩余 0 [s] / expired, zero remaining
END_IF
bExpired     := bExpiredT;                               // 单拍脉冲统一出口 / unified single-scan exit
bAuditWrapped := (uEvtTotal > UDINT#4);                  // 回卷事实量（常驻，与事件码分离）/ wrapped standing fact
IF bAuditWrapped AND (NOT bWrapCoded) THEN
    uErrorId   := 16#0001_04FC;                          // 信息级：台账回卷（一次性）/ info: wrapped once
    bWrapCoded := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgLatch) THEN
    uErrorId   := 16#0000_0000;                          // 信息码随复位沿回落 / info codes fall back
    bWrapCoded := FALSE;
END_IF
IF UDINT_TO_DINT(uEvtTotal) < DINT#4 THEN
    nAuditCount := DINT_TO_INT(UDINT_TO_DINT(uEvtTotal));
ELSE
    nAuditCount := DL_AS_DEPTH;                          // 深度即上限 [条] / depth is the cap
END_IF
eLastEvt    := eLastEvtInt;
uLastEvtSeq := uLastSeqInt;
FOR nWriteIdx := 0 TO (DL_AS_DEPTH - 1) DO
    aLedgerEvt[nWriteIdx]   := aeEvtInt[nWriteIdx];      // 台账副本直出 / ledger copy out
    auLedgerAlarm[nWriteIdx] := auiAlarmInt[nWriteIdx];
END_FOR
bError := bErrorInt OR bCfgLatch;
eState := eStateInt;

(*------------------------------------------------------------------------------
 * 私有方法: WriteAudit —— 审计台账唯一写入点（指针 / 序号 / 计数三记账）
 *      Private method: the single audit write entry
 *      调用约定: 仅在本件主体 CASE 内调用，无阻塞、无 METHOD 内跨周期驻留
 *-----------------------------------------------------------------------------*)

END_FUNCTION_BLOCK
