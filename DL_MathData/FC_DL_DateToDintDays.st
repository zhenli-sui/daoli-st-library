(*
    FC_DL_DateToDintDays —— DATE 到自纪元起的天数
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（DATE → 自 1970-01-01 起天数）；
                委托平台内建 DATE_TO_DINT 完成天数口径换算，本件不重实现历法内核；
                纪元域闸门、保守容器口径钳位、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 把日历日期折成「自 1970-01-01 起的天数」整数，供保质期、台账天数化、
                保养周期差值与数据库整型列落库使用（日期型直接落库在各家平台的位型不一致）。
                核心防御：① 早于纪元的日期在调用内建前拦下，域外调用内建可得回绕大数；
                ② 天数超保守容器口径时按容器顶钳位并发信息级，值仍可用但已注明钳位——
                   钳位事件必须可被 HMI 看见，静默钳位是本件最易漏的缺陷；
                ③ 内建返回负天数视为容器溢出（与段 2 的域门同源但不同层），单独占故障码，
                   便于区分「组态给了 1970 前日期」与「平台 DATE 位型承载异常」两类根因。
                职责边界：天数还原归 FC_DL_DintDaysToDate；带偏移的日期推算归
                FC_DL_DateAddDays；日期差值归 FC_DL_DateDiffDays。
    编译门槛  : 主路径依赖平台内建 DATE_TO_DINT（天数口径）。三平台标准库均提供该内建，
                但天数口径本身的数值锚定存在平台差异：某些平台 DATE 以秒承载、部分以天承载。
                故 DL_DATE_DAYS_MAX 取 65535（无符号 16 位天数容器上限）的保守口径，
                编码前按目标平台实测锚定；若实测口径不同，仅调本常量，闸门与出口不动。
    错误码    : 16#0001_0410 天数超保守容器口径（65535），已按容器顶钳位——信息级，值仍可用但已钳位
                16#0001_0411 预留禁用（信息级，不得挪用）
                16#0001_0336 输入日期早于纪元（1970-01-01 之前）——故障级，返回 0
                16#0001_0337 DATE 输入非法或容器溢出（内建返回负天数）——故障级，返回 0
                16#0001_0338 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0410 用 / 16#0001_0411 预留 ｜ 16#0001_0336 用 / 16#0001_0337 用 / 16#0001_0338 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DateToDintDays : DINT
VAR_INPUT
    dateIn           : DATE;                  // 输入日期 [日期]，有效域 1970-01-01 起 / input date [date], domain starts at 1970-01-01
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
END_VAR
VAR CONSTANT
    DL_DATE_DAYS_MIN : DINT := 0;             // 纪元日，天数下界 [日] / the epoch day, lower bound [day]
    DL_DATE_DAYS_MAX : DINT := 65535;         // 保守容器口径上限，无符号 16 位天数顶 [日] / conservative container top, unsigned 16-bit day limit [day]
    DL_EPOCH_DATE_ZERO : DATE := DATE#1970-01-01; // 纪元起始日期 / the epoch date
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 [日] / signed zero constant [day]
END_VAR
VAR
    nDays            : DINT;                  // 自纪元起天数中间量 [日] / day count intermediate since the epoch [day]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DateToDintDays := DL_DINT_ZERO;         // 故障缺省返回 0 [日] / fault default returns zero [day]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
nDays := DL_DINT_ZERO;                        // 中间量清零 / clear the intermediate

// 段 2｜下域闸门：早于纪元的日期先于内建拦下 / segment 2, epoch lower gate precedes the built-in call
IF dateIn < DL_EPOCH_DATE_ZERO THEN
    eErr := 16#0001_0336;                     // 故障级：输入早于纪元 / fault level, the input precedes the epoch
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_DateToDintDays := DL_DINT_ZERO;     // 确定缺省值 0 / deterministic default of zero
    RETURN;                                   // 出口，不触碰内建 / exit, the built-in is never touched
END_IF

// 段 3｜主体：域内才委托平台内建（天数口径）/ segment 3, delegate the built-in only inside the domain
nDays := DATE_TO_DINT(dateIn);                // 内建换算：DATE → 自纪元天数 [日] / built-in conversion from DATE to days since the epoch [day]

// 段 4｜容器溢出闸：内建给负天数即平台 DATE 位型承载异常 / segment 4, container overflow gate
IF nDays < DL_DATE_DAYS_MIN THEN
    eErr := 16#0001_0337;                     // 故障级：DATE 非法或容器溢出 / fault level, illegal DATE or container overflow
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_DateToDintDays := DL_DINT_ZERO;     // 确定缺省值 0 / deterministic default of zero
    RETURN;                                   // 出口 / exit
END_IF

// 段 5｜保守容器口径钳位（信息级，钳位事件必须可见）/ segment 5, conservative container clamp at info level
IF nDays > DL_DATE_DAYS_MAX THEN
    nDays := DL_DATE_DAYS_MAX;                // 钳位至容器顶 [日] / clamp to the container top [day]
    eErr := 16#0001_0410;                     // 信息级：超保守口径已钳位，值仍可用 / info level, clamped to the conservative top, still usable
END_IF

// 段 6｜发布结果 / segment 6, publish the result
FC_DL_DateToDintDays := nDays;                // 输出自纪元起天数 [日] / publish the days since the epoch [day]
bValid := TRUE;                               // 域内或已钳位均可用 / usable in domain or after the clamp
END_FUNCTION
