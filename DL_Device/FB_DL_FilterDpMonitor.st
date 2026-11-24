//==============================================================================
// 功能块：FB_DL_FilterDpMonitor ｜ 中文名称：过滤器压差寿命监视
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：过滤器压差趋势监视与滤芯更换预警——压差实测 + 趋势窗斜率
//           [kPa/h]，按更换预警/堵塞报警双阈值映射 NE107 健康态
//           （eOk / eMaintenanceReq / eOutOfSpec），eOutOfSpec 锁存需手动复位。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现
// 单位表：p_d[kPa] / 趋势斜率[kPa/h] / 阈值[kPa] / 趋势窗[ms] / 健康态[—]
// 错误码表：16#0003_0182 信息级（负压差，传感器接反疑似，按 0 处理，不置
//           bError）/ 16#0003_0183 预留禁用（不得挪用）/ 16#0003_0354
//           故障级（阈值倒置或压差非有限，置 bError，保持末次有效健康态）/
//           16#0003_0355 预留禁用（不得挪用）/ 16#0003_0356 故障级兜底
//           （置 bError，本件无状态机，保留给扩展误用拦截）
// 状态机：N/A（阈值映射 + 锁存为电平逻辑，无相位状态机；健康态降级锁存
//           由 bOosLatch 保持量承担）
// 边界行为：① fDpAlarmKpa <= fDpChangeKpa → 故障 0354（阈值倒置）；② 压差
//           非有限 → 故障 0354 复用（R90）+ 保持末次有效健康态（不静默塞
//           eOk）；③ 负压差（传感器接反疑似）→ 信息 0182 + 按 0 处理；
//           ④ 趋势窗斜率 = 窗均值差 / 窗时长[h]，窗时长非法（<= 0）→ 斜率
//           冻结 0（防除零）；⑤ eOutOfSpec 锁存，仅 bReset 清除。
// 依赖纪律：Level 1 → Level 0 组合调用合法——趋势窗均值组合调用
//           FB_DL_SignalStatistics（DL_MathData，接口已核实：fIn/bSample/
//           nWindow/bClear → fMean/fMin/fMax/fRange/fVariance），头注释
//           依赖清单声明；斜率除法在本件内联（时间维度归一属监视语义，
//           非统计算法复制）。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 公用工程 P1 §394 + T2-8 NE107 次源）
//==============================================================================

FUNCTION_BLOCK FB_DL_FilterDpMonitor
VAR_INPUT
    fDpKpa       : LREAL;                    // 压差实测 [千帕] / Measured differential pressure [kPa]
    fDpChangeKpa : LREAL := 0.8;             // 更换预警阈值 [千帕] / Replace-hint threshold [kPa]
    fDpAlarmKpa  : LREAL := 1.5;             // 堵塞报警阈值 [千帕]，须 > 预警阈值 / Clog-alarm threshold [kPa], must exceed the hint threshold
    tTrendWindow : TIME  := T#1H;            // 趋势窗时长 [ms] / Trend window duration [ms]
    bReset       : BOOL;                     // 手动复位 [—]，清除 eOutOfSpec 锁存 / Manual reset, clears the eOutOfSpec latch
END_VAR
VAR_OUTPUT
    eHealth      : E_DL_Ne107Status;         // 健康态 [—]，引用属主枚举（只引用不重声明，R70） / Health status, owner enum referenced, not redeclared
    fDpTrendKpaH : LREAL;                    // 趋势斜率 [千帕/小时] / Trend slope [kPa/h]
    bReplaceHint : BOOL;                     // 更换预警 [—] / Replace hint
    eErr         : UDINT;                    // 错误码，0 = 无错 / Error code, 0 = no error
    bError       : BOOL;                     // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid       : BOOL;                     // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbStats      : FB_DL_SignalStatistics;   // 趋势窗统计器（Level 0 组合调用） / Trend-window statistics FB, Level 0 composition
    fbWin        : TON;                      // 趋势窗计时，段 6 无条件刷新 [ms] / Trend window timer
    rtWinTick    : R_TRIG;                   // 窗满上升沿（快照单发），段 6 无条件刷新 / Window-full rising edge, one-shot snapshot
    _eHealthAcc  : E_DL_Ne107Status := E_DL_Ne107Status.eUnknown; // 末次有效健康态保持量 / Held last valid health status
    _bOosLatch   : BOOL;                     // eOutOfSpec 锁存（bReset 清除） / eOutOfSpec latch, cleared by bReset
    _fMeanPrev   : REAL;                     // 上一窗均值快照 [千帕] / Previous window-mean snapshot [kPa]
    _fWinHours   : LREAL;                    // 趋势窗时长换算 [小时] / Trend window duration [h]
    _fDpEff      : LREAL;                    // 防御后的生效压差 [千帕] / Effective defended pressure [kPa]
    _bInit       : BOOL := FALSE;            // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bThreshBad  : BOOL;                    // 阈值倒置锁存 / Threshold inversion latch
    _bFiniteBad  : BOOL;                    // 压差非有限锁存 / Non-finite pressure latch
    _bNegDp      : BOOL;                     // 负压差当拍标志 / Negative pressure flag of this scan
END_VAR
VAR CONSTANT
    DL_FD_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_FD_ZERO    : LREAL := 0.0;          // 压差物理下界 [千帕] / Pressure physical floor [kPa]
    DL_FD_H_PER_MS: LREAL := 2.77777777777778E-7; // 毫秒 → 小时换算系数 [h/ms]，1/3600000 / Millisecond-to-hour factor [h/ms]
    DL_FD_STATS_N : INT   := 32;           // 统计窗口长度 [样本] / Statistics window length [samples]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出先算后出，单拍标志预清零
 *      Outputs computed per scan, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
