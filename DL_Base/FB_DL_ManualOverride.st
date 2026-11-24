(*
  道莅工业代码库 | DL_Base | FB_DL_ManualOverride
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: brOscatLib (github.com/brOscatLib) / MIT / 借鉴 MANUAL 覆写的语义，代码为 clean-room 重写
  功能: 手动强制覆写——覆写请求上升沿激活后输出切手动值，最长保持 tMaxHold
        （T#0S = 无限时）超时自动回落自动值；释放沿/禁止输入即时回落；
        激活单拍提示脉冲与超时回落信息码。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG / SEL，零厂商私有库
  接口: 输入 bOverrideReq（沿）/bRelease（沿）/fAutoVal/fManualVal/tMaxHold/
        bInhibit/bReset；输出 bOverride/bOut/bActPulse/bTimedOut/eState/eInfo/nErrId。
  码表: 16#0001_04BC 信息级：覆写超时自动回落（锁存至复位沿）
        16#0001_04BD 信息级：覆写请求被禁止拒绝（当拍重算）
        16#0001_04BE 信息级：覆写中手动值非有限（输出保持最后有效值，当拍重算）
        码段说明：0001 段信息子带 04xx，槽位经全库实扫空闲。
  边界: ① 手动值 NaN 拒绝激活（待机相判码），覆写中手动值变 NaN → 输出保持
        最后有效值并置信息码（冻结语义不穿透坏值）；
        ② bInhibit 在覆写中即时回落自动值（禁止优先于覆写，安全侧）；
        ③ 超时判定仅当 tMaxHold > T#0S 生效（T#0S = 无限保持）；
        ④ TON/R_TRIG 段 0 无条件周期刷新；⑤ 本件全部事件均为信息级，无故障级码；
        ⑥ 零全局耦合。
  邻件比对: ToleranceWindow（单容差窗）与本件无语义交集；S04 E_DL_ControlModeSel
            为本件模式语义配套枚举（后续入库）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B3 · C11）
*)

TYPE E_DL_MovState :
(
    eIdle    := 0,   // 覆写未激活（输出自动值） | Override inactive, output auto value
    eActive  := 10   // 覆写激活（输出手动值） | Override active, output manual value
);
END_TYPE

TYPE E_DL_MovInfo :
(
    eNone      := 0,  // 无事件 | No event
    eTimeout   := 1,  // 超时自动回落（锁存至复位沿） | Timed out, auto fallback latched
    eInhibit   := 2,  // 请求被禁止拒绝（当拍重算） | Request rejected by inhibit
    eNonFinite := 3   // 手动值非有限（当拍重算，输出保持） | Manual value non-finite, output held
);
END_TYPE

