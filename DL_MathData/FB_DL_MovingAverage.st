(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MovingAverage
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），全 REAL 运算
 * 功能描述 (Function)   : O(1) 递推滑动平均滤波。窗口长度运行时可改，采样节拍由
 *                         调用方控制。两阶段启动：窗口未满阶段只"写入+累加+计数"、
 *                         绝不执行"减最旧值"；窗口已满阶段执行"减最旧+加最新+指针递增"。
 *                         每 DL_MAV_CORRECT_CYCLE 次采样做一次全窗口重算，消除浮点
 *                         累加漂移。窗口长度变更时整体重建缓冲区，避免新旧样本混算产生台阶。
 *
 * 【滞后披露 / Phase lag disclosure（边界 B11）】
 *   相位滞后约 (N-1)/2 个采样周期，滤波时间窗 = N × 采样周期。
 *   安全联锁回路（急停、超压保护、超温切断）严禁使用大窗口滤波值，
 *   必须直接使用原始信号或小窗口（N ≤ 3）值。
 *
 * 【断电保持提示 / Retain hint（边界 B12）】
 *   缓冲区、写指针、累加和、已填充数若不设 RETAIN，重新上电会重走"窗口未满"阶段，
 *   表现为输出从 0 缓慢爬升。需要无扰重启的场合，应将本实例声明为 VAR RETAIN。
 *
 * 【采样语义 / Sampling semantics（边界 B7，重要）】
 *   采样判据统一为"bSample 电平为 TRUE 即采样"：bSample := TRUE 常 TRUE 时每周期采样，
 *   接一个上升沿脉冲变量则按事件采样。绝不用 R_TRIG 承担两种语义——常 TRUE 信号经
 *   R_TRIG 只在首周期产生一次脉冲，会导致"只采到一个样本"的低级事故。
 *   因此本组件不设 fbTrigSample 采样沿实例（仅保留 fbTrigReset），
 *   这是对 ROUND_PLAN §2.13 VAR 清单的刻意收窄，依据 B7 与决策记录 P6。
 *
 * 【状态机 / State machine（边界 B1/B10）】
 *   采用 eInit / eFilling / eRunning / eFault 四态 + ELSE 兜底。
 *   两阶段判据由 bBufferFull 承担并在采样段用 IF bBufferFull THEN … ELSE … END_IF（代码骨架，示例省略）
 *   显式分支，采样算术只写一处，状态机只负责阶段迁移，避免同一段代码在两个 CASE
 *   分支中重复而导致"只改一处"的缺陷。
 * 开源溯源 (Origin)     : 原创实现。环形缓冲 + 递推求和的滑动平均为公开经典算法。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 除零双保险/窗口钳位/MOD 回绕/重算防死锁
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 四态 ENUM+CASE+ELSE 兜底
 *                         R7 ✓ R_TRIG 主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MovingAverageState（归属 DL_MathData，与 FB_DL_MovingAverage 同文件）
 * 含义: 滑动平均工作阶段。eFilling 与 eRunning 的区分仅用于状态迁移与诊断，
 *       采样算术由 bBufferFull 在单一分支内完成。
 *----------------------------------------------------------------------------*)
TYPE E_DL_MovingAverageState :
(
    eInit    := 0,    // 初始化态：清缓冲、清累加和、清故障，单周期驻留 / Initialization: clear buffer, sum and fault, single scan
    eFilling := 10,   // 填充态：窗口未满，只追加样本不做淘汰 / Filling: window not full, append only without eviction
    eRunning := 20,   // 运行态：窗口已满，执行 O(1) 递推替换 / Running: window full, O(1) recursive replacement
    eFault   := 99    // 故障态：非法状态命中，输出保持最后有效值 / Fault: illegal state hit, outputs hold the last valid value
);
END_TYPE

FUNCTION_BLOCK FB_DL_MovingAverage
VAR_INPUT
    fInput      : REAL := 0.0;      // 原始采样值 [EU] / Raw sampled value [EU]
    nWindowSize : INT := 8;         // 窗口长度，合法域 1..100 / Window length, valid range 1..100
    bSample     : BOOL := TRUE;     // 采样触发，电平 TRUE 即采样；接脉冲变量则按事件采样 / Sample trigger, TRUE level samples every scan
    bEnable     : BOOL := TRUE;     // 使能标志，FALSE 时停止采样并保持输出 / Enable flag, FALSE stops sampling and holds the output
    bReset      : BOOL;             // 复位信号，上升沿清空窗口与累加和 / Reset, rising edge clears the buffer and the sum
