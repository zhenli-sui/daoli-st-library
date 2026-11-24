(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CycleTimeMeasure
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零平台时刻函数
 * 功能描述 (Function)   : 任务扫描周期统计（最近 / 最小 / 最大 / 平均 / 样本数）。
 *                         本块自身不读取任何平台时刻，时间增量由调用方以输入引脚注入，
 *                         因此零平台依赖、三平台可编译，平台差异被关在调用方一处。
 *                         零增量与超上限增量一律拒收并告警，避免垃圾样本污染极值；
 *                         窗内首个有效样本同时初始化最小值与最大值（不得以 0 当初始值）；
 *                         样本数达上限自动重开统计窗并告警（无符号累计上限保护）。
 * 开源溯源 (Origin)     : 原创实现。指标口径（最近/最小/最大/平均/样本数）参照
 *                         工业界周期监控块的通用输出集合；时间注入设计为本库对
 *                         平台时刻函数依赖的主动拒绝方案，未复制任何源码。
 * 本文件内含       : FB    FB_DL_CycleTimeMeasure（单 POU，无配套类型）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3，零平台时刻函数 ｜ R4 ✓ 除零双保险 + 数据拒收 + 窗滚动
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯统计累加，无跨周期状态转移）
 *                         R7 ✓ R_TRIG 主体最前部无条件刷新 ｜ R8 ✓ 上限与阈值全常量化
 *
 * 【调用方契约 / Caller contract（边界 B8）】
 *   调用方须在同一任务内以"当前系统时刻 − 上周期系统时刻"得到毫秒增量后注入本引脚；
 *   首扫须跳过或注入一个已知有效值，否则 0 增量会被本块按无效数据处理并告警。
 *   本块不做任何时刻获取、不做跨任务共享，一个任务一个实例。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 A）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CycleTimeMeasure
VAR_INPUT
    uDeltaTimeMs : UDINT;              // 本任务周期实际耗时 [ms]，调用方注入 / Actual cycle time in ms, caller-provided
    bCapture     : BOOL := TRUE;       // TRUE = 本周期计入统计 / TRUE = include this cycle in statistics
    bReset       : BOOL;               // 上升沿清空全部统计 / Rising edge clears statistics
END_VAR
VAR_OUTPUT
    uCycleLast   : UDINT;              // 最近一个有效周期 [ms] / Last valid cycle time [ms]
    uCycleMin    : UDINT;              // 统计窗内最小周期 [ms] / Minimum in window [ms]
    uCycleMax    : UDINT;              // 统计窗内最大周期 [ms] / Maximum in window [ms]
    fCycleMean   : REAL;               // 统计窗内平均周期 [ms] / Mean in window [ms]
    nSampleCount : UDINT;              // 统计窗内样本数 [个] / Sample count in window [count]
    uErrorId     : UDINT;              // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uSumMs       : UDINT;              // 窗内累计耗时总和 [ms] / Accumulated sum in window [ms]
    fbTrigReset  : R_TRIG;             // 复位上升沿检测实例 / Reset rising edge detector instance
    bDeltaValid  : BOOL;               // 本周期增量有效性判定结果 / Current-cycle delta validity result
END_VAR
VAR CONSTANT
    DL_CYC_SAMPLE_MAX : UDINT := 1000000;   // 统计窗样本上限，达限自动重开窗 / Window sample cap, auto reopen at limit
    DL_CYC_DELTA_MAX  : UDINT := 3600000;   // 单周期合理上限 [ms]，超限视为无效数据 / Sanity cap per cycle [ms]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：复位沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: the reset edge instance runs at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜故障码本周期清零：错误码是"当前周期事实"，不是跨周期锁存量
 *      Error code is cleared every scan: it reports the current cycle only
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 3｜复位语义（边界 B7）：全部统计量归零，下一有效样本重新初始化极值
 *      Reset: clear every statistic, the next valid sample re-initialises extremes
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    uCycleLast   := UDINT#0;
    uCycleMin    := UDINT#0;
    uCycleMax    := UDINT#0;
    fCycleMean   := 0.0;
    nSampleCount := UDINT#0;
    uSumMs       := UDINT#0;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜增量合法性判定（边界 B2/B3）：0 表示调用方没取到时间，不是 0ms 快周期
 *      Delta validity: zero means the caller failed to read time, not a 0 ms cycle
 *      超上限增量同样拒收，防止取错基准产生的垃圾样本把 min / max 永久污染
 *      Over-limit deltas are rejected too, so a wrong time base cannot poison extremes
 *-----------------------------------------------------------------------------*)
IF (uDeltaTimeMs = UDINT#0) OR (uDeltaTimeMs > DL_CYC_DELTA_MAX) THEN
    bDeltaValid := FALSE;
    uErrorId    := 16#0001_0008;
ELSE
    bDeltaValid := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜统计窗滚动（边界 B6）：样本数达上限先重开窗再采集，避免无符号累计失控
 *      Window rolling: reopen the window before sampling when the cap is reached
 *      重开窗保留 uCycleLast（HMI 上最近值不能跳变），min / max / sum / count 清零
 *      uCycleLast is preserved across a reopen so the HMI last-value does not jump
 *-----------------------------------------------------------------------------*)
IF nSampleCount >= DL_CYC_SAMPLE_MAX THEN
    uCycleMin    := UDINT#0;
    uCycleMax    := UDINT#0;
    fCycleMean   := 0.0;
    nSampleCount := UDINT#0;
    uSumMs       := UDINT#0;
    uErrorId     := 16#0001_0007;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜采样与极值更新（边界 B4）：首样本同时写入最小与最大值
 *      Sampling and extremes: the first valid sample initialises both min and max
 *      以 0 当初始值会让最小值永远是 0——经典缺陷，此处以计数为零作首样本判据
 *      Initialising with zero would pin the minimum at zero forever
 *-----------------------------------------------------------------------------*)
IF bDeltaValid AND bCapture THEN

    uCycleLast := uDeltaTimeMs;

    IF nSampleCount = UDINT#0 THEN
        (* 首样本：双极值同时落位，不存在"初值 0"参与比较 *)
        (* First sample: both extremes take the value, no zero seed participates *)
        uCycleMin := uDeltaTimeMs;
        uCycleMax := uDeltaTimeMs;
    ELSE
        IF uDeltaTimeMs < uCycleMin THEN
            uCycleMin := uDeltaTimeMs;
        END_IF
        IF uDeltaTimeMs > uCycleMax THEN
            uCycleMax := uDeltaTimeMs;
        END_IF
    END_IF

    uSumMs       := uSumMs + uDeltaTimeMs;
    nSampleCount := nSampleCount + UDINT#1;

END_IF

(*------------------------------------------------------------------------------
 * 段 7｜平均值输出（边界 B5）：除零双保险——计数判零 + 除数显式转换
 *      Mean output: dual divide-by-zero protection before the conversion
 *-----------------------------------------------------------------------------*)
IF nSampleCount > UDINT#0 THEN
    fCycleMean := UDINT_TO_REAL(uSumMs) / UDINT_TO_REAL(nSampleCount);
ELSE
    fCycleMean := 0.0;
END_IF
END_FUNCTION_BLOCK
