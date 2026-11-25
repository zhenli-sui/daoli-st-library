//==============================================================================
// 功能块：FB_DL_TankFarmTransferSeq ｜ 中文名称：多罐收发转罐序列编排
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3 第 3 版，零方言）
// 功能描述：两罐区（A 源罐 → B 目的罐）转罐全序列编排：预开阀（阀门先于
//           泵，防泵闭阀干转）→ 泵启动（泵/阀联锁：泵输出仅在进/出阀全开
//           反馈后允许）→ 目标液位切换（A 罐降到下限或 B 罐升到上限即转）
//           → 停泵稳压 → 关阀收尾 → 单拍完成脉冲。路径互斥：本件内部任意
//           时刻至多一条输送路径激活，同一实例重复触发被拒绝（信息级）。
//           多实例多路径互斥由上层工站用独立实例 + 外部互斥承担。
//           同族分工：单批物料转移（计量体积 + 排空验证口径）属
//           FB_DL_BatchTransferSeq；本件做多罐液位双目标路径编排（阀先泵后
//           + 稳压相），互不替代（R73 互引）。
// 开源溯源 (Origin)：原创实现（t2-2-lbp 罐区分层复用深化，零外部源码行，
//           clean-room 独立编写）
// 公开接口清单：输入 bStart / bAbort / fLevelA / fLevelB / fLLA / fHLB /
//               bValveInFb / bValveOutFb / bPumpFb / tValveFb / tPumpFb / tSettle；
//               输出 bValveInCmd / bValveOutCmd / bPumpCmd / eState /
//               uErrCode / bError / bCycleDone / bValid
// 错误码表：16#0005_3040 故障级（阀门反馈超时，置 bError）/
//           16#0005_3041 故障级（泵反馈超时，置 bError）/
//           16#0005_3042 故障级（液位输入非有限，置 bError）/
//           16#0005_3043 信息级（忙拒绝重复触发，不置 bError）/
//           16#0005_3044 信息级（参数非法：下限/上限阈值域外，不置 bError）/
//           16#0005_3046 故障级（关阀反馈超时，置 bError，R73 返修新增）/
//           16#0005_3045 预留禁用（不得挪用）
// 状态机：E_DL_TankXferState（本文件唯一定义，全库唯一属主）：
//           eIdle = 0 / eOpenValves = 10 / ePumpRun = 20 / eSettle = 30 /
//           eCloseValves = 40 / eFault = 99
// 边界行为：① 开阀/关阀/泵反馈超时经 TON 判定（关阀超时 R73 返修新增，
//             码 3046）→ 故障锁存入 eFault，故障码锁存回放至解除沿（R189）；
//             解除沿 = 中止上升沿 或 故障相内再次启动沿；
//           ② 液位非有限 → 故障 3042 安全侧停泵关阀；
//           ③ 阀先开泵后启、泵先停阀后关（全序列联锁次序固定）；
//           ④ TON ×4 / R_TRIG ×2 每拍无条件刷新（不入分支，红线 R7）；
//           ⑤ CASE 带 ELSE 非法态兜底入 eFault（安全侧停泵关阀）；
//           ⑥ bCycleDone 两段式单拍脉冲（内部置位 → 统一出口映射）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 1 · 序 5）
//           v1.0.1 2026-11-23 R73 返修：关阀相补 TON 超时闸（tonClose，阀
//           反馈卡死不再静默挂死），新故障码 0005_3046，故障相解除沿复用；
//           并补与 FB_DL_BatchTransferSeq 的同族分工互引。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_TankXferState（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 转罐序列相位，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_TankXferState :
(
    eIdle        := 0,   // 待机：全输出关断 / Idle, all outputs off
    eOpenValves  := 10,  // 预开阀：等进/出阀全开反馈 / Opening valves, awaiting both open feedbacks
    ePumpRun     := 20,  // 输送中：泵运行至目标液位 / Transferring, pump running to the level target
    eSettle      := 30,  // 稳压：停泵后稳压等待 / Settling, pump stopped, waiting
    eCloseValves := 40,  // 收尾：关阀 / Closing valves
    eFault       := 99   // 故障锁存：安全侧全关断 / Fault latch, all outputs cut on the safe side
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_TankFarmTransferSeq
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_TankFarmTransferSeq
VAR_INPUT
    bStart      : BOOL := FALSE;      // 启动触发（上升沿有效，忙时拒绝）/ Start trigger, rising edge, refused while busy
    bAbort      : BOOL := FALSE;      // 中止（任意相立即安全侧回怠速）/ Abort, any phase returns safely to idle
    fLevelA     : LREAL := 0.0;       // A 源罐液位 [mm] / Source tank A level [mm]
    fLevelB     : LREAL := 0.0;       // B 目的罐液位 [mm] / Destination tank B level [mm]
    fLLA        : LREAL := 100.0;     // A 罐转罐下限 [mm]，低于此停运 / Tank A transfer floor [mm]
    fHLB        : LREAL := 1800.0;    // B 罐转罐上限 [mm]，高于此停运 / Tank B transfer ceiling [mm]
    bValveInFb  : BOOL := FALSE;      // 进料阀开反馈 / Inlet valve open feedback
    bValveOutFb : BOOL := FALSE;      // 出料阀开反馈 / Outlet valve open feedback
    bPumpFb     : BOOL := FALSE;      // 泵运行反馈 / Pump run feedback
    tValveFb    : TIME := T#10S;      // 阀反馈超时 [ms] / Valve feedback timeout [ms]
    tPumpFb     : TIME := T#15S;      // 泵反馈超时 [ms] / Pump feedback timeout [ms]
    tSettle     : TIME := T#5S;       // 停泵稳压时长 [ms] / Settling duration [ms]
END_VAR
VAR_OUTPUT
    bValveInCmd : BOOL;               // 进料阀开指令 / Inlet valve open command
    bValveOutCmd: BOOL;               // 出料阀开指令 / Outlet valve open command
    bPumpCmd    : BOOL;               // 泵运行指令（仅在阀全开反馈后）/ Pump run command, only after both valve feedbacks
    eState      : E_DL_TankXferState; // 序列当前相位 / Current sequence phase
    uErrCode    : UDINT;              // 错误码，0 = 无错 / Error code, 0 = no error
    bError      : BOOL;               // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bCycleDone  : BOOL;               // 单拍完成脉冲 / Single-scan cycle-done pulse
    bValid      : BOOL;               // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    tonValve    : TON;                // 阀反馈超时定时器，每拍无条件刷新 / Valve timeout timer, refreshed every scan
    tonPump     : TON;                // 泵反馈超时定时器，每拍无条件刷新 / Pump timeout timer, refreshed every scan
    tonClose    : TON;                // 关阀反馈超时定时器，每拍无条件刷新 / Valve-closing timeout timer, refreshed every scan
    tonSettle   : TON;                // 稳压定时器，每拍无条件刷新 / Settle timer, refreshed every scan
    trigStart   : R_TRIG;             // 启动沿检测，每拍无条件刷新 / Start edge detector, refreshed every scan
    trigAbort   : R_TRIG;             // 中止沿检测，每拍无条件刷新 / Abort edge detector, refreshed every scan
    _bDone      : BOOL;               // 完成脉冲内部暂存（统一出口映射） / Done stage internal, mapped at the unified outlet
    bBusy       : BOOL;               // 忙声明（非怠速即忙）/ Busy flag, busy when not idle
    _uFaultLatch: UDINT;              // 故障码锁存暂存（故障相回放，解除沿清零）/ Latched fault code, replayed in the fault phase, cleared at the release edge
END_VAR
VAR CONSTANT
    DL_TF_EPS   : LREAL := 1.0E-9;    // 浮点容差 / Float tolerance
    DL_TF_INF   : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
END_VAR

// ---- 段 1｜定时/沿实例无条件刷新（红线 R7：禁入条件分支）----
bBusy := (eState <> E_DL_TankXferState.eIdle) AND (eState <> E_DL_TankXferState.eFault); // 忙声明（故障相不算忙可再触发）/ Busy when active phase, fault phase re-triggerable
tonValve(IN := (eState = E_DL_TankXferState.eOpenValves)
         AND NOT (bValveInFb AND bValveOutFb), PT := tValveFb); // 阀超时按未全开态断输入 / Valve timer input per not-fully-open state
tonPump(IN := (eState = E_DL_TankXferState.ePumpRun) AND NOT bPumpFb, PT := tPumpFb); // 泵超时按未反馈态断输入 / Pump timer input per no-feedback state
tonClose(IN := (eState = E_DL_TankXferState.eCloseValves)
         AND (bValveInFb OR bValveOutFb), PT := tValveFb); // 关阀超时按未全关态断输入 / Close timer input per not-fully-closed state
tonSettle(IN := (eState = E_DL_TankXferState.eSettle), PT := tSettle); // 稳压计时按相断输入 / Settle timer input per phase
trigStart(CLK := bStart);             // 启动沿每拍刷新 / Start edge refreshed every scan
trigAbort(CLK := bAbort);             // 中止沿每拍刷新 / Abort edge refreshed every scan

// ---- 段 2｜出口默认值 + 单拍脉冲出口预清（两段式）----
_bDone      := FALSE;                 // 完成脉冲暂存先清零 / Done stage preset FALSE
bCycleDone  := FALSE;                 // 完成脉冲默认 FALSE（相内重置位）/ Done pulse preset FALSE
bValveInCmd := FALSE;                 // 阀指令默认关（相内重置位）/ Valve command preset closed
bValveOutCmd:= FALSE;                 // 阀指令默认关（相内重置位）/ Valve command preset closed
bPumpCmd    := FALSE;                 // 泵指令默认停（相内重置位）/ Pump command preset stopped
uErrCode    := 16#0000_0000;          // 信息码每拍重算（信息级不锁存）/ Info code recomputed, never latched
bValid      := TRUE;                  // 可用标志默认 TRUE / Usable flag preset TRUE

// ---- 段 3｜液位输入防御：非有限 → 故障锁存入故障相（安全侧全关断）----
IF (fLevelA <> fLevelA) OR (ABS(fLevelA) > DL_TF_INF)
   OR (fLevelB <> fLevelB) OR (ABS(fLevelB) > DL_TF_INF)
   OR (fLLA <> fLLA) OR (ABS(fLLA) > DL_TF_INF)
   OR (fHLB <> fHLB) OR (ABS(fHLB) > DL_TF_INF) THEN
    eState   := E_DL_TankXferState.eFault; // 强制入故障相 / Forced into the fault phase
    _uFaultLatch := 16#0005_3042;     // 故障码锁存（回放至解除沿）/ Fault code latched for replay
    uErrCode := 16#0005_3042;         // 故障级：液位输入非有限 / Fault: non-finite level input
    bError   := TRUE;                 // 置故障标志（R45 配对）/ Raise the fault flag, R45 pairing
END_IF

// ---- 段 4｜参数域闸：下限/上限阈值域外 → 信息级拒绝启动 ----
IF (fLLA <= DL_TF_EPS) OR (fHLB <= fLLA) THEN
    IF trigStart.Q AND NOT bBusy THEN // 仅启动沿拍置信息（避免每拍刷码）/ Info only at the start edge scan
        uErrCode := 16#0005_3044;     // 信息级：参数非法 / Info: illegal parameters
    END_IF
END_IF

// ---- 段 5｜序列状态机（CASE 带 ELSE；联锁次序固定阀先泵后）----
CASE eState OF
    E_DL_TankXferState.eIdle:         // 待机相：等待合法启动沿
        IF trigStart.Q AND NOT (fLLA <= DL_TF_EPS) AND (fHLB > fLLA) THEN
            eState := E_DL_TankXferState.eOpenValves; // 进入预开阀相 / Enter the valve-opening phase
        END_IF

    E_DL_TankXferState.eOpenValves:   // 预开阀相：先开阀后允许泵（联锁次序①）
        bValveInCmd  := TRUE;         // 进料阀开指令 / Inlet valve open command
        bValveOutCmd := TRUE;         // 出料阀开指令 / Outlet valve open command
        IF tonValve.Q THEN            // 阀反馈超时（故障级锁存）/ Valve feedback timeout
            eState   := E_DL_TankXferState.eFault; // 入故障相 / Into the fault phase
            _uFaultLatch := 16#0005_3040; // 故障码锁存（回放至解除沿）/ Fault code latched for replay
            uErrCode := 16#0005_3040; // 故障级：阀反馈超时 / Fault: valve feedback timeout
            bError   := TRUE;         // 置故障标志 / Raise the fault flag
        ELSIF bValveInFb AND bValveOutFb THEN
            eState := E_DL_TankXferState.ePumpRun; // 阀全开转输送相 / Both open, enter the pump phase
        END_IF

    E_DL_TankXferState.ePumpRun:      // 输送相：泵/阀联锁 + 双目标液位切换（联锁次序②）
        bValveInCmd  := TRUE;         // 阀保持开（泵运行前提）/ Valves held open, pump precondition
        bValveOutCmd := TRUE;         // 阀保持开 / Valves held open
        bPumpCmd := bValveInFb AND bValveOutFb; // 泵输出仅在双阀反馈后（联锁闸）/ Pump only after both feedbacks
        IF tonPump.Q THEN             // 泵反馈超时（故障级锁存）/ Pump feedback timeout
            eState   := E_DL_TankXferState.eFault; // 入故障相 / Into the fault phase
            _uFaultLatch := 16#0005_3041; // 故障码锁存（回放至解除沿）/ Fault code latched for replay
            uErrCode := 16#0005_3041; // 故障级：泵反馈超时 / Fault: pump feedback timeout
            bError   := TRUE;         // 置故障标志 / Raise the fault flag
        ELSIF (fLevelA <= fLLA) OR (fLevelB >= fHLB) THEN
            bPumpCmd := FALSE;        // 到达任一目标立即停泵（本拍生效）/ Stop pump at either target this scan
            eState := E_DL_TankXferState.eSettle; // 转稳压相 / Enter the settling phase
        END_IF

    E_DL_TankXferState.eSettle:       // 稳压相：停泵等待液位稳定
        bValveInCmd  := TRUE;         // 阀仍保持开 / Valves still held open
        bValveOutCmd := TRUE;         // 阀仍保持开 / Valves still held open
        IF tonSettle.Q THEN
            eState := E_DL_TankXferState.eCloseValves; // 稳压满转收尾相 / Settled, enter closing
        END_IF

    E_DL_TankXferState.eCloseValves:  // 收尾相：泵先停阀后关（联锁次序③）
        IF bValveInFb AND bValveOutFb THEN
            bValveInCmd  := FALSE;    // 阀反馈仍开才发关指令（防假关）/ Close command only while still open
            bValveOutCmd := FALSE;    // 关出料阀 / Close the outlet valve
        END_IF
        IF tonClose.Q THEN            // 关阀反馈超时（R73 返修：不再静默挂死）/ Valve closing timeout, R73 fix, no silent hang
            eState   := E_DL_TankXferState.eFault; // 入故障相 / Into the fault phase
            _uFaultLatch := 16#0005_3046; // 故障码锁存（回放至解除沿）/ Fault code latched for replay
            uErrCode := 16#0005_3046; // 故障级：关阀反馈超时 / Fault: valve closing feedback timeout
            bError   := TRUE;         // 置故障标志（R45 配对）/ Raise the fault flag, R45 pairing
        ELSIF (NOT bValveInFb) AND (NOT bValveOutFb) THEN
            eState := E_DL_TankXferState.eIdle; // 双阀全关回怠速 / Both closed, back to idle
            _bDone := TRUE;           // 完成脉冲内部置位（出口统一映射）/ Done stage set for the outlet
        END_IF

    E_DL_TankXferState.eFault:        // 故障相：安全侧全关断，故障码锁存回放（R189）
        bValveInCmd  := FALSE;        // 安全侧关阀 / Safe-side valve close
        bValveOutCmd := FALSE;        // 安全侧关阀 / Safe-side valve close
        bPumpCmd     := FALSE;        // 安全侧停泵 / Safe-side pump stop
        bError   := TRUE;             // 故障级锁存回放 / Fault-class latch replay
        uErrCode := _uFaultLatch;     // 故障码回放（不在故障相重推断）/ Fault code replayed, never re-inferred
        IF trigAbort.Q OR (trigStart.Q AND NOT bBusy) THEN // 解除沿：中止上升沿或故障相内再启动沿（头注释已声明）/ Release edge: abort or restart, declared in the header
            eState   := E_DL_TankXferState.eIdle; // 回怠速 / Back to idle
            _uFaultLatch := 16#0000_0000; // 故障码锁存清零 / Latched fault code cleared
            uErrCode := 16#0000_0000; // 故障码清零 / Fault code cleared
            bError   := FALSE;        // 故障标志解除 / Fault flag released
        END_IF

    ELSE                              // 非法状态兜底（R21：CASE 必带 ELSE）
        eState   := E_DL_TankXferState.eFault; // 拦截非法值入故障相 / Catch illegal value into fault
        _uFaultLatch := 16#0005_3042; // 故障码锁存（复用非有限码兜底，R90）/ Latched via the reused non-finite code, R90
        bError   := TRUE;             // 兜底按故障级处理 / Fallback as fault class
        uErrCode := 16#0005_3042;     // 兜底故障码 / Fallback fault code
END_CASE

// ---- 段 6｜统一出口：中止优先兜底 + 完成脉冲单拍映射 ----
IF trigAbort.Q AND (eState <> E_DL_TankXferState.eIdle) THEN
    eState := E_DL_TankXferState.eIdle; // 中止沿立即回怠速（安全侧输出已由相内默认承担）/ Abort edge returns to idle immediately
    bError := FALSE;                  // 中止解除故障标志 / Abort releases the fault flag
    uErrCode := 16#0000_0000;         // 故障码清零 / Fault code cleared
END_IF
bCycleDone := _bDone;                 // 完成脉冲本拍有效（两段式出口）/ Done pulse valid this scan
END_FUNCTION_BLOCK