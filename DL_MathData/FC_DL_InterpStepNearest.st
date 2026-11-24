(*
    FC_DL_InterpStepNearest —— 查表最近邻（阶梯保持）插值（越界钳端点 + 并列取左邻）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Interpolation
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （纯查表比较逻辑，无内建插值内核依赖；未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_HermiteInterp / FC_DL_CubicSplineInterp /
                FC_DL_LagrangeInterp / FC_DL_InterpolateTable2D 分工——那四件
                为连续光滑或线性口径，本件为离散阶梯保持口径（最近邻，取整
                不平滑），越界端点钳位不外插。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 在按 x 升序排布的 n 点表中取最近邻 y（阶梯保持）。n 点 ≥2
                否则拒算；x 越界钳端点不外插；相邻 x 相等（表非单调）取先见
                点并置告警；距离并列取左邻（严格 < 判据，正中不摇摆）；
                非有限表项跳过并计数。
    错误码    : 0000 正常 / 16#0003_0007 点数不足拒算 / 16#0003_0008 表非单调告警 / 16#0003_0009 已钳端点
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 3 · 序号 15）
*)
FUNCTION FC_DL_InterpStepNearest : LREAL
VAR_IN_OUT
    afX : ARRAY[0..63] OF LREAL; // 表自变量数组 [工程单位]，升序排布 / the abscissa array, ascending
    afY : ARRAY[0..63] OF LREAL; // 表因变量数组 [工程单位] / the ordinate array
END_VAR
VAR_INPUT
    nCount  : DINT; // 表点数 [个]，域 2..64 / the point count, two through sixty four
    fXQuery : LREAL; // 查询自变量 [工程单位] / the query abscissa [engineering unit]
END_VAR
VAR_OUTPUT
    eErr    : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError  : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid  : BOOL;  // 结果是否为真实值，钳位/告警降级时为假 / the result is the true value, false when degraded
    bClamp  : BOOL;  // 发生端点钳位（不外插）[-] / an endpoint clamp happened, no extrapolation
    nSkipCnt: UDINT; // 跳过的非有限表项数 [个] / the skipped non finite table entries
END_VAR
VAR
    nI     : DINT;  // 循环计数 [个] / the loop counter
    nBest  : DINT;  // 最近点索引 [个] / the nearest index
    lrD    : LREAL; // 当前距离 [工程单位] / the current distance
    lrDbest: LREAL; // 当前最近距离 [工程单位] / the best distance so far
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_InterpStepNearest := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
eErr   := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bValid := TRUE; // 有效标志预置真 / preset the valid flag true
bClamp := FALSE; // 钳位标志预置假 / preset the clamp flag false
nSkipCnt := 0; // 跳过计数预置零 / preset the skip count zero

// 段 2｜点数域闸：n < 2 拒算（边界十五）/ segment 2, the count gate, below two rejects
IF nCount < 2 THEN // 点数不足 / insufficient points
    eErr   := 16#0003_0007; // 错误级：点数不足拒算 / error grade, insufficient points rejected
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
    RETURN; // 返回预置安全值 0.0 / return the preset safe zero
ELSIF nCount > 64 THEN // 超数组容量 / beyond the array capacity
    nCount := 64; // 钳到容量上限 / clamp to the capacity
    eErr   := 16#0003_0003; // 信息级：点数已钳位 / informational, the count clamped
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 钳位口径非原始口径 / the clamped window is not the requested one
END_IF

// 段 3｜越界钳端点不外插（边界十五）/ segment 3, the endpoint clamp, no extrapolation
IF (fXQuery = fXQuery) AND ((fXQuery - fXQuery) = (fXQuery - fXQuery)) THEN // 查询值有限才判越界 / the clamp verdict only on a finite query
    IF fXQuery <= afX[0] THEN // 低于表首 / below the table head
        FC_DL_InterpStepNearest := afY[0]; // 钳端点返回 / clamp to the endpoint
        IF fXQuery < afX[0] THEN // 严格越界才置码 / the code only on a strict violation
            eErr   := 16#0003_0009; // 信息级：已钳下端点 / informational, clamped to the lower endpoint
            bError := TRUE; // 置错误标志 / raise the error flag
            bValid := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
            bClamp := TRUE; // 置钳位标志 / raise the clamp flag
        END_IF
        RETURN; // 早退 / early return
    ELSIF fXQuery >= afX[nCount - 1] THEN // 高于表尾 / beyond the table tail
        FC_DL_InterpStepNearest := afY[nCount - 1]; // 钳端点返回 / clamp to the endpoint
        IF fXQuery > afX[nCount - 1] THEN // 严格越界才置码 / the code only on a strict violation
            eErr   := 16#0003_0009; // 信息级：已钳上端点 / informational, clamped to the upper endpoint
            bError := TRUE; // 置错误标志 / raise the error flag
            bValid := FALSE; // 钳位结果非真实值 / the clamped result is not the true value
            bClamp := TRUE; // 置钳位标志 / raise the clamp flag
        END_IF
        RETURN; // 早退 / early return
    END_IF
END_IF

// 段 4｜最近邻扫描：距离并列取左邻（严格 < 判据）/ segment 4, the nearest scan, ties take the left neighbor
nBest := 0; // 最近索引预置 0 / preset the nearest index
lrDbest := 1.7976931348623157E308; // 最近距离预置 LREAL 上界 / preset the best distance to the representable bound
FOR nI := 0 TO nCount - 1 DO // 有界循环 / the bounded loop
    IF (afX[nI] = afX[nI]) AND ((afX[nI] - afX[nI]) = (afX[nI] - afX[nI])) AND (afY[nI] = afY[nI]) AND ((afY[nI] - afY[nI]) = (afY[nI] - afY[nI])) THEN // 表项有限才参与 / only finite entries participate
        lrD := ABS(fXQuery - afX[nI]); // 当前距离 / the current distance
        IF lrD < lrDbest THEN // 严格小于才替换（并列保持左邻，正中不摇摆）/ strictly smaller replaces, ties hold the left
            lrDbest := lrD; // 更新最近距离 / update the best distance
            nBest := nI; // 更新最近索引 / update the nearest index
        END_IF
    ELSE // 非有限表项跳过 / a non finite entry skipped
        nSkipCnt := nSkipCnt + 1; // 跳过计数推进 / advance the skip count
    END_IF
END_FOR

// 段 5｜非单调告警与结果出口 / segment 5, the non monotonic warning and the outlet
FOR nI := 1 TO nCount - 1 DO // 相邻对扫查 / the adjacent pair scan
    IF (afX[nI] = afX[nI]) AND ((afX[nI] - afX[nI]) = (afX[nI] - afX[nI])) THEN // 有限项才比较 / finite entries only
        IF afX[nI] <= afX[nI - 1] THEN // 非递增即非单调 / a non increasing pair is non monotonic
            eErr   := 16#0003_0008; // 告警级：表非单调（先见点已按左邻规则保持）/ warning, a non monotonic table, the first seen held by the left rule
            bError := TRUE; // 置错误标志 / raise the error flag
            EXIT; // 一次告警即出 / one warning is enough
        END_IF
    END_IF
END_FOR
FC_DL_InterpStepNearest := afY[nBest]; // 最近邻 y 出口（阶梯保持）/ the nearest ordinate, the step hold
END_FUNCTION
