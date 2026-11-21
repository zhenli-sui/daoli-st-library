(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TwoHandSafety
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 功能描述 (Function)   : 双手安全启动按钮的同步性校验与防旁路状态机。
 *                         左/右两只手按钮必须在同步窗（默认 500 ms）内先后按下才给出安全
 *                         输出；一个循环结束后必须两只手都释放才允许下一次启动；任一侧按钮
 *                         被胶带缠住、被工件压住或人为短接时，持续按下超过卡死判定时间即
 *                         升级为"旁路嫌疑"并锁存故障。典型场景是压力机、压装机、封口机——
 *                         "一只手按着启动、另一只手伸进模具"这类致死事故的全部防线。
 *                         输出侧只给一个安全位，其余全部是诊断位，避免上位机二次组合逻辑。
 *
 * 【合规披露 / Compliance disclosure（本段不得删改）】
 *   本块是标准 PLC 上的逻辑结构实现，不是安全认证功能块。ISO 13851:2019 Type IIIC
 *   要求的安全功能必须由安全继电器或安全 PLC 的安全程序承担；标准 PLC 的普通输出存在
 *   短路失效后静默失效的风险，不得作为唯一安全措施。本块的定位是：
 *   ① 在安全 PLC 中作为经过安全论证的逻辑骨架；
 *   ② 在标准 PLC 上作为非安全的工艺互锁与诊断辅助。
 *
 * 【失真披露 / Distortion disclosure】
 *   1) 输入刻意不做防抖：防抖会引入额外延时并蚕食同步窗余量，调用方必须前置
 *      FB_DL_SignalDebounce，且防抖时间计入同步窗，属串联关系而非替代关系。
 *   2) 时间判定一律用定时器 Q，不用"当前时刻减去按下时刻"，规避各平台 TIME 减法差异。
 *   3) 卡死判定跨状态持续计时：卡死按钮通常先以同步超时（0002_0001）或释放不同步
 *      （0002_0002）的面貌出现，持续计时到卡死时限后把故障码升级为 0002_0003 并置
 *      bLeftStuck/bRightStuck，HMI 才能区分"操作不规范"与"按钮被短接"。
 *
 * 开源溯源 (Origin)     : 原创实现（参考 IEC 60204-1 与 ISO 13851:2019 Type IIIC 的功能分类
 *                         与参数域，clean-room 编写，未复制任何源码）
 * 本文件内含       : TYPE  E_DL_TwoHandState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_TwoHandSafety
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无指针、无厂商私有符号）
 *                         R4 ✓ 参数钳位 + 上电锁 + 计数饱和 + 复位前提校验
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 五个实例（一沿 + 四计时）主体最前部无条件刷新（本组件核心考点）
 *
 * 【取反掩码式真值约定（边界 B10）】
 *   本块接收的是"已判定为按下"的布尔量（TRUE = 按下）。现场常闭接线的按钮由调用方在
 *   硬件抽象层取反，本块不接触任何物理电平约定。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TwoHandState（归属 DL_Base，与 FB_DL_TwoHandSafety 同文件）
 * 含义: 双手安全主状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TwoHandState :
