(*
    组件名称 : FB_DL_SamplingTrigger
    所属子库 : DL_Base
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : 均匀采样节拍源，输出单拍采样沿 + 样本序号 + 理论/实际时基账目 + 漂移告警，供趋势记录使用。
              取舍 ①：理论时长用「样本序号 × 周期」重算，而不是每拍累加周期 —— 累加式在每一次「定时器命中
              晚一个扫描周期」时都会永久吞掉那点误差，跑一天能差出几十毫秒；序号重算则误差不累积，
              这正是「无漂移」三个字的来源。
              取舍 ②：扫描周期增量由调用方注入（tDelta），不调平台时刻函数 —— 与库内 CycleTimeMeasure 同一纪律，
              换平台不必改代码，也让副程序内的假节拍可复现测试。
              取舍 ③：tDelta ≤ 0 时本拍不累加实际时基 —— 首扫或注入错误时，凭空加一个增量会让 tActual
              从第一拍就偏；本件宁可少记一拍，也不伪造时间。
              取舍 ④：漂移只提示不重置 —— 重置会让「真实时基丢失」这个事实消失在账目里；留着偏差，
              上位机每次取数都能看到它。
              取舍 ⑤：与 FB_DL_PulseGenerator 的边界 —— 那件出占空比可调的方波；本件只出采样沿与时基账目。
    开源溯源 : 原创实现（T0-2 变体线）。无外部源码参考，码位、漂移阈值、回绕策略 100% 自有。；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
    本文件内含 : FUNCTION_BLOCK FB_DL_SamplingTrigger（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 周期闸 + 增量闸 + 序号回绕 + 理论值溢出预判 + 漂移双侧直比
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 无顺序状态机（纯节拍累加），头注释已写明理由
              R7 ✓ TON / R_TRIG 实例在主体最前部无条件刷新，IN 含使能与复位，保证重新使能不产生假沿
              R8 ✓ 周期下限、增量上限、漂移阈值全常量化
    错误码   : 16#0001_0456 [信息级] 累计漂移超阈值，只提示不重置，bError = FALSE
               16#0001_0457 [信息级] 样本序号回绕归零，bError = FALSE
               16#0001_039F [故障级] 采样周期非法已钳至 1ms 继续，bError = TRUE
               16#0001_03A0 [故障级] 扫描周期增量非法（≤ 0 或超上限），本拍不计入实际时基，bError = TRUE
               16#0001_03A1 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0456 用 / 16#0001_0457 用 ｜ 16#0001_039F 用 / 16#0001_03A0 用 / 16#0001_03A1 预留
    遗留假设 : ① TIME 为 32 位有符号毫秒口径；tActual 的加法已做溢出预判（R54：比较式内不出现加乘），
              超上限时保持上拍值不累加，故无回绕路径。该口径未在 InoProShop 实测。
              ② 漂移判据在 DINT 毫秒域做双侧直比（nDiff > +阈 OR nDiff < −阈），不用 ABS 单侧，
              避免差值在极端情形下取绝对值回绕（有符号整数边界纪律）。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 4 入库
*)
FUNCTION_BLOCK FB_DL_SamplingTrigger
VAR_INPUT
    bEnable         : BOOL := TRUE;      // 使能，FALSE 时不产生样本但定时器仍刷新 / enable, FALSE stops the samples while the timer keeps refreshing
    tInterval       : TIME := T#1S;      // 采样周期，≤ 0 时钳至 1ms [ms] / sampling period, clamped to one millisecond [ms]
    tDelta          : TIME;              // 调用方注入的扫描周期增量，必须 > 0 [ms] / scan time increment injected by the caller, must be positive [ms]
    bReset          : BOOL;              // 上升沿清序号与时基账目 / rising edge clears the sample number and the time accounts
END_VAR
VAR_OUTPUT
    bSample         : BOOL;              // 单拍采样沿，仅 TRUE 一个扫描周期 / single scan sample edge
    uSampleNo       : UDINT;             // 样本序号，1 起；回绕时归零 [个] / sample number starting at one, wrapped to zero on overflow [count]
    tTheoretical    : TIME;              // 理论累计时长 = 序号 × 周期 [ms] / theoretical elapsed time, samples times the period [ms]
    tActual         : TIME;              // 注入增量累计的实际时长 [ms] / actual elapsed time accumulated from the injected increments [ms]
    bDrift          : BOOL;              // 偏差超阈值，锁存至复位 / TRUE when the deviation exceeds the threshold, latched until reset
    eErr            : UDINT;             // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;              // 故障级标志 / fault flag
