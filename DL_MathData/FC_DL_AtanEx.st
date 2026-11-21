(*
    FC_DL_AtanEx —— 反正切防御包装（全实数域 + NaN/无穷拦截降级）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Trig
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R15）
    ------------------------------------------------------------------
    功能说明  : 求输入的反正切，全实数域合法，返回值域 (-pi/2, pi/2)。
                NaN 输入拦截返回 0.0 并置 16#0001_0177；正无穷按极限口径返回
                pi/2、负无穷返回 -pi/2，均置 16#0001_0177 且 bValid=FALSE 降级；
                有限域内直接委托内建 ATAN；结果再做 NaN 复检兜底，全程
                不输出 NaN/Inf。
    错误码    : 0000 正常 / 16#0001_0177 入参越界（NaN 已归零，或无穷已取极限值降级）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_AtanEx : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，全实数域 / input real value [dimensionless], full real domain
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界（NaN/无穷降级） / error id, 0=ok, 1=input out of domain (NaN or infinity degraded)
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，降级时为 FALSE / output valid, FALSE for degraded results
END_VAR
VAR CONSTANT
    DL_AT_MAXREAL : LREAL := 1.7976931348623157E308; // 双精度有限极值 [无量纲]，超界判无穷 / double precision finite max [dimensionless], beyond treated as infinity
    DL_AT_PI2     : LREAL := 1.5707963267948966; // 圆周率一半 [rad]，无穷极限值 / half pi [rad], limit value at infinity
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_AtanEx := 0.0; // 返回值预置安全值 0.0 / preset return to safe value 0.0
eErr    := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError      := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid      := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：自不等判据，归零早退，不进内核 / segment 2, NaN interception by self-inequality, zeroed early exit
IF lrIn <> lrIn THEN
    eErr := 16#0001_0177; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN; // 返回预置安全值 0.0 / return preset safe value 0.0
END_IF

// 段 3｜无穷降级闸：按极限口径返回 ±pi/2 并置 16#0001_0177 / segment 3, infinity degradation gate, limit value plus or minus half pi returned with code 1
IF lrIn > DL_AT_MAXREAL THEN
    FC_DL_AtanEx := DL_AT_PI2; // 正无穷极限 +pi/2 / plus infinity limit plus half pi
    eErr     := 16#0001_0177; // 信息级：输入无穷，已取极限值 / informational, infinite input, limit value returned
    bError       := TRUE; // 置错误标志 / raise error flag
    bValid       := FALSE; // 降级输出 / degraded output
    RETURN;
ELSIF lrIn < -DL_AT_MAXREAL THEN
    FC_DL_AtanEx := -DL_AT_PI2; // 负无穷极限 -pi/2 / minus infinity limit minus half pi
    eErr     := 16#0001_0177; // 信息级：输入无穷，已取极限值 / informational, infinite input, limit value returned
    bError       := TRUE; // 置错误标志 / raise error flag
    bValid       := FALSE; // 降级输出 / degraded output
    RETURN;
END_IF

// 段 4｜有限域内委托内建 ATAN / segment 4, finite domain delegation to built-in ATAN
FC_DL_AtanEx := ATAN(lrIn); // 委托内建 ATAN 内核 / delegate to built-in ATAN kernel

// 段 5｜结果 NaN 复检兜底（防御纵深，正常路径不可达） / segment 5, result NaN recheck as defense in depth
IF FC_DL_AtanEx <> FC_DL_AtanEx THEN
    FC_DL_AtanEx := 0.0; // 兜底安全值 / bottom-line safe value
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_0177; // 首事件优先置码 / first-event priority code
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
END_IF
END_FUNCTION
