(*
    FC_DL_DateAddDays —— DATE 加天数偏移
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（日期 + 天数 → 日期，可负偏移）；
                经天数路径委托平台内建 DATE_TO_DINT / DINT_TO_DATE 完成历法换算，
                本件不重实现历法内核；
                偏移钳位、溢出预判、双出口错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 保质期到日子、交期推算、下次保养日（今天 + 90 天）、点检周期回推（今天 − 30 天）
                这类现场每天都在用的算术。日历加法不能靠秒数硬加：夏令时与闰秒都不参与
                工业日期的语义，天数路径才是唯一稳定口径。
                核心防御：① 统一走天数路径（先 DATE_TO_DINT，加偏移后再 DINT_TO_DATE），
                   不做 DT 秒级加减——秒级加减在跨闰日的边界上会差一天，而这一天
                   对保质期判定的意义不用解释；
                ② 溢出用减法比较预判，不用加法后回查符号位：nWork > 上限 − nBase
                   这类判据在任何整数表示下都成立，禁「先加再判是否变号」的写法
                   （带符号溢出的回绕行为在平台上并不一定有保证）；
                ③ 偏移超 ±36500 天（±100 年）先钳位并发信息级：排程里出现 ±100 年
                   必然是单位错（毫秒当秒填），钳位后可算但不静默；
                ④ 结果早于纪元或超容器域一律返回纪元日并置 bValid = FALSE，不做饱和——
                   饱和会伪造日期（把越界算成 1970-01-01），台账上看不出异常；
                ⑤ 天数上界与 FC_DL_DateToDintDays / FC_DL_DintDaysToDate 用同一常量口径，
                   三件之间不会错位。
                职责边界：日期差值归 FC_DL_DateDiffDays；闰年原子归 FC_DL_LeapYearChk；
                纯天数双向转换归 FC_DL_DateToDintDays / FC_DL_DintDaysToDate。
    编译门槛  : 主路径依赖平台内建 DATE_TO_DINT / DINT_TO_DATE（天数口径），
                三平台标准库均提供。天数口径的平台差异见 FC_DL_DateToDintDays 的
                编译门槛段与 DL_DATE_DAYS_MAX 的保守取值；若实测口径不同只调该常量，
                本件的闸门顺序与出口不变。
    错误码    : 16#0001_042A 偏移超 ±36500 天（±100 年）已钳位——信息级，值可用但偏移已被限幅
                16#0001_042B 预留禁用（信息级，不得挪用）
                16#0001_035D 结果早于纪元——故障级，返回纪元日
                16#0001_035E 结果超 DATE 容器域——故障级，返回纪元日，不做饱和
                16#0001_035F 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_042A 用 / 16#0001_042B 预留 ｜ 16#0001_035D 用 / 16#0001_035E 用 / 16#0001_035F 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DateAddDays : DATE
VAR_INPUT
    dateIn           : DATE;                  // 基准日期 [日期]，有效域 1970-01-01 起 / base date [date], domain starts at 1970-01-01
    nDays            : DINT;                  // 天数偏移，可负 [日]，有效域 −36500~36500 / day offset, signed [day], valid domain −36500 to 36500
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
    bClamped         : BOOL;                  // 偏移超 ±36500 天已钳位 / the offset was clamped into the span limit
END_VAR
VAR CONSTANT
    DL_DAYS_SPAN_MAX : DINT := 36500;         // 正向偏移钳位，约 ±100 年 [日] / forward offset clamp, about one hundred years [day]
    DL_DAYS_SPAN_NEG_MAX : DINT := -36500;    // 负向偏移钳位 [日] / backward offset clamp [day]
    DL_DATE_DAYS_MIN : DINT := 0;             // 纪元日，天数下界 [日] / the epoch day, lower bound [day]
    DL_DATE_DAYS_MAX : DINT := 65535;         // 保守容器口径上限，无符号 16 位天数顶 [日] / conservative container top [day]
    DL_EPOCH_DATE_ZERO : DATE := DATE#1970-01-01; // 纪元起始日期，故障缺省返回 / the epoch date returned on faults
END_VAR
VAR
    nBase            : DINT;                  // 基准日期天数中间量 [日] / base date in days since the epoch [day]
    nWork            : DINT;                  // 偏移副本，钳位后参与加法 [日] / offset copy, used after the clamp [day]
    nOut             : DINT;                  // 结果天数中间量 [日] / result day count intermediate [day]
    nLimit           : DINT;                  // 可用余量的减法判据中间量 [日] / headroom intermediate used by the subtraction test [day]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DateAddDays := DL_EPOCH_DATE_ZERO;      // 故障缺省返回纪元日 / fault default returns the epoch date
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bClamped := FALSE;                            // 预置未钳位 / preset no clamp
nWork := nDays;                               // 取入参副本，绝不改动调用方数据 / copy the input, never modifies caller data
nOut := DL_DATE_DAYS_MIN;                     // 结果中间量清零 / clear the result intermediate

// 段 2｜偏移跨度量闸：超 ±100 年先钳位并如实登记（信息级）/ segment 2, span gate with an explicit info-level clamp
IF nWork > DL_DAYS_SPAN_MAX THEN
    nWork := DL_DAYS_SPAN_MAX;                // 正向钳位至 +36500 天 [日] / clamp to plus 36500 days [day]
    bClamped := TRUE;                         // 标记已钳位 / flag the clamp
    eErr := 16#0001_042A;                     // 信息级：偏移超跨度已钳位 / info level, the offset was clamped
ELSIF nWork < DL_DAYS_SPAN_NEG_MAX THEN
    nWork := DL_DAYS_SPAN_NEG_MAX;            // 负向钳位至 −36500 天 [日] / clamp to minus 36500 days [day]
    bClamped := TRUE;                         // 标记已钳位 / flag the clamp
    eErr := 16#0001_042A;                     // 信息级：偏移超跨度已钳位 / info level, the offset was clamped
END_IF

// 段 3｜基准日期域闸：基准本身必须在容器域内 / segment 3, base date domain gate
nBase := DATE_TO_DINT(dateIn);                // 日期 → 自纪元天数 [日] / date to days since the epoch [day]
IF nBase < DL_DATE_DAYS_MIN THEN
    eErr := 16#0001_035D;                     // 故障级：基准日期早于纪元 / fault level, the base date precedes the epoch
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_DateAddDays := DL_EPOCH_DATE_ZERO;  // 确定缺省值：纪元日 / deterministic default of the epoch date
    RETURN;                                   // 出口 / exit
END_IF
IF nBase > DL_DATE_DAYS_MAX THEN
    eErr := 16#0001_035E;                     // 故障级：基准日期超容器域 / fault level, the base date exceeds the container
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_DateAddDays := DL_EPOCH_DATE_ZERO;  // 确定缺省值：纪元日 / deterministic default of the epoch date
    RETURN;                                   // 出口 / exit
END_IF

// 段 4｜正向溢出预判：用「上限 − 基准」做减法比较，禁先加后判变号 / segment 4, forward overflow test by subtraction
IF nWork > DL_DATE_DAYS_MIN THEN
    nLimit := DL_DATE_DAYS_MAX - nBase;       // 剩余可用天数 [日] / remaining room in days [day]
    IF nWork > nLimit THEN
        eErr := 16#0001_035E;                 // 故障级：结果将超 DATE 容器域 / fault level, the result would exceed the container
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bValid := FALSE;                      // 返回值不可用 / flag the return as unusable
        FC_DL_DateAddDays := DL_EPOCH_DATE_ZERO; // 确定缺省值：纪元日，不伪造日期 / deterministic default, no fabricated date
        RETURN;                               // 出口 / exit
    END_IF
ELSIF nWork < DL_DATE_DAYS_MIN THEN
    // 段 5｜负向溢出预判：可用余额同为负数，比较方向不变 / segment 5, backward overflow test
    nLimit := DL_DATE_DAYS_MIN - nBase;       // 负向可用余额，负值 [日] / backward headroom, a negative value [day]
    IF nWork < nLimit THEN
        eErr := 16#0001_035D;                 // 故障级：结果将早于纪元 / fault level, the result would precede the epoch
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bValid := FALSE;                      // 返回值不可用 / flag the return as unusable
        FC_DL_DateAddDays := DL_EPOCH_DATE_ZERO; // 确定缺省值：纪元日 / deterministic default of the epoch date
        RETURN;                               // 出口 / exit
    END_IF
END_IF

// 段 6｜主体：溢出已排除，加法与内建还原均安全 / segment 6, the addition and the built-in are safe after the gates
nOut := nBase + nWork;                        // 结果天数 [日] / result day count [day]
FC_DL_DateAddDays := DINT_TO_DATE(nOut);      // 天数 → 日期 / days back to a date

// 段 7｜发布结果 / segment 7, publish the result
bValid := TRUE;                               // 域内结果可用 / the in-domain result is usable
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
