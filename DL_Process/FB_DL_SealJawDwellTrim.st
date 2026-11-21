(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SealJawDwellTrim
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，无方言）
 * 功能描述 (Function)   : 热封刀驻留时间随线速自整定（限速微调）。以封口质量对目标的偏差
 *                         按微调增益积分出驻留补偿量，先按变化率限速、再按上下限钳制
 *                         （反序会让爬升把超限带出来），停机期不计数、不积分；质量读数非
 *                         有限则冻结微调并保持上次给定（不把 NaN 积分进给定）。不做温控、
 *                         不做封口质量判定本身（由引脚注入）、不做多刀头协调。
 *                         遗留假设（代理阈值三句）：① 代理任务周期取 100 ms（本件无周期
 *                         引脚）；② 覆盖 50~200 ms 的任务周期，偏差 ≤2 倍；③ 更快的任务
 *                         周期由调用方在 fDwellRateMax_msS 上折算，本件不负责。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_DwellState / FUNCTION_BLOCK FB_DL_SealJawDwellTrim
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / LIMIT / MIN / MAX）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         上下限与目标判零防除零 ｜ 质量非有限即冻结微调并保持给定 ｜ 先限速
 *                         后钳制 ｜ 枚举显式赋值 ｜ CASE 含 ELSE 兜底 ｜ 本件无定时器/沿实例，
 *                         全部逻辑为无状态算术，故无周期刷新项
 * 错误码表 (Codes)      : 16#0005_043A 就绪（微调正常或停机冻结）
 *                         16#0005_043B 预留：本版不发码（下一轮区间起点，禁止回填）
 *                         16#0005_043C 故障级 组态非法（上下限反置、目标/增益/变化率出域）
 *                         16#0005_043D 信息级 驻留给定触限并已钳制（不置故障级标志）
 *                         16#0005_043E 故障级 质量读数非有限，微调冻结并保持上次给定
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 4
 * 验收向量 (Acceptance) : 正向 标称 300 ms、线速 0→60 m/min、质量 0.85 对目标 0.90 → 微调
 *                         +10 ms、给定 310 ms、斜率 ≤50 ms/s
 *                         反向 下限设 400 ms > 上限 300 ms → 16#0005_043C；质量给 NaN →
 *                         16#0005_043E 且给定保持；给定顶到上限 → 16#0005_043D 且 bAtLimit
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DwellState（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DwellState :
(
    eFrozen  := 0,    // 冻结：停机、禁用或质量不可信 / Frozen, stopped, disabled or the quality is untrustworthy
    eTrim    := 10,   // 微调：限速 + 钳制后的驻留给定 / Trimming, rate limited and clamped
    eAtLimit := 20,   // 触限：给定顶在上下限 / At a limit, the setpoint sits on a bound
    eFault   := 99    // 故障：组态非法锁存 / Fault, the configuration error is latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_SealJawDwellTrim
VAR_INPUT
    bEnable         : BOOL := FALSE;      // 使能 / Enable
    bRunning        : BOOL := FALSE;      // 线运行（停机冻结自整定） / Line running, tuning is frozen when stopped
    fLineSpeed_mpm  : REAL := 0.0;        // 线速度 [m/min]，域 0~200 / Line speed in metres per minute, domain 0 to 200
    fDwellNominal_ms : REAL := 300.0;     // 标称驻留 [ms]，域 50~2000 / Nominal dwell, domain 50 to 2000 ms
    fDwellMin_ms    : REAL := 200.0;      // 驻留下限 [ms] / Dwell lower bound
    fDwellMax_ms    : REAL := 500.0;      // 驻留上限 [ms]，须 > 下限 / Dwell upper bound, must exceed the lower bound
    fSealQuality    : REAL := 0.9;        // 封口质量 [0~1]（注入） / Seal quality from zero to one, injected
    fQualityTarget  : REAL := 0.9;        // 目标质量 [—]，域 0.7~0.99 / Quality target, domain 0.7 to 0.99
    fTrimGain       : REAL := 20.0;       // 微调增益 [ms/单位误差]，域 0~50 / Trim gain in milliseconds per unit error
    fDwellRateMax_msS : REAL := 50.0;     // 变化率上限 [ms/s]，域 1~200 / Rate limit in milliseconds per second
END_VAR
VAR_OUTPUT
    fDwellOut_ms    : REAL;               // 驻留给定 [ms] / Dwell setpoint in milliseconds
    fDwellTrim_ms   : REAL;               // 微调分量 [ms] / Trim component in milliseconds
    bAtLimit        : BOOL;               // 到上下限 / At a bound
    uTrimCnt        : UDINT;              // 微调生效次数 [次] / Effective trim count
    eErr            : UDINT;               // 错误码，段位 16#0005_xxxx / Error code in segment 16#0005_xxxx
END_VAR
VAR
    _eState         : E_DL_DwellState := E_DL_DwellState.eFrozen; // 当前相位 / Current phase
    _bInit          : BOOL := FALSE;      // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk         : BOOL;               // 组态合法标志 / Configuration valid flag
    _bFaultLatch    : BOOL := FALSE;      // 组态故障锁存 / Configuration fault latch
    _bQualityOk     : BOOL;               // 质量读数可信标志 / Quality reading trustworthy flag
    _fErr           : REAL;               // 质量误差（目标 − 实测） / Quality error, target minus measured
    _fTrimWant      : REAL := 0.0;        // 期望微调分量 [ms] / Desired trim component
    _fTrimStep      : REAL;               // 本拍允许的微调步长 [ms] / Allowed trim step of this scan
    _fTrimDelta     : REAL;               // 本拍实际微调增量 [ms] / Actual trim increment of this scan
    _fDwellRaw      : REAL;               // 限速后驻留 [ms] / Rate-limited dwell
    _fDwellPrev     : REAL := 300.0;      // 上一拍驻留给定 [ms] / Previous dwell setpoint
END_VAR
VAR CONSTANT
    DL_DW_READY    : UDINT := 16#0005_043A;  // 就绪码 / Ready code
    DL_DW_CFG_BAD  : UDINT := 16#0005_043C;  // 故障级组态非法码 / Fault code for bad configuration
    DL_DW_LIMIT    : UDINT := 16#0005_043D;  // 信息级触限钳制码 / Info code for bound clamping
    DL_DW_QUAL_BAD : UDINT := 16#0005_043E;  // 故障级质量非有限码 / Fault code for a non-finite quality
    DL_DW_NOM_LO   : REAL := 50.0;           // 标称驻留下限 [ms] / Nominal dwell lower bound
    DL_DW_NOM_HI   : REAL := 2000.0;         // 标称驻留上限 [ms] / Nominal dwell upper bound
    DL_DW_TGT_LO   : REAL := 0.7;            // 目标质量下限 / Quality target lower bound
    DL_DW_TGT_HI   : REAL := 0.99;           // 目标质量上限 / Quality target upper bound
    DL_DW_GAIN_HI  : REAL := 50.0;           // 增益上限 [ms/单位误差] / Gain upper bound
    DL_DW_RATE_LO  : REAL := 1.0;            // 变化率下限 [ms/s] / Rate lower bound
    DL_DW_RATE_HI  : REAL := 200.0;          // 变化率上限 [ms/s] / Rate upper bound
    DL_DW_TASK_S   : REAL := 0.1;            // 代理任务周期 [s]（遗留假设） / Proxy task period in seconds
    DL_DW_TRIM_EPS : REAL := 1.0;            // 微调计数门限 [ms] / Trim counting threshold
END_VAR

// 段 1｜输出与单拍标志预置
bAtLimit := FALSE;                                  // 触限标志预清 / At-bound flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _fTrimWant := 0.0;                              // 微调起点 0 [ms] / Trim starts at zero
    _fDwellPrev := fDwellNominal_ms;                // 上一拍驻留取标称 [ms] / Previous dwell starts from the nominal value
    _eState := E_DL_DwellState.eFrozen;             // 相位冻结起步 / Phase starts frozen
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 3｜组态闸（上下限反置 → 微调区间为空；目标与变化率出域）
_bCfgOk := (fDwellMin_ms < fDwellMax_ms)
        AND NOT ((fQualityTarget <> fQualityTarget) OR ((fQualityTarget - fQualityTarget) <> (fQualityTarget - fQualityTarget)))
        AND (fQualityTarget >= DL_DW_TGT_LO) AND (fQualityTarget <= DL_DW_TGT_HI)
        AND (fDwellNominal_ms >= DL_DW_NOM_LO) AND (fDwellNominal_ms <= DL_DW_NOM_HI)
        AND (fTrimGain >= 0.0) AND (fTrimGain <= DL_DW_GAIN_HI)
        AND (fDwellRateMax_msS >= DL_DW_RATE_LO) AND (fDwellRateMax_msS <= DL_DW_RATE_HI);
IF NOT _bCfgOk THEN
    _bFaultLatch := TRUE;                           // 组态故障锁存 / Configuration fault latched
    eErr := DL_DW_CFG_BAD;                          // 故障级：组态非法 / Fault, bad configuration
    _eState := E_DL_DwellState.eFault;
END_IF

// 段 4｜质量可信闸（非有限即冻结微调，给定保持上次值）
_bQualityOk := NOT ((fSealQuality <> fSealQuality) OR ((fSealQuality - fSealQuality) <> (fSealQuality - fSealQuality)));
IF NOT _bQualityOk THEN
    eErr := DL_DW_QUAL_BAD;                         // 故障级：质量非有限，微调冻结 / Fault, the quality is not finite and the trim is frozen
    _eState := E_DL_DwellState.eFrozen;
END_IF

// 段 5｜微调积分（仅在运行、使能、组态与质量均可信时推进）
IF bEnable AND bRunning AND _bCfgOk AND _bQualityOk THEN
    _fErr := fQualityTarget - fSealQuality;         // 质量误差（正 = 质量偏低）/ Quality error, positive means poor sealing
    _fTrimWant := _fTrimWant + (_fErr * fTrimGain); // 期望微调分量积分 [ms] / Desired trim integrated
    // 先限速：单拍最大变化 = 变化率 × 代理任务周期
    _fTrimStep := fDwellRateMax_msS * DL_DW_TASK_S; // 本拍允许步长 [ms] / Allowed step of this scan
    _fTrimDelta := _fTrimWant - (_fDwellPrev - fDwellNominal_ms);   // 与上一拍的差 [ms] / Difference against the previous value
    IF _fTrimDelta > _fTrimStep THEN
        _fTrimDelta := _fTrimStep;                  // 正向限速 [ms] / Positive rate limit
    END_IF
    IF _fTrimDelta < (0.0 - _fTrimStep) THEN
        _fTrimDelta := 0.0 - _fTrimStep;            // 负向限速 [ms] / Negative rate limit
    END_IF
    _fDwellRaw := _fDwellPrev + _fTrimDelta;        // 限速后驻留 [ms] / Rate-limited dwell
    // 后钳制：把限速结果压进上下限，越限即触限并计数
    fDwellOut_ms := LIMIT(fDwellMin_ms, _fDwellRaw, fDwellMax_ms);
    IF ABS(fDwellOut_ms - _fDwellRaw) > 0.0001 THEN
        bAtLimit := TRUE;                           // 触限：给定被钳制 / At a bound, the setpoint was clamped
        eErr := DL_DW_LIMIT;                        // 信息级：触限钳制 / Info, clamped at a bound
        _eState := E_DL_DwellState.eAtLimit;
    ELSE
        _eState := E_DL_DwellState.eTrim;           // 正常微调 / Normal trimming
    END_IF
    _fTrimWant := fDwellOut_ms - fDwellNominal_ms;  // 反写分量（防积分饱和）[ms] / Anti-windup write-back
    IF ABS(_fTrimDelta) >= DL_DW_TRIM_EPS THEN
        uTrimCnt := uTrimCnt + 1;                   // 微调生效计数 +1 [次] / Effective trim count incremented
    END_IF
    _fDwellPrev := fDwellOut_ms;                    // 上一拍驻留快照 [ms] / Previous dwell snapshot
ELSE
    fDwellOut_ms := _fDwellPrev;                    // 冻结：保持上次给定 [ms] / Frozen, the previous setpoint is held
    IF _bQualityOk AND bEnable AND (NOT _bCfgOk) THEN
        eErr := DL_DW_CFG_BAD;                      // 故障级：组态非法保持 / Fault, the configuration error is held
    END_IF
END_IF

// 段 6｜微调分量出口与相位收口（ENUM + CASE + ELSE 兜底）
fDwellTrim_ms := _fTrimWant;                        // 微调分量出口 [ms] / Trim component output
CASE _eState OF
    E_DL_DwellState.eFrozen:
        bAtLimit := FALSE;                          // 冻结期不报触限 / No bound report while frozen
        IF bEnable AND bRunning AND _bCfgOk AND _bQualityOk THEN
            _eState := E_DL_DwellState.eTrim;       // 条件齐备：转微调 / Conditions met, go trimming
        END_IF
    E_DL_DwellState.eTrim:
        IF (NOT bRunning) OR (NOT bEnable) THEN
            _eState := E_DL_DwellState.eFrozen;     // 停机或失能：冻结 / Stopped or disabled, freeze
        END_IF
    E_DL_DwellState.eAtLimit:
        IF (NOT bRunning) OR (NOT bEnable) THEN
            _eState := E_DL_DwellState.eFrozen;
        END_IF
    E_DL_DwellState.eFault:
        eErr := DL_DW_CFG_BAD;                      // 故障级：组态非法保持 / Fault, the configuration error is held
        IF _bCfgOk AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                  // 组态修正且失能后解除 / Released after the configuration is fixed and the unit is disabled
            _eState := E_DL_DwellState.eFrozen;
        END_IF
    ELSE
        // 非法相位兜底（故障级）
        eErr := DL_DW_CFG_BAD;
        _bFaultLatch := TRUE;
        _eState := E_DL_DwellState.eFault;
END_CASE
IF eErr = 0 THEN
    eErr := DL_DW_READY;                            // 无事件回就绪码 / Ready code when nothing else applies
END_IF
END_FUNCTION_BLOCK
