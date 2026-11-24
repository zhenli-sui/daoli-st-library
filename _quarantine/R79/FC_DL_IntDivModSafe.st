(*==============================================================================
 * 组件名称 : FC_DL_IntDivModSafe ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 有符号整数安全除余。一次算出商与余，两个出口同时给出，供定点换算、
 *            分段取模、脉冲计数分配使用。余数按「被除数符号」口径：nRem = 被除数 − 商 × 除数。
 * 契约     : 合法时返回 TRUE；nDen = 0 返回 FALSE、bError := TRUE、两出参置 0；
 *            nNum = DINT 下界且 nDen = −1 时商不可表示（−(−2^31) 回绕），
 *            返回 FALSE、bError := TRUE、两出参置 0。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置 + 下界除 −1 溢出特判
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 商向零截断（IEC 61131-3 整数除法语义），余数与被除数同号；
 *            负数取余口径在不同平台有二分争议，本件以「被除数 − 商 × 除数」自证，不依赖平台取余。
 * 修订历史 : 2026-11-24 R79-A 首版（整数数论族 6/8）
 *============================================================================*)
FUNCTION FC_DL_IntDivModSafe : BOOL
VAR_INPUT
    nNum        : DINT;     // 被除数，全域 [无量纲] / dividend over the whole signed range
    nDen        : DINT;     // 除数，非零 [无量纲] / divisor, must be non zero
END_VAR
VAR_OUTPUT
    eErr        : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError      : BOOL;     // 除零或商溢出为真 / TRUE on division by zero or an unrepresentable quotient
    bValid      : BOOL;     // 出参可用标志 / TRUE when the outputs are usable
    nQuot       : DINT;     // 商，向零截断，故障时 0 / quotient truncated toward zero, zero on fault
    nRem        : DINT;     // 余数，与被除数同号，故障时 0 / remainder carrying the dividend sign, zero on fault
END_VAR
VAR CONSTANT
    DL_DINT_MIN : DINT := -2147483648;  // DINT 下界，取负会回绕 [无量纲] / signed lower bound whose negation wraps
    DL_NEG_ONE  : DINT := -1;           // 负一，下界除它商不可表示 / minus one, the quotient of the lower bound overflows
    DL_ZERO     : DINT := 0;            // 整数零哨兵 / integer zero sentinel
END_VAR
VAR
    nQ          : DINT;     // 商中间量 / quotient interim value
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntDivModSafe := FALSE;   // 缺省失败 / default failure
eErr    := 0;                   // 零码位范式 / zero-code rule
bError  := FALSE;               // 预置无故障 / preset no fault
bValid  := FALSE;               // 域闸前不认出参 / the outputs are unusable until the gates pass
nQuot   := DL_ZERO;             // 商清零 / clear the quotient
nRem    := DL_ZERO;             // 余数清零 / clear the remainder

// 段 2｜除零域闸：除法前唯一必需的拦截 / segment 2, the division by zero gate
IF nDen = DL_ZERO THEN
    bError := TRUE;             // 除零 / division by zero
    RETURN;                     // 出参保持 0 / the outputs stay zero
END_IF

// 段 3｜溢出特判：下界除 −1 的商为 2^31，超出 DINT 正向上界 / segment 3, the unrepresentable quotient
IF (nNum = DL_DINT_MIN) AND (nDen = DL_NEG_ONE) THEN
    bError := TRUE;             // 商不可表示 / the quotient cannot be represented
    RETURN;                     // 出参保持 0 / the outputs stay zero
END_IF

// 段 4｜商与余：余数由乘法反算自证，不依赖平台负数取余口径 / segment 4, the quotient and a self proven remainder
nQ    := nNum / nDen;           // 商，向零截断 / quotient truncated toward zero
nQuot := nQ;                    // 出口 / publish the quotient
nRem  := nNum - (nQ * nDen);    // 余数 = 被除数 − 商 × 除数 / remainder from the product reflection
bValid := TRUE;                 // 出参可用 / the outputs are usable
FC_DL_IntDivModSafe := TRUE;    // 除余完成 / the division completed
END_FUNCTION
