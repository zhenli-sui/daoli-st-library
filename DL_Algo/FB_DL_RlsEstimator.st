(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RlsEstimator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 递推最小二乘（RLS，带遗忘因子 λ）二阶参数估计器。
 *                         模型 y = θ1·u + θ2（两参数：增益与偏置，φ = [u, 1]ᵀ）。
 *                         每拍标准 RLS 更新：
 *                           n  = P·φ                     （2×1）
 *                           den= λ + φᵀ·P·φ              （标量）
 *                           K  = n / den                 （2×1 增益向量）
 *                           ε  = y − φᵀ·θ                （先验误差）
 *                           θ ← θ + K·ε
 *                           P ← (P − K·nᵀ) / λ
 *                         激励不足保护：协方差迹 tr(P) = p11 + p22 小于 fTraceMin 时**拒估并保持**
 *                         （θ 与 P 都不动，bRefused 置位）——残差已经很小、信息矩阵病态时继续更新
 *                         只会把参数拖向噪声，这是 RLS 最典型的失效模式。
 *                         数值稳定：① den 前判零（λ 与 φᵀPφ 均非负，den ≥ λ > 0，仍双保险）；
 *                         ② P 的对角元按 [fPMin, fPMax] 钳位（下界防协方差崩塌导致 K 爆炸，
 *                         上界防遗忘因子长期作用下的发散）；③ θ 按 ±fThetaMax 饱和并置 bLimited。
 * 接口     (Interface)  : 输入 fU 回归量、fY 观测值、fLambda 遗忘因子（0,1]、fTraceMin 激励阈值、
 *                         fPMin / fPMax 协方差对角钳位、fThetaMax 参数饱和限、bEnable 使能、
 *                         bReset 复位；输出 fTheta1（增益）/ fTheta2（偏置）、fTrace 协方差迹、
 *                         bEstimating 有有效估计、bRefused 本拍拒估（激励不足）、bLimited 参数
 *                         触饱和、eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做参数估计，不把参数写进任何轴/回路**。
 *                         参数注入（例如把 θ1 写给速度前馈增益）由上层显式完成并自担无扰切换；
 *                         本件不做注入、不做无扰（那是 `FB_DL_AdaptiveLeadLag` 一类的职责）。
 *                         ② 组态闸：fLambda <= 0.0 或 > 1.0（遗忘因子必须开区间 (0,1]）、
 *                         fTraceMin <= 0.0、fPMin <= 0.0、fPMax <= fPMin、fThetaMax <= 0.0、
 *                         任一引脚 NaN → 故障锁存，θ 输出 0、bEstimating=FALSE。
 *                         ③ 初始协方差取 P = fPMax·I（大初值=高初始不确定度，标准做法），
 *                         复位时重置为初值并把 θ 清零。
 *                         ④ bEnable=FALSE 语义（R191 声明）：**冻结更新但保持已估计参数**（不重置），
 *                         便于"暂停辨识再继续"；与"复位"是两种不同意图，不可混用。
 *                         ⑤ 单枚 R_TRIG（bReset）段 0 无条件周期刷新；无 TON，无跨相复位问题。
 *                         ⑥ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑦ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 来源标签 (Source Tag) : 自研线（RLS 为公开经典算法，Ljung《System Identification》标准推导；
 *                         ST 实现、激励拒估与钳位策略为本库自研，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清故障锁存、θ 归零、P 回初值。
 *                         自证可满足：复位不依赖任何锁存量。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 REAL 参数 + BOOL（bEstimating /
 *                         bRefused / bLimited / bError）+ ENUM（eState / eCause）；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前判零 + 协方差/参数双侧钳位 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ R_TRIG 段 0 无条件刷新
 * 返修记录 (Repair)     : v1.0.1（R47 P0 返修）新增 _bInit 首扫初始化标志：首拍与复位沿执行同款
 *                         初始化（θ 归零、P = fPMax·I），消除"上电首拍 P 未初始化即参与更新"的隐患；
 *                         初始化块改为 `IF rtReset.Q OR (NOT _bInit)` 单入口，_bInit 在块内置位以保证只进一次。
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 4 · 序号 16）
 *==============================================================================*)

