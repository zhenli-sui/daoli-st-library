(*
  Name: FB_DL_ForgeDieLubeSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：锻模润滑喷涂顺序：吹扫→喷涂→吹干→允许锻造，三段时长各自独立 TON。
  边界条件：① 三段时长为 TIME 入参，必须 > 0，否则组态非法（101）立即锁故障；
            ② 吹扫/喷涂/吹干各用独立 TON，PT 分别取 tBlowS / tSprayS / tDryS，禁跨相共用（R100 无同拍双窗）；
            ③ 气源不足（xAirOk = FALSE）在启动申请存在时即锁故障（102），并撤喷涂与锻造许可；
            ④ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eBlow / eSpray / eDry / eReady / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_DlsPhase :
(
    eIdle  := 0,        (* 待机：等启动沿 / Idle, waiting for start edge *)
    eBlow  := 10,       (* 吹扫相：压缩空气吹净型腔 / Blow phase, air purge *)
    eSpray := 20,       (* 喷涂相：润滑剂喷涂 / Spray phase, lubricant *)
    eDry    := 30,      (* 吹干相：吹干残留 / Dry phase, air dry *)
    eReady := 40,       (* 锻造许可相：允许锻造 / Forge permit phase *)
    eFault := 90        (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ForgeDieLubeSeq
VAR_INPUT
    xStart : BOOL;      (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    tBlowS : TIME;      (* 吹扫时长 [ms] Blow duration [ms] *)
    tSprayS : TIME;     (* 喷涂时长 [ms] Spray duration [ms] *)
    tDryS : TIME;       (* 吹干时长 [ms] Dry duration [ms] *)
    xAirOk : BOOL;      (* 气源压力正常 [-] Air supply healthy *)
END_VAR
VAR_OUTPUT
    eState : E_DL_DlsPhase;  (* 当前相 [-] Present phase *)
    xSprayValve : BOOL;      (* 喷涂阀指令（仅喷涂相） [-] Spray valve command *)
    xAllowForge : BOOL;      (* 允许锻造 [-] Forge permitted *)
    xFault : BOOL;           (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _ePhase : E_DL_DlsPhase := E_DL_DlsPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    tonBlow : TON;                  (* 吹扫计时（段 0 无条件调用） / Blow timer *)
    tonSpray : TON;                 (* 喷涂计时（段 0 无条件调用） / Spray timer *)
    tonDry : TON;                   (* 吹干计时（段 0 无条件调用） / Dry timer *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
(* —— 段 0：沿与三 TON 无条件周期刷新（R7），IN 仅由相位派生 —— *)
rtStart(CLK := xStart);                                             (* 启动沿 / Start edge *)
tonBlow(IN := (_ePhase = E_DL_DlsPhase.eBlow), PT := tBlowS);       (* 吹扫计时 / Blow timer *)
tonSpray(IN := (_ePhase = E_DL_DlsPhase.eSpray), PT := tSprayS);    (* 喷涂计时 / Spray timer *)
tonDry(IN := (_ePhase = E_DL_DlsPhase.eDry), PT := tDryS);          (* 吹干计时 / Dry timer *)
(* —— 段 1：单拍量预清 + 组态/气源故障请求（本件无码出口，成因由相位 + xFault 表达） —— *)
_bReqFault := FALSE;
IF (tBlowS <= T#0S) OR (tSprayS <= T#0S) OR (tDryS <= T#0S) THEN
    _bReqFault := TRUE;                         (* 组态非法：时长为零 / Configuration bad, zero duration *)
ELSIF xStart AND (NOT xAirOk) THEN
    _bReqFault := TRUE;                         (* 气源不足 / Air supply low *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _ePhase := E_DL_DlsPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_DlsPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) AND xAirOk THEN
        _ePhase := E_DL_DlsPhase.eBlow;         (* 起序 → 吹扫 / Start, blow *)
    END_IF
E_DL_DlsPhase.eBlow:
    IF tonBlow.Q THEN
        _ePhase := E_DL_DlsPhase.eSpray;        (* 吹扫到时 → 喷涂 / Blow done, spray *)
    END_IF
E_DL_DlsPhase.eSpray:
    IF tonSpray.Q THEN
        _ePhase := E_DL_DlsPhase.eDry;          (* 喷涂到时 → 吹干 / Spray done, dry *)
    END_IF
E_DL_DlsPhase.eDry:
    IF tonDry.Q THEN
        _ePhase := E_DL_DlsPhase.eReady;        (* 吹干到时 → 许可锻造 / Dry done, permit *)
    END_IF
E_DL_DlsPhase.eReady:
    IF NOT xStart THEN
        _ePhase := E_DL_DlsPhase.eIdle;         (* 启动释放 → 待机（撤许可） / Start released *)
    END_IF
E_DL_DlsPhase.eFault:
    _bReqFault := FALSE;                        (* 故障相驻留：锁存已置，不再新发请求 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _ePhase := E_DL_DlsPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
eState := _ePhase;
xSprayValve := (_ePhase = E_DL_DlsPhase.eSpray) AND (NOT _bFaultLatch);
xAllowForge := (_ePhase = E_DL_DlsPhase.eReady) AND (NOT _bFaultLatch) AND xAirOk;
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
