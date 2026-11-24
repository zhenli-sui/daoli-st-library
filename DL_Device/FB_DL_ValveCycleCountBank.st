//==============================================================================
// 功能块：FB_DL_ValveCycleCountBank ｜ 中文名称：多阀动作计数寿命台账组
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯标准库 R_TRIG）
// 功能描述：4 阀动作计数寿命台账 Bank：每通道对阀指令上升沿计数（全行程
//           动作次数），独立维护阈值（UDINT），计数达阈值置该通道维护预警
//           bMaintX（不置故障——维护预警是台账事实非软件错误）。计数饱和
//           于 UDINT 上限 4294967295 不回绕（信息级留痕），复位经 bRst 沿
//           或 bRstChX 单通道沿。
//           同族分工：单阀寿命判定（阀位双阈值跨越 + 双源同证去抖 + 分级
//           预警）属 FB_DL_ValveCycleLifeCounter；本件为 4 通道指令沿计数
//           Bank 台账（无反馈口径），互不替代（R73 互引）。
// 开源溯源 (Origin)：原创实现（t2-2-lbp 阀诊断深化，零外部源码行，clean-room
//           独立编写）
// 公开接口清单：输入 {bCmdCh1..4, uLimitCh1..4} / bRst / bRstCh1..4；
//               输出 {uCntCh1..4, bMaintCh1..4} / uErrCode / bValid
// 错误码表：16#0003_0754 信息级（任一通道计数饱和不回绕，不置 bError）/
//           16#0003_0755 预留禁用（不得挪用）
// 状态机：N/A（台账计数无状态机；R_TRIG ×8 每拍无条件刷新）
// 边界行为：① 计数饱和于 4294967295 不回绕（信息级 0754 留痕）；
//           ② R_TRIG 全部每拍无条件刷新（不入分支，红线 R7）；
//           ③ 维护预警随计数回落自动撤销（阈值比较瞬时量，不锁存）；
//           ④ 复位沿仅清计数，不清阈值与信息码（信息码每拍重算）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 16）
//==============================================================================

