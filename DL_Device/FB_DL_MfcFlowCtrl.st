(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MfcFlowCtrl
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : MFC 设定-回读校验：新设定上升沿启动跟踪窗，窗内峰值
 *                         对设定+超调阈判超调；回读持续 tStable 在容差窗内判
 *                         入容差；跟踪窗超时（tStable x 5）未入窗 → 稳定超时故障。
 *                         设定 0 视为关断不校验；回读 NaN/越量程判无效冻结。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_MfcState / TYPE E_DL_MfcErr /
 *                         FUNCTION_BLOCK FB_DL_MfcFlowCtrl
 * 依赖 (Depends)        : DL_MathData/FC_DL_TimeToDintMs、DL_MathData/FC_DL_TimeScaleSat
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 参数下限钳制 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         TON/沿检测实例每周期无条件调用（仅 IN 条件化）｜
 *                         跟踪窗状态机 CASE 含 ELSE 兜底 ｜ 峰值检测用比较禁浮点判等
 * 错误码表 (Codes)      : 16#0003_0398 就绪
 *                         16#0003_0399 校验通过
 *                         16#0003_039A 信息级 超调检出（不阻断判据）
 *                         16#0003_039B 故障级 稳定超时
 *                         16#0003_039C 故障级 回读无效（冻结判定）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 2
 *                         2026-11-17  v1.0.1  R27 终审修复（对外引脚零变更）：超调峰值改为
 *                         「首次入窗后才累积、初值取设定」。原实现 fPeakSlm 初值取当前回读，
 *                         降设定（如 20→10 slm）时回读 20 立即满足 20−10 > 超调阈，
 *                         每次下调设定必误报 039A 超调；改为入窗锁存后，仅真实向上超调计入。
 * 验收向量 (Acceptance) : 设定 10 slm 容差 2%FS 超调阈 5%FS：回读峰值 11.0 slm
 *                         → 超调 10%FS → 039A；回读持续 5 s 在 9.8~10.2 → 0399；
 *                         回读 8 slm 持续 25 s → 039B
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MfcState（归属 DL_Device，跟踪窗状态机状态）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MfcState :
(
    eIdle    := 0,    // 就绪待新设定 / Idle, waiting for a new setpoint
    eTrack   := 10,   // 跟踪窗：峰值检测与入窗监视 / Tracking window, peak and entry watch
    eStable  := 20,   // 稳定窗：持续容差内计时 / Stable window, dwell timing
    eDone    := 30,   // 校验通过（可被新设定重开）/ Verification passed
    eTimeout := 40,   // 稳定超时故障 / Stable timeout fault
    eFault   := 99    // 回读无效兜底态 / Readback-invalid fallback
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MfcErr（归属 DL_Device，与 FB_DL_MfcFlowCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MfcErr :
(
    eReady      := 16#0003_0398,   // 就绪 / Ready
    ePass       := 16#0003_0399,   // 校验通过 / Verification passed
    eOvershoot  := 16#0003_039A,   // 信息级：超调检出 / Info: overshoot detected
    eStableTmo  := 16#0003_039B,   // 故障级：稳定超时 / Fault: stable timeout
    eReadbackBad:= 16#0003_039C    // 故障级：回读无效 / Fault: readback invalid
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_MfcFlowCtrl
 * 调用约定: 每个扫描周期无条件调用一次；tSampleTime 注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_MfcFlowCtrl
VAR_INPUT
    fSetpointSlm   : REAL;            // 设定流量 [标准升每分钟]，有效域 0~满量程 / Setpoint flow [slm]
    fReadbackSlm   : REAL;            // 回读流量 [标准升每分钟] / Readback flow [slm]
    fScaleMaxSlm   : REAL;            // MFC 满量程 [标准升每分钟]，须 > 0 / MFC full scale [slm]
    fTolPct        : REAL := 2.0;     // 容差 [%FS]，默认 2，下限钳 0.5 / Tolerance [percent of FS]
    fOvershootPct  : REAL := 5.0;     // 超调判据 [%FS]，默认 5，下限钳 0.5 / Overshoot criterion [percent of FS]
    tStable        : TIME := T#5S;    // 稳定窗时长 [秒] / Stable window duration [s]
    bNewSp         : BOOL;            // 新设定触发（上升沿）/ New setpoint trigger, rising edge
    tSampleTime    : TIME := T#100MS; // 采样周期，调用方注入 / Sample period, caller-injected
END_VAR
VAR_OUTPUT
    bInTol         : BOOL;            // 入容差标志 / Within-tolerance flag
    bOvershoot     : BOOL;            // 超调检出标志 / Overshoot detected flag
    tSettleMs      : UDINT;           // 实测稳定时间 [毫秒] / Measured settle time [ms]
    eError         : E_DL_MfcErr;     // 错误码 / Error code
    eState         : E_DL_MfcState;   // 跟踪窗状态机当前状态 / Tracking window state
END_VAR
VAR
    fbNewSpTrig    : R_TRIG;          // 新设定上升沿实例（无条件调用）/ New setpoint edge instance
    fbTonStable    : TON;             // 稳定窗计时器（无条件调用）/ Stable window timer
    fbTonWindow    : TON;             // 跟踪窗超时计时器（无条件调用）/ Tracking window timeout timer
    fPeakSlm       : REAL;            // 跟踪窗内回读峰值 [标准升每分钟] / Readback peak in window [slm]
    fTolAbs        : REAL;            // 容差绝对值 [标准升每分钟] / Tolerance in absolute flow [slm]
    fOverAbs       : REAL;            // 超调阈绝对值 [标准升每分钟] / Overshoot threshold in absolute flow [slm]
    fSpUse         : REAL;            // 生效设定（NaN 兜底）[标准升每分钟] / Effective setpoint [slm]
    fScaleUse      : REAL;            // 生效满量程（NaN 兜底）[标准升每分钟] / Effective full scale [slm]
    bReadOk        : BOOL;            // 回读有效性判据 / Readback validity predicate
    uMsErr         : UDINT;           // 委托时间换算错误码（0 = 无错）/ Delegate time-conversion error id
    bInWin         : BOOL;            // 回读在容差窗内（瞬时）/ Readback within window, instantaneous
    bReached       : BOOL;            // 本窗内首次入窗锁存（v1.0.1：峰值仅此后计入）/ First-in-window latch, peak counted afterwards
END_VAR
VAR CONSTANT
    DL_MFC_TOL_MIN    : REAL := 0.5;     // 容差下限 [%FS] / Tolerance lower bound [percent FS]
    DL_MFC_OVER_MIN   : REAL := 0.5;     // 超调阈下限 [%FS] / Overshoot lower bound [percent FS]
    DL_MFC_PCT        : REAL := 100.0;   // 百分数系数 [百分数] / Percent factor
    DL_MFC_WINDOW_K   : INT  := 5;       // 跟踪窗超时倍率（tStable x 5）/ Tracking window timeout multiplier
    DL_MFC_INF_MAX    : REAL := 1.0E30;  // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_MFC_ZERO       : REAL := 0.0;     // 零值常量，避免裸字面量 / Zero constant
    DL_MFC_MS_CAP     : UDINT := 16#FFFF_FFFE;   // 稳定时间输出饱和值 [毫秒] / Settle time saturation [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测与 TON 实例每周期无条件调用（仅 IN 条件化）
 *----------------------------------------------------------------------------*)
fbNewSpTrig(CLK := bNewSp);                           // 新设定沿检测无条件刷新 / new setpoint edge refreshed unconditionally
fbTonStable(IN := (eState = E_DL_MfcState.eStable) AND bInWin, PT := tStable);        // 稳定窗计时 / stable dwell timing
fbTonWindow(IN := (eState = E_DL_MfcState.eTrack), PT := FC_DL_TimeScaleSat(tIn := tStable, nScale := DL_MFC_WINDOW_K));   // 跟踪窗超时计时（tStable x 5，委托换算）/ tracking window timing via delegate

(*------------------------------------------------------------------------------
 * 段 2｜参数防御：满量程/设定 NaN 兜底，容差与超调下限钳 0.5 %FS
 *----------------------------------------------------------------------------*)
fScaleUse := fScaleMaxSlm;                            // 满量程工作副本 / full-scale working copy
IF (fScaleUse <> fScaleUse) OR (fScaleUse <= DL_MFC_ZERO) OR (fScaleUse > DL_MFC_INF_MAX) THEN
    fScaleUse := 100.0;                               // 满量程非法按 100 slm 兜底 / illegal full scale falls back to 100 slm
END_IF
fSpUse := fSetpointSlm;                               // 设定工作副本 / setpoint working copy
IF (fSpUse <> fSpUse) OR (ABS(fSpUse) > DL_MFC_INF_MAX) THEN
    fSpUse := DL_MFC_ZERO;                            // 设定非有限按 0（关断语义）/ non-finite setpoint treated as zero
END_IF
IF fTolPct < DL_MFC_TOL_MIN THEN
    fTolAbs := fScaleUse * DL_MFC_TOL_MIN / DL_MFC_PCT;   // 容差下限钳制 [标准升每分钟] / tolerance floored [slm]
ELSIF fTolPct > DL_MFC_PCT THEN
    fTolAbs := fScaleUse;                             // 容差上限钳制（满量程封顶）/ tolerance capped at FS
ELSE
    fTolAbs := fScaleUse * fTolPct / DL_MFC_PCT;      // 容差换算 [标准升每分钟] / tolerance computed [slm]
END_IF
IF fOvershootPct < DL_MFC_OVER_MIN THEN
    fOverAbs := fScaleUse * DL_MFC_OVER_MIN / DL_MFC_PCT;   // 超调阈下限钳制 / overshoot floored
ELSIF fOvershootPct > DL_MFC_PCT THEN
    fOverAbs := fScaleUse;                            // 超调阈上限钳制 / overshoot capped at FS
ELSE
    fOverAbs := fScaleUse * fOvershootPct / DL_MFC_PCT;   // 超调阈换算 / overshoot computed
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜回读有效性判据：NaN/越量程/负值判无效（bReadOk 为 FALSE 时冻结判定）
 *----------------------------------------------------------------------------*)
bReadOk := (fReadbackSlm = fReadbackSlm)                      // 自反判 NaN / NaN self-reflexive test
        AND (ABS(fReadbackSlm) <= DL_MFC_INF_MAX)             // 溢出判 / overflow test
        AND (fReadbackSlm >= DL_MFC_ZERO)                     // 负流量无效 / negative flow invalid
        AND (fReadbackSlm <= fScaleUse * 1.5);                // 越量程 150% 判无效 / over-range 150 percent invalid

(*------------------------------------------------------------------------------
 * 段 4｜瞬时入窗判据：|回读 - 设定| <= 容差（比较判据，禁浮点判等）
 *----------------------------------------------------------------------------*)
bInWin := bReadOk AND (ABS(fReadbackSlm - fSpUse) <= fTolAbs);   // 瞬时入窗 / instantaneous in-window
IF bInWin THEN
    bReached := TRUE;                                 // v1.0.1：首次入窗锁存，此后峰值才计 / latch on first entry, peak counted after
END_IF
bInTol := bInWin AND fbTonStable.Q AND (eState <> E_DL_MfcState.eIdle);   // 入容差 = 瞬时 + 持续达时 / in-tol combined

(*------------------------------------------------------------------------------
 * 段 5｜新设定上升沿：重开跟踪窗（设定 0 关断不校验，直回就绪）
 *----------------------------------------------------------------------------*)
IF fbNewSpTrig.Q THEN
    IF (fSpUse <= DL_MFC_ZERO) OR (NOT bReadOk) THEN
        eState := E_DL_MfcState.eIdle;                // 设定 0 或回读无效：不启动校验 / zero setpoint or bad readback: no verify
    ELSE
        eState := E_DL_MfcState.eTrack;               // 启动跟踪窗 / start tracking window
        fPeakSlm := fSpUse;                           // v1.0.1：峰值初值取设定而非回读 / peak preset to setpoint, not readback
        bReached := FALSE;                            // v1.0.1：首次入窗锁存清零 / first-entry latch cleared
        bOvershoot := FALSE;                          // 超调标志清零 / overshoot flag cleared
        tSettleMs := 0;                               // 稳定时间清零 / settle time cleared
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜跟踪窗状态机：CASE 含 ELSE 兜底
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_MfcState.eIdle:
        bInTol := FALSE;                              // 就绪态无入容差 / no in-tol in idle
        bOvershoot := FALSE;                          // 就绪态无超调 / no overshoot in idle
        tSettleMs := 0;                               // 稳定时间清零 / settle time cleared
        eError := E_DL_MfcErr.eReady;                 // 码 0398 / code ready

    E_DL_MfcState.eTrack:
        IF bReadOk AND bReached THEN
            IF fReadbackSlm > fPeakSlm THEN
                fPeakSlm := fReadbackSlm;             // 峰值更新（仅首次入窗后计入，禁浮点判等）/ peak after first entry
            END_IF
            IF (fPeakSlm - fSpUse) > fOverAbs THEN
                bOvershoot := TRUE;                   // 超调检出 / overshoot detected
            END_IF
        END_IF
        IF NOT bReadOk THEN
            eState := E_DL_MfcState.eFault;           // 回读无效：冻结进兜底态 / readback invalid: freeze to fallback
            eError := E_DL_MfcErr.eReadbackBad;       // 故障级：回读无效 / fault: readback invalid
        ELSIF bInWin AND fbTonStable.Q THEN
            eState := E_DL_MfcState.eDone;            // 窗内已达标：直接通过（极快稳定路径）/ fast-pass path
        ELSIF bInWin THEN
            eState := E_DL_MfcState.eStable;          // 入窗：进稳定窗 / entered window: stable phase
        ELSIF fbTonWindow.Q THEN
            eState := E_DL_MfcState.eTimeout;         // 跟踪窗超时（tStable x 5）/ tracking window timeout
            eError := E_DL_MfcErr.eStableTmo;         // 故障级：稳定超时 / fault: stable timeout
        ELSE
            eError := E_DL_MfcErr.eReady;             // 跟踪中先挂就绪码 / ready code while tracking
        END_IF

    E_DL_MfcState.eStable:
        IF NOT bReadOk THEN
            eState := E_DL_MfcState.eFault;           // 回读无效：冻结进兜底态 / readback invalid: freeze
            eError := E_DL_MfcErr.eReadbackBad;       // 故障级：回读无效 / fault: readback invalid
        ELSIF fbTonStable.Q THEN
            eState := E_DL_MfcState.eDone;            // 持续在窗达 tStable：通过 / dwell met: passed
            IF bOvershoot THEN
                eError := E_DL_MfcErr.eOvershoot;     // 信息级：超调检出（通过但留痕）/ info: overshoot noted
            ELSE
                eError := E_DL_MfcErr.ePass;          // 码 0399 / code pass
            END_IF
            tSettleMs := DINT_TO_UDINT(FC_DL_TimeToDintMs(tIn := fbTonStable.ET, eErr => uMsErr));   // 实测稳定时间委托换算 [毫秒] / settle time via delegate [ms]
            IF (uMsErr <> 0) OR (tSettleMs > DL_MFC_MS_CAP) THEN
                tSettleMs := DL_MFC_MS_CAP;           // 换算失败或越界：饱和输出 / conversion failure saturates
            END_IF
        ELSIF NOT bInWin THEN
            eState := E_DL_MfcState.eTrack;           // 出窗：回跟踪窗继续监视（计时随 IN 断开自清）/ left window: back to tracking
            eError := E_DL_MfcErr.eReady;             // 回挂就绪码 / ready code again
        END_IF

    E_DL_MfcState.eDone:
        bInTol := TRUE;                               // 通过态保持入容差显示 / in-tol held on pass
        IF fbNewSpTrig.Q THEN
            eError := E_DL_MfcErr.eReady;             // 新设定沿已由段 5 处理 / new setpoint handled in section 5
        END_IF

    E_DL_MfcState.eTimeout:
        bInTol := FALSE;                              // 超时态入容差撤销 / in-tol dropped on timeout
        // 稳定超时为故障级：码 039B 已在转出时置位，保持至新设定沿 / fault code 039B held until next setpoint edge

    E_DL_MfcState.eFault:
        bInTol := FALSE;                              // 兜底态入容差撤销 / in-tol dropped
        IF NOT bReadOk THEN
            eError := E_DL_MfcErr.eReadbackBad;       // 回读仍无效：保持故障码 / readback still invalid: hold code
        ELSE
            eState := E_DL_MfcState.eIdle;            // 回读恢复：自动回就绪 / readback recovered: back to idle
            eError := E_DL_MfcErr.eReady;             // 回就绪码 / ready code
        END_IF

    ELSE
        eState := E_DL_MfcState.eFault;               // 非法状态兜底 / illegal-state fallback
        eError := E_DL_MfcErr.eReadbackBad;           // 兜底码（回读无效段，反证句：输出同为全撤+故障级）/ fallback code
        bInTol := FALSE;                              // 入容差撤 / in-tol dropped
        bOvershoot := FALSE;                          // 超调撤 / overshoot dropped

END_CASE
END_FUNCTION_BLOCK
