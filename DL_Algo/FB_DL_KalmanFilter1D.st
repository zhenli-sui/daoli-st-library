(*==============================================================================
 * 组件名称 (Component)  : FB_DL_KalmanFilter1D
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 标量卡尔曼滤波。状态 _fX 与协方差 _fP，逐拍「预测 → 更新」两段：
 *                         预测 _fP := _fP + fQ（随机游走过程噪声）；更新按标量卡尔曼增益
 *                         K = _fP / (_fP + fR)，用新息 |fMeas - _fX| 修正状态并压缩协方差。
 *                         野值门限：新息绝对值超 fInnovLimit → 本拍拒收（bRejected = TRUE，
 *                         不更新状态，协方差保留预测后的增大值，使下一拍更容易接受真变化）。
 *                         协方差发散保护：_fP > fPMax 持续 tDivTime → 用当拍实测重初始化并
 *                         置信息级。失能 bEnable = FALSE → 直通 fMeas 并**冻结协方差**（不归零，
 *                         保证恢复使能时无扰）。
 * 接口     (Interface)  : 输入 fMeas 实测值、fQ 过程噪声、fR 测量噪声、fInnovLimit 新息门限、
 *                         fPMax 协方差发散上限、tDivTime 发散确认时间、bEnable 使能、bReset 复位；
 *                         输出 fOut 滤波值、fPOut 当前协方差、bRejected 本拍拒收单拍位、
 *                         bDiverged 本拍重初始化单拍位、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：fQ / fR / fInnovLimit / fPMax 任一 <= 0.0、tDivTime <= T#0S、
 *                         或任一浮点引脚为 NaN → 故障锁存（NaN 自反判为判等禁令唯一例外）；
 *                         ② 除法前判除子：_fP + fR <= DL_FLOAT_EPS 时跳过更新（不产生 Inf）；
 *                         ③ 新息与状态全走容差比较，禁 `=` / `<>` 判量值；
 *                         ④ NaN 实测 → 本拍整体拒收并置信息级，**不让 NaN 进入 _fP / _fX**
 *                         （R133 / R135：非有限值绝不写入保持槽）；
 *                         ⑤ TON 一枚 + R_TRIG 一枚段 0 无条件周期刷新；
 *                         ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 输出语义 (Fallback)   : 【R191 声明】bEnable = FALSE → 输出**直通** fMeas（非冻结），协方差冻结
 *                         保持末值；eFault 相 → 输出**冻结保持**末次有效估计（不清零，避免下游
 *                         把 0 当成真测量），bError 同时为真。两分支语义互不相同，均在此显式声明。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧〔非发散态 ∨ 本次复位已完成协方差重装〕。
 *                         自证可满足（终审两式 1）：复位沿本身在发散态执行 _fP := fR 重装，
 *                         括内第二项即为真，故解除式不存在恒假因子。反例说明：若写成单纯
 *                         「∧ 非发散态」，故障相内 _fP 不再更新 → 该项恒假 → 故障永久不可恢复，
 *                         属 R152 恒假组合反例，故本件按括内析取式实现。
 * 码表     (Codes)      : 16#0002_03AF 故障级：卡尔曼滤波故障总码（组态非法 / 非法相位），
 *                         锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0002_04B2 信息级：非故障台账事件（野值拒收 / 发散重初始化 / 除子退化跳过）。
 *                         加码反证（R90）：三类信息事件均不改变 eCause 与 bError，且 fOut 仍为
 *                         可用值，故须留痕；三类共用一码的依据是「都只要求留痕、不要求区分动作」，
 *                         区分由 bRejected / bDiverged 两个专用布尔出口承担，无需第二个码位。
 *                         码段说明：0002 段故障子带 03xx / 信息子带 04xx，本件取 03AF / 04B2
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考公开标量卡尔曼递推式与参数域，零代码行复制）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 1 · 序号 5）
 *==============================================================================*)

