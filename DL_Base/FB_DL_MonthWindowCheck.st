(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MonthWindowCheck
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 时间窗判定功能块（Function Block · Date and Timer）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / MOD / CASE），零厂商方言
 * 功能简介 (Function)   : 月内第 N 天 / 月末倒数第 N 天的日期窗判定（支持窗口
 *                         宽度天数：目标日起连续 n 天）。可选年度模式（仅指定
 *                         月份生效，用于年度保养窗 / 年度盘点窗）。闰年与月长
 *                         规则独立实现（思想与已入库 FC_DL_DayOfWeekCalc 同源，
 *                         本块仅做月长计算、不做星期推导，注释声明同源不调用）；
 *                         日期全部由引脚注入（沿用 R5「时间由引脚注入」修正，
 *                         不读平台时钟，纯组合窗判定 + 开窗边沿脉冲）。
 *                         与已入库 FB_DL_TimeWindowCheck（日内时窗）职责分离：
 *                         本块是日粒度月窗，二者正交不互调。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 库 Date and Timer 日期时间分类的
 *                         功能域与参数域，来源标签 lgf-datetime），格里高利
 *                         历闰年规则为公开历法定义，仅借分类/参数域/命名，
 *                         clean-room 实现，未复制任何厂商私有库源码。
 * 日期     (Date)       : 2026-11-15 ｜ 作者 (Author): Daoli Library
 * 依赖     (Depends)    : 无 DL_ 内部调用依赖；Standard.library: R_TRIG
 *
 *------------------------------------------------------------------------------
 * 【引脚契约 / Pin contract】
 *   输入 bEnable       : BOOL — 使能，FALSE 时输出复位（bInWindow FALSE、
 *                               bWindowOpen FALSE、nDaysToTarget -1、码清零）；
 *   输入 nYear         : DINT — 当前年份 [公元年]，如 2026，合法域 >= 1；
 *   输入 nMonth        : DINT — 当前月份 [月]，1~12；
 *   输入 nDay          : DINT — 当前日 [日]，1~当月天数；
 *   输入 nTargetDay    : DINT — 目标日 [日]：正数 = 月内第 N 天（1~31）；
 *                               负数 = 月末倒数第 N 天（-1~-31）；0 = 非法；
 *   输入 nWindowDays   : DINT — 窗口宽度 [日]，1~31，目标日起连续 n 天；
 *   输入 bYearly       : BOOL — TRUE = 年度窗：仅生效月份的月内判定开放；
 *   输入 nYearMonth    : DINT — 年度窗生效月份 [月]，1~12（bYearly = FALSE 忽略）；
 *   输出 bInWindow     : BOOL — 当前日在窗口内（保持型，逐拍重算）；
 *   输出 bWindowOpen   : BOOL — 窗口开启单拍脉冲（R25 三律，R_TRIG 无条件刷新）；
 *   输出 nDaysToTarget : DINT — 相对目标日的天数偏移 [日]，窗口内 = 当前日 −
 *                               目标日（首日 0，逐日递增），窗口外固定 -1；
 *   输出 uErrorId      : UDINT — 故障码，0 = 无故障。
 *
 * 【nDaysToTarget 口径声明 / Countdown semantics（判据写死防误解）】
 *   窗口内：nDaysToTarget := nDay − nTargetAbs（窗口首日 = 0，第 k 日 = k−1），
 *   窗口外（含窗口已过、未到、年度模式非生效月、参数非法、未使能）固定 -1。
 *   口径依据规格「窗口外为 -1，窗内为 0 及以上」两条约束联立推导——
 *   「距目标日剩余天数」按目标日锚点偏移实现，保证 0 值必落在窗口首日，
 *   上层以 nDaysToTarget >= 0 判窗内、以 0 判开窗首日，无二义。
 *
 * 【月长与闰年 / Month length and leap year（独立实现声明）】
 *   闰年：能被 4 整除且不能被 100 整除，或能被 400 整除 → 二月 29 天；
 *   月长：1/3/5/7/8/10/12 月 31 天，4/6/9/11 月 30 天，2 月按闰年 28/29；
 *   本规则与已入库 FC_DL_DayOfWeekCalc 的闰年思想同源（公开格里高利历
 *   定义），本块独立实现、不调用该组件（泳道零互相依赖红线）。
 *
 * 【窗口口径 / Window semantics】
 *   窗口 = [nTargetAbs, nTargetAbs + nWindowDays − 1]，右端超过当月天数时
 *   截断到月末（窗口跨月末不跨月，注释写死；截断属口径而非错误，不置码）。
 *   月末倒数口径：nTargetAbs = 当月天数 − |nTargetDay| + 1（倒数第 1 天 =
 *   月末日），|nTargetDay| 超过当月天数时钳位到当月天数（31 在 2 月自动
 *   收缩到 28/29），钳位置信息级码。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 nYear < 1 / nMonth 越界（非 1~12）/ nDay 越界（非 1~当月长）/
 *      nTargetDay = 0 → 置 16#0001_0203，bInWindow FALSE，不判定不误报；
 *   B2 nTargetDay 绝对值钳位 1~当月天数（正超钳到月末、负超钳到月长，
 *      钳位先于取负运算，杜绝 DINT 极值取负回绕穿透）；
 *   B3 nWindowDays 钳位 1~31，nYearMonth 钳位 1~12，均置信息级 16#0001_0109；
 *   B4 bYearly = TRUE 且非生效月 → 直接 FALSE 且不置任何故障码（规格写死）；
 *   B5 bWindowOpen 单拍脉冲遵循 R25 三律：R_TRIG 主周期无条件刷新、
 *      边沿基准 bInWindow 单一来源、脉冲仅开窗拍置位下一拍自清；
 *   B6 全部故障码为信息级瞬时型，每拍重算（预清零 + 逐段置位），无锁存。
 *
 * 【单拍标志 R25 三律落地 / One-shot pulse lifecycle】
 *   置位律：bWindowOpen 仅在 bInWindow 由 FALSE 变 TRUE 的扫描拍为 TRUE；
 *   自清律：bInWindow 每拍预清 FALSE 后重算，R_TRIG.Q 无沿自动回落 FALSE；
 *   基准律：边沿基准唯一来源为输出 bInWindow 本身（保持型逐拍重算），
 *   不存在第二份镜像状态，杜绝基准漂移。
 *
 * 【调用示例 / Call example】
 *   「月末倒数第 3 天起开 5 天年度保养窗（仅 12 月生效）」
 *   fbMonthWin(bEnable := TRUE, nYear := 2026, nMonth := 12, nDay := nToday,
 *              nTargetDay := -3, nWindowDays := 5, bYearly := TRUE,
 *              nYearMonth := 12, bInWindow => bMaintWin,
 *              bWindowOpen => bMaintWinOpen, nDaysToTarget => nToTarget,
 *              uErrorId => uWinErr);
 *
 * 【平台移植注意 / Porting notes】
 *   DINT 的 MOD 与负数取负均为 IEC 61131-3 标准语义；本块通过边界 B2 的
 *   「钳位先于取负」次序，保证取负运算的绝对值不超过 31，远离 DINT 极值，
 *   不触发任何平台相关的极值回绕方言。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 设备月度保养窗：每月 25 日起开 5 天保养允许窗，窗内放行保养工单；
 *   ② 月末盘点窗：月末倒数第 2 天起开 3 天盘点冻结窗，窗内禁止库存异动；
 *   ③ 年度大保养：bYearly = TRUE 且 nYearMonth = 7，仅每年 7 月的指定日段
 *      放行年度检修流程，其余月份自动关闭不报错；
 *   ④ 计量器具月检提醒：nDaysToTarget 从窗口首日 0 起递增，驱动 HMI 上
 *      "窗口第 N 天"提示与窗口末日前的催办逻辑。
 *
 * 【参数组合矩阵 / Parameter combination matrix】
 *   nTargetDay > 0  ：月内第 N 天开窗（正向锚点，1 = 1 日）；
 *   nTargetDay < 0  ：月末倒数第 N 天开窗（反向锚点，-1 = 月末日）；
 *   nWindowDays = 1 ：单日窗（仅目标日当天）；
 *   nWindowDays > 1 ：连续多日窗，右端自动截断到月末；
 *   bYearly = FALSE ：每月都按同参数判定（月度模式）；
 *   bYearly = TRUE  ：仅 nYearMonth 指定月判定，其余月输出全 FALSE 零码。
 *
 * 【典型时序推演 / Typical timing walkthrough】
 *   设 2026-12，nTargetDay = -3，nWindowDays = 5：
 *     目标日 = 31 − 3 + 1 = 29；窗口 = [29, 33] → 截断 [29, 31]；
 *     nDay = 28 → FALSE / -1        （窗前一日）
 *     nDay = 29 → TRUE  / 开窗脉冲 / 0（窗口首日）
 *     nDay = 30 → TRUE  / 无脉冲   / 1
 *     nDay = 31 → TRUE  / 无脉冲   / 2（窗口末日）
 *     nDay = 1（次月）→ FALSE / -1（不跨月，下月按新月长重判）
 *   开窗脉冲仅 29 日当天一拍，次日起 bInWindow 保持 TRUE 而脉冲回落。
 *
 * 【同族职责分离 / Family separation】
 *   FB_DL_TimeWindowCheck：日内时分秒粒度时窗（TOD 比较）；本块：日粒度
 *   月窗（月长/闰年/月内日号），粒度与口径正交；FC_DL_DayOfWeekCalc：
 *   星期推导（思想同源，本块不调用）；三者零互相调用。
 *
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓ ｜ R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 标准运算 ✓ ｜ R4 日期三重校验+钳位
 *                           先于取负+窗口不跨月截断 ✓
 *                         R5 全变量中英双语同行注释 ✓ ｜ R6 月长 CASE 含 ELSE
 *                           兜底；无主状态机（纯组合窗判定，规格豁免）✓
 *                         R7 R_TRIG 主周期无条件刷新（不置于 IF/CASE 内）✓
 *                         R8 月长/月数/窗宽界限全常量化 ✓
 * 验收推演 (Acceptance) :
 *   W1 2026-12，nTargetDay = -3（月末倒数第 3 = 29 日），nWindowDays = 5，
 *      nDay = 29 → bInWindow TRUE，bWindowOpen 单拍 TRUE，nDaysToTarget = 0；
 *   W2 同上 nDay = 31 → bInWindow TRUE（窗口截断到 31），nDaysToTarget = 2；
 *   W3 同上 nDay = 28 → bInWindow FALSE（28 < 29），nDaysToTarget = -1；
 *   W4 2026-02（平年 28 天），nTargetDay = -1 → 目标日 28；nDay = 28 →
 *      bInWindow TRUE，nDaysToTarget = 0；
 *   W5 2028-02（闰年 29 天），nTargetDay = 30 → 钳位 29，置 0109；nDay = 29
 *      → bInWindow TRUE；
 *   W6 bYearly = TRUE，nMonth = 11，nYearMonth = 12 → bInWindow FALSE，
 *      uErrorId = 0（年度过滤不置码）；
 *   W7 nMonth = 13 → 置 0203，bInWindow FALSE；
 *   W8 nTargetDay = 0 → 置 0203，bInWindow FALSE；
 *   W9 bEnable = FALSE → 全输出复位，uErrorId = 0。
 *
 * 【故障码表 / Error code table】
 *   16#0001_0203  日期参数非法：年份 < 1 / 月份非 1~12 / 日非 1~当月长 /
 *                 nTargetDay = 0，本拍不判定，bInWindow FALSE（信息级瞬时码，
 *                 每拍重算；0203 空闲，0201/0202 已被星期/时窗族登记）；
 *   16#0001_0109  参数钳位提示：nTargetDay 绝对值超当月长 / nWindowDays 越界 /
 *                 nYearMonth 越界，按钳位值继续判定（信息级瞬时码，0109 空闲）。
 *
 * 【实现选择 / Implementation choice】
 *   无主状态机：窗判定为纯组合逻辑（参数校验 → 月长解析 → 目标日解析 →
 *   窗口合成 → 区间判定），逐拍全量重算、无跨拍残留状态（除 R_TRIG 内部
 *   边沿基准外），使能撤除即输出复位；月长解析用 CASE nMonth OF 且带 ELSE
 *   兜底（月份虽已在段 2 校验，ELSE 仍拦截非法值，双保险）。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · LGF Date and Timer 组）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_MonthWindowCheck
VAR_INPUT
    bEnable      : BOOL;                   // 使能，FALSE 时输出复位 / Enable, FALSE resets all outputs
    nYear        : DINT;                   // 当前年份 [公元年]，合法域 >= 1 / Current year [calendar year], legal range >= 1
    nMonth       : DINT;                   // 当前月份 [月]，1~12 / Current month [month], 1~12
    nDay         : DINT;                   // 当前日 [日]，1~当月天数 / Current day [day], 1~days in month
    nTargetDay   : DINT;                   // 目标日 [日]，正 = 月内第 N 天，负 = 月末倒数第 N 天，0 非法 / Target day [day], positive = Nth day, negative = Nth day before month end, 0 illegal
    nWindowDays  : DINT := 1;              // 窗口宽度 [日]，1~31，目标日起连续 n 天 / Window width [days], 1~31, consecutive days from target
    bYearly      : BOOL := FALSE;          // TRUE = 年度窗：仅生效月份开放 / TRUE = yearly window, open only in the configured month
    nYearMonth   : DINT := 1;              // 年度窗生效月份 [月]，1~12，非年度模式忽略 / Yearly-window month [month], 1~12, ignored unless yearly
END_VAR
VAR_OUTPUT
    bInWindow    : BOOL;                   // 当前日在窗口内（保持型逐拍重算）/ Today inside the window (held, recomputed each scan)
    bWindowOpen  : BOOL;                   // 窗口开启单拍脉冲（R25 三律）/ Window-open one-shot pulse (R25 three rules)
    nDaysToTarget: DINT := -1;             // 相对目标日天数偏移 [日]，窗内 0 起，窗外 -1 / Day offset relative to target [days], 0+ inside, -1 outside
    uErrorId     : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = none
END_VAR
VAR
    fbTrigOpen   : R_TRIG;                 // 窗口开启边沿（主周期无条件刷新）/ Window-open edge detector (unconditionally refreshed each scan)
    nMonthLen    : DINT;                   // 当月天数 [日] / Number of days in the current month [days]
    nTargetAbs   : DINT;                   // 目标日绝对日号（月内第 N 天口径）/ Absolute day number of the target (Nth-day-of-month basis)
    nTodayAbs    : DINT;                   // 今日绝对日号（= nDay，口径统一中间量）/ Absolute day number of today (equal to nDay, unified intermediate)
    bValid       : BOOL;                   // 参数合法标志（本拍判定闸门）/ Parameter validity flag (this-scan verdict gate)
    nWinDays     : DINT;                   // 钳位后的窗口宽度 [日] / Clamped window width [days]
    nWinEnd      : DINT;                   // 窗口结束日号（不跨月截断后）/ Window end day number (month-clipped)
    nWinMonth    : DINT;                   // 钳位后的年度窗生效月份 [月] / Clamped yearly-window month [month]
    nBack        : DINT;                   // 月末倒数天数工作副本 [日] / Working copy of days counted back from month end [days]
    bLeap        : BOOL;                   // 闰年标志（当年）/ Leap-year flag of the current year
    nClampMask   : UDINT;                  // 本拍钳位事件累计位图（诊断用）/ Accumulated clamp-event bitmap this scan (for diagnostics)
END_VAR
VAR CONSTANT
    DL_MONTH_MAX : DINT := 12;             // 年度月数上限 [月] / Number of months per year
    DL_DAY_MAX   : DINT := 31;             // 单月最大天数 [日]，窗口宽度上界 / Maximum days per month [days], window width upper bound
    DL_YEAR_MIN  : DINT := 1;              // 合法年份下界 [公元年] / Legal year lower bound [calendar year]
    DL_ERR_DATE  : UDINT := 16#0001_0203;  // 日期参数非法故障码 / Error code for invalid date parameters
    DL_ERR_CLAMP : UDINT := 16#0001_0109;  // 参数钳位提示故障码 / Error code for parameter clamping notice
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预清零（R25 自清律 + 信息级瞬时码每拍重算）
 *      Output preset clearing (R25 self-clear rule + transient info codes)
 *      全部输出每拍从安全态重建，不残留上拍结果
 *      All outputs rebuilt from safe state each scan, no last-scan residue
 *-----------------------------------------------------------------------------*)
