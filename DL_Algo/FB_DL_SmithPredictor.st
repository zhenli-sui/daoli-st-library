(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SmithPredictor
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG 经子块间接使用），零厂商方言
 * 功能描述 (Function)   : 大滞后对象专用史密斯预估器。内部按一阶 + 纯滞后模型
 *                         实时仿真"若无滞后过程会如何响应"，用补偿后误差驱动内
 *                         嵌 PID，等效消除纯滞后对环路稳定性的破坏；模型静态偏
 *                         差经小增益在线自适应校正。上电后队列填充期自动退化为
 *                         普通 PID（学习态），不阻塞控制。现场用途：长管道加热、
 *                         烘箱等大纯滞后温控回路。
 * 开源溯源 (Origin)     : 原创实现。史密斯预估器功能分类与参数域参考过程控制
 *                         经典文献（Smith dead-time compensator）的公开语义描
 *                         述，未复制任何厂商源码，clean-room 重写。
 * 本文件内含       : TYPE  E_DL_SmithState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_SmithPredictor
 * 依赖     (Depends)    : FB_DL_PidController（DL_Algo 内部）
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+数组边界防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM+CASE+ELSE
 *                         R7 ✓ R_TRIG 实例主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 04 · Level 1 DL_Algo
 *   2026-11-15  v1.0.1  阶段五终审精修：信息级码 0502（模型滞后截断）不再
 *                       置 bError，防下游报警误动作
 * 验收向量 (Acceptance) :
 *   V1 学习态：上电前 nLagSteps 拍内 fErrComp = fSetpoint - fPv（未补偿）
 *   V2 补偿态：队列填满后 fErrComp = fPv - (fModelDelayed + fModelBias)
 *   V3 模型收敛：fModelK=1, tModelT=T#1S, 恒定控制量 50 → fModelOut 趋近 50
 *   V4 自适应：对象静差存在 → fModelBias 朝消除偏差方向缓慢增长
 *   V5 增益非法：fModelK=0 → fModelOut 恒 0 且码 0002_0501，控制不中断
 *   V6 手动无扰：手动 30.0 切自动首拍输出保持 30.0 连续
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SmithState（归属 DL_Algo，与 FB_DL_SmithPredictor 同文件）
 * 含义: 史密斯预估器离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SmithState :
(
    eIdle         := 0,   // 使能关：模型与队列冻结，输出回下限 / Idle: model frozen, output at low limit
    eLearning     := 10,  // 学习态：队列填充中，PID 用原始误差 / Learning: queue filling, PID uses raw error
    eCompensating := 20,  // 补偿态：队列满，全补偿闭环 / Compensating: queue full, full compensation
    eManual       := 30,  // 手动态：输出手动值，模型继续仿真 / Manual: manual output, model still simulates
    eFault        := 99   // 故障兜底态：非法状态进入，输出安全值 / Fault fallback: illegal state, safe output
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SmithPredictor
 * 调用约定: 每个扫描周期无条件调用一次；bReset 上升沿重置模型与队列。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 工程披露: 模型滞后队列为固定 20 槽环形缓冲，深度按 tModelLag/tSampleTime
 *           向下取整折算，超出上限截断并置码，不做动态扩容。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SmithPredictor
VAR_INPUT
    bEnable     : BOOL := FALSE;      // 总使能，FALSE 时输出回下限 / Master enable, FALSE drives output to low limit
    bManual     : BOOL := FALSE;      // 手动模式，TRUE 时输出手动值 / Manual mode, TRUE outputs manual value
    fManualValue: REAL := 0.0;        // 手动输出值 [%]，越限自动钳位 / Manual output value, auto-clamped
    fSetpoint   : REAL := 0.0;        // 设定值 [EU] / Setpoint in engineering units
    fPv         : REAL := 0.0;        // 过程值 [EU] / Process value in engineering units
    fKp         : REAL := 1.0;        // 内嵌 PID 比例增益 [1] / Embedded PID proportional gain
    tTi         : TIME := T#2S;       // 内嵌 PID 积分时间 [s] / Embedded PID integral time
    tTd         : TIME := T#0S;       // 内嵌 PID 微分时间 [s] / Embedded PID derivative time
    fModelK     : REAL := 1.0;        // 对象模型增益 [EU/EU] / Plant model gain
    tModelT     : TIME := T#5S;       // 模型惯性时间 [s] / Model time constant in seconds
    tModelLag   : TIME := T#1S;       // 模型纯滞后 [s] / Model dead time in seconds
    rOutMin     : REAL := 0.0;        // 输出下限 [%] / Output lower limit in percent
    rOutMax     : REAL := 100.0;      // 输出上限 [%] / Output upper limit in percent
    tSampleTime : TIME := T#100MS;    // 采样周期 [s] / Sample period in seconds
    bReset      : BOOL := FALSE;      // 复位信号，上升沿重置模型 / Reset, rising edge resets model
END_VAR
VAR_OUTPUT
    fCtrlOut    : REAL;               // 控制器输出 [%] / Controller output in percent
    fModelOut   : REAL;               // 模型无滞后输出 [EU]，诊断 / Model no-delay output, diagnostics
    fErrComp    : REAL;               // 补偿后偏差 [EU]，诊断 / Compensated error, diagnostics
    fModelBias  : REAL;               // 模型自适应偏差 [EU] / Model adaptive bias
    bError      : BOOL;               // 故障标志 / Fault flag
    uErrorId    : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbPid       : FB_DL_PidController;  // 内嵌 PID 实例 / Embedded PID instance
    fModelState : REAL;               // 一阶模型状态 [EU] / First-order model state
    afLagBuf    : ARRAY[0..19] OF REAL;  // 模型滞后队列 [EU]，20 槽环形 / Model delay queue, 20-slot ring
    nLagSteps   : INT;                // 队列深度 = tModelLag/tSampleTime [拍] / Queue depth in cycles
    nWriteIdx   : INT;                // 环形队列写指针 [0..19] / Ring buffer write index
    nFillCnt    : INT;                // 队列填充计数 [拍] / Queue fill counter in cycles
    eState      : E_DL_SmithState;    // 主状态机当前状态 / Current state of the state machine
    bInit       : BOOL := FALSE;      // 首扫初始化标志 / First-scan init flag
    fbTrigReset : R_TRIG;             // 复位信号上升沿检测实例 / Reset rising edge detector instance
    fDt         : REAL;               // 生效采样周期 [s] / Effective sample period in seconds
    fLimLow     : REAL;               // 修复后的输出下限 [%] / Repaired output lower limit
    fLimHigh    : REAL;               // 修复后的输出上限 [%] / Repaired output upper limit
    fModelDelayed: REAL;              // 滞后队列读出的模型输出 [EU] / Delayed model output from queue
    fErrRaw     : REAL;               // 原始未补偿偏差 [EU] / Raw uncompensated error
    nReadIdx    : INT;                // 环形队列读指针 [0..19] / Ring buffer read index
    nDepthRaw   : INT;                // 折算的原始队列深度 [拍] / Raw computed queue depth in cycles
    bNonFinite  : BOOL;               // 本拍输入非有限值标志 / Non-finite input flag of this cycle
END_VAR
VAR CONSTANT
    DL_SMITH_LAG_MAX : INT  := 20;    // 模型滞后队列深度上限 [槽] / Model delay queue ceiling in slots
    DL_SMITH_KB      : REAL := 0.02;  // 模型偏差自适应增益 [1/s] / Model bias adaptive gain
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：复位沿检测严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): edge detector outside IF / CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜参数钳位与公共防御（不中断扫描）
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

(* 模型滞后深度折算：向下取整，超上限截断置码 *)
(* Model lag depth derivation: floor division, truncated at ceiling with code *)
nDepthRaw := REAL_TO_INT(TRUNC(TIME_TO_REAL(tModelLag) / 1000.0 / fDt));  // 原始深度 [拍] / Raw depth in cycles
IF nDepthRaw > DL_SMITH_LAG_MAX THEN
    nLagSteps := DL_SMITH_LAG_MAX;    // 深度截断至上限 / Depth truncated to ceiling
    uErrorId := 16#0002_0502;         // 组件码：模型滞后超队列上限已截断 / Code: model lag truncated
ELSIF nDepthRaw < 0 THEN
    nLagSteps := 0;                   // 负深度防御为 0 / Negative depth defended to zero
ELSE
    nLagSteps := nDepthRaw;           // 合法深度直通 / Valid depth passed
END_IF

(* 模型增益非法防御：增益为 0 时模型输出恒 0，控制不中断 *)
(* Model gain defense: zero gain gives zero model output, control continues *)
IF fModelK = 0.0 THEN
    uErrorId := 16#0002_0501;         // 组件码：模型增益非法 / Code: model gain illegal
END_IF

(* 输入非有限值防御：设定或过程值非法即拒绝本拍更新 *)
(* Non-finite defense: reject this cycle if setpoint or process value invalid *)
IF (fSetpoint <> fSetpoint) OR (ABS(fSetpoint) > 1.0E30)
   OR (fPv <> fPv) OR (ABS(fPv) > 1.0E30)
   OR (fManualValue <> fManualValue) OR (ABS(fManualValue) > 1.0E30) THEN
    bNonFinite := TRUE;               // 置非有限值标志 / Set non-finite flag
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜复位与首扫初始化：模型状态对齐过程值，队列预填，偏差清零
 *      Reset and first-scan init: model aligned to PV, queue prefilled
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q OR (NOT bInit) THEN
    fModelState := fPv;               // 模型状态对齐过程值防上电冲击 / Model state aligned to PV
    fModelBias  := 0.0;               // 自适应偏差清零 / Adaptive bias cleared
    nWriteIdx   := 0;                 // 写指针归零 / Write index reset
    nFillCnt    := 0;                 // 填充计数归零 / Fill counter reset
    FOR nReadIdx := 0 TO DL_SMITH_LAG_MAX - 1 DO
        afLagBuf[nReadIdx] := fPv;    // 队列全槽预填过程值 / Prefill all queue slots with PV
    END_FOR
    bInit := TRUE;                    // 置首扫完成标志 / Set first-scan done flag
END_IF

IF NOT bEnable THEN
    eState  := eIdle;                 // 强制回空闲态 / Force idle state
    fCtrlOut:= fLimLow;               // 输出回下限 / Output to low limit
    RETURN;                           // 本拍结束（模型冻结） / End of cycle, model frozen
END_IF

IF bNonFinite THEN
    bError   := TRUE;                 // 置故障标志 / Set fault flag
    uErrorId := 16#0002_0004;         // 公共码：输入非有限值已拒绝 / Common code: non-finite rejected
    RETURN;                           // 保持上一拍输出与状态 / Hold previous output and state
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜模型仿真：一阶惯性递推 + 增益折算 + 纯滞后队列 + 自适应偏差
 *      Model simulation: first-order recursion, gain scaling, queue, bias adaptation
 *-----------------------------------------------------------------------------*)
