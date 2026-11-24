(*
  ==================================================================
  组件名 Component  : FB_DL_FopdtStepIdent
  分类   Category   : DL_Algo
  版本   Version    : 1.0.1
  功能   Purpose    : 阶跃响应 FOPDT（一阶惯性 + 纯延迟）参数辨识，供 PID 整定使用。
                      阶跃窗内「时刻 + 过程量」二元组以环窗缓存，稳定或超时后按
                      时间序遍历样本，两条 clean-room 方法并行求解并在出口二选一：
                      一 两点法：取 28.3% 与 63.2% 两个穿越点，
                         T = 1.5 * (t63 - t28)，L = t63 - T；
                      二 切线法：取最大斜率点切线，
                         T = ΔPV / 最大斜率，L = t_slope - (PV_slope - PV_base) / 带符号斜率
                         （斜率符号取 SIGN(ΔPV)，负向阶跃与两点法同口径）；
                      增益 K = ΔPV / ΔMV 两法共用。
  溯源   Origin     : 阶跃辨识两点法与切线法均为公开控制工程方法；本件为 clean-room
                      实现，仅借鉴来源分类与参数域组织（来源标签 t2-5-modpid 的 PID
                      自整定概念域），未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / REAL 运算，无私有库、无方言转换）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  同拍双窗配比约束（R100）：tSettle 必须小于 tTimeout —— 稳定确认窗短于相超时窗，
                      两窗职责分离：tSettle 判「可以进入评估」，tTimeout 判「辨识失败退出」，
                      任一窗不得兼作另一窗用途；配比反置在组态域闸内直接判故障。
  边界 Boundary     :
                      一 本件只输出辨识参数与有效性，不算 PID 参数、不写调节器（属主边界）；
                      二 环窗遍历一律按时间序（自最旧样本起），禁按数组下标序（R194）；
                      三 采样拍周期由引脚 fSampleS 给出（秒），不读系统时基；
                      四 故障锁存解除路径 = bReset 上升沿 或 bEnable 下降沿，两条均恒可达；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fGainK / fTauS / fDeadS 仅在 bValid 为真拍更新，其余拍保持上一次
                      成功辨识值；非有限中间结果一律不写入出口（出口保持上拍值）；
                      bIdentDone 为单拍脉冲（内部 _bIdentInt 置位、统一出口映射后撤销，
                      R187 两段式）；eCause 各成因独立成员（R190 归因唯一）。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 1 · 序号 2）
    2026-11-20  v1.0.1  R56 返修（7.2）：切线法截距改用带符号斜率 _fSlopeSig（符号取
                        SIGN(_fDeltaPv)，量级守卫仍由 _fSlopeMax > DL_FOPDT_EPS 证明），
                        负向阶跃不再系统性高估死区时间；eDone 相重启分支补清
                        _fPvSlopeMax / _fTSlopeMax（与 eIdle 分支对齐）。
  ==================================================================
*)

TYPE E_DL_FopdtState :
(
    eIdle    := 0,      // 空闲：等待阶跃上升沿 / idle, waiting for the step rising edge
    eRise    := 10,     // 上升：缓存样本并监视稳定 / rising, buffering samples and watching settle
    eEval    := 20,     // 评估：时间序遍历样本算参数 / evaluating, traversing samples in time order
    eDone    := 30,     // 完成：参数已交付并驻留 / done, parameters delivered and held
    eFault   := 90      // 故障：原因锁存 / fault, cause latched
);
END_TYPE

TYPE E_DL_FopdtCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：阈值或采样周期越域 / illegal config, threshold or sample period out of domain
    eMvZero     := 2,   // 阶跃幅度近零，增益不可算 / step amplitude near zero, gain not computable
    eLackResp   := 3,   // 响应不足：总变化未达最小可辨量 / response too small, total change below the floor
    eNoSettle   := 4,   // 超时未稳定 / timeout without settle
    eNoCross    := 5,   // 未捕获穿越点或样本不足 / crossing points missing or too few samples
    eDeadNeg    := 6,   // 纯延迟算出负值，已按零处理（信息级）/ dead time negative and forced to zero, informational
    ePhaseBad   := 7    // 非法相位兜底 / illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_FopdtStepIdent
VAR_INPUT
    bEnable        : BOOL := TRUE;           // 使能，下降沿清状态回空闲 [-] / enable, falling edge clears the state back to idle
    bReset         : BOOL := FALSE;          // 复位上升沿清故障锁存 [-] / reset rising edge clears the fault latch
    bStepStart     : BOOL := FALSE;          // 阶跃施加时刻的上升沿（调用方给出）[-] / rising edge at the step application instant
    fMvStep        : REAL := 10.0;           // 操纵量阶跃幅度（带符号）[工程单位] / manipulated variable step amplitude, signed [engineering unit]
    fMvStepEps     : REAL := 1.0E-3;         // 阶跃幅度可辨下限 [工程单位] / step amplitude recognisable floor [engineering unit]
    fPv            : REAL := 0.0;            // 过程量实测 [工程单位] / measured process variable [engineering unit]
    fSampleS       : REAL := 0.1;            // 采样拍周期 [秒]，域 1E-4..10 / sample period [second], domain 1E-4 to 10
    tTimeout       : TIME := T#300S;         // 上升相超时 [毫秒] / rise phase timeout [millisecond]
    tSettle        : TIME := T#5S;           // 稳定确认时长 [毫秒] / settle confirmation duration [millisecond]
    fSettleBandPct : REAL := 1.0;            // 稳定带，占当前跨度百分比 [百分比] / settle band as a percentage of the current span [percent]
    fMinDeltaPv    : REAL := 0.5;            // 响应最小可辨量 [工程单位] / minimum recognisable response [engineering unit]
    bUseTangent    : BOOL := FALSE;          // 真 = 出口取切线法，假 = 出口取两点法 [-] / true selects the tangent method, false selects the two-point method
    fTauMinS       : REAL := 0.2;            // 时间常数可接受下限 [秒] / acceptable time constant floor [second]
    fTauMaxS       : REAL := 7200.0;         // 时间常数可接受上限 [秒] / acceptable time constant ceiling [second]
    fDeadMaxS      : REAL := 600.0;          // 纯延迟可接受上限 [秒] / acceptable dead time ceiling [second]
