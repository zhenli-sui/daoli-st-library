(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoopWaveInject
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : PID 回路调试激励源：正弦/方波/阶跃三型可选，输出经
 *                         委托 FB_DL_RateLimiter 斜率保护后叠加到给定值。
 *                         相位累加器按采样周期推进（周期越界钳制）；
 *                         使能撤销后目标平滑归零（经限速器自然回零），
 *                         完全禁用期间输出冻结 0，不塞伪值。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_WaveType / TYPE E_DL_InjErr /
 *                         FUNCTION_BLOCK FB_DL_LoopWaveInject
 * 依赖 (Depends)        : DL_Algo/FB_DL_RateLimiter、DL_MathData/FC_DL_TimeToLrealSec
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         防除零 + 量程钳位 + 非有限值防御 ｜ 枚举成员全部显式赋值
 *                         委托限速器实例每周期无条件调用（仅输入条件化）｜
 *                         相位累加器每周期无条件刷新 ｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0002_3710 就绪
 *                         16#0002_3711 信息级 幅值越界(已钳制)
 *                         16#0002_3712 信息级 周期非法(已钳制)
 *                         16#0002_3713 信息级 斜率限制非法(已钳制)
 *                         16#0002_3714 信息级 注入激活中
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 1
 * 验收向量 (Acceptance) : SIN 幅 10% 周期 10 s → 输出 5 Hz 采样下按 2*pi*相位 正弦；
 *                         幅值 120 → 钳 100 且 3711；周期 0 → 钳下限且 3712；
 *                         bEnable 撤销 → 输出按斜率回零后冻结 0
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_WaveType（归属 DL_Algo，波形类型）
 *----------------------------------------------------------------------------*)
