(*
    组件名称 : FC_DL_ArraySumLreal
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 静态数组一次性求和与均值，带非有限样本剔除与有效样本计数出口。
              取舍 ①：非有限样本剔除而不是让它们污染和 —— 一个 NaN 进和，整条链条全变 NaN，
              而均值 NaN 在 HMI 上显示为空白或 0，现场会当成「测量值为零」，这是最危险的静默错误；
              剔除 + nValidCount + 信息码，三点合起来让「有几个样本是坏的」变成可观测量。
              取舍 ②：均值独立判零分母 —— nValidCount = 0 时不算均值，直接判故障；
              绝不输出 0 冒充「均值为零」。
              取舍 ③：元素数超上限按上限钳位而非拒算 —— 静态表越界声明是配置问题，
              能算多少算多少并发信息码告警，比整表拒算更有用（配方系数、标定表都属这类）。
              取舍 ④：与 FB_DL_SignalStatistics 的边界 —— 那件是流式窗口（跨周期状态），
              本件是静态表一次性求值，纯函数、无内部状态、同入参同结果，可直接放进表达式或 CASE 分支里用。
    开源溯源 : 原创实现（T0-4 变体线，统计族「静态表求值」缺位）。无外部源码参考，码位与分级 100% 自有。；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
    本文件内含 : FUNCTION FC_DL_ArraySumLreal（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 元素数闸 + 非有限剔除 + 均值判零分母 + 累加溢出复检
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 数组上限、有限域、容差全常量化
    错误码   : 16#0001_044C [信息级] 部分非有限样本已剔除，和与均值仅基于有效样本，bValid = TRUE
               16#0001_044D [信息级] 元素数超上限已按上限钳位，bValid = TRUE
               16#0001_0390 [故障级] 元素数为负，返回 0，bValid = FALSE
               16#0001_0391 [故障级] 无有效样本（全部非有限），和与均值均返回 0，bValid = FALSE
               16#0001_0392 [故障级] 累加溢出（中间量非有限），返回 0，bValid = FALSE
    码位总账 : 16#0001_044C 用 / 16#0001_044D 用 ｜ 16#0001_0390 用 / 16#0001_0391 用 / 16#0001_0392 用
    遗留假设 : ① 非有限判据用「自比较为假判 NaN + 幅值越界判 INF」，为 IEEE 754 语义推导，未在 InoProShop 实测。
              ② 均值的除法在 nValidCount > 0 时进行，除数为 INT_TO_LREAL(≥1)，除零结构性不可能。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 3 入库
*)
FUNCTION FC_DL_ArraySumLreal : LREAL
VAR_INPUT
    nCount          : INT;    // 有效元素数，0~DL_ARRAY_MAX；超上限按上限钳位，负数判故障 [个] / number of valid elements, clamped above the bound and rejected below zero [count]
END_VAR
VAR_IN_OUT
    afData          : ARRAY[0..DL_ARRAY_MAX] OF LREAL;   // 定长数组，下标 ≥ nCount 的元素不参与 [工程单位] / fixed array, entries at or above nCount are ignored [engineering unit]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 和与均值是否可用 / sum and mean usable flag
    fMean           : LREAL;  // 均值 = 和 / 有效样本数，无有效样本时为 0 [工程单位] / mean of the valid samples, zero when none is valid [engineering unit]
    nValidCount     : INT;    // 剔除非有限样本后的有效样本数 [个] / number of valid samples after the non-finite ones were dropped [count]
END_VAR
VAR
    nEff            : INT;    // 实际遍历元素数（钳位后）[个] / effective element count after clamping [count]
    nIdx            : INT;    // 数组游标 [个] / array cursor [count]
    nDropped        : INT;    // 被剔除的非有限样本数 [个] / number of dropped non-finite samples [count]
    fSum            : LREAL;  // 累加和 [工程单位] / running sum [engineering unit]
    fSample         : LREAL;  // 当前样本值 [工程单位] / current sample [engineering unit]
    bSampleFin      : BOOL;   // 当前样本是否有限 / whether the current sample is finite
END_VAR
VAR CONSTANT
    DL_ARRAY_MAX        : INT := 255;                          // 数组下标上限 [个] / array upper index [count]
    DL_ARRAY_NONE       : INT := 0;                            // 零元素哨兵，均值判零分母用 [个] / zero element sentinel guarding the mean division [count]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;     // LREAL 最大有限值 [无量纲] / largest finite LREAL [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                        // 零哨兵 [工程单位] / zero sentinel [engineering unit]
    DL_ERR_NONE         : UDINT := 16#0000_0000;               // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_ArraySumLreal := DL_LREAL_ZERO;   // 故障缺省返回 0 / fault default returns zero
