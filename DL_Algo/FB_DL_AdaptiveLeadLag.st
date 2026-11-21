(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AdaptiveLeadLag
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 自适应超前-滞后补偿（误差驱动参数缓调 + 无扰切换）。
 *                         ① 补偿本体：连续式 G(s) = (1 + Tlead·s) / (1 + Tlag·s) 的离散实现
 *                            超前段：yLead = x + Tlead·(x − xPrev) / fDtS
 *                            滞后段：y     = y + (yLead − y) · fDtS / (Tlag + fDtS)
 *                            两段都用 fDtS（调用方给的采样周期，秒），**不做 TIME→数值转换**。
 *                         ② 参数缓调：Tlead 按误差幅值缓升缓降（相位裕度需求随误差增大），
 *                            每拍步长 = fAdaptGain·|fErr|·fDtS，并被 fAdaptRate·fDtS 限幅
 *                            （限幅保证"缓"：参数变化速度受控，不会一拍跳变引起输出突跳）。
 *                            Tlead 始终钳在 [fTleadMin, fTleadMax]。
 *                         ③ 无扰切换：bEnable 上升沿开始，fBlend 以固定步长 fDtS / fRampSec
 *                            从 0 线性升到 1；输出 = 切换前保持值 + blend·(计算值 − 保持值)。
 *                            **不用 TON 的 ET 做斜坡**，因而无 TIME→数值转换（跨平台一致），
 *                            且斜坡长度由 fRampSec 显式给出，可预测、可复现。
 * 接口     (Interface)  : 输入 fIn 输入信号、fErr 跟踪误差（驱动自适应）、fDtS 采样周期（秒）、
 *                         fTleadInit / fTlagInit 初值、fTleadMin / fTleadMax 超前时间限、
 *                         fAdaptGain 自适应增益、fAdaptRate 参数变化率限、fRampSec 无扰斜坡时长、
 *                         fOutMax 输出饱和限、bEnable 使能、bReset 复位；输出 fOut 补偿输出、
 *                         fTleadUsed / fTlagUsed 实际使用参数、fBlend 切换斜坡进度、bActive 已生效、
 *                         bLimited 输出饱和、eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件是补偿器本体，输出 fOut 供上层注入，
 *                         不直接写轴指令/不进闭环回路**；本件不做参数辨识（辨识属 `FB_DL_RlsEstimator`），
 *                         只按误差缓调。
 *                         ② 组态闸：fDtS <= DL_ALL_EPS（除零 + 步长退化）、fTlagInit < 0.0、
 *                         fTleadMin < 0.0、fTleadMax <= fTleadMin、fAdaptGain < 0.0、
 *                         fAdaptRate <= 0.0、fRampSec <= DL_ALL_EPS、fOutMax <= 0.0、任一 NaN
 *                         → 故障锁存，fOut 置 0（安全侧）。
 *                         ③ bEnable=FALSE 语义（R191 声明）：fOut 立即置 0（补偿器禁用即不注入），
 *                         但**保留 fTleadUsed 与内部滞后状态**，下次使能由 fBlend 斜坡重新接续，
 *                         属"冻结参数、清零输出"，与"复位"（参数回初值）不同。
 *                         ④ 单枚 R_TRIG（bReset 与 bEnable 各一枚）段 0 无条件周期刷新。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_StribeckFrictionComp`（摩擦模型本体）分工——本件是线性
 *                         超前滞后相位补偿，那件是非线性摩擦补偿；两者可并行相加注入，
 *                         但都不自己注入（注入点唯一）。
 * 来源标签 (Source Tag) : T2-1 ◐（公开经典超前-滞后补偿结构与自适应步长思想，参考参数域，
 *                         零代码行复制；固定步长无扰斜坡为本库自研包装）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清故障、参数回初值、清滞后状态与斜坡。
 *                         自证可满足：复位不依赖锁存量。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 REAL + BOOL（bActive / bLimited /
 *                         bError）+ ENUM（eState / eCause）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸 + 参数区间闸 + 输出饱和 + NaN 闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 4 · 序号 17）
 *==============================================================================*)

TYPE E_DL_AllState :
(
    eIdle  := 0,    // 未使能或未完成切换斜坡 / Disabled, ramp not started
    eRamp  := 10,   // 无扰切换斜坡进行中 / Bumpless transfer ramp in progress
    eRun   := 20,   // 补偿器全效运行 / Compensator fully engaged
    eFault := 90    // 组态故障相 / Configuration fault phase
);
END_TYPE

TYPE E_DL_AllCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（采样周期/时间限/增益/非有限） / Illegal configuration
    eOutSat     := 2,   // 输出触饱和（补偿量需求超限） / Output saturated
    ePhaseBad   := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AdaptiveLeadLag
VAR_INPUT
    fIn        : REAL := 0.0;       // 输入信号 [工程单位] / Input signal [unit]
    fErr       : REAL := 0.0;       // 跟踪误差（驱动自适应） [工程单位] / Tracking error driving the adaptation [unit]
    fDtS       : REAL := 0.001;     // 采样周期，域 > DL_ALL_EPS [s] / Sample period, domain > epsilon [s]
    fTleadInit : REAL := 0.05;      // 超前时间初值，域 >= 0.0 [s] / Initial lead time, >= 0.0 [s]
    fTlagInit  : REAL := 0.20;      // 滞后时间初值，域 >= 0.0 [s] / Initial lag time, >= 0.0 [s]
    fTleadMin  : REAL := 0.01;      // 超前时间下限，域 >= 0.0 [s] / Lead time lower bound, >= 0.0 [s]
    fTleadMax  : REAL := 0.50;      // 超前时间上限，域 > fTleadMin [s] / Lead time upper bound, > lower [s]
    fAdaptGain : REAL := 0.10;      // 自适应增益，域 >= 0.0 [1/s] / Adaptation gain, >= 0.0 [1/s]
    fAdaptRate : REAL := 0.50;      // 参数变化率限，域 > 0.0 [s/s] / Parameter rate limit, > 0.0 [s/s]
    fRampSec   : REAL := 0.20;      // 无扰斜坡时长，域 > DL_ALL_EPS [s] / Bumpless ramp duration, > epsilon [s]
    fOutMax    : REAL := 100.0;     // 输出饱和限，域 > 0.0 [工程单位] / Output saturation limit, > 0.0 [unit]
    bEnable    : BOOL := FALSE;     // 使能；FALSE 时输出置 0 但保留参数 [-] / Enable; FALSE zeroes the output but keeps parameters
    bReset     : BOOL := FALSE;     // 复位，上升沿清故障并使参数回初值 [-] / Reset, clears the fault and restores initial parameters
END_VAR
VAR_OUTPUT
    fOut       : REAL;              // 补偿输出（已饱和） [工程单位] / Compensation output, saturated [unit]
    fTleadUsed : REAL;              // 实际使用中的超前时间 [s] / Lead time in use [s]
    fTlagUsed  : REAL;              // 实际使用中的滞后时间 [s] / Lag time in use [s]
    fBlend     : REAL;              // 切换斜坡进度，域 0..1 [-] / Ramp progress in 0..1
    bActive    : BOOL;              // 补偿器全效生效（blend 已达 1） [-] / Compensator fully engaged
    bLimited   : BOOL;              // 本拍输出触饱和 [-] / Output saturated this scan
    eState     : E_DL_AllState;     // 状态出口 [-] / State outlet
    eCause     : E_DL_AllCause;     // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError     : BOOL;              // 故障标志（组态非法） [-] / Error flag, illegal configuration
END_VAR
VAR
    _eState  : E_DL_AllState := E_DL_AllState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_AllCause := E_DL_AllCause.eNone;    // 成因出口暂存 / Cause staging
    rtReset  : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
    rtEnable : R_TRIG;              // 使能沿实例，段 0 无条件调用 / Enable edge instance
    _fTlead  : REAL;                // 超前时间（锁存量） [s] / Lead time, latched [s]
    _fXPrev  : REAL;                // 上拍输入快照（锁存量） [工程单位] / Previous input, latched [unit]
    _fYState : REAL;                // 滞后段内部状态（锁存量） [工程单位] / Lag stage internal state, latched [unit]
    _fBlend  : REAL;                // 斜坡进度（锁存量） [-] / Ramp progress, latched
    _fHold   : REAL;                // 切换前保持值（锁存量） [工程单位] / Value held before transfer, latched [unit]
    _fLead   : REAL;                // 超前段输出当拍量 [工程单位] / Lead-stage output this scan [unit]
    _fComp   : REAL;                // 补偿计算值当拍量 [工程单位] / Computed compensation this scan [unit]
    _fStep   : REAL;                // 参数调整步长当拍量 [s] / Parameter step this scan [s]
    _fRate   : REAL;                // 每拍允许的最大参数变化量 [s] / Maximum parameter change per scan [s]
    _bFault  : BOOL;                // 组态故障锁存位（锁存量） / Latched configuration fault
    _bCfgBad : BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _bSat    : BOOL;                // 本拍输出饱和当拍量 [-] / Output saturation this scan
END_VAR
VAR CONSTANT
    DL_ALL_EPS  : REAL := 1.0E-9;   // 时间判零容差（秒级，需比通用 eps 更紧） [无量纲] / Time epsilon in seconds, tighter than usual
    DL_ALL_ONE  : REAL := 1.0;      // 斜坡进度上限 1.0 [无量纲] / Ramp ceiling
    DL_ALL_ZERO : REAL := 0.0;      // 零基准 [无量纲] / Zero baseline
END_VAR

(* —— 段 0：判据派生 + 两沿实例无条件周期刷新 —— *)
_bNonFin := (fIn <> fIn) OR (fErr <> fErr) OR (fDtS <> fDtS)              // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fTleadInit <> fTleadInit) OR (fTlagInit <> fTlagInit)
         OR (fTleadMin <> fTleadMin) OR (fTleadMax <> fTleadMax)
         OR (fAdaptGain <> fAdaptGain) OR (fAdaptRate <> fAdaptRate)
         OR (fRampSec <> fRampSec) OR (fOutMax <> fOutMax);
_bCfgBad := (fDtS <= DL_ALL_EPS)                                          // 采样周期闸（除零 + 步长退化） / Sample period gate
         OR (fTleadInit < 0.0) OR (fTlagInit < 0.0)                       // 时间初值非负闸 / Non-negative initial times
         OR (fTleadMin < 0.0) OR (fTleadMax <= fTleadMin)                 // 超前限区间闸 / Lead bounds interval gate
         OR (fAdaptGain < 0.0) OR (fAdaptRate <= 0.0)                     // 自适应增益与速率闸 / Adaptation gain and rate gates
         OR (fRampSec <= DL_ALL_EPS) OR (fOutMax <= 0.0) OR _bNonFin;     // 斜坡与饱和限 + 非有限 / Ramp, saturation limit, non-finite
rtReset(CLK := bReset);                                                   // 复位沿，每拍必调（R228A） / Reset edge, every scan
rtEnable(CLK := bEnable);                                                 // 使能沿，每拍必调 / Enable edge, every scan

(* —— 段 1：单拍量预清零（锁存量 _fTlead/_fXPrev/_fYState/_fBlend/_fHold/_bFault 不入清单） —— *)
fOut     := 0.0;        // 输出每拍预清 / Output preset
fBlend   := 0.0;        // 斜坡出口预清 / Ramp outlet preset
bActive  := FALSE;      // 生效位预清 / Active preset
bLimited := FALSE;      // 饱和位预清 / Limited preset
bError   := FALSE;      // 故障标志预清（R45 配对） / Error flag preset
_bSat    := FALSE;      // 饱和当拍量预清 / Saturation preset

(* —— 段 2：复位沿（参数回初值、清滞后状态与斜坡） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;                       // 清故障锁存 / Clear the fault latch
    _eCause  := E_DL_AllCause.eNone;         // 清成因 / Clear cause
    _fTlead  := fTleadInit;                  // 超前时间回初值 / Lead time back to the initial value
    _fYState := 0.0;                         // 滞后段状态清零 / Lag state cleared
    _fXPrev  := fIn;                         // 输入快照对齐当拍（防复位首拍伪微分） / Align the snapshot to the present input
    _fBlend  := 0.0;                         // 斜坡清零 / Ramp cleared
    _fHold   := 0.0;                         // 保持值清零 / Hold cleared
    IF _eState = E_DL_AllState.eFault THEN
        _eState := E_DL_AllState.eIdle;      // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                         // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_AllCause.eCfgIllegal;    // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：无扰切换斜坡管理（使能沿起坡；固定步长，无 TIME→数值转换） —— *)
IF rtEnable.Q THEN
    _fHold  := fOut;                         // 记录切换前输出为保持值（若无历史则为 0） / Capture the pre-transfer output
    _fBlend := 0.0;                          // 从 0 起坡 / Start the ramp at zero
    _eState := E_DL_AllState.eRamp;          // 入斜坡相 / Enter the ramp phase
END_IF
IF bEnable AND (NOT _bCfgBad) THEN
    IF _fBlend < DL_ALL_ONE THEN
        _fBlend := _fBlend + (fDtS / fRampSec);     // 固定步长推进（分母已闸） / Fixed-step advance, denominator gated
        IF _fBlend >= DL_ALL_ONE THEN
            _fBlend := DL_ALL_ONE;                  // 上限钳 / Ceiling clamp
            _eState := E_DL_AllState.eRun;           // 斜坡完成，全效运行 / Ramp done, fully engaged
        ELSE
            _eState := E_DL_AllState.eRamp;          // 仍在斜坡 / Still ramping
        END_IF
    END_IF
ELSIF NOT bEnable THEN
    _fBlend := 0.0;                                 // 禁用即清坡（下次使能重新无扰起坡） / Disable clears the ramp
END_IF

(* —— 段 4：自适应参数缓调（误差驱动，速率限幅，区间钳位） —— *)
IF bEnable AND (NOT _bCfgBad) THEN
    _fStep := fAdaptGain * ABS(fErr) * fDtS;                    // 误差驱动的期望步长 [s] / Desired step from the error
    _fRate := fAdaptRate * fDtS;                                // 每拍允许的最大变化量 [s] / Allowed change per scan
    IF _fStep > _fRate THEN
        _fStep := _fRate;                                       // 速率限幅（"缓"调的实现点） / Rate limit, where "slow" is enforced
    END_IF
    IF fErr > 0.0 THEN
        _fTlead := _fTlead + _fStep;                            // 误差为正：加大超前 / Positive error increases the lead
    ELSE
        _fTlead := _fTlead - _fStep;                            // 误差为负：减小超前 / Negative error reduces the lead
    END_IF
    IF _fTlead > fTleadMax THEN
        _fTlead := fTleadMax;                                   // 上限钳 / Upper clamp
    END_IF
    IF _fTlead < fTleadMin THEN
        _fTlead := fTleadMin;                                   // 下限钳 / Lower clamp
    END_IF
END_IF

(* —— 段 5：补偿本体计算（超前段 → 滞后段） —— *)
IF bEnable AND (NOT _bCfgBad) THEN
    _fLead := fIn + (_fTlead * ((fIn - _fXPrev) / fDtS));       // 超前段（分母已闸） / Lead stage, denominator gated
    IF (fTlagInit + fDtS) > DL_ALL_EPS THEN
        _fYState := _fYState + ((_fLead - _fYState) * (fDtS / (fTlagInit + fDtS)));   // 滞后段一阶离散 / Lag stage, first order
    ELSE
        _fYState := _fLead;                                     // 滞后时间为 0 且 dt 病态：直通 / Degenerate case: pass through
    END_IF
    _fComp := _fYState;                                         // 补偿计算值 / Computed compensation
    fOut   := _fHold + (_fBlend * (_fComp - _fHold));           // 无扰混合输出 / Bumpless blended output
    IF fOut > fOutMax THEN
        fOut   := fOutMax;                                      // 正饱和 / Saturate high
        _bSat  := TRUE;
    ELSIF fOut < -fOutMax THEN
        fOut   := -fOutMax;                                     // 负饱和 / Saturate low
        _bSat  := TRUE;
    END_IF
    _fXPrev := fIn;                                             // 输入快照更新（本拍末） / Input snapshot at body end
END_IF

(* —— 段 6：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_AllState.eFault) THEN
    _eState := E_DL_AllState.eFault;                            // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_AllState.eIdle:
    IF _bFault THEN                                             // 出口 1：组态故障 / Configuration fault
        _eState := E_DL_AllState.eFault;
    ELSIF bEnable THEN                                          // 出口 2：使能到来（无沿也算） / Enable present
        _eState := E_DL_AllState.eRamp;
    END_IF

E_DL_AllState.eRamp:
    IF _bFault THEN                                             // 出口 1：组态故障 / Configuration fault
        _eState := E_DL_AllState.eFault;
    ELSIF (NOT bEnable) THEN                                    // 出口 2：被禁用，回等待相 / Disabled, back to idle
        _eState := E_DL_AllState.eIdle;
    END_IF

E_DL_AllState.eRun:
    IF _bFault THEN                                             // 出口 1：组态故障 / Configuration fault
        _eState := E_DL_AllState.eFault;
    ELSIF NOT bEnable THEN                                      // 出口 2：被禁用，回等待相 / Disabled, back to idle
        _eState := E_DL_AllState.eIdle;
    END_IF

E_DL_AllState.eFault:
    ;                                                           // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _bFault := TRUE;                                            // 非法相位兜底锁存 / Illegal-phase fallback latch
    _eCause := E_DL_AllCause.ePhaseBad;                         // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_AllState.eFault;                            // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 8：出口单点映射（名实双出口，R191） —— *)
fTleadUsed := _fTlead;                                          // 超前时间出口 / Lead time outlet
fTlagUsed  := fTlagInit;                                        // 滞后时间出口（本件不调整滞后） / Lag time outlet, not adapted
fBlend     := _fBlend;                                          // 斜坡出口 / Ramp outlet
bActive    := (_eState = E_DL_AllState.eRun) AND (NOT _bFault); // 全效 = 运行相且无故障 / Fully engaged
bLimited   := _bSat;                                            // 饱和出口 / Saturation outlet
bError     := _bFault OR _bCfgBad;                              // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
IF _bSat AND (NOT _bFault) THEN
    _eCause := E_DL_AllCause.eOutSat;                           // 提示：输出饱和（信息级） / Notice: output saturated
END_IF
eState := _eState;                                              // 状态出口 / State outlet
eCause := _eCause;                                              // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
