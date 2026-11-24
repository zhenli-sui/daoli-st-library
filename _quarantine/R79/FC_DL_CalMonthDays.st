(*==============================================================================
 * 组件名称 : FC_DL_CalMonthDays ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 给定公历年月，返回该月天数；2 月按闰年判据取 28 或 29，其余月固定 30/31。
 *            纯整数实现，闰年判据内联自足，不调用同族其他件。
 * 契约     : 返回 1~31 为合法天数；nMonth 越界（<1 或 >12）返回 0 且 bError := TRUE。
 *            nYear < 1583 时 2 月按非闰年（28）计数 —— 儒略历口径不入本件，见遗留假设。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 月份域闸先行、取余无除零面
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突 R18 N/A（无 bReset）
 * 遗留假设 : 格里高利历起点之前的 2 月按 28 天计；该域需 29 天的场合请先自查历法归属。
 * 修订历史 : 2026-11-24 R79-A 首版（日历算术族 2/9）
 *============================================================================*)
FUNCTION FC_DL_CalMonthDays : DINT
VAR_INPUT
    nYear     : DINT;   // 公历年，仅供 2 月闰年判定 [年] / Gregorian year used by the February leap test [year]
    nMonth    : DINT;   // 月份 1~12，越界即故障 [月] / month from one to twelve, out of range is a fault [month]
END_VAR
VAR_OUTPUT
    eErr      : UDINT;  // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;   // 月份越界为真，返回 0 / TRUE when the month is out of range, the result is zero
    bValid    : BOOL;   // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_MONTH_MIN  : DINT := 1;      // 月份下界 [月] / lower month bound [month]
    DL_MONTH_MAX  : DINT := 12;     // 月份上界 [月] / upper month bound [month]
    DL_DAYS_31    : DINT := 31;     // 大月天数 [天] / days in a long month [day]
    DL_DAYS_30    : DINT := 30;     // 小月天数 [天] / days in a short month [day]
    DL_DAYS_FEB   : DINT := 28;     // 平年 2 月天数 [天] / February days in a common year [day]
    DL_GREG_START : DINT := 1583;   // 格里高利历起点年 [年] / first Gregorian year [year]
    DL_STEP4      : DINT := 4;      // 闰年基本步长 [年] / base leap step [year]
    DL_STEP100    : DINT := 100;    // 世纪基数 [年] / century radix [year]
    DL_STEP400    : DINT := 400;    // 四世纪基数 [年] / four century radix [year]
    DL_ZERO       : DINT := 0;      // 整数零哨兵 [无量纲] / integer zero sentinel [dimensionless]
END_VAR
VAR
    bLeap     : BOOL;   // 当年是否闰年 / whether the year is a leap year
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalMonthDays := 0;        // 缺省 0 天 / default zero days
eErr   := 0;                    // 零码位范式 / zero-code rule
bError := FALSE;                // 预置无故障 / preset no fault
bValid := FALSE;                // 域闸前不认结果 / unusable until the domain gate passes

// 段 2｜月份域闸：唯一故障出口 / segment 2, the month domain gate is the only fault exit
IF (nMonth < DL_MONTH_MIN) OR (nMonth > DL_MONTH_MAX) THEN
    bError := TRUE;             // 月份越界 / the month is out of range
    RETURN;                     // 返回 0 / return zero
END_IF
bValid := TRUE;                 // 月份入域 / the month is inside the domain

// 段 3｜闰年判据（内联自足，不跨件调用） / segment 3, the leap test implemented inline
bLeap := FALSE;
IF nYear >= DL_GREG_START THEN
    bLeap := (((nYear MOD DL_STEP4) = DL_ZERO) AND ((nYear MOD DL_STEP100) <> DL_ZERO)) OR ((nYear MOD DL_STEP400) = DL_ZERO);
END_IF

// 段 4｜月长选择：2 月单列，30 天月枚举，其余一律 31 天 / segment 4, month length selection
IF nMonth = 2 THEN
    IF bLeap THEN
        FC_DL_CalMonthDays := DL_DAYS_FEB + 1;     // 闰年 2 月 29 天 / twenty nine days in a leap February
    ELSE
        FC_DL_CalMonthDays := DL_DAYS_FEB;         // 平年 2 月 28 天 / twenty eight days otherwise
    END_IF
ELSIF (nMonth = 4) OR (nMonth = 6) OR (nMonth = 9) OR (nMonth = 11) THEN
    FC_DL_CalMonthDays := DL_DAYS_30;              // 4/6/9/11 月为 30 天 / thirty day months
ELSE
    FC_DL_CalMonthDays := DL_DAYS_31;              // 其余为 31 天 / the rest have thirty one days
END_IF
END_FUNCTION
