(*==============================================================================
 * 组件名称 : FC_DL_IntSignExtractLreal ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 实数符号提取 —— 返回 −1 / 0 / +1 三值符号。零死区 1.0E-12 内的输入统一归 0，
 *            避免控制量在零附近因浮点噪声来回翻符号（阀门抖动、积分反向积分）。
 * 契约     : 返回 −1 / 0 / +1；非有限值（NaN 或 |x| > 1.0E308）返回 0、bError := TRUE、
 *            bValid := FALSE。纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: ABS
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 NaN 用自反判据 x<>x、无穷用 1.0E308 上界、
 *            零死区常量化、浮点无等号判等 R5 双语注释 R6 N/A（无状态机）
 *            R7 N/A（无定时器/沿实例）R10 无类型转换 R11 全声明行分号
 *            R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 无穷判据取 |x| > 1.0E308（LREAL 最大有限值约 1.8E308），
 *            与「用 x−x 自判」的写法互斥 —— 后者在优化编译下可能被常量折叠，已被 R77 列为死谓词。
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 7/8）
 *============================================================================*)
FUNCTION FC_DL_IntSignExtractLreal : DINT
VAR_INPUT
    fVal        : LREAL;    // 待取符号的实数 [工程单位] / value whose sign is requested [engineering unit]
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 输入为非有限值时为真 / TRUE when the input is not finite
    bValid      : BOOL;     // 符号结论可用标志 / TRUE when the sign verdict is usable
END_VAR
VAR CONSTANT
    DL_EPS      : LREAL := 1.0E-12;      // 零死区容差，本件专用（比族内 1.0E-9 更紧）[工程单位] / zero deadband, tighter than the family default
    DL_FIN_LIM  : LREAL := 1.0E308;      // 有限性上界，超过按无穷处置 [工程单位] / finiteness ceiling, beyond it the value counts as infinity
    DL_ZERO     : DINT := 0;             // 符号零值 [无量纲] / the zero sign, dimensionless
    DL_POS_ONE  : DINT := 1;             // 正号值 [无量纲] / the positive sign, dimensionless
    DL_NEG_ONE  : DINT := -1;            // 负号值 [无量纲] / the negative sign, dimensionless
    DL_ZERO_L   : LREAL := 0.0;          // 实数零，仅用于严格不等比较 [工程单位] / real zero used by strict inequalities only
END_VAR
VAR
    fAbs        : LREAL;    // 输入的绝对值，供死区与有限性判定 / absolute value used by the deadband and the finiteness tests
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntSignExtractLreal := DL_ZERO;   // 缺省符号 0 / default sign zero
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := TRUE;                         // 有限输入下结论恒可用 / the verdict is usable for every finite input

// 段 2｜NaN 自反判据：x <> x 成立即为 NaN，回绕 0 / segment 2, the self reflective NaN test
IF fVal <> fVal THEN
    bError := TRUE;                     // 非数 / not a number
    bValid := FALSE;                    // 符号结论不可用 / the sign verdict is unusable
    RETURN;
END_IF

// 段 3｜无穷判据：绝对值超有限上界即按非有限处置 / segment 3, the infinity test on the magnitude
fAbs := ABS(fVal);                      // 幅度 / magnitude
IF fAbs > DL_FIN_LIM THEN
    bError := TRUE;                     // 无穷 / infinity
    bValid := FALSE;                    // 符号结论不可用 / the sign verdict is unusable
    RETURN;
END_IF

// 段 4｜零死区：幅度不足容差即归 0，抑制零附近符号抖动 / segment 4, the zero deadband
IF fAbs < DL_EPS THEN
    RETURN;                            // 返回 0 / return zero
END_IF

// 段 5｜符号：死区外按严格不等比较，不使用等号 / segment 5, the sign outside the deadband
IF fVal > DL_ZERO_L THEN
    FC_DL_IntSignExtractLreal := DL_POS_ONE;    // 正号 / positive sign
ELSE
    FC_DL_IntSignExtractLreal := DL_NEG_ONE;    // 负号 / negative sign
END_IF
END_FUNCTION
