(*
  ==================================================================
  组件名 Component  : FB_DL_FormationWeekPlan
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 周计划窗（周序号闸 + 月窗闸双闸）。把日历日换算成「月内周
                      序号（1..5）」与「周内日序号（1..7）」，两个闸同时成立才算
                      计划窗开启：一 月窗闸 = 当日落在组态的月内生产窗区间；
                      二 周序号闸 = 当日所在周序号落在允许的周区间。
                      同时给出周内与月内剩余天数，供上层排产节拍使用。
  溯源   Origin     : 周序号 / 月窗双闸为通用排产窗语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-weekplan），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（INT 整除与 MOD，除子为常量，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只判双闸与剩余天数，不生成工单、不判产量；
                      二 周序号按「月内第几周」口径（1 日为第 1 周第 1 日），非 ISO 周；
                      三 整除与取模的除子均为常量 7，且除前已把日序回钳到 1..31；
                      四 双闸任一不成立即关窗，关窗原因由两个独立布尔出口区分（R190）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bMonthGateOk / bWeekGateOk 为两条独立闸的实时值，
                      bWindowOpen 仅在两条闸同时成立时为真（挂状态量）；
                      nWeekIdx 域 1..5，nDayInWeek 域 1..7，两者恒由回钳后的日序派生；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 2 · 序号 9）
  ==================================================================
*)

TYPE E_DL_FwpCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：年月日、窗界或周区间越域（故障级，与 bError 配对）/ illegal config, calendar, window bounds or week band out of domain
    eMonthGate  := 2,   // 月窗闸不成立（信息级）/ the monthly window gate does not hold, informational
    eWeekGate   := 3    // 周序号闸不成立（信息级）/ the week index gate does not hold, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_FormationWeekPlan
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时关窗 [-] / enable, the window closes when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存 [-] / reset rising edge clears the fault latch
    nYear        : INT := 2026;              // 当前年份 [年]，域 2000..2100 / current year [year], domain 2000 to 2100
    nMonth       : INT := 1;                 // 当前月份 [月]，域 1..12 / current month [month], domain 1 to 12
    nDayOfMonth  : INT := 1;                 // 当月第几日 [日]，域 1..31 / day of month [day], domain 1 to 31
    nWinStartDay : INT := 1;                 // 月生产窗起始日 [日] / monthly production window start day [day]
    nWinEndDay   : INT := 28;                // 月生产窗结束日 [日]，须不早于起始日 / monthly window end day, not earlier than the start
    nWeekFrom    : INT := 1;                 // 允许的周序号下限（月内第几周）[周]，域 1..5 / allowed week index floor, domain 1 to 5
    nWeekTo      : INT := 5;                 // 允许的周序号上限（月内第几周）[周]，域 1..5 / allowed week index ceiling, domain 1 to 5
END_VAR
VAR_OUTPUT
    bWindowOpen  : BOOL := FALSE;            // 双闸同时成立（计划窗开启）[-] / both gates hold, the planning window is open
    bMonthGateOk : BOOL := FALSE;            // 月窗闸实时值 [-] / monthly window gate live value
    bWeekGateOk  : BOOL := FALSE;            // 周序号闸实时值 [-] / week index gate live value
    nWeekIdx     : INT := 1;                 // 月内周序号 [周]，域 1..5 / week index within the month, domain 1 to 5
    nDayInWeek   : INT := 1;                 // 周内日序号 [日]，域 1..7 / day index within the week, domain 1 to 7
    nRemainInWeek: INT := 0;                 // 本周剩余天数（不跨月）[日] / remaining days this week, not crossing the month
    nRemainInMonth : INT := 0;               // 本月剩余天数 [日] / remaining days this month
    nPlanDays    : INT := 0;                 // 本窗剩余可排产天数（双闸内计数）[日] / remaining plannable days inside the window
    eCause       : E_DL_FwpCause := E_DL_FwpCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eFaultCause : E_DL_FwpCause := E_DL_FwpCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bMonthGate  : BOOL := FALSE;            // 月窗闸工作值 [-] / monthly window gate working value
    _bWeekGate   : BOOL := FALSE;            // 周序号闸工作值 [-] / week index gate working value
    _nDaysInMonth: INT := 30;                // 当月日历天数 [日] / calendar days of the current month [day]
    _nDay        : INT := 1;                 // 回钳后的当日序号 [日] / clamped day index [day]
    _nStart      : INT := 1;                 // 回钳后的窗起始日 [日] / clamped window start day [day]
    _nEnd        : INT := 1;                 // 回钳后的窗结束日 [日] / clamped window end day [day]
    _nWeekFrom   : INT := 1;                 // 回钳后的周序号下限 [周] / clamped week index floor [week]
    _nWeekTo     : INT := 5;                 // 回钳后的周序号上限 [周] / clamped week index ceiling [week]
    _nWeekIdx    : INT := 1;                 // 周序号工作值 [周] / week index working value [week]
    _nDayInWeek  : INT := 1;                 // 周内日序号工作值 [日] / day in week working value [day]
    _nRemainWeek : INT := 0;                 // 本周剩余天数工作值 [日] / remaining week days working value [day]
    _nRemainMonth: INT := 0;                 // 本月剩余天数工作值 [日] / remaining month days working value [day]
    _nPlanDays   : INT := 0;                 // 窗内剩余可排产天数工作值 [日] / remaining plannable days working value [day]
    _nScanDay    : INT := 1;                 // 窗内扫描用日序（自当日到窗末）[日] / scanning day index from today to the window end [day]
