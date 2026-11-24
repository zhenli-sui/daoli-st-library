(*
    FC_DL_DintToUintSat —— DINT 到 UINT 饱和防御转换
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
    功能说明  : 将 DINT 输入防御性转换为 UINT 并作为返回值输出；
                nIn < 0 时钳位至 0，置信息级 16#0001_01CA（UINT 无符号，负值不可表）；
                nIn 超出 UINT 上界 65535 时钳位至上界，置信息级 16#0001_01CB；
                钳位方向：下界 0 / 上界 65535（双侧饱和）；
                纯整数域输入不存在 NaN/±INF 非有限态，亦无除法运算，故本组件无故障级路径；
                域内转换委托平台内建 DINT_TO_UINT 语义，不重实现数学内核；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_01CA 负值输入，已钳位至 0——信息级，正常防御
                16#0001_01CB 输入超 UINT 上界，已钳位至 65535——信息级，正常防御
                16#0001_029D 预留禁用（故障级，不得挪用）
                16#0001_029E 预留禁用（故障级，不得挪用）
                16#0001_029F 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_DintToUintSat : UINT
VAR_INPUT
    nIn : DINT; // 待转换输入 [无量纲] / input value to convert
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_UINT16_MAX : DINT := 65535; // UINT 域上界 65535 [无量纲] / UINT upper bound 65535
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintToUintSat := 0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（整数域无故障态） / preset no fault (no fault states in integer domain)
bValid := FALSE; // 预置无效，通过钳位判定后置位 / preset invalid, set TRUE after clamp check

// 段 2｜双侧饱和钳位与主体转换（末段） / segment 2, double-side saturating clamp and main conversion (final)
IF nIn < 0 THEN
    FC_DL_DintToUintSat := 0; // 负值钳位至 0（UINT 无符号语义） / negative input clamped to 0 (UINT is unsigned)
    eErr := 16#0001_01CA;     // 信息级：负值已钳零 / info level: negative input clamped to zero
ELSIF nIn > DL_UINT16_MAX THEN
    FC_DL_DintToUintSat := 16#FFFF; // 正向钳位至 UINT 上界 65535 / clamp to UINT upper bound 65535
    eErr := 16#0001_01CB;           // 信息级：超上界已钳位 / info level: above upper bound, clamped
ELSE
    FC_DL_DintToUintSat := DINT_TO_UINT(nIn); // 域内委托平台内建 _TO_ 转换语义 / in-domain delegate to built-in _TO_ conversion
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bValid := TRUE; // 域内或钳位输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