fModelState := fModelState + (fCtrlOut - fModelState) * fDt
               / MAX(TIME_TO_REAL(tModelT) / 1000.0, fDt);          // 一阶惯性递推 / First-order recursion
fModelOut := fModelState * fModelK;                                   // 增益折算输出 [EU] / Gain-scaled output

afLagBuf[nWriteIdx] := fModelOut;                                     // 当前模型输出入队 / Enqueue model output
nReadIdx := (nWriteIdx - nLagSteps + DL_SMITH_LAG_MAX) MOD DL_SMITH_LAG_MAX;  // 读指针 / Read index
nReadIdx := LIMIT(0, nReadIdx, DL_SMITH_LAG_MAX - 1);                 // 读指针防御钳位 / Defensive index clamp
fModelDelayed := afLagBuf[nReadIdx];                                  // 滞后读出 [EU] / Delayed readout
nWriteIdx := (nWriteIdx + 1) MOD DL_SMITH_LAG_MAX;                    // 写指针推进 / Advance write index

(* 队列填充计数：饱和于深度值，用于学习态判定 *)
(* Queue fill counter: saturated at depth, used for learning-state decision *)
IF nFillCnt < DL_SMITH_LAG_MAX THEN
    nFillCnt := nFillCnt + 1;         // 填充计数递增 / Increment fill counter
