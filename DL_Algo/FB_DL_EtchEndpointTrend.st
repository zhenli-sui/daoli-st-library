(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EtchEndpointTrend
 * 所属子库 (Sublibrary) : DL_Algo
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 TON / ABS / MAX / MIN 与库内
 *                         FB_DL_Differentiator（IN-OUT 注入消费），
 *                         零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 刻蚀终点趋势检测公开工艺语义（行业池主源；
 *                         Measurement 行统计族语义邻接不重复记账），道莅
 *                         clean-room 防御性实现，未复制任何外部源码行
 * 功能描述 (Function)   : 刻蚀终点趋势双判据检测件。学习相采基线（均值与
 *                         噪声窗）；监视相用库内 FB_DL_Differentiator 求变化
 *                         率（IN-OUT 注入，不内联），斜率换算为 单位每分钟；
 *                         双判据：斜率绝对值超阈 且 信号突破噪声窗，持续
 *                         tConf 触发终点并锁存，保持至 bRun 下降显式复位。
 *                         斜率量纲占位说明：fSignal 的工程单位由调用方定义，
 *                         fSlope 与 fSlopeTh 同量纲，单位为 调用方单位每分钟。
 * 依赖表   (Depends)    : FB_DL_Differentiator（微分器，IN-OUT 注入消费，
 *                         本件不内联差分）。
 * 状态机   (States)     : eLearning/eMonitor/eTriggered，CASE 带 ELSE 复位
 *                         回学习相（信息级提示）。
 * 码位     (Codes)      : 16#0002_3033 信息级：信号非有限冻结评估、学习相
 *                                      非有限重启学习、样本不足不出判定
 *                                      （不置 bError）
 *                         16#0002_3034 故障级：确认窗中断判据矛盾（锁存）
 *                         16#0002_3035~0037 保留未启用（码表与实现对齐）
 * 边界防错 (Boundary)   : 1 信号非有限（x<>x 自反判加幅值界）监视相冻结评估、
 *                           学习相清积累重启学习；
 *                         2 学习相样本不足不出判定；
 *                         3 斜率时间差防除零由库内微分器公共钳位承担
 *                           （其 fDt 下限 10 毫秒），本件不做二次除法；
 *                         4 TON 实例每拍无条件刷新；
 *                         5 触发锁存可达解除路径：bRun 下降沿显式复位；
 *                         6 确认窗中途判据消失按判据矛盾锁故障。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 20）
 *                         2026-11-18 v1.0.1 R31 终审修复：先验基线模式补
 *                         uCnt 计数，消除方差分母 1E-30 退化致判据二永假
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_EndpointState（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_EndpointState :
(
    eLearning  := 0,   // 学习相：采基线均值与噪声窗 / Learning, baseline mean and noise window
    eMonitor   := 10,  // 监视相：双判据评估 / Monitor, dual-criteria evaluation
    eTriggered := 20   // 触发相：终点锁存至显式复位 / Triggered, endpoint latched until explicit reset
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_EtchEndpointTrend
 * 调用约定: 每个扫描周期无条件调用一次；ioDiff 为调用方持有的库内微分器
 *           实例（IN-OUT 注入），本件驱动其引脚并读取其输出。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_EtchEndpointTrend
VAR_INPUT
    fSignal   : LREAL := 0.0;         // 工艺信号 [调用方单位] / Process signal [caller unit]
    bRun      : BOOL := FALSE;        // 工步运行（下降沿显式复位）/ Process running, falling edge resets
    fSlopeTh  : REAL := 5.0;          // 斜率判据阈 [调用方单位每分钟] / Slope threshold [caller unit per min]
    fNoiseWin : REAL := 2.0;          // 噪声窗 [调用方单位] / Noise window [caller unit]
    tConf     : TIME := T#3S;         // 触发确认窗时长 [毫秒] / Trigger confirm window [ms]
    fBaseline : LREAL := 0.0;         // 外部先验基线（0 = 无先验走自采）/ External prior baseline, 0 = none
    tLearn    : TIME := T#30S;        // 学习相时长 [毫秒]（可增引脚）/ Learning duration [ms], added pin
    tSample   : TIME := T#500MS;      // 微分器采样周期 [毫秒]（可增引脚）/ Differentiator sample period [ms], added pin
END_VAR
VAR_IN_OUT
    ioDiff    : FB_DL_Differentiator; // 库内微分器实例注入（斜率不内联）/ Library differentiator instance injected
END_VAR
VAR_OUTPUT
    bEndpoint : BOOL;                 // 终点触发锁存输出 / Endpoint trigger latched output
    fSlope    : REAL;                 // 斜率输出 [调用方单位每分钟] / Slope output [caller unit per min]
    eState    : E_DL_EndpointState;   // 判定状态 / Detection state
    bError    : BOOL;                 // 故障标志，与故障级码配对（R45）/ Fault flag paired with fault codes
    uErrorId  : UDINT;                // 错误码，0 = 无错 / Error code, 0 = none
END_VAR
VAR
    tonLearn  : TON;                  // 学习相计时，每拍无条件刷新 / Learning timer, refreshed every scan
    tonConf   : TON;                  // 触发确认窗计时，每拍无条件刷新 / Confirm window timer, refreshed every scan
    fSigR     : REAL;                 // 信号 REAL 域副本 [调用方单位] / Signal REAL copy [caller unit]
    bSigOk    : BOOL;                 // 信号有限有效 / Signal finiteness validity
    fSum      : REAL;                 // 学习相样本和 [调用方单位] / Learning sample sum [caller unit]
    fSumSq    : REAL;                 // 学习相平方和 [平方调用方单位] / Learning sum of squares
    uCnt      : UDINT;                // 学习相样本数 [个] / Learning sample count
    fMean     : REAL;                 // 基线均值 [调用方单位] / Baseline mean [caller unit]
    fNoise    : REAL;                 // 噪声窗实测 [调用方单位] / Measured noise window [caller unit]
    bLearnDone: BOOL;                 // 学习完成标志 / Learning done flag
    bCritSlope: BOOL;                 // 判据一：斜率超阈 / Criterion one, slope over threshold
    bCritNoise: BOOL;                 // 判据二：突破噪声窗 / Criterion two, beyond noise window
    bCritNow  : BOOL;                 // 双判据本拍合取 / Both criteria this scan
    bInWin    : BOOL;                 // 确认窗进行中 / Confirm window in progress
    bPriorUse : BOOL;                 // 先验基线使用标志 / Prior baseline usage flag
    uCodeLatch: UDINT;                // 故障级锁存码 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EET_FIN   : LREAL := 1.0E30;   // LREAL 有限幅值判界 / LREAL finiteness magnitude bound
    DL_EET_FINR  : REAL  := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness magnitude bound
    DL_EET_MIN   : UDINT := 20;       // 学习相最少样本数 [个] / Learning minimum samples
    DL_EET_MIN60 : REAL  := 60.0;     // 每秒到每分钟换算系数 / Per-second to per-minute factor
    DL_EET_EPS   : REAL  := 1.0E-30;  // 样本数防除零容差 / Sample count divide guard
END_VAR

// ---- 段 1｜定时器实例无条件周期刷新（红线：禁入条件分支）----------------------
tonLearn(IN := (eState = eLearning) AND bRun, PT := tLearn);   // 学习计时 / Learning timing
tonConf(IN := bCritNow, PT := tConf);                          // 确认窗计时无条件 / Confirm timing unconditionally

// ---- 段 2｜信号有效性（自反判加幅值界）----------------------------------------
bSigOk := (fSignal = fSignal) AND (ABS(fSignal) < DL_EET_FIN); // 信号有限 / Signal finite
fSigR := LREAL_TO_REAL(fSignal);                               // 信号落 REAL 域 / Signal to REAL domain

// ---- 段 3｜显式复位：bRun 下降沿清全部锁存 ------------------------------------
IF NOT bRun THEN
    bEndpoint := FALSE;                            // 复位清终点锁存 / Reset clears endpoint latch
    IF eState = eTriggered THEN
        eState := eLearning;                       // 触发相复位回学习 / Triggered resets to learning
    END_IF
END_IF

// ---- 段 4｜驱动库内微分器（IN-OUT 注入，输出即变化率 单位每秒）----------------
ioDiff(bEnable := bRun AND bSigOk,                    // 信号无效停微分防伪速率 / Invalid signal stops differentiator
       fIn := fSigR,                                  // 被微分量注入 / Differentiated input injected
       tFiltTime := T#1S,                             // 低通时间常数固定档 / Fixed low-pass constant
       tSampleTime := tSample);                       // 采样周期透传 / Sample period passed
fSlope := ioDiff.fRateOut * DL_EET_MIN60;             // 斜率换算每分钟（量纲占位见头注释）/ Slope per minute

// ---- 段 5｜学习相：采基线均值与噪声窗 ------------------------------------------
IF (eState = eLearning) AND bRun THEN
    IF NOT bSigOk THEN
        fSum := 0.0;                                  // 非有限清积累重启学习（信息级）/ Non-finite restarts learning
        fSumSq := 0.0;                                // 清平方和积累 / Clear sum-of-squares
        uCnt := 0;                                    // 清样本计数 / Clear sample count
        bLearnDone := FALSE;                          // 撤完成标志 / Withdraw done flag
        uErrorId := 16#0002_3033;                     // 信息级：学习重启 / Info: learning restarted
    ELSE
        bPriorUse := (fBaseline <> 0.0) AND (fBaseline = fBaseline)
                 AND (ABS(fBaseline) < DL_EET_FIN);   // 先验基线可用性 / Prior baseline availability
        IF bPriorUse THEN
            fMean := LREAL_TO_REAL(fBaseline);        // 先验均值直接生效 / Prior mean applied directly
            uCnt := uCnt + 1;                         // 先验模式同样计数（方差分母防爆，R28 终审）/ Prior mode counts samples too
        ELSE
            fSum := fSum + fSigR;                     // 自采样本累加 / Self-sample accumulation
            uCnt := uCnt + 1;                         // 样本计数 / Sample count
        END_IF
        fSumSq := fSumSq + fSigR * fSigR;             // 平方和积累（样本方差用）/ Sum of squares accumulation
        IF tonLearn.Q AND (bPriorUse OR (uCnt >= DL_EET_MIN)) THEN
            IF NOT bPriorUse THEN
                fMean := fSum / UDINT_TO_REAL(uCnt);  // 均值收口，分母已验下限 / Mean closed, denominator verified
            END_IF
            fNoise := SQRT(MAX(fSumSq / MAX(UDINT_TO_REAL(uCnt), DL_EET_EPS) - fMean * fMean, 0.0)); // 样本标准差收口（平方和法）/ Sample stddev via sum-of-squares
            bLearnDone := TRUE;                       // 学习完成 / Learning done
            eState := eMonitor;                       // 转监视相 / To monitor
        END_IF
    END_IF
END_IF

// ---- 段 6｜监视相：双判据评估与确认窗 ------------------------------------------
IF (eState = eMonitor) AND bRun THEN
    IF NOT bSigOk OR (NOT ioDiff.bValid) THEN
        bCritSlope := FALSE;                          // 数据无效撤判据一 / Invalid data withdraws criterion one
        bCritNoise := FALSE;                          // 数据无效撤判据二 / Invalid data withdraws criterion two
        uErrorId := 16#0002_3033;                     // 信息级：冻结评估 / Info: evaluation frozen
    ELSIF (uCnt < DL_EET_MIN) AND (NOT bPriorUse) THEN
        bCritSlope := FALSE;                          // 样本不足不出判定 / Insufficient samples, no verdict
        bCritNoise := FALSE;                          // 样本不足不出判定 / Insufficient samples, no verdict
        uErrorId := 16#0002_3033;                     // 信息级：样本不足 / Info: insufficient samples
    ELSE
        bCritSlope := ABS(fSlope) > ABS(fSlopeTh);    // 判据一：斜率超阈 / Slope over threshold
        bCritNoise := ABS(fSigR - fMean) > fNoise;    // 判据二：突破噪声窗 / Beyond noise window
    END_IF
    bCritNow := bCritSlope AND bCritNoise;            // 双判据合取 / Both criteria AND
    bInWin := (tonConf.ET > T#0MS);                   // 确认窗进行中判定 / Confirm window in progress
    IF bInWin AND (NOT bCritNow) THEN
        eState := eLearning;                          // 按判据矛盾复位回学习重采基线 / Contradiction resets to learning
        uCodeLatch := 16#0002_3034;                   // 码位：确认窗中断判据矛盾 / Code: confirm window contradiction
        bError := TRUE;                               // 故障级配对置位（R45）/ Fault flag paired
    ELSIF tonConf.Q THEN
        bEndpoint := TRUE;                            // 确认满终点触发锁存 / Confirmed, endpoint latched
        eState := eTriggered;                         // 转触发相 / To triggered
        bError := FALSE;                              // 清故障标志 / Clear fault flag
        uCodeLatch := 16#0000_0000;                   // 清锁存码 / Clear latched code
    END_IF
END_IF

// ---- 段 7｜错误码装配：故障锁存回放优先，信息级居次 -----------------------------
IF (eState = eLearning) AND bRun AND (uCodeLatch <> 16#0000_0000) THEN
    bError := TRUE;                                   // 故障锁存回放（学习相等待重试）/ Fault latched replay
    uErrorId := uCodeLatch;                           // 锁存码回放 / Latched code replayed
ELSIF NOT bRun THEN
    bError := FALSE;                                  // 撤运行清故障（可达解除）/ Run drop clears fault
    uErrorId := 16#0000_0000;                         // 清码 / Clear code
    uCodeLatch := 16#0000_0000;                       // 清锁存码 / Clear latched code
END_IF
END_FUNCTION_BLOCK