TYPE E_DL_RlsState :
(
    eIdle  := 0,    // 未取得有效估计 / No valid estimate yet
    eRun   := 10,   // 递推估计运行相 / Recursive estimation running
    eFault := 90    // 组态故障相 / Configuration fault phase
);
END_TYPE

TYPE E_DL_RlsCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（λ/阈值/钳位/非有限） / Illegal configuration
    eTraceLow   := 2,   // 激励不足，本拍拒估 / Insufficient excitation, estimate refused
    eThetaSat   := 3,   // 参数触饱和（模型与数据不匹配） / Parameter saturation
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_RlsEstimator
VAR_INPUT
    fU        : REAL := 0.0;        // 回归量（如速度/指令） [工程单位] / Regressor, e.g. velocity [unit]
    fY        : REAL := 0.0;        // 观测值（如力矩/输出） [工程单位] / Observation, e.g. torque [unit]
    fLambda   : REAL := 0.995;      // 遗忘因子，域 (0, 1] [无量纲] / Forgetting factor, open-closed interval (0,1]
    fTraceMin : REAL := 1.0E-4;     // 激励阈值（协方差迹下限），域 > 0.0 [无量纲] / Excitation threshold on the covariance trace, > 0
    fPMin     : REAL := 1.0E-6;     // 协方差对角下限，域 > 0.0 [无量纲] / Covariance diagonal lower clamp, > 0
    fPMax     : REAL := 1.0E6;      // 协方差对角上限，域 > fPMin [无量纲] / Covariance diagonal upper clamp, > fPMin
    fThetaMax : REAL := 1.0E4;      // 参数饱和限（|θ| 上限），域 > 0.0 [工程单位] / Parameter saturation limit, > 0
    bEnable   : BOOL := TRUE;       // 估计使能；FALSE 冻结更新但保持参数 [-] / Enable; FALSE freezes updates but keeps the estimate
    bReset    : BOOL := FALSE;      // 复位，上升沿清故障、θ 归零、P 回初值 [-] / Reset, clears fault, zeroes theta and re-initialises P
END_VAR
VAR_OUTPUT
    fTheta1   : REAL;               // 参数 θ1（增益） [工程单位] / Parameter theta1, the gain
    fTheta2   : REAL;               // 参数 θ2（偏置） [工程单位] / Parameter theta2, the offset
    fTrace    : REAL;               // 协方差迹 tr(P) = p11 + p22 [无量纲] / Covariance trace
    bEstimating : BOOL;             // 已取得有效估计（至少完成一次成功更新） [-] / A valid estimate exists
    bRefused  : BOOL;               // 本拍拒估（激励不足） [-] / Estimate refused this scan
    bLimited  : BOOL;               // 本拍参数触饱和 [-] / Parameter saturation hit this scan
    eState    : E_DL_RlsState;      // 状态出口 [-] / State outlet
    eCause    : E_DL_RlsCause;      // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError    : BOOL;               // 故障标志（组态非法） [-] / Error flag, illegal configuration