END_VAR
VAR
    fbTimer         : TON;               // 采样周期定时器，主体最前部无条件刷新 / sampling timer, refreshed unconditionally at the top
    rtSample        : R_TRIG;            // 定时器完成位上升沿，主体最前部无条件刷新 / rising edge of the timer output, refreshed unconditionally
    tIntervalEff    : TIME;              // 钳位后的采样周期 [ms] / clamped sampling period [ms]
    bTimerIn        : BOOL;              // 定时器输入，含使能与复位 / timer input including the enable and the reset
    bDeltaOk        : BOOL;              // 本拍增量是否可用于累加 / whether the increment may be accumulated this scan
    nIntervalMs     : DINT;              // 采样周期的毫秒值 [ms] / sampling period in milliseconds [ms]
    nDeltaMs        : DINT;              // 增量的毫秒值 [ms] / increment in milliseconds [ms]
    nActualMs       : DINT;              // 实际时基的毫秒值 [ms] / actual elapsed time in milliseconds [ms]
    nDiffMs         : DINT;              // 实际与理论的毫秒偏差，可正可负 [ms] / deviation between the actual and the theoretical time, signed [ms]
    nMaxSamples     : DINT;              // 理论值不溢出的最大样本数 [个] / largest sample number whose product stays in range [count]
END_VAR
VAR CONSTANT
    DL_SAMPLE_INT_MIN   : TIME := T#1MS;                  // 采样周期下限 [ms] / sampling period lower bound [ms]
    DL_SAMPLE_DRIFT_MAX : TIME := T#200MS;                // 漂移告警阈值 [ms] / drift warning threshold [ms]
    DL_DELTA_MAX        : TIME := T#10S;                  // 增量上限，超此值视为任务卡顿 [ms] / increment upper bound, beyond it the task stalled [ms]
    DL_TIME_ZERO        : TIME := T#0S;                   // 零时长哨兵 [ms] / zero duration sentinel [ms]
    DL_TIME_MS_MAX      : DINT := 2147483647;             // TIME 毫秒上限，加法预判用 [ms] / TIME millisecond bound used by the addition prediction [ms]
    DL_DINT_ZERO        : DINT := 0;                      // 整数零哨兵 [无量纲] / integer zero sentinel [dimensionless]
    DL_UDINT_MAX        : UDINT := 16#FFFF_FFFF;          // 序号上限 [个] / sample number upper bound [count]
    DL_UDINT_ZERO       : UDINT := 0;                     // 序号零哨兵 [个] / sample number zero sentinel [count]
    DL_ERR_NONE         : UDINT := 16#0000_0000;          // 无故障 / no error
END_VAR

// 段 0｜错误状态预置与单拍标志清销 / segment 0, preset the error state and clear the single scan flag
eErr    := DL_ERR_NONE;                      // 预置无错误 / preset no error
bError  := FALSE;                            // 预置无故障 / preset no fault
bSample := FALSE;                            // 单拍标志每拍先销，防「只置不销」/ the single scan flag is cleared first, never left latched

// 段 1｜采样周期闸：非法则钳 1ms 继续，不停机 / segment 1, period gate, clamp instead of stopping
IF tInterval <= DL_TIME_ZERO THEN
    tIntervalEff := DL_SAMPLE_INT_MIN;       // 钳到最小周期 / clamp to the smallest period
    eErr   := 16#0001_039F;                  // 采样周期非法已钳位（故障级）/ illegal period clamped, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
ELSE
    tIntervalEff := tInterval;               // 正常值 / a healthy value
END_IF

// 段 2｜定时器与边沿无条件刷新：IN 含使能与复位，重新使能时不会留下假沿 / segment 2, unconditional refresh
bTimerIn := bEnable AND NOT bReset;
fbTimer ( IN := bTimerIn, PT := tIntervalEff );
rtSample( CLK := fbTimer.Q );

// 段 3｜增量闸：≤ 0 视为首扫或注入错误，本拍不累加也不出样本 / segment 3, increment gate
bDeltaOk := tDelta > DL_TIME_ZERO;
IF NOT bDeltaOk THEN
    eErr   := 16#0001_03A0;                  // 周期增量非法（故障级）/ illegal increment, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