END_VAR
VAR CONSTANT
    DL_FWP_DAY_MAX   : INT := 31;            // 月内最大天数 [日] / maximum days within a month [day]
    DL_FWP_WEEK_N    : INT := 7;             // 一周日数，整除去子（常量非零）[日] / days per week, the division divisor as a non-zero constant [day]
    DL_FWP_WEEK_MAX  : INT := 5;             // 月内最大周序号 [周] / maximum week index within a month [week]
    DL_FWP_YEAR_MIN  : INT := 2000;          // 年份下限 [年] / year floor [year]
    DL_FWP_YEAR_MAX  : INT := 2100;          // 年份上限 [年] / year ceiling [year]
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the reset edge, never inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eFaultCause := E_DL_FwpCause.eNone; // 故障级成因清零 / clear the fault cause
    _nWeekIdx := 1; // 周序号从第一周起 / the week index starts at one
    _nDayInWeek := 1; // 周内日序号从第一日起 / the day in week starts at one
END_IF

// 段 2｜复位沿作用域：清故障锁存与故障级成因（不动日历派生量）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_FwpCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
END_IF

// 段 3｜日历天数：闰年二月二十九日 / segment 3, calendar days with a leap February
_nDaysInMonth := 31; // 默认三十一日 / default thirty one days
CASE nMonth OF
1, 3, 5, 7, 8, 10, 12: // 大月 / long months
    _nDaysInMonth := 31; // 三十一日 / thirty one days
2: // 二月 / february
    IF ((nYear MOD 4) = 0) AND (((nYear MOD 100) <> 0) OR ((nYear MOD 400) = 0)) THEN // 闰年判据 / leap year criterion
        _nDaysInMonth := 29; // 闰年二十九日 / twenty nine days in a leap year
    ELSE
        _nDaysInMonth := 28; // 平年二十八日 / twenty eight days in a common year
    END_IF
4, 6, 9, 11: // 小月 / short months
    _nDaysInMonth := 30; // 三十日 / thirty days
ELSE // 非法月份兜底（R128）/ illegal month fallback
    _nDaysInMonth := 30; // 兜底三十日，故障另由域闸锁存 / fall back to thirty days, the fault is latched by the domain gate
END_CASE

// 段 4｜组态域闸（R151 全覆盖）/ segment 4, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (nYear < DL_FWP_YEAR_MIN) OR (nYear > DL_FWP_YEAR_MAX) THEN // 年份越域 / year out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nMonth < 1) OR (nMonth > 12) THEN // 月份越域 / month out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nDayOfMonth < 1) OR (nDayOfMonth > DL_FWP_DAY_MAX) THEN // 当日序号越域 / day index out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nWinStartDay < 1) OR (nWinStartDay > DL_FWP_DAY_MAX) OR (nWinEndDay < nWinStartDay) OR (nWinEndDay > DL_FWP_DAY_MAX) THEN // 窗界越域或自相矛盾 / window bounds out of domain or contradicting
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nWeekFrom < 1) OR (nWeekFrom > DL_FWP_WEEK_MAX) OR (nWeekTo < nWeekFrom) OR (nWeekTo > DL_FWP_WEEK_MAX) THEN // 周区间越域或自相矛盾 / week band out of domain or contradicting
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_FwpCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF

