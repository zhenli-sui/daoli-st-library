(*
  Name: FB_DL_CoilCarIndexSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：钢卷小车行走定位顺控（快进→慢进→精定位→落卷→返回），五相各自独立超时 TON。
  边界条件：① 位置与公差入参全部过非有限闸；配置越域即故障（101）；
            ② 快进/慢进/精定位/返回四相各用独立 TON，落卷为确定性时窗 DL_CCS_DROP，禁跨相共用（R100）；
            ③ 位置判据假设小车前进方向为位置数值增大（fPosSlowMm < fPosTargetMm），越序即组态非法；
            ④ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eFast / eSlow / eFine / eDrop / eReturn / eDone / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_CcsPhase :
(
    eIdle   := 0,       (* 待机：等启动沿 / Idle, waiting for start edge *)
    eFast   := 10,      (* 快进相：走到减速点 / Fast travel to slow-down point *)
    eSlow   := 20,      (* 慢进相：走到精定位带 / Slow travel to fine band *)
    eFine   := 30,      (* 精定位相：进入公差带 / Fine positioning into tolerance *)
    eDrop    := 40,     (* 落卷相：确定性落卷时窗 / Coil drop, fixed window *)
    eReturn := 50,      (* 返回相：回到原点位 / Return to home position *)
    eDone    := 60,     (* 完成相：保持至启动释放 / Done, holds until start released *)
    eFault  := 90       (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoilCarIndexSeq
VAR_INPUT
    xStart : BOOL;          (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    fPosActMm : REAL;       (* 小车位置实测 [mm] Car position actual [mm] *)
    fPosSlowMm : REAL;      (* 减速（慢进）点位置 [mm] Slow-down point [mm] *)
    fPosTargetMm : REAL;    (* 精定位目标位置 [mm] Fine positioning target [mm] *)
    fTolMm : REAL;          (* 精定位公差 [mm] Fine positioning tolerance [mm] *)
    tTimeoutS : TIME;       (* 单相超时窗 [ms] Phase timeout window [ms] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_CcsPhase; (* 当前相 [-] Present phase *)
    xDone : BOOL;           (* 完成单拍脉冲 [-] One-scan done pulse *)
    xFault : BOOL;          (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;         (* 故障码 0/101 组态/102~105 超时/106 非法相 [-] Error code *)
END_VAR
VAR
    _ePhase : E_DL_CcsPhase := E_DL_CcsPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bDone : BOOL := FALSE;         (* 单拍完成标志（段 1 预清） [-] One-scan done flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 组态非法当拍量 [-] Configuration bad *)
    _nErr : INT := 0;               (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested error code *)
    _fErrMm : REAL := 0.0;          (* 距目标偏差绝对量 [mm] Absolute deviation to target [mm] *)
    tonFast : TON;                  (* 快进超时（段 0 无条件调用） / Fast travel timeout *)
    tonSlow : TON;                  (* 慢进超时（段 0 无条件调用） / Slow travel timeout *)
    tonFine : TON;                  (* 精定位超时（段 0 无条件调用） / Fine positioning timeout *)
    tonDrop : TON;                  (* 落卷时窗（确定性时窗） / Coil drop window *)
    tonReturn : TON;                (* 返回超时（段 0 无条件调用） / Return timeout *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_CCS_SLOW_BAND : REAL := 5.0;         (* 精定位带半宽（取 5 倍公差不劣于公差） [mm] Fine band half-width [mm] *)
    DL_CCS_HOME_MM : REAL := 10.0;          (* 原点位判定门限 [mm] Home position threshold [mm] *)
    DL_CCS_DROP : TIME := T#800MS;          (* 落卷动作时窗（确定性） [ms] Coil drop window [ms] *)
END_VAR
(* —— 段 0：沿与五 TON 无条件周期刷新（R7），IN 仅由相位派生 —— *)
rtStart(CLK := xStart);                                             (* 启动沿 / Start edge *)
tonFast(IN := (_ePhase = E_DL_CcsPhase.eFast), PT := tTimeoutS);    (* 快进超时 / Fast timeout *)
tonSlow(IN := (_ePhase = E_DL_CcsPhase.eSlow), PT := tTimeoutS);    (* 慢进超时 / Slow timeout *)
tonFine(IN := (_ePhase = E_DL_CcsPhase.eFine), PT := tTimeoutS);    (* 精定位超时 / Fine timeout *)
tonDrop(IN := (_ePhase = E_DL_CcsPhase.eDrop), PT := DL_CCS_DROP);  (* 落卷时窗 / Drop window *)
tonReturn(IN := (_ePhase = E_DL_CcsPhase.eReturn), PT := tTimeoutS);(* 返回超时 / Return timeout *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：位置与公差全枚举（R272） *)
_bCfgBad := (fPosActMm <> fPosActMm) OR ((fPosActMm - fPosActMm) <> 0.0)
         OR (fPosSlowMm <> fPosSlowMm) OR ((fPosSlowMm - fPosSlowMm) <> 0.0)
         OR (fPosTargetMm <> fPosTargetMm) OR ((fPosTargetMm - fPosTargetMm) <> 0.0)
         OR (fTolMm <> fTolMm) OR ((fTolMm - fTolMm) <> 0.0)
         OR (fTolMm < 0.1) OR (fTolMm > 20.0)
         OR (fPosSlowMm >= fPosTargetMm) OR (fPosTargetMm > 30000.0) OR (tTimeoutS <= T#0S);
(* 偏差绝对量：容差比较一律用差值，禁浮点判等 *)
_fErrMm := ABS(fPosActMm - fPosTargetMm);
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
    _ePhase := E_DL_CcsPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_CcsPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _ePhase := E_DL_CcsPhase.eFast;         (* 起序 → 快进 / Start to fast travel *)
    END_IF
E_DL_CcsPhase.eFast:
    IF fPosActMm >= fPosSlowMm THEN
        _ePhase := E_DL_CcsPhase.eSlow;         (* 到减速点 → 慢进 / Reached slow-down point *)
    ELSIF tonFast.Q THEN
        _bReqFault := TRUE; _nReqErr := 102;    (* 快进超时 / Fast travel timeout *)
    END_IF
E_DL_CcsPhase.eSlow:
    IF _fErrMm <= DL_CCS_SLOW_BAND THEN
        _ePhase := E_DL_CcsPhase.eFine;         (* 进精定位带 → 精定位 / Enter fine band *)
    ELSIF tonSlow.Q THEN
        _bReqFault := TRUE; _nReqErr := 103;    (* 慢进超时 / Slow travel timeout *)
    END_IF
E_DL_CcsPhase.eFine:
    IF _fErrMm <= fTolMm THEN
        _ePhase := E_DL_CcsPhase.eDrop;         (* 进公差带 → 落卷 / In tolerance, drop *)
    ELSIF tonFine.Q THEN
        _bReqFault := TRUE; _nReqErr := 104;    (* 精定位超时 / Fine positioning timeout *)
    END_IF
E_DL_CcsPhase.eDrop:
    IF tonDrop.Q THEN
        _ePhase := E_DL_CcsPhase.eReturn;       (* 落卷时窗到 → 返回 / Drop done, return *)
    END_IF
E_DL_CcsPhase.eReturn:
    IF fPosActMm <= DL_CCS_HOME_MM THEN
        _bDone := TRUE;                         (* 单拍完成（段 1 预清） / One-scan done *)
        _ePhase := E_DL_CcsPhase.eDone;         (* → 完成相 / To done *)
    ELSIF tonReturn.Q THEN
        _bReqFault := TRUE; _nReqErr := 105;    (* 返回超时 / Return timeout *)
    END_IF
E_DL_CcsPhase.eDone:
    IF NOT xStart THEN
        _ePhase := E_DL_CcsPhase.eIdle;         (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_CcsPhase.eFault:
    _fErrMm := ABS(fPosActMm - fPosTargetMm);   (* 故障相驻留：仅刷新偏差量供追溯，不迁相 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 106;
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _ePhase := E_DL_CcsPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
eState := _ePhase;
xDone := _bDone;
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
