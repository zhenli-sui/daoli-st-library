(*
    FC_DL_AbsEx —— 实数绝对值防御包装（-0.0 归一、NaN/无穷拦截、极值溢出钳位）
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
    功能说明  : 求输入实数的绝对值。NaN 输入直接拦截返回 0.0 并置 16#0001_015E；
                无穷输入（超出双精度有限极值）同口径拦截归零；-0.0 归一
                为 +0.0；负数经符号取反实现，当绝对值恰为双精度极值
                1.7976931348623157E308 时按上溢口径钳位到同值并置 16#0001_022C
                （钳位值与真实绝对值一致，bValid=TRUE 降级可用）。
                全程绝不向下游输出 NaN/Inf 毒值。
    错误码    : 0000 正常 / 16#0001_015E 入参越界（NaN/无穷，已归零） / 16#0001_022C 上溢下溢（已钳位到类型极值）
    修订记录  : 2026-11-16 v1.0.0 首次入库（R15）
*)
FUNCTION FC_DL_AbsEx : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，任意有限值或 NaN/无穷 / input real value [dimensionless], any finite value or NaN/inf
END_VAR
VAR_OUTPUT
    eErr : UDINT; // 错误码，0=正常，1=入参越界，2=上溢钳位 / error id, 0=ok, 1=input out of domain, 2=overflow clamped
    bError   : BOOL; // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid   : BOOL; // 输出是否有效可用，16#0001_022C 钳位降级时保持 TRUE / output valid, stays TRUE for usable clamped result of code 2
END_VAR
VAR
    lrAbs : LREAL; // 绝对值中间量 [无量纲] / intermediate absolute value [dimensionless]
END_VAR
VAR CONSTANT
    DL_AB_MAXREAL : LREAL := 1.7976931348623157E308; // 双精度有限极值 [无量纲]，超界判无穷，禁魔法数 / double precision finite max [dimensionless], beyond treated as infinity, no magic numbers
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states so no early exit leaves stale codes
FC_DL_AbsEx := 0.0; // 返回值预置安全值 0.0 [无量纲] / preset return to safe value 0.0
eErr    := 16#0000_0000; // 错误码预置正常 / preset error id to ok
bError      := FALSE; // 错误标志预置无错 / preset error flag to FALSE
bValid      := TRUE; // 有效标志预置可用 / preset valid flag to TRUE

// 段 2｜非有限拦截：NaN 用自不等判据，无穷用超极值判据，一律不进取反运算 / segment 2, non-finite interception, NaN by self-inequality and infinity by bound test
IF (lrIn <> lrIn) OR (lrIn > DL_AB_MAXREAL) OR (lrIn < -DL_AB_MAXREAL) THEN
    eErr := 16#0001_015E; // 信息级：输入非有限，已归零 / informational, non-finite input, zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出 0.0 非真实结果，不可用 / output 0.0 is not the true result, invalid
    RETURN; // 返回预置安全值 0.0 / return preset safe value 0.0
END_IF

// 段 3｜零值归一：与 0.0 精确比较对 -0.0 与 +0.0 均成立，统一归 +0.0 / segment 3, zero normalization, exact compare catches both minus zero and plus zero
IF lrIn = 0.0 THEN
    FC_DL_AbsEx := 0.0; // -0.0 归一为 +0.0 / normalize minus zero to plus zero
    RETURN;
END_IF

// 段 4｜负数取反与极值溢出钳位 / segment 4, negation for negative input with extreme-value overflow clamp
IF lrIn < 0.0 THEN
    IF lrIn <= -DL_AB_MAXREAL THEN
        lrAbs    := DL_AB_MAXREAL; // 绝对值恰为极值，按上溢口径钳位 / magnitude at the extreme, clamped per overflow policy
        eErr := 16#0001_022C; // 上溢码：已钳位到类型极值 / overflow code, clamped to type extreme
        bError   := TRUE; // 置错误标志 / raise error flag
        // bValid 保持 TRUE：钳位值与真实绝对值一致，降级可用 / valid stays TRUE, clamped value equals the true absolute value
    ELSE
        lrAbs := -lrIn; // 域内负数直接取反 / in-domain negative input negated
    END_IF
ELSE
    lrAbs := lrIn; // 正数直通 / positive input passes through
END_IF

// 段 5｜结果非有限复检兜底（防御纵深，正常路径不可达） / segment 5, result finiteness recheck as defense in depth
IF lrAbs <> lrAbs THEN
    lrAbs    := 0.0; // 兜底安全值 / bottom-line safe value
    eErr := 16#0001_015E; // 信息级：结果异常归零 / informational, abnormal result zeroed
    bError   := TRUE; // 置错误标志 / raise error flag
    bValid   := FALSE; // 输出不可用 / output invalid
END_IF
FC_DL_AbsEx := lrAbs; // 输出绝对值 [无量纲] / output the absolute value
END_FUNCTION
