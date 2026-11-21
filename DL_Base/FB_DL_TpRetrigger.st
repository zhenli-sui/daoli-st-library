(*
  ==================================================================
  组件名 Component  : FB_DL_TpRetrigger
  分类   Category   : DL_Base
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 可重触发 TP 脉冲定时变体。触发上升沿启动脉冲窗；窗内再次
                      触发沿刷新脉冲（ET 归零重启窗宽，不叠加）；窗满自动回空闲。
                      PT 钳位非负；PT=0 时 Q 为单扫描周期脉冲且 ET=0；首扫无假触发。
  来源   Source     : iec-std-wrapper（T0）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；内部委托标准 TON /
                      R_TRIG，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_PulseStretch 分工——PulseStretch 为不可重触发的
                      脉宽拉伸（首沿后窗内再沿被忽略）；本件为可重触发 TP（窗内
                      沿刷新 ET 重启窗宽），两者语义互斥，勿混用。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 PT 负值按信息级钳到 T#0S 执行，不锁存（每拍重算）；
                      二 重触发只刷新 ET 重启窗，不叠加窗宽；
                      三 首扫 Q 初值 FALSE，无假触发；
                      四 PT=0 时 Q 单拍脉冲且 ET=0；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      bQ 为脉冲电平（PT=0 时退化为单拍）；bWindow 为窗活动
                      指示；tEt 为窗内流逝时间（触发拍恒为 0）；uErrorId /
                      bError 为信息级（每拍重算非锁存），锁存语义为零。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 1 · 序号 1）
  ==================================================================
*)

TYPE E_DL_TprPhase :
(
    eIdle  := 0,  // 空闲：无脉冲窗 / idle, no pulse window
    ePulse := 10  // 脉冲窗：窗内触发沿可重触发刷新 / pulse window, an edge inside refreshes the retrigger
);
END_TYPE

FUNCTION_BLOCK FB_DL_TpRetrigger
VAR_INPUT
    bTrig      : BOOL;            // 触发输入，上升沿启动或重触发 [-] / trigger input, a rising edge starts or retriggers
    tPulseTime : TIME := T#1S;    // 脉冲宽度 [毫秒]，负值按信息级钳零 / pulse width [millisecond], negatives clamp to zero as informational
    bEnable    : BOOL := TRUE;    // 使能，失能即清窗 [-] / enable, disabling clears the window
    bReset     : BOOL := FALSE;   // 复位上升沿清脉冲窗 [-] / reset rising edge clears the pulse window
END_VAR
VAR_OUTPUT
    bQ       : BOOL := FALSE;  // 脉冲输出 [-] / the pulse output
    bWindow  : BOOL := FALSE;  // 重触发窗活动指示 [-] / the retrigger window active indicator
    tEt      : TIME := T#0S;   // 窗内已流逝时间 [毫秒] / elapsed time inside the window [millisecond]
    uErrorId : UDINT := 0;     // 信息级码，0 = 正常 / informational code, zero is ok
    bError   : BOOL := FALSE;  // 信息级错误标志（每拍重算，非锁存）/ informational flag, recomputed each scan, not latched
END_VAR
VAR
    rtTrig   : R_TRIG; // 触发沿检测，段 0 无条件刷新 / the trigger edge, refreshed unconditionally in segment zero
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally in segment zero
    tonPulse : TON;    // 脉冲窗定时器，段 0 无条件刷新 / the pulse window timer, refreshed unconditionally
    _ePhase  : E_DL_TprPhase := E_DL_TprPhase.eIdle; // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _bActive : BOOL := FALSE; // 窗活动保持位 [-] / the window activity holder
    _tPt     : TIME := T#0S;  // 钳位后的脉冲宽度 [毫秒] / the clamped pulse width [millisecond]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）；触发拍 IN 串 NOT rtTrig.Q 实现
//        单拍低电平使 TON 重启（重触发刷新 ET 的机制本体）/ segment 0, unconditional
//        refresh; the trigger scan gates IN low for one scan so the TON restarts,
//        which is the mechanism refreshing ET on a retrigger
rtTrig(CLK := bTrig); // 触发沿 / the trigger edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonPulse(IN := _bActive AND (NOT rtTrig.Q) AND bEnable, PT := _tPt); // 脉冲窗，IN 串窗活动闸与触发拍重启闸 / the pulse window with the activity and restart gates

// 段 1｜PT 钳位非负（信息级，每拍重算不锁存）/ segment 1, PT clamped nonnegative, informational and recomputed
IF tPulseTime < T#0S THEN // 负宽度 / a negative width
    _tPt     := T#0S; // 钳到零 / clamp to zero
    uErrorId := 16#0001_0001; // 信息级：PT 负值已钳零 / informational, a negative PT clamped to zero
    bError   := TRUE; // 置信息级标志 / raise the informational flag
ELSE // 域内 / inside the domain
    _tPt     := tPulseTime; // 直通 / passthrough
    uErrorId := 16#0000_0000; // 正常码 / the ok code
    bError   := FALSE; // 信息级标志清零 / clear the informational flag
END_IF

// 段 2｜复位沿作用域：清窗保持位与相位（两项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bActive := FALSE; // 作用域一：清窗保持位 / scope one, clear the activity holder
    _ePhase  := E_DL_TprPhase.eIdle; // 作用域二：回空闲相 / scope two, back to idle
END_IF

// 段 3｜失能门控：清窗回空闲（域外行为显式，R191）/ segment 3, the disable gate, declared explicitly
IF NOT bEnable THEN // 失能 / disabled
    _bActive := FALSE; // 清窗保持位 / clear the activity holder
    _ePhase  := E_DL_TprPhase.eIdle; // 回空闲相 / back to idle
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine with an ELSE fallback
CASE _ePhase OF

E_DL_TprPhase.eIdle: // 空闲相：等触发沿 / the idle phase, waiting for the trigger edge
    IF bEnable AND rtTrig.Q THEN // 触发沿受理（首扫沿检测自然为假，无假触发）/ the edge is accepted, no false trigger on the first scan
        _bActive := TRUE; // 开窗 / raise the window
        _ePhase  := E_DL_TprPhase.ePulse; // 迁脉冲窗相 / migrate to the pulse phase
    END_IF

E_DL_TprPhase.ePulse: // 脉冲窗相：窗内沿已在段 0 重启 TON，这里只管窗满 / the pulse phase, the restart happened in segment zero, only the expiry is handled here
    IF tonPulse.Q THEN // 窗满到期 / the window expired
        _bActive := FALSE; // 关窗 / clear the window
        _ePhase  := E_DL_TprPhase.eIdle; // 回空闲相 / back to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bActive := FALSE; // 关窗 / clear the window
    _ePhase  := E_DL_TprPhase.eIdle; // 回空闲相 / back to idle
    uErrorId := 16#0001_0005; // 信息级：非法相位 / informational, an illegal phase
    bError   := TRUE; // 置信息级标志 / raise the informational flag
END_CASE

// 段 5｜统一出口：触发拍 TON 已被单拍低电平复位，故 ET=0 且 Q 立即为真 / segment 5,
//        the unified outlet; the TON was one-scan reset on the trigger scan, so ET is zero and Q rises at once
bQ      := _bActive AND (NOT tonPulse.Q) AND bEnable; // 脉冲出口（PT=0 时恰为单拍脉冲）/ the pulse outlet, a one-scan pulse when PT is zero
bWindow := _bActive AND bEnable; // 窗活动指示 / the window indicator
tEt     := tonPulse.ET; // 已流逝时间出口 / the elapsed time outlet
END_FUNCTION_BLOCK
