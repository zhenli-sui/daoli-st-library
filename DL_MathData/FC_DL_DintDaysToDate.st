(*
    FC_DL_DintDaysToDate —— 天数到 DATE 的还原
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（自 1970-01-01 起天数 → DATE）；
                委托平台内建 DINT_TO_DATE 完成还原，本件不重实现历法内核；
                域闸门、非饱和还原口径、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 把天数整型还原成日历日期，与 FC_DL_DateToDintDays 构成双向对。
                交付期、下次保养日、保质期到期日这类「数据库存天数、PLC 要日期」的场景，
                跨零点批量换算是高频口径。
                核心防御：① 负天数与超容器天数均返回纪元日并置 bValid = FALSE，
                   绝不做饱和还原——饱和会把越界天数改写成 1970-01-01 或容器顶，
                   台账上看不出异常，这是本件刻意与饱和族件分道的地方；
                ② 域端点（纪元日 0 与容器顶 65535）发信息级提示，便于排查上游哨兵值；
                ③ 天数上界与 FC_DL_DateToDintDays 用同一常量口径，正反两向不会错位。
                职责边界：日期天数化归 FC_DL_DateToDintDays；带偏移日期推算归
                FC_DL_DateAddDays（它先经天数路径再加偏移，天然覆盖本件域内域）。
    编译门槛  : 主路径依赖平台内建 DINT_TO_DATE（天数口径），三平台标准库均提供。
                若目标平台缺该内建，按「天数 → 纪元日零点 DT → DT 取日期」路径落地，
                中间量与闸门顺序不变；DL_DATE_DAYS_MAX 取 65535 保守口径，
                编码前按目标平台实测锚定（与 FC_DL_DateToDintDays 同源裁定）。
    错误码    : 16#0001_0412 天数恰为域端点（0 或 65535），已如实还原——信息级，值仍可用
                16#0001_0413 预留禁用（信息级，不得挪用）
                16#0001_0339 负天数（nDays < 0）——故障级，返回纪元日
                16#0001_033A 天数超容器域（nDays > 65535）——故障级，返回纪元日，不做饱和
                16#0001_033B 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0412 用 / 16#0001_0413 预留 ｜ 16#0001_0339 用 / 16#0001_033A 用 / 16#0001_033B 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DintDaysToDate : DATE
VAR_INPUT
    nDays            : DINT;                  // 自纪元起天数 [日]，有效域 0~65535 / days since the epoch [day], valid domain 0 to 65535
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
END_VAR
VAR CONSTANT
    DL_DATE_DAYS_MIN : DINT := 0;             // 纪元日，天数下界 [日] / the epoch day, lower bound [day]
    DL_DATE_DAYS_MAX : DINT := 65535;         // 保守容器口径上限，无符号 16 位天数顶 [日] / conservative container top, unsigned 16-bit day limit [day]
    DL_EPOCH_DATE_ZERO : DATE := DATE#1970-01-01; // 纪元起始日期，故障缺省返回 / the epoch date returned on faults
END_VAR
VAR
    nWork            : DINT;                  // 入参副本，避免改动调用方数据 [日] / input copy, never modifies caller data [day]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintDaysToDate := DL_EPOCH_DATE_ZERO;   // 故障缺省返回纪元日 / fault default returns the epoch date
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
nWork := nDays;                               // 取入参副本参与判定 / copy the input for the comparisons

// 段 2｜下域闸门：负天数不是日期 / segment 2, negative gate, a negative day count is no date
IF nWork < DL_DATE_DAYS_MIN THEN
    eErr := 16#0001_0339;                     // 故障级：负天数 / fault level, negative day count
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    RETURN;                                   // 出口，保持纪元日 / exit, the epoch date is kept
END_IF

// 段 3｜上域闸门：超容器域不做饱和（饱和会伪造日期）/ segment 3, upper gate without saturation
IF nWork > DL_DATE_DAYS_MAX THEN
    eErr := 16#0001_033A;                     // 故障级：超平台容器域 / fault level, beyond the platform container
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    RETURN;                                   // 出口，保持纪元日，不伪造日期 / exit, no fabricated date
END_IF

// 段 4｜主体：域内才委托平台内建 / segment 4, delegate the built-in only inside the domain
FC_DL_DintDaysToDate := DINT_TO_DATE(nWork);  // 内建还原：天数 → 日期 / built-in conversion from days to a date
bValid := TRUE;                               // 域内还原可用 / the in-domain date is usable

// 段 5｜域端点提示（信息级，不置 bError）/ segment 5, domain endpoint hint at info level
IF (nWork = DL_DATE_DAYS_MIN) OR (nWork = DL_DATE_DAYS_MAX) THEN
    eErr := 16#0001_0412;                     // 信息级：天数恰为域端点，多为上游哨兵值 / info level, a domain endpoint, often an upstream sentinel
END_IF
END_FUNCTION
