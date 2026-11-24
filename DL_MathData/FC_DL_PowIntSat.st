(*
    FC_DL_PowIntSat —— 整数幂 Safe 族防御包装（指数钳位 [0,63] + 显式符号分支 + 溢出饱和）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Power
    前缀      : FC_DL_
    版本      : 1.0.1
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （纯循环乘法实现，不依赖 EXPT 浮点路径，无幂运算符；
                  未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_ExptEx / FC_DL_FactorialSat 分工——ExptEx 为浮点
                任意底任意指数码位族（委托 EXPT），本件为整数指数幂的 Safe 族
                口径（循环乘 + 预检饱和）；FactorialSat 只做阶乘口径。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 求 fBase 的 nExp 整数次幂。四段式防御（R45）：底数/指数非有限
                双判据拦截；nExp 钳位 [0, 63]（极限值→可表性反算，R63：2^63
                约 9.22E18，最大底数 1.79E308 时 2 次幂即越界，由乘法预检饱和
                兜底，63 为指数域钳位上界）；底 0 且 0 次幂判错误（返回 0）；
                负底符号按奇偶显式分支（|底| 循环乘，符号末段乘回）；每次乘法
                前做 acc > MAX/|底| 预检防 Inf，超界饱和。
    错误码    : 0000 正常 / 16#0002_0001 入参非有限已归零 / 16#0002_0002 指数已钳位 / 16#0002_0003 底 0 的 0 次幂 / 16#0002_0006 结果已饱和
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 2 · 序号 10）
                2026-11-21 v1.0.1 R58 返修：段 4 饱和置码 0206 原为无条件，会
                覆盖先发事件 0202（指数钳位）；补首事件闸对齐段 5 口径；95~97
                行 bError/bValid/bClamped 保持无条件（标志级聚合，码级唯一）。
*)
FUNCTION FC_DL_PowIntSat : LREAL
VAR_INPUT
    fBase : LREAL; // 底数实数 [无量纲] / the base real value [dimensionless]
    nExp  : INT;   // 整数指数 [次]，钳位 [0, 63] / the integer exponent, clamped to zero through sixty three
END_VAR
VAR_OUTPUT
    eErr     : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError   : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid   : BOOL;  // 结果是否为真实值，钳位/饱和降级时为假 / the result is the true value, false when degraded
    bClamped : BOOL;  // 本次调用发生指数或幅值钳位 [-] / an exponent or magnitude clamp happened this call
END_VAR
VAR
    lrMag  : LREAL; // 幅值累乘量 [无量纲] / the magnitude accumulator [dimensionless]
    lrAbB  : LREAL; // 底数绝对值 [无量纲] / the base magnitude [dimensionless]
    nI     : INT;   // 循环计数 [次] / the loop counter
    bNeg   : BOOL;  // 结果应为负（负底奇次幂）[-] / the result should be negative, an odd power of a negative base
END_VAR
VAR CONSTANT
    DL_POW_EXPMAX : INT   := 63;                  // 指数钳位上界 [次]（R63）/ the exponent clamp bound
    DL_POW_MAGMAX : LREAL := 1.7976931348623157E308; // LREAL 可表上界 [无量纲] / the representable magnitude bound
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_PowIntSat := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
eErr     := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError   := FALSE; // 错误标志预置假 / preset the error flag false
bValid   := TRUE; // 有效标志预置真 / preset the valid flag true
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false

// 段 2｜非有限拦截（双判据）：命中直接早退 / segment 2, the non finite interception
IF (fBase <> fBase) OR ((fBase - fBase) <> (fBase - fBase)) THEN // 底数非有限 / a non finite base
    eErr   := 16#0002_0001; // 信息级：底数非有限已归零 / informational, a non finite base zeroed
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0.0 / return the preset safe zero
END_IF

