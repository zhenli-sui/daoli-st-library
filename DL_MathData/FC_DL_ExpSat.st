(*
    FC_DL_ExpSat —— 指数 Safe 族防御包装（上溢饱和不 Inf + 下饱和钳零 + 委托内建）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Exp
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建 EXP，外围饱和/错误码/双语文档；
                  未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_ExpEx / FC_DL_ExptEx 分工——ExpEx 为码位族直通
                包装，ExptEx 为任意底指数；本件只做 Safe 族饱和口径（上溢
                饱和至 LREAL 可表上界不出 Inf，负大下饱和钳零）。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 求输入的指数 e^x。四段式防御（R45）：NaN 双判据拦截归零早退；
                x > 709.78 上溢界（极限值→可表性反算，R63：EXP(709.78) ≈
                1.7968E308 < LREAL 上界 1.7976931348623157E308 可表）饱和返回
                EXP(709.78) 不出 Inf；x < -745.1 下饱和返回 0（EXP(-745.2) 即
                下溢为 0）；域内委托内建 EXP；结果非有限二次复核兜底。
    错误码    : 0000 正常 / 16#0002_0001 入参非有限已归零 / 16#0002_0004 上溢已饱和 / 16#0002_0005 下溢已钳零
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 2 · 序号 9）
*)
FUNCTION FC_DL_ExpSat : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲] / input real value [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid : BOOL;  // 结果是否为真实值，饱和/归零降级时为假 / the result is the true value, false when degraded
    bSat   : BOOL;  // 本次调用发生饱和（上溢或下溢）[-] / a saturation happened this call
END_VAR
VAR
    lrUse : LREAL; // 闸后实际计算入参 [无量纲] / the gated value fed to the kernel [dimensionless]
END_VAR
VAR CONSTANT
    DL_EXP_HI : LREAL := 709.78;  // 上溢界 [无量纲]，EXP(709.78) 约 1.7968E308 可表（R63 反算）/ the overflow bound, its exponential is representable
    DL_EXP_LO : LREAL := -745.1;  // 下溢界 [无量纲]，低于该值 EXP 结果为 0 / the underflow bound, below it the exponential is zero
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_ExpSat := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
eErr   := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bValid := TRUE; // 有效标志预置真 / preset the valid flag true
bSat   := FALSE; // 饱和标志预置假 / preset the saturation flag false

// 段 2｜非有限拦截（双判据）：命中不调内建直接早退 / segment 2, the non finite interception
IF (lrIn <> lrIn) OR ((lrIn - lrIn) <> (lrIn - lrIn)) THEN // NaN 或无穷 / NaN or infinity
    eErr   := 16#0002_0001; // 信息级：输入非有限已归零 / informational, a non finite input zeroed
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0.0 / return the preset safe zero
END_IF

// 段 3｜饱和闸门：上溢饱和不出 Inf，下溢钳零 / segment 3, the saturation gate
IF lrIn > DL_EXP_HI THEN // 超上溢界 / beyond the overflow bound
    lrUse  := DL_EXP_HI; // 按上溢界执行（结果可表不出 Inf）/ run at the bound, the result representable
    eErr   := 16#0002_0004; // 信息级：上溢已饱和 / informational, overflow saturated
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 饱和结果非真实值 / the saturated result is not the true value
    bSat   := TRUE; // 置饱和标志 / raise the saturation flag
ELSIF lrIn < DL_EXP_LO THEN // 超下溢界 / beyond the underflow bound
    lrUse  := DL_EXP_LO; // 按下溢界执行 / run at the bound
    eErr   := 16#0002_0005; // 信息级：下溢已钳零 / informational, underflow clamped to zero
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 钳零结果非真实值 / the clamped result is not the true value
    bSat   := TRUE; // 置饱和标志 / raise the saturation flag
ELSE // 域内直通 / inside the domain
    lrUse := lrIn; // 直通 / passthrough
END_IF

// 段 4｜委托内建 EXP（禁重实现数学内核）/ segment 4, delegation to the built-in EXP
FC_DL_ExpSat := EXP(lrUse); // 委托内建内核 / delegate to the built-in kernel
IF FC_DL_ExpSat < 0.0 THEN // 负大下饱和钳 >=0（边界九，防御性兜底）/ the negative side clamp to zero or above
    FC_DL_ExpSat := 0.0; // 钳到零 / clamp to zero
END_IF

// 段 5｜结果非有限二次复核兜底（防御纵深，正常路径不可达）/ segment 5, the result recheck as defense in depth
IF (FC_DL_ExpSat <> FC_DL_ExpSat) OR ((FC_DL_ExpSat - FC_DL_ExpSat) <> (FC_DL_ExpSat - FC_DL_ExpSat)) THEN // 结果非有限 / a non finite result
    FC_DL_ExpSat := 0.0; // 兜底安全值 / the bottom-line safe value
    IF eErr = 16#0000_0000 THEN // 首事件优先置码 / the first event keeps the code
        eErr   := 16#0002_0001; // 信息级：结果非有限已归零 / informational, a non finite result zeroed
        bError := TRUE; // 置错误标志 / raise the error flag
        bValid := FALSE; // 输出不可用 / the output void
    END_IF
END_IF
END_FUNCTION
