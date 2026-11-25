// FC_DL_WorkdayCalendarCalc v1.0.0
// 开源溯源：self-cleanroom / 公历算法（Fliegel-Van Flandern 公开公式）
(*
  道莅工业代码库 | DL_Base | FC_DL_WorkdayCalendarCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 日期区间工作日计数（周一~周五，剔除内嵌节假日表命中项）；
        儒略日数算法取星期，整周×5 + 余数逐日扫描，节假日逐项扣减
  邻件关系: 与 WeekNumIsoCalc / DateDiffDays / DayOfWeekCalc 同族 —— 差异点：
            周号件算 ISO 周、差值件算自然日差，本件算工作日净计数（含
            节假日剔除），星期口径经 JDN MOD 7 自证（2026-11-23 周一 = 0）
  日期契约: 入参为 DINT 型 yyyymmdd 十进制编码（如 20261123）；
            节假日表 aHoliday 同口径，nHolidayCnt 个有效（0..16）
*)
FUNCTION FC_DL_WorkdayCalendarCalc : DINT
VAR_INPUT
    dStart       : DINT;                          // 起始日期 [yyyymmdd 编码] / Start date as yyyymmdd
    dEnd         : DINT;                          // 结束日期（含当日）[yyyymmdd] / End date inclusive, as yyyymmdd
    aHoliday     : ARRAY[1..16] OF DINT;          // 节假日表 [yyyymmdd 编码] / Holiday table as yyyymmdd
    nHolidayCnt  : INT;                           // 节假日有效个数 [个]，域 0..16 / Valid holiday count
END_VAR
VAR_OUTPUT
    bValid       : BOOL;                          // 结果有效回执 [-] / Result validity receipt
    nWorkdays    : DINT;                          // 工作日计数 [天] / Workday count [days]
    uErrorId     : UDINT;                         // 事件码，0 = 无事件；16#0002_2301 = 日期非法 / Event code
END_VAR
VAR
    nSx          : DINT;                          // 起始年 [年] / Start year
    nSm          : DINT;                          // 起始月 [月] / Start month
    nSd          : DINT;                          // 起始日 [日] / Start day
    nEx          : DINT;                          // 结束年 [年] / End year
    nEm          : DINT;                          // 结束月 [月] / End month
    nEd          : DINT;                          // 结束日 [日] / End day
    nTmp         : DINT;                          // 交换/中间量 [—] / Swap temp
    nTotalDays   : DINT;                          // 区间自然日总数（含端点）[天] / Total days inclusive
    nJdnS        : DINT;                          // 起始儒略日数 [天] / Start JDN
    nFullWeeks   : DINT;                          // 整周数 [周] / Full weeks
    nRemain      : DINT;                          // 余数天数 [天] / Remainder days
    nCount       : DINT;                          // 工作日累计 [天] / Workday accumulator
    nDow         : DINT;                          // 星期（0=周一..6=周日）[1] / Day of week, 0=Mon..6=Sun
    nJdnCur      : DINT;                          // 余数段当前儒略日 [天] / Current JDN in remainder scan
    h            : INT;                           // 节假日表索引 [个] / Holiday table index
    dHol         : DINT;                          // 当前节假日 [yyyymmdd] / Current holiday
    nJdnHol      : DINT;                          // 节假日儒略日 [天] / Holiday JDN
    bHolInRange  : BOOL;                          // 节假日落在区间内 [-] / Holiday within range
END_VAR
VAR CONSTANT
    DL_WDC_JDN_EPOCH_OFF : DINT := 32075;         // Fliegel 公式尾部常数 [天] / Fliegel tail constant
END_VAR

// —— 段 0：全路径缺省 —— //
bValid := FALSE;                                     // 有效回执预清 / Validity preset
nWorkdays := 0;                                      // 计数缺省零 / Count default zero
uErrorId := 16#0000;                                 // 事件码预清 / Event code preset
FC_DL_WorkdayCalendarCalc := 0;                      // 返回值缺省零 / Return default zero

// —— 段 1：日期编码与区间闸（格式 + 序向） —— //
IF dStart > dEnd THEN                                // 起点晚于终点：交换（宽容序）/ Swap tolerant order
    nTmp := dStart;
    dStart := dEnd;
    dEnd := nTmp;
END_IF
nSx := dStart / 10000;                               // 年提取 [年] / Year extract
nSm := (dStart MOD 10000) / 100;                     // 月提取 [月] / Month extract
nSd := dStart MOD 100;                               // 日提取 [日] / Day extract
nEx := dEnd / 10000;
nEm := (dEnd MOD 10000) / 100;
nEd := dEnd MOD 100;
IF (nSm < 1) OR (nSm > 12) OR (nEm < 1) OR (nEm > 12)
   OR (nSd < 1) OR (nSd > 31) OR (nEd < 1) OR (nEd > 31) THEN   // 月日域闸 / Month and day domain gate
    uErrorId := 16#0002_2301;                        // 信息级：日期编码非法 / Info level: illegal date code
    RETURN;
