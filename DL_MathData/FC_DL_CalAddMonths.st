(*==============================================================================
 * 组件名称 : FC_DL_CalAddMonths ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 日历加月。给定基准年月日与月增量（可负），输出加月后的年月日，月末钳位：
 *            1 月 31 日 + 1 月 → 2 月 28/29 日；3 月 31 日 − 1 月 → 2 月 28/29 日。
 * 契约     : 合法时返回 TRUE、bValid := TRUE；年/月/日越界（基准日按基准月长度校核）、
 *            |nDelta| > 1200、加月结果落到公元 0 年之前或超出 9999 年 →
 *            返回 FALSE、bError := TRUE、五个出参全部保持 0。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现：闰年与月长内联），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除 12 前已证 nIdx 非负且 < 120000
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 仅用 INT_TO_DINT() R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 年初口径为公元 1 年 1 月；nDelta 超 ±1200 判故障而非静默截断；
 *            nIdx 为 0 基月序号 = 年 × 12 + 月 − 1 + 增量，非负才可安全除 12 取模。
 * 修订历史 : 2026-11-24 R79-B 首版（日历数论族 1/2）
 *============================================================================*)
FUNCTION FC_DL_CalAddMonths : BOOL
VAR_INPUT
    nYear  : DINT;   // 基准年，公历 1..9999 [年] / base year in the Gregorian range
    nMonth : DINT;   // 基准月，1..12 [月] / base month, one based
    nDay   : DINT;   // 基准日，1..31（按基准月长度校核）[日] / base day checked against the base month length
    nDelta : INT;    // 月增量，可负，|nDelta| ≤ 1200 [月] / month delta, negative allowed
END_VAR
VAR_OUTPUT
    eErr      : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError    : BOOL;  // 入参越界或结果不可表示时为真 / TRUE on an input out of range or an unrepresentable result
    bValid    : BOOL;  // 出参可用标志 / TRUE when the outputs are usable
    nOutYear  : DINT;  // 结果年 [年] / resulting year
    nOutMonth : DINT;  // 结果月 1..12 [月] / resulting month
    nOutDay   : DINT;  // 结果日，已按结果月长度钳位 [日] / resulting day clamped to the length of the resulting month
END_VAR
VAR CONSTANT
    DL_ZERO    : DINT := 0;     // 整数零哨兵 / integer zero sentinel
    DL_ONE     : DINT := 1;     // 整数一哨兵 / integer one sentinel
    DL_TWELVE  : DINT := 12;    // 每年月数 [月] / months per year
    DL_D31     : DINT := 31;    // 大月日数上界 [日] / the day count of a long month
    DL_D30     : DINT := 30;    // 小月日数 [日] / the day count of a short month
    DL_D28     : DINT := 28;    // 平年二月日数 [日] / the February day count of a common year
    DL_D29     : DINT := 29;    // 闰年二月日数 [日] / the February day count of a leap year
    DL_YMIN    : DINT := 1;     // 年份下界 [年] / lower year bound
    DL_YMAX    : DINT := 9999;  // 年份上界 [年] / upper year bound
    DL_IDXMAX  : DINT := 120000; // 月序号开区间上界 = 10000 × 12 [月] / exclusive index ceiling
    DL_DMAX    : INT  := 1200;  // 月增量绝对值上界 [月] / absolute month delta ceiling
END_VAR
VAR
    nIdx    : DINT; // 0 基月序号（年 × 12 + 月 − 1 + 增量）[月] / zero based month index
    nMaxDay : DINT; // 基准月的日数 28..31 [日] / days in the base month
    nResMax : DINT; // 结果月的日数 28..31 [日] / days in the resulting month
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_CalAddMonths := FALSE;  // 缺省失败 / default failure
eErr      := 0;               // 零码位范式 / zero-code rule
bError    := FALSE;           // 预置无故障 / preset no fault
bValid    := FALSE;           // 域闸前不认出参 / the outputs are unusable until the gates pass
nOutYear  := DL_ZERO;         // 年清零 / clear the year
nOutMonth := DL_ZERO;         // 月清零 / clear the month
nOutDay   := DL_ZERO;         // 日清零 / clear the day

// 段 2｜年与月的域闸（含 nDelta 双侧直比，禁 ABS 单侧以免 INT 下界回绕）/ segment 2, the year, month and delta gates
IF (nYear < DL_YMIN) OR (nYear > DL_YMAX) THEN bError := TRUE; RETURN; END_IF              // 年越界 / year out of range
IF (nMonth < DL_ONE) OR (nMonth > DL_TWELVE) THEN bError := TRUE; RETURN; END_IF           // 月越界 / month out of range
IF (nDelta > DL_DMAX) OR (nDelta < -DL_DMAX) THEN bError := TRUE; RETURN; END_IF           // 增量越界 / delta out of range

// 段 3｜基准日校核：按基准月长度，防「2 月 30 日」这类日历不存在日 / segment 3, the base day gate by month length
nMaxDay := DL_D31;                                                                          // 缺省大月 / default to a long month
IF (nMonth = 4) OR (nMonth = 6) OR (nMonth = 9) OR (nMonth = 11) THEN nMaxDay := DL_D30; END_IF  // 小月 / short months
IF nMonth = 2 THEN nMaxDay := DL_D28; END_IF                                               // 二月先按平年 / February as a common year
IF (nMonth = 2) AND (((nYear MOD 4) = 0) AND ((nYear MOD 100) <> 0) OR ((nYear MOD 400) = 0)) THEN nMaxDay := DL_D29; END_IF  // 闰年二月 / leap February
IF (nDay < DL_ONE) OR (nDay > nMaxDay) THEN bError := TRUE; RETURN; END_IF                 // 日越界 / day out of range

// 段 4｜月序号换算与结果域闸（先验后写，出参在故障时保持 0）/ segment 4, the month index and the result domain gate
nIdx := (nYear * DL_TWELVE) + (nMonth - DL_ONE) + INT_TO_DINT(nDelta);                      // 0 基月序号 / the zero based month index
IF (nIdx < DL_ZERO) OR (nIdx >= DL_IDXMAX) THEN bError := TRUE; RETURN; END_IF             // 落到公元 0 年前或超出 9999 年 / before year one or beyond the ceiling
nOutYear  := nIdx / DL_TWELVE;                                                              // 除 12 已证 nIdx 非负 / the division is safe after the non negative gate
nOutMonth := (nIdx MOD DL_TWELVE) + DL_ONE;                                                  // 月序 0..11 加一 / the month index shifted to one based

// 段 5｜月末钳位：结果月短于基准日时收到结果月最后一天 / segment 5, the month end clamp
nResMax := DL_D31;                                                                          // 缺省大月 / default to a long month
IF (nOutMonth = 4) OR (nOutMonth = 6) OR (nOutMonth = 9) OR (nOutMonth = 11) THEN nResMax := DL_D30; END_IF  // 小月 / short months
IF nOutMonth = 2 THEN nResMax := DL_D28; END_IF                                            // 二月先按平年 / February as a common year
IF (nOutMonth = 2) AND (((nOutYear MOD 4) = 0) AND ((nOutYear MOD 100) <> 0) OR ((nOutYear MOD 400) = 0)) THEN nResMax := DL_D29; END_IF  // 闰年二月 / leap February
IF nDay > nResMax THEN nOutDay := nResMax; ELSE nOutDay := nDay; END_IF                     // 钳位 / clamp to the month length
bValid := TRUE;                                                                             // 出参可用 / the outputs are usable
FC_DL_CalAddMonths := TRUE;                                                                 // 加月完成 / the month shift completed
END_FUNCTION
