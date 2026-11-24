(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RedundantSwitch
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / F_TRIG / ABS）
 * 功能描述 (Function)   : 双通道（双传感器或双执行器反馈）冗余选择器。
 *                         持续比较 A/B 偏差，超限并经延时确认后报警；两通道互相矛盾时
 *                         不猜谁对——默认保持最后有效值，也可显式改为跟随某一路或直接判故障；
 *                         单通道失效时按停留时间与速率限制无扰切换到另一通道；
 *                         切换过于频繁则判定抖振并锁存，杜绝"接触器被程序当成振荡器打"。
 *                         解决两个现场通病：①双传感器冗余装了，程序里却只接了一路；
 *                         ②切过去那一瞬间阀门位置跳变，工艺直接甩料。
 *
 * 【核心语义 / Core semantics（边界 B1，本组件最重要的约定）】
 *   两路传感器打架时，程序没有资格替工艺判断谁对。默认策略是 eHoldLast：保持最后
 *   有效值并报警，等工程师到现场看表。要自动跟随某一路，必须显式把 eDevPolicy 改成
 *   eUseA / eUseB，并在设计文件里留档"为什么信这一路"。
 *
 * 【失真与语义披露 / Distortion disclosure】
 *   1) 本块不做 NaN/Inf 检测：IEC 61131-3 无标准判据，各平台行为不一致，强行判断会
 *      引入编译器方言。通道含 NaN 时会污染输出，调用方必须前置量程与断线校验。
 *   2) fMaxSlewRate = 0 的定义是"直接切换"，不是"不切换"。现场若按"0 = 禁用"理解，
 *      会误以为切换失效，故参数注释与手册双重明示。
 *   3) eDevPolicy = eFault 时按"无可用源"口径复用 16#0002_0005：矛盾双方均不可信，
 *      等价于没有可信源。第 4 章未为该策略单列故障码，本块不新造码，改为复用并在此披露。
 *   4) 偏差报警是"已确认事实"，切到单通道后不再有比较对象，因此保持到两路同时有效且
 *      偏差回落，或收到复位沿为止（自检向量 V4）。
 *
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 比较器功能组的公差窗口分类与工业冗余
 *                         惯例的参数域，clean-room 编写，未复制任何源码）
 * 本文件内含       : TYPE  E_DL_RedundancyPriority / E_DL_DeviationPolicy
 *                    TYPE  E_DL_ActiveChannel / E_DL_RedundState
 *                    FB    FB_DL_RedundantSwitch
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG / F_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无指针、无厂商私有符号）
 *                         R4 ✓ 偏差限钳位 + 时间增量钳位 + 除零前判零 + 抖振锁定
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 四个实例（一沿 + 三计时）主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举 1: E_DL_RedundancyPriority — 首选通道策略（归属 DL_Base）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RedundancyPriority :
(
    eAuto   := 0,     // 自动：首次选 A，之后跟随当前生效通道 / Auto, pick A first then follow the active one
    eForceA := 1,     // 强制 A，仅在 A 失效时才允许越权到 B / Force A, only A invalidity may override
    eForceB := 2      // 强制 B，仅在 B 失效时才允许越权到 A / Force B, only B invalidity may override
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举 2: E_DL_DeviationPolicy — 偏差超限时的处置策略（归属 DL_Base）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DeviationPolicy :
(
    eHoldLast := 0,   // 保持最后有效值（默认，不猜谁对）/ Hold the last valid value, never guess
    eUseA     := 1,   // 视为 B 漂移，跟随 A / Treat B as drifting, follow A
    eUseB     := 2,   // 视为 A 漂移，跟随 B / Treat A as drifting, follow B
    eFault    := 3    // 偏差超限即判故障（保守工艺）/ Fail on deviation, for conservative processes
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举 3: E_DL_ActiveChannel — 当前生效通道（归属 DL_Base）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ActiveChannel :
(
    eNone := 0,       // 无可用通道 / No usable channel
    eA    := 1,       // 通道 A 生效 / Channel A is active
    eB    := 2        // 通道 B 生效 / Channel B is active
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举 4: E_DL_RedundState — 冗余选择器主状态（归属 DL_Base）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RedundState :
(
    eInit    := 0,    // 初始化（首扫）：按首选策略装载首值 / Initialisation, load the first value per preference
    eNormal  := 10,   // 双通道一致，正常跟随 / Both channels agree, normal tracking
    eSuspect := 20,   // 偏差超限，等待判定 / Deviation confirmed, awaiting a decision
    eRamping := 30,   // 切换过渡中（限速逼近目标）/ Bumpless transition in progress
    eFault   := 99    // 无可用通道或抖振锁定 / No usable channel or chatter latched
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_RedundantSwitch
 * 调用约定: 每个扫描周期无条件调用一次，uDeltaTimeMs 必须由调用方注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RedundantSwitch
VAR_INPUT
    fChannelA       : REAL;                        // 通道 A 测量值 [EU] / Channel A value [EU]
    fChannelB       : REAL;                        // 通道 B 测量值 [EU] / Channel B value [EU]
    bChannelAValid  : BOOL := TRUE;                // A 通道健康（无断线、无超量程）/ A healthy, no wire break
    bChannelBValid  : BOOL := TRUE;                // B 通道健康 / B healthy
    fDeviationLimit : REAL := 1.0;                 // 偏差限 [EU]，合法域 > 0 / Deviation limit [EU], must be > 0
    tDeviationDelay : TIME := T#2S;                // 偏差确认延时 [s]，T#0S = 立即确认 / Confirmation delay [s], T#0S = immediate
    ePreferred      : E_DL_RedundancyPriority := E_DL_RedundancyPriority.eAuto;   // 首选通道策略 / Preferred channel policy
    eDevPolicy      : E_DL_DeviationPolicy := E_DL_DeviationPolicy.eHoldLast;     // 偏差处置策略 / Deviation policy
    tSwitchDwell    : TIME := T#500MS;             // 切换后抑制再次切换的停留时间 [ms] / Post-switch dwell [ms]
    fMaxSlewRate    : REAL := 0.0;                 // 无扰过渡最大变化率 [EU/s]，0 = 直接切换 / Max slew rate, 0 = direct switch
    uDeltaTimeMs    : UDINT;                       // 调用方注入的扫描间隔 [ms] / Injected scan delta [ms]
    fSafeValue      : REAL := 0.0;                 // 双通道失效时的安全值 [EU] / Safe value when no source is usable [EU]
    bReset          : BOOL;                        // 上升沿：复位锁存故障与偏差报警 / Rising edge: reset latched faults
END_VAR
VAR_OUTPUT
    fSelected       : REAL;                        // 选择后的输出值 [EU] / Selected output [EU]
    eActive         : E_DL_ActiveChannel;          // 当前生效通道 / Currently active channel
    bOutputValid    : BOOL;                        // 输出有效（非安全值替代）/ Output valid, not a substituted safe value
    fDeviation      : REAL;                        // 当前偏差 |A-B| [EU]，单通道时恒为 0 / Current deviation, 0 when only one channel
    bDeviationAlarm : BOOL;                        // 偏差报警（已延时确认，保持到回落或复位）/ Deviation alarm, latched until recovery or reset
    bRamping        : BOOL;                        // 过渡进行中 / Bumpless transition in progress
    uSwitchCount    : UDINT;                       // 累计切换次数（饱和）/ Switchover count, saturating
    bError          : BOOL;                        // 故障标志（锁存）/ Fault flag, latched
    uErrorId        : UDINT;                       // 故障码，0 = 无故障 / Error code, 0 = no error
    eState          : E_DL_RedundState;            // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset     : R_TRIG;                      // 复位上升沿检测实例 / Reset rising edge detector
    fbTonDev        : TON;                         // 偏差确认定时器 / Deviation confirmation timer
    fbTonDwell      : TON;                         // 切换停留定时器 / Switch dwell timer
    fbTonChatter    : TON;                         // 抖振统计窗口定时器 / Chatter observation window timer
    eStateInt       : E_DL_RedundState;            // 主状态机内部当前态 / Internal state of the main state machine
    eWanted         : E_DL_ActiveChannel;          // 本拍应生效的通道（按策略与有效性推导）/ Channel that should be active this scan
    eTarget         : E_DL_ActiveChannel;          // 过渡目标通道 / Ramp target channel
    ePending        : E_DL_ActiveChannel;          // 本拍待发起的切换目标，eNone = 无 / Pending switch target, eNone = none
    fSelectedInt    : REAL;                        // 输出值内部副本（单一出口用）/ Internal copy of the output, for the single exit
    fTargetVal      : REAL;                        // 过渡目标值 [EU] / Ramp target value [EU]
    fLastValid      : REAL;                        // 最后有效值 [EU]，保持策略的锚点 / Last valid value, the anchor of the hold policy
    fStep           : REAL;                        // 本拍允许的最大变化量 [EU] / Maximum allowed change this scan [EU]
    fDevLimEff      : REAL;                        // 钳位后的偏差限 [EU] / Clamped deviation limit [EU]
    fDtSec          : REAL;                        // 扫描间隔换算成秒 [s] / Scan delta in seconds [s]
    tDwellEff       : TIME;                        // 钳位后的停留时间 [ms] / Clamped dwell time [ms]
    uDtEff          : UDINT;                       // 钳位后的扫描间隔 [ms] / Clamped scan delta [ms]
    uSwInt          : UDINT;                       // 切换次数内部副本（饱和）/ Internal switch counter, saturating
    uWarnId         : UDINT;                       // 本拍瞬时告警码（不进锁存）/ Instantaneous warning code of this scan
    nChatterCnt     : INT;                         // 统计窗口内的切换计数 / Switch count inside the observation window
    bDwellRun       : BOOL;                        // 停留计时进行中（TRUE = 禁止再切）/ Dwell timer running, switching inhibited
    bAnyValid       : BOOL;                        // 至少一路有效 / At least one channel is valid
    bBothValid      : BOOL;                        // 两路同时有效 / Both channels are valid
    bActiveValid    : BOOL;                        // 当前生效通道仍然有效 / The active channel is still valid
    bTargetValid    : BOOL;                        // 过渡目标通道仍然有效 / The ramp target is still valid
    bSwitchNeed     : BOOL;                        // 本拍需要切换（已含停留抑制）/ Switching required this scan
    bAlarmInt       : BOOL;                        // 偏差报警内部副本 / Internal copy of the deviation alarm
    bChatterTrip    : BOOL;                        // 抖振判据成立 / Chatter criterion satisfied
    bFirstScan      : BOOL := TRUE;                // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_RS_DEV_MIN     : REAL := 1.0E-6;            // 偏差限下限 [EU]，兼作浮点判零容差 / Deviation-limit floor, doubles as epsilon
    DL_RS_CHATTER_MAX : INT  := 5;                 // 窗口内允许的最大切换次数 / Max switches per observation window
    DL_RS_CHATTER_WIN : TIME := T#10S;             // 抖振统计窗口 [s] / Chatter observation window [s]
    DL_RS_DT_MAX      : UDINT := 60000;            // 时间增量上限 [ms]，防长时间断点造成巨跳 / Delta clamp [ms]
    DL_RS_CNT_MAX     : UDINT := 16#FFFF_FFFE;     // 切换计数器饱和值 / Switch counter saturation
    DL_RS_DWELL_MAX   : TIME := T#1H;              // 停留时间上限钳位 [s] / Dwell upper clamp [s]
    DL_RS_MS_PER_S    : REAL := 1000.0;            // 毫秒换算常数 [ms/s] / Milliseconds per second
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿 + 三计时器，全部位于主体最前部
 *      Unconditional refresh zone: one edge and three timers at the very top
 *      定时器 IN 先由"原始输入 + 上一拍参数"推导成 BOOL，实例调用本身绝不进 IF
 *      偏差限取自上一拍的钳位值，滞后一拍对"确认延时"这种秒级量无影响
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(* 停留时间钳位先于计时器：超长停留会让人误以为切换失效，钳到 1 h 并保持可观测 *)
(* Clamp the dwell before the timer call so the timer never gets an absurd PT *)
IF tSwitchDwell > DL_RS_DWELL_MAX THEN
    tDwellEff := DL_RS_DWELL_MAX;
ELSE
    tDwellEff := tSwitchDwell;
END_IF

fbTonDev(IN := bChannelAValid AND bChannelBValid AND (ABS(fChannelA - fChannelB) > fDevLimEff),
         PT := tDeviationDelay);

fbTonDwell(IN := bDwellRun, PT := tDwellEff);

fbTonChatter(IN := (nChatterCnt > 0), PT := DL_RS_CHATTER_WIN);

IF fbTonDwell.Q THEN
    bDwellRun := FALSE;
END_IF

IF fbTonChatter.Q THEN
    nChatterCnt := 0;
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：状态、通道号与输出必须显式落到安全侧，不能依赖默认零
 *      First-scan init: state, channel and output are forced to the safe side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    bFirstScan   := FALSE;
    eStateInt    := E_DL_RedundState.eInit;
    eActive      := E_DL_ActiveChannel.eNone;
    eTarget      := E_DL_ActiveChannel.eNone;
    ePending     := E_DL_ActiveChannel.eNone;
    fSelectedInt := fSafeValue;
    fLastValid   := fSafeValue;
    nChatterCnt  := 0;
    bDwellRun    := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 2b｜故障码口径（红线 R15）：锁存期保留进入故障时的码，瞬时告警不得覆盖它
 *      Error-code policy: instantaneous warnings must never overwrite a latched code
 *      先把瞬时码收进 uWarnId，等确认当前不在故障锁存里才落到 uErrorId
 *-----------------------------------------------------------------------------*)
uWarnId := 16#0000;

(*------------------------------------------------------------------------------
 * 段 3｜时间增量校验（边界 B3/B8）：0 或超上限一律钳位并告警
 *      Delta-time check: zero or over-limit values are clamped and reported
 *      0 会让过渡停走（每拍增量 0）；回绕值会把运行方向算反，都不可接受
 *-----------------------------------------------------------------------------*)
IF uDeltaTimeMs = 0 THEN
    uDtEff   := 1;
    uWarnId  := 16#0001_0008;
ELSIF uDeltaTimeMs > DL_RS_DT_MAX THEN
    uDtEff   := DL_RS_DT_MAX;
    uWarnId  := 16#0001_0008;
ELSE
    uDtEff := uDeltaTimeMs;
END_IF

fDtSec := UDINT_TO_REAL(uDtEff) / DL_RS_MS_PER_S;

(*------------------------------------------------------------------------------
 * 段 4｜偏差限钳位（边界 B7）：先取绝对值再钳下限，负号视为"填错符号"
 *      Deviation-limit clamp: absolute value first, then floor at the epsilon
 *      偏差限为 0 会让任何微小噪声都报警，必须抬到 1E-6 而不是放行
 *-----------------------------------------------------------------------------*)
fDevLimEff := ABS(fDeviationLimit);

IF fDevLimEff < DL_RS_DEV_MIN THEN
    fDevLimEff := DL_RS_DEV_MIN;
    uWarnId    := 16#0001_0001;
END_IF

(* 瞬时告警落码：故障锁存期间一律不落码，保证 HMI 读到的根因不被参数告警冲掉 *)
(* Warnings land only outside the latched fault state, otherwise the root cause is lost *)
IF eStateInt <> E_DL_RedundState.eFault THEN
    IF uWarnId <> 16#0000 THEN
        uErrorId := uWarnId;
    ELSE
        uErrorId := 16#0000_0000;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜有效性与偏差（边界 B6 的前置量）：单通道时偏差恒为 0
 *      Validity and deviation: with one channel there is no comparison object
 *      单通道时"沿用旧偏差"会让报警永远挂着，必须显式归零
 *-----------------------------------------------------------------------------*)
bAnyValid  := bChannelAValid OR bChannelBValid;
bBothValid := bChannelAValid AND bChannelBValid;

IF bBothValid THEN
    fDeviation := ABS(fChannelA - fChannelB);
ELSE
    fDeviation := 0.0;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜偏差报警（边界：V4 语义）：确认后保持，回落或复位才清
 *      Deviation alarm: latched once confirmed, cleared on recovery or reset
 *-----------------------------------------------------------------------------*)
IF fbTonDev.Q THEN
    bAlarmInt := TRUE;
END_IF

IF bBothValid AND (fDeviation <= fDevLimEff) THEN
    bAlarmInt := FALSE;
END_IF

IF fbTrigReset.Q THEN
    bAlarmInt := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜目标通道推导（边界 B1/B2）
 *      Target-channel derivation: preference first, then validity, never both guesses
 *      eAuto 的语义是"保持当前有效通道"，只有当前通道失效才换——不是每拍重新投票
 *-----------------------------------------------------------------------------*)