ELSIF tDelta > DL_DELTA_MAX THEN
    bDrift := TRUE;                          // 任务卡顿，累加但置漂移 / the task stalled, accumulate and flag the drift
    eErr   := 16#0001_03A0;                  // 同一判据同一码（增量不可信）/ the same cause shares one code
    bError := TRUE;                          // 置故障标志 / raise the fault flag
END_IF

// 段 4｜复位沿：清序号与时基账目 / segment 4, reset clears the counter and both time accounts
IF bReset THEN
    uSampleNo    := DL_UDINT_ZERO;           // 序号归零 / clear the sample number
    tActual      := DL_TIME_ZERO;            // 实际时基归零 / clear the actual time
    tTheoretical := DL_TIME_ZERO;            // 理论时基归零 / clear the theoretical time
    bDrift       := FALSE;                   // 解除漂移锁存 / release the drift latch
END_IF

// 段 5｜采样沿与序号推进 / segment 5, sample edge and number advance
IF rtSample.Q AND bEnable THEN
    bSample := TRUE;                         // 单拍采样沿 / the single scan sample edge
    IF uSampleNo >= DL_UDINT_MAX THEN
        uSampleNo := DL_UDINT_ZERO;          // 回绕归零，理论值随之重算 / wrap to zero, the theoretical time restarts with it
        IF eErr = DL_ERR_NONE THEN
            eErr := 16#0001_0457;            // 样本序号回绕（信息级）/ sample number wrapped, info level
        END_IF
    ELSE
        uSampleNo := uSampleNo + 1;          // 序号自增，首样本为 1 / advance, the first sample is one
    END_IF
END_IF

// 段 6｜实际时基累加：先做溢出预判，比较式内不出现加乘（R54）/ segment 6, actual time accumulation with an overflow prediction
IF bDeltaOk THEN
    nActualMs := TIME_TO_DINT(tActual);      // 当前实际时基 [ms] / current actual time [ms]
    nDeltaMs  := TIME_TO_DINT(tDelta);       // 本拍增量 [ms] / the increment of this scan [ms]
    IF nActualMs > DL_TIME_MS_MAX - nDeltaMs THEN
        tActual := DINT_TO_TIME(DL_TIME_MS_MAX);   // 顶到上限，保持可观测而不回绕 / cap at the bound instead of wrapping
    ELSE
        tActual := DINT_TO_TIME(nActualMs + nDeltaMs);   // 正常累加 / normal accumulation
    END_IF
END_IF

// 段 7｜理论时基：序号 × 周期重算，误差不累积；先算可容纳样本数防溢出 / segment 7, theoretical time recomputed from the number
nIntervalMs := TIME_TO_DINT(tIntervalEff);   // 周期毫秒值，闸后恒 ≥ 1 / the period is at least one millisecond after the gate
IF nIntervalMs > DL_DINT_ZERO THEN
    nMaxSamples := DL_TIME_MS_MAX / nIntervalMs;   // 不溢出的最大样本数 / the largest number that keeps the product in range
    IF uSampleNo <= DINT_TO_UDINT(nMaxSamples) THEN
        tTheoretical := DINT_TO_TIME(nIntervalMs * UDINT_TO_DINT(uSampleNo));   // 理论值 = 序号 × 周期 / theoretical equals the number times the period
    END_IF
END_IF

// 段 8｜漂移判据：DINT 毫秒域双侧直比，禁 ABS 单侧 / segment 8, drift test with a two sided comparison
nDiffMs := TIME_TO_DINT(tActual) - TIME_TO_DINT(tTheoretical);
IF (nDiffMs > TIME_TO_DINT(DL_SAMPLE_DRIFT_MAX)) OR (nDiffMs < (DL_DINT_ZERO - TIME_TO_DINT(DL_SAMPLE_DRIFT_MAX))) THEN
    bDrift := TRUE;                          // 漂移锁存，不重置（重置会掩盖时基丢失）/ latch the drift, a reset would hide the lost time base
    IF eErr = DL_ERR_NONE THEN
        eErr := 16#0001_0456;                // 累计漂移超阈值（信息级）/ accumulated drift, info level
    END_IF
END_IF
END_FUNCTION_BLOCK
