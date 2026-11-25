(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PeakHoldFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / TIME_TO_REAL），零厂商私有库
 * 功能描述 (Function)   : 峰值保持（peak hold）。持续跟踪输入最大值；保持时长 tHoldTime
 *                         内无新的更高峰值即自动回落（回落到当前输入值），随后转为跟随输入。
 *                         典型用途：液压冲击峰值记录、张力瞬时峰值捕获、压力尖峰监测。
 *                         保持计时用 TON 事件重启式：每当新峰值出现，本拍把 TON 的 IN
 *                         强制为 FALSE 一拍，TON 内部 ET/Q 即复位（比外部清零更稳，
 *                         不依赖调用方沿信号）；其余拍 IN = bHolding。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 复位峰值、fIn 采样输入 [EU]、
 *                         tHoldTime 峰值保持时长 [s]；
 *                         输出 fPeak 保持峰值 [EU]、bHolding 是否处于保持期、
 *                         tHoldElapsed 已保持时长 [s]、bValid 输出有效、bError、uErrorId。
 * 边界     (Boundary)   : ① 属主边界：只做峰值保持，不做峰值-时间戳归档（另件）。
 *                         ② 非有限输入 → 进故障态冻结输出，uErrorId=16#0004_0002；
 *                         恢复路径：bEnable=FALSE 或 bReset=TRUE。
 *                         ③ tHoldTime < 0 判参数非法（TIME 无负值语义，钳到 T#0S 并置信息码
 *                         16#0004_0001）；tHoldTime = T#0S 表示不保持，逐拍跟随输入。
 *                         ④ **TON 无条件每周期调用**（R7）：位于 CASE 之外的段 3，
 *                         与状态机解耦，任何状态下计时器都被刷新。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_HoldLastGoodFilter` 分工：坏值保持归那件、
 *                         峰值保持归本件；与 `FB_DL_RateOfChangeFilter` 分工：斜率限幅归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0004_0000 无故障 / 16#0004_0001 保持时长非法已钳位（信息级）/
 *                         16#0004_0002 输入非有限（故障级）/ 16#0004_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限拒绝 + 时长域闸 + 无除法 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 ✓ TON 实例 CASE 外无条件刷新
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 10）
 * 验收向量 (Acceptance) : ① tHoldTime=T#1S，输入 5.0 后降到 3.0 → fPeak 保持 5.0，
 *                         bHolding=TRUE；保持期满后 fPeak 回落到 3.0；
 *                         ② bReset=TRUE 一拍 → fPeak 立即等于当前 fIn，bHolding=TRUE；
 *                         ③ tHoldTime=T#0S → 逐拍跟随输入，fPeak = fIn（不保持）；
 *                         ④ fIn=Inf → uErrorId=16#0004_0002，bError=TRUE，fPeak 冻结；
 *                         ⑤ bEnable=FALSE → fPeak 冻结，bValid=FALSE，计时器照常刷新。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PeakHoldState（峰值保持状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PeakHoldState :
(
    eInit  := 0,    // 首扫 / 复位后：峰值取当前输入 / First scan or after reset: peak equals input
    eRun   := 10,   // 运行态：捕获更高峰并重启保持计时 / Running: capture higher peaks and restart timer
    eHold  := 20,   // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen until cleared
);
END_TYPE

FUNCTION_BLOCK FB_DL_PeakHoldFilter
VAR_INPUT
    bEnable   : BOOL := FALSE;      // 使能，FALSE 冻结峰值 / Enable, FALSE freezes the peak
    bReset    : BOOL := FALSE;      // 复位峰值到当前输入（单拍有效） / Reset peak to current input, single scan
    fIn       : LREAL := 0.0;       // 采样输入 [EU] / Sampling input [EU]
    tHoldTime : TIME := T#1S;       // 峰值保持时长，T#0S = 不保持 [s] / Peak hold duration, zero means follow
END_VAR
VAR_OUTPUT
    fPeak        : LREAL;   // 保持峰值 [EU] / Held peak [EU]
    bHolding     : BOOL;    // 是否处于保持期 [-] / Whether inside the hold window
    tHoldElapsed : TIME;    // 已保持时长 [s] / Elapsed hold duration
    bValid       : BOOL;    // 输出有效标志 [-] / Output valid flag
    bError       : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId     : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    tonHold  : TON;                 // 峰值保持计时器（无条件每周期刷新） / Peak hold timer, refreshed unconditionally
    _bRstPul : BOOL;                // 新峰值事件脉冲（本拍重启计时） [-] / New-peak event pulse for timer restart
    _bNewPk  : BOOL;                // 本拍出现更高峰 [-] / Higher peak appeared this scan
    eState   : E_DL_PeakHoldState;  // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_PHF_ZERO_L : LREAL := 0.0;   // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_PHF_ZERO_T : TIME := T#0S;   // 时长零基准 [s] / Zero duration base
END_VAR

(* —— 段 1：参数域闸（时长非负；TIME 无负值，仍显式判等以防方言差异） —— *)
uErrorId := 16#0004_0000;                          // 预置无故障 / Preset healthy
IF tHoldTime < DL_PHF_ZERO_T THEN
    tHoldTime := DL_PHF_ZERO_T;                    // 负时长钳到零 / Negative duration clamped to zero
    uErrorId  := 16#0004_0001;                     // 信息级：保持时长已钳位 / Info: hold duration clamped
END_IF

(* —— 段 2：非有限输入防御（进故障态冻结输出） —— *)
IF (fIn <> fIn) OR ((fIn - fIn) <> DL_PHF_ZERO_L) THEN
    eState   := eFault;                            // 强制故障态 / Force fault state
    uErrorId := 16#0004_0002;                      // 故障级：输入非有限 / Fault: non-finite input
END_IF

(* —— 段 3：新峰值检测与计时器重启脉冲（仅在使能且运行态有效） —— *)
_bNewPk  := FALSE;                                 // 每拍清零事件位 / Clear event flag every scan
_bRstPul := FALSE;
IF bEnable AND (eState <> eFault) THEN
    IF fIn > fPeak THEN
        _bNewPk  := TRUE;                          // 出现更高峰 / Higher peak detected
        _bRstPul := TRUE;                          // 本拍强制 TON 的 IN=FALSE 以复位 ET/Q / Force timer reset
    END_IF
END_IF

(* —— 段 4：复位请求 → 回首扫（峰值对齐当前输入） —— *)
IF bReset THEN
    eState := eInit;
END_IF

(* —— 段 5：状态派生 —— *)
IF NOT bEnable THEN
    eState := eHold;                               // 未使能：冻结 / Disabled: freeze
ELSIF eState = eFault THEN
    eState := eFault;                              // 故障态保持 / Fault holds
ELSIF eState = eInit THEN
    eState := eInit;                               // 首扫保持一拍 / Init holds one scan
ELSE
    eState := eRun;
END_IF

(* —— 段 6：计时器无条件每周期刷新（R7 硬要求，位于 CASE 之外） —— *)
(* IN 在「使能 且 处于保持中 且 本拍无新峰」时为 TRUE；新峰拍强制 FALSE 完成复位 *)
(* IN is TRUE only when enabled, holding, and no new peak this scan; a new peak forces FALSE to reset *)
tonHold(IN := bEnable AND (eState <> eFault) AND (NOT _bRstPul), PT := tHoldTime);

(* —— 段 7：主状态机（CASE 覆盖 + ELSE 兜底） —— *)
CASE eState OF

    eInit:
        fPeak        := fIn;                       // 峰值对齐当前输入 / Align peak with input
        bHolding     := TRUE;                      // 进入保持期 / Enter hold window
        tHoldElapsed := tonHold.ET;
        bValid       := TRUE;
        eState       := eRun;

    eRun:
        IF _bNewPk THEN
            fPeak := fIn;                          // 捕获更高峰 / Capture higher peak
        ELSIF tonHold.Q THEN
            fPeak := fIn;                          // 保持期满：回落到当前输入 / Hold expired: fall back to input
        END_IF
        bHolding     := NOT tonHold.Q;             // 期满后不再处于保持期 / No longer holding after expiry
        tHoldElapsed := tonHold.ET;
        bValid       := TRUE;

    eHold:
        (* 未使能：峰值与计时保持冻结，恢复使能后继续 / Disabled: peak and timer frozen *)
        tHoldElapsed := tonHold.ET;
        bValid       := FALSE;

    eFault:
        (* 故障态：峰值冻结（不推 0，避免下游误判），计时器仍刷新 / Fault: peak frozen, timer still refreshed *)
        tHoldElapsed := tonHold.ET;
        bValid       := FALSE;

    ELSE
        eState   := eFault;
        bValid   := FALSE;
        uErrorId := 16#0004_0005;                  // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 8：出口映射（bError 与 uErrorId 同源；信息级 16#0004_0001 不置 bError） —— *)
bError := (uErrorId <> 16#0004_0000) AND (uErrorId <> 16#0004_0001);

END_FUNCTION_BLOCK
