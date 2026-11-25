(*
  Name: FB_DL_UncoilerMandrelSeq
  Category: DL_Device
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 板带剪切分条卷取，ST 开源生态实测 0 命中，无外部代码引入）
  功能：开卷机卷筒胀缩与压辊顺序：压辊压下→卷筒胀径→对中确认→允许穿带。
  边界条件：① 卷径与设定值过非有限闸；越域即故障（101）；
            ② 压辊/胀径/对中三相各用独立 TON，PT 均取 tTimeoutS，禁跨相共用（R100）；
            ③ 胀径确认用差值容差比较（±0.5 mm），禁浮点判等；
            ④ 故障解除唯一路径：故障相内 xStart 释放（R152），清锁存回 eIdle。
  状态机：eIdle / ePressRoll / eExpand / eCenter / eReady / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_UmsPhase :
(
    eIdle      := 0,    (* 待机：等启动沿 / Idle, waiting for start edge *)
    ePressRoll := 10,   (* 压辊相：等压下反馈 / Press roll, waiting down feedback *)
    eExpand    := 20,   (* 胀径相：等卷筒胀到设定 / Expanding to diameter setpoint *)
    eCenter    := 30,   (* 对中相：等对中确认 / Centering confirmation *)
    eReady     := 40,   (* 就绪相：允许穿带 / Ready, strip threading allowed *)
    eFault     := 90    (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_UncoilerMandrelSeq
VAR_INPUT
    xStart : BOOL;              (* 启动命令（上升沿起序） [-] Start command, rising edge *)
    fMandrelDiaMm : REAL;       (* 卷筒胀径实测 [mm] Mandrel diameter actual [mm] *)
    fMandrelDiaSetMm : REAL;    (* 卷筒胀径设定 [mm] Mandrel diameter setpoint [mm] *)
    xPressRollDown : BOOL;      (* 压辊压下到位反馈 [-] Press roll down feedback *)
    xCentered : BOOL;           (* 对中确认反馈 [-] Centering feedback *)
    tTimeoutS : TIME;           (* 单相超时窗 [ms] Phase timeout window [ms] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_UmsPhase;     (* 当前相 [-] Present phase *)
    xReady : BOOL;              (* 允许穿带 [-] Ready for strip threading *)
    xFault : BOOL;              (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;             (* 故障码 0/101 组态/102~104 超时/105 非法相 [-] Error code *)
END_VAR
VAR
    _ePhase : E_DL_UmsPhase := E_DL_UmsPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 组态非法当拍量 [-] Configuration bad *)
    _nErr : INT := 0;               (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested error code *)
    _fDiaErrMm : REAL := 0.0;       (* 胀径偏差绝对量 [mm] Absolute diameter deviation [mm] *)
    tonPress : TON;                 (* 压辊超时（段 0 无条件调用） / Press roll timeout *)
    tonExpand : TON;                (* 胀径超时（段 0 无条件调用） / Expand timeout *)
    tonCenter : TON;                (* 对中超时（段 0 无条件调用） / Centering timeout *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_UMS_TOL : REAL := 0.5;       (* 胀径到位容差 [mm] Diameter tolerance [mm] *)
END_VAR
(* —— 段 0：沿与三 TON 无条件周期刷新（R7），IN 仅由相位派生 —— *)
rtStart(CLK := xStart);                                                     (* 启动沿 / Start edge *)
tonPress(IN := (_ePhase = E_DL_UmsPhase.ePressRoll), PT := tTimeoutS);      (* 压辊超时 / Press timeout *)
tonExpand(IN := (_ePhase = E_DL_UmsPhase.eExpand), PT := tTimeoutS);        (* 胀径超时 / Expand timeout *)
tonCenter(IN := (_ePhase = E_DL_UmsPhase.eCenter), PT := tTimeoutS);        (* 对中超时 / Centering timeout *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸：两浮点入参全枚举（R272） *)
_bCfgBad := (fMandrelDiaMm <> fMandrelDiaMm) OR ((fMandrelDiaMm - fMandrelDiaMm) <> 0.0)
         OR (fMandrelDiaSetMm <> fMandrelDiaSetMm) OR ((fMandrelDiaSetMm - fMandrelDiaSetMm) <> 0.0)
         OR (fMandrelDiaSetMm < 300.0) OR (fMandrelDiaSetMm > 2200.0)
         OR (fMandrelDiaMm < 100.0) OR (fMandrelDiaMm > 2300.0) OR (tTimeoutS <= T#0S);
(* 胀径偏差绝对量：容差比较用差值，禁浮点判等 *)
_fDiaErrMm := ABS(fMandrelDiaMm - fMandrelDiaSetMm);
(* —— 段 1：单拍量预清零 —— *)
_bReqFault := FALSE;
_nReqErr := 0;
IF _bCfgBad THEN
    _bReqFault := TRUE; _nReqErr := 101;        (* 组态非法 / Configuration bad *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xStart 释放，R152） —— *)
IF _bFaultLatch AND (NOT xStart) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _nErr := 0;                                 (* 清码 / Clear code *)
    _ePhase := E_DL_UmsPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_UmsPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _ePhase := E_DL_UmsPhase.ePressRoll;    (* 起序 → 压辊压下 / Start, press roll down *)
    END_IF
E_DL_UmsPhase.ePressRoll:
    IF xPressRollDown THEN
        _ePhase := E_DL_UmsPhase.eExpand;       (* 压辊到位 → 胀径 / Pressed, expand *)
    ELSIF tonPress.Q THEN
        _bReqFault := TRUE; _nReqErr := 102;    (* 压辊超时 / Press roll timeout *)
    END_IF
E_DL_UmsPhase.eExpand:
    IF _fDiaErrMm <= DL_UMS_TOL THEN
        _ePhase := E_DL_UmsPhase.eCenter;       (* 胀到设定 → 对中 / Expanded, center *)
    ELSIF tonExpand.Q THEN
        _bReqFault := TRUE; _nReqErr := 103;    (* 胀径超时 / Expand timeout *)
    END_IF
E_DL_UmsPhase.eCenter:
    IF xCentered THEN
        _ePhase := E_DL_UmsPhase.eReady;        (* 对中确认 → 就绪 / Centered, ready *)
    ELSIF tonCenter.Q THEN
        _bReqFault := TRUE; _nReqErr := 104;    (* 对中超时 / Centering timeout *)
    END_IF
E_DL_UmsPhase.eReady:
    IF NOT xStart THEN
        _ePhase := E_DL_UmsPhase.eIdle;         (* 启动释放 → 待机（撤穿带许可） / Start released *)
    END_IF
E_DL_UmsPhase.eFault:
    _fDiaErrMm := ABS(fMandrelDiaMm - fMandrelDiaSetMm);   (* 故障相驻留：仅刷新偏差量供追溯 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 105;
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _ePhase := E_DL_UmsPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
eState := _ePhase;
xReady := (_ePhase = E_DL_UmsPhase.eReady) AND (NOT _bFaultLatch);
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
