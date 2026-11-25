(*
  Name: FB_DL_OvenCureProfileSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：烘干炉固化温度曲线执行顺序：升温→保温→冷却→出炉许可，每段结束判据独立。
  边界条件：① 温度与速率入参全部过非有限闸（含三元素设定数组逐项），配置越域即锁故障（101）；
            ② 保温段使用独立 TON（tonSoak，PT := tSoakS），与升温/冷却段判据不同源，无双窗配比问题（R100）；
            ③ 超温判据以段 1 设定 + 15 ℃ 为上限（固化段为最高温段），越限立即锁故障（102）；
            ④ 出炉许可为单拍脉冲（内部 _bDone 置位 → 出口映射），后驻留 eDone 至启动释放；
            ⑤ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eSeg1 / eSeg2 / eSeg3 / eDone / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_OcpPhase :
(
    eIdle := 0,         (* 待机：等启动沿 / Idle, waiting for start edge *)
    eSeg1 := 10,        (* 段 1 升温：升到固化温度带 / Segment 1, ramp to cure band *)
    eSeg2 := 20,        (* 段 2 保温：保温窗且带内 / Segment 2, soak window in band *)
    eSeg3 := 30,        (* 段 3 冷却：冷到出炉温度 / Segment 3, cool down *)
    eDone := 40,        (* 完成相：出炉许可后驻留 / Done, holds after discharge permit *)
    eFault := 90        (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_OvenCureProfileSeq
VAR_INPUT
    xStart : BOOL;                          (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    fTempActC : REAL;                       (* 炉温实测 [℃] Oven temperature actual [degC] *)
    fTempSpC : ARRAY[1..3] OF REAL;         (* 三段温度设定（升温/保温/冷却） [℃] Segment setpoints [degC] *)
    fRampCpm : REAL;                        (* 允许升温速率 [℃/min] Allowed ramp rate [degC/min] *)
    tSoakS : TIME;                          (* 保温窗 [ms] Soak window [ms] *)
    fCoolToC : REAL;                        (* 冷却目标（出炉温度） [℃] Cool-down target [degC] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_OcpPhase;                 (* 当前相 [-] Present phase *)
    nSegIdx : INT;                          (* 当前段号（0 空闲，1~3） [段] Present segment index *)
    xDone : BOOL;                           (* 出炉许可单拍脉冲 [-] Discharge permit pulse *)
    xFault : BOOL;                          (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _eState : E_DL_OcpPhase := E_DL_OcpPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bDone : BOOL := FALSE;         (* 单拍完成标志（段 1 预清） [-] One-scan done flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 配置非法当拍量 [-] Configuration bad *)
    _nSeg : INT := 0;               (* 段号保持量 [段] Segment index hold *)
    _nErr : INT := 0;               (* 故障码锁存（101 组态 / 102 超温 / 103 非法相） [-] Latched code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested code *)
    _nI : INT := 1;                 (* 设定数组遍历索引 [-] Setpoint loop index *)
    tonSoak : TON;                  (* 保温窗（段 0 无条件调用） / Soak window timer *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_OCP_TOL : REAL := 5.0;           (* 段到位带半宽 [℃] Segment in-band half-width [degC] *)
    DL_OCP_OVER : REAL := 15.0;         (* 超温裕度 [℃] Over-temperature margin [degC] *)
    DL_OCP_T_MIN : REAL := 0.0;         (* 温度下限 [℃] Temperature floor [degC] *)
    DL_OCP_T_MAX : REAL := 400.0;       (* 温度上限 [℃] Temperature ceiling [degC] *)
    DL_OCP_R_MIN : REAL := 0.5;         (* 允许速率下限 [℃/min] Ramp rate floor [degC/min] *)
    DL_OCP_R_MAX : REAL := 50.0;        (* 允许速率上限 [℃/min] Ramp rate ceiling [degC/min] *)
    DL_OCP_SEGN : INT := 3;             (* 设定段数 [-] Segment count *)
END_VAR
(* —— 段 0：沿与保温 TON 无条件周期刷新（R7） —— *)
rtStart(CLK := xStart);                                             (* 启动沿 / Start edge *)
tonSoak(IN := (_eState = E_DL_OcpPhase.eSeg2), PT := tSoakS);       (* 保温窗 / Soak window *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：标量与三元素数组全枚举（R272） *)
_bCfgBad := (fTempActC <> fTempActC) OR ((fTempActC - fTempActC) <> 0.0)
         OR (fRampCpm <> fRampCpm) OR ((fRampCpm - fRampCpm) <> 0.0)
         OR (fCoolToC <> fCoolToC) OR ((fCoolToC - fCoolToC) <> 0.0)
         OR (fTempActC < DL_OCP_T_MIN) OR (fTempActC > DL_OCP_T_MAX)
         OR (fCoolToC < DL_OCP_T_MIN) OR (fCoolToC > DL_OCP_T_MAX)
         OR (fRampCpm < DL_OCP_R_MIN) OR (fRampCpm > DL_OCP_R_MAX) OR (tSoakS <= T#0S);
FOR _nI := 1 TO DL_OCP_SEGN DO
    IF (fTempSpC[_nI] <> fTempSpC[_nI]) OR ((fTempSpC[_nI] - fTempSpC[_nI]) <> 0.0)
       OR (fTempSpC[_nI] < DL_OCP_T_MIN) OR (fTempSpC[_nI] > DL_OCP_T_MAX) THEN
        _bCfgBad := TRUE;
    END_IF
END_FOR
(* —— 段 1：单拍量预清 + 组态与超温故障请求 —— *)
_bDone := FALSE;
_bReqFault := FALSE;
_nReqErr := 0;
IF _bCfgBad THEN
    _bReqFault := TRUE; _nReqErr := 101;        (* 组态非法 / Configuration bad *)
ELSIF (NOT _bCfgBad) AND (fTempActC > (fTempSpC[1] + DL_OCP_OVER)) THEN
    _bReqFault := TRUE; _nReqErr := 102;        (* 超温 / Over-temperature *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _nErr := 0;                                 (* 清码 / Clear code *)
    _nSeg := 0;                                 (* 段号归零 / Segment index reset *)
    _eState := E_DL_OcpPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_OcpPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _nSeg := 1;                             (* 段 1 起算 / Segment 1 begins *)
        _eState := E_DL_OcpPhase.eSeg1;
    END_IF
E_DL_OcpPhase.eSeg1:
    IF ABS(fTempActC - fTempSpC[1]) <= DL_OCP_TOL THEN
        _nSeg := 2;                             (* 进带 → 保温段 / In band, soak segment *)
        _eState := E_DL_OcpPhase.eSeg2;
    END_IF
E_DL_OcpPhase.eSeg2:
    IF tonSoak.Q AND (ABS(fTempActC - fTempSpC[2]) <= DL_OCP_TOL) THEN
        _nSeg := 3;                             (* 保温窗到且带内 → 冷却段 / Soak done, cool *)
        _eState := E_DL_OcpPhase.eSeg3;
    END_IF
E_DL_OcpPhase.eSeg3:
    IF fTempActC <= fCoolToC THEN
        _bDone := TRUE;                         (* 单拍出炉许可（段 1 预清） / One-scan permit *)
        _nSeg := 0;                             (* 段号归零 / Segment index reset *)
        _eState := E_DL_OcpPhase.eDone;
    END_IF
E_DL_OcpPhase.eDone:
    IF NOT xStart THEN
        _eState := E_DL_OcpPhase.eIdle;         (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_OcpPhase.eFault:
    _nSeg := 0;                                 (* 故障相驻留：段号清零供 HMI 判别 / Residency *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 103;
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _eState := E_DL_OcpPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
eState := _eState;
nSegIdx := _nSeg;
xDone := _bDone;
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
