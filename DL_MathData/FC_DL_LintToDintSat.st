(*
    FC_DL_LintToDintSat —— LINT 到 DINT 双向域外饱和转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 LINT_TO_DINT，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 LINT 防御性转换为 DINT 并作为返回值输出，域内转换委托平台内建 LINT_TO_DINT；
                nIn 超 DINT 上界 2147483647 时饱和输出 2147483647 并置信息级 16#0001_0200；
                nIn 低于 DINT 下界 −2147483648 时饱和输出 −2147483648 并置信息级 16#0001_022D；
                下界输出采用计算式 -DL_DINT_MAX - 1，禁用负数字面量直写
                （部分编译器把负号解析为对一个越界正字面量取负，产生告警或错误结果）；
                极值比较采用双侧比较，禁用 ABS(nIn)（R55：有符号极值取绝对值会回绕漏判）；
                钳位方向：双侧饱和（−2147483648 ~ 2147483647），绝不回绕；
                纯整数域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）。
    错误码    : 16#0001_0200 nIn 超 DINT 上界，已饱和至 2147483647——信息级，正常防御
                16#0001_022D nIn 低于 DINT 下界，已饱和至 −2147483648——信息级，正常防御
                16#0001_02EE 预留禁用（故障级，不得挪用）
                16#0001_02EF 预留禁用（故障级，不得挪用）
                16#0001_02F0 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_LintToDintSat : DINT
VAR_INPUT
    nIn : LINT; // 待转换 64 位有符号整数，建议域 ±9223372036854775807 [无量纲] / signed 64-bit integer to convert, suggested domain +/-9223372036854775807 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DINT_MAX_L : LINT := 2147483647;      // DINT 上界，用 LINT 承载以便域外比较 [无量纲] / DINT upper bound carried in LINT for out-of-domain comparison [dimensionless]
    DL_DINT_MIN_L : LINT := -2147483647 - 1; // DINT 下界，用 LINT 承载以便域外比较；下界值以计算式书写，避免负字面量解析歧义 [无量纲] / DINT lower bound carried in LINT, written as a computed expression to avoid negative literal parsing ambiguity [dimensionless]
    DL_DINT_MAX   : DINT := 2147483647;      // 上界饱和输出值 [无量纲] / upper saturation output [dimensionless]
    DL_DINT_ZERO  : DINT := 0;               // 返回值预置零（本件无故障路径） [无量纲] / preset zero, no fault path in this component [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LintToDintSat := DL_DINT_ZERO; // 预置 0（本件无故障级路径，仅作预置约定） [无量纲] / preset 0, no fault-level path in this component [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过双侧预判后置位 / preset invalid, set TRUE after both bound pre-checks

// 段 2｜上界预判与饱和 / segment 2, upper bound pre-check and saturation
IF nIn > DL_DINT_MAX_L THEN // 在 LINT 域先比较，超界值绝不送入内建转换 [无量纲] / compare in the LINT domain first, out-of-range values never reach the built-in conversion [dimensionless]
    FC_DL_LintToDintSat := DL_DINT_MAX; // 饱和输出 DINT 上界 2147483647 [无量纲] / saturate to the DINT upper bound 2147483647 [dimensionless]
    eErr := 16#0001_0200;               // 信息级：上溢饱和，正常防御 / info level: upper overflow saturated, normal defence
    bError := FALSE;                    // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                     // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                             // 饱和即出口，不调用内建转换 / saturation is the exit, built-in conversion not called
END_IF

// 段 3｜下界预判与饱和 / segment 3, lower bound pre-check and saturation
IF nIn < DL_DINT_MIN_L THEN // 双侧比较，禁用 ABS 单侧式（R55：有符号极值取绝对值会回绕） [无量纲] / two-sided comparison, single-sided ABS form forbidden, ABS of a signed extreme wraps around [dimensionless]
    FC_DL_LintToDintSat := -DL_DINT_MAX - 1; // 下界输出用计算式书写，等于 DINT 最小值 [无量纲] / lower bound output written as a computed expression, equal to the DINT minimum [dimensionless]
    eErr := 16#0001_022D;                    // 信息级：下溢饱和，正常防御 / info level: lower overflow saturated, normal defence
    bError := FALSE;                         // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                          // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                                  // 饱和即出口，不调用内建转换 / saturation is the exit, built-in conversion not called
END_IF

// 段 4｜域内委托转换（末段） / segment 4, in-domain delegated conversion (final)
FC_DL_LintToDintSat := LINT_TO_DINT(nIn); // 域内委托平台内建 LINT_TO_DINT，精确无损 [无量纲] / in-domain delegate to built-in LINT_TO_DINT, exact and lossless [dimensionless]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
