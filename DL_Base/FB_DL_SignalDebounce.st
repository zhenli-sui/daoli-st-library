(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SignalDebounce
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 功能描述 (Function)   : 机械触点软件消抖。上升沿与下降沿确认延时独立可调，
 *                         输出消抖后稳定值 + 上升/下降单周期事件 + 消抖进行中标志。
 *                         上电首扫直接采样、不产生假边沿；延时超限自动钳位并告警；
 *                         零延时可直通；使能失效时输出直通原始值且事件清零。
 * 开源溯源 (Origin)     : 原创实现。算法思想源自 IEC 61131-3 标准定时器语义与
 *                         PLCopen Coding Guidelines 的"无条件周期刷新"约定，
 *                         未复制任何厂商私有库源码。
 * 本文件内含       : TYPE  E_DL_DebounceState（配套枚举，归属 DL_Base）
 *                    FB    FB_DL_SignalDebounce
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 钳位+复位+返回值确定
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM+CASE+ELSE
 *                         R7 ✓ 三实例主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DebounceState（归属 DL_Base，与 FB_DL_SignalDebounce 同文件）
 * 含义: 消抖状态机离散状态。数值步长留空位便于后续插态而不破坏已有工程。
 *----------------------------------------------------------------------------*)
TYPE E_DL_DebounceState :
(
    eInit     := 0,    // 上电首扫态：直接采样原始值，禁止产生任何事件 / Power-up first scan, sample directly without any event
    eStable   := 10,   // 稳定态：输出保持上一稳定值，监视输入变化 / Stable state, output holds last stable value and watches input
    eRiseWait := 20,   // 上升确认态：输入相对稳定值已变 TRUE，等待上升延时到期 / Rising confirmation, waiting for rising delay expiry
    eFallWait := 30,   // 下降确认态：输入相对稳定值已变 FALSE，等待下降延时到期 / Falling confirmation, waiting for falling delay expiry
    eFault    := 99    // 故障锁存态：非法状态或参数越界，输出回安全值，需 bReset 清除 / Latched fault, safe output, cleared by bReset
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SignalDebounce
 * 调用约定: 每个扫描周期无条件调用一次；bReset 上升沿重新初始化滤波器。
 * 无状态泄漏: 全部状态驻留于实例私有 VAR，零全局引用，可多实例并行。
 * 滞后披露: 输出相对输入的延迟 = 对应方向的确认延时（非固定扫描周期）。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SignalDebounce
VAR_INPUT
    bRawInput    : BOOL;              // 原始输入信号，未经消抖 / Raw input signal, not debounced
    tRiseDelay   : TIME := T#20MS;    // 上升沿确认延时 [ms]，T#0S 表示直通 / Rising confirmation delay [ms], T#0S = pass-through
    tFallDelay   : TIME := T#20MS;    // 下降沿确认延时 [ms]，T#0S 表示直通 / Falling confirmation delay [ms], T#0S = pass-through
    bEnable      : BOOL := TRUE;      // 使能标志，FALSE 时输出直通原始值 / Enable flag, FALSE bypasses output to raw input
    bReset       : BOOL;              // 复位信号，上升沿重新初始化滤波器 / Reset signal, rising edge re-initializes the filter
END_VAR
VAR_OUTPUT
    bStable      : BOOL;              // 消抖后的稳定输出 / Debounced stable output
    bRiseEvent   : BOOL;              // 稳定上升沿事件，单扫描周期脉冲 / Stable rising edge event, one-scan pulse
    bFallEvent   : BOOL;              // 稳定下降沿事件，单扫描周期脉冲 / Stable falling edge event, one-scan pulse
    bFiltering   : BOOL;              // 消抖进行中标志（输入与稳定值不一致且计时未满） / Debounce in progress flag
    bError       : BOOL;              // 故障标志，需 bReset 清除 / Fault flag, cleared by bReset
    uErrorId     : UDINT;             // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbTonRise    : TON;               // 上升确认定时器实例 / Rising confirmation timer instance
    fbTonFall    : TON;               // 下降确认定时器实例 / Falling confirmation timer instance
    fbTrigReset  : R_TRIG;            // 复位信号上升沿检测实例 / Reset rising edge detector instance
    eState       : E_DL_DebounceState; // 主状态机当前状态 / Current state of the main state machine
    bLastStable  : BOOL;              // 上一周期稳定值，仅用于边沿比较 / Previous stable value, used only for edge comparison
    tRiseClamped : TIME;              // 钳位后的上升确认延时 [ms] / Clamped rising confirmation delay [ms]
    tFallClamped : TIME;              // 钳位后的下降确认延时 [ms] / Clamped falling confirmation delay [ms]
    bNeedRise    : BOOL;              // 向上消抖请求：原始 TRUE 且稳定值 FALSE / Rise debounce request: raw TRUE while stable FALSE
    bNeedFall    : BOOL;              // 向下消抖请求：原始 FALSE 且稳定值 TRUE / Fall debounce request: raw FALSE while stable TRUE
    bRiseInstant : BOOL;              // 上升延时为零的直通快速通道标志 / Instant path flag for zero rising delay
    bFallInstant : BOOL;              // 下降延时为零的直通快速通道标志 / Instant path flag for zero falling delay
END_VAR
VAR CONSTANT
    DL_DEBOUNCE_MAX_DELAY : TIME := T#10S;  // 消抖延时上限钳位值 [s]，超限按上限执行 / Max debounce delay clamp [s], over-limit runs at clamp
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜参数钳位：延时超上限只告警不中断，保证现场不会因组态笔误停机
 *      Parameter clamping: over-limit delay only warns, never stops the machine
 *-----------------------------------------------------------------------------*)
