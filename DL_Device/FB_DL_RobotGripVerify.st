//==============================================================================
// 功能块：FB_DL_RobotGripVerify ｜ 中文名称：机械手夹持确认与掉片判据
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：机械手取放夹持确认——按夹持模式（真空/夹爪/双确认）校验
//           反馈组合，确认窗满才置 bGripVerified；已确认后反馈丢失超窗
//           判掉片疑似并累计计数；释放沿后反馈粘连监测。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现
// 单位表：反馈/命令[—]／确认窗[ms]／掉片计数[次]
// 错误码表：16#0003_0180 信息级（释放沿后确认窗内反馈仍 TRUE，粘连疑似，
//           不置 bError）/ 16#0003_0181 预留禁用（不得挪用）/
//           16#0003_0351 故障级（已确认后反馈丢失超窗，掉片疑似，置
//           bError）/ 16#0003_0352 预留禁用（不得挪用）/ 16#0003_0353
//           故障级兜底（夹持模式枚举非法或状态机落 ELSE，置 bError）
// 状态机：E_DL_GripMode（eVacuum=0 / eClamp=1 / eDualConfirm=2）为输入
//           模式枚举（本文件唯一定义，全库唯一属主）；本件主体无相位
//           状态机（确认/掉片/粘连三窗并行判定，纯电平逻辑 + 边沿单发）
// 边界行为：① 已确认后反馈丢失 > 确认窗 → bDropSuspect 置位 + uDropCount
//           递增 + 故障 0351（R45 配对）；掉片计数按事件沿单发递增，
//           不按电平重复计数；② eDualConfirm 模式双反馈缺一 → 不确认
//           （保守侧）；③ 释放沿后 200 ms 内反馈仍 TRUE → 信息 0180
//           （粘连疑似，不置故障）；④ 枚举非法 → 故障 0353 兜底；
//           ⑤ uDropCount 饱和 4294967295 不回绕。
// 依赖纪律：仅 Standard.library（TON/R_TRIG/F_TRIG）；零同层/跨层调用。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 半导体 P1 §372 + 自研线）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_GripMode（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 夹持反馈校验模式，决定 bGripVerified 的判据组合。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_GripMode :
(
    eVacuum      := 0,  // 真空模式：仅 bVacOk 参与确认 / Vacuum mode, only bVacOk participates
    eClamp       := 1,  // 夹爪模式：仅 bClampOk 参与确认 / Clamp mode, only bClampOk participates
    eDualConfirm := 2   // 双确认模式：bVacOk 与 bClampOk 须同时成立 / Dual-confirm mode, both feedbacks required
);
END_TYPE

FUNCTION_BLOCK FB_DL_RobotGripVerify
VAR_INPUT
    bVacOk      : BOOL;                     // 真空反馈 [—] / Vacuum feedback
    bClampOk    : BOOL;                     // 夹爪反馈 [—] / Clamp feedback
    eGripMode   : E_DL_GripMode;            // 夹持模式 [—] / Grip mode
    bGripCmd    : BOOL;                     // 夹持命令 [—]，电平有效 / Grip command, level active
    bReleaseCmd : BOOL;                     // 释放命令 [—]，电平有效 / Release command, level active
    tConfirmTime: TIME := T#200MS;          // 确认窗 [ms]，兼作掉片/粘连判窗 / Confirmation window [ms], also the drop and stick window
    bReset      : BOOL;                     // 故障复位 [—]，上升沿清掉片锁存 / Fault reset, rising edge clears the drop latch
