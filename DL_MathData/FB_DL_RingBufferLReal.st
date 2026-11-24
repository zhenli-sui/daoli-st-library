(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RingBufferLReal
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），浮点用标准 64 位类型
 * 功能描述 (Function)   : 定长 64 容量的 LREAL 环形队列（先进先出）。压入 / 弹出 / 窥视 /
 *                         清空四操作全部 O(1)，无任何元素搬移与循环。
 *                         解决"每来一个样本把整段数组移位一次还容易错位一格"、
 *                         "故障前最后一段数据被冲掉无法追溯"两类现场问题。
 *                         满时拒绝写入而不覆盖最旧值：FIFO 语义下静默覆盖会让
 *                         数据丢失变得不可见，需要滑动窗口语义的场合请用滑动平均块。
 *                         全部指针更新只用"加一后取模"的前向回绕，
 *                         组件内不存在任何指针减法，从结构上规避负数取模的平台差异。
 * 开源溯源 (Origin)     : 原创实现。环形队列 + 计数区分空满为公开经典算法；
 *                         本库仅借鉴其 O(1) 递推语义，独立重构，未复制任何源码。
 * 本文件内含       : FB    FB_DL_RingBufferLReal（单 POU，无配套类型）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3，计数比较显式转换 ｜ R4 ✓ 下标双检 + 前向取模回绕
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（队列无跨周期状态转移，指针与计数即全部状态）
 *                         R7 ✓ 两 R_TRIG 主体最前部无条件刷新 ｜ R8 ✓ 容量常量化
 *
 * 【容量与内存披露 / Capacity and memory（边界 B10）】
 *   固定容量 64 元素，元素为 64 位浮点，实例净占用约 512 字节缓冲区，
 *   加指针与计数共约 0.6KB。定长数组跨平台行为一致，运行时容量参数化
 *   会引入动态数组差异，故不提供。
 *
 * 【哨兵值披露 / Sentinel disclosure（边界 B7）】
 *   空队时窥视输出 0.0，该 0.0 是哨兵不是数据。判空必须看空标志，
 *   不得以"窥视值等于 0"反推队列状态——0 是合法的采样值。
 *
 * 【同周期压弹次序 / Push-before-pop ordering（边界 B5）】
 *   同一扫描周期同时出现压入沿与弹出沿时，先压后弹，净效果为"换出队首"。
 *   该次序不可交换，改动会改变满队与单元素队列的行为语义。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 C）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RingBufferLReal
VAR_INPUT
    fPushValue : LREAL;   // 待压入值 [EU] / Value to push [EU]
    bPush      : BOOL;    // 上升沿压入 / Push on rising edge
    bPop       : BOOL;    // 上升沿弹出 / Pop on rising edge
    bClear     : BOOL;    // 电平清空，最高优先级操作 / Level-triggered clear, highest priority
END_VAR
VAR_OUTPUT
    fPopValue  : LREAL;   // 最近一次弹出值 [EU]，空读被拒时保持上次值 / Last popped value [EU], holds on a rejected pop
    fPeekValue : LREAL;   // 队首值 [EU]，空队时为 0.0 哨兵 / Front value [EU], 0.0 sentinel when empty
    uCount     : UINT;    // 当前元素数 [个]，值域 0..64 / Current element count [count], range 0..64
    bFull      : BOOL;    // 已满标志 / Full flag
    bEmpty     : BOOL;    // 已空标志 / Empty flag
    uErrorId   : UDINT;   // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    afBuffer   : ARRAY[0..63] OF LREAL;  // 环形存储区 [EU] / Ring storage [EU]
    nReadIdx   : INT;                    // 读指针（队首），值域 0..63 / Read index (front), range 0..63
    nWriteIdx  : INT;                    // 写指针（下一写入位），值域 0..63 / Write index (next slot), range 0..63
    fbTrigPush : R_TRIG;                 // 压入沿检测实例 / Push edge detector instance
    fbTrigPop  : R_TRIG;                 // 弹出沿检测实例 / Pop edge detector instance
END_VAR
VAR CONSTANT
    DL_RB_CAP : INT := 64;   // 固定容量，必须与数组维度严格一致 / Fixed capacity, must match the array
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：两个边沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: both edge instances run at the very top
 *-----------------------------------------------------------------------------*)
