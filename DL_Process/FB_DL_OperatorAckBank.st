//==============================================================================
// 功能块：FB_DL_OperatorAckBank ｜ 中文名称：操作员报警确认组
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3，零方言）
// 功能描述：4 路报警确认 Bank（ISA-182 语义）：逐条确认 + 成组确认两通道；
//           每路报警"已确认"状态锁存于报警活动期，报警撤除自动复位确认
//           （下次再现须重新确认）；未确认滞留清单经位掩码 + 计数双出口
//           （nUnackMask 位 = 路号，nUnackCnt 计数），bAnyUnack 聚合声明。
// 开源溯源 (Origin)：原创实现（t2-8-isa182 报警管理语义深化，零外部源码行，
//           clean-room 独立编写）
// 公开接口清单：输入 {bAlmCh1..4} / bAckCh1..4 / bAckAll；
//               输出 {bUnackCh1..4} / nUnackMask / nUnackCnt / bAnyUnack /
//               uErrCode / bValid
// 错误码表：无状态机码轨（确认台账无故障级条件），不占用 16#0005 段码位
// 状态机：N/A（确认台账无状态机；R_TRIG ×5 每拍无条件刷新）
// 边界行为：① 确认沿在报警未活动时为空操作（不预确认未来报警）；
//           ② 报警撤除自动复位该路确认锁存（ISA-182 再现须重确认）；
//           ③ R_TRIG ×5 每拍无条件刷新（不入分支，红线 R7）；
//           ④ 位掩码按位编号 1..4（bit0..bit3），计数与掩码同源装配。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 2 · 序 20）
//==============================================================================

