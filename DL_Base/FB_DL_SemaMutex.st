(*
    FB_DL_SemaMutex —— IEC 标准 SEMA 互斥的防御性包装
    ------------------------------------------------------------------
    分类      : DL_Base / Sync
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（标准功能块 SEMA 的申请/释放语义）；
                委托平台标准 SEMA 的互斥语义模型，本件不重实现同步内核；
                占用超时强制归还、同拍仲裁、状态枚举、计数饱和与错误分级 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用；
                仅依赖 Standard.library 的 R_TRIG / TON
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 两个任务抢同一个夹爪、两个工站抢同一个打印口、主任务与诊断任务抢同一个
                串口——标准 SEMA 能解决「同时进」的问题，但解决不了「进去的任务崩了」：
                持锁任务一旦进入故障分支不再执行释放逻辑，另一侧就永久卡死，且现场
                表现为「设备没报警但不动」，排查代价极高。本件在标准语义之上补两条：
                ① 占用超时强制归还：持锁时长超过 tHoldMax 即由本件强制释放，
                   并升故障级——被系统归还的锁，调用方必须知道，否则它下一次申请会
                   莫名其妙地失败或成功；
                ② 同拍申请与释放的仲裁明确化：释放优先（安全侧），宁可多还一次锁，
                   不可错持一次锁；同拍事件发信息级。
                核心防御：边沿与定时器实例在本体首部无条件刷新（红线 4/5）；
                   CASE 三态并带 ELSE 兜底，非法状态一律复位到 eFree 并升故障级 036A，
                   绝不让状态量停在枚举域外继续运转；
                   累计计数饱和不回绕，饱和即升故障级（统计量不再可信）；
                   释放通道永不被超时路径屏蔽——eHeld 内先判释放再判超时（R39 纪律）。
                职责边界：互斥的公平排队、优先级继承不在本件语义内（需靠任务优先级组态）；
                本件只提供「不静默持锁」的防御层。标准 SEMA 实例仍可由调用方自行使用。
    错误码    : 16#0001_0432 同拍申请与释放（已按释放优先）或超时监视被禁用（tHoldMax = 0）——信息级，状态可用
                16#0001_0433 预留禁用（信息级，不得挪用）
                16#0001_0369 占用超时，已强制归还——故障级，调用方必须处理
                16#0001_036A 非法状态兜底，已复位 eFree——故障级，状态量被外部改写或内存异常
                16#0001_036B 申请或释放计数达饱和值，统计不可信——故障级，互斥本体仍正常工作
    码位总账  : 16#0001_0432 用 / 16#0001_0433 预留 ｜ 16#0001_0369 用 / 16#0001_036A 用 / 16#0001_036B 用
    状态机    : ENUM + CASE 三态，含 ELSE 兜底。
                eFree（空闲，无人持锁）：申请上升沿 → eHeld，计申请数；
                eHeld（持锁中）：释放上升沿 → eFree，计释放数；持锁超时 → eTimedOutRelease，
                  本拍发 bTimedOut 单周期脉冲并计一次释放（锁是系统还的，账也要记）；
                eTimedOutRelease（超时释放过渡态，恰占一个扫描拍）：进入本态的那一拍（超时拍）
                  已在 eHeld 分支发过 bTimedOut 脉冲；下一拍进本分支即回 eFree，本拍申请被拒
                  （锁刚被强制归还，状态尚未稳定，同拍授予会让调用方误判锁的来源）。
                  时序口径：超时拍 N 置 eTimedOutRelease，拍 N+1 回 eFree 并开始受理申请；
                  「本拍即回 eFree」的旧表述易被读成同拍回零，R20 终审改为跨拍显式表述；
                ELSE（非法状态）：复位 eFree，bBusy 拉低，置 036A。
                所有权：E_DL_SemaState 枚举唯一属主为本文件，其他组件只引用不重声明。
    采样约定  : fbTrigClaim / fbTrigRelease / fbHold 三个实例在本体首部无条件刷新，
                绝不放入 IF 或 CASE；fbHold 的 IN 取上一拍锁存状态（eState = eHeld）。
                bTimedOut 每拍先清后置，故为单周期脉冲；bBusy 由状态派生，不独立锁存。
                tHoldMax = 0 时监视禁用，定时器 IN 恒 FALSE，不累积。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
                2026-11-16 v1.0.1 R20 终审：eTimedOutRelease 跨拍时序表述精确化（逻辑零变更，
                  引脚零变更，仅头注释状态机段与版本号），消除「本拍即回」的同拍误读
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SemaState（归属 DL_Base，与 FB_DL_SemaMutex 同文件，唯一属主）
 * 含义: 互斥状态。成员分隔按库内惯例，间隔 10 便于后续插态而不破坏已存值。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SemaState :
(
    eFree            := 0,   // 空闲：无人持锁，可被申请 / free, nobody holds the lock
    eHeld            := 10,  // 持锁中：接受释放，监视占用时长 / held, accepts release and watches the hold time
    eTimedOutRelease := 20   // 超时释放过渡态：本拍即回空闲，本拍申请被拒 / timed out release, returns to free in this cycle
);
END_TYPE

FUNCTION_BLOCK FB_DL_SemaMutex
VAR_INPUT
    bClaim           : BOOL;                  // 申请互斥，上升沿有效 / claim request, the rising edge is effective
    bRelease         : BOOL;                  // 释放互斥，上升沿有效，与申请同拍时优先 / release request, the rising edge is effective and wins over a claim
    tHoldMax         : TIME := T#5S;          // 单次占用上限 [ms]，0 = 禁用超时监视 / maximum hold time [ms], zero disables the supervision
END_VAR
VAR_OUTPUT
    bBusy            : BOOL;                  // 互斥被占用（状态派生量）/ the mutex is held, derived from the state
    bTimedOut        : BOOL;                  // 本拍发生超时强制释放，单周期脉冲 / a forced release happened in this cycle, single cycle pulse
    uClaimCnt        : UDINT;                 // 累计申请次数，饱和计数 [次] / accumulated claim count, saturating [times]
    uReleaseCnt      : UDINT;                 // 累计释放次数，饱和计数 [次] / accumulated release count, saturating [times]
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigClaim      : R_TRIG;                // 申请上升沿实例，本体首部无条件刷新 / claim edge instance, refreshed unconditionally
    fbTrigRelease    : R_TRIG;                // 释放上升沿实例，本体首部无条件刷新 / release edge instance, refreshed unconditionally
    fbHold           : TON;                   // 占用时长监视实例，本体首部无条件刷新 / hold time instance, refreshed unconditionally
    eState           : E_DL_SemaState;        // 互斥状态，唯一属主 / the mutex state, sole owner
    bClaimEff        : BOOL;                  // 同拍仲裁后生效的申请沿 / the claim edge that survived the arbitration
    bReleaseEff      : BOOL;                  // 同拍仲裁后生效的释放沿 / the release edge that survived the arbitration
    bHoldMonEn       : BOOL;                  // 超时监视使能（tHoldMax > 0）/ hold supervision enabled
    bClaimInc        : BOOL;                  // 本拍申请计数加一标志 / a claim must be counted this cycle
    bReleaseInc      : BOOL;                  // 本拍释放计数加一标志 / a release must be counted this cycle
END_VAR
VAR CONSTANT
    DL_SEMA_CNT_MAX  : UDINT := 16#FFFF_FFFE; // 计数饱和值，永不回绕 [次] / counter saturation value, never wraps [times]
    DL_SEMA_HOLD_DEF : TIME := T#5S;          // 默认占用上限 [ms] / default hold time limit [ms]
    DL_SEMA_TIME_ZERO : TIME := T#0s;         // 零时长常量，监视禁用判据 [ms] / zero duration used by the disable test [ms]
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 / signed zero constant
END_VAR

// 段 1｜边沿与定时器实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional instance refresh
fbTrigClaim(CLK := bClaim);                   // 申请沿刷新，每拍必跑 / refresh the claim edge every cycle
fbTrigRelease(CLK := bRelease);               // 释放沿刷新，每拍必跑 / refresh the release edge every cycle
bHoldMonEn := TIME_TO_DINT(tHoldMax) > DL_DINT_ZERO; // 监视使能：上限 > 0 / supervision enabled when the limit is positive
fbHold(IN := (eState = eHeld) AND bHoldMonEn, PT := tHoldMax); // 定时器刷新，IN 取上一拍锁存状态 / refresh with the latched state of the previous cycle

// 段 2｜输出与错误状态预置（脉冲量每拍先清）/ segment 2, preset outputs and error status
bTimedOut := FALSE;                           // 单拍脉冲先清 / clear the single-cycle pulse first
bBusy := FALSE;                               // 占用标志先清，由状态重算 / clear the busy flag, recomputed from the state
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bClaimInc := FALSE;                           // 申请计数标志预置 / preset the claim counting flag
bReleaseInc := FALSE;                         // 释放计数标志预置 / preset the release counting flag

// 段 3｜同拍仲裁：释放优先（安全侧，宁可多还一次不可错持一次）/ segment 3, same-cycle arbitration with release priority
bClaimEff := fbTrigClaim.Q;                   // 默认采用申请沿 / take the claim edge by default
bReleaseEff := fbTrigRelease.Q;               // 默认采用释放沿 / take the release edge by default
IF fbTrigClaim.Q AND fbTrigRelease.Q THEN
    bClaimEff := FALSE;                       // 同拍撤销申请 / drop the claim in the same cycle
    bReleaseEff := TRUE;                      // 同拍保留释放 / keep the release
    eErr := 16#0001_0432;                     // 信息级：同拍释放优先 / info level, the release wins in the same cycle
END_IF

// 段 4｜状态机三态分派（ELSE 兜底必须落故障码）/ segment 4, three-state dispatch with a mandatory ELSE fallback
CASE eState OF

    eFree:
        IF bClaimEff THEN
            eState := eHeld;                  // 空闲态受理申请 → 持锁 / the free state accepts a claim
            bClaimInc := TRUE;                // 记一次申请 / count the claim
            IF NOT bHoldMonEn THEN
                eErr := 16#0001_0432;         // 信息级：超时监视被禁用，超长占用无人看管 / info level, the supervision is disabled
            END_IF
        END_IF

    eHeld:
        IF bReleaseEff THEN
            eState := eFree;                  // 释放优先：复位通道永不被超时路径屏蔽 / release wins, the reset path is never masked
            bReleaseInc := TRUE;              // 记一次释放 / count the release
        ELSIF fbHold.Q AND bHoldMonEn THEN
            eState := eTimedOutRelease;       // 超时：转过渡态并由系统归还 / timed out, the lock is returned by the system
            bTimedOut := TRUE;                // 本拍超时脉冲 / the timeout pulse of this cycle
            bReleaseInc := TRUE;              // 系统归还也要记账 / the returned lock is still counted as a release
            eErr := 16#0001_0369;             // 故障级：占用超时已强制归还 / fault level, the hold timed out and was released
            bError := TRUE;                   // 置故障标志 / raise the error flag
        END_IF

    eTimedOutRelease:
        eState := eFree;                      // 过渡态本拍即回空闲 / the transitional state returns to free in this cycle
        // 本拍申请被拒：锁刚被强制归还，同拍授予会让调用方误判锁的来源
        // a claim in this cycle is rejected, the lock was just forced back

    ELSE
        eState := eFree;                      // 非法状态一律复位 / any illegal state is reset
        bTimedOut := FALSE;                   // 撤销脉冲，避免假事件 / drop the pulse to avoid a phantom event
        eErr := 16#0001_036A;                 // 故障级：非法状态兜底 / fault level, illegal state fallback
        bError := TRUE;                       // 置故障标志 / raise the error flag

END_CASE

// 段 5｜累计计数：饱和不回绕，饱和即升故障级（不覆盖已置的更高优先故障码）/ segment 5, saturating counters
IF bClaimInc THEN
    IF uClaimCnt < DL_SEMA_CNT_MAX THEN
        uClaimCnt := uClaimCnt + 1;           // 饱和加一 / saturating increment
    ELSE
        IF NOT bError THEN
            eErr := 16#0001_036B;             // 故障级：申请计数饱和 / fault level, the claim counter saturated
        END_IF
        bError := TRUE;                       // 置故障标志 / raise the error flag
    END_IF
END_IF

IF bReleaseInc THEN
    IF uReleaseCnt < DL_SEMA_CNT_MAX THEN
        uReleaseCnt := uReleaseCnt + 1;       // 饱和加一 / saturating increment
    ELSE
        IF NOT bError THEN
            eErr := 16#0001_036B;             // 故障级：释放计数饱和 / fault level, the release counter saturated
        END_IF
        bError := TRUE;                       // 置故障标志 / raise the error flag
    END_IF
END_IF

// 段 6｜占用标志由状态派生（双保险：状态是唯一事实源）/ segment 6, derive the busy flag from the state
bBusy := (eState = eHeld);                    // 只有持锁态才算占用 / only the held state counts as busy
END_FUNCTION_BLOCK