bInWindow    := FALSE;                    // 窗判定预清 FALSE，段 5 合法路径覆盖 / Window verdict preset FALSE, overwritten by stage 5 on legal paths
bWindowOpen  := FALSE;                    // 开窗脉冲预清 FALSE，段 6 边沿覆盖 / Open pulse preset FALSE, overwritten by stage 6 edge
nDaysToTarget:= -1;                       // 天数偏移预置 -1（窗外安全值）/ Day offset preset to -1 (safe outside value)
uErrorId     := 16#0000_0000;             // 故障码预清零，瞬时码逐段置位 / Error code preset to zero, transient codes raised per stage
nClampMask   := 0;                        // 钳位事件位图清零（Clamp bitmap cleared）
bValid       := TRUE;                     // 参数合法性预置通过（Validity preset to pass）
nTodayAbs    := nDay;                     // 今日日号接管输入（Today's day number takes over the input）

(*------------------------------------------------------------------------------
 * 段 2｜参数校验与钳位（边界 B1/B2/B3）
 *      Parameter validation and clamping (guards B1/B2/B3)
 *      校验失败仅置码关闸，不做部分判定，杜绝非法日期误开窗
 *      Failed checks only raise codes and close the gate, never partial verdicts
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    bValid := FALSE;                       // 未使能：跳过判定，输出保持预清态 / Disabled: skip verdict, outputs stay at preset state
END_IF

IF bValid AND (nYear < DL_YEAR_MIN) THEN
    bValid   := FALSE;                     // 年份非法关闭闸门 / Illegal year closes the gate
    uErrorId := DL_ERR_DATE;               // 置日期参数非法码 / Raise invalid-date code
END_IF

IF bValid AND ((nMonth < 1) OR (nMonth > DL_MONTH_MAX)) THEN
    bValid   := FALSE;                     // 月份非法关闭闸门 / Illegal month closes the gate
    uErrorId := DL_ERR_DATE;               // 置日期参数非法码 / Raise invalid-date code
END_IF

IF bValid AND ((nDay < 1) OR (nDay > DL_DAY_MAX)) THEN
    bValid   := FALSE;                     // 日号粗校验失败（细校验在月长解析后）/ Coarse day check failed (fine check follows month-length parse)
    uErrorId := DL_ERR_DATE;               // 置日期参数非法码 / Raise invalid-date code
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜年度窗生效月钳位（边界 B3/B4）
 *      Yearly-window month clamping (guards B3/B4)
 *   bYearly = FALSE 时 nWinMonth 不使用；bYearly = TRUE 且越界时钳位到 1
 *   并置钳位提示码，保证钳位值本身永远合法，下游无越界分支
 *-----------------------------------------------------------------------------*)
