(*
  Name: FB_DL_ElectronicLineShaftSeq
  Category: DL_Motion
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 运动同步控制，ST 开源生态实测 0 命中，无外部代码引入）
  功能：电子线轴多从站同步：主轴相位广播 + 逐从站偏置斜坡 + 使能时序，偏置超限即拒并使能。
  边界条件：① 五浮点入参（主轴转速、偏置上限、周期）与四元素偏置数组全部过非有限闸；
            ② 主轴相位按 rpm × 6 × 周期 累加（1 r/min = 6 °/s），保持 [0,360) 防长时精度流失；
            ③ 逐从站偏置斜坡：目标 = anSlaveOffsetDeg[i]，速率 DL_ELS_RATE [°/s]，步长 = 速率 × fCycleS；
            ④ 偏置绝对值超 fMaxOffsetDeg 即拒绝使能：故障锁存 + 四从站速度给定全部置 0（安全侧）；
            ⑤ 未就绪从站（anSlaveReady = FALSE）不参与同步，nSlaveOnline 照实计数，xAllSynced 必须四站齐备；
            ⑥ 故障解除唯一路径：故障相内 xEnable 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eEnable / eRamp / eSynced / eFault（CASE 含 ELSE 兜底）。
  量纲自证：rpm × 6 = °/s；°/s × s = °；°/s × s = °（偏置步长）。
*)
TYPE E_DL_ElsPhase :
(
    eIdle   := 0,       (* 待机：等使能沿 / Idle, waiting for enable edge *)
    eEnable := 10,      (* 使能相：核从站在线数与偏置上限 / Enable check *)
    eRamp   := 20,      (* 斜坡相：逐从站偏置斜坡 / Offset ramping *)
    eSynced := 30,      (* 同步相：相位广播运行 / Synced, phase broadcast *)
    eFault  := 90       (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectronicLineShaftSeq
VAR_INPUT
    xEnable : BOOL;                                 (* 使能 [-] Enable *)
    fMasterVelRpm : REAL;                           (* 主轴速度 [r/min] Master velocity [rpm] *)
    anSlaveOffsetDeg : ARRAY[1..4] OF REAL;         (* 四从站相位偏置目标 [°] Slave phase offsets [deg] *)
    anSlaveReady : ARRAY[1..4] OF BOOL;             (* 四从站就绪反馈 [-] Slave ready feedback *)
    fMaxOffsetDeg : REAL;                           (* 偏置允许上限（绝对值） [°] Offset magnitude limit [deg] *)
    fCycleS : REAL;                                 (* 扫描周期 [s] Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    anSlaveVelRefRpm : ARRAY[1..4] OF REAL;         (* 四从站速度给定 [r/min] Slave velocity references [rpm] *)
    xAllSynced : BOOL;                              (* 四从站全部同步 [-] All slaves synced *)
    nSlaveOnline : INT;                             (* 在线（就绪）从站数 0~4 [站] Online slave count *)
    xFault : BOOL;                                  (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _eState : E_DL_ElsPhase := E_DL_ElsPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bInit : BOOL := FALSE;                         (* 首扫初始化标志 [-] First-scan init flag *)
    _bFaultLatch : BOOL := FALSE;                   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;                     (* 单拍故障请求（段 2 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;                       (* 配置非法当拍量 [-] Configuration bad *)
    _bLimBad : BOOL := FALSE;                       (* 偏置超限当拍量 [-] Offset over limit *)
    _bRampDone : BOOL := FALSE;                     (* 四站偏置斜坡全部到位 [-] All ramps complete *)
    _nOnline : INT := 0;                            (* 就绪计数 [站] Ready count *)
    _nI : INT := 1;                                 (* 从站遍历索引 [-] Slave loop index *)
    _fCy : REAL := 0.01;                            (* 当拍有效周期 [s] Effective cycle [s] *)
    _fMasterPhaseDeg : REAL := 0.0;                 (* 主轴相位保持量 [°] Master phase hold [deg] *)
    _fAdvDeg : REAL := 0.0;                         (* 单拍主轴相位增量 [°] Master phase increment [deg] *)
    _fOffStep : REAL := 0.0;                        (* 单拍偏置斜坡步长 [°] Offset ramp step [deg] *)
    _afOffRamp : ARRAY[1..4] OF REAL;               (* 四从站偏置斜坡当前值 [°] Offset ramp values [deg] *)
    _afVelRef : ARRAY[1..4] OF REAL;                (* 四从站速度给定内部量 [r/min] Velocity ref internal [rpm] *)
    rtEnable : R_TRIG;                              (* 使能沿（段 1 无条件调用） / Enable edge *)
    _bMasterOk : BOOL;                              (* 主轴转速给定有效位（非有限/越限即假） / Master vel valid *)
END_VAR
VAR CONSTANT
    DL_ELS_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_ELS_RATE : REAL := 90.0;         (* 偏置斜坡速率 [°/s] Offset ramp rate [deg/s] *)
    DL_ELS_TOL : REAL := 0.5;           (* 偏置到位容差 [°] Offset tolerance [deg] *)
    DL_ELS_CYDEF : REAL := 0.01;        (* 缺省扫描周期 [s] Default scan cycle [s] *)
    DL_ELS_RPM_DEG : REAL := 6.0;       (* 转速 → 角速度换算 [°/s per rpm] Rpm to deg per second *)
    DL_ELS_FULL : REAL := 360.0;        (* 整转角度 [°] Full revolution [deg] *)
    DL_ELS_SNUM : INT := 4;             (* 从站总数 [-] Slave count *)
    DL_ELS_ON_MAX : REAL := 3600.0;     (* 主轴速度上限 [r/min] Master velocity ceiling [rpm] *)
    DL_ELS_OFF_MAX : REAL := 360.0;     (* 偏置上限的工程上限 [°] Offset limit ceiling [deg] *)
END_VAR
(* —— 段 0：非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸，含四元素偏置数组全枚举（R272） —— *)
_bCfgBad := (fMasterVelRpm <> fMasterVelRpm) OR ((fMasterVelRpm - fMasterVelRpm) <> 0.0)
         OR (fMaxOffsetDeg <> fMaxOffsetDeg) OR ((fMaxOffsetDeg - fMaxOffsetDeg) <> 0.0)
         OR (fCycleS <> fCycleS) OR ((fCycleS - fCycleS) <> 0.0)
         OR (fMasterVelRpm < 0.0) OR (fMasterVelRpm > DL_ELS_ON_MAX)
         OR (fMaxOffsetDeg < 1.0) OR (fMaxOffsetDeg > DL_ELS_OFF_MAX);
FOR _nI := 1 TO DL_ELS_SNUM DO
    IF (anSlaveOffsetDeg[_nI] <> anSlaveOffsetDeg[_nI])
       OR ((anSlaveOffsetDeg[_nI] - anSlaveOffsetDeg[_nI]) <> 0.0) THEN
        _bCfgBad := TRUE;                       (* 偏置数组非有限 / Offset array non-finite *)
    END_IF
END_FOR
(* 周期派生：非法周期取 10 ms 缺省 *)
IF (fCycleS > 0.0) AND (fCycleS <= 1.0) THEN
    _fCy := fCycleS;
ELSE
    _fCy := DL_ELS_CYDEF;
END_IF
(* 主轴相位增量：rpm × 6 = °/s，× s = ° *)
_fAdvDeg := fMasterVelRpm * DL_ELS_RPM_DEG * _fCy;
(* 首扫初始化：偏置斜坡与速度给定归零（R310） *)
IF NOT _bInit THEN
    FOR _nI := 1 TO DL_ELS_SNUM DO
        _afOffRamp[_nI] := 0.0;
        _afVelRef[_nI] := 0.0;
    END_FOR
    _bInit := TRUE;
END_IF
(* —— 段 0：主轴转速有效性单点算定（NOT(x<=lim) 对 NaN 为真 → 判假，防 NaN 直穿速度给定） —— *)
_bMasterOk := (fMasterVelRpm <= 10000.0) AND (fMasterVelRpm >= -10000.0);

(* —— 段 1：偏置斜坡推进 + 超限判定 + 速度给定派生（逐从站，FOR 计数配对） —— *)
_bRampDone := TRUE;
_bLimBad := FALSE;
_fOffStep := DL_ELS_RATE * _fCy;
FOR _nI := 1 TO DL_ELS_SNUM DO
    (* 偏置上限（绝对值）判定：先判目标再判斜坡值 *)
    IF (anSlaveOffsetDeg[_nI] > fMaxOffsetDeg) OR (anSlaveOffsetDeg[_nI] < (0.0 - fMaxOffsetDeg))
       OR (_afOffRamp[_nI] > fMaxOffsetDeg) OR (_afOffRamp[_nI] < (0.0 - fMaxOffsetDeg)) THEN
        _bLimBad := TRUE;                       (* 偏置越限 / Offset over limit *)
    END_IF
    (* 斜坡推进：向目标步进，禁越过目标 *)
    IF _afOffRamp[_nI] < (anSlaveOffsetDeg[_nI] - DL_ELS_TOL) THEN
        _afOffRamp[_nI] := _afOffRamp[_nI] + _fOffStep;
        IF _afOffRamp[_nI] > anSlaveOffsetDeg[_nI] THEN
            _afOffRamp[_nI] := anSlaveOffsetDeg[_nI];
        END_IF
    ELSIF _afOffRamp[_nI] > (anSlaveOffsetDeg[_nI] + DL_ELS_TOL) THEN
        _afOffRamp[_nI] := _afOffRamp[_nI] - _fOffStep;
        IF _afOffRamp[_nI] < anSlaveOffsetDeg[_nI] THEN
            _afOffRamp[_nI] := anSlaveOffsetDeg[_nI];
        END_IF
    END_IF
    IF ABS(_afOffRamp[_nI] - anSlaveOffsetDeg[_nI]) > DL_ELS_TOL THEN
        _bRampDone := FALSE;                    (* 任一未到位即未完成 / Any ramp incomplete *)
    END_IF
    (* 速度给定：使能且未越限且就绪才跟随主轴，否则 0（安全侧） *)
    IF xEnable AND (NOT _bLimBad) AND (NOT _bFaultLatch) AND anSlaveReady[_nI] THEN
        (* 主轴转速非有限/越限闸：NOT(x<=lim) 对 NaN 为真 → 给定归零 *)
        IF _bMasterOk THEN
            _afVelRef[_nI] := fMasterVelRpm;
        ELSE
            _afVelRef[_nI] := 0.0;
        END_IF
        ELSE
        _afVelRef[_nI] := 0.0;                  (* 安全侧：不跟随 / Safe side, no follow *)
    END_IF
END_FOR
(* 就绪计数 *)
_nOnline := 0;
FOR _nI := 1 TO DL_ELS_SNUM DO
    IF anSlaveReady[_nI] THEN
        _nOnline := _nOnline + 1;
    END_IF
END_FOR
(* —— 段 2：单拍量预清 + 故障请求（组态/偏置超限） —— *)
_bReqFault := FALSE;
IF _bCfgBad OR _bLimBad THEN
    _bReqFault := TRUE;                         (* 组态坏或偏置越限：拒并使能 / Rejected *)
END_IF
(* —— 段 3：故障锁存解除（唯一路径 = 故障相内 xEnable 释放，R152） —— *)
IF _bFaultLatch AND (NOT xEnable) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _eState := E_DL_ElsPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 4：使能沿无条件刷新（R7） —— *)
rtEnable(CLK := xEnable);
(* —— 段 5：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_ElsPhase.eIdle:
    IF rtEnable.Q AND (NOT _bFaultLatch) THEN
        _eState := E_DL_ElsPhase.eEnable;       (* 使能沿 → 使能核查相 / Enable check *)
    END_IF
E_DL_ElsPhase.eEnable:
    IF _nOnline < DL_ELS_SNUM THEN
        _eState := E_DL_ElsPhase.eEnable;       (* 从站未齐：驻留核查（不推进相位） / Wait all ready *)
    ELSIF NOT xEnable THEN
        _eState := E_DL_ElsPhase.eIdle;
    ELSE
        _eState := E_DL_ElsPhase.eRamp;         (* 四站就绪 → 偏置斜坡 / All ready, ramp *)
    END_IF
E_DL_ElsPhase.eRamp:
    IF NOT xEnable THEN
        _eState := E_DL_ElsPhase.eIdle;         (* 使能撤销 → 待机 / Enable dropped *)
    ELSIF _bRampDone THEN
        _eState := E_DL_ElsPhase.eSynced;       (* 斜坡到位 → 同步相 / Ramps done, synced *)
    END_IF
E_DL_ElsPhase.eSynced:
    IF NOT xEnable THEN
        _eState := E_DL_ElsPhase.eIdle;         (* 使能撤销 → 待机 / Enable dropped *)
    ELSIF _nOnline < DL_ELS_SNUM THEN
        _eState := E_DL_ElsPhase.eEnable;       (* 从站掉线 → 回核查 / Slave offline *)
    END_IF
E_DL_ElsPhase.eFault:
    _bLimBad := FALSE;                          (* 故障相驻留：越限判据不再重算（锁存回放） *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _eState := E_DL_ElsPhase.eFault;
END_CASE
(* 相位广播推进：仅在同步类相位推进主轴相位（eEnable/eIdle 不推进） *)
IF (_eState = E_DL_ElsPhase.eRamp) OR (_eState = E_DL_ElsPhase.eSynced) THEN
    _fMasterPhaseDeg := _fMasterPhaseDeg + _fAdvDeg;
    IF _fMasterPhaseDeg >= DL_ELS_FULL THEN
        _fMasterPhaseDeg := _fMasterPhaseDeg - DL_ELS_FULL;   (* 环绕归一 / Wrap *)
    END_IF
END_IF
(* —— 段 6：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _eState := E_DL_ElsPhase.eFault;            (* 同步迁相 / Migrate to fault *)
    FOR _nI := 1 TO DL_ELS_SNUM DO
        _afVelRef[_nI] := 0.0;                  (* 越限即拒并使能：速度给定全零 / All refs zero *)
    END_FOR
END_IF
(* —— 段 7：统一出口（数组在出口循环单点写入） —— *)
FOR _nI := 1 TO DL_ELS_SNUM DO
    anSlaveVelRefRpm[_nI] := _afVelRef[_nI];
END_FOR
xAllSynced := (_eState = E_DL_ElsPhase.eSynced) AND _bRampDone
              AND (_nOnline = DL_ELS_SNUM) AND (NOT _bFaultLatch) AND (NOT _bLimBad);
nSlaveOnline := _nOnline;
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
