(*==============================================================================
 * 组件名称 (Component)  : FB_DL_InterlockMatrix
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / SHR / SHL），零厂商方言
 * 功能描述 (Function)   : 16 路安全联锁条件的汇总与首因（首出）追踪。
 *                         全部停机级条件满足才给出唯一一个运行许可位 bPermitToRun；
 *                         条件失效的瞬间锁存"第一个失效的通道号 + 完整位图 + 全局序号"，
 *                         复位后若条件仍未恢复，复位挂起而不清锁存。
 *                         解决两类现场顽疾：①停机后十条联锁同时报，维修工不知道先查哪条；
 *                         ②复位键一按就放行，根因被掩盖，第二天同一故障再来一次。
 *                         本块只回答"能不能开机"，"先看哪条报警"由报警管理组件负责。
 *
 * 【取反掩码真值表 / Invert-mask truth table（边界 B7）】
 *   raw  invert  →  有效值   现场含义
 *    0     0     →   0       常开触点未动作，条件不满足
 *    1     0     →   1       常开触点动作，条件满足
 *    0     1     →   1       常闭触点未断开（如未拍下的急停），条件满足
 *    1     1     →   0       常闭触点已断开（急停被拍下），条件不满足
 *   结论：常闭接线的急停、安全门、油压过低开关，必须把对应 invert 位置 1。
 *
 * 【失真与语义披露 / Distortion disclosure】
 *   1) 首因只在"停机级位图由 0 变非 0"的那一拍捕获。若两路在同一扫描周期内失效，
 *      扫描粒度内无法排序，此时取最低索引为代表值、置 bFirstOutSimult，并锁存整张位图；
 *      严禁在 HMI 上编造"谁先谁后"。
 *   2) 提示级失效不参与首因、不阻断许可，避免"料仓低"把停机首因挤掉。
 *   3) 上电首扫即锁存（不等沿）：冷启动时的首因可能只是"本来就断着"的条件，
 *      不代表本次停机原因，bLatchedAtStartup 用于区分这两种情形。
 *
 * 开源溯源 (Origin)     : 原创实现（参考 ISA-18.2 的首出方法论与西门子 LGF 位逻辑功能组的
 *                         参数分类，clean-room 编写，未复制任何源码）
 * 本文件内含       : TYPE  E_DL_InterlockState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_InterlockMatrix
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG / SHR / SHL
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（位操作一律 SHR/SHL + AND/OR，无位访问方言）
 *                         R4 ✓ 配置非法即禁放行 + 复位挂起 + 序号饱和 + 索引钳位
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 边沿实例主体最前部无条件刷新（本块仅一个实例）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *   2026-11-16  v1.0.1  R13 机检 R39 修复：段 8 未使能覆盖原先把 eStateInt 无条件
 *                       改写为 eDisabled，而 eLatched / eFault 两态的复位沿消化
 *                       位于其后段 9 的 CASE 分支内——禁用期间按下的复位沿被整拍
 *                       吞掉，首因锁存与配置故障均需二次复位才清除。改为两个持有
 *                       复位沿的状态不被禁用覆盖，其余态行为不变
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_InterlockState（归属 DL_Base，与 FB_DL_InterlockMatrix 同文件）
 * 含义: 联锁矩阵主状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_InterlockState :
