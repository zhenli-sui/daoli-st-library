(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EventRateCalc
 * 溯源说明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现（零检索变体线）
 * 所属子库 (Sublibrary) : DL_MathData / Statistics
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON / R_TRIG
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 滑窗事件速率
 * 功能一句话 (Summary)  : 环形 60 桶滑窗事件计数，输出事件每分钟速率与累计数。
 * 边界与安全 (Boundary) : ①窗口小于 1 s 钳 1 s；大于 1 h 钳 1 h，均置钳位码；
 *                         ②钳位后继续正常工作（码级不断链）；
 *                         ③bReset 清全部桶、速率与累计；
 *                         ④桶推进定时器与事件沿检测均无条件周期刷新；
 *                         ⑤窗口时长为 0 防御（除零前判）。
 * 错误码    : 16#0001_03C3 窗口钳位发生（1 s 或 1 h 边界）——故障级（持续态）
 *             16#0001_03C4 保留禁用（不得挪用，本件零赋值）
 * 码位总账  : 16#0001_03C3 用 ｜ 16#0001_03C4 预留
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_EventRateCalc
VAR_INPUT
    bEvent  : BOOL;   // 事件脉冲输入（内部取上升沿）/ Event pulse input (edge taken inside)
    tWindow : TIME;   // 滑窗时长 1 s~1 h，越界钳位 [ms] / Sliding window 1 s to 1 h, clamped
    bReset  : BOOL;   // 复位：清桶、速率与累计 / Reset: clear buckets, rate and total
END_VAR
VAR_OUTPUT
    fRate  : LREAL; // 事件速率（事件每分钟）/ Event rate (events per minute)
    uTotal : ULINT; // 累计事件总数 / Total accumulated events
    eErr   : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cBuckets   : INT := 60;        // 环形桶数（固定）/ Fixed ring bucket count
    cMsMin     : DINT := 1000;     // 窗口下限 1 s [ms] / Window lower bound 1 s [ms]
    cMsMax     : DINT := 3600000;  // 窗口上限 1 h [ms] / Window upper bound 1 h [ms]
END_VAR
VAR
    aBuckets   : ARRAY[0..59] OF ULINT; // 环形计数桶 / Ring counting buckets
    iHead      : INT;            // 当前桶索引 / Current bucket index
    tonBkt     : TON;            // 桶推进定时器（无条件刷新）/ Bucket advance timer (unconditional refresh)
    rTrigEvt   : R_TRIG;         // 事件上升沿检测（无条件刷新）/ Event rising edge (unconditional refresh)
    dwWinMs    : DINT;           // 窗口有效时长 [ms] / Effective window duration [ms]
    dwBktMs    : DINT;           // 单桶时长 [ms] / Per-bucket duration [ms]
    i          : INT;            // 求和游标 / Summation cursor
    uSum       : ULINT;          // 窗口内事件合计 / Events summed over window
    fWinSec    : LREAL;          // 窗口时长秒值（速率换算分母）/ Window seconds (rate denominator)
END_VAR

// ---------- 无条件周期刷新：沿检测 + 桶推进定时器 ----------
rTrigEvt(CLK := bEvent);
dwWinMs := TIME_TO_DINT(tWindow);            // 窗口毫秒读数 / Window in milliseconds

// ---------- 窗口钳位防御（先钳后用，码级持续态） ----------
eErr := 0;
IF dwWinMs < cMsMin THEN
    dwWinMs := cMsMin;                       // 下限钳 1 s / Clamp to 1 s lower bound
    eErr    := 16#0001_03C3;                 // 钳位码 / Clamp code
ELSIF dwWinMs > cMsMax THEN
    dwWinMs := cMsMax;                       // 上限钳 1 h / Clamp to 1 h upper bound
    eErr    := 16#0001_03C3;                 // 钳位码（复用同码）/ Clamp code (shared)
END_IF

// ---------- 复位优先：清桶清累计清速率 ----------
IF bReset THEN
    FOR i := 0 TO cBuckets - 1 DO
        aBuckets[i] := 0;                    // 清所有桶 / Clear all buckets
    END_FOR
    iHead  := 0;                             // 桶头归零 / Head index reset
    uTotal := 0;                             // 累计清零 / Total cleared
    fRate  := 0.0;                           // 速率清零 / Rate cleared
END_IF

// ---------- 桶推进：单桶时长 = 窗口 / 桶数（除零前判） ----------
IF dwWinMs > 0 THEN
    dwBktMs := dwWinMs / cBuckets;           // 整除单桶毫秒 / Integer per-bucket ms
ELSE
    dwBktMs := cMsMin;                       // 防御缺省（理论不可达）/ Defensive default
END_IF
tonBkt(IN := TRUE, PT := DINT_TO_TIME(dwBktMs));
IF tonBkt.Q THEN
    iHead := (iHead + 1) MOD cBuckets;       // 环形推进 / Ring advance
    aBuckets[iHead] := 0;                    // 新桶清零（旧桶自然滑出窗）/ New bucket cleared
END_IF

// ---------- 事件入桶：沿触发计数，累计同步递增 ----------
IF rTrigEvt.Q THEN
    aBuckets[iHead] := aBuckets[iHead] + 1;  // 当前桶计数加一 / Increment current bucket
    uTotal := uTotal + 1;                    // 累计事件加一 / Total incremented
END_IF

// ---------- 速率换算：窗口合计 / 窗口分钟数（分母前判零） ----------
uSum := 0;
FOR i := 0 TO cBuckets - 1 DO
    uSum := uSum + aBuckets[i];              // 窗口合计 / Window sum
END_FOR
fWinSec := ULINT_TO_LREAL(DINT_TO_ULINT(dwWinMs)) / 1000.0; // 窗口秒值 / Window seconds
IF fWinSec > 0.0 THEN
    fRate := ULINT_TO_LREAL(uSum) * 60.0 / fWinSec;    // 事件每分钟 / Events per minute
ELSE
    fRate := 0.0;                            // 除零防御缺省 / Divide-by-zero guard default
END_IF

END_FUNCTION_BLOCK