END_VAR
VAR_OUTPUT
    fGainK         : REAL := 0.0;            // 辨识增益 K [工程单位比] / identified process gain [engineering unit ratio]
    fTauS          : REAL := 0.0;            // 辨识时间常数 T [秒] / identified time constant [second]
    fDeadS         : REAL := 0.0;            // 辨识纯延迟 L [秒] / identified dead time [second]
    fDeltaPv       : REAL := 0.0;            // 本次阶跃的总过程量变化 [工程单位] / total process change of this step [engineering unit]
    fPvBase        : REAL := 0.0;            // 阶跃前基线过程量 [工程单位] / baseline process variable before the step [engineering unit]
    fPvFinal       : REAL := 0.0;            // 稳定后过程量 [工程单位] / settled process variable [engineering unit]
    fTauTwoPointS  : REAL := 0.0;            // 两点法时间常数 [秒] / two-point method time constant [second]
    fDeadTwoPointS : REAL := 0.0;            // 两点法纯延迟 [秒] / two-point method dead time [second]
    fTauTangentS   : REAL := 0.0;            // 切线法时间常数 [秒] / tangent method time constant [second]
    fDeadTangentS  : REAL := 0.0;            // 切线法纯延迟 [秒] / tangent method dead time [second]
    bValid         : BOOL := FALSE;          // 参数是否可交付 [-] / parameters deliverable flag
    bIdentDone     : BOOL := FALSE;          // 辨识完成单拍脉冲 [-] / identification done single-shot pulse
    eState         : E_DL_FopdtState := E_DL_FopdtState.eIdle; // 相位出口，段尾单点映射 [枚举] / phase outlet, single-point mapped at the tail
    eCause         : E_DL_FopdtCause := E_DL_FopdtCause.eNone; // 成因出口，锁存至复位 [枚举] / cause outlet, latched until reset
    bError         : BOOL := FALSE;          // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtStep         : R_TRIG;                 // 阶跃沿检测，段 0 无条件刷新 / step edge detector, refreshed unconditionally in segment zero
    rtReset        : R_TRIG;                 // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonTimeout     : TON;                    // 上升相超时计时，段 0 无条件刷新 / rise phase timeout timer, refreshed unconditionally in segment zero
    tonSettle      : TON;                    // 稳定确认计时，段 0 无条件刷新 / settle confirmation timer, refreshed unconditionally in segment zero
    _eState        : E_DL_FopdtState := E_DL_FopdtState.eIdle;  // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause        : E_DL_FopdtCause := E_DL_FopdtCause.eNone;  // 内部成因，锁存量 / internal cause, latched quantity
    _bFault        : BOOL := FALSE;          // 故障锁存位 [-] / fault latch bit
    _bValid        : BOOL := FALSE;          // 参数有效内部位，锁存至下次辨识 / internal validity bit, latched until the next identification
    _bIdentInt     : BOOL := FALSE;          // 完成脉冲内部位，统一出口映射 / internal done bit, mapped at the unified outlet
    _bInit         : BOOL := FALSE;          // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bSampleOk     : BOOL := FALSE;          // 本拍样本有效（过程量有限）[-] / this-scan sample valid flag
    _bStoreOk      : BOOL := FALSE;          // 环窗槽位合法可写 [-] / ring slot legal and writable
    _bSpanOk       : BOOL := FALSE;          // 跨度估计可用于稳定带判据 [-] / span estimate usable for the settle band
    _bCfgBad       : BOOL := FALSE;          // 组态非法标志 [-] / illegal configuration flag
    _bCross28      : BOOL := FALSE;          // 已捕获 28.3% 穿越点 [-] / 28.3 percent crossing captured
    _bCross63      : BOOL := FALSE;          // 已捕获 63.2% 穿越点 [-] / 63.2 percent crossing captured
    _bDeadClamped  : BOOL := FALSE;          // 纯延迟负值已按零处理 [-] / negative dead time forced to zero
    _nHead         : INT := 0;               // 环窗最近样本槽位（1 起，回钳 1..N）[槽号] / newest ring slot, one-based, clamped one through N
    _nFill         : INT := 0;               // 环窗已填样本数（0..N）[个] / samples held in the ring [count]
    _nIdx          : INT := 0;               // 环窗下标游标 [槽号] / ring index cursor [slot]
    _nPrev         : INT := 0;               // 时间序前一槽位 [槽号] / previous slot in time order [slot]
    _nGuard        : INT := 0;               // 遍历防死循环守护计数 [次] / traversal guard against runaway loops [count]
    _nK            : INT := 0;               // 时间序遍历序号（1 = 最旧样本）[序号] / time-order ordinal, one is the oldest [ordinal]
    _fDtS          : REAL := 0.1;            // 钳定后的采样拍周期 [秒] / clamped sample period [second]
    _fElapsedS     : REAL := 0.0;            // 上升相已历时 [秒] / elapsed time within the rise phase [second]
    _fPvPrev       : REAL := 0.0;            // 上一拍过程量快照 [工程单位] / previous scan process value snapshot [engineering unit]
    _fPvBase       : REAL := 0.0;            // 基线过程量（时间序最旧样本）[工程单位] / baseline process value from the oldest sample [engineering unit]
    _fPvNow        : REAL := 0.0;            // 本拍样本过程量 [工程单位] / current sample process value [engineering unit]
    _fPvFinal      : REAL := 0.0;            // 稳定后过程量（时间序最新样本）[工程单位] / settled process value from the newest sample [engineering unit]
    _fPvOld        : REAL := 0.0;            // 遍历中的前一有效样本过程量 [工程单位] / previous valid sample during traversal [engineering unit]
    _fDeltaPv      : REAL := 0.0;            // 总过程量变化 [工程单位] / total process change [engineering unit]
    _fSpan         : REAL := 0.0;            // 已观测过程量跨度上确界 [工程单位] / supremum of the observed process span [engineering unit]
    _fSettleAbs    : REAL := 0.0;            // 稳定带绝对量 [工程单位] / absolute settle band [engineering unit]
    _fFrac         : REAL := 0.0;            // 归一化响应分数（0..1）[无量纲] / normalised response fraction [dimensionless]
    _fSlopeNow     : REAL := 0.0;            // 本拍斜率 [工程单位每秒] / slope of this scan [engineering unit per second]
    _fSlopeMax     : REAL := 0.0;            // 最大斜率上确界 [工程单位每秒] / supremum of the slope magnitude [engineering unit per second]
    _fSlopeSig     : REAL := 0.0;            // 带符号最大斜率，符号取 SIGN(ΔPV) [工程单位每秒] / signed maximum slope carrying the delta PV sign [engineering unit per second]
    _fSlopeLoc     : REAL := 0.0;            // 相邻样本斜率 [工程单位每秒] / slope between adjacent samples [engineering unit per second]
    _fDtLoc        : REAL := 0.0;            // 相邻样本时差 [秒] / time difference between adjacent samples [second]
    _fT28          : REAL := 0.0;            // 28.3% 穿越时刻 [秒] / 28.3 percent crossing instant [second]
    _fT63          : REAL := 0.0;            // 63.2% 穿越时刻 [秒] / 63.2 percent crossing instant [second]
    _fTSlopeMax    : REAL := 0.0;            // 最大斜率出现时刻 [秒] / instant of the maximum slope [second]
    _fPvSlopeMax   : REAL := 0.0;            // 最大斜率处过程量 [工程单位] / process value at the maximum slope [engineering unit]
    _fTauTwo       : REAL := 0.0;            // 两点法时间常数计算值 [秒] / two-point time constant, computed value [second]
    _fDeadTwo      : REAL := 0.0;            // 两点法纯延迟计算值 [秒] / two-point dead time, computed value [second]
    _fTauTan       : REAL := 0.0;            // 切线法时间常数计算值 [秒] / tangent time constant, computed value [second]
    _fDeadTan      : REAL := 0.0;            // 切线法纯延迟计算值 [秒] / tangent dead time, computed value [second]
    _fTauOut       : REAL := 0.0;            // 出口选用时间常数 [秒] / selected outlet time constant [second]
    _fDeadOut      : REAL := 0.0;            // 出口选用纯延迟 [秒] / selected outlet dead time [second]
    _fGain         : REAL := 0.0;            // 增益计算值 [工程单位比] / computed gain [engineering unit ratio]
    _fMvDen        : REAL := 0.0;            // 增益分母（阶跃幅度）暂存 [工程单位] / gain denominator held in a local [engineering unit]
    _fGainK        : REAL := 0.0;            // 出口保持：增益 [工程单位比] / outlet holder for the gain [engineering unit ratio]
    _fTauS         : REAL := 0.0;            // 出口保持：时间常数 [秒] / outlet holder for the time constant [second]
    _fDeadS        : REAL := 0.0;            // 出口保持：纯延迟 [秒] / outlet holder for the dead time [second]
    _fDeltaPvOut   : REAL := 0.0;            // 出口保持：总变化量 [工程单位] / outlet holder for the total change [engineering unit]
    _fPvBaseOut    : REAL := 0.0;            // 出口保持：基线过程量 [工程单位] / outlet holder for the baseline value [engineering unit]
    _fPvFinalOut   : REAL := 0.0;            // 出口保持：稳定点过程量 [工程单位] / outlet holder for the settled value [engineering unit]
    _fTauTwoOut    : REAL := 0.0;            // 出口保持：两点法时间常数 [秒] / outlet holder for the two-point time constant [second]
    _fDeadTwoOut   : REAL := 0.0;            // 出口保持：两点法纯延迟 [秒] / outlet holder for the two-point dead time [second]
    _fTauTanOut    : REAL := 0.0;            // 出口保持：切线法时间常数 [秒] / outlet holder for the tangent time constant [second]
    _fDeadTanOut   : REAL := 0.0;            // 出口保持：切线法纯延迟 [秒] / outlet holder for the tangent dead time [second]
    _afPvV         : ARRAY[1..512] OF REAL := [512(0.0)]; // 环窗过程量缓存 [工程单位] / ring buffer of process values [engineering unit]
    _afPvT         : ARRAY[1..512] OF REAL := [512(0.0)]; // 环窗时刻缓存，与过程量同槽同步写入 [秒] / ring buffer of instants, lockstep with the values [second]
