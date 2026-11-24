(*
  Component : FB_DL_BilletShearGaugeSeq
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 铸锭定尺剪切时序控制：ENUM 八态（Idle/Feed/Measure/Clamp/Shear/Trim/Release/Fault），按定尺长度送进、夹紧确认后剪切，首件去头尾。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 定尺长度须 > 1e-9、各段时长为 0 判组态非法，拒绝启动并锁存故障；
              ② 首件定尺 = 定尺长度 + 去头尾长度，去头尾仅首件执行一次；
              ③ 夹紧超时 / 松开超时均判故障，故障锁存唯一解除路径 = bReset 上升沿。
*)

TYPE E_DL_ShearPhase :
(
    eIdle    := 0,    (* 空闲：等启动沿 / Idle waiting start edge *)
    eFeed    := 10,   (* 送进：至定尺到位 / Feeding to gauge length *)
    eMeasure := 20,   (* 测长：稳定驻留 / Measuring dwell *)
    eClamp   := 30,   (* 夹紧：至夹紧反馈 / Clamping to feedback *)
    eShear   := 40,   (* 剪切：剪切保持 / Shearing hold *)
    eTrim    := 50,   (* 去头尾：首件端部切除 / Head-trim cut on first piece *)
    eRelease := 60,   (* 松开：至松开确认 / Releasing to confirmation *)
    eFault   := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BilletShearGaugeSeq
VAR_INPUT
    bEnable     : BOOL;   (* 使能电平 [-] Enable level *)
    bReset      : BOOL;   (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart      : BOOL;   (* 启动上升沿 [-] Start edge *)
    fLengthMm   : REAL;   (* 送进实测长度 [mm] Measured feed length *)
    fGaugeLenMm : REAL;   (* 定尺长度 [mm] Gauge length setpoint *)
    fTrimLenMm  : REAL;   (* 去头尾长度 [mm] Head trim length *)
    bClampFb    : BOOL;   (* 夹紧到位反馈 [-] Clamp feedback *)
    bShearFb    : BOOL;   (* 剪切到位反馈 [-] Shear feedback *)
    tMeasure    : TIME;   (* 测长驻留 [ms] Measuring dwell *)
    tShear      : TIME;   (* 剪切保持 [ms] Shear hold *)
    tTrim       : TIME;   (* 去头尾保持 [ms] Trim hold *)
    tClampTo    : TIME;   (* 夹紧超时 [ms] Clamp timeout *)
    tReleaseTo  : TIME;   (* 松开超时 [ms] Release timeout *)
END_VAR
VAR_OUTPUT
    bFeedRun    : BOOL;              (* 送进运行输出 [-] Feed run output *)
    bClampCmd   : BOOL;              (* 夹紧指令输出 [-] Clamp command *)
    bShearCmd   : BOOL;              (* 剪切指令输出 [-] Shear command *)
    bTrimCmd    : BOOL;              (* 去头尾刀指令输出 [-] Trim cut command *)
    bReleaseCmd : BOOL;              (* 松开指令输出 [-] Release command *)
    nPieceCnt   : INT;               (* 完成件数 [-] Finished piece counter *)
    ePhase      : E_DL_ShearPhase;   (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bError      : BOOL;              (* 故障锁存标志 [-] Fault latch flag *)
    uErrId      : UDINT;             (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset   : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart   : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonMeasure: TON;      (* 测长驻留计时（独立实例） / Measuring timer *)
    tonShear  : TON;      (* 剪切保持计时（独立实例） / Shear timer *)
    tonTrim   : TON;      (* 去头尾保持计时（独立实例） / Trim timer *)
    tonClampTo: TON;      (* 夹紧超时（专用超时件） / Clamp timeout *)
    tonRelTo  : TON;      (* 松开超时（专用超时件） / Release timeout *)
    _ePhase   : E_DL_ShearPhase := E_DL_ShearPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault   : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault   : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bFirst   : BOOL;     (* 首件标志（锁存量） / First piece flag *)
    _bCfgBad  : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin  : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    fTargetMm : REAL;     (* 本件定尺目标 [mm] Target length of this piece *)
END_VAR
VAR CONSTANT
    DL_EPS : REAL := 1.0E-9;   (* 浮点比较容差 [无量纲] Float compare tolerance *)
    DL_ZERO: REAL := 0.0;      (* 零常量 [-] Zero constant *)
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内，使能挂 IN 引脚） —— *)
rtReset(CLK := bReset);
rtStart(CLK := bStart);
tonMeasure(IN := (_ePhase = E_DL_ShearPhase.eMeasure) AND (NOT _bFault), PT := tMeasure);
tonShear  (IN := (_ePhase = E_DL_ShearPhase.eShear)   AND (NOT _bFault), PT := tShear);
tonTrim   (IN := (_ePhase = E_DL_ShearPhase.eTrim)    AND (NOT _bFault), PT := tTrim);
tonClampTo(IN := (_ePhase = E_DL_ShearPhase.eClamp)   AND (NOT _bFault), PT := tClampTo);
tonRelTo  (IN := (_ePhase = E_DL_ShearPhase.eRelease) AND (NOT _bFault), PT := tReleaseTo);

(* —— 段 1｜每拍量预清零（锁存量 _bFault/_uFault/_bFirst/nPieceCnt 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，首件标志复原 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _bFirst := TRUE;
    _ePhase := E_DL_ShearPhase.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖定尺长度与各段时长） —— *)
IF (fGaugeLenMm <= DL_EPS) OR (fTrimLenMm < DL_ZERO) OR (tMeasure = T#0S)
   OR (tShear = T#0S) OR (tTrim = T#0S) OR (tClampTo = T#0S) OR (tReleaseTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fLengthMm <> fLengthMm) OR ((fLengthMm - fLengthMm) <> 0.0)
   OR (fGaugeLenMm <> fGaugeLenMm) OR ((fGaugeLenMm - fGaugeLenMm) <> 0.0)
   OR (fTrimLenMm <> fTrimLenMm) OR ((fTrimLenMm - fTrimLenMm) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜本件定尺目标：首件叠加去头尾长度 —— *)
IF _bFirst THEN
    fTargetMm := fGaugeLenMm + fTrimLenMm;
ELSE
    fTargetMm := fGaugeLenMm;
END_IF

(* —— 段 5｜主状态机：八态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_ShearPhase.eIdle:
    bFeedRun := FALSE; bClampCmd := FALSE; bShearCmd := FALSE;
    bTrimCmd := FALSE; bReleaseCmd := FALSE;
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        nPieceCnt := 0;
        _bFirst := TRUE;
        _ePhase := E_DL_ShearPhase.eFeed;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                  (* 带病启动拒绝 / Reject start with bad config *)
        _uFault := 16#0024_0001;
        _ePhase := E_DL_ShearPhase.eFault;
    END_IF

E_DL_ShearPhase.eFeed:
    bFeedRun := TRUE; bClampCmd := FALSE; bShearCmd := FALSE;
    bTrimCmd := FALSE; bReleaseCmd := FALSE;
    IF _bNonFin THEN
        _bFault := TRUE; _uFault := 16#0024_0002;   (* 故障级：长度反馈非有限 *)
        _ePhase := E_DL_ShearPhase.eFault;
    ELSIF fLengthMm >= fTargetMm THEN
        _ePhase := E_DL_ShearPhase.eMeasure;        (* 迁出条件 1：定尺到位 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_ShearPhase.eIdle;           (* 迁出条件 2：使能撤销回安全态 *)
    END_IF

E_DL_ShearPhase.eMeasure:
    bFeedRun := FALSE; bClampCmd := FALSE; bShearCmd := FALSE;
    bTrimCmd := FALSE; bReleaseCmd := FALSE;
    IF tonMeasure.Q THEN
        _ePhase := E_DL_ShearPhase.eClamp;          (* 迁出条件 1：测长驻留完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_ShearPhase.eIdle;           (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_ShearPhase.eClamp:
    bFeedRun := FALSE; bClampCmd := TRUE; bShearCmd := FALSE;
    bTrimCmd := FALSE; bReleaseCmd := FALSE;
    IF bClampFb THEN
        _ePhase := E_DL_ShearPhase.eShear;          (* 迁出条件 1：夹紧反馈到位 *)
    ELSIF tonClampTo.Q THEN
        _bFault := TRUE; _uFault := 16#0024_0003;   (* 故障级：夹紧超时 *)
        _ePhase := E_DL_ShearPhase.eFault;
    END_IF

E_DL_ShearPhase.eShear:
    bFeedRun := FALSE; bClampCmd := TRUE; bShearCmd := TRUE;
    bTrimCmd := FALSE; bReleaseCmd := FALSE;
    IF bShearFb OR tonShear.Q THEN
        IF _bFirst THEN
            _ePhase := E_DL_ShearPhase.eTrim;       (* 首件：追加去头尾刀 *)
        ELSE
            _ePhase := E_DL_ShearPhase.eRelease;    (* 迁出条件 1：剪切到位或保持到时 *)
        END_IF
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_ShearPhase.eIdle;           (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_ShearPhase.eTrim:
    bFeedRun := FALSE; bClampCmd := TRUE; bShearCmd := FALSE;
    bTrimCmd := TRUE; bReleaseCmd := FALSE;
    IF tonTrim.Q THEN
        _ePhase := E_DL_ShearPhase.eRelease;        (* 迁出条件 1：去头尾保持完成 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_ShearPhase.eIdle;           (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_ShearPhase.eRelease:
    bFeedRun := FALSE; bClampCmd := FALSE; bShearCmd := FALSE;
    bTrimCmd := FALSE; bReleaseCmd := TRUE;
    IF NOT bClampFb THEN
        nPieceCnt := nPieceCnt + 1;                 (* 完成件数累加：仅在迁出拍执行一次 *)
        _bFirst := FALSE;                           (* 首件完成，后续按纯定尺 *)
        _ePhase := E_DL_ShearPhase.eFeed;           (* 迁出条件 1：松开确认到位 *)
    ELSIF tonRelTo.Q THEN
        _bFault := TRUE; _uFault := 16#0024_0004;   (* 故障级：松开超时 *)
        _ePhase := E_DL_ShearPhase.eFault;
    END_IF

E_DL_ShearPhase.eFault:
    bFeedRun := FALSE; bClampCmd := FALSE; bShearCmd := FALSE;
    bTrimCmd := FALSE; bReleaseCmd := FALSE;        (* 故障相：全部输出走安全侧 *)

ELSE
    _bFault := TRUE;                                (* 兜底：非法相位锁存 *)
    _uFault := 16#0024_0009;
    _ePhase := E_DL_ShearPhase.eFault;
END_CASE

(* —— 段 6｜相位与故障码出口单点映射 —— *)
ePhase := _ePhase;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                              (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
