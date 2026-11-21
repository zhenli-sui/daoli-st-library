(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WeekOfYearCalc
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 日历计算（ISO-8601 周序号）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；全程整数运算，零浮点、零标准库依赖
 * 功能描述 (Function)   : 给定公历年月日，按 ISO-8601 规则计算「ISO 周年 + ISO
 *                         周序号（1 到 53）+ 周内日（周一 = 1，周日 = 7）」，
 *                         并给出该 ISO 周年是否为长年（含第 53 周）。用于周排产、
 *                         周窗判定、周报闸门、按周统计的 OEE 与班次报表。
 * 与既有件边界 (Boundary): FC_DL_DayOfWeekCalc 给星期几；本件给周序号与 ISO
 *                         周年（含跨年归属：12 月 31 日可能属次年第 1 周，1 月
 *                         1 日可能属上年第 52 或 53 周）；FB_DL_TimeWindowCheck
 *                         与 FB_DL_MonthWindowCheck 是时间窗判定块，粒度不同，
 *                         不重叠。本件不调用任何既有件（泳道零互相依赖）。
 * 设计要点 (Key notes)  : ① 周四归属法：一个 ISO 周归属于其周四所在的年份，故
 *                           先求当日周内日，再推算本周周四的年内序日；
 *                         ② 星期几用 Zeller 同余的整数重排式，避免闰年 1 月
 *                           2 月的偏置陷阱（把 1 月 2 月折算为上一年的 13 月
 *                           14 月是 Zeller 原式的关键约定，不可省）；
 *                         ③ 长年判据：ISO 周年的 1 月 1 日为周四，或该年为闰年
 *                           且 1 月 1 日为周三，则该 ISO 年含第 53 周；
 *                         ④ 全程除法除数均为常量（4 / 100 / 400 / 7 / 5），
 *                           且被除数恒为非负，不触发除零，也不依赖负数截断方向。
 * 规格偏离登记 (Deviations):
 *   规格 1.2 节给出的速算式 nDow0 = (nDoy + 5 + y + y/4 - y/100 + y/400) MOD 7
 *   与本件验收向量 V1（2026-01-01 须为周四）互相矛盾：该式对 2026-01-01 得 3，
 *   且对闰年 1 月 2 月未做「上一年的 13 月 14 月」折算，会整体偏一天。本实现
 *   改用等价但无闰年偏置的 Zeller 重排式，并逐条验证 V1 至 V5 全部命中，
 *   按 R11 留档。
 * 开源溯源 (Origin)     : lgf-datetime。参考 LGF（Libre Graphical Framework）
 *                         公开函数库「Date and Timer」分类中周数计算类函数的
 *                         功能分类与参数域（年 / 月 / 日 三段输入，年 + 周 +
 *                         周内日 三段输出），只借分类、参数域与命名习惯，
 *                         算法与实现 100% 自有 clean-room，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 故障码表 (Error codes):
 *   16#0001_0116【信息级】年份越界（须 1970 到 2099），输出全 0，返回 FALSE
 *   16#0001_0117【信息级】月份或日非法（含非闰年 2 月 29 日），输出全 0，返回 FALSE
 * 验收向量 (Acceptance) :
 *   V1 2026-01-01 → 2026 年第 1 周，周内日 4（周四）
 *   V2 2021-01-01 → 2020 年第 53 周，周内日 5（经典跨年例）
 *   V3 2027-01-01 → 2026 年第 53 周，且 2026 长年标志为 TRUE（自洽性）
 *   V4 2026-02-29 → 非法，码 0117；2024-02-29 → 合法
 *   V5 2026-11-15 → 周内日 7（周日）
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 域校验先判后算 + 除法除数恒为常量
 *                         R5 全变量中英双语同行注释 ｜ R6 CASE 含 ELSE 兜底（月份
 *                         查表用 CASE，非法月份走 ELSE）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · Level 0 日历族回补）
 *============================================================================*)

FUNCTION FC_DL_WeekOfYearCalc : BOOL
VAR_INPUT
    nYear  : INT := 2026;   // 公历年，有效域 1970 到 2099 [年] / Calendar year, valid 1970 to 2099
    nMonth : INT := 1;      // 公历月，有效域 1 到 12 [月] / Calendar month, valid 1 to 12
    nDay   : INT := 1;      // 公历日，有效域 1 到该月天数 [日] / Day of month, valid 1 to month length
