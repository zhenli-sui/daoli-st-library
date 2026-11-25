(*
  Name: FB_DL_FurnaceDoorInterlockSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 锻造加热退火，ST 开源生态实测 0 命中，无外部代码引入）
  功能：炉门与气氛/温度联锁开关顺序：开门前必须先断气氛、并降到安全温度以下、且炉内无正压。
  边界条件：① 三浮点入参全部过非有限闸；配置越域即锁故障（101）；
            ② 顺序强制：气氛未断不降温等待、温度未降到「安全温度 − 20 ℃」不给开门许可（带回差防抖）；
            ③ 正压（> 2.0 kPa）时禁止开门并锁故障（102），须泄压后重新申请；
            ④ 开门许可相内若温度回升或气氛复投，立即撤回许可并退回冷却等待相（安全侧优先）；
            ⑤ 故障解除唯一路径：故障相内 xOpenCmd 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eAtmosCut / eCoolWait / eDoorPermit / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_FdiState :
(
    eIdle      := 0,    (* 待机：等开门申请 / Idle, waiting for open request *)
    eAtmosCut  := 10,   (* 断气氛相：等气氛阀关闭反馈 / Atmos cut, waiting feedback *)
    eCoolWait  := 20,   (* 降温等待相：等温度降到安全值以下 / Cooling wait *)
    eDoorPermit := 30,  (* 开门许可相：允许开炉门 / Door permit *)
    eFault     := 90    (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_FurnaceDoorInterlockSeq
VAR_INPUT
    xOpenCmd : BOOL;        (* 开门申请 [-] Door open request *)
    fTempC : REAL;          (* 炉内温度实测 [℃] Furnace temperature actual [degC] *)
    fTempSafeC : REAL;      (* 安全开门温度 [℃] Safe opening temperature [degC] *)
    xAtmosOn : BOOL;        (* 气氛投入反馈（TRUE = 已投） [-] Atmosphere on feedback *)
    fPressKPa : REAL;       (* 炉内压力（表压） [kPa] Furnace gauge pressure [kPa] *)
END_VAR
VAR_OUTPUT
    xDoorPermit : BOOL;     (* 开门许可 [-] Door permit *)
    xAtmosCutCmd : BOOL;    (* 断气氛指令（顺序期间保持） [-] Atmosphere cut command *)
    xFault : BOOL;          (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;         (* 故障码 0/101 组态/102 正压超限/103 非法相 [-] Error code *)
END_VAR
VAR
    _eState : E_DL_FdiState := E_DL_FdiState.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 组态非法当拍量 [-] Configuration bad *)
    _bTempSafe : BOOL := FALSE;     (* 温度已降到安全值以下 [-] Temperature below safe value *)
    _bPressOk : BOOL := FALSE;      (* 炉内无正压 [-] No positive pressure *)
    _nErr : INT := 0;               (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested error code *)
END_VAR
VAR CONSTANT
    DL_FDI_HYST : REAL := 20.0;     (* 安全温度回差 [℃] Safety temperature hysteresis [degC] *)
    DL_FDI_PMAX : REAL := 2.0;      (* 允许开门正压上限 [kPa] Allowed positive pressure [kPa] *)
    DL_FDI_TS_MIN : REAL := 20.0;   (* 安全温度下限 [℃] Safe temperature floor [degC] *)
    DL_FDI_TS_MAX : REAL := 200.0;  (* 安全温度上限 [℃] Safe temperature ceiling [degC] *)
    DL_FDI_T_MIN : REAL := -50.0;   (* 炉温下限 [℃] Furnace temperature floor [degC] *)
    DL_FDI_T_MAX : REAL := 1400.0;  (* 炉温上限 [℃] Furnace temperature ceiling [degC] *)
    DL_FDI_P_MIN : REAL := -5.0;    (* 压力量程下限 [kPa] Pressure floor [kPa] *)
    DL_FDI_P_MAX : REAL := 5.0;     (* 压力量程上限 [kPa] Pressure ceiling [kPa] *)
END_VAR
(* —— 段 0：非有限闸（NaN 自反 + Inf 差值自减）+ 组态域闸，三浮点入参全枚举（R272） —— *)
_bCfgBad := (fTempC <> fTempC) OR ((fTempC - fTempC) <> 0.0)
         OR (fTempSafeC <> fTempSafeC) OR ((fTempSafeC - fTempSafeC) <> 0.0)
         OR (fPressKPa <> fPressKPa) OR ((fPressKPa - fPressKPa) <> 0.0)
         OR (fTempC < DL_FDI_T_MIN) OR (fTempC > DL_FDI_T_MAX)
         OR (fTempSafeC < DL_FDI_TS_MIN) OR (fTempSafeC > DL_FDI_TS_MAX)
         OR (fPressKPa < DL_FDI_P_MIN) OR (fPressKPa > DL_FDI_P_MAX);
(* 两个判据量：温度须低于「安全温度 − 回差」；压力须不超过允许正压 *)
_bTempSafe := fTempC <= (fTempSafeC - DL_FDI_HYST);
_bPressOk := fPressKPa <= DL_FDI_PMAX;
(* —— 段 1：单拍量预清 + 组态故障请求 —— *)
_bReqFault := FALSE;
_nReqErr := 0;
IF _bCfgBad THEN
    _bReqFault := TRUE; _nReqErr := 101;        (* 组态非法 / Configuration bad *)
END_IF
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内 xOpenCmd 释放，R152） —— *)
IF _bFaultLatch AND (NOT xOpenCmd) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _nErr := 0;                                 (* 清码 / Clear code *)
    _eState := E_DL_FdiState.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_FdiState.eIdle:
    IF xOpenCmd AND (NOT _bFaultLatch) THEN
        IF xAtmosOn THEN
            _eState := E_DL_FdiState.eAtmosCut; (* 已投气氛：先断气氛 / Atmosphere on, cut first *)
        ELSE
            _eState := E_DL_FdiState.eCoolWait; (* 未投气氛：直接降温等待 / No atmos, cool wait *)
        END_IF
    END_IF
E_DL_FdiState.eAtmosCut:
    IF NOT xAtmosOn THEN
        _eState := E_DL_FdiState.eCoolWait;     (* 气氛已断 → 降温等待 / Atmos off, cool wait *)
    END_IF
E_DL_FdiState.eCoolWait:
    IF (NOT xAtmosOn) AND _bTempSafe THEN
        IF _bPressOk THEN
            _eState := E_DL_FdiState.eDoorPermit;   (* 三项齐备 → 开门许可 / All ready, permit *)
        ELSE
            _bReqFault := TRUE; _nReqErr := 102;    (* 正压超限：禁止开门 / Positive pressure *)
        END_IF
    END_IF
E_DL_FdiState.eDoorPermit:
    IF NOT xOpenCmd THEN
        _eState := E_DL_FdiState.eIdle;         (* 申请撤销 → 待机 / Request withdrawn *)
    ELSIF xAtmosOn OR (NOT _bTempSafe) OR (NOT _bPressOk) THEN
        _eState := E_DL_FdiState.eCoolWait;     (* 前置失守 → 退回等待（安全侧优先） / Precondition lost *)
    END_IF
E_DL_FdiState.eFault:
    _bPressOk := fPressKPa <= DL_FDI_PMAX;      (* 故障相驻留：判据照算供追溯，不迁相 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 103;
END_CASE
(* —— 段 4：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _eState := E_DL_FdiState.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 5：统一出口（各出口单点赋值） —— *)
xDoorPermit := (_eState = E_DL_FdiState.eDoorPermit) AND (NOT _bFaultLatch);
xAtmosCutCmd := (_eState = E_DL_FdiState.eAtmosCut) OR (_eState = E_DL_FdiState.eCoolWait)
             OR (_eState = E_DL_FdiState.eDoorPermit);
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
