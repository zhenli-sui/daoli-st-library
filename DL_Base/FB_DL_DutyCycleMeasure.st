(*
  ==================================================================
  组件名 Component  : FB_DL_DutyCycleMeasure
  分类   Category   : DL_Base
  版本   Version    : 1.0.0
  功能   Purpose    : 占空比/周期双沿测量：上升沿→上升沿累计测周期，高电平
                      期间累计测高宽度，周期闭合拍一次性算占空比并钳位 0~100。
                      首周期未闭合不出数（bValid=FALSE）；闭合周期累计值 ≤ 0
                      视为无效测量，bValid=FALSE 且保持上次输出值（不静默清零）。
                      周期闭合判据用「累计值 > 0」整数级事实，禁浮点判等。
  来源   Source     : t2-1-lgf-measurement（测量族：双沿计时口径为公开教科书
                      算法，实现零源码复制）
  互引   Cross-ref  : FB_DL_FrequencyGenerator（对偶件：本件测周期，彼件产生
                      频率信号，可组成环路自检）；FC_DL_PeriodJitterCalc（下游
                      可把本件 fPeriodMs 序列喂给它算抖动）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG/F_TRIG/LREAL 四则），三平台通用
  依赖   Depends    : 仅 Standard.library（R_TRIG/F_TRIG 属标准件）
  设计偏差 Deviation: 时间基准按本库「时间注入」纪律（R 平台时刻函数拒绝方案，
                      参见 FB_DL_CycleTimeMeasure 头注）：新增输入 fCallCycleMs
                      由调用方按扫描增量注入，本件不读任何平台时刻函数。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 除法前分母 > 0 显式闸 + 输出 0~100 钳位 + 输入有限闸
                      R5 全变量双语同行注释/R6 纯时序累计无状态机（CASE 不适用）
                      R7 R_TRIG/F_TRIG 段 0 无条件刷新/R8 钳位与容差常量化
  契约   Contract   : bEnable=FALSE 语义（FB33-4 写死）：冻结全部输出保持上次
                      值、bValid=FALSE，累计器清零（失能相串清账，R 失能清账
                      条款）；重新使能从下一上升沿重新起测（首周期语义重置）。
                      fCallCycleMs ≤ 0 或非有限：本拍拒绝累计、bValid=FALSE
                      （推进判据与计时不同源防线：计时基准本身必须有效）。
  错误码 Codes      : 16#0001_0011【信息级】fCallCycleMs 非法（≤0 或非有限），
                      本拍拒绝计时
  验收   Acceptance : V1 50% 占空恒定方波 → fDutyPct≈50 ｜ V2 使能前首周期 →
                      bValid=FALSE ｜ V3 周期累计≤0 → bValid=FALSE 且保持上次
                      ｜ V4 失能 → 冻结 + 累计清零 ｜ V5 计时基准非法 → 拒绝
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 1 序 2）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_DutyCycleMeasure
VAR_INPUT
    bSignal     : BOOL;               // 被测方波信号电平 [-] / the measured square wave level
    bEnable     : BOOL := FALSE;      // 使能，FALSE 冻结输出并清累计（头注契约）[-] / the enable, false freezes outputs and clears accumulators
    fCallCycleMs: LREAL := 0.0;       // 调用方注入的扫描周期增量 [ms] / caller injected scan delta [ms]
END_VAR
VAR_OUTPUT
    fPeriodMs   : LREAL := 0.0;       // 最近一次闭合周期 [ms]（无效拍保持上次值）/ the last closed period [ms], held when invalid
    fDutyPct    : LREAL := 0.0;       // 最近一次闭合占空比，钳位 0~100 [%]（无效拍保持）/ the last closed duty, clamped 0 to 100 [%], held when invalid
    bValid      : BOOL := FALSE;      // 本拍输出有效标志（首周期未闭合=FALSE）[-] / the output validity, false until the first period closes
    uErrorId    : UDINT := 16#0000_0000; // 错误码，0=正常，16#0001_0011=计时基准非法 [码] / the error code [code]
END_VAR
VAR
    rtSig       : R_TRIG;             // 信号上升沿实例，段 0 无条件刷新 / the rising edge instance refreshed unconditionally
    ftSig       : F_TRIG;             // 信号下降沿实例，段 0 无条件刷新 / the falling edge instance refreshed unconditionally
    _bHasEdge   : BOOL := FALSE;      // 首个上升沿是否已捕获（FALSE=首周期未闭合）[-] / the first rising edge captured flag
    _fCycAccMs  : LREAL := 0.0;       // 当前周期累计时长 [ms] / the current period accumulator [ms]
    _fHiAccMs   : LREAL := 0.0;       // 当前周期高电平累计时长 [ms] / the current high level accumulator [ms]
    _bTimeOk    : BOOL := FALSE;      // 本拍计时基准有效性 [-] / the per scan time base validity
END_VAR
VAR CONSTANT
    DCM_DUTY_MIN : LREAL := 0.0;      // 占空比输出下限 [%] / duty output lower clamp [%]
    DCM_DUTY_MAX : LREAL := 100.0;    // 占空比输出上限 [%] / duty output upper clamp [%]
    DCM_ERR_TIME : UDINT := 16#0001_0011; // 计时基准非法（信息级）/ invalid time base, info level
    DCM_ERR_NONE : UDINT := 16#0000_0000; // 无错误 [码] / no error [code]
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜沿检测无条件刷新区（红线 R7）：严禁移入 IF / CASE
 *      Edge instances refresh unconditionally, never inside a condition
 *-----------------------------------------------------------------------------*)
