(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StepperZLiftMicron
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : Z 轴微米级步进升降：细分当量组态（um/步）+ 相对目标
 *                         微动 + 软限位行程拦截。目标先 ROUND 换算步数（防浮点
 *                         累积）并做步数溢出检测（> 1e7 拒绝）；软限位预检先行；
 *                         运动中越限立即急停拦截；步脉冲经 TP 成形，位置以
 *                         LREAL 累加防微米级累积误差。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_StepZState / TYPE E_DL_StepZErr /
 *                         FUNCTION_BLOCK FB_DL_StepperZLiftMicron
 * 依赖 (Depends)        : DL_MathData/FC_DL_DintMsToTime、DL_MathData/FC_DL_TimeToLrealSec
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         当量下限防除零 + 步数溢出检测 + 速度钳位 + 非有限防御 ｜
 *                         枚举成员全部显式赋值 ｜ TP/TON/R_TRIG 每周期无条件调用 ｜
 *                         状态机 CASE 含 ELSE 兜底 ｜ 位置累加用 LREAL
 * 错误码表 (Codes)      : 16#0004_0322 就绪
 *                         16#0004_0323 故障级 配置非法（当量/速度/限位组态，共用反证句）
 *                         16#0004_0324 故障级 目标超软限位或步数溢出（拒绝启动，共用反证句）
 *                         16#0004_0325 故障级 运动中限位拦截(急停)
 *                         16#0004_0326 到位
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 3
 * 验收向量 (Acceptance) : 当量 0.5 um/步，目标 +100 um → 200 步；到位 0326；
 *                         目标超上限 → 0324 拒绝；运动中 fPosNow 越限 → 0325 急停
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StepZState（归属 DL_Motion，步进状态机状态）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StepZState :
(
    eIdle    := 0,    // 就绪待启动 / Idle, waiting for a start
    eMoving  := 10,   // 步进运动中（TP 成形步脉冲）/ Stepping, TP-formed pulses
    eDone    := 20,   // 到位（保持至下一次启动）/ In position, held until next start
    eFault   := 99    // 故障兜底态（急停后保持）/ Fault fallback, held after e-stop
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StepZErr（归属 DL_Motion，与 FB_DL_StepperZLiftMicron 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StepZErr :
(
    eReady     := 16#0004_0322,   // 就绪 / Ready
    eConfigBad := 16#0004_0323,   // 故障级：配置非法（当量/速度/限位组态）/ Fault: illegal configuration
    eTargetBad := 16#0004_0324,   // 故障级：目标超软限位或步数溢出 / Fault: target beyond soft limit or step overflow
    eLimitHit  := 16#0004_0325,   // 故障级：运动中限位拦截（急停）/ Fault: limit hit in motion, e-stop
    eInPos     := 16#0004_0326    // 到位 / In position
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_StepperZLiftMicron
 * 调用约定: 每个扫描周期无条件调用一次；tSampleTime 注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_StepperZLiftMicron
VAR_INPUT
    fUmPerStep  : REAL;                // 细分当量 [微米每步]，有效域 0.01~100 / Micrometers per step, subdivision config
    fTargetUm   : REAL;                // 目标位置 [微米]（绝对目标）/ Target position [um]
    fUpLimit_um : REAL;                // 软限位上限 [微米] / Soft limit upper [um]
    fLoLimit_um : REAL;                // 软限位下限 [微米] / Soft limit lower [um]
    fSpeedPps   : UDINT;               // 速度 [步每秒]，有效域 1~100000 / Speed [steps per second]
    bStartMove  : BOOL;                // 启动微动（上升沿）/ Start move trigger, rising edge
    bReset      : BOOL;                // 故障复位（上升沿）/ Fault reset, rising edge
    tSampleTime : TIME := T#1MS;       // 采样周期，调用方注入 / Sample period, caller-injected
END_VAR
VAR_OUTPUT
    fPosNow_um  : LREAL;               // 当前位置 [微米]（LREAL 累加防累积误差）/ Current position [um], LREAL accumulation
    bMoving     : BOOL;                // 运动中标志 / Moving flag
    bStepPulse  : BOOL;                // 步脉冲输出（TP 成形）/ Step pulse output, TP-formed
    bLimitHit   : BOOL;                // 限位拦截标志（锁存至复位）/ Limit-hit flag, latched until reset
    eErr        : E_DL_StepZErr;       // 错误码 / Error code
    eState      : E_DL_StepZState;     // 步进状态机当前状态 / Stepper state
END_VAR
VAR
    fbStartTrig : R_TRIG;              // 启动沿实例（无条件调用）/ Start edge instance
    fbResetTrig : R_TRIG;              // 复位沿实例（无条件调用）/ Reset edge instance
    fbPulse     : TP;                  // 步脉冲成形实例（无条件调用）/ Step pulse forming instance
    nStepsTotal : DINT;                // 本程总步数 [步]（ROUND 换算）/ Total steps this move [steps]
    nStepsDone  : DINT;                // 已发步数 [步] / Steps issued [steps]
    fStepAcc    : LREAL;               // 步数小数累积器 [步] / Fractional step accumulator [steps]
    fEquivUse   : REAL;                // 生效当量（钳位后）[微米每步] / Effective equivalence [um per step]
    fSpeedUse   : UDINT;               // 生效速度（钳位后）[步每秒] / Effective speed [steps per second]
    fUpUse      : REAL;                // 生效软限位上限 [微米] / Effective upper soft limit [um]
    fLoUse      : REAL;                // 生效软限位下限 [微米] / Effective lower soft limit [um]
    fTargetUse  : REAL;                // 生效目标（NaN 拒绝）[微米] / Effective target [um]
    fStepPulseW : TIME;                // 步脉冲宽度 [毫秒]（半步周期，委托换算）/ Step pulse width [ms] via delegate
    fDirSign    : LREAL;               // 运动方向符号（+1 上行 / -1 下行）/ Direction sign, plus up minus down
    fDtSec      : LREAL;               // 采样周期秒值（委托换算）[秒] / Sample period seconds via delegate
    bNonFin     : BOOL;                // 非有限输入汇总标志 / Non-finite input aggregate flag
    bStepReq    : BOOL;                // 步脉冲请求锁存（TP 输入源，脉宽完成后解锁）/ Step pulse request latch, released after the pulse
    uTmErr      : UDINT;               // 委托时间换算错误码（0 = 无错）/ Delegate time error id
END_VAR
VAR CONSTANT
    DL_STZ_EQUIV_MIN  : REAL := 0.01;     // 当量下限 [微米每步] / Equivalence lower bound [um per step]
    DL_STZ_EQUIV_MAX  : REAL := 100.0;    // 当量上限 [微米每步] / Equivalence upper bound [um per step]
    DL_STZ_SPEED_MIN  : UDINT := 1;       // 速度下限 [步每秒] / Speed lower bound [steps per s]
    DL_STZ_SPEED_MAX  : UDINT := 100000;  // 速度上限 [步每秒] / Speed upper bound [steps per s]
    DL_STZ_STEPS_MAX  : DINT := 10000000; // 步数溢出上限 [步] / Step overflow bound [steps]
    DL_STZ_INF_MAX    : REAL := 1.0E30;   // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_STZ_ZERO       : REAL := 0.0;      // 零值常量，避免裸字面量 / Zero constant
    DL_STZ_TOL        : REAL := 1.0E-6;   // 浮点比较容差 / Float comparison tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测/TP 实例每周期无条件调用（仅输入条件化）
 *----------------------------------------------------------------------------*)
fbStartTrig(CLK := bStartMove);                       // 启动沿检测无条件刷新 / start edge refreshed unconditionally
fbResetTrig(CLK := bReset);                           // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
fbPulse(IN := bStepReq, PT := fStepPulseW);   // 步脉冲成形（请求锁存源，宽度为半步周期）/ step pulse formed

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：故障清除回就绪（限位标志解锁）
 *----------------------------------------------------------------------------*)
IF fbResetTrig.Q THEN
    eState := E_DL_StepZState.eIdle;                 // 回就绪态 / back to idle
    eErr := E_DL_StepZErr.eReady;                    // 回就绪码 / back to ready
    bLimitHit := FALSE;                              // 限位标志解锁 / limit flag released
    bMoving := FALSE;                                // 运动标志撤 / moving dropped
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限值闸与配置钳位：当量/速度/限位非法 → 0323（共用反证句）
 *----------------------------------------------------------------------------*)
