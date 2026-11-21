(*
    FC_DL_RmsCalc —— 窗口均方根（增量式平方累加防溢出 + 窗长钳位 + 非有限剔除）
    ------------------------------------------------------------------
    分类      : DL_MathData / Math-Statistics
    前缀      : FC_DL_
    版本      : 1.0.1
    来源标签  : iec-std-wrapper（T0）
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （无状态纯函数，SQRT 为 IEC 标准内建；未复制任何闭源厂商源码）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    分工声明  : 与存量 FB_DL_SignalStatistics / FC_DL_StdDevOnline 分工——
                SignalStatistics 为驻留统计族（均值/方差多出口），StdDevOnline
                为在线流式标准差；本件为无状态数组窗口 RMS 单出口口径，
                与批 2 Safe 族惯性一致（无依赖，仅排期顺延）。
    作者      : 道莅代码库 · PLC 编程专家（R57）
    ------------------------------------------------------------------
    功能说明  : 对输入数组前 nCount 个样本求均方根。增量式累加 sum += x²/n
                防大数平方溢出（先除后加，边界十二）；窗长钳位 1..4096；
                非有限样本剔除并计数出口；有效样本数为零判错误返回 0。
    错误码    : 0000 正常 / 16#0003_0003 窗长已钳位 / 16#0003_0004 有效样本为零
                / 16#0003_0005 非有限样本已剔除（信息级，bValid 保持 TRUE）
    bValid 偏离段: 部分剔除时 bValid 保持 TRUE——有效样本统计量仍可用（与
                0303 钳位件 bValid=FALSE 的口径差异在此声明，v1.0.1）。
    修订记录  : 2026-11-21 v1.0.0 首次入库（R57 批 3 · 序号 12）
                2026-11-21 v1.0.1 R58 返修：部分剔除（nUsed>0 且 nNanCnt>0）
                置信息级 0003_0005（首事件闸），调用方可感知口径已收窄；
                全剔除路径 0304 优先级在先不动。
*)
FUNCTION FC_DL_RmsCalc : LREAL
VAR_IN_OUT
    afData : ARRAY[0..4095] OF LREAL; // 样本数组 [工程单位]，前 nCount 个有效 / the sample array, the first nCount entries valid
END_VAR
VAR_INPUT
    nCount : DINT; // 样本数 [个]，钳位 1..4096 / the sample count, clamped to one through four thousand ninety six
END_VAR
VAR_OUTPUT
    eErr     : UDINT; // 错误码，0 = 正常 / error code, zero is ok
    bError   : BOOL;  // 出错标志，eErr 非 0 时为真 / error flag, true when eErr is nonzero
    bValid   : BOOL;  // 结果是否为真实值，钳位/剔除降级时可能为假 / the result is the true value, false when degraded
    nNanCnt  : UDINT; // 剔除的非有限样本数 [个] / the excluded non finite sample count
END_VAR
VAR
    nI     : DINT;  // 循环计数 [个] / the loop counter
    nUsed  : DINT;  // 实际参与样本数 [个] / the actually used sample count
    lrSum  : LREAL; // 增量式平方和 [工程单位平方] / the incremental sum of squares
    lrX    : LREAL; // 当前样本 [工程单位] / the current sample [engineering unit]
    bClamp : BOOL;  // 窗长钳位发生 [-] / a window clamp happened
END_VAR
VAR CONSTANT
    DL_RMS_NMAX : DINT := 4096; // 窗长上限 [个]，与数组容量一致 / the window bound, aligned with the array capacity
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_RmsCalc := 0.0; // 返回值预置安全值 0.0 / preset the return to the safe zero
eErr   := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
bValid := TRUE; // 有效标志预置真 / preset the valid flag true
nNanCnt := 0; // 剔除计数预置零 / preset the excluded count zero
bClamp := FALSE; // 钳位标志预置假 / preset the clamp flag false

// 段 2｜窗长钳位 1..4096（边界十二；上界与数组容量一致，索引结构性安全）/ segment 2, the window clamp
IF nCount < 1 THEN // 低于下界 / below the floor
    nCount := 1; // 钳到 1 / clamp to one
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
ELSIF nCount > DL_RMS_NMAX THEN // 高于上界 / above the bound
    nCount := DL_RMS_NMAX; // 钳到上限 / clamp to the bound
    bClamp := TRUE; // 置钳位标记 / raise the clamp flag
END_IF
IF bClamp THEN // 钳位发生时置信息级 / raise the informational code on a clamp
    eErr   := 16#0003_0003; // 信息级：窗长已钳位 / informational, the window clamped
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 钳位口径非原始窗长口径 / the clamped window is not the requested one
END_IF

// 段 3｜增量式平方累加：sum += x²/n（先除后加防大数溢出，边界十二）/ segment 3, the incremental accumulation
lrSum := 0.0; // 平方和清零 / clear the sum
nUsed := 0; // 参与样本数清零 / clear the used count
FOR nI := 0 TO nCount - 1 DO // 有界循环（nCount 已钳 ≤4096）/ the bounded loop
    lrX := afData[nI]; // 取样本（索引已证在数组界内）/ take the sample, the index proven inside the bounds
    IF (lrX = lrX) AND ((lrX - lrX) = (lrX - lrX)) THEN // 非有限双判据通过才参与 / only finite samples participate
        lrSum := lrSum + lrX * lrX / INT_TO_LREAL(nCount); // 先除窗长再加，防 x² 大数溢出 / divide first then add against overflow
        nUsed := nUsed + 1; // 参与计数推进 / advance the used count
    ELSE // 非有限样本剔除 / a non finite sample excluded
        nNanCnt := nNanCnt + 1; // 剔除计数推进 / advance the excluded count
    END_IF
END_FOR

// 段 3b｜部分剔除信息级置码（v1.0.1：首事件闸，0303 先发则不再覆盖）/ segment 3b, the partial exclusion informational code
IF (nNanCnt > 0) AND (nUsed > 0) AND (eErr = 16#0000_0000) THEN // 部分剔除且无先发事件 / a partial exclusion with no earlier event
    eErr   := 16#0003_0005; // 信息级：非有限样本已剔除，口径为有效样本 RMS / informational, non finite samples excluded, the effective sample RMS
    bError := TRUE; // 置错误标志（信息级随事件置位惯例）/ raise the error flag
END_IF // bValid 保持 TRUE：有效样本统计量仍可用（头注释偏离段声明）/ bValid stays true, the effective sample statistic remains usable

// 段 4｜结果计算与兜底 / segment 4, the result and the guard
IF nUsed > 0 THEN // 有有效样本 / with valid samples
    FC_DL_RmsCalc := SQRT(lrSum * INT_TO_LREAL(nCount) / INT_TO_LREAL(nUsed)); // 复原除子后开方（除子已证大于零）/ restore the divisor then the square root
ELSE // 全部剔除 / all excluded
    eErr   := 16#0003_0004; // 错误级：有效样本为零 / error grade, no valid sample
    bError := TRUE; // 置错误标志 / raise the error flag
    bValid := FALSE; // 输出不可用 / the output void
END_IF
IF (FC_DL_RmsCalc <> FC_DL_RmsCalc) OR ((FC_DL_RmsCalc - FC_DL_RmsCalc) <> (FC_DL_RmsCalc - FC_DL_RmsCalc)) THEN // 结果非有限兜底 / the non finite result guard
    FC_DL_RmsCalc := 0.0; // 兜底安全值 / the bottom-line safe value
    bValid := FALSE; // 输出不可用 / the output void
END_IF
END_FUNCTION
