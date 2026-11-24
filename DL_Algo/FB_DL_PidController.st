(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PidController
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能描述 (Function)   : 单回路通用离散 PID 控制器。位置式与增量式由独立布尔
 *                         bIncremental 选择（不堆模式枚举）；含控制死区、积分
 *                         分离（触限停积分）、两级抗积分饱和（条件积分 + 限幅
 *                         反算回填）、手自动无扰切换与跟踪回投。fKp 为负即反
 *                         作用（沿 OSCAT / 西门子惯例）。现场用途：温度 / 压力 /
 *                         流量单闭环调节主块，温控区与后续串级块的基石。
 * 开源溯源 (Origin)     : 原创实现。功能分类与参数域参考 OSCAT 基础库 FT_PIWL
 *                         反算抗饱和思想与西门子 CONT_C 公开语义描述，
 *                         未复制任何厂商源码，clean-room 重写。
 * 本文件内含       : TYPE  E_DL_PidState（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_PidController
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 防除零+钳位+非有限值防御
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE
 *                         R7 ✓ R_TRIG 实例主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 04 · Level 1 DL_Algo
 *   2026-11-15  v1.0.1  阶段五终审精修：积分量纲统一为[%]；eIdle 补 bActive
 *                       清零；信息级码不置 bError；首扫与手自动历史同步防踢腿
 * 验收向量 (Acceptance) :
 *   V1 阶跃纯比例：fKp=2, tTi=T#0S, SP=50, PV=0 → fOut=rOutMax 触限
 *   V2 抗饱和：fKp=2, tTi=T#2S, SP=200 → 触上限后撤销阶跃，输出快速回落
 *      （积分已反算回填，无长时间停限）
 *   V3 无扰切换：手动 30.0 切自动首拍输出保持 30.0 连续
 *   V4 死区：fDeadband=5 且 |偏差|<5 → 输出保持不变
 *   V5 非有限值：fSetpoint 写入非法浮点 → 输出保持上一拍且 uErrorId=0002_0004
 *   V6 增量式：fKp=1, tTi=T#1S, 恒偏差 10 → fOut 单调爬升至上限后停
 *============================================================================*)