END_VAR
VAR CONSTANT
    DL_FOPDT_MAX    : INT := 512;            // 环窗容量与槽位回钳上界 [个] / ring capacity and slot clamp upper bound [count]
    DL_FOPDT_SMIN   : REAL := 1.0E-4;        // 采样周期下限，防除零 [秒] / sample period floor against division by zero [second]
    DL_FOPDT_SMAX   : REAL := 10.0;          // 采样周期上限，防时基错配 [秒] / sample period ceiling against a mismatched time base [second]
    DL_FOPDT_DTMIN  : REAL := 1.0E-6;        // 相邻样本时差下限，斜率除子 [秒] / adjacent sample time difference floor for the slope divisor [second]
    DL_FOPDT_FRAC28 : REAL := 0.283;         // 两点法第一穿越点 [无量纲] / two-point first crossing fraction [dimensionless]
    DL_FOPDT_FRAC63 : REAL := 0.632;         // 两点法第二穿越点 [无量纲] / two-point second crossing fraction [dimensionless]
    DL_FOPDT_TAUCOEF: REAL := 1.5;           // 两点法时间常数系数 [无量纲] / two-point time constant coefficient [dimensionless]
    DL_FOPDT_EPS    : REAL := 1.0E-9;        // 斜率与分数类除子下限 [无量纲] / floor for slope and fraction divisors [dimensionless]
    DL_FOPDT_GAINMAX: REAL := 1.0E9;         // 增益量级上限，防量纲错配 [工程单位比] / gain magnitude ceiling against a dimension mismatch [engineering unit ratio]
    DL_FOPDT_GUARD  : INT := 1024;           // 遍历守护上限，两倍容量 [次] / traversal guard, twice the capacity [count]
    DL_FOPDT_MINPTS : INT := 4;              // 参与辨识的最少样本数 [个] / minimum sample count for identification [count]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸 / segment 0, unconditional refresh of timers and edge detectors with state gates on IN only
