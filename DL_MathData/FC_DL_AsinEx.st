(*
    FC_DL_AsinEx —— 反正弦防御包装（定义域 [-1,1] 域闸钳位 + NaN 拦截）
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
    功能说明  : 求输入的反正弦，返回值域 [-pi/2, pi/2]。定义域闸门先行：
                NaN 输入拦截返回 0.0 并置 16#0001_016D；定义域 [-1,1] 之外（含
                无穷）钳位到 ±1 并置 16#0001_016D，bValid=FALSE 但仍返回钳位后的
                计算结果（±pi/2）供降级使用；域内委托内建 ASIN，边界值
                ±1 为合法输入直接通过；结果再做 NaN 复检兜底。
    错误码    : 0000 正常 / 16#0001_016D 入参越界（NaN 已归零，或域外已钳位到 ±1）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_AsinEx : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，定义域 [-1,1] / input real value [dimensionless], domain minus 1 to plus 1
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界（已钳位/归零） / error id, 0=ok, 1=input out of domain, clamped or zeroed
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，钳位/归零降级时为 FALSE / output valid, FALSE for clamped or zeroed degraded results
END_VAR
VAR
    lrUse : LREAL; // 钳位后的实际计算入参 [无量纲] / clamped value actually fed to the kernel [dimensionless]
END_VAR
VAR CONSTANT
    DL_AS_DOM : LREAL := 1.0; // 定义域边界 [无量纲]，闭区间 / domain bound [dimensionless], closed interval
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_AsinEx := 0.0; // 返回值预置安全值 0.0 / preset return to safe value 0.0
eErr    := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError      := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid      := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：自不等判据，归零早退，不进内核 / segment 2, NaN interception by self-inequality, zeroed early exit
IF lrIn <> lrIn THEN
    eErr := 16#0001_016D; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN; // 返回预置安全值 0.0 / return preset safe value 0.0
END_IF

// 段 3｜定义域闸门：域外（含无穷）钳位到 ±1，仍返回钳位后结果 / segment 3, domain gate, out-of-domain including infinity clamped to plus or minus 1 with result still returned
IF lrIn > DL_AS_DOM THEN
    lrUse    := DL_AS_DOM; // 上越界钳位 +1 / upper overflow clamped to plus 1
    eErr := 16#0001_016D; // 信息级：域外已钳位 / informational, out of domain clamped
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 钳位结果非真实值 / clamped result is not the true value
ELSIF lrIn < -DL_AS_DOM THEN
    lrUse    := -DL_AS_DOM; // 下越界钳位 -1 / lower overflow clamped to minus 1
    eErr := 16#0001_016D; // 信息级：域外已钳位 / informational, out of domain clamped
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 钳位结果非真实值 / clamped result is not the true value
ELSE
    lrUse := lrIn; // 域内直通（±1 边界合法） / in-domain pass-through, boundary plus or minus 1 legal
END_IF

// 段 4｜委托内建 ASIN / segment 4, delegation to built-in ASIN
FC_DL_AsinEx := ASIN(lrUse); // 委托内建 ASIN 内核 / delegate to built-in ASIN kernel

// 段 5｜结果 NaN 复检兜底（防御纵深，正常路径不可达） / segment 5, result NaN recheck as defense in depth
IF FC_DL_AsinEx <> FC_DL_AsinEx THEN
    FC_DL_AsinEx := 0.0; // 兜底安全值 / bottom-line safe value
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_016D; // 首事件优先置码 / first-event priority code
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
END_IF
END_FUNCTION
