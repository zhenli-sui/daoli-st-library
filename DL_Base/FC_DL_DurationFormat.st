(*
    FC_DL_DurationFormat —— TIME 时长分解为 天/时/分/秒 四分量（HMI 显示用纯函数）
    ------------------------------------------------------------------
    组件名称  : FC_DL_DurationFormat
    分类      : DL_Base / TimeFormat
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— IEC 61131-3 TIME 类型语义（无符号毫秒容器），
                T0-2 族内补口（Date and Timer → DL_Base 分类事实，T0 = 1，
                允许区间 0~1）。
                本件只借**标准类型语义**，分解规格与码位口径为自有。
                clean-room 声明 —— 零代码行复制；仅用标准类型转换
                TIME_TO_DINT / DINT_TO_UDINT 与整除 / 取模运算符。
                许可证 —— 本件 MIT。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 1 · 序号 4）
    ------------------------------------------------------------------
    功能说明  : 将输入时长 tDur 一次性换算到毫秒整数，再整除分解为
                天 / 时 / 分 / 秒四分量（HMI 显示口径，秒以下毫秒余量舍弃，
                向下取整到秒）：
                uDays  = uMs / 86400000，余数级联
                uHours = 余 / 3600000，余数级联
                uMins  = 余 / 60000，余数级联
                uSecs  = 余 / 1000，毫秒余量 = bTruncated 判据。
                除法除子全为**常量** 86400000 / 3600000 / 60000 / 1000
                （VAR CONSTANT 声明），**无变量除零面**（R45 纪律：常量除子
                不设判零闸，头注释声明即为口径）。
                负 TIME 不可表示（TIME 无符号语义）：输入域闸按防御性复检
                落码 —— TIME_TO_DINT 结果 < 0 即拒绝（非法入参），四分量
                清零、返回 FALSE；标准平台负 TIME 本就不可构造，闸属防御
                兜底而非业务判据（声明口径）。
                uDays 上界声明：TIME 容器毫秒上限 2147483647 ms（DINT 域）
                ÷ 86400000 = 24 天余 63487 秒分量 —— 四分量均为 UDINT，
                分解结果恒在容器内，无溢出面（声明即口径）。
    错误码    : N/A —— 本件按计划规格不出码位（输出契约：四分量 + bValid +
                bTruncated）；入参非法以返回值 FALSE 表达，四分量清零，
                绝不送未定义值给下游。
    码位总账  : 无码位（计划口径：多出口分解件，有效性以 bValid / 返回值承载）
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无边沿实例 / 无数组下标，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 整除分解全链无浮点量、无浮点判等面（纯整数运算）；
                四 bTruncated 语义：毫秒余量非零被舍弃（显示口径为向下取整
                   到秒），非「容器上界截断」—— TIME 入参本身即为容器
                   全域，不存在入参超出容器的问题（R191 名实双出口：
                   位名 bTruncated 对齐「余量舍弃」实现语义）；
                五 返回值即 bValid 语义（出参契约：入参合法且已完整分解
                   才 TRUE）。
    分工声明  : FC_DL_TimeToDintMs（DL_MathData，TIME → DINT 毫秒单一数值
                换算）、FC_DL_TimeToLrealSec（DL_MathData，TIME → LREAL 秒
                单一数值换算）—— 两者为**单一数值换算**件；本件为**日历
                分量分解**件（天 / 时 / 分 / 秒多出口语义，HMI 显示用），
                分工边界为「一个数 vs 四个分量」，非同算法变体，互引不互代。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 1 · 序号 4）
*)
FUNCTION FC_DL_DurationFormat : BOOL
VAR_INPUT
    tDur : TIME;                           (* 输入时长（TIME 无符号毫秒容器），[ms] / the input duration, an unsigned millisecond TIME container *)
END_VAR
VAR_OUTPUT
    uDays      : UDINT;                    (* 天分量，[d]，上界 24（TIME 容器毫秒上限 ÷ 86400）/ the days component, capped at 24 by the container *)
    uHours     : UDINT;                    (* 时分量，[h]，域 [0, 23] / the hours component, 0..23 *)
    uMins      : UDINT;                    (* 分分量，[min]，域 [0, 59] / the minutes component, 0..59 *)
    uSecs      : UDINT;                    (* 秒分量，[s]，域 [0, 59] / the seconds component, 0..59 *)
    bTruncated : BOOL;                     (* 毫秒余量非零被舍弃（显示口径向下取整到秒），[标志] / TRUE when a nonzero millisecond remainder was discarded *)