(
    eIdle        := 0,     // 待机：双手均未按下，等待首次按下 / Idle, both released
    eWaitSecond  := 10,    // 已按下单手，等待另一手在同步窗内按下 / One pressed, waiting for the second
    eBothPressed := 20,    // 双手同步按下，安全输出有效 / Both pressed synchronously, output valid
    eWaitRelease := 30,    // 已释放一手，等待另一手在释放窗内释放 / One released, waiting for the other
    eFault       := 99     // 故障锁存，仅复位沿且双手已释放可解除 / Fault latched, reset requires both released
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_TwoHandSafety
 * 调用约定: 每个扫描周期无条件调用一次，禁止放在 IF 分支内调用。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多工位并行实例化。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TwoHandSafety
VAR_INPUT
    bLeftPressed   : BOOL;                    // 左按钮，TRUE = 按下（调用方已完成常闭取反）/ Left pressed, TRUE = pressed
    bRightPressed  : BOOL;                    // 右按钮，TRUE = 按下（调用方已完成常闭取反）/ Right pressed, TRUE = pressed
    bEnable        : BOOL := TRUE;            // 使能，FALSE 时输出立即复位且状态回待机 / Enable, FALSE drops the output and resets to idle
    tSyncWindow    : TIME := T#500MS;         // 双手同步窗 [ms]，合法域 T#0MS~500MS / Sync window [ms], valid 0..500 ms
    tReleaseWindow : TIME := T#100MS;         // 双手释放差允许窗 [ms]，合法域 T#0MS~500MS / Release difference window [ms]
    tStuckTime     : TIME := T#5S;            // 单侧持续按下判卡死时间 [s]，下限 1 s / Single-side stuck detection time [s], min 1 s
    bReset         : BOOL;                    // 上升沿：故障复位（须双手已释放）/ Rising edge: fault reset, requires both released
END_VAR
VAR_OUTPUT
    bSafeOutput    : BOOL;                    // 安全输出，仅双手同步按下期间为 TRUE / Safe output, TRUE only while both held synchronously
    bBothPressed   : BOOL;                    // 双手同时按下（无同步含义）/ Both pressed, no synchronism implied
    bSynced        : BOOL;                    // 本次启动满足同步窗 / This actuation was synchronous
    bArmed         : BOOL;                    // 已武装：自上次全部释放后尚未启动过 / Armed, no cycle since the last full release
    bLeftStuck     : BOOL;                    // 左按钮卡死嫌疑（锁存至复位）/ Left button stuck, latched until reset
    bRightStuck    : BOOL;                    // 右按钮卡死嫌疑（锁存至复位）/ Right button stuck, latched until reset
    bError         : BOOL;                    // 故障标志（锁存）/ Fault flag, latched
    uErrorId       : UDINT;                   // 故障码，0 = 无故障 / Error code, 0 = no error
    uCycleCount    : UDINT;                   // 成功完成的双手循环数（饱和）/ Completed cycles, saturating
    uAbortCount    : UDINT;                   // 同步窗前主动放弃的累计次数（饱和）/ Aborted attempts, saturating
    eState         : E_DL_TwoHandState;       // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset    : R_TRIG;                  // 复位上升沿检测实例 / Reset rising edge detector
    fbTonSync      : TON;                     // 同步窗计时（单手按下期间运行）/ Sync-window timer, runs while one hand is held
    fbTonRelease   : TON;                     // 释放窗计时（另一手仍按下期间运行）/ Release-window timer, runs while the other hand stays held
    fbTonStuckL    : TON;                     // 左侧卡死计时 / Left stuck timer
    fbTonStuckR    : TON;                     // 右侧卡死计时 / Right stuck timer
    eStateInt      : E_DL_TwoHandState;       // 主状态机内部当前态 / Internal state of the main state machine
    bSyncOkLatch   : BOOL;                    // 本次启动已通过同步判定的锁存 / Latch: this actuation passed the synchronism test
    bArmLatch      : BOOL;                    // 武装标志锁存（上电必须为 FALSE）/ Armed latch, must be FALSE at power-up
    bFirstLeft     : BOOL;                    // TRUE = 本次先按下的是左手 / TRUE = the left button was pressed first
    bLeftOnly      : BOOL;                    // 仅左手按下（卡死计时的输入条件）/ Left only, the stuck-timer input condition
    bRightOnly     : BOOL;                    // 仅右手按下（卡死计时的输入条件）/ Right only, the stuck-timer input condition
    bCountCycle    : BOOL;                    // 本拍请求累加循环计数 / Cycle counter increment requested this scan
    bCountAbort    : BOOL;                    // 本拍请求累加放弃计数 / Abort counter increment requested this scan
    bCntWarned     : BOOL;                    // 计数饱和告警已发过一次 / Saturation warning already raised once
    bSkipSm        : BOOL;                    // 本拍跳过主状态机（未使能）/ Skip the state machine this scan, not enabled
    uWarnId        : UDINT;                   // 本拍瞬时告警码（参数钳位用）/ Instantaneous warning code of this scan
    bFirstScan     : BOOL := TRUE;            // 上电首扫标志 / First-scan flag
    tSyncEff       : TIME;                    // 钳位后的同步窗 [ms] / Clamped sync window [ms]
    tReleaseEff    : TIME;                    // 钳位后的释放窗 [ms] / Clamped release window [ms]
    tStuckEff      : TIME;                    // 钳位后的卡死判定时间 [ms] / Clamped stuck detection time [ms]
END_VAR
VAR CONSTANT
    DL_TH_SYNC_MAX  : TIME := T#500MS;        // 同步窗硬上限，禁止向上放宽 / Hard sync-window limit, never widened
    DL_TH_REL_MAX   : TIME := T#500MS;        // 释放窗硬上限 / Hard release-window limit
    DL_TH_STUCK_MIN : TIME := T#1S;           // 卡死判定时间下限，防正常点动误报 / Stuck-time lower bound, avoids false trips
    DL_TH_STUCK_MAX : TIME := T#1H;           // 卡死判定时间上限，防参数笔误 / Stuck-time upper bound, guards against typos
    DL_TH_CNT_MAX   : UDINT := 16#FFFF_FFFE;  // 计数器饱和值 / Counter saturation value
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7 / 边界 B9）
 *      Unconditional refresh zone, placed at the very top of the body
 *      五个定时器的 IN 先由"状态 + 使能 + 输入组合"推导成 BOOL，实例调用本身无条件；
 *      状态取自上一拍末尾，滞后一拍是定时器语义的正常代价，换来的是永不停更
 *      IN is derived first from state and inputs; the instance call itself never sits in an IF
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

bLeftOnly  := bLeftPressed AND (NOT bRightPressed);
bRightOnly := bRightPressed AND (NOT bLeftPressed);

fbTonSync(IN := bEnable AND (eStateInt = E_DL_TwoHandState.eWaitSecond), PT := tSyncEff);
fbTonRelease(IN := bEnable AND (eStateInt = E_DL_TwoHandState.eWaitRelease), PT := tReleaseEff);
fbTonStuckL(IN := bEnable AND bLeftOnly, PT := tStuckEff);
fbTonStuckR(IN := bEnable AND bRightOnly, PT := tStuckEff);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫（边界 B1 的第一道防线）
 *      First-scan init: the arming latch must be FALSE, never rely on the default value
 *      上电时双手可能已被压住或短接，若武装位默认为 TRUE，第一拍就会放行
 *      A default-TRUE arming latch would release the machine on the very first scan
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    bFirstScan   := FALSE;
    eStateInt    := E_DL_TwoHandState.eIdle;
    bArmLatch    := FALSE;
    bSyncOkLatch := FALSE;
    bLeftStuck   := FALSE;
    bRightStuck  := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜时间参数钳位（边界 B3/B4/B5）
 *      Parameter clamping: widening the window means weakening safety, so clamp downwards only
 *      放宽同步窗等于放宽安全，因此越上限只向下钳位并告警；下限方向同理
 *-----------------------------------------------------------------------------*)
