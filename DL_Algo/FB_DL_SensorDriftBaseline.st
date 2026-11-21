(*
  Name        : FB_DL_SensorDriftBaseline
  Category    : DL_Algo
  Version     : 1.0.1
  Purpose     : 传感器慢漂移基线跟踪：长窗指数（EMA）基线随测量缓慢跟随，测量对基线的快偏差超限经确认延时即报警（区分真实工况阶跃与传感器漂移）；/ Sensor slow-drift baseline tracking: a long-window EMA baseline follows the measurement, and a fast deviation beyond limit confirmed over a delay raises an alarm
  溯源        : 借 t2-1-measurement 的分类/参数域组织，clean-room 实现
  Changelog   : v1.0.1 R54 非有限输入穿透修复：迁入拍/基线更新/残差出口前置有限性闸，非有限拍冻结基线并置 bSensorBad，出口保持上拍值
  Boundary    : ① 组态闸：基线因子域 (0..1] / 快偏差限 > 0 / 确认延时 > 0 → 锁存故障（因子 0/1 端点使基线冻结或退化为直通）；
                ② 非有限测量该拍不更新基线（基线保持上拍值，防污染慢积分器），判据整拍跳过；
                ③ 基线快照在迁入 eMon 拍取（fValue 首值），避免从 0 慢爬造成的假偏差；
                ④ 确认延时 TON 串 eMon 相位闸（族③），段 0 无 IF 包裹；
                ⑤ bDriftFast 锁存至复位沿；fBaseline/fDeviation 出口在 eIdle/eFault 有确定值；
                ⑥ 本件为诊断层，不修正测量值、不重标定（属主边界）。
*)
TYPE E_DL_SdbState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 基线跟踪运行 / Tracking *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_SdbCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：因子/偏差限/延时越域 / Illegal config *)
    eDriftFast  := 2,                        (* 快偏差确认（基线失跟或真实阶跃，上层判别） / Fast deviation confirmed *)
    ePhaseBad   := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SensorDriftBaseline
