(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RuntimeMeter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零平台时刻函数
 * 功能描述 (Function)   : 设备累计运行时间（分钟 / 小时双口径）与启动次数统计，
 *                         带保养间隔到期预警。时间增量由调用方注入，本块零平台依赖。
 *                         采用"秒 + 毫秒进位缓存"的整数化累加，不做逐周期浮点累加，
 *                         从根上消除浮点漂移（与滑动平均的整数化思想同源）。
 *                         保养到期锁存至确认沿；启动计数达上限饱和停增不回绕。
 * 开源溯源 (Origin)     : 原创实现。运行小时表 + 保养计数的功能组合为工业界通行做法，
 *                         整数化累加与注入式时间设计为本库既有范式，未复制任何源码。
 * 本文件内含       : FB    FB_DL_RuntimeMeter（单 POU，无配套类型）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3，零平台时刻函数 ｜ R4 ✓ 增量拒收 + 乘法溢出钳位 + 结构性除零论证
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯累计统计，无状态转移）
 *                         R7 ✓ 三 R_TRIG 主体最前部无条件刷新 ｜ R8 ✓ 换算系数全部常量化
 *
 * 【断电保持提示 / Retain hint（边界 B9）】
 *   本块全部累计量若不声明为断电保持类型，重新上电即归零，保养预警与启动次数随之丢失。
 *   推荐调用方把本 FB 的实例声明为断电保持变量。
 *   All accumulators are lost on power cycle unless the caller declares the instance retentive.
 *
 * 【除零结构性豁免 / Structural divide-by-zero exemption（边界 B7）】
 *   fRunHours 的除数为常量 3600 秒/小时，编译期恒大于零，不存在运行期为零的可能，
 *   故不设前置判断；uMaintRemainMin 的除数为常量 60 秒/分钟，同理。
 *   The divisors are compile-time positive constants, so no runtime guard is required.
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 A）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RuntimeMeter
VAR_INPUT
    bRunning          : BOOL;                  // 设备运行反馈（电平，TRUE 期间累计时间）/ Equipment running feedback, level
    uDeltaTimeMs      : UDINT;                 // 本任务周期耗时 [ms]，调用方注入 / Cycle time in ms, caller-provided
    uMaintIntervalMin : UDINT := UDINT#0;      // 保养间隔 [min]，0 = 关闭保养预警 / Maintenance interval [min], 0 = disabled
    bMaintAck         : BOOL;                  // 上升沿：保养确认，重置保养计时 / Rising edge: acknowledge maintenance
    bReset            : BOOL;                  // 上升沿：清零全部累计 / Rising edge: clear all totals
END_VAR
VAR_OUTPUT
    uRunTotalMin     : UDINT;   // 累计运行时间 [min] / Total runtime in minutes
    fRunHours        : REAL;    // 累计运行小时 [h]（HMI 直显口径）/ Total runtime in hours for HMI
    nStartCount      : UDINT;   // 累计启动次数 [次] / Accumulated start count [count]
    bMaintDue        : BOOL;    // 保养到期（锁存至确认）/ Maintenance due, latched until acknowledged
    uMaintRemainMin  : UDINT;   // 距下次保养剩余 [min]，未启用时为 0 / Minutes to next maintenance, 0 when disabled
    uErrorId         : UDINT;   // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uTotalSec        : UDINT;   // 累计运行秒 [s] / Total runtime seconds [s]
    uSinceMaintSec   : UDINT;   // 距上次保养累计秒 [s] / Seconds since last maintenance [s]
    uMsCarry         : UDINT;   // 毫秒进位缓存 [ms] / Millisecond carry buffer [ms]
    fbTrigRun        : R_TRIG;  // 启动上升沿检测实例 / Start rising edge detector instance
    fbTrigMaintAck   : R_TRIG;  // 保养确认上升沿检测实例 / Maintenance ack rising edge detector instance
    fbTrigReset      : R_TRIG;  // 复位上升沿检测实例 / Reset rising edge detector instance
    uMaintIntEff     : UDINT;   // 钳位后的保养间隔 [min] / Clamped maintenance interval [min]
    uMaintThreshSec  : UDINT;   // 保养到期门槛秒数 [s] / Maintenance due threshold in seconds
    uCarrySec        : UDINT;   // 本周期可折算的整秒数 [s] / Whole seconds derivable this cycle
END_VAR
VAR CONSTANT
    DL_RT_SEC_PER_MIN   : UDINT := 60;             // 每分钟秒数 [s/min] / Seconds per minute
    DL_RT_SEC_PER_HOUR  : UDINT := 3600;           // 每小时秒数 [s/h] / Seconds per hour
    DL_RT_MS_PER_SEC    : UDINT := 1000;           // 每秒毫秒数 [ms/s] / Milliseconds per second
    DL_RT_COUNT_MAX     : UDINT := 16#FFFF_FFFE;   // 启动计数饱和上限 [次] / Start count saturation limit
    DL_RT_DELTA_MAX     : UDINT := 3600000;        // 单周期合理上限 [ms] / Sanity cap per cycle [ms]
    DL_RT_MAINT_INT_MAX : UDINT := 525600;         // 保养间隔上限 [min]，一年，防乘法溢出 / Interval cap [min], one year
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：三个边沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: all three edge instances run at the very top
 *-----------------------------------------------------------------------------*)
