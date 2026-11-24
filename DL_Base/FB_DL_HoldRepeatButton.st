(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HoldRepeatButton
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : HMI 按钮长按连发原语：按下沿先出一次有效脉冲（bRepeatPulse 单拍
 *                         一次，计入 nRepeats）；持续按住超过 tDelayInitial 首连发延迟后，
 *                         按 tRepeat 重复周期连发脉冲；松开立即停发且计数冻结（不清零，
 *                         清零由 bReset 引脚显式做）。bHolding 指示长按中状态。
 * 接口     (Interface)  : 输入 bPress 按钮、tDelayInitial 首连发延迟、tRepeat 重复周期、
 *                         bReset 复位（清计数与组态故障）；输出 bRepeatPulse 重复脉冲单拍、
 *                         bHolding 长按中、nRepeats 累计连发次数、bError 组态故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出连发脉冲节律，不解释步距/速度含义、
 *                         不直接改任何设定值**；脉冲消费与步距语义由上层画面层负责。
 *                         ② 组态闸：tRepeat <= T#0S → 锁存 bError（零周期连发会打爆下游）；
 *                         解除路径 = bReset 上升沿（头注释声明：bReset 上升沿同时清计数与
 *                         组态故障锁存，为本件唯一故障清除边）。
 *                         ③ tonRepeat 采用自复位周期窗接法 IN := bHolding ∧ ¬tonRepeat.Q
 *                         （R188 定时器自复位，禁外部沿清零）；tonDelay/tonRepeat 在段 0
 *                         无条件周期刷新。
 *                         ④ nRepeats 饱和不回绕：到达 UDINT 上限后停止累加（不取模回绕）。
 *                         ⑤ 脉冲出口两段式：内部 _bPulse 当拍合成 → 段 4 统一出口映射单拍
 *                         （R34 同拍抹除防护）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_MultiClickDetect` 分工：长按连发（本件，节奏生成）≠
 *                         连击识别（那件，次数统计判双击三击）；二者可并联不可互替。
 * 来源标签 (Source Tag) : 自研线（HMI 连发语义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 脉冲组 + UDINT 计数；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 周期下限组态闸 + 计数饱和 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机，两定时器节律） ｜ R7 ✓ 两 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 1 · 序号 5）
 *                         验收向量：按下沿单脉冲计数+1；按住 tDelayInitial 后每 tRepeat
 *                         一脉冲；松开停发计数冻结；tRepeat=0 → bError 锁存。
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_HoldRepeatButton
VAR_INPUT
    bPress        : BOOL := FALSE;   // 按钮输入（按下沿触发首发脉冲） [-] / Button input
    tDelayInitial : TIME := T#500MS; // 首连发延迟（按下到开始连发的等待） [ms] / Initial repeat delay [ms]
    tRepeat       : TIME := T#100MS; // 连发重复周期，域 > T#0S [ms] / Repeat period, > T#0S [ms]
    bReset        : BOOL := FALSE;   // 复位，上升沿清 nRepeats 与组态故障锁存 [-] / Reset, rising edge clears count and config latch
END_VAR
VAR_OUTPUT
    bRepeatPulse : BOOL;             // 连发脉冲（按下沿首发 + 周期连发），单拍 [-] / Repeat pulse, single-scan
    bHolding     : BOOL;             // 长按进行中指示 [-] / Button held indicator
    nRepeats     : UDINT;            // 累计连发次数（松开冻结，bReset 清零） [次] / Cumulative repeat count, frozen on release
    bError       : BOOL;             // 组态故障标志（tRepeat 非正，锁存） [-] / Configuration fault flag, latched
END_VAR
VAR
    _bPulse   : BOOL;                // 当拍脉冲内部量（统一出口映射源，R34 两段式） / Internal pulse this scan
    _bHolding : BOOL;                // 长按内部量（与出口同源，R191） / Internal holding
    _nCount   : UDINT := 0;          // 计数锁存量（松开不清零） / Latched count, kept on release
    _bErrLatch: BOOL;                // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault, cleared by reset edge
    tonDelay  : TON;                 // 首连发延迟定时器，段 0 无条件调用 / Initial delay timer
    tonRepeat : TON;                 // 连发周期定时器（自复位接法），段 0 无条件调用 / Repeat period timer, self-reset wiring
    rtPress   : R_TRIG;              // 按下沿实例，段 0 无条件调用 / Press edge instance
    rtReset   : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_HRB_UDMAX : UDINT := 4294967295;   // UDINT 可表上限（计数饱和点） [次] / UDINT ceiling, count saturation point
END_VAR

(* —— 段 0：组态闸 + 两 TON 两沿无条件周期刷新 —— *)
IF tRepeat <= T#0S THEN
    _bErrLatch := TRUE;                                     // 零周期连发会打爆下游：锁存（R188 解除沿=bReset 上升沿） / Zero-period repeat: latch fault
END_IF
tonDelay(IN := bPress AND (NOT _bErrLatch), PT := tDelayInitial);   // 首连发延迟计时 / Initial delay timing
tonRepeat(IN := tonDelay.Q AND (NOT tonRepeat.Q) AND (NOT _bErrLatch), PT := tRepeat);   // 自复位周期窗（R188） / Self-reset period window
rtPress(CLK := bPress);                                         // 按下沿，每拍必调 / Press edge, every scan
rtReset(CLK := bReset);                                         // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：单拍量预清零（_nCount/_bErrLatch 锁存量不入清单，R107） —— *)
bRepeatPulse := FALSE;                                          // 脉冲出口预清 / Pulse outlet preset
bHolding     := FALSE;                                          // 长按出口预清 / Holding outlet preset
_bPulse      := FALSE;                                          // 内部脉冲预清 / Internal pulse preset
_bHolding    := FALSE;                                          // 内部长按预清 / Internal holding preset

(* —— 段 2：复位沿（唯一清除边：清计数 + 清组态故障锁存） —— *)
IF rtReset.Q THEN
    _nCount    := 0;                                            // 计数显式清零（不清零只由本沿做） / Explicit count clear
    _bErrLatch := FALSE;                                        // 清组态故障锁存 / Clear config fault latch
END_IF

(* —— 段 3：脉冲合成与计数（按下沿首发 + 周期连发两源合一） —— *)
IF NOT _bErrLatch THEN
    IF rtPress.Q THEN
        _bPulse := TRUE;                                        // 按下沿首发脉冲（规格定：按下沿先出一次有效） / First pulse on press edge
    END_IF
    IF tonRepeat.Q THEN
        _bPulse := TRUE;                                        // 延迟后按周期连发脉冲 / Periodic repeat pulse after delay
    END_IF
END_IF
IF _bPulse AND (_nCount < DL_HRB_UDMAX) THEN
    _nCount := _nCount + 1;                                     // 计数累加，UDINT 上限饱和不回绕 / Count increment, saturating at ceiling
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191；故障相语义=停发脉冲、长按指示复位） —— *)
bRepeatPulse := _bPulse AND (NOT _bErrLatch);                   // 脉冲出口（故障期停发） / Pulse outlet, suppressed on fault
bHolding     := bPress AND (NOT _bErrLatch);                    // 长按指示（故障期复位） / Holding indicator, reset on fault
nRepeats     := _nCount;                                        // 计数出口 / Count outlet
bError       := _bErrLatch;                                     // 故障标志出口 / Error flag outlet

END_FUNCTION_BLOCK
