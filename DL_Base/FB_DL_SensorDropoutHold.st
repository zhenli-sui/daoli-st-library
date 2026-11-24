(*
  ==================================================================
  组件名 Component  : FB_DL_SensorDropoutHold
  分类   Category   : DL_Base
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 传感器掉线 / 无效拍保持件。输入非有限（双判据）时冻结输出
                      为最近一次有效值并出保持电平与保持时长；保持超窗后输出仍
                      保持但置陈旧级（不回零，防下游联锁误动）；首拍无历史值时
                      输出安全侧 0 并置 bNoValid。
  来源   Source     : t1-oscat（借鉴 OSCAT 库域外行为显式化纪律：失能 / 无效 /
                      首扫三类域外拍的出口语义逐条声明，clean-room 自研实现，
                      未复制 OSCAT 任何源码行）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_SignalStagnationWatch 分工——呆滞件监视有效值
                      不动，本件处理无效值保持；与 FB_DL_NtcTempScan 分工——
                      扫描件决定有效性，本件只按有效性保持，超窗口径与
                      NtcTempScan 一致（保持不回零 + 置级）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 无效判据 = 非有限双判据（x<>x 判 NaN，x-x<>x-x 判 Inf）；
                      二 首拍无历史值：输出 0.0 + bNoValid，不进保持路径；
                      三 保持超窗：输出保持末次有效值但 bStale 置级（R191 显式
                         声明：不回 0，防联锁误动）；
                      四 失能拍：输出直通原始值（域外行为显式化，R191）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fValueOut 为保持后输出；bHolding 为掉线保持电平；
                      bNoValid 为无历史有效值指示；bStale 为超窗陈旧级
                      （保持不回零口径）；tHoldTime 为已保持时长。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 1 · 序号 5）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_SensorDropoutHold
VAR_INPUT
    fValueIn : LREAL := 0.0;   // 传感器原始输入 [工程单位] / the raw sensor input [engineering unit]
    tHoldWin : TIME := T#2S;   // 保持窗宽 [毫秒]，超窗转陈旧级 / the hold window [millisecond], beyond it the stale grade
    bEnable  : BOOL := TRUE;   // 使能，失能直通原始值 [-] / enable, disabling passes the raw value through
    bReset   : BOOL := FALSE;  // 复位上升沿清历史值与保持状态 [-] / reset rising edge clears the history and the hold state
END_VAR
VAR_OUTPUT
    fValueOut  : LREAL := 0.0; // 保持后的输出 [工程单位] / the held output [engineering unit]
    bHolding   : BOOL := FALSE; // 掉线保持中电平 [-] / the dropout hold level
    bNoValid   : BOOL := FALSE; // 无历史有效值指示（首拍或复位后）[-] / no valid history indicator
    bStale     : BOOL := FALSE; // 保持超窗陈旧级 [-] / the stale grade beyond the window
    tHoldTime  : TIME := T#0S; // 已保持时长 [毫秒] / the held duration [millisecond]
    bError     : BOOL := FALSE; // 故障标志，本件无锁存故障恒为假 [-] / the fault flag, no latched fault, always false
END_VAR
VAR
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    tonHold : TON;    // 保持窗计时，段 0 无条件刷新 / the hold timer, refreshed unconditionally
    _bInit    : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan flag
    _bHaveVal : BOOL := FALSE; // 历史有效值存在标记 [-] / the valid history flag
    _fHold    : LREAL := 0.0;  // 最近有效值保持量 [工程单位] / the last valid value holder [engineering unit]
    _bValid   : BOOL := FALSE; // 本拍输入有效判定 [-] / the input validity verdict this scan
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonHold(IN := _bHaveVal AND (NOT _bValid) AND bEnable, PT := tHoldWin); // 保持窗，IN 串有历史 / 无效 / 使能三重闸 / the hold timer with a triple gate

// 段 1｜首扫初始化（R310）：无历史值，输出安全侧 0 + bNoValid / segment 1, first scan, no history
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit    := TRUE; // 置首扫标志 / raise the flag
    _bHaveVal := FALSE; // 无历史有效值 / no valid history
    fValueOut := 0.0; // 输出安全侧 0 / the outlet to the safe zero
    bNoValid  := TRUE; // 置无有效值指示 / raise the no valid indicator
END_IF

// 段 2｜复位沿作用域：清历史值 / 清保持与陈旧（三项逐项声明）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bHaveVal := FALSE; // 作用域一：清历史值标记 / scope one, clear the history flag
    bHolding  := FALSE; // 作用域二：清保持电平 / scope two, clear the hold level
    bStale    := FALSE; // 作用域二：清陈旧级 / scope two, clear the stale grade
END_IF

// 段 3｜输入有效性判定（双判据，边界一）/ segment 3, the input validity verdict
_bValid := (fValueIn = fValueIn) AND ((fValueIn - fValueIn) = (fValueIn - fValueIn)); // 非有限双判据 / the dual finiteness criteria

// 段 4｜有效拍：值更新 / 状态归位 / segment 4, the valid scan, the value updates
IF bEnable AND _bValid THEN // 使能且有效 / enabled and valid
    _fHold    := fValueIn; // 刷新最近有效值 / refresh the last valid value
    _bHaveVal := TRUE; // 置历史标记 / raise the history flag
    fValueOut := fValueIn; // 输出直通有效值 / the outlet passes the valid value
    bHolding  := FALSE; // 清保持电平 / clear the hold level
    bStale    := FALSE; // 清陈旧级 / clear the stale grade
    bNoValid  := FALSE; // 清无有效值指示 / clear the no valid indicator
END_IF

// 段 5｜无效拍：保持或无历史安全侧 / segment 5, the invalid scan, hold or the safe side
IF bEnable AND (NOT _bValid) THEN // 使能但无效 / enabled but invalid
    IF _bHaveVal THEN // 有历史值 / with history
        fValueOut := _fHold; // 输出保持末次有效值（超窗也不回零，边界三）/ the outlet holds the last valid value, never zeroed beyond the window
        bHolding  := TRUE; // 置保持电平 / raise the hold level
        bStale    := tonHold.Q; // 超窗置陈旧级 / the stale grade beyond the window
    ELSE // 无历史值（首拍或复位后即无效）/ without history
        fValueOut := 0.0; // 输出安全侧 0（边界二）/ the outlet to the safe zero
        bNoValid  := TRUE; // 置无有效值指示 / raise the no valid indicator
        bHolding  := FALSE; // 无保持 / no hold
        bStale    := FALSE; // 无陈旧 / no stale
    END_IF
END_IF

// 段 6｜失能拍：直通原始值（域外行为显式，边界四）/ segment 6, the disabled scan passes the raw value through
IF NOT bEnable THEN // 失能 / disabled
    fValueOut := fValueIn; // 直通原始值（含非有限值，由调用方闸后）/ the raw passthrough, the caller gates non finite values
    bHolding  := FALSE; // 清保持电平 / clear the hold level
    bStale    := FALSE; // 清陈旧级 / clear the stale grade
    _bHaveVal := FALSE; // 清历史标记（恢复使能后重新建立）/ clear the history flag, rebuilt after re-enabling
END_IF

// 段 7｜统一出口 / segment 7, the unified outlet
tHoldTime := tonHold.ET; // 已保持时长出口 / the held duration outlet
bError := FALSE; // 本件无锁存故障，恒为假 / no latched fault, always false
END_FUNCTION_BLOCK
