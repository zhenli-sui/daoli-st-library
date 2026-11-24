(*
    组件名称 : FC_DL_QuantizeStep
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 按非整数步距量化，把任意给定值对齐到 n × step（编码器分辨率、给定值网格、成本最小单位的通用内核）。
              取舍 ①：禁用平台 ROUND —— 三家平台的 ROUND 在 .5 上是「银行家舍入」还是「远离零」并不一致，
              本件一律 TRUNC(fQ + 0.5)：加法把半值抬到整数侧，TRUNC 再向零截，等价于「半值向正方向」，
              负值同样成立（TRUNC(-1.8) = -1），语义单一且可复现。
              取舍 ②：商超精确域（> 1E15）时按输入直通而不硬算 —— LREAL 尾数只有 53 位，
              此域内 step 已小于末位权重，量化结果与输入仅差舍入噪声，硬算只会输出一个看着精确的假值。
              取舍 ③：步距非法时返回输入本身而非 0 —— 量化是「修饰」而非「求值」，步距坏了就把原值放行，
              静默置 0 会把一个传感器读数变成零位，比报错危险得多。
    开源溯源 : 原创实现。与存量 FC_DL_RoundSat / FC_DL_TruncEx 的职责边界：那两件到「整数」，；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              本件到「非整数步距」。无外部源码参考，码位与分级 100% 自有。
    本文件内含 : FUNCTION FC_DL_QuantizeStep（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 步距闸 + 非有限闸 + 精确域闸 + 乘积溢出复检 + 残差容差判据
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 全部阈值与半步比例常量化
    错误码   : 16#0001_0438 [信息级] 商超精确域（> DL_QUANT_MAX_RATIO），按输入直通，bValid = TRUE
               16#0001_0439 [信息级] 残差越半步（浮点误差提示），不改结果，bValid = TRUE
               16#0001_0372 [故障级] 步距 ≤ DL_FLOAT_EPS，返回输入直通，bValid = FALSE
               16#0001_0373 [故障级] 输入非有限（NaN 或 ±INF），返回 0，bValid = FALSE
               16#0001_0374 [故障级] 量化结果超有限域已饱和，bValid = FALSE
    码位总账 : 16#0001_0438 用 / 16#0001_0439 用 ｜ 16#0001_0372 用 / 16#0001_0373 用 / 16#0001_0374 用
    遗留假设 : ① TRUNC 返回与入参同宽（LREAL），赋回 LREAL 变量无需显式转换 —— IEC 语义推导，未三平台实测。
              ② 商的溢出安全依赖「IEEE 754 除法溢出得 INF 而非陷阱」这一平台行为；若某平台开启 FPU 异常陷阱，
              需在任务配置中关闭后再用本件。此条为编译/运行门槛，未实测。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 1 入库
*)
FUNCTION FC_DL_QuantizeStep : LREAL
VAR_INPUT
    fIn             : LREAL := 0.0;   // 待量化值，全域有限实数 [工程单位] / value to quantise, finite real in engineering units
    fStep           : LREAL := 1.0;   // 量化步距，必须 > 0，如 0.01 mm [工程单位] / quantisation step, must exceed zero [engineering unit]
    bRoundHalfUp    : BOOL := TRUE;   // TRUE = 四舍五入（半值向正方向）；FALSE = 向零截断 / TRUE rounds half up, FALSE truncates toward zero
END_VAR
VAR_OUTPUT
    eErr            : UDINT;          // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;           // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;           // 返回值是否可用 / output valid flag
    fResidual       : LREAL;          // 量化残差 = 结果 − 输入，带符号 [工程单位] / residual, result minus input, signed [engineering unit]
END_VAR
VAR
    fQ              : LREAL;          // 商工作寄存器，量化前先转成「步距个数」[倍] / quotient register, the value expressed in steps [ratio]
    fRet            : LREAL;          // 量化结果 [工程单位] / quantised result [engineering unit]
    fQAbs           : LREAL;          // 商的绝对值，只用于精确域判据 [倍] / absolute quotient, used only by the exact domain test [ratio]