bNonFin := (fUmPerStep <> fUmPerStep) OR (ABS(fUmPerStep) > DL_STZ_INF_MAX)
        OR (fTargetUm  <> fTargetUm)  OR (ABS(fTargetUm)  > DL_STZ_INF_MAX)
        OR (fUpLimit_um <> fUpLimit_um) OR (ABS(fUpLimit_um) > DL_STZ_INF_MAX)
        OR (fLoLimit_um <> fLoLimit_um) OR (ABS(fLoLimit_um) > DL_STZ_INF_MAX);
IF bNonFin THEN
    eState := E_DL_StepZState.eFault;                // 进故障态 / enter fault
    eErr := E_DL_StepZErr.eConfigBad;                // 故障级：配置非法（非有限并入配置段）/ fault: config band
    bMoving := FALSE;                                // 运动撤 / moving dropped
    bStepPulse := FALSE;                             // 脉冲撤 / pulse dropped
    RETURN;
END_IF
fEquivUse := fUmPerStep;                              // 当量工作副本 / equivalence working copy
IF (fEquivUse < DL_STZ_EQUIV_MIN) OR (fEquivUse > DL_STZ_EQUIV_MAX) THEN
    eErr := E_DL_StepZErr.eConfigBad;                // 故障级：当量非法 / fault: illegal equivalence
    IF eState = E_DL_StepZState.eMoving THEN
        eState := E_DL_StepZState.eFault;            // 运动中配置突变：急停进故障态 / config change in motion: e-stop
        bMoving := FALSE;                            // 运动撤 / moving dropped
    END_IF
