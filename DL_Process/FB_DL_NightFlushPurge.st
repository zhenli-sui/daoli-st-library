(*
  Name        : FB_DL_NightFlushPurge
  Category    : DL_Process
  Version     : 1.0.0
  Purpose     : HVAC 夜间吹扫编排：日历窗 + 风机允许 + 室外低温差三闸同拍进入吹扫相，温降达标或超时退出，退出入冷却驻留窗防反复启停；/ HVAC night flush purge orchestration: calendar window, fan permit and outdoor-cool delta enter the purge phase together, exit on target drop or timeout into a cooldown dwell window
  溯源        : 借 oscat-building 的夜间吹扫待挖组织，clean-room 实现（日历窗信号由属主日历窗件提供）
  Boundary    : ① 进入闸 = 日历窗内 AND 风机允许 AND 室外温 < 室内温 - 温差阈，三闸同拍成立才进入；
                ② 吹扫相与冷却相 TON 断输入归零（IN 由相位门控，实例调用无条件，R40 家族）；
                ③ 温降达标判定用差值双阈迟滞防边界抖动（达标锁存，跌破迟滞带才解除）；
                ④ 任一温度非有限 → 降级退出吹扫（安全侧不维持），bSensorBad 锁存至复位沿；
                ⑤ 超时/达标退出后冷却驻留窗计时，窗未满禁止再次进入（防夜间反复启停，边界⑤）；
                ⑥ 本件为编排层，不直接驱动风机输出（属主边界，出吹扫命令信号）。
*)
TYPE E_DL_NfpState :
(
    eIdle    := 0,                           (* 未吹扫 / Not purging *)
    ePurge   := 10,                          (* 吹扫运行 / Purging *)
    eHoldout := 20,                          (* 冷却驻留窗 / Cooldown dwell *)
    eFault   := 90                           (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_NfpCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：温差/达标/周期域越界 / Illegal config *)
    eSensorBad := 2,                        (* 传感器失效降级退出（边界④） / Sensor bad degraded exit *)
    ePhaseBad  := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_NightFlushPurge
VAR_INPUT
    bWindow  : BOOL := FALSE;                (* 日历窗内信号（属主日历窗件提供）[-] / In calendar window *)
    bFanAllow: BOOL := FALSE;                (* 风机允许联锁 [-] / Fan permit *)
    fTin     : REAL := 20.0;                 (* 室内温度 [摄氏度] / Indoor temperature *)
    fTout    : REAL := 15.0;                 (* 室外温度 [摄氏度] / Outdoor temperature *)
    fDelta   : REAL := 3.0;                  (* 进入温差阈，域 > 0 [摄氏度] / Entry delta threshold *)
    fDropTgt : REAL := 3.0;                  (* 温降达标阈，域 > 0 [摄氏度] / Drop target threshold *)
    fDropHys : REAL := 0.5;                  (* 达标迟滞带，域 >= 0 且 < 达标阈 [摄氏度] / Drop hysteresis band *)
    tPurgeMax: TIME := T#60M;                (* 吹扫超时，域 > T#0S [ms] / Purge timeout *)
    tCooldown: TIME := T#30M;                (* 冷却驻留窗，域 > T#0S [ms] / Cooldown dwell *)
    tScan    : TIME := T#1S;                 (* 扫描周期，域 > T#0S [ms] / Scan period *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障与状态 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bPurgeCmd: BOOL;                         (* 吹扫命令信号（属主驱动风机）[-] / Purge command signal *)
    bHoldout : BOOL;                         (* 冷却驻留中指示 [-] / Cooldown indicator *)
    bSensorBad: BOOL;                        (* 传感器失效锁存（复位沿清）[-] / Sensor bad latched *)
    eState   : E_DL_NfpState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_NfpCause;                (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_NfpState := E_DL_NfpState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_NfpCause := E_DL_NfpCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonPurge: TON;                           (* 吹扫超时计时（IN 串 ePurge 相闸，边界②） / Purge timeout timer *)
    tonCool : TON;                           (* 冷却驻留计时（IN 串 eHoldout 相闸，边界②） / Cooldown timer *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 双温度有限性当拍量（边界④） / Temperatures finiteness *)
    _bCoolDone: BOOL := TRUE;                (* 冷却窗完成标志（初值 TRUE 允许首轮进入） / Cooldown done flag *)
    _bDropOk: BOOL;                          (* 温降达标锁存量（迟滞双阈，边界③） / Drop reached latch *)
    _fTinStart: REAL;                        (* 吹扫迁入拍室内温快照 [摄氏度] / Indoor snapshot at entry *)
END_VAR
VAR CONSTANT
    DL_NFP_EPS : REAL := 1.0E-6;             (* 判零容差 [-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；TON 全段 0 无 IF 包裹，边界②） —— *)
_bCfgBad := (fDelta <= DL_NFP_EPS) OR (fDropTgt <= DL_NFP_EPS)          (* 温差/达标阈正域闸（边界①） / Delta and target gates *)
            OR (fDropHys < 0.0) OR (fDropHys >= fDropTgt)               (* 迟滞带域闸（边界③） / Hysteresis gate *)
            OR NOT (tPurgeMax > T#0S) OR NOT (tCooldown > T#0S) OR NOT (tScan > T#0S);   (* 周期域闸 / Period gates *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fTin = fTin) AND ((fTin - fTin) = (fTin - fTin))              (* 室内温 NaN 自反 + Inf 差判闸（边界④） / Indoor NaN and Inf gate *)
         AND (fTout = fTout) AND ((fTout - fTout) = (fTout - fTout));   (* 室外温 NaN 自反 + Inf 差判闸 / Outdoor NaN and Inf gate *)
tonPurge(IN := (_eState = E_DL_NfpState.ePurge), PT := tPurgeMax);      (* 吹扫超时：相位闸 + 无条件调用（边界②） / Purge timeout *)
tonCool(IN := (_eState = E_DL_NfpState.eHoldout), PT := tCooldown);     (* 冷却驻留：相位闸 + 无条件调用（边界②） / Cooldown timer *)

(* —— 段 1：单拍量预清零（R107） —— *)
bPurgeCmd := FALSE;                                      (* 吹扫命令出口预清（派生拍覆盖） / Purge command preset *)
bHoldout := FALSE;                                       (* 冷却指示出口预清 / Cooldown preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清传感器锁存 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_NfpCause.eNone;                      (* 清成因 / Clear cause *)
    bSensorBad := FALSE;                                 (* 清传感器失效锁存 / Clear sensor latch *)
    _bCoolDone := TRUE;                                  (* 冷却完成回 TRUE（复位即放行首轮） / Cooldown done reset *)
    _bDropOk := FALSE;                                   (* 清达标锁存 / Clear drop latch *)
    _eState := E_DL_NfpState.eIdle;                      (* 迁未吹扫相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_NfpCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_NfpState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_NfpState.eIdle:                                 (* 未吹扫：出口确定值 / Idle *)
        bPurgeCmd := FALSE;                              (* 失能吹扫命令确定 FALSE / Disabled command false *)
        bHoldout := FALSE;                               (* 失能冷却指示 FALSE / Disabled holdout false *)
        IF bEnable AND NOT _bFault AND _bCoolDone AND _bFin              (* 使能 + 冷却窗满（边界⑤）+ 温度有限 / Entry preconditions *)
           AND bWindow AND bFanAllow                                     (* 日历窗 + 风机允许（边界①） / Window and fan permit *)
           AND (fTout < fTin - fDelta) THEN                              (* 室外低温差闸（边界①） / Outdoor cool delta *)
            _fTinStart := fTin;                          (* 迁入拍室内温快照（温降基准） / Indoor snapshot *)
            _bDropOk := FALSE;                           (* 清达标锁存（新一轮） / Clear drop latch *)
            _bCoolDone := FALSE;                         (* 冷却窗未满（退出后重计） / Cooldown not done *)
            _eState := E_DL_NfpState.ePurge;             (* 进入吹扫相 / Enter purging *)
        END_IF
    E_DL_NfpState.ePurge:                                 (* 吹扫相：达标/超时/降级三出口 / Purging *)
        bPurgeCmd := TRUE;                                (* 吹扫命令出口 / Purge command *)
        IF NOT bEnable OR NOT bWindow OR NOT bFanAllow OR NOT _bFin THEN   (* 前置消失或传感器失效（安全侧降级，边界④） / Preconditions lost *)
            IF NOT _bFin THEN
                bSensorBad := TRUE;                      (* 传感器失效锁存（复位沿清，边界④） / Sensor bad latch *)
                _eCause := E_DL_NfpCause.eSensorBad;     (* 成因：传感器失效 / Cause sensor bad *)
            END_IF
            _eState := E_DL_NfpState.eHoldout;           (* 降级入冷却驻留（安全侧不维持） / To cooldown *)
            _bDropOk := FALSE;                           (* 清达标锁存 / Clear drop latch *)
        ELSE
            IF (_fTinStart - fTin) >= fDropTgt THEN      (* 温降达标上阈（差值直比，边界③） / Drop reached upper *)
                _bDropOk := TRUE;                        (* 达标锁存 / Drop latch *)
            END_IF
            IF _bDropOk AND ((_fTinStart - fTin) < (fDropTgt - fDropHys)) THEN   (* 跌破迟滞下带才解除达标（边界③） / Release below band *)
                _bDropOk := FALSE;                       (* 解除达标 / Drop release *)
            END_IF
            IF _bDropOk OR tonPurge.Q THEN               (* 达标或超时退出 / Drop or timeout exit *)
                _eState := E_DL_NfpState.eHoldout;       (* 入冷却驻留窗（边界⑤） / To cooldown *)
                _bDropOk := FALSE;                       (* 清达标锁存 / Clear drop latch *)
            END_IF
        END_IF
    E_DL_NfpState.eHoldout:                              (* 冷却驻留相：窗满回未吹扫 / Cooldown *)
        bHoldout := TRUE;                                (* 冷却指示出口 / Cooldown indicator *)
        bPurgeCmd := FALSE;                              (* 冷却相吹扫命令确定 FALSE / Purge command false *)
        IF tonCool.Q THEN
            _bCoolDone := TRUE;                          (* 冷却窗满放行（边界⑤） / Cooldown done *)
            _eState := E_DL_NfpState.eIdle;              (* 回未吹扫相 / Back to idle *)
        END_IF
    E_DL_NfpState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_NfpState.eFault; _bFault := TRUE;    (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_NfpCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
