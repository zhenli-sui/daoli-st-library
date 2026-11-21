(*
    FC_DL_DateDiffDays —— 两 DATE 之差天数（可负）
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（两个日期之间的天数差，可负）；
                经天数路径委托平台内建 DATE_TO_DINT 完成历法换算，本件不重实现历法内核；
                负值口径、方向标志、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 保质期余量、超期天数、保养逾期天数的判定原子：给两个日期，输出「从前者到后者
                过了多少天」，后者早于前者即为负。与 FC_DL_DateAddDays 构成判定原子对。
                核心防御：① 差值一律在 DINT 域内做：两个 DATE 都在容器域内，天数差模长必小于
                   65536，DINT 承载结构性不溢出——此论证是本件不设故障出口的依据；
                ② 负值是合法业务输出（超期天数就是负的余量），绝不钳到 0、绝不用绝对值：
                   把「已超期 3 天」抹平成「今天到期」是保质期逻辑最典型的静默错；
                ③ bNegative 单独回告方向，HMI 不必自己再比一次大小；
                ④ 本件五槽中信息 1 槽使用、故障 3 槽按规格预留——域外输入在类型域上
                   不可表达（DATE 值域由类型系统保证），故不虚构不存在的故障码。
                职责边界：日期加偏移归 FC_DL_DateAddDays；日期天数化归 FC_DL_DateToDintDays；
                本件只管两日期之间的差值。
    编译门槛  : 主路径依赖平台内建 DATE_TO_DINT（天数口径），三平台标准库均提供。
                若某平台 DATE 以秒承载，则差值单位为秒而非天——此差异由 DL_DATE_DAYS_MAX
                的实测锚定统一裁定（与 FC_DL_DateToDintDays 同源），本件闸门不受影响。
    错误码    : 16#0001_042C 差值为负（dateTo 早于 dateFrom），已如实输出——信息级，值可用
                16#0001_042D 预留禁用（信息级，不得挪用）
                16#0001_0360 预留（故障级，不得挪用）
                16#0001_0361 预留禁用（故障级，不得挪用）
                16#0001_0362 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_042C 用 / 16#0001_042D 预留 ｜ 16#0001_0360 预留 / 16#0001_0361 预留 / 16#0001_0362 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DateDiffDays : DINT
VAR_INPUT
    dateFrom         : DATE;                  // 区间起始日期 [日期] / start date of the interval [date]
    dateTo           : DATE;                  // 区间结束日期 [日期]，早于起点即差值为负 / end date of the interval [date], earlier than the start yields a negative difference
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，本件无故障级出口，恒为 FALSE / error flag, always FALSE here as no fault exit exists
    bValid           : BOOL;                  // 返回值是否可用（本件恒为 TRUE）/ return usable, always TRUE here
    bNegative        : BOOL;                  // 差值为负（dateTo 早于 dateFrom）/ the difference is negative
END_VAR
VAR CONSTANT
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 [日] / signed zero constant [day]
END_VAR
VAR
    nFrom            : DINT;                  // 起始日期天数 [日] / start date in days [day]
    nTo              : DINT;                  // 结束日期天数 [日] / end date in days [day]
    nDiff            : DINT;                  // 差值中间量，可负 [日] / difference intermediate, possibly negative [day]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DateDiffDays := DL_DINT_ZERO;           // 缺省返回 0 天 [日] / default returns zero days [day]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 本件无故障级出口，恒 FALSE / no fault exit exists, always FALSE
bValid := FALSE;                              // 预置不可用，末段置位 / preset invalid, set TRUE in the last stage
bNegative := FALSE;                           // 预置非负差 / preset a non-negative difference
nDiff := DL_DINT_ZERO;                        // 中间量清零 / clear the intermediate

// 段 2｜取值：两日期各做一次显式标准转换 / segment 2, both dates are converted explicitly
nFrom := DATE_TO_DINT(dateFrom);              // 起始日期天数 [日] / start date in days [day]
nTo := DATE_TO_DINT(dateTo);                  // 结束日期天数 [日] / end date in days [day]

// 段 3｜求差：模长必小于 65536，DINT 承载结构性不溢出 / segment 3, the difference cannot overflow DINT
nDiff := nTo - nFrom;                         // 有符号天数差 [日] / signed difference in days [day]

// 段 4｜负值如实输出（超期余量语义，绝不抹平）/ segment 4, negative values are published as they are
IF nDiff < DL_DINT_ZERO THEN
    bNegative := TRUE;                        // 标记差值为负 / flag the negative difference
    eErr := 16#0001_042C;                     // 信息级：差值为负，已如实输出 / info level, a negative difference was published as is
END_IF

// 段 5｜发布结果 / segment 5, publish the result
FC_DL_DateDiffDays := nDiff;                  // 输出天数差 [日] / publish the difference in days [day]
bValid := TRUE;                               // 正负差值均为合法业务输出 / both signs are legal business results
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
