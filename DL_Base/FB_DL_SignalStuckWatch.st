(*
  Name        : FB_DL_SignalStuckWatch
  Category    : DL_Base
  Version     : 1.0.0
  Purpose     : 信号卡死监视：监视值在卡死判定窗内变化量始终不超过死区（变化率恒零）即报警，捕捉传感器冻结/线束搭死；/ Signal stuck watch: raises an alarm when the monitored value stays within the deadband for the whole stuck window, catching frozen sensors or shorted wiring
  溯源        : 借 t2-1-lgf 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：死区 < 0 / 卡死窗 <= T#0S → 锁存故障（死区 0 合法：严格等值判死）；
                ② 卡死判定窗用 TON，IN 由「未变化 + 已取基线」派生并串 eMon 相位闸（族③：eIdle/eFault 不计时，上拍相位 1 拍延迟可接受），段 0 无 IF 包裹；
                ③ 非有限值该拍不更新基线不计时（防 NaN 把窗持续清零而漏报，也防污染基线）；
                ④ 基线快照在迁入 eMon 拍取（fValue 首值），变化超死区即刷新基线并重置计时；
                ⑤ bStuck 锁存至复位沿；bStuck 起始沿单拍脉冲 bStuckEdge 供事件记录（R187 两段式）。
*)
TYPE E_DL_SswState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 卡死监视运行 / Monitoring *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_SswCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：死区/窗口越域 / Illegal config *)
    eStuck      := 2,                        (* 信号卡死（窗满无有效变化） / Signal stuck *)
    ePhaseBad   := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SignalStuckWatch