(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PidState（归属 DL_Algo，与 FB_DL_PidController 同文件）
 * 含义: PID 控制器离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_PidState :
(
    eIdle   := 0,    // 使能关：输出回输出下限，积分冻结 / Idle: enable off, output at low limit, integral frozen
    eAuto   := 10,   // 自动调节：闭环 PID 运算中 / Auto: closed-loop PID computation active
    eManual := 20,   // 手动模式：输出手动值，积分同步跟踪保证无扰 / Manual: output manual value, integral tracked for bumpless
    eFault  := 99    // 故障兜底态：非法状态进入，输出安全值 / Fault fallback: entered on illegal state, safe output
);
END_TYPE
(*==============================================================================
 * 功能块: FB_DL_PidController
 * 调用约定: 每个扫描周期无条件调用一次；bReset 上升沿清积分与故障。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 工程披露: 微分项对偏差做一阶预滤波（滤波时间取 tTd 的 1/10），抑制微分尖峰。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PidController
VAR_INPUT
    bEnable      : BOOL := FALSE;     // 总使能，FALSE 时输出回输出下限 / Master enable, FALSE drives output to low limit
    bManual      : BOOL := FALSE;     // 手动模式选择，TRUE = 手动输出 / Manual mode select, TRUE = manual output
    fManualValue : REAL := 0.0;       // 手动输出值 [%]，越限自动钳位 / Manual output value [%], auto-clamped
    fSetpoint    : REAL := 0.0;       // 设定值 [EU] / Setpoint in engineering units
    fActual      : REAL := 0.0;       // 过程实际值 [EU] / Process actual value in engineering units
    fKp          : REAL := 1.0;       // 比例增益 [1]，负值 = 反作用 / Proportional gain, negative = reverse acting
    tTi          : TIME := T#2S;      // 积分时间 [s]，T#0S 表示纯 PD 无积分 / Integral time [s], T#0S = pure PD
    tTd          : TIME := T#0S;      // 微分时间 [s]，T#0S 关闭微分 / Derivative time [s], T#0S disables derivative
    fDeadband    : REAL := 0.0;       // 控制死区 [EU]，负值自动钳 0 / Control deadband [EU], negative clamped to 0
    bIncremental : BOOL := FALSE;     // TRUE = 增量式算法，FALSE = 位置式 / TRUE = incremental form, FALSE = positional
    rOutMin      : REAL := 0.0;       // 输出下限 [%] / Output lower limit in percent
    rOutMax      : REAL := 100.0;     // 输出上限 [%] / Output upper limit in percent
    tSampleTime  : TIME := T#100MS;   // 采样周期 [s]，小于 T#10MS 钳位 / Sample period, clamped to 10 ms minimum
    bTrack       : BOOL := FALSE;     // 跟踪使能，TRUE 时输出立即跟随跟踪值 / Track enable, output follows track value
    fTrackValue  : REAL := 0.0;       // 跟踪值 [%]，与输出同量纲，用于无扰投切 / Track value in percent, same unit as output
    bReset       : BOOL := FALSE;     // 复位信号，上升沿清积分与故障 / Reset, rising edge clears integral and fault
END_VAR
VAR_OUTPUT
    fOut         : REAL;              // 控制输出 [%] / Control output in percent
    fErr         : REAL;              // 偏差 = 设定 - 实际 [EU] / Error = setpoint minus actual
    fIntPart     : REAL;              // 积分分量 [%]，诊断用 / Integral component in percent, diagnostics
    bLimitHigh   : BOOL;              // 输出触上限标志 / Output saturated at upper limit flag
    bLimitLow    : BOOL;              // 输出触下限标志 / Output saturated at lower limit flag
    bActive      : BOOL;              // 自动调节进行中标志 / Auto regulation active flag
    bError       : BOOL;              // 故障标志，0 除外均置位 / Fault flag, set on any nonzero error code
    uErrorId     : UDINT;             // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fErrPrev1    : REAL;              // 上一拍偏差（增量式历史） [EU] / Previous error for incremental form
    fErrPrev2    : REAL;              // 上上拍偏差（增量式历史） [EU] / Error two cycles ago for incremental form
    fErrF        : REAL;              // 微分预滤波后的偏差 [EU] / Prefiltered error for derivative term
    fErrFPrev    : REAL;              // 上一拍预滤波偏差 [EU] / Previous prefiltered error
    fbTrigReset  : R_TRIG;            // 复位信号上升沿检测实例 / Reset rising edge detector instance
    eState       : E_DL_PidState;     // 主状态机当前状态 / Current state of the main state machine
    bInit        : BOOL := TRUE;      // 历史同步标志，TRUE 触发历史同步（首扫即同步防踢腿）/ History sync flag, TRUE syncs histories on first scan
    fDt          : REAL;              // 生效采样周期 [s] / Effective sample period in seconds
    fLimLow      : REAL;              // 修复后的输出下限 [%] / Repaired output lower limit
    fLimHigh     : REAL;              // 修复后的输出上限 [%] / Repaired output upper limit
    fDeadbandEff : REAL;              // 钳位后的有效死区 [EU] / Clamped effective deadband
    fInt         : REAL;              // 积分累积 [%]，与输出同量纲 / Accumulated integral in percent, same unit as output
    fP           : REAL;              // 比例分量 [%] / Proportional component
    fD           : REAL;              // 微分分量 [%] / Derivative component
    fPre         : REAL;              // 抗饱和判定用预输出 [%] / Pre-output for anti-windup test
    fDelta       : REAL;              // 增量式单拍增量 [%] / Incremental delta of one cycle
    fTdS         : REAL;              // 微分时间换算秒 [s] / Derivative time in seconds
    fAlpha       : REAL;              // 微分预滤波权重 [0..1] / Derivative prefilter weight
    fManOut      : REAL;              // 钳位后的手动输出 [%] / Clamped manual output
    bSkipInt     : BOOL;              // 积分分离标志：触限且误差继续推进 / Conditional integration flag
END_VAR
VAR CONSTANT
    DL_PID_ERR_MAX : REAL := 1.0E10;  // 积分钳位上限 [%]，防浮点溢出的极端钳位 / Integral clamp ceiling [%], extreme guard against float overflow
END_VAR
(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：复位沿检测严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): edge detector outside IF / CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
(*------------------------------------------------------------------------------
 * 段 2｜参数钳位与公共防御（不中断扫描，现场组态笔误不停机）
 *      Parameter clamping and common defenses, never stops the scan
 *-----------------------------------------------------------------------------*)
bError   := FALSE;                    // 每拍重算故障标志 / Recompute fault flag every cycle
uErrorId := 16#0002_0000;             // 每拍重算故障码 / Recompute error code every cycle
bLimitHigh := FALSE;                  // 触限标志每拍重算 / Saturation flags recomputed every cycle
bLimitLow  := FALSE;                  // 触限标志每拍重算 / Saturation flags recomputed every cycle
IF tSampleTime < T#10MS THEN
    fDt := 0.01;                      // 采样周期非法钳位为 0.01 s / Illegal sample period clamped to 0.01 s
    uErrorId := 16#0002_0002;         // 公共码：采样周期已钳位 / Common code: sample period clamped
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;  // 采样周期换算为秒 [s] / Sample period converted to seconds
END_IF
IF rOutMin > rOutMax THEN
    fLimLow  := rOutMax;              // 上下限对调修复（下限取原上限） / Swapped limits after repair
    fLimHigh := rOutMin;              // 上下限对调修复（上限取原下限） / Swapped limits after repair
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fLimLow  := rOutMin;              // 合法下限直通 / Valid lower limit passed through
    fLimHigh := rOutMax;              // 合法上限直通 / Valid upper limit passed through
END_IF
IF fDeadband < 0.0 THEN
    fDeadbandEff := 0.0;              // 死区负值钳 0 / Negative deadband clamped to zero
    uErrorId := 16#0002_0001;         // 公共码：参数越界已钳位 / Common code: parameter clamped
ELSE
    fDeadbandEff := fDeadband;        // 合法死区直通 / Valid deadband passed through
END_IF
(*------------------------------------------------------------------------------
 * 段 3｜复位处理：清积分、清增量式历史、清滤波偏差，故障归零
 *      Reset handling: clear integral, incremental history and filtered error
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    fInt       := 0.0;                // 清积分累积 [%] / Clear accumulated integral in percent
    fErrPrev1  := 0.0;                // 清上一拍偏差 / Clear previous error history
    fErrPrev2  := 0.0;                // 清上上拍偏差 / Clear two-cycle error history
    fErrF      := 0.0;                // 清滤波偏差 / Clear prefiltered error
    fErrFPrev  := 0.0;                // 清上拍滤波偏差 / Clear previous prefiltered error
    fOut       := fLimLow;            // 输出回安全下限 / Output to safe lower limit
    eState     := eIdle;              // 状态回空闲 / State back to idle
    bInit      := TRUE;               // 置首扫标志使下一拍同步历史 / Set init flag to resync history next cycle
END_IF
(*------------------------------------------------------------------------------
 * 段 4｜非有限值防御：设定值 / 过程值 / 手动值 / 跟踪值任一非法即拒绝本拍更新
 *      Non-finite defense: reject this cycle if any relevant input is invalid
 *-----------------------------------------------------------------------------*)
IF (fSetpoint <> fSetpoint) OR (ABS(fSetpoint) > 1.0E30)
   OR (fActual <> fActual) OR (ABS(fActual) > 1.0E30)
   OR (fManualValue <> fManualValue) OR (ABS(fManualValue) > 1.0E30)
   OR (fTrackValue <> fTrackValue) OR (ABS(fTrackValue) > 1.0E30) THEN
    bError   := TRUE;                 // 置故障标志 / Set fault flag
    uErrorId := 16#0002_0004;         // 公共码：输入非有限值已拒绝 / Common code: non-finite input rejected
    RETURN;                           // 保持上一拍输出与状态 / Hold previous output and state
END_IF
(*------------------------------------------------------------------------------
 * 段 5｜使能关断：输出回下限、积分冻结、状态回空闲（允许带电观察）
 *      Enable off: output to low limit, integral frozen, state back to idle
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    eState  := eIdle;                 // 强制回空闲态 / Force idle state
    fOut    := fLimLow;               // 输出回下限安全值 / Output to safe low limit
    fErr    := fSetpoint - fActual;   // 偏差仍刷新供诊断 / Error still refreshed for diagnostics
    bActive := FALSE;                 // 调节未激活 / Regulation not active
    fIntPart:= fInt;                  // 保留积分分量供诊断 / Keep integral component for diagnostics
    RETURN;                           // 本拍结束 / End of this cycle
END_IF
(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine: ENUM + CASE with mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eState OF
    eIdle:
        (* 空闲态：按手动 / 自动请求迁移，迁移前同步增量式历史防微分踢腿 *)
        (* Idle: migrate by mode request, sync incremental history before transfer *)
        bActive := FALSE;             // 空闲态激活标志清零防跨拍残留 / Clear active flag against stale carry-over
        fErr := fSetpoint - fActual;  // 计算原始偏差 [EU] / Raw error in engineering units
        IF ABS(fErr) < fDeadbandEff THEN
            fErr := 0.0;              // 死区内偏差按 0 处理 / Error inside deadband treated as zero
        END_IF
        IF bManual THEN
            eState := eManual;        // 请求手动 / Request manual mode
        ELSE
            eState := eAuto;          // 请求自动 / Request auto mode
        END_IF
    eAuto:
        (* 自动调节态：位置式或增量式 PID 闭环运算 + 两级抗饱和 *)
        (* Auto: positional or incremental closed-loop PID with two-stage anti-windup *)
        bActive := TRUE;              // 自动调节激活 / Auto regulation active
        fErr := fSetpoint - fActual;  // 原始偏差 [EU] / Raw error
        IF ABS(fErr) < fDeadbandEff THEN
            fErr := 0.0;              // 死区内偏差置 0 / Zero error inside deadband
        END_IF
        IF bInit THEN
            (* 首扫 / 复位后同步全部历史，杜绝上电尖峰与虚假微分 *)
            (* First scan / post-reset history sync, no power-up spike *)
            fErrF     := fErr;        // 滤波偏差同步 / Sync prefiltered error
            fErrFPrev := fErr;        // 上拍滤波偏差同步 / Sync previous prefiltered error
            fErrPrev1 := fErr;        // 增量式历史同步 / Sync incremental history
            fErrPrev2 := fErr;        // 增量式历史同步 / Sync incremental history
            bInit     := FALSE;       // 清首扫标志 / Clear first-scan flag
        END_IF
        fP := fKp * fErr;             // 比例项 [%] / Proportional term
        IF bTrack THEN
            (* 跟踪回投：输出立即跟随跟踪值，积分反算同步，恢复自动零扰动 *)
            (* Track mode: output follows track value, integral back-calculated in sync *)
            fOut    := LIMIT(fLimLow, fTrackValue, fLimHigh);   // 输出钳位跟随 / Clamped tracking output
            fInt    := fOut - fP - fD;                          // 积分反算同步 / Back-calculated integral
            fErrF   := fErr;        // 滤波偏差同步 / Sync prefiltered error
            fErrFPrev := fErr;      // 上拍滤波偏差同步 / Sync previous prefiltered error
            fErrPrev1 := fErr;      // 增量式历史同步 / Sync incremental history
            fErrPrev2 := fErr;      // 增量式历史同步 / Sync incremental history
            fIntPart := fInt;       // 诊断分量刷新 / Refresh diagnostic component
        ELSIF bIncremental THEN
            (* 增量式：PID 增量作用于输出累积，天然抗饱和由限幅兜底 *)
            (* Incremental form: PID delta applied to output accumulation *)
            fDelta := fKp * (fErr - fErrPrev1);                 // 比例增量 [%] / Proportional delta
            IF tTi > T#0S THEN
                fDelta := fDelta + fKp * fErr * fDt / (TIME_TO_REAL(tTi) / 1000.0);  // 积分增量 / Integral delta
            END_IF
            IF tTd > T#0S THEN
                fDelta := fDelta + fKp * (TIME_TO_REAL(tTd) / 1000.0) / fDt
                          * (fErr - 2.0 * fErrPrev1 + fErrPrev2);  // 微分增量 / Derivative delta
            END_IF
            fOut := LIMIT(fLimLow, fOut + fDelta, fLimHigh);    // 输出累积并限幅 / Accumulate and clamp
            fErrPrev2 := fErrPrev1;                             // 历史滚动 / Roll history
            fErrPrev1 := fErr;                                  // 历史滚动 / Roll history
            fIntPart  := fOut - fP - fD;                        // 诊断分量 / Diagnostic component
            IF ((fOut >= fLimHigh) AND (fDelta > 0.0))
               OR ((fOut <= fLimLow) AND (fDelta < 0.0)) THEN
                bLimitHigh := (fOut >= fLimHigh);               // 触上限标志 / Upper saturation flag
                bLimitLow  := (fOut <= fLimLow);                // 触下限标志 / Lower saturation flag
                IF uErrorId = 16#0002_0000 THEN
                    uErrorId := 16#0002_0101;                   // 信息级：输出饱和提示 / Info: output saturated
                END_IF
            END_IF
        ELSE
            (* 位置式：先做微分预滤波，再做积分分离与两级抗饱和 *)
            (* Positional: derivative prefilter, then conditional integration and back-calc *)
            IF tTd > T#0S THEN
                fTdS   := TIME_TO_REAL(tTd) / 1000.0;           // 微分时间换算秒 [s] / Derivative time in seconds
                fAlpha := fDt / (0.1 * fTdS + fDt);             // 预滤波权重 [0..1] / Prefilter weight
                fErrF  := fErrF + fAlpha * (fErr - fErrF);      // 一阶预滤波递推 / First-order prefilter recursion
                fD     := fKp * fTdS / fDt * (fErrF - fErrFPrev);  // 微分项 [%] / Derivative term
                fErrFPrev := fErrF;                             // 滚动滤波历史 / Roll filtered history
            ELSE
                fD        := 0.0;                               // 微分关闭 / Derivative disabled
                fErrF     := fErr;                              // 滤波偏差直通 / Prefiltered error follows
                fErrFPrev := fErr;                              // 上拍滤波偏差同步 / Sync previous value
            END_IF
            fPre := fP + fD + fInt;                             // 当前积分下的预输出 [%] / Pre-output with current integral
            bSkipInt := (fPre > fLimHigh AND fErr > 0.0)
                     OR (fPre < fLimLow  AND fErr < 0.0);       // 积分分离判定 / Conditional integration test
            IF (tTi > T#0S) AND (NOT bSkipInt) THEN
                fInt := fInt + fKp * fErr * fDt / (TIME_TO_REAL(tTi) / 1000.0);  // 条件积分 / Conditional integration
            END_IF
            fInt := LIMIT(-DL_PID_ERR_MAX, fInt, DL_PID_ERR_MAX);  // 积分钳位防溢出 / Clamp integral against overflow
            fPre := fP + fD + fInt;                             // 二次合成预输出 [%] / Recomposed pre-output
            IF fPre > fLimHigh THEN
                fOut := fLimHigh;                               // 输出钳上限 / Output at upper limit
                fInt := fLimHigh - fP - fD;                     // 反算回填积分 / Back-calculated integral
                bLimitHigh := TRUE;                             // 触上限标志 / Upper saturation flag
                IF uErrorId = 16#0002_0000 THEN
                    uErrorId := 16#0002_0101;                   // 信息级：输出饱和提示 / Info: output saturated
                END_IF
            ELSIF fPre < fLimLow THEN
                fOut := fLimLow;                                // 输出钳下限 / Output at lower limit
                fInt := fLimLow - fP - fD;                      // 反算回填积分 / Back-calculated integral
                bLimitLow := TRUE;                              // 触下限标志 / Lower saturation flag
                IF uErrorId = 16#0002_0000 THEN
                    uErrorId := 16#0002_0101;                   // 信息级：输出饱和提示 / Info: output saturated
                END_IF
            ELSE
                fOut := fPre;                                   // 正常输出 / Normal output
            END_IF
            fIntPart := fInt;                                   // 诊断分量刷新 / Refresh diagnostic component
        END_IF
        IF bManual THEN
            eState := eManual;                                  // 切手动 / Switch to manual
        END_IF
    eManual:
        (* 手动态：输出手动值（钳位），积分反算同步保证回自动瞬间输出连续 *)
        (* Manual: clamped manual output, integral back-calculated for bumpless return *)
        bActive := FALSE;                                       // 自动调节未激活 / Auto not active
        fErr := fSetpoint - fActual;                            // 偏差仍计算供诊断 / Error for diagnostics
        IF ABS(fErr) < fDeadbandEff THEN
            fErr := 0.0;                                        // 死区内偏差置 0 / Zero inside deadband
        END_IF
        (* 手动期间持续同步微分与增量式历史，杜绝切回自动瞬间的踢腿 *)
        (* Keep syncing derivative and incremental history in manual, no kick on auto return *)
        fErrF     := fErr;                                      // 微分滤波偏差同步 / Sync prefiltered error
        fErrFPrev := fErr;                                      // 上拍滤波偏差同步 / Sync previous prefiltered error
        fErrPrev1 := fErr;                                      // 增量式历史同步 / Sync incremental history
        fErrPrev2 := fErr;                                      // 增量式历史同步 / Sync incremental history
        fP := fKp * fErr;                                       // 比例项 [%] / Proportional term
        fD := 0.0;                                              // 手动下微分置 0 / Derivative zero in manual
        fManOut := LIMIT(fLimLow, fManualValue, fLimHigh);      // 手动值钳位 / Clamped manual value
        IF fManualValue > fLimHigh OR fManualValue < fLimLow THEN
            IF uErrorId = 16#0002_0000 THEN
                uErrorId := 16#0002_0102;                       // 手动值超限已钳位 / Manual value clamped
            END_IF
        END_IF
        fOut      := fManOut;                                   // 输出手动值 / Output manual value
        fInt      := fManOut - fP - fD;                         // 积分反算同步 / Back-calculated integral
        fInt      := LIMIT(-DL_PID_ERR_MAX, fInt, DL_PID_ERR_MAX);  // 积分钳位 / Clamp integral
        fIntPart  := fInt;                                      // 诊断分量刷新 / Refresh diagnostic component
        IF bTrack THEN
            fOut := LIMIT(fLimLow, fTrackValue, fLimHigh);      // 跟踪值优先 / Track value takes priority
            fInt := fOut - fP - fD;                             // 积分同步 / Integral in sync
        END_IF
        IF bInit THEN
            fErrF     := fErr;                                  // 滤波偏差同步 / Sync prefiltered error
            fErrFPrev := fErr;                                  // 上拍滤波偏差同步 / Sync previous value
            fErrPrev1 := fErr;                                  // 增量式历史同步 / Sync history
            fErrPrev2 := fErr;                                  // 增量式历史同步 / Sync history
            bInit     := FALSE;                                 // 清首扫标志 / Clear first-scan flag
        END_IF
        IF NOT bManual THEN
            eState := eAuto;                                    // 切自动 / Switch to auto
        END_IF
    eFault:
        (* 故障兜底态：输出安全下限，等待复位沿解除 *)
        (* Fault fallback: safe low-limit output, released by reset edge *)
        fOut    := fLimLow;                                     // 安全输出 / Safe output
        bActive := FALSE;                                       // 调节未激活 / Not active
    ELSE
        (* 非法状态拦截：任何未定义状态一律进故障兜底，不做隐式恢复 *)
        (* Illegal state interception: any undefined state goes to fault fallback *)
        eState   := eFault;                                     // 进故障态 / Enter fault state
        bError   := TRUE;                                       // 置故障标志 / Set fault flag
        uErrorId := 16#0002_0005;                               // 非法状态兜底码 / Illegal state fallback code
        fOut     := fLimLow;                                    // 安全输出 / Safe output
END_CASE;
(* 信息级码（0101 输出饱和 / 0102 手动值钳位）不置故障标志，防下游报警误动作 *)
(* Info-level codes (saturation / manual clamp) never raise the fault flag *)
bError := (uErrorId <> 16#0002_0000) AND (uErrorId <> 16#0002_0101)
          AND (uErrorId <> 16#0002_0102);                        // 非信息级码才置故障 / Fault flag only on non-info codes
END_FUNCTION_BLOCK