rtStep(CLK := bStepStart); // 阶跃沿检测无条件刷新 / unconditional refresh of the step edge detector
rtReset(CLK := bReset); // 复位沿检测无条件刷新 / unconditional refresh of the reset edge detector
tonTimeout(IN := (_eState = E_DL_FopdtState.eRise) AND (NOT _bFault), PT := tTimeout); // 上升相超时，IN 串相位闸与故障闸 / rise phase timeout, IN carries the phase gate and the fault gate
tonSettle(IN := (_eState = E_DL_FopdtState.eRise) AND _bSampleOk AND _bSpanOk AND (ABS(fPv - _fPvPrev) <= _fSettleAbs), PT := tSettle); // 稳定确认，IN 串相位闸与稳定带判据 / settle confirmation with the phase gate and the settle band criterion on IN

// 段 1｜首扫初始化（R310）：学习量与环窗从确定起点开始 / segment 1, first scan initialisation so that learning quantities and the ring start known
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_FopdtState.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_FopdtCause.eNone; // 成因清零 / clear the cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _bValid := FALSE; // 有效位清零 / clear the validity bit
    _nHead := 0; // 环窗无样本 / the ring holds no sample
    _nFill := 0; // 环窗计数清零 / clear the ring count
    _fSpan := 0.0; // 跨度估计清零 / clear the span estimate
END_IF

// 段 2｜复位沿作用域逐项声明：清锁存 / 迁相位 / 清累计量 / segment 2, reset edge scope declared item by item
IF rtReset.Q OR (NOT bEnable) THEN // 复位沿或失能 / reset edge or disabled
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eCause := E_DL_FopdtCause.eNone; // 作用域一：清成因 / scope one, clear the cause
    _bIdentInt := FALSE; // 作用域一：清完成脉冲内部位 / scope one, clear the internal done bit
    _eState := E_DL_FopdtState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _nHead := 0; // 作用域三：清环窗槽位 / scope three, clear the ring slot cursor
    _nFill := 0; // 作用域三：清环窗计数 / scope three, clear the ring count
    _fSpan := 0.0; // 作用域三：清跨度估计 / scope three, clear the span estimate
    _fElapsedS := 0.0; // 作用域三：清历时 / scope three, clear the elapsed time
END_IF

