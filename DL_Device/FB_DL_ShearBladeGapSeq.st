(*
  Name: FB_DL_ShearBladeGapSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：剪切刀间隙调整与锁定顺控：松开夹紧→伺服调隙→间隙测量确认→夹紧锁定。
  边界条件：① 位置与公差入参全部过非有限闸；配置越域即故障（101）；
            ② 松开/调整/确认/夹紧四相各用独立 TON，PT 均取 tTimeoutS，禁跨相共用（R100）；
            ③ 确认相要求「偏差在带内且仍处于松开状态」，防夹紧前已被误夹导致间隙失真；
            ④ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eRelease / eAdjust / eVerify / eClamp / eDone / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_SbgPhase :
(
    eIdle    := 0,      (* 待机：等启动沿 / Idle, waiting for start edge *)
    eRelease := 10,     (* 松开相：等夹紧松开反馈 / Release, waiting clamp open *)
    eAdjust  := 20,     (* 调整相：伺服调隙进带 / Adjusting gap into band *)
    eVerify  := 30,     (* 确认相：测量确认且仍松开 / Verify gap while still released *)
    eClamp   := 40,     (* 夹紧相：等夹紧到位 / Clamping, waiting lock feedback *)
    eDone    := 50,     (* 完成相：保持至启动释放 / Done, holds until start released *)
    eFault   := 90      (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ShearBladeGapSeq
VAR_INPUT
    xStart : BOOL;          (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    fGapTargetMm : REAL;    (* 间隙目标值 [mm] Target gap [mm] *)
    fGapActMm : REAL;       (* 间隙实测值 [mm] Actual gap [mm] *)
    fGapTolMm : REAL;       (* 间隙公差 [mm] Gap tolerance [mm] *)
    xClamped : BOOL;        (* 夹紧到位反馈（TRUE = 已夹紧） [-] Clamp feedback *)
    tTimeoutS : TIME;       (* 单相超时窗 [ms] Phase timeout window [ms] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_SbgPhase; (* 当前相 [-] Present phase *)
    xDone : BOOL;           (* 完成单拍脉冲 [-] One-scan done pulse *)
    xFault : BOOL;          (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;         (* 故障码 0/101 组态/102~105 超时/106 非法相 [-] Error code *)
END_VAR
VAR
    _ePhase : E_DL_SbgPhase := E_DL_SbgPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bDone : BOOL := FALSE;         (* 单拍完成标志（段 1 预清） [-] One-scan done flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 组态非法当拍量 [-] Configuration bad *)
    _nErr : INT := 0;               (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested error code *)
    _fErrMm : REAL := 0.0;          (* 间隙偏差绝对量 [mm] Absolute gap deviation [mm] *)
    tonRelease : TON;               (* 松开超时（段 0 无条件调用） / Release timeout *)
    tonAdjust : TON;                (* 调整超时（段 0 无条件调用） / Adjust timeout *)
    tonVerify : TON;                (* 确认超时（段 0 无条件调用） / Verify timeout *)
    tonClamp : TON;                 (* 夹紧超时（段 0 无条件调用） / Clamp timeout *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_SBG_EPS : REAL := 1.0E-9;    (* 判据容差 [-] Criterion tolerance *)
END_VAR
(* —— 段 0：沿与四 TON 无条件周期刷新（R7），IN 仅由相位派生 —— *)
rtStart(CLK := xStart);                                                     (* 启动沿 / Start edge *)
tonRelease(IN := (_ePhase = E_DL_SbgPhase.eRelease), PT := tTimeoutS);      (* 松开超时 / Release timeout *)
tonAdjust(IN := (_ePhase = E_DL_SbgPhase.eAdjust), PT := tTimeoutS);        (* 调整超时 / Adjust timeout *)
tonVerify(IN := (_ePhase = E_DL_SbgPhase.eVerify), PT := tTimeoutS);        (* 确认超时 / Verify timeout *)
tonClamp(IN := (_ePhase = E_DL_SbgPhase.eClamp), PT := tTimeoutS);          (* 夹紧超时 / Clamp timeout *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：三浮点入参全枚举（R272） *)
_bCfgBad := (fGapTargetMm <> fGapTargetMm) OR ((fGapTargetMm - fGapTargetMm) <> 0.0)
         OR (fGapActMm <> fGapActMm) OR ((fGapActMm - fGapActMm) <> 0.0)
         OR (fGapTolMm <> fGapTolMm) OR ((fGapTolMm - fGapTolMm) <> 0.0)
         OR (fGapTargetMm <= 0.0) OR (fGapTargetMm > 50.0)
         OR (fGapTolMm <= DL_SBG_EPS) OR (fGapTolMm > 5.0) OR (tTimeoutS <= T#0S);
(* 偏差绝对量：容差比较一律用差值，禁浮点判等 *)
_fErrMm := ABS(fGapActMm - fGapTargetMm);
(* —— 段 1：单拍量预清零 —— *)
_bDone := FALSE;
_bReqFault := FALSE;
_nReqErr := 0;
IF _bCfgBad THEN
    _bReqFault := TRUE; _nReqErr := 101;        (* 组态非法 / Configuration bad *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _nErr := 0;                                 (* 清码 / Clear code *)
    _ePhase := E_DL_SbgPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_SbgPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _ePhase := E_DL_SbgPhase.eRelease;      (* 起序 → 松开 / Start to release *)
    END_IF
E_DL_SbgPhase.eRelease:
    IF NOT xClamped THEN
        _ePhase := E_DL_SbgPhase.eAdjust;       (* 已松开 → 调隙 / Released, adjust *)
    ELSIF tonRelease.Q THEN
        _bReqFault := TRUE; _nReqErr := 102;    (* 松开超时 / Release timeout *)
    END_IF
E_DL_SbgPhase.eAdjust:
    IF _fErrMm <= fGapTolMm THEN
        _ePhase := E_DL_SbgPhase.eVerify;       (* 进带 → 测量确认 / In band, verify *)
    ELSIF tonAdjust.Q THEN
        _bReqFault := TRUE; _nReqErr := 103;    (* 调整超时 / Adjust timeout *)
    END_IF
E_DL_SbgPhase.eVerify:
    IF (_fErrMm <= fGapTolMm) AND (NOT xClamped) THEN
        _ePhase := E_DL_SbgPhase.eClamp;        (* 确认通过且仍松开 → 夹紧 / Verified, clamp *)
    ELSIF tonVerify.Q THEN
        _bReqFault := TRUE; _nReqErr := 104;    (* 确认超时 / Verify timeout *)
    END_IF
E_DL_SbgPhase.eClamp:
    IF xClamped AND (_fErrMm <= fGapTolMm) THEN
        _bDone := TRUE;                         (* 单拍完成（段 1 预清） / One-scan done *)
        _ePhase := E_DL_SbgPhase.eDone;         (* → 完成相 / To done *)
    ELSIF tonClamp.Q THEN
        _bReqFault := TRUE; _nReqErr := 105;    (* 夹紧超时 / Clamp timeout *)
    END_IF
E_DL_SbgPhase.eDone:
    IF NOT xStart THEN
        _ePhase := E_DL_SbgPhase.eIdle;         (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_SbgPhase.eFault:
    _fErrMm := ABS(fGapActMm - fGapTargetMm);   (* 故障相驻留：仅刷新偏差量供追溯，不迁相 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 106;
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _ePhase := E_DL_SbgPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
eState := _ePhase;
xDone := _bDone;
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