VAR_INPUT
    fValue    : REAL := 0.0;                 (* 被监视信号值（任意工程量）[-] / Monitored signal value *)
    fDeadband : REAL := 0.01;               (* 变化判定死区，域 >= 0 [工程单位] / Deadband for change detection *)
    tStuckWin : TIME := T#60S;              (* 卡死判定窗长，域 > T#0S [ms] / Stuck window length, > 0 *)
    bEnable   : BOOL := TRUE;               (* 监视使能 [-] / Enable *)
    bReset    : BOOL := FALSE;              (* 复位命令，上升沿清报警与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDelta    : REAL;                        (* 本拍相对基线变化量（实时派生）[工程单位] / Delta versus baseline *)
    bStuck    : BOOL;                        (* 卡死报警锁存（复位沿清）[-] / Stuck alarm latched *)
    bStuckEdge: BOOL;                        (* 卡死报警起始沿（单拍脉冲）[-] / Stuck alarm rising edge pulse *)
    fLastMove : TIME;                       (* 最近一次有效变化距今时长（本窗计时镜像）[ms] / Time since last valid move *)
    eState    : E_DL_SswState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_SswCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_SswState := E_DL_SswState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_SswCause := E_DL_SswCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    rtStuck   : R_TRIG;                      (* 卡死计时器输出沿实例，段 0 无条件调用 / Stuck-timer edge instance *)
    tonStuck  : TON;                         (* 卡死判定窗计时器（IN 由变化判据派生 + 相位闸） / Stuck window timer *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
    _bFin     : BOOL;                        (* 监视值有限性当拍量 / Value finiteness *)
    _bMoved   : BOOL;                        (* 本拍有效变化当拍量（超死区） / Valid move this scan *)
    _bSeen    : BOOL;                        (* 基线已建立标志 / Baseline established flag *)
    _fLast    : REAL;                        (* 基线快照（最近一次有效变化的值）[工程单位] / Baseline snapshot *)
    _fDeltaI  : REAL;                        (* 变化量中间量 [工程单位] / Delta intermediate *)
    _bStuckC  : BOOL;                        (* 卡死起始沿内部单拍量（出口统一映射，R187） / Stuck-edge internal pulse *)
END_VAR
VAR CONSTANT
    DL_SSW_EPS : REAL := 1.0E-6;             (* 判零容差（REAL 量级）[-] / Epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (fDeadband < 0.0) OR NOT (tStuckWin > T#0S);                       (* 死区非负闸 + 卡死窗正域闸 / Deadband and window gates *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fValue = fValue) AND ((fValue - fValue) = (fValue - fValue));        (* 监视值 NaN 自反 + Inf 差判闸 / Value NaN and Inf gate *)
_fDeltaI := fValue - _fLast;                                                   (* 相对基线变化量（基线无效期不用于判据）[工程单位] / Delta versus baseline *)
_bMoved := _bFin AND _bSeen AND (ABS(_fDeltaI) > fDeadband);                   (* 有效变化：有限 + 基线在 + 超死区（死区 0 即严格不等） / Valid move gate *)
tonStuck(IN := (_eState = E_DL_SswState.eMon) AND _bSeen AND NOT _bMoved AND _bFin, PT := tStuckWin);   (* 卡死窗计时：基线在 + 未变化 + 有限才计时，串 eMon 相位闸 / Stuck timer with phase gate *)
rtStuck(CLK := tonStuck.Q);                                                    (* 卡死窗到点沿每拍必调 / Stuck-elapsed edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bStuckC := FALSE;                                                             (* 卡死起始沿内部量预清 / Stuck-edge preset *)
bStuckEdge := FALSE;                                                           (* 卡死起始沿出口预清 / Stuck-edge outlet preset *)
fDelta := 0.0;                                                                 (* 变化量出口预清 / Delta outlet preset *)
fLastMove := T#0S;                                                             (* 最近变化距今出口预清 / Last-move outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清报警 + 清基线 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_SswCause.eNone;                                            (* 清成因 / Clear cause *)
    bStuck := FALSE;                                                           (* 清卡死报警锁存 / Clear stuck latch *)
    _bSeen := FALSE;                                                           (* 清基线已建立位（重使能重新取基线） / Clear baseline flag *)
    _fLast := 0.0;                                                             (* 清基线快照值 / Clear baseline value *)
    _eState := E_DL_SswState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_SswCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_SswState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_SswState.eIdle:                                                       (* 未使能：不判死 / Disabled *)
        bStuck := FALSE;                                                       (* 失能清报警出口（eIdle/eFault 出口确定值） / Clear stuck outlet *)
        fDelta := 0.0;                                                         (* 失能清变化量出口 / Clear delta outlet *)
        _bSeen := FALSE;                                                       (* 失能清基线位（重使能重新对齐） / Clear baseline flag *)
        IF bEnable AND NOT _bFault THEN
            _fLast := fValue;                                                  (* 迁入拍取基线首快照（相位闸配套） / Baseline snapshot at entry *)
            _bSeen := TRUE;                                                    (* 基线已建立 / Baseline established *)
            _eState := E_DL_SswState.eMon;                                     (* 使能进入监视 / Enter monitoring *)
        END_IF
    E_DL_SswState.eMon:                                                        (* 监视相：变化刷基线，未变化累计 / Monitoring *)
        IF NOT bEnable THEN
            _eState := E_DL_SswState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            IF _bFin THEN
                fDelta := _fDeltaI;                                            (* 变化量出口（有限拍才派生） / Delta outlet *)
                fLastMove := tonStuck.ET;                                      (* 本窗已积时长镜像 [ms] / Window elapsed mirror *)
            END_IF
            IF _bMoved THEN
                _fLast := fValue;                                              (* 有效变化：基线刷新为当前值（计时器随 IN 翻 FALSE 自动归零） / Refresh baseline on move *)
            END_IF
            IF rtStuck.Q THEN                                                  (* 卡死窗满且全程未变化：报警 / Window elapsed without move *)
                _bStuckC := TRUE;                                              (* 起始沿内部置位（出口统一映射，R187） / Stuck-edge internal *)
                bStuck := TRUE;                                                (* 卡死报警锁存（复位沿清） / Latch stuck alarm *)
                _bFault := TRUE;                                               (* 同步故障锁存（卡死按故障级处理，R45 配对） / Latch fault *)
                _eCause := E_DL_SswCause.eStuck;                               (* 成因：信号卡死（R190 归因唯一） / Cause: signal stuck *)
            END_IF
        END_IF
    E_DL_SswState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_SswState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_SswCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bStuckEdge := _bStuckC;                                                        (* 卡死起始沿单拍出口 / Stuck-edge single-scan outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