eHealth      := E_DL_Ne107Status.eUnknown; // 健康态预置未知 / Health preset unknown
fDpTrendKpaH := 0.0;                       // 趋势斜率预置零 / Trend slope preset zero
bReplaceHint := FALSE;                     // 更换预警预清零 / Replace hint pre-cleared
eErr         := 16#0000_0000;              // 错误码每拍重算 / Error code recomputed
bError       := FALSE;                     // 故障标志每拍重算 / Fault flag recomputed
bValid       := FALSE;                     // 可用标志每拍重算 / Usable flag recomputed
_bNegDp      := FALSE;                     // 负压差标志预清零 / Negative flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eHealthAcc := E_DL_Ne107Status.eOk;   // 末次有效健康态起步正常 / Held health starts OK
    _fMeanPrev  := 0.0;                    // 均值快照清零 / Mean snapshot cleared
    _bOosLatch  := FALSE;                  // 超规格锁存清零 / OOS latch cleared
    _bInit      := TRUE;                   // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态与输入防御闸：阈值倒置 / 非有限 → 0354（保持末次健康态）
 *      Configuration and input defense gate, last valid health held
 *-----------------------------------------------------------------------------*)
IF fDpAlarmKpa <= fDpChangeKpa THEN
    _bThreshBad := TRUE;                   // 阈值倒置锁存 / Threshold inversion latched
END_IF
IF (fDpKpa <> fDpKpa) OR (ABS(fDpKpa) > DL_FD_INF) THEN
    _bFiniteBad := TRUE;                   // 压差非有限锁存 / Non-finite pressure latched
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜负压差防御：传感器接反疑似，按 0 处理并声明
 *      Negative pressure defense, treated as zero with a notice
 *-----------------------------------------------------------------------------*)
_fDpEff := fDpKpa;                          // 生效压差先取原值 / Effective pressure starts as-is
IF (NOT _bFiniteBad) AND (fDpKpa < DL_FD_ZERO) THEN
    _bNegDp := TRUE;                        // 负压差当拍成立 / Negative pressure active this scan
    _fDpEff := 0.0;                         // 负压差按 0 处理 / Negative pressure treated as zero
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜趋势组合调用与窗计时无条件刷新（R40：CASE 之外每拍必调）
 *      Trend composition and window timing refreshed unconditionally
 *-----------------------------------------------------------------------------*)
fbStats(fIn := LREAL_TO_REAL(_fDpEff), bSample := TRUE, nWindow := DL_FD_STATS_N); // 统计器每拍采样（标准类型转换，零方言） / Statistics FB sampled every scan, standard type conversion
fbWin(IN := TRUE, PT := tTrendWindow);     // 趋势窗连续计时 / Trend window timing continuous
rtWinTick(CLK := fbWin.Q);                 // 窗满上升沿 / Window-full edge
_fWinHours := TIME_TO_DINT(tTrendWindow) * DL_FD_H_PER_MS; // 窗时长换算 [小时] / Window duration converted [h]
IF rtWinTick.Q AND (_fWinHours > 0.0) THEN
    fDpTrendKpaH := (fbStats.fMean - _fMeanPrev) / _fWinHours; // 趋势斜率 [千帕/小时]，分母已闸 / Trend slope, denominator gated
    _fMeanPrev := fbStats.fMean;           // 快照推进 / Snapshot advanced
ELSIF _fWinHours <= 0.0 THEN
    fDpTrendKpaH := 0.0;                   // 窗时长非法：斜率冻结（防除零） / Illegal duration, slope frozen, divide-by-zero guarded
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜阈值映射与降级锁存（eOutOfSpec 需手动复位才回 eOk）
 *      Threshold mapping and the degradation latch
 *-----------------------------------------------------------------------------*)
IF (NOT _bThreshBad) AND (NOT _bFiniteBad) THEN
    bReplaceHint := (_fDpEff >= fDpChangeKpa); // 生效压差达预警阈值 / Effective pressure at the hint threshold
    IF _fDpEff >= fDpAlarmKpa THEN
        _bOosLatch := TRUE;                // 达报警阈值，锁存超规格 / At the alarm threshold, OOS latched
    END_IF
    IF _bOosLatch THEN
        _eHealthAcc := E_DL_Ne107Status.eOutOfSpec; // 锁存期保持超规格 / OOS held during the latch
    ELSIF bReplaceHint THEN
        _eHealthAcc := E_DL_Ne107Status.eMaintenanceReq; // 预警期维护请求 / Maintenance required during the hint
    ELSE
        _eHealthAcc := E_DL_Ne107Status.eOk; // 正常 / OK
    END_IF
END_IF
IF bReset THEN
    _bOosLatch := FALSE;                   // 手动复位清锁存 / Manual reset clears the latch
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出与码位出口
 *      Outputs and the code outlet
 *-----------------------------------------------------------------------------*)
eHealth := _eHealthAcc;                    // 健康态出口（故障期保持末次有效值） / Health outlet, last valid value held on fault
IF _bThreshBad OR _bFiniteBad THEN
    eErr   := 16#0003_0354;                // 故障级：阈值倒置或非有限（R90 复用） / Fault: threshold inversion or non-finite, code reused
    bError := TRUE;                        // 置故障标志（R45 配对） / Raise the fault flag
    bValid := FALSE;                       // 输出不可用 / Outputs unusable
ELSE
    IF _bNegDp THEN
        eErr := 16#0003_0182;              // 信息级：负压差按 0 处理（不置 bError） / Info: negative pressure treated as zero, no fault flag
    END_IF
    bValid := TRUE;                        // 输出可用 / Outputs usable
END_IF
END_FUNCTION_BLOCK
