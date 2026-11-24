(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AnalogSensorHealthClassify
 * 所属子库 (Sublibrary) : DL_Device ｜ 版本 (Version) : 1.0.2 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准（TON / CASE / SQRT 标准函数），零厂商私有库
 * 功能描述 (Function)   : 模拟量通道健康分级（统计窗口径）：在长度 tWinTime 的滑动统计窗内
 *                         累计样本数 / 和 / 平方和 / 最小 / 最大，窗末算出均值 μ 与方差 σ²，
 *                         按四条判据分级：
 *                         · 超量程：本拍样本 > fRangeMax（上侧）或 < fRangeMin（下侧）——即时判，
 *                           上/下各占独立健康成员（R190 归因唯一，禁合并）；
 *                         · 噪声过大：σ² > fNoiseVarMax（窗口级）；
 *                         · 卡滞：σ² < fVarStuckMax 连续 nStuckWinNeed 个统计窗（持续判，
 *                           单窗低方差不算卡滞——慢变工艺量单窗内方差天然很小）；
 *                         · 正常：以上皆否。
 *                         同时输出置信码 nConfidence（0..100），供 HMI 分级显示与预测性维护。
 *                         **与 4-20mA 断线件的分工**：断线 / NE43 电平分级归
 *                         FB_DL_AnalogSignalHealth；本件只看统计特征，不做电平判据。
 * 接口     (Interface)  : 输入 bEnable / bReset / fValue（本拍样本）/ fRangeMin / fRangeMax /
 *                         tWinTime（统计窗长）/ fVarStuckMax / fNoiseVarMax / nStuckWinNeed；
 *                         输出 eHealth（E_DL_AscHealth）/ nConfidence / fMean / fMin / fMax /
 *                         fVar / eState / bError / eCause / bValid。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eCollect：bEnable 上升（开始采样）；拍 N 进入（使能）/ 本拍行为：清统计量、
 *      不判级 / 拍 N+1 转出至 eCollect。
 *   ② eCollect → eClassify：tonWin.Q（统计窗到时）；拍 N 进入（窗到时）/ 本拍行为：
 *      本拍样本不入账（入账发生在 eCollect 拍）/ 拍 N+1 转出至 eClassify。
 *   ③ eClassify → eCollect：分级完成并清统计累加器（同拍完成，单拍驻留）；拍 N 进入 /
 *      本拍行为：算 μ、σ²、判四级、清窗 / 拍 N+1 转出至 eCollect。
 *   ④ eCollect / eClassify → eFault：组态域闸失败（量程倒置 / 窗长 ≤0 / 阈值倒置 /
 *      非有限入参 / nStuckWinNeed < 1）；拍 N 进入（判据失败）/ 本拍行为：锁存首因、
 *      eHealth := eUnknown、nConfidence := 0 / 拍 N+1 转出至 eFault（段尾迁移闸）。
 *   ⑤ eCollect → eIdle：bEnable 落 FALSE（失能退出，健康值冻结为 eUnknown 并置 eNoSample）。
 *   ⑥ eFault → eIdle：bReset 上升且 NOT bEnable（可达性自证 R152：两引脚外部恒可达）；
 *      拍 N 进入 / 本拍行为：清锁存与成因 / 拍 N+1 转出至 eIdle。
 *   ⑦ ELSE（非法枚举值）→ eFault，成因 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 统计窗 TON 自复位：IN := (状态 = eCollect) AND NOT tonWin.Q
 *                            AND (NOT 故障锁存)（R188 / FB50-1③），不依赖外部沿清零。
 *                         ② 方差公式 σ² = E[x²] − μ²，样本数 n ≥ 1 才计算；n = 0 时置
 *                            信息级 eNoSample 并跳过（除零结构性不可达，R4）。
 *                         ③ 方差可能出现 −1E−18 级负残差（浮点相减），取 MAX(σ², 0) 归零。
 *                         ④ 均值 / 方差 / 极值仅在窗末刷新，窗内保持上一窗结果（不逐拍抖动）。
 *                         ⑤ 浮点同值比较统一容差 DL_ASC_EPS（1E-6），禁 `=`。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_AscCause 归属本文件（全库唯一属主）。信息级
 *                         eNoSample / eWinDone 永不置 bError；故障级码锁存回放至 bReset 沿。
 * 分工声明 (Scope)      : 4-20mA 断线 / NE43 分级归 FB_DL_AnalogSignalHealth；通用信号冻结
 *                         监视归 FB_DL_SignalStuckWatch；窗内中值 / 均值滤波归
 *                         FB_DL_MedianFilter / FB_DL_MovingAverage。
 * 归属     (Ownership)  : E_DL_AscHealth / E_DL_AscPhase / E_DL_AscCause 归属本文件
 *                         （全库唯一定义，R264）；E_DL_AshHealth 属主为
 *                         FB_DL_AnalogSignalHealth.st，本件不引用亦不重声明。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 样本数闸防除零 +
 *                         非有限双判 + 容差比较 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ 三态 ENUM +
 *                         CASE + ELSE ｜ R7 ✓ tonWin 在 CASE 外无条件调用 ｜ R14 ✓ 无 PROPERTY
 *                         R8/R9 N/A（无 METHOD）｜ FB50-1① ✓ CASE 内无 TON 调用
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B3 首版
 * 验收向量 (Acceptance) :
 *   V1 量程 0..100、样本恒为 50.0、窗长 1s：首窗 σ²=0 → 第 1 窗不判卡滞（nStuckWinNeed=3），
 *      连续 3 窗后 eHealth=eStuck、nConfidence=20。
 *   V2 样本在 40..60 间交替（σ²≈100）、fNoiseVarMax=10 → eHealth=eNoisy、nConfidence=40。
 *   V3 样本 105.0（> fRangeMax=100）→ 当拍 eHealth=eOverHigh、nConfidence=10（不等窗末）。
 *   V4 fRangeMin=100、fRangeMax=0（倒置）→ eState=eFault、eCause=eBadConfig、bError=TRUE；
 *      bReset 上升且 bEnable=FALSE → 回 eIdle。
 *   V5 tWinTime=T#0s → eState=eFault、eCause=eBadConfig（窗长越域）。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AscHealth（通道健康分级；超量程上/下独立成员，R190）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AscHealth :
(
    eUnknown  := 0,    // 未知：未采样 / 未成窗 / 故障 / Unknown: not sampled or faulted
    eNormal   := 10,   // 正常：窗内方差在带内且未超量程 / Normal: variance in band and within range
    eStuck    := 20,   // 卡滞：连续多窗方差低于阈值 / Stuck: variance below threshold for several windows
    eOverHigh := 30,   // 超量程（上侧）：样本 > fRangeMax / Over range high: sample above the high limit
    eOverLow  := 40,   // 超量程（下侧）：样本 < fRangeMin / Over range low: sample below the low limit
    eNoisy    := 50    // 噪声过大：窗内方差 > fNoiseVarMax / Noisy: window variance above the noise limit
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AscPhase（状态机相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AscPhase :
(
    eIdle     := 0,    // 空闲：未使能，不采样 / Idle: disabled, no sampling
    eCollect  := 10,   // 采样：逐拍累计统计量 / Collect: accumulate statistics per scan
    eClassify := 20,   // 分级：单拍窗末计算 μ、σ² 并判级 / Classify: single-scan window evaluation
    eFault    := 90    // 故障安全相：组态非法，锁存成因 / Fault safe phase with a latched cause
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AscCause（成因码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AscCause :
(
    eNone         := 0,   // 信息级：无事件 / Info: no event
    eNoSample     := 1,   // 信息级：窗内无样本（已跳过方差计算）/ Info: no sample in the window, variance skipped
    eWinDone      := 2,   // 信息级：统计窗完成 / Info: statistics window completed
    eBadConfig    := 10,  // 故障级：量程倒置 / 窗长 ≤0 / 阈值倒置 / Fault: inverted range, zero window or inverted thresholds
    eNonFinite    := 11,  // 故障级：入参非有限 / Fault: non-finite input
    eBadWinNeed   := 12,  // 故障级：卡滞窗数需求 < 1 / Fault: stuck window count below one
    eIllegalState := 13   // 故障级：非法状态枚举值 / Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnalogSensorHealthClassify
VAR_INPUT
    bEnable      : BOOL := FALSE;      // 使能：FALSE 停止采样（健康值冻结 eUnknown）/ Enable, FALSE stops sampling
    bReset       : BOOL := FALSE;      // 复位（上升沿，需同时 bEnable=FALSE）/ Reset rising edge, requires disabled state
    fValue       : REAL := 0.0;        // 本拍样本值 [工程单位] / Sample value of this scan
    fRangeMin    : REAL := 0.0;        // 量程下限 [工程单位] / Range low limit
    fRangeMax    : REAL := 100.0;      // 量程上限，域 > fRangeMin [工程单位] / Range high limit, domain > fRangeMin
    tWinTime     : TIME := T#1S;       // 统计窗长，域 > 0 [s] / Statistics window length, domain > 0
    fVarStuckMax : REAL := 0.01;       // 卡滞方差阈值（σ² < 该值判疑似卡滞），域 ≥ 0 / Stuck variance threshold, domain >= 0
    fNoiseVarMax : REAL := 25.0;       // 噪声方差阈值（σ² > 该值判噪声过大），域 > fVarStuckMax / Noise variance threshold
    nStuckWinNeed : INT := 3;          // 连续低方差窗数需求，域 ≥ 1 [-] / Consecutive low-variance windows required
END_VAR
VAR_OUTPUT
    eHealth      : E_DL_AscHealth := E_DL_AscHealth.eUnknown;  // 健康分级出口 [-] / Health classification outlet
    nConfidence  : INT := 0;                     // 置信码 0..100（100 = 完全可信）[-] / Confidence code 0..100
    fMean        : REAL := 0.0;                  // 上一窗均值 μ [工程单位] / Mean of the last window
    fMin         : REAL := 0.0;                  // 上一窗最小值 [工程单位] / Minimum of the last window
    fMax         : REAL := 0.0;                  // 上一窗最大值 [工程单位] / Maximum of the last window
    fVar         : REAL := 0.0;                  // 上一窗方差 σ² [(工程单位)²] / Variance of the last window
    eState       : E_DL_AscPhase;                // 状态出口（段尾单点映射）[-] / State outlet mapped at the tail
    bError       : BOOL;                         // 故障锁存标志 [-] / Fault latch flag
    eCause       : E_DL_AscCause;                // 成因码出口（故障期锁存回放）[-] / Cause code outlet
    bValid       : BOOL;                         // 分级结果有效回执 [-] / Health result validity receipt
END_VAR
VAR
    _eState      : E_DL_AscPhase := E_DL_AscPhase.eIdle;      // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch : BOOL := FALSE;                             // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit
    _eCauseLatch : E_DL_AscCause := E_DL_AscCause.eNone;       // 锁存成因码（FB33-1）[-] / Latched cause code
    _eCauseTmp   : E_DL_AscCause := E_DL_AscCause.eNone;       // 本拍首个成因（未锁存）[-] / First cause of this scan
    _bCfgOk      : BOOL := TRUE;                              // 组态与入参闸通过标志 [-] / Configuration gate flag
    _nCnt        : INT := 0;                                  // 窗内样本数 [个] / Sample count in the current window
    _fSum        : LREAL := 0.0;                              // 窗内样本和 [工程单位] / Sum of samples in the window
    _fSumSq      : LREAL := 0.0;                              // 窗内样本平方和 [(工程单位)²] / Sum of squared samples
    _fWinMin     : REAL := 0.0;                               // 窗内最小值（窗内滚动） / Rolling minimum in the window
    _fWinMax     : REAL := 0.0;                               // 窗内最大值（窗内滚动） / Rolling maximum in the window
    _fMeanCalc   : LREAL := 0.0;                              // 窗末均值中间量 / Mean intermediate at window end
    _fVarCalc    : LREAL := 0.0;                              // 窗末方差中间量 / Variance intermediate at window end
    _nStuckWin   : INT := 0;                                  // 连续低方差窗计数（跨窗保持）/ Consecutive low-variance window counter
    _bOverHigh   : BOOL := FALSE;                             // 本拍上侧超量程标志 [-] / Over-range high flag of this scan
    _bOverLow    : BOOL := FALSE;                             // 本拍下侧超量程标志 [-] / Over-range low flag of this scan
    tonWin       : TON;                                       // 统计窗定时器（段 2 无条件调用）/ Statistics window timer, called unconditionally
    _rtReset     : R_TRIG;                                 // 复位沿检测实例（v1.0.2 补：声明沿即实现沿，CASE 外无条件刷新）/ Reset edge detector refreshed outside the CASE
END_VAR
VAR CONSTANT
    DL_ASC_ZERO  : REAL := 0.0;      // 零基准 [-] / Zero base
    DL_ASC_ONE   : REAL := 1.0;      // 一基准（样本数换算用）[-] / Unity base
    DL_ASC_FULL  : REAL := 100.0;    // 置信码满值 [-] / Full confidence value
    DL_ASC_EPS   : REAL := 1.0E-6;   // 浮点同值比较容差 [-] / Float equality tolerance
END_VAR

(* —— 段 1：当拍工作量预置（单拍标志与中间量，不清锁存/累加器/计数） —— *)
_bCfgOk    := TRUE;                                    // 闸通过标志复位 / Gate flag reset
_eCauseTmp := E_DL_AscCause.eNone;                      // 当拍成因复位 / Scan cause reset
_bOverHigh := FALSE;                                    // 上超量程标志复位 / Over-high flag reset
_bOverLow  := FALSE;                                    // 下超量程标志复位 / Over-low flag reset

(* —— 段 2：组态与入参域闸（R272 全量枚举所有浮点与时间引脚） —— *)
IF (fValue <> fValue) OR ((fValue - fValue) <> DL_ASC_ZERO)
    OR (fRangeMin <> fRangeMin) OR ((fRangeMin - fRangeMin) <> DL_ASC_ZERO)
    OR (fRangeMax <> fRangeMax) OR ((fRangeMax - fRangeMax) <> DL_ASC_ZERO)
    OR (fVarStuckMax <> fVarStuckMax) OR ((fVarStuckMax - fVarStuckMax) <> DL_ASC_ZERO)
    OR (fNoiseVarMax <> fNoiseVarMax) OR ((fNoiseVarMax - fNoiseVarMax) <> DL_ASC_ZERO) THEN
    _bCfgOk    := FALSE;
    _eCauseTmp := E_DL_AscCause.eNonFinite;             // 故障级：非有限入参 / Fault: non-finite input
END_IF
IF _bCfgOk THEN
    IF fRangeMax <= fRangeMin THEN
        _bCfgOk    := FALSE;
        _eCauseTmp := E_DL_AscCause.eBadConfig;          // 故障级：量程倒置 / Fault: inverted range
    ELSIF tWinTime <= T#0S THEN
        _bCfgOk    := FALSE;
        _eCauseTmp := E_DL_AscCause.eBadConfig;          // 故障级：窗长越域 / Fault: window length out of domain
    ELSIF fVarStuckMax < DL_ASC_ZERO THEN
        _bCfgOk    := FALSE;
        _eCauseTmp := E_DL_AscCause.eBadConfig;          // 故障级：卡滞阈值为负 / Fault: negative stuck threshold
    ELSIF fNoiseVarMax <= fVarStuckMax THEN
        _bCfgOk    := FALSE;
        _eCauseTmp := E_DL_AscCause.eBadConfig;          // 故障级：噪声阈值不高于卡滞阈值 / Fault: noise threshold not above the stuck one
    ELSIF nStuckWinNeed < 1 THEN
        _bCfgOk    := FALSE;
        _eCauseTmp := E_DL_AscCause.eBadWinNeed;         // 故障级：窗数需求越域 / Fault: window count out of domain
    END_IF
END_IF

(* —— 段 3：统计窗定时器（CASE 外无条件调用；IN 自复位 + 串故障锁存，R188 / FB50-1③） —— *)
tonWin(IN := (_eState = E_DL_AscPhase.eCollect) AND (NOT tonWin.Q) AND (NOT _bFaultLatch),
       PT := tWinTime);                                  // 窗长取引脚（TIME 类型原样传入）/ Window length from the pin

(* —— 段 4：状态机主体（唯一相位写入点） —— *)
_rtReset(CLK := bReset);                                // 复位沿刷新无条件周期调用（R7；v1.0.2 修复 J1 电平判据缺陷 / R18）/ Refresh the reset edge unconditionally every scan
CASE _eState OF
    E_DL_AscPhase.eIdle :
        IF bEnable AND _bCfgOk THEN
            _nCnt      := 0;                             // 清样本计数 / Clear the sample count
            _fSum      := 0.0;                           // 清样本和 / Clear the sum
            _fSumSq    := 0.0;                           // 清平方和 / Clear the squared sum
            _nStuckWin := 0;                             // 清卡滞窗计数 / Clear the stuck window counter
            eHealth    := E_DL_AscHealth.eUnknown;       // 未成窗 → 未知 / Not yet windowed: unknown
            nConfidence := 0;                            // 置信码清零 / Confidence zeroed
            _eState    := E_DL_AscPhase.eCollect;        // 迁移①：进入采样相 / Move to collect
        END_IF

    E_DL_AscPhase.eCollect :
        IF NOT bEnable THEN
            eHealth     := E_DL_AscHealth.eUnknown;      // 迁移⑤：失能后健康值不再成立 / Health no longer valid after disable
            nConfidence := 0;                            // 置信码清零 / Confidence zeroed
            eCause      := E_DL_AscCause.eNoSample;      // 信息级：停止采样 / Info: sampling stopped
            _nStuckWin  := 0;                            // 停采清卡滞计数 / Clear the stuck counter while stopped
            _eState     := E_DL_AscPhase.eIdle;          // 回空闲相 / Back to idle
        ELSE
            (* 逐拍入账（样本数 / 和 / 平方和 / 极值），极值用窗内滚动 *)
            IF _nCnt = 0 THEN
                _fWinMin := fValue;                      // 首样本初始化最小值 / First sample initialises the minimum
                _fWinMax := fValue;                      // 首样本初始化最大值 / First sample initialises the maximum
            ELSE
                _fWinMin := MIN(_fWinMin, fValue);       // 滚动最小 / Rolling minimum
                _fWinMax := MAX(_fWinMax, fValue);       // 滚动最大 / Rolling maximum
            END_IF
            _nCnt   := _nCnt + 1;                        // 样本计数递增 / Increment the sample count
            _fSum   := _fSum + fValue;                   // 累加样本和 / Accumulate the sum
            _fSumSq := _fSumSq + (fValue * fValue);      // 累加平方和 / Accumulate the squared sum
            (* 超量程即时判（上 / 下分列，R146 / R190） *)
            IF fValue > (fRangeMax + DL_ASC_EPS) THEN
                _bOverHigh  := TRUE;                     // 上侧超量程 / Over range high
                eHealth     := E_DL_AscHealth.eOverHigh; // 健康分级立即上报 / Health reported immediately
                nConfidence := 10;                       // 低置信 / Low confidence
                eCause      := E_DL_AscCause.eNone;      // 成因码由健康枚举承担 / Cause expressed by the health enum
            ELSIF fValue < (fRangeMin - DL_ASC_EPS) THEN
                _bOverLow   := TRUE;                     // 下侧超量程 / Over range low
                eHealth     := E_DL_AscHealth.eOverLow;  // 健康分级立即上报 / Health reported immediately
                nConfidence := 10;                       // 低置信 / Low confidence
                eCause      := E_DL_AscCause.eNone;      // 成因码由健康枚举承担 / Cause expressed by the health enum
            END_IF
            IF tonWin.Q THEN
                _eState := E_DL_AscPhase.eClassify;      // 迁移②：窗到时进入分级相 / Window elapsed: move to classify
            END_IF
        END_IF

    E_DL_AscPhase.eClassify :
        IF _nCnt < 1 THEN
            eCause := E_DL_AscCause.eNoSample;           // 信息级：窗内无样本 / Info: no sample in the window
            fMean  := DL_ASC_ZERO;                       // 均值置零哨兵 / Mean sentinel
            fVar   := DL_ASC_ZERO;                       // 方差置零哨兵 / Variance sentinel
            fMin   := DL_ASC_ZERO;                       // 最小值置零哨兵 / Minimum sentinel
            fMax   := DL_ASC_ZERO;                       // 最大值置零哨兵 / Maximum sentinel
            eHealth     := E_DL_AscHealth.eUnknown;      // 分级未知 / Unknown classification
            nConfidence := 0;                            // 置信码清零 / Confidence zeroed
        ELSE
            (* 窗末统计：μ = Σx/n，σ² = Σx²/n − μ²（n ≥ 1，除零不可达） *)
            _fMeanCalc := _fSum / INT_TO_LREAL(_nCnt);                     // 均值 / Mean
            _fVarCalc  := (_fSumSq / INT_TO_LREAL(_nCnt)) - (_fMeanCalc * _fMeanCalc);   // 方差 / Variance
            IF _fVarCalc < 0.0 THEN
                _fVarCalc := 0.0;                                          // 负残差归零（浮点相减残差）/ Negative residual zeroed
            END_IF
            fMean := LREAL_TO_REAL(_fMeanCalc);                            // 均值出口（显式窄化）/ Mean outlet, explicit narrowing
            fVar  := LREAL_TO_REAL(_fVarCalc);                             // 方差出口（显式窄化）/ Variance outlet, explicit narrowing
            fMin  := _fWinMin;                                             // 最小值出口 / Minimum outlet
            fMax  := _fWinMax;                                             // 最大值出口 / Maximum outlet
            eCause := E_DL_AscCause.eWinDone;                              // 信息级：窗完成 / Info: window completed
            (* v1.0.2 补（闸 P1）：_bOverHigh/_bOverLow 段 1 每拍被清，逐拍置位到 eClassify 已不可见
               → 改由窗极值重算，超量程判据真正生效（窗级口径，与头注窗末分级一致） *)
            IF _fWinMax > fRangeMax THEN                                  // 窗内最高样本越上限 / window max above the range
                _bOverHigh := TRUE;                                        // 上超量程成立 / Over-high confirmed
            END_IF
            IF _fWinMin < fRangeMin THEN                                  // 窗内最低样本越下限 / window min below the range
                _bOverLow := TRUE;                                         // 下超量程成立 / Over-low confirmed
            END_IF
            (* 分级：超量程优先（安全侧），其次噪声，再次卡滞，最后正常 *)
            IF _bOverHigh THEN
                eHealth     := E_DL_AscHealth.eOverHigh;                   // 超量程（上）/ Over range high
                nConfidence := 10;                                         // 低置信 / Low confidence
                _nStuckWin  := 0;                                          // 清卡滞计数 / Clear the stuck counter
            ELSIF _bOverLow THEN
                eHealth     := E_DL_AscHealth.eOverLow;                    // 超量程（下）/ Over range low
                nConfidence := 10;                                         // 低置信 / Low confidence
                _nStuckWin  := 0;                                          // 清卡滞计数 / Clear the stuck counter
            ELSIF fVar > fNoiseVarMax THEN
                eHealth     := E_DL_AscHealth.eNoisy;                      // 噪声过大 / Noisy
                nConfidence := 40;                                         // 中低置信 / Medium-low confidence
                _nStuckWin  := 0;                                          // 清卡滞计数 / Clear the stuck counter
            ELSIF fVar < fVarStuckMax THEN
                _nStuckWin := _nStuckWin + 1;                              // 连续低方差窗计数 / Consecutive low-variance windows
                IF _nStuckWin >= nStuckWinNeed THEN
                    eHealth     := E_DL_AscHealth.eStuck;                  // 卡滞（持续判已满足）/ Stuck after the required windows
                    nConfidence := 20;                                     // 低置信 / Low confidence
                ELSE
                    eHealth     := E_DL_AscHealth.eNormal;                 // 尚未满足持续条件：按正常上报 / Not yet persistent: normal
                    nConfidence := 70;                                     // 中等置信 / Medium confidence
                END_IF
            ELSE
                eHealth     := E_DL_AscHealth.eNormal;                     // 正常 / Normal
                nConfidence := 100;                                        // 满置信 / Full confidence
                _nStuckWin  := 0;                                          // 清卡滞计数 / Clear the stuck counter
            END_IF
        END_IF
        (* 清窗（样本数 / 和 / 平方和），极值在下一窗首样本重初始化 *)
        _nCnt   := 0;                                                      // 清样本计数 / Clear the sample count
        _fSum   := 0.0;                                                    // 清和 / Clear the sum
        _fSumSq := 0.0;                                                    // 清平方和 / Clear the squared sum
        _bOverHigh := FALSE;                                               // 清上超量程（窗级标志随窗清零）/ Clear the over-high window flag
        _bOverLow  := FALSE;                                               // 清下超量程 / Clear the over-low window flag
        _eState := E_DL_AscPhase.eCollect;                                 // 迁移③：回到采样相 / Back to collect

    E_DL_AscPhase.eFault :
        (* 迁移⑥：唯一出口 —— bReset 沿 + 已失能 *)
        IF _rtReset.Q AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                                        // 清故障锁存 / Clear the latch
            _eCauseLatch := E_DL_AscCause.eNone;                          // 清锁存成因 / Clear the latched cause
            eCause       := E_DL_AscCause.eNone;                          // 出口同步 / Outlet follows
            _eState      := E_DL_AscPhase.eIdle;                          // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑦：非法枚举兜底（R6） *)
    _eCauseLatch := E_DL_AscCause.eIllegalState;                          // 故障级：非法状态
    _bFaultLatch := TRUE;                                                 // 置锁存 / Latch
    eHealth      := E_DL_AscHealth.eUnknown;                              // 分级未知 / Unknown health
    nConfidence  := 0;                                                    // 置信清零 / Confidence zeroed
    _eState      := E_DL_AscPhase.eFault;                                 // 迁入故障相 / Move to fault
END_CASE

(* —— 段 5：组态闸失败处理（在状态机之后统一置故障，避免分支内重复） —— *)
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _eCauseLatch := _eCauseTmp;                                           // 锁存首因 / Latch the first cause
    _bFaultLatch := TRUE;                                                 // 置故障锁存 / Latch the fault
    eHealth      := E_DL_AscHealth.eUnknown;                              // 分级未知 / Unknown health
    nConfidence  := 0;                                                    // 置信清零 / Confidence zeroed
END_IF

(* —— 段 6：段尾故障迁移闸（锁存与迁相分离，FB50-1④） —— *)
IF _bFaultLatch AND (_eState <> E_DL_AscPhase.eFault) THEN
    _eState := E_DL_AscPhase.eFault;                                       // 锁存即迁相 / Latch forces the fault phase
END_IF

(* —— 段 7：统一出口（状态映射 + 锁存回放） —— *)
eState := _eState;                                                        // 相位映射 / Phase mapping
bError := _bFaultLatch;                                                   // 故障标志取锁存位 / Fault flag from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                                               // 故障期回放锁存码（FB33-1）/ Replay the latched code
END_IF
bValid := (_eState = E_DL_AscPhase.eCollect) AND (NOT _bFaultLatch) AND (_nCnt > 0);   // 采样相且有样本时有效
END_FUNCTION_BLOCK
