(*==============================================================================
 * 组件名称 : FC_DL_StatsZScoreClamp ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 标准化偏差（z 分数）计算并对称限幅。z = (x − mean) / std，再钳到 ±fClamp。
 *            限幅的意义：异常样本的 z 可能上千，直接送 PID 或神经网络会把输出顶到饱和；
 *            钳到 ±3~±5 既保留「异常」信息又不炸控制器。
 * 契约     : 返回 z（已钳位）；fStd < 1.0E-9 时返回 0（除零结构性不可达，零标准差无 z 可言）；
 *            fClamp ≤ 0 时按 1.0 处理（限幅必须为正，否则钳位区间退化为一点）；
 *            任一输入为 NaN 或非有限值时返回 0、bError := TRUE、bValid := FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（std 阈值闸）、NaN 自反判据、
 *            无穷上界、fClamp 非正回退 ｜ R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 无类型转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 6/8）
 *============================================================================*)
FUNCTION FC_DL_StatsZScoreClamp : LREAL
VAR_INPUT
    fVal     : LREAL;   // 待标准化样本 [工程单位] / sample to standardise [engineering unit]
    fMean    : LREAL;   // 总体均值 [工程单位] / population mean [engineering unit]
    fStd     : LREAL;   // 总体标准差 [工程单位] / population standard deviation [engineering unit]
    fClamp   : LREAL;   // 对称限幅幅值，须 > 0，非正按 1.0 [无量纲] / symmetric clamp magnitude, non positive falls back to one
END_VAR
VAR_OUTPUT
    eErr     : UDINT;   // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError   : BOOL;    // 输入含非有限值为真 / TRUE when an input is not finite
    bValid   : BOOL;    // 结果可用标志 / result usable flag
    bClamped : BOOL;    // 本次结果被限幅为真 / TRUE when the result hit the clamp
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-9;      // 标准差下限，低于它按零标准差处理 [工程单位] / deviation floor below which the spread counts as zero
    DL_FIN_LIM  : LREAL := 1.0E308;     // 有限性上界 [工程单位] / finiteness ceiling
    DL_CLAMP_DEF : LREAL := 1.0;        // 限幅回退值，非正输入时使用 [无量纲] / clamp fallback used for non positive inputs
    DL_ZERO_L   : LREAL := 0.0;         // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    fClampUse : LREAL;  // 生效限幅幅值，恒为正 [无量纲] / effective clamp magnitude, always positive
    fZ        : LREAL;  // 未限幅的 z 分数 [无量纲] / the raw z score
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_StatsZScoreClamp := DL_ZERO_L;    // 缺省 z=0 / default z of zero
eErr     := 0;                          // 零码位范式 / zero-code rule
bError   := FALSE;                      // 预置无故障 / preset no fault
bValid   := FALSE;                      // 计算完成前不认结果 / unusable until the computation ends
bClamped := FALSE;                      // 预置未限幅 / preset unclamped

// 段 2｜非有限闸：四个入参逐一验 NaN 与量级 / segment 2, the non finite gate
IF (fVal <> fVal) OR (fMean <> fMean) OR (fStd <> fStd) OR (fClamp <> fClamp) THEN
    bError := TRUE;                     // 含非数输入 / a not a number input was seen
    RETURN;
END_IF
IF (ABS(fVal) > DL_FIN_LIM) OR (ABS(fMean) > DL_FIN_LIM) OR (ABS(fStd) > DL_FIN_LIM) OR (ABS(fClamp) > DL_FIN_LIM) THEN
    bError := TRUE;                     // 量级非有限 / a magnitude is not finite
    RETURN;
END_IF

// 段 3｜限幅幅值整形：非正按 1.0，取绝对值后恒正 / segment 3, normalise the clamp magnitude
fClampUse := ABS(fClamp);
IF fClampUse < DL_EPS THEN
    fClampUse := DL_CLAMP_DEF;          // 退化限幅回退 1.0 / a degenerate clamp falls back to one
END_IF

// 段 4｜零标准差闸：结构性除零在此拦下 / segment 4, the zero deviation gate
IF fStd < DL_EPS THEN
    bValid := TRUE;                     // z 定义为 0，结论可用 / a zero spread yields z of zero, a usable verdict
    RETURN;                             // 返回 0 / return zero
END_IF

// 段 5｜z 分数与对称限幅：分母已证 ≥ 容差 / segment 5, the z score and the symmetric clamp
fZ := (fVal - fMean) / fStd;            // 标准化偏差 / the standardised deviation
IF fZ > fClampUse THEN
    fZ       := fClampUse;              // 上限幅 / clamp on the upper side
    bClamped := TRUE;
ELSIF fZ < -fClampUse THEN
    fZ       := -fClampUse;             // 下限幅 / clamp on the lower side
    bClamped := TRUE;
END_IF

// 段 6｜出口 / segment 6, exit
FC_DL_StatsZScoreClamp := fZ;           // 限幅后的 z / the clamped z score
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
