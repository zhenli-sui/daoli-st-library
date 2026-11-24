(*==============================================================================
 * 组件名称 : FC_DL_CalIsoWeekNo ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : ISO 8601 周号 —— 周一起算，含 1 月 4 日的那一周为第 1 周。核心式
 *            week = (年内序号 − ISO 星期 + 10) DIV 7。跨年归属单独处理：算出 0 即属
 *            上年末周，算出超过当年周数即属次年 W1，并用出参 nWeekYear 标明归属年。
 * 契约     : 返回周号 1~53，nWeekYear 为归属年；nYear < 1583、月份或日越界时返回 -1、
 *            bError := TRUE、nWeekYear := 0。纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 三层域闸、取余操作数恒非负、除数为常量 7
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 53 周年判据按 ISO 官方口径取「1 月 1 日为周四」或「闰年且 1 月 1 日为周三」；
 *            该两式与「12 月 31 日落在第 53 周」等价，本件用前者以便直接复用 1 月 1 日序数。
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 6/9）
 *============================================================================*)
FUNCTION FC_DL_CalIsoWeekNo : DINT
VAR_INPUT
    nYear      : DINT;  // 公历年，域闸 1583 及以上 [年] / Gregorian year, domain starts at 1583 [year]
    nMonth     : DINT;  // 月份 1~12 [月] / month from one to twelve [month]
    nDay       : DINT;  // 日 1~当月天数 [天] / day from one to the month length [day]
END_VAR
VAR_OUTPUT
    eErr       : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError     : BOOL;  // 日期非法或域外为真 / TRUE when the date is illegal or out of domain
    bValid     : BOOL;  // 结果可用标志 / result usable flag
    nWeekYear  : DINT;  // 周号归属年，故障时 0 [年] / year owning the ISO week, zero on fault [year]
END_VAR
VAR CONSTANT
    DL_GREG_START : DINT := 1583;   // 格里高利历起点年 [年] / first Gregorian year [year]
    DL_MONTH_MIN  : DINT := 1;      // 月份与日的下界 [月] / lower bound of the month and the day [month]
    DL_MONTH_MAX  : DINT := 12;     // 月份上界 [月] / upper month bound [month]
    DL_DAYS_COMMON : DINT := 365;   // 平年天数 [天] / days in a common year [day]
    DL_DAYS_FEB   : DINT := 28;     // 平年 2 月天数 [天] / February days in a common year [day]
    DL_DAYS_30    : DINT := 30;     // 小月天数 [天] / days in a short month [day]
    DL_DAYS_31    : DINT := 31;     // 大月天数 [天] / days in a long month [day]
    DL_STEP4      : DINT := 4;      // 闰年基本步长 [年] / base leap step [year]
    DL_STEP100    : DINT := 100;    // 世纪基数 [年] / century radix [year]
    DL_STEP400    : DINT := 400;    // 四世纪基数 [年] / four century radix [year]
    DL_WEEK_MOD   : DINT := 7;      // 星期与周号的基数 [天] / weekday and week radix [day]
    DL_WEEK_MIN   : DINT := 1;      // 周号下界 [周] / lower bound of the week number [week]
    DL_WEEK_BASE  : DINT := 52;     // 每年基础周数，53 周为特例 [周] / base weeks per year, fifty three is the exception [week]
    DL_WEEK_OFF   : DINT := 10;     // 周号式的固定偏移 [天] / fixed offset of the week formula [day]
    DL_JAN1_DOW53A : DINT := 4;     // 1 月 1 日周四 → 53 周 [星期序号] / Thursday first of January gives fifty three weeks
    DL_JAN1_DOW53B : DINT := 3;     // 闰年 1 月 1 日周三 → 53 周 [星期序号] / Wednesday first of January in a leap year gives fifty three weeks
    DL_ZERO       : DINT := 0;      // 整数零哨兵 [无量纲] / integer zero sentinel [dimensionless]
END_VAR
VAR
    bLeap      : BOOL;  // 当年是否闰年 / whether the year is a leap year
    bLeapPrev  : BOOL;  // 上一年是否闰年 / whether the previous year is a leap year
    nDaysInMon : DINT;  // 当月实际天数 [天] / actual length of the month [day]
    nDaysYear  : DINT;  // 当年总天数 365 或 366 [天] / total days of the year [day]
    nDaysPrev  : DINT;  // 上年总天数 365 或 366 [天] / total days of the previous year [day]
    nA         : DINT;  // 月份压缩偏置 0 或 1 / month compression offset, zero or one
    nY2        : DINT;  // 儒略式内的世纪内年份 / shifted year inside the Julian formula
    nM2        : DINT;  // 儒略式内的三月基月份 / March based month inside the Julian formula
    nJdn       : DINT;  // 目标日期的儒略日序数 [日] / Julian day number of the requested date [day]
    nJdnJan1   : DINT;  // 同年 1 月 1 日的儒略日序数 [日] / Julian day number of January the first [day]
    nDowJan1   : DINT;  // 1 月 1 日的 ISO 星期 1~7 [星期序号] / ISO weekday of January the first, one to seven
    nW         : DINT;  // 目标日期的 ISO 星期 1~7 [星期序号] / ISO weekday of the requested date, one to seven
    nOrd       : DINT;  // 年内序号 1~366 [天] / day of year, one to three hundred sixty six [day]
    nWeek      : DINT;  // 周号中间量 0~54 [周] / week interim value, zero to fifty four [week]
    nWeeksYear : DINT;  // 当年 ISO 周数 52 或 53 [周] / ISO weeks in the year, fifty two or fifty three [week]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalIsoWeekNo := -1;       // 缺省无效哨兵 / default invalid sentinel
