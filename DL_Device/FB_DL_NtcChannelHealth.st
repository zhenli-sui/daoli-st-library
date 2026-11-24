(*==============================================================================
 * 组件名称 (Component)  : FB_DL_NtcChannelHealth
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : NTC 通道健康度 0~100 评分与预警。按评分周期对三维度打分：
 *                         上游故障（有故障即 0 分）、长期漂移（超限按「限值/实测」折算）、
 *                         窗口噪声（同法），按组态权重加权并分档 Good/Watch/Warn/Bad。
 *                         权重和不为 100 时回退默认 40/40/20 并报组态错（不停摆但必须报）；
 *                         温度非有限则本周期不计分（记 0 分会把健康通道判死）。不做温度
 *                         换算、不做断线检测本身（由上游掩码注入）。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_HealthGrade / FUNCTION_BLOCK FB_DL_NtcChannelHealth
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS / MIN）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         两个限值判零防除零 ｜ 温度非有限只跳过本周期、不清健康度 ｜
 *                         评分周期定时器与沿实例无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE
 * 错误码表 (Codes)      : 16#0003_03B1 就绪（评分正常或本周期未到期）
 *                         16#0003_03B2 信息级 温度非有限，本周期不计分（健康度保持上次值）
 *                         16#0003_03B3 故障级 组态非法（权重和 ≠100 已回退默认、限值 ≤0）
 *                         16#0003_03B4 故障级 断线累计达 3 次（更换建议触发条件之一）
 *                         16#0003_03B5 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 2
 * 验收向量 (Acceptance) : 正向 无故障、漂移 0.2/2.0 ℃、噪声 0.01/0.5 ℃、权重 40/40/20 →
 *                         健康度 100、Good
 *                         反向 断线位置位且漂移 5 ℃（限 2.0）→ 健康度 ≤60 且 bReplaceReq=TRUE；
 *                         漂移限给 0 → 16#0003_03B3；温度给 NaN → 16#0003_03B2 且健康度保持
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HealthGrade（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HealthGrade :
(
    eGood  := 0,    // 良好：健康度 ≥80 / Good, health of 80 or above
    eWatch := 10,   // 关注：健康度 60~79 / Watch, health from 60 to 79
    eWarn  := 20,   // 预警：健康度 40~59 / Warn, health from 40 to 59
    eBad   := 30    // 差：健康度 <40，需更换 / Bad, health below 40, replacement required
);
END_TYPE

FUNCTION_BLOCK FB_DL_NtcChannelHealth
VAR_INPUT
    bEnable        : BOOL := FALSE;       // 使能 / Enable
    fTemp_C        : REAL := 25.0;        // 该通道温度 [℃] / Channel temperature in degrees Celsius
    uChFaultMask   : WORD;                // 上游通道故障掩码 [bit]，bit0 断线 bit1 短路 bit2 超域 / Upstream channel fault mask
    fDriftTotal_C  : REAL := 0.0;         // 长期漂移（对投运基线）[℃] / Long-term drift against the commissioning baseline
    fNoise_C       : REAL := 0.0;         // 窗口噪声（标准差）[℃] / Window noise as a standard deviation
    fDriftLimit_C  : REAL := 2.0;         // 漂移扣尽阈 [℃]，域 0.5~20 / Drift limit that zeroes the score, domain 0.5 to 20
    fNoiseLimit_C  : REAL := 0.5;         // 噪声扣尽阈 [℃]，域 0.05~5 / Noise limit that zeroes the score, domain 0.05 to 5
    uFaultWeight   : UINT := 40;          // 故障权重 [—]，域 0~100 / Fault weight, domain 0 to 100
    uDriftWeight   : UINT := 40;          // 漂移权重 [—]，域 0~100 / Drift weight, domain 0 to 100
    uNoiseWeight   : UINT := 20;          // 噪声权重 [—]，域 0~100 / Noise weight, domain 0 to 100
    tEvalPeriod    : TIME := T#5S;        // 评分周期 [ms]，域 1~60 s / Scoring period, domain 1 to 60 s
END_VAR
VAR_OUTPUT
    uHealth        : UINT := 100;         // 健康度 [0~100] / Health score from 0 to 100
    eGrade         : E_DL_HealthGrade;    // 健康分档 [—] / Health grade
    bReplaceReq    : BOOL;                // 更换建议（Bad 或断线累计 3 次） / Replacement advice
    bError         : BOOL;                // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    eErr           : UDINT;               // 错误码，段位 16#0003_xxxx / Error code in segment 16#0003_xxxx
END_VAR
VAR
    _bInit         : BOOL := FALSE;       // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk        : BOOL;                // 组态合法标志 / Configuration valid flag
    _bFallback     : BOOL;                // 权重回退标志 / Weight fallback flag
    _bScoreNow     : BOOL;                // 本拍评分标志（周期到） / Score this scan flag
    _uwFault       : UINT := 40;          // 生效故障权重 / Effective fault weight
    _uwDrift       : UINT := 40;          // 生效漂移权重 / Effective drift weight
    _uwNoise       : UINT := 20;          // 生效噪声权重 / Effective noise weight
    _uwDisconnect  : UINT := 0;           // 断线累计次数 [次] / Disconnect count
    _uwFaultScore  : UINT;                // 故障维度得分 [0~100] / Fault dimension score
    _uwDriftScore  : UINT;                // 漂移维度得分 [0~100] / Drift dimension score
    _uwNoiseScore  : UINT;                // 噪声维度得分 [0~100] / Noise dimension score
    _uwSum         : UDINT;               // 加权和中间量 / Weighted sum intermediate
    _fDriftRatio   : REAL;                // 漂移占比（限值/实测） / Drift ratio, limit over measurement
    _fNoiseRatio   : REAL;                // 噪声占比（限值/实测） / Noise ratio, limit over measurement
    _rtrigFault    : R_TRIG;              // 断线位上升沿 / Rising edge of the disconnect bit
    _tonEval       : TON;                 // 评分周期计时（自复位） / Scoring period timer, self resetting
END_VAR
VAR CONSTANT
    DL_NTC_READY   : UDINT := 16#0003_03B1;  // 就绪码 / Ready code
    DL_NTC_SKIP    : UDINT := 16#0003_03B2;  // 信息级温度非有限码 / Info code for a non-finite temperature
    DL_NTC_CFG_BAD : UDINT := 16#0003_03B3;  // 故障级组态非法码 / Fault code for bad configuration
    DL_NTC_DISC    : UDINT := 16#0003_03B4;  // 故障级断线累计码 / Fault code for accumulated disconnections
    DL_NTC_BIT_DISC : WORD := 16#0001;       // 断线位 / Disconnect bit
    DL_NTC_DISC_MAX : UINT := 3;             // 断线累计阈值 [次] / Disconnect count threshold
    DL_NTC_DRIFT_LO : REAL := 0.5;           // 漂移限下限 [℃] / Drift limit lower bound
    DL_NTC_DRIFT_HI : REAL := 20.0;          // 漂移限上限 [℃] / Drift limit upper bound
    DL_NTC_NOISE_LO : REAL := 0.05;          // 噪声限下限 [℃] / Noise limit lower bound
    DL_NTC_NOISE_HI : REAL := 5.0;           // 噪声限上限 [℃] / Noise limit upper bound
    DL_NTC_GOOD     : UINT := 80;            // Good 档门限 / Good threshold
    DL_NTC_WATCH    : UINT := 60;            // Watch 档门限 / Watch threshold
    DL_NTC_WARN     : UINT := 40;            // Warn 档门限 / Warn threshold
    DL_NTC_HUNDRED  : REAL := 100.0;         // 百分比基准 / Percentage base
END_VAR

// 段 1｜输出与单拍标志预置
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_bScoreNow := FALSE;                                // 评分标志预清 / Scoring flag pre-cleared

// 段 2｜沿检测与评分周期定时器无条件周期刷新（自复位：IN 取上一拍 Q 取非）
_rtrigFault(CLK := ((uChFaultMask AND DL_NTC_BIT_DISC) <> 16#0000));
_tonEval(IN := bEnable AND (NOT _tonEval.Q), PT := tEvalPeriod);
IF _tonEval.Q THEN
    _bScoreNow := TRUE;                             // 周期到：本拍评分 / The period elapsed, score this scan
END_IF

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    uHealth := 100;                                 // 健康度起点 100 / Health starts at 100
    eGrade := E_DL_HealthGrade.eGood;               // 分档起点 Good / Grade starts good
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜断线累计（上升沿计数，供更换建议）
IF _rtrigFault.Q THEN
    _uwDisconnect := _uwDisconnect + 1;             // 断线累计 +1 [次] / Disconnect count incremented
END_IF

// 段 5｜权重与限值组态闸（和 ≠100 → 回退 40/40/20 并报组态错；限值判零防除零）
_bFallback := (uFaultWeight + uDriftWeight + uNoiseWeight) <> 100;
IF _bFallback THEN
    _uwFault := 40;                                 // 回退故障权重 / Fallback fault weight
    _uwDrift := 40;                                 // 回退漂移权重 / Fallback drift weight
    _uwNoise := 20;                                 // 回退噪声权重 / Fallback noise weight
ELSE
    _uwFault := uFaultWeight;                       // 采用组态权重 / Use the configured weight
    _uwDrift := uDriftWeight;
    _uwNoise := uNoiseWeight;
END_IF
_bCfgOk := (NOT _bFallback)
        AND NOT ((fDriftLimit_C <> fDriftLimit_C) OR ((fDriftLimit_C - fDriftLimit_C) <> (fDriftLimit_C - fDriftLimit_C)))
        AND (fDriftLimit_C >= DL_NTC_DRIFT_LO) AND (fDriftLimit_C <= DL_NTC_DRIFT_HI)
        AND NOT ((fNoiseLimit_C <> fNoiseLimit_C) OR ((fNoiseLimit_C - fNoiseLimit_C) <> (fNoiseLimit_C - fNoiseLimit_C)))
        AND (fNoiseLimit_C >= DL_NTC_NOISE_LO) AND (fNoiseLimit_C <= DL_NTC_NOISE_HI)
        AND (tEvalPeriod >= T#1S) AND (tEvalPeriod <= T#60S);
IF NOT _bCfgOk THEN
    eErr := DL_NTC_CFG_BAD;                         // 故障级：组态非法 / Fault, bad configuration
    bError := TRUE;
END_IF
IF _uwDisconnect >= DL_NTC_DISC_MAX THEN
    eErr := DL_NTC_DISC;                            // 故障级：断线累计达阈值 / Fault, the disconnect count reached the threshold
    bError := TRUE;
END_IF

// 段 6｜评分（周期到且组态合法时才计分；温度非有限则本周期不计分）
IF _bScoreNow AND _bCfgOk THEN
    IF (fTemp_C <> fTemp_C) OR ((fTemp_C - fTemp_C) <> (fTemp_C - fTemp_C)) THEN
        eErr := DL_NTC_SKIP;                        // 信息级：温度非有限，本周期不计分 / Info, temperature not finite, no scoring this period
    ELSE
        // 故障维度：有任何上游故障位即 0 分
        IF uChFaultMask <> 16#0000 THEN
            _uwFaultScore := 0;                     // 故障维度 0 分 / Fault dimension scores zero
        ELSE
            _uwFaultScore := 100;                   // 故障维度满分 / Fault dimension scores full
        END_IF
        // 漂移维度：限内满分，超限按「限值 / 实测」折算
        IF ABS(fDriftTotal_C) <= fDriftLimit_C THEN
            _uwDriftScore := 100;
        ELSE
            _fDriftRatio := fDriftLimit_C / ABS(fDriftTotal_C);          // 占比 ≤1 / Ratio at most one
            _uwDriftScore := REAL_TO_UINT(_fDriftRatio * DL_NTC_HUNDRED);
        END_IF
        // 噪声维度：同法折算
        IF ABS(fNoise_C) <= fNoiseLimit_C THEN
            _uwNoiseScore := 100;
        ELSE
            _fNoiseRatio := fNoiseLimit_C / ABS(fNoise_C);               // 占比 ≤1 / Ratio at most one
            _uwNoiseScore := REAL_TO_UINT(_fNoiseRatio * DL_NTC_HUNDRED);
        END_IF
        // 加权合成（权重和恒为 100，除零不可达）
        _uwSum := (UINT_TO_UDINT(_uwFault) * UINT_TO_UDINT(_uwFaultScore)
                 + UINT_TO_UDINT(_uwDrift) * UINT_TO_UDINT(_uwDriftScore)
                 + UINT_TO_UDINT(_uwNoise) * UINT_TO_UDINT(_uwNoiseScore)) / 100;
        uHealth := UDINT_TO_UINT(_uwSum);           // 健康度落定 [0~100] / Health latched
    END_IF
END_IF

// 段 7｜分档（整数比较，禁浮点等判；ENUM + CASE + ELSE 兜底）
IF uHealth >= DL_NTC_GOOD THEN
    eGrade := E_DL_HealthGrade.eGood;
ELSIF uHealth >= DL_NTC_WATCH THEN
    eGrade := E_DL_HealthGrade.eWatch;
ELSIF uHealth >= DL_NTC_WARN THEN
    eGrade := E_DL_HealthGrade.eWarn;
ELSE
    eGrade := E_DL_HealthGrade.eBad;
END_IF
CASE eGrade OF
    E_DL_HealthGrade.eGood:
        bReplaceReq := FALSE;                       // Good 不建更换 / No replacement advice for good channels
    E_DL_HealthGrade.eWatch:
        bReplaceReq := FALSE;                       // Watch 暂不更换 / No replacement advice while watching
    E_DL_HealthGrade.eWarn:
        bReplaceReq := FALSE;                       // Warn 暂不更换 / No replacement advice while warning
    E_DL_HealthGrade.eBad:
        bReplaceReq := TRUE;                        // Bad 建议更换 / Replacement advised on bad channels
    ELSE
        // 非法分档兜底：按 Bad 处理（安全侧）并报组态错
        eGrade := E_DL_HealthGrade.eBad;
        bReplaceReq := TRUE;
        eErr := DL_NTC_CFG_BAD;                     // 故障级：分档非法 / Fault, illegal grade
        bError := TRUE;
END_CASE
IF (_uwDisconnect >= DL_NTC_DISC_MAX) THEN
    bReplaceReq := TRUE;                            // 断线累计达阈值亦建议更换 / Replacement also advised on repeated disconnections
END_IF
IF eErr = 0 THEN
    eErr := DL_NTC_READY;                           // 无事件回就绪码 / Ready code when nothing else applies
END_IF
END_FUNCTION_BLOCK