END_IF

(* 模型静态偏差在线自适应校正：小增益缓慢收敛 *)
(* Online adaptive bias correction: small gain slow convergence *)
fModelBias := fModelBias + DL_SMITH_KB * (fPv - fModelDelayed - fModelBias) * fDt;

(*------------------------------------------------------------------------------
 * 段 5｜内嵌 PID 引脚注入（本块不自写 PID 律）
 *      Embedded PID pin injection, no PID law rewritten here
 *-----------------------------------------------------------------------------*)
fbPid.bEnable      := TRUE;           // PID 使能 / PID enabled
fbPid.fSetpoint    := fErrComp;       // 设定 = 补偿后误差（实际引脚恒 0）/ Setpoint equals compensated error
fbPid.fActual      := 0.0;            // 实际恒 0，使偏差 = 补偿误差 / Actual zero so error equals compensated error
fbPid.fKp          := fKp;            // 增益透传 / Gain passthrough
fbPid.tTi          := tTi;            // 积分时间透传 / Integral time passthrough
fbPid.tTd          := tTd;            // 微分时间透传 / Derivative time passthrough
fbPid.fDeadband    := 0.0;            // 死区默认关闭 / Deadband off by default
fbPid.bIncremental := FALSE;          // 默认位置式 / Positional by default
fbPid.rOutMin      := rOutMin;        // 输出下限透传 / Low limit passthrough
fbPid.rOutMax      := rOutMax;        // 输出上限透传 / High limit passthrough
fbPid.tSampleTime  := tSampleTime;   // 采样周期透传 / Sample period passthrough
fbPid.bTrack       := FALSE;          // PID 自身不跟踪 / PID tracking off
fbPid.fTrackValue  := 0.0;            // 跟踪值占位 / Track value placeholder
fbPid.bReset       := bReset;         // 复位透传 / Reset passthrough

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine: ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eState OF

    eIdle:
        (* 空闲态已在早退段处理；本分支仅做迁移防御 *)
        (* Idle handled in early exit; this branch only guards transfers *)
        IF bEnable THEN
            IF bManual THEN
                eState := eManual;    // 请求手动 / Request manual mode
            ELSIF nFillCnt < nLagSteps THEN
                eState := eLearning;  // 队列未满进学习态 / Queue not full, learning state
            ELSE
                eState := eCompensating;  // 队列满进补偿态 / Queue full, compensating
            END_IF
        END_IF

    eLearning:
        (* 学习态：队列填充中，PID 用原始误差闭环，不阻塞控制 *)
        (* Learning: queue filling, PID closed loop on raw error, control not blocked *)
        fErrRaw  := fSetpoint - fPv;  // 原始偏差 [EU] / Raw error
        fErrComp := fErrRaw;          // 补偿误差 = 原始误差 / Compensated equals raw
        fbPid.fSetpoint := fErrComp;  // 设定 = 补偿后误差 / Setpoint equals compensated error
        fbPid.bManual := FALSE;       // PID 自动 / PID auto
        fbPid();                      // PID 运算 / PID computation
        fCtrlOut := fbPid.fOut;       // 输出透传 / Output passthrough
        IF bManual THEN
            eState := eManual;        // 切手动 / Switch to manual
        ELSIF nFillCnt >= nLagSteps THEN
            eState := eCompensating;  // 队列满切补偿 / Queue full, compensating
        END_IF

    eCompensating:
        (* 补偿态：用模型滞后输出与自适应偏差重构等效无滞后误差 *)
        (* Compensating: reconstruct delay-free error from delayed model and bias *)
        fErrComp := fPv - (fModelDelayed + fModelBias);   // 补偿后偏差 [EU] / Compensated error
        fbPid.fSetpoint := fErrComp;  // 设定 = 补偿后误差 / Setpoint equals compensated error
        fbPid.bManual := FALSE;       // PID 自动 / PID auto
        fbPid();                      // PID 运算 / PID computation
        fCtrlOut := fbPid.fOut;       // 输出透传 / Output passthrough
        IF bManual THEN
            eState := eManual;        // 切手动 / Switch to manual
        END_IF

    eManual:
        (* 手动态：输出手动值（钳位），模型与队列继续仿真保证回自动连续 *)
        (* Manual: clamped manual output, model keeps simulating for bumpless return *)
        fErrRaw  := fSetpoint - fPv;  // 原始偏差诊断 / Raw error diagnostics
        fErrComp := fErrRaw;          // 补偿误差诊断 / Compensated error diagnostics
        fbPid.bManual     := TRUE;    // PID 手动 / PID manual
        fbPid.fManualValue:= fManualValue;  // 手动值注入 / Inject manual value
        fbPid();                      // PID 手动运算 / PID manual computation
        fbPid.bManual     := FALSE;   // 恢复自动配置位 / Restore auto config bit
        fCtrlOut := fbPid.fOut;       // 输出透传 / Output passthrough
        IF NOT bEnable THEN
            eState := eIdle;          // 切空闲 / Switch to idle
        ELSIF NOT bManual THEN
            IF nFillCnt >= nLagSteps THEN
                eState := eCompensating;  // 回补偿态 / Back to compensating
            ELSE
                eState := eLearning;  // 回学习态 / Back to learning
            END_IF
        END_IF

    eFault:
        (* 故障兜底态：输出安全下限，模型继续仿真 *)
        (* Fault fallback: safe low-limit output, model keeps simulating *)
        fCtrlOut := fLimLow;          // 安全输出 / Safe output

    ELSE
        (* 非法状态拦截：任何未定义状态一律进故障兜底，不做隐式恢复 *)
        (* Illegal state interception: any undefined state goes to fault fallback *)
        eState   := eFault;           // 进故障态 / Enter fault state
        bError   := TRUE;             // 置故障标志 / Set fault flag
        uErrorId := 16#0002_0005;     // 非法状态兜底码 / Illegal state fallback code
        fCtrlOut := fLimLow;          // 安全输出 / Safe output
END_CASE;

(* 信息级码（0502 模型滞后截断）不置故障标志，防下游报警误动作 *)
(* Info-level code (model lag truncation 0502) never raises the fault flag *)
bError := (uErrorId <> 16#0002_0000) AND (uErrorId <> 16#0002_0502);  // 非信息级码才置故障 / Fault flag only on non-info codes
END_FUNCTION_BLOCK