(
    eDisabled  := 0,     // 未使能：许可强制 FALSE，锁存内容保持 / Disabled, permit forced FALSE, latches kept
    eBlocked   := 10,    // 条件不满足：许可 FALSE，等待恢复 / Blocked, waiting for the conditions
    ePermitted := 20,    // 全部停机级条件满足，许可 TRUE / Permitted, all trip-class conditions OK
    eLatched   := 30,    // 首因已锁存，等待复位 / First-out latched, waiting for reset
    eFault     := 99     // 配置非法：无任何停机级通道，需改配置后复位 / Invalid configuration
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_InterlockMatrix
 * 调用约定: 每个扫描周期无条件调用一次；abConditionOk 必须每拍整体刷新。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多机组并行实例化。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_InterlockMatrix
VAR_INPUT
    abConditionOk : ARRAY[0..15] OF BOOL;     // 16 路原始条件，TRUE = 满足（上限 16 路）/ Raw conditions, TRUE = OK, max 16
    auInvertMask  : WORD := 16#0000;          // 取反掩码，bit=1 表示该路原始信号需取反 / Invert mask, bit=1 inverts that channel
    auTripMask    : WORD := 16#FFFF;          // 停机级掩码，bit=1 = 停机级，bit=0 = 提示级 / Trip-class mask, bit=1 is trip class
    bEnable       : BOOL := TRUE;             // 使能，FALSE 时许可 FALSE 且不清锁存 / Enable, FALSE forces permit down but keeps latches
    bReset        : BOOL;                     // 上升沿：清除首因锁存（条件未恢复则挂起）/ Rising edge: clear the first-out latch
END_VAR
VAR_OUTPUT
    bPermitToRun      : BOOL;                 // 运行许可（唯一放行信号）/ Run permit, the only release signal
    bFirstOutValid    : BOOL;                 // 首因有效 / First-out valid
    nFirstOutIndex    : INT;                  // 首因通道号 0..15，-1 = 无 / First-out channel 0..15, -1 = none
    uFirstOutMask     : WORD;                 // 首因位图（同拍多点时多 bit）/ First-out bitmap, multi-bit on simultaneous trips
    uFirstOutSeq      : UDINT;                // 首因发生的全局序号（单调递增）/ First-out global sequence, monotonic
    bFirstOutSimult   : BOOL;                 // 首因为同拍多点失效，扫描粒度内不可排序 / Simultaneous first-out, unorderable
    bLatchedAtStartup : BOOL;                 // 首因发生在上电首扫（冷启动即不满足）/ Latched during the first scan
    uTripActiveMask   : WORD;                 // 当前失效的停机级通道位图 / Currently failed trip channels
    uWarnActiveMask   : WORD;                 // 当前失效的提示级通道位图 / Currently failed warning channels
    bResetPending     : BOOL;                 // 复位挂起：已按复位但条件未恢复 / Reset pending, conditions not restored
    bError            : BOOL;                 // 故障标志（配置类锁存）/ Fault flag, configuration fault latched
    uErrorId          : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = no error
    eState            : E_DL_InterlockState;  // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿检测实例 / Reset rising edge detector
    auEffOk         : ARRAY[0..15] OF BOOL;   // 取反后的有效条件（上限 16 路）/ Effective conditions after inversion, max 16
    uTripNow        : WORD;                   // 本拍失效的停机级位图 / Failed trip channels this scan
    uWarnNow        : WORD;                   // 本拍失效的提示级位图 / Failed warning channels this scan
    uPrevTripNow    : WORD;                   // 上一拍失效的停机级位图（判沿用）/ Previous trip bitmap, for edge detection
    uLatchMask      : WORD;                   // 锁存的首因位图 / Latched first-out bitmap
    uFirstOutSeqInt : UDINT;                  // 首因序号的内部副本 / Internal copy of the first-out sequence
    uBitMask        : WORD;                   // 单通道取位探针 / Single-channel bit probe
    nLatchIdx       : INT;                    // 锁存的首因通道号，-1 = 无 / Latched first-out index, -1 = none
    nNewLowest      : INT;                    // 本拍首个失效通道（最低索引）/ Lowest failed index this scan
    nBitCount       : INT;                    // 本拍失效通道总数 / Number of failed channels this scan
    nIdx            : INT;                    // 通道遍历索引 / Channel loop index
    uSeqCounter     : UDINT;                  // 全局序号计数器 / Global sequence counter
    eStateInt       : E_DL_InterlockState;    // 主状态机内部当前态 / Internal state of the main state machine
    bInv            : BOOL;                   // 该通道是否取反 / Whether this channel is inverted
    bConfigInvalid  : BOOL;                   // 本拍配置是否非法（无停机级通道）/ Configuration invalid this scan
    bConfigLatch    : BOOL;                   // 配置故障锁存 / Configuration fault latched
    bNewEvent       : BOOL;                   // 本拍出现新的停机级失效事件 / A new trip event started this scan
    bStartupScan    : BOOL := TRUE;           // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_ILK_CHANNELS : INT  := 16;             // 通道数，必须等于数组维度 / Channel count, must match the array dimension
    DL_ILK_IDX_NONE : INT  := -1;             // 无效通道号哨兵 / No-channel sentinel
    DL_ILK_BIT0     : WORD := 16#0001;        // 最低位掩码 / Least significant bit mask
    DL_ILK_SEQ_MAX  : UDINT := 16#FFFF_FFFE;  // 序号饱和值 / Sequence saturation value
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）
 *      Unconditional refresh zone, placed at the very top of the body
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫（边界 B2）：索引与位图必须显式置为哨兵值，不能依赖默认零
 *      First-scan init: the index must be forced to the sentinel, never left at zero
 *      0 号通道是合法的首因值，用 0 当"无首因"会让 HMI 永远显示 CH0 故障
 *-----------------------------------------------------------------------------*)
