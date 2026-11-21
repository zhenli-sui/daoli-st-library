(*==============================================================================
 * 组件名称 (Component)  : FB_DL_YearWindowCheck
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 时间窗判定功能块（Function Block · Date and Timer）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / F_TRIG / 整数除法 / SQRT 不涉及），
 *                         无任何厂商方言、无系统时钟调用
 * 功能简介 (Function)   : 年度生效窗判定（年粒度区间窗，允许跨年与按年重复）。
 *                         判定「当前日期是否落在年度生效区间内」，并输出开窗 / 关窗
 *                         单拍脉冲、距下一次窗沿的天数、组态非法标志与主状态机态。
 *                         支持跨年窗（如 11 月 1 日至次年 2 月末）、结束日含 / 不含、
 *                         闰日自动生效、多年度组态按「一年一循环」折叠判定。
 *                         三个日期（当前 / 起始 / 结束）全部由引脚注入，本块不读
 *                         平台时钟、不猜时区、不做夏冬令时换算。
 *
 * 【引脚契约 / Pin contract】
 *   输入 bEnable        : BOOL — 使能。FALSE 时 bInWindow 强制 FALSE、状态回空闲、
 *                                eState 落 eIdle、脉冲不输出、nDaysUntilEdge 保持 0；
 *   输入 bReset         : BOOL — 上升沿清组态非法态（仅在组态已修正时有效）；
 *   输入 nYear          : INT  — 当前年 [年]，有效域 1970~2099，越界钳位照算；
 *   输入 nMonth         : INT  — 当前月 [月]，1~12，越界钳位照算；
 *   输入 nDay           : INT  — 当前日 [日]，1~31，超当月天数钳到月末照算；
 *   输入 nStartYear     : INT  — 窗口起始年 [年]，有效域 1970~2099；
 *   输入 nStartMonth    : INT  — 窗口起始月 [月]，1~12；
 *   输入 nStartDay      : INT  — 窗口起始日 [日]，1~31；
 *   输入 nEndYear       : INT  — 窗口结束年 [年]，有效域 1970~2099；
 *   输入 nEndMonth      : INT  — 窗口结束月 [月]，1~12；
 *   输入 nEndDay        : INT  — 窗口结束日 [日]，1~31；
 *   输入 bIncludeEnd    : BOOL — 结束日是否含当天，默认 TRUE（闭区间）；
 *   输出 bInWindow      : BOOL — 当前日在窗内。仅当状态机处于入窗态时为 TRUE
 *                                （失效态期间宁可不开窗，不可误开窗）；
 *   输出 bEdgeOpen      : BOOL — 入窗单拍脉冲（进入窗口的那一个扫描拍）；
 *   输出 bEdgeClose     : BOOL — 出窗单拍脉冲（离开窗口、或入窗后失效、或使能撤除）；
 *   输出 bInvalidConfig : BOOL — 窗口归一后为空（组态非法），本拍按空窗处理；
 *   输出 nDaysUntilEdge : INT  — 距下一次窗沿的天数 [日]：窗内 = 距关沿，窗外 = 距开沿；
 *   输出 eState         : ENUM — 主状态机当前态（E_DL_YearWinPhase）；
 *   输出 uErrorId       : UDINT — 事件码，0 = 无。本块全部码为信息级，不置报警位。
 *
 * 【日期口径 / Date basis（整数序数法，禁用浮点与时间类型）】
 *   把每个日期折算成「相对 DL_EPOCH_YEAR（2000 年）1 月 1 日的连续日序数」：
 *     nOrd = (年 - 2000) × 365 + (截至上年末的闰日累计 - 基准年闰日累计) + 年内序日
 *   闰日累计 = (年 - 1) / 4 - (年 - 1) / 100 + (年 - 1) / 400（格里高利历公开定义）；
 *   年内序日 = 月前累计天数 + 日 + (闰年且月份 >= 3 时补 1)。
 *   全部运算用 LINT 中间量：2099 年序数约 3.6 万，远小于 LINT 域，绝无溢出；
 *   相邻日期之差即为真实天数差，月末、年末、闰日由序数法自动对齐，无需分支特判。
 *
 * 【跨年与重复语义 / Cross-year and repetition semantics（防止多年度歧义）】
 *   ① 跨年窗判定：结束日期「早于」起始日期（同年比月日、或结束年小于起始年）
 *      视为跨年窗，跨度自动补一个年度周期（11 月 1 日到次年 2 月末合法）；
 *   ② 按年重复：判定时把当前位置折叠到以窗口起点为原点的单个年度周期内
 *      （周期长度 = 365 或起算年为闰年时的 366），因此同一月日组合每年自动生效，
 *      多年度组态（如 2026 至 2031）不再需要逐年配置；
 *   ③ 跨度超过一个周期（组态区间跨越多于一年）时钳到「整周期覆盖」，
 *      等价于「当前日期恒在窗内」，属口径而非错误，不置任何码；
 *   ④ 归一后跨度为负（起止同日且不含尾）→ 空窗，bInvalidConfig 置位并置码 011F。
 *
 * 【主状态机 / Main state machine（ENUM + CASE + ELSE 兜底）】
 *   eIdle      → bEnable 且组态合法：按本拍判定直接落 eInWindow / eOutWindow
 *                （首拍落态不产生脉冲，无前一拍基准可比）；
 *   eIdle      → 组态非法：eInvalid；
 *   eOutWindow → 判定上升沿：eInWindow 并输出 bEdgeOpen 单拍；
 *   eInWindow  → 判定下降沿：eOutWindow 并输出 bEdgeClose 单拍；
 *   任一态     → 组态非法：eInvalid（入窗态额外补发 bEdgeClose）；
 *   任一态     → 使能撤除：eIdle（入窗态额外补发 bEdgeClose）；
 *   eInvalid   → bReset 上升沿且组态已修正：eIdle；
 *   ELSE       → 非法态值：回 eInvalid 并置 011F（兜底拦截，绝不落空态）。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 年越界 → 钳到 1970~2099，置 011E，继续判定（现场 HMI 误设不应停机）；
 *   B2 月越界 → 钳到 1~12，置 011E；
 *   B3 日超当月天数（含闰年 2 月 29 日判定）→ 钳到月末，置 011E；
 *   B4 空窗（归一后跨度为负）→ bInvalidConfig 置位、置 011F、bInWindow FALSE；
 *   B5 折叠循环防死锁：偏移量折叠用两条 WHILE，各带同一 nGuard 计数，
 *      上限 DL_GUARD_MAX；触顶时偏移归零、判定 FALSE、置 011E（保底不挂死）；
 *   B6 整数比较一律用 = / <> 于 INT、LINT 域（无浮点判等参与），
 *      浮点容差红线在本块不适用（本块零浮点运算，头注释显式声明）；
 *   B7 组态非法期间窗输出保持 FALSE，即便组态随后被修正也需 bReset 沿退出，
 *      杜绝「参数刚改好一刹那误开窗」。
 *
 * 【单拍标志三律 / One-shot pulse lifecycle（R24 / R25）】
 *   置位律：bEdgeOpen / bEdgeClose 每拍在段 1 预清零，仅由段 7 状态迁移分支置位；
 *   分离律：边沿「消费」发生在段 6 的实例调用结果，脉冲「转出」发生在段 7，
 *           两者不在同一语句上叠加，下一拍由段 1 预清零自清；
 *   基准律：边沿基准唯一来源为本拍归一判定量，实例在主体顶层无条件刷新，
 *           不置于任何 IF / CASE 分支内，扫描抖动不丢沿、不重沿。
 *
 * 【调用示例 / Call example（仅行注释，不嵌套块注释）】
 *   // 采暖季窗：每年 11 月 1 日至次年 3 月 15 日，当前日期由 HMI 注入
 *   // fbHeatWin(bEnable := bSystemRun, bReset := bCfgReset,
 *   //           nYear := nHmiYear, nMonth := nHmiMonth, nDay := nHmiDay,
 *   //           nStartYear := 2026, nStartMonth := 11, nStartDay := 1,
 *   //           nEndYear := 2027, nEndMonth := 3, nEndDay := 15,
 *   //           bIncludeEnd := TRUE,
 *   //           bInWindow => bHeatSeason, bEdgeOpen => bHeatOn,
 *   //           bEdgeClose => bHeatOff, nDaysUntilEdge => nDaysToHeatEdge,
 *   //           bInvalidConfig => bHeatCfgBad, eState => eHeatState,
 *   //           uErrorId => uHeatErr);
 *
 * 【平台移植注意 / Porting notes】
 *   LINT 除法与 MOD 均为 IEC 61131-3 标准语义（向零截断），本块只用非负数做
 *   除法与 MOD，不触碰负数取整差异；WHILE 循环有显式计数上限，三平台行为一致；
 *   F_TRIG 为 Standard.library 标准实例，语义与 R_TRIG 对称，不依赖厂商扩展。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 暖通季节窗：每年采暖季放行锅炉群控，非采暖季只保留防冻循环；
 *   ② 年度计量检定窗：每年固定月日区间放行强制检定工单，其余时段锁单；
 *   ③ 汛期 / 旱季工艺配方切换：跨年窗（11 月至次年 2 月）自动切到低温配方；
 *   ④ 年度盘点冻结：只在年末指定区间冻结库存异动，窗沿脉冲驱动 HMI 提示。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1 窗内：窗口 2026-03-01 至 2026-06-30，当前 2026-04-15
 *            → bInWindow TRUE、nDaysUntilEdge 76（4 月 15 日到 6 月 30 日）；
 *   V2 窗外：同窗口，当前 2026-07-01 → bInWindow FALSE，窗沿当日切换拍出 bEdgeClose；
 *   V3 跨年窗：窗口 2026-11-01 至 2027-02-28，当前 2027-01-10 → bInWindow TRUE；
 *   V4 不含尾：窗口 2026-03-01 至 2026-06-30，bIncludeEnd FALSE，当前 2026-06-30
 *            → bInWindow FALSE；bIncludeEnd TRUE 时同输入为 TRUE；
 *   V5 闰日：窗口 2028-02-01 至 2028-03-01，当前 2028-02-29 → bInWindow TRUE；
 *   V6 非法：起止同为 2026-05-10 且 bIncludeEnd FALSE
 *            → bInvalidConfig TRUE、uErrorId 011F、bInWindow FALSE。
 *
 * 【故障码表 / Error code table（本块全部信息级，不置报警位）】
 *   16#0001_011E  日期参数越界已钳位照算：年越界 / 月越界 / 日超当月天数 /
 *                 折叠循环触顶，均按钳位值继续判定，扫描不中断；
 *   16#0001_011F  窗口归一后为空：跨度小于零（起止同日且不含尾等），
 *                 本拍 bInvalidConfig 置位、bInWindow 强制 FALSE。
 *
 * 【同族职责分离 / Family separation（四件日历族互斥，零互相调用）】
 *   FB_DL_TimeWindowCheck    = 日内时刻窗（时分秒粒度）；
 *   FB_DL_MonthWindowCheck   = 月度日窗（月内第 N 天 / 月末倒数，月粒度）；
 *   FB_DL_OccScheduleWindow  = 多时刻窗排程；
 *   本块                     = 年粒度区间窗（允许跨年）。
 *   年窗不复用月窗实现：年窗跨年合法、月窗跨月非法，语义相反，复用必然错判。
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 A · LGF Date and Timer 组）
 *
 * 同文件发布类型 (Co-published type) : E_DL_YearWinPhase（本块主状态机枚举，
 *   按库内惯例随宿主 POU 同文件发布，禁止在其他文件重复声明同名枚举）。
 *============================================================================*)