END_VAR
VAR
    _eState  : E_DL_RlsState := E_DL_RlsState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_RlsCause := E_DL_RlsCause.eNone;    // 成因锁存量 / Latched cause
    rtReset  : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bInit   : BOOL := FALSE;       // 首扫初始化标志（首拍执行与复位沿同款初始化） / First-scan init flag
    _fTh1    : REAL;                // θ1 锁存（锁存量） [工程单位] / Latched theta1
    _fTh2    : REAL;                // θ2 锁存（锁存量） [工程单位] / Latched theta2
    _fP11    : REAL;                // 协方差 p11（锁存量） [无量纲] / Covariance p11, latched
    _fP12    : REAL;                // 协方差 p12（锁存量） [无量纲] / Covariance p12, latched
    _fP21    : REAL;                // 协方差 p21（锁存量） [无量纲] / Covariance p21, latched
    _fP22    : REAL;                // 协方差 p22（锁存量） [无量纲] / Covariance p22, latched
    _fN1     : REAL;                // P·φ 第一分量当拍量 [无量纲] / First component of P·phi
    _fN2     : REAL;                // P·φ 第二分量当拍量 [无量纲] / Second component of P·phi
    _fDen    : REAL;                // λ + φᵀPφ 当拍量 [无量纲] / Scalar denominator
    _fK1     : REAL;                // 增益向量第一分量当拍量 [无量纲] / Gain vector, first component
    _fK2     : REAL;                // 增益向量第二分量当拍量 [无量纲] / Gain vector, second component
    _fErr    : REAL;                // 先验误差当拍量 [工程单位] / A priori error
    _fTr     : REAL;                // 协方差迹当拍量 [无量纲] / Covariance trace
    _fC1     : REAL;                // 更新中间量 c1 = p11 − k1·n1 [无量纲] / Intermediate c1
    _fC2     : REAL;                // 更新中间量 c2 = p12 − k1·n2 [无量纲] / Intermediate c2
    _fC3     : REAL;                // 更新中间量 c3 = p21 − k2·n1 [无量纲] / Intermediate c3
    _fC4     : REAL;                // 更新中间量 c4 = p22 − k2·n2 [无量纲] / Intermediate c4
    _bFault  : BOOL;                // 组态故障锁存位（锁存量） / Latched configuration fault
    _bValid  : BOOL;                // 已成功更新过（锁存量） / At least one successful update, latched
    _bCfgBad : BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _bRefuse : BOOL;                // 本拍拒估当拍量 [-] / Refusal this scan
    _bSat    : BOOL;                // 本拍饱和当拍量 [-] / Saturation this scan
END_VAR
VAR CONSTANT
    DL_RLS_EPS  : REAL := 1.0E-12;  // 分母判零容差（比通用 eps 更紧，因 den >= λ） [无量纲] / Denominator epsilon, tighter than usual
    DL_RLS_ONE  : REAL := 1.0;      // 遗忘因子上界 1.0 [无量纲] / Forgetting factor upper bound
END_VAR

(* —— 段 0：判据派生 + 复位沿无条件周期刷新 —— *)
_bNonFin := (fU <> fU) OR (fY <> fY) OR (fLambda <> fLambda)              // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fTraceMin <> fTraceMin) OR (fPMin <> fPMin) OR (fPMax <> fPMax)
         OR (fThetaMax <> fThetaMax);
_bCfgBad := (fLambda <= 0.0) OR (fLambda > DL_RLS_ONE)                    // 遗忘因子开闭区间 (0,1] / Forgetting factor in (0,1]
         OR (fTraceMin <= 0.0) OR (fPMin <= 0.0) OR (fPMax <= fPMin)      // 阈值与钳位几何闸 / Threshold and clamp geometry
         OR (fThetaMax <= 0.0) OR _bNonFin;                               // 参数限 + 非有限 / Parameter limit and non-finite
rtReset(CLK := bReset);                                                    // 复位沿，每拍必调（R228A） / Reset edge, every scan

(* —— 段 1：单拍量预清零（锁存量 _fTh1/_fTh2/_fP*/_bFault/_bValid 不入清单，R107） —— *)
bEstimating := FALSE;       // 估计有效位每拍预清 / Estimating preset
bRefused    := FALSE;       // 拒估位每拍预清 / Refused preset
bLimited    := FALSE;       // 饱和位每拍预清 / Limited preset
bError      := FALSE;       // 故障标志每拍预清（R45 配对） / Error flag preset
_bRefuse    := FALSE;       // 拒估当拍量预清 / Refusal preset
_bSat       := FALSE;       // 饱和当拍量预清 / Saturation preset

