(*
    FC_DL_RealToLintSat —— REAL 到 LINT 域外饱和转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 REAL_TO_LREAL、TRUNC 与 LREAL_TO_LINT，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 REAL 防御性转换为 LINT 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02F1，返回 0 且 bValid=FALSE；
                取整取向声明：向零截断（TRUNC 语义）后钳位，与 R16 FC_DL_LrealToDintSat 同口径；
                升位先行：先 REAL_TO_LREAL 升位再与 LREAL 域界比较，
                禁用 REAL 常量直接比较（REAL 尾数仅 24 位，域界值本身不可精确表示，会漏判）；
                域外按方向饱和（上界 9223372036854775807 / 下界负向极值）
                并置信息级 16#0001_022E；下界用 -DL_LINT_MAX - 1 计算式，禁负数字面量直写；
                钳位方向：双侧饱和，绝不回绕。
    错误码    : 16#0001_022E 输入超 LINT 域，已按符号饱和——信息级，正常防御
                16#0001_022F 预留禁用（信息级，不得挪用）
                16#0001_02F1 非有限输入（NaN 或 ±INF）——故障级，返回 0
                16#0001_02F2 预留禁用（故障级，不得挪用）
                16#0001_02F3 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_RealToLintSat : LINT
VAR_INPUT
    fIn : REAL; // 待转换浮点值，建议域 ±9.2E18（非有限拦截，域外饱和） [无量纲] / floating value to convert, suggested domain +/-9.2E18 [dimensionless]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_LINT_MAX_LR : LREAL := 9.2233720368547758E18;  // LINT 域上界在 LREAL 域的精确可表近似值 [无量纲] / LINT upper bound represented in LREAL [dimensionless]
    DL_LINT_MAX    : LINT  := 9223372036854775807;    // LINT 上界饱和输出值 [无量纲] / LINT upper saturation output [dimensionless]
    DL_LINT_ZERO   : LINT  := 0;                      // 故障缺省返回值 [无量纲] / fault default return value [dimensionless]
    DL_REAL_INF_GUARD : LREAL := 4.0E38;              // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL
END_VAR
VAR
    fLr        : LREAL; // 升位后的 LREAL 中间量 [无量纲] / widened LREAL intermediate [dimensionless]
    bNonFinite : BOOL;  // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_RealToLintSat := DL_LINT_ZERO; // 故障缺省返回 0 [无量纲] / fault default 0 [dimensionless]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过三路闸后置位 / preset invalid, set TRUE after the three gates

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_REAL_INF_GUARD) OR (fIn < -DL_REAL_INF_GUARD); // 非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / non-finite check (NaN by self-inequality, +/-INF by safe magnitude) [dimensionless]
IF bNonFinite THEN
    eErr := 16#0001_02F1; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 0 / early return on fault, keep default 0
END_IF

// 段 3｜升位与域外判定饱和 / segment 3, widening and out-of-domain saturation
fLr := REAL_TO_LREAL(fIn); // 升位先行，REAL 域界值本身不可精确表示，直接用 REAL 比较会漏判 [无量纲] / widen first, REAL cannot represent the bound exactly so comparing in REAL would miss the overflow [dimensionless]
IF fLr > DL_LINT_MAX_LR THEN
    FC_DL_RealToLintSat := DL_LINT_MAX; // 上界饱和至 LINT 上界 [无量纲] / saturate to the LINT upper bound [dimensionless]
    eErr := 16#0001_022E;               // 信息级：域外饱和，正常防御 / info level: out-of-domain saturation, normal defence
    bError := FALSE;                    // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                     // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                             // 饱和即出口 / saturation is the exit
END_IF
IF fLr < -DL_LINT_MAX_LR THEN
    FC_DL_RealToLintSat := -DL_LINT_MAX - 1; // 下界饱和，用计算式书写，等于 LINT 最小值 [无量纲] / saturate to the LINT minimum, written as a computed expression [dimensionless]
    eErr := 16#0001_022E;                    // 上下共用同一业务语义码，方向写进头注释 / both directions share one business-semantics code, directions documented in the header
    bError := FALSE;                         // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                          // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                                  // 饱和即出口 / saturation is the exit
END_IF

// 段 4｜域内向零截断与委托转换（末段） / segment 4, in-domain truncate-toward-zero and delegated conversion (final)
FC_DL_RealToLintSat := LREAL_TO_LINT(TRUNC(fLr)); // 先 TRUNC 成整值 LREAL 再转，取向恒为向零截断，规避内建舍入取向差异 [无量纲] / TRUNC to an integral LREAL before converting, always truncates toward zero and avoids built-in rounding differences [dimensionless]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
