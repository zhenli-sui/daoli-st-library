(*
    FC_DL_TimeToLrealSec —— TIME 到 LREAL 秒防御转换
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeConv
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 TIME_TO_LREAL，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 TIME 值转换为 LREAL 秒数并作为返回值输出（节拍/速度/加速度算法的标准入口）；
                先委托平台内建 TIME_TO_LREAL 取毫秒数值，再除以常量 1000.0 得秒；
                除子为编译期常量 1000.0 恒非零，结构性满足除法前判除子非零红线；
                无上溢风险：TIME 域上限 4294967295 ms 远小于 2^53，LREAL 精确可表；
                负 TIME 照转不钳零（本件为观测语义，钳零会掩盖上游非法减法）并置信息级 16#0001_01F6；
                钳位方向：无钳位（仅记录负值，输出值与输入严格等价）。
    错误码    : 16#0001_01F6 负 TIME 输入（照转不钳零，仅记录）——信息级，正常防御
                16#0001_01F7 预留禁用（信息级，不得挪用）
                16#0001_02DF 预留禁用（故障级，不得挪用）
                16#0001_02E0 预留禁用（故障级，不得挪用）
                16#0001_02E1 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_TimeToLrealSec : LREAL
VAR_INPUT
    tIn : TIME; // 待转换时间值，有效域 0 ms ~ 4294967295 ms [ms] / time value to convert, domain 0 ms .. 4294967295 ms [ms]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_MS_PER_SEC : LREAL := 1000.0; // 毫秒/秒换算除子（编译期常量，恒非零） [ms/s] / ms-per-second divisor, compile-time constant, never zero [ms/s]
    DL_LREAL_ZERO : LREAL := 0.0;    // 返回值预置零（本件无故障路径，仅作预置约定） [s] / preset zero, no fault path in this component [s]
END_VAR
VAR
    fMsL : LREAL; // 毫秒数值（LREAL 承载） [ms] / millisecond value carried in LREAL [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeToLrealSec := DL_LREAL_ZERO; // 故障缺省预置 0.0 s（本件无故障级路径） [s] / preset 0.0 s, no fault-level path in this component [s]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过数值整备后置位 / preset invalid, set TRUE after value preparation

// 段 2｜毫秒数值整备与负值记录 / segment 2, millisecond preparation and negative value recording
fMsL := TIME_TO_LREAL(tIn); // 委托平台内建 TIME_TO_LREAL 取毫秒数值 [ms] / delegate to built-in TIME_TO_LREAL for the millisecond value [ms]
IF fMsL < 0.0 THEN
    eErr := 16#0001_01F6; // 信息级：负 TIME 照转不钳零，仅记录（钳零会掩盖上游非法减法） / info level: negative TIME passed through and recorded only, clamping would hide an illegal upstream subtraction
ELSE
    eErr := 0;            // 非负时间无错误 / non-negative time, no error
END_IF

// 段 3｜毫秒转秒（末段） / segment 3, milliseconds to seconds (final)
FC_DL_TimeToLrealSec := fMsL / DL_MS_PER_SEC; // 除子为编译期常量 1000.0，恒非零 [s] / divisor is the compile-time constant 1000.0, never zero [s]
bError := FALSE;                              // 信息级不置故障 / info level never raises fault
bValid := TRUE;                               // 域内输出有效可用（负值亦有效，仅附信息码） / output is valid in-domain, including recorded negatives
END_FUNCTION