(* —— 段 2：复位沿 ∨ 首扫（θ 归零、P 回大初值=高初始不确定度；R47 返修 v1.0.1） —— *)
IF rtReset.Q OR (NOT _bInit) THEN
    _bInit  := TRUE;                        // 首扫置位：后续仅在复位沿重入（只进一次） / Set on the first scan only
    _bFault := FALSE;                       // 清故障锁存 / Clear the fault latch
    _bValid := FALSE;                       // 清有效标记（重新累积信息） / Clear the validity flag
    _eCause := E_DL_RlsCause.eNone;         // 清成因 / Clear cause
    _fTh1   := 0.0;                         // θ1 归零 / Zero theta1
    _fTh2   := 0.0;                         // θ2 归零 / Zero theta2
    _fP11   := fPMax;                       // 初值 p11 = 上限 / Initial p11 at the upper clamp
    _fP12   := 0.0;                         // 初值 p12 = 0 / Initial p12 zero
    _fP21   := 0.0;                         // 初值 p21 = 0 / Initial p21 zero
    _fP22   := fPMax;                       // 初值 p22 = 上限 / Initial p22 at the upper clamp
    IF _eState = E_DL_RlsState.eFault THEN
        _eState := E_DL_RlsState.eIdle;     // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                        // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_RlsCause.eCfgIllegal;   // 归因：组态非法 / Cause: illegal configuration
    _fTh1   := 0.0;                         // 参数清零，不宣称 / Parameters zeroed, not claimed
    _fTh2   := 0.0;
END_IF

(* —— 段 3：激励判据（协方差迹 = 信息量，低即拒估） —— *)
_fTr := _fP11 + _fP22;                      // 协方差迹 / Covariance trace
_bRefuse := _fTr < fTraceMin;               // 迹低于阈值 → 激励不足 / Trace below threshold means insufficient excitation

(* —— 段 4：RLS 一拍更新（使能 ∧ 组态合法 ∧ 激励充足） —— *)
IF bEnable AND (NOT _bCfgBad) AND (NOT _bRefuse) AND (NOT rtReset.Q) THEN
    _fN1  := (_fP11 * fU) + (_fP12 * DL_RLS_ONE);            // P·φ 第一分量（φ=[u,1]） / P·phi, first component
    _fN2  := (_fP21 * fU) + (_fP22 * DL_RLS_ONE);            // P·φ 第二分量 / P·phi, second component
    _fDen := fLambda + ((fU * _fN1) + _fN2);                 // λ + φᵀPφ（恒 >= λ > 0，仍判零双保险） / Scalar denominator
    IF ABS(_fDen) > DL_RLS_EPS THEN                          // 除零闸 / Divide gate
        _fK1  := _fN1 / _fDen;                               // 增益第一分量 / Gain, first component
        _fK2  := _fN2 / _fDen;                               // 增益第二分量 / Gain, second component
        _fErr := fY - ((_fTh1 * fU) + _fTh2);                // 先验误差 ε = y − φᵀθ / A priori error
        _fTh1 := _fTh1 + (_fK1 * _fErr);                     // θ1 更新 / Theta1 update
        _fTh2 := _fTh2 + (_fK2 * _fErr);                     // θ2 更新 / Theta2 update
        _fC1  := _fP11 - (_fK1 * _fN1);                      // P 更新中间量 c1 / Intermediate c1
        _fC2  := _fP12 - (_fK1 * _fN2);                      // P 更新中间量 c2 / Intermediate c2
        _fC3  := _fP21 - (_fK2 * _fN1);                      // P 更新中间量 c3 / Intermediate c3
        _fC4  := _fP22 - (_fK2 * _fN2);                      // P 更新中间量 c4 / Intermediate c4
        _fP11 := _fC1 / fLambda;                             // 除以遗忘因子（λ 已闸 > 0） / Divide by lambda, gated above zero
        _fP12 := _fC2 / fLambda;
        _fP21 := _fC3 / fLambda;
        _fP22 := _fC4 / fLambda;
        IF _fP11 > fPMax THEN                                // 对角上限钳（防长期遗忘发散） / Upper diagonal clamp
            _fP11 := fPMax;
        END_IF
        IF _fP11 < fPMin THEN                                // 对角下限钳（防协方差崩塌） / Lower diagonal clamp
            _fP11 := fPMin;
        END_IF
        IF _fP22 > fPMax THEN
            _fP22 := fPMax;
        END_IF
        IF _fP22 < fPMin THEN
            _fP22 := fPMin;
        END_IF
        IF _fTh1 > fThetaMax THEN                            // 参数饱和（正） / Saturate theta1 high
            _fTh1 := fThetaMax;
            _bSat := TRUE;
        ELSIF _fTh1 < -fThetaMax THEN                        // 参数饱和（负） / Saturate theta1 low
            _fTh1 := -fThetaMax;
            _bSat := TRUE;
        END_IF
        IF _fTh2 > fThetaMax THEN                            // 参数饱和（正） / Saturate theta2 high
            _fTh2 := fThetaMax;
            _bSat := TRUE;
        ELSIF _fTh2 < -fThetaMax THEN                        // 参数饱和（负） / Saturate theta2 low
            _fTh2 := -fThetaMax;
            _bSat := TRUE;
        END_IF
        _bValid := TRUE;                                     // 至少成功一次 / At least one success
        IF _eState = E_DL_RlsState.eIdle THEN
            _eState := E_DL_RlsState.eRun;                   // 首次成功入运行相 / First success enters run
        END_IF
        IF _bSat THEN
            _eCause := E_DL_RlsCause.eThetaSat;              // 提示：参数触饱和（信息级） / Notice: parameter saturation
        END_IF
    ELSE
        _bRefuse := TRUE;                                    // 分母病态：按拒估处理，不动状态 / Degenerate denominator: refuse, keep state
    END_IF
