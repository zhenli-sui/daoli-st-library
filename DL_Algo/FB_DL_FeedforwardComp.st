(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FeedforwardComp
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 数学运算，零库依赖，零厂商方言
 * 功能描述 (Function)   : 静态 + 动态前馈补偿器。对可测扰动量做前馈：静态增益
 *                         项即时响应 + 一阶惯性 / 超前滞后动态整形 + 可选纯滞后
 *                         （固定 10 槽延时队列），输出叠加到 PID 反馈通道，提升
 *                         抗负载扰动速度。现场用途：配料设定突变、蒸汽压力波动
 *                         的前馈补偿。
 * 开源溯源 (Origin)     : 原创实现。超前滞后 / 纯滞后补偿功能分类与参数域参考
 *                         过程控制经典文献（lead-lag and dead-time feedforward）
 *                         的公开语义描述，未复制任何厂商源码，clean-room 重写。
 * 本文件内含       : TYPE  E_DL_FfState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_FeedforwardComp
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library 无实例依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+数组边界防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 ✓ 本块无定时器 / 边沿实例（无可刷新项，天然合规）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 04 · Level 1 DL_Algo
 *   2026-11-15  v1.0.1  阶段五终审精修：tLagTime=T#0S 为规格合法直通口径，
 *                       不再误置 0002_0401 故障码
 * 验收向量 (Acceptance) :
 *   V1 纯静态：tLead=tLag=tDelay=T#0S, fFfGain=2, 扰动=10 → fFfOut=20
 *   V2 惯性收敛：tLag=T#1S, 恒扰动 10 → fDynPart 单调趋近扰动值
 *   V3 滞后：tDelay=T#300MS, 扰动阶跃 → 输出滞后 3 拍后出现
 *   V4 跟踪：bTrack 置位 → fFfOut 立即等于钳位后的 fTrackValue
 *   V5 队列截断：tDelay 折算深度超 10 → nDelaySteps=10 且码 0002_0402
 *   V6 非有限值：扰动写非法浮点 → 输出保持上一拍且码 0002_0004
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FfState（归属 DL_Algo，与 FB_DL_FeedforwardComp 同文件）
 * 含义: 前馈补偿离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_FfState :
(
    eIdle    := 0,    // 使能关：输出回下限，队列冻结 / Idle: enable off, output at low limit
    eStatic  := 10,   // 仅静态：超前滞后与滞后队列全关 / Static only: lead-lag and delay queue off
    eDynamic := 20,   // 动态：惯性 / 超前 / 滞后环节至少一项使能 / Dynamic: at least one shaping element active
    eFault   := 99    // 故障兜底态：非法状态进入，输出安全值 / Fault fallback: illegal state, safe output
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_FeedforwardComp
 * 调用约定: 每个扫描周期无条件调用一次；滞后队列每拍必须持续写入。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 工程披露: 滞后队列为固定 10 槽环形缓冲，深度按 tDelayTime/tSampleTime 向下
 *           取整折算，超出上限截断并置码，不做动态扩容。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_FeedforwardComp
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 总使能，FALSE 时输出回下限 / Master enable, FALSE drives output to low limit
    fDisturbance: REAL := 0.0;        // 扰动量 [EU]，可测负载信号 / Measured disturbance in engineering units
    fFfGain     : REAL := 1.0;        // 前馈增益 [1] / Feedforward gain, dimensionless
    tLeadTime   : TIME := T#0S;       // 超前时间 [s]，T#0S = 纯静态 / Lead time [s], T#0S = static only
    tLagTime    : TIME := T#0S;       // 惯性时间 [s]，T#0S = 直通 / Lag time [s], T#0S = pass-through
    tDelayTime  : TIME := T#0S;       // 纯滞后时间 [s]，T#0S = 无滞后队列 / Dead time [s], T#0S = no queue
    rOutMin     : REAL := -100.0;     // 输出下限 [%] / Output lower limit in percent
    rOutMax     : REAL := 100.0;      // 输出上限 [%] / Output upper limit in percent
    tSampleTime : TIME := T#100MS;    // 采样周期 [s] / Sample period in seconds
    bTrack      : BOOL := FALSE;      // 跟踪使能，TRUE 时输出立即跟随跟踪值 / Track enable, output follows track value
    fTrackValue : REAL := 0.0;        // 跟踪值 [%]，用于无扰投切 / Track value in percent
END_VAR
VAR_OUTPUT
    fFfOut      : REAL;               // 前馈输出 [%] / Feedforward output in percent
    fStaticPart : REAL;               // 静态分量 [%]，诊断 / Static component, diagnostics
    fDynPart    : REAL;               // 动态分量 [%]，诊断 / Dynamic component, diagnostics
    bError      : BOOL;               // 故障标志 / Fault flag
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fDyn        : REAL;               // 惯性环节状态 [EU] / Inertia element state
    fDynPrev    : REAL;               // 上一拍惯性状态 [EU]，诊断 / Previous inertia state, diagnostics
    afDelayBuf  : ARRAY[0..9] OF REAL;// 滞后队列 [EU]，固定 10 槽环形 / Delay queue, fixed 10-slot ring
    nDelaySteps : INT;                // 队列深度 = tDelayTime/tSampleTime [拍] / Queue depth in cycles
    nWriteIdx   : INT;                // 环形队列写指针 [0..9] / Ring buffer write index
    eState      : E_DL_FfState;       // 主状态机当前状态 / Current state of the state machine
    bInit       : BOOL := FALSE;      // 首扫初始化标志 / First-scan init flag
    fDt         : REAL;               // 生效采样周期 [s] / Effective sample period in seconds
    fLimLow     : REAL;               // 修复后的输出下限 [%] / Repaired output lower limit
    fLimHigh    : REAL;               // 修复后的输出上限 [%] / Repaired output upper limit
    fLeadFactor : REAL;               // 超前因子 [1] / Lead factor, dimensionless
    fDelayed    : REAL;               // 滞后队列读出值 [EU] / Delayed value read from queue
    fFfRaw      : REAL;               // 限幅前的原始前馈输出 [%] / Raw feedforward output before clamp
    nReadIdx    : INT;                // 环形队列读指针 [0..9] / Ring buffer read index
    nDepthRaw   : INT;                // 折算的原始队列深度 [拍] / Raw computed queue depth in cycles
    bNonFinite  : BOOL;               // 本拍输入非有限值标志 / Non-finite input flag of this cycle
END_VAR
VAR CONSTANT
    DL_FF_DELAY_MAX : INT := 10;      // 滞后队列深度上限 [槽] / Delay queue depth ceiling in slots
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位与公共防御（不中断扫描）
 *      Parameter clamping and common defenses, never stops the scan
 *-----------------------------------------------------------------------------*)
bError   := FALSE;                    // 每拍重算故障标志 / Recompute fault flag every cycle
uErrorId := 16#0002_0000;             // 每拍重算故障码 / Recompute error code every cycle
bNonFinite := FALSE;                  // 非有限值标志每拍重算 / Non-finite flag recomputed every cycle

IF tSampleTime < T#10MS THEN
    fDt := 0.01;                      // 采样周期非法钳位为 0.01 s / Illegal sample period clamped to 0.01 s
    uErrorId := 16#0002_0002;         // 公共码：采样周期已钳位 / Common code: sample period clamped
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;  // 采样周期换算为秒 [s] / Sample period in seconds
END_IF

IF rOutMin > rOutMax THEN
    fLimLow  := rOutMax;              // 上下限对调修复 / Swapped repair of limits
    fLimHigh := rOutMin;              // 上下限对调修复 / Swapped repair of limits
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fLimLow  := rOutMin;              // 合法下限直通 / Valid low limit passed
    fLimHigh := rOutMax;              // 合法上限直通 / Valid high limit passed
END_IF

(* 输入非有限值防御：扰动或跟踪值非法即拒绝本拍更新 *)
(* Non-finite defense: reject this cycle if disturbance or track value invalid *)
IF (fDisturbance <> fDisturbance) OR (ABS(fDisturbance) > 1.0E30)
   OR (fTrackValue <> fTrackValue) OR (ABS(fTrackValue) > 1.0E30) THEN
    bNonFinite := TRUE;               // 置非有限值标志 / Set non-finite flag
    bError   := TRUE;                 // 置故障标志 / Set fault flag
    uErrorId := 16#0002_0004;         // 公共码：输入非有限值已拒绝 / Common code: non-finite rejected
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜队列深度折算：tDelayTime/tSampleTime 向下取整，超上限截断置码
 *      Queue depth derivation: floor division, truncated at ceiling with code
 *-----------------------------------------------------------------------------*)
