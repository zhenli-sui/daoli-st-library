(*==============================================================================
 * 组件名称 : FC_DL_StatsHistogramBin ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 等宽直方图落桶序号。桶宽 fWidth、桶数 nBins、起点 fMin 给定，
 *            返回 1~nBins 的桶号，供桶计数数组自增（直方图 = 落桶 + 计数两步）。
 *            首尾桶按开区间外延钳位：小于起点归首桶，大于末桶归末桶 ——
 *            线上数据超界不该丢样本，也不该写越界下标。
 * 契约     : 返回 1~nBins；fVal < fMin 返回 1，fVal ≥ 末桶上界返回 nBins；
 *            fWidth ≤ 1.0E-9 或 nBins < 1 返回 0、bError := TRUE（桶结构非法）；
 *            非有限输入返回 0、bError := TRUE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: TRUNC / ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 桶宽闸防除零、实数上限兜底后才取整防溢出、
 *            NaN 自反判据 ｜ R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 标准转换（TRUNC + LREAL_TO_DINT）R11 全声明行分号
 *            R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（统计扩展族 7/8）
 *============================================================================*)
FUNCTION FC_DL_StatsHistogramBin : DINT
VAR_INPUT
    fVal    : LREAL;    // 待落桶样本 [工程单位] / sample to place into a bin [engineering unit]
    fMin    : LREAL;    // 首桶下界（含） [工程单位] / lower edge of the first bin, inclusive [engineering unit]
    fWidth  : LREAL;    // 桶宽，须 > 0 [工程单位] / bin width, must be positive [engineering unit]
    nBins   : INT;      // 桶数，须 ≥ 1 [个] / bin count, at least one [count]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 桶结构非法或输入非有限为真 / TRUE on an illegal bin structure or non finite inputs
    bValid  : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_WIDTH_MIN : LREAL := 1.0E-9;     // 桶宽下限，低于它判结构非法 [工程单位] / width floor below which the structure is illegal
    DL_FIN_LIM   : LREAL := 1.0E308;    // 有限性上界 [工程单位] / finiteness ceiling
    DL_ONE       : DINT := 1;           // 首桶号与下标偏移 [个] / the first bin number [count]
    DL_ZERO      : DINT := 0;           // 整数零哨兵，代表非法 / integer zero sentinel meaning illegal
    DL_ZERO_L    : LREAL := 0.0;        // 实数零哨兵 / real zero sentinel
END_VAR
VAR
    fOffset : LREAL;    // 样本相对首桶下界的偏移 [工程单位] / offset of the sample from the first lower edge
    fIdx    : LREAL;    // 零基桶序号实数形式 [个] / zero based bin index as a real number
    nBin    : DINT;     // 一基桶序号 [个] / one based bin number [count]
END_VAR

// 段 1｜出口预置：0 为非法桶号 / segment 1, preset the exit with the illegal bin number
FC_DL_StatsHistogramBin := DL_ZERO;     // 缺省非法 / default illegal
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 域闸前不认结果 / unusable until the gates pass

// 段 2｜桶结构闸与输入闸：桶宽、桶数、三个实数的有限性 / segment 2, the structure and finiteness gates
IF nBins < DL_ONE THEN
    bError := TRUE;                     // 桶数非法 / the bin count is illegal
    RETURN;
END_IF
IF fWidth < DL_WIDTH_MIN THEN
    bError := TRUE;                     // 桶宽非正或近零，落桶除零不可达 / the width is not positive, division is blocked here
    RETURN;
END_IF
IF (fVal <> fVal) OR (fMin <> fMin) OR (fWidth <> fWidth) THEN
    bError := TRUE;                     // 含非数输入 / a not a number input was seen
    RETURN;
END_IF
IF (ABS(fVal) > DL_FIN_LIM) OR (ABS(fMin) > DL_FIN_LIM) THEN
    bError := TRUE;                     // 量级非有限 / a magnitude is not finite
    RETURN;
END_IF

// 段 3｜偏移与首桶钳位：低于起点一律归首桶 / segment 3, the offset and the first bin clamp
fOffset := fVal - fMin;                 // 相对偏移 / the relative offset
IF fOffset < DL_ZERO_L THEN
    FC_DL_StatsHistogramBin := DL_ONE;  // 首桶钳位 / clamp into the first bin
    bValid := TRUE;
    RETURN;
END_IF

// 段 4｜零基序号：先做实数上限兜底再取整，防取整溢出 / segment 4, the real bound before the truncation
fIdx := fOffset / fWidth;               // 分母已证 ≥ 容差 / the divisor is proven to be at least the floor
IF fIdx >= INT_TO_LREAL(nBins) THEN
    FC_DL_StatsHistogramBin := INT_TO_DINT(nBins);      // 末桶钳位，越界样本不丢 / clamp into the last bin
    bValid := TRUE;
    RETURN;
END_IF
nBin := LREAL_TO_DINT(TRUNC(fIdx)) + DL_ONE;            // 零基转一基 / zero based to one based

// 段 5｜出口：档位已证落在 1..nBins / segment 5, the bin is proven to be inside the range
FC_DL_StatsHistogramBin := nBin;        // 桶号 / the bin number
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