rtSig(CLK := bSignal);  // 上升沿 / the rising edge
ftSig(CLK := bSignal);  // 下降沿 / the falling edge

(*------------------------------------------------------------------------------
 * 段 1｜错误码本拍预置（当前周期事实，非锁存）
 *      The error code is a per scan fact, preset each cycle
 *-----------------------------------------------------------------------------*)
uErrorId := DCM_ERR_NONE;  // 预置无错误 / preset no error

(*------------------------------------------------------------------------------
 * 段 2｜失能相串清账：冻结输出 + bValid 撤销 + 累计器清零（R 失能清账）
 *      Disable phase clears the books: freeze outputs, revoke validity, wipe accumulators
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    bValid     := FALSE;     // 失能不出数 / no output while disabled
    _bHasEdge  := FALSE;     // 首周期语义复位，重新使能从下一上升沿起测 / re-arm from the next rising edge after re-enable
    _fCycAccMs := 0.0;       // 周期累计清零 / clear the period accumulator
    _fHiAccMs  := 0.0;       // 高电平累计清零 / clear the high level accumulator
    RETURN;                  // 冻结保持 fPeriodMs / fDutyPct 上次值 / outputs hold their last values
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜计时基准闸（推进判据与超时计时不得同源的计时侧防线）：
 *      ≤ 0 或非有限即拒绝本拍计时，bValid 撤销，输出保持上次值
 *      Reject the whole scan when the time base is illegal or non finite
 *-----------------------------------------------------------------------------*)
_bTimeOk := (fCallCycleMs > 0.0) AND (fCallCycleMs = fCallCycleMs);  // 自反判 NaN，> 0 排除零与负 / reflexive NaN test and positive gate
IF NOT _bTimeOk THEN
    bValid   := FALSE;          // 撤销有效性，输出保持 / revoke validity, outputs hold
    uErrorId := DCM_ERR_TIME;   // 信息级码（不置故障锁存）/ info level code, no fault latch
    _fCycAccMs := 0.0;          // 丢弃脏累计，避免混入错误时间基准的样本 / drop the dirty accumulation
    _fHiAccMs  := 0.0;          // 同上 / the same
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜正常计时累计：周期全程累计 + 高电平条件累计
 *      Normal accumulation: period accumulates all scan, high only when level
 *-----------------------------------------------------------------------------*)
_fCycAccMs := _fCycAccMs + fCallCycleMs;  // 周期累计 [ms] / accumulate the period [ms]
IF bSignal THEN
    _fHiAccMs := _fHiAccMs + fCallCycleMs;  // 高电平宽度累计 [ms] / accumulate the high width [ms]
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜上升沿闭合周期：非首沿才出数；闭合判据为累计值 > 0，禁浮点判等
 *      A rising edge closes the period, only when it is not the first edge
 *-----------------------------------------------------------------------------*)
IF rtSig.Q THEN
    IF _bHasEdge THEN
        IF _fCycAccMs > 0.0 THEN        // 闭合判据：整数级事实「累计为正」/ close test is the positive accumulator fact
            fPeriodMs := _fCycAccMs;    // 发布闭合周期 [ms] / publish the closed period [ms]
            fDutyPct  := (_fHiAccMs / _fCycAccMs) * DCM_DUTY_MAX;  // 分母已闸 > 0 / the denominator is gated above zero
            IF fDutyPct < DCM_DUTY_MIN THEN
                fDutyPct := DCM_DUTY_MIN;   // 显式下限钳位 / explicit lower clamp
            END_IF
            IF fDutyPct > DCM_DUTY_MAX THEN
                fDutyPct := DCM_DUTY_MAX;   // 显式上限钳位 / explicit upper clamp
            END_IF
            bValid := TRUE;             // 周期闭合，输出生效 / the period closed, the outputs are live
        ELSE
            bValid := FALSE;            // 分母周期 ≤ 0：不出数且保持上次输出（头注契约）/ keep last outputs when the period is not positive
        END_IF
    END_IF
    _bHasEdge  := TRUE;   // 首沿已捕获 / the first edge is captured
    _fCycAccMs := 0.0;    // 新周期累计从零起 / the new period accumulates from zero
    _fHiAccMs  := 0.0;    // 高电平累计同步清零 / the high accumulator resets with it
END_IF
END_FUNCTION_BLOCK
