(*
    FC_DL_LrealToLintSat —— LREAL 到 LINT 域外饱和转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 TRUNC 与 LREAL_TO_LINT，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 LREAL 防御性转换为 LINT 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02F4，返回 0 且 bValid=FALSE；
                取整取向声明：向零截断（TRUNC 语义）后钳位，与 FC_DL_RealToLintSat 及
                R16 FC_DL_LrealToDintSat 同口径；
                与 FC_DL_RealToLintSat 的职责边界：源类型不同（IEC 61131-3 无 ANY_REAL 泛型），
                双版本是库内既定策略（R16 饱和转换族先例），不做类型合并；
                域外按方向饱和（上界 9223372036854775807 / 下界负向极值）
                并置信息级 16#0001_0230；下界用 -DL_LINT_MAX - 1 计算式，禁负数字面量直写；
                钳位方向：双侧饱和，绝不回绕。
    错误码    : 16#0001_0230 输入超 LINT 域，已按符号饱和——信息级，正常防御
                16#0001_0231 预留禁用（信息级，不得挪用）
                16#0001_02F4 非有限输入（NaN 或 ±INF）——故障级，返回 0
                16#0001_02F5 预留禁用（故障级，不得挪用）
                16#0001_02F6 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_LrealToLintSat : LINT
VAR_INPUT
    fIn : LREAL; // 待转换 64 位浮点值，建议域 ±9.2E18（非有限拦截，域外饱和） [无量纲] / 64-bit floating value to convert, suggested domain +/-9.2E18 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LINT_MAX_LR    : LREAL := 9.2233720368547758E18;          // LINT 域上界在 LREAL 域的精确可表近似值 [无量纲] / LINT upper bound represented in LREAL [dimensionless]
    DL_LINT_MAX       : LINT  := 9223372036854775807;            // LINT 上界饱和输出值 [无量纲] / LINT upper saturation output [dimensionless]
    DL_LINT_ZERO      : LINT  := 0;                              // 故障缺省返回值 [无量纲] / fault default return value [dimensionless]
    DL_LREAL_HUGE     : LREAL := 1.7976931348623157E308;         // LREAL 最大有限幅值，超过即判 ±INF [无量纲] / max finite LREAL magnitude, beyond means +/-INF [dimensionless]
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LrealToLintSat := DL_LINT_ZERO; // 故障缺省返回 0 [无量纲] / fault default 0 [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过三路闸后置位 / preset invalid, set TRUE after the three gates

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_LREAL_HUGE) OR (fIn < -DL_LREAL_HUGE); // 非有限判定（NaN 自不等 + 最大有限幅值判 ±INF） [无量纲] / non-finite check (NaN by self-inequality, +/-INF by max finite magnitude) [dimensionless]
IF bNonFinite THEN
    eErr := 16#0001_02F4; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0 / early return on fault, keep default 0
END_IF

// 段 3｜域外判定饱和与域内截断转换（末段） / segment 3, out-of-domain saturation and in-domain truncate conversion (final)
IF fIn > DL_LINT_MAX_LR THEN
    FC_DL_LrealToLintSat := DL_LINT_MAX; // 上界饱和至 LINT 上界 [无量纲] / saturate to the LINT upper bound [dimensionless]
    eErr := 16#0001_0230;                // 信息级：域外饱和，正常防御 / info level: out-of-domain saturation, normal defence
    bError := FALSE;                     // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                      // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                              // 饱和即出口 / saturation is the exit
ELSIF fIn < -DL_LINT_MAX_LR THEN
    FC_DL_LrealToLintSat := -DL_LINT_MAX - 1; // 下界饱和，用计算式书写，等于 LINT 最小值 [无量纲] / saturate to the LINT minimum, written as a computed expression [dimensionless]
    eErr := 16#0001_0230;                     // 上下共用同一业务语义码，方向写进头注释 / both directions share one business-semantics code, directions documented in the header
    bError := FALSE;                          // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                           // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                                   // 饱和即出口 / saturation is the exit
ELSE
    FC_DL_LrealToLintSat := LREAL_TO_LINT(TRUNC(fIn)); // 先 TRUNC 成整值再转，取向恒为向零截断 [无量纲] / TRUNC to an integral value before converting, always truncates toward zero [dimensionless]
    eErr := 0;                                         // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内或饱和输出均有效可用 / in-domain or saturated output is valid
END_FUNCTION