TYPE E_DL_YearWinPhase :
(
    eIdle      := 0,   // 空闲：未使能或等待首次落态 / Idle, disabled or awaiting the first verdict
    eOutWindow := 10,  // 窗外：监视入窗沿 / Outside the window, watching the entry edge
    eInWindow  := 20,  // 窗内：监视出窗沿 / Inside the window, watching the exit edge
    eInvalid   := 30   // 失效：归一后空窗，需复位沿退出 / Invalid, empty window, exits on a reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_YearWindowCheck
VAR_INPUT
    bEnable        : BOOL;                 // 使能，FALSE 时窗判定强制 FALSE / Enable, FALSE forces the verdict FALSE
    bReset         : BOOL;                 // 上升沿清组态非法态，需组态已修正 / Rising edge clears the invalid state once fixed
    nYear          : INT;                  // 当前年 [年]，1970~2099 / Current year [year], 1970 to 2099
    nMonth         : INT;                  // 当前月 [月]，1~12 / Current month [month], 1 to 12
    nDay           : INT;                  // 当前日 [日]，1~31 按当月天数细校验 / Current day [day], 1 to 31 checked against the month length
    nStartYear     : INT;                  // 窗口起始年 [年]，1970~2099 / Window start year [year], 1970 to 2099
    nStartMonth    : INT;                  // 窗口起始月 [月]，1~12 / Window start month [month], 1 to 12
    nStartDay      : INT;                  // 窗口起始日 [日]，1~31 / Window start day [day], 1 to 31
    nEndYear       : INT;                  // 窗口结束年 [年]，1970~2099 / Window end year [year], 1970 to 2099
    nEndMonth      : INT;                  // 窗口结束月 [月]，1~12 / Window end month [month], 1 to 12
    nEndDay        : INT;                  // 窗口结束日 [日]，1~31 / Window end day [day], 1 to 31
    bIncludeEnd    : BOOL := TRUE;         // 结束日含当天，TRUE = 闭区间 / Include the end day, TRUE = closed interval
END_VAR
VAR_OUTPUT
    bInWindow      : BOOL;                 // 当前日在窗内，逐拍重算非锁存 / Today inside the window, recomputed each scan
    bEdgeOpen      : BOOL;                 // 入窗单拍脉冲 / One-shot pulse on window entry
    bEdgeClose     : BOOL;                 // 出窗单拍脉冲 / One-shot pulse on window exit
    bInvalidConfig : BOOL;                 // 组态非法（空窗），按空窗处理 / Invalid configuration, treated as an empty window
    nDaysUntilEdge : INT;                  // 距下次窗沿天数 [日]，窗内为关沿 / Days to the next window edge [day]
    eState         : E_DL_YearWinPhase;    // 主状态机当前态 / Current state of the main state machine
    uErrorId       : UDINT;                // 事件码，0 = 无 / Event code, 0 = none
END_VAR
VAR
    _eState        : E_DL_YearWinPhase;    // 内部状态寄存器，段 7 为唯一写点 / Internal state register, single writer in stage 7
    _fbTrigOpen    : R_TRIG;               // 入窗上升沿实例，顶层无条件刷新 / Rising-edge instance for entry, refreshed unconditionally
    _fbTrigClose   : F_TRIG;               // 出窗下降沿实例，顶层无条件刷新 / Falling-edge instance for exit, refreshed unconditionally
    _fbTrigReset   : R_TRIG;               // 复位上升沿实例，顶层无条件刷新 / Rising-edge instance of the reset pin
    _bRawInWin     : BOOL;                 // 本拍归一判定结果，状态机与输出唯一依据 / Raw verdict, sole basis for state and outputs
    _bValidCfg     : BOOL;                 // 组态有效性闸门 / Configuration validity gate
    _bClamped      : BOOL;                 // 本拍发生过钳位事件 / A clamping event happened in this scan
    _bCrossYear    : BOOL;                 // 跨年窗标志 / Cross-year window flag
    _bLeap         : BOOL;                 // 工作闰年标志，逐元素重算 / Working leap flag, recomputed per element
    _bLeapStart    : BOOL;                 // 起算年闰年标志，决定周期长度 / Leap flag of the start year, decides the cycle length
    _nMonthLen     : INT;                  // 当月天数 [日] / Days in the working month [day]
    _nDoy          : INT;                  // 年内序日 [日] / Day of year [day]
    _nLeapAcc      : LINT;                 // 截至上年末的闰日累计 [日] / Accumulated leap days up to the previous year end [day]
    _nEpochLeapAcc : LINT;                 // 基准年的闰日累计 [日] / Accumulated leap days at the epoch year [day]
    _nCycleLen     : LINT;                 // 年度周期长度 [日]，365 或 366 / Annual cycle length [day], 365 or 366
    _nSpan         : LINT;                 // 窗口跨度，含尾调整后 [日] / Window span after the end-day adjustment [day]
    _nOffset       : LINT;                 // 当前日相对窗口起点的周期内偏移 [日] / In-cycle offset of today from the window start [day]
    _nGuard        : INT;                  // 折叠循环防死锁计数器 / Fold-loop guard counter
    _nK            : INT;                  // 三日期循环索引 / Index of the three-date loop
    aiDateY        : ARRAY[1..3] OF INT;   // 三日期年分量 [年]：1 当前 2 起始 3 结束 / Year parts, 1 current 2 start 3 end
    aiDateM        : ARRAY[1..3] OF INT;   // 三日期月分量 [月]：1 当前 2 起始 3 结束 / Month parts of the three dates [month]
    aiDateD        : ARRAY[1..3] OF INT;   // 三日期日分量 [日]：1 当前 2 起始 3 结束 / Day parts of the three dates [day]
    aiCum          : ARRAY[1..3] OF INT;   // 月前累计天数 [日]，含闰日修正前 / Cumulative days before the month [day]
    aliOrd         : ARRAY[1..3] OF LINT;  // 连续日序数 [日]：1 当前 2 起始 3 结束 / Continuous day ordinals [day]
END_VAR
VAR CONSTANT
    DL_YEAR_MIN    : INT   := 1970;        // 可算年下限 [年] / Lower bound of the computable year [year]
    DL_YEAR_MAX    : INT   := 2099;        // 可算年上限 [年] / Upper bound of the computable year [year]
    DL_MONTH_MAX   : INT   := 12;          // 月上限 [月] / Upper bound of the month [month]
    DL_DAY_MAX     : INT   := 31;          // 日上限 [日] / Upper bound of the day [day]
    DL_DAY_MIN     : INT   := 1;           // 日下限 [日] / Lower bound of the day [day]
    DL_EPOCH_YEAR  : INT   := 2000;        // 序数基准年 [年] / Ordinal epoch year [year]
    DL_PERIOD_BASE : LINT  := 365;         // 平年周期长度 [日] / Cycle length of a common year [day]
    DL_DATE_SLOTS  : INT   := 3;           // 日期槽数 [个]：当前 / 起始 / 结束 / Number of date slots [pcs]
    DL_GUARD_MAX   : INT   := 2048;        // 折叠循环防死锁上限 [次] / Fold-loop guard limit [count]
    DL_ERR_CLAMP   : UDINT := 16#0001_011E;// 日期越界已钳位照算（信息级）/ Date clamped and evaluated, info level
    DL_ERR_EMPTY   : UDINT := 16#0001_011F;// 窗口归一后为空（信息级）/ Window empty after normalisation, info level
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出与内部量预清零（单拍标志置位律的起点）
 *      Preset clearing of outputs and working flags
 *   脉冲、判定、组态标志每拍从安全态重建，不残留上一拍结果；
 *   状态寄存器 _eState 只在段 7 改写，此处不清，保证跨拍驻留语义。
 *-----------------------------------------------------------------------------*)
