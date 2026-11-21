(*
    FC_DL_DintMsToTime —— DINT 毫秒到 TIME 防御转换（负值钳零）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeConv
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 DINT_TO_TIME，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 DINT 毫秒数防御性转换为 TIME 并作为返回值输出，域内委托平台内建 DINT_TO_TIME；
                负值（TIME 无负语义）钳为 T#0S 并置信息级 16#0001_01F4；
                上溢结构性不可能：DINT 正域上限 2147483647 ms 小于 TIME 域上限 4294967295 ms，
                故本件不设上界饱和分支（该结论已在此声明，后续轮次不得误加上溢假分支）；
                钳位方向：下界钳 0 ms，上界无需要钳；
                纯值类型域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）。
    错误码    : 16#0001_01F4 负毫秒输入（TIME 无负语义），已钳 T#0S——信息级，正常防御
                16#0001_01F5 预留禁用（信息级，不得挪用）
                16#0001_02DC 预留禁用（故障级，不得挪用）
                16#0001_02DD 预留禁用（故障级，不得挪用）
                16#0001_02DE 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_DintMsToTime : TIME
VAR_INPUT
    nMs : DINT; // 毫秒数，有效域 0 ~ 2147483647 ms（负值钳 0） [ms] / milliseconds, valid domain 0 .. 2147483647 ms, negative clamps to 0 [ms]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_ZERO : TIME := T#0S; // TIME 零值（负值钳位结果与故障缺省） [ms] / TIME zero value, negative clamp and fault default [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintMsToTime := DL_TIME_ZERO; // 故障缺省返回 T#0S（TIME 无负语义） [ms] / fault default T#0S, TIME has no negative semantics [ms]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过负值闸后置位 / preset invalid, set TRUE after the negative gate

// 段 2｜负值防御闸（TIME 无负语义） / segment 2, negative guard (TIME has no negative semantics)
IF nMs < 0 THEN
    FC_DL_DintMsToTime := DL_TIME_ZERO; // 负值钳为 T#0S [ms] / clamp the negative value to T#0S [ms]
    eErr := 16#0001_01F4;               // 信息级：负毫秒已钳零，正常防御 / info level: negative milliseconds clamped to zero
    bError := FALSE;                    // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                     // 钳位值本身有效可用 / the clamped value itself is valid
    RETURN;                             // 钳位即出口，不调用内建转换 / clamping is the exit, built-in conversion not called
END_IF

// 段 3｜域内委托转换（末段） / segment 3, in-domain delegated conversion (final)
FC_DL_DintMsToTime := DINT_TO_TIME(nMs); // 域内委托平台内建 DINT_TO_TIME（DINT 正域恒小于 TIME 域，无上溢路径） [ms] / in-domain delegate to built-in DINT_TO_TIME, DINT positive range is always below the TIME range so no overflow path [ms]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