END_VAR
VAR_OUTPUT
    fAverage     : REAL;            // 窗口算术平均 [EU] / Window arithmetic mean [EU]
    bBufferFull  : BOOL;            // 窗口已填满标志，同时作为两阶段判据 / Buffer full flag, also the two-phase discriminator
    nSampleCount : INT;             // 窗口内有效样本数，值域 0..nWindowSize / Valid sample count in the window, range 0..nWindowSize
    fWindowSum   : REAL;            // 窗口累加和，诊断用 [EU] / Window sum for diagnostics [EU]
    bError       : BOOL;            // 故障标志，需 bReset 清除 / Fault flag, cleared by bReset
    uErrorId     : UDINT;           // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    afBuffer     : ARRAY[0..99] OF REAL;  // 环形缓冲区，容量等于窗口上限 [EU] / Ring buffer sized to the max window [EU]
    nWriteIndex  : INT;             // 环形写指针，值域 0..99 / Ring write index, range 0..99
    nFilled      : INT;             // 已填充样本数，值域 0..100 / Number of filled samples, range 0..100
    fSum         : REAL;            // 滑动累加和 [EU]，与 nFilled 同步维护 / Running sum [EU], maintained with nFilled
    nLastWindow  : INT;             // 上周期窗口长度，用于变更检测 / Previous window length for change detection
    fbTrigReset  : R_TRIG;          // 复位上升沿检测实例 / Reset rising edge detector instance
    nCorrectCnt  : DINT;            // 距下次全窗口重算的采样计数 / Sample counter until the next full-window recalculation
    nGuard       : DINT;            // 重算循环防死锁计数器 / Recalculation loop deadlock guard
    fRecalcSum   : REAL;            // 重算中间累加和 [EU] / Recalculation intermediate sum [EU]
    nIdx         : INT;             // 重算循环索引，值域 0..99 / Recalculation loop index, range 0..99
    nWindowEff   : INT;             // 钳位后的有效窗口长度 / Clamped effective window length
    eState       : E_DL_MovingAverageState; // 主状态机当前状态 / Current state of the main state machine
    bDoSample    : BOOL;            // 本周期采样使能（bSample AND bEnable） / Sampling enabled this scan
    bJustReset   : BOOL;            // 本周期刚发生复位/初始化，需跳过采样 / Reset or init happened this scan, sampling is skipped
END_VAR
VAR CONSTANT
    DL_MAV_MAX_WINDOW    : INT := 100;        // 窗口上限，必须与数组维度一致 / Max window, must match the array dimension
    DL_MAV_MIN_WINDOW    : INT := 1;          // 窗口下限 / Min window
    DL_MAV_CORRECT_CYCLE : DINT := 10000;     // 每 N 次采样做一次全窗口重算校正 / Recalculate every N samples
    DL_MAV_MAX_LOOP      : DINT := 100;       // 重算循环迭代上限 / Recalculation loop iteration limit
    DL_FLOAT_EPS         : REAL := 1.0E-6;    // 浮点判零容差 / Float zero tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：复位沿实例在主体最前部调用，严禁进入 IF/CASE
 *      Unconditional refresh zone: the reset edge instance runs at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜窗口长度钳位（边界 B3）：先钳位，后用于所有后续计算
 *      Window length clamping: clamp first, then use everywhere
 *------------------------------------------------------------------------------*)
IF nWindowSize < DL_MAV_MIN_WINDOW THEN
    nWindowEff := DL_MAV_MIN_WINDOW;
    uErrorId   := 16#0001_0001;
    bError     := TRUE;
ELSIF nWindowSize > DL_MAV_MAX_WINDOW THEN
    nWindowEff := DL_MAV_MAX_WINDOW;
    uErrorId   := 16#0001_0001;
    bError     := TRUE;
ELSE
    nWindowEff := nWindowSize;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜窗口长度变更重建（边界 B4）：清空缓冲、指针、累加和，重走未满阶段
 *      Window change rebuild: clear buffer, pointer and sum, restart the filling phase
 *      不清空会让新旧窗口样本混算，输出出现台阶，现场会误判为传感器跳变
 *-----------------------------------------------------------------------------*)
bJustReset := FALSE;

IF nWindowEff <> nLastWindow THEN
    nLastWindow  := nWindowEff;
    nWriteIndex  := 0;
    nFilled      := 0;
    fSum         := 0.0;
    nCorrectCnt  := 0;
    bBufferFull  := FALSE;
    eState       := eInit;
    bJustReset   := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜复位处理（边界 B9）：复位优先于采样，本周期不再采样
 *      Reset handling: reset wins over sampling, no sample is taken this scan
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    eState      := eInit;
    bJustReset  := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6 / 边界 B10）：四态迁移，ELSE 兜底进故障
 *      Main state machine: four-state transition with an ELSE fallback
 *------------------------------------------------------------------------------*)