FUNCTION_BLOCK FB_DL_ManualOverride
VAR_INPUT
    bOverrideReq : BOOL := FALSE;   // 覆写请求（上升沿激活）[-] | Override request, rising edge activates
    bRelease     : BOOL := FALSE;   // 释放请求（上升沿回落）[-] | Release request, rising edge falls back
    fAutoVal     : REAL := 0.0;     // 自动值 [工程单位] | Auto value
    fManualVal   : REAL := 0.0;     // 手动值（覆写目标）[工程单位] | Manual value, override target
    tMaxHold     : TIME := T#30S;   // 最长覆写保持，T#0S = 无限 | Max hold duration, T#0S = unlimited
    bInhibit     : BOOL := FALSE;   // 覆写禁止（电平，覆写中即时回落）[-] | Override inhibit level
    bReset       : BOOL := FALSE;   // 复位命令，上升沿清超时锁存 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    bOverride : BOOL;               // 覆写激活态 [-] | Override active state
    fOut      : REAL;               // 选择输出（自动/手动/保持值）[工程单位] | Selected output value
    bActPulse : BOOL;               // 激活单拍提示脉冲 [-] | Activation one-shot pulse
    bTimedOut : BOOL;               // 超时回落锁存标志 [-] | Timed-out latch flag
    eState    : E_DL_MovState;      // 状态出口 | State outlet
    eInfo     : E_DL_MovInfo;       // 事件成因出口 | Event cause outlet
    nErrId    : UDINT;              // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _eState    : E_DL_MovState := E_DL_MovState.eIdle;   // 内部状态（CASE 唯一写入目标） | Internal state
    _eInfo     : E_DL_MovInfo := E_DL_MovInfo.eNone;     // 事件成因锁存（超时级） | Latched event cause
    _bOverride : BOOL;          // 覆写激活锁存位 | Override active latch bit
    _bTimedOut : BOOL;          // 超时回落锁存位 | Timed-out latch bit
    _bHold     : BOOL;          // 输出保持当拍量（手动值非有限）[-] | Output hold this scan
    _fOutLast  : REAL := 0.0;   // 最后有效输出保持值 [工程单位] | Last valid output hold value
    _bNonFin   : BOOL;          // 手动值非有限当拍量 [-] | Manual value non-finite this scan
    _uInfo     : UDINT;         // 信息码每拍重算 | Info code per scan
    rtReq      : R_TRIG;        // 覆写请求沿实例，段 0 无条件刷新 | Override request edge instance
    rtRel      : R_TRIG;        // 释放沿实例，段 0 无条件刷新 | Release edge instance
    rtReset    : R_TRIG;        // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    rtAct      : R_TRIG;        // 激活沿实例（单拍提示），段 0 无条件刷新 | Activation edge instance for one-shot
    tonHold    : TON;           // 覆写保持计时，段 0 无条件刷新 | Override hold timer
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bNonFin := (fManualVal <> fManualVal);                                     // 手动值 NaN 自反判 / Manual value NaN self-reflex check
rtReq(CLK := bOverrideReq);                                                 // 请求沿每拍必调 / Request edge every scan
rtRel(CLK := bRelease);                                                     // 释放沿每拍必调 / Release edge every scan
rtReset(CLK := bReset);                                                     // 复位沿每拍必调 / Reset edge every scan
rtAct(CLK := _bOverride);                                                   // 激活态沿（单拍提示用）每拍必调 / Activation edge for one-shot
tonHold(IN := (_eState = E_DL_MovState.eActive) AND (tMaxHold > T#0S), PT := tMaxHold);  // 保持计时，IN 挂激活 ∧ 有限时限 / Hold timer gated by active and finite limit

(* —— 段 1：复位沿清超时锁存 —— *)
IF rtReset.Q THEN
    _bTimedOut := FALSE;                                                    // 清超时锁存位 / Clear timed-out latch
    _eInfo := E_DL_MovInfo.eNone;                                           // 清成因锁存 / Clear latched cause
END_IF

(* —— 段 2：状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF

E_DL_MovState.eIdle:
    IF rtReq.Q AND bInhibit THEN
        _uInfo := 16#0001_04BD;                                             // 信息级：请求被禁止拒绝 / Info: request rejected by inhibit
    ELSIF rtReq.Q AND _bNonFin THEN
        _uInfo := 16#0001_04BE;                                             // 信息级：手动值非有限拒绝激活 / Info: non-finite manual refused
    ELSIF rtReq.Q THEN
        _bOverride := TRUE;                                                 // 激活覆写锁存 / Activate override latch
        _eState := E_DL_MovState.eActive;                                   // 进入激活相 / Enter active phase
    END_IF

E_DL_MovState.eActive:
    IF rtRel.Q THEN
        _bOverride := FALSE;                                                // 释放沿回落 / Release edge falls back
        _eState := E_DL_MovState.eIdle;
    ELSIF bInhibit THEN
        _bOverride := FALSE;                                                // 禁止输入即时回落（安全侧优先，边界②）/ Inhibit forces fallback
        _eState := E_DL_MovState.eIdle;
    ELSIF tonHold.Q THEN
        _bOverride := FALSE;                                                // 超时回落 / Timed out, fall back
        _bTimedOut := TRUE;                                                 // 超时锁存（复位沿清）/ Latch timeout
        _eInfo := E_DL_MovInfo.eTimeout;                                    // 归因超时 / Cause: timeout
        _eState := E_DL_MovState.eIdle;
    END_IF

ELSE
    _eState := E_DL_MovState.eIdle;                                         // 非法状态兜底（R6，回落安全侧）/ Illegal state fallback to safe side
    _bOverride := FALSE;                                                    // 非法态覆写强制撤 / Override forced off

END_CASE

(* —— 段 3：出口单点映射（名实同源；选择 + 保持 + 锁存码回放） —— *)
IF _bOverride AND _bNonFin THEN
    _bHold := TRUE;                                                         // 覆写中手动值变坏：保持当拍置位（边界①）/ Manual went bad while active, hold
    _uInfo := 16#0001_04BE;                                                 // 信息级：手动值非有限 / Info: manual non-finite
ELSE
    _bHold := FALSE;                                                        // 正常拍不保持 / No hold on normal scan
END_IF
IF (NOT _bHold) AND (NOT (_bOverride AND _bNonFin)) THEN
    _fOutLast := fManualVal;                                                // 有效拍刷新保持值（手动值载体）/ Refresh hold value on valid manual
END_IF
bOverride := _bOverride;                                                    // 覆写态镜像 / Override mirror
IF _bOverride AND _bNonFin THEN
    fOut := _fOutLast;                                                      // 坏值拍输出保持值（冻结语义）/ Bad-value scan outputs held value
ELSIF _bOverride THEN
    fOut := fManualVal;                                                     // 覆写输出手动值 / Override outputs manual value
ELSE
    fOut := fAutoVal;                                                       // 未覆写输出自动值 / Idle outputs auto value
END_IF
bActPulse := rtAct.Q;                                                       // 激活单拍提示（R_TRIG 单拍化） / Activation one-shot
bTimedOut := _bTimedOut;                                                    // 超时锁存镜像 / Timeout latch mirror
eState := _eState;                                                          // 状态出口 / State outlet
eInfo := _eInfo;                                                            // 成因出口 / Cause outlet
IF _bTimedOut THEN
    nErrId := 16#0001_04BC;                                                 // 超时回落锁存码回放（最高优先）/ Replay timeout code
ELSIF _uInfo <> 16#0000_0000 THEN
    nErrId := _uInfo;                                                       // 当拍信息码 / Per-scan info code
ELSE
    nErrId := 16#0000_0000;                                                 // 无事件 / No event
END_IF

END_FUNCTION_BLOCK
