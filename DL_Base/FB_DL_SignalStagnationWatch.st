(*
  ==================================================================
  组件名 Component  : FB_DL_SignalStagnationWatch
  分类   Category   : DL_Base
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 信号呆滞（卡死）检测。双判据持续 tStall 判呆滞：
                      ① 值纹波消失——相邻拍变化量 |Δ| ≤ fEps 持续；
                      ② 伴生活动信号边沿计数归零——活动观测窗内零边沿。
                      两判据同时成立才出呆滞电平与单拍事件。
  来源   Source     : iec-std-wrapper（T0）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；呆滞双判据为公开
                      诊断语义，clean-room 自研实现，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_SignalDebounce 分工——Debounce 是（抑制）件
                      （吸收毛刺防误动），本件是（检出）件（发现信号呆滞
                      疑点），方向相反、互不替代；与 FB_DL_SensorDropoutHold
                      分工——掉线保持件处理无效值，本件处理有效但不动值。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 fEps 为显式纹波死区参数，组态闸要求 > 0（信息级）；
                      二 tStall 期间边沿计数窗独立自复位（R188：IN := NOT Q），
                         与呆滞计时互不牵连；
                      三 使能断开即复位：计时清零、窗计数清零、出口回假，
                         不锁存（每拍重算）；
                      四 首扫快照取当拍，无假呆滞（tonStall 从零起步）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 1 · 序号 4）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_SignalStagnationWatch
VAR_INPUT
    fValue    : LREAL := 0.0;    // 被监视值 [工程单位] / the monitored value [engineering unit]
    bActivity : BOOL := FALSE;   // 伴生活动信号（如传感器自检翻转）[-] / the companion activity signal
    fEps      : LREAL := 0.01;   // 纹波死区 [工程单位]，域 大于零 / the ripple deadband [engineering unit], above zero
    tStall    : TIME := T#10S;   // 呆滞确认窗 [毫秒] / the stall confirm window [millisecond]
    tEdgeWin  : TIME := T#5S;    // 边沿观测窗 [毫秒] / the edge observation window [millisecond]
    bEnable   : BOOL := TRUE;    // 使能，失能即复位不锁存 [-] / enable, disabling resets without latching
    bReset    : BOOL := FALSE;   // 复位上升沿清计数 [-] / reset rising edge clears the counters
END_VAR
VAR_OUTPUT
    bStalled    : BOOL := FALSE; // 呆滞电平出口（双判据同时成立）[-] / the stalled level outlet, both criteria met
    bStallEvent : BOOL := FALSE; // 呆滞进入单拍事件 [-] / the stall entry one-scan event
    nRippleCnt  : UDINT := 0;    // 纹波事件累计 [次] / the ripple event count [count]
    nActWinCnt  : UDINT := 0;    // 当前观测窗内活动边沿计数 [次] / the activity edge count in the current window [count]
    uErrorId    : UDINT := 0;    // 信息级码，0 = 正常 / informational code, zero is ok
    bError      : BOOL := FALSE; // 信息级错误标志（每拍重算）/ informational flag, recomputed each scan
END_VAR
VAR
    rtReset : R_TRIG;  // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    rtAct   : R_TRIG;  // 活动信号沿检测，段 0 无条件刷新 / the activity edge, refreshed unconditionally
    rtStall : R_TRIG;  // 呆滞电平沿检测，段 0 无条件刷新 / the stalled level edge, refreshed unconditionally
    tonStall: TON;     // 呆滞确认窗，段 0 无条件刷新 / the stall confirm timer, refreshed unconditionally
    tonWin  : TON;     // 边沿观测窗（自复位），段 0 无条件刷新 / the observation window, self resetting, refreshed unconditionally
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ first scan flag
    _fPrev  : LREAL := 0.0;  // 上拍值快照 [工程单位] / previous scan value snapshot [engineering unit]
    _bRipple: BOOL := FALSE; // 本拍纹波事件标记（上拍值供段 0 判据闸使用）/ the ripple flag this scan, the last value feeds the segment zero gate
    _bCfgOk : BOOL := FALSE; // 组态域内 [-] / the configuration inside the domain
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）；观测窗自复位（R188）/ segment 0, unconditional refresh, the window self resetting
rtReset(CLK := bReset); // 复位沿 / the reset edge
rtAct(CLK := bActivity); // 活动沿 / the activity edge
rtStall(CLK := bStalled); // 呆滞电平沿 / the stalled level edge
tonStall(IN := _bCfgOk AND bEnable AND (NOT _bRipple) AND (rtAct.Q = FALSE) AND (nActWinCnt = 0), PT := tStall); // 呆滞窗，IN 串双判据闸 / the stall timer gated by both criteria
tonWin(IN := bEnable AND (NOT tonWin.Q), PT := tEdgeWin); // 观测窗自复位循环（R188）/ the self resetting observation loop

// 段 1｜首扫初始化（R310）：快照取当拍防假呆滞 / segment 1, first scan, the snapshot takes this scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
    _fPrev := fValue; // 快照取当拍 / the snapshot takes this scan
END_IF

// 段 2｜复位沿作用域：清计数（出口电平随计时自清，无需另清）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    nRippleCnt := 0; // 清纹波计数 / clear the ripple counter
    nActWinCnt := 0; // 清窗计数 / clear the window counter
END_IF

// 段 3｜组态域闸（信息级，每拍重算）/ segment 3, the configuration gate, informational
_bCfgOk := (fEps > 0.0) AND (fEps = fEps) AND ((fEps - fEps) = (fEps - fEps)) AND (tStall > T#0S) AND (tEdgeWin > T#0S); // 死区与窗域判定 / the deadband and window verdict
IF NOT _bCfgOk THEN // 组态非法 / an illegal configuration
    uErrorId := 16#0001_0001; // 信息级：组态越域 / informational, a config violation
    bError   := TRUE; // 置信息级标志 / raise the flag
ELSE // 域内 / inside the domain
    uErrorId := 16#0000_0000; // 正常码 / the ok code
    bError   := FALSE; // 清标志 / clear the flag
END_IF

// 段 4｜双判据量测 / segment 4, the dual criteria measurement
_bRipple := ABS(fValue - _fPrev) > fEps; // 纹波判据（变化量超死区）/ the ripple verdict beyond the deadband
IF _bRipple THEN // 纹波事件 / a ripple event
    nRippleCnt := nRippleCnt + 1; // 纹波计数推进 / advance the ripple counter
    IF nRippleCnt = 4294967295 THEN // UDINT 上界防回绕 / the wrap guard
        nRippleCnt := 4294967294; // 钳在次上界 / clamp below the ceiling
    END_IF
END_IF
IF rtAct.Q THEN // 活动沿 / an activity edge
    nActWinCnt := nActWinCnt + 1; // 窗内计数推进 / advance the window counter
END_IF
IF tonWin.Q THEN // 观测窗到期：窗计数独立归零重开（边界二）/ the window expired, the counter reset independently
    nActWinCnt := 0; // 窗计数归零 / the window counter zeroed
END_IF
IF NOT bEnable THEN // 失能即复位不锁存（边界三）/ disabled resets without latching
    nRippleCnt := 0; // 清纹波计数 / clear the ripple counter
    nActWinCnt := 0; // 清窗计数 / clear the window counter
END_IF

// 段 5｜统一出口：双判据电平 + 进入事件 / segment 5, the unified outlet
bStalled := _bCfgOk AND bEnable AND tonStall.Q AND (nActWinCnt = 0); // 双判据电平 / the dual criteria level
bStallEvent := rtStall.Q; // 进入单拍事件（沿检测已无条件刷新）/ the entry one-scan event
IF NOT bEnable THEN // 失能拍出口回假 / the disabled scan forces false
    bStalled := FALSE; // 电平回假 / the level false
    bStallEvent := FALSE; // 事件回假 / the event false
END_IF
_fPrev := fValue; // 快照推进（无条件）/ the snapshot advances unconditionally
END_FUNCTION_BLOCK