bInWindow      := FALSE;                   // 窗判定预清 FALSE（Verdict preset FALSE）
bEdgeOpen      := FALSE;                   // 入窗脉冲预清（Entry pulse preset）
bEdgeClose     := FALSE;                   // 出窗脉冲预清（Exit pulse preset）
bInvalidConfig := FALSE;                   // 组态非法标志预清（Invalid flag preset）
nDaysUntilEdge := 0;                       // 窗沿天数预置 0（Edge-day count preset）
uErrorId       := 16#0000_0000;            // 事件码预清零，逐段置位（Event code preset to zero）
_bRawInWin     := FALSE;                   // 归一判定预清（Raw verdict preset）
_bValidCfg     := TRUE;                    // 组态闸门预置通过（Validity gate preset to pass）
_bClamped      := FALSE;                   // 钳位事件预清（Clamp flag preset）
_bCrossYear    := FALSE;                   // 跨年标志预清（Cross-year flag preset）
_nSpan         := 0;                       // 窗口跨度预清（Span preset）
_nOffset       := 0;                       // 周期内偏移预清（Offset preset）

(*------------------------------------------------------------------------------
 * 段 2｜组态输入接管（三日期以数组承载，后续校验与折算共用同一段代码）
 *      Take over the three dates into working arrays
 *   下标语义写死：1 = 当前日期，2 = 窗口起始日，3 = 窗口结束日。
 *-----------------------------------------------------------------------------*)