END_VAR
VAR_OUTPUT
    bGripVerified : BOOL;                   // 夹持已确认 [—] / Grip verified
    bDropSuspect  : BOOL;                   // 掉片疑似 [—]，已确认后反馈丢失 / Drop suspected, feedback lost after confirmation
    uDropCount    : UDINT;                  // 掉片累计 [次]，饱和 4294967295 不回绕 / Cumulative drops [count], saturated at 4294967295
    eErr          : UDINT;                  // 错误码，0 = 无错 / Error code, 0 = no error
    bError        : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbConfirm   : TON;                      // 夹持确认窗，段 6 无条件刷新 [ms] / Grip confirmation window
    fbDrop      : TON;                      // 掉片判窗（确认后反馈丢失），段 6 无条件刷新 [ms] / Drop window, feedback lost after confirmation
    fbStick     : TON;                      // 粘连判窗（释放沿后反馈保持），段 6 无条件刷新 [ms] / Stick window, feedback held after release
    rtDrop      : R_TRIG;                   // 掉片判窗满上升沿（计数单发），段 6 无条件刷新 / Drop window-full rising edge, one-shot counting
    rtStick     : R_TRIG;                   // 粘连判窗满上升沿（信息单发），段 6 无条件刷新 / Stick window-full rising edge, one-shot info
    _bCond      : BOOL;                     // 本拍模式判据组合结果 [—] / Mode criteria result of this scan
    _bVerifiedAcc: BOOL;                    // 已确认保持量（掉片判据基准） / Held verified flag, the drop-criterion base
    _bDropLatch : BOOL;                     // 掉片疑似锁存（bReset 清除） / Held drop-suspect latch, cleared by bReset
    _bStickInfo : BOOL;                     // 粘连信息单发保持量（当拍销毁） / One-shot stick info holder, destroyed the same scan
    _bInit      : BOOL := FALSE;            // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bModeBad   : BOOL;                     // 模式枚举非法标志 / Illegal mode flag
    _bReleaseEdge: BOOL;                    // 释放沿单拍标志 / One-scan release edge flag
    _bReleaseEdgeDone: BOOL;                // 释放命令上拍电平快照（沿检测基准） / Previous-scan level snapshot of the release command
END_VAR
VAR CONSTANT
    DL_GRIP_STICK   : TIME := T#200MS;      // 粘连判窗 [ms]，释放沿后反馈仍 TRUE 的窗 / Stick window [ms] after the release edge
    DL_GRIP_CNT_MAX : UDINT := 4294967295;  // 掉片计数饱和上限 [次] / Drop counter saturation ceiling [count]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先算后出，单拍标志预清零（R25 第一律：只置必销）
 *      Outputs computed per scan, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bGripVerified := FALSE;                     // 确认输出每拍重算 / Verified output recomputed
bDropSuspect  := FALSE;                     // 掉片输出每拍重算 / Drop output recomputed
eErr          := 16#0000_0000;              // 错误码每拍重算 / Error code recomputed
bError        := FALSE;                     // 故障标志每拍重算 / Fault flag recomputed
bValid        := FALSE;                     // 可用标志每拍重算 / Usable flag recomputed
_bCond        := FALSE;                     // 模式判据预清零 / Mode criteria pre-cleared
_bReleaseEdge := FALSE;                     // 释放沿预清零 / Release edge pre-cleared
_bStickInfo   := FALSE;                     // 粘连单发预清零 / Stick one-shot pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _bVerifiedAcc := FALSE;                 // 确认保持量清零 / Verified holder cleared
    _bDropLatch   := FALSE;                 // 掉片锁存清零 / Drop latch cleared
    uDropCount    := 0;                     // 掉片计数清零 / Drop counter cleared
    _bReleaseEdgeDone := FALSE;             // 释放电平快照首扫清零（此后跨拍保持） / Release snapshot cleared on the first scan, held afterwards
    _bInit        := TRUE;                  // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜模式判据组合（CASE 含 ELSE 兜底 → 0353）
 *      Mode criteria combination with the ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eGripMode OF
    E_DL_GripMode.eVacuum:                  // 真空模式：仅真空反馈 / Vacuum mode: vacuum feedback only
        _bCond := bVacOk;                   // 判据组合 / Criteria combination
    E_DL_GripMode.eClamp:                   // 夹爪模式：仅夹爪反馈 / Clamp mode: clamp feedback only
        _bCond := bClampOk;                 // 判据组合 / Criteria combination
    E_DL_GripMode.eDualConfirm:             // 双确认模式：双反馈须同时成立（缺一不确认，保守侧）
        _bCond := bVacOk AND bClampOk;      // 判据组合 / Criteria combination
    ELSE                                    // 枚举非法兜底 / Illegal enum fallback
        _bModeBad := TRUE;                  // 标记模式非法 / Flag the illegal mode
