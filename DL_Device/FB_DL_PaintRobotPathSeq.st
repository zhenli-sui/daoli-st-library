(*
  Name: FB_DL_PaintRobotPathSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：喷涂机器人轨迹段执行顺序（含枪距补偿）：按段完成沿推进段号，输出段号、枪距补偿量与轨迹完成脉冲。
  边界条件：① 枪距两入参过非有限闸；总段数与段索引按 1~999 域闸拦截，越域即故障（101）；
            ② 段完成沿用 R_TRIG 在段 0 无条件刷新（R7），禁放入 CASE 分支；
            ③ 枪距补偿 = 设定 − 实测，钳 ±5 mm（伺服补偿行程死区外的机械限）；
            ④ 完成脉冲两段式：相内置 _bDone，出口统一映射单拍（R187）；
            ⑤ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eRun / eDone / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_DpsState :
(
    eIdle  := 0,        (* 待机：等启动沿 / Idle, waiting for start edge *)
    eRun   := 10,       (* 执行相：按段完成沿推进 / Running, advancing by segment done edge *)
    eDone  := 20,       (* 完成相：保持至启动释放 / Done, holds until start released *)
    eFault := 90        (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PaintRobotPathSeq
VAR_INPUT
    xStart : BOOL;              (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    nSegTotal : INT;            (* 轨迹总段数 [段] Total segment count *)
    nSegIdxIn : INT;            (* 起始段索引 [段] Initial segment index *)
    fGunDistActMm : REAL;       (* 枪距实测 [mm] Gun distance actual [mm] *)
    fGunDistSpMm : REAL;        (* 枪距设定 [mm] Gun distance setpoint [mm] *)
    xSegDone : BOOL;            (* 当前段完成反馈（上升沿有效） [-] Segment done feedback *)
END_VAR
VAR_OUTPUT
    nSegIdxOut : INT;           (* 当前段索引 [段] Present segment index *)
    fGunDistCompMm : REAL;      (* 枪距补偿量 [mm] Gun distance compensation [mm] *)
    xPathDone : BOOL;           (* 轨迹完成单拍脉冲 [-] One-scan path done pulse *)
    xFault : BOOL;              (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _eState : E_DL_DpsState := E_DL_DpsState.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bDone : BOOL := FALSE;         (* 单拍完成标志（段 1 预清） [-] One-scan done flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 配置非法当拍量 [-] Configuration bad *)
    _nSeg : INT := 1;               (* 段索引保持量 [段] Segment index hold *)
    _fComp : REAL := 0.0;           (* 枪距补偿保持量 [mm] Compensation hold [mm] *)
    rtSeg : R_TRIG;                 (* 段完成沿（段 0 无条件调用） / Segment done edge *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_DPS_COMP_MAX : REAL := 5.0;      (* 补偿量行程限 [mm] Compensation stroke limit [mm] *)
    DL_DPS_SEG_MAX : INT := 999;        (* 段数上限 [段] Segment count ceiling *)
    DL_DPS_DIST_MIN : REAL := 10.0;     (* 枪距下限 [mm] Gun distance floor [mm] *)
    DL_DPS_DIST_MAX : REAL := 400.0;    (* 枪距上限 [mm] Gun distance ceiling [mm] *)
END_VAR
(* —— 段 0：两沿无条件周期刷新（R7） —— *)
rtStart(CLK := xStart);                     (* 启动沿 / Start edge *)
rtSeg(CLK := xSegDone);                     (* 段完成沿 / Segment done edge *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 域闸：两枪距入参与段数全枚举（R272） *)
_bCfgBad := (fGunDistActMm <> fGunDistActMm) OR ((fGunDistActMm - fGunDistActMm) <> 0.0)
         OR (fGunDistSpMm <> fGunDistSpMm) OR ((fGunDistSpMm - fGunDistSpMm) <> 0.0)
         OR (fGunDistActMm < DL_DPS_DIST_MIN) OR (fGunDistActMm > DL_DPS_DIST_MAX)
         OR (fGunDistSpMm < DL_DPS_DIST_MIN) OR (fGunDistSpMm > DL_DPS_DIST_MAX)
         OR (nSegTotal < 1) OR (nSegTotal > DL_DPS_SEG_MAX)
         OR (nSegIdxIn < 1) OR (nSegIdxIn > nSegTotal);
(* 枪距补偿：设定 − 实测，钳 ±行程限 *)
_fComp := fGunDistSpMm - fGunDistActMm;
IF _fComp > DL_DPS_COMP_MAX THEN
    _fComp := DL_DPS_COMP_MAX;
ELSIF _fComp < (0.0 - DL_DPS_COMP_MAX) THEN
    _fComp := 0.0 - DL_DPS_COMP_MAX;
END_IF
(* —— 段 1：单拍量预清 + 组态故障请求 —— *)
_bDone := FALSE;
_bReqFault := FALSE;
IF _bCfgBad THEN
    _bReqFault := TRUE;                     (* 组态非法：段数/枪距越域 / Configuration bad *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                  (* 清锁存 / Clear latch *)
    _nSeg := 1;                             (* 段号归位 / Segment index reset *)
    _eState := E_DL_DpsState.eIdle;         (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_DpsState.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _nSeg := nSegIdxIn;                 (* 按外部起始段进入 / Start from given segment *)
        _eState := E_DL_DpsState.eRun;
    END_IF
E_DL_DpsState.eRun:
    IF rtSeg.Q THEN
        IF _nSeg < nSegTotal THEN
            _nSeg := _nSeg + 1;             (* 推进一段 / Advance one segment *)
        ELSE
            _bDone := TRUE;                 (* 末段完成：单拍脉冲 / Last segment done *)
            _eState := E_DL_DpsState.eDone;
        END_IF
    END_IF
E_DL_DpsState.eDone:
    IF NOT xStart THEN
        _eState := E_DL_DpsState.eIdle;     (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_DpsState.eFault:
    _fComp := fGunDistSpMm - fGunDistActMm; (* 故障相驻留：补偿量照算供追溯，不迁相 *)
ELSE
    _bReqFault := TRUE;                     (* 非法相兜底 / Illegal phase fallback *)
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                   (* 锁存 / Latch *)
    _eState := E_DL_DpsState.eFault;        (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值；补偿量在段 0 已按行程限钳定） —— *)
nSegIdxOut := _nSeg;
(* 出口非有限/越界闸：NOT(x<=lim) 对 NaN 为真，防补偿量 NaN 直穿 *)
IF NOT ((_fComp <= 1000.0) AND (_fComp >= -1000.0)) THEN
    _fComp := 0.0;                          (* 归零补偿，保持原枪距 / Zero comp, keep gun distance *)
END_IF
fGunDistCompMm := _fComp;
xPathDone := _bDone;
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