END_IF
IF (nHolidayCnt < 0) OR (nHolidayCnt > 16) THEN      // 节假日计数域闸 / Holiday count gate
    uErrorId := 16#0002_2301;                        // 计数非法同码段 / Same code family
    RETURN;
END_IF

// —— 段 2：儒略日数（Fliegel-Van Flandern，整数除即 ST DIV 截断口径） —— //
nJdnS := (1461 * (nSx + 4800 + (nSm - 14) / 12)) / 4
         + (367 * (nSm - 2 - 12 * ((nSm - 14) / 12))) / 12
         - (3 * ((nSx + 4900 + (nSm - 14) / 12) / 100)) / 4
         + nSd - DL_WDC_JDN_EPOCH_OFF;               // 起始 JDN [天] / Start JDN
nTmp := (1461 * (nEx + 4800 + (nEm - 14) / 12)) / 4
        + (367 * (nEm - 2 - 12 * ((nEm - 14) / 12))) / 12
        - (3 * ((nEx + 4900 + (nEm - 14) / 12) / 100)) / 4
        + nEd - DL_WDC_JDN_EPOCH_OFF;                // 结束 JDN（复用暂存）/ End JDN
nTotalDays := nTmp - nJdnS + 1;                      // 含端点自然日 [天] / Inclusive day count

// —— 段 3：整周×5 工作日基数 —— //
nFullWeeks := nTotalDays / 7;                        // 整周数 [周] / Full weeks
nRemain := nTotalDays - nFullWeeks * 7;              // 余数天 [天] / Remainder days
nCount := nFullWeeks * 5;                            // 整周工作日基数 [天] / Full-week weekday base

// —— 段 4：余数段逐日扫描（起点 JDN 起，nRemain ≤ 6 循环有界） —— //
nJdnCur := nJdnS;                                    // 扫描游标 [天] / Scan cursor
FOR nTmp := 1 TO nRemain DO                           // 余数天逐日（≤6 次）/ Day scan, bounded
    nDow := (nJdnCur MOD 7);                         // 星期 0=周一..6=周日（自证：2026-11-23 JDN MOD 7 = 0 = 周一）/ Dow 0=Mon..6=Sun
    IF nDow <= 4 THEN                                // 周一~周五 / Monday to Friday
        nCount := nCount + 1;                        // 工作日累加 / Count workday
    END_IF
    nJdnCur := nJdnCur + 1;                          // 游标前进 / Advance cursor
END_FOR

// —— 段 5：节假日扣减（表内逐项：在区间内且为工作日则扣 1） —— //
FOR h := 1 TO nHolidayCnt DO                         // 逐节假日（h ≤ nHolidayCnt ≤ 16 判界安全）/ Per holiday, index safe
    dHol := aHoliday[h];                             // 取节假日编码 / Holiday code
    IF (dHol MOD 10000) / 100 >= 1 AND (dHol MOD 10000) / 100 <= 12 AND (dHol MOD 100 >= 1) AND (dHol MOD 100 <= 31) THEN
        nJdnHol := (1461 * (dHol / 10000 + 4800 + ((dHol MOD 10000) / 100 - 14) / 12)) / 4
                   + (367 * ((dHol MOD 10000) / 100 - 2 - 12 * (((dHol MOD 10000) / 100 - 14) / 12))) / 12
                   - (3 * ((dHol / 10000 + 4900 + ((dHol MOD 10000) / 100 - 14) / 12) / 100)) / 4
                   + (dHol MOD 100) - DL_WDC_JDN_EPOCH_OFF;   // 节假日 JDN [天] / Holiday JDN
        bHolInRange := (nJdnHol >= nJdnS) AND (nJdnHol <= nJdnS + nTotalDays - 1);   // 区间内判据 / In-range test
        IF bHolInRange THEN
            nDow := (nJdnHol MOD 7);                 // 节假日星期 [1] / Holiday dow
            IF nDow <= 4 THEN                        // 仅工作日节假日扣减（周末节假日已不在基数）/ Deduct only weekday holidays
                nCount := nCount - 1;                // 扣减 / Deduct
            END_IF
        END_IF
    END_IF
END_FOR

// —— 段 6：输出收口 —— //
IF nCount < 0 THEN
    nCount := 0;                                     // 负值兜底（防御）/ Negative guard
END_IF
nWorkdays := nCount;                                 // 计数输出 / Count output
bValid := TRUE;                                      // 有效回执 / Validity receipt
FC_DL_WorkdayCalendarCalc := nCount;                 // 返回值 = 工作日数 / Return equals count
END_FUNCTION