END_CASE

(*------------------------------------------------------------------------------
 * 段 4｜释放沿单发（当拍置位、当拍销毁，不跨周期驻留）
 *      Release edge one-shot, set and destroyed within the same scan
 *-----------------------------------------------------------------------------*)
IF bReleaseCmd AND (NOT _bReleaseEdgeDone) THEN
    _bReleaseEdge := TRUE;                  // 释放沿成立 / Release edge active
END_IF
_bReleaseEdgeDone := bReleaseCmd;           // 电平快照供下一拍比较 / Level snapshot for the next-scan comparison

(*------------------------------------------------------------------------------
 * 段 5｜三窗无条件刷新（R40：CASE 之外每拍必调，各司其职不复用）
 *      Three windows refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbConfirm(IN := bGripCmd AND _bCond AND (NOT bReleaseCmd), PT := tConfirmTime); // 夹持确认窗 / Grip confirmation window
fbDrop(IN := _bVerifiedAcc AND (NOT _bCond), PT := tConfirmTime);               // 掉片判窗 / Drop window
fbStick(IN := _bReleaseEdge AND _bCond, PT := DL_GRIP_STICK);                   // 粘连判窗 / Stick window
rtDrop(CLK := fbDrop.Q);                    // 掉片判窗满上升沿 / Drop window-full edge
rtStick(CLK := fbStick.Q);                  // 粘连判窗满上升沿 / Stick window-full edge

(*------------------------------------------------------------------------------
 * 段 6｜判定与锁存：确认保持 / 掉片单发计数 / 粘连单发信息
 *      Verdicts and latches
 *-----------------------------------------------------------------------------*)
IF rtStick.Q THEN
    _bStickInfo := TRUE;                    // 粘连信息单发置位（本拍销毁） / Stick info one-shot, destroyed this scan
END_IF
IF rtDrop.Q AND (NOT bReleaseCmd) THEN
    _bDropLatch := TRUE;                    // 掉片疑似锁存 / Drop suspect latched
    IF uDropCount < DL_GRIP_CNT_MAX THEN
        uDropCount := uDropCount + 1;       // 掉片计数递增（饱和不回绕） / Drop counter increment, saturated without wrap
    END_IF
END_IF
IF bGripCmd AND _bCond AND (NOT bReleaseCmd) THEN
    _bVerifiedAcc := TRUE;                  // 确认保持量置位 / Verified holder set
ELSIF (NOT bGripCmd) OR bReleaseCmd THEN
    _bVerifiedAcc := FALSE;                 // 命令撤销或释放，保持量清零 / Command dropped or release, holder cleared
END_IF
IF bReset THEN
    _bDropLatch := FALSE;                   // 复位清掉片锁存（计数不清，留痕） / Reset clears the drop latch, the counter is kept for traceability
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出与码位出口
 *      Outputs and the code outlet
 *-----------------------------------------------------------------------------*)
bGripVerified := _bVerifiedAcc AND _bCond;  // 确认输出 = 保持量与当拍判据同时成立 / Verified = holder and current criteria both hold
bDropSuspect  := _bDropLatch;               // 掉片输出 = 锁存 / Drop output = latch

IF _bModeBad THEN
    eErr   := 16#0003_0353;                 // 故障级：模式枚举非法兜底 / Fault: illegal mode enum fallback
    bError := TRUE;                         // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                        // 输出不可用 / Outputs unusable
ELSIF _bDropLatch THEN
    eErr   := 16#0003_0351;                 // 故障级：掉片疑似 / Fault: drop suspected
    bError := TRUE;                         // 置故障标志 / Raise the fault flag
    bValid := TRUE;                         // 判定结果本身可用（掉片是有效结论） / The verdict itself is usable
ELSIF _bStickInfo THEN
    eErr := 16#0003_0180;                   // 信息级：释放后粘连疑似（不置 bError） / Info: stick suspected after release, no fault flag
    bValid := TRUE;                         // 输出可用 / Outputs usable
ELSE
    bValid := TRUE;                         // 正常输出可用 / Outputs usable
END_IF
END_FUNCTION_BLOCK