VAR_INPUT
    fValue    : REAL := 0.0;                 (* 传感器测量值（任意工程量）[-] / Sensor measurement *)
    fAlpha    : REAL := 0.005;               (* 基线 EMA 因子（每拍跟随比例），域 (0..1] [-] / Baseline EMA factor *)
    fFastLim  : REAL := 5.0;                 (* 快偏差报警限，域 > 0 [工程单位] / Fast-deviation limit, > 0 *)
    tConfirm  : TIME := T#30S;               (* 快偏差确认延时，域 > T#0S [ms] / Deviation confirm delay, > 0 *)
    bEnable   : BOOL := TRUE;                (* 跟踪使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清报警与基线 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fBaseline : REAL;                        (* 慢漂移基线（EMA 跟踪值）[工程单位] / Slow-drift baseline *)
    fDeviation: REAL;                        (* 测量对基线快偏差（实时派生）[工程单位] / Fast deviation versus baseline *)
    bDriftFast: BOOL;                        (* 快偏差报警锁存（复位沿清）[-] / Fast-deviation alarm latched *)
    bSensorBad: BOOL;                        (* 测量非有限传感器失效锁存（复位沿清，v1.0.1）[-] / Sensor bad latched *)
    eState    : E_DL_SdbState;               (* 状态出口 / State outlet *)
    eCause    : E_DL_SdbCause;               (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError    : BOOL;                        (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_SdbState := E_DL_SdbState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_SdbCause := E_DL_SdbCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonConf  : TON;                          (* 快偏差确认延时计时器（IN 由偏差判据派生 + 相位闸） / Deviation confirm timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFin    : BOOL;                         (* 测量值有限性当拍量 / Measurement finiteness *)
    _bBase   : BOOL;                         (* 基线已建立标志 / Baseline established flag *)
    _fBaseI  : REAL;                         (* 基线内部量（EMA 状态）[工程单位] / Baseline internal EMA state *)
    _fDevI   : REAL;                         (* 快偏差中间量 [工程单位] / Deviation intermediate *)
    _fDevLast: REAL;                         (* 上拍有效偏差快照（非有限拍出口冻结用，v1.0.1）[工程单位] / Last valid deviation snapshot *)
    _bDevRaw : BOOL;                         (* 快偏差原始判据当拍量 / Raw deviation verdict *)
END_VAR
VAR CONSTANT
    DL_SDB_EPS  : REAL := 1.0E-6;            (* 判零容差 [-] / Epsilon *)
    DL_SDB_ONE  : REAL := 1.0;               (* 因子上界常量 [-] / Factor upper bound *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (fAlpha <= DL_SDB_EPS) OR (fAlpha > DL_SDB_ONE)                    (* 基线因子域闸 (0..1]（端点退化解拦截） / Factor domain gate *)
            OR (fFastLim <= DL_SDB_EPS)                                        (* 快偏差限正域闸 / Deviation limit gate *)
            OR NOT (tConfirm > T#0S);                                          (* 确认延时正域闸 / Confirm delay gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fValue = fValue) AND ((fValue - fValue) = (fValue - fValue));        (* 测量值 NaN 自反 + Inf 差判闸 / Measurement NaN and Inf gate *)
_fDevI := 0.0;                                                                 (* 偏差中间量预置（基线无效期为 0，不误触发计时） / Deviation preset zero *)
IF _bFin AND _bBase THEN
    _fDevI := fValue - _fBaseI;                                                (* 快偏差 = 测量 - 基线（基线已建立才派生）[工程单位] / Deviation versus baseline *)
END_IF
_bDevRaw := _bFin AND _bBase AND (ABS(_fDevI) > fFastLim);                     (* 原始判据：有限 + 基线在 + 超限（直比阈值，非浮点等值） / Raw deviation verdict *)
tonConf(IN := (_eState = E_DL_SdbState.eMon) AND _bDevRaw, PT := tConfirm);    (* 确认延时：判据持续才计时，串 eMon 相位闸 / Confirm timer with phase gate *)

(* —— 段 1：单拍量预清零（R107；bDriftFast 为锁存出口不预清，复位沿清，族② 口径） —— *)
fBaseline := 0.0;                                                              (* 基线出口预清（派生拍覆盖） / Baseline outlet preset *)
fDeviation := 0.0;                                                             (* 偏差出口预清 / Deviation outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清报警 + 清基线 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_SdbCause.eNone;                                            (* 清成因 / Clear cause *)
    bDriftFast := FALSE;                                                       (* 清快偏差报警锁存 / Clear alarm latch *)
    _bBase := FALSE;                                                           (* 清基线已建立位（重使能重新取快照） / Clear baseline flag *)
    _fBaseI := 0.0;                                                            (* 清基线内部量 / Clear baseline internal *)
    _fDevLast := 0.0;                                                          (* 清有效偏差快照（v1.0.1） / Clear deviation snapshot *)
    bSensorBad := FALSE;                                                       (* 清传感器失效锁存（v1.0.1） / Clear sensor bad latch *)
    fBaseline := 0.0;                                                          (* 清基线出口 / Clear baseline outlet *)
    fDeviation := 0.0;                                                         (* 清偏差出口 / Clear deviation outlet *)
    _eState := E_DL_SdbState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_SdbCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_SdbState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_SdbState.eIdle:                                                       (* 未使能：出口确定值 / Disabled *)
        fBaseline := 0.0;                                                      (* 失能清基线出口 / Clear baseline outlet *)
        fDeviation := 0.0;                                                     (* 失能清偏差出口 / Clear deviation outlet *)
        bDriftFast := FALSE;                                                   (* 失能清报警出口 / Clear alarm outlet *)
        _bBase := FALSE;                                                       (* 失能清基线位（重使能重新对齐） / Clear baseline flag *)
        bSensorBad := FALSE;                                                   (* 失能清传感器失效出口（确定值） / Clear sensor bad *)
        IF bEnable AND NOT _bFault AND _bFin THEN                              (* 迁入闸加有限性闸：迁入拍为非有限不建基线不迁入（v1.0.1 修复） / Entry gate with finiteness *)
            _fBaseI := fValue;                                                 (* 迁入拍取基线首快照（相位闸配套，边界③） / Baseline snapshot at entry *)
            _bBase := TRUE;                                                    (* 基线已建立 / Baseline established *)
            _eState := E_DL_SdbState.eMon;                                     (* 使能进入跟踪 / Enter tracking *)
        END_IF
    E_DL_SdbState.eMon:                                                        (* 跟踪相：EMA 基线 + 快偏差判 / Tracking *)
        IF NOT bEnable THEN
            _eState := E_DL_SdbState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSE
            fBaseline := _fBaseI;                                              (* 基线出口（状态镜像，R191；非有限拍 _fBaseI 冻结即保持上拍） / Baseline outlet *)
            IF _bFin THEN
                fDeviation := _fDevI;                                          (* 偏差出口（有限拍派生） / Deviation outlet *)
                _fDevLast := _fDevI;                                           (* 有效偏差快照推进（v1.0.1） / Advance deviation snapshot *)
                _fBaseI := _fBaseI + fAlpha * (fValue - _fBaseI);              (* EMA 基线慢跟随（因子域闸保证 (0..1]） / EMA baseline update *)
            ELSE
                fDeviation := _fDevLast;                                       (* 非有限拍：偏差出口保持上拍值（v1.0.1 修复） / Hold last deviation *)
                bSensorBad := TRUE;                                            (* 非有限拍置传感器失效锁存（复位沿清，v1.0.1） / Sensor bad latch *)
            END_IF
            IF tonConf.Q THEN                                                  (* 快偏差持续满确认延时：报警 / Deviation confirmed *)
                bDriftFast := TRUE;                                            (* 报警锁存（复位沿清） / Latch alarm *)
                _bFault := TRUE;                                               (* 同步故障锁存（R45 配对） / Latch fault *)
                _eCause := E_DL_SdbCause.eDriftFast;                           (* 成因：快偏差 / Cause: fast deviation *)
            END_IF
        END_IF
    E_DL_SdbState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_SdbState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_SdbCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