END_VAR
VAR_OUTPUT
    nIsoYear  : INT;        // ISO 周年，可能不等于 nYear（跨年归属所致）[年] / ISO week-numbering year, may differ from nYear
    nIsoWeek  : INT;        // ISO 周序号，1 到 53 [周] / ISO week number, 1 to 53
    nIsoDow   : INT;        // ISO 周内日，周一 = 1，周日 = 7 [1 到 7] / ISO day of week, Monday = 1, Sunday = 7
    nWeek53En : BOOL;       // 该 ISO 周年是否含第 53 周（长年判据）[布尔] / TRUE if that ISO year has week 53
    uErrorId  : UDINT;      // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    bLeapYear   : BOOL;     // 输入年是否闰年 [-] / TRUE if the input year is a leap year
    bLeapIso    : BOOL;     // ISO 周年是否闰年（长年判定用）[-] / TRUE if the ISO year is a leap year
    bPending    : BOOL;     // 周号待定标志（周四落到上一年时为 TRUE）[-] / TRUE when the week number must be resolved after the long-year test
    nMonthLen   : INT;      // 当月天数，随闰年调整 [日] / Length of the input month in days
    nDaysBefore : INT;      // 当月起点的年内序日偏移（不含当月 1 日）[日] / Day offset of the month start
    nDoy        : INT;      // 当日的年内序日，1 起 [日] / Day of year, 1-based
    nDaysInYear : INT;      // 输入年的总天数，365 或 366 [日] / Total days of the input year
    nThursday   : INT;      // 本周周四的年内序日，可能小于 1 或超过当年天数 [日] / Day of year of the Thursday of this week
    nZYear      : INT;      // Zeller 折算用年份（1 月 2 月取上一年）[年] / Year used by the Zeller term, shifted for January and February
    nZMonth     : INT;      // Zeller 折算用月份（1 月 2 月取 13 月 14 月）[月] / Month used by the Zeller term, shifted to 13 and 14
    nZCentury   : INT;      // Zeller 世纪项 J = 年 除以 100 [世纪] / Zeller century term J
    nZYearInC   : INT;      // Zeller 年内项 K = 年 对 100 取模 [年] / Zeller year-in-century term K
    nZMonthTerm : INT;      // Zeller 月份项，floor(13 乘 (月 加 1) 除以 5) [-] / Zeller month term
    nZSum       : INT;      // Zeller 求和中间量，域内不溢出 [-] / Zeller sum temporaries
    nZWeekday   : INT;      // Zeller 结果，0 = 周六，1 = 周日，2 = 周一，6 = 周五 [-] / Zeller weekday, 0 = Saturday
    nJan1IsoDow : INT;      // ISO 周年 1 月 1 日的 ISO 周内日 [1 到 7] / ISO weekday of January 1st of the ISO year
END_VAR
VAR CONSTANT
    DL_YEAR_MIN  : INT := 1970;   // 可算年下限 [年] / Lowest computable year
    DL_YEAR_MAX  : INT := 2099;   // 可算年上限 [年] / Highest computable year
    DL_WEEK_DAYS : INT := 7;      // 每周天数 [日] / Days per week
    DL_THU_KEY   : INT := 4;      // 周四的 ISO 周内日编号，周四归属法基准 [-] / ISO weekday index of Thursday
    DL_MONTH_MIN : INT := 1;      // 月份下限 [月] / Lowest month index
    DL_MONTH_MAX : INT := 12;     // 月份上限 [月] / Highest month index
    DL_DAY_MIN   : INT := 1;      // 日起点，0 与负数一律非法 [日] / Lowest day index
    DL_DAYS_COMMON : INT := 365;  // 平年天数 [日] / Days in a common year
    DL_DAYS_LEAP   : INT := 366;  // 闰年天数 [日] / Days in a leap year
    DL_WEEK_LAST   : INT := 52;   // 短年最后一周号 [周] / Last week number of a short ISO year
    DL_WEEK_LAST53 : INT := 53;   // 长年最后一周号 [周] / Last week number of a long ISO year
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出与返回值预置：任何早退路径下输出必须为确定的 0
 *      Pre-set outputs and return value: deterministic zeros on early exit
 *-----------------------------------------------------------------------------*)
