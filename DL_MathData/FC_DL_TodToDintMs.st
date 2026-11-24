(*
    FC_DL_TodToDintMs —— TOD 到当日毫秒偏移防御转换
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeConv
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （接口语义由 IEC 61131-3 定义，内部委托平台内建 TOD_TO_TIME 与 TIME_TO_DINT，
                  外围统一错误码 / 钳位 / 双语文档；clean-room 重写，
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R17）
    ------------------------------------------------------------------
    功能说明  : 将 TOD（当日时刻）转换为当日 0 点起的毫秒偏移并作为返回值输出，
                内部委托标准转换链 TOD_TO_TIME 再 TIME_TO_DINT，不自行按小时/分/秒累加
                （自实现累加会把时区、闰秒、平台 TOD 精度差异一并写进业务代码）；
                结果越出 0 ~ 86399999 ms 时按方向钳位并置信息级 16#0001_01FA；
                钳位方向：下界 0 ms，上界 86399999 ms（24h − 1 ms）；
                纯值类型域无 NaN/±INF 态，故无故障级路径（三个故障槽预留）；
                交付门槛：本件因依赖 TOD_TO_TIME 链，须在 CODESYS / TwinCAT / InoProShop 三平台各编译验证一次。
    错误码    : 16#0001_01FA TOD 转换结果越出 0 ~ 86399999 ms，已按方向钳位——信息级，正常防御
                16#0001_01FB 预留禁用（信息级，不得挪用）
                16#0001_02E5 预留禁用（故障级，不得挪用）
                16#0001_02E6 预留禁用（故障级，不得挪用）
                16#0001_02E7 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R17）
*)
FUNCTION FC_DL_TodToDintMs : DINT
VAR_INPUT
    todIn : TOD; // 当日时刻，有效域 00:00:00 ~ 23:59:59.999 [ms since 00:00:00] / time of day, domain 00:00:00 .. 23:59:59.999 [ms since midnight]
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TOD_MAX_MS : DINT := 86399999; // 当日毫秒上界（24h − 1 ms） [ms] / day upper bound, 24h minus 1 ms [ms]
    DL_TOD_MIN_MS : DINT := 0;        // 当日毫秒下界 [ms] / day lower bound [ms]
END_VAR
VAR
    nMs : DINT; // 当日毫秒偏移中间结果 [ms] / intermediate day-millisecond offset [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TodToDintMs := DL_TOD_MIN_MS; // 故障缺省返回 0 ms（当日 0 点） [ms] / fault default 0 ms, midnight [ms]
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（本件无故障级路径） / preset no fault, no fault-level path here
bValid := FALSE; // 预置输出无效，通过域钳位段后置位 / preset invalid, set TRUE after the domain clamp segment

// 段 2｜标准转换链整备 / segment 2, standard conversion chain preparation
nMs := TIME_TO_DINT(TOD_TO_TIME(todIn)); // 标准链：TOD 先转 TIME，再转 DINT 毫秒，绝不自行按时分秒累加 [ms] / standard chain: TOD to TIME then to DINT milliseconds, never accumulate hours/minutes/seconds by hand [ms]

// 段 3｜当日毫秒域钳位（末段） / segment 3, day-millisecond domain clamp (final)
IF nMs < DL_TOD_MIN_MS THEN
    nMs := DL_TOD_MIN_MS; // 越下界钳 0 ms [ms] / clamp upward to 0 ms [ms]
    eErr := 16#0001_01FA; // 信息级：TOD 域外已钳位，正常防御 / info level: out of the TOD domain and clamped, normal defence
ELSIF nMs > DL_TOD_MAX_MS THEN
    nMs := DL_TOD_MAX_MS; // 越上界钳 86399999 ms（24h − 1 ms） [ms] / clamp downward to 86399999 ms, 24h minus 1 ms [ms]
    eErr := 16#0001_01FA; // 同一业务语义复用同一信息码，不另立码 / same business semantics reuses the same info id, no extra code
ELSE
    eErr := 0;            // 域内无错误 / in-domain, no error
END_IF
FC_DL_TodToDintMs := nMs; // 输出钳位后的当日毫秒偏移 [ms] / output the clamped day-millisecond offset [ms]
bError := FALSE;          // 信息级不置故障 / info level never raises fault
bValid := TRUE;           // 域内或钳位后输出均有效可用 / in-domain or clamped output is valid
END_FUNCTION