IF bStartupScan THEN
    nLatchIdx    := DL_ILK_IDX_NONE;
    uLatchMask   := 16#0000;
    uPrevTripNow := 16#0000;
    uSeqCounter  := 0;
    eStateInt    := E_DL_InterlockState.eBlocked;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜有效条件求值（边界 B7）：有效 = 原始 XOR 取反位
 *      Effective value = raw XOR invert, one pass over the 16 channels
 *      真值表见文件头；常闭接线的急停必须置 invert 位，否则"拍下急停"会被判为满足
 *      Normally-closed devices must set the invert bit, otherwise pressing the e-stop
 *      would read as a satisfied condition
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_ILK_CHANNELS - 1) DO
    uBitMask      := SHR(auInvertMask, nIdx) AND DL_ILK_BIT0;
    bInv          := (uBitMask <> 16#0000);
    auEffOk[nIdx] := abConditionOk[nIdx] XOR bInv;
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜分类汇总（边界 B6）：停机级进 uTripNow，提示级进 uWarnNow
 *      Classification: trip-class feeds the bitmap, warning-class only reports
 *      位操作一律 SHR/SHL 取位置位，禁止位访问方言，保证三平台同码
 *-----------------------------------------------------------------------------*)
uTripNow := 16#0000;
uWarnNow := 16#0000;

FOR nIdx := 0 TO (DL_ILK_CHANNELS - 1) DO
    IF NOT auEffOk[nIdx] THEN
        uBitMask := SHR(auTripMask, nIdx) AND DL_ILK_BIT0;
        IF uBitMask <> 16#0000 THEN
            uTripNow := uTripNow OR SHL(DL_ILK_BIT0, nIdx);
        ELSE
            uWarnNow := uWarnNow OR SHL(DL_ILK_BIT0, nIdx);
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 5｜首因定位（边界 B3/B4）：求最低索引与失效总数
 *      First-out localisation: find the lowest failed index and the failed count
 *      同拍多路失效时无法排序，只能给代表值与位图，绝不编造先后
 *-----------------------------------------------------------------------------*)
nNewLowest := DL_ILK_IDX_NONE;
nBitCount  := 0;

FOR nIdx := 0 TO (DL_ILK_CHANNELS - 1) DO
    uBitMask := SHR(uTripNow, nIdx) AND DL_ILK_BIT0;
    IF uBitMask <> 16#0000 THEN
        nBitCount := nBitCount + 1;
        IF nNewLowest < 0 THEN
            nNewLowest := nIdx;
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 6｜首因捕获：上电首扫特殊处理（边界 B2），其余按 0→非 0 的沿捕获
 *      First-out capture: special case on the first scan, edge-triggered afterwards
 *      锁存后不再被新故障覆盖——首因就是首因，覆盖等于把根因洗掉
 *      Once latched the value is never overwritten: the first cause stays the first cause
 *      首扫时 uPrevTripNow 已被置 0，因此"上电本来就不满足"同样走这条沿路径，
 *      只是序号从 1 开始并被标记为 bLatchedAtStartup
 *-----------------------------------------------------------------------------*)
bNewEvent := FALSE;