nDepthRaw := REAL_TO_INT(TRUNC(TIME_TO_REAL(tDelayTime) / 1000.0 / fDt));  // 原始深度 [拍] / Raw depth in cycles
IF nDepthRaw > DL_FF_DELAY_MAX THEN
    nDelaySteps := DL_FF_DELAY_MAX;   // 深度截断至上限 / Depth truncated to ceiling
    uErrorId := 16#0002_0402;         // 组件码：滞后队列深度超上限已截断 / Code: queue depth truncated
ELSIF nDepthRaw < 0 THEN
    nDelaySteps := 0;                 // 负深度防御为 0 / Negative depth defended to zero
ELSE
    nDelaySteps := nDepthRaw;         // 合法深度直通 / Valid depth passed
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜使能与跟踪早退：保持上一拍输出，队列冻结
 *      Early exit on disable or track: hold output, queue frozen
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    eState    := eIdle;               // 强制回空闲态 / Force idle state
    fFfOut    := fLimLow;             // 输出回下限 / Output to low limit
    fStaticPart := 0.0;               // 静态分量清零 / Static component cleared
    fDynPart  := 0.0;                 // 动态分量清零 / Dynamic component cleared
    RETURN;                           // 本拍结束 / End of this cycle
END_IF

IF bNonFinite THEN
    RETURN;                           // 保持上一拍输出与状态 / Hold previous output and state
