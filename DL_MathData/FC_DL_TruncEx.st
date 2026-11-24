(*
    FC_DL_TruncEx —— 向零取整防御包装（DINT 范围钳位 + NaN 拦截）
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
    功能说明  : 向零取整（委托内建 TRUNC），如 1.9 得 1、-1.9 得 -1。
                NaN 输入拦截返回 0 并置 16#0001_018B；结果超 DINT 范围
                [-2147483648, 2147483647] 时钳位到对应边界并置 16#0001_0259
                （钳位值非真实取整，bValid=FALSE；无穷输入被范围闸自然
                拦截）。先做范围闸再调 TRUNC，保证内建转换永不溢出。
    错误码    : 0000 正常 / 16#0001_018B 入参越界（NaN 已归零） / 16#0001_0259 上溢下溢（已钳位到 DINT 边界）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_TruncEx : DINT
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，任意有限值或 NaN/无穷 / input real value [dimensionless], any finite value or NaN/inf
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界，2=上溢下溢 / error id, 0=ok, 1=input out of domain, 2=overflow or underflow
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，钳位降级时为 FALSE / output valid, FALSE for clamped degraded results
END_VAR
VAR CONSTANT
    DL_TR_HI : LREAL := 2147483648.0; // DINT 上溢闸 [无量纲]，入参达到即超界 / DINT upper overflow gate [dimensionless]
    DL_TR_LO : LREAL := -2147483649.0; // DINT 下溢闸 [无量纲]，入参达到即超界 / DINT lower overflow gate [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_TruncEx := 0; // 返回值预置安全值 0 / preset return to safe value 0
eErr      := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError        := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid        := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：自不等判据，归零早退，不进内核 / segment 2, NaN interception by self-inequality, zeroed early exit
IF lrIn <> lrIn THEN
    eErr := 16#0001_018B; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN; // 返回预置安全值 0 / return preset safe value 0
END_IF

// 段 3｜DINT 范围闸：先判后转换，保证内建 TRUNC 永不溢出（无穷输入同样命中闸） / segment 3, DINT range gate, decide before conversion so built-in TRUNC never overflows, infinity hits the gate too
IF lrIn >= DL_TR_HI THEN
    FC_DL_TruncEx := 2147483647; // 上溢钳位到 DINT 上界 / overflow clamped to the DINT upper bound
    eErr      := 16#0001_0259; // 上溢码 / overflow code
    bError        := TRUE; // 置错误标志 / raise error flag
    bValid        := FALSE; // 钳位值非真实取整 / clamped value is not the true truncation
    RETURN;
ELSIF lrIn <= DL_TR_LO THEN
    FC_DL_TruncEx := -2147483648; // 下溢钳位到 DINT 下界 / underflow clamped to the DINT lower bound
    eErr      := 16#0001_0259; // 下溢码 / underflow code
    bError        := TRUE; // 置错误标志 / raise error flag
    bValid        := FALSE; // 钳位值非真实取整 / clamped value is not the true truncation
    RETURN;
END_IF

// 段 4｜域内委托内建 TRUNC（向零取整） / segment 4, in-domain delegation to built-in TRUNC, rounding toward zero
FC_DL_TruncEx := TRUNC(lrIn); // 委托内建 TRUNC 内核，不自实现取整内核 / delegate to built-in TRUNC kernel

// 段 5｜结果复检兜底（防御纵深，正常路径不可达） / segment 5, result recheck as defense in depth
IF (FC_DL_TruncEx <> FC_DL_TruncEx) OR (FC_DL_TruncEx > 2147483647) OR (FC_DL_TruncEx < -2147483648) THEN
    FC_DL_TruncEx := 0; // 兜底安全值 / bottom-line safe value
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_018B; // 首事件优先置码 / first-event priority code
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
END_IF
END_FUNCTION
