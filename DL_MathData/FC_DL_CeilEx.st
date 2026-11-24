(*
    FC_DL_CeilEx —— 向上取整防御包装（向 +∞，DINT 范围钳位 + NaN 拦截）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Round
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R15）
    ------------------------------------------------------------------
    功能说明  : 向正无穷方向取整（委托内建 CEIL），负小数如 -1.2 得
                -1。NaN 输入拦截返回 0 并置 16#0001_0195；先以 LREAL 承载 CEIL
                结果再做 DINT 范围闸（CEIL 本身不会上溢 LREAL），超
                [-2147483648, 2147483647] 时钳位到边界并置 16#0001_0263，bValid=
                FALSE；无穷输入被范围闸自然拦截。范围内再经 LREAL_TO_DINT
                显式转换，转换永不溢出。
    错误码    : 0000 正常 / 16#0001_0195 入参越界（NaN 已归零） / 16#0001_0263 上溢下溢（已钳位到 DINT 边界）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_CeilEx : DINT
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，任意有限值或 NaN/无穷 / input real value [dimensionless], any finite value or NaN/inf
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界，2=上溢下溢 / error id, 0=ok, 1=input out of domain, 2=overflow or underflow
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，钳位降级时为 FALSE / output valid, FALSE for clamped degraded results
END_VAR
VAR
    lrR : LREAL; // CEIL 结果中间量 [无量纲]，LREAL 承载不溢出 / intermediate CEIL result [dimensionless], carried in LREAL without overflow
END_VAR
VAR CONSTANT
    DL_CE_HI : LREAL := 2147483647.0; // DINT 上界 [无量纲]，超过即钳位 / DINT upper bound [dimensionless], beyond clamped
    DL_CE_LO : LREAL := -2147483648.0; // DINT 下界 [无量纲]，低于即钳位 / DINT lower bound [dimensionless], below clamped
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_CeilEx := 0; // 返回值预置安全值 0 / preset return to safe value 0
eErr     := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError       := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid       := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：自不等判据，归零早退，不进内核 / segment 2, NaN interception by self-inequality, zeroed early exit
IF lrIn <> lrIn THEN
    eErr := 16#0001_0195; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN; // 返回预置安全值 0 / return preset safe value 0
END_IF

// 段 3｜委托内建 CEIL（向 +∞ 取整），LREAL 承载结果，无穷输入得无穷 / segment 3, delegation to built-in CEIL toward plus infinity, LREAL carry, infinite input stays infinite
lrR := CEIL(lrIn); // 委托内建 CEIL 内核，不自实现取整内核 / delegate to built-in CEIL kernel

// 段 4｜DINT 范围闸：超界钳位并置 16#0001_0263（无穷输入在此被拦截） / segment 4, DINT range gate, clamp beyond bounds with code 2, infinite input intercepted here
IF lrR > DL_CE_HI THEN
    FC_DL_CeilEx := 2147483647; // 上溢钳位到 DINT 上界 / overflow clamped to the DINT upper bound
    eErr     := 16#0001_0263; // 上溢码 / overflow code
    bError       := TRUE; // 置错误标志 / raise error flag
    bValid       := FALSE; // 钳位值非真实取整 / clamped value is not the true ceiling
    RETURN;
ELSIF lrR < DL_CE_LO THEN
    FC_DL_CeilEx := -2147483648; // 下溢钳位到 DINT 下界 / underflow clamped to the DINT lower bound
    eErr     := 16#0001_0263; // 下溢码 / underflow code
    bError       := TRUE; // 置错误标志 / raise error flag
    bValid       := FALSE; // 钳位值非真实取整 / clamped value is not the true ceiling
    RETURN;
END_IF

// 段 5｜范围内显式转换输出（转换永不溢出） / segment 5, explicit in-range conversion and output
FC_DL_CeilEx := LREAL_TO_DINT(lrR); // 范围内显式转换 / explicit in-range conversion
END_FUNCTION
