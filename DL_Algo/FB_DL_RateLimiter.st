(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RateLimiter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 数学运算，零库依赖，零厂商方言
 * 功能描述 (Function)   : 变化率限制器（对应变化率限制语义）。输入阶跃时输出
 *                         以最大速率跟随，保护加热元件 / 执行器免受给定值阶跃
 *                         冲击；上升与下降速率独立可调，速率为 0 表示该方向不
 *                         限速直通（沿测量库惯例），负值非法按 0 处理并置码；
 *                         支持跟踪回投与限速进行中标志。
 * 开源溯源 (Origin)     : 原创实现。功能分类与参数域参考测量函数库中变化率
 *                         限制单元的公开语义描述，未复制任何厂商源码，
 *                         clean-room 重写。
 * 本文件内含       : TYPE  E_DL_RateState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_RateLimiter
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 无实例依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+非有限值防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM+CASE+ELSE
 *                         R7 ✓ 本块无定时器 / 边沿实例（无可刷新项，天然合规）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 04 · Level 1 DL_Algo
 * 验收向量 (Acceptance) :
 *   V1 上升限速：fRateUp=10 EU/s, 输入阶跃 +100 → 输出每拍 +1 EU（100 ms 周期）
 *   V2 下降限速：fRateDown=5 EU/s, 输入阶跃 -100 → 输出每拍 -0.5 EU
 *   V3 零速率直通：fRateUp=0 → 上升方向立即跟随输入
 *   V4 到达直通：输出追上输入后 bLimiting=FALSE 且输出等于输入
 *   V5 跟踪：bTrack 置位 → 输出立即等于 fTrackValue
 *   V6 非有限值：输入写非法浮点 → 输出保持上一拍且码 0002_0004
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RateState（归属 DL_Algo，与 FB_DL_RateLimiter 同文件）
 * 含义: 变化率限制离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_RateState :
(
    eIdle      := 0,   // 使能关：输出直通输入 / Idle: enable off, output follows input
    eFollow    := 10,  // 不限速直通：两方向均无需限速 / Follow: no rate limit needed in either direction
    eLimitUp   := 20,  // 上升限速：输出按最大上升速率逼近 / Limit up: output approaches at max rise rate
    eLimitDown := 30,  // 下降限速：输出按最大下降速率逼近 / Limit down: output approaches at max fall rate
    eFault     := 99   // 故障兜底态：非法状态进入，输出保持 / Fault fallback: illegal state, output held
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_RateLimiter
 * 调用约定: 每个扫描周期无条件调用一次；采样周期引脚按子库通用约定配置。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 工程披露: 输出变量自身即斜坡历史状态，不另设历史缓冲；实际变化率按本拍
 *           输出增量除以采样周期计算，供 HMI 趋势与诊断。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RateLimiter
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 总使能，FALSE 时输出直通输入 / Master enable, FALSE passes input through
    fIn         : REAL := 0.0;        // 输入信号 [EU] / Input signal in engineering units
    fRateUp     : REAL := 0.0;        // 最大上升速率 [EU/s]，0 = 不限 / Max rising rate, 0 = unlimited
    fRateDown   : REAL := 0.0;        // 最大下降速率 [EU/s]，0 = 不限 / Max falling rate, 0 = unlimited
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时输出立即跟随跟踪值 / Track enable, output follows track value
    fTrackValue : REAL := 0.0;        // 跟踪值 [EU]，用于无扰投切 / Track value for bumpless transfer
    tSampleTime : TIME := T#100MS;    // 采样周期，按子库通用约定 / Sample period per sublibrary convention
END_VAR
VAR_OUTPUT
    fOut        : REAL;               // 限速后输出 [EU] / Rate-limited output in engineering units
    bLimiting   : BOOL;               // 限速进行中标志 / Rate limiting in progress flag
    fRateActual : REAL;               // 本拍实际变化率 [EU/s] / Actual rate of change this cycle
    bError      : BOOL;               // 故障标志 / Fault flag
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    eState      : E_DL_RateState;     // 主状态机当前状态 / Current state of the state machine
    bInit       : BOOL := FALSE;      // 首扫初始化标志 / First-scan init flag
    fDt         : REAL;               // 生效采样周期 [s] / Effective sample period in seconds
    fRateUpEff  : REAL;               // 钳位后的有效上升速率 [EU/s] / Clamped effective rise rate
    fRateDownEff: REAL;               // 钳位后的有效下降速率 [EU/s] / Clamped effective fall rate
    fDelta      : REAL;               // 输入与输出的差值 [EU] / Difference between input and output
    fStepMax    : REAL;               // 本拍允许的最大步进 [EU] / Maximum allowed step this cycle
    fStepApply  : REAL;               // 本拍实际施加步进 [EU] / Actually applied step this cycle
    fOutBefore  : REAL;               // 本拍更新前的输出 [EU] / Output before this cycle update
    bNonFinite  : BOOL;               // 本拍输入非有限值标志 / Non-finite input flag of this cycle
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位与公共防御（不中断扫描）
 *      Parameter clamping and common defenses, never stops the scan
 *-----------------------------------------------------------------------------*)
bError   := FALSE;                    // 每拍重算故障标志 / Recompute fault flag every cycle
uErrorId := 16#0002_0000;             // 每拍重算故障码 / Recompute error code every cycle
bLimiting := FALSE;                   // 限速标志每拍重算 / Limiting flag recomputed every cycle
bNonFinite := FALSE;                  // 非有限值标志每拍重算 / Non-finite flag recomputed every cycle

IF tSampleTime < T#10MS THEN
    fDt := 0.01;                      // 采样周期非法钳位为 0.01 s / Illegal sample period clamped to 0.01 s
    uErrorId := 16#0002_0002;         // 公共码：采样周期已钳位 / Common code: sample period clamped
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;  // 采样周期换算为秒 [s] / Sample period in seconds
END_IF

(* 速率防御：负值非法按 0（不限速）处理并置码，正值直通 *)
(* Rate defense: negative treated as 0 (unlimited) with code, positive passed *)
IF fRateUp < 0.0 THEN
    fRateUpEff := 0.0;                // 负上升速率按 0 处理 / Negative rise rate treated as zero
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fRateUpEff := fRateUp;            // 合法上升速率直通 / Valid rise rate passed
END_IF
IF fRateDown < 0.0 THEN
    fRateDownEff := 0.0;              // 负下降速率按 0 处理 / Negative fall rate treated as zero
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fRateDownEff := fRateDown;        // 合法下降速率直通 / Valid fall rate passed
END_IF

(* 输入非有限值防御：非法浮点拒绝本拍更新，保持上一拍输出 *)
(* Non-finite defense: reject this cycle, hold previous output *)
IF (fIn <> fIn) OR (ABS(fIn) > 1.0E30)
   OR (fTrackValue <> fTrackValue) OR (ABS(fTrackValue) > 1.0E30) THEN
    bNonFinite := TRUE;               // 置非有限值标志 / Set non-finite flag
    bError   := TRUE;                 // 置故障标志 / Set fault flag
    uErrorId := 16#0002_0004;         // 公共码：输入非有限值已拒绝 / Common code: non-finite rejected
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜早退：使能关 / 非有限值 / 跟踪，输出直通或保持，状态机旁路
 *      Early exits: disable, non-finite, track; output passes or holds
 *-----------------------------------------------------------------------------*)
