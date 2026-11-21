(*
    FC_DL_TimeAddSat —— TIME 加法溢出饱和防御包装
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
    功能说明  : TIME 加法：返回 tA + tB，TIME 算术委托 `+` 与 `-` 运算符，
                不重实现任何时间运算内核；
                溢出预判采用减法比较口径（规避「先算后判」红线）：
                tA > DL_TIME_MAX - tB 时判加法将溢出，直接饱和输出 DL_TIME_MAX，
                置信息级 16#0001_01E0（bError=FALSE、bValid=TRUE）；
                预判安全性：TIME 为 32 位无符号容器，tB 恒 ≤ DL_TIME_MAX，
                故 DL_TIME_MAX - tB 恒 ≥ T#0S，减法比较本身不下溢；
                钳位方向：仅上界单侧饱和至 DL_TIME_MAX（T#49D17H2M47S295MS）；
                常量字面量说明：DL_TIME_MAX 采用 D/H/M/S/MS 组合字面量（三大平台均支持），
                等价于 ms 口径 4294967295 ms，若目标平台不支持组合字面量可改为 T#4294967295MS。
    错误码    : 16#0001_01E0 加法结果超 TIME 上限，已饱和至 DL_TIME_MAX——信息级，正常防御
                16#0001_01E1 预留禁用（信息级，不得挪用）
                16#0001_02BE 预留禁用（故障级，不得挪用）
                16#0001_02BF 预留禁用（故障级，不得挪用）
                16#0001_02C0 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_TimeAddSat : TIME
VAR_INPUT
    tA : TIME; // 加数 A [ms] / addend A
    tB : TIME; // 加数 B [ms] / addend B
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_MAX   : TIME := T#49D17H2M47S295MS; // 32 位 TIME 容器上限，等价 4294967295 ms [ms] / 32-bit TIME container ceiling, equals 4294967295 ms
    DL_TIME_ZERO  : TIME := T#0S;               // TIME 零值 [ms] / TIME zero value
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeAddSat := DL_TIME_ZERO; // 故障缺省返回 T#0S [ms] / fault default returns T#0S
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过溢出预判后置位 / preset invalid, set TRUE after overflow pre-check

// 段 2｜减法比较溢出预判与主体加法（末段） / segment 2, subtract-compare overflow pre-check and main addition (final)
IF tA > DL_TIME_MAX - tB THEN
    FC_DL_TimeAddSat := DL_TIME_MAX; // 溢出预判命中，饱和至上限（tB ≤ DL_TIME_MAX 恒成立，预判减法不下溢） / overflow pre-check hit, saturate to ceiling (tB never exceeds DL_TIME_MAX, pre-check subtraction cannot underflow)
    eErr := 16#0001_01E0;            // 信息级：加法溢出已饱和 / info level: addition overflow, saturated
ELSE
    FC_DL_TimeAddSat := tA + tB; // 预判通过，域内委托 `+` 运算符加法 / pre-check passed, in-domain addition via `+` operator
    eErr := 0; // 域内无错误 / in-domain, no error
END_IF
bError := FALSE; // 信息级饱和不置故障 / info-level saturation never raises fault
bValid := TRUE;  // 域内或饱和输出均有效可用 / in-domain or saturated output is valid
END_FUNCTION