IF NOT bAnyValid THEN
    eWanted := E_DL_ActiveChannel.eNone;
ELSIF ePreferred = E_DL_RedundancyPriority.eForceA THEN
    IF bChannelAValid THEN
        eWanted := E_DL_ActiveChannel.eA;
    ELSE
        eWanted := E_DL_ActiveChannel.eB;
    END_IF
ELSIF ePreferred = E_DL_RedundancyPriority.eForceB THEN
    IF bChannelBValid THEN
        eWanted := E_DL_ActiveChannel.eB;
    ELSE
        eWanted := E_DL_ActiveChannel.eA;
    END_IF
ELSE
    (* eAuto：当前通道仍有效就不动，失效才换到另一路 *)
    IF (eActive = E_DL_ActiveChannel.eA) AND bChannelAValid THEN
        eWanted := E_DL_ActiveChannel.eA;
    ELSIF (eActive = E_DL_ActiveChannel.eB) AND bChannelBValid THEN
        eWanted := E_DL_ActiveChannel.eB;
    ELSIF bChannelAValid THEN
        eWanted := E_DL_ActiveChannel.eA;
    ELSE
        eWanted := E_DL_ActiveChannel.eB;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜切换判据（边界 B5）：源通道失效可越权（安全优先），否则受停留时间抑制
 *      Switch criterion: a dead source overrides the dwell, a healthy one does not
 *-----------------------------------------------------------------------------*)