TYPE E_DL_WaveType :
(
    eWaveSin  := 0,    // 正弦波 / Sine wave
    eWaveSqr  := 1,    // 方波（半周期正半幅，半周期负半幅）/ Square wave
    eWaveStep := 2     // 阶跃（激活期间恒幅）/ Step wave
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_InjErr（归属 DL_Algo，与 FB_DL_LoopWaveInject 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_InjErr :
(
    eReady      := 16#0002_3710,    // 就绪 / Ready
    eAmpClamped := 16#0002_3711,    // 信息级：幅值越界已钳制 / Info: amplitude clamped
    ePeriodBad  := 16#0002_3712,    // 信息级：周期非法已钳制 / Info: period clamped
    eSlewBad    := 16#0002_3713,    // 信息级：斜率限制非法已钳制 / Info: slew limit clamped
    eActive     := 16#0002_3714     // 信息级：注入激活中 / Info: injection active
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_LoopWaveInject
 * 调用约定: 每个扫描周期无条件调用一次；tSampleTime 必须注入真实任务间隔。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_LoopWaveInject
VAR_INPUT
    bEnable      : BOOL;               // 注入使能 / Injection enable
    eWaveType    : E_DL_WaveType;      // 波形类型 SIN/SQR/STEP / Wave type selection
    fAmplitude   : REAL;               // 幅值 [百分数]，有效域 0~100 / Amplitude [percent]
    fPeriod_s    : REAL;               // 周期 [秒]，有效域 0.1~600 / Period [s]
    fSlewLimit   : REAL;               // 斜率限制 [百分数每秒]，有效域 0.01~100 / Slew limit [percent per s]
    tSampleTime  : TIME := T#100MS;    // 采样周期，调用方注入真实任务间隔 / Sample period, caller-injected task interval
END_VAR
VAR_OUTPUT
    fInjectOut   : REAL;               // 注入量 [百分数] / Injection output [percent]
    bActive      : BOOL;               // 注入有效（输出非零或正在回零）/ Injection active flag
    eErr         : E_DL_InjErr;        // 错误码 / Error code
END_VAR
VAR
    fbLimiter    : FB_DL_RateLimiter;  // 委托限速器实例（每周期无条件调用）/ Delegate rate limiter instance
    fPhase       : REAL;               // 相位累加器 [0~1)，无量纲 / Phase accumulator [0..1)
    fAmpUse      : REAL;               // 生效幅值（钳位后）[百分数] / Effective amplitude [percent]
    fPeriodUse   : REAL;               // 生效周期（钳位后）[秒] / Effective period [s]
    fSlewUse     : REAL;               // 生效斜率（钳位后）[百分数每秒] / Effective slew limit [percent per s]
    fDtSec       : LREAL;              // 采样周期秒值（委托换算）[秒] / Sample period in seconds via delegate
    fWaveTarget  : REAL;               // 波形目标值（限速器输入）[百分数] / Wave target value, limiter input [percent]
    fTwoPi       : REAL := 6.283185307179586;   // 圆周率二倍 [弧度] / Two pi [rad]
    bLimErr      : BOOL;               // 委托限速器故障位 / Delegate rate limiter fault bit
END_VAR
VAR CONSTANT
    DL_INJ_AMP_MIN    : REAL := 0.0;    // 幅值下限 [百分数] / Amplitude lower bound [percent]
    DL_INJ_AMP_MAX    : REAL := 100.0;  // 幅值上限 [百分数] / Amplitude upper bound [percent]
    DL_INJ_PERIOD_MIN : REAL := 0.1;    // 周期下限 [秒] / Period lower bound [s]
    DL_INJ_PERIOD_MAX : REAL := 600.0;  // 周期上限 [秒] / Period upper bound [s]
    DL_INJ_SLEW_MIN   : REAL := 0.01;   // 斜率下限 [百分数每秒] / Slew lower bound [percent per s]
    DL_INJ_SLEW_MAX   : REAL := 100.0;  // 斜率上限 [百分数每秒] / Slew upper bound [percent per s]
    DL_INJ_INF_MAX    : REAL := 1.0E30; // 非有限值判定幅值上限 / Magnitude bound for finite-value check
    DL_INJ_ZERO       : REAL := 0.0;    // 零值常量，避免裸字面量 / Zero constant
    DL_INJ_TOL        : REAL := 1.0E-6; // 浮点比较容差 / Float comparison tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜委托限速器每周期无条件调用（仅输入条件化）：斜率保护永不断流
 *----------------------------------------------------------------------------*)
fbLimiter(bEnable := TRUE,                    // 限速器自身常开，方向限速由 fRate 引脚承载 / limiter always enabled
          fIn := fWaveTarget,                 // 波形目标作为限速输入 / wave target as limiter input
          fRateUp := fSlewUse,                // 上升斜率限制 [百分数每秒] / rising slew limit
          fRateDown := fSlewUse,              // 下降斜率限制（回零同样受保护）/ falling slew limit
          bTrack := FALSE,                    // 不使用跟踪回投 / no tracking
          fTrackValue := DL_INJ_ZERO,         // 跟踪值未用 / track value unused
          tSampleTime := tSampleTime,         // 采样周期透传 / sample period passed through
          fOut => fInjectOut,                 // 限速输出直接对外 / rate-limited output exported
          bError => bLimErr);                 // 委托故障位回收 / delegate fault bit captured

(*------------------------------------------------------------------------------
 * 段 2｜非有限值与参数钳位：越界钳制并置信息码（先到先得，斜率最后判）
 *----------------------------------------------------------------------------*)
IF (fAmplitude <> fAmplitude) OR (ABS(fAmplitude) > DL_INJ_INF_MAX) THEN
    fAmpUse := DL_INJ_AMP_MAX;                       // 非有限幅值按上限处置 / non-finite amplitude treated as upper bound
    eErr := E_DL_InjErr.eAmpClamped;                 // 信息级：幅值越界 / info: amplitude clamped
ELSIF fAmplitude < DL_INJ_AMP_MIN THEN
    fAmpUse := DL_INJ_AMP_MIN;                       // 下限钳位 / floored
    eErr := E_DL_InjErr.eAmpClamped;                 // 信息级：幅值越界 / info: amplitude clamped
ELSIF fAmplitude > DL_INJ_AMP_MAX THEN
    fAmpUse := DL_INJ_AMP_MAX;                       // 上限钳位 / capped
    eErr := E_DL_InjErr.eAmpClamped;                 // 信息级：幅值越界 / info: amplitude clamped
ELSE
    fAmpUse := fAmplitude;                           // 幅值域内 / amplitude in range
END_IF
IF (fPeriod_s <> fPeriod_s) OR (ABS(fPeriod_s) > DL_INJ_INF_MAX) THEN
    fPeriodUse := DL_INJ_PERIOD_MIN;                 // 非有限周期按下限处置（防除零）/ non-finite period treated as lower bound
    IF eErr = E_DL_InjErr.eReady THEN
        eErr := E_DL_InjErr.ePeriodBad;              // 信息级：周期非法 / info: period clamped
    END_IF
ELSIF fPeriod_s < DL_INJ_PERIOD_MIN THEN
    fPeriodUse := DL_INJ_PERIOD_MIN;                 // 周期下限钳位（防除零）/ period floored
    IF eErr = E_DL_InjErr.eReady THEN
        eErr := E_DL_InjErr.ePeriodBad;              // 信息级：周期非法 / info: period clamped
    END_IF
ELSIF fPeriod_s > DL_INJ_PERIOD_MAX THEN
    fPeriodUse := DL_INJ_PERIOD_MAX;                 // 周期上限钳位 / period capped
    IF eErr = E_DL_InjErr.eReady THEN
        eErr := E_DL_InjErr.ePeriodBad;              // 信息级：周期非法 / info: period clamped
    END_IF
ELSE
    fPeriodUse := fPeriod_s;                         // 周期域内 / period in range
END_IF
IF (fSlewLimit <> fSlewLimit) OR (ABS(fSlewLimit) > DL_INJ_INF_MAX) THEN
    fSlewUse := DL_INJ_SLEW_MAX;                     // 非有限斜率按上限处置 / non-finite slew treated as upper bound
    IF eErr = E_DL_InjErr.eReady THEN
        eErr := E_DL_InjErr.eSlewBad;                // 信息级：斜率非法 / info: slew clamped
    END_IF
ELSIF (fSlewLimit < DL_INJ_SLEW_MIN) OR (fSlewLimit > DL_INJ_SLEW_MAX) THEN
    IF fSlewLimit < DL_INJ_SLEW_MIN THEN
        fSlewUse := DL_INJ_SLEW_MIN;                 // 斜率下限钳位 / slew floored
    ELSE
        fSlewUse := DL_INJ_SLEW_MAX;                 // 斜率上限钳位 / slew capped
    END_IF
    IF eErr = E_DL_InjErr.eReady THEN
        eErr := E_DL_InjErr.eSlewBad;                // 信息级：斜率非法 / info: slew clamped
    END_IF
ELSE
    fSlewUse := fSlewLimit;                          // 斜率域内 / slew in range
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜采样周期委托换算（FC_DL_TimeToLrealSec）与除零防御
 *----------------------------------------------------------------------------*)
