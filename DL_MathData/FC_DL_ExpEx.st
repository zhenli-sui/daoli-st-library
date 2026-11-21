(*
    FC_DL_ExpEx —— 自然指数防御包装（上溢/下溢预判钳位 + NaN 拦截）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Exp
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R15）
    ------------------------------------------------------------------
    功能说明  : 求自然指数 EXP(lrIn)。NaN 输入拦截返回 0.0 并置 16#0001_0181；
                上溢预判 lrIn > 709.782712893384 时直接返回双精度极值并置
                16#0001_024F（饱和值降级可用，bValid=TRUE）；下溢预判 lrIn <
                -745.1332191019411 时返回 0.0 并置 16#0001_024F（bValid=TRUE 降级
                可用）；域内委托内建 EXP，结果再做 NaN/Inf 复检兜底，全程
                不输出 NaN/Inf。
    错误码    : 0000 正常 / 16#0001_0181 入参越界（NaN 已归零） / 16#0001_024F 上溢下溢（已钳位到类型极值，降级可用）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_ExpEx : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入指数 [无量纲]，任意有限值或 NaN/无穷 / input exponent [dimensionless], any finite value or NaN/inf
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界，2=上溢下溢 / error id, 0=ok, 1=input out of domain, 2=overflow or underflow
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，16#0001_024F 饱和降级时保持 TRUE / output valid, stays TRUE for saturated degraded result of code 2
END_VAR
VAR CONSTANT
    DL_EX_MAXREAL : LREAL := 1.7976931348623157E308; // 双精度有限极值 [无量纲]，上溢钳位目标 / double precision finite max [dimensionless], overflow clamp target
    DL_EX_OV      : LREAL := 709.782712893384; // 上溢预判阈值 [无量纲]，超过则 EXP 结果超极值 / overflow pre-check threshold [dimensionless]
    DL_EX_UN      : LREAL := -745.1332191019411; // 下溢预判阈值 [无量纲]，低于则 EXP 结果归零 / underflow pre-check threshold [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states
FC_DL_ExpEx := 0.0; // 返回值预置安全值 0.0 / preset return to safe value 0.0
eErr    := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError      := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid      := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜NaN 拦截：自不等判据，归零早退，不进内核 / segment 2, NaN interception by self-inequality, zeroed early exit
IF lrIn <> lrIn THEN
    eErr := 16#0001_0181; // 信息级：输入 NaN，已归零 / informational, NaN input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
    RETURN; // 返回预置安全值 0.0 / return preset safe value 0.0
END_IF

// 段 3｜上溢/下溢预判闸：先判后算，杜绝 Inf 穿透（正无穷输入同样命中上溢闸） / segment 3, overflow and underflow pre-check gates, decide before computing, plus infinity hits the overflow gate too
IF lrIn > DL_EX_OV THEN
    FC_DL_ExpEx := DL_EX_MAXREAL; // 上溢钳位到双精度极值 / overflow clamped to the double precision max
    eErr    := 16#0001_024F; // 上溢码：已钳位到类型极值 / overflow code, clamped to type extreme
    bError      := TRUE; // 置错误标志 / raise error flag
    // bValid 保持 TRUE：饱和值降级可用 / valid stays TRUE, saturated value usable in degraded mode
    RETURN;
ELSIF lrIn < DL_EX_UN THEN
    FC_DL_ExpEx := 0.0; // 下溢钳位到 0.0 / underflow clamped to 0.0
    eErr    := 16#0001_024F; // 下溢码：已钳位到类型极值 / underflow code, clamped to type extreme
    bError      := TRUE; // 置错误标志 / raise error flag
    // bValid 保持 TRUE：下溢结果 0.0 降级可用 / valid stays TRUE, underflow 0.0 usable in degraded mode
    RETURN;
END_IF

// 段 4｜域内委托内建 EXP / segment 4, in-domain delegation to built-in EXP
FC_DL_ExpEx := EXP(lrIn); // 委托内建 EXP 内核，不自实现指数内核 / delegate to built-in EXP kernel

// 段 5｜结果复检兜底：NaN 归零置 16#0001_0181，超极值钳位置 16#0001_024F / segment 5, result recheck, NaN zeroed with code 1, beyond-extreme clamped with code 2
IF FC_DL_ExpEx <> FC_DL_ExpEx THEN
    FC_DL_ExpEx := 0.0; // 兜底安全值 / bottom-line safe value
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_0181; // 首事件优先置码 / first-event priority code
        bError   := TRUE; // 置错误标志 / raise error flag
        bValid   := FALSE; // 输出不可用 / output invalid
    END_IF
ELSIF FC_DL_ExpEx > DL_EX_MAXREAL THEN
    FC_DL_ExpEx := DL_EX_MAXREAL; // 防御纵深钳位 / defense in depth clamp
    IF eErr = 16#0000_0000 THEN
        eErr := 16#0001_024F; // 上溢码 / overflow code
        bError   := TRUE; // 置错误标志 / raise error flag
    END_IF
END_IF
END_FUNCTION