fbTrigRun(CLK := bRunning);
fbTrigMaintAck(CLK := bMaintAck);
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜故障码本周期清零：错误码只描述当前周期事实
 *      Error code is cleared every scan: it reports the current cycle only
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 3｜复位语义（边界 B8）：全部累计归零，故障码同时清除，口径统一
 *      Reset: every total goes to zero together with the error code
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    uTotalSec       := UDINT#0;
    uSinceMaintSec  := UDINT#0;
    uMsCarry        := UDINT#0;
    uRunTotalMin    := UDINT#0;
    fRunHours       := 0.0;
    nStartCount     := UDINT#0;
    bMaintDue       := FALSE;
    uMaintRemainMin := UDINT#0;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜保养间隔钳位（边界 B6）：上限一年，防止分钟折算秒时乘法溢出
 *      Interval clamping: one year cap prevents overflow in the minute-to-second product
 *-----------------------------------------------------------------------------*)
IF uMaintIntervalMin > DL_RT_MAINT_INT_MAX THEN
    uMaintIntEff := DL_RT_MAINT_INT_MAX;
    uErrorId     := 16#0001_0001;
ELSE
    uMaintIntEff := uMaintIntervalMin;
END_IF

uMaintThreshSec := uMaintIntEff * DL_RT_SEC_PER_MIN;

(*------------------------------------------------------------------------------
 * 段 5｜增量防御（边界 B3）：零增量与超上限增量均不计入，口径与周期测量块一致
 *      Delta defence: zero and over-limit deltas are ignored, same policy as the cycle block
 *-----------------------------------------------------------------------------*)
IF (uDeltaTimeMs > UDINT#0) AND (uDeltaTimeMs <= DL_RT_DELTA_MAX) THEN

    IF bRunning THEN
        (*----------------------------------------------------------------------
         * 段 6｜毫秒进位累加（边界 B2）：先把毫秒攒够整秒，再折算进秒计数
         *      Millisecond carry: accumulate to whole seconds before folding into the counters
         *      避免每周期浮点累加，长期运行不产生漂移；进位缓存保留不足一秒的余量
         *      No per-cycle float accumulation, so no long-term drift is possible
         *---------------------------------------------------------------------*)
        uMsCarry := uMsCarry + uDeltaTimeMs;

        IF uMsCarry >= DL_RT_MS_PER_SEC THEN
            (* 除数 1000 为编译期正的常量，结构性免除零判断（见头注释） *)
            (* The divisor 1000 is a compile-time positive constant, structurally safe *)
            uCarrySec  := uMsCarry / DL_RT_MS_PER_SEC;
            uMsCarry   := uMsCarry - (uCarrySec * DL_RT_MS_PER_SEC);
            uTotalSec  := uTotalSec + uCarrySec;
            uSinceMaintSec := uSinceMaintSec + uCarrySec;
        END_IF
    END_IF

ELSE
    uErrorId := 16#0001_0008;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜启动计数（边界 B4）：上升沿计数，达上限饱和停增，绝不回绕
 *      Start count: rising edge increments, saturation instead of wrap-around
 *-----------------------------------------------------------------------------*)
IF fbTrigRun.Q THEN
    IF nStartCount < DL_RT_COUNT_MAX THEN
        nStartCount := nStartCount + UDINT#1;
    ELSE
        uErrorId := 16#0001_0007;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜保养预警（边界 B5）：到期锁存，确认沿清零计时并解除锁存
 *      Maintenance warning: latched on due, cleared by the acknowledge edge
 *-----------------------------------------------------------------------------*)
IF uMaintIntEff = UDINT#0 THEN
    (* 功能关闭：不预警、不显示剩余，历史保养计时保留不影响累计口径 *)
    (* Function disabled: no warning, no remaining display, history is kept *)
    bMaintDue       := FALSE;
    uMaintRemainMin := UDINT#0;
ELSE
    IF uSinceMaintSec >= uMaintThreshSec THEN
        bMaintDue := TRUE;
    END_IF

    IF fbTrigMaintAck.Q THEN
        bMaintDue      := FALSE;
        uSinceMaintSec := UDINT#0;
    END_IF

    IF uSinceMaintSec >= uMaintThreshSec THEN
        uMaintRemainMin := UDINT#0;
    ELSE
        (* 除数 60 为编译期正的常量，结构性免除零判断（见头注释） *)
        (* The divisor 60 is a compile-time positive constant, structurally safe *)
        uMaintRemainMin := (uMaintThreshSec - uSinceMaintSec) / DL_RT_SEC_PER_MIN;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜输出刷新：分钟取整下取整口径，小时保留小数供 HMI 直显
 *      Output refresh: minutes are truncated, hours keep the fractional part for HMI
 *      除数 3600 为编译期正的常量，结构性免除零判断（边界 B7）
 *      The divisor 3600 is a compile-time positive constant, structurally safe
 *-----------------------------------------------------------------------------*)
uRunTotalMin := uTotalSec / DL_RT_SEC_PER_MIN;
fRunHours    := UDINT_TO_REAL(uTotalSec) / UDINT_TO_REAL(DL_RT_SEC_PER_HOUR);
END_FUNCTION_BLOCK