nWinMonth := nYearMonth;                   // 生效月工作副本接管输入 / Working copy takes over the input
IF (nWinMonth < 1) OR (nWinMonth > DL_MONTH_MAX) THEN
    nWinMonth := 1;                        // 钳位到 1 月（Clamp to month 1）
    nClampMask := nClampMask + 1;          // 钳位事件计数（Clamp event counted）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜月长解析与闰年判定（独立实现，思想与 FC_DL_DayOfWeekCalc 同源）
 *      Month-length parse and leap-year verdict (independent implementation)
 *   闰年：能被 4 整除且非整百年，或能被 400 整除（格里高利历公开定义）
 *   Leap year: divisible by 4 and not by 100, or divisible by 400
 *   CASE nMonth OF 自带 ELSE 兜底：月份已校验，ELSE 属双保险拦截
 *   CASE carries an ELSE fallback: month pre-validated, ELSE is double insurance
 *-----------------------------------------------------------------------------*)
IF bValid THEN
    bLeap := ((nYear MOD 4 = 0) AND (nYear MOD 100 <> 0)) OR (nYear MOD 400 = 0); // 闰年判定 / Leap-year verdict

    CASE nMonth OF                         // 月长查表（Day-length lookup）
    1, 3, 5, 7, 8, 10, 12:                 // 大月 31 天 / Long months with 31 days
        nMonthLen := 31;                   // 31 天（31 days）
    4, 6, 9, 11:                           // 小月 30 天 / Short months with 30 days
        nMonthLen := 30;                   // 30 天（30 days）
    2:                                     // 二月按闰年 28/29 / February by leap year
        IF bLeap THEN
            nMonthLen := 29;               // 闰二月 29 天 / Leap February, 29 days
        ELSE
            nMonthLen := 28;               // 平二月 28 天 / Common February, 28 days
        END_IF
    ELSE                                   // 兜底：非法月份拦截（双保险）/ Fallback: illegal month intercepted (double insurance)
        nMonthLen := 0;                    // 月长清零，后续细校验必失败 / Zero length forces the fine check to fail
        bValid   := FALSE;                 // 关闭判定闸门（Close the verdict gate）
        uErrorId := DL_ERR_DATE;           // 置日期参数非法码 / Raise invalid-date code
    END_CASE

    IF bValid AND ((nDay < 1) OR (nDay > nMonthLen)) THEN
        bValid   := FALSE;                 // 日号细校验：超当月长（如 2 月 30 日）/ Fine day check: beyond month length (e.g. Feb 30)
        uErrorId := DL_ERR_DATE;           // 置日期参数非法码 / Raise invalid-date code
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜目标日解析与窗口合成（边界 B2 + 窗口不跨月）
 *      Target-day parse and window assembly (guard B2 + no cross-month)
 *   正目标日：月内第 N 天，超当月长钳到月末（31 在 2 月自动收缩）；
 *   负目标日：月末倒数第 N 天 = 月长 − |N| + 1，|N| 先钳位再取负，
 *   杜绝 DINT 极值取负回绕穿透；窗口右端超月长截断到月末不置码（口径）。
 *-----------------------------------------------------------------------------*)
