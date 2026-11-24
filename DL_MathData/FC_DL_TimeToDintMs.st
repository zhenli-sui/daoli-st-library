(*
    FC_DL_TimeToDintMs —— TIME 到 DINT 毫秒防御转换（超域饱和）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeConv
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 TIME_TO_DINT，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 TIME 值防御性转换为 DINT 毫秒数并作为返回值输出，域内委托平台内建 TIME_TO_DINT；
                溢出预判先行：先在 TIME 域与 2147483647 ms（T#24D20H31M23S647MS）比较，
                超限直接饱和输出 2147483647 并置信息级 16#0001_01F2，
                严禁把超限值送进 TIME_TO_DINT（部分平台此时返回负值，静默翻转语义）；
                转换结果为负（负 TIME 或平台回绕）时钳 0 并置信息级 16#0001_01F3；
                钳位方向：上界饱和至 2147483647 ms，下界钳 0 ms；
                纯值类型域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）。
    错误码    : 16#0001_01F2 输入超 DINT 毫秒域（> 2147483647 ms），已饱和——信息级，正常防御
                16#0001_01F3 转换结果为负（负 TIME 或平台回绕），已钳 0——信息级，正常防御
                16#0001_02D9 预留禁用（故障级，不得挪用）
                16#0001_02DA 预留禁用（故障级，不得挪用）
                16#0001_02DB 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_TimeToDintMs : DINT
VAR_INPUT
    tIn : TIME; // 待转换时间值，有效域 0 ms ~ 4294967295 ms [ms] / time value to convert, domain 0 ms .. 4294967295 ms [ms]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_DINT_MAX : TIME := T#24D20H31M23S647MS; // DINT 正域可承载的最大毫秒数 2147483647 ms [ms] / max ms a DINT can carry, 2147483647 ms [ms]
    DL_DINT_MAX_MS   : DINT := 2147483647;          // 上界饱和输出值 [ms] / upper saturation output [ms]
    DL_MS_MIN        : DINT := 0;                   // 下界钳位值（TIME 无负语义） [ms] / lower clamp, TIME has no negative semantics [ms]
END_VAR
VAR
    nOut : DINT; // 域内转换中间结果 [ms] / in-domain conversion intermediate [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeToDintMs := DL_MS_MIN; // 故障缺省返回 0 ms（TIME 无负语义） [ms] / fault default 0 ms, TIME has no negative semantics [ms]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过上界预判后置位 / preset invalid, set TRUE after the upper-bound pre-check

// 段 2｜上界预判与饱和（先判后算，禁先转换） / segment 2, upper bound pre-check and saturation (compare before convert)
IF tIn > DL_TIME_DINT_MAX THEN // 在 TIME 域先比较，绝不让超限值进入内建转换 [ms] / compare in the TIME domain first, never let an oversized value reach the built-in conversion [ms]
    FC_DL_TimeToDintMs := DL_DINT_MAX_MS; // 饱和输出 DINT 正域上限 2147483647 ms [ms] / saturate to the DINT positive bound 2147483647 ms [ms]
    eErr := 16#0001_01F2;                 // 信息级：超 DINT 毫秒域已饱和，正常防御 / info level: beyond the DINT ms domain, saturated
    bError := FALSE;                      // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                       // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                               // 饱和即出口，不调用内建转换 / saturation is the exit, built-in conversion not called
END_IF

// 段 3｜域内委托转换与负值钳零（末段） / segment 3, in-domain delegated conversion and negative clamp (final)
nOut := TIME_TO_DINT(tIn); // 域内委托平台内建 TIME_TO_DINT [ms] / in-domain delegate to built-in TIME_TO_DINT [ms]
IF nOut < DL_MS_MIN THEN
    nOut := DL_MS_MIN;    // 负结果钳 0（负 TIME 或平台回绕，TIME 无负语义） [ms] / clamp negative results to 0, TIME has no negative semantics [ms]
    eErr := 16#0001_01F3; // 信息级：结果为负已钳零，正常防御 / info level: result was negative and clamped to zero
ELSE
    eErr := 0;            // 域内无错误 / in-domain, no error
END_IF
FC_DL_TimeToDintMs := nOut; // 输出钳位后的毫秒结果 [ms] / output the clamped millisecond result [ms]
bError := FALSE;            // 信息级不置故障 / info level never raises fault
bValid := TRUE;             // 域内或钳位后输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