aiDateY[1] := nYear;                       // 当前日期年分量 [年]（Current date year）
aiDateM[1] := nMonth;                      // 当前日期月分量 [月]（Current date month）
aiDateD[1] := nDay;                        // 当前日期日分量 [日]（Current date day）
aiDateY[2] := nStartYear;                  // 窗口起始年分量 [年]（Start date year）
aiDateM[2] := nStartMonth;                 // 窗口起始月分量 [月]（Start date month）
aiDateD[2] := nStartDay;                   // 窗口起始日分量 [日]（Start date day）
aiDateY[3] := nEndYear;                    // 窗口结束年分量 [年]（End date year）
aiDateM[3] := nEndMonth;                   // 窗口结束月分量 [月]（End date month）
aiDateD[3] := nEndDay;                     // 窗口结束日分量 [日]（End date day）

(*------------------------------------------------------------------------------
 * 段 3｜三日期独立校验、钳位与序数折算（边界 B1 / B2 / B3）
 *      Validation, clamping and ordinal conversion of the three dates
 *   顺序写死：先钳年 → 再钳月 → 由年算闰年 → 由月查月长 → 再钳日 → 折算序数。
 *   次序不可颠倒：月长依赖闰年，日钳位依赖月长，序数依赖日钳位。
 *-----------------------------------------------------------------------------*)