tSyncEff    := tSyncWindow;
tReleaseEff := tReleaseWindow;
tStuckEff   := tStuckTime;
uWarnId     := 16#0000;

IF tSyncEff > DL_TH_SYNC_MAX THEN
    tSyncEff  := DL_TH_SYNC_MAX;
    uWarnId   := 16#0001_0001;
END_IF

IF tSyncEff < T#0MS THEN
    tSyncEff  := T#0MS;
    uWarnId   := 16#0001_0001;
END_IF

IF tReleaseEff > DL_TH_REL_MAX THEN
    tReleaseEff := DL_TH_REL_MAX;
    uWarnId     := 16#0001_0001;
END_IF

IF tReleaseEff < T#0MS THEN
    tReleaseEff := T#0MS;
    uWarnId     := 16#0001_0001;
END_IF

IF tStuckEff < DL_TH_STUCK_MIN THEN
    tStuckEff := DL_TH_STUCK_MIN;
    uWarnId   := 16#0001_0001;
END_IF

IF tStuckEff > DL_TH_STUCK_MAX THEN
    tStuckEff := DL_TH_STUCK_MAX;
    uWarnId   := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜故障码口径（红线 R15）
 *      Error-code policy: a latched code survives until the reset path clears it
 *      故障锁存期间必须保留进入故障时的码，否则 HMI 下一拍读回 0，根因丢失；
 *      非故障态下瞬时告警每拍重算，条件消失即归零
 *-----------------------------------------------------------------------------*)
