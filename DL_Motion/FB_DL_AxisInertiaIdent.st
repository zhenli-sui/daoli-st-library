(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisInertiaIdent
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS）与库内开方内核 FC_DL_SqrtEx，
 *                         零厂商私有库
 * 功能描述 (Function)   : 转动惯量与摩擦转矩在线辨识。在加速段采集 (a, T) 样本对，用最小二乘
 *                         闭式解拟合 T = J·a + Tf，得惯量 J 与摩擦转矩 Tf：
 *                         J = 〔n·ΣaT − Σa·ΣT〕/〔n·Σa² − (Σa)²〕，Tf = 〔ΣT − J·Σa〕/ n。
 *                         采样门限：|fAcc| >= fAccMin 才纳入样本；有效样本数 < nSampleMin 不出结果。
 *                         置信度：残差均方根 fRms 超 fRmsMax 时 bConfident = FALSE——**照出结果但标
 *                         不可信**（不静默丢弃，现场需要看到「拟合出来了但不可信」这个事实）。
 *                         bFreeze 为真时停止更新，fInertiaOut 保持（供调试比对）。
 * 接口     (Interface)  : 输入 fAcc 角加速度、fTorque 转矩、fAccMin 采样门限、nSampleMin 最小
 *                         样本数、fRmsMax 残差均方根上限、bEnable 使能、bFreeze 结果冻结、bReset 复位；
 *                         输出 fInertiaOut 惯量、fFrictionOut 摩擦转矩、fRms 残差均方根、
 *                         bConfident 置信标记、nSampleCount 有效样本数、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 回归分母〔n·Σa² − (Σa)²〕<= DL_FLOAT_EPS 判定样本不可分（如全等
 *                         加速度），置信息级并**保持上次结果**（不清零，避免把「没算出来」错当
 *                         「惯量为 0」）；② 全部累加量用 LREAL 防精度丢失；**本件用累积量闭式解，
 *                         不使用样本环形缓冲**，故无下标越界路径（派单「环缓冲下标先判边界」
 *                         条款以零数组方式结构性满足）；
 *                         ③ 组态闸：fAccMin <= 0.0、nSampleMin = 0、fRmsMax <= 0.0 或任一浮点引脚
 *                         NaN → 故障锁存；④ 输入非有限 → 该样本剔除并计数，不污染累加量；
 *                         ⑤ R_TRIG 一枚段 0 无条件刷新（本件为纯算术拟合，无工艺相计时）；
 *                         ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 回归分母非病态（当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：分母只依赖累加量与样本数，复位后累加量清空
 *                         即重新开始积累，加速度样本一旦分散分母即脱离病态，无恒假因子。
 * 码表     (Codes)      : 16#0004_03B7 故障级：惯量辨识故障总码（组态非法 / 输入非有限累计超限 /
 *                         非法相位），锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0004_04B7 信息级：非故障台账事件（分母病态保持上次结果 / 样本数不足）。
 *                         加码反证（R90）：二者都不改 bError、不改 eCause，且 bConfident 仍可能为真
 *                         （保持的旧结果可能高置信），若不立码则「本轮没算出新结果」不可观测，故立
 *                         一码；二者共用一码的依据是「都只要求留痕」，区分由 nSampleCount 反推。
 *                         码段说明：0004 段故障子带 03xx / 信息子带 04xx，本件取 03B7 / 04B7
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考最小二乘闭式解与运动辨识参数域，零代码行复制；
 *                         t2-4-s7-motion 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 3 · 序号 13）
 *==============================================================================*)