(*==============================================================================
 * 功能块: FB_DL_OperatorAckBank
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_OperatorAckBank
VAR_INPUT
    bAlmCh1 : BOOL := FALSE;           // 报警 1 活动信号 / Alarm 1 active signal
    bAlmCh2 : BOOL := FALSE;           // 报警 2 活动信号 / Alarm 2 active signal
    bAlmCh3 : BOOL := FALSE;           // 报警 3 活动信号 / Alarm 3 active signal
    bAlmCh4 : BOOL := FALSE;           // 报警 4 活动信号 / Alarm 4 active signal
    bAckCh1 : BOOL := FALSE;           // 报警 1 逐条确认按钮（沿有效）/ Alarm 1 ack pushbutton, edge active
    bAckCh2 : BOOL := FALSE;           // 报警 2 逐条确认按钮（沿有效）/ Alarm 2 ack pushbutton, edge active
    bAckCh3 : BOOL := FALSE;           // 报警 3 逐条确认按钮（沿有效）/ Alarm 3 ack pushbutton, edge active
    bAckCh4 : BOOL := FALSE;           // 报警 4 逐条确认按钮（沿有效）/ Alarm 4 ack pushbutton, edge active
    bAckAll : BOOL := FALSE;           // 成组确认按钮（沿有效，仅确认当前活动路）/ Group ack pushbutton, edge active, active channels only
END_VAR
VAR_OUTPUT
    bUnackCh1 : BOOL;                  // 报警 1 未确认滞留声明 / Alarm 1 unacknowledged pending
    bUnackCh2 : BOOL;                  // 报警 2 未确认滞留声明 / Alarm 2 unacknowledged pending
    bUnackCh3 : BOOL;                  // 报警 3 未确认滞留声明 / Alarm 3 unacknowledged pending
    bUnackCh4 : BOOL;                  // 报警 4 未确认滞留声明 / Alarm 4 unacknowledged pending
    nUnackMask: UINT;                  // 未确认滞留位掩码（bit0..bit3 = 路 1..4）/ Unacked pending bitmask
    nUnackCnt : UDINT;                 // 未确认滞留计数 [路] / Unacked pending count [channels]
    bAnyUnack : BOOL;                  // 存在未确认滞留聚合声明 / Any unacked aggregate declaration
    uErrCode  : UDINT;                 // 信息级码，恒 0（无故障级条件）/ Info code, always 0
    bValid    : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    trigAck1  : R_TRIG;                // 确认 1 沿检测，每拍无条件刷新 / Ack 1 edge, refreshed every scan
    trigAck2  : R_TRIG;                // 确认 2 沿检测，每拍无条件刷新 / Ack 2 edge, refreshed every scan
    trigAck3  : R_TRIG;                // 确认 3 沿检测，每拍无条件刷新 / Ack 3 edge, refreshed every scan
    trigAck4  : R_TRIG;                // 确认 4 沿检测，每拍无条件刷新 / Ack 4 edge, refreshed every scan
    trigAckAll: R_TRIG;                // 成组确认沿检测，每拍无条件刷新 / Group ack edge, refreshed every scan
    bAcked1   : BOOL;                  // 报警 1 确认锁存（活动期内）/ Alarm 1 acked latch, while active
    bAcked2   : BOOL;                  // 报警 2 确认锁存（活动期内）/ Alarm 2 acked latch, while active
    bAcked3   : BOOL;                  // 报警 3 确认锁存（活动期内）/ Alarm 3 acked latch, while active
    bAcked4   : BOOL;                  // 报警 4 确认锁存（活动期内）/ Alarm 4 acked latch, while active
END_VAR

// ---- 段 1｜沿实例无条件刷新（红线 R7：全部 5 实例不入分支）----
trigAck1(CLK := bAckCh1);             // 确认 1 沿每拍刷新 / Ack 1 edge refreshed
trigAck2(CLK := bAckCh2);             // 确认 2 沿每拍刷新 / Ack 2 edge refreshed
trigAck3(CLK := bAckCh3);             // 确认 3 沿每拍刷新 / Ack 3 edge refreshed
trigAck4(CLK := bAckCh4);             // 确认 4 沿每拍刷新 / Ack 4 edge refreshed
trigAckAll(CLK := bAckAll);           // 成组确认沿每拍刷新 / Group ack edge refreshed

// ---- 段 2｜确认锁存推进：报警撤除自动复位（ISA-182 再现须重确认）----
IF trigAck1.Q AND bAlmCh1 THEN        // 逐条确认沿且报警活动（沿在无活动时为空操作）/ Per-channel ack while active
    bAcked1 := TRUE;                  // 确认锁存置位 / Acked latch set
END_IF
IF trigAck2.Q AND bAlmCh2 THEN
    bAcked2 := TRUE;                  // 报警 2 确认锁存 / Alarm 2 acked latch
END_IF
IF trigAck3.Q AND bAlmCh3 THEN
    bAcked3 := TRUE;                  // 报警 3 确认锁存 / Alarm 3 acked latch
END_IF
IF trigAck4.Q AND bAlmCh4 THEN
    bAcked4 := TRUE;                  // 报警 4 确认锁存 / Alarm 4 acked latch
END_IF
IF trigAckAll.Q THEN                  // 成组确认沿：仅确认当前活动路 / Group ack: active channels only
    IF bAlmCh1 THEN
        bAcked1 := TRUE;              // 报警 1 成组确认 / Alarm 1 group acked
    END_IF
    IF bAlmCh2 THEN
        bAcked2 := TRUE;              // 报警 2 成组确认 / Alarm 2 group acked
    END_IF
    IF bAlmCh3 THEN
        bAcked3 := TRUE;              // 报警 3 成组确认 / Alarm 3 group acked
    END_IF
    IF bAlmCh4 THEN
        bAcked4 := TRUE;              // 报警 4 成组确认 / Alarm 4 group acked
    END_IF
END_IF
IF NOT bAlmCh1 THEN
    bAcked1 := FALSE;                 // 报警撤除自动复位确认锁存 / Latch auto-reset on alarm clear
END_IF
IF NOT bAlmCh2 THEN
    bAcked2 := FALSE;                 // 报警 2 撤除复位 / Alarm 2 reset on clear
END_IF
IF NOT bAlmCh3 THEN
    bAcked3 := FALSE;                 // 报警 3 撤除复位 / Alarm 3 reset on clear
END_IF
IF NOT bAlmCh4 THEN
    bAcked4 := FALSE;                 // 报警 4 撤除复位 / Alarm 4 reset on clear
END_IF

// ---- 段 3｜未确认滞留清单装配：位掩码 + 计数同源（掩码按位号 1..4）----
bUnackCh1 := bAlmCh1 AND (NOT bAcked1); // 报警 1 未确认滞留 / Alarm 1 unacked pending
bUnackCh2 := bAlmCh2 AND (NOT bAcked2); // 报警 2 未确认滞留 / Alarm 2 unacked pending
bUnackCh3 := bAlmCh3 AND (NOT bAcked3); // 报警 3 未确认滞留 / Alarm 3 unacked pending
bUnackCh4 := bAlmCh4 AND (NOT bAcked4); // 报警 4 未确认滞留 / Alarm 4 unacked pending
nUnackMask := UINT#0;                 // 掩码先清零（显式类型字面量，R10 口径）/ Mask preset zero, typed literal
IF bUnackCh1 THEN
    nUnackMask := nUnackMask OR UINT#1; // bit0 置位（路 1）/ Bit0 set, channel 1
END_IF
IF bUnackCh2 THEN
    nUnackMask := nUnackMask OR UINT#2; // bit1 置位（路 2）/ Bit1 set, channel 2
END_IF
IF bUnackCh3 THEN
    nUnackMask := nUnackMask OR UINT#4; // bit2 置位（路 3）/ Bit2 set, channel 3
END_IF
IF bUnackCh4 THEN
    nUnackMask := nUnackMask OR UINT#8; // bit3 置位（路 4）/ Bit3 set, channel 4
END_IF
nUnackCnt := UDINT#0;                 // 计数先清零 / Count preset zero
IF bUnackCh1 THEN
    nUnackCnt := nUnackCnt + UDINT#1; // 路 1 计入 / Channel 1 counted
END_IF
IF bUnackCh2 THEN
    nUnackCnt := nUnackCnt + UDINT#1; // 路 2 计入 / Channel 2 counted
END_IF
IF bUnackCh3 THEN
    nUnackCnt := nUnackCnt + UDINT#1; // 路 3 计入 / Channel 3 counted
END_IF
IF bUnackCh4 THEN
    nUnackCnt := nUnackCnt + UDINT#1; // 路 4 计入 / Channel 4 counted
END_IF
bAnyUnack := nUnackCnt > UDINT#0;     // 聚合声明 / Aggregate declaration
uErrCode  := UDINT#0;                 // 信息码恒零（无故障级条件，码表对齐）/ Info code always zero
bValid    := TRUE;                    // 台账输出恒可用 / Ledger outputs always usable
END_FUNCTION_BLOCK