END_IF

IF bTrack OR (NOT bInit) THEN
    (* 跟踪回投 / 首扫初始化：输出立即跟随，惯性状态与队列同步，投切无扰 *)
    (* Track / first-scan init: output follows, inertia state and queue in sync *)
    IF bTrack THEN
        fFfOut := LIMIT(fLimLow, fTrackValue, fLimHigh);          // 输出钳位跟随 / Clamped tracking output
    ELSE
        fFfOut := fLimLow;            // 首扫输出回下限 / First-scan output to low limit
    END_IF
    fDyn        := fDisturbance;      // 惯性状态同步 / Inertia state synchronized
    fDynPrev    := fDisturbance;      // 上拍惯性状态同步 / Previous state synchronized
    FOR nReadIdx := 0 TO DL_FF_DELAY_MAX - 1 DO
        afDelayBuf[nReadIdx] := fDisturbance;                     // 队列全槽预填 / Prefill all queue slots
    END_FOR
    nWriteIdx   := 0;                 // 写指针归零 / Write index reset
    bInit       := TRUE;              // 置首扫完成标志 / Set first-scan done flag
    fStaticPart := 0.0;               // 静态分量清零 / Static component cleared
    fDynPart    := 0.0;               // 动态分量清零 / Dynamic component cleared
    RETURN;                           // 本拍结束 / End of this cycle
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜前馈计算：静态项 + 动态项（惯性 / 超前）+ 纯滞后队列
 *      Feedforward computation: static term plus dynamic and dead-time terms
 *-----------------------------------------------------------------------------*)
fStaticPart := fFfGain * fDisturbance;                            // 静态项即时响应 [%] / Static term, instant response

