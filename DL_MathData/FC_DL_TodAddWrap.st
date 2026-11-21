(*
    FC_DL_TodAddWrap —— TOD 加 TIME 偏移的午夜回绕加法
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（TOD + TIME → TOD，跨零点回绕）；
                委托平台内建 TOD_TO_DINT / TIME_TO_DINT / DINT_TO_TOD 完成显式换算，
                本件不重实现时间算术内核；
                偏移模长闸、回绕归一、回绕圈数回告、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 排程偏移、班次推算、延时启动时刻这类场景要把当日时刻加/减一段时间，
                结果必须落在同一日的 TOD 域内（跨零点即回绕）。与 DINT 毫秒加法件的
                本质区别是：TOD 域是环形的，回绕不是溢出而是正常语义。
                核心防御：① 全程显式标准转换（TOD_TO_DINT / TIME_TO_DINT），禁隐式赋值，
                   时间位型在不同平台的隐式转换口径不一致；
                ② 回绕归一**禁用取模**：负数取余在三种平台上分别可能是截断、向下取整或
                   实现未定义（R11 RolloverCounter 纪律），本件改条件加减；
                ③ 单次条件加减即可覆盖全域，条件是结构性成立的：段 2 已把偏移模长收到
                   一日以内、段 3 已把基准时刻收到 [0, 一日)，故 nSum 必落在
                   (−一日, 2×一日) 的开区间内，一次加或减必然落域，无需循环；
                ④ 偏移模长 ≥ 一日直接升故障级 034E：排程偏移不存在跨日以上的语义，
                   宁报不用——回绕圈数虽可算，但调用方拿到的多半不是他要的东西；
                ⑤ 回绕发生即置 bWrapped 与带符号的 nWrapCircles，方向可查；
                ⑥ 归一后再断言一次落域（034F），防平台时间位型异常。
                职责边界：两 TOD 之差（跨零点为正）归 FC_DL_TodDiffWrap；
                DINT 毫秒 → TOD 的纯转换归 FC_DL_DintMsToTod；本件只管带偏移的回绕加法。
    编译门槛  : 主路径依赖平台内建 TOD_TO_DINT（TOD 毫秒口径）、TIME_TO_DINT（TIME 毫秒口径）、
                DINT_TO_TOD。三平台标准库均提供；若某平台 TOD 以 32 位毫秒承载而 TIME 以
                64 位承载，段 3 的落域断言会拦下 TIME_TO_DINT 的高位截断，不会静默出错。
    错误码    : 16#0001_0420 发生午夜回绕（bWrapped 与 nWrapCircles 可查）——信息级，值可用
                16#0001_0421 预留禁用（信息级，不得挪用）
                16#0001_034E 偏移模长超一日，超出本件收窄域——故障级，返回 TOD 零点
                16#0001_034F 合成路径中间量非域（基准时刻或归一后结果越界）——故障级，返回 TOD 零点
                16#0001_0350 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0420 用 / 16#0001_0421 预留 ｜ 16#0001_034E 用 / 16#0001_034F 用 / 16#0001_0350 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_TodAddWrap : TOD
VAR_INPUT
    todIn            : TOD;                   // 当日基准时刻 [时刻]，有效域 00:00:00.000~23:59:59.999 / base time of day [time of day], valid domain 00:00:00.000 to 23:59:59.999
    tOffset          : TIME;                  // 时刻偏移，可正可负 [ms]，本件收窄到模长 < 一日 / offset, signed [ms], narrowed to less than one day
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bWrapped         : BOOL;                  // 本拍发生午夜回绕 / a midnight wrap happened in this cycle
    nWrapCircles     : INT;                   // 回绕圈数，正向 +1、负向 −1，未回绕为 0 [圈] / wrap circles, +1 forward, −1 backward, 0 when no wrap [circle]
END_VAR
VAR CONSTANT
    DL_TOD_DAY_MS    : DINT := 86400000;      // 当日毫秒数 [ms/日] / milliseconds per day [ms/day]
    DL_TOD_DAY_NEG_MS : DINT := -86400000;    // 当日毫秒数的负值，负向闸门用 [ms/日] / negative milliseconds per day used by the backward gate [ms/day]
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 [ms] / signed zero constant [ms]
    DL_WRAP_POS      : INT := 1;              // 正向回绕圈数 [圈] / positive wrap circle [circle]
    DL_WRAP_NEG      : INT := -1;             // 负向回绕圈数 [圈] / negative wrap circle [circle]
    DL_WRAP_NONE     : INT := 0;              // 未回绕时的圈数 [圈] / the circle count when nothing wrapped [circle]
    DL_TOD_ZERO      : TOD := TOD#00:00:00;   // 故障缺省返回的当日零点 / the midnight instant returned on faults
END_VAR
VAR
    nBase            : DINT;                  // 基准时刻毫秒中间量 [ms] / base time of day in milliseconds [ms]
    nOff             : DINT;                  // 偏移毫秒中间量 [ms] / offset in milliseconds [ms]
    nSum             : DINT;                  // 求和与归一中间量 [ms] / sum and normalisation intermediate [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TodAddWrap := DL_TOD_ZERO;              // 故障缺省返回当日零点 / fault default returns midnight
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bWrapped := FALSE;                            // 预置未回绕 / preset no wrap
nWrapCircles := DL_WRAP_NONE;                 // 预置回绕圈数 0 [圈] / preset zero wrap circles [circle]
nSum := DL_DINT_ZERO;                         // 归一中间量清零 / clear the normalisation intermediate

// 段 2｜偏移模长闸：跨日以上的偏移不在本件语义内，先判后算 / segment 2, offset magnitude gate
nOff := TIME_TO_DINT(tOffset);                // TIME → 毫秒，显式标准转换 [ms] / explicit standard conversion from TIME to milliseconds [ms]
IF (nOff >= DL_TOD_DAY_MS) OR (nOff <= DL_TOD_DAY_NEG_MS) THEN
    eErr := 16#0001_034E;                     // 故障级：偏移模长超一日 / fault level, the offset magnitude reaches one day
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_TodAddWrap := DL_TOD_ZERO;          // 确定缺省值：当日零点 / deterministic default of midnight
    RETURN;                                   // 出口，不触碰时间合成 / exit, no time synthesis happens
END_IF

// 段 3｜基准时刻域闸：TOD 必须落在 [0, 一日) / segment 3, base time domain gate
nBase := TOD_TO_DINT(todIn);                  // TOD → 毫秒，显式标准转换 [ms] / explicit standard conversion from TOD to milliseconds [ms]
IF (nBase < DL_DINT_ZERO) OR (nBase >= DL_TOD_DAY_MS) THEN
    eErr := 16#0001_034F;                     // 故障级：合成路径中间量非域 / fault level, an intermediate left its domain
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_TodAddWrap := DL_TOD_ZERO;          // 确定缺省值：当日零点 / deterministic default of midnight
    RETURN;                                   // 出口 / exit
END_IF

// 段 4｜求和：两操作数均已收窄，DINT 加法结构性不溢出 / segment 4, summation, structurally overflow free
nSum := nBase + nOff;                         // 基准毫秒 + 偏移毫秒 [ms] / base milliseconds plus offset milliseconds [ms]

// 段 5｜回绕归一：条件加减，禁用取模（R11 纪律）/ segment 5, wrap normalisation by conditional add and subtract
IF nSum >= DL_TOD_DAY_MS THEN
    nSum := nSum - DL_TOD_DAY_MS;             // 正向回绕减一日 [ms] / forward wrap, subtract one day [ms]
    nWrapCircles := DL_WRAP_POS;              // 圈数 +1 [圈] / one forward circle [circle]
    bWrapped := TRUE;                         // 标记回绕 / flag the wrap
    eErr := 16#0001_0420;                     // 信息级：发生午夜回绕 / info level, a midnight wrap happened
ELSIF nSum < DL_DINT_ZERO THEN
    nSum := nSum + DL_TOD_DAY_MS;             // 负向回绕加一日 [ms] / backward wrap, add one day [ms]
    nWrapCircles := DL_WRAP_NEG;              // 圈数 −1 [圈] / one backward circle [circle]
    bWrapped := TRUE;                         // 标记回绕 / flag the wrap
    eErr := 16#0001_0420;                     // 信息级：发生午夜回绕 / info level, a midnight wrap happened
END_IF

// 段 6｜归一后落域断言（双保险，防平台时间位型异常）/ segment 6, post-normalisation domain assertion
IF (nSum < DL_DINT_ZERO) OR (nSum >= DL_TOD_DAY_MS) THEN
    eErr := 16#0001_034F;                     // 故障级：归一后仍越界，平台时间位型异常 / fault level, still out of domain after normalisation
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_TodAddWrap := DL_TOD_ZERO;          // 确定缺省值：当日零点 / deterministic default of midnight
    RETURN;                                   // 出口 / exit
END_IF

// 段 7｜发布结果 / segment 7, publish the result
FC_DL_TodAddWrap := DINT_TO_TOD(nSum);        // 毫秒 → 当日时刻 [时刻] / milliseconds back to a time of day [time of day]
bValid := TRUE;                               // 域内与回绕均可用 / usable in domain and after a wrap
bError := FALSE;                              // 信息级不置故障 / info level never raises a fault
END_FUNCTION