IF eStateInt <> E_DL_TwoHandState.eFault THEN
    IF uWarnId <> 16#0000 THEN
        uErrorId := uWarnId;
    ELSE
        uErrorId := 16#0000_0000;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜未使能处理：输出撤销、状态回待机、清码但不计故障
 *      Disabled: drop the output, return to idle, clear the code without recording a fault
 *      未使能是操作员的主动动作，不是故障；重新使能后仍必须重新武装才可能放行
 *-----------------------------------------------------------------------------*)
bSkipSm := FALSE;

IF NOT bEnable THEN
    eStateInt    := E_DL_TwoHandState.eIdle;
    bArmLatch    := FALSE;
    bSyncOkLatch := FALSE;
    bLeftStuck   := FALSE;
    bRightStuck  := FALSE;
    uErrorId     := 16#0000_0000;
    bSkipSm      := TRUE;
END_IF

IF NOT bSkipSm THEN

    (*--------------------------------------------------------------------------
     * 段 6｜卡死诊断（边界 B6 的对应项）：先于主状态机判定
     *      Stuck diagnosis runs before the state machine
     *      仅单侧持续按下才计时；双手同时按下属正常操作，绝不参与卡死计时
     *      卡死按钮往往先以同步超时码出现，到时后升级为旁路嫌疑码——这是 HMI 区分
     *      "操作不规范"与"按钮被短接"的唯一依据
     *      A stuck button first shows up as a sync timeout; the upgrade to the bypass code
     *      is what lets the HMI tell sloppy operation from a taped-down button
     *-------------------------------------------------------------------------*)
    IF fbTonStuckL.Q OR fbTonStuckR.Q THEN
        bLeftStuck  := bLeftStuck OR fbTonStuckL.Q;
        bRightStuck := bRightStuck OR fbTonStuckR.Q;
        eStateInt   := E_DL_TwoHandState.eFault;
        uErrorId    := 16#0002_0003;
    END_IF

    (*--------------------------------------------------------------------------
     * 段 7｜武装（边界 B1）：只有"待机且双手全释放"才武装
     *      Arming: only idle with both hands released may arm the block
     *      这是"上电时双手已被按下 / 短接"不启动的唯一保证
     *-------------------------------------------------------------------------*)
    IF (eStateInt = E_DL_TwoHandState.eIdle) AND (NOT bLeftPressed) AND (NOT bRightPressed) THEN
        bArmLatch := TRUE;
    END_IF

    bCountCycle := FALSE;
    bCountAbort := FALSE;

    (*--------------------------------------------------------------------------
     * 段 8｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
     *      Main state machine with the mandatory ELSE fallback
     *-------------------------------------------------------------------------*)
    CASE eStateInt OF

        E_DL_TwoHandState.eIdle:
            (* 未武装时的任何按下都被忽略，状态原地不动（边界 B1） *)
            (* Without arming, any press is ignored and the state stays put *)
            IF bArmLatch AND (bLeftPressed OR bRightPressed) THEN
                bSyncOkLatch := FALSE;
                IF bLeftPressed AND bRightPressed THEN
                    (* 边界 B2：同拍按下直接判定同步成功，但仍需武装 *)
                    (* Same-scan press counts as synchronous, arming still required *)
                    bSyncOkLatch := TRUE;
                    bArmLatch    := FALSE;
                    bCountCycle  := TRUE;
                    eStateInt    := E_DL_TwoHandState.eBothPressed;
                ELSE
                    bFirstLeft := bLeftPressed;
                    eStateInt  := E_DL_TwoHandState.eWaitSecond;
                END_IF
            END_IF

        E_DL_TwoHandState.eWaitSecond:
            (* 超时优先判定：定时器 Q 是唯一依据，不做 TIME 减法 *)
            (* Timeout first: the timer Q is the only criterion, no TIME subtraction *)
            IF fbTonSync.Q THEN
                eStateInt := E_DL_TwoHandState.eFault;
                uErrorId  := 16#0002_0001;
            ELSIF bLeftPressed AND bRightPressed THEN
                bSyncOkLatch := TRUE;
                bArmLatch    := FALSE;
                bCountCycle  := TRUE;
                eStateInt    := E_DL_TwoHandState.eBothPressed;
            ELSIF (bFirstLeft AND (NOT bLeftPressed)) OR ((NOT bFirstLeft) AND (NOT bRightPressed)) THEN
                (* 先按的手先松开：本次尝试作废，不计故障但计入放弃次数 *)
                (* The first hand released: the attempt is void, counted as an abort, not a fault *)
                (* 同时撤销武装，必须重新全释放才能再来一次，防止反复空跳 *)
                (* Arming is dropped as well, a full release is required before the next attempt *)
                bArmLatch    := FALSE;
                bSyncOkLatch := FALSE;
                bCountAbort  := TRUE;
                eStateInt    := E_DL_TwoHandState.eIdle;
            END_IF

        E_DL_TwoHandState.eBothPressed:
            (* 任一手释放立即进入释放监视，输出当拍撤销（状态即输出） *)
            (* Any release starts release monitoring; the output drops within the same scan *)
            IF NOT (bLeftPressed AND bRightPressed) THEN
                eStateInt := E_DL_TwoHandState.eWaitRelease;
            END_IF

        E_DL_TwoHandState.eWaitRelease:
            (* 两只手都释放是成功路径，优先于超时判定 *)
            (* Both released is the success path and wins over the timeout *)
            IF (NOT bLeftPressed) AND (NOT bRightPressed) THEN
                eStateInt := E_DL_TwoHandState.eIdle;
                bArmLatch := FALSE;
            ELSIF fbTonRelease.Q THEN
                eStateInt := E_DL_TwoHandState.eFault;
                uErrorId  := 16#0002_0002;
            END_IF

        E_DL_TwoHandState.eFault:
            (* 边界 B6：双手未全释放时复位无效，否则"按住一手 + 复位"即可旁路 *)
            (* Reset is ignored unless both hands are released, otherwise it is a bypass *)
            IF fbTrigReset.Q AND (NOT bLeftPressed) AND (NOT bRightPressed) THEN
                eStateInt    := E_DL_TwoHandState.eIdle;
                uErrorId     := 16#0000_0000;
                bSyncOkLatch := FALSE;
                bArmLatch    := FALSE;
                bLeftStuck   := FALSE;
                bRightStuck  := FALSE;
            END_IF

        ELSE
            (* 非法状态拦截：不做隐式恢复，直接锁存上报 *)
            (* Illegal state interception: no implicit recovery, latch and report *)
            eStateInt := E_DL_TwoHandState.eFault;
            uErrorId  := 16#0001_0005;

    END_CASE;

    (*--------------------------------------------------------------------------
     * 段 9｜计数器累加（边界 B7）：单一累加点 + 饱和不再回绕
     *      Counter accumulation: one single increment point with saturation
     *      回绕会让"运行了 43 亿次"变成"0 次"，保养周期判断随之失效
     *-------------------------------------------------------------------------*)
    IF bCountCycle THEN
        IF uCycleCount < DL_TH_CNT_MAX THEN
            uCycleCount := uCycleCount + 1;
        ELSIF NOT bCntWarned THEN
            uErrorId   := 16#0001_0007;
            bCntWarned := TRUE;
        END_IF
    END_IF

    IF bCountAbort THEN
        IF uAbortCount < DL_TH_CNT_MAX THEN
            uAbortCount := uAbortCount + 1;
        ELSIF NOT bCntWarned THEN
            uErrorId   := 16#0001_0007;
            bCntWarned := TRUE;
        END_IF
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 10｜输出单一出口（边界 B9 / 范式 P-05）
 *      Single output exit: the safe bit is assigned exactly once, here
 *      分支内只改状态，输出全部在末尾由状态派生，杜绝"多处置位、漏撤一处"的经典事故
 *      Branches only move the state; the safe bit derives from the state in one place
 *-----------------------------------------------------------------------------*)
bSafeOutput  := (eStateInt = E_DL_TwoHandState.eBothPressed) AND bEnable;
bBothPressed := bLeftPressed AND bRightPressed;
bSynced      := bSyncOkLatch AND bEnable;
bArmed       := bArmLatch;
bError       := (eStateInt = E_DL_TwoHandState.eFault);
eState       := eStateInt;
END_FUNCTION_BLOCK