TYPE E_DL_Kf1State :
(
    eIdle  := 0,     // 失能待使能（直通输出） / Idle, disabled, pass-through output
    eRun   := 10,    // 滤波运行 / Filtering in run
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_Kf1Cause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法（含 NaN 参数） / Illegal configuration, including NaN parameters
    ePhaseBad   := 2    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_KalmanFilter1D
VAR_INPUT
    fMeas       : REAL := 0.0;          // 实测值 [工程单位] / Measured value
    fQ          : REAL := 0.01;         // 过程噪声方差，域 > 0.0 [工程单位²] / Process noise variance, domain > 0.0
    fR          : REAL := 0.10;         // 测量噪声方差，域 > 0.0 [工程单位²] / Measurement noise variance, domain > 0.0
    fInnovLimit : REAL := 5.0;          // 新息门限（野值判据），域 > 0.0 [工程单位] / Innovation limit, domain > 0.0
    fPMax       : REAL := 100.0;        // 协方差发散上限，域 > 0.0 [工程单位²] / Covariance divergence limit, domain > 0.0
    tDivTime    : TIME := T#5S;         // 发散确认时间，域 > T#0S [ms] / Divergence confirm time, domain > T#0S
    bEnable     : BOOL := TRUE;         // 滤波使能，FALSE 时直通并冻结协方差 [-] / Enable, FALSE passes through and freezes covariance
    bReset      : BOOL := FALSE;        // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    fOut        : REAL;                 // 滤波输出值（故障相冻结保持末值） [工程单位] / Filtered output, frozen in fault
    fPOut       : REAL;                 // 当前协方差 [工程单位²] / Current covariance
    bRejected   : BOOL;                 // 本拍野值拒收单拍位 [-] / Single-scan outlier rejection flag
    bDiverged   : BOOL;                 // 本拍发散重初始化单拍位 [-] / Single-scan divergence reinit flag
    eState      : E_DL_Kf1State;        // 状态出口，段 6 单点映射 / State outlet
    eCause      : E_DL_Kf1Cause;        // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError      : BOOL;                 // 故障锁存标志 [-] / Fault latch flag
    nErrId      : UDINT;                // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState     : E_DL_Kf1State := E_DL_Kf1State.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause     : E_DL_Kf1Cause := E_DL_Kf1Cause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonDiv      : TON;                  // 发散确认计时，段 0 无条件调用 / Divergence confirm timer
    rtReset     : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _fX         : REAL;                 // 状态估计（锁存量） [工程单位] / State estimate, latched
    _fP         : REAL;                 // 状态协方差（锁存量） [工程单位²] / State covariance, latched
    _fInnov     : REAL;                 // 本拍新息 [工程单位] / Innovation this scan
    _fK         : REAL;                 // 本拍卡尔曼增益 [-] / Kalman gain this scan
    _fDen       : REAL;                 // 更新除子 _fP + fR [工程单位²] / Update divisor _fP + fR
    _bInit      : BOOL;                 // 首次初始化完成位（锁存量） [-] / Initialized flag, latched
    _bNonFin    : BOOL;                 // 实测非有限当拍量 [-] / Non-finite measurement this scan
    _bDivCond   : BOOL;                 // 协方差超上限当拍量 [-] / Covariance above limit this scan
    _bCfgBad    : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bReinit    : BOOL;                 // 本次复位已做协方差重装当拍量 [-] / Covariance re-armed by this reset
    _bFault     : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault     : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo      : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;      // 浮点判零容差（除子与判等统一口径） [工程单位²] / Float epsilon for zero tests [unit2]
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_bNonFin := (fMeas <> fMeas) OR ((fMeas - fMeas) <> (fMeas - fMeas));       // 实测 NaN 自反 + Inf 差值自减双判（判等禁令唯一例外） / NaN and Inf detection
_bDivCond := _fP > fPMax;                                                   // 协方差超上限当拍量 / Covariance above limit
_bCfgBad := (fQ <> fQ) OR (fR <> fR) OR (fInnovLimit <> fInnovLimit) OR (fPMax <> fPMax)   // 参数 NaN 组态闸（R151 覆盖每个引脚） / NaN config gate covering every pin
            OR (fQ <= 0.0) OR (fR <= 0.0) OR (fInnovLimit <= 0.0) OR (fPMax <= 0.0)        // 正域组态闸 / Positive-domain config gate
            OR (tDivTime <= T#0S);                                                          // 时间组态闸 / Time config gate
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调（R228A） / Reset edge, called every scan
tonDiv(IN := _bDivCond AND bEnable, PT := tDivTime);                        // 发散确认计时，IN 由判据派生 / Divergence timer, IN derived from verdict

(* —— 段 1：单拍量预清零（锁存量与实例不入清单，R107） —— *)
_uInfo     := 16#0000_0000;        // 信息码每拍重算 / Info recomputed every scan
bRejected  := FALSE;               // 拒收位每拍预清，唯一分支置位（R44 单拍脉冲范式） / Reject flag preset, set in one branch only
bDiverged  := FALSE;               // 重初始化位每拍预清 / Divergence flag preset
_bReinit   := FALSE;               // 复位重装标记每拍预清 / Reset re-arm marker preset
nErrId     := 16#0000_0000;        // 事件码缺省无事件 / Event code default none
bError     := FALSE;               // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿（含发散重装）+ 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_Kf1Cause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _bDivCond AND (NOT _bNonFin) THEN                                 // 发散态复位：协方差重装（解除可达性关键） / Divergent reset re-arms covariance
        _fP := fR;                                                       // 协方差按测量噪声重装 / Covariance re-armed to measurement noise
        _fX := fMeas;                                                    // 状态按当拍实测重装 / State re-armed to current measurement
        _bReinit := TRUE;                                                // 标记本次复位已完成重装 / Mark re-arm done by this reset
    END_IF
    IF _eState = E_DL_Kf1State.eFault THEN
        _eState := E_DL_Kf1State.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0002_03AF;                                             // 故障级：卡尔曼滤波故障总码 / Fault-level: filter fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_Kf1Cause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：首次初始化（仅在无故障且实测有限时取首值） —— *)
IF (NOT _bFault) AND (NOT _bInit) AND (NOT _bNonFin) THEN
    _fX := fMeas;                                                        // 首值取实测 / First value from measurement
    _fP := fR;                                                           // 协方差取测量噪声 / Covariance from measurement noise
    _bInit := TRUE;                                                      // 初始化完成（锁存量） / Initialization done
END_IF

(* —— 段 4：预测 → 更新（仅运行态执行） —— *)
IF (NOT _bFault) AND bEnable AND _bInit AND (NOT _bNonFin) THEN
    _fP := _fP + fQ;                                                     // 预测：协方差增大 / Predict, covariance grows
    IF tonDiv.Q THEN                                                     // 发散确认到：用实测重初始化 / Divergence confirmed, reinit from measurement
        _fX := fMeas;
        _fP := fR;
        bDiverged := TRUE;                                               // 单拍位：本拍做过重初始化 / Single-scan reinit flag
        _uInfo := 16#0002_04B2;                                          // 信息级：发散重初始化留痕 / Info: divergence reinit recorded
    ELSE
        _fInnov := fMeas - _fX;                                          // 新息 / Innovation
        IF ABS(_fInnov) > fInnovLimit THEN                               // 野值门限 / Outlier gate
            bRejected := TRUE;                                           // 单拍位：本拍拒收 / Single-scan reject flag
            _uInfo := 16#0002_04B2;                                      // 信息级：野值拒收留痕 / Info: outlier rejection recorded
        ELSE
            _fDen := _fP + fR;                                           // 更新除子 / Update divisor
            IF _fDen > DL_FLOAT_EPS THEN                                 // 除零前置判 / Divide-by-zero guard
                _fK := _fP / _fDen;                                      // 卡尔曼增益 / Kalman gain
                _fX := _fX + _fK * _fInnov;                              // 状态更新 / State update
                _fP := (1.0 - _fK) * _fP;                                // 协方差压缩 / Covariance shrink
            ELSE
                _uInfo := 16#0002_04B2;                                  // 信息级：除子退化跳过 / Info: degenerate divisor skipped
            END_IF
        END_IF
    END_IF
END_IF
IF (NOT _bFault) AND bEnable AND _bNonFin THEN                           // NaN 实测：本拍拒收留痕 / NaN measurement, reject and record
    bRejected := TRUE;                                                   // 单拍位：本拍拒收 / Single-scan reject flag
    _uInfo := 16#0002_04B2;                                              // 信息级：非有限实测拒收 / Info: non-finite measurement rejected
END_IF

(* —— 段 5：故障解除式（R240 全当拍量；括内析取式自证可满足） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND ((NOT _bDivCond) OR _bReinit) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_Kf1Cause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_Kf1State.eFault) THEN
    _eState := E_DL_Kf1State.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_Kf1State.eIdle:
    IF bEnable AND _bInit AND (NOT _bFault) THEN                         // 出口 1：使能且已初始化 / Enabled and initialized
        _eState := E_DL_Kf1State.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_Kf1State.eFault;
    END_IF

E_DL_Kf1State.eRun:
    IF (NOT bEnable) THEN                                                // 出口 1：失能（前置条件消失，R98） / Disabled, precondition gone
        _eState := E_DL_Kf1State.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_Kf1State.eFault;
    END_IF

E_DL_Kf1State.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0002_03AF;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_Kf1Cause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_Kf1State.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放；故障相显式钳位） —— *)
IF _bFault THEN
    fOut := _fX;                                                         // 故障相冻结保持末次有效估计（R191 声明） / Frozen hold in fault
ELSIF NOT bEnable THEN
    fOut := fMeas;                                                       // 失能相直通实测（R191 声明） / Pass-through when disabled
ELSE
    fOut := _fX;                                                         // 运行相输出状态估计 / Run-phase state estimate
END_IF
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN                // 出口非有限复检兜底 / Output non-finite recheck
    fOut := 0.0;                                                         // 非有限即归 0，绝不外溢 / Zero out, never propagate
END_IF
fPOut := _fP;                                                            // 协方差出口（锁存量回放） / Covariance outlet
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
