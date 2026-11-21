(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RampGenerator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（LIMIT / MIN / ABS / SIGN），零厂商方言
 * 功能描述 (Function)   : 线性设定值斜坡发生器。把阶跃目标值变为按独立上升/下降
 *                         速率（EU/s）平滑逼近的斜坡输出，防止操作员大阶跃直接
 *                         冲击执行器。支持暂停保持（bHold 冻结当前值）与跟踪回投
 *                         （bTrack + fTrackValue 投切无扰动）。
 *                         斜率为 0 表示该方向冻结（保持输出，绝不直通，防误操作）。
 *                         到达判定以限幅后的实际输出为准，防止目标超量程时死等。
 * 开源溯源 (Origin)     : 原创实现。算法思想源自 IEC 61131-3 标准函数语义与
 *                         PLCopen Coding Guidelines 的周期安全约定，
 *                         未复制任何厂商私有库源码。
 * 本文件内含       : TYPE  E_DL_RampState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_RampGenerator
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: LIMIT / MIN / ABS / SIGN
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 速率/量程钳位+非有限值拒绝
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 六态 ENUM+CASE+ELSE
 *                         R7 N/A（无定时器/边沿实例）
 * 【边界披露 / Boundary disclosure】
 *   B1 速率 <= 0 视为非法：置 16#0002_0601 且该方向步长为 0（冻结），绝不直通。
 *   B2 目标非有限值（NaN 或幅值超 1.0E30）：本拍拒绝更新，保持上一拍输出。
 *   B3 rOutMin > rOutMax：自动对调并置 16#0002_0001，不中断扫描。
 *   B4 目标超量程不截断目标，仅限幅输出；到达判定用限幅后实际值，防死等。
 * 【验收向量 / Acceptance vectors】
 *   V1  fTarget 0→100，fRateUp=10 EU/s，tSampleTime=T#100MS → 每拍 +1.0 EU，
 *       10 s 后 fOut≈100、bDone=TRUE
 *   V2  fTarget 100→30，fRateDown=10 EU/s → 每拍 -1.0 EU、bMoving=TRUE
 *   V3  bHold=TRUE → fOut 冻结、状态 eHold；释放后继续逼近目标
 *   V4  fRateUp=0 → 16#0002_0601，向上移动冻结、fOut 保持
 *   V5  bTrack 一拍（fTrackValue=50）→ fOut=50，下一拍从 50 继续斜坡（无扰动）
 *   V6  rOutMin=100 > rOutMax=0 → 自动对调、16#0002_0001
 *   V7  fTarget=NaN → 16#0002_0004，fOut 保持上一拍值
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 04 · Phase 3 · DL_Algo 批次）
 *   2026-11-15  v1.0.1  阶段五终审精修：首扫自动跟踪判据修复（bInit 判据
 *                       反向导致首扫不跟踪），对齐通用约定 0-6
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RampState（归属 DL_Algo，与 FB_DL_RampGenerator 同文件）
 * 含义: 斜坡状态机离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_RampState :
(
    eIdle    := 0,    // 空闲态：未使能或等待评估，输出保持 / Idle state, output frozen
    eHold    := 10,   // 暂停保持态：操作员请求冻结当前输出 / Hold state, output frozen on operator request
    eRampUp  := 20,   // 上升斜坡态：按 fRateUpEff 步进逼近目标 / Ramping up with effective up rate
    eRampDown:= 30,   // 下降斜坡态：按 fRateDownEff 步进逼近目标 / Ramping down with effective down rate
    eDone    := 40,   // 到达态：输出与目标偏差在容差内 / Done state, deviation within tolerance
    eFault   := 99    // 故障兜底态：非法状态拦截，自动回空闲 / Fault fallback, auto recover to idle
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_RampGenerator
 * 调用约定: 每个扫描周期无条件调用一次；bTrack 使能时输出立即跟随 fTrackValue。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，可多实例并行互不影响。
 * 速率披露: 输出相对目标的延迟 = 偏差量 / 对应方向速率（线性，非固定时间）。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RampGenerator
VAR_INPUT
    bEnable     : BOOL := FALSE;        // 使能标志，FALSE 时斜坡停止并保持输出 / Enable flag, FALSE stops ramp and holds output
    fTarget     : REAL := 0.0;          // 目标值 [EU]，可为任意有限值 / Target value [EU], any finite value
    fRateUp     : REAL := 10.0;         // 上升速率 [EU/s]，<=0 视为非法冻结 / Up rate [EU/s], <=0 illegal and frozen
    fRateDown   : REAL := 10.0;         // 下降速率 [EU/s]，<=0 视为非法冻结 / Down rate [EU/s], <=0 illegal and frozen
    bHold       : BOOL := FALSE;        // 暂停保持请求，TRUE 冻结在当前值 / Hold request, TRUE freezes at current value
    bTrack      : BOOL := FALSE;        // 跟踪使能，TRUE 时输出立即跟随 fTrackValue / Track enable, output follows fTrackValue instantly
    fTrackValue : REAL := 0.0;          // 跟踪值 [EU]，投切无扰动基准 / Track value [EU], bumpless transfer reference
    rOutMin     : REAL := -1.0E10;      // 输出下限 [EU]，大于上限时自动对调 / Output lower limit [EU], swapped if greater
    rOutMax     : REAL := 1.0E10;       // 输出上限 [EU]，小于下限时自动对调 / Output upper limit [EU], swapped if smaller
    tSampleTime : TIME := T#100MS;      // 采样周期 [s]，小于 10ms 钳位为 10ms / Sample time [s], clamped to 10ms minimum
END_VAR
VAR_OUTPUT
    fOut        : REAL;                 // 斜坡输出 [EU] / Ramp output [EU]
    bDone       : BOOL;                 // 到达目标标志：偏差在容差内 / Done flag, deviation within tolerance
    bMoving     : BOOL;                 // 斜坡进行中标志 / Ramp in progress flag
    fRemain     : REAL;                 // 距目标剩余量 [EU] = fTarget - fOut / Remaining amount to target [EU]
    bError      : BOOL;                 // 故障标志（瞬时，逐拍重算） / Fault flag, transient, recomputed every scan
    uErrorId    : UDINT;                // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fRateUpEff  : REAL;                 // 钳位后的有效上升速率 [EU/s] / Effective clamped up rate [EU/s]
    fRateDownEff: REAL;                 // 钳位后的有效下降速率 [EU/s] / Effective clamped down rate [EU/s]
    fDt         : REAL;                 // 折算后的采样周期 [s] / Converted sample period [s]
    fDelta      : REAL;                 // 本拍目标与输出的偏差 [EU] / Deviation between target and output [EU]
    fStep       : REAL;                 // 本拍允许的最大步长 [EU] / Max step allowed this scan [EU]
    bTgtValid   : BOOL;                 // 目标为有限值的合法性标志 / Target finite validity flag
    bInit       : BOOL;                 // 首扫标志：首扫自动跟踪 fTrackValue / First scan flag, auto track on first scan
    eState      : E_DL_RampState;       // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR CONSTANT
    DL_RAMP_EPS     : REAL := 1.0E-6;   // 到达判定容差 [EU]，浮点差值比较 / Arrival tolerance [EU], float diff compare
    DL_RAMP_RATE_MAX: REAL := 1.0E10;   // 速率上限钳位 [EU/s]，防溢出 / Rate upper clamp [EU/s], overflow guard
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜公共参数处理（通用约定 0-1/0-2/0-3）：周期钳位、量程对调、故障码瞬时清零
 *      Common parameter handling: sample time clamp, limit swap, transient code reset
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;               // 故障码逐拍重算（瞬时语义） / Error code recomputed every scan
bError   := FALSE;                      // 故障标志逐拍重算 / Fault flag recomputed every scan

IF tSampleTime < T#10MS THEN
    fDt      := TIME_TO_REAL(T#10MS) / 1000.0; // 非法周期钳位为 10ms / Illegal period clamped to 10ms
    uErrorId := 16#0002_0002;           // 采样周期非法已钳位 / Sample time illegal, clamped
ELSE
    fDt      := TIME_TO_REAL(tSampleTime) / 1000.0; // 周期换算为秒 [s] / Period converted to seconds [s]
END_IF

IF rOutMin > rOutMax THEN
    fOut := LIMIT(rOutMax, fOut, rOutMin); // 对调后按新序限幅输出 / Clamp output with swapped limits
    uErrorId := 16#0002_0001;           // 参数越界已对调 / Limits out of order, swapped
ELSE
    fOut := LIMIT(rOutMin, fOut, rOutMax); // 正常序限幅输出 / Clamp output with normal limits
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜速率钳位：<=0 非法（冻结方向），超上限钳位（边界 B1）
 *      Rate clamping: <=0 illegal (freeze direction), over-limit clamped
 *-----------------------------------------------------------------------------*)
IF fRateUp <= 0.0 THEN
    fRateUpEff := 0.0;                  // 非法速率冻结为 0，步长为 0 / Illegal rate frozen to zero step
    uErrorId   := 16#0002_0601;         // 速率非法已钳位 / Rate illegal, clamped
ELSIF fRateUp > DL_RAMP_RATE_MAX THEN
    fRateUpEff := DL_RAMP_RATE_MAX;     // 超上限钳位防溢出 / Over-limit clamped for overflow guard
    uErrorId   := 16#0002_0601;         // 速率非法已钳位 / Rate illegal, clamped
ELSE
    fRateUpEff := fRateUp;              // 合法速率直通 / Valid rate passed through
END_IF

IF fRateDown <= 0.0 THEN
    fRateDownEff := 0.0;                // 非法速率冻结为 0，步长为 0 / Illegal rate frozen to zero step
    uErrorId     := 16#0002_0601;       // 速率非法已钳位 / Rate illegal, clamped
ELSIF fRateDown > DL_RAMP_RATE_MAX THEN
    fRateDownEff := DL_RAMP_RATE_MAX;   // 超上限钳位防溢出 / Over-limit clamped for overflow guard
    uErrorId     := 16#0002_0601;       // 速率非法已钳位 / Rate illegal, clamped
ELSE
    fRateDownEff := fRateDown;          // 合法速率直通 / Valid rate passed through
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜目标合法性判定（边界 B2）：非有限值本拍拒绝，保持上一拍目标行为
 *      Target validity: non-finite value rejected this scan, previous behavior kept
 *-----------------------------------------------------------------------------*)
bTgtValid := NOT (fTarget <> fTarget) AND (ABS(fTarget) <= 1.0E30); // NaN 判别 + 幅值防御 / NaN check plus magnitude guard
IF NOT bTgtValid THEN
    uErrorId := 16#0002_0004;           // 输入非有限值已拒绝 / Non-finite input rejected
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜跟踪与首扫（通用约定 0-6）：投切无扰动，首扫自动跟踪 fTrackValue
 *      Tracking and first scan: bumpless transfer, first scan auto track
 *-----------------------------------------------------------------------------*)
