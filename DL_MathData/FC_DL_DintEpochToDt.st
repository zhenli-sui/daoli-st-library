(*
    FC_DL_DintEpochToDt —— Unix 纪元秒到 DATE_AND_TIME
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（Unix 纪元秒 → DATE_AND_TIME）；
                委托平台内建 DINT_TO_DT 完成还原，本件不重实现历法内核；
                域闸门、非饱和还原口径、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 把 MES / 日志侧回传的 Unix 纪元秒还原成 PLC 本地时刻，与
                FC_DL_DtToDintEpoch 构成双向对。
                核心防御：① 还原方向遇域外输入一律不输出「错值」——负秒与超 Y2038 秒
                   均返回纪元零点并置 bValid = FALSE，宁可不给时刻也不给错时刻，
                   因为错时刻会污染趋势曲线与批次记录，而空值只会触发一次重试；
                ② 本件不做饱和还原（与正向件的饱和出口刻意不同）：饱和会把数据库里的
                   越界秒静默改写成 2038-01-19，故障现场证据随之消失；
                ③ 边界秒（0 与 2147483647）发信息级提示，提示该值处于域端点，
                   便于排查上游把哨兵值当时刻下发的组态错。
                职责边界：正方向（DT → 纪元秒）归 FC_DL_DtToDintEpoch；
                本件只管「秒 → 时刻」单向还原。
    编译门槛  : 主路径依赖平台内建 DINT_TO_DT，三平台标准库均提供。
                若目标平台缺该内建，按合成路径落地：nDays = n / DL_SEC_PER_DAY、
                nSecOfDay = n MOD DL_SEC_PER_DAY，两操作数先判非负（段 2 已保证 n >= 0，
                余数口径安全），再 DINT_TO_DATE + DINT_TO_TOD 合成 DATE_AND_TIME。
                合成路径只在操作数非负域内使用模运算，与 TOD 回绕件的禁模纪律不冲突。
    错误码    : 16#0001_040E 输入恰为域端点（0 或 2147483647），已如实还原——信息级，值仍可用
                16#0001_040F 预留禁用（信息级，不得挪用）
                16#0001_0333 负纪元秒（nEpochSec < 0）——故障级，返回纪元零点
                16#0001_0334 超出 Y2038 秒域（nEpochSec > 2147483647）——故障级，返回纪元零点，不做饱和
                16#0001_0335 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_040E 用 / 16#0001_040F 预留 ｜ 16#0001_0333 用 / 16#0001_0334 用 / 16#0001_0335 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DintEpochToDt : DATE_AND_TIME
VAR_INPUT
    nEpochSec        : DINT;                  // 纪元秒 [s]，有效域 0~2147483647 / epoch seconds [s], valid domain 0 to 2147483647
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
END_VAR
VAR CONSTANT
    DL_EPOCH_SEC_MAX : DINT := 2147483647;    // DINT 秒域上限，即 2038-01-19T03:14:07Z [s] / DINT second domain top, the Y2038 instant [s]
    DL_EPOCH_SEC_ZERO : DINT := 0;            // 纪元零点秒 [s] / the epoch second [s]
    DL_SEC_PER_DAY   : DINT := 86400;         // 每日秒数 [s/日]，合成路径的除数量 / seconds per day [s/day], divisor of the synthesis path
    DL_EPOCH_DT_ZERO : DATE_AND_TIME := DT#1970-01-01-00:00:00; // 纪元零点时刻，故障缺省返回 / the epoch instant returned on faults
END_VAR
VAR
    nWork            : DINT;                  // 入参副本，避免改动调用方数据 [s] / input copy, never modifies caller data [s]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintEpochToDt := DL_EPOCH_DT_ZERO;      // 故障缺省返回纪元零点 / fault default returns the epoch instant
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
nWork := nEpochSec;                           // 取入参副本参与判定 / copy the input for the comparisons

// 段 2｜下域闸门：负秒不是时刻，绝不进内建 / segment 2, negative gate, a negative second is no instant
IF nWork < DL_EPOCH_SEC_ZERO THEN
    eErr := 16#0001_0333;                     // 故障级：负纪元秒 / fault level, negative epoch seconds
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    RETURN;                                   // 出口，保持纪元零点 / exit, the epoch instant is kept
END_IF

// 段 3｜上域闸门：超 Y2038 域不做饱和（饱和会伪造时刻，破坏故障证据）/ segment 3, upper gate without saturation
IF nWork > DL_EPOCH_SEC_MAX THEN
    eErr := 16#0001_0334;                     // 故障级：超 Y2038 秒域 / fault level, beyond the Y2038 second domain
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    RETURN;                                   // 出口，保持纪元零点，不伪造时刻 / exit, no fabricated instant
END_IF

// 段 4｜主体：域内才委托平台内建 / segment 4, delegate the built-in only inside the domain
FC_DL_DintEpochToDt := DINT_TO_DT(nWork);     // 内建还原：纪元秒 → 时刻 / built-in conversion from epoch seconds to an instant
bValid := TRUE;                               // 域内还原可用 / the in-domain instant is usable

// 段 5｜域端点提示（信息级，不置 bError）/ segment 5, domain endpoint hint at info level
IF (nWork = DL_EPOCH_SEC_ZERO) OR (nWork = DL_EPOCH_SEC_MAX) THEN
    eErr := 16#0001_040E;                     // 信息级：输入恰为域端点，多为上游哨兵值 / info level, a domain endpoint, often an upstream sentinel
END_IF
END_FUNCTION
