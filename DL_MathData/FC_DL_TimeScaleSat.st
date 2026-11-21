(*
    FC_DL_TimeScaleSat —— TIME 整数乘法溢出饱和防御包装
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : TIME 整数乘法：返回 tIn × nScale，TIME 算术委托 `×` 运算符，
                不重实现任何时间运算内核；
                nScale < 0 时防御性输出 T#0S 并置信息级 16#0001_01E5
                （TIME 无负语义，负乘子按钳零处理，bError=FALSE、bValid=TRUE）；
                nScale = 0 时输出 T#0S，无错误码（零乘合法）；
                溢出预判采用除法比较口径（规避「先算后判」红线）：
                nScale > 0 且 tIn > DL_TIME_MAX / nScale 时判乘法将溢出，
                直接饱和输出 DL_TIME_MAX，置信息级 16#0001_01E4；
                预判除法除子 nScale > 0 恒非零，满足除法前判除子红线；
                钳位方向：负乘子钳零 / 正乘子溢出钳上界 DL_TIME_MAX（双侧饱和语义）。
    错误码    : 16#0001_01E4 乘法结果超 TIME 上限，已饱和至 DL_TIME_MAX——信息级，正常防御
                16#0001_01E5 负乘子输入，已钳位输出 T#0S——信息级，正常防御
                16#0001_02C4 预留禁用（故障级，不得挪用）
                16#0001_02C5 预留禁用（故障级，不得挪用）
                16#0001_02C6 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_TimeScaleSat : TIME
VAR_INPUT
    tIn    : TIME; // 输入时长 [ms] / input duration
    nScale : INT;  // 乘子 [倍]，0~32767，负值输出钳 T#0s / scale factor [x], 0~32767, negative clamps output to T#0s
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_MAX  : TIME := T#49D17H2M47S295MS; // 32 位 TIME 容器上限，等价 4294967295 ms [ms] / 32-bit TIME container ceiling, equals 4294967295 ms
    DL_TIME_ZERO : TIME := T#0S;               // TIME 零值（钳位目标） [ms] / TIME zero value (clamp target)
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeScaleSat := DL_TIME_ZERO; // 故障缺省返回 T#0S [ms] / fault default returns T#0S
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本组件无故障级路径） / preset no fault (no fault-level path in this component)
bValid := FALSE; // 预置无效，通过乘子判定后置位 / preset invalid, set TRUE after factor check

// 段 2｜乘子符号判定 / segment 2, scale factor sign check
IF nScale < 0 THEN
    FC_DL_TimeScaleSat := DL_TIME_ZERO; // 负乘子钳位输出 T#0S（TIME 无负语义） / negative factor clamps output to T#0S (TIME has no negative semantics)
    eErr := 16#0001_01E5;               // 信息级：负乘子已钳零 / info level: negative factor clamped to zero
    bError := FALSE;                    // 信息级钳零不置故障 / info-level clamp never raises fault
    bValid := TRUE;                     // 钳零输出有效可用 / clamped output is valid
    RETURN;                             // 立即返回 / immediate return
ELSIF nScale = 0 THEN
    FC_DL_TimeScaleSat := DL_TIME_ZERO; // 零乘子输出 T#0S（零乘合法，无错误码） / zero factor yields T#0S (legal zero multiply, no error id)
    bError := FALSE;                    // 无故障 / no fault
    bValid := TRUE;                     // 输出有效可用 / output is valid
    RETURN;                             // 立即返回 / immediate return
END_IF

// 段 3｜除法比较溢出预判与主体乘法（末段） / segment 3, divide-compare overflow pre-check and main multiplication (final)
IF tIn > DL_TIME_MAX / nScale THEN
    FC_DL_TimeScaleSat := DL_TIME_MAX; // 溢出预判命中，饱和至上限（除子 nScale > 0 恒非零） / overflow pre-check hit, saturate to ceiling (divisor nScale > 0 guaranteed nonzero)
    eErr := 16#0001_01E4;              // 信息级：乘法溢出已饱和 / info level: multiplication overflow, saturated
ELSE
    FC_DL_TimeScaleSat := tIn * nScale; // 预判通过，域内委托 `×` 运算符乘法 / pre-check passed, in-domain multiplication via `×` operator
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级饱和不置故障 / info-level saturation never raises fault
bValid := TRUE;  // 域内或饱和输出均有效可用 / in-domain or saturated output is valid
END_FUNCTION
