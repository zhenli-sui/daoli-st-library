(*
    FC_DL_LrealToDintSat —— LREAL 到 DINT 向零截断饱和防御转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : 将 LREAL 输入防御性转换为 DINT 并作为返回值输出；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_0291，返回 0 且 bValid=FALSE；
                取整取向声明：向零截断（TRUNC 语义）后钳位，钳位按符号直接取界值；
                溢出预判先行（规避「先算后判」红线）：先在 LREAL 域判定越界并钳位，
                再对界值委托 TRUNC 向零截断，从而杜绝 TRUNC 越界未定义行为；
                越界时置信息级 16#0001_01C2（bError=FALSE、bValid=TRUE），输出钳位后防御值。
    错误码    : 16#0001_0291 非有限输入（NaN 或 ±INF）——故障级，返回 0
                16#0001_01C2 输入超 DINT 域，已按符号饱和钳位——信息级，正常防御
                16#0001_01C3 预留禁用（信息级，不得挪用）
                16#0001_0292 预留禁用（故障级，不得挪用）
                16#0001_0293 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_LrealToDintSat : DINT
VAR_INPUT
    fIn : LREAL; // 待转换输入 [无量纲] / input value to convert
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_DINT_MAX   : LREAL := 2147483647.0;           // DINT 域上界，LREAL 承载 [无量纲] / DINT upper bound carried in LREAL
    DL_DINT_MIN   : LREAL := -2147483648.0;          // DINT 域下界，LREAL 承载 [无量纲] / DINT lower bound carried in LREAL
    DL_LREAL_HUGE : LREAL := 1.7976931348623157E308; // LREAL 最大有限幅值，超过即判 ±INF [无量纲] / max finite LREAL magnitude, beyond means +/-INF
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LrealToDintSat := 0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fIn <> fIn) OR (fIn > DL_LREAL_HUGE) OR (fIn < -DL_LREAL_HUGE); // NaN 自不等判定，±INF 用安全幅值比较 [无量纲] / NaN by self-inequality, +/-INF by safe magnitude compare
IF bNonFinite THEN
    FC_DL_LrealToDintSat := 0; // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_0291;    // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;            // 置故障标志 / set fault flag
    bValid := FALSE;           // 输出无效 / output invalid
    RETURN;                    // 立即返回 / immediate return
END_IF

// 段 3｜域判定先行钳位与向零截断主体计算（末段） / segment 3, domain-first clamp then truncate-toward-zero main conversion (final)
IF fIn > DL_DINT_MAX THEN
    FC_DL_LrealToDintSat := DL_DINT_MAX; // 正向钳至 DINT 上界（界值整数部分精确可表） / clamp to DINT upper bound (integer part exactly representable)
    eErr := 16#0001_01C2;                // 信息级：超上界已钳位 / info level: above upper bound, clamped
ELSIF fIn < DL_DINT_MIN THEN
    FC_DL_LrealToDintSat := DL_DINT_MIN; // 负向钳至 DINT 下界（界值整数部分精确可表） / clamp to DINT lower bound (integer part exactly representable)
    eErr := 16#0001_01C2;                // 信息级：超下界已钳位 / info level: below lower bound, clamped
ELSE
    FC_DL_LrealToDintSat := TRUNC(fIn); // 域内委托平台内建 TRUNC 向零截断 / in-domain delegate to built-in TRUNC toward zero
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 / info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 域内或钳位输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
