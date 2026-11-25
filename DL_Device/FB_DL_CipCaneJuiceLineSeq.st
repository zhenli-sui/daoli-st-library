(*
  Component : FB_DL_CipCaneJuiceLineSeq
  Category  : DL_Device
  Type      : FB
  Complexity: C2
  VERSION   : v1.0.0
  功能      : 蔗汁线 CIP 五步清洗时序：ENUM 九态（Idle/PreRinse/Caustic/Intermediate/Rinse/Acid/Final/Done/Fault），按步计时推进，漂洗类步按回液电导早退，单步超时联锁。
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 六段步时长与单步超时均须非 0、回液电导合格限须 > 1e-9，否则拒启动并锁故障；
              ② 回液电导早退仅对 Intermediate/Rinse/Final 三个漂洗类步生效，酸洗与碱洗步只认计时；
              ③ 碱洗步叠加温度下限联锁；单步超时为最高优先级故障出口，锁存至 bReset 上升沿。
*)

TYPE E_DL_CaneCipPhase :
(
    eIdle         := 0,    (* 空闲：等启动沿 / Idle waiting start edge *)
    ePreRinse     := 10,   (* 预冲洗：第 1 步 / Pre-rinse step 1 *)
    eCaustic      := 20,   (* 碱洗：第 2 步 / Caustic wash step 2 *)
    eIntermediate := 30,   (* 中间冲洗：第 3 步 / Intermediate rinse step 3 *)
    eRinse        := 40,   (* 清水冲洗：第 4 步 / Rinse step 4 *)
    eAcid         := 50,   (* 酸洗：第 5 步 / Acid wash step 5 *)
    eFinal        := 60,   (* 终冲洗：第 6 步 / Final rinse step 6 *)
    eDone         := 70,   (* 完成：待撤销 / Done holding *)
    eFault        := 90    (* 故障：锁存待复位 / Fault latched *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CipCaneJuiceLineSeq
VAR_INPUT
    bEnable    : BOOL;                  (* 使能电平 [-] Enable level *)
    bReset     : BOOL;                  (* 复位上升沿，清故障锁存 [-] Reset edge *)
    bStart     : BOOL;                  (* 启动上升沿 [-] Start edge *)
    fCondUs    : REAL;                  (* 回液电导率 [μS/cm] Return liquor conductivity *)
    fCondOkUs  : REAL;                  (* 回液电导合格限 [μS/cm] Conductivity pass limit *)
    atStepTime : ARRAY[0..5] OF TIME;   (* 六段步时长 [ms] Step durations *)
    tStepMax   : TIME;                  (* 单步超时上限 [ms] Single step timeout *)
    fTempC     : REAL;                  (* 碱洗液温度 [°C] Caustic solution temperature *)
    fTempMinC  : REAL;                  (* 碱洗温度下限 [°C] Caustic temperature lower limit *)
END_VAR
VAR_OUTPUT
    bPumpCmd : BOOL;              (* CIP 循环泵输出 [-] CIP circulation pump output *)
    bValveCmd: BOOL;              (* CIP 进液阀输出 [-] CIP inlet valve output *)
    nStep    : INT;               (* 当前步号 1~6 [-] Current step number *)
    ePhase   : E_DL_CaneCipPhase;     (* 相位出口，段尾单点映射 [-] Phase outlet *)
    bDone    : BOOL;              (* 清洗完成（锁存） [-] CIP done latched *)
    bError   : BOOL;              (* 故障锁存标志 [-] Fault latch flag *)
    uErrId   : UDINT;             (* 事件码，0 = 无事件 [-] Event code *)
END_VAR
VAR
    rtReset   : R_TRIG;   (* 复位沿实例，每拍无条件刷新 / Reset edge *)
    rtStart   : R_TRIG;   (* 启动沿实例，每拍无条件刷新 / Start edge *)
    tonStep   : TON;      (* 当前步计时（每拍重装 PT） / Current step timer *)
    tonStepMax: TON;      (* 单步超时（专用超时件） / Step timeout *)
    _ePhase   : E_DL_CaneCipPhase := E_DL_CaneCipPhase.eIdle;  (* 内部相位 / Internal phase *)
    _bFault   : BOOL;     (* 故障锁存位（锁存量） / Latched fault bit *)
    _uFault   : UDINT;    (* 故障码锁存（锁存量） / Latched fault code *)
    _bDone    : BOOL;     (* 完成锁存位（锁存量） / Latched done bit *)
    _bCfgBad  : BOOL;     (* 组态非法当拍量 [-] Config illegal flag *)
    _bNonFin  : BOOL;     (* 输入非有限当拍量 [-] Non-finite input flag *)
    nIdx      : INT;      (* 步时长表遍历下标 [-] Step time loop index *)
    nStepIdx  : INT;      (* 当前步在时长表中的下标 [-] Step index in duration table *)
    tStepNow  : TIME;     (* 当前步时长（已判界） [ms] Current step duration after bound check *)
    bActive   : BOOL;     (* 处于清洗步中 [-] In washing step flag *)
END_VAR
VAR CONSTANT
    DL_EPS     : REAL := 1.0E-9;   (* 除零判定容差 [无量纲] Divide-by-zero tolerance *)
    DL_IDX_MAX : INT := 5;         (* 步时长表最高下标 [-] Highest step table index *)
    DL_ZERO    : TIME := T#0S;     (* 零时长常量 [-] Zero duration *)
END_VAR

(* —— 段 0｜每拍量预清零（锁存量 _bFault/_uFault/_bDone 不入清单） —— *)
uErrId := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 1｜当前步下标：相位映射到 0~5，判界后再取步时长（禁越界读） —— *)
nStepIdx := 0;
CASE _ePhase OF
E_DL_CaneCipPhase.ePreRinse:     nStepIdx := 0;
E_DL_CaneCipPhase.eCaustic:      nStepIdx := 1;
E_DL_CaneCipPhase.eIntermediate: nStepIdx := 2;
E_DL_CaneCipPhase.eRinse:        nStepIdx := 3;
E_DL_CaneCipPhase.eAcid:         nStepIdx := 4;
E_DL_CaneCipPhase.eFinal:        nStepIdx := 5;
ELSE
    nStepIdx := 0;                        (* 非清洗相：下标归 0，时长不用 *)
END_CASE
tStepNow := DL_ZERO;
IF (nStepIdx >= 0) AND (nStepIdx <= DL_IDX_MAX) THEN
    tStepNow := atStepTime[nStepIdx];
END_IF

(* —— 段 2｜非有限拦截与组态闸（覆盖六段时长、单步超时、电导限） —— *)
IF (fCondUs <> fCondUs) OR ((fCondUs - fCondUs) <> 0.0)
   OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> 0.0)
   OR (fCondOkUs <> fCondOkUs) OR ((fCondOkUs - fCondOkUs) <> 0.0)
   OR (fTempMinC <> fTempMinC) OR ((fTempMinC - fTempMinC) <> 0.0) THEN
    _bNonFin := TRUE;
