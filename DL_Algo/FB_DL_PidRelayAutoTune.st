(*
  Name        : FB_DL_PidRelayAutoTune
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : 继电器反馈自整定：强制振荡观测极限周期/幅值，按 Åström-Hägglund 公开公式给 PID 初值（Kp = 4d/πa，Ti = Tu/2，Td = Tu/8）；/ Relay-feedback auto-tuning: forced-oscillation observation of ultimate period and amplitude, PID seed values from the published Astrom-Hagglund formulas
  溯源        : 自研-公开方法（relay-tuning 公开公式），clean-room 实现
  Boundary    : ① 迟滞带宽/激励幅值/采样周期三重正域闸，任一越域锁存故障；
                ② 振荡周期须测得 ≥ 3 个完整周期且逐周期稳定才出参数（防半波截断算错极限周期）；
                ③ 出口 PID 初值域钳位（Kp > 0、Ti > 0、Td >= 0），幅值发散或周期不稳 → 有效性出口 FALSE 且不出参数；
                ④ 整定中不写控制输出：本件零控制量引脚，仅出继电器建议态信号（属主边界，防误动作）；
                ⑤ 非有限测量该拍不入振荡检测（计时暂停非快进，防污染周期窗）；
                ⑥ 超时未达成 3 周期为信息级（不置故障标志，成因出口可查）。
*)
TYPE E_DL_PatState :
(
    eIdle  := 0,                             (* 未整定 / Not tuning *)
    eRelay := 10,                            (* 继电器振荡观测中 / Relay oscillation observing *)
    eReady := 20,                            (* 整定完成（有效性查 bValid 出口） / Tuning finished, see bValid *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_PatCause :
(
    eNone      := 0,                         (* 无成因 / No cause *)
    eCfgIllegal:= 1,                        (* 组态非法：幅值/迟滞/周期越域 / Illegal config *)
    eNoOsc     := 2,                        (* 信息级：未达成 3 稳定周期（超时/发散） / Info: no stable periods *)
    ePhaseBad  := 3                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PidRelayAutoTune
VAR_INPUT
    fMeas    : REAL := 0.0;                  (* 被整定回路测量值（任意工程量）[-] / Loop measurement *)
    fSetpoint: REAL := 50.0;                 (* 振荡基准（被控量目标中值）[-] / Oscillation reference *)
    fRelayAmp: REAL := 5.0;                  (* 继电器激励幅值，域 > 0 [工程单位] / Relay excitation amplitude *)
    fHyst    : REAL := 1.0;                  (* 迟滞半带宽，域 > 0 且 < 幅值 [工程单位] / Hysteresis half band *)
    tSample  : TIME := T#100MS;              (* 采样周期，域 > T#0S [ms] / Sampling period *)
    tWatch   : TIME := T#120S;               (* 整定观测总超时，域 > T#0S [ms] / Tuning watch timeout *)
    bStart   : BOOL := FALSE;                (* 启动整定命令，上升沿进入观测 [-] / Start tuning command *)
    bEnable  : BOOL := TRUE;                 (* 使能 [-] / Enable *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清故障与结果 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bRelaySug: BOOL;                         (* 继电器建议态（属主自行施加，本件不写控制输出）[-] / Suggested relay state *)
    nCycles  : INT;                          (* 已测得完整周期数 [个] / Complete periods measured *)
    fKp      : REAL;                         (* PID 初值：比例增益 [-] / PID seed: gain *)
    fTi      : REAL;                         (* PID 初值：积分时间 [s] / PID seed: integral time *)
    fTd      : REAL;                         (* PID 初值：微分时间 [s] / PID seed: derivative time *)
    bValid   : BOOL;                         (* 参数有效性出口（3 稳定周期达成才 TRUE）[-] / Parameter validity *)
    eState   : E_DL_PatState;                (* 状态出口 / State outlet *)
    eCause   : E_DL_PatCause;                (* 成因出口（R190 归因唯一） / Cause outlet *)
    bError   : BOOL;                         (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState : E_DL_PatState := E_DL_PatState.eIdle;  (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause : E_DL_PatCause := E_DL_PatCause.eNone;  (* 成因锁存量 / Latched cause *)
    rtStart : R_TRIG;                        (* 启动沿实例，段 0 无条件调用 / Start edge instance *)
    rtReset : R_TRIG;                        (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault : BOOL;                          (* 故障锁存位 / Latched fault bit *)
    _bCfgBad: BOOL;                          (* 组态非法当拍量 / Illegal config this scan *)
    _bFin   : BOOL;                          (* 测量有限性当拍量 / Measurement finiteness *)
    _bRelayI: BOOL;                          (* 继电器态内部量（迟滞保持）[-] / Relay state internal *)
    _bPrevRel: BOOL;                         (* 上拍继电器态（沿检测）[-] / Previous relay state *)
    _bUpCr  : BOOL;                          (* 本拍向上穿越当拍量（继电器态由高变低）[-] / Upward crossing this scan *)
    _fDtSec : REAL;                          (* 采样周期秒值，域 > eps [s] / Sampling period seconds *)
    _fTacc  : REAL;                          (* 周期计时累加量 [s] / Period time accumulator *)
    _fTune  : REAL;                          (* 整定总耗时累加量 [s] / Total tuning elapsed *)
    _fTu1   : REAL;                          (* 周期样本 1 [s] / Period sample 1 *)
    _fTu2   : REAL;                          (* 周期样本 2 [s] / Period sample 2 *)
    _fTu3   : REAL;                          (* 周期样本 3 [s] / Period sample 3 *)
    _nTuN   : INT;                           (* 已存周期样本数 [个] / Stored period samples *)
    _fPk    : REAL;                          (* 本周期峰值 [工程单位] / Cycle peak *)
    _fTr    : REAL;                          (* 本周期谷值 [工程单位] / Cycle trough *)
    _fAmp   : REAL;                          (* 上周期振荡半幅值 [工程单位] / Previous cycle amplitude *)
    _fAmI   : REAL;                          (* 本周期半幅值中间量 [工程单位] / Current amplitude *)
    _fKpI   : REAL;                          (* Kp 中间量（出参域钳前）[-] / Kp intermediate *)
    _fTiI   : REAL;                          (* Ti 中间量 [s] / Ti intermediate *)
    _fTdI   : REAL;                          (* Td 中间量 [s] / Td intermediate *)
END_VAR
VAR CONSTANT
    DL_PAT_EPS   : REAL := 1.0E-6;           (* 判零容差 [-] / Epsilon *)
    DL_PAT_PI    : REAL := 3.14159265;       (* 圆周率常量（公开公式用）[-] / Pi constant *)
    DL_PAT_TUSTAB: REAL := 0.2;              (* 周期稳定相对容差（20%）[-] / Period stability tolerance *)
    DL_PAT_AMPDIV: REAL := 0.5;              (* 幅值发散相对判据（50%）[-] / Amplitude divergence ratio *)
    DL_PAT_NNEED : INT   := 3;               (* 完整周期需求数（边界②）[个] / Required periods *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tSample) / 1000.0;              (* 采样周期秒化（除子常量 1000） / Period seconds *)
_bCfgBad := (fRelayAmp <= DL_PAT_EPS) OR (fHyst <= DL_PAT_EPS) OR (fHyst >= fRelayAmp)   (* 幅值/迟滞正域闸（边界①） / Amplitude and hysteresis gates *)
            OR NOT (tSample > T#0S) OR NOT (tWatch > T#0S);   (* 采样/超时周期正域闸（边界①） / Period gates *)
rtStart(CLK := bStart);                                  (* 启动沿每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                  (* 复位沿每拍必调 / Reset edge every scan *)
_bFin := (fMeas = fMeas) AND ((fMeas - fMeas) = (fMeas - fMeas));   (* 测量 NaN 自反 + Inf 差判闸 / Measurement NaN and Inf gate *)
_bUpCr := FALSE;                                         (* 向上穿越当拍量预清 / Crossing preset *)
_bPrevRel := _bRelayI;                                   (* 上拍继电器态快照 / Relay state snapshot *)

(* —— 段 1：单拍量预清零（R107） —— *)
bRelaySug := _bRelayI;                                   (* 建议态出口 = 内部保持量（确定值） / Suggested relay outlet *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清结果 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                    (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_PatCause.eNone;                      (* 清成因 / Clear cause *)
    bValid := FALSE;                                     (* 清有效性出口 / Clear validity *)
    fKp := 0.0; fTi := 0.0; fTd := 0.0;                  (* 清 PID 初值出口 / Clear PID seed outlets *)
    nCycles := 0;                                        (* 清周期数出口 / Clear cycles *)
    _nTuN := 0; _fTacc := 0.0; _fTune := 0.0;            (* 清样本数/计时/耗时 / Clear samples and timers *)
    _bRelayI := FALSE;                                   (* 清继电器态 / Clear relay state *)
    _eState := E_DL_PatState.eIdle;                      (* 迁未整定相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                     (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_PatCause.eCfgIllegal;                (* 成因：组态非法 / Cause illegal config *)
    _eState := E_DL_PatState.eFault;                     (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_PatState.eIdle:                                 (* 未整定：出口保持确定值 / Idle *)
        bValid := FALSE;                                 (* 未整定有效性 FALSE（不留陈旧） / Validity false *)
        IF rtStart.Q AND bEnable AND NOT _bFault THEN
            _nTuN := 0; _fTacc := 0.0; _fTune := 0.0;    (* 清样本数/计时/耗时（新整定轮） / Clear samples and timers *)
            _fPk := fMeas; _fTr := fMeas;                (* 峰谷以首拍测量锚定 / Anchor peak and trough *)
            _fAmp := 0.0;                                (* 清上周期幅值 / Clear previous amplitude *)
            _bRelayI := FALSE;                           (* 继电器态从低起始 / Relay from low *)
            _eState := E_DL_PatState.eRelay;             (* 进入观测相 / Enter observing *)
        END_IF
    E_DL_PatState.eRelay:                                (* 观测相：迟滞继电器 + 周期/幅值测量 / Observing *)
        IF NOT bEnable THEN
            _eState := E_DL_PatState.eIdle;              (* 失能回未整定 / Back to idle *)
        ELSIF _bFin AND (_fDtSec > DL_PAT_EPS) THEN      (* 非有限拍整拍跳过（边界⑤） / Skip non-finite scan *)
            _fTacc := _fTacc + _fDtSec;                  (* 周期计时累加（暂停非快进） / Period acc advance *)
            _fTune := _fTune + _fDtSec;                  (* 总耗时累加 / Elapsed advance *)
            IF (NOT _bRelayI AND (fMeas < fSetpoint - fHyst)) OR (_bRelayI AND (fMeas > fSetpoint + fHyst)) THEN
                _bRelayI := NOT _bRelayI;                (* 迟滞带直比翻转（禁浮点等值） / Hysteresis band toggle *)
            END_IF
            IF _bPrevRel AND NOT _bRelayI THEN
                _bUpCr := TRUE;                          (* 向上穿越沿（低 → 高穿越上带） / Upward crossing edge *)
            END_IF
            IF fMeas > _fPk THEN
                _fPk := fMeas;                           (* 本周期峰值刷新 / Cycle peak update *)
            END_IF
            IF fMeas < _fTr THEN
                _fTr := fMeas;                           (* 本周期谷值刷新 / Cycle trough update *)
            END_IF
            IF _bUpCr THEN                               (* 向上穿越：收口一个完整周期 / Crossing closes a period *)
                IF _nTuN >= 1 THEN
                    IF _nTuN = 1 THEN
                        _fTu1 := _fTacc;                 (* 周期样本 1 收存 / Store sample 1 *)
                    ELSIF _nTuN = 2 THEN
                        _fTu2 := _fTacc;                 (* 周期样本 2 收存 / Store sample 2 *)
                    END_IF
                    _fAmp := _fAmI; _fAmI := (_fPk - _fTr) / 2.0;   (* 幅值转存 + 本周期半幅值（除子常量 2） / Amplitude roll *)
                END_IF
                _nTuN := _nTuN + 1;                      (* 完整周期计数净额 +1 / Period count *)
                IF _nTuN > 3 THEN _fTu3 := _fTacc; END_IF   (* 周期样本 3 收存（覆盖） / Store sample 3 *)
                _fTacc := 0.0;                           (* 周期计时重置（R227） / Period acc reset *)
                _fPk := fMeas; _fTr := fMeas;            (* 峰谷重锚定 / Peak and trough re-anchor *)
            END_IF
            IF (_fTu1 > DL_PAT_EPS) AND (_fTu2 > DL_PAT_EPS) AND (_fTu3 > DL_PAT_EPS) AND (_nTuN >= DL_PAT_NNEED + 1) THEN
                IF (ABS(_fTu3 - _fTu2) <= DL_PAT_TUSTAB * _fTu3) AND (ABS(_fTu2 - _fTu1) <= DL_PAT_TUSTAB * _fTu2) THEN
                    _fKpI := 4.0 * fRelayAmp / (DL_PAT_PI * _fAmI);   (* 周期稳定 + 公开公式 Kp（除子已过幅值正域闸，边界②③） / Stable periods, formula Kp *)
                    _fTiI := _fTu3 / 2.0;                (* 公开公式 Ti（除子常量 2） / Formula Ti *)
                    _fTdI := _fTu3 / 8.0;                (* 公开公式 Td（除子常量 8） / Formula Td *)
                    IF (_fAmI > DL_PAT_EPS) AND (_fKpI > 0.0) AND (_fTiI > 0.0) AND (_fTdI >= 0.0) THEN
                        fKp := _fKpI; fTi := _fTiI; fTd := _fTdI;   (* PID 初值出口（域钳后放行，边界③） / PID seed outlets *)
                        bValid := TRUE;                  (* 有效性 TRUE / Validity true *)
                        nCycles := _nTuN - 1;            (* 已测完整周期数出口 / Cycles outlet *)
                        _eState := E_DL_PatState.eReady; (* 迁整定完成相 / To ready *)
                    ELSE
                        bValid := FALSE; nCycles := _nTuN - 1;   (* 域钳拦截不出参数（边界③） / Clamp reject *)
                        _eCause := E_DL_PatCause.eNoOsc; (* 信息级成因（不置 bError，边界⑥） / Info cause *)
                        _eState := E_DL_PatState.eReady; (* 迁完成相（无效结论） / To ready invalid *)
                    END_IF
                ELSE
                    bValid := FALSE; nCycles := _nTuN - 1;   (* 周期不稳不出参数（边界③） / Unstable: invalid *)
                    _eCause := E_DL_PatCause.eNoOsc;     (* 信息级成因（边界⑥） / Info cause *)
                    _eState := E_DL_PatState.eReady;     (* 迁完成相（无效结论） / To ready invalid *)
                END_IF
            ELSIF _fTune > TIME_TO_LREAL(tWatch) THEN    (* 总超时：未达成 3 周期（信息级） / Watch timeout *)
                bValid := FALSE;                         (* 不出参数（边界②） / No parameters *)
                nCycles := _nTuN - 1;                    (* 已达成周期数照报 / Cycles outlet *)
                IF nCycles < 0 THEN nCycles := 0; END_IF (* 负数钳零（半周期不计） / Clamp negative *)
                _eCause := E_DL_PatCause.eNoOsc;         (* 信息级成因（边界⑥） / Info cause *)
                _eState := E_DL_PatState.eReady;         (* 迁完成相（无效结论） / To ready invalid *)
            END_IF
        END_IF
    E_DL_PatState.eReady:                                (* 完成相：结论与参数冻结保持 / Ready *)
        IF rtStart.Q THEN
            _eState := E_DL_PatState.eIdle;              (* 新启动沿经 eIdle 重入（防隐性回夹） / Restart via idle *)
        END_IF
    E_DL_PatState.eFault:                                (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                                (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                 (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_PatState.eFault; _bFault := TRUE;   (* 迁故障相 + 同步锁存 / To fault and latch *)
        _eCause := E_DL_PatCause.ePhaseBad;              (* 成因：非法相位 / Cause illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bRelaySug := _bRelayI;                                   (* 继电器建议态出口（观测相实时镜像） / Relay suggestion outlet *)
bError := _bFault;                                       (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                       (* 状态出口 / State outlet *)
eCause := _eCause;                                       (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