_nEpochLeapAcc := INT_TO_LINT(DL_EPOCH_YEAR - 1) / 4
                - INT_TO_LINT(DL_EPOCH_YEAR - 1) / 100
                + INT_TO_LINT(DL_EPOCH_YEAR - 1) / 400;  // 基准年闰日累计（Epoch leap-day accumulation）

FOR _nK := 1 TO DL_DATE_SLOTS DO          // 三日期共用同一段校验逻辑（Shared validation for the three dates）

    IF aiDateY[_nK] < DL_YEAR_MIN THEN     // 年低于下限（Year below the lower bound）
        aiDateY[_nK] := DL_YEAR_MIN;       // 钳到下限（Clamp to the lower bound）
        _bClamped    := TRUE;              // 记录钳位事件（Record the clamp event）
    ELSIF aiDateY[_nK] > DL_YEAR_MAX THEN  // 年高于上限（Year above the upper bound）
        aiDateY[_nK] := DL_YEAR_MAX;       // 钳到上限（Clamp to the upper bound）
        _bClamped    := TRUE;              // 记录钳位事件（Record the clamp event）
    END_IF

    IF aiDateM[_nK] < 1 THEN               // 月低于 1（Month below one）
        aiDateM[_nK] := 1;                 // 钳到 1 月（Clamp to January）
        _bClamped    := TRUE;              // 记录钳位事件（Record the clamp event）
    ELSIF aiDateM[_nK] > DL_MONTH_MAX THEN // 月高于 12（Month above twelve）
        aiDateM[_nK] := DL_MONTH_MAX;      // 钳到 12 月（Clamp to December）
        _bClamped    := TRUE;              // 记录钳位事件（Record the clamp event）
    END_IF

    _bLeap := ((aiDateY[_nK] MOD 4 = 0) AND (aiDateY[_nK] MOD 100 <> 0))
              OR (aiDateY[_nK] MOD 400 = 0);  // 闰年判定，格里高利历公开定义（Leap-year verdict）

    CASE aiDateM[_nK] OF                   // 月长与月前累计查表（Month length and cumulative lookup）
    1:                                     // 一月（January）
        aiCum[_nK]   := 0;                 // 月前累计 0 天（Zero days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    2:                                     // 二月（February）
        aiCum[_nK]   := 31;                // 月前累计 31 天（31 days before）
        IF _bLeap THEN                     // 闰年二月（Leap February）
            _nMonthLen := 29;              // 29 天（29 days）
        ELSE                               // 平年二月（Common February）
            _nMonthLen := 28;              // 28 天（28 days）
        END_IF
    3:                                     // 三月（March）
        aiCum[_nK]   := 59;                // 月前累计 59 天（59 days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    4:                                     // 四月（April）
        aiCum[_nK]   := 90;                // 月前累计 90 天（90 days before）
        _nMonthLen   := 30;                // 当月 30 天（30 days）
    5:                                     // 五月（May）
        aiCum[_nK]   := 120;               // 月前累计 120 天（120 days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    6:                                     // 六月（June）
        aiCum[_nK]   := 151;               // 月前累计 151 天（151 days before）
        _nMonthLen   := 30;                // 当月 30 天（30 days）
    7:                                     // 七月（July）
        aiCum[_nK]   := 181;               // 月前累计 181 天（181 days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    8:                                     // 八月（August）
        aiCum[_nK]   := 212;               // 月前累计 212 天（212 days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    9:                                     // 九月（September）
        aiCum[_nK]   := 243;               // 月前累计 243 天（243 days before）
        _nMonthLen   := 30;                // 当月 30 天（30 days）
    10:                                    // 十月（October）
        aiCum[_nK]   := 273;               // 月前累计 273 天（273 days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    11:                                    // 十一月（November）
        aiCum[_nK]   := 304;               // 月前累计 304 天（304 days before）
        _nMonthLen   := 30;                // 当月 30 天（30 days）
    12:                                    // 十二月（December）
        aiCum[_nK]   := 334;               // 月前累计 334 天（334 days before）
        _nMonthLen   := 31;                // 当月 31 天（31 days）
    ELSE                                   // 兜底：非法月份（Fallback for an illegal month）
        aiCum[_nK]   := 0;                 // 累计归零（Cumulative reset）
        _nMonthLen   := DL_DAY_MAX;        // 按最大月长兜底（Fall back to the maximum month length）
        _bValidCfg   := FALSE;             // 关闭组态闸门（Close the configuration gate）
        uErrorId     := DL_ERR_CLAMP;      // 置钳位信息码（Raise the clamp info code）
    END_CASE

    IF aiDateD[_nK] < DL_DAY_MIN THEN      // 日低于 1（Day below one）
        aiDateD[_nK] := DL_DAY_MIN;        // 钳到 1 日（Clamp to day one）
        _bClamped    := TRUE;              // 记录钳位事件（Record the clamp event）
    ELSIF aiDateD[_nK] > _nMonthLen THEN   // 日超当月天数，如 2 月 30 日（Day beyond the month length）
        aiDateD[_nK] := _nMonthLen;        // 钳到月末（Clamp to the month end）
        _bClamped    := TRUE;              // 记录钳位事件（Record the clamp event）
    END_IF

    _nDoy := aiCum[_nK] + aiDateD[_nK];    // 年内序日 = 月前累计 + 日（Day of year）
    IF _bLeap AND (aiDateM[_nK] > 2) THEN  // 闰年三月及以后补 1 天（Leap day shifts later months）
        _nDoy := _nDoy + 1;                // 补闰日（Add the leap day）
    END_IF

    _nLeapAcc := INT_TO_LINT(aiDateY[_nK] - 1) / 4
               - INT_TO_LINT(aiDateY[_nK] - 1) / 100
               + INT_TO_LINT(aiDateY[_nK] - 1) / 400;  // 截至上年末的闰日累计（Leap days before this year）

    aliOrd[_nK] := INT_TO_LINT(aiDateY[_nK] - DL_EPOCH_YEAR) * DL_PERIOD_BASE
                 + (_nLeapAcc - _nEpochLeapAcc)
                 + INT_TO_LINT(_nDoy);     // 相对基准年的连续日序数（Continuous ordinal）
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜跨年判别与区间归一（边界 B4）
 *      Cross-year discrimination and interval normalisation
 *   跨年窗 = 结束日期早于起始日期（同年比月日，或结束年更小）；
 *   跨度先补一个周期，再按含尾口径减 1；跨度为负即空窗，超周期即整周期覆盖。
 *-----------------------------------------------------------------------------*)