IF bValid THEN
    IF nTargetDay = 0 THEN
        bValid   := FALSE;                 // 0 既非正也非负序号，判非法 / Zero is neither a forward nor backward index, deemed illegal
        uErrorId := DL_ERR_DATE;           // 置日期参数非法码 / Raise invalid-date code
    ELSIF nTargetDay > 0 THEN
        IF nTargetDay > nMonthLen THEN     // 正向越当月长 / Forward index beyond month length
            nTargetAbs := nMonthLen;    // 钳到月末（Clamp to month end）
            nClampMask := nClampMask + 1; // 钳位事件计数（Clamp event counted）
        ELSE
            nTargetAbs := nTargetDay;   // 月内第 N 天原值生效 / Nth day of month taken as-is
        END_IF
    ELSE
        IF nTargetDay < -nMonthLen THEN    // 负向绝对值超当月长 / Backward magnitude beyond month length
            nBack := nMonthLen;            // 先钳位（不取负，防极值回绕）/ Clamp first (no negation, no extreme-value wrap)
            nClampMask := nClampMask + 1;  // 钳位事件计数（Clamp event counted）
        ELSE
            nBack := -nTargetDay;          // 安全取负（|N| ≤ 31 远离 DINT 极值）/ Safe negation (magnitude at most 31, far from DINT limits)
        END_IF
        nTargetAbs := nMonthLen - nBack + 1; // 月末倒数口径：倒数第 1 = 月末日 / Backward basis: 1st from end = last day
    END_IF
