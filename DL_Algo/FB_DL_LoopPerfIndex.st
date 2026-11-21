(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoopPerfIndex
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS / MIN / MAX）与库内
 *                         TIME 换算内核 FC_DL_TimeToLrealSec，零厂商私有库
 * 功能描述 (Function)   : 回路性能指标采集与评价（只出指标与建议档，**不做自整定**）。
 *                         阶跃发生后开窗采集：IAE（绝对误差积分）、ISE（误差平方积分）、
 *                         超调百分比、衰减比（相邻两峰比）、过零振荡计数（带去抖）。
 *                         相序：eIdle（非自动/未使能）→ eCollect（阶跃后窗口采集）→
 *                         eEval（一次算出全部指标）→ eDone（保持到撤自动）。窗口到点由
 *                         TON 单点置位（wording：窗口到时由 tonWindow.Q 单拍事件驱动）。
 * 分工声明 (Scope)      : 自整定属主为 `FB_DL_RelayAutoTune` / `FB_DL_AutoTuneRelay`；
 *                         本件**只测量、只给建议档**（偏快/合适/偏慢/振荡），不修改任何 PID 参数、
 *                         不输出激励信号。若上层把 eTuneHint 直接写进 PID 即为越权使用。
 * 接口     (Interface)  : 输入 fSp 设定、fPv 测量、bInAuto 自动态、bEnable 使能、fStepMin
 *                         阶跃判别门限、tWindow 采集窗时长、tTaskPeriod 调用任务周期、fSettleBandPct
 *                         入窗判据带、fOscHystPct 过零去抖带、bReset 复位；输出 fIae / fIse /
 *                         fOvershootPct / fDecayRatio / nOscCount 五指标、eTuneHint 建议档、
 *                         bEvalDone 评价完成单拍、eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 阶跃判据用容差（|ΔfSp| > fStepMin），浮点禁判等；
 *                         ② 窗口到时由 TON 单点置位；能量积分用 LREAL 中间量，防 REAL 逐拍
 *                         累积溢出（REAL 只有 24 位有效位，1e7 拍后即饱和）；
 *                         ③ 测量非有限 → 该拍剔除并计数，连续超过 5 拍置故障（单拍毛刺不断线）；
 *                         ④ 组态闸：fStepMin <= 0.0、tWindow <= T#0S、tTaskPeriod <= T#0S、
 *                         fSettleBandPct <= 0.0、fOscHystPct <= 0.0 或任一浮点引脚 NaN → 故障锁存；
 *                         ⑤ TON 一枚 + R_TRIG 一枚段 0 无条件周期刷新；
 *                         ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 遗留假设 (Assumption) : 【R95 三句声明】① 代理值 = 引脚 tTaskPeriod（调用方任务周期），用于把
 *                         逐拍误差换算成秒；② 覆盖范围 = 任务周期 1 ms ~ 1000 ms 的周期任务与
 *                         自由运行任务的等效周期；③ 覆盖不到的区间（事件任务、抖动 > 50% 的
 *                         超载任务）由调用方负责：这类工况下积分量只作相互比较用，不可与
 *                         示波器实测 IAE 绝对值对拍。该假设已挂入编译验证债。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 非自动态（NOT bInAuto）。
 *                         自证可满足（终审两式 1）：bInAuto 是外部引脚，切手动即可满足；
 *                         该因子**必须是析取语义里的必要条件之一而非恒假组合**——若写成
 *                         「复位沿 ∧ 自动态」则自动态下复位永远清不掉故障（R152 反例），
 *                         本件按「非自动态」实现，解除可达。
 * 码表     (Codes)      : 16#0002_03B2 故障级：回路性能指标故障总码（组态非法 / 测量持续非有限 /
 *                         非法相位），锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0002_04B5 信息级：本次评价完成（指标已定稿，附建议档）。
 *                         加码反证（R90）：评价完成与「窗口未开」在五指标数值上不可区分
 *                         （未开窗时指标全为上次值或 0），且 bEvalDone 只是单拍位不进台账，
 *                         故须立一码；信息码只在 eEval 迁移那一拍发出。
 *                         码段说明：0002 段故障子带 03xx / 信息子带 04xx，本件取 03B2 / 04B5
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 编译门槛 (Build Gate) : 本件委托 FC_DL_TimeToLrealSec（内部转调平台内建 TIME_TO_LREAL），
 *                         交付门槛：须在 CODESYS / TwinCAT 3 / InoProShop 三平台各编译验证一次。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考公开回路性能指标定义与参数域，零代码行复制；
 *                         t2-5-modpid 参数域族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 2 · 序号 8）
 *==============================================================================*)

