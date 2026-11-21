(*
  Name        : FB_DL_AxisJerkLimitCheck
  Category    : DL_Motion
  Version     : 1.0.0
  Purpose     : 加加速度（jerk）指令合法性检查与钳位：由速度指令序列二次差分得加速度与 jerk，jerk 越限时把本拍速度指令回退到「上一拍加速度 ± jerk 上限」允许的取值，防高速贴装冲击；/ Check and clamp jerk of a velocity command sequence: derive acceleration and jerk by successive differences, and when jerk exceeds the limit back off the velocity command to the value permitted by the jerk-limited acceleration
  溯源        : 借 t1-6-plcopen·limits 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：扫描周期 <= T#0S / jerk 上限 <= eps / 加速度上限 <= eps / 速度上限 <= eps → 锁存故障；
                ② 二次差分除子 dt 秒值在组态闸后使用，且使用前再判 > eps（双保险）；
                ③ 非有限速度指令该拍直通不钳位（保持上拍状态量，不作伪钳位）；
                ④ 输出速度钳到 [-fVelMax, +fVelMax]（双侧直比，不用 ABS 单侧）；
                ⑤ 本件只改「指令」，不参与位置环闭环；钳位生效即置 bLimited，供上层记录。
*)
TYPE E_DL_AjcState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eChk   := 10,                            (* 检查运行 / Checking *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_AjcCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：周期/限值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisJerkLimitCheck
VAR_INPUT
    fVelCmd   : REAL := 0.0;                 (* 原始速度指令 [mm/s] / Raw velocity command *)
    tScan     : TIME := T#4MS;               (* 指令更新周期，域 > T#0S [ms] / Command update period, > 0 *)
    fJerkMax  : REAL := 1.0E5;               (* 允许 jerk 上限，域 > 0 [mm/s³] / Allowed jerk limit, > 0 *)
    fAccMax   : REAL := 1.0E4;               (* 允许加速度上限，域 > 0 [mm/s²] / Allowed acceleration limit, > 0 *)
    fVelMax   : REAL := 2000.0;              (* 速度双向限幅，域 > 0 [mm/s] / Symmetric velocity limit, > 0 *)
    bEnable   : BOOL := TRUE;                (* 检查使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清状态量与标志 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fVelOut   : REAL;                        (* 钳位后速度指令 [mm/s] / Clamped velocity command *)
    fAcc      : REAL;                        (* 本拍实测加速度 [mm/s²] / Measured acceleration this scan *)
    fJerk     : REAL;                        (* 本拍实测 jerk [mm/s³] / Measured jerk this scan *)
    bLimited  : BOOL;                        (* 本拍钳位生效 [-] / Clamp applied this scan *)
    bVelClamp : BOOL;                        (* 本拍速度限幅生效（与 jerk 钳位分开归因）[-] / Velocity clamp applied *)
    eState    : E_DL_AjcState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_AjcCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_AjcState := E_DL_AjcState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_AjcCause := E_DL_AjcCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 输入有限性当拍量 / Input finiteness *)
    _fDtSec  : REAL;                         (* 周期秒值，域 > eps [s] / Period in seconds *)
    _fVelPrev: REAL;                         (* 上拍（钳位后）速度快照 [mm/s] / Previous clamped velocity *)
    _fAccPrev: REAL;                         (* 上拍加速度快照 [mm/s²] / Previous acceleration *)
    _fAccNew : REAL;                         (* 本拍加速度（由速度差分）[mm/s²] / New acceleration *)
    _fJerkNew: REAL;                         (* 本拍 jerk（由加速度差分）[mm/s³] / New jerk *)
    _fAccLim : REAL;                         (* jerk 受限后允许的加速度 [mm/s²] / Jerk-limited acceleration *)
    _fVelTgt : REAL;                         (* 未限幅的目标速度 [mm/s] / Target velocity before clamp *)
    _fVelCl  : REAL;                         (* 限幅后速度中间量 [mm/s] / Clamped velocity intermediate *)
END_VAR
VAR CONSTANT
    DL_AJC_EPS : REAL := 1.0E-6;             (* 判零容差（REAL 量级，含 dt/限值）[-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tScan) / 1000.0;                                      (* 周期秒化（除子常量 1000） / Period to seconds *)
_bCfgBad := NOT (tScan > T#0S)                                                 (* 周期正域闸（二次差分除零前置） / Period gate *)
            OR (fJerkMax <= DL_AJC_EPS)                                        (* jerk 上限正域闸 / Jerk gate *)
            OR (fAccMax <= DL_AJC_EPS)                                         (* 加速度上限正域闸 / Acc gate *)
            OR (fVelMax <= DL_AJC_EPS);                                        (* 速度上限正域闸 / Velocity gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fVelCmd = fVelCmd) AND ((fVelCmd - fVelCmd) = (fVelCmd - fVelCmd));   (* NaN 自反 + Inf 差判联合闸 / NaN and Inf gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
bLimited := FALSE;                                                             (* jerk 钳位预清 / Jerk clamp preset *)
bVelClamp := FALSE;                                                            (* 速度限幅预清 / Velocity clamp preset *)
fVelOut := fVelCmd;                                                            (* 出口缺省直通（未命中钳位分支时语义） / Outlet default passthrough *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清差分状态量 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AjcCause.eNone;                                            (* 清成因 / Clear cause *)
    _fVelPrev := 0.0;                                                          (* 清速度快照（复位后从静止起算） / Clear velocity snapshot *)
    _fAccPrev := 0.0;                                                          (* 清加速度快照 / Clear acceleration snapshot *)
    fVelOut := 0.0;                                                            (* 出口归零（静止态） / Outlet zeroed *)
    fAcc := 0.0;                                                               (* 清加速度出口 / Clear acc outlet *)
    fJerk := 0.0;                                                              (* 清 jerk 出口 / Clear jerk outlet *)
    _eState := E_DL_AjcState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AjcCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_AjcState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AjcState.eIdle:                                                       (* 未使能：指令直通，不检查 / Disabled *)
        fVelOut := fVelCmd;                                                    (* 直通（不出钳位） / Passthrough *)
        _fVelPrev := fVelCmd;                                                  (* 快照跟随，避免重使能首拍虚假 jerk / Track snapshot *)
        _fAccPrev := 0.0;                                                      (* 加速度快照清零 / Acc snapshot cleared *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_AjcState.eChk;                                     (* 使能进入检查 / Enter checking *)
        END_IF
    E_DL_AjcState.eChk:                                                        (* 检查相：差分求 acc/jerk + 越限钳位 / Checking *)
        IF NOT bEnable THEN
            _eState := E_DL_AjcState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite AND (_fDtSec > DL_AJC_EPS) THEN
            _fAccNew := (fVelCmd - _fVelPrev) / _fDtSec;                       (* 加速度 = Δv/dt（除子已过闸）[mm/s²] / Acceleration, divisor gated *)
            _fJerkNew := (_fAccNew - _fAccPrev) / _fDtSec;                     (* jerk = Δa/dt（除子已过闸）[mm/s³] / Jerk, divisor gated *)
            fAcc := _fAccNew;                                                  (* 加速度出口 / Acc outlet *)
            fJerk := _fJerkNew;                                                (* jerk 出口 / Jerk outlet *)
            IF _fJerkNew > fJerkMax THEN
                _fAccLim := _fAccPrev + fJerkMax * _fDtSec;                    (* 正向越限：加速度只许升到上限步长 / Positive: limit acc rise *)
                bLimited := TRUE;                                              (* 钳位生效 / Clamp applied *)
            ELSIF _fJerkNew < (-fJerkMax) THEN
                _fAccLim := _fAccPrev - fJerkMax * _fDtSec;                    (* 负向越限：加速度只许降到下限步长 / Negative: limit acc fall *)
                bLimited := TRUE;                                              (* 钳位生效 / Clamp applied *)
            ELSE
                _fAccLim := _fAccNew;                                          (* 未越限：沿用实测加速度 / No clamp *)
            END_IF
            IF _fAccLim > fAccMax THEN
                _fAccLim := fAccMax;                                           (* 加速度上限双侧直比 / Acc upper clamp *)
                bLimited := TRUE;                                              (* 计入钳位归因 / Count as clamp *)
            ELSIF _fAccLim < (-fAccMax) THEN
                _fAccLim := -fAccMax;                                          (* 加速度下限双侧直比 / Acc lower clamp *)
                bLimited := TRUE;                                              (* 计入钳位归因 / Count as clamp *)
            END_IF
            _fVelTgt := _fVelPrev + _fAccLim * _fDtSec;                        (* 由受限加速度重建本拍速度指令 / Rebuild velocity from limited acc *)
            _fVelCl := _fVelTgt;                                               (* 限幅前中间量 / Intermediate before clamp *)
            IF _fVelCl > fVelMax THEN
                _fVelCl := fVelMax;                                            (* 速度上限钳位（双侧直比，禁 ABS 单侧） / Velocity upper clamp *)
                bVelClamp := TRUE;                                             (* 限幅归因独立（R190） / Velocity clamp cause *)
            ELSIF _fVelCl < (-fVelMax) THEN
                _fVelCl := -fVelMax;                                           (* 速度下限钳位 / Velocity lower clamp *)
                bVelClamp := TRUE;                                             (* 限幅归因独立 / Velocity clamp cause *)
            END_IF
            fVelOut := _fVelCl;                                                (* 钳位后指令出口 / Clamped command outlet *)
            _fVelPrev := _fVelCl;                                              (* 快照推进为钳位后值（下拍差分基准） / Advance snapshot *)
            _fAccPrev := _fAccLim;                                             (* 加速度快照推进为受限值 / Advance acc snapshot *)
        END_IF                                                                 (* 非有限/周期退化：直通不钳位（边界③） / Passthrough *)
    E_DL_AjcState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AjcState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_AjcCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