END_IF

IF bValid THEN
    nWinDays := nWindowDays;               // 窗宽工作副本接管输入 / Window-width working copy takes over the input
    IF nWinDays < 1 THEN
        nWinDays := 1;                     // 下钳 1 天（Clamp to 1 day）
        nClampMask := nClampMask + 1;      // 钳位事件计数（Clamp event counted）
    END_IF
    IF nWinDays > DL_DAY_MAX THEN
        nWinDays := DL_DAY_MAX;            // 上钳 31 天（Clamp to 31 days）
        nClampMask := nClampMask + 1;      // 钳位事件计数（Clamp event counted）
    END_IF

    nWinEnd := nTargetAbs + nWinDays - 1;  // 窗口右端合成 / Window right edge assembled
    IF nWinEnd > nMonthLen THEN
        nWinEnd := nMonthLen;              // 截断到月末，窗口不跨月（口径，不置码）/ Clip to month end, window never crosses months (policy, no code)
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜窗判定与年度过滤（边界 B4）
 *      Window verdict and yearly filtering (guard B4)
 *   年度模式非生效月 → 直接 FALSE 且不置任何码（规格写死）；
 *   窗内 nDaysToTarget := 当前日 − 目标日（首日 0），窗外保持 -1。
 *-----------------------------------------------------------------------------*)
