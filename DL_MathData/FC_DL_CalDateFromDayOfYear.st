(*==============================================================================
 * 组件名称 : FC_DL_CalDateFromDayOfYear ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 年内序号反解月日 —— 输入公历年与 1~366 的年内序号，出参月、日。
 *            逐月递减法，闰年 2 月按 29 天参与递减。
 * 契约     : 合法时返回 TRUE 并写出 nMonth / nDay；nDayOfYear 越界（<1 或 >当年天数）
 *            或 nYear < 1583 时返回 FALSE、bError := TRUE、nMonth / nDay 均置 0。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 年份与序号双域闸、无除法
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 4/9）
 *            2026-11-24  v1.0.1  R79/P4：补年份上界闸 DL_GREG_LAST=9999（原仅下界 1583）
 *============================================================================*)
FUNCTION FC_DL_CalDateFromDayOfYear : BOOL
VAR_INPUT
    nYear      : DINT;  // 公历年，域闸 1583 及以上 [年] / Gregorian year, domain starts at 1583 [year]
    nDayOfYear : DINT;  // 年内序号 1~365 或 366 [天] / day of year, one to three hundred sixty six [day]
END_VAR
VAR_OUTPUT
    eErr       : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError     : BOOL;  // 序号越界或年份域外为真 / TRUE when the ordinal or the year is out of range
    bValid     : BOOL;  // 出参可用标志 / TRUE when the outputs are usable
    nMonth     : DINT;  // 解出的月份 1~12，故障时 0 [月] / solved month, zero on fault [month]
    nDay       : DINT;  // 解出的日 1~31，故障时 0 [天] / solved day, zero on fault [day]
END_VAR
VAR CONSTANT
    DL_GREG_START : DINT := 1583;   // 格里高利历起点年 [年] / first Gregorian year [year]
    DL_GREG_LAST  : DINT := 9999;   // 年份上界（v1.0.1 补：防 int64/日期串溢出）[年] / Upper year bound added in v1.0.1 [year]
    DL_MONTH_MIN  : DINT := 1;      // 月份下界 [月] / lower month bound [month]
    DL_MONTH_MAX  : DINT := 12;     // 月份上界 [月] / upper month bound [month]
    DL_DAYS_COMMON : DINT := 365;   // 平年天数 [天] / days in a common year [day]
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
    nDaysYear  : DINT;  // 当年总天数 365 或 366 [天] / total days of the year, 365 or 366 [day]
    nRem       : DINT;  // 递减过程中的剩余序号 [天] / remaining ordinal during the walk [day]
    nMonthDays : DINT;  // 当前游标月的天数 [天] / length of the month at the cursor [day]
    i          : DINT;  // 月份游标 1~12 [月] / month cursor from one to twelve [month]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalDateFromDayOfYear := FALSE;    // 缺省失败 / default failure
eErr     := 0;                          // 零码位范式 / zero-code rule
bError   := FALSE;                      // 预置无故障 / preset no fault
bValid   := FALSE;                      // 域闸前不认出参 / outputs unusable until the gates pass
nMonth   := 0;                          // 月出参清零 / clear the month output
nDay     := 0;                          // 日出参清零 / clear the day output

// 段 2｜域闸：年份 + 年内序号上界（闰年 366） / segment 2, year gate plus the ordinal upper bound
bLeap := (((nYear MOD DL_STEP4) = DL_ZERO) AND ((nYear MOD DL_STEP100) <> DL_ZERO)) OR ((nYear MOD DL_STEP400) = DL_ZERO);
nDaysYear := DL_DAYS_COMMON;
IF bLeap THEN
    nDaysYear := DL_DAYS_COMMON + 1;    // 闰年 366 天 / leap years carry one extra day
END_IF
IF ((nYear < DL_GREG_START) OR (nYear > DL_GREG_LAST)) OR (nDayOfYear < DL_MONTH_MIN) OR (nDayOfYear > nDaysYear) THEN
    bError := TRUE;                     // 年份域外或序号越界 / year out of domain or ordinal out of range
    RETURN;                             // 出参保持 0 / the outputs stay zero
END_IF

// 段 3｜逐月递减：剩余序号超过当月天数即扣减并推进月份 / segment 3, walk the months subtracting their lengths
nRem   := nDayOfYear;                   // 从完整序号起步 / start from the full ordinal
nMonth := DL_MONTH_MIN;                 // 从 1 月起 / start at January
FOR i := DL_MONTH_MIN TO DL_MONTH_MAX DO
    IF i = 2 THEN
        nMonthDays := DL_DAYS_FEB;      // 平年 2 月 / common February
        IF bLeap THEN
            nMonthDays := DL_DAYS_FEB + 1;  // 闰年 2 月 / leap February
        END_IF
    ELSIF (i = 4) OR (i = 6) OR (i = 9) OR (i = 11) THEN
        nMonthDays := DL_DAYS_30;       // 小月 / short month
    ELSE
        nMonthDays := DL_DAYS_31;       // 大月 / long month
    END_IF
    IF nRem > nMonthDays THEN
        nRem   := nRem - nMonthDays;    // 整月扣减 / subtract the whole month
        nMonth := nMonth + 1;           // 月份推进 / advance the month
    END_IF
END_FOR

// 段 4｜出口：剩余序号即日 / segment 4, the leftover ordinal is the day
nDay   := nRem;                         // 1~31 / one to thirty one
bValid := TRUE;                         // 出参可用 / the outputs are usable
FC_DL_CalDateFromDayOfYear := TRUE;     // 转换成功 / conversion succeeded
END_FUNCTION