IF (uTripNow <> 16#0000) AND (uPrevTripNow = 16#0000) THEN
    bNewEvent := TRUE;
END_IF

IF bNewEvent THEN

    IF uSeqCounter < DL_ILK_SEQ_MAX THEN
        uSeqCounter := uSeqCounter + 1;
    ELSE
        uErrorId := 16#0001_0007;
    END_IF

    IF nLatchIdx < 0 THEN
        nLatchIdx         := nNewLowest;
        uLatchMask        := uTripNow;
        uFirstOutSeqInt   := uSeqCounter;
        bFirstOutSimult   := (nBitCount > 1);
        bLatchedAtStartup := bStartupScan;
    END_IF

END_IF

uPrevTripNow := uTripNow;

(*------------------------------------------------------------------------------
 * 段 7｜配置校验（边界 B1，fail-safe 第一原则）
 *      Configuration check: no trip-class channel means the permit can never be gated
 *      无任何停机级通道时若默认放行，等于把"没配置"当成"全部满足"，这是最危险的缺省
 *      Defaulting to permit when nothing is configured is the most dangerous default
 *-----------------------------------------------------------------------------*)
bConfigInvalid := (auTripMask = 16#0000);

IF bConfigInvalid THEN
    bConfigLatch := TRUE;
END_IF

IF bConfigLatch THEN
    uErrorId  := 16#0002_0004;
    eStateInt := E_DL_InterlockState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜未使能处理：许可撤销、锁存保持（使能不是复位）
 *      Disabled: the permit drops but the latches survive, enabling is not resetting
 *      R39 纪律：复位沿只在发生的那一拍为真，其消化权归段 9 的 eLatched 与 eFault
 *      两个分支所有。本段若无条件把状态改写成 eDisabled，则禁用期间按下的复位沿
 *      在本拍即被抹掉（段 9 走 eDisabled 分支，两处复位判据都摸不到该沿），首因
 *      锁存与配置故障只能靠操作员补按第二次复位——故这两态不参与禁用覆盖。
 *      R39: the reset edge lives for exactly one scan and is consumed inside the CASE
 *      branches of eLatched and eFault, so the disable override must leave both
 *      states untouched; otherwise a reset pressed while disabled is lost and the
 *      first-out latch needs a second press. The other states keep the old behaviour.
 *-----------------------------------------------------------------------------*)
IF (eStateInt <> E_DL_InterlockState.eLatched)
AND (eStateInt <> E_DL_InterlockState.eFault)
AND (NOT bEnable) THEN
    eStateInt := E_DL_InterlockState.eDisabled;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_InterlockState.eDisabled:
        IF bEnable THEN
            IF bConfigLatch THEN
                eStateInt := E_DL_InterlockState.eFault;
            ELSE
                eStateInt := E_DL_InterlockState.eBlocked;
            END_IF
        END_IF

    E_DL_InterlockState.eBlocked:
        IF uTripNow <> 16#0000 THEN
            eStateInt := E_DL_InterlockState.eLatched;
        ELSE
            eStateInt := E_DL_InterlockState.ePermitted;
        END_IF

    E_DL_InterlockState.ePermitted:
        (* 任一停机级失效立即降级，许可在同一拍撤销（状态即许可） *)
        (* Any trip-class failure demotes at once, the permit drops in the same scan *)
        IF uTripNow <> 16#0000 THEN
            eStateInt := E_DL_InterlockState.eLatched;
        END_IF

    E_DL_InterlockState.eLatched:
        (* 边界 B5：条件未恢复时复位只挂起、不清锁存 *)
        (* Reset only pends while a trip condition is still present *)
        IF fbTrigReset.Q THEN
            IF uTripNow = 16#0000 THEN
                nLatchIdx         := DL_ILK_IDX_NONE;
                uLatchMask        := 16#0000;
                uFirstOutSeqInt   := 0;
                bFirstOutSimult   := FALSE;
                bLatchedAtStartup := FALSE;
                bResetPending     := FALSE;
                eStateInt         := E_DL_InterlockState.eBlocked;
            ELSE
                bResetPending := TRUE;
            END_IF
        END_IF

    E_DL_InterlockState.eFault:
        (* 配置故障：必须先把停机级掩码改对，再按复位退出 *)
        (* Configuration fault: fix the trip mask first, then reset *)
        IF fbTrigReset.Q AND (NOT bConfigInvalid) THEN
            bConfigLatch := FALSE;
            uErrorId     := 16#0000_0000;
            eStateInt    := E_DL_InterlockState.eBlocked;
        END_IF

    ELSE
        (* 非法状态拦截：不做隐式恢复，直接锁存上报 *)
        (* Illegal state interception: no implicit recovery, latch and report *)
        eStateInt := E_DL_InterlockState.eFault;
        uErrorId  := 16#0001_0005;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 10｜输出单一出口（范式 P-05）
 *      Single output exit: the permit derives from the state exactly once
 *      分支内只改状态，许可位只在此处派生，"多处置位、漏撤一处"从结构上不可能
 *-----------------------------------------------------------------------------*)
bPermitToRun      := (eStateInt = E_DL_InterlockState.ePermitted) AND bEnable AND (NOT bConfigLatch);
bFirstOutValid    := (nLatchIdx >= 0);
nFirstOutIndex    := nLatchIdx;
uFirstOutMask     := uLatchMask;
uFirstOutSeq      := uFirstOutSeqInt;
uTripActiveMask   := uTripNow;
uWarnActiveMask   := uWarnNow;
bError            := (eStateInt = E_DL_InterlockState.eFault) OR bConfigLatch;
eState            := eStateInt;

(* 首扫标志在主体末尾撤销：段 6 需要它区分"冷启动即不满足"与"运行中失效" *)
(* The first-scan flag is cleared only here, stage 6 needs it for the cold-start case *)
bStartupScan := FALSE;
END_FUNCTION_BLOCK