IF aliOrd[3] > aliOrd[2] THEN              // 结束年大于起始年（End year later than the start year）
    _bCrossYear := FALSE;                  // 正向跨期窗，直接区间判定（Forward span, plain interval）
ELSIF aliOrd[3] < aliOrd[2] THEN           // 结束日期早于起始日期（End date earlier than the start date）
    _bCrossYear := TRUE;                   // 跨年窗，需补一个周期（Cross-year window, add one cycle）
ELSE                                       // 起止同日（Start and end on the same day）
    _bCrossYear := FALSE;                  // 非跨年，交给含尾调整决定是否空窗（No cross-year, span decides）
END_IF

_bLeapStart := ((aiDateY[2] MOD 4 = 0) AND (aiDateY[2] MOD 100 <> 0))
               OR (aiDateY[2] MOD 400 = 0);          // 起算年闰年判定（Leap verdict of the start year）
_nCycleLen  := DL_PERIOD_BASE;                        // 周期长度起步为 365 天（Cycle length starts at 365 days）
IF _bLeapStart THEN                                   // 起算年为闰年（The start year is a leap year）
    _nCycleLen := _nCycleLen + 1;                      // 周期 366 天，与闰日对齐（366 days, aligned with the leap day）
END_IF

_nSpan := aliOrd[3] - aliOrd[2];           // 原始跨度（Raw span）
IF _bCrossYear THEN                        // 跨年窗（Cross-year window）
    _nSpan := _nSpan + _nCycleLen;         // 补一个周期，语义为「起始日到次年结束日」（Add one cycle）
