(*
  Name: FB_DL_ColorChangeSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 涂装喷涂线，ST 开源生态实测 0 命中，无外部代码引入）
  功能：换色清洗顺序：吹扫→溶剂冲洗→再吹干→试喷确认，三段时间与试喷确认窗口各自独立 TON。
  边界条件：① 三段时长必须 > 0，否则组态非法直接锁故障（本件无码出口，成因由相位 + xFault 表达）；
            ② 吹扫/冲洗/吹干各用独立 TON，PT 分别取 tBlowS / tFlushS / tDryS，禁跨相共用（R100）；
            ③ 试喷确认窗为固定时窗 DL_CCS_PILOT（10 s，无外部引脚），超窗未确认即锁故障；
            ④ 完成脉冲两段式：相内只置 _bDone，出口统一映射单拍，避免同拍抹除（R187）；
            ⑤ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eBlow / eFlush / eDry / ePilot / eDone / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_Ccs2Phase :
(
    eIdle  := 0,        (* 待机：等启动沿 / Idle, waiting for start edge *)
    eBlow  := 10,       (* 吹扫相：压缩空气吹除残漆 / Blow phase, purge residual paint *)
    eFlush := 20,       (* 冲洗相：溶剂冲洗管路 / Flush phase, solvent *)
    eDry    := 30,      (* 吹干相：吹干溶剂残留 / Dry phase, air dry *)
    ePilot := 40,       (* 试喷相：等试喷确认 / Pilot spray, waiting confirmation *)
    eDone  := 50,       (* 完成相：保持至启动释放 / Done, holds until start released *)
    eFault := 90        (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ColorChangeSeq
VAR_INPUT
    xStart : BOOL;          (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    tBlowS : TIME;          (* 吹扫时长 [ms] Blow duration [ms] *)
    tFlushS : TIME;         (* 溶剂冲洗时长 [ms] Flush duration [ms] *)
    tDryS : TIME;           (* 吹干时长 [ms] Dry duration [ms] *)
    xPilotOk : BOOL;        (* 试喷确认（膜厚/色差合格） [-] Pilot spray confirmed *)
END_VAR
VAR_OUTPUT
    eState : E_DL_Ccs2Phase;    (* 当前相 [-] Present phase *)
    xValveSolvent : BOOL;       (* 溶剂阀指令（仅冲洗相） [-] Solvent valve command *)
    xValveAir : BOOL;           (* 空气阀指令（吹扫/吹干相） [-] Air valve command *)
    xDone : BOOL;               (* 换色完成单拍脉冲 [-] One-scan done pulse *)
    xFault : BOOL;              (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _ePhase : E_DL_Ccs2Phase := E_DL_Ccs2Phase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bDone : BOOL := FALSE;         (* 单拍完成标志（段 1 预清） [-] One-scan done flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    tonBlow : TON;                  (* 吹扫计时（段 0 无条件调用） / Blow timer *)
    tonFlush : TON;                 (* 冲洗计时（段 0 无条件调用） / Flush timer *)
    tonDry : TON;                   (* 吹干计时（段 0 无条件调用） / Dry timer *)
    tonPilot : TON;                 (* 试喷确认窗（段 0 无条件调用） / Pilot confirm window *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_CCS2_PILOT : TIME := T#10S;  (* 试喷确认窗（固定时窗） [ms] Pilot confirmation window [ms] *)
END_VAR
(* —— 段 0：沿与四 TON 无条件周期刷新（R7），IN 仅由相位派生 —— *)
rtStart(CLK := xStart);                                                 (* 启动沿 / Start edge *)
tonBlow(IN := (_ePhase = E_DL_Ccs2Phase.eBlow), PT := tBlowS);          (* 吹扫计时 / Blow timer *)
tonFlush(IN := (_ePhase = E_DL_Ccs2Phase.eFlush), PT := tFlushS);       (* 冲洗计时 / Flush timer *)
tonDry(IN := (_ePhase = E_DL_Ccs2Phase.eDry), PT := tDryS);             (* 吹干计时 / Dry timer *)
tonPilot(IN := (_ePhase = E_DL_Ccs2Phase.ePilot), PT := DL_CCS2_PILOT); (* 试喷窗 / Pilot window *)
(* —— 段 1：单拍量预清 + 组态故障请求 —— *)
_bDone := FALSE;
_bReqFault := FALSE;
IF (tBlowS <= T#0S) OR (tFlushS <= T#0S) OR (tDryS <= T#0S) THEN
    _bReqFault := TRUE;                         (* 组态非法：时长为零 / Configuration bad, zero duration *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _ePhase := E_DL_Ccs2Phase.eIdle;            (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_Ccs2Phase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _ePhase := E_DL_Ccs2Phase.eBlow;        (* 起序 → 吹扫 / Start, blow *)
    END_IF
E_DL_Ccs2Phase.eBlow:
    IF tonBlow.Q THEN
        _ePhase := E_DL_Ccs2Phase.eFlush;       (* 吹扫到时 → 冲洗 / Blow done, flush *)
    END_IF
E_DL_Ccs2Phase.eFlush:
    IF tonFlush.Q THEN
        _ePhase := E_DL_Ccs2Phase.eDry;         (* 冲洗到时 → 吹干 / Flush done, dry *)
    END_IF
E_DL_Ccs2Phase.eDry:
    IF tonDry.Q THEN
        _ePhase := E_DL_Ccs2Phase.ePilot;       (* 吹干到时 → 试喷 / Dry done, pilot *)
    END_IF
E_DL_Ccs2Phase.ePilot:
    IF xPilotOk THEN
        _bDone := TRUE;                         (* 单拍完成（段 1 预清） / One-scan done *)
        _ePhase := E_DL_Ccs2Phase.eDone;        (* → 完成相 / To done *)
    ELSIF tonPilot.Q THEN
        _bReqFault := TRUE;                     (* 试喷窗超时未确认 / Pilot window expired *)
    END_IF
E_DL_Ccs2Phase.eDone:
    IF NOT xStart THEN
        _ePhase := E_DL_Ccs2Phase.eIdle;        (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_Ccs2Phase.eFault:
    _bReqFault := FALSE;                        (* 故障相驻留：锁存已置，不再新发请求 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _ePhase := E_DL_Ccs2Phase.eFault;           (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
eState := _ePhase;
xValveSolvent := (_ePhase = E_DL_Ccs2Phase.eFlush) AND (NOT _bFaultLatch);
xValveAir := ((_ePhase = E_DL_Ccs2Phase.eBlow) OR (_ePhase = E_DL_Ccs2Phase.eDry)) AND (NOT _bFaultLatch);
xDone := _bDone;
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
