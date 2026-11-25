(*==============================================================================
 * 组件名称 : FB_DL_StatsSkewKurtStream ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 流式三阶/四阶中心矩累加器（Terriberry 单遍递推），出偏度与超额峰度。
 *            在 Welford 的 n / mean / M2 之上再加 M3 / M4，四个量同拍更新：
 *            d = x − mean；dn = d/n；t1 = d·dn·(n−1)；
 *            M4 += t1·dn²·(n²−3n+3) + 6·dn²·M2 − 4·dn·M3；
 *            M3 += t1·dn·(n−2) − 3·dn·M2；M2 += t1；mean += dn。
 *            更新顺序固定为 M4 → M3 → M2，保证每一步读到的都是上一拍的历史矩。
 * 契约     : 偏度 = √n·M3 / M2^1.5；超额峰度 = n·M4 / M2² − 3。
 *            n < 4 时 fSkew / fKurt 置 0 且 bValid := FALSE（四阶矩少于四样本无意义）；
 *            M2 < 1.0E-18（零方差流）时形状量置 0，除零结构性不可达。
 *            bEnable 上升沿采样一次，bReset 上升沿全清（R18 / R7 均用 R_TRIG）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: R_TRIG / ABS / SQRT
 * 错误码   : R297 零码位范式：eErr 恒 0，丢弃以 bRejected 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（n≥1、M2 阈值闸）、NaN 自反判据、
 *            无穷上界、平方项先转实数再乘 ｜ R5 双语注释 R6 ENUM+CASE+ELSE 兜底
 *            R7 R_TRIG 置于 CASE 外无条件刷新 ｜ R10 标准转换 R11 全声明行分号
 *            R14 无 PROPERTY R15 标识符零保留字冲突 R18 bReset 走 R_TRIG
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 2/8）
 *============================================================================*)
TYPE E_DL_SkewKurtStage :
(
    eSkewIdle  := 0,        // 零样本 / no sample
    eSkewAccum := 1,        // 一至三样本，形状量不可用 / one to three samples, the shape measures are unavailable
    eSkewReady := 2         // 四样本以上，偏度峰度可用 / four samples or more, skewness and kurtosis are usable
);
END_TYPE

FUNCTION_BLOCK FB_DL_StatsSkewKurtStream
VAR_INPUT
    bEnable   : BOOL;   // 采样使能，上升沿表示新样本到达 / capture enable, a rising edge marks a new sample
    bReset    : BOOL;   // 复位，上升沿清零四个矩累加器 / reset, a rising edge clears all four moments
    fSample   : LREAL;  // 样本值，非有限者被丢弃 [工程单位] / sample value, non finite ones are dropped [engineering unit]
END_VAR
VAR_OUTPUT
    eErr      : UDINT;  // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;   // 故障标志，本件不产生故障级 / fault flag, never raised by this component
    bRejected : BOOL;   // 本拍样本被丢弃（非有限） / TRUE when this cycle sample was dropped
    fMean     : LREAL;  // 在线均值 [工程单位] / running mean [engineering unit]
    fSkew     : LREAL;  // 偏度（三阶标准化矩） [无量纲] / skewness, the standardised third moment [dimensionless]
    fKurt     : LREAL;  // 超额峰度，正态分布为 0 [无量纲] / excess kurtosis, zero for a normal distribution [dimensionless]
    nCount    : UDINT;  // 已纳入样本数 [个] / number of accepted samples [count]
    bValid    : BOOL;   // n ≥ 4 时为真 / TRUE from four samples on
    eStage    : E_DL_SkewKurtStage; // 累加器阶段 / accumulator stage
END_VAR
VAR CONSTANT
    DL_ONE      : UDINT := 1;           // 无符号一 / unsigned one
    DL_FOUR     : UDINT := 4;           // 无符号四，形状量可用门槛 [个] / unsigned four, the shape measure threshold [count]
    DL_M2_MIN   : LREAL := 1.0E-18;     // 零方差闸，低于它形状量置 0 / zero variance gate
    DL_KURT_BIAS : LREAL := 3.0;        // 峰度的正态基准值 3，超额峰度需减去 [无量纲] / normal reference of the raw kurtosis [dimensionless]
    DL_THREE    : LREAL := 3.0;         // 递推式常数 3 [无量纲] / recursion constant three [dimensionless]
    DL_FOUR_L   : LREAL := 4.0;         // 递推式常数 4 [无量纲] / recursion constant four [dimensionless]
    DL_SIX      : LREAL := 6.0;         // 递推式常数 6 [无量纲] / recursion constant six [dimensionless]
    DL_ONE_L    : LREAL := 1.0;         // 实数一，用于 n−1 / real one used by the n minus one factor
    DL_TWO_L    : LREAL := 2.0;         // 实数二，用于 n−2 / real two used by the n minus two factor
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界，超过按无穷处置 [工程单位] / finiteness ceiling [engineering unit]
    DL_ZERO_L   : LREAL := 0.0;         // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    rtReset   : R_TRIG; // 复位上升沿检测，无条件周期刷新 / reset rising edge, refreshed every cycle
    rtSample  : R_TRIG; // 采样上升沿检测，无条件周期刷新 / sample rising edge, refreshed every cycle
    nAcc      : UDINT;  // 内部样本计数 / internal sample counter
    fMeanInt  : LREAL;  // 内部均值累加器 [工程单位] / internal mean accumulator [engineering unit]
    fM2       : LREAL;  // 二阶中心矩 [工程单位²] / second central moment [unit squared]
    fM3       : LREAL;  // 三阶中心矩 [工程单位³] / third central moment [unit cubed]
    fM4       : LREAL;  // 四阶中心矩 [工程单位⁴] / fourth central moment [unit to the fourth]
    fDelta    : LREAL;  // 新样本偏差 d [工程单位] / deviation of the new sample [engineering unit]
    fDeltaN   : LREAL;  // 偏差除以 n [工程单位] / deviation over the sample count [engineering unit]
    fTerm1    : LREAL;  // 递推主项 t1 = d·dn·(n−1) [工程单位²] / the leading recursion term [unit squared]
    fN        : LREAL;  // 样本数的实数形式 [个] / the sample count as a real number [count]