END_IF
IF NOT bIncludeEnd THEN                    // 不含结束日（End day excluded）
    _nSpan := _nSpan - 1;                  // 跨度减 1 天（Shrink the span by one day）
END_IF

IF _nSpan < 0 THEN                         // 归一后跨度为负（Negative span after normalisation）
    bInvalidConfig := TRUE;                // 空窗：组态非法（Empty window, invalid configuration）
    _bValidCfg     := FALSE;               // 关闭组态闸门（Close the configuration gate）
    uErrorId       := DL_ERR_EMPTY;        // 置空窗信息码（Raise the empty-window info code）
ELSIF _nSpan >= _nCycleLen THEN            // 跨度覆盖整周期（Span covers the whole cycle）
    _nSpan := _nCycleLen - 1;              // 钳到整周期，等价恒在窗内（Clamp to the full cycle）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜折叠求偏移与窗内判定（边界 B5）
 *      Fold the offset into one cycle and take the verdict
 *   偏移 = 当前日序数 - 窗口起点序数，再折叠到 0 ~ 周期长度-1 的单周期内；
 *   折叠用两条 WHILE 各带同一防死锁计数，触顶即偏移归零、判定 FALSE、置 011E。
 *-----------------------------------------------------------------------------*)
IF _bValidCfg AND bEnable THEN             // 组态合法且已使能才判定（Judge only when valid and enabled）

    _nOffset := aliOrd[1] - aliOrd[2];     // 当前日相对窗口起点的原始偏移（Raw offset）
    _nGuard  := 0;                         // 防死锁计数清零（Guard counter cleared）

    WHILE (_nOffset < 0) AND (_nGuard < DL_GUARD_MAX) DO    // 偏移早于起点：向后并入本周期（Fold forward）
        _nOffset := _nOffset + _nCycleLen; // 加一个周期（Add one cycle）
        _nGuard  := _nGuard + 1;           // 计数递增（Guard increments）
    END_WHILE

    WHILE (_nOffset >= _nCycleLen) AND (_nGuard < DL_GUARD_MAX) DO  // 偏移超周期：向前折回（Fold backward）
        _nOffset := _nOffset - _nCycleLen; // 减一个周期（Subtract one cycle）
        _nGuard  := _nGuard + 1;           // 计数递增（Guard increments）
    END_WHILE

    IF _nGuard >= DL_GUARD_MAX THEN        // 折叠触顶，理论上不可达（Guard exhausted, unreachable in theory）
        _nOffset   := 0;                   // 偏移归零兜底（Offset reset as a fallback）
        uErrorId   := DL_ERR_CLAMP;        // 置钳位信息码（Raise the clamp info code）
    END_IF

    _bRawInWin := (_nOffset >= 0) AND (_nOffset <= _nSpan);  // 周期内区间闭判定（Closed-interval verdict in the cycle）

    IF _bRawInWin THEN                     // 窗内（Inside the window）
        nDaysUntilEdge := LINT_TO_INT(_nSpan - _nOffset);    // 距关沿天数 [日]（Days to the closing edge）
    ELSE                                   // 窗外（Outside the window）
        nDaysUntilEdge := LINT_TO_INT(_nCycleLen - _nOffset); // 距开沿天数 [日]（Days to the opening edge）
    END_IF

    IF _bClamped THEN                      // 判定过程中发生过钳位（Clamping happened during the verdict）
        uErrorId := DL_ERR_CLAMP;          // 钳位照算，置信息码（Clamped and evaluated, raise the info code）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜边沿实例无条件周期刷新（周期安全红线）
 *      Unconditional per-cycle refresh of all edge instances
 *   三个实例固定在主体顶层调用，严禁挪入 IF / CASE 分支；
 *   输入为本拍归一判定量（唯一基准），扫描抖动不丢沿。
 *-----------------------------------------------------------------------------*)
