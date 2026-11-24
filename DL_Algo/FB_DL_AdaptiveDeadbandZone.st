(*
  Name        : FB_DL_AdaptiveDeadbandZone
  Category    : DL_Algo
  Version     : 1.0.0
  Purpose     : 噪声带自适应死区：以一阶差分绝对值的 EMA 在线估计噪声幅值，按倍率整定死区宽度（上下限可组态），输出死区后信号仅供显示/滤波链使用；/ Noise-adaptive deadband: estimate noise amplitude by EMA of absolute first differences, scale it into a configurable deadband width, output the deadbanded signal
  溯源        : 借 t2-5-modpid·deadband 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：fDbMax - fDbMin <= eps / fDbMin < 0 / fNoiseGain <= 0 / fAlpha 不在 (0,1] → 锁存故障，输出保持；
                ② 非有限输入该拍不更新噪声估计与输出（保留上拍值）；
                ③ 死区判据 |fIn - fOut| > db 用容差比较（禁 = / <>）；
                ④ 首拍无前值时以当前输入初始化，不产生虚假大差分（隐性回夹防护）；
                ⑤ 倍率钳位：db 先按 [fDbMin, fDbMax] 饱和再参与判据，饱和方向为「更保守的大死区」。
*)
TYPE E_DL_AdzState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eRun   := 10,                            (* 自适应运行 / Adaptive running *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_AdzCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：限值/倍率/系数越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AdaptiveDeadbandZone
VAR_INPUT
    fIn        : REAL := 0.0;                (* 原始测量输入（噪声信号）[工程单位] / Raw noisy measurement *)
    fNoiseGain : REAL := 3.0;                (* 噪声→死区倍率（典型 2..4），域 > 0 [-] / Noise to deadband gain, > 0 *)
    fDbMin     : REAL := 0.0;                (* 死区下限，域 >= 0 [工程单位] / Deadband lower limit, >= 0 *)
    fDbMax     : REAL := 10.0;               (* 死区上限，域 > fDbMin [工程单位] / Deadband upper limit *)
    fAlpha     : REAL := 0.2;                (* 噪声 EMA 新值权重，域 (0, 1] [-] / Noise EMA weight, (0,1] *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清噪声估计与输出 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fOut       : REAL;                       (* 死区处理后信号 [工程单位] / Deadbanded signal *)
    fDeadband  : REAL;                       (* 当前生效死区宽度（半宽）[工程单位] / Effective deadband half-width *)
    fNoiseEst  : REAL;                       (* 噪声幅值估计（|Δ| EMA）[工程单位] / Estimated noise amplitude *)
    bDbActive  : BOOL;                       (* 死区正在吞掉变化（本拍输出保持）[-] / Deadband currently suppressing *)
    eState     : E_DL_AdzState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_AdzCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_AdzState := E_DL_AdzState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_AdzCause := E_DL_AdzCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
    _bInit    : BOOL;                        (* 前值初始化标志（首拍不产虚假差分） / First-scan init flag *)
    _bFinite  : BOOL;                        (* 输入有限性当拍量 / Input finiteness this scan *)
    _fPrev    : REAL;                        (* 上拍输入快照（差分基准）[工程单位] / Previous input snapshot *)
    _fDiff    : REAL;                        (* 本拍一阶差分绝对值 [工程单位] / Absolute first difference *)
    _fNoise   : REAL;                        (* 噪声幅值 EMA 内部量 [工程单位] / Noise EMA internal *)
    _fDb      : REAL;                        (* 未钳位死区 = 倍率 × 噪声 [工程单位] / Unclamped deadband *)
    _fDelta   : REAL;                        (* |输入 - 输出| 偏离量（判据用）[工程单位] / Deviation magnitude *)
    _fOne     : REAL;                        (* 实数 1 常量（EMA 系数补数用）[-] / Real one constant *)
END_VAR
VAR CONSTANT
    DL_ADZ_EPS : REAL := 1.0E-6;             (* 容差（REAL 量级，带宽/系数/比较共用）[-] / Tolerance epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := ((fDbMax - fDbMin) <= DL_ADZ_EPS)                                  (* 死区上下限颠倒闸 / Band inversion gate *)
            OR (fDbMin < 0.0)                                                  (* 下限负域闸 / Negative lower-limit gate *)
            OR (fNoiseGain <= DL_ADZ_EPS)                                      (* 倍率正域闸（防死区恒 0 或取反） / Gain positive gate *)
            OR (fAlpha <= DL_ADZ_EPS) OR (fAlpha > 1.0);                       (* EMA 系数域闸 (0,1] / EMA weight gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
_bFinite := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn));                       (* NaN 自反 + Inf 差判联合闸 / NaN and Inf gate *)
_fOne := 1.0;                                                                  (* 常量装载（避免字面量散布） / Constant load *)

(* —— 段 1：单拍量预清零（R107） —— *)
bDbActive := FALSE;                                                            (* 死区抑制指示预清 / Suppression preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清噪声估计 + 清初始化 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AdzCause.eNone;                                            (* 清成因 / Clear cause *)
    _fNoise := 0.0;                                                            (* 清噪声估计 / Clear noise estimate *)
    _fPrev := 0.0;                                                             (* 清差分基准 / Clear previous sample *)
    _bInit := FALSE;                                                           (* 清初始化标志（首拍重新对齐） / Clear init flag *)
    fOut := 0.0;                                                               (* 清输出 / Clear output *)
    fDeadband := fDbMin;                                                       (* 死区回下限（组态基准值） / Deadband back to lower limit *)
    fNoiseEst := 0.0;                                                          (* 清噪声出口 / Clear noise outlet *)
    _eState := E_DL_AdzState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AdzCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_AdzState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AdzState.eIdle:                                                       (* 未使能：输出直通、死区置下限 / Disabled *)
        _bInit := FALSE;                                                       (* 失能清初始化，重使能时重新对齐 / Clear init while disabled *)
        fDeadband := fDbMin;                                                   (* 死区取组态下限 / Deadband = lower limit *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_AdzState.eRun;                                     (* 使能进入自适应 / Enter adaptive *)
        END_IF
    E_DL_AdzState.eRun:                                                        (* 自适应相：噪声估计 + 死区整定 + 死区输出 / Adaptive *)
        IF NOT bEnable THEN
            _eState := E_DL_AdzState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF _bFinite THEN
            IF NOT _bInit THEN
                _fPrev := fIn;                                                 (* 首拍对齐：基准取当前输入（防虚假大差分） / First scan alignment *)
                fOut := fIn;                                                   (* 首拍直通（无历史可比） / First scan passthrough *)
                _bInit := TRUE;                                                (* 立初始化标志 / Set init flag *)
            END_IF
            _fDiff := ABS(fIn - _fPrev);                                       (* 一阶差分绝对值（噪声代理）[工程单位] / Absolute first difference *)
            _fNoise := (1.0 - fAlpha) * _fNoise + fAlpha * _fDiff;             (* 噪声 EMA（系数和恒 1，无漂移） / Noise EMA *)
            _fPrev := fIn;                                                     (* 快照推进（仅有限拍推进） / Advance snapshot *)
            _fDb := fNoiseGain * _fNoise;                                      (* 倍率映射到死区半宽 / Gain to deadband *)
            IF _fDb < fDbMin THEN
                _fDb := fDbMin;                                                (* 下限饱和：死区不小于组态下限 / Lower saturation *)
            ELSIF _fDb > fDbMax THEN
                _fDb := fDbMax;                                                (* 上限饱和：防死区吞掉真实变化过大 / Upper saturation *)
            END_IF
            fDeadband := _fDb;                                                 (* 死区出口（实时派生） / Deadband outlet *)
            fNoiseEst := _fNoise;                                              (* 噪声估计出口 / Noise outlet *)
            _fDelta := ABS(fIn - fOut);                                        (* 与当前输出的偏离量 / Deviation from output *)
            IF _fDelta > _fDb THEN
                fOut := fIn;                                                   (* 偏离超死区：输出跟随（更新） / Exceeds band: follow *)
                bDbActive := FALSE;                                            (* 未抑制 / Not suppressing *)
            ELSE
                bDbActive := TRUE;                                             (* 偏离在带内：输出保持（抑制噪声） / Within band: hold *)
            END_IF
        END_IF                                                                 (* 非有限输入：噪声估计与输出均保持上拍（边界②） / Non-finite: hold *)
    E_DL_AdzState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AdzState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_AdzCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