TYPE E_DL_AiiState :
(
    eIdle  := 0,     // 失能或样本不足（无结果） / Idle, disabled or not enough samples
    eRun   := 10,    // 辨识运行 / Identification running
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_AiiCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eNonFinRun  := 2,   // 输入非有限累计超限 / Too many consecutive non-finite inputs
    ePhaseBad   := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisInertiaIdent
VAR_INPUT
    fAcc        : REAL := 0.0;          // 角加速度（或线加速度） [rad/s²] / Angular acceleration [rad/s2]
    fTorque     : REAL := 0.0;          // 实测转矩 [N·m] / Measured torque [N·m]
    fAccMin     : REAL := 5.0;          // 采样门限（|a| 大于该值才纳入），域 > 0.0 [rad/s²] / Sampling threshold, domain > 0.0 [rad/s2]
    nSampleMin  : UDINT := 50;          // 最小有效样本数，域 > 0 [个] / Minimum sample count, domain > 0 [pcs]
    fRmsMax     : REAL := 0.50;         // 残差均方根上限，域 > 0.0 [N·m] / Residual RMS limit, domain > 0.0 [N·m]
    bEnable     : BOOL := TRUE;         // 辨识使能 [-] / Identification enable
    bFreeze     : BOOL := FALSE;        // 结果冻结（停止更新，保持末值） [-] / Freeze results, hold last value
    bReset      : BOOL := FALSE;        // 复位命令，上升沿清故障并使累加量净重装 [-] / Reset clears fault and re-arms accumulators
END_VAR
VAR_OUTPUT
    fInertiaOut  : REAL;                // 辨识惯量（拟合斜率） [kg·m²] / Identified inertia, fitted slope [kg m2]
    fFrictionOut : REAL;                // 辨识摩擦转矩（拟合截距） [N·m] / Identified friction torque, fitted intercept [N·m]
    fRms         : REAL;                // 残差均方根（拟合优度） [N·m] / Residual RMS [N·m]
    bConfident   : BOOL;                // 置信标记（RMS 未超上限） [-] / Confident flag
    nSampleCount : UDINT;               // 当前有效样本数 [个] / Current valid sample count
    eState       : E_DL_AiiState;       // 状态出口，段 6 单点映射 / State outlet
    eCause       : E_DL_AiiCause;       // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError       : BOOL;                // 故障锁存标志 [-] / Fault latch flag
    nErrId       : UDINT;               // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState      : E_DL_AiiState := E_DL_AiiState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause      : E_DL_AiiCause := E_DL_AiiCause.eNone;    // 故障成因锁存（锁存量） / Latched cause
    rtReset      : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge
    _nSamples    : UDINT;               // 样本数（锁存量） [个] / Sample count, latched
    _fSumA       : LREAL;               // Σa（锁存量，LREAL 防精度丢失） [rad/s²] / Sum of acceleration in LREAL
    _fSumT       : LREAL;               // ΣT（锁存量） [N·m] / Sum of torque
    _fSumAA      : LREAL;               // Σa²（锁存量） [rad²/s⁴] / Sum of squared acceleration
    _fSumAT      : LREAL;               // ΣaT（锁存量） [N·m·rad/s²] / Sum of acceleration times torque
    _fSumTT      : LREAL;               // ΣT²（锁存量） [N²·m²] / Sum of squared torque
    _fDen        : LREAL;               // 回归分母 n·Σa² − (Σa)²（当拍量） [rad²/s⁴] / Regression denominator
    _fJ          : LREAL;               // 惯量拟合值（当拍量） [kg·m²] / Fitted inertia
    _fTf         : LREAL;               // 摩擦转矩拟合值（当拍量） [N·m] / Fitted friction torque
    _fSse        : LREAL;               // 残差平方和（当拍量） [N²·m²] / Residual sum of squares
    _fRmsCalc    : LREAL;               // 残差均方根计算值（当拍量） [N·m] / Computed residual RMS
    _fInertiaHold : REAL;               // 惯量保持槽（锁存量，病态时保持） [kg·m²] / Inertia hold slot, latched
    _fFricHold   : REAL;                // 摩擦保持槽（锁存量） [N·m] / Friction hold slot, latched
    _fRmsHold    : REAL;                // RMS 保持槽（锁存量） [N·m] / RMS hold slot, latched
    _bConfHold   : BOOL;                // 置信保持槽（锁存量） [-] / Confidence hold slot
    _nNonFinRun  : UDINT;               // 非有限连续计数（锁存量） [拍] / Consecutive non-finite counter
    _uSqrtErr    : UDINT;               // 开方内核错误码（当拍量） [-] / Sqrt kernel error code
    _bNonFin     : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad     : BOOL;                // 组态非法当拍量 [-] / Illegal configuration
    _bDenBad     : BOOL;                // 分母病态当拍量 [-] / Degenerate denominator
    _bFault      : BOOL;                // 故障锁存位（锁存量） / Latched fault bit
    _uFault      : UDINT;               // 故障码锁存（锁存量） / Latched fault code
    _uInfo       : UDINT;               // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS  : LREAL := 1.0E-6;    // 浮点判零容差（分母与判据统一口径） [无量纲] / Float epsilon for zero tests
    DL_NONFIN_MAX : UDINT := 10;        // 非有限连续拍数上限 [拍] / Consecutive non-finite limit [scan]
END_VAR

(* —— 段 0：去当拍判据派生 + 沿实例无条件周期刷新 —— *)
_bNonFin := (fAcc <> fAcc) OR (fTorque <> fTorque)                                          // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR ((fAcc - fAcc) <> (fAcc - fAcc)) OR ((fTorque - fTorque) <> (fTorque - fTorque));   // Inf 差值自减判 / Inf tests
_bCfgBad := (fAccMin <= 0.0) OR (nSampleMin = 0) OR (fRmsMax <= 0.0)                         // 组态域闸（R151 全覆盖） / Config gate
            OR (fAccMin <> fAccMin) OR (fRmsMax <> fRmsMax);                                 // 参数 NaN 判 / Parameter NaN tests
rtReset(CLK := bReset);                                                                       // 复位沿，每拍必调（R228A） / Reset edge

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo       := 16#0000_0000;      // 信息码每拍重算 / Info recomputed every scan
nSampleCount := _nSamples;         // 样本数镜像（锁存量回放） / Sample count mirror
nErrId       := 16#0000_0000;      // 事件码缺省无事件 / Event code default none
bError       := FALSE;             // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿（含累加量净重装）+ 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_AiiCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    _nSamples := 0;                                                      // 样本累加量净重装 / Re-arm accumulators
    _fSumA := 0.0;
    _fSumT := 0.0;
    _fSumAA := 0.0;
    _fSumAT := 0.0;
    _fSumTT := 0.0;
    _nNonFinRun := 0;                                                    // 非有限计数清空 / Clear non-finite counter
    IF _eState = E_DL_AiiState.eFault THEN
        _eState := E_DL_AiiState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0004_03B7;                                             // 故障级：惯量辨识故障总码 / Fault-level: identification fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_AiiCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：样本采集（门限过滤 + 非有限剔除 + LREAL 累加） —— *)
IF (NOT _bFault) THEN
    IF _bNonFin THEN                                                     // 非有限：剔除且不污染累加量 / Non-finite sample dropped, accumulators untouched
        IF _nNonFinRun < DL_NONFIN_MAX THEN
            _nNonFinRun := _nNonFinRun + 1;
        END_IF
        _uInfo := 16#0004_04B7;                                          // 信息级：该样本剔除留痕 / Info: sample dropped
    ELSE
        _nNonFinRun := 0;                                                // 恢复有限即清连续计数 / Reset counter
        IF ABS(fAcc) >= fAccMin THEN                                     // 门限过滤（容差式） / Threshold filter
            _nSamples := _nSamples + 1;
            _fSumA  := _fSumA  + REAL_TO_LREAL(fAcc);                    // 累加 Σa / Accumulate sum of acceleration
            _fSumT  := _fSumT  + REAL_TO_LREAL(fTorque);                 // 累加 ΣT / Accumulate sum of torque
            _fSumAA := _fSumAA + REAL_TO_LREAL(fAcc) * REAL_TO_LREAL(fAcc);              // 累加 Σa² / Accumulate sum of squared acceleration
            _fSumAT := _fSumAT + REAL_TO_LREAL(fAcc) * REAL_TO_LREAL(fTorque);           // 累加 ΣaT / Accumulate cross sum
            _fSumTT := _fSumTT + REAL_TO_LREAL(fTorque) * REAL_TO_LREAL(fTorque);        // 累加 ΣT² / Accumulate sum of squared torque
        END_IF
    END_IF
END_IF
IF (NOT _bFault) AND (_nNonFinRun >= DL_NONFIN_MAX) THEN                 // 非有限累计超限置故障 / Too many non-finite inputs
    _uFault := 16#0004_03B7;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_AiiCause.eNonFinRun;                                 // 归因：非有限累计超限 / Cause: sustained non-finite
END_IF

(* —— 段 4：最小二乘闭式解（样本够、未冻结、使能时才求解） —— *)
_bDenBad := FALSE;                                                       // 病态标记复位 / Reset degenerate marker
IF (NOT _bFault) AND bEnable AND (NOT bFreeze) AND (_nSamples >= nSampleMin) THEN
    _fDen := REAL_TO_LREAL(UDINT_TO_REAL(_nSamples)) * _fSumAA - _fSumA * _fSumA;   // 回归分母 / Regression denominator
    IF _fDen <= DL_FLOAT_EPS THEN                                        // 分母病态：样本不可分 / Degenerate denominator
        _bDenBad := TRUE;
        _uInfo := 16#0004_04B7;                                          // 信息级：分母病态，保持上次结果 / Info: degenerate, hold last result
    ELSE
        _fJ := (REAL_TO_LREAL(UDINT_TO_REAL(_nSamples)) * _fSumAT - _fSumA * _fSumT) / _fDen;   // 惯量 = 斜率 / Inertia as the slope
        _fTf := (_fSumT - _fJ * _fSumA) / REAL_TO_LREAL(UDINT_TO_REAL(_nSamples));               // 摩擦 = 截距 / Friction as the intercept
        _fSse := _fSumTT - 2.0 * _fJ * _fSumAT - 2.0 * _fTf * _fSumT
                 + _fJ * _fJ * _fSumAA + 2.0 * _fJ * _fTf * _fSumA
                 + REAL_TO_LREAL(UDINT_TO_REAL(_nSamples)) * _fTf * _fTf;                        // 残差平方和 / Residual sum of squares
        IF _fSse < 0.0 THEN                                              // 舍入误差可能给极小负值 / Rounding may make it slightly negative
            _fSse := 0.0;
        END_IF
        _fRmsCalc := FC_DL_SqrtEx(fX := _fSse / REAL_TO_LREAL(UDINT_TO_REAL(_nSamples)), eErr => _uSqrtErr);   // 委托开方内核（R140） / Delegate sqrt kernel
        _fInertiaHold := LREAL_TO_REAL(_fJ);                             // 写入保持槽（经非有限复核见段 5） / Update inertia hold slot
        _fFricHold := LREAL_TO_REAL(_fTf);                               // 写入摩擦保持槽 / Update friction hold slot
        _fRmsHold := LREAL_TO_REAL(_fRmsCalc);                           // 写入 RMS 保持槽 / Update RMS hold slot
        IF _fRmsCalc > REAL_TO_LREAL(fRmsMax) THEN
            _bConfHold := FALSE;                                         // 残差超限：标不可信但照出结果 / Mark unconfident but still publish
        ELSE
            _bConfHold := TRUE;                                          // 置信 / Confident
        END_IF
    END_IF
END_IF
IF (NOT _bFault) AND bEnable AND (NOT bFreeze) AND (_nSamples < nSampleMin) THEN
    _uInfo := 16#0004_04B7;                                              // 信息级：样本不足，不出结果 / Info: not enough samples
END_IF

(* —— 段 5：保持槽非有限复核（非有限绝不写进保持槽，R133） —— *)
IF (_fInertiaHold <> _fInertiaHold) OR (_fFricHold <> _fFricHold) OR (_fRmsHold <> _fRmsHold) THEN
    _fInertiaHold := 0.0;                                                // 非有限保持槽清零 / Zero out non-finite hold slots
    _fFricHold := 0.0;
    _fRmsHold := 0.0;
    _bConfHold := FALSE;                                                 // 置信位撤销 / Revoke confidence
END_IF

(* —— 段 6：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bDenBad) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_AiiCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 6A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_AiiState.eFault) THEN
    _eState := E_DL_AiiState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_AiiState.eIdle:
    IF (_nSamples >= nSampleMin) AND (NOT _bFault) THEN                  // 出口 1：样本够数 / Enough samples
        _eState := E_DL_AiiState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_AiiState.eFault;
    END_IF