END_IF
fSpeedUse := fSpeedPps;                               // 速度工作副本 / speed working copy
IF (fSpeedUse < DL_STZ_SPEED_MIN) OR (fSpeedUse > DL_STZ_SPEED_MAX) THEN
    IF fSpeedUse < DL_STZ_SPEED_MIN THEN
        fSpeedUse := DL_STZ_SPEED_MIN;               // 速度下限钳位 / speed floored
    ELSE
        fSpeedUse := DL_STZ_SPEED_MAX;               // 速度上限钳位 / speed capped
    END_IF
END_IF
fUpUse := fUpLimit_um;                                // 上限工作副本 / upper working copy
fLoUse := fLoLimit_um;                                // 下限工作副本 / lower working copy
IF fLoUse >= fUpUse THEN
    eErr := E_DL_StepZErr.eConfigBad;                 // 故障级：限位组态非法（下限 >= 上限）/ fault: illegal limit config
    IF eState = E_DL_StepZState.eMoving THEN
        eState := E_DL_StepZState.eFault;            // 运动中组态突变：急停 / config change in motion: e-stop
        bMoving := FALSE;                            // 运动撤 / moving dropped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜速度换算：步周期 [毫秒] 与采样周期秒值（委托，防除零）
 *----------------------------------------------------------------------------*)
fStepPulseW := FC_DL_DintMsToTime(nMs := REAL_TO_DINT(500.0 / UDINT_TO_REAL(fSpeedUse)), eErr => uTmErr);   // 脉宽 = 半步周期（500/speed ms，委托换算；速度已钳位为正，除子非零）/ pulse width via delegate
IF uTmErr <> 0 THEN
    fStepPulseW := T#1MS;                             // 换算失败按 1 ms 兜底 / conversion failure falls back to 1 ms
END_IF
fDtSec := FC_DL_TimeToLrealSec(tIn := tSampleTime);   // 采样周期秒值（委托换算）/ sample period seconds via delegate
IF (fDtSec <> fDtSec) OR (fDtSec < LREAL#1.0E-6) THEN
    fDtSec := LREAL#0.001;                            // 非法采样周期按 1 ms 兜底（防除零）/ illegal sample period falls back
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜启动沿：软限位预检先行 + ROUND 换算步数 + 溢出检测 → 0324 拒绝
 *----------------------------------------------------------------------------*)
IF fbStartTrig.Q AND (eState <> E_DL_StepZState.eFault) AND (eErr <> E_DL_StepZErr.eConfigBad) THEN
    fTargetUse := fTargetUm;                          // 目标工作副本 / target working copy
    IF (fTargetUse > fUpUse + DL_STZ_TOL) OR (fTargetUse < fLoUse - DL_STZ_TOL) THEN
        eErr := E_DL_StepZErr.eTargetBad;             // 故障级：目标超软限位（预检拒绝）/ fault: target beyond soft limit
    ELSE
        nStepsTotal := REAL_TO_DINT(ROUND((fTargetUse - fPosNow_um) / fEquivUse));   // ROUND 换算步数（防浮点累积）/ steps by ROUND
        IF (nStepsTotal > DL_STZ_STEPS_MAX) OR (nStepsTotal < -DL_STZ_STEPS_MAX) THEN
            eErr := E_DL_StepZErr.eTargetBad;         // 故障级：步数溢出（与超限共用 0324，反证句：同为拒绝启动+脉冲撤）/ fault: step overflow
            nStepsTotal := 0;                         // 步数清零 / steps cleared
        ELSE
            nStepsDone := 0;                          // 已发步数清零 / issued steps cleared
            fStepAcc := LREAL#0.0;                    // 小数累积器清零 / fractional accumulator cleared
            IF (fTargetUse - fPosNow_um) >= DL_STZ_ZERO THEN
                fDirSign := LREAL#1.0;                // 上行方向 / upward direction
            ELSE
                fDirSign := LREAL#-1.0;               // 下行方向 / downward direction
            END_IF
            IF nStepsTotal = 0 THEN
                eErr := E_DL_StepZErr.eInPos;         // 零步数：已在目标位 / zero steps: already in position
                eState := E_DL_StepZState.eDone;      // 进到位相 / enter done phase
            ELSE
                eState := E_DL_StepZState.eMoving;    // 启动运动 / start moving
            END_IF
        END_IF
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜步进运动：按速度累积步数（LREAL），整数步经 TP 成形脉冲发出
 *----------------------------------------------------------------------------*)