END_VAR

// 段 1｜沿检测无条件周期刷新（R7） / segment 1, refresh both edges unconditionally
rtReset(CLK := bReset);
rtSample(CLK := bEnable);

// 段 2｜出口预置 / segment 2, preset the single cycle outputs
eErr      := 0;             // 零码位范式 / zero-code rule
bError    := FALSE;         // 本件不产生故障级 / this component raises no fault
bRejected := FALSE;         // 本拍未丢弃 / nothing dropped yet

// 段 3｜复位优先：四个矩全清 / segment 3, reset has priority and clears all four moments
IF rtReset.Q THEN
    nAcc     := 0;
    fMeanInt := DL_ZERO_L;
    fM2      := DL_ZERO_L;
    fM3      := DL_ZERO_L;
    fM4      := DL_ZERO_L;
END_IF

// 段 4｜采样与递推：顺序固定 M4 → M3 → M2，均读历史矩 / segment 4, the recursion in a fixed order
IF rtSample.Q THEN
    IF (fSample <> fSample) OR (ABS(fSample) > DL_FIN_LIM) THEN
        bRejected := TRUE;                                  // 非数或无穷，丢弃 / not a number or infinity, dropped
    ELSE
        nAcc     := nAcc + DL_ONE;                          // 先自增，保证除数 ≥ 1 / increment first so the divisor is at least one
        fN       := UDINT_TO_LREAL(nAcc);                   // 实数样本数 / the count as a real number
        fDelta   := fSample - fMeanInt;                     // 偏差 / deviation
        fDeltaN  := fDelta / fN;                            // 偏差除以 n / deviation over the count
        fTerm1   := fDelta * fDeltaN * (fN - DL_ONE_L);     // 递推主项 / the leading term
        fMeanInt := fMeanInt + fDeltaN;                     // 均值递推 / mean update
        fM4      := fM4 + (fTerm1 * fDeltaN * fDeltaN * ((fN * fN) - (DL_THREE * fN) + DL_THREE)) + (DL_SIX * fDeltaN * fDeltaN * fM2) - (DL_FOUR_L * fDeltaN * fM3);
        fM3      := fM3 + (fTerm1 * fDeltaN * (fN - DL_TWO_L)) - (DL_THREE * fDeltaN * fM2);
        fM2      := fM2 + fTerm1;                           // 二阶矩最后更新，供下一拍使用 / the second moment is updated last
    END_IF
END_IF

// 段 5｜阶段机与出口发布：每分支内自洽，无跨分支残留 / segment 5, the stage machine
CASE eStage OF
    eSkewIdle, eSkewAccum:
        fMean  := fMeanInt;                         // 空相时内部均值恒 0，两相共用一条发布路径 / the internal mean is zero when empty, so both stages share one path
        fSkew  := DL_ZERO_L;                        // 不足四样本，偏度置 0 / fewer than four samples, skewness is zero
        fKurt  := DL_ZERO_L;                        // 不足四样本，峰度置 0 / fewer than four samples, kurtosis is zero
        bValid := FALSE;                            // 形状量不可用 / the shape measures are unavailable
        IF nAcc >= DL_FOUR THEN
            eStage := eSkewReady;                   // 进入可用相 / enter the ready stage
        ELSIF nAcc = 0 THEN
            eStage := eSkewIdle;                    // 回落空闲相（复位后）/ fall back to idle after a reset
        ELSE
            eStage := eSkewAccum;                   // 停在累加相 / stay at the accumulation stage
        END_IF
    eSkewReady:
        fMean := fMeanInt;
        fN    := UDINT_TO_LREAL(nAcc);              // 实数样本数 / the count as a real number
        IF fM2 > DL_M2_MIN THEN
            fSkew := (SQRT(fN) * fM3) / (fM2 * SQRT(fM2));      // √n·M3 / M2^1.5 / the standardised third moment
            fKurt := ((fN * fM4) / (fM2 * fM2)) - DL_KURT_BIAS; // n·M4 / M2² − 3 / the excess kurtosis
        ELSE
            fSkew := DL_ZERO_L;                     // 零方差流，形状量置 0（除零不可达）/ zero variance keeps the shapes at zero
            fKurt := DL_ZERO_L;
        END_IF
        bValid := TRUE;                             // 形状量可用 / the shape measures are usable
        IF nAcc < DL_FOUR THEN
            IF nAcc = 0 THEN
                eStage := eSkewIdle;                // 复位后回落 / fall back after a reset
            ELSE
                eStage := eSkewAccum;               // 回落累加相 / fall back to the accumulation stage
            END_IF
        END_IF
ELSE
    eStage := eSkewIdle;                            // 非法阶段拦截并复位 / intercept an illegal stage and recover
    fMean  := DL_ZERO_L;
    fSkew  := DL_ZERO_L;
    fKurt  := DL_ZERO_L;
    bValid := FALSE;
END_CASE

// 段 6｜计数出口：与阶段机解耦 / segment 6, publish the count independently
nCount := nAcc;
END_FUNCTION_BLOCK
