(*
  ==================================================================
  组件名 Component  : FC_DL_RoundSigFigs
  分类   Category   : DL_MathData
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 按有效数字位数舍入。把 fVal 舍入到 nSigFigs 位有效数字
                      （半值远离零），10 的幂用整数循环累乘实现（禁 ** 幂运算符）；
                      nSigFigs 越域回钳 1..15 并置 bClamped，非有限值透传并置
                      bInvalid，舍入位置超出 DINT 安全域时原值透传并置 bClamped。
  来源   Source     : t2-1-lgf-math
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；有效数字舍入为公开数值
                      方法，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL / TRUNC / 循环累乘，无私有库、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做十进制有效位舍入，不做定点小数位舍入（属主边界）；
                      二 DINT 可表上界反算（R63）：DINT 上限 2.147E9，取 1.0E9 为
                         TRUNC 安全阈；被舍整数部分 q >= 1.0E9 时（即 nSigFigs >= 10
                         且量级 >= 1E9），拆高低两段各 TRUNC（每段 < 1.0E9 可表），
                         合成值 < 1E15 < 2^53 在 LREAL 精确可表；
                      三 指数域钳 [-300, 300]：LREAL 上限 1.797E308，10^308 可表、
                         10^309 不可表；越钳透传原值并置 bClamped；
                      四 非有限输入透传（规格明示方向）并置 bInvalid，不参与舍入；
                      五 无全局变量、无外部变量声明、无物理地址寻址、无定时器（纯函数）。
  输出契约 Output contract:
                      fOut 在 bInvalid = FALSE 时为舍入结果，bInvalid = TRUE 时透传 fVal；
                      本件为纯函数，无跨扫描周期状态驻留。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 1 · 序号 3）
  ==================================================================
*)

FUNCTION FC_DL_RoundSigFigs : BOOL
VAR_INPUT
    fVal     : LREAL; // 待舍入值（带符号）[工程单位] / the value to be rounded, signed [engineering unit]
    nSigFigs : INT;   // 有效数字位数，越域回钳 1..15 [位] / significant digit count, clamped one through fifteen [digit]
END_VAR
VAR_OUTPUT
    fOut     : LREAL; // 舍入结果（带符号）[工程单位] / the rounded result, signed [engineering unit]
    bInvalid : BOOL;  // 非有限输入透传标志 [-] / the passthrough flag for a non finite input
    bClamped : BOOL;  // 位数或指数被回钳标志 [-] / the clamp flag for the digit count or the exponent
END_VAR
VAR
    _nSig    : INT := 1;    // 钳定后的有效位数 [位] / the clamped significant digit count [digit]
    _fAbs    : LREAL := 0.0;  // 绝对值工作值 [工程单位] / absolute value working quantity
    _fV      : LREAL := 0.0;  // 量级归一工作值 [工程单位] / magnitude normalising working quantity
    _eDec    : DINT := 0;     // 十进位阶（最高位有效数字所在幂）[幂] / decimal decade exponent of the leading digit
    _nPow    : DINT := 0;     // 舍入位置的十的幂（10^nPow）[幂] / power of ten at the rounding position
    _fP      : LREAL := 1.0;  // 十的幂累乘值 [无量纲] / accumulated power of ten
    _fQ      : LREAL := 0.0;  // 被舍实数（|fVal| / 10^nPow）[无量纲] / the value to be rounded integrally
    _fQHi    : LREAL := 0.0;  // 高段被舍实数 [无量纲] / the high segment to be rounded
    _fQLo    : LREAL := 0.0;  // 低段被舍实数 [无量纲] / the low segment to be rounded
    _nHi     : DINT := 0;     // 高段整数部分 [无量纲] / the high segment integer part
    _nLo     : DINT := 0;     // 低段整数部分 [无量纲] / the low segment integer part
    _fR      : LREAL := 0.0;  // 舍入后的整数（LREAL 精确表出）[无量纲] / the rounded integer, exactly representable in LREAL
    _i       : DINT := 0;     // 累乘循环游标 [次] / accumulation loop cursor
END_VAR

// 段 1｜非有限闸：透传并置标志（规格明示透传方向）/ segment 1, finiteness gate, passthrough per the specification
bInvalid := (fVal <> fVal) OR ((fVal - fVal) <> (fVal - fVal)); // NaN 自反、Inf 差值自减 / NaN by reflexivity, Inf by the self difference
IF bInvalid THEN // 非有限输入 / non finite input
    fOut := fVal; // 透传（规格明示）/ passthrough per the specification
    bClamped := FALSE; // 钳位标志不成立 / the clamp flag is false
    FC_DL_RoundSigFigs := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF
bInvalid := FALSE; // 有限输入，标志不成立 / finite input, the flag is false
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag to false
FC_DL_RoundSigFigs := TRUE; // 默认返回成功 / default to success