ELSIF _bRefuse AND bEnable AND (NOT _bCfgBad) THEN
    _eCause := E_DL_RlsCause.eTraceLow;                      // 归因：激励不足拒估 / Cause: insufficient excitation
END_IF

(* —— 段 5：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_RlsState.eFault) THEN
    _eState := E_DL_RlsState.eFault;                         // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_RlsState.eIdle:
    IF _bFault THEN                                          // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_RlsState.eFault;
    ELSIF _bValid THEN                                       // 出口 2：已取得有效估计 / A valid estimate exists
        _eState := E_DL_RlsState.eRun;
    END_IF

E_DL_RlsState.eRun:
    IF _bFault THEN                                          // 出口 1：组态故障 / Configuration fault
        _eState := E_DL_RlsState.eFault;
    ELSIF _bValid = FALSE THEN                               // 出口 2：复位清空估计 / Estimate cleared by reset
        _eState := E_DL_RlsState.eIdle;
    END_IF

E_DL_RlsState.eFault:
    ;                                                        // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _bFault := TRUE;                                         // 非法相位兜底锁存 / Illegal-phase fallback latch
    _eCause := E_DL_RlsCause.ePhaseBad;                      // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_RlsState.eFault;                         // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 7：出口单点映射（参数恒回放，拒估时保持上次值——这正是"拒估并保持"的含义） —— *)
fTheta1     := _fTh1;                                        // θ1 出口（保持语义） / Theta1 outlet, held on refusal
fTheta2     := _fTh2;                                        // θ2 出口（保持语义） / Theta2 outlet, held on refusal
fTrace      := _fTr;                                         // 迹出口 / Trace outlet
bEstimating := _bValid AND (NOT _bFault);                    // 有效估计 = 成功过且无故障 / Valid estimate
bRefused    := _bRefuse;                                     // 拒估出口 / Refusal outlet
bLimited    := _bSat;                                        // 饱和出口 / Saturation outlet
bError      := _bFault;                                      // 故障标志与锁存同源（R191） / Error from latch
eState      := _eState;                                      // 状态出口 / State outlet
eCause      := _eCause;                                      // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