IF bValid THEN
    IF bYearly AND (nMonth <> nWinMonth) THEN
        bInWindow := FALSE;                // 年度过滤：非生效月不开窗 / Yearly filter: window closed outside the configured month
        (* uErrorId 保持 0：年度过滤属口径而非故障 / uErrorId stays 0: filtering is policy, not fault *)
    ELSE
        bInWindow := (nTodayAbs >= nTargetAbs) AND (nTodayAbs <= nWinEnd); // 区间闭判定 / Closed-interval verdict
        IF bInWindow THEN
            nDaysToTarget := nTodayAbs - nTargetAbs; // 窗内偏移：首日 0 逐日递增 / Inside offset: 0 on the first day, +1 per day
        END_IF
    END_IF
    IF nClampMask > 0 THEN
        uErrorId := DL_ERR_CLAMP;          // 存在钳位事件 → 置钳位提示码 / Any clamp event raises the clamp notice code
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜开窗单拍脉冲（R25 三律 + R7 无条件刷新红线）
 *      Window-open one-shot pulse (R25 three rules + R7 unconditional refresh)
 *   R_TRIG 调用置于主体顶层，严禁挪入 IF/CASE 分支（周期安全红线）；
 *   边沿基准唯一来源 bInWindow；脉冲仅开窗拍为 TRUE，下一拍自清。
 *-----------------------------------------------------------------------------*)
fbTrigOpen(CLK := bInWindow);              // 无条件周期刷新（Unconditional per-cycle refresh）
bWindowOpen := fbTrigOpen.Q;               // 开窗拍单拍脉冲，无沿自动回落 / One-shot on the opening scan, falls back without an edge

(*------------------------------------------------------------------------------
 * 段 8｜验收推演索引 / Acceptance walkthrough index
 *   W1 12 月 29 日（倒数第 3 开 5 天窗）→ TRUE / 脉冲一拍 / 偏移 0
 *   W2 12 月 31 日 → TRUE / 偏移 2（窗口截断到 31）
 *   W3 12 月 28 日 → FALSE / 偏移 -1
 *   W4 2026-02-28（平年倒数第 1）→ TRUE / 偏移 0
 *   W5 2028-02 目标 30 → 钳 29 置 0109，29 日 → TRUE
 *   W6 年度模式 11 月非生效月 → FALSE / 码 0
 *   W7 13 月 → 0203；W8 目标 0 → 0203；W9 未使能 → 全复位
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