FC_DL_WeekOfYearCalc := FALSE;
nIsoYear  := 0;
nIsoWeek  := 0;
nIsoDow   := 0;
nWeek53En := FALSE;
uErrorId  := 16#0000_0000;
bPending  := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜年份域校验（边界 B1）：早退，绝不带着非法年进入后续整除
 *      Year bounds check (boundary B1): early return before any integer division
 *-----------------------------------------------------------------------------*)
IF (nYear < DL_YEAR_MIN) OR (nYear > DL_YEAR_MAX) THEN
    uErrorId := 16#0001_0116;   // 年份越界，输出全 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜闰年判定：四年一闰、百年不闰、四百年再闰
 *      Leap year test: divisible by 4, not by 100, unless divisible by 400
 *-----------------------------------------------------------------------------*)
IF ((nYear MOD 4) = 0) AND (((nYear MOD 100) <> 0) OR ((nYear MOD 400) = 0)) THEN
    bLeapYear   := TRUE;
    nDaysInYear := DL_DAYS_LEAP;
ELSE
    bLeapYear   := FALSE;
    nDaysInYear := DL_DAYS_COMMON;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜月份天数与月首偏移查表（边界 B2）：CASE 带 ELSE 兜底，非法月份直接拒绝
 *      Month length and month-start offset lookup with an ELSE fallback branch
 *      用 CASE 而非数组常量，是为了让非法月份在 ELSE 里被显式拦下
 *-----------------------------------------------------------------------------*)
CASE nMonth OF
    1:
        nMonthLen   := 31;
        nDaysBefore := 0;
    2:
        nDaysBefore := 31;
        IF bLeapYear THEN
            nMonthLen := 29;     // 闰年 2 月 29 天
        ELSE
            nMonthLen := 28;     // 平年 2 月 28 天
        END_IF
    3:
        nMonthLen   := 31;
        nDaysBefore := 59;
        IF bLeapYear THEN
            nDaysBefore := 60;   // 闰年 3 月前多一天
        END_IF
    4:
        nMonthLen   := 30;
        nDaysBefore := 90;
        IF bLeapYear THEN
            nDaysBefore := 91;
        END_IF
    5:
        nMonthLen   := 31;
        nDaysBefore := 120;
        IF bLeapYear THEN
            nDaysBefore := 121;
        END_IF
    6:
        nMonthLen   := 30;
        nDaysBefore := 151;
        IF bLeapYear THEN
            nDaysBefore := 152;
        END_IF
    7:
        nMonthLen   := 31;
        nDaysBefore := 181;
        IF bLeapYear THEN
            nDaysBefore := 182;
        END_IF
    8:
        nMonthLen   := 31;
        nDaysBefore := 212;
        IF bLeapYear THEN
            nDaysBefore := 213;
        END_IF
    9:
        nMonthLen   := 30;
        nDaysBefore := 243;
        IF bLeapYear THEN
            nDaysBefore := 244;
        END_IF
    10:
        nMonthLen   := 31;
        nDaysBefore := 273;
        IF bLeapYear THEN
            nDaysBefore := 274;
        END_IF
    11:
        nMonthLen   := 30;
        nDaysBefore := 304;
        IF bLeapYear THEN
            nDaysBefore := 305;
        END_IF
    12:
        nMonthLen   := 31;
        nDaysBefore := 334;
        IF bLeapYear THEN
            nDaysBefore := 335;
        END_IF
    ELSE
        nMonthLen   := 0;        // 非法月份：不做任何推算
        nDaysBefore := 0;
        uErrorId    := 16#0001_0117;
        RETURN;
END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜日期域校验（边界 B3）：日必须落在 1 到当月天数之间
 *      Day bounds check (boundary B3): day must be within the month length
 *-----------------------------------------------------------------------------*)
IF (nDay < DL_DAY_MIN) OR (nDay > nMonthLen) THEN
    uErrorId := 16#0001_0117;   // 日非法（含平年 2 月 29 日）
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜年内序日：月首偏移加当日，1 起
 *      Day of year: month-start offset plus the day, 1-based
 *-----------------------------------------------------------------------------*)
nDoy := nDaysBefore + nDay;

(*------------------------------------------------------------------------------
 * 段 7｜星期几（Zeller 同余重排）：1 月 2 月折算为上年的 13 月 14 月
 *      Weekday via a Zeller rearrangement: January and February shift to 13 and 14
 *      结果 0 = 周六，1 = 周日，2 = 周一，3 = 周二，4 = 周三，5 = 周四，6 = 周五
 *      再折算为 ISO 周内日：周一 1，周日 7，公式为 ((h 加 5) 对 7 取模) 加 1
 *-----------------------------------------------------------------------------*)