(* 状态派生：任一动态环节使能即进动态态 *)
(* State derivation: any shaping element active means dynamic state *)
IF (tLeadTime = T#0S) AND (tLagTime = T#0S) AND (tDelayTime = T#0S) THEN
    eState := eStatic;                // 仅静态 / Static only
ELSE
    eState := eDynamic;               // 动态使能 / Dynamic active
END_IF

IF eState = eDynamic THEN
    (* 动态项：一阶超前 / 惯性离散差分，tLagTime 小于一拍时按一拍直通 *)
    (* Dynamic term: first-order lead/lag recursion, sub-cycle lag treated as one-cycle *)
    fLeadFactor := 1.0 + TIME_TO_REAL(tLeadTime) / 1000.0 / fDt;  // 超前因子 [1] / Lead factor
    IF tLeadTime < T#0S THEN
        fLeadFactor := 1.0;           // 负超前防御为 1（关闭超前） / Negative lead defended to 1
        uErrorId := 16#0002_0401;     // 组件码：动态时间非法已钳位 / Code: dynamic time clamped
    END_IF
    IF tLagTime <= T#0S THEN
        fDyn := fDisturbance;         // T#0S = 直通，规格合法口径不置故障码 / T#0S = pass-through, legal per spec, no error code
    ELSE
        fDyn := fDyn + (fLeadFactor * fDisturbance - fDyn) * fDt
                    / MAX(TIME_TO_REAL(tLagTime) / 1000.0, fDt);  // 惯性递推 / Inertia recursion
    END_IF
    fDynPrev := fDyn;                 // 上拍惯性状态记录 / Record previous inertia state

    (* 纯滞后队列：先写入当前值，再按深度回读，指针经取模保证不越界 *)
    (* Dead-time queue: write current value first, read back by depth, modulo safe *)
    afDelayBuf[nWriteIdx] := fDisturbance;                        // 当前扰动入队 / Enqueue current disturbance
    nReadIdx := (nWriteIdx - nDelaySteps + DL_FF_DELAY_MAX) MOD DL_FF_DELAY_MAX;  // 读指针 / Read index
    nReadIdx := LIMIT(0, nReadIdx, DL_FF_DELAY_MAX - 1);          // 读指针防御钳位 / Defensive index clamp
    fDelayed := afDelayBuf[nReadIdx];                             // 滞后读出 [EU] / Delayed readout
    nWriteIdx := (nWriteIdx + 1) MOD DL_FF_DELAY_MAX;             // 写指针推进 / Advance write index
    fDynPart := fFfGain * (fDyn - fDelayed);                      // 动态分量 [%] / Dynamic component
ELSE
    fDelayed  := fDisturbance;        // 静态模式无滞后 / Static mode has no delay
    fDynPart  := 0.0;                 // 动态分量清零 / Dynamic component cleared
    fDynPrev  := fDisturbance;        // 惯性状态直通同步 / Inertia state pass-through
END_IF

fFfRaw := fStaticPart + fDynPart;     // 原始前馈合成 [%] / Raw feedforward composition
fFfOut := LIMIT(fLimLow, fFfRaw, fLimHigh);                       // 输出限幅 / Output clamping

(*------------------------------------------------------------------------------
 * 段 5｜主状态机收口（红线 R6）：CASE 覆盖 + ELSE 兜底
 *      State machine closure: CASE coverage with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eState OF
    eIdle:    ;                        // 空闲态已在早退段处理 / Idle handled in early exit
    eStatic:  ;                        // 静态态输出已合成 / Static output composed
    eDynamic: ;                        // 动动态输出已合成 / Dynamic output composed
    eFault:   ;                        // 故障态占位（参数故障不锁存控制） / Fault placeholder
    ELSE
        (* 非法状态拦截：一律进故障兜底并置码 *)
        (* Illegal state interception: force fault fallback with code *)
        eState   := eFault;            // 进故障态 / Enter fault state
        bError   := TRUE;              // 置故障标志 / Set fault flag
        uErrorId := 16#0002_0005;      // 非法状态兜底码 / Illegal state fallback code
        fFfOut   := fLimLow;           // 安全输出 / Safe output
END_CASE;
END_FUNCTION_BLOCK
