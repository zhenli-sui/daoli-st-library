(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ThermalRampPredict
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS / MIN / MAX）与库内时间换算内核
 *                         FC_DL_TimeToLrealSec / FC_DL_LrealSecToTime，零厂商私有库
 * 功能描述 (Function)   : 一阶热模型预测与前馈。模型 dT/dt = 〔u·K − (T − Tamb)〕/ tau，本件不驱 u，
 *                         而以「满功率模型斜率」作参考，用实测斜率在线修正时间常数 tau：
 *                         ① tRemain：据当前温度、目标温度与实测斜率外推到目标所需剩余时间；
 *                         ② fFfBias：进入目标前 fLeadBand 带内按接近程度线性加大「减功率量」，
 *                         抑制热惯性造成的超调（前馈偏移，非闭环）；
 *                         ③ tau 在线修正：实测斜率与模型斜率偏差持续超阈值时按 ±5% 微调，
 *                         并钳在〔tTauMin, tTauMax〕，防单次扰动把模型带偏。
 * 分工声明 (Scope)      : 与 `FB_DL_DryingOvenZone` / `FB_DL_CvdTempRamp`（分区控温与温度曲线
 *                         执行）分工 —— 本件**只出预测与前馈偏置**，不闭环、不持曲线、不下发
 *                         加热指令；曲线执行与闭环属主为上列两件。
 * 接口     (Interface)  : 输入 fTempC 当前温度、fTargetC 目标温度、fAmbC 环境温度、fGainK 稳态
 *                         增益、tTau 时间常数、tTauMin / tTauMax 修正上下限、fLeadBand 前馈起始带、
 *                         fFfBiasMax 前馈偏置上限、fSlopeDevMax 斜率偏差阈值、tTaskPeriod 任务周期、
 *                         bEnable 使能、bReset 复位；输出 tRemain 剩余时间（无趋势时为哨兵）、
 *                         bNoTrend 无趋势标志、fFfBias 前馈减功率量、fTauUsed 当前使用的时间常数、
 *                         eState / eCause / bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：tTau <= T#0S、tTauMin <= T#0S、tTauMax <= tTauMin、fGainK <= 0.0、
 *                         fLeadBand <= 0.0、fFfBiasMax <= 0.0、fSlopeDevMax < 0.0、tTaskPeriod <= T#0S
 *                         或任一浮点引脚 NaN → 故障锁存（每个参与判据的引脚都在闸内，R151）；
 *                         ② tRemain 计算防除零：当实测斜率绝对值 <= DL_SLOPE_EPS 时**不返回 T#0S**
 *                         （T#0S 会被上层读成「马上就到」），而返回哨兵 DL_TIME_INF 并置 bNoTrend；
 *                         ③ 前馈偏置双侧钳位〔0.0, fFfBiasMax〕，禁单侧钳位；
 *                         ④ 非有限输入 → 故障闸，输出侧 tRemain 哨兵、fFfBias 0（安全侧）；
 *                         ⑤ R_TRIG 一枚段 0 无条件周期刷新；⑥ 故障相迁出唯一路径 = bReset 上升沿；
 *                         ⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 遗留假设 (Assumption) : 【R95 三句声明】① 代理值 = 引脚 tTaskPeriod，用于把逐拍温差换算成 °C/s；
 *                         ② 覆盖范围 = 任务周期 10 ms ~ 2 s 的周期任务；③ 覆盖不到的区间
 *                         （< 10 ms 的高速任务或超载抖动任务）由调用方负责：此时斜率噪声偏大，
 *                         tau 修正应经 bEnable 关断，仅使用 fFfBias 前馈。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 非无趋势（NOT bNoTrend，当拍量）。
 *                         自证可满足（终审两式 1）：bNoTrend 由当拍斜率派生，温度一旦真实变化
 *                         斜率即非零，标志必落假；解除式不含计时器输出与锁存量比较，无恒假因子。
 * 码表     (Codes)      : 16#0002_03B3 故障级：热模型预测故障总码（组态非法 / 输入非有限 / 非法
 *                         相位），锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0002_04B6 信息级：无趋势（斜率近似为 0，剩余时间输出哨兵）。
 *                         加码反证（R90）：无趋势时 tRemain 是哨兵常量、fFfBias 仍有效，若只靠
 *                         「tRemain = 86400 s」判断，上层无法区分「真的还要一天」与「算不出来」，
 *                         故须立一码（bNoTrend 只是布尔位，不进报警台账）。
 *                         码段说明：0002 段故障子带 03xx / 信息子带 04xx，本件取 03B3 / 04B6
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 编译门槛 (Build Gate) : 本件委托 FC_DL_TimeToLrealSec 与 FC_DL_LrealSecToTime（内部转调平台
 *                         内建 TIME_TO_LREAL / LREAL_TO_TIME），交付门槛：须在 CODESYS / TwinCAT 3 /
 *                         InoProShop 三平台各编译验证一次。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考一阶热模型与时间常数在线修正参数域，
 *                         零代码行复制；t2-1-lgf 技术子族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 2 · 序号 9）
 *==============================================================================*)