// 段 3｜指数钳位与底 0 的 0 次幂判定 / segment 3, the exponent clamp and the zero base zero power
IF nExp < 0 THEN // 负指数越下界 / a negative exponent
    nExp     := 0; // 钳到 0 / clamp to zero
    eErr     := 16#0002_0002; // 信息级：指数已钳位 / informational, the exponent clamped
    bError   := TRUE; // 置错误标志 / raise the error flag
    bValid   := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF nExp > DL_POW_EXPMAX THEN // 越上界 / above the bound
    nExp     := DL_POW_EXPMAX; // 钳到上界 / clamp to the bound
    eErr     := 16#0002_0002; // 信息级：指数已钳位 / informational, the exponent clamped
    bError   := TRUE; // 置错误标志 / raise the error flag
    bValid   := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
END_IF
IF (fBase = 0.0) AND (nExp = 0) THEN // 底 0 的 0 次幂（数学未定义，判错误）/ the zero base zero power, undefined
    eErr   := 16#0002_0003; // 错误级：底 0 的 0 次幂返回 0 / error grade, the zero base zero power returns zero
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0.0 / return the preset safe zero
END_IF
IF fBase = 0.0 THEN // 底 0 的正整数幂恒为 0 / a zero base with a positive power is zero
    RETURN; // 返回安全值 0.0，标志保持正常 / return the safe zero, the flags stay ok
END_IF

// 段 4｜幅值循环乘 + 预检饱和 + 负底奇偶符号显式分支 / segment 4, the magnitude loop with the pre-check saturation and the explicit sign branch
lrAbB := ABS(fBase); // 底数绝对值 / the base magnitude
bNeg  := (fBase < 0.0) AND ((nExp MOD 2) = 1); // 负底且奇次幂为负（nExp 非负，MOD 合法）/ negative when an odd power of a negative base
lrMag := 1.0; // 幅值从 1 起乘 / the magnitude starts at one
FOR nI := 1 TO nExp DO // 逐次乘（nExp 已钳 ≤63，循环有界）/ the bounded loop
    IF lrMag > DL_POW_MAGMAX / lrAbB THEN // 乘前预检防 Inf（除子为正底绝对值已证大于零）/ the pre-check against infinity
        lrMag    := DL_POW_MAGMAX; // 幅值饱和到可表上界 / saturate the magnitude
        IF eErr = 16#0000_0000 THEN // 首事件优先置码（对齐段 5 闸式，v1.0.1）/ the first event keeps the code, aligned with segment five
            eErr     := 16#0002_0006; // 信息级：结果已饱和 / informational, the result saturated
        END_IF
        bError   := TRUE; // 置错误标志（标志级无条件聚合）/ raise the error flag unconditionally
        bValid   := FALSE; // 饱和结果非真实值 / the saturated result is not the true value
        bClamped := TRUE; // 置钳位标志 / raise the clamp flag
        EXIT; // 提前出循环 / leave the loop early
    END_IF
    lrMag := lrMag * lrAbB; // 幅值累乘 / accumulate the magnitude
END_FOR
IF bNeg THEN // 负底奇次幂符号乘回（显式分支，边界十）/ the sign multiplied back, the explicit branch
    FC_DL_PowIntSat := -lrMag; // 负结果 / the negative result
ELSE // 正结果（含负底偶次幂）/ the positive result, including an even power of a negative base
    FC_DL_PowIntSat := lrMag; // 正结果 / the positive result
END_IF

// 段 5｜结果非有限复核兜底（防御纵深，正常路径不可达）/ segment 5, the result recheck as defense in depth
IF (FC_DL_PowIntSat <> FC_DL_PowIntSat) OR ((FC_DL_PowIntSat - FC_DL_PowIntSat) <> (FC_DL_PowIntSat - FC_DL_PowIntSat)) THEN // 结果非有限 / a non finite result
    FC_DL_PowIntSat := 0.0; // 兜底安全值 / the bottom-line safe value
    IF eErr = 16#0000_0000 THEN // 首事件优先置码 / the first event keeps the code
        eErr   := 16#0002_0001; // 信息级：结果非有限已归零 / informational, a non finite result zeroed
        bError := TRUE; // 置错误标志 / raise the error flag
        bValid := FALSE; // 输出不可用 / the output void
    END_IF
END_IF
END_FUNCTION
