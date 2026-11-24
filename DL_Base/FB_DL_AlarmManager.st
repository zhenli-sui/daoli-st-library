(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AlarmManager
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG）+ 本库位打包构件
 * 功能描述 (Function)   : 16 通道报警优先级仲裁器。通道可配停机级 / 警告级 / 提示级 /
 *                         禁用四档；输出激活报警字、激活通道数、停机联锁位、
 *                         首出通道索引与当前最高优先级通道索引。
 *                         首出采用"先到先得"序号仲裁：每通道在激活沿取一个全局递增序号，
 *                         首出即序号最小者，与通道物理位置无关，避免低位通道永远抢先。
 *                         确认只清除首出锁存、不清除激活态——激活 / 已确认 / 首出锁存
 *                         三个信号正交输出，这是报警管理的基本纪律。
 *                         只做仲裁与锁存，不做事件历史与抑制管理（属上位机职责）。
 * 开源溯源 (Origin)     : 原创实现。优先级分级、首出锁存、确认三态分离等概念
 *                         参照 ISA-18.2 报警管理方法论的公开描述；代码为本库独立重构，
 *                         未复制任何源码。
 * 本文件内含       : FB    FB_DL_AlarmManager（单 POU，无配套类型）
 * 依赖     (Depends)    : FC_DL_PackBitsToWord（首轮 #6，报警字打包）
 *                         Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 禁用全局存储与物理寻址 ｜ R2 ✓ 无地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 数组双检 + 序号饱和 + 优先级钳位
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（仲裁为每周期全量重算，
 *                            无跨周期状态转移，故以本节说明替代 ELSE 兜底）
 *                         R7 ✓ R_TRIG 主体最前部无条件刷新 ｜ R8 ✓ 通道数与优先级全常量化
 *
 * 【首出语义：电平敏感 / First-out is level-sensitive（决策 D-R2-04）】
 *   输入即"报警态信号"（TRUE = 正在报警）。冷启动时已处于报警态的通道
 *   会在首扫按扫描顺序依次取号，因而谁先被扫到谁就是首出——
 *   这是电平敏感方案的固有行为，手册必须写明；需要"相对已知良好起点"判定
 *   的场合应由调用方在输入侧做沿处理。
 *
 * 【确认语义 / Acknowledge semantics（决策 D-R2-07）】
 *   确认沿只推进序号水位并清首出锁存，不改变任何通道的激活态。
 *   确认后若有更新的报警，按序号顺序自动补位成为新首出；
 *   已确认但仍在报警的通道不会再次成为首出，直到它消失后重新激活。
 *
 * 【使能恢复语义 / Re-enable semantics（决策 P6）】
 *   禁用会清空序号表与全部输出，重新使能视同冷启动重扫，
 *   避免"禁用期间积压的报警在恢复瞬间集中爆发、首出指向历史事件"的混淆。
 *
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 第二轮 · Level 0 批次 D）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AlarmManager
VAR_INPUT
    abAlarmActive : ARRAY[0..15] OF BOOL;   // 16 路报警激活态，电平敏感 / 16 alarm active levels, level-sensitive
    auPriority    : ARRAY[0..15] OF USINT;  // 通道优先级，0=禁用 1=停机 2=警告 3=提示 / Channel priority
    bAck          : BOOL;                   // 上升沿确认：清除首出锁存 / Rising edge: acknowledge the first-out latch
    bEnable       : BOOL := TRUE;           // 使能，FALSE 时全部输出清零 / Enable, FALSE clears every output
END_VAR
VAR_OUTPUT
    uAlarmWord    : WORD;    // 激活报警位图，bit0 = 通道 0，仅含启用通道 / Active bitmap, bit0 = channel 0, enabled only
    uActiveCount  : USINT;   // 激活通道数 [个]，值域 0..16 / Active channel count [count], range 0..16
    bAnyActive    : BOOL;    // 存在任意激活报警 / Any alarm active
    bShutdown     : BOOL;    // 存在停机级激活报警（联锁用）/ Any stop-level alarm active, for interlocking
    nFirstOutIdx  : INT;     // 首出通道索引，-1 = 无 / First-out channel index, -1 = none
    bFirstOutAck  : BOOL;    // 首出已确认标志 / First-out acknowledged flag
    nTopPrioIdx   : INT;     // 当前最高优先级激活通道（同级先到先得），-1 = 无 / Top-priority active channel, -1 = none
    uErrorId      : UDINT;   // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    auSeqNo       : ARRAY[0..15] OF UDINT;  // 通道激活序号，0 = 从未激活 / Activation sequence number, 0 = never activated
    auPrioEff     : ARRAY[0..15] OF USINT;  // 钳位后的通道优先级 / Clamped channel priority
    abPackSrc     : ARRAY[0..15] OF BOOL;   // 打包源（禁用通道置 FALSE）/ Packing source, disabled channels forced FALSE
    uSeqNext      : UDINT;                  // 全局递增序号发生器 / Global sequence generator
    uAckSeq       : UDINT;                  // 最近一次确认时刻的序号水位 / Sequence watermark at the last acknowledge
    uFirstSeq     : UDINT;                  // 扫描中的首出候选序号 / First-out candidate sequence during the scan
    uTopSeq       : UDINT;                  // 扫描中的最高优先级候选序号 / Top-priority candidate sequence during the scan
    bLatchValid   : BOOL;                   // 首出锁存有效 / First-out latch valid
    fbTrigAck     : R_TRIG;                 // 确认上升沿检测实例 / Acknowledge rising edge detector instance
    nIdx          : INT;                    // 扫描索引，值域 0..15 / Scan index, range 0..15
    nBestPrio     : USINT;                  // 扫描中的最优优先级 / Best priority during the scan
    uBestSeq      : UDINT;                  // 扫描中的最优序号（保留诊断口径）/ Best sequence during the scan
END_VAR
VAR CONSTANT
    DL_ALM_CH_COUNT  : INT   := 16;             // 通道数 [个]，与数组维度一致 / Channel count [count], must match the arrays
    DL_ALM_PRIO_STOP : USINT := 1;              // 停机级 / Stop level
    DL_ALM_PRIO_WARN : USINT := 2;              // 警告级 / Warning level
    DL_ALM_PRIO_INFO : USINT := 3;              // 提示级 / Info level
    DL_ALM_PRIO_MAX  : USINT := 3;              // 合法优先级上限 / Max valid priority
    DL_ALM_IDX_NONE  : INT   := -1;             // 无效通道索引哨兵 / Sentinel for no channel
    DL_ALM_SEQ_MAX   : UDINT := 16#FFFF_FFFE;   // 序号饱和上限，不回绕 / Sequence saturation limit, no wrap-around
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：确认沿实例位于主体最前部，严禁进入 IF / CASE
 *      Unconditional refresh zone: the acknowledge edge instance runs at the very top
 *-----------------------------------------------------------------------------*)
