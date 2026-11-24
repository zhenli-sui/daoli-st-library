(*
    FC_DL_LrealSecToTime —— LREAL 秒到 TIME 防御转换（三路防御）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeConv
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 LREAL_TO_TIME，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 LREAL 秒数防御性转换为 TIME 并作为返回值输出，域内委托平台内建 LREAL_TO_TIME；
                非有限输入（NaN 或 ±INF）判为故障级 16#0001_02E2，返回 T#0S 且 bValid=FALSE；
                负值（TIME 无负语义）钳为 T#0S 并置信息级 16#0001_01F8；
                溢出预判先行：先在 LREAL 域与 4294967.295 s（对应 4294967295 ms）比较，
                超限直接饱和输出 T#49D17H2M47S295MS 并置信息级 16#0001_01F9，
                严禁把超限值乘 1000 后送进 LREAL_TO_TIME（先算后判必溢出）；
                钳位方向：下界钳 0 s，上界饱和至 TIME 域上限。
    错误码    : 16#0001_01F8 负秒输入（TIME 无负语义），已钳 T#0S——信息级，正常防御
                16#0001_01F9 秒数超 TIME 域上限（4294967.295 s），已饱和——信息级，正常防御
                16#0001_02E2 非有限输入（NaN 或 ±INF）——故障级，返回 T#0S
                16#0001_02E3 预留禁用（故障级，不得挪用）
                16#0001_02E4 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_LrealSecToTime : TIME
VAR_INPUT
    fSec : LREAL; // 秒数，有效域 0.0 ~ 4294967.295 s（负值钳 0，超限饱和） [s] / seconds, valid domain 0.0 .. 4294967.295 s, negative clamps, overflow saturates [s]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_SEC_MAX        : LREAL := 4294967.295;                     // TIME 域上限对应秒数（4294967295 ms） [s] / seconds equal to the TIME upper bound, 4294967295 ms [s]
    DL_SEC_MIN        : LREAL := 0.0;                             // 秒域下界 [s] / seconds lower bound [s]
    DL_MS_PER_SEC     : LREAL := 1000.0;                          // 秒转毫秒乘子（编译期常量） [ms/s] / seconds-to-milliseconds multiplier [ms/s]
    DL_TIME_MAX       : TIME  := T#49D17H2M47S295MS;              // TIME 域上限 4294967295 ms [ms] / TIME upper bound, 4294967295 ms [ms]
    DL_TIME_ZERO      : TIME  := T#0S;                            // TIME 零值（负值钳位与故障缺省） [ms] / TIME zero value, negative clamp and fault default [ms]
    DL_LREAL_HUGE     : LREAL := 1.7976931348623157E308;          // LREAL 最大有限幅值，超过即判 ±INF [无量纲] / max finite LREAL magnitude, beyond means +/-INF [dimensionless]
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±INF）判定结果 / non-finite (NaN or +/-INF) detection result
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LrealSecToTime := DL_TIME_ZERO; // 故障缺省返回 T#0S [ms] / fault default T#0S [ms]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置输出无效，通过三路闸后置位 / preset invalid, set TRUE after the three gates

// 段 2｜非有限防御闸 / segment 2, non-finite guard
bNonFinite := (fSec <> fSec) OR (fSec > DL_LREAL_HUGE) OR (fSec < -DL_LREAL_HUGE); // 非有限判定（NaN 自不等 + 最大有限幅值判 ±INF） [s] / non-finite check (NaN by self-inequality, +/-INF by max finite magnitude) [s]
IF bNonFinite THEN
    eErr := 16#0001_02E2; // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;       // 置故障标志 / raise error flag
    bValid := FALSE;      // 输出不可用 / output not usable
    RETURN;               // 故障级提前返回，保持缺省 T#0S / early return on fault, keep default T#0S
END_IF

// 段 3｜负值闸与上界预判饱和 / segment 3, negative gate and upper-bound pre-check saturation
IF fSec < DL_SEC_MIN THEN
    FC_DL_LrealSecToTime := DL_TIME_ZERO; // 负值钳为 T#0S（TIME 无负语义） [ms] / clamp the negative value to T#0S, TIME has no negative semantics [ms]
    eErr := 16#0001_01F8;                 // 信息级：负秒已钳零，正常防御 / info level: negative seconds clamped to zero
    bError := FALSE;                      // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                       // 钳位值本身有效可用 / the clamped value itself is valid
    RETURN;                               // 钳位即出口，不进入换算 / clamping is the exit, no scaling
END_IF
IF fSec > DL_SEC_MAX THEN // 在 LREAL 域先比较，先算后判必溢出 [s] / compare in the LREAL domain first, scaling before comparing would overflow [s]
    FC_DL_LrealSecToTime := DL_TIME_MAX; // 饱和至 TIME 域上限 T#49D17H2M47S295MS [ms] / saturate to the TIME upper bound T#49D17H2M47S295MS [ms]
    eErr := 16#0001_01F9;                // 信息级：秒数超上限已饱和，正常防御 / info level: seconds exceeded the upper bound and saturated
    bError := FALSE;                     // 信息级不置故障 / info level never raises fault
    bValid := TRUE;                      // 饱和值本身有效可用 / the saturated value itself is valid
    RETURN;                              // 饱和即出口，不进入换算 / saturation is the exit, no scaling
END_IF

// 段 4｜域内换算委托转换（末段） / segment 4, in-domain scaling and delegated conversion (final)
FC_DL_LrealSecToTime := LREAL_TO_TIME(fSec * DL_MS_PER_SEC); // 域内先乘常量 1000.0 转毫秒，再委托内建 LREAL_TO_TIME [ms] / in-domain multiply by the constant 1000.0 then delegate to built-in LREAL_TO_TIME [ms]
eErr   := 0;     // 域内无错误 / in-domain, no error
bError := FALSE; // 信息级不置故障 / info level never raises fault
bValid := TRUE;  // 域内输出有效可用 / in-domain output is valid
END_FUNCTION
