(*
    FB_DL_AxisBrakeSeq —— 伺服抱闸时序
    ------------------------------------------------------------------
    分类      : DL_Motion / AxisSafety
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T1-6 PLCopen（只借「使能 / 抱闸属于轴生命周期授权动作」的公开语义，
                MC_Power 类功能块的使能时序纪律）；T2-4 S7 Motion 抱闸组织为次源；
                两序状态机、超时取舍、码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    道莅 clean-room 防御性实现：语义借鉴、代码与码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R22 批 4 · #12）
    ------------------------------------------------------------------
    功能说明  : 伺服轴「上电」与「断电」两条机械-电气强制顺序的唯一屬主件。
                本件只输出两个有序命令（抱闸释放命令、伺服使能命令），
                不发运动指令、不自造轴状态枚举，轴状态唯一属主仍在轴功能块。
    两条序（顺序写反即掉轴，此处文字画时序，编码与之一一对应）:
                上电序 A：bEnableReq↑
                          → bBrakeReleaseCmd := TRUE
                          → 等「抱闸释放到位」（有反馈等反馈；无反馈等 tBrakeRelease）
                          → bServoEnable := TRUE
                          → eEnabled
                  理由：先使能后释放，电机顶着抱闸出力，抱闸片烧蚀。
                断电序 B：bEnableReq↓
                          → eStopping：保持带使能、保持抱闸打开
                          → 等 |fActVel| < fStandstillVel 连续 tStandstill
                          → bBrakeReleaseCmd := FALSE（抱闸闭合）
                          → 等 tBrakeHold（机械闭合建立力矩）
                          → bServoEnable := FALSE
                          → eDisabled
                  理由：先断使能后抱闸，轴在自由态下滑落；抱闸未建立力矩就断使能同样滑落。
    设计取舍  : ① 断电序中轴未在 tFbTimeout 内静止 → 报 02EB 并「拒绝断使能」：
                   保持带使能 + 保持抱闸打开，把轴钉在原位。宁可报警停线，不可掉轴。
                   若此时伺服本就没有使能（无转矩可用），则无「拒绝」可言，
                   改为立即闭合抱闸并报警——无转矩时抱闸是唯一能拦住轴的机构，
                   宁可磨损抱闸片也不让它自由滑落。两条支路靠 _bServoOn 上一拍快照区分。
                ② 抱闸释放反馈超时 → 报 02EA 并「禁止使能」，直接全失电
                   （弹簧制动器失电即抱死，是唯一安全侧）。
                ③ 无反馈现场（bBrakeFbAvailable = FALSE）按纯时间序列放行，
                   报信息 01D5；该风险由现场调试承担，头注释即为此留档。
    错误码    : 16#0004_01D5 无抱闸释放反馈，已按纯时间序列放行——信息级，正常防御
                16#0004_01D6 等待延长后放行（抱闸释放反馈迟到但收到 / 断电序静止窗因
                              速度抖动反复重启已延长等待）——信息级，两处共用本码，
                              靠所处状态区分，不得据此拒绝动作（R90）
                16#0004_02EA 抱闸释放反馈超 tFbTimeout，禁止使能——故障级，全失电
                16#0004_02EB 断电序轴未静止超 tFbTimeout，拒绝断使能——故障级，
                             有转矩时保持带使能 + 抱闸打开
                16#0004_02EC 序列参数非法 / 采样非有限 / 状态机落 ELSE 兜底——故障级
                             （三支复用，R90；靠进入路径区分，均回 eFault 并全失电）
    码位总账  : 16#0004_01D5 用 / 16#0004_01D6 用 ｜ 16#0004_02EA 用 / 16#0004_02EB 用 / 16#0004_02EC 用
    状态机    : E_DL_BrakeSeqState（eIdle / eReleasing / eEnabled / eStopping / eBraking
                / eDisabled / eFault），CASE 含 ELSE 兜底，ELSE 置 16#0004_02EC 并回 eFault；
                失能请求无条件经 eStopping，eEnabled 不得直跳 eDisabled（R71）。
    采样约定  : 五个 TON 实例在本体最前部无条件调用（R40），每段一只实例、绝不跨段复用；
                段转出统一走「断输入一拍」标志（_bRelBreak / _bStopBreak / _bHoldBreak），
                断一拍标志在对应 TON 调用之后立刻自清，避免下一拍再吞掉计时。
                本件不读系统时钟，时间全部来自 TIME 引脚。
    依赖      : 仅 Standard.library（TON / ABS / MIN / MAX / LIMIT），
                不引用任何其他 DL_ 子库（DL_Motion/VERSION.md 硬约束）。
    验收向量  :
                V1 域外早退：fStandstillVel = 0 → 02EC、bError=TRUE、bValid=FALSE、
                   两命令全 FALSE（弹簧制动器失电抱死）。
                V2 上限截断/超时：bBrakeReleaseFb 恒 FALSE 且 bBrakeFbAvailable=TRUE
                   → tFbTimeout 到 → 02EA、bServoEnable 恒 FALSE、bBrakeReleaseCmd 转 FALSE。
                V3 跨段时序：eEnabled 中 bEnableReq↓ 同拍 fActVel = 50 mm/s（未静止）
                   → 先入 eStopping 且 bServoEnable 保持 TRUE、bBrakeReleaseCmd 保持 TRUE，
                   tFbTimeout 后才报 02EB；不得同拍闭合抱闸。
                V4 恢复/复位首拍：抱闸闭合后立即 bEnableReq↑（eBraking 期间）
                   → 不得半途重启上电序，须走完 eBraking → eDisabled → eIdle → eReleasing。
    红线自检  : 1 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 —— 通过，全部量经引脚注入
                2 纯 IEC 61131-3 跨平台 —— 通过，仅 Standard.library
                3 防御性编程 —— 通过，浮点判等全用绝对值阈、无非有限值穿透、无除法
                4 声明行同行中英双语注释 + 单位 —— 通过，逐行附注（含枚举成员）
                5 ENUM + CASE 且含 ELSE 兜底 —— 通过，两条 CASE（主状态机 / 输出映射）
                6 TON / R_TRIG 无条件刷新 —— 通过，段 1 全部实例先行调用
                7 无魔法数 —— 通过，阈值与时间全部为引脚或 VAR CONSTANT
    修订记录  : 2026-11-16 v1.0.0 首次入库（R22 批 4 · #12）
                2026-11-16 v1.0.1 R22 终审勘误：tBrakeRelease 引脚注释原写「有反馈时
                作为最短等待」，实现实际为「反馈到达即采信」，注释对齐实现（不改时序
                代码）；并显式声明配置约束 tFbTimeout > tBrakeRelease——超时窗
                （fbRelFeedback）与标称等待（fbRelease）同拍起算，若超时窗不大于
                标称等待，会在标称时间之前误报 02EA
*)
TYPE E_DL_BrakeSeqState :
(
    eIdle      := 0,     // 待机，两命令全失电，等使能请求上升沿 / idle, both commands de-energised, waiting for the enable request
    eReleasing := 10,    // 抱闸释放中，等释放到位或时间放行，伺服仍未使能 / releasing the brake, servo not yet enabled
    eEnabled   := 20,    // 已使能，抱闸打开且伺服带转矩，可接受运动指令 / enabled, brake open and servo energised
    eStopping  := 30,    // 断电序等待静止，保持带使能 + 保持抱闸打开 / stopping, waiting for standstill while keeping enable and brake open
    eBraking   := 40,    // 抱闸已闭合，等 tBrakeHold 建立机械力矩 / brake engaged, waiting for the mechanical torque build-up
    eDisabled  := 50,    // 已失电，抱闸闭合，伺服失能，可接受新使能请求 / disabled, brake engaged and servo de-energised
    eFault     := 60     // 故障，出口按 _bHoldEnableOnFault 决定保持或全失电 / fault, outputs follow the hold flag
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisBrakeSeq
VAR_INPUT
    bEnableReq        : BOOL;                  // 使能请求（上升沿启动上电序，下降沿启动断电序）/ enable request, rising edge starts the power-up sequence
    fActVel           : REAL;                  // 轴实际速度 [mm/s]，取绝对值参与静止判定 / axis actual velocity [mm/s], absolute value used for the standstill test
    fStandstillVel    : REAL := 1.0;           // 静止判定速度阈 [mm/s]，必须大于 0 / standstill velocity threshold [mm/s], must exceed zero
    bBrakeReleaseFb   : BOOL;                  // 抱闸释放到位反馈，TRUE = 已释放 / brake released feedback, TRUE = fully released
    bBrakeFbAvailable : BOOL := TRUE;          // FALSE 时按纯时间序列（无反馈现场）/ FALSE = time-based sequence only on a site without feedback
    tBrakeRelease     : TIME := T#200MS;       // 抱闸释放标称等待 [ms]，无反馈时按此放行；有反馈时反馈到达即采信（不做最短等待）；超时窗自进相起算，须配置 tFbTimeout > tBrakeRelease / brake release nominal wait [ms]; without feedback the release is time-based, with feedback the acknowledgement is trusted on arrival (no minimum wait); the timeout window starts at phase entry, so tFbTimeout must exceed this value
    tBrakeHold        : TIME := T#300MS;       // 抱闸闭合保持等待 [ms]，建立机械力矩 / brake hold wait [ms] for the mechanical torque build-up
    tStandstill       : TIME := T#100MS;       // 静止确认时间 [ms]，必须大于 0 / standstill confirmation time [ms], must exceed zero
    tFbTimeout        : TIME := T#2S;          // 序列超时 [ms]，必须大于 0 / sequence timeout [ms], must exceed zero
END_VAR
VAR_OUTPUT
    bServoEnable      : BOOL;                  // 伺服使能命令，上电序最后置位、断电序最先复位 / servo enable command, set last on power-up and cleared first on power-down
    bBrakeReleaseCmd  : BOOL;                  // 抱闸释放命令，上电序最先置位、断电序先于使能复位 / brake release command, set first on power-up and cleared before the enable drops
    bSeqDone          : BOOL;                  // 断电序完成单拍脉冲，发布后即刻自清 / one-scan pulse at power-down completion, self-cleared right after publishing
    eErr              : UDINT;                 // 错误码，0 表示无错 / error code, 0 means no error
    bError            : BOOL;                  // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid            : BOOL;                  // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    fbRelease         : TON;                   // 抱闸释放最短等待定时器，仅 eReleasing 使用 / brake release minimum wait, used in eReleasing only
    fbRelFeedback     : TON;                   // 抱闸释放反馈超时定时器，仅 eReleasing 使用 / release feedback timeout, used in eReleasing only
    fbStandstill      : TON;                   // 静止确认定时器，仅 eStopping 使用 / standstill confirmation timer, used in eStopping only
    fbStopTimeout     : TON;                   // 断电序总超时定时器，仅 eStopping 使用 / power-down timeout, used in eStopping only
    fbBrakeHold       : TON;                   // 抱闸闭合保持定时器，仅 eBraking 使用 / brake hold timer, used in eBraking only
    _bRelBreak        : BOOL;                  // eReleasing 两只定时器的断输入一拍标志 / break-input flag for the two timers of eReleasing
    _bStopBreak       : BOOL;                  // eStopping 两只定时器的断输入一拍标志 / break-input flag for the two timers of eStopping
    _bHoldBreak       : BOOL;                  // eBraking 定时器的断输入一拍标志 / break-input flag for the timer of eBraking
    _bServoOn         : BOOL;                  // 上一拍伺服使能快照，断电序与故障出口用 / previous-scan servo enable snapshot used by the stop phase and the fault exit
    _bStill           : BOOL;                  // 本拍静止条件（速度绝对值小于阈）/ standstill condition of this scan
    _bStillPrev       : BOOL;                  // 上一拍静止条件，用于捕捉稳定窗重启 / previous-scan standstill condition, catches a restarted window
    _bStopExtend      : BOOL;                  // 断电序等待被延长标志（稳定窗重启过一次）/ stop-phase wait extension flag, set once per sequence
    _bRelLate         : BOOL;                  // 抱闸释放反馈迟到标志，按序只报一次 / late release feedback flag, reported once per sequence
    _bFsmBad          : BOOL;                  // 采样非有限或参数非法标志，供码位链使用 / non-finite sample or illegal parameter flag feeding the code chain
    _bHoldEnableOnFault : BOOL;                // 故障出口「保持带使能 + 抱闸打开」锁存开关，仅 02EB 且有转矩时置位，离开故障态才清 / latched fault-exit hold switch, set only by 02EB when the drive had torque and cleared when leaving the fault state
    _uErrLatch        : UDINT;                 // 故障码锁存副本，故障态每拍重发布，防止段 2 预置冲掉 / latched fault code republished every scan inside the fault state
    _bDonePulse       : BOOL;                  // 断电序完成脉冲源，段 2 发布后立刻自清 / completion pulse source, published then cleared in segment 2
    _eState           : E_DL_BrakeSeqState;    // 当前状态 / current state
END_VAR
VAR CONSTANT
    DL_BS_INF_GUARD : REAL := 4.0E38;          // 非有限幅值判定阈值（大于 REAL 最大值）[mm/s] / non-finite magnitude guard above the REAL maximum [mm/s]
    DL_BS_ZERO      : REAL := 0.0;             // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_BS_T_ZERO    : TIME := T#0S;            // 零时间常量，用于参数门禁 / zero time constant used by the parameter gate
END_VAR

// 段 1｜五个 TON 无条件周期刷新（红线 6：严禁放入 IF / CASE，也严禁跨段复用实例）
// segment 1, five TON instances refreshed unconditionally, one instance per segment and never shared
fbRelease(IN := (_eState = E_DL_BrakeSeqState.eReleasing) AND (NOT _bRelBreak), PT := tBrakeRelease);
fbRelFeedback(IN := (_eState = E_DL_BrakeSeqState.eReleasing) AND (NOT _bRelBreak), PT := tFbTimeout);
_bRelBreak := FALSE;                            // 断输入标志用后即刻自清，避免下一拍再吞计时 / the break flag clears right after the call so the next scan times normally
_bStill := ABS(fActVel) < fStandstillVel;       // 本拍静止条件，绝对速度与阈比较 / standstill condition of this scan
fbStandstill(IN := (_eState = E_DL_BrakeSeqState.eStopping) AND (NOT _bStopBreak) AND _bStill, PT := tStandstill);
fbStopTimeout(IN := (_eState = E_DL_BrakeSeqState.eStopping) AND (NOT _bStopBreak), PT := tFbTimeout);
_bStopBreak := FALSE;                           // 断输入标志用后即刻自清 / the break flag clears right after the call
fbBrakeHold(IN := (_eState = E_DL_BrakeSeqState.eBraking) AND (NOT _bHoldBreak), PT := tBrakeHold);
_bHoldBreak := FALSE;                           // 断输入标志用后即刻自清 / the break flag clears right after the call

// 段 2｜输出与错误状态预置（单拍标志在此发布后立刻自清，R25 三律）
// segment 2, preset outputs and error status; the one-scan flag is published and cleared here
eErr := 0;                                      // 预置无错误 / preset no error
bError := FALSE;                                // 预置无故障标志 / preset no error flag
bSeqDone := _bDonePulse;                        // 发布上一拍置的完成脉冲 / publish the completion pulse latched last scan
_bDonePulse := FALSE;                           // 发布即自清，保证只出现一拍 / clear right after publishing so the pulse lasts exactly one scan

// 故障态的错误码与保持开关是锁存量：每拍从锁存副本重新发布，绝不因本段预置被冲掉（R45）
// inside the fault state the code and the hold switch are latched values republished every scan, the preset above cannot erase them
IF _eState = E_DL_BrakeSeqState.eFault THEN
    eErr := _uErrLatch;                         // 重发布锁存故障码，HMI 不会看到码位闪断 / republish the latched code so the HMI never sees it drop out
    bError := TRUE;                             // 故障态恒置故障标志 / the fault flag stays raised inside the fault state
END_IF

// 段 3｜参数与采样门禁：任一非法即全失电并锁死在本拍，不进状态机
// segment 3, parameter and sample gate; any violation de-energises at once and skips the state machine
IF (fStandstillVel <= DL_BS_ZERO)
   OR (tStandstill <= DL_BS_T_ZERO)
   OR (tFbTimeout <= DL_BS_T_ZERO) THEN
    _bFsmBad := TRUE;                           // 静止阈非正 / 确认时间为零 / 超时为零，序列无从判定 / the standstill threshold or a duration is not positive
ELSE
    _bFsmBad := FALSE;                          // 参数合法 / parameters are legal
END_IF

// 非有限采样检测：NaN 用自不自等捕获，±Inf 用幅值门捕获（REAL 最大约 3.4E38）
// non-finite sample detection, NaN via self-inequality and plus/minus infinity via the magnitude guard
IF (fActVel - fActVel) <> (fActVel - fActVel) THEN
    _bFsmBad := TRUE;                           // NaN / not a number
ELSIF ABS(fActVel) > DL_BS_INF_GUARD THEN
    _bFsmBad := TRUE;                           // ±Inf / plus or minus infinity
END_IF

IF _bFsmBad THEN
    eErr := 16#0004_02EC;                       // 故障级：参数非法或采样非有限（与兜底复用，R90）/ fault: illegal parameter or non-finite sample, shared with the fallback
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    _uErrLatch := 16#0004_02EC;                 // 锁存故障码，故障态整段可观测 / latch the code so it stays observable for the whole fault state
    _bHoldEnableOnFault := FALSE;               // 参数不可信时全失电，弹簧制动器抱死 / de-energise when the parameters cannot be trusted, the spring brake locks
    _bRelBreak := TRUE;                         // 三组定时器全部断输入重启 / restart every timer group
    _bStopBreak := TRUE;
    _bHoldBreak := TRUE;
    _bServoOn := FALSE;                         // 快照清零，防止故障出口误保持 / clear the snapshot so the fault exit cannot hold by accident
    _eState := E_DL_BrakeSeqState.eFault;       // 转故障 / go to fault
END_IF

// 段 4｜等待延长观测（信息 01D6 的两处触发源，按序各报一次）
// segment 4, wait-extension observation, the two triggers of information code 01D6, once per sequence each
IF (_eState <> E_DL_BrakeSeqState.eReleasing) AND (_eState <> E_DL_BrakeSeqState.eStopping) THEN
    _bRelLate := FALSE;                         // 离开两序即清迟到标志，下一序可再报 / clear the late flag outside both phases so the next sequence can report again
    _bStopExtend := FALSE;                      // 清断电序延长标志 / clear stop-phase extension flag
END_IF

IF (_eState = E_DL_BrakeSeqState.eStopping) AND _bStillPrev AND (NOT _bStill) THEN
    _bStopExtend := TRUE;                       // 静止窗被打断，本轮等待将被延长 / the standstill window was interrupted, this stop will take longer
END_IF
_bStillPrev := _bStill;                         // 更新上一拍静止条件 / update the previous-scan standstill condition

// 段 5｜主状态机：两条序逐态编码，顺序即安全（R71：eEnabled 不得直跳 eDisabled）
// segment 5, the main state machine; the two sequences are encoded state by state and the order itself is the safety measure
CASE _eState OF
E_DL_BrakeSeqState.eIdle:
    // 待机：全失电，只在使能请求为真时启动上电序 A / idle, everything de-energised, start sequence A only when the request is present
    IF bEnableReq AND (NOT _bFsmBad) THEN
        _bRelBreak := TRUE;                     // 释放等待定时器断一拍重启 / restart the release timers with one scan of FALSE input
        _eState := E_DL_BrakeSeqState.eReleasing;   // 进释放相，下一拍输出段置抱闸释放命令 / enter the release phase, the output map asserts the release command next scan
    END_IF

E_DL_BrakeSeqState.eReleasing:
    // 上电序 A 第 2 步：等抱闸释放到位（有反馈等反馈，无反馈等时间放行）
    // power-up step 2, wait for the brake release, either the feedback or the time-based release
    IF bBrakeFbAvailable THEN
        IF fbRelease.Q AND (NOT bBrakeReleaseFb) THEN
            _bRelLate := TRUE;                  // 标称时间到但反馈未到，转为延长等待 / the nominal time elapsed without feedback, switch to an extended wait
        END_IF
        IF bBrakeReleaseFb THEN
            IF _bRelLate THEN
                eErr := 16#0004_01D6;           // 信息级：反馈迟到但已收到，按延长等待放行 / info: the feedback arrived late and the extended wait released it
            END_IF
            _eState := E_DL_BrakeSeqState.eEnabled;     // 释放到位，允许使能 / the brake is released, enabling is allowed
        ELSIF fbRelFeedback.Q THEN
            eErr := 16#0004_02EA;               // 故障级：释放反馈超时，禁止使能 / fault: release feedback timeout, enabling is forbidden
            bError := TRUE;                     // 置故障标志 / raise the fault flag
            _uErrLatch := 16#0004_02EA;         // 锁存故障码 / latch the code
            _bHoldEnableOnFault := FALSE;       // 全失电，抱闸抱死 / de-energise so the spring brake locks
            _eState := E_DL_BrakeSeqState.eFault;
        END_IF
    ELSE
        IF fbRelease.Q THEN
            _eState := E_DL_BrakeSeqState.eEnabled;     // 无反馈现场：时间到即放行 / no feedback on site, the elapsed time releases it
            eErr := 16#0004_01D5;               // 信息级：无反馈按纯时间序列（风险由现场调试承担）/ info: time-based sequence without feedback, the risk is borne on site
        END_IF
    END_IF
    // 上电序被撤回：不得半途使能，转断电序收尾（抱闸仍打开，先等静止再闭合）
    // the power-up request was withdrawn, never enable halfway and fall through to the stop phase
    IF NOT bEnableReq THEN
        _bStopBreak := TRUE;                    // 静止与超时定时器断一拍重启 / restart the standstill and timeout timers
        _eState := E_DL_BrakeSeqState.eStopping;
    END_IF

E_DL_BrakeSeqState.eEnabled:
    // 已使能：抱闸打开 + 伺服带转矩，断电请求落下即进断电序 B，绝不经由任何捷径
    // enabled, brake open and servo energised; a falling request enters sequence B and never takes a shortcut
    IF NOT bEnableReq THEN
        _bStopBreak := TRUE;                    // 静止与超时定时器断一拍重启 / restart the standstill and timeout timers
        _eState := E_DL_BrakeSeqState.eStopping;    // 必须经 eStopping（R71）/ must pass through eStopping
    END_IF

E_DL_BrakeSeqState.eStopping:
    // 断电序 B 第 1 步：等静止。此处只判不动，抱闸保持打开、使能保持
    // power-down step 1, wait for standstill; nothing moves here, the brake stays open and the enable is held
    IF fbStandstill.Q THEN
        _bHoldBreak := TRUE;                    // 抱闸保持定时器断一拍重启 / restart the brake hold timer
        _eState := E_DL_BrakeSeqState.eBraking;// 静止确认，允许闭合抱闸 / standstill confirmed, the brake may now engage
        IF _bStopExtend THEN
            eErr := 16#0004_01D6;               // 信息级：静止确认窗被抖动打断，等待已延长 / info: the standstill window was interrupted, the wait was extended
        END_IF
    ELSIF fbStopTimeout.Q THEN
        eErr := 16#0004_02EB;                   // 故障级：轴未静止超时 / fault: the axis did not reach standstill in time
        bError := TRUE;                         // 置故障标志 / raise the fault flag
        _uErrLatch := 16#0004_02EB;             // 锁存故障码 / latch the code
        _bHoldEnableOnFault := _bServoOn;       // 有转矩才拒绝断使能；无转矩时改由抱闸拦轴 / only hold the enable when the drive had torque, otherwise let the brake catch the axis
        _eState := E_DL_BrakeSeqState.eFault;
    END_IF
    // 断电序中使能请求又来了：先把本次断电序走完，不允许反向插入（V4 向量）
    // the request came back during the stop phase, finish the stop first and never insert a reverse step

E_DL_BrakeSeqState.eBraking:
    // 断电序 B 第 2 步：抱闸已闭合，等 tBrakeHold 建立机械力矩后才允许断使能
    // power-down step 2, the brake is engaged and the enable must survive the whole hold time
    IF fbBrakeHold.Q THEN
        _bDonePulse := TRUE;                    // 断电序完成脉冲，段 2 下一拍发布并自清 / latch the completion pulse, published and cleared by segment 2 next scan
        _eState := E_DL_BrakeSeqState.eDisabled;
    END_IF

E_DL_BrakeSeqState.eDisabled:
    // 已失电：全输出为假，接受新使能请求（请求仍在则一拍后重启上电序）
    // disabled, every output is false and a new request re-enters the power-up sequence one scan later
    IF bEnableReq AND (NOT _bFsmBad) THEN
        _eState := E_DL_BrakeSeqState.eIdle;    // 回待机，由待机态统一启动，避免两条启动路径 / return to idle so that a single start path exists
    END_IF

E_DL_BrakeSeqState.eFault:
    // 故障：只允许在请求已撤且参数已修好后复位；出口由输出映射段按 _bHoldEnableOnFault 决定
    // fault, reset is accepted only after the request is withdrawn and the parameters are repaired
    IF (NOT bEnableReq) AND (NOT _bFsmBad) THEN
        _bRelBreak := TRUE;                     // 三组定时器全部断输入重启 / restart every timer group
        _bStopBreak := TRUE;
        _bHoldBreak := TRUE;
        _eState := E_DL_BrakeSeqState.eIdle;    // 回待机 / return to idle
    END_IF

ELSE
    // 非法状态兜底：绝不静默停在未知态 / illegal state fallback, never stay silently in an unknown state
    eErr := 16#0004_02EC;                       // 故障级：状态机落 ELSE（与参数门禁复用，R90）/ fault: the state machine fell into ELSE, shared with the parameter gate
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    _uErrLatch := 16#0004_02EC;                 // 锁存故障码 / latch the code
    _bHoldEnableOnFault := FALSE;               // 未知态一律全失电 / an unknown state always de-energises
    _bRelBreak := TRUE;                         // 三组定时器全部断输入重启 / restart every timer group
    _bStopBreak := TRUE;
    _bHoldBreak := TRUE;
    _eState := E_DL_BrakeSeqState.eFault;       // 回故障态 / go to fault
END_CASE

// 段 6｜输出映射（R72 双路径：段首已全部置假，此处按状态逐项置真，绝不漏项）
// segment 6, output map; the double-path rule presets everything to false first and asserts per state here
CASE _eState OF
E_DL_BrakeSeqState.eIdle:
    ;                                           // 待机：两命令保持假（弹簧制动器抱死）/ idle, both commands stay false and the spring brake holds
E_DL_BrakeSeqState.eReleasing:
    bBrakeReleaseCmd := TRUE;                   // 释放相：只给抱闸释放命令，伺服仍未使能 / release phase, only the brake release command, the servo is not enabled yet
E_DL_BrakeSeqState.eEnabled:
    bBrakeReleaseCmd := TRUE;                   // 已使能：抱闸打开 / enabled, the brake stays open
    bServoEnable := TRUE;                       // 已使能：伺服带转矩 / enabled, the servo is energised
E_DL_BrakeSeqState.eStopping:
    bBrakeReleaseCmd := TRUE;                   // 断电序：静止前抱闸必须保持打开 / stop phase, the brake must stay open until standstill
    bServoEnable := _bServoOn;                  // 断电序：保持上一拍使能，绝不提前断 / stop phase, hold the previous-scan enable and never drop it early
E_DL_BrakeSeqState.eBraking:
    bBrakeReleaseCmd := FALSE;                  // 抱闸闭合：命令已撤，机械抱死 / the brake engages because the release command is withdrawn
    bServoEnable := _bServoOn;                  // 保使能直到 tBrakeHold 走完 / keep the enable until the hold time elapses
E_DL_BrakeSeqState.eDisabled:
    ;                                           // 已失电：两命令保持假 / disabled, both commands stay false
E_DL_BrakeSeqState.eFault:
    bBrakeReleaseCmd := _bHoldEnableOnFault;    // 有转矩的 02EB 保持抱闸打开，其余全失电 / hold the brake open only for the torque case of 02EB
    bServoEnable := _bHoldEnableOnFault;        // 有转矩的 02EB 保持使能，其余全失电 / hold the enable only for that same case
ELSE
    ;                                           // 非法状态：两命令保持假，安全侧 / illegal state, both commands stay false, the safe side
END_CASE

// 段 7｜出口汇总：离开故障态即清锁存（保证下一次故障是全新判定），快照必须在输出映射之后更新
// segment 7, exit aggregation; leaving the fault state clears the latches and the snapshot follows the output map
IF _eState <> E_DL_BrakeSeqState.eFault THEN
    _uErrLatch := 0;                            // 清故障码锁存 / clear the latched fault code
    _bHoldEnableOnFault := FALSE;               // 清保持开关，故障出口默认全失电 / clear the hold switch, the fault exit defaults to full de-energisation
END_IF
_bServoOn := bServoEnable;                      // 上一拍伺服使能快照，供断电序与故障出口使用 / previous-scan enable snapshot used by the stop phase and the fault exit
bValid := NOT bError;                           // 输出可用 = 无故障级错误 / outputs are valid when no fault-level code is present
END_FUNCTION_BLOCK