// 段 3｜组态域闸（R151）：参与判据换算的每个引脚逐项闸，缺一即判据静默失效 / segment 3, configuration domain gate over every pin used by the criteria
_bCfgBad := FALSE; // 组态非法标志预置假 / preset the illegal configuration flag to false
IF (fSampleS <> fSampleS) THEN // 采样周期 NaN 自反判 / NaN detection on the sample period
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fSampleS < DL_FOPDT_SMIN) OR (fSampleS > DL_FOPDT_SMAX) THEN // 采样周期越域 / sample period out of domain
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fMvStep <> fMvStep) OR ((fMvStep - fMvStep) <> (fMvStep - fMvStep)) THEN // 阶跃幅度非有限 / step amplitude non-finite
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fMvStepEps <= 0.0) OR (fMvStepEps <> fMvStepEps) THEN // 幅度可辨下限非正或非有限 / amplitude floor not positive or non-finite
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fMinDeltaPv <= 0.0) OR (fMinDeltaPv <> fMinDeltaPv) THEN // 最小可辨量非正或非有限 / response floor not positive or non-finite
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fSettleBandPct <= 0.0) OR (fSettleBandPct >= 100.0) OR (fSettleBandPct <> fSettleBandPct) THEN // 稳定带百分比越域 / settle band percentage out of domain
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fTauMinS <= 0.0) OR (fTauMaxS <= fTauMinS) OR (fTauMaxS <> fTauMaxS) THEN // 时间常数上下限自相矛盾 / time constant bounds contradict each other
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (fDeadMaxS < 0.0) OR (fDeadMaxS <> fDeadMaxS) THEN // 纯延迟上限为负或非有限 / dead time ceiling negative or non-finite
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF (tTimeout <= T#0S) OR (tSettle <= T#0S) THEN // 时间引脚非正 / time pins not positive
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF tSettle >= tTimeout THEN // 稳定窗不短于相超时窗，违反双窗配比（R100）/ the settle window is not shorter than the phase timeout
    _bCfgBad := TRUE; // 判组态非法 / illegal configuration
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _eCause := E_DL_FopdtCause.eCfgIllegal; // 成因记组态非法 / record the illegal configuration cause
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _bValid := FALSE; // 参数不可交付 / parameters not deliverable
    _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 4｜本拍量预置（单拍标志限域，不含快照与环窗保持量）/ segment 4, per-scan presets limited to single-shot flags
_fDtS := fSampleS; // 采样周期直通 / sample period passes through
IF _fDtS < DL_FOPDT_SMIN THEN // 周期过小 / period too small
    _fDtS := DL_FOPDT_SMIN; // 抬到下限，防时基除零 / raised against a zero time base
ELSIF _fDtS > DL_FOPDT_SMAX THEN // 周期过大 / period too large
    _fDtS := DL_FOPDT_SMAX; // 压到上限 / pressed to the ceiling
END_IF
_bSampleOk := (fPv = fPv) AND ((fPv - fPv) = (fPv - fPv)); // 过程量有限性闸，NaN 用自反、无穷用差值自减 / process value finiteness gate
_fPvNow := fPv; // 本拍样本默认取实测 / the current sample defaults to the measurement
IF NOT _bSampleOk THEN // 非有限拍 / non-finite scan
    _fPvNow := _fPvPrev; // 非有限不穿透：改取上拍快照 / nothing non-finite passes, the previous snapshot is used
END_IF
_fSettleAbs := _fSpan * fSettleBandPct / 100.0; // 稳定带绝对量，除子为常量 100.0 / absolute settle band, the divisor is the literal constant one hundred
_bSpanOk := _fSpan > 0.0; // 跨度估计可用性 / span estimate availability

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, phase machine with an ELSE fallback for illegal phases
CASE _eState OF
E_DL_FopdtState.eIdle: // 空闲相：等阶跃上升沿 / idle phase, waiting for the step rising edge
    IF rtStep.Q THEN // 阶跃沿到达 / the step edge arrived
        _nHead := 0; // 环窗槽位清零 / clear the ring slot cursor
        _nFill := 0; // 环窗计数清零 / clear the ring count
        _fSpan := 0.0; // 跨度估计清零 / clear the span estimate
        _fElapsedS := 0.0; // 历时清零 / clear the elapsed time
        _fSlopeMax := 0.0; // 最大斜率清零 / clear the maximum slope
        _fPvSlopeMax := 0.0; // 最大斜率处过程量清零 / clear the value at the maximum slope
        _fTSlopeMax := 0.0; // 最大斜率时刻清零 / clear the instant of the maximum slope
        _bCross28 := FALSE; // 穿越标志清零 / clear the crossing flag
        _bCross63 := FALSE; // 穿越标志清零 / clear the crossing flag
        _fPvPrev := fPv; // 基线快照取当拍实测 / the baseline snapshot takes the current measurement
        _fPvBase := fPv; // 基线过程量取当拍实测 / the baseline process value takes the current measurement
        _eState := E_DL_FopdtState.eRise; // 迁上升相 / migrate to the rise phase
    END_IF

E_DL_FopdtState.eRise: // 上升相：缓存样本、跟踪斜率与跨度 / rise phase, buffering samples and tracking slope and span
    _fElapsedS := _fElapsedS + _fDtS; // 累计历时 / accumulate the elapsed time
    _bStoreOk := FALSE; // 写入许可预置假 / preset the write permit to false
    IF _nFill < DL_FOPDT_MAX THEN // 环窗未满 / the ring is not yet full
        _nHead := _nHead + 1; // 槽位前移，天然落在 1..N / advance the slot, naturally inside one through N
        _nFill := _nFill + 1; // 计数递增 / increment the count
        _bStoreOk := TRUE; // 允许写入 / writing permitted
    ELSE // 环窗已满 / the ring is full
        _nHead := _nHead + 1; // 槽位前移 / advance the slot
        IF _nHead > DL_FOPDT_MAX THEN // 越过上界 / past the upper bound
            _nHead := 1; // 回钳到一号槽（环窗回钳口径）/ clamp back to slot one
        END_IF
        _bStoreOk := TRUE; // 允许写入 / writing permitted
    END_IF
    IF _bStoreOk THEN // 槽位合法 / slot is legal
        _afPvV[_nHead] := _fPvNow; // 过程量入环窗 / store the process value
        _afPvT[_nHead] := _fElapsedS; // 时刻同步入同槽 / store the instant into the same slot
    END_IF
    IF ABS(_fPvNow - _fPvBase) > _fSpan THEN // 跨度取绝对偏差上确界 / the span takes the supremum of absolute deviation
        _fSpan := ABS(_fPvNow - _fPvBase); // 更新跨度 / refresh the span
    END_IF
    _fSlopeNow := ABS(_fPvNow - _fPvPrev) / _fDtS; // 本拍斜率绝对值，除子已钳定大于零 / absolute slope of this scan, divisor proven positive
    IF _fSlopeNow > _fSlopeMax THEN // 斜率上确界跟踪 / supremum slope tracking
        _fSlopeMax := _fSlopeNow; // 更新最大斜率 / refresh the maximum slope
        _fPvSlopeMax := _fPvNow; // 记录该点过程量 / record the value at that point
        _fTSlopeMax := _fElapsedS; // 记录该点时刻 / record the instant of that point
    END_IF
    _fPvPrev := _fPvNow; // 快照推进 / advance the snapshot
    IF tonSettle.Q OR tonTimeout.Q THEN // 稳定达成或超时 / settled or timed out
        _eState := E_DL_FopdtState.eEval; // 迁评估相 / migrate to the evaluation phase
    END_IF

E_DL_FopdtState.eEval: // 评估相：按时间序遍历环窗，两法并行求解 / evaluation phase, traversal in time order with both methods solved
    _nK := _nFill; // 参与判定的样本数 / samples participating in the verdict
    IF _nK > DL_FOPDT_MAX THEN // 防御：计数不得越容 / defence, the count must not exceed capacity
        _nK := DL_FOPDT_MAX; // 回钳到容量 / clamp to the capacity
    END_IF
    IF _nK < DL_FOPDT_MINPTS THEN // 样本不足 / too few samples
        _eCause := E_DL_FopdtCause.eNoCross; // 成因记样本不足缺穿越点 / record the missing crossing cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _bValid := FALSE; // 参数不可交付 / parameters not deliverable
        _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
    ELSE
        _nIdx := _nHead - _nFill + 1; // 时间序最旧槽位 / the oldest slot in time order
        IF _nIdx < 1 THEN // 越过下界 / below the lower bound
            _nIdx := _nIdx + DL_FOPDT_MAX; // 单次回绕补齐（时间序回钳）/ a single wrap restores the time order
        END_IF
        _fPvBase := _afPvV[_nIdx]; // 基线取时间序最旧样本 / the baseline takes the oldest sample
        _fPvOld := _fPvBase; // 遍历起点过程量 / traversal start value
        _fPvFinal := _afPvV[_nHead]; // 稳定点取时间序最新样本 / the settled value takes the newest sample
        _fDeltaPv := _fPvFinal - _fPvBase; // 总变化量 / total change
        IF ABS(_fDeltaPv) <= fMinDeltaPv THEN // 响应不足 / response too small
            _eCause := E_DL_FopdtCause.eLackResp; // 成因记响应不足 / record the insufficient response cause
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _bValid := FALSE; // 参数不可交付 / parameters not deliverable
            _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
        ELSIF ABS(fMvStep) <= fMvStepEps THEN // 阶跃幅度近零 / step amplitude near zero
            _eCause := E_DL_FopdtCause.eMvZero; // 成因记幅度近零 / record the near-zero amplitude cause
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _bValid := FALSE; // 参数不可交付 / parameters not deliverable
            _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
        ELSE
            _bCross28 := FALSE; // 穿越标志复位 / clear the crossing flag
            _bCross63 := FALSE; // 穿越标志复位 / clear the crossing flag
            _nGuard := 0; // 遍历守护计数清零 / reset the traversal guard
            _nK := 1; // 自最旧样本起按时间序遍历（R194）/ traverse from the oldest sample in time order
            WHILE (_nK <= _nFill) AND (_nGuard < DL_FOPDT_GUARD) DO // 双重守护：样本数与计数上限 / dual guard on the sample count and the counter cap
                _nGuard := _nGuard + 1; // 守护计数递增 / increment the guard
                _nIdx := _nHead - _nFill + _nK; // 时间序槽位 / the slot in time order
                IF _nIdx < 1 THEN // 越过下界 / below the lower bound
                    _nIdx := _nIdx + DL_FOPDT_MAX; // 单次回绕 / single wrap
                END_IF
                _fFrac := (_afPvV[_nIdx] - _fPvBase) / _fDeltaPv; // 归一化响应分数，除子绝对值已证超可辨量 / normalised fraction, divisor proven above the floor
                IF (NOT _bCross28) AND (_fFrac >= DL_FOPDT_FRAC28) THEN // 首次越过 28.3% / first crossing of 28.3 percent
                    _fT28 := _afPvT[_nIdx]; // 记录穿越时刻 / record the crossing instant
                    _bCross28 := TRUE; // 置穿越标志 / raise the crossing flag
                END_IF
                IF (NOT _bCross63) AND (_fFrac >= DL_FOPDT_FRAC63) THEN // 首次越过 63.2% / first crossing of 63.2 percent
                    _fT63 := _afPvT[_nIdx]; // 记录穿越时刻 / record the crossing instant
                    _bCross63 := TRUE; // 置穿越标志 / raise the crossing flag
                END_IF
                IF _nK > 1 THEN // 自第二个样本起可算斜率 / slopes exist from the second sample onward
                    _nPrev := _nIdx - 1; // 前一槽位 / the previous slot
                    IF _nPrev < 1 THEN // 越过下界 / below the lower bound
                        _nPrev := _nPrev + DL_FOPDT_MAX; // 单次回绕 / single wrap
                    END_IF
                    _fDtLoc := _afPvT[_nIdx] - _afPvT[_nPrev]; // 相邻样本时差 / adjacent sample time difference
                    IF _fDtLoc > DL_FOPDT_DTMIN THEN // 时差可用 / the difference is usable
                        _fSlopeLoc := ABS((_afPvV[_nIdx] - _fPvOld) / _fDtLoc); // 局部斜率绝对值 / local absolute slope
                        IF _fSlopeLoc > _fSlopeMax THEN // 斜率上确界 / slope supremum
                            _fSlopeMax := _fSlopeLoc; // 更新最大斜率 / refresh the maximum slope
                            _fPvSlopeMax := _afPvV[_nIdx]; // 记录该点过程量 / record the value at that point
                            _fTSlopeMax := _afPvT[_nIdx]; // 记录该点时刻 / record the instant of that point
                        END_IF
                    END_IF
                END_IF
                _fPvOld := _afPvV[_nIdx]; // 推进前一有效样本 / advance the previous valid sample
                _nK := _nK + 1; // 序号递增 / increment the ordinal
            END_WHILE
            IF (NOT _bCross28) OR (NOT _bCross63) THEN // 缺穿越点 / a crossing is missing
                _eCause := E_DL_FopdtCause.eNoCross; // 成因记缺穿越点 / record the missing crossing cause
                _bFault := TRUE; // 置故障锁存 / raise the fault latch
                _bValid := FALSE; // 参数不可交付 / parameters not deliverable
                _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
            ELSIF (_fT63 - _fT28) < DL_FOPDT_DTMIN THEN // 两穿越点重合，时间常数不可辨 / the crossings coincide and the time constant is unresolvable
                _eCause := E_DL_FopdtCause.eNoCross; // 成因记穿越点不可辨 / record the unresolvable crossing cause
                _bFault := TRUE; // 置故障锁存 / raise the fault latch
                _bValid := FALSE; // 参数不可交付 / parameters not deliverable
                _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
            ELSE
                _fTauTwo := DL_FOPDT_TAUCOEF * (_fT63 - _fT28); // 两点法时间常数 / two-point time constant
                _fDeadTwo := _fT63 - _fTauTwo; // 两点法纯延迟 / two-point dead time
                _bDeadClamped := FALSE; // 钳位标志复位 / clear the clamp flag
                IF _fDeadTwo < 0.0 THEN // 延迟负值不可能 / a negative dead time is impossible
                    _fDeadTwo := 0.0; // 按零处理 / forced to zero
                    _bDeadClamped := TRUE; // 置钳位标志 / raise the clamp flag
                END_IF
                IF _fSlopeMax > DL_FOPDT_EPS THEN // 斜率可用 / the slope is usable
                    _fSlopeSig := _fSlopeMax * SIGN(_fDeltaPv); // 带符号斜率：SIGN(ΔPV) ∈ {-1, 1}（ΔPV 已证 |·| > fMinDeltaPv > 0），量级仍由 _fSlopeMax 超阈证明 / signed slope, the sign of delta PV is proven nonzero and the magnitude stays proven by the slope floor
                    _fTauTan := _fDeltaPv / _fSlopeSig; // 切线法时间常数，除子量级已证超阈且符号与分子同源 / tangent time constant, the divisor magnitude is proven and its sign matches the numerator
                    _fDeadTan := _fTSlopeMax - (_fPvSlopeMax - _fPvBase) / _fSlopeSig; // 切线法纯延迟：截距用带符号斜率，负向阶跃不再系统性高估（R56 返修）/ tangent dead time, the intercept uses the signed slope so a negative step no longer overestimates
                    IF _fDeadTan < 0.0 THEN // 延迟负值不可能 / a negative dead time is impossible
                        _fDeadTan := 0.0; // 按零处理 / forced to zero
                        _bDeadClamped := TRUE; // 置钳位标志 / raise the clamp flag
                    END_IF
                ELSE // 斜率不可用 / the slope is unusable
                    _fTauTan := _fTauTwo; // 以两点法兜底 / fall back to the two-point result
                    _fDeadTan := _fDeadTwo; // 纯延迟同款兜底 / the dead time falls back the same way
                END_IF
                _fMvDen := fMvStep; // 增益分母落局部量 / the gain denominator lands in a local
                IF ABS(_fMvDen) <= fMvStepEps THEN // 分母近零 / denominator near zero
                    _eCause := E_DL_FopdtCause.eMvZero; // 成因记幅度近零 / record the near-zero amplitude cause
                    _bFault := TRUE; // 置故障锁存 / raise the fault latch
                    _bValid := FALSE; // 参数不可交付 / parameters not deliverable
                    _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
                ELSE
                    _fGain := _fDeltaPv / _fMvDen; // 增益 = ΔPV / ΔMV / gain equals delta PV over delta MV
                    IF ABS(_fGain) > DL_FOPDT_GAINMAX THEN // 增益量级越界 / gain magnitude out of range
                        _eCause := E_DL_FopdtCause.eCfgIllegal; // 成因记组态非法（量纲错配）/ record illegal configuration, dimension mismatch
                        _bFault := TRUE; // 置故障锁存 / raise the fault latch
                        _bValid := FALSE; // 参数不可交付 / parameters not deliverable
                        _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
                    ELSE
                        _fTauOut := _fTauTwo; // 出口时间常数默认取两点法 / the outlet time constant defaults to the two-point result
                        _fDeadOut := _fDeadTwo; // 出口纯延迟默认取两点法 / the outlet dead time defaults to the two-point result
                        IF bUseTangent THEN // 切线法优先 / the tangent method takes precedence
                            _fTauOut := _fTauTan; // 取切线法时间常数 / take the tangent time constant
                            _fDeadOut := _fDeadTan; // 取切线法纯延迟 / take the tangent dead time
                        END_IF
                        IF (_fTauOut < fTauMinS) OR (_fTauOut > fTauMaxS) THEN // 时间常数越接受域 / time constant outside the acceptable domain
                            _eCause := E_DL_FopdtCause.eCfgIllegal; // 成因记组态非法（接受域不匹配）/ record illegal configuration, bound mismatch
                            _bFault := TRUE; // 置故障锁存 / raise the fault latch
                            _bValid := FALSE; // 参数不可交付 / parameters not deliverable
                            _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
                        ELSIF _fDeadOut > fDeadMaxS THEN // 纯延迟越接受域 / dead time outside the acceptable domain
                            _eCause := E_DL_FopdtCause.eCfgIllegal; // 成因记组态非法（接受域不匹配）/ record illegal configuration, bound mismatch
                            _bFault := TRUE; // 置故障锁存 / raise the fault latch
                            _bValid := FALSE; // 参数不可交付 / parameters not deliverable
                            _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
                        ELSE
                            _fGainK := _fGain; // 增益落定 / settle the gain
                            _fTauS := _fTauOut; // 时间常数落定 / settle the time constant
                            _fDeadS := _fDeadOut; // 纯延迟落定 / settle the dead time
                            _fDeltaPvOut := _fDeltaPv; // 总变化量落定 / settle the total change
                            _fTauTwoOut := _fTauTwo; // 两点法时间常数落定 / settle the two-point time constant
                            _fDeadTwoOut := _fDeadTwo; // 两点法纯延迟落定 / settle the two-point dead time
                            _fTauTanOut := _fTauTan; // 切线法时间常数落定 / settle the tangent time constant
                            _fDeadTanOut := _fDeadTan; // 切线法纯延迟落定 / settle the tangent dead time
                            _fPvBaseOut := _fPvBase; // 基线落定 / settle the baseline
                            _fPvFinalOut := _fPvFinal; // 稳定点落定 / settle the settled value
                            _bValid := TRUE; // 参数可交付（锁存至下一次辨识）/ parameters deliverable until the next identification
                            _bIdentInt := TRUE; // 完成脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit, mapped at the unified outlet
                            IF _bDeadClamped THEN // 延迟负值已钳零 / the dead time was clamped to zero
                                _eCause := E_DL_FopdtCause.eDeadNeg; // 信息级成因，不置故障标志 / informational cause without raising the fault flag
                            END_IF
                            _eState := E_DL_FopdtState.eDone; // 迁完成相 / migrate to the done phase
                        END_IF
                    END_IF
                END_IF
            END_IF
        END_IF
    END_IF

E_DL_FopdtState.eDone: // 完成相：参数驻留，仅接受复位或新阶跃 / done phase, parameters held, only reset or a new step accepted
    IF rtStep.Q THEN // 新阶跃沿 / a new step edge
        _nHead := 0; // 环窗槽位清零 / clear the ring slot cursor
        _nFill := 0; // 环窗计数清零 / clear the ring count
        _fSpan := 0.0; // 跨度估计清零 / clear the span estimate
        _fElapsedS := 0.0; // 历时清零 / clear the elapsed time
        _fSlopeMax := 0.0; // 最大斜率清零 / clear the maximum slope
        _fPvSlopeMax := 0.0; // 最大斜率处过程量清零（R56 返修补齐，与空闲相分支对齐）/ clear the value at the maximum slope, aligned with the idle branch
        _fTSlopeMax := 0.0; // 最大斜率时刻清零（R56 返修补齐，与空闲相分支对齐）/ clear the instant of the maximum slope, aligned with the idle branch
        _bCross28 := FALSE; // 穿越标志清零 / clear the crossing flag
        _bCross63 := FALSE; // 穿越标志清零 / clear the crossing flag
        _fPvPrev := fPv; // 新基线快照 / take a fresh baseline snapshot
        _fPvBase := fPv; // 新基线过程量 / take a fresh baseline process value
        _eState := E_DL_FopdtState.eRise; // 迁上升相 / migrate to the rise phase
    END_IF

E_DL_FopdtState.eFault: // 故障相：原因锁存，等待复位沿 / fault phase, the cause is latched until the reset edge
    _bValid := FALSE; // 故障拍参数不可交付，数值保持上拍 / parameters are not deliverable and the values hold the last scan

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _eCause := E_DL_FopdtCause.ePhaseBad; // 成因记非法相位 / record the illegal phase cause
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _bValid := FALSE; // 参数不可交付 / parameters not deliverable
    _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜超时判据：仅上升相内判，IN 已带相位闸（R212）/ segment 6, timeout verdict inside the rise phase only, IN already carries the phase gate
IF (_eState = E_DL_FopdtState.eRise) AND tonTimeout.Q AND (NOT _bFault) THEN // 超时且未锁存 / timed out and not yet latched
    _eCause := E_DL_FopdtCause.eNoSettle; // 成因记超时未稳定 / record the timeout without settle cause
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _bValid := FALSE; // 参数不可交付 / parameters not deliverable
    _eState := E_DL_FopdtState.eFault; // 迁故障相 / migrate to the fault phase
END_IF

// 段 7｜统一出口：相位映射、单拍脉冲映射、故障锁存与有效位同源 / segment 7, unified outlet for phase mapping, single-shot pulse and matched fault outlets
eState := _eState; // 相位出口单点映射 / single-point phase outlet mapping
eCause := _eCause; // 成因出口单点映射（锁存量）/ single-point cause outlet mapping of the latched value
bError := _bFault; // 故障标志与锁存位同源赋值 / the fault flag shares the latch source
bIdentDone := _bIdentInt; // 完成脉冲映射本拍值 / map the done bit for this scan
_bIdentInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
bValid := _bValid AND (NOT _bFault); // 有效出口受故障锁存否决（挂状态量，非单拍标志）/ the valid outlet is vetoed by the fault latch, a state quantity
fGainK := _fGainK; // 增益出口 / gain outlet
fTauS := _fTauS; // 时间常数出口 / time constant outlet
fDeadS := _fDeadS; // 纯延迟出口 / dead time outlet
fDeltaPv := _fDeltaPvOut; // 总变化量出口 / total change outlet
fPvBase := _fPvBaseOut; // 基线出口 / baseline outlet
fPvFinal := _fPvFinalOut; // 稳定点出口 / settled value outlet
fTauTwoPointS := _fTauTwoOut; // 两点法时间常数出口 / two-point time constant outlet
fDeadTwoPointS := _fDeadTwoOut; // 两点法纯延迟出口 / two-point dead time outlet
fTauTangentS := _fTauTanOut; // 切线法时间常数出口 / tangent time constant outlet
fDeadTangentS := _fDeadTanOut; // 切线法纯延迟出口 / tangent dead time outlet
END_FUNCTION_BLOCK
