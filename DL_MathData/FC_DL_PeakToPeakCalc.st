(*
    FC_DL_PeakToPeakCalc —— 峰峰值计算（窗口 max−min + 非有限剔除 + 量程百分比）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Statistics
    前缀      : FC_DL_
    版本      : 1.0.0
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （纯比较逻辑，无内建数学内核依赖；未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FC_DL_SearchMinMax / FB_DL_WindowExtremaStat 分工——
                SearchMinMax 返回极值对本身，WindowExtremaStat 为驻留滑窗族；
                本件为无状态数组窗口峰峰值单出口并附量程百分比口径。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 对输入数组前 nCount 个样本求峰峰值（max−min）。窗长钳位
                ≥1（单样本峰峰值 0，边界十四）；非有限样本不参与并计数；
                fSpan <= 0 时百分比出口置 0 并置无效标志（防除零）。
    错误码    : 0000 正常 / 16#0003_0003 窗长已钳位 / 16#0003_0004 有效样本为零 / 16#0003_0006 量程组态非法
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 3 · 序号 14）
*)
FUNCTION FC_DL_PeakToPeakCalc : LREAL
VAR_IN_OUT
    afData : ARRAY[0..4095] OF LREAL; // 样本数组 [工程单位]，前 nCount 个有效 / the sample array, the first nCount entries valid
END_VAR
VAR_INPUT
    nCount : DINT; // 样本数 [个]，钳位 ≥1 / the sample count, clamped to one or above
    fSpan  : LREAL := 100.0; // 量程（用于百分比出口）[工程单位]，域 大于零 / the span for the percent outlet, above zero
END_VAR
VAR_OUTPUT
    eErr      : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError    : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid    : BOOL;  // 结果是否为真实值，钳位/剔除降级时为假 / the result is the true value, false when degraded
    fPctOfSpan: LREAL; // 峰峰值占量程百分比 [百分比] / the peak to peak over the span [percent]
    nNanCnt   : UDINT; // 剔除的非有限样本数 [个] / the excluded non finite sample count
    bPctValid : BOOL;  // 百分比出口有效性（fSpan 非法时为假）[-] / the percent outlet validity
END_VAR
VAR
    nI     : DINT;  // 循环计数 [个] / the loop counter
    nUsed  : DINT;  // 实际参与样本数 [个] / the used sample count
    lrMax  : LREAL; // 窗口最大值 [工程单位] / the window maximum
    lrMin  : LREAL; // 窗口最小值 [工程单位] / the window minimum
    lrX    : LREAL; // 当前样本 [工程单位] / the current sample
    bFirst : BOOL;  // 首个有效样本标记 [-] / the first valid sample flag
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_PeakToPeakCalc := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
fPctOfSpan := 0.0; // 百分比预置 0 / preset the percent zero
eErr   := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bValid := TRUE; // 有效标志预置真 / preset the valid flag true
bPctValid := TRUE; // 百分比有效性预置真 / preset the percent validity true
nNanCnt := 0; // 剔除计数预置零 / preset the excluded count zero
bFirst := TRUE; // 首样本标记预置真 / preset the first flag true
nUsed := 0; // 参与样本数预置零（防函数局部量残值）/ preset the used count zero

// 段 2｜窗长钳位 ≥1（边界十四）/ segment 2, the window clamp to one or above
IF nCount < 1 THEN // 低于下界 / below the floor
    nCount := 1; // 钳到 1 / clamp to one
    eErr   := 16#0003_0003; // 信息级：窗长已钳位 / informational, the window clamped
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 钳位口径非原始口径 / the clamped window is not the requested one
END_IF

// 段 3｜量程组态闸（防除零，边界十四）/ segment 3, the span config gate against division by zero
IF (fSpan <= 0.0) OR (fSpan <> fSpan) OR ((fSpan - fSpan) <> (fSpan - fSpan)) THEN // 量程非法或非有限 / an illegal or non finite span
    fPctValid := FALSE; // 百分比出口置无效 / the percent outlet void
    eErr      := 16#0003_0006; // 信息级：量程组态非法 / informational, an illegal span config
    bError    := TRUE; // 置错误标志 / raise the error flag
END_IF

// 段 4｜窗口极值扫描（非有限剔除）/ segment 4, the extrema scan with exclusion
FOR nI := 0 TO nCount - 1 DO // 有界循环（nCount 已钳 ≤4096）/ the bounded loop
    lrX := afData[nI]; // 取样本（索引已证在数组界内）/ take the sample
    IF (lrX = lrX) AND ((lrX - lrX) = (lrX - lrX)) THEN // 非有限双判据通过才参与 / only finite samples participate
        IF bFirst THEN // 首个有效样本直接设为极值 / the first valid sample seeds both extrema
            lrMax := lrX; // 最大值播种 / seed the maximum
            lrMin := lrX; // 最小值播种 / seed the minimum
            bFirst := FALSE; // 播种完成 / the seeding done
        ELSE // 非首样本比较更新 / the later samples compared
            IF lrX > lrMax THEN // 超最大 / above the maximum
                lrMax := lrX; // 更新最大 / update the maximum
            END_IF
            IF lrX < lrMin THEN // 低于最小 / below the minimum
                lrMin := lrX; // 更新最小 / update the minimum
            END_IF
        END_IF
        nUsed := nUsed + 1; // 参与计数推进 / advance the used count
    ELSE // 非有限样本剔除 / a non finite sample excluded
        nNanCnt := nNanCnt + 1; // 剔除计数推进 / advance the excluded count
    END_IF
END_FOR

// 段 5｜结果计算 / segment 5, the result
IF nUsed > 0 THEN // 有有效样本 / with valid samples
    FC_DL_PeakToPeakCalc := lrMax - lrMin; // 峰峰值（单样本恰为 0，边界十四）/ the peak to peak, zero for a single sample
    IF bPctValid THEN // 量程合法才算百分比 / the percent only with a legal span
        fPctOfSpan := FC_DL_PeakToPeakCalc / fSpan * 100.0; // 百分比（除子已证大于零）/ the percent with a proven divisor
    END_IF
ELSE // 全部剔除 / all excluded
    eErr   := 16#0003_0004; // 错误级：有效样本为零 / error grade, no valid sample
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
END_IF
END_FUNCTION
