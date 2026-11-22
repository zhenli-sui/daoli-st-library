(*
  ==================================================================
  组件名 Component  : FC_DL_WeekNumIsoCalc
  分类   Category   : DL_MathData
  版本   Version    : 1.0.0
  功能   Purpose    : ISO 8601 周号计算：输入公历日期，输出 ISO 周号（1~53）
                      与 ISO 周年。全整数实现「儒略日偏移法」：先折儒略日数
                      JDN（整数式，全程正数域整除=向下取整，无符号陷阱），
                      再由「本周四的 JDN」定位所属 ISO 周年，最后以
                      「周年首个周四」为基准做整除求周号。禁 TRUNC 技巧、
                      禁浮点参与，逐整数分支推导。
  来源   Source     : t2-1-lgf-dateandtimer（日期族：JDN 整数式为公开历法
                      口径（Richards 算法公开条款），实现零源码复制）
  互引   Cross-ref  : FC_DL_DayOfWeekCalc（同族星期原子，本件内部 wd 计算
                      与其同口径：JDN mod 7，0=周一）；FC_DL_LeapYearChk
                      （闰年判据同口径，本件以本地常量实现同口径逻辑）
  平台   Platform   : 纯 IEC 61131-3 整数四则 + MOD，三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；无标准库
  归属   Ownership  : 闰年判定以本地常量实现，判据与 FC_DL_LeapYearChk 严格
                      同口径：(y mod 4 = 0 且 y mod 100 <> 0) 或 y mod 400 = 0；
                      本件不声明新枚举。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 月/日域闸 + 年域闸 + 除数全为正常量（结构性无除零）
                      R5 全变量双语同行注释/R6 纯函数无状态机（CASE 不适用）
                      R7 无定时器与沿检测/R8 域界与容差全常量化
  错误码 Codes      : 01【失效级】非法日期（月 1~12 / 日 1~当月天数外）
                      02【失效级】年份域外（有效域 1990~2100）
  码位反证 Note     : 01 与 02 分立依据（R90）：01 在「域内年份 + 日期非法」
                      可观测、02 在「年份域外」可观测，两输入面不同；
                      bValid/nErrId 双通道可区分，无第三码需求。
  验收   Acceptance : V1 2026-11-22（周日）→ 周 47 / 周年 2026 ｜
                      V2 2026-01-01（周四）→ 周 1 / 2026 ｜
                      V3 2026-12-28（周一，周四落 2027）→ 周 53 / 周年 2026
                      ｜ V4 2027-01-01 → 周年 2026 周 53 ｜ V5 2 月 30 → 码 01
                      ｜ V6 1989 或 2101 → 码 02 ｜ V7 2024-02-29（闰）合法
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 1 序 4）
  ==================================================================
*)
FUNCTION FC_DL_WeekNumIsoCalc : UINT
VAR_INPUT
    nYear    : UINT;  // 公历年 [年]，有效域 1990~2100 / the calendar year, valid 1990 to 2100
    nMonth   : UINT;  // 公历月 [月]，有效域 1~12 / the calendar month, valid 1 to 12
    nDay     : UINT;  // 公历日 [日]，有效域 1~当月天数 / the calendar day, valid 1 to days in month
END_VAR
VAR_OUTPUT
    nIsoWeek : UINT;  // ISO 周号 1~53 [周] / the ISO week number [week]
    nIsoYear : UINT;  // ISO 周年 [年]（含跨年周归属）/ the ISO week year with cross year attribution
    bValid   : BOOL;  // 结果可用标志 [-] / the result usable flag
    nErrId   : UDINT; // 错误码，0=正常，01=非法日期，02=年域外 [码] / the error code [code]