eErr         := DL_ERR_NONE;            // 预置无错误 / preset no error
bError       := FALSE;                  // 预置无故障 / preset no fault
bValid       := FALSE;                  // 预置结果不可用 / preset unusable
fMean        := DL_LREAL_ZERO;          // 预置均值 0 / preset the mean to zero
nValidCount  := 0;                      // 预置有效样本 0 / preset the valid count to zero
nDropped     := 0;                      // 预置剔除数 0 / preset the dropped count to zero
fSum         := DL_LREAL_ZERO;          // 累加器清零 / clear the accumulator
nEff         := nCount;                 // 先按请求数占位 / start from the requested count

// 段 2｜元素数闸：负值判故障，超上限钳位并告警 / segment 2, count gate, reject negatives and clamp above the bound
IF nCount < DL_ARRAY_NONE THEN
    eErr   := 16#0001_0390;             // 元素数为负（故障级）/ negative element count, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF
IF nCount > DL_ARRAY_MAX THEN
    nEff := DL_ARRAY_MAX;               // 钳到上限，能算多少算多少 / clamp to the bound and evaluate what is available
    eErr := 16#0001_044D;               // 元素数超上限已钳位（信息级，不置 bError）/ count clamped, info level
END_IF

// 段 3｜单遍求和：非有限样本剔除并计数，不污染和 / segment 3, single pass sum with non-finite samples dropped
IF nEff > DL_ARRAY_NONE THEN
    FOR nIdx := 0 TO nEff - 1 DO
        fSample    := afData[nIdx];                                                     // 取当前样本 / fetch the sample
        bSampleFin := (fSample = fSample) AND (ABS(fSample) <= DL_LREAL_MAX_FINITE);     // 自比较判 NaN，幅值判 INF / self compare for NaN, magnitude for INF
        IF bSampleFin THEN
            fSum := fSum + fSample;     // 只累加有效样本 / accumulate only valid samples
        ELSE
            nDropped := nDropped + 1;   // 剔除并计数 / drop and count
        END_IF
    END_FOR
END_IF
nValidCount := nEff - nDropped;         // 有效样本数 = 遍历数 − 剔除数 / valid count equals the visited minus the dropped

// 段 4｜剔除提示（先置者保留：超上限码若已占则不覆盖）/ segment 4, drop hint, never overwriting an existing code
IF (nDropped > 0) AND (eErr = DL_ERR_NONE) THEN
    eErr := 16#0001_044C;               // 非有限样本已剔除（信息级）/ non-finite samples dropped, info level
END_IF

// 段 5｜累加溢出复检：中间量非有限即溢出 / segment 5, overflow re-check on the accumulator
IF (fSum <> fSum) OR (ABS(fSum) > DL_LREAL_MAX_FINITE) THEN
    FC_DL_ArraySumLreal := DL_LREAL_ZERO;   // 溢出不给伪值 / never emit a pseudo value on overflow
    eErr   := 16#0001_0392;                // 累加溢出（故障级）/ accumulation overflow, fault level
    bError := TRUE;                        // 置故障标志 / raise the fault flag
    RETURN;                                // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 6｜无有效样本闸：均值绝不靠除零得出 / segment 6, no valid sample gate, the mean never comes out of a division by zero
IF nValidCount = DL_ARRAY_NONE THEN
    FC_DL_ArraySumLreal := DL_LREAL_ZERO;   // 和仍为 0 / the sum stays zero
    fMean  := DL_LREAL_ZERO;               // 均值不计算，置 0 / the mean is not computed
    eErr   := 16#0001_0391;                // 无有效样本（故障级）/ no valid sample, fault level
    bError := TRUE;                        // 置故障标志 / raise the fault flag
    RETURN;                                // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 7｜出口 / segment 7, exit
FC_DL_ArraySumLreal := fSum;                               // 输出和 / publish the sum
fMean := fSum / INT_TO_LREAL(nValidCount);                 // 除数恒 ≥ 1，结构性安全 / the divisor is at least one by construction
bValid := TRUE;                                            // 结果可用 / the results are usable
END_FUNCTION