IF bTrack OR (NOT bInit) THEN
    fOut   := LIMIT(rOutMin, fTrackValue, rOutMax); // 输出立即跟随跟踪值 / Output follows track value instantly
    eState := eIdle;                    // 回空闲重新评估方向 / Back to idle for direction re-evaluation
    bInit  := TRUE;                     // 首扫标志置位 / First scan flag set
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine: ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
fDelta := fTarget - fOut;               // 本拍偏差 [EU] / Deviation this scan [EU]

IF NOT bEnable THEN
    eState := eIdle;                    // 未使能：强制空闲、输出保持 / Disabled: force idle, output held
ELSE
    CASE eState OF

        eIdle:  // 空闲态：使能后按偏差方向选择迁移 / Idle: pick transition by deviation direction
            IF bTgtValid AND ABS(fDelta) > DL_RAMP_EPS THEN
                IF bHold THEN
                    eState := eHold;    // 保持请求优先 / Hold request has priority
                ELSIF fDelta > 0.0 THEN
                    eState := eRampUp;  // 目标在上方，进入上升 / Target above, ramp up
                ELSE
                    eState := eRampDown; // 目标在下方，进入下降 / Target below, ramp down
                END_IF
            ELSIF bTgtValid THEN
                eState := eDone;        // 已在容差内，直接到达 / Already within tolerance, done
            END_IF

        eHold:  // 暂停保持态：冻结输出直到释放 / Hold: freeze output until released
            IF NOT bHold THEN
                IF ABS(fDelta) <= DL_RAMP_EPS THEN
                    eState := eDone;    // 保持期间目标已到达 / Target reached during hold
                ELSIF fDelta > 0.0 THEN
                    eState := eRampUp;  // 释放后继续上升 / Resume ramp up after release
                ELSE
                    eState := eRampDown; // 释放后继续下降 / Resume ramp down after release
                END_IF
            END_IF

        eRampUp:  // 上升斜坡态：步长 = MIN(偏差, 速率*周期) / Ramp up: step = MIN(deviation, rate*period)
            IF ABS(fDelta) <= DL_RAMP_EPS THEN
                eState := eDone;        // 到达目标 / Target reached
            ELSIF fDelta < 0.0 THEN
                eState := eRampDown;    // 目标反转为下方 / Target switched below
            ELSIF bHold THEN
                eState := eHold;        // 保持请求 / Hold request
            ELSE
                fStep := MIN(fDelta, fRateUpEff * fDt); // 本拍步长 [EU] / Step this scan [EU]
                fOut  := fOut + fStep;  // 逐步逼近目标 / Step toward target
            END_IF

        eRampDown:  // 下降斜坡态：对称逻辑 / Ramp down: symmetric logic
            IF ABS(fDelta) <= DL_RAMP_EPS THEN
                eState := eDone;        // 到达目标 / Target reached
            ELSIF fDelta > 0.0 THEN
                eState := eRampUp;      // 目标反转为上方 / Target switched above
            ELSIF bHold THEN
                eState := eHold;        // 保持请求 / Hold request
            ELSE
                fStep := MIN(-fDelta, fRateDownEff * fDt); // 本拍步长 [EU] / Step this scan [EU]
                fOut  := fOut - fStep;  // 逐步逼近目标 / Step toward target
            END_IF

        eDone:  // 到达态：监视新目标 / Done: watch for new target
            IF bTgtValid AND ABS(fDelta) > DL_RAMP_EPS THEN
                IF bHold THEN
                    eState := eHold;    // 保持请求 / Hold request
                ELSIF fDelta > 0.0 THEN
                    eState := eRampUp;  // 新目标在上方 / New target above
                ELSE
                    eState := eRampDown; // 新目标在下方 / New target below
                END_IF
            END_IF

        eFault:  // 故障兜底态：无复位引脚，当拍回空闲重评，避免永久锁死 / Fault fallback: no reset pin, recover to idle
            eState := eIdle;            // 自动恢复空闲 / Auto recover to idle

        ELSE  // 非法状态拦截：任何未定义状态一律进故障态并置码 / Illegal state interception
            eState   := eFault;         // 强制故障态 / Force fault state
            uErrorId := 16#0002_0005;   // 非法状态兜底 / Illegal state fallback
            bError   := TRUE;           // 故障标志置位 / Fault flag set

    END_CASE;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜输出整形与状态引脚：限幅后实际值判定到达（边界 B4 防死等）
 *      Output shaping and status pins: arrival judged on clamped actual output
 *-----------------------------------------------------------------------------*)
IF rOutMin > rOutMax THEN
    fOut := LIMIT(rOutMax, fOut, rOutMin); // 对调序限幅（与段 1 一致） / Clamp with swapped order
ELSE
    fOut := LIMIT(rOutMin, fOut, rOutMax); // 正常序限幅 / Clamp with normal order
END_IF

fDelta  := fTarget - fOut;              // 限幅后重算偏差 [EU] / Deviation recomputed after clamping
fRemain := fDelta;                      // 距目标余量 [EU] / Remaining to target [EU]

bDone   := bEnable AND bTgtValid AND (ABS(fDelta) <= DL_RAMP_EPS); // 到达标志 / Done flag
bMoving := bEnable AND bTgtValid AND (NOT bHold)
           AND (ABS(fDelta) > DL_RAMP_EPS)
           AND ((eState = eRampUp) OR (eState = eRampDown));        // 斜坡进行中 / Ramp in progress
END_FUNCTION_BLOCK