IF nMonth <= 2 THEN
    nZYear  := nYear - 1;       // 1 月 2 月归属上一年
    nZMonth := nMonth + 12;     // 1 月 改为 13 月，2 月 改为 14 月
ELSE
    nZYear  := nYear;
    nZMonth := nMonth;
END_IF

nZCentury   := nZYear / 100;                          // 世纪项 J
nZYearInC   := nZYear MOD 100;                        // 年内项 K
nZMonthTerm := (13 * (nZMonth + 1)) / 5;              // 月份项，整除向下取整
nZSum       := nDay + nZMonthTerm + nZYearInC
               + (nZYearInC / 4) + (nZCentury / 4) + (5 * nZCentury);

nZWeekday := nZSum MOD DL_WEEK_DAYS;                  // 0 = 周六 起算
nIsoDow   := ((nZWeekday + 5) MOD DL_WEEK_DAYS) + 1;  // 折算为 ISO 周内日

(*------------------------------------------------------------------------------
 * 段 8｜周四归属法：本周周四落在哪一年，本周就归属哪一年
 *      Thursday-ownership rule: the ISO year is the year of this week's Thursday
 *-----------------------------------------------------------------------------*)
nThursday := nDoy + (DL_THU_KEY - nIsoDow);   // 本周周四的年内序日，可为 0 或超过当年天数

IF nThursday < 1 THEN
    nIsoYear := nYear - 1;                    // 落在上一年：属上一年最后一周
    nIsoWeek := 0;                            // 周号待定（52 或 53），段 10 收口
    bPending := TRUE;
ELSIF nThursday > nDaysInYear THEN
    nIsoYear := nYear + 1;                    // 落在次年：属次年第 1 周
    nIsoWeek := 1;
ELSE
    nIsoYear := nYear;                        // 落在本年：正常整除求周号
    nIsoWeek := ((nThursday - 1) / DL_WEEK_DAYS) + 1;
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜长年判定：ISO 周年 1 月 1 日为周四，或闰年且 1 月 1 日为周三
 *      Long-year test: January 1st is a Thursday, or a leap year starting on Wednesday
 *      长年含第 53 周；短年至第 52 周
 *-----------------------------------------------------------------------------*)
IF ((nIsoYear MOD 4) = 0) AND (((nIsoYear MOD 100) <> 0) OR ((nIsoYear MOD 400) = 0)) THEN
    bLeapIso := TRUE;
ELSE
    bLeapIso := FALSE;
END_IF

(* 复用同一套 Zeller 重排式，仅把入参固定为 ISO 周年的 1 月 1 日 *)
nZYear      := nIsoYear - 1;                    // 1 月 归属上一年
nZCentury   := nZYear / 100;
nZYearInC   := nZYear MOD 100;
nZMonthTerm := (13 * 14) / 5;                   // 14 月 的月份项，常量 36
nZSum       := 1 + nZMonthTerm + nZYearInC
               + (nZYearInC / 4) + (nZCentury / 4) + (5 * nZCentury);
nZWeekday   := nZSum MOD DL_WEEK_DAYS;
nJan1IsoDow := ((nZWeekday + 5) MOD DL_WEEK_DAYS) + 1;

IF (nJan1IsoDow = DL_THU_KEY) OR (bLeapIso AND (nJan1IsoDow = (DL_THU_KEY - 1))) THEN
    nWeek53En := TRUE;                          // 长年，含第 53 周
ELSE
    nWeek53En := FALSE;                         // 短年，最后一周为第 52 周
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜跨年周号收口：周四落上一年时，按上一年是长年还是短年取 53 或 52
 *      Pending week resolution: 53 for a long ISO year, 52 for a short one
 *-----------------------------------------------------------------------------*)
IF bPending THEN
    IF nWeek53En THEN
        nIsoWeek := DL_WEEK_LAST53;
    ELSE
        nIsoWeek := DL_WEEK_LAST;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜返回值收口：三段输出均已赋值，标记计算成功
 *      Close-out: all three outputs assigned, flag success
 *-----------------------------------------------------------------------------*)
FC_DL_WeekOfYearCalc := TRUE;
END_FUNCTION
