(*==============================================================================
 * 组件名称 : FC_DL_CalDateSpanMonths ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 两日期之间的整月差（月龄/账龄/保养周期用）。含日修正：月差算出后，
 *            若「结束日 < 起始日」则该月不计（正向再减 1）；反向对称（结束日 > 起始日再加 1）。
 * 契约     : 返回整月差，起始晚于结束返回负值；任一日期非法（年 1..9999、月 1..12、
 *            日超出该月长度）→ 返回 0 并置 bError := TRUE、bValid := FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现：闰年与月长内联），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 无除法（只乘 12 与加减）+ 无浮点
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 日修正按符号对称，故 Span(a→b) = −Span(b→a) 恒成立；同日不同月按月末口径
 *            计（1 月 31 日 → 2 28 日为 0 个月，非 1 个月）；日修正只看日号不比月长。
 * 修订历史 : 2026-11-24 R79-B 首版（日历数论族 2/2）
 *============================================================================*)
FUNCTION FC_DL_CalDateSpanMonths : DINT
VAR_INPUT
    nYearA  : DINT := 0; // 起始日之年，1..9999 [年] / year of the start date
    nMonthA : DINT := 0; // 起始日之月，1..12 [月] / month of the start date
    nDayA   : DINT := 0; // 起始日之日，1..31 [日] / day of the start date
    nYearB  : DINT := 0; // 结束日之年，1..9999 [年] / year of the end date
    nMonthB : DINT := 0; // 结束日之月，1..12 [月] / month of the end date
    nDayB   : DINT := 0; // 结束日之日，1..31 [日] / day of the end date
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 任一日期非法时为真 / TRUE when either date is invalid
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO   : DINT := 0;     // 整数零哨兵 / integer zero sentinel
    DL_ONE    : DINT := 1;     // 整数一哨兵 / integer one sentinel
    DL_ELEVEN : DINT := 11;    // 小月判定上界之一（11 月）[月] / one of the short month keys
    DL_TWELVE : DINT := 12;    // 每年月数 [月] / months per year
    DL_D31    : DINT := 31;    // 大月日数上界 [日] / the day count of a long month
    DL_D30    : DINT := 30;    // 小月日数 [日] / the day count of a short month
    DL_D28    : DINT := 28;    // 平年二月日数 [日] / the February day count of a common year
    DL_D29    : DINT := 29;    // 闰年二月日数 [日] / the February day count of a leap year
    DL_YMIN   : DINT := 1;     // 年份下界 [年] / lower year bound
    DL_YMAX   : DINT := 9999;  // 年份上界 [年] / upper year bound
END_VAR
VAR
    nMaxA   : DINT; // 起始月的日数 28..31 [日] / days in the start month
    nMaxB   : DINT; // 结束月的日数 28..31 [日] / days in the end month
    nMonths : DINT; // 未做日修正的整月差 [月] / the raw month difference before the day correction
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalDateSpanMonths := DL_ZERO;  // 缺省零 / default zero
eErr   := 0;                          // 零码位范式 / zero-code rule
bError := FALSE;                      // 预置无故障 / preset no fault
bValid := FALSE;                      // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜两日期的域闸：年/月先行，日按各自月长度（防 2 月 30 日一类不存在日）/ segment 2, the domain gates
IF (nYearA < DL_YMIN) OR (nYearA > DL_YMAX) OR (nYearB < DL_YMIN) OR (nYearB > DL_YMAX) THEN bError := TRUE; RETURN; END_IF      // 年越界 / year out of range
IF (nMonthA < DL_ONE) OR (nMonthA > DL_TWELVE) OR (nMonthB < DL_ONE) OR (nMonthB > DL_TWELVE) THEN bError := TRUE; RETURN; END_IF  // 月越界 / month out of range
nMaxA := DL_D31;                                                                                    // 起始月缺省大月 / start month defaults to long
IF (nMonthA = 4) OR (nMonthA = 6) OR (nMonthA = 9) OR (nMonthA = DL_ELEVEN) THEN nMaxA := DL_D30; END_IF  // 起始小月 / start short month
IF nMonthA = 2 THEN nMaxA := DL_D28; END_IF                                                        // 起始二月按平年 / start February as common year
IF (nMonthA = 2) AND (((nYearA MOD 4) = 0) AND ((nYearA MOD 100) <> 0) OR ((nYearA MOD 400) = 0)) THEN nMaxA := DL_D29; END_IF     // 起始闰二月 / start leap February
nMaxB := DL_D31;                                                                                    // 结束月缺省大月 / end month defaults to long
IF (nMonthB = 4) OR (nMonthB = 6) OR (nMonthB = 9) OR (nMonthB = DL_ELEVEN) THEN nMaxB := DL_D30; END_IF  // 结束小月 / end short month
IF nMonthB = 2 THEN nMaxB := DL_D28; END_IF                                                        // 结束二月按平年 / end February as common year
IF (nMonthB = 2) AND (((nYearB MOD 4) = 0) AND ((nYearB MOD 100) <> 0) OR ((nYearB MOD 400) = 0)) THEN nMaxB := DL_D29; END_IF     // 结束闰二月 / end leap February
IF (nDayA < DL_ONE) OR (nDayA > nMaxA) OR (nDayB < DL_ONE) OR (nDayB > nMaxB) THEN bError := TRUE; RETURN; END_IF                 // 日越界 / day out of range

// 段 3｜未修正整月差：年差乘 12 加月差的代数和（无除法、无溢出风险：年份已限 9999）/ segment 3, the raw month difference
nMonths := ((nYearB - nYearA) * DL_TWELVE) + (nMonthB - nMonthA);                                   // 整月代数和 [月] / signed month difference

// 段 4｜日修正按符号对称分支：正向「结束日 < 起始日」减一，反向「结束日 > 起始日」加一 / segment 4, the sign symmetric day correction
IF nMonths >= DL_ZERO THEN
    IF nDayB < nDayA THEN nMonths := nMonths - DL_ONE; END_IF                                      // 不足以计满一个月 / not a full month yet
ELSE
    IF nDayB > nDayA THEN nMonths := nMonths + DL_ONE; END_IF                                      // 反向对称修正 / the mirrored correction
END_IF

bValid := TRUE;                                    // 返回值可用 / the return value is usable
FC_DL_CalDateSpanMonths := nMonths;                // 回写整月差 / publish the month span
END_FUNCTION