// 段 2｜位数回钳 1..15（R117 两级回退：一级常量钳定）/ segment 2, digit count clamp
_nSig := nSigFigs; // 位数直通 / the count passes through
IF _nSig < 1 THEN // 下越域 / below the floor
    _nSig := 1; // 回钳到一位 / clamp to one digit
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF _nSig > 15 THEN // 上越域 / above the ceiling
    _nSig := 15; // 回钳到十五位 / clamp to fifteen digits
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
END_IF

// 段 3｜零值与超小值快速出口 / segment 3, the fast exits for zero and tiny magnitudes
_fAbs := ABS(fVal); // 绝对值 / the absolute value
IF _fAbs < 1.0E-300 THEN // 量级低于指数域下限，舍入无意义 / the magnitude is below the exponent floor
    fOut := fVal; // 原值透传 / the value passes through
    RETURN; // 早退 / early return
END_IF

// 段 4｜十进位阶定位：整数循环归一（禁 **）/ segment 4, decade location by integer loops
_fV := _fAbs; // 归一工作值起步 / start the normalising working value
_eDec := 0; // 位阶清零 / clear the decade exponent
WHILE (_fV >= 10.0) AND (_eDec < 320) DO // 向上归一到 [1, 10) / normalise upward into the unit decade
    _fV := _fV / 10.0; // 除十 / divide by ten
    _eDec := _eDec + 1; // 位阶递增 / increment the decade
END_WHILE
WHILE (_fV < 1.0) AND (_eDec > -320) DO // 向下归一到 [1, 10) / normalise downward into the unit decade
    _fV := _fV * 10.0; // 乘十 / multiply by ten
    _eDec := _eDec - 1; // 位阶递减 / decrement the decade
END_WHILE

// 段 5｜舍入位置的十的幂：nPow = eDec - (nSig - 1)，越域钳 [-300, 300] / segment 5, the power at the rounding position
_nPow := _eDec - INT_TO_DINT(_nSig) + 1; // 目标幂（用钳定后位数）/ the target power from the clamped count
IF _nPow < -300 THEN // 下越域（10^-301 不可表）/ below the representable floor
    _nPow := -300; // 回钳 / clamp
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF _nPow > 300 THEN // 上越域（10^301 不可表，R63 反算）/ above the representable ceiling
    _nPow := 300; // 回钳 / clamp
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
END_IF
_fP := 1.0; // 累乘起步一 / start the accumulation at one
IF _nPow >= 0 THEN // 正幂累乘 / the positive accumulation
    _i := 0; // 游标清零 / clear the cursor
    WHILE _i < _nPow DO // 累乘到目标幂 / accumulate to the target power
        _fP := _fP * 10.0; // 乘十 / multiply by ten
        _i := _i + 1; // 游标递增 / increment the cursor
    END_WHILE
ELSE // 负幂累乘 / the negative accumulation
    _i := 0; // 游标清零 / clear the cursor
    WHILE _i > _nPow DO // 累乘到目标幂 / accumulate to the target power
        _fP := _fP / 10.0; // 除十 / divide by ten
        _i := _i - 1; // 游标递减 / decrement the cursor
    END_WHILE
END_IF

// 段 6｜被舍实数与两段舍入（DINT 可表性分段，R63）/ segment 6, the value to be rounded and the two segment rounding
_fQ := _fAbs / _fP; // 被舍实数，除子为累乘幂已证非零 / the value to be rounded, the divisor is the proven power
IF _fQ < 1.0E9 THEN // 单段安全：q < 1.0E9 < DINT 上限（R63 反算）/ single segment safe against the DINT ceiling
    _nLo := TRUNC(_fQ + 0.5); // 半值远离零的整数舍入（|fVal| 口径恒正）/ integral rounding half away from zero on the always positive magnitude
    _fR := DINT_TO_LREAL(_nLo); // 整数精确落 LREAL / the integer lands exactly in LREAL
ELSE // 两段分解：高段 < 1.0E9、低段 < 1.0E6 均可表 / the two segment decomposition, both segments representable
    _fQHi := _fQ / 1000000.0; // 高段 = q / 1E6 / the high segment
    _nHi := TRUNC(_fQHi); // 高段截断 / truncate the high segment
    _fQLo := _fQ - DINT_TO_LREAL(_nHi) * 1000000.0; // 低段 = 余量 / the low segment remainder
    _nLo := TRUNC(_fQLo + 0.5); // 低段舍入 / round the low segment
    _fR := DINT_TO_LREAL(_nHi) * 1000000.0 + DINT_TO_LREAL(_nLo); // 合成（< 1E15 < 2^53 精确，进位由加法自然承载）/ the composition, exact below two to the fifty third, the carry rides the addition
END_IF

// 段 7｜符号回贴与出口 / segment 7, sign restore and the outlet
IF fVal < 0.0 THEN // 负值 / a negative value
    fOut := -_fR * _fP; // 符号回贴 / restore the sign
ELSE // 非负值 / a non negative value
    fOut := _fR * _fP; // 直接过出口 / straight to the outlet
END_IF
END_FUNCTION
