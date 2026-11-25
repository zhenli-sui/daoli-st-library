(*
  Name: FB_DL_CrusherGapAdjustSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：破碎机排矿口液压调整顺控（卸压→调整→锁定→复检→完成），四相超时各自独立 TON。
  边界条件：① 卸压相为确定性时窗 DL_CGA_DEPRESS（无压力反馈引脚，纯时序稳定窗），不计超时；
            ② 调整/锁定/复检三相各用独立 TON，PT 均取 tTimeoutS，禁跨相共用实例（R100 无同拍双窗）；
            ③ 故障锁存解除唯一路径：故障相内 xStart 释放（下降）即清锁存回 eIdle（R152 可达性自证）；
            ④ 复位语义：本件在每个扫描周期先清单拍量再判条件，锁存清除仅发生在 xStart 释放拍。
  状态机：eIdle / eDepress / eAdjust / eLock / eVerify / eDone / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_CgaPhase :
(
    eIdle    := 0,      (* 待机：等启动沿 / Idle, waiting for start edge *)
    eDepress := 10,     (* 卸压相：固定稳定窗 / Depress phase, fixed settle window *)
    eAdjust  := 20,     (* 调整相：等排矿口进容差带 / Adjusting into tolerance band *)
    eLock    := 30,     (* 锁定相：等液压锁定反馈 / Waiting for hydraulic lock feedback *)
    eVerify  := 40,     (* 复检相：锁定且偏差仍在带内 / Verify locked and gap still in band *)
    eDone    := 50,     (* 完成相：保持至启动命令释放 / Done, holds until start released *)
    eFault   := 90      (* 故障相：锁存待复位 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CrusherGapAdjustSeq
VAR_INPUT
    xStart : BOOL;          (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    fGapTargetMm : REAL;    (* 排矿口目标值 [mm] Target gap [mm] *)
    fGapActMm : REAL;       (* 排矿口实测值 [mm] Actual gap [mm] *)
    xLocked : BOOL;         (* 液压锁定到位反馈 [-] Lock feedback *)
    tTimeoutS : TIME;       (* 调整/锁定/复检相超时窗 [ms] Phase timeout window [ms] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_CgaPhase; (* 当前相 [-] Present phase *)
    xDone : BOOL;           (* 完成单拍脉冲 [-] One-scan done pulse *)
    xBusy : BOOL;           (* 顺序执行中 [-] Sequence busy *)
    xFault : BOOL;          (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;         (* 故障码 0/101 组态/102 调整超时/103 锁定超时/104 复检超时/105 复检不符/106 非法相 [-] Error code *)
END_VAR
VAR
    _ePhase : E_DL_CgaPhase := E_DL_CgaPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bDone : BOOL := FALSE;          (* 单拍完成标志（段 1 预清） [-] One-scan done flag *)
    _bFaultLatch : BOOL := FALSE;    (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;      (* 单拍故障请求（段 1 预清，段 4 落地） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;        (* 组态非法当拍量 [-] Configuration bad *)
    _nErr : INT := 0;                (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;             (* 当拍请求码 [-] Requested error code *)
    _fErr : REAL := 0.0;             (* 排矿口偏差绝对量 [mm] Absolute gap deviation [mm] *)
    tonDepress : TON;                (* 卸压稳定窗（段 0 无条件调用） / Depress window *)
    tonAdjust : TON;                 (* 调整超时（段 0 无条件调用） / Adjust timeout *)
    tonLock : TON;                   (* 锁定超时（段 0 无条件调用） / Lock timeout *)
    tonVerify : TON;                 (* 复检超时（段 0 无条件调用） / Verify timeout *)
    rtStart : R_TRIG;                (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_CGA_TOL : REAL := 0.5;               (* 排矿口到位容差 [mm] Gap tolerance [mm] *)
    DL_CGA_DEPRESS : TIME := T#500MS;       (* 卸压稳定窗（确定性时窗，不设超时） [ms] Depress window *)
END_VAR
(* —— 段 0：两沿与四 TON 无条件周期刷新（R7），IN 仅由相位派生，禁放入分支 —— *)
rtStart(CLK := xStart);                                                            (* 启动沿 / Start edge *)
tonDepress(IN := (_ePhase = E_DL_CgaPhase.eDepress), PT := DL_CGA_DEPRESS);        (* 卸压窗 / Depress window *)
tonAdjust(IN := (_ePhase = E_DL_CgaPhase.eAdjust), PT := tTimeoutS);               (* 调整超时 / Adjust timeout *)
tonLock(IN := (_ePhase = E_DL_CgaPhase.eLock), PT := tTimeoutS);                   (* 锁定超时 / Lock timeout *)
tonVerify(IN := (_ePhase = E_DL_CgaPhase.eVerify), PT := tTimeoutS);               (* 复检超时 / Verify timeout *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 静态组态域闸 *)
_bCfgBad := (fGapTargetMm <> fGapTargetMm) OR ((fGapTargetMm - fGapTargetMm) <> 0.0)
         OR (fGapActMm <> fGapActMm) OR ((fGapActMm - fGapActMm) <> 0.0)
         OR (fGapTargetMm <= 0.0) OR (fGapTargetMm > 300.0) OR (tTimeoutS <= T#0S);
(* 偏差绝对量：容差比较一律用差值，禁浮点判等 *)
_fErr := ABS(fGapActMm - fGapTargetMm);
(* —— 段 1：单拍量预清零（不含锁存/快照量，R107） —— *)
_bDone := FALSE;
_bReqFault := FALSE;
_nReqErr := 0;
IF _bCfgBad THEN
    _bReqFault := TRUE;
    _nReqErr := 101;                            (* 组态非法 / Configuration bad *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _nErr := 0;                                 (* 清码 / Clear code *)
    _ePhase := E_DL_CgaPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_CgaPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _ePhase := E_DL_CgaPhase.eDepress;      (* 起序 → 卸压 / Start to depress *)
    END_IF
E_DL_CgaPhase.eDepress:
    IF tonDepress.Q THEN
        _ePhase := E_DL_CgaPhase.eAdjust;       (* 稳定窗到 → 调整 / Settled, adjust *)
    END_IF
E_DL_CgaPhase.eAdjust:
    IF _fErr <= DL_CGA_TOL THEN
        _ePhase := E_DL_CgaPhase.eLock;         (* 进带 → 锁定 / In band, lock *)
    ELSIF tonAdjust.Q THEN
        _bReqFault := TRUE; _nReqErr := 102;    (* 调整超时 / Adjust timeout *)
    END_IF
E_DL_CgaPhase.eLock:
    IF xLocked AND (_fErr <= DL_CGA_TOL) THEN
        _ePhase := E_DL_CgaPhase.eVerify;       (* 已锁且带内 → 复检 / Locked, verify *)
    ELSIF tonLock.Q THEN
        _bReqFault := TRUE; _nReqErr := 103;    (* 锁定超时 / Lock timeout *)
    END_IF
E_DL_CgaPhase.eVerify:
    IF (_fErr <= DL_CGA_TOL) AND xLocked THEN
        _bDone := TRUE;                         (* 单拍完成（段 1 预清） / One-scan done *)
        _ePhase := E_DL_CgaPhase.eDone;         (* → 完成相 / To done *)
    ELSIF tonVerify.Q THEN
        IF xLocked THEN
            _bReqFault := TRUE; _nReqErr := 105;    (* 复检偏差超带 / Verify deviation out of band *)
        ELSE
            _bReqFault := TRUE; _nReqErr := 104;    (* 复检超时 / Verify timeout *)
        END_IF
    END_IF
E_DL_CgaPhase.eDone:
    IF NOT xStart THEN
        _ePhase := E_DL_CgaPhase.eIdle;         (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_CgaPhase.eFault:
    _fErr := ABS(fGapActMm - fGapTargetMm);     (* 故障相驻留：码已锁存回放，此处仅刷新偏差量供追溯（R189） *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 106;
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252；落在 CASE 之后免同拍抹除） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _ePhase := E_DL_CgaPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（电平量由相派生，单拍量由标志映射，各出口单点赋值） —— *)
eState := _ePhase;
xDone := _bDone;
xBusy := (_ePhase = E_DL_CgaPhase.eDepress) OR (_ePhase = E_DL_CgaPhase.eAdjust)
      OR (_ePhase = E_DL_CgaPhase.eLock) OR (_ePhase = E_DL_CgaPhase.eVerify);
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