eErr       := 0;                // 零码位范式 / zero-code rule
bError     := FALSE;            // 预置无故障 / preset no fault
bValid     := FALSE;            // 域闸前不认结果 / unusable until the domain gates pass
nWeekYear  := 0;                // 归属年清零 / clear the owning year

// 段 2｜域闸：年份 → 月份 → 日（含闰年 2 月） / segment 2, the three domain gates
bLeap := (((nYear MOD DL_STEP4) = DL_ZERO) AND ((nYear MOD DL_STEP100) <> DL_ZERO)) OR ((nYear MOD DL_STEP400) = DL_ZERO);
nDaysYear := DL_DAYS_COMMON;
IF bLeap THEN
    nDaysYear := DL_DAYS_COMMON + 1;    // 闰年多一天 / a leap year carries one extra day
END_IF
IF (nYear < DL_GREG_START) OR (nMonth < DL_MONTH_MIN) OR (nMonth > DL_MONTH_MAX) THEN
    bError := TRUE;             // 年份或月份越界 / the year or the month is out of range
    RETURN;
END_IF
IF nMonth = 2 THEN
    nDaysInMon := DL_DAYS_FEB;          // 平年 2 月 / common February
    IF bLeap THEN
        nDaysInMon := DL_DAYS_FEB + 1;  // 闰年 2 月 / leap February
    END_IF
ELSIF (nMonth = 4) OR (nMonth = 6) OR (nMonth = 9) OR (nMonth = 11) THEN
    nDaysInMon := DL_DAYS_30;           // 小月 / short month
ELSE
    nDaysInMon := DL_DAYS_31;           // 大月 / long month
END_IF
IF (nDay < DL_MONTH_MIN) OR (nDay > nDaysInMon) THEN
    bError := TRUE;             // 日超出当月天数 / the day exceeds the month length
    RETURN;
END_IF

// 段 3｜两个儒略日序数：目标日期与同年 1 月 1 日 / segment 3, two Julian day numbers
nA   := (14 - nMonth) / 12;                                  // 1、2 月折入上一年 / January and February fold backwards
nY2  := nYear + 4800 - nA;                                   // 世纪内年份偏置 / shifted year
nM2  := nMonth + 12 * nA - 3;                                // 三月基月份 / March based month
nJdn := nDay + (153 * nM2 + 2) / 5 + 365 * nY2 + nY2 / DL_STEP4 - nY2 / DL_STEP100 + nY2 / DL_STEP400 - 32045;
nJdnJan1 := 307 + 365 * (nYear + 4799) + (nYear + 4799) / DL_STEP4 - (nYear + 4799) / DL_STEP100 + (nYear + 4799) / DL_STEP400 - 32045;
nOrd := nJdn - nJdnJan1 + 1;                                 // 年内序号 / day of year
nW   := (nJdn MOD DL_WEEK_MOD) + 1;                           // ISO 星期 1=周一 … 7=周日 / ISO weekday

// 段 4｜周号主式与当年周数：53 周须 1 月 1 日为周四，或闰年且为周三 / segment 4, the week formula and the year length
nWeek := (nOrd - nW + DL_WEEK_OFF) / DL_WEEK_MOD;             // 0~54 中间值 / interim value
nDowJan1 := (nJdnJan1 MOD DL_WEEK_MOD) + 1;                   // 1 月 1 日的 ISO 星期 / ISO weekday of January the first
nWeeksYear := DL_WEEK_BASE;                                   // 缺省 52 周 / default fifty two weeks
IF (nDowJan1 = DL_JAN1_DOW53A) OR (bLeap AND (nDowJan1 = DL_JAN1_DOW53B)) THEN
    nWeeksYear := DL_WEEK_BASE + 1;                           // 该年为 53 周 / the year carries fifty three weeks
END_IF

// 段 5｜跨年归属：0 归上年末周，超年周数归次年 W1 / segment 5, the two cross year branches
nWeekYear := nYear;
IF nWeek < DL_WEEK_MIN THEN
    bLeapPrev := ((((nYear - 1) MOD DL_STEP4) = DL_ZERO) AND (((nYear - 1) MOD DL_STEP100) <> DL_ZERO)) OR (((nYear - 1) MOD DL_STEP400) = DL_ZERO);
    nDaysPrev := DL_DAYS_COMMON;
    IF bLeapPrev THEN
        nDaysPrev := DL_DAYS_COMMON + 1;    // 上年为闰年 / the previous year is a leap year
    END_IF
    nWeek     := (nOrd + nDaysPrev - nW + DL_WEEK_OFF) / DL_WEEK_MOD;   // 换算到上年的序数 / rebase onto the previous year
    nWeekYear := nYear - 1;                                             // 归属上年 / owned by the previous year
ELSIF nWeek > nWeeksYear THEN
    nWeek     := (nOrd - nDaysYear - nW + DL_WEEK_OFF) / DL_WEEK_MOD;   // 换算到次年的序数 / rebase onto the next year
    IF nWeek < DL_WEEK_MIN THEN
        nWeek := DL_WEEK_MIN;                                          // 结构性必为 1，兜底防御 / always one, kept as a guard
    END_IF
    nWeekYear := nYear + 1;                                             // 归属次年 / owned by the next year
END_IF

// 段 6｜出口 / segment 6, exit
FC_DL_CalIsoWeekNo := nWeek;    // 1~53 / one to fifty three
bValid := TRUE;                 // 结果可用 / the result is usable
END_FUNCTION