TYPE E_DL_TrpState :
(
    eIdle  := 0,     // 失能待使能 / Idle, disabled
    eRun   := 10,    // 预测运行 / Predicting in run
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_TrpCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eNonFinite  := 2,   // 输入非有限 / Non-finite input
    ePhaseBad   := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ThermalRampPredict
VAR_INPUT
    fTempC        : REAL := 25.0;       // 当前温度 [°C] / Current temperature [degC]
    fTargetC      : REAL := 80.0;       // 目标温度 [°C] / Target temperature [degC]
    fAmbC         : REAL := 25.0;       // 环境温度 [°C] / Ambient temperature [degC]
    fGainK        : REAL := 55.0;       // 稳态增益（满功率温升上界），域 > 0.0 [°C] / Steady-state gain, domain > 0.0 [degC]
    tTau          : TIME := T#120S;     // 时间常数初值，域 > T#0S [ms] / Initial time constant, domain > T#0S [ms]
    tTauMin       : TIME := T#20S;      // 修正下限，域 > T#0S 且 < tTauMax [ms] / Correction lower bound [ms]
    tTauMax       : TIME := T#900S;     // 修正上限，域 > tTauMin [ms] / Correction upper bound [ms]
    fLeadBand     : REAL := 10.0;       // 前馈起始带（距目标多近开始减功率），域 > 0.0 [°C] / Lead band, domain > 0.0 [degC]
    fFfBiasMax    : REAL := 60.0;       // 前馈减功率量上限，域 > 0.0 [%] / Feed-forward bias ceiling, domain > 0.0 [%]
    fSlopeDevMax  : REAL := 0.05;       // 斜率偏差阈值（相对值），域 >= 0.0 [p.u.] / Slope deviation threshold [p.u.]
    tTaskPeriod   : TIME := T#100MS;    // 调用任务周期（代理值，见头注释遗留假设），域 > T#0S [ms] / Task period proxy [ms]
    bEnable       : BOOL := TRUE;       // 预测使能 [-] / Prediction enable
    bReset        : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    tRemain       : TIME;               // 剩余时间（无趋势时输出哨兵 24 h） [ms] / Remaining time, sentinel 24 h when no trend [ms]
    bNoTrend      : BOOL;               // 无趋势标志（斜率近似 0） [-] / No-trend flag
    fFfBias       : REAL;               // 前馈减功率量（双侧钳位后） [%] / Feed-forward power reduction, clamped [%]
    fTauUsed      : REAL;               // 当前使用的时间常数（在线修正后） [s] / Time constant in use after correction [s]
    eState        : E_DL_TrpState;      // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_TrpCause;      // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;              // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_TrpState := E_DL_TrpState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_TrpCause := E_DL_TrpCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    rtReset       : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge
    _fTsSec       : LREAL;              // 任务周期秒数（当拍量） [s] / Task period in seconds
    _fTauSec      : LREAL;              // 时间常数秒数（当拍量，取自修正后的 tTau） [s] / Time constant in seconds
    _fTempPrev    : REAL;               // 上拍温度快照（锁存量） [°C] / Previous-scan temperature snapshot
    _fSlopeMeas   : LREAL;              // 实测斜率（当拍量） [°C/s] / Measured slope [degC/s]
    _fSlopeModel  : LREAL;              // 满功率模型斜率（当拍量） [°C/s] / Full-power model slope [degC/s]
    _fDeltaT      : REAL;               // 目标 − 当前温差 [°C] / Target minus current temperature [degC]
    _fRemSec      : LREAL;              // 剩余时间秒数（转换前） [s] / Remaining seconds before conversion
    _fTauUsedSec  : LREAL;              // 在线修正后的时间常数（锁存量） [s] / Corrected time constant, latched
    _nDevRun      : INT;                // 斜率偏差持续计数（锁存量） [拍] / Slope deviation persistence counter, latched
    _uConvErrT    : UDINT;              // 周期换算错误码（当拍量） [-] / Period conversion error code
    _uConvErrU    : UDINT;              // 时间常数换算错误码（当拍量） [-] / Tau conversion error code
    _uConvErrR    : UDINT;              // 剩余时间换算错误码（当拍量） [-] / Remaining-time conversion error code
    _bConvErrT    : BOOL;               // 周期换算故障位（当拍量） [-] / Period conversion fault flag
    _bConvErrU    : BOOL;               // 时间常数换算故障位（当拍量） [-] / Tau conversion fault flag
    _bConvErrR    : BOOL;               // 剩余时间换算故障位（当拍量） [-] / Remaining-time conversion fault flag
    _bConvValidT  : BOOL;               // 周期换算有效位（当拍量） [-] / Period conversion valid flag
    _bConvValidU  : BOOL;               // 时间常数换算有效位（当拍量） [-] / Tau conversion valid flag
    _bConvValidR  : BOOL;               // 剩余时间换算有效位（当拍量） [-] / Remaining-time conversion valid flag
    _bInit        : BOOL;               // 首拍初始化完成位（锁存量） [-] / First-scan init done
    _bNonFin      : BOOL;               // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad      : BOOL;               // 组态非法当拍量 [-] / Illegal configuration
    _bFault       : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;              // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS  : LREAL := 1.0E-6;    // 浮点判零容差 [无量纲] / Float epsilon for zero tests
    DL_SLOPE_EPS  : LREAL := 1.0E-4;    // 斜率判零容差（低于此判无趋势） [°C/s] / Slope epsilon, below means no trend [degC/s]
    DL_TIME_INF   : LREAL := 86400.0;   // 「无趋势」哨兵秒数（24 h，远离任何真实剩余时间） [s] / No-trend sentinel seconds, 24 h [s]
    DL_TAU_STEP   : LREAL := 1.05;      // 时间常数单次修正倍率 [-] / Time constant correction factor per adjustment
    DL_DEV_MAX    : INT := 10;          // 斜率偏差持续拍数门限 [拍] / Slope deviation persistence limit [scan]
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件周期刷新 —— *)
_fTsSec := FC_DL_TimeToLrealSec(tIn := tTaskPeriod, eErr => _uConvErrT, bError => _bConvErrT, bValid => _bConvValidT);   // 周期换算（R140 委托） / Period conversion
_fTauSec := FC_DL_TimeToLrealSec(tIn := tTau, eErr => _uConvErrU, bError => _bConvErrU, bValid => _bConvValidU);         // 时间常数换算 / Tau conversion
_bNonFin := (fTempC <> fTempC) OR (fTargetC <> fTargetC) OR (fAmbC <> fAmbC) OR (fGainK <> fGainK)    // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fLeadBand <> fLeadBand) OR (fFfBiasMax <> fFfBiasMax) OR (fSlopeDevMax <> fSlopeDevMax); // 前馈参数 NaN 判 / Feed-forward parameter NaN tests
_bCfgBad := (tTau <= T#0S) OR (tTauMin <= T#0S) OR (tTauMax <= tTauMin) OR (tTaskPeriod <= T#0S)     // 时间类组态闸 / Time config gates
            OR (fGainK <= 0.0) OR (fLeadBand <= 0.0) OR (fFfBiasMax <= 0.0) OR (fSlopeDevMax < 0.0)   // 浮点域闸（R151 全覆盖） / Float domain gates
            OR (_uConvErrT <> 16#0000_0000) OR (_uConvErrU <> 16#0000_0000);                          // 换算错误并入闸 / Conversion errors folded in
rtReset(CLK := bReset);                                                                              // 复位沿，每拍必调（R228A） / Reset edge

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
_uInfo   := 16#0000_0000;          // 信息码每拍重算 / Info recomputed every scan
bNoTrend := FALSE;                 // 无趋势标志每拍预清 / No-trend flag preset
nErrId   := 16#0000_0000;          // 事件码缺省无事件 / Event code default none
bError   := FALSE;                 // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset
fFfBias  := 0.0;                   // 前馈偏置缺省 0（安全侧：不减功率） / Bias default 0, safe side

(* —— 段 2：复位沿 + 组态域闸 + 非有限闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_TrpCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_TrpState.eFault THEN
        _eState := E_DL_TrpState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0002_03B3;                                             // 故障级：热模型预测故障总码 / Fault-level: prediction fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_TrpCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 输入非有限 / Non-finite input
    _uFault := 16#0002_03B3;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_TrpCause.eNonFinite;                                 // 归因：非有限 / Cause: non-finite
END_IF

(* —— 段 3：时间常数初始化（首拍取初值并钳在修正域内） —— *)
IF NOT _bInit THEN
    IF _fTauSec < FC_DL_TimeToLrealSec(tIn := tTauMin) THEN              // 初值低于下限即钳入域内 / Clamp initial value into domain
        _fTauUsedSec := FC_DL_TimeToLrealSec(tIn := tTauMin);
    ELSIF _fTauSec > FC_DL_TimeToLrealSec(tIn := tTauMax) THEN
        _fTauUsedSec := FC_DL_TimeToLrealSec(tIn := tTauMax);
    ELSE
        _fTauUsedSec := _fTauSec;
    END_IF
    _fTempPrev := fTempC;                                                // 温度快照初始化 / Initialize temperature snapshot
    _bInit := TRUE;                                                      // 初始化完成 / Init done
END_IF

(* —— 段 4：斜率测量、模型斜率与时间常数在线修正（仅无故障且使能） —— *)
IF (NOT _bFault) AND bEnable THEN
    IF _fTsSec > DL_FLOAT_EPS THEN                                       // 除零前置判 / Divide-by-zero guard
        _fSlopeMeas := REAL_TO_LREAL(fTempC - _fTempPrev) / _fTsSec;      // 实测斜率 [°C/s] / Measured slope
    ELSE
        _fSlopeMeas := 0.0;                                              // 周期退化时置 0（组态闸已拦，防御纵深） / Degenerate period
    END_IF
    IF _fTauUsedSec > DL_FLOAT_EPS THEN                                  // 除零前置判 / Divide-by-zero guard
        _fSlopeModel := REAL_TO_LREAL(fGainK - (fTempC - fAmbC)) / _fTauUsedSec;   // 满功率模型斜率 / Full-power model slope
    ELSE
        _fSlopeModel := 0.0;                                             // 退化兜底 / Degenerate guard
    END_IF
    IF ABS(_fSlopeModel) > DL_SLOPE_EPS THEN                             // 相对偏差需有非零参照 / Relative deviation needs a non-zero reference
        IF ABS((_fSlopeMeas - _fSlopeModel) / _fSlopeModel) > fSlopeDevMax THEN
            IF _nDevRun < DL_DEV_MAX THEN
                _nDevRun := _nDevRun + 1;                                // 偏差持续计数 / Deviation persistence count
            END_IF
        ELSE
            _nDevRun := 0;                                               // 回到阈值内即清零 / Reset inside threshold
        END_IF
    ELSE
        _nDevRun := 0;
    END_IF
    IF _nDevRun >= DL_DEV_MAX THEN                                       // 偏差持续：按符号微调时间常数 / Sustained deviation, adjust tau by sign
        IF _fSlopeMeas < _fSlopeModel THEN                               // 实测偏慢 → 时间常数变大 / Slower than model, tau up
            _fTauUsedSec := MIN(_fTauUsedSec * DL_TAU_STEP, FC_DL_TimeToLrealSec(tIn := tTauMax));
        ELSE
            _fTauUsedSec := MAX(_fTauUsedSec / DL_TAU_STEP, FC_DL_TimeToLrealSec(tIn := tTauMin));
        END_IF
        _nDevRun := 0;                                                   // 修正后计数清零 / Reset after correction
    END_IF
END_IF

(* —— 段 5：剩余时间预测（防除零；无趋势输出哨兵而非 T#0S） —— *)
IF (NOT _bFault) AND bEnable THEN
    _fDeltaT := fTargetC - fTempC;                                       // 剩余温差 / Remaining temperature difference
    IF ABS(_fSlopeMeas) <= DL_SLOPE_EPS THEN                             // 斜率近似 0：不得输出 T#0S 冒充「马上到」 / Slope near zero, never emit T#0S
        bNoTrend := TRUE;                                                // 无趋势标志 / No-trend flag
        _fRemSec := DL_TIME_INF;                                         // 哨兵秒数 / Sentinel seconds
        _uInfo := 16#0002_04B6;                                          // 信息级：无趋势留痕 / Info: no trend recorded
    ELSE
        _fRemSec := REAL_TO_LREAL(_fDeltaT) / _fSlopeMeas;               // 线性外推剩余时间 / Linear extrapolation
        IF _fRemSec < 0.0 THEN                                           // 已越过目标（过冲在恢复）：剩余判 0 而非负数 / Already past target
            _fRemSec := 0.0;
        END_IF
        IF _fRemSec > DL_TIME_INF THEN                                   // 上界兜底防 TIME 溢出 / Upper bound guard
            _fRemSec := DL_TIME_INF;
        END_IF
    END_IF
    tRemain := FC_DL_LrealSecToTime(fSec := _fRemSec, eErr => _uConvErrR, bError => _bConvErrR, bValid => _bConvValidR);   // 委托时间换算 / Delegate conversion
ELSE
    tRemain := FC_DL_LrealSecToTime(fSec := DL_TIME_INF);                // 非运行相输出哨兵（不宣称「马上到」） / Sentinel outside run phase
END_IF

(* —— 段 6：前馈偏置（进入 fLeadBand 带内线性加大减功率量，双侧钳位） —— *)
IF (NOT _bFault) AND bEnable THEN
    IF ABS(_fDeltaT) < fLeadBand THEN                                    // 进入前馈带 / Inside lead band
        fFfBias := fFfBiasMax * (1.0 - (ABS(_fDeltaT) / fLeadBand));      // 越接近目标减得越多 / More reduction as target nears
    ELSE
        fFfBias := 0.0;                                                  // 带外不减功率 / No reduction outside band
    END_IF
    IF fFfBias > fFfBiasMax THEN                                         // 双侧钳位（上侧） / Two-sided clamp, upper
        fFfBias := fFfBiasMax;
    END_IF
    IF fFfBias < 0.0 THEN                                                // 双侧钳位（下侧） / Two-sided clamp, lower
        fFfBias := 0.0;
    END_IF
END_IF

(* —— 段 7：温度快照更新（主体末行，跨拍纪律） —— *)
_fTempPrev := fTempC;                                                    // 温度快照（本拍末更新） / Temperature snapshot at body end

(* —— 段 8：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND (NOT bNoTrend) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_TrpCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 8A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_TrpState.eFault) THEN
    _eState := E_DL_TrpState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 9：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_TrpState.eIdle:
    IF bEnable AND _bInit AND (NOT _bFault) THEN                         // 出口 1：使能且已初始化 / Enabled and initialized
        _eState := E_DL_TrpState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_TrpState.eFault;
    END_IF

E_DL_TrpState.eRun:
    IF (NOT bEnable) THEN                                                // 出口 1：失能（前置消失，R98） / Disabled
        _eState := E_DL_TrpState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_TrpState.eFault;
    END_IF

E_DL_TrpState.eFault:
    ;                                                                     // 故障相：仅段 8 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0002_03B3;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_TrpCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_TrpState.eFault;

END_CASE

(* —— 段 10：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF _bFault THEN
    tRemain  := FC_DL_LrealSecToTime(fSec := DL_TIME_INF);               // 故障相输出哨兵（不宣称短时到达） / Sentinel in fault
    bNoTrend := TRUE;                                                    // 故障相判无趋势（不给出时间承诺） / No-trend in fault
    fFfBias  := 0.0;                                                     // 故障相不减功率（不加未知偏置） / No bias in fault
    fTauUsed := LREAL_TO_REAL(_fTauUsedSec);                             // 时间常数镜像（供调试） / Tau mirror for commissioning
ELSIF NOT bEnable THEN
    fTauUsed := LREAL_TO_REAL(_fTauUsedSec);                             // 失能相仍回放时间常数（观测语义） / Tau echoed when disabled
    tRemain  := FC_DL_LrealSecToTime(fSec := DL_TIME_INF);               // 失能相哨兵 / Sentinel when disabled
    bNoTrend := TRUE;                                                    // 失能相无预测 / No prediction when disabled
ELSE
    fTauUsed := LREAL_TO_REAL(_fTauUsedSec);                             // 运行相时间常数 / Tau in run
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
