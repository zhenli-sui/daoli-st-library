(*
  Name: FB_DL_FurnaceZoneHeatSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：多区加热炉分区升温监视与顺序校核：每区独立稳态判定，低温区未到位而高温区先到即判顺序违例。
  边界条件：① 八浮点入参（四区实测 + 四区设定）与公差、稳态窗全部过非有限闸；
            ② 每区独立 TON（tonZ1~tonZ4），PT 均取 tSettleS，禁跨区共用（R100 无同拍双窗）；
            ③ 顺序判据：区 i 已进带而存在设定更低（低 1 ℃ 以上）的区 j 尚未进带 → 违例 → 锁故障；
            ④ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eHeat / eAllReady / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_FzsState :
(
    eIdle     := 0,     (* 待机：等启动沿 / Idle, waiting for start edge *)
    eHeat     := 10,    (* 升温监视相：逐区稳态计时与顺序校核 / Heat monitoring *)
    eAllReady := 20,    (* 全区到位相：保持至启动释放 / All zones ready, holds *)
    eFault    := 90     (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FurnaceZoneHeatSeq
VAR_INPUT
    xStart : BOOL;                          (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    anZoneTempC : ARRAY[1..4] OF REAL;      (* 四区实测温度 [℃] Zone temperatures [degC] *)
    fZoneSpC : ARRAY[1..4] OF REAL;         (* 四区设定温度 [℃] Zone setpoints [degC] *)
    fDevTolC : REAL;                        (* 稳态带半宽 [℃] Steady band half-width [degC] *)
    tSettleS : TIME;                        (* 单区稳态窗 [ms] Per-zone settling window [ms] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_FzsState;                 (* 当前相 [-] Present phase *)
    nZoneReady : INT;                       (* 已稳态到位的区数（0~4） [区] Ready zone count *)
    xAllReady : BOOL;                       (* 四区全部到位 [-] All zones ready *)
    xFault : BOOL;                          (* 故障锁存标志 [-] Fault latched *)
END_VAR
VAR
    _eState : E_DL_FzsState := E_DL_FzsState.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _abBand : ARRAY[1..4] OF BOOL;          (* 各区在稳态带内 [-] Zone in steady band *)
    _abSettled : ARRAY[1..4] OF BOOL;       (* 各区稳态窗已满 [-] Zone settled *)
    _bFaultLatch : BOOL := FALSE;           (* 故障锁存位 [-] Fault latch *)
    _bCfgBad : BOOL := FALSE;               (* 组态非法当拍量 [-] Configuration bad *)
    _bOrderViol : BOOL := FALSE;            (* 升温顺序违例 [-] Heating order violation *)
    _bAllReady : BOOL := FALSE;             (* 全区到位当拍量 [-] All ready this scan *)
    _nReady : INT := 0;                     (* 到位区计数 [区] Ready count *)
    _nI : INT := 1;                         (* 区遍历索引（外层） [-] Outer loop index *)
    _nJ : INT := 1;                         (* 区遍历索引（内层） [-] Inner loop index *)
    tonZ1 : TON;                            (* 一区稳态窗（段 0 无条件调用） / Zone 1 window *)
    tonZ2 : TON;                            (* 二区稳态窗（段 0 无条件调用） / Zone 2 window *)
    tonZ3 : TON;                            (* 三区稳态窗（段 0 无条件调用） / Zone 3 window *)
    tonZ4 : TON;                            (* 四区稳态窗（段 0 无条件调用） / Zone 4 window *)
    rtStart : R_TRIG;                       (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_FZS_TOL_MIN : REAL := 0.5;       (* 稳态带半宽下限 [℃] Band floor [degC] *)
    DL_FZS_TOL_MAX : REAL := 50.0;      (* 稳态带半宽上限 [℃] Band ceiling [degC] *)
    DL_FZS_SP_MIN : REAL := 50.0;       (* 设定温度下限 [℃] Setpoint floor [degC] *)
    DL_FZS_SP_MAX : REAL := 1350.0;     (* 设定温度上限 [℃] Setpoint ceiling [degC] *)
    DL_FZS_ORD : REAL := 1.0;           (* 顺序比较死区（设定差大于此值才判前后） [℃] Order deadband [degC] *)
    DL_FZS_ZNUM : INT := 4;             (* 分区总数 [-] Zone count *)
END_VAR
(* —— 段 0：沿与四区稳态 TON 无条件周期刷新（R7），IN 由带内判据与相位共同派生 —— *)
rtStart(CLK := xStart);                                                     (* 启动沿 / Start edge *)
(* 带内判据：逐区算（NaN 与非有限在下面组态闸统一拦截，此处比较对 NaN 恒假即不进带） *)
FOR _nI := 1 TO DL_FZS_ZNUM DO
    _abBand[_nI] := (anZoneTempC[_nI] = anZoneTempC[_nI]) AND (ABS(anZoneTempC[_nI] - fZoneSpC[_nI]) <= fDevTolC);
END_FOR
tonZ1(IN := _abBand[1] AND (_eState = E_DL_FzsState.eHeat), PT := tSettleS);   (* 一区稳态窗 / Zone 1 *)
tonZ2(IN := _abBand[2] AND (_eState = E_DL_FzsState.eHeat), PT := tSettleS);   (* 二区稳态窗 / Zone 2 *)
tonZ3(IN := _abBand[3] AND (_eState = E_DL_FzsState.eHeat), PT := tSettleS);   (* 三区稳态窗 / Zone 3 *)
tonZ4(IN := _abBand[4] AND (_eState = E_DL_FzsState.eHeat), PT := tSettleS);   (* 四区稳态窗 / Zone 4 *)
_abSettled[1] := tonZ1.Q;                   (* 一区到位 / Zone 1 settled *)
_abSettled[2] := tonZ2.Q;                   (* 二区到位 / Zone 2 settled *)
_abSettled[3] := tonZ3.Q;                   (* 三区到位 / Zone 3 settled *)
_abSettled[4] := tonZ4.Q;                   (* 四区到位 / Zone 4 settled *)
(* 非有限闸 + 组态域闸：公差、稳态窗与八区温度量全枚举（R272） *)
_bCfgBad := (fDevTolC <> fDevTolC) OR ((fDevTolC - fDevTolC) <> 0.0)
         OR (fDevTolC < DL_FZS_TOL_MIN) OR (fDevTolC > DL_FZS_TOL_MAX)
         OR (tSettleS <= T#0S);
FOR _nI := 1 TO DL_FZS_ZNUM DO
    IF (anZoneTempC[_nI] <> anZoneTempC[_nI]) OR ((anZoneTempC[_nI] - anZoneTempC[_nI]) <> 0.0)
       OR (fZoneSpC[_nI] <> fZoneSpC[_nI]) OR ((fZoneSpC[_nI] - fZoneSpC[_nI]) <> 0.0)
       OR (fZoneSpC[_nI] < DL_FZS_SP_MIN) OR (fZoneSpC[_nI] > DL_FZS_SP_MAX) THEN
        _bCfgBad := TRUE;
    END_IF
END_FOR
(* 顺序校核：区 i 已进带，而存在设定更低（低 DL_FZS_ORD 以上）的区 j 尚未进带 → 违例 *)
_bOrderViol := FALSE;
FOR _nI := 1 TO DL_FZS_ZNUM DO
    IF _abBand[_nI] THEN
        FOR _nJ := 1 TO DL_FZS_ZNUM DO
            IF (fZoneSpC[_nJ] < (fZoneSpC[_nI] - DL_FZS_ORD)) AND (NOT _abBand[_nJ]) THEN
                _bOrderViol := TRUE;
            END_IF
        END_FOR
    END_IF
END_FOR
(* 到位计数：稳态窗满即计入 *)
_nReady := 0;
FOR _nI := 1 TO DL_FZS_ZNUM DO
    IF _abSettled[_nI] THEN
        _nReady := _nReady + 1;
    END_IF
END_FOR
_bAllReady := (_nReady = DL_FZS_ZNUM);
(* —— 段 1：单拍量预清 + 组态/顺序故障请求 —— *)
IF _bCfgBad OR _bOrderViol THEN
    _bFaultLatch := TRUE;                   (* 锁存 / Latch *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                  (* 清锁存 / Clear latch *)
    _eState := E_DL_FzsState.eIdle;         (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_FzsState.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _eState := E_DL_FzsState.eHeat;     (* 起序 → 升温监视 / Start, heat monitoring *)
    END_IF
E_DL_FzsState.eHeat:
    IF _bFaultLatch THEN
        _eState := E_DL_FzsState.eFault;    (* 违例/组态坏 → 故障 / Violation, to fault *)
    ELSIF _bAllReady THEN
        _eState := E_DL_FzsState.eAllReady; (* 全区到位 → 到位相 / All ready *)
    END_IF
E_DL_FzsState.eAllReady:
    IF NOT xStart THEN
        _eState := E_DL_FzsState.eIdle;     (* 启动释放 → 待机 / Start released, idle *)
    END_IF
E_DL_FzsState.eFault:
    _bAllReady := (_nReady = DL_FZS_ZNUM);  (* 故障相驻留：到位判据照算供追溯，不迁相 *)
ELSE
    _bFaultLatch := TRUE;                   (* 非法相兜底 / Illegal phase fallback *)
    _eState := E_DL_FzsState.eFault;
END_CASE
(* —— 段 4：统一出口（各出口单点赋值） —— *)
eState := _eState;
nZoneReady := _nReady;
xAllReady := _bAllReady AND (NOT _bFaultLatch);
xFault := _bFaultLatch;
END_FUNCTION_BLOCK
