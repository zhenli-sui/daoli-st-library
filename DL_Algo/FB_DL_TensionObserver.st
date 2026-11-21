(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TensionObserver
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 卷绕材料张力观测器（观测/换算层）。由电机转矩、卷径、角加速度、
 *                         传动比与机械效率反算材料张力估计：
 *                         T = 〔M·i·η − J·α − Tf_signed〕 / (D/2)
 *                         其中 M 为转矩输入、i 为传动比、η 为机械效率、J 为转动惯量（外部辨识
 *                         件给值，本件不内联辨识）、α 为角加速度、Tf_signed 为带方向滞环的
 *                         摩擦转矩、D 为实际卷径。惯量项与摩擦项分离补偿，避免把加减速转矩
 *                         误算成材料张力（这是现场最常见的伪张力来源）。
 * 分工声明 (Scope)      : 本件是**观测/换算**层，不做张力闭环控制；闭环控制属主为
 *                         `FB_DL_WindingTensionCtrl`（控制层）。二者**不允许多实例互相喂值**
 *                         （观测值不得作为控制器的唯一反馈，否则观测误差与闭环误差互相掩盖）。
 * 接口     (Interface)  : 输入 fTorqueNm 电机转矩、fDiaM 实际卷径、fAngAccRadS2 角加速度、
 *                         fGearRatio 传动比、fEff 机械效率、fInertiaKgm2 折算转动惯量、
 *                         fFrictionNm 摩擦转矩幅值、fVelRadS 角速度（方向判据）、fDirHystN
 *                         方向滞环带宽、fDiaMaxM 卷径上限、fTensionMinN / fTensionMaxN 输出
 *                         限幅、bReset 复位；输出 fTensionN 张力估计、bValid 结果有效、
 *                         bSaturated 卷径超域退化标记、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 除零闸：fDiaM / fGearRatio / fEff 任一 <= DL_FLOAT_EPS
 *                         → bValid = FALSE、fTensionN = 0.0 并置故障码（**绝不输出伪张力**，
 *                         现场联锁会把伪张力当真值去调张力）；
 *                         ② 卷径超域（fDiaM > fDiaMaxM）→ 退化保持上次有效值并置 bSaturated（信息级）；
 *                         ③ 输出限幅走显式 MIN / MAX 双侧钳位，禁止只钳一侧（单侧钳位会让
 *                         负向异常以「负张力」形式穿透到联锁）；
 *                         ④ 输入非有限（NaN / ±Inf）走故障闸，安全侧输出 0 并置码；
 *                         ⑤ 方向滞环：|fVelRadS| < fDirHystN 时保持上一拍方向，防零速附近抖动；
 *                         ⑥ R_TRIG 一枚段 0 无条件周期刷新；故障相迁出唯一路径 = bReset 上升沿；
 *                         ⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍输入齐备（卷径、传动比、效率均
 *                         高于 DL_FLOAT_EPS 且输入有限，全为当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：解除式不含任何计时器输出与锁存量比较，
 *                         输入修正后即可达，无恒假因子。
 * 码表     (Codes)      : 16#0002_03B0 故障级：张力观测故障总码（组态非法 / 卷径除零退化 /
 *                         输入非有限 / 非法相位），锁存至 bReset 上升沿，归因由 eCause 承载；
 *                         16#0002_04B3 信息级：卷径超上限，输出退化为保持上次有效值。
 *                         加码反证（R90）：退化保持时 fTensionN 仍为可用数值、bValid 仍为真，
 *                         若不单立码则该退化对 HMI 完全不可观测（bSaturated 只是布尔位，
 *                         无法进报警台账），故立一码。
 *                         码段说明：0002 段故障子带 03xx / 信息子带 04xx，本件取 03B0 / 04B3
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考卷绕张力静态平衡式与参数域，零代码行复制；
 *                         t2-1-lgf 技术子族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 2 · 序号 6）
 *==============================================================================*)

