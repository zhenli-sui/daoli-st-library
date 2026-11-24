(*
    FC_DL_TodDiffWrap —— 两 TOD 之差（跨零点为正）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（两个当日时刻的区间时长，跨零点折算）；
                委托平台内建 TOD_TO_DINT / DINT_TO_TIME 完成显式换算，本件不重实现时间算术内核；
                跨零点判定、单次折算、跨零点标志与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 班次工时、节拍间隔、夜间保温时段时长的高频口径：给两个当日时刻，
                求「从前者走到后者」的时长；后者小于前者即视为跨零点，按加一日折算，
                结果恒为非负。与 FC_DL_TodAddWrap 的加偏移语义互补。
                核心防御：① 差值后判定为负才加一日，且**只加一次**——判据是结构性的：
                   TOD 类型值域为 [0, 一日)，两值之差的模长必小于一日，故单次折算必然落域，
                   不需要循环也不需要取模（负数取余的三平台口径不一致，R11 纪律）；
                ② 本件五槽中信息 1 槽使用、故障 3 槽按规格预留禁用——域外输入在此件的
                   类型域上不可表达（TOD 值域由类型系统保证），故不设故障出口，
                   也不为「不存在的越界」虚构码位；
                ③ 跨零点事件用 bCrossMidnight 回告，HMI 可据此区分「同日间隔」与
                   「跨零点间隔」，否则 2 小时的结果看不出是凌晨还是傍晚来的；
                ④ 全程显式标准转换，禁隐式赋值。
                职责边界：时刻加偏移归 FC_DL_TodAddWrap；窗内判定归 FB_DL_TimeWindowCheck
                （它不提供原子差值）；本件只管两时刻的区间时长。
    编译门槛  : 主路径依赖平台内建 TOD_TO_DINT（毫秒口径）与 DINT_TO_TIME。
                三平台标准库均提供；结果上限 86399999 ms 恒落在 TIME 正域内，
                不存在 TIME 位型截断风险。
    错误码    : 16#0001_0422 跨零点区间（已按加一日折算，bCrossMidnight 可查）——信息级，值可用
                16#0001_0423 预留禁用（信息级，不得挪用）
                16#0001_0351 预留（故障级，不得挪用）
                16#0001_0352 预留禁用（故障级，不得挪用）
                16#0001_0353 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0422 用 / 16#0001_0423 预留 ｜ 16#0001_0351 预留 / 16#0001_0352 预留 / 16#0001_0353 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_TodDiffWrap : TIME
VAR_INPUT
    todEarlier       : TOD;                   // 区间起点时刻 [时刻]，有效域 00:00:00.000~23:59:59.999 / start of the interval [time of day]
    todLater         : TOD;                   // 区间终点时刻 [时刻]，小于起点即视为跨零点 / end of the interval [time of day], earlier than the start means a midnight crossing
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，本件无故障级出口，恒为 FALSE / error flag, always FALSE here as no fault exit exists
    bValid           : BOOL;                  // 返回值是否可用（本件恒为 TRUE）/ return usable, always TRUE here
    bCrossMidnight   : BOOL;                  // 区间跨零点判定 / the interval crosses midnight
END_VAR
VAR CONSTANT
    DL_TOD_DAY_MS    : DINT := 86400000;      // 当日毫秒数 [ms/日] / milliseconds per day [ms/day]
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 [ms] / signed zero constant [ms]
    DL_TIME_ZERO     : TIME := T#0s;          // 零时长，缺省返回 / zero duration returned by default
END_VAR
VAR
    nFrom            : DINT;                  // 起点时刻毫秒 [ms] / start instant in milliseconds [ms]
    nTo              : DINT;                  // 终点时刻毫秒 [ms] / end instant in milliseconds [ms]
    nDiff            : DINT;                  // 区间时长中间量，可为负 [ms] / interval duration intermediate, possibly negative [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TodDiffWrap := DL_TIME_ZERO;            // 缺省返回零时长 / default returns a zero duration
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 本件无故障级出口，恒 FALSE / no fault exit exists, always FALSE
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bCrossMidnight := FALSE;                      // 预置未跨零点 / preset no midnight crossing
nDiff := DL_DINT_ZERO;                        // 中间量清零 / clear the intermediate

// 段 2｜取值：两时刻各做一次显式标准转换 / segment 2, both instants are converted explicitly
nFrom := TOD_TO_DINT(todEarlier);             // 起点毫秒 [ms] / start instant in milliseconds [ms]
nTo := TOD_TO_DINT(todLater);                 // 终点毫秒 [ms] / end instant in milliseconds [ms]

// 段 3｜求差：模长必小于一日的结构性事实来自 TOD 类型值域 / segment 3, difference bounded by one day
nDiff := nTo - nFrom;                         // 有符号区间差 [ms] / signed interval difference [ms]

// 段 4｜跨零点单次折算（禁取模，只加一次）/ segment 4, single midnight conversion without any modulo
IF nDiff < DL_DINT_ZERO THEN
    nDiff := nDiff + DL_TOD_DAY_MS;           // 负差值加一日折算为正 [ms] / add one day so the value becomes positive [ms]
    bCrossMidnight := TRUE;                   // 标记跨零点 / flag the midnight crossing
    eErr := 16#0001_0422;                     // 信息级：跨零点区间已折算 / info level, the interval crossed midnight and was converted
END_IF

// 段 5｜发布结果 / segment 5, publish the result
FC_DL_TodDiffWrap := DINT_TO_TIME(nDiff);     // 毫秒 → 时长 [ms] / milliseconds back to a duration [ms]
bValid := TRUE;                               // 折算后恒落 TIME 正域 / always inside the positive TIME domain after the conversion
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