fbTrigAck(CLK := bAck);

(*------------------------------------------------------------------------------
 * 段 2｜故障码本周期清零
 *      Error code is cleared every scan
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 3｜使能失效（决策 P6）：输出与序号表全部清零，重新使能视同冷启动
 *      Disabled: outputs and the sequence table are cleared, re-enable is a cold start
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN

    uAlarmWord   := 16#0000;
    uActiveCount := USINT#0;
    bAnyActive   := FALSE;
    bShutdown    := FALSE;
    nFirstOutIdx := DL_ALM_IDX_NONE;
    bFirstOutAck := FALSE;
    nTopPrioIdx  := DL_ALM_IDX_NONE;
    bLatchValid  := FALSE;
    uSeqNext     := UDINT#0;
    uAckSeq      := UDINT#0;

    FOR nIdx := 0 TO (DL_ALM_CH_COUNT - 1) DO
        IF (nIdx >= 0) AND (nIdx < DL_ALM_CH_COUNT) THEN
            auSeqNo[nIdx]   := UDINT#0;
            auPrioEff[nIdx] := USINT#0;
            abPackSrc[nIdx] := FALSE;
        END_IF
    END_FOR;

ELSE

    (*--------------------------------------------------------------------------
     * 段 4｜确认水位推进（边界 B5）：确认沿只推水位，绝不动激活态
     *      Acknowledge: advance the watermark only, the active states are untouched
     *-------------------------------------------------------------------------*)
    IF fbTrigAck.Q THEN
        uAckSeq := uSeqNext;
    END_IF

    (*--------------------------------------------------------------------------
     * 段 5｜优先级钳位与激活取号（边界 B2/B3/B6/B9）：单次全通道扫描完成
     *      Priority clamp and activation numbering in one full-channel scan
     *      激活沿取号：通道由未激活变激活时取当前序号并递增发生器
     *      Activation numbering: a channel takes a number when it starts alarming
     *      通道消失即清号，使其下次激活能重新排队参与首出竞争
     *      The number is cleared on deactivation so a re-activation queues again
     *-------------------------------------------------------------------------*)
    FOR nIdx := 0 TO (DL_ALM_CH_COUNT - 1) DO

        IF (nIdx >= 0) AND (nIdx < DL_ALM_CH_COUNT) THEN

            IF auPriority[nIdx] > DL_ALM_PRIO_MAX THEN
                auPrioEff[nIdx] := DL_ALM_PRIO_MAX;
                uErrorId        := 16#0001_0001;
            ELSE
                auPrioEff[nIdx] := auPriority[nIdx];
            END_IF

            IF abAlarmActive[nIdx] THEN
                IF auSeqNo[nIdx] = UDINT#0 THEN
                    IF uSeqNext < DL_ALM_SEQ_MAX THEN
                        uSeqNext        := uSeqNext + UDINT#1;
                        auSeqNo[nIdx]   := uSeqNext;
                    ELSE
                        (* 序号饱和停增：回绕会破坏先到先得次序（边界 B6） *)
                        (* Saturation instead of wrap-around keeps the arrival order intact *)
                        auSeqNo[nIdx] := DL_ALM_SEQ_MAX;
                        uErrorId      := 16#0001_0007;
                    END_IF
                END_IF
            ELSE
                auSeqNo[nIdx] := UDINT#0;
            END_IF

        END_IF

    END_FOR;

    (*--------------------------------------------------------------------------
     * 段 6｜仲裁扫描（边界 B4）：首出取最小序号，最高优先级取最小优先级
     *      Arbitration: first-out is the smallest sequence, top priority the smallest level
     *      同级之间再比序号，实现"同级先到先得"，扫描为有限 FOR，无 WHILE
     *      Ties are broken by the sequence number, the scan is a bounded FOR loop
     *-------------------------------------------------------------------------*)
    nFirstOutIdx := DL_ALM_IDX_NONE;
    nTopPrioIdx  := DL_ALM_IDX_NONE;
    nBestPrio    := DL_ALM_PRIO_MAX;
    uFirstSeq    := UDINT#0;
    uTopSeq      := UDINT#0;
    uBestSeq     := UDINT#0;
    uActiveCount := USINT#0;
    bShutdown    := FALSE;

    FOR nIdx := 0 TO (DL_ALM_CH_COUNT - 1) DO

        IF (nIdx >= 0) AND (nIdx < DL_ALM_CH_COUNT) THEN

            (* 禁用通道（优先级 0）不参与计数与仲裁 *)
            (* Disabled channels take no part in counting or arbitration *)
            IF abAlarmActive[nIdx] AND (auPrioEff[nIdx] > USINT#0) THEN

                uActiveCount := uActiveCount + USINT#1;

                IF auPrioEff[nIdx] = DL_ALM_PRIO_STOP THEN
                    bShutdown := TRUE;
                END_IF

                (*--------------------------------------------------------------
                 * 段 6a｜首出候选：只接受晚于确认水位的序号（已确认的不再补位）
                 *      First-out candidate: only sequences newer than the watermark count
                 *-------------------------------------------------------------*)
                IF auSeqNo[nIdx] > uAckSeq THEN
                    IF (nFirstOutIdx = DL_ALM_IDX_NONE) OR (auSeqNo[nIdx] < uFirstSeq) THEN
                        nFirstOutIdx := nIdx;
                        uFirstSeq    := auSeqNo[nIdx];
                    END_IF
                END_IF

                (*--------------------------------------------------------------
                 * 段 6b｜最高优先级候选：优先级数值更小者胜，同级比序号
                 *      Top-priority candidate: the smaller level wins, ties by sequence
                 *-------------------------------------------------------------*)
                IF (nTopPrioIdx = DL_ALM_IDX_NONE) OR (auPrioEff[nIdx] < nBestPrio) THEN
                    nTopPrioIdx := nIdx;
                    nBestPrio   := auPrioEff[nIdx];
                    uTopSeq     := auSeqNo[nIdx];
                    uBestSeq    := auSeqNo[nIdx];
                ELSIF (auPrioEff[nIdx] = nBestPrio) AND (auSeqNo[nIdx] < uTopSeq) THEN
                    nTopPrioIdx := nIdx;
                    uTopSeq     := auSeqNo[nIdx];
                END_IF

            END_IF

        END_IF

    END_FOR;

    (*--------------------------------------------------------------------------
     * 段 7｜报警字打包（边界 B7）：先构造打包源，再调用位打包构件
     *      Bitmap packing: build the source array first, then call the packing function
     *      禁用通道对应位强制 0：报警字是给上位机的最终事实，
     *      混入"禁用但确实跳了"的位会让上位机与 PLC 状态产生错觉（决策 P5）
     *      Disabled bits are forced to zero so the bitmap never contradicts the arbitration
     *-------------------------------------------------------------------------*)
    FOR nIdx := 0 TO (DL_ALM_CH_COUNT - 1) DO
        IF (nIdx >= 0) AND (nIdx < DL_ALM_CH_COUNT) THEN
            abPackSrc[nIdx] := abAlarmActive[nIdx] AND (auPrioEff[nIdx] > USINT#0);
        END_IF
    END_FOR;

    uAlarmWord := FC_DL_PackBitsToWord(abBits := abPackSrc);

    (*--------------------------------------------------------------------------
     * 段 8｜输出汇总（边界 B5）：三态正交——激活、已确认、首出锁存各管一路
     *      Output summary: active, acknowledged and first-out latched stay orthogonal
     *-------------------------------------------------------------------------*)
    bLatchValid  := (nFirstOutIdx <> DL_ALM_IDX_NONE);
    bAnyActive   := (uActiveCount > USINT#0);
    bFirstOutAck := (NOT bLatchValid) AND (uAckSeq > UDINT#0);

END_IF
END_FUNCTION_BLOCK
