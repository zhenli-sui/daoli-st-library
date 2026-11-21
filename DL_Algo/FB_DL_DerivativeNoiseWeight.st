(*
  Name        : FB_DL_DerivativeNoiseWeight
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : 微分项噪声权重与降权：以原始微分为基准，用低通差分残差估计高频能量占比，占比超阈时按比例衰减有效微分增益 Kd，抑制噪声放大而不改 PidController 契约；/ Derivative noise weighting: estimate high-frequency energy share from the residual between raw and low-passed derivative, and attenuate the effective Kd proportionally when the share exceeds threshold
  溯源        : 借 t2-5-modpid·deriv 的分类/参数域组织，clean-room 实现
  Boundary    : ① 采样周期闸：tDt <= T#0S → 锁存故障（除零前置，dt 秒化后仍 > eps）；
                ② 能量比除子闸：eSig + eHf <= eps → 占比按 0 处理（不产生 Inf/NaN）；
                ③ 非有限输入该拍不推进差分与能量估计（保留上拍值，防污染 EMA）；
                ④ 衰减上限钳位 fAttenMax ∈ [0,1]，KdEff >= KdNom·(1-fAttenMax) 不会取负；
                ⑤ 本件只作观测器输出，不修改任何控制回路参数（属主边界声明）。
*)
TYPE E_DL_DnwState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 观测运行 / Observing *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_DnwCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：周期/增益/阈值越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_DerivativeNoiseWeight
VAR_INPUT
    fIn        : REAL := 0.0;                (* 反馈测量输入（PV）[工程单位] / Feedback measurement *)
    tDt        : TIME := T#10MS;             (* 采样周期（微分除子），域 > T#0S [ms] / Sampling period, must be > 0 *)
    fKdNom     : REAL := 1.0;                (* 标称微分增益（不动原参数），域 > 0 [s] / Nominal derivative gain, > 0 *)
    fRatioThr  : REAL := 0.3;                (* 高频能量占比阈值，域 (0,1) [-] / High-frequency ratio threshold *)
    fAttenMax  : REAL := 0.9;                (* 最大衰减比，域 [0,1] [-] / Maximum attenuation ratio *)
    fBeta      : REAL := 0.1;                (* 低通/能量 EMA 权重，域 (0,1] [-] / Filter and energy EMA weight *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清估计与输出 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDerivRaw  : REAL;                       (* 原始微分（未滤波）[工程单位/s] / Raw derivative *)
    fDerivFilt : REAL;                       (* 低通微分 [工程单位/s] / Low-passed derivative *)
    fHfRatio   : REAL;                       (* 高频能量占比 0..1 [-] / High-frequency energy ratio *)
    fKdEff     : REAL;                       (* 降权后有效微分增益 [s] / Effective attenuated derivative gain *)
    bAtten     : BOOL;                       (* 降权生效指示 [-] / Attenuation active *)
    eState     : E_DL_DnwState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_DnwCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_DnwState := E_DL_DnwState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_DnwCause := E_DL_DnwCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bInit   : BOOL;                         (* 前值初始化标志（首拍不产虚假微分尖峰） / First-scan init *)
    _bFinite : BOOL;                         (* 输入有限性当拍量 / Input finiteness *)
    _fPrev   : REAL;                         (* 上拍输入快照 [工程单位] / Previous input *)
    _fDtSec  : REAL;                         (* 采样周期折算秒值，域 > eps [s] / Sampling period in seconds *)
    _fHf     : REAL;                         (* 高频残差 = 原始 - 低通 [工程单位/s] / High-frequency residual *)
    _fEHf    : REAL;                         (* 高频能量 EMA [工程单位²/s²] / High-frequency energy EMA *)
    _fESig   : REAL;                         (* 低通信号能量 EMA [工程单位²/s²] / Signal energy EMA *)
    _fRatio  : REAL;                         (* 未钳位占比 [-] / Unclamped ratio *)
    _fAtten  : REAL;                         (* 本拍衰减比 0..fAttenMax [-] / Attenuation this scan *)
END_VAR
VAR CONSTANT
    DL_DNW_EPS : REAL := 1.0E-6;             (* 判零容差（REAL 量级）[-] / Epsilon *)
    DL_DNW_ONE : REAL := 1.0;                (* 实数 1 常量 [-] / Real one *)
    DL_DNW_ZERO: REAL := 0.0;                (* 实数零常量 [-] / Real zero *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tDt) / 1000.0;                                        (* 周期秒化（除子为常量 1000，无除零） / Period to seconds *)
_bCfgBad := NOT (tDt > T#0S)                                                   (* 周期正域闸（除零前置） / Period gate *)
            OR (fKdNom <= DL_DNW_EPS)                                          (* 微分增益正域闸 / Kd positive gate *)
            OR (fRatioThr <= DL_DNW_EPS) OR (fRatioThr >= DL_DNW_ONE)          (* 阈值域闸 (0,1) / Threshold gate *)
            OR (fAttenMax < DL_DNW_ZERO) OR (fAttenMax > DL_DNW_ONE)           (* 衰减比域闸 [0,1] / Attenuation gate *)
            OR (fBeta <= DL_DNW_EPS) OR (fBeta > DL_DNW_ONE);                  (* EMA 系数域闸 (0,1] / EMA weight gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn));                       (* NaN 自反 + Inf 差判联合闸 / NaN and Inf gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
bAtten := FALSE;                                                               (* 降权指示预清 / Attenuation preset *)
_fAtten := DL_DNW_ZERO;                                                        (* 衰减比预清 / Attenuation preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清估计 + 清初始化 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_DnwCause.eNone;                                            (* 清成因 / Clear cause *)
    _fPrev := DL_DNW_ZERO;                                                     (* 清前值 / Clear previous *)
    _fHf := DL_DNW_ZERO;                                                       (* 清高频残差 / Clear residual *)
    _fEHf := DL_DNW_ZERO;                                                      (* 清高频能量 / Clear hf energy *)
    _fESig := DL_DNW_ZERO;                                                     (* 清信号能量 / Clear signal energy *)
    _bInit := FALSE;                                                           (* 清初始化标志 / Clear init *)
    fDerivRaw := DL_DNW_ZERO;                                                  (* 清原始微分出口 / Clear raw outlet *)
    fDerivFilt := DL_DNW_ZERO;                                                 (* 清低通微分出口 / Clear filtered outlet *)
    fHfRatio := DL_DNW_ZERO;                                                   (* 清占比出口 / Clear ratio outlet *)
    fKdEff := fKdNom;                                                          (* 有效增益回标称（无降权基准） / Effective gain back to nominal *)
    _eState := E_DL_DnwState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_DnwCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_DnwState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_DnwState.eIdle:                                                       (* 未使能：输出回标称基准 / Disabled *)
        fKdEff := fKdNom;                                                      (* 无降权：有效增益 = 标称 / No attenuation *)
        _bInit := FALSE;                                                       (* 失能清初始化 / Clear init *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_DnwState.eRun;                                     (* 使能进入观测 / Enter observing *)
        END_IF
    E_DL_DnwState.eRun:                                                        (* 观测相：微分 + 能量分离 + 降权 / Observing *)
        IF NOT bEnable THEN
            _eState := E_DL_DnwState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite AND (_fDtSec > DL_DNW_EPS) THEN
            IF NOT _bInit THEN
                _fPrev := fIn;                                                 (* 首拍对齐：防虚假微分尖峰 / First-scan alignment *)
                _bInit := TRUE;                                                (* 立初始化标志 / Set init *)
            END_IF
            fDerivRaw := (fIn - _fPrev) / _fDtSec;                             (* 原始微分：除子 dt 已过闸 > eps [工程单位/s] / Raw derivative, divisor gated *)
            fDerivFilt := fDerivFilt + fBeta * (fDerivRaw - fDerivFilt);       (* 一阶低通（EMA 形式，系数 (0,1]） / First-order low pass *)
            _fHf := fDerivRaw - fDerivFilt;                                    (* 高频残差：低通漏掉的快变成分 / High-frequency residual *)
            _fEHf := (1.0 - fBeta) * _fEHf + fBeta * _fHf * _fHf;              (* 高频能量 EMA（平方项恒非负） / HF energy EMA *)
            _fESig := (1.0 - fBeta) * _fESig + fBeta * fDerivFilt * fDerivFilt; (* 信号能量 EMA / Signal energy EMA *)
            _fPrev := fIn;                                                     (* 前值推进（仅有限拍推进） / Advance previous *)
            IF (_fEHf + _fESig) > DL_DNW_EPS THEN
                _fRatio := _fEHf / (_fEHf + _fESig);                           (* 占比：除子已过闸（边界②） / Ratio, divisor gated *)
            ELSE
                _fRatio := DL_DNW_ZERO;                                        (* 能量全零：占比按 0（无噪声语义） / Zero energy: ratio 0 *)
            END_IF
            IF _fRatio < DL_DNW_ZERO THEN
                _fRatio := DL_DNW_ZERO;                                        (* 下限兜底（数值噪声防负） / Lower fallback *)
            ELSIF _fRatio > DL_DNW_ONE THEN
                _fRatio := DL_DNW_ONE;                                         (* 上限饱和 1.0 / Upper saturation *)
            END_IF
            fHfRatio := _fRatio;                                               (* 占比出口 / Ratio outlet *)
            IF _fRatio > fRatioThr THEN
                _fAtten := fAttenMax * (_fRatio - fRatioThr) / (1.0 - fRatioThr);   (* 超阈后线性升权衰减（除子 < 1 且已过闸） / Linear attenuation beyond threshold *)
                IF _fAtten > fAttenMax THEN
                    _fAtten := fAttenMax;                                      (* 衰减上限钳位 / Attenuation cap *)
                ELSIF _fAtten < DL_DNW_ZERO THEN
                    _fAtten := DL_DNW_ZERO;                                    (* 衰减下限钳位 / Attenuation floor *)
                END_IF
                bAtten := TRUE;                                                (* 降权生效 / Attenuation active *)
            END_IF
            fKdEff := fKdNom * (1.0 - _fAtten);                                (* 有效增益：_fAtten <= 1 保证非负（边界④） / Effective gain, non-negative *)
        END_IF                                                                 (* 非有限输入：全部估计保持上拍（边界③） / Non-finite: hold *)
    E_DL_DnwState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_DnwState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_DnwCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
