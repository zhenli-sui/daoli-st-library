(*
  FC_DL_TimeToCycleCeil  —  时间→扫描周期数向上取整（正好整除不 +1，含 0 与上限钳制） / Time to scan-cycle count with ceiling, exact-division and limit clamping
  分类 Category : DL_Base
  版本 Version  : 1.0.0
  来源 Source   : iec-std-wrapper — T0 防御包装（不重实现数学内核，仅按标准语义做域守卫与钳制）
  溯源 Origin   : 本件为「IEC 61131-3 标准语义的道莅防御性实现」：委托 TIME_TO_UDINT 与整数除法内建，
                 不重写取整内核，只在委托链外层补齐零值、异常域、上限与溢出四类守卫
  功能 Function : 1) 委托链：TIME → UDINT（ms）→ 商 / 余数 → 余量进位（ceil）；
                  2) 正好整除边界：余数为 0 时商不 +1（验收向量：tSpan = 3 s、tCycle = 1 s → 3，
                  非 4）；3) 非整除边界：tSpan = 3.5 s、tCycle = 1 s → 4；
                  4) 零值边界：tSpan <= 0 → 返回 0（零周期，正常语义，非错误）；
                  5) 上限钳制：商超过 nCycleMax → 返回 nCycleMax（饱和，可表性反算见边界）；
                  6) 异常域：tCycle <= 0 或 nCycleMax = 0 → 返回 0 哨兵并置 16#0001_0002。
  接口 Interface: 入 tSpan / tCycle / nCycleMax；出 返回值（周期数） + nErrId（错误码）
  边界 Boundary : ① 除数 tCycle 非正时直接返回 0 哨兵（不进入除法，禁零除）；
                  ② 商 +1 溢出处以 16#FFFF_FFFF 反算判据拦截（极限值→类型可表性反算）；
                  ③ 上限钳制先于返回，钳制值来自引脚 nCycleMax（无魔法数）；
                  ④ 全部整数运算（UDINT），无浮点、无取舍歧义；⑤ 本 FC 无内部状态、无静态变量，
                  同一扫描周期内多次调用结果一致。
  依赖 Depends  : Standard.library（TIME_TO_UDINT）
  码表 Error codes（Base 段 0001，故障/异常窗口 0002；本件无信息码）:
    16#0001_0002 故障级：入参域非法（tCycle 非正 或 nCycleMax = 0），返回 0 哨兵；
                 本 FC 无锁存能力，码随每次调用重算并由调用方判读
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 4 · 序号 20）
*)

FUNCTION FC_DL_TimeToCycleCeil : UDINT
VAR_INPUT
    tSpan     : TIME;             // 时间跨度 [ms]，负值按 0 处理 / Time span, negatives treated as zero
    tCycle    : TIME := T#1S;     // 扫描周期 [ms]，域 > 0 / Scan cycle, must be positive
    nCycleMax : UDINT := 1000000; // 周期数上限 [次]，域 > 0 / Cycle count upper limit
END_VAR
VAR_OUTPUT
    nErrId    : UDINT;            // 错误码，0 = 无错误 / Error code, zero means no error
END_VAR
VAR
    nSpanMs   : UDINT;            // 跨度毫秒值 [ms] / Span in milliseconds
    nCycleMs  : UDINT;            // 周期毫秒值 [ms] / Cycle in milliseconds
    nQuot     : UDINT;            // 商（周期数） [次] / Quotient
    nRem      : UDINT;            // 余数 [ms] / Remainder
END_VAR

(* —— 段 0：异常域守卫（除零前置判，禁进入除法） —— *)
nErrId := 16#0000_0000;                      // 错误码缺省无错误 / Error code default
FC_DL_TimeToCycleCeil := 0;                  // 返回值缺省 0 / Return default
IF (tCycle <= T#0S) OR (nCycleMax = 0) THEN  // 入参域非法（当拍判据） / Illegal input domain
    nErrId := 16#0001_0002;                  // 异常码：入参域非法 / Invalid-input code
    RETURN;                                  // 返回 0 哨兵，不进入除法 / Return sentinel
END_IF

(* —— 段 1：零值边界（跨度非正 → 0 周期，正常语义） —— *)
IF tSpan <= T#0S THEN                        // 跨度为 0 或负 / Zero or negative span
    FC_DL_TimeToCycleCeil := 0;              // 零周期（非错误） / Zero cycles, not an error
    RETURN;
END_IF

(* —— 段 2：委托内建取商与余数（TIME_TO_UDINT 委托） —— *)
nSpanMs := TIME_TO_UDINT(tSpan);             // 跨度毫秒 [ms] / Span in ms
nCycleMs := TIME_TO_UDINT(tCycle);           // 周期毫秒 [ms] / Cycle in ms
nQuot := nSpanMs / nCycleMs;                 // 商（截断取整） [次] / Truncated quotient
nRem := nSpanMs MOD nCycleMs;               // 余数 [ms] / Remainder

(* —— 段 3：余量进位（正好整除不 +1；溢出与上限双守卫） —— *)
IF nRem > 0 THEN                             // 有剩余才进位（正好整除不进位） / Ceil only when remainder exists
    IF nQuot = 16#FFFF_FFFF THEN             // 商已达类型上界：进位必溢出 / Overflow guard
        nQuot := nCycleMax;                  // 直接取上限钳制值 / Saturate to limit
    ELSE
        nQuot := nQuot + 1;                  // 余量进位 / Ceiling increment
    END_IF
END_IF

(* —— 段 4：上限钳制（先钳制后返回，钳制值来自引脚） —— *)
IF nQuot > nCycleMax THEN                    // 超上限 / Above limit
    nQuot := nCycleMax;                      // 饱和到上限（验收向量：上限 +1 → 上限） / Saturate
END_IF

FC_DL_TimeToCycleCeil := nQuot;              // 返回周期数 / Return cycle count
END_FUNCTION