IF eActive = E_DL_ActiveChannel.eA THEN
    bActiveValid := bChannelAValid;
ELSIF eActive = E_DL_ActiveChannel.eB THEN
    bActiveValid := bChannelBValid;
ELSE
    bActiveValid := FALSE;
END_IF

bSwitchNeed := (eWanted <> E_DL_ActiveChannel.eNone)
               AND (eWanted <> eActive)
               AND ((NOT bDwellRun) OR (NOT bActiveValid));

(*------------------------------------------------------------------------------
 * 段 9｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
ePending := E_DL_ActiveChannel.eNone;

CASE eStateInt OF

    E_DL_RedundState.eInit:
        (* 首扫后按策略装载首值；双无效直接进故障，输出安全值 *)
        (* Load the first value per preference; no valid source goes straight to fault *)
        IF bAnyValid THEN
            eActive      := eWanted;
            IF eActive = E_DL_ActiveChannel.eA THEN
                fSelectedInt := fChannelA;
            ELSE
                fSelectedInt := fChannelB;
            END_IF
            fLastValid := fSelectedInt;
            eTarget    := eActive;
            fTargetVal := fSelectedInt;
            eStateInt  := E_DL_RedundState.eNormal;
        ELSE
            eStateInt := E_DL_RedundState.eFault;
            uErrorId  := 16#0002_0005;
        END_IF

    E_DL_RedundState.eNormal:
        IF NOT bAnyValid THEN
            eStateInt := E_DL_RedundState.eFault;
            uErrorId  := 16#0002_0005;
        ELSIF bSwitchNeed THEN
            ePending  := eWanted;
            eStateInt := E_DL_RedundState.eRamping;
        ELSIF fbTonDev.Q THEN
            (* 偏差确认到期：进入疑似态，由策略决定输出与后续动作 *)
            (* Deviation confirmed: enter the suspect state, the policy decides *)
            eStateInt := E_DL_RedundState.eSuspect;
        ELSE
            (* 正常跟随：输出必须每拍跟踪当前生效通道，否则会输出一个冻结值 *)
            (* Normal tracking: the output must follow the active channel every scan *)
            IF (eActive = E_DL_ActiveChannel.eA) AND bChannelAValid THEN
                fSelectedInt := fChannelA;
            ELSIF (eActive = E_DL_ActiveChannel.eB) AND bChannelBValid THEN
                fSelectedInt := fChannelB;
            END_IF
            fLastValid := fSelectedInt;
        END_IF

    E_DL_RedundState.eSuspect:
        IF NOT bAnyValid THEN
            eStateInt := E_DL_RedundState.eFault;
            uErrorId  := 16#0002_0005;
        ELSIF bSwitchNeed THEN
            (* 疑似失效的那一路被宣告 Valid = FALSE：偏差比较已无意义，直接切 *)
            (* The suspect channel dropped its valid flag: compare is meaningless, switch at once *)
            ePending  := eWanted;
            eStateInt := E_DL_RedundState.eRamping;
        ELSIF (NOT bBothValid) OR (fDeviation <= fDevLimEff) THEN
            (* 偏差已无对象或已回落：回到正常跟随 *)
            (* No comparison object left, or the deviation recovered: back to normal *)
            eStateInt := E_DL_RedundState.eNormal;
        ELSE
            CASE eDevPolicy OF
                E_DL_DeviationPolicy.eHoldLast:
                    (* 默认：保持最后有效值，谁都不信 *)
                    (* Default: hold the last valid value, trust neither channel *)
                    fSelectedInt := fLastValid;

                E_DL_DeviationPolicy.eUseA:
                    IF bChannelAValid THEN
                        fSelectedInt := fChannelA;
                        fLastValid   := fSelectedInt;
                    ELSE
                        fSelectedInt := fLastValid;
                    END_IF

                E_DL_DeviationPolicy.eUseB:
                    IF bChannelBValid THEN
                        fSelectedInt := fChannelB;
                        fLastValid   := fSelectedInt;
                    ELSE
                        fSelectedInt := fLastValid;
                    END_IF

                E_DL_DeviationPolicy.eFault:
                    (* 保守工艺：矛盾即停机，按"无可用源"口径复用 0002_0005（见头注释） *)
                    (* Conservative: contradictory means stop, reuse 0002_0005 as documented *)
                    eStateInt := E_DL_RedundState.eFault;
                    uErrorId  := 16#0002_0005;

                ELSE
                    eStateInt := E_DL_RedundState.eFault;
                    uErrorId  := 16#0001_0005;
            END_CASE
        END_IF

    E_DL_RedundState.eRamping:
        IF eTarget = E_DL_ActiveChannel.eA THEN
            bTargetValid := bChannelAValid;
        ELSIF eTarget = E_DL_ActiveChannel.eB THEN
            bTargetValid := bChannelBValid;
        ELSE
            bTargetValid := FALSE;
        END_IF

        (* 目标通道的物理值在过渡期间仍会变，目标值必须每拍刷新，否则会爬向一个陈旧值 *)
        (* The target channel keeps moving during the ramp, so refresh the target value each scan *)
        IF bTargetValid THEN
            IF eTarget = E_DL_ActiveChannel.eA THEN
                fTargetVal := fChannelA;
            ELSE
                fTargetVal := fChannelB;
            END_IF
        END_IF

        IF NOT bAnyValid THEN
            eStateInt := E_DL_RedundState.eFault;
            uErrorId  := 16#0002_0005;
        ELSIF NOT bTargetValid THEN
            (* 目标在过渡途中失效：中止过渡，退回当前生效通道，不产生第二次切换计数 *)
            (* Target died mid-ramp: abort and retreat, without counting a second switch *)
            eTarget    := eActive;
            fTargetVal := fSelectedInt;
            eStateInt  := E_DL_RedundState.eNormal;
        ELSIF (ABS(fMaxSlewRate) <= DL_RS_DEV_MIN) OR (fDtSec <= 0.0) THEN
            (* 边界 B4：速率 0 定义为直接切换；dt 异常时也取向直接吸附，绝不发散的慢慢爬 *)
            (* Rate 0 means direct switching; an abnormal dt snaps instead of crawling forever *)
            fSelectedInt := fTargetVal;
            eActive      := eTarget;
            fLastValid   := fSelectedInt;
            eStateInt    := E_DL_RedundState.eNormal;
        ELSE
            fStep := ABS(fMaxSlewRate) * fDtSec;
            IF ABS(fTargetVal - fSelectedInt) <= fStep THEN
                fSelectedInt := fTargetVal;
                eActive      := eTarget;
                fLastValid   := fSelectedInt;
                eStateInt    := E_DL_RedundState.eNormal;
            ELSE
                IF fTargetVal > fSelectedInt THEN
                    fSelectedInt := fSelectedInt + fStep;
                ELSE
                    fSelectedInt := fSelectedInt - fStep;
                END_IF
            END_IF
        END_IF

    E_DL_RedundState.eFault:
        (* 边界 B6：双通道失效时输出安全值，绝不输出"最后有效值"——最后值同样可疑 *)
        (* Both channels dead: output the safe value, never the last valid one *)
        fSelectedInt := fSafeValue;
        IF fbTrigReset.Q AND bAnyValid THEN
            uErrorId    := 16#0000_0000;
            nChatterCnt := 0;
            bDwellRun   := FALSE;
            eStateInt   := E_DL_RedundState.eInit;
        END_IF

    ELSE
        (* 非法状态拦截：不做隐式恢复，直接锁存上报 *)
        (* Illegal state interception: no implicit recovery, latch and report *)
        eStateInt := E_DL_RedundState.eFault;
        uErrorId  := 16#0001_0005;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 10｜切换提交（唯一切换记账点）
 *      Switch commitment: the one and only place where switching is booked
 *      只在状态机确实发起切换的那一拍记账，过渡期内绝不重复累加，否则抖振判据必被误触
 *      Bookkeeping happens once per initiated switch, never during the ramp itself
 *-----------------------------------------------------------------------------*)