CASE eState OF

    eInit:
        (* 清空全部累积量，进入填充阶段；故障与错误码同时清除（边界 B9） *)
        (* Clear all accumulators and enter filling; fault and error code are cleared too *)
        nWriteIndex := 0;
        nFilled     := 0;
        fSum        := 0.0;
        fAverage    := 0.0;
        fWindowSum  := 0.0;
        bBufferFull := FALSE;
        nCorrectCnt := 0;
        uErrorId    := 16#0000_0000;
        bError      := FALSE;
        eState      := eFilling;

    eFilling:
        (* 未满阶段：窗口填满即迁移到运行阶段 *)
        (* Filling phase: migrate to running once the window is full *)
        IF bBufferFull THEN
            eState := eRunning;
        END_IF

    eRunning:
        (* 满窗阶段：若窗口被放大导致已填样本不足，回退到填充阶段（边界 B4 配套） *)
        (* Running phase: fall back to filling if the window grew beyond the filled count *)
        IF NOT bBufferFull THEN
            eState := eFilling;
        END_IF

    eFault:
        (* 故障态：不采样、不清缓冲；锁存故障标志，输出由段 8 按最后有效累加值刷新 *)
        (* Fault state: no sampling, no buffer clearing; latch the fault flag, stage 8 holds the output *)
        bError := TRUE;

    ELSE
        (* 非法状态拦截：进入故障态并上报，不做隐式恢复 *)
        (* Illegal state interception: enter fault and report, no implicit recovery *)
        eState   := eFault;
        uErrorId := 16#0001_0005;
        bError   := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜采样触发判定（边界 B8）：电平语义 + 使能串接，复位当周期不采样
 *      Sampling decision: level semantics AND enable, suppressed on a reset scan
 *-----------------------------------------------------------------------------*)
bDoSample := bSample AND bEnable AND NOT bJustReset AND (eState <> eFault);

(*------------------------------------------------------------------------------
 * 段 7｜采样与递推（边界 B1/B2/B5/B6，本组件核心）
 *      Sampling and recursion, the core of this block
 *-----------------------------------------------------------------------------*)
IF bDoSample THEN

    (* 写指针上下界双检（红线 R4）：MOD 已保证范围内，仍显式兜底防越界写 *)
    (* Write index double check: MOD already guarantees the range, kept as an explicit guard *)
    IF (nWriteIndex < 0) OR (nWriteIndex > (DL_MAV_MAX_WINDOW - 1)) THEN
        nWriteIndex := 0;
        uErrorId    := 16#0001_0001;
        bError      := TRUE;
    END_IF

    IF bBufferFull THEN
        (*----------------------------------------------------------------------
         * 段 7a｜窗口已满：O(1) 递推——减去写指针处的最旧样本，再写入最新样本
         *       Buffer full: O(1) recursion, subtract the oldest then write the newest
         *       满窗时写指针恰好指向最旧样本，一个指针同时承担写入位与淘汰位
         *---------------------------------------------------------------------*)
        fSum := fSum - afBuffer[nWriteIndex] + fInput;
        afBuffer[nWriteIndex] := fInput;
    ELSE
        (*----------------------------------------------------------------------
         * 段 7b｜窗口未满：只追加样本与累加，绝不执行"减最旧值"
         *       Buffer not full: append only, never subtract the oldest
         *       若此处也减最旧值，会减掉尚未写入的 0，输出被系统性压低，
         *       表现为上电初期滤波值比原始信号更抖——即经典的两阶段缺陷
         *---------------------------------------------------------------------*)
        afBuffer[nWriteIndex] := fInput;
        fSum      := fSum + fInput;
        nFilled   := nFilled + 1;

        IF nFilled >= nWindowEff THEN
            nFilled     := nWindowEff;
            bBufferFull := TRUE;
        END_IF
    END_IF

    (*--------------------------------------------------------------------------
     * 段 7c｜指针回绕（边界 B5）：必须用 MOD，除数已由段 2 保证 ≥ 1
     *       Pointer wrap: MOD is mandatory, the divisor is guaranteed ≥ 1 by stage 2
     *-------------------------------------------------------------------------*)
    nWriteIndex := (nWriteIndex + 1) MOD nWindowEff;

    (*--------------------------------------------------------------------------
     * 段 7d｜浮点累加漂移校正（边界 B6）：每 N 次采样做一次全窗口重算
     *       Drift correction: a full-window recalculation every N samples
     *       FOR 循环设迭代上限并 EXIT，防止异常数据把扫描周期拖死
     *-------------------------------------------------------------------------*)
    nCorrectCnt := nCorrectCnt + 1;

    IF nCorrectCnt >= DL_MAV_CORRECT_CYCLE THEN
        nCorrectCnt := 0;
        fRecalcSum  := 0.0;
        nGuard      := 0;

        FOR nIdx := 0 TO (nFilled - 1) DO
            IF (nIdx >= 0) AND (nIdx <= (DL_MAV_MAX_WINDOW - 1)) THEN
                fRecalcSum := fRecalcSum + afBuffer[nIdx];
            END_IF

            nGuard := nGuard + 1;

            IF nGuard >= DL_MAV_MAX_LOOP THEN
                EXIT;
            END_IF
        END_FOR;

        fSum := fRecalcSum;
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出刷新（边界 B2）：除零双保险——窗口钳位已保证 nWindowEff ≥ 1，
 *      此处再以 nFilled > 0 兜底，两道防线缺一不可
 *      Output refresh: dual divide-by-zero protection, both guards are mandatory
 *      使能关闭时 nFilled 与 fSum 不变，平均值自然保持，不清空缓冲区（边界 B8）
 *-----------------------------------------------------------------------------*)
fWindowSum   := fSum;
nSampleCount := nFilled;

IF nFilled > 0 THEN
    fAverage := fSum / INT_TO_REAL(nFilled);
ELSE
    fAverage := 0.0;
END_IF
END_FUNCTION_BLOCK
