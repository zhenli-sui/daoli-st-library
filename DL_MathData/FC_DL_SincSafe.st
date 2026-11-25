(*==============================================================================
 * 名称 : FC_DL_SincSafe —— 安全 sinc(x)=sin(x)/x（0 点泰勒展开防除零）
 * 分类 / 前缀 / 版本 : DL_MathData / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 计算 sinc(x)=sin(x)/x。|x|<1.0E-8 时用四阶泰勒近似
 *            1 - x^2/6 + x^4/120（该区间误差 < 1.0E-16 量级），避免 0 点
 *            除零；其余区间直接 sin(x)/x（|x|>=1.0E-8 保证分母非零）。
 *            边界处理：输入非有限（NaN/±Inf）置 eErr 返回 0.0；x=0 精确落
 *            入泰勒支路返回 1.0（sinc 极限值），属正确结果非故障。
 * 错误码 : 16#0001_1B0F = 输入非有限（NaN/±Inf）
 *          eErr=0 且 bValid=TRUE 表示返回值可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/除零防护 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_SincSafe : LREAL
VAR_INPUT
    fX : LREAL;    // 输入自变量 [rad] / input argument in radians
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1B0F=输入非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=返回值可用 / TRUE when return value is usable
END_VAR
VAR
    _x2 : LREAL;       // x 的平方（泰勒中间量）/ squared input for Taylor series
    _x4 : LREAL;       // x 的四次方（泰勒中间量）/ fourth power for Taylor series
END_VAR

FC_DL_SincSafe := 0.0;                       // 返回值预设 0.0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fX <> fX) OR ((fX - fX) <> (fX - fX)) THEN    // NaN 或 ±Inf / NaN or infinite
    eErr   := 16#0001_1B0F;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 返回值不可用 / return not usable
    RETURN;                                  // 返回 0.0 / return zero
END_IF

IF ABS(fX) < 1.0E-8 THEN                     // 0 点邻域走泰勒支路 / Taylor branch near zero
    _x2 := fX * fX;                          // 平方中间量 / square
    _x4 := _x2 * _x2;                        // 四次方中间量 / fourth power
    FC_DL_SincSafe := 1.0 - _x2 / 6.0 + _x4 / 120.0;    // 四阶泰勒近似（0 点返回 1.0）/ 4th-order Taylor
ELSE                                         // 非零区间直接作商（分母 |x|>=1E-8 非零）/ direct quotient
    FC_DL_SincSafe := SIN(fX) / fX;          // sin(x)/x，分母已保证非零 / denominator guaranteed nonzero
END_IF

END_FUNCTION
