(*
    FC_DL_SinEx —— 正弦防御包装（2π 周期归约保精度 + 非有限拦截 + 超大角度降级）
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
    功能说明  : 求输入弧度的正弦值。入口先做非有限拦截（NaN/Inf 返回 0.0
                并置 16#0001_0163）；随后按 2π 做周期归约，商取 FLOOR 语义避免负向
                误差，商绝对值 < 2.0E9 保证 DINT 转换不溢出；超大角度
                （绝对值 > 1.0E12 或商超 DINT 安全域）降级处理：置 16#0001_0163、
                bValid=FALSE 但仍继续计算；域内委托内建 SIN，结果再做
                NaN 复检兜底，全程不输出 NaN/Inf。
    错误码    : 0000 正常 / 16#0001_0163 入参越界（非有限输入或超大角度降级，已归零/降级可用）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_SinEx : LREAL
VAR_INPUT
    lrRad : LREAL; // 输入角度 [rad]，任意有限弧度值 / input angle [rad], any finite radian value
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界（非有限或超大角度） / error id, 0=ok, 1=input out of domain (non-finite or super-large angle)
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，超大角度降级时为 FALSE / output valid, FALSE for degraded super-large angle
END_VAR
VAR
    lrQ   : LREAL; // 周期商 [周期数]，输入角除以 2π / cycle quotient [cycles], input divided by two pi
    nCyc  : DINT; // 归约周期数 [周期数]，FLOOR 语义整数 / reduction cycle count [cycles], integer with floor semantics
    lrRed : LREAL; // 归约后弧度 [rad]，域约至 0 到 2π / reduced angle [rad], bounded to 0 to 2 pi
END_VAR
VAR CONSTANT
    DL_SN_MAXREAL : LREAL := 1.7976931348623157E308; // 双精度有限极值 [rad]，超界判无穷 / double precision finite max [rad], beyond treated as infinity
    DL_SN_TWOPI   : LREAL := 6.283185307179586; // 圆周率两倍 [rad]，归约模数 / two pi [rad], reduction modulus
    DL_SN_BIG     : LREAL := 1.0E12; // 超大角度阈值 [rad]，超过判降级 / super-large angle threshold [rad], beyond degraded
    DL_SN_QMAX    : LREAL := 2.0E9; // 周期商安全域 [周期数]，保证 DINT 转换不溢出 / quotient safe bound [cycles], keeps DINT conversion overflow-free
    DL_SN_EPS     : LREAL := 1.0E-9; // 浮点容差 [无量纲] / floating point tolerance [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_SinEx := 0.0; // 返回值预置安全值 0.0 / preset return to safe value 0.0
eErr    := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError      := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid      := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜非有限拦截：NaN 用自不等判据，无穷用超极值判据 / segment 2, non-finite interception
IF (lrRad <> lrRad) OR (lrRad > DL_SN_MAXREAL) OR (lrRad < -DL_SN_MAXREAL) THEN
    eErr := 16#0001_0163; // 信息级：输入非有限，已归零 / informational, non-finite input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN; // 返回预置安全值 0.0 / return preset safe value 0.0
END_IF

// 段 3｜2π 周期归约（FLOOR 语义）：商超 DINT 安全域则跳过归约原值直通 / segment 3, two-pi reduction with floor semantics, skipped when quotient exceeds the DINT safe bound
lrQ := lrRad / DL_SN_TWOPI; // 周期商 [周期数] / cycle quotient [cycles]
IF ABS(lrQ) < DL_SN_QMAX THEN
    nCyc := TRUNC(lrQ); // 向零截取周期数 / truncate quotient toward zero
    IF (lrQ < 0.0) AND (ABS(lrQ - DINT_TO_LREAL(nCyc)) > DL_SN_EPS) THEN
        nCyc := nCyc - 1; // 负非整数商补一，落实 FLOOR 语义 / decrement for negative non-integer quotient to enforce floor semantics
    END_IF
    lrRed := lrRad - DL_SN_TWOPI * DINT_TO_LREAL(nCyc); // 归约后弧度 [rad] / reduced angle [rad]
ELSE
    lrRed := lrRad; // 商超安全域，放弃归约原值直通 / quotient beyond safe bound, reduction skipped
END_IF

// 段 4｜超大角度精度闸：置 16#0001_0163 降级但继续计算 / segment 4, super-large angle precision gate, degraded with code 1 but computation continues
IF (ABS(lrRad) > DL_SN_BIG) OR (ABS(lrQ) >= DL_SN_QMAX) THEN
    eErr := 16#0001_0163; // 信息级：超大角度，精度不可保证 / informational, super-large angle, precision not guaranteed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 降级输出，需上层注意 / degraded output, upper layer attention required
END_IF

// 段 5｜委托内建 SIN + 结果 NaN 复检兜底 / segment 5, delegation to built-in SIN with result NaN recheck
FC_DL_SinEx := SIN(lrRed); // 委托内建 SIN 内核，不自实现三角内核 / delegate to built-in SIN kernel
IF FC_DL_SinEx <> FC_DL_SinEx THEN
    FC_DL_SinEx := 0.0; // 兜底安全值 / bottom-line safe value
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_0163; // 首事件优先置码 / first-event priority code
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
END_IF
END_FUNCTION