TYPE E_DL_LpiState :
(
    eIdle    := 0,     // 非自动或未使能，等待阶跃 / Idle, awaiting a setpoint step
    eCollect := 10,    // 窗口采集 / Collecting inside the window
    eEval    := 20,    // 一次求解全部指标 / Evaluating all indices once
    eDone    := 50,    // 评价完成保持 / Done, result held
    eFault   := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_LpiCause :
(
    eNone        := 0,   // 无故障成因 / No cause
    eCfgIllegal  := 1,   // 组态非法 / Illegal configuration
    eNonFinRun   := 2,   // 测量连续非有限 / Measurement non-finite too long
    ePhaseBad    := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

TYPE E_DL_LpiHint :
(
    eSuitable   := 0,    // 合适：超调与衰减比均在线内 / Suitable, overshoot and decay ratio within band
    eTooFast    := 10,   // 偏快：超调偏大或衰减比偏大 / Too fast, overshoot or decay ratio high
    eTooSlow    := 20,   // 偏慢：超调过小且响应迟滞 / Too slow, overshoot too small
    eOscillating := 30   // 振荡：过零次数多或衰减比接近 1 / Oscillating, many crossings or decay ratio near one
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoopPerfIndex
VAR_INPUT
    fSp           : REAL := 0.0;        // 设定值 [工程单位] / Setpoint [unit]
    fPv           : REAL := 0.0;        // 测量值 [工程单位] / Process value [unit]
    bInAuto       : BOOL := FALSE;      // 回路在自动态（采集前置条件） [-] / Loop in automatic mode, precondition for collection
    bEnable       : BOOL := TRUE;       // 指标采集使能 [-] / Index collection enable
    fStepMin      : REAL := 1.0;        // 阶跃判别门限，域 > 0.0 [工程单位] / Step detection threshold, domain > 0.0 [unit]
    tWindow       : TIME := T#30S;      // 采集窗时长，域 > T#0S [ms] / Collection window duration, domain > T#0S [ms]
    tTaskPeriod   : TIME := T#10MS;     // 调用任务周期（代理值，见头注释遗留假设），域 > T#0S [ms] / Task period proxy, domain > T#0S [ms]
    fSettleBandPct: REAL := 5.0;        // 入窗判据带（相对阶跃量百分比），域 > 0.0 [%] / Settling band relative to step, domain > 0.0 [%]
    fOscHystPct   : REAL := 1.0;        // 过零去抖带（相对阶跃量百分比），域 > 0.0 [%] / Zero-crossing debounce band, domain > 0.0 [%]
    bReset        : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    fIae          : REAL;               // 绝对误差积分 [工程单位·s] / Integral of absolute error [unit s]
    fIse          : REAL;               // 误差平方积分 [工程单位²·s] / Integral of squared error [unit2 s]
    fOvershootPct : REAL;               // 超调百分比 [%] / Overshoot percentage [%]
    fDecayRatio   : REAL;               // 衰减比（相邻两峰比），0~1 越好 [p.u.] / Decay ratio of adjacent peaks [p.u.]
    nOscCount     : INT;                // 过零振荡计数（已去抖） [次] / Zero-crossing oscillation count, debounced
    eTuneHint     : E_DL_LpiHint;       // 整定建议档（只建议不整定） [-] / Tuning hint, advisory only
    bEvalDone     : BOOL;               // 评价完成单拍位 [-] / Single-scan evaluation done flag
    eState        : E_DL_LpiState;      // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_LpiCause;      // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;              // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_LpiState := E_DL_LpiState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_LpiCause := E_DL_LpiCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonWindow     : TON;                // 采集窗计时，段 0 无条件调用 / Collection window timer
    rtReset       : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge
    _fTsSec       : LREAL;              // 任务周期秒数（当拍量） [s] / Task period in seconds
    _uConvErr     : UDINT;              // 时间换算内核错误码（当拍量） [-] / Time-conversion kernel error code
    _bConvErr     : BOOL;               // 时间换算内核故障位（当拍量） [-] / Time-conversion kernel fault flag
    _bConvValid   : BOOL;               // 时间换算内核有效位（当拍量） [-] / Time-conversion kernel valid flag
    _fIaeAcc      : LREAL;              // IAE 累加器（LREAL 防溢出，锁存量） [工程单位·s] / IAE accumulator in LREAL, latched
    _fIseAcc      : LREAL;              // ISE 累加器（LREAL 防溢出，锁存量） [工程单位²·s] / ISE accumulator in LREAL, latched
    _fErr         : REAL;               // 本拍误差 [工程单位] / Error this scan
    _fStepAmp     : REAL;               // 本次阶跃幅值（带符号） [工程单位] / Step amplitude with sign
    _fPvPeak      : REAL;               // 峰值跟踪（锁存量，入窗后开始累积） [工程单位] / Peak tracking, latched, armed after entering band
    _bBandArmed   : BOOL;               // 峰值累积武装位（首次入窗后置位，锁存量） [-] / Peak accumulation armed after first band entry
    _fPeakLast    : REAL;               // 最近一次过零前峰值偏差（锁存量） [工程单位] / Latest pre-crossing peak deviation
    _fPeakPrev    : REAL;               // 上一次过零前峰值偏差（锁存量） [工程单位] / Previous pre-crossing peak deviation
    _fCrossRef    : REAL;               // 过零参考电平（锁存量） [工程单位] / Crossing reference level, latched
    _bCrossSign   : BOOL;               // 上个去抖后误差符号（锁存量） [-] / Debounced error sign, latched
    _nOscAcc      : INT;                // 振荡累计（锁存量） [次] / Oscillation count accumulator, latched
    _nNonFinRun   : INT;                // 非有限连续计数（锁存量） [拍] / Consecutive non-finite scans, latched
    _fSpPrev      : REAL;               // 上拍设定快照（锁存量） [工程单位] / Previous-scan setpoint snapshot
    _fRatios      : REAL;               // 衰减比中间量 [p.u.] / Decay ratio intermediate
    _bNonFin      : BOOL;               // 本拍测量非有限 [-] / Non-finite measurement this scan
    _bCfgBad      : BOOL;               // 组态非法当拍量 [-] / Illegal configuration
    _bStep        : BOOL;               // 阶跃发生当拍量 [-] / Step detected this scan
    _bFault       : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;              // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS  : REAL := 1.0E-6;     // 浮点判零容差（除子统一口径） [无量纲] / Float epsilon for zero tests
    DL_NONFIN_MAX : INT := 5;           // 非有限连续拍数上限（超限置故障） [拍] / Consecutive non-finite limit [scan]
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_fTsSec := FC_DL_TimeToLrealSec(tIn := tTaskPeriod, eErr => _uConvErr, bError => _bConvErr, bValid => _bConvValid);   // 委托时间换算内核取秒数（R140 委托优先） / Delegate to time kernel for seconds
_bNonFin  := (fSp <> fSp) OR (fPv <> fPv);                                                      // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
_bCfgBad  := (fStepMin <= 0.0) OR (tWindow <= T#0S) OR (tTaskPeriod <= T#0S)                    // 组态域闸（R151 全覆盖） / Config gate
             OR (fSettleBandPct <= 0.0) OR (fOscHystPct <= 0.0)                                 // 判据带正域闸 / Band gates
             OR (fStepMin <> fStepMin) OR (fSettleBandPct <> fSettleBandPct)                     // 参数 NaN 判 / Parameter NaN tests
             OR (fOscHystPct <> fOscHystPct) OR (_uConvErr <> 16#0000_0000);                     // 换算错误并入组态闸 / Conversion error folded into config gate
_bStep := ABS(fSp - _fSpPrev) > fStepMin;                                                        // 阶跃判据（容差式，禁判等） / Step criterion, tolerance-based
rtReset(CLK := bReset);                                                                          // 复位沿，每拍必调（R228A） / Reset edge
tonWindow(IN := (_eState = E_DL_LpiState.eCollect), PT := tWindow);                              // 采集窗计时，IN 由相位派生 / Window timer, IN from phase

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
_uInfo      := 16#0000_0000;       // 信息码每拍重算 / Info recomputed every scan
bEvalDone   := FALSE;              // 完成单拍位每拍预清，唯一分支置位（R44 范式） / Done flag preset
nErrId      := 16#0000_0000;       // 事件码缺省无事件 / Event code default none
bError      := FALSE;              // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 连续非有限计数 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_LpiCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_LpiState.eFault THEN
        _eState := E_DL_LpiState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0002_03B2;                                             // 故障级：回路性能指标故障总码 / Fault-level: index fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_LpiCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF _bNonFin THEN                                                         // 测量非有限：该拍剔除并计数 / Non-finite measurement, drop and count
    IF _nNonFinRun < DL_NONFIN_MAX THEN
        _nNonFinRun := _nNonFinRun + 1;
    END_IF
ELSE
    _nNonFinRun := 0;                                                    // 恢复有限即清连续计数 / Reset counter on finite value
END_IF
IF (NOT _bFault) AND (_nNonFinRun >= DL_NONFIN_MAX) THEN                 // 连续越限置故障 / Consecutive overrun
    _uFault := 16#0002_03B2;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_LpiCause.eNonFinRun;                                 // 归因：测量持续非有限 / Cause: sustained non-finite
END_IF

(* —— 段 3：指标采集（仅 eCollect 相且测量有限时累加） —— *)
IF (_eState = E_DL_LpiState.eCollect) AND (NOT _bNonFin) AND (NOT _bFault) THEN
    _fErr := fSp - fPv;                                                  // 本拍误差 / Error this scan
    _fIaeAcc := _fIaeAcc + ABS(_fErr) * _fTsSec;                         // IAE 累加（LREAL） / IAE accumulation
    _fIseAcc := _fIseAcc + _fErr * _fErr * _fTsSec;                      // ISE 累加（LREAL） / ISE accumulation
    IF (NOT _bBandArmed) AND (ABS(_fErr) <= (ABS(_fStepAmp) * fSettleBandPct * 0.01)) THEN   // 首次入窗才武装峰值累积（R144） / Arm peak accumulation on first band entry
        _bBandArmed := TRUE;
        _fPvPeak := fSp;                                                 // 峰值初值取设定量而非回读量（R144） / Peak seeded from setpoint, not from PV
    END_IF
    IF _bBandArmed THEN
        IF _fStepAmp > 0.0 THEN
            IF fPv > _fPvPeak THEN
                _fPvPeak := fPv;                                         // 上行阶跃：跟踪最高测量 / Upward step peak tracking
            END_IF
        ELSE
            IF fPv < _fPvPeak THEN
                _fPvPeak := fPv;                                         // 下行阶跃：跟踪最低测量 / Downward step peak tracking
            END_IF
        END_IF
    END_IF
    IF ABS(_fErr) > (ABS(_fStepAmp) * fOscHystPct * 0.01) THEN           // 去抖：误差需超出滞环带才更新符号 / Debounce before sign update
        IF _bCrossSign AND (_fErr < 0.0) THEN                            // 正 → 负过零 / Positive to negative crossing
            _fPeakPrev := _fPeakLast;                                    // 峰值队列后移 / Shift peak queue
            _fPeakLast := ABS(_fCrossRef);
            _nOscAcc := _nOscAcc + 1;                                    // 振荡计数递增 / Oscillation count increment
            _bCrossSign := FALSE;
        ELSIF (NOT _bCrossSign) AND (_fErr > 0.0) THEN                   // 负 → 正过零 / Negative to positive crossing
            _fPeakPrev := _fPeakLast;
            _fPeakLast := ABS(_fCrossRef);
            _nOscAcc := _nOscAcc + 1;
            _bCrossSign := TRUE;
        END_IF
        _fCrossRef := _fErr;                                             // 过零参考电平更新 / Update crossing reference
    END_IF
END_IF

(* —— 段 4：阶跃检测（进相前置，同时清采集量） —— *)
IF (NOT _bFault) AND bEnable AND bInAuto AND _bStep AND (_eState <> E_DL_LpiState.eCollect) THEN
    _fStepAmp := fSp - _fSpPrev;                                         // 阶跃幅值（带符号） / Step amplitude with sign
    _fIaeAcc := 0.0;                                                     // 采集量唯一重置点 / Sole reset point for accumulators
    _fIseAcc := 0.0;
    _fPvPeak := fSp;                                                     // 峰值初值取设定量 / Peak seeded from setpoint
    _bBandArmed := FALSE;                                                // 峰值累积重新武装 / Re-arm peak accumulation
    _fPeakLast := 0.0;                                                   // 峰值队列清空 / Clear peak queue
    _fPeakPrev := 0.0;
    _fCrossRef := 0.0;
    _bCrossSign := FALSE;
    _nOscAcc := 0;                                                       // 振荡计数清零 / Clear oscillation count
    _eState := E_DL_LpiState.eCollect;                                   // 进采集相 / Enter collection phase
END_IF
_fSpPrev := fSp;                                                         // 设定快照（主体末更新） / Setpoint snapshot at body end

(* —— 段 5：故障解除式（R240 全当拍量；非自动态为可达必要条件） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT bInAuto) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_LpiCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_LpiState.eFault) THEN
    _eState := E_DL_LpiState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_LpiState.eIdle:
    IF _bFault THEN                                                      // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_LpiState.eFault;
    ELSIF (NOT bInAuto) OR (NOT bEnable) THEN                            // 出口 2：前置不满足，明确驻留（不落 ELSE 兜底） / Precondition unmet, stay idle explicitly
        _eState := E_DL_LpiState.eIdle;
    END_IF
    (* 进相路径：段 4 阶跃检测命中时置 eCollect（进相前置与采集量重置同处一段） / Phase entry handled in segment 4 *)

E_DL_LpiState.eCollect:
    IF tonWindow.Q THEN                                                  // 出口 1：窗口到点（TON 单拍事件） / Window elapsed
        _eState := E_DL_LpiState.eEval;
    ELSIF (NOT bInAuto) OR (NOT bEnable) THEN                            // 出口 2：前置条件消失（R98 双出口） / Precondition gone
        _eState := E_DL_LpiState.eIdle;
    END_IF

E_DL_LpiState.eEval:
    fIae := LREAL_TO_REAL(_fIaeAcc);                                     // 指标定稿：IAE / Final IAE
    fIse := LREAL_TO_REAL(_fIseAcc);                                     // 指标定稿：ISE / Final ISE
    IF ABS(_fStepAmp) > DL_FLOAT_EPS THEN                                // 除零前置判 / Divide-by-zero guard
        IF _fStepAmp > 0.0 THEN
            fOvershootPct := ((_fPvPeak - fSp) / ABS(_fStepAmp)) * 100.0;   // 上行超调百分比 / Upward overshoot percentage
        ELSE
            fOvershootPct := ((fSp - _fPvPeak) / ABS(_fStepAmp)) * 100.0;   // 下行超调百分比 / Downward overshoot percentage
        END_IF
        IF fOvershootPct < 0.0 THEN
            fOvershootPct := 0.0;                                        // 无超调不报负值 / No negative overshoot
        END_IF
    ELSE
        fOvershootPct := 0.0;                                            // 阶跃量退化，超调不可算 / Degenerate step, overshoot unavailable
    END_IF
    IF _fPeakLast > DL_FLOAT_EPS THEN                                    // 除零前置判 / Divide-by-zero guard
        _fRatios := _fPeakPrev / _fPeakLast;                             // 相邻峰比 / Adjacent peak ratio
        IF _fRatios > 1.0 THEN
            fDecayRatio := 1.0;                                          // 上侧钳位 / Upper clamp
        ELSIF _fRatios < 0.0 THEN
            fDecayRatio := 0.0;                                          // 下侧钳位 / Lower clamp
        ELSE
            fDecayRatio := _fRatios;
        END_IF
    ELSE
        fDecayRatio := 0.0;                                              // 峰值不足，比值不可算 / Not enough peaks
    END_IF
    nOscCount := _nOscAcc;                                               // 振荡计数定稿 / Final oscillation count
    IF (_nOscAcc >= 4) OR (fDecayRatio > 0.60) THEN                      // 判据 1：振荡 / Criterion 1, oscillating
        eTuneHint := E_DL_LpiHint.eOscillating;
    ELSIF fOvershootPct > 20.0 THEN                                      // 判据 2：偏快 / Criterion 2, too fast
        eTuneHint := E_DL_LpiHint.eTooFast;
    ELSIF (fOvershootPct < 5.0) AND (fIae > (ABS(_fStepAmp) * DL_FLOAT_EPS)) THEN   // 判据 3：偏慢 / Criterion 3, too slow
        eTuneHint := E_DL_LpiHint.eTooSlow;
    ELSE
        eTuneHint := E_DL_LpiHint.eSuitable;                             // 默认合适 / Default suitable
    END_IF
    _uInfo := 16#0002_04B5;                                              // 信息级：本次评价完成 / Info: evaluation completed
    _eState := E_DL_LpiState.eDone;                                      // 进完成相 / Enter done phase

E_DL_LpiState.eDone:
    bEvalDone := TRUE;                                                   // 完成相保持完成位（映射到出口） / Done flag held in done phase
    IF (NOT bInAuto) OR (NOT bEnable) THEN                               // 出口 1：前置消失回空闲 / Precondition gone
        _eState := E_DL_LpiState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_LpiState.eFault;
    END_IF

E_DL_LpiState.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0002_03B2;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_LpiCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_LpiState.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF _bFault THEN
    bEvalDone := FALSE;                                                  // 故障相不宣称完成 / No completion claim in fault
    eTuneHint := E_DL_LpiHint.eSuitable;                                 // 故障相建议档归中性档（不外推整定建议） / Neutral hint in fault
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
