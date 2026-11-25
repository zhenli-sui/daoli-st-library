(*
  Name: FB_DL_CamSlavePhaseOffsetSeq
  Category: DL_Motion
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 运动同步控制，ST 开源生态实测 0 命中，无外部代码引入）
  功能：凸轮从动相位偏置在线切换：偏置斜坡 + 接合点判定，非接合点/关键区一律拒绝并给出 ENUM 原因。
  边界条件：① 五浮点入参全部过非有限闸，配置越域即锁故障（eFault），拒因出口同拍置 eCfgBad；
            ② 切换许可四项与门：使能、啮合（xInMesh）、非关键区、目标在 ±90° 内；任一不满足即拒并锁拒因；
            ③ 关键区（接合禁区）定义为相位 0~20° 与 340~360° 两段（相位按 0~360 口径输入）；
            ④ 斜坡起点取实测偏置 fOffsetActDeg，避免切换瞬间偏置跳变；步长 = fRampDegPerS × fCycleS；
            ⑤ 斜坡中若啮合丢失立即中止（拒因 eNotInMesh），已走偏置保持，不再回退；
            ⑥ 故障解除唯一路径：故障相内 xEnable 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eHold / eRamp / eFault（CASE 含 ELSE 兜底）。
  量纲自证：°/s × s = °；偏置与目标同为 °，容差比较同量纲。
*)
TYPE E_DL_CspoPhase :
(
    eIdle  := 0,        (* 待机：未使能 / Idle, not enabled *)
    eHold  := 10,       (* 保持相：偏置保持，等切换申请 / Hold, waiting switch request *)
    eRamp  := 20,       (* 斜坡相：偏置向目标推进 / Ramping offset to target *)
    eFault := 90        (* 故障相：配置越域锁存 / Fault, configuration latched *)
);
END_TYPE
TYPE E_DL_CspoReject :
(
    eNone       := 0,   (* 无拒绝（最近一次切换被接受） / No rejection, last switch accepted *)
    eNotEnabled := 1,   (* 拒绝：未使能 / Rejected, not enabled *)
    eNotInMesh  := 2,   (* 拒绝：凸轮未啮合（或斜坡中脱啮） / Rejected, cam not in mesh *)
    eKeyZone    := 3,   (* 拒绝：处于关键区（接合禁区） / Rejected, inside key zone *)
    eTargetLim  := 4,   (* 拒绝：目标偏置超 ±90° / Rejected, target beyond limit *)
    eCfgBad     := 5    (* 拒绝：组态非法（非有限或越域） / Rejected, bad configuration *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CamSlavePhaseOffsetSeq
VAR_INPUT
    xEnable : BOOL;             (* 使能 [-] Enable *)
    xSwitchCmd : BOOL;          (* 切换申请（上升沿有效） [-] Switch request, rising edge *)
    fPhaseActDeg : REAL;        (* 凸轮实际相位（0~360） [°] Cam actual phase [deg] *)
    fOffsetTargetDeg : REAL;    (* 目标偏置 [°] Target offset [deg] *)
    fOffsetActDeg : REAL;       (* 实测偏置（斜坡起点） [°] Actual offset [deg] *)
    fRampDegPerS : REAL;        (* 偏置斜坡速率 [°/s] Offset ramp rate [deg/s] *)
    xInMesh : BOOL;             (* 凸轮啮合反馈 [-] Cam in mesh *)
    fCycleS : REAL;             (* 扫描周期 [s] Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    fOffsetOutDeg : REAL;       (* 偏置输出（斜坡后） [°] Offset output [deg] *)
    eState : E_DL_CspoPhase;    (* 当前相 [-] Present phase *)
    xApplyDone : BOOL;          (* 切换完成单拍脉冲 [-] One-scan apply done *)
    xRejectReason : E_DL_CspoReject;    (* 最近一次切换的拒绝原因 [-] Reject reason *)
    xFault : BOOL;              (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _eState : E_DL_CspoPhase := E_DL_CspoPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _eReject : E_DL_CspoReject := E_DL_CspoReject.eNone;   (* 拒因锁存 [-] Reject reason latch *)
    _bInit : BOOL := FALSE;         (* 首扫初始化标志 [-] First-scan init flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bApply : BOOL := FALSE;        (* 单拍完成标志（段 2 预清） [-] One-scan apply flag *)
    _bRampReq : BOOL := FALSE;      (* 当拍切换受理标志（段 2 预清） [-] Switch accepted flag *)
    _bCfgBad : BOOL := FALSE;       (* 配置非法当拍量 [-] Configuration bad *)
    _bKeyZone : BOOL := FALSE;      (* 关键区判据 [-] Inside key zone *)
    _fOut : REAL := 0.0;            (* 偏置输出保持量 [°] Offset output hold [deg] *)
    _fStep : REAL := 0.0;           (* 单拍斜坡步长 [°] Ramp step [deg] *)
    _fCy : REAL := 0.01;            (* 当拍有效周期 [s] Effective cycle [s] *)
    rtSwitch : R_TRIG;              (* 切换沿（段 1 无条件调用） / Switch edge *)
END_VAR
VAR CONSTANT
    DL_CSPO_TOL : REAL := 0.05;     (* 偏置到位容差 [°] Offset tolerance [deg] *)
    DL_CSPO_MAX : REAL := 90.0;     (* 目标偏置工程限 [°] Target offset limit [deg] *)
    DL_CSPO_KEY_HALF : REAL := 20.0;(* 关键区半宽（0~20 与 340~360） [°] Key zone half width [deg] *)
    DL_CSPO_FULL : REAL := 360.0;   (* 整转角度 [°] Full revolution [deg] *)
    DL_CSPO_CYDEF : REAL := 0.01;   (* 缺省扫描周期 [s] Default scan cycle [s] *)
    DL_CSPO_RATE_MIN : REAL := 1.0; (* 斜坡速率下限 [°/s] Ramp rate floor [deg/s] *)
    DL_CSPO_RATE_MAX : REAL := 720.0;   (* 斜坡速率上限 [°/s] Ramp rate ceiling [deg/s] *)
END_VAR
(* —— 段 0：非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸，五浮点入参全枚举（R272） —— *)
_bCfgBad := (fPhaseActDeg <> fPhaseActDeg) OR ((fPhaseActDeg - fPhaseActDeg) <> 0.0)
         OR (fOffsetTargetDeg <> fOffsetTargetDeg) OR ((fOffsetTargetDeg - fOffsetTargetDeg) <> 0.0)
         OR (fOffsetActDeg <> fOffsetActDeg) OR ((fOffsetActDeg - fOffsetActDeg) <> 0.0)
         OR (fRampDegPerS <> fRampDegPerS) OR ((fRampDegPerS - fRampDegPerS) <> 0.0)
         OR (fCycleS <> fCycleS) OR ((fCycleS - fCycleS) <> 0.0)
         OR (fPhaseActDeg < 0.0) OR (fPhaseActDeg > DL_CSPO_FULL)
         OR (fOffsetTargetDeg > DL_CSPO_MAX) OR (fOffsetTargetDeg < (0.0 - DL_CSPO_MAX))
         OR (fOffsetActDeg > DL_CSPO_MAX) OR (fOffsetActDeg < (0.0 - DL_CSPO_MAX))
         OR (fRampDegPerS < DL_CSPO_RATE_MIN) OR (fRampDegPerS > DL_CSPO_RATE_MAX);
(* 关键区判据：相位 0~20° 或 340~360° 为接合禁区 *)
_bKeyZone := (fPhaseActDeg <= DL_CSPO_KEY_HALF)
          OR (fPhaseActDeg >= (DL_CSPO_FULL - DL_CSPO_KEY_HALF));
(* 周期派生：非法周期取 10 ms 缺省 *)
IF (fCycleS > 0.0) AND (fCycleS <= 1.0) THEN
    _fCy := fCycleS;
ELSE
    _fCy := DL_CSPO_CYDEF;
END_IF
(* 首扫初始化：偏置输出以实测偏置播种，避免首拍跳变（R310） *)
IF NOT _bInit THEN
    (* 播种前非有限闸：NOT(x<=360) 对 NaN 为真，防 NaN 播种后永久冻结 *)
    IF (fOffsetActDeg <= 360.0) AND (fOffsetActDeg >= -360.0) THEN
        _fOut := fOffsetActDeg;
    ELSE
        _fOut := 0.0;                       (* 实测偏置无效即零播种 / Seed zero on invalid actual *)
    END_IF
    _bInit := TRUE;
END_IF
(* —— 段 1：切换沿无条件刷新（R7） —— *)
rtSwitch(CLK := xSwitchCmd);
(* —— 段 2：单拍量预清 —— *)
_bApply := FALSE;
_bRampReq := FALSE;
(* —— 段 3：切换受理校验（拒因唯一出口，逐项归因互不共用成员，R190） —— *)
IF rtSwitch.Q THEN
    IF _bCfgBad THEN
        _eReject := E_DL_CspoReject.eCfgBad;        (* 组态非法 / Bad configuration *)
    ELSIF NOT xEnable THEN
        _eReject := E_DL_CspoReject.eNotEnabled;    (* 未使能 / Not enabled *)
    ELSIF NOT xInMesh THEN
        _eReject := E_DL_CspoReject.eNotInMesh;     (* 未啮合 / Not in mesh *)
    ELSIF _bKeyZone THEN
        _eReject := E_DL_CspoReject.eKeyZone;       (* 关键区 / Key zone *)
    ELSIF (fOffsetTargetDeg > DL_CSPO_MAX) OR (fOffsetTargetDeg < (0.0 - DL_CSPO_MAX)) THEN
        _eReject := E_DL_CspoReject.eTargetLim;     (* 目标越限 / Target over limit *)
    ELSE
        _eReject := E_DL_CspoReject.eNone;          (* 受理 / Accepted *)
        _bRampReq := TRUE;
    END_IF
END_IF
(* —— 段 4：故障锁存解除（唯一路径 = 故障相内 xEnable 释放，R152） —— *)
IF _bFaultLatch AND (NOT xEnable) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _eState := E_DL_CspoPhase.eIdle;            (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 5：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_CspoPhase.eIdle:
    IF xEnable AND (NOT _bFaultLatch) THEN
        _fOut := fOffsetActDeg;                 (* 上电取实测偏置为起点 / Seed from actual *)
        _eState := E_DL_CspoPhase.eHold;
    END_IF
E_DL_CspoPhase.eHold:
    _fOut := fOffsetActDeg;                     (* 保持相：偏置跟随实测（外部闭环保持） / Hold *)
    IF NOT xEnable THEN
        _eState := E_DL_CspoPhase.eIdle;
    ELSIF _bRampReq THEN
        _fOut := fOffsetActDeg;                 (* 斜坡起点重置为实测值 / Reset start point *)
        _eState := E_DL_CspoPhase.eRamp;
    END_IF
E_DL_CspoPhase.eRamp:
    _fStep := fRampDegPerS * _fCy;              (* °/s × s = ° / Ramp step *)
    IF NOT xInMesh THEN
        _eReject := E_DL_CspoReject.eNotInMesh; (* 斜坡中脱啮：中止 / Mesh lost, abort *)
        _eState := E_DL_CspoPhase.eHold;
    ELSIF NOT xEnable THEN
        _eState := E_DL_CspoPhase.eIdle;        (* 使能撤销 / Enable dropped *)
    ELSIF _fOut < (fOffsetTargetDeg - DL_CSPO_TOL) THEN
        _fOut := _fOut + _fStep;
        IF _fOut > fOffsetTargetDeg THEN
            _fOut := fOffsetTargetDeg;          (* 上钳 / Upper clamp *)
        END_IF
    ELSIF _fOut > (fOffsetTargetDeg + DL_CSPO_TOL) THEN
        _fOut := _fOut - _fStep;
        IF _fOut < fOffsetTargetDeg THEN
            _fOut := fOffsetTargetDeg;          (* 下钳 / Lower clamp *)
        END_IF
    ELSE
        _fOut := fOffsetTargetDeg;              (* 到位落定 / Settle to target *)
        _bApply := TRUE;                        (* 单拍完成（段 2 预清） / One-scan done *)
        _eReject := E_DL_CspoReject.eNone;      (* 本次切换成功，清拒因 / Clear reject *)
        _eState := E_DL_CspoPhase.eHold;
    END_IF
E_DL_CspoPhase.eFault:
    _bKeyZone := (fPhaseActDeg <= DL_CSPO_KEY_HALF)
              OR (fPhaseActDeg >= (DL_CSPO_FULL - DL_CSPO_KEY_HALF));   (* 故障相驻留：判据照算 *)
ELSE
    _bCfgBad := TRUE;                           (* 非法相兜底 / Illegal phase fallback *)
    _eState := E_DL_CspoPhase.eFault;
END_CASE
(* —— 段 6：组态故障统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bCfgBad AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _eReject := E_DL_CspoReject.eCfgBad;        (* 拒因同拍置 eCfgBad / Reject cause *)
    _eState := E_DL_CspoPhase.eFault;           (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 7：统一出口（各出口单点赋值） —— *)
(* 出口非有限闸：偏置输出绝不外泄 NaN / INF *)
IF NOT ((_fOut <= 360.0) AND (_fOut >= -360.0)) THEN
    _fOut := 0.0;                           (* 归零偏置 / Zero offset *)
END_IF
fOffsetOutDeg := _fOut;
eState := _eState;
xApplyDone := _bApply;
xRejectReason := _eReject;
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