IF bNonFinite THEN
    RETURN;                           // 保持上一拍输出与状态 / Hold previous output and state
END_IF

IF NOT bEnable THEN
    eState := eIdle;                  // 强制回空闲态 / Force idle state
    fOut   := fIn;                    // 输出直通输入 / Output passes input through
    fRateActual := 0.0;               // 直通拍变化率为 0 / Zero rate on pass-through cycle
    bInit  := FALSE;                  // 复位首扫标志以便重使能时同步 / Reset init flag for resync
    RETURN;                           // 本拍结束 / End of this cycle
END_IF

IF bTrack OR (NOT bInit) THEN
    (* 跟踪回投 / 首扫初始化：输出立即同步，杜绝上电阶跃冲击 *)
    (* Track / first-scan init: output synchronized immediately, no power-up step *)
    IF bTrack THEN
        fOut := fTrackValue;          // 输出立即跟随跟踪值 / Output follows track value
    ELSE
        fOut := fIn;                  // 首扫输出直通输入 / First-scan output passes input
    END_IF
    eState := eFollow;                // 状态回直通态 / State back to follow
    fRateActual := 0.0;               // 同步拍变化率为 0 / Zero rate on sync cycle
    bInit  := TRUE;                   // 置首扫完成标志 / Set first-scan done flag
    RETURN;                           // 本拍结束 / End of this cycle
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜限速需求判定：差值方向与有效速率共同决定本拍状态
 *      Limit demand: direction and effective rates decide this cycle state
 *-----------------------------------------------------------------------------*)
