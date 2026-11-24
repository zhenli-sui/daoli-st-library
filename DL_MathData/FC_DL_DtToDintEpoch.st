(*
    FC_DL_DtToDintEpoch —— DATE_AND_TIME 到 Unix 纪元秒
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（DATE_AND_TIME → Unix 纪元秒）；
                委托平台内建 DT_TO_DINT 完成秒口径换算，本件不重实现历法内核；
                纪元下域闸门、Y2038 上域饱和出口、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 把 PLC 本地时刻统一落成 MES / 日志通用的 Unix 纪元秒（1970-01-01T00:00:00Z 起算）。
                核心防御：① 早于纪元的时刻在类型域上可能出现（平台允许任意 DT 位型），
                   一律在调用内建前拦下——域外调用内建会得到回绕负值，混入日志后无法追溯；
                ② Y2038 是 DINT 秒域硬边界：结果超域时饱和至上限并升故障级，
                   绝不让溢出后的负秒静默流进 MES 台账；
                ③ 结果进入 Y2038 邻近带（2035-01-01 起）只发信息级告警，
                   量仍然可用——告警与故障分级严格分开，HMI 不因提示码停机；
                ④ 负秒重判为第二道防线：域门已保证不可达，仍保留判据，
                   防平台 DT_TO_DINT 在内建层做异常符号处理。
                职责边界：反方向（纪元秒 → DT）归 FC_DL_DintEpochToDt；
                日期天数化归 FC_DL_DateToDintDays；本件只承担「时刻 → 秒」单向标准化。
    编译门槛  : 主路径依赖平台内建 DT_TO_DINT（DT 秒口径），三平台标准库均提供。
                若目标平台缺该内建，按合成路径落地：DT_TO_DATE 取天数、DT_TO_TOD 取当日
                毫秒再折秒，nSec = nDays * DL_SEC_PER_DAY + nSecOfDay；乘法前先判
                nDays < DL_EPOCH_SEC_MAX / DL_SEC_PER_DAY（先判后算，防 DINT 乘法溢出）。
                合成路径不改变本件的闸门顺序与出口，仅替换段 3 的内建调用。
    错误码    : 16#0001_040C Y2038 邻近告警（结果已进入 2035-01-01 起算的告警带）——信息级，值仍可用
                16#0001_040D 预留禁用（信息级，不得挪用）
                16#0001_0330 输入时刻早于纪元（1970-01-01-00:00:00 之前）——故障级，返回 0
                16#0001_0331 结果超出 DINT 秒域（Y2038 2038-01-19T03:14:07Z 之后）——故障级，已饱和至上限
                16#0001_0332 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_040C 用 / 16#0001_040D 预留 ｜ 16#0001_0330 用 / 16#0001_0331 用 / 16#0001_0332 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_DtToDintEpoch : DINT
VAR_INPUT
    dtIn             : DATE_AND_TIME;         // 输入时刻 [日期时间]，有效域自 1970-01-01-00:00:00 起 / input instant [date and time], domain starts at the epoch
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 返回值是否可用（故障级为 FALSE）/ return usable, FALSE on fault level
END_VAR
VAR CONSTANT
    DL_EPOCH_SEC_MAX : DINT := 2147483647;    // DINT 秒域上限，即 2038-01-19T03:14:07Z [s] / DINT second domain top, the Y2038 instant [s]
    DL_Y2038_WARN_SEC : DINT := 2051222400;   // Y2038 告警阈值，即 2035-01-01T00:00:00Z [s] / Y2038 warning threshold [s]
    DL_SEC_PER_DAY   : DINT := 86400;         // 每日秒数 [s/日]，合成路径备用量 / seconds per day [s/day], reserved for the synthesis path
    DL_DINT_ZERO     : DINT := 0;             // 有符号零常量，避免裸字面量 [s] / signed zero constant [s]
    DL_EPOCH_DT_ZERO : DATE_AND_TIME := DT#1970-01-01-00:00:00; // 纪元起点时刻 / the epoch instant
END_VAR
VAR
    nSec             : DINT;                  // 纪元秒中间量 [s] / epoch second intermediate [s]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DtToDintEpoch := DL_DINT_ZERO;          // 故障缺省返回 0 [s] / fault default returns zero [s]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
nSec := DL_DINT_ZERO;                         // 中间量清零 / clear the intermediate

// 段 2｜下域闸门：早于纪元的时刻在调用内建之前拦下 / segment 2, epoch lower gate precedes any built-in call
IF dtIn < DL_EPOCH_DT_ZERO THEN
    eErr := 16#0001_0330;                     // 故障级：输入早于纪元 / fault level, the input precedes the epoch
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_DtToDintEpoch := DL_DINT_ZERO;      // 确定缺省值 0 / deterministic default of zero
    RETURN;                                   // 出口，不触碰内建 / exit, the built-in is never touched
END_IF

// 段 3｜主体：域内才委托平台内建（秒口径） / segment 3, delegate the built-in only inside the domain
nSec := DT_TO_DINT(dtIn);                     // 内建换算：DT → 纪元秒 [s] / built-in conversion from DT to epoch seconds [s]

// 段 4｜负值第二道防线（域门已保证不可达，保留以防内建层异常符号处理）/ segment 4, second line of defence against a negative result
IF nSec < DL_DINT_ZERO THEN
    eErr := 16#0001_0330;                     // 故障级：内建层给出负秒，等价于早于纪元 / fault level, a negative second means the epoch was underflowed
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / flag the return as unusable
    FC_DL_DtToDintEpoch := DL_DINT_ZERO;      // 确定缺省值 0 / deterministic default of zero
    RETURN;                                   // 出口 / exit
END_IF

// 段 5｜Y2038 上域闸：溢出不容静默，饱和并升故障级 / segment 5, Y2038 upper gate, saturation is reported as a fault
IF nSec > DL_EPOCH_SEC_MAX THEN
    nSec := DL_EPOCH_SEC_MAX;                 // 饱和至 DINT 秒域上限 [s] / saturate to the DINT second domain top [s]
    FC_DL_DtToDintEpoch := nSec;              // 发布饱和值供 HMI 观察 / publish the saturated value so HMI can see the overrun
    eErr := 16#0001_0331;                     // 故障级：结果超 DINT 秒域，已饱和 / fault level, the result passed the domain and was saturated
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 饱和值不可用于台账 / the saturated value must not enter the ledgers
    RETURN;                                   // 出口 / exit
END_IF

// 段 6｜发布结果与 Y2038 邻近告警（信息级永不置 bError）/ segment 6, publish and raise the info-level Y2038 warning
FC_DL_DtToDintEpoch := nSec;                  // 输出纪元秒 [s] / publish the epoch seconds [s]
bValid := TRUE;                               // 域内与告警带内均可用 / usable inside the domain and inside the warning band
IF nSec >= DL_Y2038_WARN_SEC THEN
    eErr := 16#0001_040C;                     // 信息级：Y2038 邻近告警，值仍可用 / info level, near Y2038, the value is still usable
END_IF
END_FUNCTION
