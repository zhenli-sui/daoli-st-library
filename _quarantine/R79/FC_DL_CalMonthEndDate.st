(*==============================================================================
 * 组件名称 : FC_DL_CalMonthEndDate ｜ 子库 : DL_MathData ｜ v1.0.1 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 给定公历年月，出参返回该月最后一天的日号（月末日期）。月度报表切日、
 *            月累计清零、月末结账触发都以本件为唯一口径。2 月按闰年判据取 28 / 29。
 * 契约     : 合法时返回 TRUE 并写出 nLastDay（1~31）；nMonth 越界或 nYear < 1583 时
 *            返回 FALSE、bError := TRUE、nLastDay := 0。纯函数无状态。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 年份与月份双域闸、取余无除零面
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 9/9）
 *            2026-11-24  v1.0.1  R79/P4：补年份上界闸 DL_GREG_LAST=9999（原仅下界 1583）
 *============================================================================*)
FUNCTION FC_DL_CalMonthEndDate : BOOL
VAR_INPUT
    nYear     : DINT;   // 公历年，域闸 1583 及以上 [年] / Gregorian year, domain starts at 1583 [year]
    nMonth    : DINT;   // 月份 1~12 [月] / month from one to twelve [month]
END_VAR
VAR_OUTPUT
    eErr      : UDINT;  // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;   // 年份或月份越界为真 / TRUE when the year or the month is out of range
    bValid    : BOOL;   // 出参可用标志 / TRUE when the output is usable
    nLastDay  : DINT;   // 该月最后一天的日号 1~31，故障时 0 [天] / last day of the month, zero on fault [day]
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
    bLeap     : BOOL;   // 当年是否闰年 / whether the year is a leap year
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalMonthEndDate := FALSE;     // 缺省失败 / default failure
eErr      := 0;                     // 零码位范式 / zero-code rule
bError    := FALSE;                 // 预置无故障 / preset no fault
bValid    := FALSE;                 // 域闸前不认出参 / the output is unusable until the gates pass
nLastDay  := 0;                     // 日号清零 / clear the day number

// 段 2｜域闸：年份 → 月份 / segment 2, the year and the month gates
IF ((nYear < DL_GREG_START) OR (nYear > DL_GREG_LAST)) OR (nMonth < DL_MONTH_MIN) OR (nMonth > DL_MONTH_MAX) THEN
    bError := TRUE;                 // 年份或月份越界 / the year or the month is out of range
    RETURN;                         // 出参保持 0 / the output stays zero
END_IF

// 段 3｜闰年判据（内联自足） / segment 3, the leap test implemented inline
bLeap := (((nYear MOD DL_STEP4) = DL_ZERO) AND ((nYear MOD DL_STEP100) <> DL_ZERO)) OR ((nYear MOD DL_STEP400) = DL_ZERO);

// 段 4｜月末日号：2 月单列，30 天月枚举，其余 31 天 / segment 4, the last day selection
IF nMonth = 2 THEN
    nLastDay := DL_DAYS_FEB;        // 平年 2 月 / common February
    IF bLeap THEN
        nLastDay := DL_DAYS_FEB + 1;    // 闰年 2 月 / leap February
    END_IF
ELSIF (nMonth = 4) OR (nMonth = 6) OR (nMonth = 9) OR (nMonth = 11) THEN
    nLastDay := DL_DAYS_30;         // 小月 / short month
ELSE
    nLastDay := DL_DAYS_31;         // 大月 / long month
END_IF

// 段 5｜出口 / segment 5, exit
bValid := TRUE;                     // 出参可用 / the output is usable
FC_DL_CalMonthEndDate := TRUE;      // 求解成功 / the request succeeded
END_FUNCTION