END_VAR
VAR
    y        : DINT;  // 年工作寄存器 [年] / the year working register
    m        : DINT;  // 月工作寄存器 [月] / the month working register
    d        : DINT;  // 日工作寄存器 [日] / the day working register
    bLeap    : BOOL;  // 闰年判定结果（与 FC_DL_LeapYearChk 同口径）[-] / the leap year verdict, same criteria as the family checker
    uDim     : DINT;  // 当月天数 [日] / the days in the current month
    a        : DINT;  // JDN 折算中间量 (14-m)/12 / the JDN intermediate (14 minus m) over 12
    y2       : DINT;  // JDN 折算年中间量 / the JDN shifted year
    m2       : DINT;  // JDN 折算月中间量 / the JDN shifted month
    jdn      : DINT;  // 输入日期儒略日数 [日] / the Julian day number of the input date
    wd       : DINT;  // 星期序号 0=周一..6=周日 [日] / the weekday index, zero is Monday
    jThu     : DINT;  // 本周周四的 JDN [日] / the JDN of this week's Thursday
    jJanY    : DINT;  // 输入年 1 月 1 日 JDN [日] / the JDN of the input year's Jan 1
    jJanPrev : DINT;  // 前一年 1 月 1 日 JDN [日] / the JDN of the previous year's Jan 1
    jJanNext : DINT;  // 次年 1 月 1 日 JDN [日] / the JDN of the next year's Jan 1
    isoY     : DINT;  // ISO 周年工作寄存器 [年] / the ISO week year working register
    jRef     : DINT;  // ISO 周年 1 月 1 日 JDN [日] / the JDN of the ISO year's Jan 1
    wd0101   : DINT;  // ISO 周年元旦星期序号 [日] / the weekday of the ISO year's Jan 1
    off      : DINT;  // 元素距首个周四的偏移 [日] / the offset from Jan 1 to the first Thursday
    jThu1    : DINT;  // ISO 周年首个周四 JDN [日] / the JDN of the ISO year's first Thursday
    nWeek    : DINT;  // 周号工作寄存器 [周] / the week number working register
END_VAR
VAR CONSTANT
    WIC_Y_MIN    : DINT := 1990;           // 年份有效域下限 [年] / the valid year lower bound
    WIC_Y_MAX    : DINT := 2100;           // 年份有效域上限 [年] / the valid year upper bound
    WIC_JDN_1970 : DINT := 2440588;        // JDN 基准锚点（1970-01-01，星期四）[日] / the JDN anchor of 1970-01-01, a Thursday
    WIC_ERR_NONE  : UDINT := 16#0000_0000; // 无错误 [码] / no error [code]
    WIC_ERR_DATE  : UDINT := 16#0000_0001; // 码 01：非法日期 / code 01, illegal date
    WIC_ERR_YEAR  : UDINT := 16#0000_0002; // 码 02：年域外 / code 02, year out of domain
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
FC_DL_WeekNumIsoCalc := UINT#0;  // 失效缺省返回 0 / fault default returns zero
nIsoWeek := UINT#0;              // 周号预置 0 / preset the week to zero
nIsoYear := UINT#0;              // 周年预置 0 / preset the week year to zero
bValid   := FALSE;               // 预置不可用 / preset unusable
nErrId   := WIC_ERR_NONE;        // 预置无错误 / preset no error

