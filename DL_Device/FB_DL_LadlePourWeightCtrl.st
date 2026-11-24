(*
  Component : FB_DL_LadlePourWeightCtrl
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 浇包定量浇注控制：ENUM 五态（Idle/Fast/Slow/Done/Fault），快浇到"目标-快浇量"转慢浇，慢浇到"目标-提前量"停浇，称重偏差超差报警。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 目标重量、快浇量、提前量、公差须满足 快浇量 < 目标重量 且公差 > 0，否则拒绝启动并锁故障；
              ② 提前量用于补偿落料惯性，提前量 >= 目标重量时判组态非法（永不达量）；
              ③ 浇注全程有超时监控；偏差百分比在每拍按输入重算（信息量，不入锁存）。
*)

TYPE E_DL_PourPhase :
(
    eIdle  := 0,    (* 空闲：等待启动条件 / Idle waiting start *)
    eFast  := 10,   (* 快浇：大流量阶段 / Fast pouring stage *)
    eSlow  := 20,   (* 慢浇：精计量阶段 / Slow metering stage *)
    eDone  := 50,   (* 完成：偏差已判定 / Done, deviation judged *)
    eFault := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LadlePourWeightCtrl
VAR_INPUT
    bEnable     : BOOL;   (* 使能电平 [-] Enable level *)
    bReset      : BOOL;   (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart      : BOOL;   (* 启动上升沿 [-] Start edge *)
    bLadleReady : BOOL;   (* 浇包就位反馈 [-] Ladle in position feedback *)
    fWeightKg   : REAL;   (* 称重实测重量 [kg] Measured weight *)
    fTargetKg   : REAL;   (* 目标浇注重量 [kg] Target pouring weight *)
    fFastToKg   : REAL;   (* 快浇转慢浇的剩余量 [kg] Fast-to-slow switch remainder *)
    fAdvanceKg  : REAL;   (* 停浇提前量（落料惯性补偿） [kg] Stop advance *)
    fTolPct     : REAL;   (* 称重偏差公差 [%] Weight deviation tolerance *)
    tPourTo     : TIME;   (* 浇注全程超时 [ms] Pouring overall timeout *)
END_VAR
VAR_OUTPUT
    bPourFast : BOOL;              (* 快浇阀输出 [-] Fast pour valve output *)
    bPourSlow : BOOL;              (* 慢浇阀输出 [-] Slow pour valve output *)
    fDevPct   : REAL;              (* 相对目标重量偏差 [%] Weight deviation percent *)
    bOverTol  : BOOL;              (* 偏差超差报警 [-] Deviation over tolerance *)
    bDone     : BOOL;              (* 浇注完成（锁存） [-] Pouring done latched *)
    ePhase    : E_DL_PourPhase;    (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bError    : BOOL;              (* 故障锁存标志 [-] Fault latch flag *)
    uErrId    : UDINT;             (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart  : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonPourTo: TON;      (* 浇注全程超时（专用超时件） / Pouring timeout *)
    _ePhase  : E_DL_PourPhase := E_DL_PourPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bDone   : BOOL;     (* 完成锁存位（锁存量） / Latched done bit *)
    _bOver   : BOOL;     (* 超差锁存位（锁存量） / Latched over-tolerance bit *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
END_VAR
VAR CONSTANT
    DL_EPS      : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStart);
tonPourTo(IN := ((_ePhase = E_DL_PourPhase.eFast) OR (_ePhase = E_DL_PourPhase.eSlow))
              AND (NOT _bFault), PT := tPourTo);

(* —— 段 1｜每拍量预清零（锁存量 _bFault/_uFault/_bDone/_bOver 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：一次性清干净（唯一解除路径，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _bDone := FALSE;
    _bOver := FALSE;
    _ePhase := E_DL_PourPhase.eIdle;
END_IF

(* —— 段 3｜非有限拦截与组态闸（覆盖目标/快浇量/提前量/公差/时长） —— *)
IF (fWeightKg <> fWeightKg) OR ((fWeightKg - fWeightKg) <> 0.0)
   OR (fTargetKg <> fTargetKg) OR ((fTargetKg - fTargetKg) <> 0.0)
   OR (fFastToKg <> fFastToKg) OR ((fFastToKg - fFastToKg) <> 0.0)
   OR (fAdvanceKg <> fAdvanceKg) OR ((fAdvanceKg - fAdvanceKg) <> 0.0)
   OR (fTolPct <> fTolPct) OR ((fTolPct - fTolPct) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
IF (fTargetKg <= DL_EPS) OR (fFastToKg <= DL_ZERO) OR (fFastToKg >= fTargetKg)
   OR (fAdvanceKg < DL_ZERO) OR (fAdvanceKg >= fTargetKg) OR (fTolPct <= DL_ZERO)
   OR (tPourTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF

(* —— 段 4｜偏差百分比：每拍按输入重算（信息级量，不入锁存） —— *)
IF ABS(fTargetKg) > DL_EPS THEN
    fDevPct := (fWeightKg - fTargetKg) / fTargetKg * DL_PCT_BASE;   (* 分母已过域闸 [%] / Guarded division *)
ELSE
    fDevPct := 0.0;                                (* 目标为 0：偏差无定义，置 0 不留 Inf/NaN / Undefined -> 0 *)
END_IF
IF fDevPct < DL_ZERO THEN
    fDevPct := -fDevPct;                         (* 取绝对值 [%] / Absolute value *)
END_IF

(* —— 段 5｜主状态机：五态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_PourPhase.eIdle:
    bPourFast := FALSE; bPourSlow := FALSE;
    IF rtStart.Q AND bEnable AND bLadleReady AND (NOT _bFault)
       AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _bDone := FALSE;
        _bOver := FALSE;
        _ePhase := E_DL_PourPhase.eFast;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin OR (NOT bLadleReady)) THEN
        _bFault := TRUE;                 (* 带病启动拒绝 / Reject start with bad conditions *)
        _uFault := 16#0026_0001;
        _ePhase := E_DL_PourPhase.eFault;
    END_IF

E_DL_PourPhase.eFast:
    bPourFast := TRUE; bPourSlow := FALSE;
    IF _bNonFin THEN
        _bFault := TRUE; _uFault := 16#0026_0002;    (* 故障级：称重非有限 *)
        _ePhase := E_DL_PourPhase.eFault;
    ELSIF fWeightKg >= (fTargetKg - fFastToKg) THEN
        _ePhase := E_DL_PourPhase.eSlow;             (* 迁出条件 1：转慢浇精计量 *)
    ELSIF tonPourTo.Q THEN
        _bFault := TRUE; _uFault := 16#0026_0003;    (* 故障级：快浇超时 *)
        _ePhase := E_DL_PourPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_PourPhase.eIdle;             (* 迁出条件 2：使能撤销回安全态 *)
    END_IF

E_DL_PourPhase.eSlow:
    bPourFast := FALSE; bPourSlow := TRUE;
    IF _bNonFin THEN
        _bFault := TRUE; _uFault := 16#0026_0002;    (* 故障级：称重非有限 *)
        _ePhase := E_DL_PourPhase.eFault;
    ELSIF fWeightKg >= (fTargetKg - fAdvanceKg) THEN
        _bDone := TRUE;                              (* 迁出条件 1：到量提前量达成 *)
        _ePhase := E_DL_PourPhase.eDone;
    ELSIF tonPourTo.Q THEN
        _bFault := TRUE; _uFault := 16#0026_0003;    (* 故障级：慢浇超时 *)
        _ePhase := E_DL_PourPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_PourPhase.eIdle;             (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_PourPhase.eDone:
    bPourFast := FALSE; bPourSlow := FALSE;          (* 到量即双阀全关 *)
    IF fDevPct > fTolPct THEN
        _bOver := TRUE;                              (* 超差锁存，待复位清除 *)
    END_IF
    IF NOT bStart THEN
        _ePhase := E_DL_PourPhase.eIdle;             (* 启动撤销：回空闲 *)
    END_IF

E_DL_PourPhase.eFault:
    bPourFast := FALSE; bPourSlow := FALSE;          (* 故障相：双阀全关走安全侧 *)

ELSE
    bPourFast := FALSE; bPourSlow := FALSE;          (* 兜底相：先关双阀再锁故障，安全侧不留上拍开阀值 *)
    _bFault := TRUE;                                 (* 兜底：非法相位锁存 *)
    _uFault := 16#0026_0009;
    _ePhase := E_DL_PourPhase.eFault;
END_CASE

(* —— 段 6｜出口单点映射 —— *)
ePhase := _ePhase;
bDone := _bDone;
bOverTol := _bOver;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                               (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