(*==============================================================================
 * 功能块: FB_DL_ValveCycleCountBank
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ValveCycleCountBank
VAR_INPUT
    bCmdCh1  : BOOL := FALSE;          // 阀 1 指令（上升沿 = 一次全行程动作）/ Valve 1 command, rising edge = one full stroke
    bCmdCh2  : BOOL := FALSE;          // 阀 2 指令（上升沿计数）/ Valve 2 command, counted on rising edge
    bCmdCh3  : BOOL := FALSE;          // 阀 3 指令（上升沿计数）/ Valve 3 command, counted on rising edge
    bCmdCh4  : BOOL := FALSE;          // 阀 4 指令（上升沿计数）/ Valve 4 command, counted on rising edge
    uLimitCh1: UDINT := 1000000;       // 阀 1 维护阈值 [次] / Valve 1 maintenance threshold [cycles]
    uLimitCh2: UDINT := 1000000;       // 阀 2 维护阈值 [次] / Valve 2 maintenance threshold [cycles]
    uLimitCh3: UDINT := 1000000;       // 阀 3 维护阈值 [次] / Valve 3 maintenance threshold [cycles]
    uLimitCh4: UDINT := 1000000;       // 阀 4 维护阈值 [次] / Valve 4 maintenance threshold [cycles]
    bRst     : BOOL := FALSE;          // 全组复位（上升沿，清全部计数）/ Bank reset, rising edge, clears all counts
    bRstCh1  : BOOL := FALSE;          // 阀 1 单通道复位沿 / Valve 1 channel reset edge
    bRstCh2  : BOOL := FALSE;          // 阀 2 单通道复位沿 / Valve 2 channel reset edge
    bRstCh3  : BOOL := FALSE;          // 阀 3 单通道复位沿 / Valve 3 channel reset edge
    bRstCh4  : BOOL := FALSE;          // 阀 4 单通道复位沿 / Valve 4 channel reset edge
END_VAR
VAR_OUTPUT
    uCntCh1  : UDINT;                  // 阀 1 累计动作数 [次] / Valve 1 accumulated cycles
    uCntCh2  : UDINT;                  // 阀 2 累计动作数 [次] / Valve 2 accumulated cycles
    uCntCh3  : UDINT;                  // 阀 3 累计动作数 [次] / Valve 3 accumulated cycles
    uCntCh4  : UDINT;                  // 阀 4 累计动作数 [次] / Valve 4 accumulated cycles
    bMaintCh1: BOOL;                   // 阀 1 维护预警（计数达阈值）/ Valve 1 maintenance warning
    bMaintCh2: BOOL;                   // 阀 2 维护预警（计数达阈值）/ Valve 2 maintenance warning
    bMaintCh3: BOOL;                   // 阀 3 维护预警（计数达阈值）/ Valve 3 maintenance warning
    bMaintCh4: BOOL;                   // 阀 4 维护预警（计数达阈值）/ Valve 4 maintenance warning
    uErrCode : UDINT;                  // 信息级码，0 = 无信息 / Info-level code, 0 = none
    bValid   : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    trigCmd1 : R_TRIG;                 // 阀 1 指令沿检测，每拍无条件刷新 / Valve 1 command edge, refreshed every scan
    trigCmd2 : R_TRIG;                 // 阀 2 指令沿检测，每拍无条件刷新 / Valve 2 command edge, refreshed every scan
    trigCmd3 : R_TRIG;                 // 阀 3 指令沿检测，每拍无条件刷新 / Valve 3 command edge, refreshed every scan
    trigCmd4 : R_TRIG;                 // 阀 4 指令沿检测，每拍无条件刷新 / Valve 4 command edge, refreshed every scan
    trigRst  : R_TRIG;                 // 全组复位沿检测，每拍无条件刷新 / Bank reset edge, refreshed every scan
    trigRst1 : R_TRIG;                 // 阀 1 复位沿检测，每拍无条件刷新 / Valve 1 reset edge, refreshed every scan
    trigRst2 : R_TRIG;                 // 阀 2 复位沿检测，每拍无条件刷新 / Valve 2 reset edge, refreshed every scan
    trigRst3 : R_TRIG;                 // 阀 3 复位沿检测，每拍无条件刷新 / Valve 3 reset edge, refreshed every scan
    trigRst4 : R_TRIG;                 // 阀 4 复位沿检测，每拍无条件刷新 / Valve 4 reset edge, refreshed every scan
END_VAR
VAR CONSTANT
    DL_VCC_MAX     : UDINT := 4294967295; // UDINT 计数上限（饱和不回绕）/ UDINT count ceiling, saturating
    DL_VCC_CODE_SAT: UDINT := 16#0003_0754; // 信息级：计数饱和码 / Info code: count saturated
END_VAR

// ---- 段 1｜沿实例无条件刷新（红线 R7：全部 8 实例不入分支）----
trigCmd1(CLK := bCmdCh1);             // 阀 1 指令沿每拍刷新 / Valve 1 edge refreshed
trigCmd2(CLK := bCmdCh2);             // 阀 2 指令沿每拍刷新 / Valve 2 edge refreshed
trigCmd3(CLK := bCmdCh3);             // 阀 3 指令沿每拍刷新 / Valve 3 edge refreshed
trigCmd4(CLK := bCmdCh4);             // 阀 4 指令沿每拍刷新 / Valve 4 edge refreshed
trigRst(CLK := bRst);                 // 全组复位沿每拍刷新 / Bank reset edge refreshed
trigRst1(CLK := bRstCh1);             // 阀 1 复位沿每拍刷新 / Valve 1 reset edge refreshed
trigRst2(CLK := bRstCh2);             // 阀 2 复位沿每拍刷新 / Valve 2 reset edge refreshed
trigRst3(CLK := bRstCh3);             // 阀 3 复位沿每拍刷新 / Valve 3 reset edge refreshed
trigRst4(CLK := bRstCh4);             // 阀 4 复位沿每拍刷新 / Valve 4 reset edge refreshed

// ---- 段 2｜计数推进：饱和不回绕（信息级留痕，每拍重算）----
IF trigCmd1.Q AND (uCntCh1 < DL_VCC_MAX) THEN
    uCntCh1 := uCntCh1 + 1;           // 阀 1 计数推进 / Valve 1 count advance
END_IF
IF trigCmd2.Q AND (uCntCh2 < DL_VCC_MAX) THEN
    uCntCh2 := uCntCh2 + 1;           // 阀 2 计数推进 / Valve 2 count advance
END_IF
IF trigCmd3.Q AND (uCntCh3 < DL_VCC_MAX) THEN
    uCntCh3 := uCntCh3 + 1;           // 阀 3 计数推进 / Valve 3 count advance
END_IF
IF trigCmd4.Q AND (uCntCh4 < DL_VCC_MAX) THEN
    uCntCh4 := uCntCh4 + 1;           // 阀 4 计数推进 / Valve 4 count advance
END_IF
IF (uCntCh1 = DL_VCC_MAX) OR (uCntCh2 = DL_VCC_MAX)
   OR (uCntCh3 = DL_VCC_MAX) OR (uCntCh4 = DL_VCC_MAX) THEN
    uErrCode := DL_VCC_CODE_SAT;      // 信息级：计数饱和不回绕留痕 / Info: saturation trace, no wrap
END_IF

// ---- 段 3｜复位路径：全组沿 + 单通道沿（锁存声明的清除沿）----
IF trigRst.Q THEN                     // 全组复位沿
    uCntCh1 := 0;                     // 阀 1 计数清零 / Valve 1 count cleared
    uCntCh2 := 0;                     // 阀 2 计数清零 / Valve 2 count cleared
    uCntCh3 := 0;                     // 阀 3 计数清零 / Valve 3 count cleared
    uCntCh4 := 0;                     // 阀 4 计数清零 / Valve 4 count cleared
END_IF
IF trigRst1.Q THEN
    uCntCh1 := 0;                     // 阀 1 单通道清零 / Valve 1 channel clear
END_IF
IF trigRst2.Q THEN
    uCntCh2 := 0;                     // 阀 2 单通道清零 / Valve 2 channel clear
END_IF
IF trigRst3.Q THEN
    uCntCh3 := 0;                     // 阀 3 单通道清零 / Valve 3 channel clear
END_IF
IF trigRst4.Q THEN
    uCntCh4 := 0;                     // 阀 4 单通道清零 / Valve 4 channel clear
END_IF

// ---- 段 4｜维护预警装配：阈值比较瞬时量（随计数回落自动撤销，不锁存）----
bMaintCh1 := uCntCh1 >= uLimitCh1;    // 阀 1 维护预警 / Valve 1 maintenance warning
bMaintCh2 := uCntCh2 >= uLimitCh2;    // 阀 2 维护预警 / Valve 2 maintenance warning
bMaintCh3 := uCntCh3 >= uLimitCh3;    // 阀 3 维护预警 / Valve 3 maintenance warning
bMaintCh4 := uCntCh4 >= uLimitCh4;    // 阀 4 维护预警 / Valve 4 maintenance warning
bValid := TRUE;                       // 台账输出恒可用 / Ledger outputs always usable
END_FUNCTION_BLOCK