// 段 5｜回钳：日序、窗界、周区间一律回钳到可比较域 / segment 5, clamping the day, the window bounds and the week band
_nDay := nDayOfMonth; // 日序直通 / day index passes through
IF _nDay < 1 THEN // 下越界 / below the lower bound
    _nDay := 1; // 回钳到一日 / clamp to day one
ELSIF _nDay > _nDaysInMonth THEN // 上越界 / above the upper bound
    _nDay := _nDaysInMonth; // 回钳到月末 / clamp to the last day
END_IF
_nStart := nWinStartDay; // 窗起始日直通 / window start passes through
IF _nStart < 1 THEN // 下越界 / below the lower bound
    _nStart := 1; // 回钳到一日 / clamp to day one
ELSIF _nStart > _nDaysInMonth THEN // 上越界 / above the upper bound
    _nStart := _nDaysInMonth; // 回钳到月末 / clamp to the last day
END_IF
_nEnd := nWinEndDay; // 窗结束日直通 / window end passes through
IF _nEnd < _nStart THEN // 结束早于起始 / end earlier than start
    _nEnd := _nStart; // 回钳到起始日 / clamp to the start day
ELSIF _nEnd > _nDaysInMonth THEN // 上越界 / above the upper bound
    _nEnd := _nDaysInMonth; // 回钳到月末 / clamp to the last day
END_IF
_nWeekFrom := nWeekFrom; // 周下限直通 / the week floor passes through
IF _nWeekFrom < 1 THEN // 下越界 / below the lower bound
    _nWeekFrom := 1; // 回钳到第一周 / clamp to the first week
ELSIF _nWeekFrom > DL_FWP_WEEK_MAX THEN // 上越界 / above the upper bound
    _nWeekFrom := DL_FWP_WEEK_MAX; // 回钳到第五周 / clamp to the fifth week
END_IF
_nWeekTo := nWeekTo; // 周上限直通 / the week ceiling passes through
IF _nWeekTo < _nWeekFrom THEN // 上限早于下限 / ceiling earlier than the floor
    _nWeekTo := _nWeekFrom; // 回钳到下限 / clamp to the floor
ELSIF _nWeekTo > DL_FWP_WEEK_MAX THEN // 上越界 / above the upper bound
    _nWeekTo := DL_FWP_WEEK_MAX; // 回钳到第五周 / clamp to the fifth week
END_IF

// 段 6｜周序号与周内日序号派生：除子为常量 7，日序已回钳 1..31 / segment 6, week index and day in week derived with the constant divisor seven
_nWeekIdx := ((_nDay - 1) / DL_FWP_WEEK_N) + 1; // 月内周序号，整除除子为常量七 / week index within the month with the constant divisor seven
IF _nWeekIdx < 1 THEN // 下越界（防御）/ below the lower bound as a defence
    _nWeekIdx := 1; // 回钳到第一周 / clamp to the first week
ELSIF _nWeekIdx > DL_FWP_WEEK_MAX THEN // 上越界 / above the upper bound
    _nWeekIdx := DL_FWP_WEEK_MAX; // 回钳到第五周 / clamp to the fifth week
END_IF
_nDayInWeek := ((_nDay - 1) MOD DL_FWP_WEEK_N) + 1; // 周内日序，取模除子为常量七 / day in week with the constant divisor seven
IF _nDayInWeek < 1 THEN // 下越界（防御）/ below the lower bound as a defence
    _nDayInWeek := 1; // 回钳到第一日 / clamp to the first day
ELSIF _nDayInWeek > DL_FWP_WEEK_N THEN // 上越界 / above the upper bound
    _nDayInWeek := DL_FWP_WEEK_N; // 回钳到第七日 / clamp to the seventh day
END_IF