// 段 2｜年份域闸（码 02，结构 RETURN 早退）/ segment 2, the year domain gate
IF (nYear < UINT#1990) OR (nYear > UINT#2100) THEN        // 域外年份 / year outside the domain
    nErrId := WIC_ERR_YEAR;
    RETURN;
END_IF

// 段 3｜月/日域闸 + 当月天数（闰年本地常量实现，与 FC_DL_LeapYearChk 同口径）
//      segment 3, month and day gates with the local days in month table
y := UINT_TO_DINT(nYear);       // 年入工作寄存器 / move the year into the register
m := UINT_TO_DINT(nMonth);      // 月入工作寄存器 / move the month into the register
d := UINT_TO_DINT(nDay);        // 日入工作寄存器 / move the day into the register
IF (m < 1) OR (m > 12) THEN     // 月域闸（码 01）/ the month gate, code 01
    nErrId := WIC_ERR_DATE;
    RETURN;
END_IF
bLeap := ((y MOD 4 = 0) AND (y MOD 100 <> 0)) OR (y MOD 400 = 0);  // 闰年判据（同口径）/ the leap criteria, family aligned
CASE m OF        // 当月天数表 / the days in month table
1, 3, 5, 7, 8, 10, 12:  uDim := 31;   // 大月 / the long months
4, 6, 9, 11:            uDim := 30;   // 小月 / the short months
2:                      IF bLeap THEN uDim := 29; ELSE uDim := 28; END_IF  // 二月按闰年 / February by leap
ELSE                    uDim := 0;    // CASE 兜底（结构性不可达，月域已闸）/ unreachable else, the month is gated
END_CASE
IF (d < 1) OR (d > uDim) THEN   // 日域闸（码 01）/ the day gate, code 01
    nErrId := WIC_ERR_DATE;
    RETURN;
END_IF

// 段 4｜JDN 整数折算（Richards 公开式，全程正数域，整除=向下取整）
//      segment 4, the integer JDN conversion, all positive so truncation is floor
a  := (14 - m) DIV 12;                   // m≥1 保证 14-m ≥ 2，商为 0 或 1 / the month shift term
y2 := y + 4800 - a;                      // 折算年，约 6800 量级，DINT 安全 / the shifted year
m2 := m + 12 * a - 3;                    // 折算月 0~11 / the shifted month
jdn := d + (153 * m2 + 2) DIV 5 + 365 * y2 + y2 DIV 4 - y2 DIV 100 + y2 DIV 400 - 32045;  // 儒略日数 [日] / the Julian day number
IF (jdn < WIC_JDN_1970) THEN             // 防御性锚点闸（域内年份结构上不可能触发，留档）/ defensive anchor gate, unreachable in domain
    nErrId := WIC_ERR_YEAR;
    RETURN;
END_IF

// 段 5｜星期与本周四：JDN mod 7 得 0=周一..6=周日（与 FC_DL_DayOfWeekCalc 同口径）
//      segment 5, the weekday and this week's Thursday, family aligned weekday rule
wd   := jdn MOD 7;                       // 星期序号 / the weekday index
jThu := jdn + 3 - wd;                    // 本周周四（wd=3 即周四自身）/ the Thursday of this week

// 段 6｜ISO 周年归属：本周四落在哪个公历年即归属该年
//      segment 6, the ISO year attribution by where this week's Thursday falls
//      三个元旦 JDN 用「本年元旦 ± 365/366」等差推算（闰差由闰年判据决定），
//      不引入辅助 POU，保持单文件自洽：
//      the three Jan 1 JDNs are derived arithmetically, no helper POU, single file self contained
jJanY    := 1 + (153 * 10 + 2) DIV 5 + 365 * (y + 4800 - 1) + (y + 4800 - 1) DIV 4
            - (y + 4800 - 1) DIV 100 + (y + 4800 - 1) DIV 400 - 32045;
            // 本年元旦 JDN（1 月：a=1, m2=10, d=1 代入段 4 同式）/ this year Jan 1 JDN, month terms substituted
bLeap    := ((y MOD 4 = 0) AND (y MOD 100 <> 0)) OR (y MOD 400 = 0);          // 本年闰否 [-] / this year leap flag
IF bLeap THEN
    jJanNext := jJanY + 366;             // 本年为闰 → 次年元旦 = 本年元旦 + 366 / the next Jan 1 is 366 days ahead
ELSE
    jJanNext := jJanY + 365;             // 平年 365 / 365 in a common year
END_IF
IF ((y - 1) MOD 4 = 0) AND NOT (((y - 1) MOD 100 = 0) AND ((y - 1) MOD 400 <> 0)) THEN
    jJanPrev := jJanY - 366;             // 前年为闰 → 本年元旦 = 前年元旦 + 366 / the previous year was leap
ELSE
    jJanPrev := jJanY - 365;             // 前年平年 / the previous year was common
END_IF
IF jThu >= jJanNext THEN                 // 周四落次年 → 归次年 / the Thursday in the next year
    isoY := y + 1;
    jRef := jJanNext;
ELSIF jThu >= jJanY THEN                 // 周四落本年 → 归本年 / the Thursday in this year
    isoY := y;
    jRef := jJanY;
ELSE                                     // 周四落前年 → 归前年 / the Thursday in the previous year
    isoY := y - 1;
    jRef := jJanPrev;
END_IF

// 段 7｜ISO 周年首个周四：从元旦起找第一个 wd=3（周四）
//      segment 7, the ISO year's first Thursday from its Jan 1
wd0101 := jRef MOD 7;                    // 元旦星期序号 / the Jan 1 weekday
IF wd0101 <= 3 THEN
    off := 3 - wd0101;                   // 周四在本周内，向前推 / the Thursday is inside this week
ELSE
    off := 10 - wd0101;                  // 周四在下一周，跨周推 / the Thursday falls into the next week
END_IF
jThu1 := jRef + off;                     // 首个周四 JDN / the first Thursday JDN

// 段 8｜周号整除求解：两周四之差恒为 7 的倍数，DIV 无余数陷阱
//      segment 8, the week number by exact division of two Thursdays
nWeek := (jThu - jThu1) DIV 7 + 1;       // 周号 1~53 [周] / the week number, 1 to 53
IF (nWeek < 1) OR (nWeek > 53) THEN      // 防御性输出域闸（整数法结构上不越域，留档）/ defensive output domain gate
    nErrId := WIC_ERR_DATE;
    RETURN;
END_IF

// 段 9｜出口（ISO 周年归属逻辑上恒在 1989~2101，转 UINT 安全）
//      segment 9, exit, the ISO year stays inside the UINT safe range by construction
nIsoWeek := DINT_TO_UINT(nWeek);         // 发布周号 / publish the week number
nIsoYear := DINT_TO_UINT(isoY);          // 发布周年 / publish the week year
bValid   := TRUE;                        // 结果可用 / the result is usable
FC_DL_WeekNumIsoCalc := nIsoWeek;        // 返回值与输出同源（R191 名实双出口）/ the return mirrors the output
END_FUNCTION
