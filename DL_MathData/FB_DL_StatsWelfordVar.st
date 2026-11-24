(*==============================================================================
 * 组件名称 : FB_DL_StatsWelfordVar ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : Welford 在线均值/方差累加器 —— 单遍递推，不保存样本、不做减法抵消，
 *            长序列下数值稳定性远优于「先求和再平方和」。递推式：
 *            d = x − mean；mean += d/n；M2 += d·(x − mean)；样本方差 = M2/(n−1)。
 * 契约     : bEnable 按「新样本到达」语义使用 —— 只在上升沿采样一次（内部 R_TRIG），
 *            bEnable 保持为真的多个周期不会重复计入同一值。
 *            bReset 上升沿清零 n / mean / M2（R18 用 R_TRIG，禁电平判据）。
 *            出参 fMean / fVar / fStd / nCount / bValid；n = 1 时 fVar := 0；
 *            bValid 仅在 n ≥ 2（三件套同时可用）为真，均值本身 n = 1 即有效。
 *            非有限样本直接丢弃并置 bRejected（单拍），不污染累加器。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: R_TRIG / ABS / SQRT
 * 错误码   : R297 零码位范式：eErr 恒 0，丢弃以 bRejected 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（n 自增后才整除）、NaN 自反判据、
 *            无穷上界、负方差兜底 ｜ R5 双语注释 R6 ENUM+CASE+ELSE 兜底
 *            R7 R_TRIG 实例置于 CASE 外无条件周期刷新 ｜ R10 标准转换
 *            R11 全声明行分号 R14 无 PROPERTY R15 标识符零保留字冲突
 *            R18 bReset 走 R_TRIG 上升沿
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 1/8）
 *============================================================================*)
TYPE E_DL_WelfordStage :
(
    eWelfordIdle  := 0,     // 零样本，无均值 / no sample, no mean
    eWelfordAccum := 1,     // 单样本，均值可用方差不可用 / one sample, the mean exists but the variance does not
    eWelfordReady := 2      // 两样本以上，均值方差均可用 / two samples or more, everything is usable
);
END_TYPE

FUNCTION_BLOCK FB_DL_StatsWelfordVar
VAR_INPUT
    bEnable   : BOOL;   // 采样使能，上升沿表示新样本到达 / capture enable, a rising edge marks a new sample
    bReset    : BOOL;   // 复位，上升沿清零全部累加器 / reset, a rising edge clears every accumulator
    fSample   : LREAL;  // 样本值，非有限者被丢弃 [工程单位] / sample value, non finite ones are dropped [engineering unit]
END_VAR
VAR_OUTPUT
    eErr      : UDINT;  // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;   // 故障标志，本件不产生故障级 / fault flag, never raised by this component
    bRejected : BOOL;   // 本拍样本被丢弃（非有限） / TRUE when this cycle sample was dropped
    fMean     : LREAL;  // 在线均值 [工程单位] / running mean [engineering unit]
    fVar      : LREAL;  // 样本方差（n−1 分母），n=1 时为 0 [工程单位²] / sample variance with the n minus one divisor [unit squared]
    fStd      : LREAL;  // 样本标准差 [工程单位] / sample standard deviation [engineering unit]
    nCount    : UDINT;  // 已纳入样本数 [个] / number of accepted samples [count]
    bValid    : BOOL;   // n ≥ 2 时为真，三件套同时可用 / TRUE from two samples on, when all three outputs are usable
    eStage    : E_DL_WelfordStage;  // 累加器阶段 / accumulator stage
END_VAR
VAR CONSTANT
    DL_ONE      : UDINT := 1;           // 无符号一 / unsigned one
    DL_TWO      : UDINT := 2;           // 无符号二，方差可用门槛 / unsigned two, the usable variance threshold
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界，超过按无穷处置 [工程单位] / finiteness ceiling [engineering unit]
    DL_ZERO_L   : LREAL := 0.0;         // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    rtReset   : R_TRIG; // 复位上升沿检测，无条件周期刷新 / reset rising edge, refreshed every cycle
    rtSample  : R_TRIG; // 采样上升沿检测，无条件周期刷新 / sample rising edge, refreshed every cycle
    nAcc      : UDINT;  // 内部样本计数 / internal sample counter
    fMeanInt  : LREAL;  // 内部均值累加器 [工程单位] / internal mean accumulator [engineering unit]
    fM2       : LREAL;  // 二阶中心矩累加器 M2 [工程单位²] / second central moment accumulator [unit squared]
    fDelta    : LREAL;  // 偏差 d = x − mean [工程单位] / deviation of the new sample [engineering unit]
    fVarInt   : LREAL;  // 方差中间量，负偏时兜底到 0 [工程单位²] / variance interim value, clamped at zero [unit squared]