bMoving := (eState = E_DL_StepZState.eMoving);        // 运动标志随状态 / moving follows state
bStepPulse := fbPulse.Q;                              // 脉冲输出由 TP 成形结果驱动 / pulse output driven by the TP result
IF fbPulse.Q THEN
    bStepReq := FALSE;                                // 脉宽完成：请求解锁 / pulse done: request released
END_IF
IF eState = E_DL_StepZState.eMoving THEN
    fStepAcc := fStepAcc + UDINT_TO_LREAL(fSpeedUse) * fDtSec;   // 步数累积 [步] / step accumulation
    WHILE (fStepAcc >= LREAL#1.0) AND (nStepsDone < nStepsTotal) DO
        fStepAcc := fStepAcc - LREAL#1.0;             // 消耗一个整数步 / consume one integer step
        nStepsDone := nStepsDone + 1;                 // 已发步数递增 [步] / issued steps incremented
        bStepReq := TRUE;                             // 步脉冲请求锁存（下拍 TP 成形）/ step pulse request latched
        fPosNow_um := fPosNow_um + fDirSign * fEquivUse;   // 位置 LREAL 累加 [微米]（含方向符号）/ position accumulated with direction
    END_WHILE
    // 运动中越限急停：位置一旦离开软限位区间立即拦截 / in-motion overtravel e-stop
    IF (fPosNow_um > fUpUse + DL_STZ_TOL) OR (fPosNow_um < fLoUse - DL_STZ_TOL) THEN
        eState := E_DL_StepZState.eFault;             // 急停进故障态 / e-stop to fault
        eErr := E_DL_StepZErr.eLimitHit;              // 故障级：限位拦截 / fault: limit hit
        bLimitHit := TRUE;                            // 限位标志锁存 / limit flag latched
        bMoving := FALSE;                             // 运动撤 / moving dropped
        bStepPulse := FALSE;                          // 脉冲撤 / pulse dropped
        bStepReq := FALSE;                            // 脉冲请求撤 / pulse request dropped
        nStepsDone := nStepsTotal;                    // 终止本程 / terminate the move
    ELSIF nStepsDone >= nStepsTotal THEN
        eState := E_DL_StepZState.eDone;              // 步数发完：到位 / steps done: in position
        eErr := E_DL_StepZErr.eInPos;                 // 到位码 / in-position code
        bMoving := FALSE;                             // 运动撤 / moving dropped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜状态码映射与 CASE 兜底
 *----------------------------------------------------------------------------*)
CASE eState OF
    E_DL_StepZState.eIdle:
        IF (eErr <> E_DL_StepZErr.eConfigBad) AND (eErr <> E_DL_StepZErr.eTargetBad) AND (eErr <> E_DL_StepZErr.eLimitHit) THEN
            eErr := E_DL_StepZErr.eReady;             // 无挂起故障时保持就绪码 / ready code unless a fault is pending
        END_IF
    E_DL_StepZState.eMoving:
        bMoving := TRUE;                              // 运动相运动标志保持 / moving flag held in motion phase
    E_DL_StepZState.eDone:
        eErr := E_DL_StepZErr.eInPos;                 // 到位码 / in-position code
    E_DL_StepZState.eFault:
        bMoving := FALSE;                             // 故障态运动撤 / moving dropped in fault
        bStepPulse := FALSE;                          // 故障态脉冲撤 / pulse dropped in fault
        bStepReq := FALSE;                            // 故障态请求撤 / request dropped in fault
    ELSE
        eState := E_DL_StepZState.eFault;             // 非法状态兜底 / illegal-state fallback
        eErr := E_DL_StepZErr.eConfigBad;             // 兜底码（配置段，反证句：输出同为运动撤+故障级）/ fallback code
        bMoving := FALSE;                             // 运动撤 / moving dropped
        bStepPulse := FALSE;                          // 脉冲撤 / pulse dropped
        bStepReq := FALSE;                            // 请求撤 / request dropped
END_CASE
END_FUNCTION_BLOCK