fDtSec := FC_DL_TimeToLrealSec(tIn := tSampleTime);  // 采样周期秒值（委托换算）/ sample period in seconds via delegate
IF (fDtSec <> fDtSec) OR (fDtSec < DL_INJ_TOL) OR (fDtSec > REAL_TO_LREAL(DL_INJ_INF_MAX)) THEN
    fDtSec := LREAL#0.1;                             // 非法采样周期按 0.1 s 兜底（防除零）/ illegal sample period falls back to 0.1 s
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜相位累加器：每周期无条件推进，按波形周期归一化回卷
 *----------------------------------------------------------------------------*)
IF bEnable THEN
    fPhase := fPhase + LREAL_TO_REAL(fDtSec / REAL_TO_LREAL(fPeriodUse));   // 相位推进 [无量纲] / phase advance
    WHILE fPhase >= 1.0 DO
        fPhase := fPhase - 1.0;                      // 相位回卷 [0~1) / phase wrap into [0..1)
    END_WHILE
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜波形目标计算：CASE 含 ELSE 兜底（默认目标 0）
 *----------------------------------------------------------------------------*)
IF bEnable THEN
    CASE eWaveType OF
        E_DL_WaveType.eWaveSin:
            fWaveTarget := fAmpUse * SIN(fPhase * fTwoPi);          // 正弦目标 [百分数] / sine target [percent]
        E_DL_WaveType.eWaveSqr:
            IF fPhase < 0.5 THEN
                fWaveTarget := fAmpUse;                             // 方波正半幅 [百分数] / square positive half [percent]
            ELSE
                fWaveTarget := -fAmpUse;                            // 方波负半幅 [百分数] / square negative half [percent]
            END_IF
        E_DL_WaveType.eWaveStep:
            fWaveTarget := fAmpUse;                                 // 阶跃恒幅目标 [百分数] / step target [percent]
        ELSE
            fWaveTarget := DL_INJ_ZERO;                             // 非法波形兜底目标 0 / illegal wave type, target zero
    END_CASE
    bActive := TRUE;                                 // 注入激活 / injection active
    IF eErr = E_DL_InjErr.eReady THEN
        eErr := E_DL_InjErr.eActive;                 // 信息级：注入激活中 / info: injection active
    END_IF
ELSE
    fWaveTarget := DL_INJ_ZERO;                      // 禁用目标 0（经限速器平滑回零）/ disabled target zero, slews down
    bActive := ABS(fInjectOut) > DL_INJ_TOL;         // 回零期间仍视为激活 / active while settling to zero
    IF ABS(fInjectOut) <= DL_INJ_TOL THEN
        fInjectOut := DL_INJ_ZERO;                   // 回零完成冻结 0（禁用期不塞伪值）/ settled frozen at zero
        bActive := FALSE;                            // 注入失效 / injection inactive
        fPhase := DL_INJ_ZERO;                       // 相位复位（下次启用从零相位起）/ phase reset for next enable
    END_IF
END_IF
END_FUNCTION_BLOCK