E_DL_AiiState.eRun:
    IF _nSamples < nSampleMin THEN                                       // 出口 1：样本被复位清空（前置消失，R98） / Samples re-armed
        _eState := E_DL_AiiState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_AiiState.eFault;
    END_IF

E_DL_AiiState.eFault:
    ;                                                                     // 故障相：仅段 6 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0004_03B7;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_AiiCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_AiiState.eFault;

END_CASE

(* —— 段 8：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF _bFault THEN
    fInertiaOut  := 0.0;                                                 // 故障相惯量输出 0（不外推未知参数） / Zero inertia in fault
    fFrictionOut := 0.0;                                                 // 故障相摩擦输出 0 / Zero friction in fault
    fRms         := 0.0;                                                 // 故障相 RMS 输出 0 / Zero RMS in fault
    bConfident   := FALSE;                                               // 故障相不宣称置信 / No confidence claim in fault
ELSE
    fInertiaOut  := _fInertiaHold;                                       // 惯量出口（保持槽回放） / Inertia outlet from hold slot
    fFrictionOut := _fFricHold;                                          // 摩擦出口 / Friction outlet
    fRms         := _fRmsHold;                                           // RMS 出口 / RMS outlet
    bConfident   := _bConfHold;                                          // 置信出口 / Confidence outlet
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
