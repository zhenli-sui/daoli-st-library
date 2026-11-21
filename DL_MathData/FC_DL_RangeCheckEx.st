(*
    FC_DL_RangeCheckEx —— 标量域检查纯函数（LREAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Compare
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托比较运算语义，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 标量域检查：返回 fIn 是否落在 [fLower, fUpper] 域内（返回值），
                并经 bAboveUpper 与 bBelowLower 双输出给出越上/下侧别；
                上下界按各自边界独立判定（fIn > fUpper 判越上、fIn < fLower 判越下），
                故上下限倒置（fLower > fUpper）不判故障：倒置且 fIn 落在倒置间隙时
                双越界标志同拍为 TRUE、返回 FALSE，行为完全可解释（设计取舍见下）；
                任一输入非有限（NaN 或 ±Inf）判为故障级 16#0001_03CC，
                三个判定输出全 FALSE 且 bValid=FALSE（NaN 与一切比较均 FALSE，
                若放行会使「域内」静默失真，一律拦截）；
                非有限判定口径（R15）：NaN 用自不等 f <> f，±Inf 用 (f − f) <> (f − f)。
    错误码    : 16#0001_03CC 任一输入非有限（NaN 或 ±Inf）——故障级，三输出全 FALSE
    设计取舍  : 上下限倒置不占码位（R90 反证句：倒置场景可由输出组合完整观测——
                bAboveUpper=TRUE 且 bBelowLower=TRUE 的组合在本件语义中仅倒置间隙可产生，
                域正常时两标志互斥，现有输出组合已唯一还原倒置事实，故不新占码位）。
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 1 · T0 快车道）
*)
FUNCTION FC_DL_RangeCheckEx : BOOL
VAR_INPUT
    fIn     : LREAL; // 被检标量 [无量纲] ｜ scalar value under check
    fLower  : LREAL; // 域下限 [无量纲]，大于上限时本件按独立边界判定 ｜ domain lower bound, judged per boundary when greater than upper
    fUpper  : LREAL; // 域上限 [无量纲]，小于下限时本件按独立边界判定 ｜ domain upper bound, judged per boundary when less than lower
END_VAR
VAR_OUTPUT
    bAboveUpper : BOOL; // 越上侧标志，fIn > fUpper 时为 TRUE ｜ above-upper flag, TRUE when fIn exceeds fUpper
    bBelowLower : BOOL; // 越下侧标志，fIn < fLower 时为 TRUE ｜ below-lower flag, TRUE when fIn falls under fLower
    eErr        : UDINT; // 错误码，0=正常，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_03XX=fault level
    bError      : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid      : BOOL;  // 判定结果是否有效可用 ｜ check result valid flag
END_VAR
VAR
    bBad : BOOL; // 三输入非有限判定结果（NaN 或 ±Inf）｜ non-finite detection result of the three inputs
END_VAR

// 段 1｜返回值与输出预置 ｜ segment 1, preset return value and outputs
FC_DL_RangeCheckEx := FALSE; // 故障缺省判不在域内 ｜ fault default judges out-of-domain
bAboveUpper := FALSE;        // 预置未越上 ｜ preset not above upper
bBelowLower := FALSE;        // 预置未越下 ｜ preset not below lower
eErr        := 0;            // 预置无错误 ｜ preset no error
bError      := FALSE;        // 预置无故障 ｜ preset no fault
bValid      := FALSE;        // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes

// 段 2｜三输入非有限防御闸（早退） ｜ segment 2, non-finite guard of the three inputs (early return)
bBad := (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn))
     OR (fLower <> fLower) OR ((fLower - fLower) <> (fLower - fLower))
     OR (fUpper <> fUpper) OR ((fUpper - fUpper) <> (fUpper - fUpper)); // 三输入非有限判定：NaN 自不等 + 差值自减判 ±Inf [无量纲] ｜ non-finite check: NaN by self-inequality, +/-Inf by self-subtraction
IF bBad THEN
    FC_DL_RangeCheckEx := FALSE; // 故障级判不在域内 ｜ fault level judges out-of-domain
    bAboveUpper := FALSE;        // 越上侧标志清零 ｜ clear the above-upper flag
    bBelowLower := FALSE;        // 越下侧标志清零 ｜ clear the below-lower flag
    eErr        := 16#0001_03CC; // 非有限输入故障码 ｜ non-finite input fault id
    bError      := TRUE;         // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid      := FALSE;        // 判定无效 ｜ check result invalid
    RETURN;                      // 早退 ｜ early return
END_IF

// 段 3｜双边界独立判定主体（末段） ｜ segment 3, independent per-boundary check body (final)
bAboveUpper := fIn > fUpper;  // 越上侧判定（与下限无关）｜ above-upper check (independent of the lower bound)
bBelowLower := fIn < fLower;  // 越下侧判定（与上限无关）｜ below-lower check (independent of the upper bound)
IF (NOT bAboveUpper) AND (NOT bBelowLower) THEN
    FC_DL_RangeCheckEx := TRUE;  // 双边界均未越，判在域内 ｜ neither boundary exceeded, judged in-domain
ELSE
    FC_DL_RangeCheckEx := FALSE; // 任一边界越出，判不在域内 ｜ either boundary exceeded, judged out-of-domain
END_IF
bError := FALSE; // 正常出口不置故障 ｜ normal exit raises no fault
bValid := TRUE;  // 判定输出有效可用 ｜ check output is valid
END_FUNCTION