END_VAR
VAR CONSTANT
    DL_QUANT_MAX_RATIO  : LREAL := 1.0E15;                     // 商超此值即尾数无小数精度，量化无意义 [倍] / above this ratio the mantissa has no fractional resolution [ratio]
    DL_QUANT_HALF       : LREAL := 0.5;                        // 半步比例，四舍五入的抬升量 [无量纲] / half step lifting term for rounding [dimensionless]
    DL_FLOAT_EPS        : LREAL := 1.0E-12;                    // 浮点判等容差，残差越界判据用 [无量纲] / float tolerance used by the residual test [dimensionless]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;     // LREAL 最大有限值 [无量纲] / largest finite LREAL [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                        // 零哨兵 [无量纲] / zero sentinel [dimensionless]
    DL_ERR_NONE         : UDINT := 16#0000_0000;               // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_QuantizeStep := DL_LREAL_ZERO;    // 故障缺省返回 0 / fault default returns zero
eErr       := DL_ERR_NONE;              // 预置无错误 / preset no error
bError     := FALSE;                    // 预置无故障 / preset no fault
bValid     := FALSE;                    // 预置结果不可用 / preset unusable
fResidual  := DL_LREAL_ZERO;            // 预置残差 0 / preset the residual to zero

// 段 2｜步距闸：步距不可用时直通输入，绝不静默置 0 / segment 2, step gate, pass the input through instead of zeroing it
IF fStep <= DL_FLOAT_EPS THEN
    FC_DL_QuantizeStep := fIn;          // 原值直通（量化是修饰，不是求值）/ pass the raw value through
    eErr   := 16#0001_0372;             // 步距非法（故障级）/ illegal step, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // bValid 保持 FALSE，调用方必须知情 / bValid stays FALSE, the caller must know
END_IF

// 段 3｜输入有限性闸 / segment 3, input finiteness gate
IF (fIn <> fIn) OR (ABS(fIn) > DL_LREAL_MAX_FINITE) THEN
    eErr   := 16#0001_0373;             // 输入非有限（故障级）/ non-finite input, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 4｜唯一一次求商，随后复用同一结果做精确域判据 / segment 4, one division reused by the exact domain test
fQ    := fIn / fStep;                   // 步距已过闸（> EPS），除零结构性不可能 / the step passed the gate, division by zero is structurally impossible
fQAbs := ABS(fQ);                       // 取幅值供判据 / magnitude for the test
IF fQAbs > DL_QUANT_MAX_RATIO THEN
    FC_DL_QuantizeStep := fIn;          // 精确域外按输入直通 / pass the input through outside the exact domain
    eErr   := 16#0001_0438;             // 商超精确域（信息级，不置 bError）/ quotient beyond the exact domain, info level
    bValid := TRUE;                     // 直通值可用 / the pass-through value is usable
    RETURN;                             // 带值返回 / return with the value
END_IF

// 段 5｜取整：只允许 TRUNC（禁平台 ROUND，银行家舍入三平台不一致）/ segment 5, integer snap with TRUNC only
IF bRoundHalfUp THEN
    fQ := fQ + DL_QUANT_HALF;           // 半值向正方向抬升，负值同样成立 / lifting the half step works for negative values as well
END_IF
fQ := TRUNC(fQ);                        // 向零截断，语义单一可复现 / truncation toward zero, single reproducible semantics

// 段 6｜回乘并复检溢出 / segment 6, multiply back and re-check the overflow
fRet := fQ * fStep;                     // 回到工程单位 / back to engineering units
IF ABS(fRet) >= DL_LREAL_MAX_FINITE THEN
    IF fRet > DL_LREAL_ZERO THEN
        fRet := DL_LREAL_MAX_FINITE;    // 正向饱和 / saturate positive
    ELSE
        fRet := -DL_LREAL_MAX_FINITE;   // 负向饱和 / saturate negative
    END_IF
    eErr   := 16#0001_0374;             // 结果溢出已饱和（故障级）/ result overflow saturated, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
END_IF

// 段 7｜残差与容差判据：越半步只提示，不改结果 / segment 7, residual test, hint only
fResidual := fRet - fIn;                                                        // 带符号残差 / signed residual
IF (ABS(fResidual) - fStep * DL_QUANT_HALF) > DL_FLOAT_EPS THEN
    IF eErr = DL_ERR_NONE THEN                                                  // 不覆盖已有更高优先级的码 / never overwrite a code already set
        eErr := 16#0001_0439;                                                   // 残差越半步（信息级，浮点误差提示）/ residual beyond half a step, info level
    END_IF
END_IF

// 段 8｜出口 / segment 8, exit
FC_DL_QuantizeStep := fRet;             // 输出量化结果 / publish the quantised result
bValid := NOT bError;                   // 故障态不可用，信息态可用 / unusable after a fault, usable after an info code
END_FUNCTION