IF tRiseDelay > DL_DEBOUNCE_MAX_DELAY THEN
    tRiseClamped := DL_DEBOUNCE_MAX_DELAY;
    bError       := TRUE;
    uErrorId     := 16#0001_0001;
ELSE
    tRiseClamped := tRiseDelay;
END_IF

IF tFallDelay > DL_DEBOUNCE_MAX_DELAY THEN
    tFallClamped := DL_DEBOUNCE_MAX_DELAY;
    bError       := TRUE;
    uErrorId     := 16#0001_0001;
ELSE
    tFallClamped := tFallDelay;
END_IF

(* 零延时判定：T#0S 必须直通，不得因 PT=0 而让输出永久不动作（边界 B4） *)
(* Zero-delay detection: T#0S must pass through, never block the output (boundary B4) *)
bRiseInstant := (tRiseClamped <= T#0S);
bFallInstant := (tFallClamped <= T#0S);

(*------------------------------------------------------------------------------
 * 段 2｜消抖需求判定：以"原始值 vs 上一周期稳定值"的偏差方向决定消抖方向
 *      Debounce request: direction derived from the deviation between raw and last stable
 *      该判定只依赖输入与上一稳定值，与状态机解耦，供下段定时器无条件使用
 *-----------------------------------------------------------------------------*)
bNeedRise := bRawInput AND NOT bStable;
bNeedFall := (NOT bRawInput) AND bStable;

(*------------------------------------------------------------------------------
 * 段 3｜无条件刷新区（红线 R7）：三个实例调用严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE
 *      IN 为 FALSE 时 TON 自动清零 ET，天然实现"抖动不累积计时"（边界 B8）
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTonRise(IN := bNeedRise AND bEnable AND NOT fbTrigReset.Q, PT := tRiseClamped);
fbTonFall(IN := bNeedFall AND bEnable AND NOT fbTrigReset.Q, PT := tFallClamped);

(*------------------------------------------------------------------------------
 * 段 4｜复位处理（边界 B7）：回到 eInit 重新采样，清故障与事件
 *      Reset handling: back to eInit for re-sampling, clear fault and events
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    eState      := eInit;
    bError      := FALSE;
    uErrorId    := 16#0000_0000;
    bStable     := FALSE;
    bLastStable := bRawInput;
    bRiseEvent  := FALSE;
    bFallEvent  := FALSE;
    bFiltering  := FALSE;
END_IF

IF NOT bEnable THEN
    (*--------------------------------------------------------------------------
     * 段 5a｜使能失效语义（边界 B6）：直通原始值、事件清零、状态回 eInit
     *      恢复使能时由 eInit 重新采样，绝不补发禁用期间的历史边沿
     *      Disabled: bypass raw value, clear events, force eInit; no historical edge replay
     *-------------------------------------------------------------------------*)
    bStable     := bRawInput;
    bLastStable := bRawInput;
    bRiseEvent  := FALSE;
    bFallEvent  := FALSE;
    bFiltering  := FALSE;
    eState      := eInit;
ELSE
    (*--------------------------------------------------------------------------
     * 段 5b｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
     *      Main state machine: ENUM + CASE with mandatory ELSE fallback
     *-------------------------------------------------------------------------*)
    CASE eState OF

        eInit:
            (* 首扫直接采样；bStable 与 bLastStable 同时赋值使边沿差为零（边界 B2） *)
            (* First scan samples directly; equal assignment keeps the edge difference zero *)
            bStable     := bRawInput;
            bLastStable := bRawInput;
            bRiseEvent  := FALSE;
            bFallEvent  := FALSE;
            eState      := eStable;

        eStable:
            (* 稳定监视：仅当输入偏离稳定值时才启动对应方向的确认流程 *)
            (* Stable watch: start the matching confirmation only on deviation *)
            IF bNeedRise THEN
                eState := eRiseWait;
            ELSIF bNeedFall THEN
                eState := eFallWait;
            END_IF

        eRiseWait:
            IF NOT bNeedRise THEN
                (* 输入回落：抖动被吸收，TON.IN 变 FALSE 自动清零 ET（边界 B8） *)
                (* Input bounced back: jitter absorbed, TON.IN FALSE resets ET automatically *)
                eState := eStable;
            ELSIF bRiseInstant OR fbTonRise.Q THEN
                (* 延时到期或零延时直通：确认稳定值为 TRUE *)
                (* Delay expired or zero-delay path: confirm stable value as TRUE *)
                bStable := TRUE;
                eState  := eStable;
            END_IF

        eFallWait:
            IF NOT bNeedFall THEN
                (* 输入回升：抖动被吸收，TON.IN 变 FALSE 自动清零 ET（边界 B8） *)
                (* Input recovered: jitter absorbed, TON.IN FALSE resets ET automatically *)
                eState := eStable;
            ELSIF bFallInstant OR fbTonFall.Q THEN
                (* 延时到期或零延时直通：确认稳定值为 FALSE *)
                (* Delay expired or zero-delay path: confirm stable value as FALSE *)
                bStable := FALSE;
                eState  := eStable;
            END_IF

        eFault:
            (* 故障锁存：输出回安全值 FALSE，等待 bReset 解除（边界 B9） *)
            (* Latched fault: force safe output FALSE until bReset releases it *)
            bStable := FALSE;

        ELSE
            (* 非法状态拦截：任何未定义状态一律进故障态，不做隐式恢复（边界 B9） *)
            (* Illegal state interception: any undefined state goes to fault, no implicit recovery *)
            eState   := eFault;
            bStable  := FALSE;
            bError   := TRUE;
            uErrorId := 16#0001_0005;

    END_CASE;

    (*--------------------------------------------------------------------------
     * 段 6｜边沿统一出口：只对"消抖后的稳定值"取沿（需求硬约束，边界 B5）
     *      Single edge outlet: edges are taken from the debounced stable value only
     *      放在状态机之后，任何分支改写 bStable 都只会产生一个脉冲，杜绝重发
     *-------------------------------------------------------------------------*)
    bRiseEvent := bStable AND NOT bLastStable AND NOT fbTrigReset.Q;
    bFallEvent := (NOT bStable) AND bLastStable AND NOT fbTrigReset.Q;

    (* 上一稳定值更新必须在事件计算之后，否则边沿永远为 FALSE *)
    (* Previous stable update must follow the edge evaluation, otherwise edges vanish *)
    bLastStable := bStable;

    (* 消抖进行中：处于任一确认态时为 TRUE，供 HMI 显示"滤波忙" *)
    (* Filtering busy: TRUE while in either confirmation state, for HMI display *)
    bFiltering := (eState = eRiseWait) OR (eState = eFallWait);
END_IF
END_FUNCTION_BLOCK
