(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LifoStack
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），无厂商方言
 * 功能描述 (Function)   : 定长 64 深度 LIFO 栈（后进先出），支持压栈、弹栈、
 *                         窥视栈顶、清空四操作，全部 O(1)，无任何元素搬移。
 *                         带上溢/下溢锁存与单调累计计数。用于工艺路径回溯
 *                         （走了哪些工位、原路退回）、嵌套配方解析、报警确认
 *                         的"撤销"语义、深度优先搜索的待办表。
 *                         满栈压入拒绝且不覆盖栈底：LIFO 无"丢最旧"语义，
 *                         静默覆盖会让路径回溯错位一格，现场极难排查。
 * 本文件内含       : E_DL_StackState（枚举，归属本组件）
 *                    FB_DL_LifoStack（功能块主体）
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 数据处理组的 FIFO/LIFO
 *                         拆分方式与"满/空/长度"状态位粒度，clean-room 编写，
 *                         未复制任何源码）。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3，计数比较显式转换 ｜ R4 ✓ 下标双检 + 空满拒绝
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 两 R_TRIG 主体最前部无条件刷新
 *
 * 【与 FIFO 的区别 / Difference to FIFO（边界 B7）】
 *   同一序列 1,2,3 依次压入：FIFO（FB_DL_RingBufferLReal）弹出 1,2,3；
 *   本块弹出 3,2,1。本块只有单栈顶指针、无回绕，读/写双指针结构见环形队列块。
 *
 * 【同周期压弹次序 / Push-before-pop ordering（边界 B3）】
 *   同一扫描周期同时出现压栈沿与弹栈沿时，先压后弹：弹出的是刚压入的值。
 *   这是"写入后立即读回校验"的常见用法；次序不可交换，先弹后压会读到
 *   旧栈顶，调用方会误判校验失败。
 *
 * 【哨兵值披露 / Sentinel disclosure（边界 B2）】
 *   空栈时栈顶输出 0.0、下溢弹出值输出 0.0，该 0.0 是哨兵不是数据。
 *   判空必须看空标志或深度计数，不得以"栈顶等于 0"反推栈状态。
 *
 * 【锁存纪律 / Latch discipline（边界 B5）】
 *   上溢/下溢故障码为锁存码，bClear 是唯一清锁存路径；清空保留
 *   累计计数（生命周期统计不清零）。
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
TYPE E_DL_StackState :
(
    eEmpty := 0,      // 空栈，无可弹数据 / Empty, nothing to pop
    eReady := 10,     // 有数据可弹 / Has data available
    eFault := 99      // 上溢或下溢锁存，需 bClear 解除 / Overflow or underflow latched, clear required
);
END_TYPE

FUNCTION_BLOCK FB_DL_LifoStack
VAR_INPUT
    bPush      : BOOL;                     // 上升沿：压入 fPushValue / Rising edge: push value
    fPushValue : LREAL := 0.0;             // 待压入值 [EU] / Value to push [EU]
    bPop       : BOOL;                     // 上升沿：弹出栈顶 / Rising edge: pop top
    bPeek      : BOOL;                     // TRUE：fTop 输出当前栈顶（不改变栈） / TRUE: expose top without popping
    bClear     : BOOL;                     // TRUE：清空栈与锁存（保留累计计数） / TRUE: clear stack and latches, counters kept
    bEnable    : BOOL := TRUE;             // 使能，FALSE 时禁止入栈/出栈 / Enable, FALSE blocks push and pop
END_VAR
VAR_OUTPUT
    fTop       : LREAL;                    // 栈顶值 [EU]，空栈时为 0.0 哨兵 / Top value [EU], 0.0 sentinel when empty
    fPopValue  : LREAL;                    // 本次弹出值 [EU]，未弹出为 0.0 / Popped value [EU], 0.0 when nothing popped
    nCount     : INT;                      // 当前深度 [个]，值域 0..64 / Current depth [count], range 0..64
    bEmpty     : BOOL;                     // 空栈标志 / Empty flag
    bFull      : BOOL;                     // 满栈标志 / Full flag
    bOverflow  : BOOL;                     // 上溢锁存（压栈被拒） / Overflow latched, push rejected
    bUnderflow : BOOL;                     // 下溢锁存（弹栈被拒） / Underflow latched, pop rejected
    uPushCount : UDINT;                    // 累计入栈次数（饱和），仅成功写入时递增 / Total successful pushes, saturating
    uPopCount  : UDINT;                    // 累计出栈次数（饱和），仅成功弹出时递增 / Total successful pops, saturating
    bError     : BOOL;                     // 故障标志（上溢/下溢锁存） / Fault flag, latched
    uErrorId   : UDINT;                    // 故障码，0 = 无故障 / Error code, 0 = no error
    eState     : E_DL_StackState;          // 当前状态（供诊断） / Current state for diagnostics
END_VAR
VAR
    fbTrigPush : R_TRIG;                   // 压栈沿检测实例 / Push edge detector instance
    fbTrigPop  : R_TRIG;                   // 弹栈沿检测实例 / Pop edge detector instance
    afStack    : ARRAY[0..63] OF LREAL;    // 栈体 [EU] / Stack body [EU]
    nTop       : INT;                      // 栈顶指针 = 元素个数，0 = 空 / Top pointer = element count, 0 = empty
    bOvfLatch  : BOOL;                     // 上溢锁存 / Overflow latch
    bUnfLatch  : BOOL;                     // 下溢锁存 / Underflow latch
    eStateInt  : E_DL_StackState;          // 内部状态机当前态 / Internal state machine state
END_VAR
VAR CONSTANT
    DL_LIFO_CAP     : INT   := 64;           // 栈容量，必须与数组维度严格一致 / Capacity, must match the array
    DL_LIFO_CNT_MAX : UDINT := 16#FFFF_FFFE; // 累计计数饱和值，不回绕 / Counter saturation, no wrap-around
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：两个边沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: both edge instances run at the very top
 *-----------------------------------------------------------------------------*)