END_IF
IF (tStepMax = T#0S) OR (fCondOkUs <= DL_EPS) THEN
    _bCfgBad := TRUE;
END_IF
FOR nIdx := 0 TO 5 DO
    IF (nIdx >= 0) AND (nIdx <= DL_IDX_MAX) THEN
        IF atStepTime[nIdx] = T#0S THEN
            _bCfgBad := TRUE;             (* 任一段步时长为 0 判组态非法 *)
        END_IF
    END_IF
END_FOR

(* —— 段 3｜清洗步判定 + 沿与定时器每拍无条件刷新（使能挂 IN 引脚） —— *)
bActive := (_ePhase = E_DL_CaneCipPhase.ePreRinse) OR (_ePhase = E_DL_CaneCipPhase.eCaustic)
           OR (_ePhase = E_DL_CaneCipPhase.eIntermediate) OR (_ePhase = E_DL_CaneCipPhase.eRinse)
           OR (_ePhase = E_DL_CaneCipPhase.eAcid) OR (_ePhase = E_DL_CaneCipPhase.eFinal);
rtReset  (CLK := bReset);
rtStart  (CLK := bStart);
tonStep  (IN := bActive AND (NOT _bFault), PT := tStepNow);
tonStepMax(IN := bActive AND (NOT _bFault), PT := tStepMax);

(* —— 段 4｜复位沿：一次性清干净，回空闲（唯一解除路径，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    _bDone := FALSE;
    _ePhase := E_DL_CaneCipPhase.eIdle;
END_IF

(* —— 段 5｜主状态机：九态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF
E_DL_CaneCipPhase.eIdle:
    bPumpCmd := FALSE; bValveCmd := FALSE; nStep := 0;
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        _bDone := FALSE;
        _ePhase := E_DL_CaneCipPhase.ePreRinse;
    ELSIF rtStart.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                  (* 带病启动拒绝 / Reject start with bad config *)
        _uFault := 16#0030_0001;
        _ePhase := E_DL_CaneCipPhase.eFault;
    END_IF

E_DL_CaneCipPhase.ePreRinse:
    bPumpCmd := TRUE; bValveCmd := TRUE; nStep := 1;
    IF tonStepMax.Q THEN
        _bFault := TRUE; _uFault := 16#0030_0002;   (* 故障级：第 1 步超时 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF tonStep.Q THEN
        _ePhase := E_DL_CaneCipPhase.eCaustic;          (* 迁出条件 1：步计时到 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_CaneCipPhase.eCaustic:
    bPumpCmd := TRUE; bValveCmd := TRUE; nStep := 2;
    IF tonStepMax.Q THEN
        _bFault := TRUE; _uFault := 16#0030_0003;   (* 故障级：第 2 步超时 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF fTempC < fTempMinC THEN
        _bFault := TRUE; _uFault := 16#0030_0004;   (* 故障级：碱洗温度不足 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF tonStep.Q THEN
        _ePhase := E_DL_CaneCipPhase.eIntermediate;     (* 迁出条件 1：步计时到 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_CaneCipPhase.eIntermediate:
    bPumpCmd := TRUE; bValveCmd := TRUE; nStep := 3;
    IF tonStepMax.Q THEN
        _bFault := TRUE; _uFault := 16#0030_0005;   (* 故障级：第 3 步超时 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF tonStep.Q THEN
        _ePhase := E_DL_CaneCipPhase.eRinse;            (* 迁出条件 1：步计时到 *)
    ELSIF fCondUs <= fCondOkUs THEN
        _ePhase := E_DL_CaneCipPhase.eRinse;            (* 迁出条件 2：回液电导早退 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 迁出条件 3：使能撤销 *)
    END_IF

E_DL_CaneCipPhase.eRinse:
    bPumpCmd := TRUE; bValveCmd := TRUE; nStep := 4;
    IF tonStepMax.Q THEN
        _bFault := TRUE; _uFault := 16#0030_0006;   (* 故障级：第 4 步超时 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF tonStep.Q THEN
        _ePhase := E_DL_CaneCipPhase.eAcid;             (* 迁出条件 1：步计时到 *)
    ELSIF fCondUs <= fCondOkUs THEN
        _ePhase := E_DL_CaneCipPhase.eAcid;             (* 迁出条件 2：回液电导早退 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 迁出条件 3：使能撤销 *)
    END_IF

E_DL_CaneCipPhase.eAcid:
    bPumpCmd := TRUE; bValveCmd := TRUE; nStep := 5;
    IF tonStepMax.Q THEN
        _bFault := TRUE; _uFault := 16#0030_0007;   (* 故障级：第 5 步超时 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF tonStep.Q THEN
        _ePhase := E_DL_CaneCipPhase.eFinal;            (* 迁出条件 1：步计时到 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 迁出条件 2：使能撤销 *)
    END_IF

E_DL_CaneCipPhase.eFinal:
    bPumpCmd := TRUE; bValveCmd := TRUE; nStep := 6;
    IF tonStepMax.Q THEN
        _bFault := TRUE; _uFault := 16#0030_0008;   (* 故障级：第 6 步超时 *)
        _ePhase := E_DL_CaneCipPhase.eFault;
    ELSIF tonStep.Q THEN
        _bDone := TRUE;
        _ePhase := E_DL_CaneCipPhase.eDone;             (* 迁出条件 1：末步计时到 *)
    ELSIF fCondUs <= fCondOkUs THEN
        _bDone := TRUE;
        _ePhase := E_DL_CaneCipPhase.eDone;             (* 迁出条件 2：回液电导早退 *)
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 迁出条件 3：使能撤销 *)
    END_IF

E_DL_CaneCipPhase.eDone:
    bPumpCmd := FALSE; bValveCmd := FALSE; nStep := 0;
    IF NOT bStart THEN
        _ePhase := E_DL_CaneCipPhase.eIdle;             (* 启动撤销：回空闲 *)
    END_IF

E_DL_CaneCipPhase.eFault:
    bPumpCmd := FALSE; bValveCmd := FALSE;          (* 故障相：泵与阀全部切除 *)

ELSE
    _bFault := TRUE;                                (* 兜底：非法相位锁存 *)
    _uFault := 16#0030_0009;
    _ePhase := E_DL_CaneCipPhase.eFault;
END_CASE

(* —— 段 6｜出口单点映射 —— *)
ePhase := _ePhase;
bDone := _bDone;
bError := _bFault;
IF _bFault AND (_uFault <> 16#0000_0000) THEN
    uErrId := _uFault;                              (* 故障码锁存回放 / Latched fault replay *)
END_IF
END_FUNCTION_BLOCK