// 段 7｜双闸判定：月窗闸与周序号闸各自独立（R190 归因唯一）/ segment 7, the two gates evaluated independently
_bMonthGate := (_nDay >= _nStart) AND (_nDay <= _nEnd); // 月窗闸：当日落在月生产窗内 / monthly window gate
_bWeekGate := (_nWeekIdx >= _nWeekFrom) AND (_nWeekIdx <= _nWeekTo); // 周序号闸：周序号落在允许区间 / week index gate
IF NOT bEnable THEN // 失能：关窗（R191 显式声明）/ disabled, the window closes
    _bMonthGate := FALSE; // 月窗闸撤除 / the monthly gate is withdrawn
    _bWeekGate := FALSE; // 周序号闸撤除 / the week gate is withdrawn
END_IF

// 段 8｜剩余天数：周内剩余不跨月，窗内剩余按双闸逐日推演 / segment 8, remaining days within the week and inside the window
_nRemainWeek := DL_FWP_WEEK_N - _nDayInWeek; // 本周剩余天数（跨月部分由下一行截断）/ remaining days this week, truncated by the next line
IF (_nDay + _nRemainWeek) > _nDaysInMonth THEN // 周尾越过月末 / the week tail crosses the month end
    _nRemainWeek := _nDaysInMonth - _nDay; // 截断到月末 / truncated at the month end
END_IF
IF _nRemainWeek < 0 THEN // 防御：负值不可能 / defence, a negative value is impossible
    _nRemainWeek := 0; // 钳零 / clamped to zero
END_IF
_nRemainMonth := _nDaysInMonth - _nDay; // 本月剩余天数 / remaining days this month
IF _nRemainMonth < 0 THEN // 防御：负值不可能 / defence, a negative value is impossible
    _nRemainMonth := 0; // 钳零 / clamped to zero
END_IF
_nPlanDays := 0; // 窗内剩余可排产天数清零 / clear the remaining plannable days
IF _bMonthGate AND _bWeekGate THEN // 双闸内才逐日推演 / the day sweep only runs inside both gates
    _nScanDay := _nDay; // 自当日起扫 / sweep from today
    WHILE _nScanDay <= _nEnd DO // 扫到窗末为止，上界为回钳后的窗末日 / sweep up to the window end
        IF ((((_nScanDay - 1) / DL_FWP_WEEK_N) + 1) >= _nWeekFrom) AND ((((_nScanDay - 1) / DL_FWP_WEEK_N) + 1) <= _nWeekTo) THEN // 该日的周序号落在允许区间 / the week index of that day is inside the band
            _nPlanDays := _nPlanDays + 1; // 计入可排产天数 / count as a plannable day
        END_IF
        _nScanDay := _nScanDay + 1; // 日序递增 / increment the day index
    END_WHILE
END_IF

// 段 9｜成因分派（固定优先级：故障 > 月窗闸 > 周序号闸 > 无成因）/ segment 9, cause dispatch with a fixed priority
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSIF (NOT _bMonthGate) AND _bWeekGate THEN // 仅月窗闸不成立 / only the monthly gate fails
    eCause := E_DL_FwpCause.eMonthGate; // 信息级成因 / informational cause
ELSIF _bMonthGate AND (NOT _bWeekGate) THEN // 仅周序号闸不成立 / only the week gate fails
    eCause := E_DL_FwpCause.eWeekGate; // 信息级成因 / informational cause
ELSIF (NOT _bMonthGate) AND (NOT _bWeekGate) THEN // 两闸均不成立 / both gates fail
    eCause := E_DL_FwpCause.eMonthGate; // 按月窗闸优先报告（上游先解除大闸）/ report the monthly gate first because the upstream gate must clear first
ELSE
    eCause := E_DL_FwpCause.eNone; // 双闸内无成因 / no cause inside both gates
END_IF

// 段 10｜统一出口 / segment 10, unified outlet
bMonthGateOk := _bMonthGate; // 月窗闸出口 / monthly gate outlet
bWeekGateOk := _bWeekGate; // 周序号闸出口 / week gate outlet
bWindowOpen := _bMonthGate AND _bWeekGate; // 双闸合成（挂状态量，非单拍标志）/ the composite gate as a state quantity
nWeekIdx := _nWeekIdx; // 周序号出口 / week index outlet
nDayInWeek := _nDayInWeek; // 周内日序号出口 / day in week outlet
nRemainInWeek := _nRemainWeek; // 本周剩余天数出口 / remaining week days outlet
nRemainInMonth := _nRemainMonth; // 本月剩余天数出口 / remaining month days outlet
nPlanDays := _nPlanDays; // 窗内可排产天数出口 / remaining plannable days outlet
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
