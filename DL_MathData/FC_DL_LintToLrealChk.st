(*
    FC_DL_LintToLrealChk —— LINT 到 LREAL 精度告警防御转换
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
    功能说明  : 将 LINT 输入防御性转换为 LREAL 并作为返回值输出；
                |nIn| 超过 2^53（9007199254740992，双精度浮点尾数 53 位精度极限）时，
                值照常转换输出，仅置信息级 16#0001_01CE 提示低位精度损失（bError=FALSE、bValid=TRUE）；
                钳位方向：无钳位（信息级仅记录，转换结果仍为最接近的可表值）；
                极值对称性防御：直接采用双侧比较 nIn > 上界 OR nIn < -下界，
                规避 ABS 对 LINT 最小值取绝对值的回绕未定义行为；
                域内转换委托平台内建 LINT_TO_LREAL 语义，不重实现数学内核；
                信息级码属正常防御：bError=FALSE、bValid=TRUE。
    错误码    : 16#0001_01CE |nIn| 超 2^53 精度极限，转换值低位可能失真——信息级，正常防御
                16#0001_01CF 预留禁用（信息级，不得挪用）
                16#0001_02A3 预留禁用（故障级，不得挪用）
                16#0001_02A4 预留禁用（故障级，不得挪用）
                16#0001_02A5 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_LintToLrealChk : LREAL
VAR_INPUT
    nIn : LINT; // 待转换输入 [无量纲] / input value to convert
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_F53_MAX : LINT := 9007199254740992; // 双精度浮点尾数 53 位精度极限 2^53 [无量纲] / double-precision 53-bit mantissa precision limit 2^53
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LintToLrealChk := 0.0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本组件无故障级路径） / preset no fault (no fault-level path in this component)
bValid := FALSE; // 预置无效，通过精度判定后置位 / preset invalid, set TRUE after precision check

// 段 2｜53 位精度极限判定与主体转换（末段） / segment 2, 53-bit precision limit check and main conversion (final)
IF (nIn > DL_F53_MAX) OR (nIn < -DL_F53_MAX) THEN
    FC_DL_LintToLrealChk := LINT_TO_LREAL(nIn); // 值照常转换（委托内建 _TO_ 语义） / convert as-is via built-in _TO_ conversion
    eErr := 16#0001_01CE; // 信息级：超 2^53 精度极限，低位可能失真，仅记录不钳位 / info level: beyond 2^53 precision limit, low bits may lose accuracy, record only
ELSE
    FC_DL_LintToLrealChk := LINT_TO_LREAL(nIn); // 域内委托平台内建 _TO_ 转换语义，精确无损 / in-domain delegate to built-in _TO_ conversion, exact lossless
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级精度告警不置故障 / info-level precision notice never raises fault
bValid := TRUE;  // 域内或精度告警输出均有效可用 / in-domain or precision-noticed output is valid
END_FUNCTION