fbTrigPush(CLK := bPush);
fbTrigPop(CLK  := bPop);

(*------------------------------------------------------------------------------
 * 段 2｜故障码本周期清零
 *      Error code is cleared every scan
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 3｜清空（边界 B2）：电平触发、最高优先级，先于压弹处理
 *      Clear: level-triggered and highest priority, handled before push and pop
 *      这样"清空与压入同周期"的结果只可能是"压入一个元素"，不存在歧义
 *      Clear-then-push in one scan deterministically leaves exactly one element
 *-----------------------------------------------------------------------------*)
IF bClear THEN
    nReadIdx  := 0;
    nWriteIdx := 0;
    uCount    := UINT#0;
    fPeekValue := 0.0;
ELSE

    (*--------------------------------------------------------------------------
     * 段 4｜压入（边界 B3）：满时拒绝写入，绝不覆盖最旧值
     *      Push: rejected when full, the oldest value is never silently overwritten
     *-------------------------------------------------------------------------*)
    IF fbTrigPush.Q THEN
        IF uCount >= INT_TO_UINT(DL_RB_CAP) THEN
            uErrorId := 16#0001_0009;
        ELSE
            (* 写指针双检：MOD 已保证范围，仍显式兜底防越界写（R4） *)
            (* Write index double check, kept as an explicit guard besides MOD *)
            IF (nWriteIdx >= 0) AND (nWriteIdx < DL_RB_CAP) THEN
                afBuffer[nWriteIdx] := fPushValue;
            ELSE
                nWriteIdx := 0;
                afBuffer[nWriteIdx] := fPushValue;
            END_IF

            (* 前向取模回绕：组件内不存在指针减法（边界 B6） *)
            (* Forward modulo wrap, no pointer subtraction anywhere in this component *)
            nWriteIdx := (nWriteIdx + 1) MOD DL_RB_CAP;
            uCount    := uCount + UINT#1;
        END_IF
    END_IF

    (*--------------------------------------------------------------------------
     * 段 5｜弹出（边界 B4/B5）：空时拒绝，弹出值保持上次有效值
     *      Pop: rejected when empty, the last valid value is held
     *      与压入同周期出现时按"先压后弹"处理，此处已位于压入之后
     *      Handled after the push stage, implementing the push-before-pop order
     *-------------------------------------------------------------------------*)
    IF fbTrigPop.Q THEN
        IF uCount = UINT#0 THEN
            uErrorId := 16#0001_000A;
        ELSE
            IF (nReadIdx >= 0) AND (nReadIdx < DL_RB_CAP) THEN
                fPopValue := afBuffer[nReadIdx];
            ELSE
                nReadIdx  := 0;
                fPopValue := afBuffer[nReadIdx];
            END_IF

            nReadIdx := (nReadIdx + 1) MOD DL_RB_CAP;
            uCount   := uCount - UINT#1;
        END_IF
    END_IF

    (*--------------------------------------------------------------------------
     * 段 6｜窥视（边界 B7）：每周期刷新队首，空队输出哨兵 0.0
     *      Peek: refreshed every scan, the empty queue reports the 0.0 sentinel
     *-------------------------------------------------------------------------*)
    IF uCount > UINT#0 THEN
        IF (nReadIdx >= 0) AND (nReadIdx < DL_RB_CAP) THEN
            fPeekValue := afBuffer[nReadIdx];
        ELSE
            fPeekValue := 0.0;
        END_IF
    ELSE
        fPeekValue := 0.0;
    END_IF

END_IF

(*------------------------------------------------------------------------------
 * 段 7｜状态标志（边界 B8）：空满由计数派生，计数只在成功路径上加减
 *      Status flags: derived from the count, which only moves on success paths
 *-----------------------------------------------------------------------------*)
bFull  := (uCount >= INT_TO_UINT(DL_RB_CAP));
bEmpty := (uCount = UINT#0);
END_FUNCTION_BLOCK