END_VAR

// 段 1｜沿检测无条件周期刷新（R7）：先刷新，后判定 / segment 1, refresh both edges unconditionally before any test
rtReset(CLK := bReset);
rtSample(CLK := bEnable);

// 段 2｜出口预置：单拍量与码位每拍重算 / segment 2, preset the single cycle outputs
eErr      := 0;             // 零码位范式 / zero-code rule
bError    := FALSE;         // 本件不产生故障级 / this component raises no fault
bRejected := FALSE;         // 本拍未丢弃 / nothing dropped yet

// 段 3｜复位优先：上升沿清 n / mean / M2，不动阶段（阶段在段 5 回落）/ segment 3, reset has priority
IF rtReset.Q THEN
    nAcc     := 0;          // 计数清零 / clear the counter
    fMeanInt := DL_ZERO_L;  // 均值清零 / clear the mean
    fM2      := DL_ZERO_L;  // 二阶矩清零 / clear the second moment
END_IF

// 段 4｜采样：仅上升沿计入，非有限样本丢弃 / segment 4, capture on the rising edge only
IF rtSample.Q THEN
    IF (fSample <> fSample) OR (ABS(fSample) > DL_FIN_LIM) THEN
        bRejected := TRUE;                                  // 非数或无穷，丢弃 / not a number or infinity, dropped
    ELSE
        nAcc     := nAcc + DL_ONE;                          // 先自增，保证下面除数的 n ≥ 1 / increment first so the divisor is at least one
        fDelta   := fSample - fMeanInt;                     // 新样本偏差 / deviation of the new sample
        fMeanInt := fMeanInt + (fDelta / UDINT_TO_LREAL(nAcc));     // Welford 均值递推 / Welford mean update
        fM2      := fM2 + (fDelta * (fSample - fMeanInt));          // Welford 二阶矩递推 / Welford second moment update
    END_IF
END_IF

// 段 5｜阶段机与出口发布：ENUM + CASE + ELSE 兜底，每分支内不留跨拍中间量 / segment 5, the stage machine
CASE eStage OF
    eWelfordIdle, eWelfordAccum:
        fMean  := fMeanInt;                         // 空相时内部均值恒 0，两相共用一条发布路径 / the internal mean is zero when empty, so both stages share one path
        fVar   := DL_ZERO_L;                        // 不足两样本，方差按契约置 0 / fewer than two samples, the variance is zero by contract
        fStd   := DL_ZERO_L;                        // 标准差同步置 0 / the deviation is zero as well
        bValid := FALSE;                            // 三件套不可用 / the outputs are unusable
        IF nAcc >= DL_TWO THEN
            eStage := eWelfordReady;                // 进入可用相 / enter the ready stage
        ELSIF nAcc = 0 THEN
            eStage := eWelfordIdle;                 // 回落空闲相（复位后）/ fall back to idle after a reset
        ELSE
            eStage := eWelfordAccum;                // 停在单样本相 / stay at the single sample stage
        END_IF
    eWelfordReady:
        fMean := fMeanInt;                          // 均值 / the mean
        IF nAcc > DL_ONE THEN
            fVarInt := fM2 / UDINT_TO_LREAL(nAcc - DL_ONE);     // 样本方差，分母 n−1 / sample variance
        ELSE
            fVarInt := DL_ZERO_L;                   // 结构性不可达，兜底防除零 / unreachable guard against a zero divisor
        END_IF
        IF fVarInt < DL_ZERO_L THEN
            fVarInt := DL_ZERO_L;                   // 数值负偏兜底，方差不得为负 / a numeric undershoot must not go negative
        END_IF
        fVar   := fVarInt;                          // 出口方差 / publish the variance
        fStd   := SQRT(fVarInt);                    // 出口标准差 / publish the deviation
        bValid := TRUE;                             // 三件套可用 / every output is usable
        IF nAcc < DL_TWO THEN
            IF nAcc = 0 THEN
                eStage := eWelfordIdle;             // 复位后回落空闲相 / fall back after a reset
            ELSE
                eStage := eWelfordAccum;            // 回落单样本相 / fall back to the single sample stage
            END_IF
        END_IF
ELSE
    eStage := eWelfordIdle;                         // 非法阶段拦截并复位 / intercept an illegal stage and recover
    fMean  := DL_ZERO_L;
    fVar   := DL_ZERO_L;
    fStd   := DL_ZERO_L;
    bValid := FALSE;
END_CASE

// 段 6｜计数出口：与阶段机解耦，无条件映射 / segment 6, publish the count independently of the stage machine
nCount := nAcc;                                     // 已纳入样本数 / accepted sample count
END_FUNCTION_BLOCK
