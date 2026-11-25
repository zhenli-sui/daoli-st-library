(*
  Component : FB_DL_DieSprayReleaseSeq
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 喷涂脱模剂时序控制：ENUM 七态（Idle/Open/Spray/Blow/Close/Done/Fault），按设定喷涂次数循环喷涂-吹扫，末次吹扫后关模。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 喷涂次数须 >= 1、四段时长均须非 0，否则拒绝启动并锁存故障码；
              ② 喷涂计数在喷涂段迁出拍单点累加，不在段内每拍累加；
              ③ 故障锁存唯一解除路径 = bReset 上升沿；eDone 撤销 bStart 回 eIdle。
*)

TYPE E_DL_SprayPhase :
(
    eIdle  := 0,    (* 空闲：等启动沿 / Idle waiting start edge *)
    eOpen  := 10,   (* 开模：开模动作 / Die opening *)
    eSpray := 20,   (* 喷涂：单次喷涂 / Single spray shot *)
    eBlow  := 30,   (* 吹扫：残液吹扫 / Air blow-off *)
    eClose := 40,   (* 关模：关模动作 / Die closing *)
    eDone  := 50,   (* 完成：驻留待撤销 / Done holding *)
    eFault := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_DieSprayReleaseSeq
VAR_INPUT
    bEnable   : BOOL;   (* 使能电平 [-] Enable level *)
    bReset    : BOOL;   (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart    : BOOL;   (* 启动上升沿 [-] Start edge *)
    nSpraySet : INT;    (* 设定喷涂次数 [次] Spray shot count setpoint *)
    tOpen     : TIME;   (* 开模动作时长 [ms] Die opening duration *)
    tSpray    : TIME;   (* 单次喷涂时长 [ms] Spray shot duration *)
    tBlow     : TIME;   (* 吹扫时长 [ms] Air blow duration *)
    tClose    : TIME;   (* 关模动作时长 [ms] Die closing duration *)
END_VAR
VAR_OUTPUT
    bOpenCmd   : BOOL;               (* 开模指令 [-] Die open command *)
    bSprayCmd  : BOOL;               (* 喷涂指令 [-] Spray command *)
    bBlowCmd   : BOOL;               (* 吹扫指令 [-] Air blow command *)
    bCloseCmd  : BOOL;               (* 关模指令 [-] Die close command *)
    nSprayDone : INT;                (* 已完成喷涂次数 [次] Completed spray shots *)
    ePhase     : E_DL_SprayPhase;    (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bError     : BOOL;               (* 故障锁存标志 [-] Fault latch flag *)
    uErrId     : UDINT;              (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart  : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonOpen  : TON;      (* 开模动作计时（独立实例） / Open timer *)
    tonSpray : TON;      (* 喷涂计时（独立实例） / Spray timer *)
    tonBlow  : TON;      (* 吹扫计时（独立实例） / Blow timer *)
    tonClose : TON;      (* 关模动作计时（独立实例） / Close timer *)
    _ePhase  : E_DL_SprayPhase := E_DL_SprayPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStart);
tonOpen (IN := (_ePhase = E_DL_SprayPhase.eOpen)  AND (NOT _bFault), PT := tOpen);
tonSpray(IN := (_ePhase = E_DL_SprayPhase.eSpray) AND (NOT _bFault), PT := tSpray);
tonBlow (IN := (_ePhase = E_DL_SprayPhase.eBlow)  AND (NOT _bFault), PT := tBlow);
tonClose(IN := (_ePhase = E_DL_SprayPhase.eClose) AND (NOT _bFault), PT := tClose);

(* —— 段 1｜每拍量预清零（锁存量 _bFault/_uFault/nSprayDone 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，喷涂计数清零 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    nSprayDone := 0;
    _ePhase := E_DL_SprayPhase.eIdle;
END_IF

(* —— 段 3｜组态闸：喷涂次数与四段时长全覆盖 —— *)
IF (nSpraySet < 1) OR (tOpen = T#0S) OR (tSpray = T#0S) OR (tBlow = T#0S) OR (tClose = T#0S) THEN
    _bCfgBad := TRUE;
END_IF

(* —— 段 4｜主状态机：七态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_SprayPhase.eIdle:
    bOpenCmd := FALSE; bSprayCmd := FALSE; bBlowCmd := FALSE; bCloseCmd := FALSE;
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) THEN
        nSprayDone := 0;
        _ePhase := E_DL_SprayPhase.eOpen;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad) THEN
        _bFault := TRUE;                 (* 带病启动拒绝 / Reject start with bad config *)
        _uFault := 16#0025_0001;
        _ePhase := E_DL_SprayPhase.eFault;
    END_IF

E_DL_SprayPhase.eOpen:
    bOpenCmd := TRUE; bSprayCmd := FALSE; bBlowCmd := FALSE; bCloseCmd := FALSE;
    IF tonOpen.Q THEN
        _ePhase := E_DL_SprayPhase.eSpray;   (* 迁出条件 1：开模到位 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SprayPhase.eIdle;    (* 迁出条件 2：使能撤销回安全态 *)
    END_IF

E_DL_SprayPhase.eSpray:
    bOpenCmd := TRUE; bSprayCmd := TRUE; bBlowCmd := FALSE; bCloseCmd := FALSE;
    IF tonSpray.Q THEN
        nSprayDone := nSprayDone + 1;        (* 次数在迁出拍单点累加 *)
        _ePhase := E_DL_SprayPhase.eBlow;    (* 迁出条件 1：单次喷涂完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SprayPhase.eIdle;    (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_SprayPhase.eBlow:
    bOpenCmd := TRUE; bSprayCmd := FALSE; bBlowCmd := TRUE; bCloseCmd := FALSE;
    IF tonBlow.Q THEN
        IF nSprayDone < nSpraySet THEN
            _ePhase := E_DL_SprayPhase.eSpray;   (* 次数未达：重复喷涂-吹扫 *)
        ELSE
            _ePhase := E_DL_SprayPhase.eClose;   (* 迁出条件 1：次数达成转关模 *)
        END_IF
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SprayPhase.eIdle;        (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_SprayPhase.eClose:
    bOpenCmd := FALSE; bSprayCmd := FALSE; bBlowCmd := FALSE; bCloseCmd := TRUE;
    IF tonClose.Q THEN
        _ePhase := E_DL_SprayPhase.eDone;    (* 迁出条件 1：关模到位 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_SprayPhase.eIdle;    (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_SprayPhase.eDone:
    bOpenCmd := FALSE; bSprayCmd := FALSE; bBlowCmd := FALSE; bCloseCmd := FALSE;
    IF NOT bStart THEN
        _ePhase := E_DL_SprayPhase.eIdle;    (* 启动指令撤销：回空闲 *)
    END_IF

E_DL_SprayPhase.eFault:
    bOpenCmd := FALSE; bSprayCmd := FALSE; bBlowCmd := FALSE; bCloseCmd := FALSE;

ELSE
    _bFault := TRUE;                         (* 兜底：非法相位锁存 *)
    _uFault := 16#0025_0009;
    _ePhase := E_DL_SprayPhase.eFault;
END_CASE

(* —— 段 5｜相位与故障码出口单点映射 —— *)
ePhase := _ePhase;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                       (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