fbTrigPush(CLK := bPush);
fbTrigPop(CLK  := bPop);

(*------------------------------------------------------------------------------
 * 段 2｜弹出值本周期清零（边界 B2）：未弹出时输出 0.0 哨兵而非保留上次值，
 *      Popped value cleared every scan
 *      保留上次值会让调用方把旧数据当新数据用
 *-----------------------------------------------------------------------------*)
fPopValue := 0.0;

(*------------------------------------------------------------------------------
 * 段 3｜清空（边界 B5）：电平触发、最高优先级，先于压弹处理；
 *      Clear: level-triggered, highest priority, handled before push and pop
 *      bClear 是唯一清锁存路径；累计计数为生命周期统计，不清零
 *-----------------------------------------------------------------------------*)
IF bClear THEN
    nTop      := 0;
    bOvfLatch := FALSE;
    bUnfLatch := FALSE;
    uErrorId  := 16#0000_0000;
    fTop      := 0.0;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜压栈（边界 B1/B4）：满栈拒绝写入，绝不覆盖栈底；
 *      Push: rejected when full, the deepest element is never overwritten
 *      拒绝路径不递增累计计数，避免"溢出一次计数暴涨"（边界 B4）
 *-----------------------------------------------------------------------------*)
IF fbTrigPush.Q AND bEnable THEN

    IF nTop >= DL_LIFO_CAP THEN
        bOvfLatch := TRUE;
        uErrorId  := 16#0001_0009;      // 上溢：满栈压入被拒 / Overflow: push rejected on full stack
    ELSIF (nTop >= 0) AND (nTop < DL_LIFO_CAP) THEN
        (* 栈顶指针双检（红线 R4）：写入前显式校验上下界 *)
        (* Top pointer double check: explicit bounds check before writing *)
        afStack[nTop] := fPushValue;
        nTop := nTop + 1;
        IF uPushCount < DL_LIFO_CNT_MAX THEN
            uPushCount := uPushCount + 1;
        END_IF
    ELSE
        (* 指针异常兜底：正常流程不可达，命中说明内存被外部破坏 *)
        (* Pointer anomaly fallback: unreachable in normal flow, memory corruption *)
        bOvfLatch := TRUE;
        uErrorId  := 16#0001_0007;      // 栈顶指针越界 / Top pointer out of range
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 5｜弹栈（边界 B2/B3）：空栈拒绝，弹出值置 0.0 哨兵；
 *      Pop: rejected when empty, popped value set to the 0.0 sentinel
 *      与压栈同周期出现时按"先压后弹"处理，此处已位于压栈之后（边界 B3）
 *-----------------------------------------------------------------------------*)
IF fbTrigPop.Q AND bEnable THEN

    IF nTop <= 0 THEN
        bUnfLatch := TRUE;
        uErrorId  := 16#0001_000A;      // 下溢：空栈弹出被拒 / Underflow: pop rejected on empty stack
        fPopValue := 0.0;
    ELSE
        nTop := nTop - 1;
        IF (nTop >= 0) AND (nTop < DL_LIFO_CAP) THEN
            (* 读回前下标双检（红线 R4） *)
            (* Index double check before read-back *)
            fPopValue := afStack[nTop];
        ELSE
            fPopValue := 0.0;
            uErrorId  := 16#0001_0007;  // 栈顶指针越界 / Top pointer out of range
        END_IF
        IF uPopCount < DL_LIFO_CNT_MAX THEN
            uPopCount := uPopCount + 1;
        END_IF
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 6｜状态派生：锁存优先，其次按深度分空/就绪
 *      State derivation: latches first, then empty or ready by depth
 *-----------------------------------------------------------------------------*)
IF bOvfLatch OR bUnfLatch THEN
    eStateInt := E_DL_StackState.eFault;
ELSIF nTop <= 0 THEN
    eStateInt := E_DL_StackState.eEmpty;
ELSE
    eStateInt := E_DL_StackState.eReady;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with ELSE fallback
 *      故障态仍允许反向操作（满栈可弹、空栈可压），仅置故障标志（见规格语义表）
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_StackState.eEmpty:
        (* 空栈：栈顶输出哨兵 0.0 / Empty: top outputs the 0.0 sentinel *)
        fTop := 0.0;

    E_DL_StackState.eReady:
        (* 就绪：栈顶输出 afStack[nTop-1]，读前下标双检（红线 R4） *)
        (* Ready: top outputs afStack[nTop-1] with a bounds check before read *)
        IF (nTop > 0) AND (nTop <= DL_LIFO_CAP) THEN
            fTop := afStack[nTop - 1];
        ELSE
            fTop := 0.0;
        END_IF

    E_DL_StackState.eFault:
        (* 故障锁存：保持现状，bClear 在段 3 解除 / Fault latched, cleared via bClear *)

    ELSE
        (* 非法状态一律回故障态并置码（红线 R6） *)
        (* Illegal state falls back to fault with a code *)
        eStateInt := E_DL_StackState.eFault;
        uErrorId  := 16#0001_0005;

END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口：空满标志由指针派生，指针只在成功路径上增减
 *      Single output exit: flags derived from the pointer, which only moves on success
 *-----------------------------------------------------------------------------*)
nCount     := nTop;
bEmpty     := (nTop <= 0);
bFull      := (nTop >= DL_LIFO_CAP);
bOverflow  := bOvfLatch;
bUnderflow := bUnfLatch;
bError     := (bOvfLatch OR bUnfLatch);
eState     := eStateInt;
END_FUNCTION_BLOCK