TYPE E_DL_TobState :
(
    eIdle  := 0,     // 输入不齐备，无可用估计 / Idle, inputs incomplete
    eRun   := 10,    // 观测运行 / Observing in run
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_TobCause :
(
    eNone        := 0,   // 无故障成因 / No cause
    eCfgIllegal  := 1,   // 组态非法 / Illegal configuration
    eDiaZero     := 2,   // 卷径/传动比/效率除零退化 / Divisor degenerate
    eNonFinite   := 3,   // 输入非有限 / Non-finite input
    ePhaseBad    := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_TensionObserver
VAR_INPUT
    fTorqueNm     : REAL := 0.0;         // 电机侧实测转矩 [N·m] / Measured motor torque [N·m]
    fDiaM         : REAL := 0.5;         // 实际卷径，域 > DL_FLOAT_EPS [m] / Actual roll diameter, domain > epsilon [m]
    fAngAccRadS2  : REAL := 0.0;         // 角加速度（减速为负） [rad/s²] / Angular acceleration, negative on decel [rad/s2]
    fGearRatio    : REAL := 10.0;        // 传动比（电机:卷轴），域 > DL_FLOAT_EPS [-] / Gear ratio, domain > epsilon [-]
    fEff          : REAL := 0.90;        // 机械效率，有效域 0.0 ~ 1.0，须 > DL_FLOAT_EPS [-] / Mechanical efficiency, domain (0,1]
    fInertiaKgm2  : REAL := 0.10;        // 折算到卷轴的转动惯量（外部辨识件给值） [kg·m²] / Reflected inertia from external identification [kg m2]
    fFrictionNm   : REAL := 0.0;         // 摩擦转矩幅值（恒正，方向由速度符号决定） [N·m] / Friction torque magnitude, positive [N·m]
    fVelRadS      : REAL := 0.0;         // 卷轴角速度（方向判据） [rad/s] / Roll angular velocity, direction criterion [rad/s]
    fDirHystN     : REAL := 0.5;         // 方向滞环带宽，域 >= 0.0 [rad/s] / Direction hysteresis band, domain >= 0.0 [rad/s]
    fDiaMaxM      : REAL := 1.2;         // 卷径上限，域 > 0.0 [m] / Diameter upper limit, domain > 0.0 [m]
    fTensionMinN  : REAL := 0.0;         // 张力输出下限 [N] / Tension output lower limit [N]
    fTensionMaxN  : REAL := 5000.0;      // 张力输出上限，域 > fTensionMinN [N] / Tension output upper limit [N]
    bReset        : BOOL := FALSE;       // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    fTensionN     : REAL;                // 材料张力估计（双侧限幅后） [N] / Estimated material tension, clamped both sides [N]
    bValid        : BOOL;                // 估计有效（输入齐备且在域内） [-] / Estimate valid
    bSaturated    : BOOL;                // 卷径超域退化标记（保持上次有效值） [-] / Diameter over-range degradation flag
    eState        : E_DL_TobState;       // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_TobCause;       // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;                // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;               // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_TobState := E_DL_TobState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_TobCause := E_DL_TobCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtReset       : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge
    _nDir         : INT;                 // 摩擦方向（带滞环，锁存量）：1 正 / -1 负 / 0 未定 [向] / Friction direction with hysteresis, latched
    _fFricSigned  : REAL;                // 带方向的摩擦转矩 [N·m] / Direction-signed friction torque [N·m]
    _fRadiusM     : REAL;                // 卷轴半径 [m] / Roll radius [m]
    _fRawTensionN : REAL;                // 限幅前张力 [N] / Unclamped tension [N]
    _fTensionHold : REAL;                // 上次有效张力（锁存量，退化保持用） [N] / Last valid tension, latched hold
    _bHoldValid   : BOOL;                // 是否存在有效历史值（锁存量） [-] / Hold value available flag
    _bDivBad      : BOOL;                // 除子退化当拍量 [-] / Divisor degenerate this scan
    _bNonFin      : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _bDiaOver     : BOOL;                // 卷径超上限当拍量 [-] / Diameter over limit this scan
    _bCfgBad      : BOOL;                // 组态非法当拍量 [-] / Illegal configuration
    _bFault       : BOOL;                // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;               // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;               // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;       // 浮点判零容差（除子与退化判据统一口径） [无量纲] / Float epsilon for zero tests
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件周期刷新 —— *)
_bNonFin := (fTorqueNm <> fTorqueNm) OR (fDiaM <> fDiaM) OR (fAngAccRadS2 <> fAngAccRadS2)      // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fGearRatio <> fGearRatio) OR (fEff <> fEff) OR (fInertiaKgm2 <> fInertiaKgm2)       // 参数 NaN 判 / Parameter NaN tests
         OR (fFrictionNm <> fFrictionNm) OR (fVelRadS <> fVelRadS) OR (fDirHystN <> fDirHystN);   // 摩擦与速度 NaN 判 / Friction and velocity NaN tests
_bDivBad := (fDiaM <= DL_FLOAT_EPS) OR (fGearRatio <= DL_FLOAT_EPS) OR (fEff <= DL_FLOAT_EPS);   // 三除子退化当拍量 / Three divisors degenerate
_bDiaOver := fDiaM > fDiaMaxM;                                                                   // 卷径超上限当拍量 / Diameter over limit
_bCfgBad := (fDiaMaxM <= 0.0) OR (fDirHystN < 0.0) OR (fTensionMaxN <= fTensionMinN)             // 组态域闸（覆盖每个参与判据的引脚，R151） / Config gate covering every criterion pin
            OR (fEff > 1.0) OR (fFrictionNm < 0.0);                                              // 效率上限与摩擦幅值正域闸 / Efficiency ceiling and friction positivity
rtReset(CLK := bReset);                                                                          // 复位沿，每拍必调（R228A） / Reset edge, called every scan

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo     := 16#0000_0000;        // 信息码每拍重算 / Info recomputed every scan
bSaturated := FALSE;               // 退化标记每拍预清 / Saturation flag preset
bValid     := FALSE;               // 有效位每拍预清 / Valid flag preset
nErrId     := 16#0000_0000;        // 事件码缺省无事件 / Event code default none
bError     := FALSE;               // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 输入有效闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_TobCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_TobState.eFault THEN
        _eState := E_DL_TobState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0002_03B0;                                             // 故障级：张力观测故障总码 / Fault-level: observer fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_TobCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 输入非有限 / Non-finite input
    _uFault := 16#0002_03B0;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_TobCause.eNonFinite;                                 // 归因：非有限 / Cause: non-finite
END_IF
IF (NOT _bFault) AND _bDivBad THEN                                       // 除子退化：绝不输出伪张力 / Divisor degenerate, never emit fake tension
    _uFault := 16#0002_03B0;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_TobCause.eDiaZero;                                   // 归因：除零退化 / Cause: divisor degenerate
END_IF

(* —— 段 3：摩擦方向判定（带滞环，零速附近保持上一拍方向） —— *)
IF fVelRadS > fDirHystN THEN
    _nDir := 1;                                                          // 正转方向 / Positive direction
ELSIF fVelRadS < (0.0 - fDirHystN) THEN
    _nDir := -1;                                                         // 反转方向 / Negative direction
ELSE
    _nDir := _nDir;                                                      // 滞环带内保持（显式自赋值，便于审计） / Hold inside hysteresis band
END_IF
IF _nDir >= 0 THEN
    _fFricSigned := fFrictionNm;                                         // 正向摩擦 / Positive friction
ELSIF _nDir < 0 THEN
    _fFricSigned := 0.0 - fFrictionNm;                                   // 反向摩擦（取负不用取反运算符） / Negative friction
ELSE
    _fFricSigned := 0.0;                                                 // 不可达兜底（INT 仅三态） / Unreachable guard
END_IF

(* —— 段 4：张力换算（仅无故障且输入有效时计算） —— *)
IF NOT _bFault THEN
    _fRadiusM := fDiaM * 0.5;                                            // 半径 = 直径 / 2 / Radius from diameter
    _fRawTensionN := (fTorqueNm * fGearRatio * fEff
                      - fInertiaKgm2 * fAngAccRadS2
                      - _fFricSigned) / _fRadiusM;                       // 静态平衡式反算张力 / Static balance inversion
    IF _fRawTensionN <> _fRawTensionN THEN                               // NaN 自反复检（判等禁令唯一例外） / NaN recheck
        bValid := FALSE;                                                 // 复检失败不生效 / Recheck failed
    ELSE
        IF _bDiaOver THEN                                                // 卷径超域：退化保持上次有效值 / Over-range, hold last valid
            bSaturated := TRUE;                                          // 退化标记 / Degradation flag
            _uInfo := 16#0002_04B3;                                      // 信息级：卷径超上限退化 / Info: diameter over limit
            IF _bHoldValid THEN
                fTensionN := _fTensionHold;                              // 保持上次有效值（不饱和到上限） / Hold last valid value
                bValid := TRUE;                                          // 保持值仍视为有效 / Hold value still valid
            ELSE
                fTensionN := 0.0;                                        // 无历史值输出 0 / No history, output zero
                bValid := FALSE;                                         // 无历史值判无效 / No history, invalid
            END_IF
        ELSE
            IF _fRawTensionN < fTensionMinN THEN                          // 双侧钳位（下侧） / Two-sided clamp, lower
                fTensionN := fTensionMinN;
            ELSIF _fRawTensionN > fTensionMaxN THEN                       // 双侧钳位（上侧） / Two-sided clamp, upper
                fTensionN := fTensionMaxN;
            ELSE
                fTensionN := _fRawTensionN;                               // 域内直通 / Pass through in range
            END_IF
            bValid := TRUE;                                              // 结果有效 / Result valid
            _fTensionHold := fTensionN;                                  // 更新保持槽（已过非有限闸） / Update hold slot after finite gate
            _bHoldValid := TRUE;                                         // 保持槽可用 / Hold slot available
        END_IF
    END_IF
END_IF

(* —— 段 5：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND (NOT _bDivBad) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_TobCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_TobState.eFault) THEN
    _eState := E_DL_TobState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_TobState.eIdle:
    IF bValid AND (NOT _bFault) THEN                                     // 出口 1：估计有效 / Estimate valid
        _eState := E_DL_TobState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_TobState.eFault;
    END_IF

E_DL_TobState.eRun:
    IF (NOT bValid) AND (NOT _bFault) THEN                               // 出口 1：估计失效（前置消失，R98） / Estimate invalid
        _eState := E_DL_TobState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_TobState.eFault;
    END_IF

E_DL_TobState.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0002_03B0;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_TobCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_TobState.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放；故障相安全侧钳位） —— *)
IF _bFault THEN
    fTensionN := 0.0;                                                    // 故障相安全侧：零张力，绝不外溢伪值 / Safe side in fault: zero tension
    bValid    := FALSE;                                                  // 故障相判无效 / Invalid in fault
    bSaturated := FALSE;                                                 // 故障相清退化标记 / Clear degradation flag in fault
ELSIF NOT bValid THEN
    fTensionN := 0.0;                                                    // 无效相零输出（不保持，避免掩盖失效） / Zero when invalid
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
