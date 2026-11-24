(*
  Component : FB_DL_PowderBlendDoseSeq
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 混粉配料称量控制：ENUM 五态（Idle/Dose/Settle/Done/Fault），多组分顺序放料，按累计称重提前量关阀，稳定后比对公差，超差判重称。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 组分数须 1~4、目标重量均为正、稳定时长与放料超时非 0，否则拒绝启动并锁故障；
              ② 数组下标在使用前显式判 0..3 与 小于 nCompCnt，越界即判故障不下发放料指令；
              ③ 超差处理为锁存故障并停料，复位后配料从头开始（不自动中途重称）。
*)

TYPE E_DL_BlendPhase :
(
    eIdle   := 0,    (* 空闲：等启动沿 / Idle waiting start edge *)
    eDose   := 10,   (* 放料：单组分投料 / Dosing one component *)
    eSettle := 20,   (* 稳定：等称重稳定 / Waiting weight settling *)
    eDone   := 50,   (* 完成：全部组分到位 / All components dosed *)
    eFault  := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PowderBlendDoseSeq
VAR_INPUT
    bEnable    : BOOL;                  (* 使能电平 [-] Enable level *)
    bReset     : BOOL;                  (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart     : BOOL;                  (* 启动上升沿 [-] Start edge *)
    nCompCnt   : INT;                   (* 实际组分数 1~4 [-] Component count *)
    afTargetKg : ARRAY[0..3] OF REAL;   (* 各组分目标重量 [kg] Target weight per component *)
    fWeightKg  : REAL;                  (* 秤台实测累计重量 [kg] Measured scale weight *)
    fAdvanceKg : REAL;                  (* 关阀提前量（落料惯性） [kg] Valve closing advance *)
    fTolPct    : REAL;                  (* 称量公差 [%] Weighing tolerance *)
    tSettle    : TIME;                  (* 称重稳定驻留 [ms] Settling dwell *)
    tDoseTo    : TIME;                  (* 单组分放料超时 [ms] Dosing timeout *)
END_VAR
VAR_OUTPUT
    abDoseCmd : ARRAY[0..3] OF BOOL;    (* 各组分放料阀指令 [-] Dose valve commands *)
    nCompIdx  : INT;                    (* 当前组分下标 [-] Current component index *)
    bDone     : BOOL;                   (* 配料完成（锁存） [-] Batching done latched *)
    bOverTol  : BOOL;                   (* 称量超差标志（锁存） [-] Over-tolerance latched *)
    ePhase    : E_DL_BlendPhase;        (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bError    : BOOL;                   (* 故障锁存标志 [-] Fault latch flag *)
    uErrId    : UDINT;                  (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset  : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart  : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonSettle: TON;      (* 稳定驻留计时（独立实例） / Settling timer *)
    tonDoseTo: TON;      (* 放料超时（专用超时件） / Dosing timeout *)
    _ePhase  : E_DL_BlendPhase := E_DL_BlendPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault  : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault  : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bDone   : BOOL;     (* 完成锁存位（锁存量） / Latched done bit *)
    _bOver   : BOOL;     (* 超差锁存位（锁存量） / Latched over-tolerance bit *)
    _bCfgBad : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    nIdx     : INT;      (* 数组遍历下标 [-] Array loop index *)
    fTargetNow : REAL;   (* 当前组分目标重量（已判界） [kg] Current target after bound check *)
    fDevPct  : REAL;     (* 当前组分称量偏差 [%] Current component deviation *)
END_VAR
VAR CONSTANT
    DL_PCT_BASE : REAL := 100.0;    (* 百分比基准 [%] Percent base *)
    DL_IDX_MAX  : INT := 3;         (* 数组最高下标 [-] Highest array index *)
    DL_ZERO     : REAL := 0.0;      (* 零常量 [无量纲] Zero constant *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStart);
tonSettle(IN := (_ePhase = E_DL_BlendPhase.eSettle) AND (NOT _bFault), PT := tSettle);
tonDoseTo(IN := (_ePhase = E_DL_BlendPhase.eDose)   AND (NOT _bFault), PT := tDoseTo);

(* —— 段 1｜每拍量预清零 + 放料阀全预置关闭（锁存量不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;
FOR nIdx := 0 TO 3 DO
    IF (nIdx >= 0) AND (nIdx <= DL_IDX_MAX) THEN
        abDoseCmd[nIdx] := FALSE;            (* 阀门预置关闭 [-] / Valve preset closed *)
    END_IF
END_FOR

(* —— 段 2｜非有限拦截与组态闸 —— *)
IF (fWeightKg <> fWeightKg) OR ((fWeightKg - fWeightKg) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
IF (nCompCnt < 1) OR (nCompCnt > 4) OR (fAdvanceKg < DL_ZERO) OR (fTolPct <= DL_ZERO)
   OR (tSettle = T#0S) OR (tDoseTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
FOR nIdx := 0 TO 3 DO
    IF (nIdx >= 0) AND (nIdx <= DL_IDX_MAX) AND (nIdx < nCompCnt) THEN
        IF (afTargetKg[nIdx] <> afTargetKg[nIdx]) OR (afTargetKg[nIdx] <= DL_ZERO) THEN
            _bCfgBad := TRUE;
        END_IF
    END_IF
END_FOR

(* —— 段 3｜当前组分目标重量：下标显式判界后取值，越界保持 0 —— *)
fTargetNow := DL_ZERO;
IF (nCompIdx >= 0) AND (nCompIdx <= DL_IDX_MAX) AND (nCompIdx < nCompCnt) THEN
    fTargetNow := afTargetKg[nCompIdx];
END_IF

(* —— 段 4｜复位沿：一次性清干净，配料从头开始（唯一解除路径） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _bDone := FALSE;
    _bOver := FALSE;
    nCompIdx := 0;
    _ePhase := E_DL_BlendPhase.eIdle;
END_IF

(* —— 段 5｜主状态机：五态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_BlendPhase.eIdle:
    nCompIdx := 0;
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _bDone := FALSE;
        _bOver := FALSE;
        _ePhase := E_DL_BlendPhase.eDose;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                     (* 带病启动拒绝 / Reject start with bad config *)
        _uFault := 16#0028_0001;
        _ePhase := E_DL_BlendPhase.eFault;
    END_IF

E_DL_BlendPhase.eDose:
    IF (nCompIdx >= 0) AND (nCompIdx <= DL_IDX_MAX) AND (nCompIdx < nCompCnt) THEN
        abDoseCmd[nCompIdx] := TRUE;         (* 打开当前组分放料阀 [-] / Open current valve *)
        IF fWeightKg >= (fTargetNow - fAdvanceKg) THEN
            _ePhase := E_DL_BlendPhase.eSettle;      (* 迁出条件 1：到提前量关阀 *)
        ELSIF tonDoseTo.Q THEN
            _bFault := TRUE; _uFault := 16#0028_0002;  (* 故障级：放料超时 *)
            _ePhase := E_DL_BlendPhase.eFault;
        ELSIF NOT bEnable THEN
            _ePhase := E_DL_BlendPhase.eIdle;        (* 迁出条件 2：使能撤销 *)
        END_IF
    ELSE
        _bFault := TRUE; _uFault := 16#0028_0003;    (* 故障级：组分下标越界 *)
        _ePhase := E_DL_BlendPhase.eFault;
    END_IF

E_DL_BlendPhase.eSettle:
    IF tonSettle.Q THEN
        fDevPct := (fWeightKg - fTargetNow) / fTargetNow * DL_PCT_BASE;
        IF fDevPct < DL_ZERO THEN
            fDevPct := -fDevPct;                     (* 取绝对值 [%] / Absolute value *)
        END_IF
        IF fDevPct > fTolPct THEN
            _bOver := TRUE;                          (* 超差锁存 *)
            _bFault := TRUE; _uFault := 16#0028_0004;(* 故障级：称量超差需重称 *)
            _ePhase := E_DL_BlendPhase.eFault;
        ELSIF (nCompIdx + 1) >= nCompCnt THEN
            _bDone := TRUE;
            _ePhase := E_DL_BlendPhase.eDone;        (* 迁出条件 1：末组分到位 *)
        ELSE
            nCompIdx := nCompIdx + 1;                (* 转下一组分，单点累加 *)
            _ePhase := E_DL_BlendPhase.eDose;        (* 迁出条件 2：转下一组分 *)
        END_IF
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_BlendPhase.eIdle;            (* 迁出条件 3：使能撤销 *)
    END_IF

E_DL_BlendPhase.eDone:
    IF NOT bStart THEN
        _ePhase := E_DL_BlendPhase.eIdle;            (* 启动撤销：回空闲 *)
    END_IF

E_DL_BlendPhase.eFault:
    ;                                        (* 故障相：放料阀已全预置关闭 *)

ELSE
    _bFault := TRUE;                         (* 兜底：非法相位锁存 *)
    _uFault := 16#0028_0009;
    _ePhase := E_DL_BlendPhase.eFault;
END_CASE

(* —— 段 6｜出口单点映射 —— *)
ePhase := _ePhase;
bDone := _bDone;
bOverTol := _bOver;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                       (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
