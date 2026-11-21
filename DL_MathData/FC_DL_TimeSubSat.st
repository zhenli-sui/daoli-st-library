(*
    FC_DL_TimeSubSat —— TIME 减法负差钳零防御包装
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
    功能说明  : TIME 减法：返回 tA - tB（tA 为被减数、tB 为减数），TIME 算术
                委托 `-` 运算符，不重实现任何时间运算内核；
                tB > tA 时差为负，而 TIME 为无符号语义、负差跨平台未定义，
                故防御性钳位输出 T#0S 并置信息级 16#0001_01E2
                （bError=FALSE、bValid=TRUE，属正常防御）；
                钳位方向：仅下界单侧钳零（负差归 T#0S，不产生回绕）；
                本组件无故障级路径（减法运算不存在除法/非有限态故障源），
                故障三码位预留禁用。
    错误码    : 16#0001_01E2 减数为大，负差已钳位至 T#0S——信息级，正常防御
                16#0001_01E3 预留禁用（信息级，不得挪用）
                16#0001_02C1 预留禁用（故障级，不得挪用）
                16#0001_02C2 预留禁用（故障级，不得挪用）
                16#0001_02C3 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_TimeSubSat : TIME
VAR_INPUT
    tA : TIME; // 被减数 [ms] / minuend
    tB : TIME; // 减数 [ms] / subtrahend
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_ZERO : TIME := T#0S; // TIME 零值（负差钳位目标） [ms] / TIME zero value (clamp target for negative difference)
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeSubSat := DL_TIME_ZERO; // 故障缺省返回 T#0S [ms] / fault default returns T#0S
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本组件无故障级路径） / preset no fault (no fault-level path in this component)
bValid := FALSE; // 预置无效，通过负差判定后置位 / preset invalid, set TRUE after negative-difference check

// 段 2｜负差钳零判定与主体减法（末段） / segment 2, negative-difference clamp-to-zero check and main subtraction (final)
IF tB > tA THEN
    FC_DL_TimeSubSat := DL_TIME_ZERO; // 负差钳位至 T#0S（TIME 无符号语义，负差跨平台未定义） / negative difference clamped to T#0S (TIME is unsigned, negative difference is platform-undefined)
    eErr := 16#0001_01E2;             // 信息级：负差已钳零 / info level: negative difference clamped to zero
ELSE
    FC_DL_TimeSubSat := tA - tB; // 域内委托 `-` 运算符减法 / in-domain subtraction via `-` operator
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级钳零不置故障 / info-level clamp never raises fault
bValid := TRUE;  // 域内或钳零输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
