(*
    FC_DL_TimeRatioCalc —— 两个 TIME 的无量纲比值
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 公开算术定义的道莅防御性实现（比值 = 分子时长 / 分母时长）；
                库内 FC_DL_TimeDivChk 只出整数毫秒商（小数全丢），本件用 LREAL 承载
                以保留 15 位有效数字；饱和限、取模长口径、错误分级、双语文档 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 计算节拍分析 / 稼动率 / 循环时间偏差 / 加速比所需的比值，可选 ×100 出百分比。
                核心防御：① 分母毫秒值为 0 是除零唯一出口（故障级 0321 早退，绝不进入除法）；
                ② 分母模长 < 1 ms 视为无意义分母，比值直接饱和到 fRatioSpan（1 ms 以下
                   的分母在任何现场都无意义，且会让比值爆炸）；
                ③ 输入为负时按模长参与运算（TIME 的平台符号语义不一致，方向差异
                   由本件统一吃掉），并置信息码 0402；
                ④ 比值超 fRatioSpan 双侧钳位，禁 NaN / ±INF 穿透；
                ⑤ 同一拍同时命中两条信息级时以 0403（饱和）为准，码位单值不可并列。
                职责边界：本件只出比值，不做时间加减、不做时基换算。
    错误码    : 16#0001_0402 分母模长 < 1 ms 或输入为负，已按模长运算/饱和——信息级，正常防御
                16#0001_0403 比值超 fRatioSpan 已钳位（bSaturated = TRUE）——信息级，正常防御
                16#0001_0321 分母为 0（除零）——故障级，返回 0.0 且 bValid = FALSE
                16#0001_0322 结果非有限（NaN / ±INF）或比值上限参数非法——故障级，返回 0.0
                16#0001_0323 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0402 用 / 16#0001_0403 用 ｜ 16#0001_0321 用 / 16#0001_0322 用 / 16#0001_0323 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测；TIME 实参由调用方按自身时基给出，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION FC_DL_TimeRatioCalc : LREAL
VAR_INPUT
    tNumerator      : TIME := T#0S;           // 分子时长 [ms]，域 -24 h~+24 h / numerator duration [ms], domain -24 h~+24 h
    tDenominator    : TIME := T#1S;           // 分母时长 [ms]，域 -24 h~+24 h，模长须 ≥ 1 ms / denominator duration [ms], domain -24 h~+24 h, magnitude >= 1 ms
    bAsPercent      : BOOL := FALSE;          // TRUE = 结果 ×100 输出百分比 [%] / TRUE multiplies the result by 100 to percent [%]
    fRatioSpan      : LREAL := 1.0E6;         // 比值饱和上限（作用在返回量上）[无量纲]，域 1.0~1.0E12 / ratio saturation span applied to the returned value [dimensionless], 1.0~1.0E12
END_VAR
VAR_OUTPUT
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 返回值是否可用 / return value valid flag
    fRatioAbs       : LREAL;                  // 比值绝对值（HMI 只看量级用）[无量纲] / absolute ratio for HMI magnitude view [dimensionless]
    bSaturated      : BOOL;                   // 比值已饱和到 fRatioSpan / ratio saturated to fRatioSpan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS        : REAL := 1.0E-6;     // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_TR_MIN_DEN_MS    : LREAL := 1.0;       // 分母模长下限 [ms] / denominator magnitude lower bound [ms]
    DL_TR_PERCENT       : LREAL := 100.0;     // 百分比放大因子 [无量纲] / percent scale factor [dimensionless]
    DL_TR_SPAN_MIN      : LREAL := 1.0;       // 比值上限最小值 [无量纲] / minimum ratio span [dimensionless]
    DL_TR_SPAN_MAX      : LREAL := 1.0E12;    // 比值上限最大值 [无量纲] / maximum ratio span [dimensionless]
    DL_TR_INF_GUARD     : LREAL := 1.0E300;   // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_TR_ZERO          : LREAL := 0.0;       // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR
VAR
    fNumAbs         : LREAL;                  // 分子模长 [ms] / numerator magnitude [ms]
    fDenAbs         : LREAL;                  // 分母模长 [ms] / denominator magnitude [ms]
    fSpanEff        : LREAL;                  // 生效比值上限，钳位后使用 [无量纲] / effective ratio span after clamping [dimensionless]
    fRatio          : LREAL;                  // 计算中的比值中间量 [无量纲] / ratio intermediate value [dimensionless]
    nDenMs          : DINT;                   // 分母毫秒整数形态，除零判定用 [ms] / denominator in integer milliseconds, used for the divide-by-zero gate [ms]
    bNegativeIn     : BOOL;                   // 输入存在负值时基的标志 / flag for negative time base inputs
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeRatioCalc := DL_TR_ZERO;            // 故障缺省返回 0.0 / fault default returns zero
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
fRatioAbs := DL_TR_ZERO;                      // 量级输出先清零 / clear the magnitude output
bSaturated := FALSE;                          // 预置未饱和 / preset not saturated

// 段 2｜比值上限参数闸（非法上限等于比值域不存在，落入结果不可表示）/ segment 2, ratio span gate
fSpanEff := fRatioSpan;                       // 取入参副本，不改调用方数据 / copy the input, never modify caller data
IF (fSpanEff <> fSpanEff) OR (fSpanEff > DL_TR_INF_GUARD) OR (fSpanEff < -DL_TR_INF_GUARD) THEN
    eErr := 16#0001_0322;                     // 上限非有限即结果不可表示 / a non-finite span makes the result unrepresentable
    bError := TRUE;                           // 置故障标志 / raise the error flag
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF
IF fSpanEff < DL_TR_SPAN_MIN THEN
    fSpanEff := DL_TR_SPAN_MIN;               // 上限过小钳到 1.0，避免比值域退化 / clamp a too small span to 1.0
    eErr := 16#0001_0403;                     // 信息级：上限已钳位 / info level, the span has been clamped
ELSIF fSpanEff > DL_TR_SPAN_MAX THEN
    fSpanEff := DL_TR_SPAN_MAX;               // 上限过大钳到 1.0E12 / clamp an oversized span to 1.0E12
    eErr := 16#0001_0403;                     // 信息级：上限已钳位 / info level, the span has been clamped
END_IF

// 段 3｜除零唯一出口（先取整数毫秒判定，再进入浮点除法）/ segment 3, the only divide-by-zero exit
nDenMs := TIME_TO_DINT(tDenominator);         // 显式取分母毫秒整数，禁隐式换算 / take denominator milliseconds explicitly, no implicit cast
IF nDenMs = 0 THEN
    eErr := 16#0001_0321;                     // 除零故障码 / divide-by-zero fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 结果不可用 / result not usable
    RETURN;                                   // 故障级提前返回，绝不进入除法 / early return, the division is never executed
END_IF

// 段 4｜按模长参与运算（TIME 符号语义跨平台不一致，方向差异在此统一吃掉）/ segment 4, magnitudes only
fNumAbs := ABS(TIME_TO_LREAL(tNumerator));    // 分子模长 [ms] / numerator magnitude [ms]
fDenAbs := ABS(TIME_TO_LREAL(tDenominator));  // 分母模长 [ms] / denominator magnitude [ms]
bNegativeIn := (TIME_TO_DINT(tNumerator) < 0) OR (nDenMs < 0); // 负时基判定 / negative time base detection
IF bNegativeIn THEN
    eErr := 16#0001_0402;                     // 信息级：输入为负已按模长运算 / info level, negative inputs are handled by magnitude
END_IF

// 段 5｜分母过小闸：不足 1 ms 直接饱和，不做除法 / segment 5, tiny-denominator gate
IF fDenAbs < DL_TR_MIN_DEN_MS THEN
    fRatio := fSpanEff;                       // 过小分母直接给饱和值，规避比值爆炸 / jump straight to the span, avoid an exploding ratio
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
    eErr := 16#0001_0402;                     // 信息级：分母过小已饱和 / info level, tiny denominator saturated
ELSE
    fRatio := fNumAbs / fDenAbs;              // 分母模长 ≥ 1 ms，除法安全 / the denominator is at least 1 ms, the division is safe
    IF bAsPercent THEN
        fRatio := fRatio * DL_TR_PERCENT;     // 可选百分比放大 [%] / optional percent scaling [%]
    END_IF
END_IF

// 段 6｜结果非有限复检（NaN 穿透拦截）/ segment 6, non-finite recheck
IF (fRatio <> fRatio) OR (fRatio > DL_TR_INF_GUARD) OR (fRatio < -DL_TR_INF_GUARD) THEN
    eErr := 16#0001_0322;                     // 结果非有限故障码 / non-finite result fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 结果不可用 / result not usable
    FC_DL_TimeRatioCalc := DL_TR_ZERO;        // 明确返回 0.0 / return zero explicitly
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 7｜饱和钳位（单侧上限，比值恒非负）/ segment 7, saturation clamp
IF fRatio > fSpanEff THEN
    fRatio := fSpanEff;                       // 钳到生效上限 / clamp to the effective span
    bSaturated := TRUE;                       // 标记饱和 / flag the saturation
    eErr := 16#0001_0403;                     // 信息级：超上限已钳位，与 0402 同拍时以本码为准 / info level, clamped; this id wins over 0402 in the same cycle
END_IF

// 段 8｜发布结果 / segment 8, publish the result
FC_DL_TimeRatioCalc := fRatio;                // 输出比值（含百分比放大） [无量纲] / publish the ratio incl. percent scaling [dimensionless]
fRatioAbs := fRatio;                          // 比值恒按模长运算，量级即本身 / the ratio is magnitude based, so the magnitude equals the value
bValid := TRUE;                               // 通过全部闸门，结果可用 / all gates passed, the result is usable
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION
