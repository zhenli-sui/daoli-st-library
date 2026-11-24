(*
    FC_DL_AsinSafe —— 反正弦 Safe 族防御包装（域钳位 + bClamped 显式标志 + 委托内建）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Trig
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建 ASIN，外围钳位/错误码/双语文档；
                  未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_AsinEx 分工——AsinEx 为码位族（16#0001_016D 口径），
                本件为 Safe 族样板（bClamped 显式钳位标志 + 16#0002 子带码位），
                两件并存服务不同调用方约定，算法内核同为内建 ASIN 委托。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 求输入的反正弦，返回值域 [-pi/2, pi/2]。四段式防御（R45）：
                NaN 双判据拦截归零早退；|x|>1（含无穷）钳到 ±1 并置 bClamped
                仍返回钳位结果供降级；域内委托内建 ASIN；结果 NaN 复检兜底。
    错误码    : 0000 正常 / 16#0002_0001 入参非有限已归零 / 16#0002_0002 域外已钳位
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 2 · 序号 6）
*)
FUNCTION FC_DL_AsinSafe : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，定义域 [-1,1] / input real value [dimensionless], domain minus one to plus one
END_VAR
VAR_OUTPUT
    eErr     : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError   : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid   : BOOL;  // 结果是否为真实值，钳位/归零降级时为假 / the result is the true value, false when degraded
    bClamped : BOOL;  // 本次调用发生定义域钳位 [-] / a domain clamp happened this call
END_VAR
VAR
    lrUse : LREAL; // 钳位后的实际计算入参 [无量纲] / the clamped value fed to the kernel [dimensionless]
END_VAR
VAR CONSTANT
    DL_ASN_DOM : LREAL := 1.0; // 定义域边界 [无量纲]，闭区间 / the domain bound [dimensionless], closed interval
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_AsinSafe := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
eErr     := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError   := FALSE; // 错误标志预置假 / preset the error flag false
bValid   := TRUE; // 有效标志预置真 / preset the valid flag true
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false

// 段 2｜非有限拦截（双判据）：命中不调内建直接早退 / segment 2, the non finite interception, early exit without the kernel
IF (lrIn <> lrIn) OR ((lrIn - lrIn) <> (lrIn - lrIn)) THEN // NaN 或无穷 / NaN or infinity
    eErr   := 16#0002_0001; // 信息级：输入非有限已归零 / informational, a non finite input zeroed
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0.0 / return the preset safe zero
END_IF

// 段 3｜定义域闸门：域外钳到 ±1 并置 bClamped，仍返回钳位结果 / segment 3, the domain gate, clamped to plus or minus one with the flag raised
IF lrIn > DL_ASN_DOM THEN // 上越界（含正无穷，已被段 2 拦截故此处为有限值）/ above the bound
    lrUse    := DL_ASN_DOM; // 钳到 +1 / clamp to plus one
    eErr     := 16#0002_0002; // 信息级：域外已钳位 / informational, clamped
    bError   := TRUE; // 置错误标志 / raise the error flag
    bValid   := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF lrIn < -DL_ASN_DOM THEN // 下越界 / below the bound
    lrUse    := -DL_ASN_DOM; // 钳到 -1 / clamp to minus one
    eErr     := 16#0002_0002; // 信息级：域外已钳位 / informational, clamped
    bError   := TRUE; // 置错误标志 / raise the error flag
    bValid   := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSE // 域内直通（±1 边界合法）/ inside the domain, the boundary legal
    lrUse := lrIn; // 直通 / passthrough
END_IF

// 段 4｜委托内建 ASIN（禁重实现数学内核）/ segment 4, delegation to the built-in ASIN
FC_DL_AsinSafe := ASIN(lrUse); // 委托内建内核 / delegate to the built-in kernel

// 段 5｜结果 NaN 复检兜底（防御纵深，正常路径不可达）/ segment 5, the result recheck as defense in depth
IF (FC_DL_AsinSafe <> FC_DL_AsinSafe) OR ((FC_DL_AsinSafe - FC_DL_AsinSafe) <> (FC_DL_AsinSafe - FC_DL_AsinSafe)) THEN // 结果非有限 / a non finite result
    FC_DL_AsinSafe := 0.0; // 兜底安全值 / the bottom-line safe value
    IF eErr = 16#0000_0000 THEN // 首事件优先置码 / the first event keeps the code
        eErr   := 16#0002_0001; // 信息级：结果非有限已归零 / informational, a non finite result zeroed
        bError := TRUE; // 置错误标志 / raise the error flag
        bValid := FALSE; // 输出不可用 / the output void
    END_IF
END_IF
END_FUNCTION
