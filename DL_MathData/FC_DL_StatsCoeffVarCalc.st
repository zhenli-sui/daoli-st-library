(*==============================================================================
 * 组件名称 : FC_DL_StatsCoeffVarCalc ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 变异系数 CV = σ / |μ| × 100 [%]，即标准差相对均值的离散度，用于跨量纲比较
 *            工艺稳定性（灌装量、片厚、温度均匀性等）。
 * 契约     : |fMean| ≥ 1.0E-9 且 fStd ≥ 0 且入参有限 → 返回 CV [%]、bValid := TRUE；
 *            |fMean| < 1.0E-9（近零均值下 CV 无意义，商发散）→ 返回 0、bError := TRUE；
 *            fStd < 0（标准差不可能为负，属组态/上游故障，按 0 口径返回 0）→ 同上置故障；
 *            入参非有限 → 返回 0、bError := TRUE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），仅用标准库 ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（|μ| ≥ 1.0E-9）+ 非有限拦截 + 无 = 比较
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 分母取 |μ| 绝对值，故负均值同样给出正的离散百分比；CV 量纲为 %（已乘 100）；
 *            近零阈值 1.0E-9 与全库统一容差口径一致；标准差为负时「按 0 处理」的出口值
 *            同样是 0，但 bError 置位以示上游异常，二者靠 bError / bValid 区分。
 * 修订历史 : 2026-11-24 R79-B 首版（统计族 1/2）
 *============================================================================*)
FUNCTION FC_DL_StatsCoeffVarCalc : LREAL
VAR_INPUT
    fMean : LREAL := 0.0; // 样本均值 μ，可负 [工程单位] / the sample mean, negative allowed
    fStd  : LREAL := 0.0; // 样本标准差 σ，须 ≥ 0 [工程单位] / the sample standard deviation, must be non negative
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 近零均值、负标准差或非有限入参时为真 / TRUE on a near zero mean, a negative deviation or a non finite input
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_FIN     : LREAL := 1.0E30;  // 有限性判据上界（R477 范式：ABS(x)>FIN 判 Inf，禁用 x-x 差判）/ finiteness ceiling, ABS(x)>FIN flags Inf
    DL_ZERO : LREAL := 0.0;    // 实数零哨兵 [工程单位] / the real zero sentinel
    DL_MIN  : LREAL := 1.0E-9; // 近零均值判定阈值，全库统一容差 [工程单位] / the near zero threshold shared by the library
    DL_PCT  : LREAL := 100.0;  // 百分比换算系数 [%] / the percent scaling factor
END_VAR
VAR
    fAbsMean : LREAL; // 均值绝对值，作分母 [工程单位] / the absolute mean used as the divisor
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsCoeffVarCalc := DL_ZERO;  // 缺省零 / default zero
eErr   := 0;                         // 零码位范式 / zero-code rule
bError := FALSE;                     // 预置无故障 / preset no fault
bValid := FALSE;                     // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜非有限拦截：NaN 自反判，Inf 自减判 / segment 2, the non finite gate
IF (fMean <> fMean) OR (fStd <> fStd) THEN
    bError := TRUE;                  // NaN 入参 / a NaN input
    RETURN;                          // 返回 0 / return the preset zero
END_IF
IF (ABS(fMean) > DL_FIN) OR (ABS(fStd) > DL_FIN) THEN
    bError := TRUE;                  // Inf 入参 / an infinite input
    RETURN;                          // 返回 0 / return the preset zero
END_IF

// 段 3｜负标准差域闸：σ 不可能为负，判上游故障并按 0 口径返回 / segment 3, the negative deviation gate
IF fStd < DL_ZERO THEN
    bError := TRUE;                  // 上游给错标准差 / the upstream delivered an impossible deviation
    RETURN;                          // 按 0 口径返回 0 / return zero by convention
END_IF

// 段 4｜近零均值域闸：除法前唯一必需的拦截（CV 在 μ→0 处发散）/ segment 4, the near zero mean gate
fAbsMean := ABS(fMean);              // 分母取绝对值 / the absolute mean
IF fAbsMean < DL_MIN THEN            // 禁 = 比较，用容差下界 / a tolerance bound instead of an equality test
    bError := TRUE;                  // 近零均值，CV 无意义 / the coefficient is meaningless near a zero mean
    RETURN;                          // 返回 0 / return the preset zero
END_IF

// 段 5｜出口：CV = σ / |μ| × 100 [%] / segment 5, the coefficient of variation
FC_DL_StatsCoeffVarCalc := (fStd / fAbsMean) * DL_PCT;  // 变异系数 [%] / the coefficient of variation in percent
bValid := TRUE;                      // 返回值可用 / the return value is usable
END_FUNCTION
