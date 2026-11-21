(*
    FC_DL_SignumCalc —— 三态符号函数（浮点容差判零 + 非有限拦截）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Sign
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （纯比较逻辑，无内建数学内核依赖；未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_RealEqTolEx（判等）分工——EqTolEx 只回答是否相等，
                本件返回三态符号（负/零/正）；与 Hysteresis 分工——迟滞件带
                状态记忆，本件为无状态纯函数。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 返回输入的三态符号：|x| < fEps 判零返回 0（禁 = 判等）；
                x <= -fEps 返回 -1；x >= fEps 返回 +1。fEps <= 0 组态错误
                返回 0；非有限（NaN/Inf 双判据）返回 0 并出错误码。
    错误码    : 0000 正常 / 16#0003_0001 入参非有限 / 16#0003_0002 fEps 组态非法
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 3 · 序号 11）
*)
FUNCTION FC_DL_SignumCalc : INT
VAR_INPUT
    lrIn : LREAL;       // 输入实数 [工程单位] / input real value [engineering unit]
    fEps : LREAL := 1E-9; // 判零容差 [工程单位]，域 大于零 / the zero tolerance [engineering unit], above zero
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid : BOOL;  // 结果是否可用，拦截/组态错误时为假 / the result usable, false when intercepted
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_SignumCalc := 0; // 符号预置零 / preset the sign to zero
eErr   := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bValid := TRUE; // 有效标志预置真 / preset the valid flag true

// 段 2｜非有限拦截（双判据）：命中早退不比较 / segment 2, the non finite interception
IF (lrIn <> lrIn) OR ((lrIn - lrIn) <> (lrIn - lrIn)) THEN // NaN 或无穷 / NaN or infinity
    eErr   := 16#0003_0001; // 信息级：输入非有限返回零 / informational, a non finite input returns zero
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0 / return the preset safe zero
END_IF

// 段 3｜组态闸：fEps <= 0 判组态错误（边界十一）/ segment 3, the config gate, a nonpositive tolerance illegal
IF (fEps <= 0.0) OR (fEps <> fEps) OR ((fEps - fEps) <> (fEps - fEps)) THEN // 容差非法或非有限 / an illegal or non finite tolerance
    eErr   := 16#0003_0002; // 错误级：容差组态非法 / error grade, an illegal tolerance config
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0 / return the preset safe zero
END_IF

// 段 4｜三态符号判定：容差判零，禁 = 判等（边界十一）/ segment 4, the three state verdict with the tolerance
IF lrIn >= fEps THEN // 显著为正 / clearly positive
    FC_DL_SignumCalc := 1; // 返回正号 / return plus one
ELSIF lrIn <= -fEps THEN // 显著为负 / clearly negative
    FC_DL_SignumCalc := -1; // 返回负号 / return minus one
ELSE // 容差带内判零 / inside the tolerance band
    FC_DL_SignumCalc := 0; // 返回零 / return zero
END_IF
END_FUNCTION