END_VAR
VAR CONSTANT
    DL_DUF_MS_DAY  : UDINT := 86400000;    (* 一天的毫秒数（常量除子，无变量除零面）/ the milliseconds per day, a constant divisor *)
    DL_DUF_MS_HOUR : UDINT := 3600000;     (* 一小时的毫秒数（常量除子）/ the milliseconds per hour, a constant divisor *)
    DL_DUF_MS_MIN  : UDINT := 60000;       (* 一分钟的毫秒数（常量除子）/ the milliseconds per minute, a constant divisor *)
    DL_DUF_MS_SEC  : UDINT := 1000;        (* 一秒的毫秒数（常量除子）/ the milliseconds per second, a constant divisor *)
END_VAR
VAR
    dMs   : DINT;                          (* 毫秒整数中间量（容器原值），[ms] / the millisecond integer temporary *)
    uMs   : UDINT;                         (* 毫秒无符号中间量，[ms] / the unsigned millisecond temporary *)
    uRem1 : UDINT;                         (* 天分解余数，[ms] / the remainder after the days split *)
    uRem2 : UDINT;                         (* 时分解余数，[ms] / the remainder after the hours split *)
    uRem3 : UDINT;                         (* 分分解余数，[ms] / the remainder after the minutes split *)
END_VAR

// 段 1｜返回值与分量预置（统一出口预置，R256）/ segment 1, preset the return and the components
FC_DL_DurationFormat := FALSE;             // 故障缺省返回不可信 / the fault default is not trustworthy
uDays      := 0;                           // 天分量预置零 / preset the days component to zero
uHours     := 0;                           // 时分量预置零 / preset the hours component to zero
uMins      := 0;                           // 分分量预置零 / preset the minutes component to zero
uSecs      := 0;                           // 秒分量预置零 / preset the seconds component to zero
bTruncated := FALSE;                       // 舍弃标志预清零 / preset the truncation flag false

// 段 2｜容器换算与负值防御闸（TIME 无符号语义，负值不可表示，防御性复检）/ segment 2, the container conversion and the negative guard
dMs := TIME_TO_DINT(tDur);                 // 容器毫秒原值（标准类型转换）/ the container value in ms, a standard conversion
IF dMs < 0 THEN                            // 负值不可表示（非法入参，防御兜底）/ a negative value is not representable
    RETURN;                                // 结构早退（分量保持清零预置，返回 FALSE）/ structural exit, the components stay zeroed
END_IF

// 段 3｜整除分解（常量除子级联，无变量除零面）/ segment 3, the integer division cascade
uMs   := DINT_TO_UDINT(dMs);               // 毫秒无符号化（已过负值闸，无负数面）/ the unsigned milliseconds, guarded
uDays := uMs / DL_DUF_MS_DAY;              // 天分量（整除向下取整）/ the days component
uRem1 := uMs MOD DL_DUF_MS_DAY;            // 天分解余数 / the remainder after days
uHours := uRem1 / DL_DUF_MS_HOUR;          // 时分量 / the hours component
uRem2 := uRem1 MOD DL_DUF_MS_HOUR;         // 时分解余数 / the remainder after hours
uMins := uRem2 / DL_DUF_MS_MIN;            // 分分量 / the minutes component
uRem3 := uRem2 MOD DL_DUF_MS_MIN;          // 分分解余数 / the remainder after minutes
uSecs := uRem3 / DL_DUF_MS_SEC;            // 秒分量 / the seconds component

// 段 4｜毫秒余量舍弃声明（bTruncated 名实对齐，边界四）/ segment 4, the millisecond remainder disclosure
bTruncated := (uRem3 MOD DL_DUF_MS_SEC) <> 0; // 余量非零即已舍弃 / a nonzero remainder was discarded

// 段 5｜正常出口 / segment 5, the normal outlet
FC_DL_DurationFormat := TRUE;              // 入参合法且已完整分解 / a valid input fully decomposed
END_FUNCTION