fDelta := fIn - fOut;                 // 输入与输出差值 [EU] / Input minus output difference
fOutBefore := fOut;                   // 记录更新前输出用于变化率计算 / Record output before update

IF fDelta > 0.0 THEN
    (* 上升需求：速率 0 直通，否则按最大上升步进逼近 *)
    (* Rise demand: zero rate passes through, else approach at max rise step *)
    IF fRateUpEff > 0.0 THEN
        eState := eLimitUp;           // 进上升限速态 / Enter rise-limit state
    ELSE
        eState := eFollow;            // 不限速直通 / Unlimited follow
    END_IF
ELSIF fDelta < 0.0 THEN
    (* 下降需求：速率 0 直通，否则按最大下降步进逼近 *)
    (* Fall demand: zero rate passes through, else approach at max fall step *)
    IF fRateDownEff > 0.0 THEN
        eState := eLimitDown;         // 进下降限速态 / Enter fall-limit state
    ELSE
        eState := eFollow;            // 不限速直通 / Unlimited follow
    END_IF
ELSE
    eState := eFollow;                // 已到达：直通 / Reached: follow
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine: ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eState OF

    eIdle:
        (* 空闲态已在早退段处理；本分支仅做迁移防御 *)
        (* Idle handled in early exit; this branch only guards transfers *)
        fOut := fIn;                  // 直通输出 / Pass-through output
        fRateActual := 0.0;           // 变化率为 0 / Zero rate

    eFollow:
        (* 不限速直通：输出立即等于输入 *)
        (* Unlimited follow: output equals input immediately *)
        fOut := fIn;                  // 直通输出 / Pass-through output
        fRateActual := fDelta / fDt;  // 本拍实际变化率 [EU/s] / Actual rate this cycle

    eLimitUp:
        (* 上升限速：步进 = MIN(|差值|, 速率*dt)，方向取差值符号 *)
        (* Rise limit: step = MIN(|delta|, rate*dt) in delta direction *)
        fStepMax   := fRateUpEff * fDt;                             // 最大步进 [EU] / Maximum step
        fStepApply := MIN(ABS(fDelta), fStepMax) * 1.0;             // 施加步进 [EU] / Applied step
        fOut       := fOutBefore + fStepApply;                      // 输出推进 / Output advanced
        bLimiting  := (ABS(fDelta) > fStepMax);                     // 限速进行中 / Limiting in progress
        fRateActual := fStepApply / fDt;                            // 本拍实际变化率 / Actual rate this cycle

    eLimitDown:
        (* 下降限速：步进取负方向 *)
        (* Fall limit: step taken in negative direction *)
        fStepMax   := fRateDownEff * fDt;                           // 最大步进 [EU] / Maximum step
        fStepApply := MIN(ABS(fDelta), fStepMax) * (-1.0);          // 施加步进 [EU] / Applied step
        fOut       := fOutBefore + fStepApply;                      // 输出推进 / Output advanced
        bLimiting  := (ABS(fDelta) > fStepMax);                     // 限速进行中 / Limiting in progress
        fRateActual := fStepApply / fDt;                            // 本拍实际变化率 / Actual rate this cycle

    eFault:
        (* 故障兜底态：输出保持上一拍值 *)
        (* Fault fallback: output holds previous value *)
        fOut := fOutBefore;           // 输出保持 / Output held
        fRateActual := 0.0;           // 变化率为 0 / Zero rate

    ELSE
        (* 非法状态拦截：任何未定义状态一律进故障兜底，不做隐式恢复 *)
        (* Illegal state interception: any undefined state goes to fault fallback *)
        eState   := eFault;           // 进故障态 / Enter fault state
        bError   := TRUE;             // 置故障标志 / Set fault flag
        uErrorId := 16#0002_0005;     // 非法状态兜底码 / Illegal state fallback code
        fOut     := fOutBefore;       // 输出保持 / Output held
        fRateActual := 0.0;           // 变化率为 0 / Zero rate
END_CASE;
END_FUNCTION_BLOCK
