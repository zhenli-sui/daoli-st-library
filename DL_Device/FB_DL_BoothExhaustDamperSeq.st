(*
  Name: FB_DL_BoothExhaustDamperSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：喷房排风风门开度顺序：起机预吹→生产→清洗大风量→停机，斜坡按周期步进，含卡涩监视。
  边界条件：① 四浮点入参全部过非有限闸；配置越域进冻结分支：输出保持末值 + xValid = FALSE（R191）；
            ② 目标开度按模式赋值：预吹取 min(60 %, 外部设定)、生产取外部设定、清洗取 100 %（大风量）；
            ③ 斜坡步长 = fRampPctPerS × fCycleS，周期非法取 10 ms 缺省；开度钳 0~100 %；
            ④ 卡涩监视：实际开度与斜坡输出偏差 > 10 % 时锁故障（风门卡滞/执行器失气）；
            ⑤ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eRamp / eHold / eFault（CASE 含 ELSE 兜底；模式亦用 ENUM + CASE 兜底）。
*)
TYPE E_DL_BedMode :
(
    ePurge   := 0,      (* 预吹模式：低开度预吹 / Purge mode, low opening *)
    eProduce := 1,      (* 生产模式：按外部设定 / Production mode, external setpoint *)
    eClean   := 2       (* 清洗模式：大风量满开 / Cleaning mode, full opening *)
);
END_TYPE
TYPE E_DL_BedsPhase :
(
    eIdle  := 0,        (* 停机相：斜坡回 0 / Stopped, ramping to zero *)
    eRamp  := 10,       (* 斜坡相：向目标开度推进 / Ramping to setpoint *)
    eHold  := 20,       (* 保持相：已在目标开度带内 / Holding at setpoint *)
    eFault := 90        (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_BoothExhaustDamperSeq
VAR_INPUT
    xStart : BOOL;              (* 起机命令 [-] Start command *)
    eMode : E_DL_BedMode;       (* 运行模式（0 预吹 / 1 生产 / 2 清洗） [-] Operating mode *)
    fDamperActPct : REAL;       (* 风门实际开度 [%] Damper actual opening [%] *)
    fDamperSpPct : REAL;        (* 生产模式开度设定 [%] Production setpoint opening [%] *)
    fRampPctPerS : REAL;        (* 斜坡速率 [%/s] Ramp rate [%/s] *)
    fCycleS : REAL;             (* 扫描周期 [s] Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    xDamperCmd : BOOL;          (* 风门开命令 [-] Damper open command *)
    fDamperOutPct : REAL;       (* 风门开度输出（斜坡后） [%] Damper opening output [%] *)
    eState : E_DL_BedsPhase;     (* 当前相 [-] Present phase *)
    xValid : BOOL;              (* 配置与链路有效 [-] Configuration and chain valid *)
END_VAR
VAR
    _eState : E_DL_BedsPhase := E_DL_BedsPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bCfgBad : BOOL := FALSE;       (* 配置非法当拍量 [-] Configuration bad *)
    _bCalcOk : BOOL := FALSE;       (* 本拍计算有效 [-] Calculation valid this scan *)
    _bStuck : BOOL := FALSE;        (* 卡涩判据 [-] Damper stuck *)
    _fOut : REAL := 0.0;            (* 开度斜坡保持量 [%] Opening hold [%] *)
    _fSp : REAL := 0.0;             (* 当拍目标开度 [%] Target opening [%] *)
    _fStep : REAL := 0.0;           (* 单拍斜坡步长 [%] Ramp step [%] *)
    _fCy : REAL := 0.01;            (* 当拍有效周期 [s] Effective cycle [s] *)
END_VAR
VAR CONSTANT
    DL_BDS_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_BDS_PURGE : REAL := 60.0;        (* 预吹开度 [%] Purge opening [%] *)
    DL_BDS_CLEAN : REAL := 100.0;       (* 清洗开度 [%] Cleaning opening [%] *)
    DL_BDS_TOL : REAL := 1.0;           (* 到位带半宽 [%] In-position band [%] *)
    DL_BDS_STUCK : REAL := 10.0;        (* 卡涩偏差门限 [%] Stuck deviation threshold [%] *)
    DL_BDS_CYDEF : REAL := 0.01;        (* 缺省扫描周期 [s] Default scan cycle [s] *)
    DL_BDS_PCT_MAX : REAL := 100.0;     (* 开度满量程 [%] Opening full scale [%] *)
END_VAR
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：四浮点入参全枚举（R272） *)
_bCfgBad := (fDamperActPct <> fDamperActPct) OR ((fDamperActPct - fDamperActPct) <> 0.0)
         OR (fDamperSpPct <> fDamperSpPct) OR ((fDamperSpPct - fDamperSpPct) <> 0.0)
         OR (fRampPctPerS <> fRampPctPerS) OR ((fRampPctPerS - fRampPctPerS) <> 0.0)
         OR (fCycleS <> fCycleS) OR ((fCycleS - fCycleS) <> 0.0)
         OR (fDamperActPct < 0.0) OR (fDamperActPct > DL_BDS_PCT_MAX)
         OR (fDamperSpPct < 0.0) OR (fDamperSpPct > DL_BDS_PCT_MAX)
         OR (fRampPctPerS < 1.0) OR (fRampPctPerS > 200.0);
(* 周期派生：非法周期取 10 ms 缺省 *)
IF (fCycleS > 0.0) AND (fCycleS <= 1.0) THEN
    _fCy := fCycleS;
ELSE
    _fCy := DL_BDS_CYDEF;
END_IF
_bCalcOk := xStart AND (NOT _bCfgBad);
(* 目标开度：按模式取值（ENUM + CASE，含 ELSE 兜底） *)
CASE eMode OF
E_DL_BedMode.ePurge:
    IF fDamperSpPct < DL_BDS_PURGE THEN
        _fSp := fDamperSpPct;               (* 预吹取设定与 60 % 的较小者 / Lower of setpoint and 60 % *)
    ELSE
        _fSp := DL_BDS_PURGE;
    END_IF
E_DL_BedMode.eProduce:
    _fSp := fDamperSpPct;                   (* 生产按外部设定 / Production uses setpoint *)
E_DL_BedMode.eClean:
    _fSp := DL_BDS_CLEAN;                   (* 清洗满开 / Cleaning full open *)
ELSE
    _fSp := 0.0;                            (* 非法模式：目标归零 / Illegal mode, zero target *)
END_CASE
(* 停机即目标归零（安全侧） *)
IF NOT _bCalcOk THEN
    _fSp := 0.0;
END_IF
(* 斜坡推进：步长 = 速率 × 周期，方向按目标与当前比较 *)
_fStep := fRampPctPerS * _fCy;
(* 非有限/越界步长闸：NOT(x>=0) 对 NaN 为真，防 NaN 直穿 _fOut 出口 *)
IF NOT ((_fStep >= 0.0) AND (_fStep <= 100.0)) THEN
    _fStep := 0.0;                          (* 步长归零，风门保持原位 / Zero step, hold position *)
END_IF
IF _fOut < (_fSp - DL_BDS_TOL) THEN
    _fOut := _fOut + _fStep;
    IF _fOut > _fSp THEN
        _fOut := _fSp;                      (* 上钳 / Upper clamp *)
    END_IF
ELSIF _fOut > (_fSp + DL_BDS_TOL) THEN
    _fOut := _fOut - _fStep;
    IF _fOut < _fSp THEN
        _fOut := _fSp;                      (* 下钳 / Lower clamp *)
    END_IF
END_IF
(* 卡涩判据：指令与实际偏差超门限（仅在斜坡/保持相监视） *)
_bStuck := ABS(_fOut - fDamperActPct) > DL_BDS_STUCK;
(* 状态机（ENUM + CASE，ELSE 兜底） *)
CASE _eState OF
E_DL_BedsPhase.eIdle:
    IF _bCalcOk THEN
        _eState := E_DL_BedsPhase.eRamp;     (* 起机 → 斜坡 / Start, ramp *)
    END_IF
E_DL_BedsPhase.eRamp:
    IF _bStuck THEN
        _eState := E_DL_BedsPhase.eFault;    (* 卡涩 → 故障 / Stuck, fault *)
    ELSIF ABS(_fOut - _fSp) <= DL_BDS_TOL THEN
        _eState := E_DL_BedsPhase.eHold;     (* 到位 → 保持 / In position, hold *)
    END_IF
E_DL_BedsPhase.eHold:
    IF NOT _bCalcOk THEN
        _eState := E_DL_BedsPhase.eIdle;     (* 停机 → 回斜坡关风门 / Stop, close damper *)
    ELSIF _bStuck THEN
        _eState := E_DL_BedsPhase.eFault;    (* 卡涩 → 故障 / Stuck, fault *)
    ELSIF ABS(_fOut - _fSp) > DL_BDS_TOL THEN
        _eState := E_DL_BedsPhase.eRamp;     (* 目标变化 → 回斜坡 / Target changed, re-ramp *)
    END_IF
E_DL_BedsPhase.eFault:
    _bFaultLatch := TRUE;                   (* 故障相锁存（码由相位表达） / Latch in fault phase *)
    IF NOT xStart THEN
        _bFaultLatch := FALSE;              (* 解除路径：启动释放（R152） / Released by start drop *)
        _eState := E_DL_BedsPhase.eIdle;     (* 回待机 / Back to idle *)
    END_IF
ELSE
    _bFaultLatch := TRUE;                   (* 非法相兜底 / Illegal phase fallback *)
    _eState := E_DL_BedsPhase.eFault;
END_CASE
(* 统一出口（单点赋值）：停机相也照实输出斜坡值，避免风门瞬断 *)
xDamperCmd := (_fOut > 0.5) OR (_eState = E_DL_BedsPhase.eRamp) OR (_eState = E_DL_BedsPhase.eHold);
fDamperOutPct := _fOut;
eState := _eState;
xValid := _bCalcOk;
END_FUNCTION_BLOCK
