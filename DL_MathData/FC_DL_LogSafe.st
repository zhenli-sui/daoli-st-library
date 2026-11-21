(*
    FC_DL_LogSafe —— 自然对数 Safe 族防御包装（零/负拦截 + 下界钳 1E-300 + 委托内建）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Log
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建 LN，外围钳位/错误码/双语文档；
                  未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_LnEx / FC_DL_LogBaseEx 分工——LnEx 为任意底对数
                码位族，LogBaseEx 为换底包装；本件只做自然对数的 Safe 族口径
                （x<=0 判错误返回安全下界不返回 NaN + 下界钳 1E-300）。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 求输入的自然对数。四段式防御（R45）：NaN 双判据拦截归零早退；
                x<=0 判错误，返回安全下界 LN(1E-300) 不返回 NaN；0<x<1E-300
                钳到下界 1E-300 并置 bClamped；域内委托内建 LN；结果复检兜底。
                1E-300 量级依据：LN(1E-300) ≈ -690.7755278982 可表，
                LN(0) 与负数对数在 IEC 平台行为未定义，必须上游拦截。
    错误码    : 0000 正常 / 16#0002_0001 入参非有限已归零 / 16#0002_0003 x<=0 已按安全下界返回 / 16#0002_0002 下界钳位发生
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 2 · 序号 8）
*)
FUNCTION FC_DL_LogSafe : LREAL
VAR_INPUT
    lrIn : LREAL; // 输入实数 [无量纲]，定义域 大于零 / input real value [dimensionless], domain above zero
END_VAR
VAR_OUTPUT
    eErr     : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError   : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid   : BOOL;  // 结果是否为真实值，拦截/钳位降级时为假 / the result is the true value, false when degraded
    bClamped : BOOL;  // 本次调用发生下界钳位 [-] / a floor clamp happened this call
END_VAR
VAR
    lrUse : LREAL; // 钳位后的实际计算入参 [无量纲] / the clamped value fed to the kernel [dimensionless]
END_VAR
VAR CONSTANT
    DL_LOG_FLOOR : LREAL := 1E-300; // 下界钳位值 [无量纲]，LN(1E-300) 约 -690.78 可表 / the floor clamp, its log is representable
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_LogSafe := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
eErr     := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError   := FALSE; // 错误标志预置假 / preset the error flag false
bValid   := TRUE; // 有效标志预置真 / preset the valid flag true
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false

// 段 2｜非有限拦截（双判据）：命中不调内建直接早退 / segment 2, the non finite interception
IF (lrIn <> lrIn) OR ((lrIn - lrIn) <> (lrIn - lrIn)) THEN // NaN 或无穷 / NaN or infinity
    eErr   := 16#0002_0001; // 信息级：输入非有限已归零 / informational, a non finite input zeroed
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0.0 / return the preset safe zero
END_IF

// 段 3｜定义域闸门：x<=0 错误返回安全下界不返回 NaN；0<x<下界钳到下界 / segment 3, the domain gate
IF lrIn <= 0.0 THEN // 零或负 / zero or negative
    lrUse    := DL_LOG_FLOOR; // 按下界执行（返回 LN(1E-300) 而非 NaN）/ run at the floor, LN returned instead of NaN
    eErr     := 16#0002_0003; // 错误级：零负入参按安全下界返回 / error grade, a nonpositive input returned at the safe floor
    bError   := TRUE; // 置错误标志 / raise the error flag
    bValid   := FALSE; // 输出不可用（仅降级参考）/ the output void, degraded reference only
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF lrIn < DL_LOG_FLOOR THEN // 正值但低于下界 / positive but below the floor
    lrUse    := DL_LOG_FLOOR; // 钳到下界 / clamp to the floor
    eErr     := 16#0002_0002; // 信息级：下界钳位发生 / informational, a floor clamp happened
    bError   := TRUE; // 置错误标志 / raise the error flag
    bValid   := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSE // 域内直通 / inside the domain
    lrUse := lrIn; // 直通 / passthrough
END_IF

// 段 4｜委托内建 LN（禁重实现数学内核）/ segment 4, delegation to the built-in LN
FC_DL_LogSafe := LN(lrUse); // 委托内建内核，除域已证为正 / delegate to the built-in kernel, the argument proven positive

// 段 5｜结果复检兜底（防御纵深，正常路径不可达）/ segment 5, the result recheck as defense in depth
IF (FC_DL_LogSafe <> FC_DL_LogSafe) OR ((FC_DL_LogSafe - FC_DL_LogSafe) <> (FC_DL_LogSafe - FC_DL_LogSafe)) THEN // 结果非有限 / a non finite result
    FC_DL_LogSafe := 0.0; // 兜底安全值 / the bottom-line safe value
    IF eErr = 16#0000_0000 THEN // 首事件优先置码 / the first event keeps the code
        eErr   := 16#0002_0001; // 信息级：结果非有限已归零 / informational, a non finite result zeroed
        bError := TRUE; // 置错误标志 / raise the error flag
        bValid := FALSE; // 输出不可用 / the output void
    END_IF
END_IF
END_FUNCTION