_fbTrigOpen(CLK  := _bRawInWin);           // 入窗上升沿（Entry rising edge）
_fbTrigClose(CLK := _bRawInWin);           // 出窗下降沿（Exit falling edge）
_fbTrigReset(CLK := bReset);               // 复位上升沿（Reset rising edge）

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（ENUM + CASE + ELSE 兜底）
 *      Main state machine with the mandatory ELSE fallback
 *   脉冲在本段消费段 6 的实例结果并转出，下一拍由段 1 预清零自清；
 *   状态寄存器 _eState 在本段为唯一写点，不存在旁路写入。
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_YearWinPhase.eIdle:               // 空闲：等待使能与合法组态（Idle: waiting for enable and a valid configuration）
        IF NOT bEnable THEN                // 未使能（Not enabled）
            _eState := E_DL_YearWinPhase.eIdle;              // 保持空闲（Stay idle）
        ELSIF bInvalidConfig THEN          // 组态非法（Invalid configuration）
            _eState := E_DL_YearWinPhase.eInvalid;           // 落失效态（Enter the invalid state）
        ELSIF _bRawInWin THEN              // 首拍即窗内（Inside on the very first scan）
            _eState := E_DL_YearWinPhase.eInWindow;          // 直接落入窗态，不产生脉冲（No pulse on the first scan）
        ELSE                               // 首拍在窗外（Outside on the very first scan）
            _eState := E_DL_YearWinPhase.eOutWindow;         // 落入窗外态（Enter the out-of-window state）
        END_IF

    E_DL_YearWinPhase.eOutWindow:          // 窗外：监视入窗沿（Outside: watch for the entry edge）
        IF bInvalidConfig THEN             // 组态转非法（Configuration became invalid）
            _eState := E_DL_YearWinPhase.eInvalid;           // 落失效态（Enter the invalid state）
        ELSIF NOT bEnable THEN             // 使能撤除（Enable removed）
            _eState := E_DL_YearWinPhase.eIdle;              // 回空闲（Back to idle）
        ELSIF _fbTrigOpen.Q THEN           // 入窗沿（Entry edge detected）
            bEdgeOpen := TRUE;             // 转出入窗单拍（Emit the entry one-shot）
            _eState   := E_DL_YearWinPhase.eInWindow;        // 迁移入窗态（Move to the in-window state）
        END_IF

    E_DL_YearWinPhase.eInWindow:           // 窗内：监视出窗沿（Inside: watch for the exit edge）
        IF bInvalidConfig THEN             // 组态转非法（Configuration became invalid）
            bEdgeClose := TRUE;            // 补发出窗单拍，防止上层悬挂（Emit the exit one-shot to avoid a hang）
            _eState    := E_DL_YearWinPhase.eInvalid;        // 落失效态（Enter the invalid state）
        ELSIF NOT bEnable THEN             // 使能撤除（Enable removed）
            bEdgeClose := TRUE;            // 补发出窗单拍（Emit the exit one-shot）
            _eState    := E_DL_YearWinPhase.eIdle;           // 回空闲（Back to idle）
        ELSIF _fbTrigClose.Q THEN          // 出窗沿（Exit edge detected）
            bEdgeClose := TRUE;            // 转出出窗单拍（Emit the exit one-shot）
            _eState    := E_DL_YearWinPhase.eOutWindow;      // 迁移窗外态（Move to the out-of-window state）
        END_IF

    E_DL_YearWinPhase.eInvalid:            // 失效：需复位沿且组态已修正才退出（Invalid: reset edge required）
        IF (NOT bInvalidConfig) AND _fbTrigReset.Q THEN      // 组态已修正且有复位沿（Fixed configuration and a reset edge）
            _eState := E_DL_YearWinPhase.eIdle;              // 回空闲重新落态（Back to idle, verdict re-taken）
        END_IF

    ELSE                                   // 兜底：非法态值（Fallback for an illegal state value）
        _eState  := E_DL_YearWinPhase.eInvalid;              // 一律回失效态（Force the invalid state）
        uErrorId := DL_ERR_EMPTY;          // 置空窗信息码，提示组态检查（Raise the info code for diagnosis）
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜输出映射（窗输出与状态机严格同源，杜绝双基准漂移）
 *      Output mapping, strictly derived from the state machine
 *   bInWindow 只在入窗态为 TRUE：失效态期间即便判定为真也不开窗，
 *   宁可不开窗，不可误开窗（B7 防御口径）。
 *-----------------------------------------------------------------------------*)
bInWindow := _bRawInWin AND (_eState = E_DL_YearWinPhase.eInWindow);  // 窗输出与状态同源（Verdict sourced from the state）
eState    := _eState;                      // 状态引脚映射（State pin mapping）
END_FUNCTION_BLOCK
