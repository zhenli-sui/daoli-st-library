(*==============================================================================
 * 组件名称 (Component)  : FB_DL_InlineCheckweighGauge
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，无方言）
 * 功能描述 (Function)   : 在线称重动态窗判据与 σ 控制图。逐件判欠重/超重（不平顺：平滑会
 *                         漏掉单件超重），滑动统计窗给均值与样本标准差（分母 n−1，n≥5 前置
 *                         保证防除零），满窗后才判 σ 越控制限；可选的 ±3σ 冲击剔除只影响
 *                         统计窗，不影响逐件判据。不做传感器标定、不做零点跟踪（另有专件）、
 *                         不做剔除机构驱动。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_GaugeWin / FUNCTION_BLOCK FB_DL_InlineCheckweighGauge
 * 依赖 (Depends)        : 无（仅 Standard.library 的 SQRT / ABS / MIN）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         公差与控制限判零防除零 ｜ 样本非有限即丢弃并计丢弃数 ｜ 标准差前置
 *                         n≥5 且分母 n−1 ｜ σ 仅满窗判 ｜ 枚举显式赋值 ｜ CASE 含 ELSE 兜底
 *                         ｜ 本件无定时器/沿实例，全部为周期算术，故无周期刷新项
 * 错误码表 (Codes)      : 16#0005_0444 就绪（窗口统计正常）
 *                         16#0005_0445 预留：本版不发码（下一轮区间起点，禁止回填）
 *                         16#0005_0446 故障级 组态非法（公差 ≤0、窗长 <5、σ 限 ≤0）
 *                         16#0005_0447 故障级 目标重量非有限（逐件判据停判，统计继续）
 *                         16#0005_0448 信息级 样本非有限已丢弃（计入丢弃数）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 4
 * 验收向量 (Acceptance) : 正向 目标 500 g、公差 ±5、10 件 500±1 → 均值 ≈500、σ ≈0.7、
 *                         无报警
 *                         反向 一件 508 g → bOver 单件置位、uRejectCnt 不增（非剔除开关）、
 *                         均值仍 ≈500；σ 升到 6 超控制限 2 → bSpcAlarm；样本给 NaN →
 *                         16#0005_0448 且丢弃数 +1；窗长给 3 → 16#0005_0446
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GaugeWin（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_GaugeWin :
(
    eEmpty := 0,    // 空窗：尚无有效样本 / Empty window, no valid sample yet
    eFill  := 10,   // 填充中：样本数未满窗长 / Filling, the sample count is below the window length
    eFull  := 20,   // 满窗：均值与 σ 可信 / Full window, the mean and sigma are trustworthy
    eFault := 99    // 故障：组态非法 / Fault, the configuration is invalid
);
END_TYPE

FUNCTION_BLOCK FB_DL_InlineCheckweighGauge
VAR_INPUT
    bEnable        : BOOL := FALSE;       // 使能 / Enable
    bSampleValid   : BOOL := FALSE;       // 本拍有有效样本 / A valid sample is present in this scan
    fWeight_g      : REAL := 0.0;         // 件重 [g]，域 0~50000 / Piece weight in grammes, domain 0 to 50000
    fTarget_g      : REAL := 500.0;       // 目标重量 [g] / Target weight in grammes
    fTolUp_g       : REAL := 5.0;         // 上公差带 [g]，须 >0 / Upper tolerance in grammes, must be positive
    fTolLow_g      : REAL := 5.0;         // 下公差带 [g]，须 >0 / Lower tolerance in grammes, must be positive
    uWinSamples    : UINT := 10;          // 统计窗长 [个]，域 5~50 / Statistical window length, domain 5 to 50
    fSigmaLimit_g  : REAL := 2.0;         // σ 控制限 [g]，域 0.1~20 / Sigma control limit in grammes, domain 0.1 to 20
    bOutlierReject : BOOL := FALSE;       // ±3σ 冲击剔除开关 / Plus minus three sigma outlier rejection switch
END_VAR
VAR_OUTPUT
    fMeanOut_g     : REAL;                // 窗口均值 [g] / Window mean in grammes
    fSigmaOut_g    : REAL;                // 窗口标准差 [g] / Window standard deviation in grammes
    bUnder         : BOOL;                // 本件欠重（逐件判据） / This piece is underweight
    bOver          : BOOL;                // 本件超重（逐件判据） / This piece is overweight
    bSpcAlarm      : BOOL;                // σ 越控制限（满窗后才判） / Sigma above the control limit, judged on a full window only
    uRejectCnt     : UDINT;               // 剔除件数 [件]（±3σ 剔除） / Outlier rejection count
    uSpcCnt        : UDINT;               // SPC 越限次数 [次] / SPC limit violation count
    eErr           : UDINT;               // 错误码，段位 16#0005_xxxx / Error code in segment 16#0005_xxxx
END_VAR
VAR
    _eWin          : E_DL_GaugeWin := E_DL_GaugeWin.eEmpty; // 窗口相位 / Window phase
    _bInit         : BOOL := FALSE;       // 首扫标志，取非判定 / First-scan flag, tested negated
    _bCfgOk        : BOOL;                // 组态合法标志 / Configuration valid flag
    _bTgtOk        : BOOL;                // 目标有限标志 / Target finite flag
    _bSpcLatched   : BOOL := FALSE;       // SPC 报警锁存（单拍计数用） / SPC alarm latch for one-shot counting
    _uWinEff       : UINT := 10;          // 生效窗长（钳制后）[个] / Effective window length after clamping
    _uIdx          : UINT := 1;           // 环形写指针 / Circular write index
    _uFill         : UINT := 0;           // 已填样本数 [个] / Number of samples collected
    _fSum          : REAL := 0.0;         // 样本和 [g] / Sample sum
    _fMean         : REAL := 0.0;         // 窗口均值 [g] / Window mean
    _fMeanOut_g    : REAL := 0.0;         // 窗口均值中间量（出口映射源）[g] / Window mean intermediate, source of the outlet [g]
    _fVar          : REAL := 0.0;         // 样本方差 [g²] / Sample variance
    _afWin         : ARRAY[1..50] OF REAL; // 样本环形窗 [g] / Sample ring buffer
    _iLoop         : INT;                 // 统计循环索引 / Statistical loop index
    _iGuard        : INT;                 // 防死循环计数器 / Loop guard counter
END_VAR
VAR CONSTANT
    DL_CW_READY    : UDINT := 16#0005_0444;  // 就绪码 / Ready code
    DL_CW_CFG_BAD  : UDINT := 16#0005_0446;  // 故障级组态非法码 / Fault code for bad configuration
    DL_CW_TGT_BAD  : UDINT := 16#0005_0447;  // 故障级目标非有限码 / Fault code for a non-finite target
    DL_CW_SKIP     : UDINT := 16#0005_0448;  // 信息级样本丢弃码 / Info code for a discarded sample
    DL_CW_WIN_LO   : UINT := 5;              // 窗长下限 [个] / Window length lower bound
    DL_CW_WIN_HI   : UINT := 50;             // 窗长上限 [个] / Window length upper bound
    DL_CW_SIG_LO   : REAL := 0.1;            // σ 控制限下限 [g] / Sigma limit lower bound
    DL_CW_SIG_HI   : REAL := 20.0;           // σ 控制限上限 [g] / Sigma limit upper bound
    DL_CW_LOOP_MAX : INT := 60;              // 循环保护上限 / Loop guard bound
    DL_CW_EPS      : REAL := 1.0E-6;         // 浮点判零容差 / Float zero tolerance
END_VAR

// 段 1｜输出与单拍标志预置
bUnder := FALSE;                                    // 欠重预清 / Underweight pre-cleared
bOver := FALSE;                                     // 超重预清 / Overweight pre-cleared
bSpcAlarm := FALSE;                                 // SPC 报警预清 / SPC alarm pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _afWin[1] := 0.0;                               // 环形窗首元素预置 [g] / Ring buffer first element pre-set
    _eWin := E_DL_GaugeWin.eEmpty;                  // 窗口相位起点 / Window phase starts empty
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 3｜组态闸（公差与控制限判零防除零；窗长 <5 使 σ 不可信）
_bCfgOk := (fTolUp_g > 0.0) AND (fTolLow_g > 0.0)
        AND NOT ((fSigmaLimit_g <> fSigmaLimit_g) OR ((fSigmaLimit_g - fSigmaLimit_g) <> (fSigmaLimit_g - fSigmaLimit_g)))
        AND (fSigmaLimit_g >= DL_CW_SIG_LO) AND (fSigmaLimit_g <= DL_CW_SIG_HI)
        AND (uWinSamples >= DL_CW_WIN_LO) AND (uWinSamples <= DL_CW_WIN_HI);
_bTgtOk := NOT ((fTarget_g <> fTarget_g) OR ((fTarget_g - fTarget_g) <> (fTarget_g - fTarget_g)));
IF NOT _bCfgOk THEN
    eErr := DL_CW_CFG_BAD;                          // 故障级：组态非法 / Fault, bad configuration
    _eWin := E_DL_GaugeWin.eFault;
ELSE
    _uWinEff := uWinSamples;                        // 采用组态窗长 [个] / Use the configured window length
END_IF
IF NOT _bTgtOk THEN
    eErr := DL_CW_TGT_BAD;                          // 故障级：目标非有限（逐件判据停判） / Fault, the target is not finite
END_IF

// 段 4｜逐件判据（不平顺，单件即判；目标不可读时停判）
IF bEnable AND bSampleValid AND _bTgtOk THEN
    IF (fWeight_g <> fWeight_g) OR ((fWeight_g - fWeight_g) <> (fWeight_g - fWeight_g)) THEN
        eErr := DL_CW_SKIP;                         // 信息级：样本非有限，丢弃 / Info, the sample is not finite and is discarded
        uRejectCnt := uRejectCnt + 1;               // 丢弃计数 +1 [件] / Discard count incremented
    ELSE
        IF fWeight_g < (fTarget_g - fTolLow_g) THEN
            bUnder := TRUE;                         // 本件欠重 / This piece is underweight
        END_IF
        IF fWeight_g > (fTarget_g + fTolUp_g) THEN
            bOver := TRUE;                          // 本件超重 / This piece is overweight
        END_IF
        // 冲击剔除（±3σ，仅满窗且开关有效时；剔除只影响统计窗）
        IF bOutlierReject AND (_uFill >= DL_CW_WIN_LO) AND (fSigmaOut_g > DL_CW_EPS) THEN
            IF ABS(fWeight_g - _fMean) > (3.0 * fSigmaOut_g) THEN
                uRejectCnt := uRejectCnt + 1;       // ±3σ 剔除 +1 [件] / Outlier rejected
            ELSE
                _fSum := _fSum - _afWin[_uIdx];                 // 换出最旧样本 [g] / Remove the oldest sample
                _afWin[_uIdx] := fWeight_g;                     // 写入新样本 [g] / Insert the new sample
                _fSum := _fSum + fWeight_g;                     // 样本和更新 [g] / Update the sum
                _uIdx := _uIdx + 1;
                IF _uIdx > _uWinEff THEN
                    _uIdx := 1;                                 // 环形回卷 / Ring wrap
                END_IF
                IF _uFill < _uWinEff THEN
                    _uFill := _uFill + 1;                       // 已填样本数 +1 [个] / Sample count incremented
                END_IF
            END_IF
        ELSE
            _fSum := _fSum - _afWin[_uIdx];                     // 换出最旧样本 [g] / Remove the oldest sample
            _afWin[_uIdx] := fWeight_g;                         // 写入新样本 [g] / Insert the new sample
            _fSum := _fSum + fWeight_g;                         // 样本和更新 [g] / Update the sum
            _uIdx := _uIdx + 1;
            IF _uIdx > _uWinEff THEN
                _uIdx := 1;                                     // 环形回卷 / Ring wrap
            END_IF
            IF _uFill < _uWinEff THEN
                _uFill := _uFill + 1;                           // 已填样本数 +1 [个] / Sample count incremented
            END_IF
        END_IF
    END_IF
END_IF

// 段 5｜均值与样本标准差（分母 n−1，n≥5 前置保证防除零）
IF _uFill > 0 THEN
    _fMean := _fSum / UINT_TO_REAL(_uFill);         // 窗口均值 [g] / Window mean
END_IF
_fMeanOut_g := _fMean;                              // 均值出口 [g] / Mean output
_fVar := 0.0;                                       // 方差清零 [g²] / Variance reset
IF _uFill >= DL_CW_WIN_LO THEN
    _iLoop := 1;
    _iGuard := 0;
    WHILE (_iLoop <= UINT_TO_INT(_uWinEff)) AND (_iGuard < DL_CW_LOOP_MAX) DO
        _fVar := _fVar + ((_afWin[_iLoop] - _fMean) * (_afWin[_iLoop] - _fMean));   // 偏差平方累加 [g²] / Squared deviation accumulated
        _iLoop := _iLoop + 1;
        _iGuard := _iGuard + 1;                     // 防死循环计数 / Loop guard incremented
    END_WHILE
    _fVar := _fVar / UINT_TO_REAL(_uWinEff - 1);    // 样本方差（分母 n−1）[g²] / Sample variance with n minus one
    fSigmaOut_g := SQRT(_fVar);                     // 样本标准差 [g] / Sample standard deviation
ELSE
    fSigmaOut_g := 0.0;                             // 样本不足：σ 记 0（不参与判据） / Not enough samples, sigma reported as zero
END_IF

// 段 6｜σ 控制图（仅满窗判；越限只在锁存沿计数一次）
IF (_uFill >= _uWinEff) AND (_uWinEff >= DL_CW_WIN_LO) THEN
    IF fSigmaOut_g > fSigmaLimit_g THEN
        bSpcAlarm := TRUE;                          // σ 越控制限 / Sigma above the control limit
        IF NOT _bSpcLatched THEN
            uSpcCnt := uSpcCnt + 1;                 // 越限次数 +1（沿计数）[次] / Violation count incremented on the edge
            _bSpcLatched := TRUE;
        END_IF
    ELSE
        _bSpcLatched := FALSE;                      // 回限内：锁存解除 / Back inside the limit, the latch is released
    END_IF
END_IF

// 段 7｜窗口相位映射（ENUM + CASE + ELSE 兜底）
CASE _eWin OF
    E_DL_GaugeWin.eEmpty:
        IF _uFill > 0 THEN
            _eWin := E_DL_GaugeWin.eFill;           // 有样本：进入填充 / Samples exist, go filling
        END_IF
    E_DL_GaugeWin.eFill:
        IF _uFill >= _uWinEff THEN
            _eWin := E_DL_GaugeWin.eFull;           // 满窗 / Window full
        END_IF
    E_DL_GaugeWin.eFull:
        IF _uFill < _uWinEff THEN
            _eWin := E_DL_GaugeWin.eFill;           // 窗被重置 / The window was reset
        END_IF
    E_DL_GaugeWin.eFault:
        IF _bCfgOk THEN
            _eWin := E_DL_GaugeWin.eEmpty;          // 组态修正：回空窗 / Configuration fixed, back to empty
        END_IF
        eErr := DL_CW_CFG_BAD;                      // 故障级：组态非法保持 / Fault, the configuration error is held
    ELSE
        // 非法相位兜底（故障级）
        eErr := DL_CW_CFG_BAD;
        _eWin := E_DL_GaugeWin.eFault;
END_CASE
IF eErr = 0 THEN
    eErr := DL_CW_READY;                            // 无事件回就绪码 / Ready code when nothing else applies
END_IF
END_FUNCTION_BLOCK