IF ePending <> E_DL_ActiveChannel.eNone THEN

    eTarget := ePending;

    IF eTarget = E_DL_ActiveChannel.eA THEN
        fTargetVal := fChannelA;
    ELSE
        fTargetVal := fChannelB;
    END_IF

    IF uSwInt < DL_RS_CNT_MAX THEN
        uSwInt := uSwInt + 1;
    ELSE
        uErrorId := 16#0001_0007;
    END_IF

    (* 计数封顶在 MAX+1，既能判定越限又不会让 INT 溢出 *)
    (* The counter stops at MAX+1: enough to trip, never enough to overflow *)
    IF nChatterCnt <= DL_RS_CHATTER_MAX THEN
        nChatterCnt := nChatterCnt + 1;
    END_IF

    bDwellRun := TRUE;

    (* 抖振判据（边界 B6）：窗口内切换次数超限即锁定，说明设定错误或信号在临界点抖 *)
    (* Chatter: too many switches inside the window means a bad setup or a dithering signal *)
    bChatterTrip := (nChatterCnt > DL_RS_CHATTER_MAX);
    IF bChatterTrip THEN
        uErrorId  := 16#0002_0006;
        eStateInt := E_DL_RedundState.eFault;
    ELSE
        (* 边界 B4：速率 0 定义为"直接切换"，在发起的同一拍吸附到目标值 *)
        (* Rate 0 means a direct switch: snap to the target in the very same scan *)
        IF ABS(fMaxSlewRate) <= DL_RS_DEV_MIN THEN
            fSelectedInt := fTargetVal;
            eActive      := eTarget;
            fLastValid   := fSelectedInt;
            eStateInt    := E_DL_RedundState.eNormal;
        END_IF
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 11｜输出单一出口（范式 P-05）
 *      Single output exit: every output is derived once, here
 *-----------------------------------------------------------------------------*)
fSelected       := fSelectedInt;
bOutputValid    := bAnyValid AND (eActive <> E_DL_ActiveChannel.eNone)
                   AND (eStateInt <> E_DL_RedundState.eFault);
bDeviationAlarm := bAlarmInt;
bRamping        := (eStateInt = E_DL_RedundState.eRamping);
uSwitchCount    := uSwInt;
bError          := (eStateInt = E_DL_RedundState.eFault);
eState          := eStateInt;
END_FUNCTION_BLOCK
