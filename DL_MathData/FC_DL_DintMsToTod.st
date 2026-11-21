(*
    FC_DL_DintMsToTod —— 当日毫秒到 TOD 的防御转换
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeConv
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准 TOD 语义的道莅防御性实现；本件为
                FC_DL_TodToDintMs 的严格逆运算，接口语义由标准定义，
                内部委托平台内建 DINT_TO_TOD，不自行按时基重算；
                外围错误分级、单圈折回、双端钳位与双语文档 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把「自当日 00:00 起的毫秒数」还原为 TOD，供上层排程件与定时器比较。
                有效域 0~86399999 ms；可接受域 -86400000~172799999 ms（含跨日正负各一圈）。
                核心防御：① 超可接受域直接故障级 031E 早退，绝不对非法值调内建；
                ② 负值按单圈折回当日（先判后算，仅一圈内成立，无循环语句）；
                ③ 钳位只在 0 与 86399999 ms 两端，越界量由 bClampSilently 决定分级；
                ④ 交付门槛：委托 DINT_TO_TOD 内建链，须在 CODESYS / TwinCAT 3 /
                   InoProShop 三平台各编译验证一次（跨平台时间类转换链行为存疑）。
                职责边界：本件只做数值还原，不判时区、不做日历进位。
    错误码    : 16#0001_0400 输入越当日域已被钳位到 0 或 86399999 ms——信息级，正常防御
                16#0001_0401 预留禁用（信息级，不得挪用）
                16#0001_031E 输入超可接受域（< -86400000 ms 或 > 172799999 ms）——故障级，返回 T#0S 且 bValid = FALSE
                16#0001_031F 调用方要求不静默（bClampSilently = FALSE）且发生钳位——故障级，返回钳位值但 bValid = FALSE
                16#0001_0320 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0400 用 / 16#0001_0401 预留 ｜ 16#0001_031E 用 / 16#0001_031F 用 / 16#0001_0320 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无顺序状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION FC_DL_DintMsToTod : TOD
VAR_INPUT
    nMsOfDay        : DINT := 0;              // 当日毫秒偏移 [ms]，有效域 0~86399999，可接受域 -86400000~172799999 / day-millisecond offset [ms], valid 0~86399999, accepted -86400000~172799999
    bClampSilently  : BOOL := TRUE;           // TRUE = 越界钳位只置信息码；FALSE = 越界置故障级 / TRUE clamps with info code only, FALSE raises a fault level
END_VAR
VAR_OUTPUT
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 返回值是否可用 / return value valid flag
    bClamped        : BOOL;                   // 本拍是否发生钳位 / clamp event in this cycle
END_VAR
VAR CONSTANT
    DL_TOD_MS_MIN   : DINT := 0;              // 当日毫秒下界 [ms] / day-millisecond lower bound [ms]
    DL_TOD_MS_MAX   : DINT := 86399999;       // 当日毫秒上界（24 h − 1 ms） [ms] / day-millisecond upper bound, 24 h minus 1 ms [ms]
    DL_TOD_DAY_MS   : DINT := 86400000;       // 一整天毫秒数（单圈折回用） [ms] / milliseconds of one day, for single-wrap folding [ms]
    DL_TOD_MS_MIN_EXT : DINT := -86400000;    // 可接受下界（跨日回退一圈） [ms] / accepted lower bound, one day backwards [ms]
    DL_TOD_MS_MAX_EXT : DINT := 172799999;    // 可接受上界（跨日超前一圈） [ms] / accepted upper bound, one day forwards [ms]
END_VAR
VAR
    nMs             : DINT;                   // 折回与钳位后的中间毫秒值 [ms] / intermediate millisecond value after folding and clamping [ms]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_DintMsToTod := T#0S;                    // 故障缺省返回当日零点 / fault default returns midnight
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bClamped := FALSE;                            // 预置未钳位 / preset no clamp

// 段 2｜可接受域闸门（越一圈直接故障级，绝不对非法值调内建）/ segment 2, accepted domain gate
IF (nMsOfDay < DL_TOD_MS_MIN_EXT) OR (nMsOfDay > DL_TOD_MS_MAX_EXT) THEN
    eErr := 16#0001_031E;                     // 超可接受域故障码 / accepted domain exceeded fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 返回值不可用 / return value not usable
    FC_DL_DintMsToTod := T#0S;                // 明确返回零点，不用非法值调内建 / return midnight explicitly, never feed an illegal value to the built-in
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 3｜负值单圈折回当日（先判后算，无循环语句）/ segment 3, fold negative values back by one day
nMs := nMsOfDay;                              // 取入参副本参与运算，不改调用方数据 / copy the input, never modify caller data
IF nMs < DL_TOD_MS_MIN THEN
    nMs := nMs + DL_TOD_DAY_MS;               // 单圈折回：域已由段 2 保证 |nMs| ≤ 一圈 / single wrap is enough, segment 2 bounded the magnitude to one day
END_IF

// 段 4｜当日双端钳位（永不对非法值直接调内建）/ segment 4, clamp on both day bounds
IF nMs < DL_TOD_MS_MIN THEN
    nMs := DL_TOD_MS_MIN;                     // 防御性兜底：折回后仍为负则钳 0 ms / defensive floor, clamp to 0 ms if still negative
    bClamped := TRUE;                         // 记录钳位事件 / record the clamp event
ELSIF nMs > DL_TOD_MS_MAX THEN
    nMs := DL_TOD_MS_MAX;                     // 越上界钳 86399999 ms（24 h − 1 ms） / clamp to 86399999 ms, 24 h minus 1 ms
    bClamped := TRUE;                         // 记录钳位事件 / record the clamp event
END_IF

// 段 5｜钳位分级：静默只置信息码，不静默置故障级但返回钳位值 / segment 5, clamp severity
IF bClamped THEN
    IF bClampSilently THEN
        eErr := 16#0001_0400;                 // 信息级：越当日域已钳位，正常防御，不置故障 / info level, clamped into the day domain, no fault raised
        bValid := TRUE;                       // 钳位值仍可用 / the clamped value is usable
    ELSE
        eErr := 16#0001_031F;                 // 故障级：调用方要求不静默 / fault level, the caller refused silent clamping
        bError := TRUE;                       // 置故障标志 / raise the error flag
        bValid := FALSE;                      // 钳位结果标记为不可用 / the clamped result is flagged unusable
    END_IF
ELSE
    eErr := 0;                                // 一轮内合法输入不进钳位分支 / in-domain input never enters the clamp branch
    bValid := TRUE;                           // 域内结果可用 / in-domain result is usable
END_IF

// 段 6｜委托内建转换（入参已保证落在 0~86399999 ms）/ segment 6, delegate to the built-in conversion
FC_DL_DintMsToTod := DINT_TO_TOD(nMs);        // 委托内建，不自行按时基累加 / delegate to the built-in, never accumulate the time base by hand
END_FUNCTION
