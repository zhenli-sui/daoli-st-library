(*==============================================================================
 * 组件名称 : FC_DL_CalDayOfYear ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 给定公历年月日，返回年内序号 1~366。用儒略日序数相减实现 ——
 *            JDN(年月日) − JDN(同年 1 月 1 日) + 1，闰年自动含入，无需月长表。
 * 契约     : 返回 1~366；nMonth 不在 1~12、nDay 不在当月 1~当月天数、nYear < 1583
 *            时返回 0 且 bError := TRUE。纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 域闸三层先行、整数式除数恒正
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : JDN 整数式对 1583 年及以后恒为正，故 1583 为域闸下限；更早年份不入本件。
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 3/9）
 *            2026-11-24  v1.0.1  R79/P4：补年份上界闸 DL_GREG_LAST=9999（原仅下界 1583）
 *============================================================================*)
FUNCTION FC_DL_CalDayOfYear : DINT
VAR_INPUT
    nYear     : DINT;   // 公历年，域闸 1583 及以上 [年] / Gregorian year, domain starts at 1583 [year]
    nMonth    : DINT;   // 月份 1~12 [月] / month from one to twelve [month]
    nDay      : DINT;   // 日 1~当月天数 [天] / day from one to the month length [day]
END_VAR
VAR_OUTPUT
    eErr      : UDINT;  // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;   // 日期不存在或域外为真，返回 0 / TRUE when the date is invalid or out of domain, result is zero
    bValid    : BOOL;   // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_GREG_START : DINT := 1583;   // 格里高利历起点年 [年] / first Gregorian year [year]
    DL_GREG_LAST  : DINT := 9999;   // 年份上界（v1.0.1 补：防 int64/日期串溢出）[年] / Upper year bound added in v1.0.1 [year]
    DL_MONTH_MIN  : DINT := 1;      // 月份下界 [月] / lower month bound [month]
    DL_MONTH_MAX  : DINT := 12;     // 月份上界 [月] / upper month bound [month]
    DL_DAYS_FEB   : DINT := 28;     // 平年 2 月天数 [天] / February days in a common year [day]
    DL_DAYS_30    : DINT := 30;     // 小月天数 [天] / days in a short month [day]
    DL_DAYS_31    : DINT := 31;     // 大月天数 [天] / days in a long month [day]
    DL_STEP4      : DINT := 4;      // 闰年基本步长 [年] / base leap step [year]
    DL_STEP100    : DINT := 100;    // 世纪基数 [年] / century radix [year]
    DL_STEP400    : DINT := 400;    // 四世纪基数 [年] / four century radix [year]
    DL_ZERO       : DINT := 0;      // 整数零哨兵 [无量纲] / integer zero sentinel [dimensionless]
END_VAR
VAR
    bLeap      : BOOL;  // 当年是否闰年 / whether the year is a leap year
    nA         : DINT;  // 月份压缩偏置 0 或 1 / month compression offset, zero or one
    nY2        : DINT;  // 儒略式内的世纪内年份 / shifted year inside the Julian formula
    nM2        : DINT;  // 儒略式内的三月基月份 / March based month inside the Julian formula
    nJdn       : DINT;  // 目标日期的儒略日序数 [日] / Julian day number of the requested date [day]
    nJdnJan1   : DINT;  // 同年 1 月 1 日的儒略日序数 [日] / Julian day number of January the first [day]
    nDaysInMon : DINT;  // 当月的实际天数 [天] / actual length of the requested month [day]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalDayOfYear := 0;        // 缺省 0 / default zero
eErr   := 0;                    // 零码位范式 / zero-code rule
bError := FALSE;                // 预置无故障 / preset no fault
bValid := FALSE;                // 域闸前不认结果 / unusable until the domain gates pass

// 段 2｜域闸：年份 → 月份 → 日，三层依次拦 / segment 2, three domain gates in sequence
IF ((nYear < DL_GREG_START) OR (nYear > DL_GREG_LAST)) OR (nMonth < DL_MONTH_MIN) OR (nMonth > DL_MONTH_MAX) THEN
    bError := TRUE;             // 年份或月份越界 / the year or the month is out of range
    RETURN;                     // 返回 0 / return zero
END_IF
bLeap := (((nYear MOD DL_STEP4) = DL_ZERO) AND ((nYear MOD DL_STEP100) <> DL_ZERO)) OR ((nYear MOD DL_STEP400) = DL_ZERO);
IF nMonth = 2 THEN
    nDaysInMon := DL_DAYS_FEB;      // 平年 2 月 / common February
    IF bLeap THEN
        nDaysInMon := DL_DAYS_FEB + 1;  // 闰年 2 月 / leap February
    END_IF
ELSIF (nMonth = 4) OR (nMonth = 6) OR (nMonth = 9) OR (nMonth = 11) THEN
    nDaysInMon := DL_DAYS_30;       // 小月 / short month
ELSE
    nDaysInMon := DL_DAYS_31;       // 大月 / long month
END_IF
IF (nDay < DL_MONTH_MIN) OR (nDay > nDaysInMon) THEN
    bError := TRUE;             // 日超出当月天数 / the day exceeds the month length
    RETURN;                     // 返回 0 / return zero
END_IF

// 段 3｜儒略日序数：月压缩到三月基，年偏置 4800，偏移 32045 / segment 3, the Julian day number
nA   := (14 - nMonth) / 12;                                  // 1、2 月归上一年的第 13、14 月 / January and February fold into the previous year
nY2  := nYear + 4800 - nA;                                   // 世纪内年份偏置 / shifted year
nM2  := nMonth + 12 * nA - 3;                                // 三月基月份 0~11 / March based month
nJdn := nDay + (153 * nM2 + 2) / 5 + 365 * nY2 + nY2 / DL_STEP4 - nY2 / DL_STEP100 + nY2 / DL_STEP400 - 32045;

// 段 4｜同年 1 月 1 日的序数：m=1、d=1 代入同一式子后化简 / segment 4, ordinal of January the first
nJdnJan1 := 1 + 306 + 365 * (nYear + 4799) + (nYear + 4799) / DL_STEP4 - (nYear + 4799) / DL_STEP100 + (nYear + 4799) / DL_STEP400 - 32045;

// 段 5｜出口：差值加一即年内序号 / segment 5, the difference plus one is the day of year
FC_DL_CalDayOfYear := nJdn - nJdnJan1 + 1;   // 1~366 / one to three hundred sixty six
bValid := TRUE;                              // 日期合法，结果可用 / the date is legal and the result is usable
END_FUNCTION
